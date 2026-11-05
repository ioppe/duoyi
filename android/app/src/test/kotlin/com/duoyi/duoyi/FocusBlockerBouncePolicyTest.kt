package com.duoyi.duoyi

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 原生拉回纯策略：连续事件不得饿死后续拉回，旧窗口观察不得覆盖更新的前台确认，
 * 补发请求必须同时满足“目标仍被拦截 + 仍在前台 + 未超预算”。
 */
class FocusBlockerBouncePolicyTest {

    private companion object {
        const val weibo = "com.sina.weibo"
        const val alipay = "com.eg.android.AlipayGphone"
        const val wechat = "com.tencent.mm"
        const val qq = "com.tencent.mobileqq"
        const val duoyi = "com.duoyi.duoyi"
        const val cooldown = FocusBlockerBounceGate.defaultCooldownMillis
    }

    @After
    fun clearSharedForegroundState() {
        FocusBlockerForegroundState.reset()
    }

    @Test
    fun firstRequestIncludingZeroClockIsAcceptedImmediately() {
        val gate = FocusBlockerBounceGate()
        assertEquals(0L, gate.delayUntilAllowed(weibo, 0L))
        assertEquals(weibo, gate.lastAcceptedPackageName())
        assertEquals(0L, gate.lastAcceptedAtUptimeMillis())
        assertEquals(cooldown, gate.delayUntilAllowed(weibo, 0L))
    }

    @Test
    fun continuousDuplicateBurstKeepsTheDeadlineAndNeverStarvesLaterReturns() {
        val gate = FocusBlockerBounceGate()
        // 真机事件突发：立即、100ms、500ms、1400ms 连续重复，1500ms 才算冷却结束。
        assertEquals(0L, gate.delayUntilAllowed(weibo, 0L))
        assertEquals(0L, gate.lastAcceptedAtUptimeMillis())

        val burst = listOf(100L to 1_400L, 500L to 1_000L, 1_400L to 100L)
        for ((at, remaining) in burst) {
            // 只返回“还需等待多久”：剩余延迟递减，说明截止时刻固定在 1500。
            assertEquals(remaining, gate.delayUntilAllowed(weibo, at))
            // 被拒事件绝不能推进已接受时刻，否则连续事件会把冷却无限推后。
            assertEquals(0L, gate.lastAcceptedAtUptimeMillis())
        }

        assertEquals(0L, gate.delayUntilAllowed(weibo, cooldown))
        assertEquals(cooldown, gate.lastAcceptedAtUptimeMillis())
    }

    @Test
    fun cooldownIsGlobalAcrossBlockedPackageChanges() {
        val gate = FocusBlockerBounceGate()
        // T0：weibo 的真实检测被接受。
        assertEquals(0L, gate.delayUntilAllowed(weibo, 0L))
        // 冷却期内换到另一个被拦截应用：同样只拿到剩余冷却，且不推进、不改写已接受状态。
        assertEquals(1_400L, gate.delayUntilAllowed(alipay, 100L))
        assertEquals(weibo, gate.lastAcceptedPackageName())
        assertEquals(0L, gate.lastAcceptedAtUptimeMillis())
        assertEquals(1_000L, gate.delayUntilAllowed(weibo, 500L))
        assertEquals(weibo, gate.lastAcceptedPackageName())
        assertEquals(0L, gate.lastAcceptedAtUptimeMillis())
        // 全局冷却到期后，新目标才被接受并记录。
        assertEquals(0L, gate.delayUntilAllowed(alipay, cooldown))
        assertEquals(alipay, gate.lastAcceptedPackageName())
        assertEquals(cooldown, gate.lastAcceptedAtUptimeMillis())
    }

    @Test
    fun backwardsClockRestartsTheWindowInsteadOfBlockingForALongTime() {
        val gate = FocusBlockerBounceGate()
        assertEquals(0L, gate.delayUntilAllowed(weibo, 5_000L))
        // 设备重启后 uptime 归零：不能把更大的旧时刻当成“冷却中”拒绝。
        assertEquals(0L, gate.delayUntilAllowed(weibo, 10L))
        assertEquals(10L, gate.lastAcceptedAtUptimeMillis())
        assertEquals(cooldown - 10L, gate.delayUntilAllowed(weibo, 20L))
        assertEquals(10L, gate.lastAcceptedAtUptimeMillis())
    }

