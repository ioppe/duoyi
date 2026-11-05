package com.duoyi.duoyi.services

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 通知 payload 解析与显示语义：
 * - 可见正文以本地化“剩余/已计时 + 时间”开头，倒计时秒向上取整、正计时向下取整；
 * - canonical 锚点只用于折算“此刻”，秒级刷新/主题重推都不延长到期时刻；
 * - 暂停冻结在传入剩余值，正计时向上累计；
 * - 控制绑定校验 session/revision/state，并给出运行态/暂停态各自的按钮与 URI。
 */
class FocusTimerNotificationModelTest {

    private fun payload(
        phase: String = "focus",
        phaseLabel: String = "Focus",
        remaining: Long = 600_000L,
        total: Long = 1_500_000L,
        paused: Boolean = false,
        isCountUp: Boolean = false,
        progress: Int = 600,
        task: String? = null,
        noTask: String = "No linked task",
        pausedLabel: String = "Paused",
        remainingLabel: String = "Remaining",
        elapsedLabel: String = "Elapsed",
        startLabel: String = "Start",
        pauseActionLabel: String = "Pause",
        resetLabel: String = "Reset",
        color: Int = 0xFFC85656.toInt(),
        anchor: Long? = null,
        session: String? = null,
        revision: Int? = null,
        controlState: String? = null,
    ): Map<String, Any?> = buildMap {
        put("phase", phase)
        put("phaseLabel", phaseLabel)
        put("appTitle", "Duoyi")
        put("channelName", "Focus timer")
        put("taskLabel", task)
        put("noTaskLabel", noTask)
        put("pausedLabel", pausedLabel)
        put("remainingLabel", remainingLabel)
        put("elapsedLabel", elapsedLabel)
        put("startActionLabel", startLabel)
        put("pauseActionLabel", pauseActionLabel)
        put("resetActionLabel", resetLabel)
        put("paused", paused)
        put("isCountUp", isCountUp)
        put("remainingMillis", remaining)
        put("totalMillis", total)
        put("progressPermille", progress)
        put("accentColorArgb", color)
        put("returnUri", "duoyi://tab/focus")
        if (anchor != null) put("anchorMillis", anchor)
        if (session != null) put("controlSessionId", session)
        if (revision != null) put("controlRevision", revision)
        if (controlState != null) put("controlState", controlState)
    }

    private fun parseModel(raw: Map<String, Any?> = payload()) =
        FocusTimerNotificationModel.fromMap(raw)!!

    @Test
    fun countdownUsesChronometerCountingDownFromRemaining() {
        val model = parseModel()
        assertTrue(model.usesChronometer)
        assertTrue(model.chronometerCountDown)
        assertTrue(model.showsProgress)
        assertEquals(600_100L, model.chronometerBaseElapsed(100L))
        assertEquals(600_000L, model.expiryDelayMillis)
    }

    @Test
    fun countUpCountsUpwardsAndHidesProgress() {
        val model = parseModel(
            payload(isCountUp = true, remaining = 90_000L, total = 0L, progress = 0),
        )
        assertTrue(model.usesChronometer)
        assertFalse(model.chronometerCountDown)
        assertFalse(model.showsProgress)
        // 正计时基准在“现在”之前，chronometer 才会向上增长。
        assertEquals(-89_900L, model.chronometerBaseElapsed(100L))
        // 正计时不调度到期：由用户手动结束。
        assertEquals(0L, model.expiryDelayMillis)
    }

    @Test
    fun pausedFreezesTimeAndCancelsExpiry() {
        val model = parseModel(payload(paused = true))
        assertFalse(model.usesChronometer)
        assertEquals(0L, model.expiryDelayMillis)
        assertTrue(model.text.contains("Paused"))
    }

