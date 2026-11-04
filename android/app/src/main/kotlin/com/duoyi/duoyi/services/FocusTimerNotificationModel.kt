package com.duoyi.duoyi.services

/**
 * 专注计时通知的纯数据模型（无 Android 依赖，便于 JVM 单测）。
 *
 * Dart 只传“当前剩余/已累计毫秒 + 文案 + 主题色”，倒计时与秒级跳动全部由
 * 原生 chronometer / Handler 负责，不依赖 Dart 持续 timer。
 */
data class FocusTimerNotificationModel(
    val phase: String,
    val phaseLabel: String,
    val appTitle: String,
    val channelName: String,
    val taskLabel: String?,
    val noTaskLabel: String,
    val pausedLabel: String,
    val paused: Boolean,
    val isCountUp: Boolean,
    val remainingMillis: Long,
    val totalMillis: Long,
    val progressPermille: Int,
    val accentColorArgb: Int,
    val returnUri: String,
) {
    /** 通知标题：阶段名（主题/语言切换后由 Dart 重新下发）。 */
    val title: String
        get() = phaseLabel.ifEmpty { appTitle }

    /** 关联任务名，缺失时用“无关联任务”兜底。 */
    val taskText: String
        get() = taskLabel?.trim()?.takeIf { it.isNotEmpty() } ?: noTaskLabel

    /** 通知正文；暂停时追加暂停标记，不伪造剩余时间。 */
    val text: String
        get() = if (paused && pausedLabel.isNotEmpty()) "$taskText · $pausedLabel" else taskText

    /** 是否显示系统 chronometer（暂停时冻结为静态时间）。 */
    val usesChronometer: Boolean
        get() = !paused && (isCountUp || remainingMillis > 0)

    /** 倒计时从剩余时间往下走，正计时往上走。 */
    val chronometerCountDown: Boolean
        get() = !isCountUp

    /**
     * `SystemClock.elapsedRealtime` 形式的 chronometer 基准。
     *
     * 倒计时：now + 剩余；正计时：now - 已累计。now 取自调用时的单调时钟。
     */
    fun chronometerBaseElapsed(elapsedRealtimeNow: Long): Long =
        if (isCountUp) elapsedRealtimeNow - remainingMillis else elapsedRealtimeNow + remainingMillis

    /** Notification.when 接受日期时间戳，系统模板再将其换算为 chronometer 基准。 */
    fun notificationWhen(wallClockNow: Long): Long =
        if (isCountUp) wallClockNow - remainingMillis else wallClockNow + remainingMillis

    /** 根据单调时钟推进显示状态；暂停冻结，倒计时及进度在结束时钳制。 */
    fun afterElapsed(elapsedMillis: Long): FocusTimerNotificationModel {
        if (paused) return this
        val elapsed = elapsedMillis.coerceAtLeast(0L)
        val remaining = if (isCountUp) {
            if (remainingMillis > Long.MAX_VALUE - elapsed) Long.MAX_VALUE else remainingMillis + elapsed
        } else {
            remainingMillis - elapsed.coerceAtMost(remainingMillis)
        }
        val progress = if (showsProgress) {
            ((totalMillis - remaining.coerceAtMost(totalMillis)).toDouble() / totalMillis * 1000)
                .toInt().coerceIn(0, 1000)
        } else {
            0
        }
        return copy(remainingMillis = remaining, progressPermille = progress)
    }

    /** 是否显示确定性进度条（正计时/缺少总时长时不显示）。 */
    val showsProgress: Boolean
        get() = !isCountUp && totalMillis > 0

    /** 仅倒计时运行态需要到期调度；暂停/正计时返回 0 表示不调度。 */
    val expiryDelayMillis: Long
        get() = if (paused || isCountUp) 0L else remainingMillis.coerceAtLeast(0L)

    companion object {
        const val defaultReturnUri = "duoyi://tab/focus"

        /**
         * 解析 Dart payload；缺少必需字段时返回 null（调用方清理通知，不显示空壳）。
         */
        fun fromMap(raw: Map<*, *>?): FocusTimerNotificationModel? {
            if (raw == null) return null
            val phase = raw["phase"]?.toString()?.trim().orEmpty()
            val phaseLabel = raw["phaseLabel"]?.toString()?.trim().orEmpty()
            val appTitle = raw["appTitle"]?.toString()?.trim().orEmpty()
            if (phase.isEmpty() && phaseLabel.isEmpty() && appTitle.isEmpty()) return null
            val remaining = (raw["remainingMillis"] as? Number)?.toLong() ?: 0L
            val total = (raw["totalMillis"] as? Number)?.toLong() ?: 0L
            val progress = (raw["progressPermille"] as? Number)?.toInt() ?: 0
            val task = raw["taskLabel"]?.toString()?.trim().orEmpty()
            val returnUri = raw["returnUri"]?.toString()?.trim().orEmpty()
            return FocusTimerNotificationModel(
                phase = phase,
                phaseLabel = phaseLabel.ifEmpty { appTitle },
                appTitle = appTitle,
                channelName = raw["channelName"]?.toString()?.trim().orEmpty(),
                taskLabel = task.takeIf { it.isNotEmpty() },
                noTaskLabel = raw["noTaskLabel"]?.toString()?.trim().orEmpty(),
                pausedLabel = raw["pausedLabel"]?.toString()?.trim().orEmpty(),
                paused = raw["paused"] == true,
                isCountUp = raw["isCountUp"] == true,
                remainingMillis = remaining.coerceAtLeast(0L),
                totalMillis = total.coerceAtLeast(0L),
                progressPermille = progress.coerceIn(0, 1000),
                accentColorArgb = (raw["accentColorArgb"] as? Number)?.toInt() ?: 0,
                returnUri = returnUri.ifEmpty { defaultReturnUri },
            )
        }
    }
}