    @Test
    fun blankPackageNeverMovesTheAcceptedTimestamp() {
        val gate = FocusBlockerBounceGate()
        assertEquals(0L, gate.delayUntilAllowed(weibo, 0L))
        assertEquals(0L, gate.delayUntilAllowed("", 1_000L))
        assertEquals(weibo, gate.lastAcceptedPackageName())
        assertEquals(0L, gate.lastAcceptedAtUptimeMillis())
    }

    @Test
    fun staleSplashObservationDoesNotReplaceNewerOwnConfirmation() {
        val tracker = FocusBlockerWindowTracker()
        // MainActivity 的 onTopResumedActivityChanged 记录：本应用在前台，时刻 1000。
        assertTrue(tracker.observe(duoyi, 1_000L, 1_200L))
        // Splash 结束后补发的旧 Weibo 事件（时刻 900）必须被拒绝。
        assertFalse(tracker.observe(weibo, 900L, 1_300L))
        assertEquals(duoyi, tracker.latestPackageName())
        assertEquals(1_000L, tracker.latestObservedAtUptimeMillis())
    }

    @Test
    fun newerMainTabObservationCanReplaceTheTrackedForeground() {
        val tracker = FocusBlockerWindowTracker()
        assertTrue(tracker.observe(weibo, 1_000L, 1_000L))
        // 真正更新的本应用窗口事件（新的 MainTab）必须能替换。
        assertTrue(tracker.observe(duoyi, 1_050L, 1_060L))
        assertEquals(duoyi, tracker.latestPackageName())
        assertEquals(1_050L, tracker.latestObservedAtUptimeMillis())
        assertTrue(tracker.observe(weibo, 1_100L, 1_100L))
        assertEquals(weibo, tracker.latestPackageName())
    }

    @Test
    fun equalTimestampObservationStillReplacesAndTiesAreDeterministic() {
        val tracker = FocusBlockerWindowTracker()
        assertTrue(tracker.observe(weibo, 700L, 700L))
        assertTrue(tracker.observe(duoyi, 700L, 700L))
        assertEquals(duoyi, tracker.latestPackageName())
        assertEquals(700L, tracker.latestObservedAtUptimeMillis())
    }

    @Test
    fun missingOrFutureEventTimeFallsBackToNowWithoutPoisoningOrdering() {
        val tracker = FocusBlockerWindowTracker()
        // eventTime <= 0 回退到当前 uptime。
        assertTrue(tracker.observe(wechat, 0L, 500L))
        assertEquals(500L, tracker.latestObservedAtUptimeMillis())
        // 未来时间戳被夹到当前时刻，之后真实事件仍可覆盖。
        assertTrue(tracker.observe(duoyi, 9_999L, 600L))
        assertEquals(600L, tracker.latestObservedAtUptimeMillis())
        assertTrue(tracker.observe(weibo, 650L, 650L))
        assertEquals(weibo, tracker.latestPackageName())
    }

    @Test
    fun trackerIgnoresMissingPackages() {
        val tracker = FocusBlockerWindowTracker()
        assertFalse(tracker.observe(null, 100L, 100L))
        assertFalse(tracker.observe(" ", 100L, 100L))
        assertNull(tracker.latestPackageName())
        assertEquals(FocusBlockerWindowTracker.neverObserved, tracker.latestObservedAtUptimeMillis())
    }

    @Test
    fun retryOnlyForMatchingActiveBlockedTargetWithinBudget() {
        // 目标仍是被拦截的前台应用、拦截有效、还有预算：可以补发一次。
        assertTrue(
            FocusBlockerForegroundState.shouldRetryReturn(
                targetPackage = weibo,
                foregroundPackage = weibo,
                blockingActive = true,
                attempt = 0,
            ),
        )
        // 已经补发过一次：预算耗尽。
        assertFalse(
            FocusBlockerForegroundState.shouldRetryReturn(weibo, weibo, blockingActive = true, attempt = 1),
        )
        // 用户已回到多仪。
        assertFalse(
            FocusBlockerForegroundState.shouldRetryReturn(weibo, duoyi, blockingActive = true, attempt = 0),
        )
        // 白名单应用在前台：绝不抢。
        assertFalse(
            FocusBlockerForegroundState.shouldRetryReturn(weibo, wechat, blockingActive = true, attempt = 0),
        )
        assertFalse(
            FocusBlockerForegroundState.shouldRetryReturn(weibo, qq, blockingActive = true, attempt = 0),
        )
        // 前台是另一个被拦截应用：让给它的请求。
        assertFalse(
            FocusBlockerForegroundState.shouldRetryReturn(weibo, alipay, blockingActive = true, attempt = 0),
        )
        // 没有可信前台观察时不补发。
        assertFalse(
            FocusBlockerForegroundState.shouldRetryReturn(weibo, null, blockingActive = true, attempt = 0),
        )
        // 配置停用/过期。
        assertFalse(
            FocusBlockerForegroundState.shouldRetryReturn(weibo, weibo, blockingActive = false, attempt = 0),
        )
        assertFalse(
            FocusBlockerForegroundState.shouldRetryReturn("", weibo, blockingActive = true, attempt = 0),
        )
        assertFalse(
            FocusBlockerForegroundState.shouldRetryReturn(weibo, weibo, blockingActive = true, attempt = -1),
        )
    }