    @Test
    fun negativeAndOversizedValuesAreClamped() {
        val model = parseModel(payload(remaining = -5_000L, total = -1L, progress = 9_999))
        assertEquals(0L, model.remainingMillis)
        assertEquals(0L, model.totalMillis)
        assertEquals(1000, model.progressPermille)
        assertFalse(model.usesChronometer)
        assertEquals(0L, model.expiryDelayMillis)
    }

    @Test
    fun missingTaskFallsBackToInjectedNoTaskLabel() {
        val model = parseModel(payload(task = "  "))
        assertEquals("No linked task", model.taskText)
        assertEquals("No linked task", model.text)
    }

    @Test
    fun taskLabelIsUsedWhenPresent() {
        val model = parseModel(payload(task = "Write report"))
        assertEquals("Write report", model.taskText)
        assertEquals("Write report", model.text)
    }

    @Test
    fun missingPhaseLabelFallsBackToAppTitle() {
        val model = parseModel(payload(phaseLabel = "  "))
        assertEquals("Duoyi", model.title)
    }

    @Test
    fun emptyPayloadIsRejectedSoNoEmptyNotificationIsShown() {
        assertNull(FocusTimerNotificationModel.fromMap(null))
        assertNull(FocusTimerNotificationModel.fromMap(emptyMap<String, Any?>()))
    }

    @Test
    fun missingReturnUriFallsBackToFocusDeepLink() {
        val raw = payload().toMutableMap().apply { remove("returnUri") }
        assertEquals("duoyi://tab/focus", parseModel(raw).returnUri)
    }

    @Test
    fun notificationWhenUsesWallClockEpochInsteadOfElapsedRealtime() {
        val now = 1_794_000_000_000L
        val countdown = parseModel()
        assertEquals(now + 600_000L, countdown.notificationWhen(now))
        val countUp = parseModel(payload(isCountUp = true, remaining = 90_000L, total = 0L))
        assertEquals(now - 90_000L, countUp.notificationWhen(now))
    }

    @Test
    fun countUpStartsItsChronometerAtZero() {
        val model = parseModel(payload(isCountUp = true, remaining = 0L, total = 0L))
        assertTrue(model.usesChronometer)
        assertEquals(15_000L, model.afterElapsed(15_000L).remainingMillis)
        assertEquals(0L, model.afterElapsed(15_000L).expiryDelayMillis)
    }

    @Test
    fun backgroundProgressAdvancesWithoutExtendingCountdownDeadline() {
        val model = parseModel()
        val updated = model.afterElapsed(300_000L)
        assertEquals(300_000L, updated.remainingMillis)
        assertEquals(800, updated.progressPermille)
        val now = 1_794_000_000_000L
        assertEquals(model.notificationWhen(now), updated.notificationWhen(now + 300_000L))
        assertEquals(0L, model.afterElapsed(900_000L).remainingMillis)
        assertEquals(1000, model.afterElapsed(900_000L).progressPermille)
    }

    @Test
    fun pausedProgressAndTimeStayFrozen() {
        val model = parseModel(payload(paused = true))
        assertEquals(model, model.afterElapsed(300_000L))
    }

    @Test
    fun compactContentTextStartsWithLocalizedTime() {
        val model = parseModel()
        assertEquals("Remaining 10:00", model.contentText)
        // 展开后仍显示时间，并在第二行保留任务名或兜底。
        assertEquals("Remaining 10:00\nNo linked task", model.detailText)
        assertEquals(
            "Remaining 24:53",
            parseModel(payload(remaining = 1_493_000L)).contentText,
        )
    }

    @Test
    fun pausedContentTextShowsFrozenTimeAndPausedLabel() {
        val model = parseModel(payload(paused = true, remaining = 240_000L))
        assertEquals("Remaining 04:00 · Paused", model.contentText)
        assertEquals("Remaining 04:00 · Paused\nNo linked task", model.detailText)
    }

