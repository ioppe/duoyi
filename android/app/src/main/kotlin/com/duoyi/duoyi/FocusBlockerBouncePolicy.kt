package com.duoyi.duoyi

/**
 * 严格专注拉回的纯策略层（纯 Kotlin，无 Android 依赖，便于 JVM 单测）。
 *
 * 真机问题（小米 API 36）暴露了两个具体缺陷：
 * 1. 旧的去重逻辑在每个事件上都推进 `lastBounceAt`，只要分心应用持续产生窗口事件，
 *    冷却窗口就被无限推后，后续拉回永远被判定为“重复”而饿死。
 * 2. `startActivity` 返回成功不代表用户真的回到了多仪：Splash → MainTab 重入、
 *    事件滑动去抖都可能让前台仍是分心应用，需要“请求”与“确认返回”分离。
 *
 * 本文件只提供判定所需的纯状态与函数，不持有 Activity/View 引用、不注册监听、
 * 不读取任何界面内容。时钟统一使用 `SystemClock.uptimeMillis`（与
 * `AccessibilityEvent.eventTime` 同基准），不使用 `elapsedRealtime`。
 */

/**
 * 固定冷却门控：冷却**全局**生效（跨包名），冷却期内只放行第一个请求。
 *
 * 被拒事件不推进已接受时刻、也不改变已接受包名，因此连续重复事件与冷却期内出现的
 * 另一个被拦截应用都不会饿死下一次真正的拉回；`now` 早于已接受时刻（重启/时钟回退）
 * 时重新开窗。
 */
class FocusBlockerBounceGate(
    private val cooldownMillis: Long = defaultCooldownMillis,
) {
    private var acceptedPackageName: String? = null
    private var acceptedAtUptimeMillis: Long = neverAccepted

    /**
     * 返回还需要等待的毫秒数：`0` 表示本次请求被接受并记录时刻；`> 0` 表示仍在冷却中，
     * 返回剩余冷却时间且不修改已接受时刻与包名。
     */
    fun delayUntilAllowed(packageName: String, nowUptimeMillis: Long): Long {
        if (packageName.isBlank()) return 0L
        val now = nowUptimeMillis.coerceAtLeast(0L)
        val acceptedAt = acceptedAtUptimeMillis
        // 从未接受过、或 uptime 回退（重启/时钟异常）时重新开窗，不做无限等待。
        if (acceptedPackageName == null || now < acceptedAt) {
            accept(packageName, now)
            return 0L
        }
        val elapsed = now - acceptedAt
        if (elapsed >= cooldownMillis) {
            accept(packageName, now)
            return 0L
        }
        return cooldownMillis - elapsed
    }

    /** 最近一次被接受的包名；从未接受过时为 `null`。 */
    fun lastAcceptedPackageName(): String? = acceptedPackageName

    /** 最近一次被接受的时刻（uptime）；从未接受过时为 [neverAccepted]。 */
    fun lastAcceptedAtUptimeMillis(): Long = acceptedAtUptimeMillis

    private fun accept(packageName: String, nowUptimeMillis: Long) {
        acceptedPackageName = packageName
        acceptedAtUptimeMillis = nowUptimeMillis
    }

    companion object {
        /** 与旧 `bounceDebounceMillis` 一致的固定冷却。 */
        const val defaultCooldownMillis = 1500L

        /** 从未接受过请求的哨兵值。 */
        const val neverAccepted = -1L
    }
}

/**
 * 前台窗口观察：保存最近的包名与观察时刻，拒绝比已记录更旧的观察。
 *
 * 拒绝旧观察可以避免“Splash 结束后补发的旧 Weibo 事件”覆盖更新的本应用
 * `onTopResumedActivityChanged` 确认结果；更新的真实事件（如新的 MainTab 窗口）
 * 仍可正常替换。
 */
class FocusBlockerWindowTracker {
    private var trackedPackageName: String? = null
    private var trackedObservedAtUptimeMillis: Long = neverObserved