    @Test
    fun returnAttemptBudgetIsTwoByDefault() {
        assertEquals(2, FocusBlockerForegroundState.defaultMaxReturnAttempts)
        assertTrue(FocusBlockerForegroundState.shouldRetryReturn(weibo, weibo, true, 0, maxAttempts = 3))
        assertTrue(FocusBlockerForegroundState.shouldRetryReturn(weibo, weibo, true, 1, maxAttempts = 3))
        assertFalse(FocusBlockerForegroundState.shouldRetryReturn(weibo, weibo, true, 2, maxAttempts = 3))
        assertFalse(FocusBlockerForegroundState.shouldRetryReturn(weibo, weibo, true, 0, maxAttempts = 1))
    }

    @Test
    fun sharedForegroundStateUsesTheProcessLocalTracker() {
        FocusBlockerForegroundState.reset()
        assertNull(FocusBlockerForegroundState.foregroundPackageName())
        assertTrue(FocusBlockerForegroundState.observeForeground(weibo, 1_000L, 1_000L))
        assertTrue(FocusBlockerForegroundState.observeForeground(duoyi, 1_200L, 1_300L))
        assertEquals(duoyi, FocusBlockerForegroundState.foregroundPackageName())
        assertEquals(1_200L, FocusBlockerForegroundState.foregroundObservedAtUptimeMillis())
        // 更旧的观察被拒绝，共享状态保持不变。
        assertFalse(FocusBlockerForegroundState.observeForeground(weibo, 1_100L, 1_400L))
        assertEquals(duoyi, FocusBlockerForegroundState.foregroundPackageName())
    }

    @Test
    fun eventTimelineKeepsTheEventArmedDeferredCheckAfterUnconfirmed() {
        val gate = FocusBlockerBounceGate()
        val work = FocusBlockerPendingWorkState()
        // T0：真实检测被接受，第一轮开始并记账一次。
        assertEquals(0L, gate.delayUntilAllowed(weibo, 0L))
        assertTrue(work.beginCycle(weibo, recordDetection = true))
        val requestId = work.generation()
        assertTrue(work.isCurrent(requestId, weibo))
        // T200：重复事件被拒，排队固定截止 T0 + 1500 的复查。
        val remaining = gate.delayUntilAllowed(weibo, 200L)
        assertEquals(1_300L, remaining)
        assertTrue(work.armDeferred(weibo, 200L + remaining))
        assertEquals(1_500L, work.deferredDeadlineUptimeMillis())
        // T600：验证发现仍停在被拦截应用，补发第二次（同一 generation）。
        assertTrue(work.isCurrent(requestId, weibo))
        assertFalse(work.armDeferred(weibo, 1_500L))
        // T1200：预算耗尽，只结束本轮验证。
        work.finishVerificationCycle()
        assertNull(work.pendingTargetPackage())
        // 事件触发的 deferred 必须保留，否则 T1500 的复查被删掉（评审发现的缺陷）。
        assertEquals(weibo, work.deferredTargetPackage())
        assertEquals(1_500L, work.deferredDeadlineUptimeMillis())
        // T1200 之后的陈旧验证回调不能再补发。
        assertFalse(work.isCurrent(requestId, weibo))
        // T1500：复查触发新一轮，同目标不重复记账。
        assertEquals(weibo, work.consumeDeferred())
        assertNull(work.deferredTargetPackage())
        assertFalse(work.beginCycle(weibo, recordDetection = true))
        assertTrue(work.isCurrent(work.generation(), weibo))
    }