    @Test
    fun countUpContentTextUsesElapsedLabelInsteadOfFakeRemaining() {
        val model = parseModel(
            payload(isCountUp = true, remaining = 83_900L, total = 0L, progress = 0),
        )
        // 正计时向下取整：83.9s 仍显示 01:23，不会提前跳秒。
        assertEquals("Elapsed 01:23", model.contentText)
        assertEquals("Elapsed 01:23\nNo linked task", model.detailText)
    }

    @Test
    fun countdownRoundsSecondsUpSoOneThousandOneMillisIsNotTwoStepsAhead() {
        assertEquals("00:02", FocusTimerNotificationModel.formatDuration(1_001L, roundUp = true))
        assertEquals("00:01", FocusTimerNotificationModel.formatDuration(1_001L))
        assertEquals("00:00", FocusTimerNotificationModel.formatDuration(0L, roundUp = true))
        assertEquals(
            "1:00:00",
            FocusTimerNotificationModel.formatDuration(3_600_000L, roundUp = true),
        )
        assertEquals(
            "1:01:06",
            FocusTimerNotificationModel.formatDuration(3_665_001L, roundUp = true),
        )
        assertEquals(
            "1:01:05",
            FocusTimerNotificationModel.formatDuration(3_665_999L),
        )
    }

    @Test
    fun anchorRebasesToCanonicalEndSoRebroadcastDoesNotExtendDeadline() {
        val now = 1_794_000_000_000L
        val anchor = now + 600_000L
        val first = parseModel(payload(remaining = 600_000L, anchor = anchor))
        val rebroadcast = parseModel(payload(remaining = 600_000L, anchor = anchor))
        val laterNow = now + 120_000L

        // 首次同步按锚点折算，主题/语言重推也一样（不按“now + 旧剩余”重算）。
        assertEquals(600_000L, first.rebasedAt(now).remainingMillis)
        assertEquals(480_000L, rebroadcast.rebasedAt(laterNow).remainingMillis)
        assertEquals(
            first.expiryDeadlineMillis(now),
            rebroadcast.expiryDeadlineMillis(laterNow),
        )
        assertEquals(anchor, rebroadcast.expiryDeadlineMillis(laterNow))
        assertEquals(480_000L, rebroadcast.expiryDelayMillisAt(laterNow))
    }

    @Test
    fun anchoredProgressFollowsRebasedRemaining() {
        val now = 1_794_000_000_000L
        val anchor = now + 750_000L
        val model = parseModel(
            payload(remaining = 1_500_000L, total = 1_500_000L, anchor = anchor),
        )
        val rebased = model.rebasedAt(now + 250_000L)
        assertEquals(500_000L, rebased.remainingMillis)
        assertEquals(666, rebased.progressPermille)
        assertEquals(500_000L, rebased.expiryDelayMillisAt(now + 250_000L))
    }

    @Test
    fun countUpUsesNowMinusAnchor() {
        val now = 1_794_000_000_000L
        val model = parseModel(
            payload(isCountUp = true, remaining = 0L, total = 0L, anchor = now - 90_000L),
        )
        val rebased = model.rebasedAt(now)
        assertEquals("Elapsed 01:30", rebased.contentText)
        assertEquals(0L, rebased.expiryDeadlineMillis(now))
    }

    @Test
    fun anchoredCountdownInThePastClampsToZeroInsteadOfNegative() {
        val now = 1_794_000_000_000L
        val model = parseModel(payload(anchor = now - 5_000L))
        assertEquals(0L, model.rebasedAt(now).remainingMillis)
        assertEquals("Remaining 00:00", model.rebasedAt(now).contentText)
    }

    @Test
    fun pausedRebaseKeepsIncomingRemainingEvenWithAnchor() {
        val now = 1_794_000_000_000L
        val model = parseModel(
            payload(paused = true, remaining = 240_000L, anchor = now + 900_000L),
        )
        assertEquals(model, model.rebasedAt(now + 300_000L))
        assertEquals("Remaining 04:00 · Paused", model.contentText)
    }