    /** 最近一次被接受的前台包名。 */
    fun latestPackageName(): String? = trackedPackageName

    /** 最近一次被接受的观察时刻（uptime）。 */
    fun latestObservedAtUptimeMillis(): Long = trackedObservedAtUptimeMillis

    /**
     * 记录一次前台观察；返回是否被接受。
     *
     * [observedAtUptimeMillis] 来自 `AccessibilityEvent.eventTime`（uptime 基准）或
     * `SystemClock.uptimeMillis()`；`<= 0` 回退到 [nowUptimeMillis]，未来值夹到当前时刻。
     */
    fun observe(
        packageName: String?,
        observedAtUptimeMillis: Long,
        nowUptimeMillis: Long,
    ): Boolean {
        if (packageName.isNullOrBlank()) return false
        val now = nowUptimeMillis.coerceAtLeast(0L)
        val observedAt = normalizeObservedAt(observedAtUptimeMillis, now)
        // 即使包名已被 loss 清空，也要按已记录时刻拒绝更旧的观察，避免旧事件复活旧前台。
        if (trackedObservedAtUptimeMillis != neverObserved &&
            observedAt < trackedObservedAtUptimeMillis
        ) {
            return false
        }
        trackedPackageName = packageName
        trackedObservedAtUptimeMillis = observedAt
        return true
    }

    /**
     * 记录一次“该包已不再前台”的明确 loss（UsageEvents PAUSED/STOPPED）。
     *
     * 只在“当前跟踪的仍是这个包”且观察不旧于已记录时刻时生效：清空包名但**保留**观察
     * 时刻，所以更旧的 AA/Splash 事件仍会被 [observe] 拒绝，不会把旧包复活。
     */
    fun observeLoss(
        packageName: String?,
        observedAtUptimeMillis: Long,
        nowUptimeMillis: Long,
    ): Boolean {
        if (packageName.isNullOrBlank()) return false
        if (trackedPackageName != packageName) return false
        val now = nowUptimeMillis.coerceAtLeast(0L)
        val observedAt = normalizeObservedAt(observedAtUptimeMillis, now)
        if (trackedObservedAtUptimeMillis != neverObserved &&
            observedAt < trackedObservedAtUptimeMillis
        ) {
            return false
        }
        trackedPackageName = null
        trackedObservedAtUptimeMillis = observedAt
        return true
    }

    /** 清空跟踪状态（进程重建/测试用）。 */
    fun clear() {
        trackedPackageName = null
        trackedObservedAtUptimeMillis = neverObserved
    }

    companion object {
        /** 从未观察到任何窗口的哨兵值。 */
        const val neverObserved = -1L

        /** 归一化观察时刻：非正数回退当前 uptime，未来值夹到当前 uptime。 */
        fun normalizeObservedAt(observedAtUptimeMillis: Long, nowUptimeMillis: Long): Long {
            val now = nowUptimeMillis.coerceAtLeast(0L)
            val observed = if (observedAtUptimeMillis <= 0L) now else observedAtUptimeMillis
            return if (observed > now) now else observed
        }
    }
}

/**
 * 进程内共享的前台状态：`MainActivity` 与无障碍服务共用同一个 tracker。
 *
 * 只保存包名与 uptime，不持有 Activity/View/Service 引用，避免单例泄漏；
 * 也不做跨进程持久化。
 */
object FocusBlockerForegroundState {
    /** 首次请求 + 最多一次重试。 */
    const val defaultMaxReturnAttempts = 2

    private val tracker = FocusBlockerWindowTracker()

    /** 记录一次前台观察；返回是否被接受（更旧的观察会被拒绝）。 */
    fun observeForeground(
        packageName: String?,
        observedAtUptimeMillis: Long,
        nowUptimeMillis: Long,
    ): Boolean = tracker.observe(packageName, observedAtUptimeMillis, nowUptimeMillis)

