package com.duoyi.duoyi

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * UsageEvents 补漏策略：纯 reducer / 监控状态 / loss 语义 / 每轮请求上限。
 *
 * 覆盖真实竞态：旧事件不得伪造新前台、明确 loss 保留观察时刻、冷却期拒绝不消费事件、
 * 以及迟到 worker 结果因 generation 变化被丢弃。
 */
class FocusBlockerUsagePolicyTest {

    private companion object {
        const val weibo = "com.sina.weibo"
        const val alipay = "com.eg.android.AlipayGphone"
        const val wechat = "com.tencent.mm"
        const val duoyi = "com.duoyi.duoyi"

        const val nowWall = 1_700_000_010_000L
        const val nowUptime = 90_000L
        const val sessionStart = nowWall - 4_000L
    }

    @After
    fun resetSharedForegroundState() {
        FocusBlockerForegroundState.reset()
    }

    private fun resumed(pkg: String, atWall: Long) =
        FocusBlockerUsageObservation(pkg, atWall, FocusBlockerUsageKind.RESUMED)

    private fun paused(pkg: String, atWall: Long) =
        FocusBlockerUsageObservation(pkg, atWall, FocusBlockerUsageKind.PAUSED)

    private fun stopped(pkg: String, atWall: Long) =
        FocusBlockerUsageObservation(pkg, atWall, FocusBlockerUsageKind.STOPPED)

    @Test
    fun emptyOldFutureAndBeforeSessionEventsAreNeverForegroundEvidence() {
        val reducer = FocusBlockerUsageEventsReducer()
        assertEquals(
            FocusBlockerUsageVerdict.None,
            reducer.resolve(emptyList(), nowWall, nowUptime, sessionStart),
        )
        // 过旧（超过 5s 新鲜窗口）。
        assertEquals(
            FocusBlockerUsageVerdict.None,
            reducer.resolve(
                listOf(resumed(weibo, nowWall - 6_000L)),
                nowWall,
                nowUptime,
                sessionStart,
            ),
        )
        // 未来事件。
        assertEquals(
            FocusBlockerUsageVerdict.None,
            reducer.resolve(
                listOf(resumed(weibo, nowWall + 1_000L)),
                nowWall,
                nowUptime,
                sessionStart,
            ),
        )
        // 监控/会话起点之前的事件。
        assertEquals(
            FocusBlockerUsageVerdict.None,
            reducer.resolve(
                listOf(resumed(weibo, sessionStart - 1L)),
                nowWall,
                nowUptime,
                sessionStart,
            ),
        )
    }

    @Test
    fun latestResumeWinsAndLatePauseOfAnOlderPackageIsIgnored() {
        val reducer = FocusBlockerUsageEventsReducer()
        val verdict = reducer.resolve(
            listOf(
                resumed(weibo, nowWall - 900L),
                resumed(alipay, nowWall - 600L),
                // 旧包迟到的 pause：不得清掉新前台。
                paused(weibo, nowWall - 300L),
            ),
            nowWall,
            nowUptime,
            sessionStart,
        )
        assertTrue(verdict is FocusBlockerUsageVerdict.Foreground)
        val foreground = verdict as FocusBlockerUsageVerdict.Foreground
        assertEquals(alipay, foreground.packageName)
        assertEquals(nowWall - 600L, foreground.decisiveAtWallMillis)
        // uptime 由事件 wall 时刻映射，而不是被“当前时刻”刷新。
        assertEquals(nowUptime - 600L, foreground.observedAtUptimeMillis)
    }