    @Test
    fun legacyPayloadWithoutAnchorKeepsRelativeBehaviour() {
        val model = parseModel()
        assertEquals(0L, model.anchorMillis)
        assertEquals(model, model.rebasedAt(1_794_000_000_000L))
        assertEquals(600_000L, model.remainingMillis)
    }

    @Test
    fun runningBindingOffersPauseAndReset() {
        val model = parseModel(
            payload(session = "focus-1", revision = 3, controlState = "running"),
        )
        assertTrue(model.hasControlBinding)
        assertEquals(
            listOf(FocusTimerControlAction.pause, FocusTimerControlAction.reset),
            model.controlActions,
        )
        assertEquals(
            "duoyi://focus-timer/pause?session=focus-1&revision=3&state=running",
            model.controlUri(FocusTimerControlAction.pause),
        )
        assertEquals("Pause", model.actionLabel(FocusTimerControlAction.pause))
        assertEquals("Reset", model.actionLabel(FocusTimerControlAction.reset))
    }

    @Test
    fun pausedBindingOffersStartAndReset() {
        val model = parseModel(
            payload(
                paused = true,
                session = "focus-1",
                revision = 4,
                controlState = "paused",
            ),
        )
        assertEquals(
            listOf(FocusTimerControlAction.start, FocusTimerControlAction.reset),
            model.controlActions,
        )
        assertEquals(
            "duoyi://focus-timer/start?session=focus-1&revision=4&state=paused",
            model.controlUri(FocusTimerControlAction.start),
        )
        assertEquals("Start", model.actionLabel(FocusTimerControlAction.start))
    }

    @Test
    fun missingOrMalformedBindingShowsNoActions() {
        // 旧 payload：完全没有绑定字段。
        assertFalse(parseModel(payload()).hasControlBinding)
        assertTrue(parseModel(payload()).controlActions.isEmpty())
        // 空 session / 非法字符 / 超长。
        assertFalse(
            parseModel(payload(session = "", revision = 1, controlState = "running"))
                .hasControlBinding,
        )
        assertFalse(
            parseModel(payload(session = "focus 1", revision = 1, controlState = "running"))
                .hasControlBinding,
        )
        assertFalse(
            parseModel(payload(session = "a".repeat(129), revision = 1, controlState = "running"))
                .hasControlBinding,
        )
        // 负 revision / 非法 state。
        assertFalse(
            parseModel(payload(session = "focus-1", revision = -1, controlState = "running"))
                .hasControlBinding,
        )
        assertFalse(
            parseModel(payload(session = "focus-1", revision = 1, controlState = "idle"))
                .hasControlBinding,
        )
    }

    @Test
    fun bindingStateMustMatchPausedFlag() {
        // 运行态却声明 paused，或暂停态却声明 running：一律不生成按钮。
        val runningSaysPaused = parseModel(
            payload(session = "focus-1", revision = 1, controlState = "paused"),
        )
        assertFalse(runningSaysPaused.hasControlBinding)
        assertTrue(runningSaysPaused.controlActions.isEmpty())

        val pausedSaysRunning = parseModel(
            payload(paused = true, session = "focus-1", revision = 1, controlState = "running"),
        )
        assertFalse(pausedSaysRunning.hasControlBinding)
        assertTrue(pausedSaysRunning.controlActions.isEmpty())
    }

    @Test
    fun controlUriFallsBackToReturnUriWithoutBinding() {
        val model = parseModel(payload())
        assertEquals(
            "duoyi://tab/focus",
            model.controlUri(FocusTimerControlAction.pause),
        )
    }

    @Test
    fun controlActionWireNamesMatchDeepLinkSegments() {
        assertEquals("start", FocusTimerControlAction.fromWire("start")?.wireName)
        assertEquals("pause", FocusTimerControlAction.fromWire("pause")?.wireName)
        assertEquals("reset", FocusTimerControlAction.fromWire("reset")?.wireName)
        assertNull(FocusTimerControlAction.fromWire("stop"))
    }
}