    /**
     * 记录一次明确 loss（该包已不再前台）。
     *
     * 只在 tracker 当前仍是该包且观察不旧时才生效：清空包名但保留观察时刻，
     * 之后更旧的 AA/MainActivity 观察仍会被拒绝。
     */
    fun observeForegroundLoss(
        packageName: String?,
        observedAtUptimeMillis: Long,
        nowUptimeMillis: Long,
    ): Boolean = tracker.observeLoss(packageName, observedAtUptimeMillis, nowUptimeMillis)

    /** 最近一次被接受的前台包名。 */
    fun foregroundPackageName(): String? = tracker.latestPackageName()

    /** 最近一次被接受的观察时刻（uptime）。 */
    fun foregroundObservedAtUptimeMillis(): Long = tracker.latestObservedAtUptimeMillis()

    /** 清空共享状态（测试/进程重建用）。 */
    fun reset() = tracker.clear()

    /**
     * 是否还值得再发一次拉回请求。
     *
     * 只有“目标仍然是被拦截的前台应用 + 拦截仍然有效 + 请求次数未超预算”时才为 `true`。
     * 用户已经回到多仪、切到微信/QQ 等允许的应用、或配置停用/过期时都为 `false`。
     */
    fun shouldRetryReturn(
        targetPackage: String,
        foregroundPackage: String?,
        blockingActive: Boolean,
        attempt: Int,
        maxAttempts: Int = defaultMaxReturnAttempts,
    ): Boolean {
        if (targetPackage.isBlank()) return false
        if (!blockingActive) return false
        if (attempt < 0) return false
        // attempt 是“已发出的请求序号”（0 起）：达到预算即不再补发。
        if (attempt >= maxAttempts - 1) return false
        return foregroundPackage == targetPackage
    }
}

/**
 * 待执行工作状态：generation / pending / deferred 的唯一权威（服务不保留镜像字段）。
 *
 * 关键区分：
 * - “结束本轮验证”（[finishVerificationCycle]）只清 pending 并作废本轮 generation，
 *   **保留**由真实重复事件触发排队的 deferred 复查；
 * - “完整取消”（[cancelAll]：本应用确认返回、允许应用在前台、配置停用、销毁、
 *   新一轮替换）才清空 deferred。
 *
 * deferred 截止时刻是全局固定的：重复事件只更换目标、不改期，因此既不会被连续事件
 * 推后（饿死），也不会因为换了被拦截应用而丢掉复查。
 */
class FocusBlockerPendingWorkState {
    private var currentGeneration = 0L
    private var pendingTarget: String? = null
    private var deferredTarget: String? = null
    private var deferredDeadline = 0L
    private var lastRecordedDetection: String? = null

    /** 本轮允许发出的请求次数上限（AA 默认 2，Usage 来源 1）；finish/cancel 恢复默认。 */
    private var cycleAttemptLimit = defaultCycleAttemptLimit

    /** 当前轮次标识；迟到回调必须用它判断是否仍然有效。 */
    fun generation(): Long = currentGeneration

    /** 本轮允许的请求次数上限。 */
    fun attemptLimit(): Int = cycleAttemptLimit

    /** 当前轮正在拉回的目标。 */
    fun pendingTargetPackage(): String? = pendingTarget

    /** 事件触发排队的复查目标。 */
    fun deferredTargetPackage(): String? = deferredTarget

    /** 事件触发复查的固定截止时刻（uptime）；未排程时为 `0`。 */
    fun deferredDeadlineUptimeMillis(): Long = deferredDeadline

    /** 最近一次真正记账的检测包名。 */
    fun lastRecordedDetectionPackage(): String? = lastRecordedDetection

