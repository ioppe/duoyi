package com.duoyi.duoyi

import java.util.ArrayDeque
import java.util.concurrent.Executor
import java.util.concurrent.RejectedExecutionException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 焦点状态快照查询：后台读取 / 单飞合并 / 主线程回调 / 有界等待 / 销毁后丢弃迟到结果。
 *
 * 全部用假队列执行器驱动，不 sleep、不依赖 Android 与真实线程调度。
 */
class FocusStatusQueryTest {

    /** 假单线程 worker：只排队不自动执行，由测试显式 drain。 */
    private class FakeWorker(private val rejectOnSubmit: Boolean = false) : Executor {
        private val tasks = ArrayDeque<Runnable>()
        var submitted = 0

        override fun execute(command: Runnable) {
            if (rejectOnSubmit) throw RejectedExecutionException("closed")
            submitted += 1
            tasks.addLast(command)
        }

        fun runNext() {
            tasks.removeFirst().run()
        }

        val pending: Int
            get() = tasks.size
    }

    /** 假 owner 队列（主线程）：post 只排队，由测试显式 drain。 */
    private class FakeOwnerQueue {
        private val tasks = ArrayDeque<Runnable>()

        fun post(command: Runnable) {
            tasks.addLast(command)
        }

        fun drain() {
            while (tasks.isNotEmpty()) tasks.removeFirst().run()
        }

        val pending: Int
            get() = tasks.size
    }

    private class Fixture(
        val worker: FakeWorker = FakeWorker(),
        val owner: FakeOwnerQueue = FakeOwnerQueue(),
        private val readFailure: Throwable? = null,
        nanoTime: () -> Long = System::nanoTime,
        val slowWarnings: MutableList<Long> = ArrayList(),
    ) {
        var readCount = 0

        val query = FocusStatusQuery<String>(
            worker = worker,
            postToOwner = owner::post,
            readSnapshot = {
                readCount += 1
                if (readFailure != null) throw readFailure
                foregroundPackage
            },
            nanoTime = nanoTime,
            onSlowQuery = { elapsedMillis -> slowWarnings.add(elapsedMillis) },
        )

        val snapshots = ArrayList<String>()
        val failures = ArrayList<Throwable>()
        val unavailable = ArrayList<FocusStatusUnavailable>()

        /** 一次回复 = 一个等待者恰好被回复一次。 */
        val replies: Int
            get() = snapshots.size + failures.size + unavailable.size

        fun request() {
            query.request(
                onSnapshot = { value -> snapshots.add(value) },
                onFailure = { cause -> failures.add(cause) },
                onUnavailable = { reason -> unavailable.add(reason) },
            )
        }
    }

    private companion object {
        const val foregroundPackage = "com.sina.weibo"
    }

    @Test
    fun readRunsOnWorkerAndNeverOnTheOwnerQueue() {
        val fixture = Fixture()

        fixture.request()

        // 提交阶段不读取、不回复，只排一次 worker 任务。
        assertEquals(0, fixture.readCount)
        assertEquals(0, fixture.replies)
        assertEquals(1, fixture.worker.pending)

        fixture.worker.runNext()
        assertEquals(1, fixture.readCount)
        // 读取完成也不能在 worker 线程里直接回主线程的调用方。
        assertEquals(0, fixture.replies)
        assertEquals(1, fixture.owner.pending)

        fixture.owner.drain()
        assertEquals(listOf(foregroundPackage), fixture.snapshots)
        assertFalse(fixture.query.hasInFlightSnapshot)
        assertEquals(0, fixture.query.pendingRequestCount)
    }

    @Test
    fun ownerQueueKeepsRunningControlActionsWhileSnapshotIsBlocked() {
        val fixture = Fixture()
        fixture.request()

        // worker 读取被阻塞（任务仍在队列里）时，owner 队列照样能执行控制动作。
        var controlRan = false
        fixture.owner.post { controlRan = true }
        fixture.owner.drain()

        assertTrue(controlRan)
        assertEquals(0, fixture.readCount)
        assertEquals(0, fixture.replies)
        assertEquals(1, fixture.worker.pending)
    }

    @Test
    fun concurrentRequestsShareOneInFlightSnapshot() {
        val fixture = Fixture()

        fixture.request()
        fixture.request()
        fixture.request()

        assertEquals(1, fixture.worker.submitted)
        assertEquals(3, fixture.query.pendingRequestCount)
        assertTrue(fixture.query.hasInFlightSnapshot)

        fixture.worker.runNext()
        fixture.owner.drain()

        assertEquals(1, fixture.readCount)
        assertEquals(
            listOf(foregroundPackage, foregroundPackage, foregroundPackage),
            fixture.snapshots,
        )
        assertEquals(0, fixture.worker.pending)
    }