    @Test
    fun pauseOrStopOfTheCurrentPackageYieldsAnExplicitLoss() {
        val reducer = FocusBlockerUsageEventsReducer()
        val stoppedVerdict = reducer.resolve(
            listOf(resumed(weibo, nowWall - 500L), stopped(weibo, nowWall - 400L)),
            nowWall,
            nowUptime,
            sessionStart,
        )
        assertTrue(stoppedVerdict is FocusBlockerUsageVerdict.Loss)
        val loss = stoppedVerdict as FocusBlockerUsageVerdict.Loss
        assertEquals(weibo, loss.packageName)
        assertEquals(nowUptime - 400L, loss.observedAtUptimeMillis)

        // resume → pause → resume：最终仍是前台，不是 loss。
        val reopened = reducer.resolve(
            listOf(
                resumed(weibo, nowWall - 500L),
                paused(weibo, nowWall - 400L),
                resumed(weibo, nowWall - 100L),
            ),
            nowWall,
            nowUptime,
            sessionStart,
        )
        assertTrue(reopened is FocusBlockerUsageVerdict.Foreground)
        assertEquals(
            weibo,
            (reopened as FocusBlockerUsageVerdict.Foreground).packageName,
        )
    }

    @Test
    fun lonePauseWithoutInBatchResumeIsALossCandidateForTheTracker() {
        val reducer = FocusBlockerUsageEventsReducer()
        val verdict = reducer.resolve(
            listOf(paused(weibo, nowWall - 200L)),
            nowWall,
            nowUptime,
            sessionStart,
        )
        // 批内没有 resume：输出候选，由 tracker 判断是否仍是当前包。
        assertTrue(verdict is FocusBlockerUsageVerdict.Loss)
        assertEquals(
            weibo,
            (verdict as FocusBlockerUsageVerdict.Loss).packageName,
        )
    }

    @Test
    fun consumedEventsAreNotResolvedOrRequestedAgainOnRefresh() {
        val reducer = FocusBlockerUsageEventsReducer()
        val events = listOf(resumed(weibo, nowWall - 800L))
        val first = reducer.resolve(events, nowWall, nowUptime, sessionStart)
        assertTrue(first is FocusBlockerUsageVerdict.Foreground)
        reducer.consume(first)
        // 同一批事件在下一轮刷新中不再作为证据（避免重复记录/重复请求）。
        assertEquals(
            FocusBlockerUsageVerdict.None,
            reducer.resolve(events, nowWall, nowUptime, sessionStart),
        )
        assertEquals(
            FocusBlockerUsageVerdict.None,
            reducer.resolve(events, nowWall + 500L, nowUptime + 500L, sessionStart),
        )
        // 新事件仍然有效。
        assertTrue(
            reducer.resolve(
                listOf(resumed(alipay, nowWall - 100L)),
                nowWall,
                nowUptime,
                sessionStart,
            ) is FocusBlockerUsageVerdict.Foreground,
        )
    }

    @Test
    fun cooldownRejectionKeepsTheEventForTheNextFreshQuery() {
        val gate = FocusBlockerBounceGate()
        val reducer = FocusBlockerUsageEventsReducer()
        // 冷却窗口起点：另一次请求刚被接受。
        assertEquals(0L, gate.delayUntilAllowed(wechat, nowUptime))
        val events = listOf(resumed(alipay, nowWall - 1_000L))
        val verdict = reducer.resolve(events, nowWall, nowUptime + 400L, sessionStart)
        assertTrue(verdict is FocusBlockerUsageVerdict.Foreground)
        // 冷却中：被拒时不消费，下一次 fresh 查询仍能读到同一事件。
        assertTrue(gate.delayUntilAllowed(alipay, nowUptime + 400L) > 0L)
        val again = reducer.resolve(events, nowWall, nowUptime + 400L, sessionStart)
        assertTrue(again is FocusBlockerUsageVerdict.Foreground)
        // 冷却结束：接受并消费，此后不再重复请求。
        assertEquals(0L, gate.delayUntilAllowed(alipay, nowUptime + 1_500L))
        reducer.consume(again)
        assertEquals(
            FocusBlockerUsageVerdict.None,
            reducer.resolve(events, nowWall, nowUptime + 1_600L, sessionStart),
        )
    }