    /**
     * 开始新一轮请求：generation++ 让旧回调失效、登记 pending，并清空 deferred
     * （新一轮属于完整替换）。
     *
     * 返回是否应记录一次原生拦截事件：同一轮内同一目标（补发请求、deferred 复查）
     * 只记一次，只有换目标或换轮才再记一次。
     */
    fun beginCycle(
        target: String,
        recordDetection: Boolean,
        maxAttempts: Int = defaultCycleAttemptLimit,
    ): Boolean {
        currentGeneration += 1
        pendingTarget = target
        clearDeferred()
        cycleAttemptLimit = maxAttempts.coerceIn(1, defaultCycleAttemptLimit)
        val shouldRecord = recordDetection && target != lastRecordedDetection
        if (shouldRecord) lastRecordedDetection = target
        return shouldRecord
    }

    /**
     * 结束本轮验证（未确认/预算耗尽）：只清 pending 并换 generation，
     * **保留**事件触发的 deferred 复查（它自带固定截止时刻）。
     */
    fun finishVerificationCycle() {
        currentGeneration += 1
        pendingTarget = null
        cycleAttemptLimit = defaultCycleAttemptLimit
    }

    /** 完整取消：清空 pending、deferred 与记账，并作废所有旧回调。 */
    fun cancelAll() {
        currentGeneration += 1
        pendingTarget = null
        clearDeferred()
        lastRecordedDetection = null
        cycleAttemptLimit = defaultCycleAttemptLimit
    }

    /**
     * 事件触发的一次复查排程。
     *
     * 已有同截止时刻的复查时只更换目标并返回 `false`（调用方无需重新 post，期限不变）；
     * 否则替换并返回 `true`。
     */
    fun armDeferred(target: String, deadlineUptimeMillis: Long): Boolean {
        if (target.isBlank()) return false
        if (deferredTarget != null && deferredDeadline == deadlineUptimeMillis) {
            deferredTarget = target
            return false
        }
        deferredTarget = target
        deferredDeadline = deadlineUptimeMillis
        return true
    }

    /** 取出 deferred 目标并清空（复查开始时调用一次，保证不会自动重排）。 */
    fun consumeDeferred(): String? {
        val target = deferredTarget
        clearDeferred()
        return target
    }

    /** 回调是否仍属于当前轮：陈旧 generation 与不匹配目标都不得再补发请求。 */
    fun isCurrent(generationId: Long, target: String?): Boolean =
        target != null && generationId == currentGeneration && pendingTarget == target

    private fun clearDeferred() {
        deferredTarget = null
        deferredDeadline = 0L
    }

    companion object {
        /** AA 来源一轮最多 2 次请求；Usage 来源固定 1 次。 */
        const val defaultCycleAttemptLimit = 2
    }
}

/** UsageEvents 元数据类型（adapter 只填 type/package/timestamp，不含任何界面内容）。 */
enum class FocusBlockerUsageKind {
    /** 进入前台（MOVE_TO_FOREGROUND / ACTIVITY_RESUMED）。 */
    RESUMED,

    /** 暂停（MOVE_TO_BACKGROUND / ACTIVITY_PAUSED）。 */
    PAUSED,

    /** 停止（ACTIVITY_STOPPED）。 */
    STOPPED,
}

/** 单条前台元数据事件；不含 text/className/节点等任何内容字段。 */
data class FocusBlockerUsageObservation(
    val packageName: String,
    val eventAtWallMillis: Long,
    val kind: FocusBlockerUsageKind,
)

/** UsageEvents 归约结论：前台 / 明确 loss / 无证据。 */
sealed class FocusBlockerUsageVerdict {
    /** 决定该结论的事件时刻（wall）；无证据时为 [Long.MIN_VALUE]。 */
    abstract val decisiveAtWallMillis: Long

    /** 无可作为前台依据的事件（空/过旧/未来/无关类型/重复）。 */
    object None : FocusBlockerUsageVerdict() {
        override val decisiveAtWallMillis: Long = Long.MIN_VALUE
    }

    /** 最近一次仍是前台的包。 */
    data class Foreground(
        override val decisiveAtWallMillis: Long,
        val packageName: String,
        val observedAtUptimeMillis: Long,
    ) : FocusBlockerUsageVerdict()

