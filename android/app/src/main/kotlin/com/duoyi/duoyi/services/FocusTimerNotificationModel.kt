package com.duoyi.duoyi.services

import java.util.Locale

/**
 * 专注计时通知的纯数据模型（无 Android 依赖，便于 JVM 单测）。
 *
 * Dart 传入“canonical 锚点（真实 instant）+ 文案 + 控制绑定”，原生负责：
 * - 首次收到 sync 时按 [anchorMillis] 与 `System.currentTimeMillis()` 折算当前
 *   剩余/已计时，之后只用单调时钟推进（系统时间被调整也不会跳变）；
 * - 通知正文以时间开头（`剩余 24:53` / `已计时 01:23`），任务全名为展开详情；
 * - 运行态/暂停态各自的按钮由 [controlActions] 决定，URI 由 [controlUri] 生成。
 *
 * 锚点缺失（旧 payload）时退回相对的 [remainingMillis]，行为与旧版一致。
 */
data class FocusTimerNotificationModel(
    val phase: String,
    val phaseLabel: String,
    val appTitle: String,
    val channelName: String,
    val taskLabel: String?,
    val noTaskLabel: String,
    val pausedLabel: String,
    val remainingLabel: String,
    val elapsedLabel: String,
    val startActionLabel: String,
    val pauseActionLabel: String,
    val resetActionLabel: String,
    val paused: Boolean,
    val isCountUp: Boolean,
    val remainingMillis: Long,
    val totalMillis: Long,
    val progressPermille: Int,
    val accentColorArgb: Int,
    val returnUri: String,
    /** Dart 的 canonical 锚点（epoch ms）：倒计时=结束时刻，正计时=开始时刻；0=旧 payload。 */
    val anchorMillis: Long = 0L,
    /** 控制绑定：不透明 session id（空=旧 payload，通知不显示可操作按钮）。 */
    val controlSessionId: String = "",
    val controlRevision: Int = 0,
    /** `running` / `paused`；与 [paused] 不一致时绑定作废。 */
    val controlState: String = "",
) {
    /** 通知标题：阶段名（主题/语言切换后由 Dart 重新下发）。 */
    val title: String
        get() = phaseLabel.ifEmpty { appTitle }

    /** 关联任务名，缺失时用“无关联任务”兜底。 */
    val taskText: String
        get() = taskLabel?.trim()?.takeIf { it.isNotEmpty() } ?: noTaskLabel

    /** 展开详情（BigTextStyle）：任务全名；暂停时追加暂停标记。 */
    val text: String
        get() = if (paused && pausedLabel.isNotEmpty()) "$taskText · $pausedLabel" else taskText

    /** 展开后仍保留时间首行，第二行显示完整任务名。 */
    val detailText: String
        get() = "$contentText\n$taskText"

    /** 紧凑正文的时间部分：倒计时向上取整到秒，正计时向下取整。 */
    val timeText: String
        get() {
            val formatted = formatDuration(remainingMillis, roundUp = !isCountUp)
            val label = if (isCountUp) elapsedLabel else remainingLabel
            return if (label.isEmpty()) formatted else "$label $formatted"
        }

    /** 紧凑正文（MIUI 折叠态优先显示这一行）：必须以时间开头，暂停追加“已暂停”。 */
    val contentText: String
        get() = if (paused && pausedLabel.isNotEmpty()) "$timeText · $pausedLabel" else timeText

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

    /**
     * 首次接收 sync 时按锚点折算当前时刻的剩余/已计时。
     *
     * 旧 payload（无锚点）或暂停态保持 Dart 传入的相对值：暂停必须冻结在传入值。
     */
    fun rebasedAt(wallClockNow: Long): FocusTimerNotificationModel {
        if (paused || anchorMillis <= 0L) return this
        val remaining = if (isCountUp) {
            (wallClockNow - anchorMillis).coerceAtLeast(0L)
        } else {
            (anchorMillis - wallClockNow).coerceAtLeast(0L)
        }
        return copy(
            remainingMillis = remaining,
            progressPermille = progressFor(remaining),
        )
    }

    /** 根据单调时钟推进显示状态；暂停冻结，倒计时及进度在结束时钳制。 */
    fun afterElapsed(elapsedMillis: Long): FocusTimerNotificationModel {
        if (paused) return this
        val elapsed = elapsedMillis.coerceAtLeast(0L)
        val remaining = if (isCountUp) {
            if (remainingMillis > Long.MAX_VALUE - elapsed) Long.MAX_VALUE else remainingMillis + elapsed
        } else {
            remainingMillis - elapsed.coerceAtMost(remainingMillis)
        }
        return copy(
            remainingMillis = remaining,
            progressPermille = progressFor(remaining),
        )
    }

    private fun progressFor(remaining: Long): Int {
        if (!showsProgress) return 0
        val elapsed = (totalMillis - remaining.coerceAtMost(totalMillis)).coerceAtLeast(0L)
        return ((elapsed.toDouble() / totalMillis) * 1000).toInt().coerceIn(0, 1000)
    }

    /** 是否显示确定性进度条（正计时/缺少总时长时不显示）。 */
    val showsProgress: Boolean
        get() = !isCountUp && totalMillis > 0

    /** 旧口径的到期延迟（相对剩余值）；服务端改用锚点版本的 [expiryDelayMillisAt]。 */
    val expiryDelayMillis: Long
        get() = if (paused || isCountUp) 0L else remainingMillis.coerceAtLeast(0L)

    /**
     * 到期时刻（epoch ms）。有锚点时就是锚点本身，因此每次 notify / 主题重推
     * 都不会延长期限；旧 payload 才退回 now + 相对剩余。
     */
    fun expiryDeadlineMillis(wallClockNow: Long): Long = when {
        paused || isCountUp -> 0L
        anchorMillis > 0L -> anchorMillis
        else -> wallClockNow + remainingMillis.coerceAtLeast(0L)
    }

    /** 距到期还有多久；0 表示不调度（暂停/正计时）。 */
    fun expiryDelayMillisAt(wallClockNow: Long): Long {
        val deadline = expiryDeadlineMillis(wallClockNow)
        return if (deadline <= 0L) 0L else (deadline - wallClockNow).coerceAtLeast(0L)
    }

    /** 绑定是否可用于生成可操作按钮：session 合法、revision 非负、状态合法且与 [paused] 一致。 */
    val hasControlBinding: Boolean
        get() = controlSessionPattern.matches(controlSessionId) &&
            controlRevision >= 0 &&
            controlState in controlStates &&
            (controlState == "paused") == paused

    /** 运行态=暂停/重置，暂停态=开始/重置；无有效绑定时不生成按钮。 */
    val controlActions: List<FocusTimerControlAction>
        get() = when {
            !hasControlBinding -> emptyList()
            paused -> listOf(FocusTimerControlAction.start, FocusTimerControlAction.reset)
            else -> listOf(FocusTimerControlAction.pause, FocusTimerControlAction.reset)
        }

    /** 按钮深链：`duoyi://focus-timer/<action>?session=&revision=&state=`。 */
    fun controlUri(action: FocusTimerControlAction): String {
        if (!hasControlBinding) return returnUri
        return "$controlScheme://$controlHost/${action.wireName}" +
            "?session=$controlSessionId&revision=$controlRevision&state=$controlState"
    }

    /** 按钮文案由 Dart 注入；缺失时返回空串，调用方不添加该按钮。 */
    fun actionLabel(action: FocusTimerControlAction): String = when (action) {
        FocusTimerControlAction.start -> startActionLabel
        FocusTimerControlAction.pause -> pauseActionLabel
        FocusTimerControlAction.reset -> resetActionLabel
    }

    companion object {
        const val defaultReturnUri = "duoyi://tab/focus"

        const val controlScheme = "duoyi"
        const val controlHost = "focus-timer"
        val controlStates = setOf("running", "paused")

        /** session 必须是 URI 安全的短标识（Dart 侧 `focus-<micros>`）。 */
        val controlSessionPattern = Regex("^[A-Za-z0-9._~-]{1,128}$")

        /**
         * 时长文案：倒计时向上取整（1001ms 仍显示 00:02，不会提前跳两秒），
         * 正计时向下取整；小时以上用 `h:mm:ss`。
         */
        fun formatDuration(millis: Long, roundUp: Boolean = false): String {
            val safe = millis.coerceAtLeast(0L)
            val seconds = if (roundUp) {
                if (safe > Long.MAX_VALUE - 999L) Long.MAX_VALUE / 1000L else (safe + 999L) / 1000L
            } else {
                safe / 1000L
            }
            val hours = seconds / 3600L
            val minutes = (seconds % 3600L) / 60L
            val secs = seconds % 60L
            return if (hours > 0) {
                java.lang.String.format(Locale.US, "%d:%02d:%02d", hours, minutes, secs)
            } else {
                java.lang.String.format(Locale.US, "%02d:%02d", minutes, secs)
            }
        }

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
            val anchor = (raw["anchorMillis"] as? Number)?.toLong() ?: 0L
            return FocusTimerNotificationModel(
                phase = phase,
                phaseLabel = phaseLabel.ifEmpty { appTitle },
                appTitle = appTitle,
                channelName = raw["channelName"]?.toString()?.trim().orEmpty(),
                taskLabel = task.takeIf { it.isNotEmpty() },
                noTaskLabel = raw["noTaskLabel"]?.toString()?.trim().orEmpty(),
                pausedLabel = raw["pausedLabel"]?.toString()?.trim().orEmpty(),
                remainingLabel = raw["remainingLabel"]?.toString()?.trim().orEmpty(),
                elapsedLabel = raw["elapsedLabel"]?.toString()?.trim().orEmpty(),
                startActionLabel = raw["startActionLabel"]?.toString()?.trim().orEmpty(),
                pauseActionLabel = raw["pauseActionLabel"]?.toString()?.trim().orEmpty(),
                resetActionLabel = raw["resetActionLabel"]?.toString()?.trim().orEmpty(),
                paused = raw["paused"] == true,
                isCountUp = raw["isCountUp"] == true,
                remainingMillis = remaining.coerceAtLeast(0L),
                totalMillis = total.coerceAtLeast(0L),
                progressPermille = progress.coerceIn(0, 1000),
                accentColorArgb = (raw["accentColorArgb"] as? Number)?.toInt() ?: 0,
                returnUri = returnUri.ifEmpty { defaultReturnUri },
                anchorMillis = anchor.coerceAtLeast(0L),
                controlSessionId = raw["controlSessionId"]?.toString()?.trim().orEmpty(),
                controlRevision = (raw["controlRevision"] as? Number)?.toInt() ?: 0,
                controlState = raw["controlState"]?.toString()?.trim()?.lowercase(Locale.US).orEmpty(),
            )
        }
    }
}

/** 通知按钮对应的动作（wireName 即深链路径段）。 */
enum class FocusTimerControlAction(val wireName: String) {
    start("start"),
    pause("pause"),
    reset("reset");

    companion object {
        fun fromWire(raw: String?): FocusTimerControlAction? =
            values().firstOrNull { it.wireName == raw }
    }
}