    @Test
    fun usageCycleAllowsOnlyOneRequestWhileAaKeepsTwo() {
        val work = FocusBlockerPendingWorkState()
        assertEquals(FocusBlockerPendingWorkState.defaultCycleAttemptLimit, work.attemptLimit())
        work.beginCycle(alipay, recordDetection = true, maxAttempts = 1)
        assertEquals(1, work.attemptLimit())
        // 第 1 次请求之后不再补发第二次。
        assertFalse(
            FocusBlockerForegroundState.shouldRetryReturn(
                targetPackage = alipay,
                foregroundPackage = alipay,
                blockingActive = true,
                attempt = 0,
                maxAttempts = work.attemptLimit(),
            ),
        )
        // finish 恢复默认：AA 轮次仍然允许一次补发。
        work.finishVerificationCycle()
        assertEquals(FocusBlockerPendingWorkState.defaultCycleAttemptLimit, work.attemptLimit())
        work.beginCycle(weibo, recordDetection = true)
        assertEquals(2, work.attemptLimit())
        assertTrue(
            FocusBlockerForegroundState.shouldRetryReturn(
                targetPackage = weibo,
                foregroundPackage = weibo,
                blockingActive = true,
                attempt = 0,
                maxAttempts = work.attemptLimit(),
            ),
        )
        assertFalse(
            FocusBlockerForegroundState.shouldRetryReturn(
                targetPackage = weibo,
                foregroundPackage = weibo,
                blockingActive = true,
                attempt = 1,
                maxAttempts = work.attemptLimit(),
            ),
        )
        work.cancelAll()
        assertEquals(FocusBlockerPendingWorkState.defaultCycleAttemptLimit, work.attemptLimit())
        work.beginCycle(alipay, recordDetection = true, maxAttempts = Int.MAX_VALUE)
        assertEquals(2, work.attemptLimit())
    }

    @Test
    fun ownConfirmationIsNotOverwrittenByAnOlderUsageObservation() {
        FocusBlockerForegroundState.reset()
        // MainActivity/AA 已确认回到多仪。
        assertTrue(FocusBlockerForegroundState.observeForeground(duoyi, 5_000L, 5_000L))
        // 更旧的 usage 结果必须被拒绝，且不改变已确认的前台。
        assertFalse(FocusBlockerForegroundState.observeForeground(weibo, 4_000L, 5_100L))
        assertEquals(duoyi, FocusBlockerForegroundState.foregroundPackageName())
        assertEquals(5_000L, FocusBlockerForegroundState.foregroundObservedAtUptimeMillis())
    }

    @Test
    fun lossPreservesObservationTimeSoOlderEventsCannotReviveIt() {
        FocusBlockerForegroundState.reset()
        assertTrue(FocusBlockerForegroundState.observeForeground(weibo, 1_000L, 1_000L))
        assertTrue(FocusBlockerForegroundState.observeForegroundLoss(weibo, 2_000L, 2_000L))
        assertNull(FocusBlockerForegroundState.foregroundPackageName())
        // 观察时刻保留：更旧的事件不能把该包复活。
        assertEquals(2_000L, FocusBlockerForegroundState.foregroundObservedAtUptimeMillis())
        assertFalse(FocusBlockerForegroundState.observeForeground(weibo, 1_500L, 2_100L))
        assertNull(FocusBlockerForegroundState.foregroundPackageName())
        // 更新的真实观察仍然有效。
        assertTrue(FocusBlockerForegroundState.observeForeground(alipay, 2_500L, 2_500L))
        assertEquals(alipay, FocusBlockerForegroundState.foregroundPackageName())
    }

    @Test
    fun lossForAnotherPackageDoesNotClearTheCurrentForeground() {
        FocusBlockerForegroundState.reset()
        assertTrue(FocusBlockerForegroundState.observeForeground(alipay, 1_000L, 1_000L))
        // 其他包的 pause 不是当前前台的 loss。
        assertFalse(FocusBlockerForegroundState.observeForegroundLoss(wechat, 1_200L, 1_200L))
        assertEquals(alipay, FocusBlockerForegroundState.foregroundPackageName())
        // 时间更早的 loss 同样不生效。
        assertFalse(FocusBlockerForegroundState.observeForegroundLoss(alipay, 900L, 1_300L))
        assertEquals(alipay, FocusBlockerForegroundState.foregroundPackageName())
        // 当前包的 loss 才能清空。
        assertTrue(FocusBlockerForegroundState.observeForegroundLoss(alipay, 1_400L, 1_400L))
        assertNull(FocusBlockerForegroundState.foregroundPackageName())
    }