    /** 明确“某包已不再前台”的 loss。 */
    data class Loss(
        override val decisiveAtWallMillis: Long,
        val packageName: String,
        val observedAtUptimeMillis: Long,
    ) : FocusBlockerUsageVerdict()
}

/**
 * UsageEvents 归约器（纯 Kotlin）。
 *
 * - 只处理“会话/监控起点之后、最近 [freshnessMillis] 内、且不晚于当前时刻”的事件；
 * - 按 timestamp 稳定排序：RESUMED 取最近的包，同一当前包的 PAUSED/STOPPED 给出明确 loss；
 * - 新 app 的 resume 覆盖旧包，旧包迟到的 pause 不会清掉新前台；
 * - 已消费事件按 timestamp+package+kind 去重，重复读取不会重复请求；
 * - uptime 由事件 wall 时刻映射（`nowUptime - (nowWall - eventAtWall)`），不用“当前时刻”
 *   刷新旧事件，因此不可能凭重复旧事件伪造出更新的前台。
 */
class FocusBlockerUsageEventsReducer(
    private val freshnessMillis: Long = defaultFreshnessMillis,
) {
    private val consumedEvents = LinkedHashMap<String, Long>()
    private var lastResolved: List<FocusBlockerUsageObservation> = emptyList()

    /**
     * 归约一批元数据事件。
     *
     * 本方法**不**消费事件：调用方在接受/忽略后显式 [consume]；因全局冷却被拒绝时必须
     * 不消费，让下一次 fresh 查询重新读到它。
     */
    fun resolve(
        events: List<FocusBlockerUsageObservation>,
        nowWallMillis: Long,
        nowUptimeMillis: Long,
        sessionStartedAtWallMillis: Long,
    ): FocusBlockerUsageVerdict {
        val nowWall = nowWallMillis
        val nowUptime = nowUptimeMillis.coerceAtLeast(0L)
        pruneConsumed(nowWall)
        val oldest = nowWall - freshnessMillis
        val window = events
            .filter { it.eventAtWallMillis > 0L }
            .filter { it.eventAtWallMillis <= nowWall }
            .filter { it.eventAtWallMillis >= oldest }
            .filter { it.eventAtWallMillis >= sessionStartedAtWallMillis }
            // 墙钟事件若早于本次启动，不能映射成 0 后再被 tracker 当作“现在”。
            .filter { nowWall - it.eventAtWallMillis <= nowUptime }
            .filterNot { isConsumed(it) }
            .sortedBy { it.eventAtWallMillis }
        lastResolved = window
        var current: FocusBlockerUsageObservation? = null
        var loss: FocusBlockerUsageObservation? = null
        for (event in window) {
            when (event.kind) {
                FocusBlockerUsageKind.RESUMED -> {
                    current = event
                    loss = null
                }
                FocusBlockerUsageKind.PAUSED, FocusBlockerUsageKind.STOPPED -> {
                    val foreground = current
                    if (foreground == null) {
                        // 批内没有 resume：作为 loss 候选，由 tracker 判断是否仍是当前包。
                        loss = event
                    } else if (foreground.packageName == event.packageName) {
                        loss = event
                        current = null
                    }
                    // 旧包迟到的 pause：忽略，绝不清掉新前台。
                }
            }
        }
        val foreground = current
        val lossEvent = loss
        return when {
            foreground != null -> FocusBlockerUsageVerdict.Foreground(
                decisiveAtWallMillis = foreground.eventAtWallMillis,
                packageName = foreground.packageName,
                observedAtUptimeMillis = mapToUptime(
                    foreground.eventAtWallMillis,
                    nowWall,
                    nowUptime,
                ),
            )
            lossEvent != null -> FocusBlockerUsageVerdict.Loss(
                decisiveAtWallMillis = lossEvent.eventAtWallMillis,
                packageName = lossEvent.packageName,
                observedAtUptimeMillis = mapToUptime(lossEvent.eventAtWallMillis, nowWall, nowUptime),
            )
            else -> FocusBlockerUsageVerdict.None
        }
    }

    /** 消费该结论及其之前的全部事件（已被结论取代），之后重复读取不再重复请求。 */
    fun consume(verdict: FocusBlockerUsageVerdict) {
        if (verdict is FocusBlockerUsageVerdict.None) return
        val through = verdict.decisiveAtWallMillis
        for (event in lastResolved) {
            if (event.eventAtWallMillis <= through) {
                consumedEvents[key(event)] = event.eventAtWallMillis
            }
        }
    }

    /** 清空去重记录（会话重建/测试用）。 */
    fun reset() {
        consumedEvents.clear()
        lastResolved = emptyList()
    }

    private fun isConsumed(event: FocusBlockerUsageObservation): Boolean =
        consumedEvents.containsKey(key(event))

    private fun pruneConsumed(nowWallMillis: Long) {
        val oldest = nowWallMillis - freshnessMillis - pruneSlackMillis
        consumedEvents.entries.removeAll { it.value < oldest }
    }

    private fun key(event: FocusBlockerUsageObservation): String =
        "${event.eventAtWallMillis}|${event.packageName}|${event.kind.name}"

    private fun mapToUptime(
        eventAtWallMillis: Long,
        nowWallMillis: Long,
        nowUptimeMillis: Long,
    ): Long {
        val age = (nowWallMillis - eventAtWallMillis).coerceAtLeast(0L)
        return (nowUptimeMillis - age).coerceIn(0L, nowUptimeMillis)
    }

    companion object {
        /** 只接受最近 5s 的 UsageEvents。 */
        const val defaultFreshnessMillis = 5_000L

        /** 去重记录比 freshness 多留 1s，避免跨轮边界重复。 */
        private const val pruneSlackMillis = 1_000L
    }
}

