package com.duoyi.duoyi.services

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 通知 payload 解析与 chronometer/到期语义：倒计时不为负、暂停冻结、
 * 正计时向上计时，文案缺失时用注入的兜底文案而不是硬编码。
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
        color: Int = 0xFFC85656.toInt(),
    ): Map<String, Any?> = mapOf(
        "phase" to phase,
        "phaseLabel" to phaseLabel,
        "appTitle" to "Duoyi",
        "channelName" to "Focus timer",
        "taskLabel" to task,
        "noTaskLabel" to noTask,
        "pausedLabel" to pausedLabel,
        "paused" to paused,
        "isCountUp" to isCountUp,
        "remainingMillis" to remaining,
        "totalMillis" to total,
        "progressPermille" to progress,
        "accentColorArgb" to color,
        "returnUri" to "duoyi://tab/focus",
    )

    @Test
    fun countdownUsesChronometerCountingDownFromRemaining() {
        val model = FocusTimerNotificationModel.fromMap(payload())!!
        assertTrue(model.usesChronometer)
        assertTrue(model.chronometerCountDown)
        assertTrue(model.showsProgress)
        assertEquals(600_100L, model.chronometerBaseElapsed(100L))
        assertEquals(600_000L, model.expiryDelayMillis)
    }

    @Test
    fun countUpCountsUpwardsAndHidesProgress() {
        val model = FocusTimerNotificationModel.fromMap(
            payload(isCountUp = true, remaining = 90_000L, total = 0L, progress = 0),
        )!!
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
        val model = FocusTimerNotificationModel.fromMap(payload(paused = true))!!
        assertFalse(model.usesChronometer)
        assertEquals(0L, model.expiryDelayMillis)
        assertTrue(model.text.contains("Paused"))
    }

    @Test
    fun negativeAndOversizedValuesAreClamped() {
        val model = FocusTimerNotificationModel.fromMap(
            payload(remaining = -5_000L, total = -1L, progress = 9_999),
        )!!
        assertEquals(0L, model.remainingMillis)
        assertEquals(0L, model.totalMillis)
        assertEquals(1000, model.progressPermille)
        assertFalse(model.usesChronometer)
        assertEquals(0L, model.expiryDelayMillis)
    }

    @Test
    fun missingTaskFallsBackToInjectedNoTaskLabel() {
        val model = FocusTimerNotificationModel.fromMap(payload(task = "  "))!!
        assertEquals("No linked task", model.taskText)
        assertEquals("No linked task", model.text)
    }

    @Test
    fun taskLabelIsUsedWhenPresent() {
        val model = FocusTimerNotificationModel.fromMap(payload(task = "Write report"))!!
        assertEquals("Write report", model.taskText)
        assertEquals("Write report", model.text)
    }

    @Test
    fun missingPhaseLabelFallsBackToAppTitle() {
        val model = FocusTimerNotificationModel.fromMap(payload(phaseLabel = "  "))!!
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
        val model = FocusTimerNotificationModel.fromMap(raw)!!
        assertEquals("duoyi://tab/focus", model.returnUri)
    }

    @Test
    fun notificationWhenUsesWallClockEpochInsteadOfElapsedRealtime() {
        val now = 1_794_000_000_000L
        val countdown = FocusTimerNotificationModel.fromMap(payload())!!
        assertEquals(now + 600_000L, countdown.notificationWhen(now))
        val countUp = FocusTimerNotificationModel.fromMap(
            payload(isCountUp = true, remaining = 90_000L, total = 0L),
        )!!
        assertEquals(now - 90_000L, countUp.notificationWhen(now))
    }

    @Test
    fun countUpStartsItsChronometerAtZero() {
        val model = FocusTimerNotificationModel.fromMap(
            payload(isCountUp = true, remaining = 0L, total = 0L),
        )!!
        assertTrue(model.usesChronometer)
        assertEquals(15_000L, model.afterElapsed(15_000L).remainingMillis)
        assertEquals(0L, model.afterElapsed(15_000L).expiryDelayMillis)
    }

    @Test
    fun backgroundProgressAdvancesWithoutExtendingCountdownDeadline() {
        val model = FocusTimerNotificationModel.fromMap(payload())!!
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
        val model = FocusTimerNotificationModel.fromMap(payload(paused = true))!!
        assertEquals(model, model.afterElapsed(300_000L))
    }
}
