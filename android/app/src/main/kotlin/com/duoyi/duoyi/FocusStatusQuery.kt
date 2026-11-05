package com.duoyi.duoyi

import java.util.ArrayDeque
import java.util.concurrent.Executor
import java.util.concurrent.RejectedExecutionException

/** 无法产生快照的结构化原因：调用方（MethodChannel）分别映射成显式错误码。 */
enum class FocusStatusUnavailable {
    /** 同时在等的回调已达上限，本次不再排队。 */
    BUSY,

    /** 持有者已销毁，不再执行也不再回复新请求。 */
    DISPOSED,
}

/**
 * 有界、单飞（coalescing）的焦点状态快照查询器，纯 Kotlin、无 Android 依赖。
 *
 * 设计约束：
 * - [request] 只在 owner 线程（Activity 主线程）调用，只是入队 + 最多提交一次 worker 任务；
 *   owner 线程不做任何读取，也不阻塞等待结果。
 * - 同一时刻最多一个在飞快照；新请求合并等待同一次结果，不会堆积任务。
 * - 等待回调数上限 [maxPendingRequests]；超出直接回 [FocusStatusUnavailable.BUSY]。
 * - worker 完成后经 [postToOwner] 回到 owner 线程再分发，期间其他控制动作可继续执行。
 * - [dispose] 递增 generation：迟到的 worker 结果被丢弃，等待者只收到一次
 *   [FocusStatusUnavailable.DISPOSED]。
 */
class FocusStatusQuery<S : Any>(
    private val worker: Executor,
    private val postToOwner: (Runnable) -> Unit,
    private val readSnapshot: () -> S,
    private val maxPendingRequests: Int = defaultPendingRequestLimit,
    private val slowQueryWarnNanos: Long = defaultSlowQueryWarnMillis * nanosPerMilli,
    private val nanoTime: () -> Long = System::nanoTime,
    private val onSlowQuery: (Long) -> Unit = {},
) {
    /** 一个等待同一次快照的调用方。 */
    private class Waiter<S : Any>(
        val onSnapshot: (S) -> Unit,
        val onFailure: (Throwable) -> Unit,
        val onUnavailable: (FocusStatusUnavailable) -> Unit,
    )

    private val ownerThread: Thread = Thread.currentThread()
    private val waiters = ArrayDeque<Waiter<S>>()
    private var inFlight = false
    private var disposed = false
    private var generation = 0L

    /** 当前等待同一快照的回调数量。 */
    val pendingRequestCount: Int
        get() = waiters.size

    /** 是否已有在飞快照。 */
    val hasInFlightSnapshot: Boolean
        get() = inFlight

    val isDisposed: Boolean
        get() = disposed

    /**
     * 请求一份快照：结果（成功 / 读取异常 / 上限 / 已销毁）都在 owner 线程各送达一次。
     */
    fun request(
        onSnapshot: (S) -> Unit,
        onFailure: (Throwable) -> Unit,
        onUnavailable: (FocusStatusUnavailable) -> Unit,
    ) {
        checkOwnerThread()
        if (disposed) {
            onUnavailable(FocusStatusUnavailable.DISPOSED)
            return
        }
        if (waiters.size >= maxPendingRequests) {
            onUnavailable(FocusStatusUnavailable.BUSY)
            return
        }
        waiters.addLast(Waiter(onSnapshot, onFailure, onUnavailable))
        if (inFlight) return
        inFlight = true
        val token = generation
        try {
            worker.execute { runSnapshot(token) }
        } catch (rejected: RejectedExecutionException) {
            // 执行器已关闭（销毁竞态）：立刻结束，不让等待者悬空。
            inFlight = false
            drainUnavailable(FocusStatusUnavailable.DISPOSED)
        }
    }

    /**
     * 结束生命周期：拒绝新任务、把等待者按 [FocusStatusUnavailable.DISPOSED] 各回复一次，
     * 之后迟到的 worker 结果因 generation 变化被丢弃。
     */
    fun dispose() {
        checkOwnerThread()
        if (disposed) return
        disposed = true
        generation += 1
        inFlight = false
        drainUnavailable(FocusStatusUnavailable.DISPOSED)
    }

    /** worker 侧：只做读取与计时，随后把完成事件投回 owner 线程。 */
    private fun runSnapshot(token: Long) {
        val startedAt = nanoTime()
        val result = runCatching { readSnapshot() }
        val elapsedNanos = nanoTime() - startedAt
        postToOwner { complete(token, result, elapsedNanos) }
    }

    /** owner 侧：校验 generation 后一次性分发本次快照给全部等待者。 */
    private fun complete(token: Long, result: Result<S>, elapsedNanos: Long) {
        checkOwnerThread()
        // 迟到结果（销毁后到达）不得再回复一次。
        if (token != generation) return
        inFlight = false
        if (elapsedNanos >= slowQueryWarnNanos) {
            // 诊断只保留耗时，不带包名等额外应用信息。
            onSlowQuery(elapsedNanos / nanosPerMilli)
        }
        result.fold(
            onSuccess = { value -> drain { waiter -> waiter.onSnapshot(value) } },
            onFailure = { cause -> drain { waiter -> waiter.onFailure(cause) } },
        )
    }

    private fun drainUnavailable(reason: FocusStatusUnavailable) {
        drain { waiter -> waiter.onUnavailable(reason) }
    }

    /** 先摘出全部等待者再回调：回调里重新 request 不会被吞掉或重复回复。 */
    private fun drain(action: (Waiter<S>) -> Unit) {
        if (waiters.isEmpty()) return
        val pending = ArrayList<Waiter<S>>(waiters.size)
        while (waiters.isNotEmpty()) pending.add(waiters.removeFirst())
        for (waiter in pending) action(waiter)
    }

    private fun checkOwnerThread() {
        check(Thread.currentThread() === ownerThread) {
            "FocusStatusQuery must be used on its owner thread"
        }
    }

    companion object {
        /** 同时在等的回调上限：超出立即回 busy，而不是无限排队。 */
        const val defaultPendingRequestLimit = 32

        /** 单次快照超过该耗时打一条警告（仅耗时）。 */
        const val defaultSlowQueryWarnMillis = 500L

        private const val nanosPerMilli = 1_000_000L
    }
}