/**
 * Usage 监控生命周期状态（纯 Kotlin）：generation / inflight / 会话起点。
 *
 * 服务把它当作唯一权威：配置变更、停止、过期、销毁都换 generation，迟到的 worker 结果
 * 因此无法恢复旧会话；主 looper 侧最多只有一个 inflight 查询。
 */
class FocusBlockerUsageMonitorState {
    private var currentGeneration = 0L
    private var active = false
    private var sessionStartedAtWall = 0L
    private var inflightGeneration: Long? = null

    fun generation(): Long = currentGeneration

    fun isActive(): Boolean = active

    fun sessionStartedAtWallMillis(): Long = sessionStartedAtWall

    fun hasInflightQuery(): Boolean = inflightGeneration != null

    /** 启动/重启监控：旧 worker 的占用保留到它真正返回，避免跨配置积压查询。 */
    fun start(nowWallMillis: Long): Long {
        currentGeneration += 1
        active = true
        sessionStartedAtWall = nowWallMillis.coerceAtLeast(0L)
        return currentGeneration
    }

    /** 停止监控（配置关闭/过期/销毁）：换 generation，迟到结果全部失效。 */
    fun stop(): Long {
        currentGeneration += 1
        active = false
        sessionStartedAtWall = 0L
        return currentGeneration
    }

    /** 占用一次查询；未激活或已有 inflight 时返回 false（主 looper 最多一个查询在飞）。 */
    fun beginQuery(): Boolean {
        if (!active || inflightGeneration != null) return false
        inflightGeneration = currentGeneration
        return true
    }

    /** 旧查询也须释放它自己的占用；旧结果不能清掉其他查询或进入新会话。 */
    fun completeQuery(generationId: Long): Boolean {
        if (inflightGeneration != generationId) return false
        inflightGeneration = null
        return isCurrent(generationId)
    }

    fun isCurrent(generationId: Long): Boolean = active && generationId == currentGeneration
}