    @Test
    fun slowWorkerResultsKeepTheirOriginalAgeAndCannotOverrideANewerAllowedApp() {
        val reducer = FocusBlockerUsageEventsReducer()
        val events = listOf(resumed(alipay, nowWall - 500L))
        // 处理时墙钟与 uptime 一起前进 2 秒；事件观察时刻必须仍是原来的时刻。
        val result = reducer.resolve(events, nowWall + 2_000L, nowUptime + 2_000L, sessionStart)
        assertTrue(result is FocusBlockerUsageVerdict.Foreground)
        val foreground = result as FocusBlockerUsageVerdict.Foreground
        assertEquals(nowUptime - 500L, foreground.observedAtUptimeMillis)
        assertTrue(FocusBlockerForegroundState.observeForeground(wechat, nowUptime + 100L, nowUptime + 100L))
        assertFalse(FocusBlockerForegroundState.observeForeground(alipay, foreground.observedAtUptimeMillis, nowUptime + 2_000L))
        assertEquals(wechat, FocusBlockerForegroundState.foregroundPackageName())
        // worker 超过新鲜窗口才返回时，整批已不能作为新前台证据。
        assertEquals(FocusBlockerUsageVerdict.None, reducer.resolve(events, nowWall + 6_000L, nowUptime + 6_000L, sessionStart))
    }

    @Test
    fun eventsPredatingThisBootCannotBeMappedToTheCurrentForeground() {
        val reducer = FocusBlockerUsageEventsReducer()
        assertEquals(
            FocusBlockerUsageVerdict.None,
            reducer.resolve(listOf(resumed(alipay, nowWall - 1_000L)), nowWall, 100L, sessionStart),
        )
    }

    @Test
    fun monitorGenerationRejectsLateWorkerResultsAndKeepsOneInflightQuery() {
        val monitor = FocusBlockerUsageMonitorState()
        assertFalse(monitor.isActive())
        assertFalse(monitor.beginQuery())

        val first = monitor.start(1_000L)
        assertTrue(monitor.isActive())
        assertEquals(1_000L, monitor.sessionStartedAtWallMillis())
        assertTrue(monitor.beginQuery())
        // 主 looper 侧最多一个 inflight 查询。
        assertFalse(monitor.beginQuery())

        // 配置变化后旧查询仍占用槽位；未真正返回前不得再排新查询。
        val second = monitor.start(2_000L)
        assertTrue(monitor.hasInflightQuery())
        assertFalse(monitor.beginQuery())
        assertFalse(monitor.completeQuery(first))
        assertTrue(monitor.isCurrent(second))
        assertFalse(monitor.isCurrent(first))
        assertFalse(monitor.hasInflightQuery())
        assertTrue(monitor.beginQuery())
        // 旧 worker 重复回调不得清掉新查询的占用。
        assertFalse(monitor.completeQuery(first))
        assertTrue(monitor.hasInflightQuery())
        assertTrue(monitor.completeQuery(second))

        // 停止再启动也不能积压旧读取；结果只能释放自己的槽位，不能恢复旧会话。
        val third = monitor.start(3_000L)
        assertTrue(monitor.beginQuery())
        monitor.stop()
        val fourth = monitor.start(4_000L)
        assertFalse(monitor.beginQuery())
        assertFalse(monitor.completeQuery(third))
        assertTrue(monitor.beginQuery())
        monitor.stop()
        assertFalse(monitor.completeQuery(fourth))
        assertFalse(monitor.isActive())
        assertFalse(monitor.hasInflightQuery())
        assertFalse(monitor.beginQuery())
        assertEquals(0L, monitor.sessionStartedAtWallMillis())
    }
}