    @Test
    fun readFailureReachesEveryWaiter() {
        val boom = IllegalStateException("binder died")
        val fixture = Fixture(readFailure = boom)

        fixture.request()
        fixture.request()
        fixture.worker.runNext()
        fixture.owner.drain()

        assertEquals(2, fixture.failures.size)
        assertSame(boom, fixture.failures[0])
        assertSame(boom, fixture.failures[1])
        // 失败不得用缓存前台包名兜底。
        assertTrue(fixture.snapshots.isEmpty())
        assertTrue(fixture.unavailable.isEmpty())
    }

    @Test
    fun waitingCallbacksAreBoundedWithExplicitBusy() {
        val fixture = Fixture()
        val capacity = FocusStatusQuery.defaultPendingRequestLimit

        repeat(capacity) { fixture.request() }
        assertEquals(capacity, fixture.query.pendingRequestCount)
        assertEquals(1, fixture.worker.submitted)

        fixture.request()
        assertEquals(listOf(FocusStatusUnavailable.BUSY), fixture.unavailable)
        assertEquals(capacity, fixture.query.pendingRequestCount)
        assertEquals(1, fixture.worker.submitted)

        fixture.worker.runNext()
        fixture.owner.drain()
        assertEquals(capacity, fixture.snapshots.size)
        assertEquals(1, fixture.unavailable.size)
    }

    @Test
    fun disposeRepliesDisposedOnceAndDropsLateSuccess() {
        val fixture = Fixture()
        fixture.request()
        fixture.request()

        fixture.query.dispose()

        assertEquals(
            listOf(FocusStatusUnavailable.DISPOSED, FocusStatusUnavailable.DISPOSED),
            fixture.unavailable,
        )
        assertTrue(fixture.query.isDisposed)

        // 迟到的 worker 成功结果必须被 generation 丢弃，不得二次回复。
        fixture.worker.runNext()
        fixture.owner.drain()
        assertEquals(2, fixture.replies)
        assertTrue(fixture.snapshots.isEmpty())

        // 销毁后停止新任务。
        fixture.request()
        assertEquals(3, fixture.replies)
        assertEquals(1, fixture.worker.submitted)
        assertEquals(0, fixture.query.pendingRequestCount)
    }

    @Test
    fun completionPostedBeforeDisposeIsDroppedToo() {
        val fixture = Fixture()
        fixture.request()

        fixture.worker.runNext()
        // 完成事件已投进 owner 队列，但还没执行就销毁了。
        fixture.query.dispose()
        fixture.owner.drain()

        assertEquals(listOf(FocusStatusUnavailable.DISPOSED), fixture.unavailable)
        assertEquals(1, fixture.replies)
        assertTrue(fixture.snapshots.isEmpty())
    }

    @Test
    fun requestMustBeMadeFromTheOwnerThread() {
        val fixture = Fixture()
        var thrown: Throwable? = null

        val foreignThread = Thread { thrown = runCatching { fixture.request() }.exceptionOrNull() }
        foreignThread.start()
        foreignThread.join()

        assertTrue(thrown is IllegalStateException)
        assertEquals(0, fixture.readCount)
        assertEquals(0, fixture.worker.submitted)
    }

    @Test
    fun slowSnapshotWarnsOnceWithDurationOnly() {
        // 读取前 0ns、读取后 600ms：只允许一条仅含耗时的警告。
        val clock = ArrayDeque(listOf(0L, 600_000_000L, 600_000_000L))
        val warnings = ArrayList<Long>()
        val fixture = Fixture(
            nanoTime = { if (clock.isEmpty()) 600_000_000L else clock.removeFirst() },
            slowWarnings = warnings,
        )

        fixture.request()
        fixture.request()
        fixture.worker.runNext()
        fixture.owner.drain()

        assertEquals(listOf(600L), warnings)
        assertEquals(2, fixture.replies)
    }

    @Test
    fun rejectedSubmissionDoesNotStrandWaiters() {
        val fixture = Fixture(worker = FakeWorker(rejectOnSubmit = true))

        fixture.request()

        assertEquals(listOf(FocusStatusUnavailable.DISPOSED), fixture.unavailable)
        assertEquals(1, fixture.replies)
        assertEquals(0, fixture.worker.pending)
        assertEquals(0, fixture.worker.submitted)
        assertEquals(0, fixture.query.pendingRequestCount)
        assertFalse(fixture.query.hasInFlightSnapshot)
    }
}