    @Test
    fun fullCancellationReasonsRemoveTheEventArmedDeferredCheck() {
        val reasons = listOf("own-foreground", "nonblocked-window", "config-inactive", "service-destroyed")
        for (reason in reasons) {
            val work = FocusBlockerPendingWorkState()
            work.beginCycle(weibo, recordDetection = true)
            work.armDeferred(weibo, 1_500L)
            // 已结束本轮验证时，own/允许应用等取消仍必须清掉保留下来的 deferred。
            work.finishVerificationCycle()
            assertEquals(weibo, work.deferredTargetPackage())
            work.cancelAll()
            assertNull("pending kept for $reason", work.pendingTargetPackage())
            assertNull("deferred kept for $reason", work.deferredTargetPackage())
            assertEquals(0L, work.deferredDeadlineUptimeMillis())
            assertNull(work.consumeDeferred())
            assertNull(work.lastRecordedDetectionPackage())
        }
    }

    @Test
    fun staleGenerationCannotRetryAfterTheCycleEndsOrReplacesTarget() {
        val work = FocusBlockerPendingWorkState()
        work.beginCycle(weibo, recordDetection = true)
        val firstGeneration = work.generation()
        assertTrue(work.isCurrent(firstGeneration, weibo))
        // 结束验证后旧 generation 不能补发。
        work.finishVerificationCycle()
        assertFalse(work.isCurrent(firstGeneration, weibo))
        // 新目标轮次里，旧轮次与不匹配目标都不算当前。
        work.beginCycle(alipay, recordDetection = true)
        assertFalse(work.isCurrent(firstGeneration, weibo))
        assertFalse(work.isCurrent(firstGeneration, alipay))
        assertTrue(work.isCurrent(work.generation(), alipay))
        assertFalse(work.isCurrent(work.generation(), weibo))
        assertFalse(work.isCurrent(work.generation(), null))
    }

    @Test
    fun repeatedDeadlineStaysStableAndChangedTargetKeepsTheSameGlobalDeadline() {
        val work = FocusBlockerPendingWorkState()
        work.beginCycle(weibo, recordDetection = true)
        // 首次排程需要调用方 post。
        assertTrue(work.armDeferred(weibo, 1_500L))
        // 同目标同截止时刻：不改期、无需再次 post（否则期限会被推后而饿死）。
        assertFalse(work.armDeferred(weibo, 1_500L))
        assertEquals(1_500L, work.deferredDeadlineUptimeMillis())
        // 冷却剩余期内出现另一个被拦截应用：只换目标，截止时刻保持 1500。
        assertFalse(work.armDeferred(alipay, 1_500L))
        assertEquals(alipay, work.deferredTargetPackage())
        assertEquals(1_500L, work.deferredDeadlineUptimeMillis())
        // 到点复查的是最新目标。
        assertEquals(alipay, work.consumeDeferred())
        assertNull(work.deferredTargetPackage())
        assertEquals(0L, work.deferredDeadlineUptimeMillis())
    }

    @Test
    fun newCycleClearsDeferredAndRecordsEachDetectionOnce() {
        val work = FocusBlockerPendingWorkState()
        assertTrue(work.beginCycle(weibo, recordDetection = true))
        // 同一轮内的重复检测与补发不再记账。
        assertFalse(work.beginCycle(weibo, recordDetection = true))
        assertTrue(work.armDeferred(weibo, 1_500L))
        // 新一轮完整替换会清空 deferred。
        assertTrue(work.beginCycle(alipay, recordDetection = true))
        assertNull(work.deferredTargetPackage())
        assertEquals(0L, work.deferredDeadlineUptimeMillis())
        // 完整取消后同一应用属于新的真实检测，需要再记一次。
        work.cancelAll()
        assertTrue(work.beginCycle(weibo, recordDetection = true))
        assertEquals(weibo, work.lastRecordedDetectionPackage())
    }

    @Test
    fun deferredFireForRetargetedPackageIsRecordedOnceInsteadOfSkipped() {
        val work = FocusBlockerPendingWorkState()
        work.beginCycle(weibo, recordDetection = true)
        work.armDeferred(weibo, 1_500L)
        work.finishVerificationCycle()
        // 冷却剩余期内当前前台换成另一个被拦截应用 → deferred 只换目标。
        work.armDeferred(alipay, 1_500L)
        assertEquals(alipay, work.consumeDeferred())
        // 复查触发的新目标必须记一次事件；随后同目标复查不重复记账。
        assertTrue(work.beginCycle(alipay, recordDetection = true))
        assertFalse(work.beginCycle(alipay, recordDetection = true))
    }
}
