package com.duoyi.duoyi

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.SystemClock
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.max

/**
 * "专注" 小组件。类名保留用于兼容已安装的旧小组件。
 *
 * 视觉（Apple 风）：顶栏 18dp logo + 13sp 模块名 + MM/dd（secondary）。
 * body 统计保持「左大右小」：左侧 32sp 主数（旧 widget_focus_streak_count）配 11sp
 * 说明，右侧两行 16sp 计数/分钟配 11sp 单位。running 时左侧主数换成 RemoteViews
 * Chronometer 实时走表（原 TextView 隐藏但 ID 保留）；idle 显示下一轮分钟，
 * paused 显示停住的剩余时间 + 「已暂停」说明。
 *
 * 交互：三枚并排按钮「开始 / 暂停 / 停止」走 HomeWidgetBackgroundIntent 广播直接
 * 驱动后台计时，不再跳转 App。旧 widget_focus_quick_start 保留 ID 且 GONE，只作旧
 * 实例兼容。原生侧只读 prefs 快照并透传 session / revision / state / scope 绑定，
 * owner、会话与修订号的权威判定在 Dart 后台完成；绑定缺失时三按钮禁用。
 */
open class DuoyiFocusHabitWidgetProvider : DuoyiStyledWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            requestUpdate(context)
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val prefs = HomeWidgetPlugin.getData(context)
        appWidgetIds.forEach { DuoyiWidgetDisplayMode.clearForWidget(prefs, it) }
        super.onDeleted(context, appWidgetIds)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs: SharedPreferences = HomeWidgetPlugin.getData(context)

        appWidgetIds.forEach { id ->
            DuoyiWidgetProviderRegistry.styleForProvider(this::class.java.name)?.let { style ->
                DuoyiWidgetDisplayMode.saveForWidgetIfMissing(prefs, id, style)
            }
            // 同时产出横屏 / 竖屏两套 RemoteViews（宿主旋转后直接复用对应方向）。
            // lambda 的 context 有意遮蔽外层，使 resolve / 主题 / 底栏 / PendingIntent
            // 全部基于同一方向配置生成；以下渲染逻辑原样保留。
            val views = DuoyiWidgetLayout.forOrientations(context) { context ->
            val views = RemoteViews(context.packageName, R.layout.duoyi_focus_habit_widget)
            val profile = DuoyiWidgetLayout.resolve(context, appWidgetManager, id)
            DuoyiWidgetTheme.applyContainer(
                context = context,
                views = views,
                prefs = prefs,
                rootId = R.id.widget_focus_habit_root,
                navId = R.id.widget_focus_habit_bottom_nav,
                appWidgetId = id,
                appleStyle = true,
            )
            DuoyiWidgetTheme.applyTextColors(
                views,
                prefs,
                primaryIds = intArrayOf(
                    R.id.widget_focus_quick_start,
                    R.id.widget_focus_start_button,
                    R.id.widget_focus_pause_button,
                    R.id.widget_focus_stop_button,
                ),
                bodyIds = intArrayOf(
                    R.id.widget_module_title,
                    R.id.widget_focus_streak_count,
                    R.id.widget_focus_chronometer,
                    R.id.widget_focus_count,
                    R.id.widget_focus_habit_progress,
                ),
                mutedIds = intArrayOf(
                    R.id.widget_focus_habit_date,
                    R.id.widget_focus_timer_caption,
                    R.id.widget_focus_count_caption,
                    R.id.widget_focus_minutes_caption,
                    R.id.widget_focus_summary,
                    R.id.widget_focus_habit_summary,
                    R.id.widget_focus_streak_summary,
                ),
                appleStyle = true,
            )
            // 淡 accent 背景必须交给主题设置：RemoteViews 只有带 background 的视图
            // 才会接收点击，三枚计时按钮因此也依赖这里的 surface。
            DuoyiWidgetTheme.applyButtonSurfaces(
                views,
                prefs,
                primaryIds = intArrayOf(
                    R.id.widget_focus_quick_start,
                    R.id.widget_focus_start_button,
                    R.id.widget_focus_pause_button,
                    R.id.widget_focus_stop_button,
                ),
                appleStyle = true,
            )
            val today = SimpleDateFormat("MM/dd", Locale.getDefault()).format(Date())

            views.setTextViewText(
                R.id.widget_module_title,
                prefs.getString("nav_focus", "专注") ?: "专注"
            )
            views.setTextViewText(R.id.widget_focus_habit_date, today)
            val pomodoroToday = prefs.getInt("pomodoro_today", 0)
            val focusMinutesToday = prefs.getInt("focus_minutes_today", pomodoroToday * 25)
            val nextFocusLabel = prefs.getString("next_focus_label", "25 分钟专注") ?: "25 分钟专注"
            // 权威状态来自 Dart 写入的 focus_timer_state；旧实例沿用 focus_timer_running。
            val timerState = resolveTimerState(prefs)
            val timerRunning = timerState == FocusTimerState.RUNNING
            // 控制绑定：id / scope 为空即视为未绑定，按钮全部禁用，不做 App 兜底跳转。
            val controlSessionId = prefs.getString("focus_timer_session_id", "")?.trim().orEmpty()
            val controlScope = prefs.getString("focus_control_scope", "")?.trim().orEmpty()
            val timerRevision = getIntCompat(prefs, "focus_timer_revision")
            val countUp = getBooleanCompat(prefs, "focus_timer_count_up")
            val timerRemainingSeconds = currentTimerRemainingSeconds(prefs, timerRunning)
            val timerLabel = prefs.getString("focus_timer_label", "专注倒计时") ?: "专注倒计时"
            val pausedLabel = prefs.getString("widget_focus_paused_label", "已暂停") ?: "已暂停"
            val timerText = when (timerState) {
                FocusTimerState.IDLE -> extractFirstNumber(nextFocusLabel)
                else -> formatTimer(timerRemainingSeconds)
            }
            // 主数下方说明：运行中「剩余时间」，暂停「已暂停」，否则「下轮专注（分钟）」。
            val timerCaption = if (timerRunning) {
                prefs.getString("widget_focus_remaining_label", "剩余时间") ?: "剩余时间"
            } else if (timerState == FocusTimerState.PAUSED) {
                pausedLabel
            } else {
                prefs.getString("widget_focus_next_label", "下轮专注（分钟）")
                    ?: "下轮专注（分钟）"
            }
            val timerSummary = when (timerState) {
                FocusTimerState.IDLE -> "下一轮：$nextFocusLabel"
                FocusTimerState.PAUSED -> "$pausedLabel：${formatTimer(timerRemainingSeconds)}"
                FocusTimerState.RUNNING -> "$timerLabel：${formatTimer(timerRemainingSeconds)}"
            }
            val timerHint = when (timerState) {
                FocusTimerState.RUNNING -> {
                    val endsAtMillis = getLongCompat(prefs, "focus_timer_ends_at_millis")
                    if (endsAtMillis > 0L) {
                        "预计 ${SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(endsAtMillis))} 结束"
                    } else {
                        "正在专注中"
                    }
                }
                FocusTimerState.PAUSED -> pausedLabel
                FocusTimerState.IDLE -> "结束后提醒休息"
            }
            // 旧 CTA 只保留 ID 兼容（GONE），入口已由三枚计时按钮接管。
            val quickStartText = if (timerRunning) {
                prefs.getString("widget_focus_running_label", "查看倒计时") ?: "查看倒计时"
            } else {
                prefs.getString("widget_focus_open_label", "前往专注") ?: "前往专注"
            }
            views.setTextViewText(
                R.id.widget_focus_count,
                pomodoroToday.toString()
            )
            views.setTextViewText(
                R.id.widget_focus_count_caption,
                prefs.getString("widget_focus_count_label", "次数") ?: "次数"
            )
            views.setTextViewText(
                R.id.widget_focus_habit_progress,
                focusMinutesToday.toString()
            )
            views.setTextViewText(
                R.id.widget_focus_minutes_caption,
                prefs.getString("widget_focus_minutes_label", "分钟") ?: "分钟"
            )
            views.setTextViewText(
                R.id.widget_focus_streak_count,
                timerText
            )
            views.setTextViewText(
                R.id.widget_focus_timer_caption,
                timerCaption
            )
            views.setTextViewText(
                R.id.widget_focus_summary,
                prefs.getString("focus_summary", "今日还未专注") ?: "今日还未专注"
            )
            views.setTextViewText(
                R.id.widget_focus_habit_summary,
                timerSummary
            )
            views.setTextViewText(
                R.id.widget_focus_streak_summary,
                timerHint
            )
            views.setTextViewText(
                R.id.widget_focus_quick_start,
                quickStartText
            )
            views.setViewVisibility(R.id.widget_focus_quick_start, View.GONE)
            // Chronometer 与旧主数同槽位：running 时后者 GONE，其余状态反之。
            applyTimerDisplay(views, prefs, timerState, timerRemainingSeconds, countUp)
            // 容量优先：先按实例真实高度决定哪些块完整放得下，再叠加密度上限。
            applyCapacity(views, prefs, id, profile, timerText, timerRunning)
            // 计时控制绑定：开始 / 暂停 / 停止均为后台广播，不拉起 App。
            applyControls(
                views = views,
                context = context,
                prefs = prefs,
                timerState = timerState,
                sessionId = controlSessionId,
                scope = controlScope,
                revision = timerRevision,
            )

            val tabTodo = prefs.getString("nav_todo", "待办") ?: "待办"
            val tabHabit = prefs.getString("nav_habit", "习惯") ?: "习惯"
            val tabCalendar = prefs.getString("nav_calendar", "日历") ?: "日历"
            val tabFocus = prefs.getString("nav_focus", "专注") ?: "专注"
            views.setTextViewText(R.id.widget_focus_nav_todo, tabTodo)
            views.setTextViewText(R.id.widget_focus_nav_habit, tabHabit)
            views.setTextViewText(R.id.widget_focus_nav_calendar, tabCalendar)
            views.setTextViewText(R.id.widget_focus_nav_focus, tabFocus)

            val navTarget = DuoyiWidgetNavigation.targetFor(context, id)
            // 顶部区域（品牌 logo / 模块名 / 日期 / 统计 / 倒计时说明）进入 App 专注页。
            // 三枚计时按钮不在此列：它们只做后台动作，绝不回退到通用分页。
            val openFocusPage = appPageIntent(context, Uri.parse("duoyi://tab/focus"))
            intArrayOf(
                R.id.widget_focus_habit_root,
                R.id.widget_brand_logo,
                R.id.widget_focus_habit_title,
                R.id.widget_module_title,
                R.id.widget_focus_habit_date,
                R.id.widget_focus_count,
                R.id.widget_focus_habit_progress,
                R.id.widget_focus_streak_count,
                R.id.widget_focus_timer_caption,
                R.id.widget_focus_summary,
                R.id.widget_focus_habit_summary,
                R.id.widget_focus_streak_summary,
                R.id.widget_focus_quick_start,
                R.id.widget_focus_count_caption,
                R.id.widget_focus_minutes_caption,
            ).forEach { views.setOnClickPendingIntent(it, openFocusPage) }
            // 底部四项直接切换小组件内容。
            DuoyiWidgetNavigation.bindBottomTabs(
                context = context,
                views = views,
                prefs = prefs,
                target = navTarget,
                appWidgetId = id,
                navId = R.id.widget_focus_habit_bottom_nav,
                // 核心四页底栏必须始终可见（compact 首次进入也不例外）；
                // 实例内切页的本地行为仍由 bindBottomTabs/navVisibility 保留。
                defaultNavVisibility = View.VISIBLE,
                tabViewIds = mapOf(
                    DuoyiWidgetNavigation.TAB_TODO to R.id.widget_focus_nav_todo,
                    DuoyiWidgetNavigation.TAB_HABIT to R.id.widget_focus_nav_habit,
                    DuoyiWidgetNavigation.TAB_CALENDAR to R.id.widget_focus_nav_calendar,
                    DuoyiWidgetNavigation.TAB_FOCUS to R.id.widget_focus_nav_focus,
                ),
            )
            DuoyiWidgetTheme.applySegmentedNavigation(
                context = context,
                views = views,
                prefs = prefs,
                tabViewIds = intArrayOf(
                    R.id.widget_focus_nav_todo,
                    R.id.widget_focus_nav_habit,
                    R.id.widget_focus_nav_calendar,
                    R.id.widget_focus_nav_focus,
                ),
                selectedId = R.id.widget_focus_nav_focus,
                profile = profile,
            )

                views
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    /**
     * 运行中把左侧主数交给 RemoteViews Chronometer 实时走表，其余状态明确停表。
     *
     * 倒计时：base = elapsedRealtime + max(0, ends_at - now)，缺失 ends_at 时用
     * remaining_seconds 兜底；倒计时/正计时两个方向都由原生 Chronometer 驱动，
     * 这里不写业务 JSON、也不维护第二套计时状态机。预算上限避免 base 溢出。
     */
    private fun applyTimerDisplay(
        views: RemoteViews,
        prefs: SharedPreferences,
        timerState: FocusTimerState,
        remainingSeconds: Int,
        countUp: Boolean,
    ) {
        val chronometerId = R.id.widget_focus_chronometer
        if (timerState != FocusTimerState.RUNNING) {
            // 暂停/空闲必须显式停表，避免复用实例里残留上一个会话的走表。
            views.setChronometer(chronometerId, 0L, null, false)
            views.setViewVisibility(chronometerId, View.GONE)
            views.setViewVisibility(R.id.widget_focus_streak_count, View.VISIBLE)
            return
        }
        val elapsedRealtime = SystemClock.elapsedRealtime()
        val base = if (countUp) {
            // 正计时协议中 remaining_seconds 就是已累计秒数（total_seconds 为 0）。
            val elapsedSeconds = remainingSeconds.coerceAtLeast(0).toLong()
            elapsedRealtime - elapsedSeconds * 1000L
        } else {
            val endsAtMillis = getLongCompat(prefs, "focus_timer_ends_at_millis")
            val remainingMillis = if (endsAtMillis > 0L) {
                (endsAtMillis - System.currentTimeMillis()).coerceAtLeast(0L)
            } else {
                remainingSeconds.coerceAtLeast(0).toLong() * 1000L
            }
            elapsedRealtime + remainingMillis.coerceAtMost(MAX_CHRONOMETER_MILLIS)
        }
        views.setChronometer(chronometerId, base, null, true)
        views.setChronometerCountDown(chronometerId, !countUp)
        views.setViewVisibility(chronometerId, View.VISIBLE)
        views.setViewVisibility(R.id.widget_focus_streak_count, View.GONE)
    }

    /**
     * 三枚计时按钮：开始仅 idle/paused、暂停仅 running、停止仅 running/paused，
     * 且 session / scope 绑定齐全才可用。禁用时停机位（setEnabled + alpha），
     * 即使宿主仍派发点击，带完整绑定的广播也会被服务端按状态严格拒绝。
     */
    private fun applyControls(
        views: RemoteViews,
        context: Context,
        prefs: SharedPreferences,
        timerState: FocusTimerState,
        sessionId: String,
        scope: String,
        revision: Int,
    ) {
        val bound = sessionId.isNotEmpty() && scope.isNotEmpty()
        val startLabel = if (timerState == FocusTimerState.PAUSED) {
            prefs.getString("widget_focus_resume_label", "继续") ?: "继续"
        } else {
            prefs.getString("widget_focus_start_label", "开始") ?: "开始"
        }
        bindControlButton(
            views = views,
            context = context,
            viewId = R.id.widget_focus_start_button,
            action = ACTION_START,
            label = startLabel,
            enabled = bound && timerState != FocusTimerState.RUNNING,
            timerState = timerState,
            sessionId = sessionId,
            revision = revision,
            scope = scope,
        )
        bindControlButton(
            views = views,
            context = context,
            viewId = R.id.widget_focus_pause_button,
            action = ACTION_PAUSE,
            label = prefs.getString("widget_focus_pause_label", "暂停") ?: "暂停",
            enabled = bound && timerState == FocusTimerState.RUNNING,
            timerState = timerState,
            sessionId = sessionId,
            revision = revision,
            scope = scope,
        )
        bindControlButton(
            views = views,
            context = context,
            viewId = R.id.widget_focus_stop_button,
            action = ACTION_STOP,
            label = prefs.getString("widget_focus_stop_label", "停止") ?: "停止",
            enabled = bound && timerState != FocusTimerState.IDLE,
            timerState = timerState,
            sessionId = sessionId,
            revision = revision,
            scope = scope,
        )
    }

    private fun bindControlButton(
        views: RemoteViews,
        context: Context,
        viewId: Int,
        action: String,
        label: String,
        enabled: Boolean,
        timerState: FocusTimerState,
        sessionId: String,
        revision: Int,
        scope: String,
    ) {
        views.setTextViewText(viewId, label)
        views.setBoolean(viewId, "setEnabled", enabled)
        views.setFloat(viewId, "setAlpha", if (enabled) CONTROL_ENABLED_ALPHA else CONTROL_DISABLED_ALPHA)
        views.setContentDescription(viewId, if (enabled) label else "$label，当前不可用")
        // 始终带上 session / revision / state / scope 完整绑定：绑定为空时服务端拒绝，
        // 原生侧不猜测 owner、不伪造 revision，也不跳 App 伪装成"直接开始"。
        val uri = controlUri(
            action = action,
            sessionId = sessionId,
            revision = revision,
            timerState = timerState,
            scope = scope,
        )
        views.setOnClickPendingIntent(viewId, HomeWidgetBackgroundIntent.getBroadcast(context, uri))
    }

    private fun controlUri(
        action: String,
        sessionId: String,
        revision: Int,
        timerState: FocusTimerState,
        scope: String,
    ): Uri = Uri.Builder()
        .scheme(URI_SCHEME)
        .authority(URI_AUTHORITY)
        .appendPath(action)
        .appendQueryParameter("session", sessionId)
        .appendQueryParameter("revision", revision.toString())
        .appendQueryParameter("state", timerState.wire)
        .appendQueryParameter("scope", scope)
        .build()

    /**
     * 按真实高度预算决定专注页显示哪些块，取代原来只看展示模式的可见性。
     *
     * 优先级：整块 stats（左大 timer + 说明、右两行计数/分钟 + 单位必须一起放下）
     * -> 整块三按钮 controls -> 现有摘要行。整块放不下就 GONE，把高度让给顶栏和
     * 底栏；底栏由 bindBottomTabs 以 View.VISIBLE 保持。每档候选都校验宽度，
     * 不允许"最后一个候选无条件接受"而把 h:mm:ss 裁成半行。
     */
    private fun applyCapacity(
        views: RemoteViews,
        prefs: SharedPreferences,
        appWidgetId: Int,
        profile: DuoyiWidgetProfile,
        timerText: String,
        timerRunning: Boolean,
    ) {
        val padded = profile.withPadding(profile.applePaddingDp)
        val paddingPx = padded.px(padded.paddingDp)
        views.setViewPadding(
            R.id.widget_focus_content,
            paddingPx,
            paddingPx,
            paddingPx,
            paddingPx,
        )
        val budget = padded.budget(
            padded.headerDp(DuoyiWidgetLayout.MODULE_TITLE_SP) +
                STATS_MARGIN_DP +
                DuoyiWidgetLayout.NAV_MARGIN_DP +
                padded.navDp(padded.navLabelSp)
        )
        // 左侧主数可用宽度 = 内容宽度 - 右侧两行最小占位；长 HH:MM:SS 自动降档不裁字。
        val leftWidthDp = (padded.contentWidthDp - MINI_STATS_WIDTH_DP).coerceAtLeast(0f)
        // 运行中主数是 Chronometer，按最长 h:mm:ss 占位校验宽度。
        val measuredTimerText = if (timerRunning) CHRONOMETER_WIDEST_TEXT else timerText
        // 整块统计预算 = max(左 32sp 主数 + 11sp 说明, 右两行 16sp 值 + 8dp 间距)。
        var statsShown = false
        var timerSp = TIMER_SP
        var valueSp = VALUE_SP
        for (index in TIMER_SP_CANDIDATES.indices) {
            val candidateTimer = TIMER_SP_CANDIDATES[index]
            val candidateValue = VALUE_SP_CANDIDATES[index]
            val leftDp = padded.lineDp(candidateTimer) +
                TIMER_CAPTION_GAP_DP +
                padded.lineDp(CAPTION_SP)
            val rightDp = 2f * padded.lineDp(candidateValue) + MINI_ROW_GAP_DP
            val fitsWidth =
                padded.textWidthDp(measuredTimerText, candidateTimer) * 1.1f <= leftWidthDp
            // 每一档都校验宽高；极端小尺寸整块收起，不让长倒计时显示成半截。
            if (fitsWidth && budget.reserve(max(leftDp, rightDp))) {
                statsShown = true
                timerSp = candidateTimer
                valueSp = candidateValue
                break
            }
        }
        views.setViewVisibility(
            R.id.widget_focus_stats,
            if (statsShown) View.VISIBLE else View.GONE
        )
        if (statsShown) {
            intArrayOf(
                R.id.widget_focus_streak_count,
                R.id.widget_focus_chronometer,
            ).forEach {
                views.setTextViewTextSize(it, TypedValue.COMPLEX_UNIT_SP, timerSp)
            }
            intArrayOf(
                R.id.widget_focus_count,
                R.id.widget_focus_habit_progress,
            ).forEach {
                views.setTextViewTextSize(it, TypedValue.COMPLEX_UNIT_SP, valueSp)
            }
        }
        val dense = !DuoyiWidgetDisplayMode.isCompact(prefs, appWidgetId)
        val detailed = DuoyiWidgetDisplayMode.isDetailed(prefs, appWidgetId)
        // 三按钮块预算替代旧单行 CTA：XML 的 margin + minHeight + 上下 padding 精确计入。
        val controlsDp = CONTROL_MARGIN_DP + max(
            CONTROL_MIN_HEIGHT_DP,
            padded.lineDp(CONTROL_SP) + 2f * CONTROL_VERTICAL_PADDING_DP,
        )
        val showControls = statsShown && budget.reserve(controlsDp)
        views.setViewVisibility(
            R.id.widget_focus_controls,
            if (showControls) View.VISIBLE else View.GONE
        )
        val summary1 = statsShown && budget.reserve(SUMMARY_MARGIN_DP + padded.lineDp(SUMMARY_SP))
        val summary2 = summary1 && detailed &&
            budget.reserve(2f + padded.lineDp(SUMMARY_SP))
        val summary3 = summary2 && dense && detailed &&
            budget.reserve(2f + padded.lineDp(SUMMARY_SP))
        views.setViewVisibility(
            R.id.widget_focus_summary,
            if (summary1) View.VISIBLE else View.GONE
        )
        views.setViewVisibility(
            R.id.widget_focus_habit_summary,
            if (summary2) View.VISIBLE else View.GONE
        )
        views.setViewVisibility(
            R.id.widget_focus_streak_summary,
            if (summary3) View.VISIBLE else View.GONE
        )
    }

    /**
     * 状态快照解析：只认 Dart 写入的 idle / running / paused。缺失或非法时按旧
     * focus_timer_running 回退，绝不自行发明 paused。
     */
    private fun resolveTimerState(prefs: SharedPreferences): FocusTimerState {
        val raw = when (val value = prefs.all["focus_timer_state"]) {
            is String -> value.trim().lowercase(Locale.ROOT)
            else -> ""
        }
        FocusTimerState.byWire(raw)?.let { return it }
        return if (getBooleanCompat(prefs, "focus_timer_running")) {
            FocusTimerState.RUNNING
        } else {
            FocusTimerState.IDLE
        }
    }

    private fun extractFirstNumber(text: String): String {
        return Regex("\\d+").find(text)?.value ?: "0"
    }

    private fun currentTimerRemainingSeconds(prefs: SharedPreferences, running: Boolean): Int {
        val storedRemaining = getIntCompat(prefs, "focus_timer_remaining_seconds")
        if (!running) return storedRemaining
        val endsAtMillis = getLongCompat(prefs, "focus_timer_ends_at_millis")
        if (endsAtMillis <= 0L) return storedRemaining
        val secondsUntilEnd = ((endsAtMillis - System.currentTimeMillis()) / 1000L).coerceAtLeast(0L)
        return secondsUntilEnd.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    }

    private fun formatTimer(totalSeconds: Int): String {
        val safeSeconds = totalSeconds.coerceAtLeast(0)
        val hours = safeSeconds / 3600
        val minutes = (safeSeconds % 3600) / 60
        val seconds = safeSeconds % 60
        return if (hours > 0) {
            "%d:%02d:%02d".format(Locale.getDefault(), hours, minutes, seconds)
        } else {
            "%02d:%02d".format(Locale.getDefault(), minutes, seconds)
        }
    }

    private fun getBooleanCompat(prefs: SharedPreferences, key: String): Boolean {
        return when (val value = prefs.all[key]) {
            is Boolean -> value
            is String -> value == "true"
            is Number -> value.toInt() != 0
            else -> false
        }
    }

    private fun getIntCompat(prefs: SharedPreferences, key: String): Int {
        return when (val value = prefs.all[key]) {
            is Int -> value
            is Long -> value.coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()
            is String -> value.toIntOrNull() ?: 0
            else -> 0
        }
    }

    private fun getLongCompat(prefs: SharedPreferences, key: String): Long {
        return when (val value = prefs.all[key]) {
            is Long -> value
            is Int -> value.toLong()
            is String -> value.toLongOrNull() ?: 0L
            else -> 0L
        }
    }

    private fun appPageIntent(context: Context, uri: Uri): PendingIntent {
        return HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri)
    }

    companion object {

        // 与 duoyi_focus_habit_widget.xml 一致的几何参数。
        private const val STATS_MARGIN_DP = 6f
        /** 三按钮块上边距，与 XML layout_marginTop 一致。 */
        private const val CONTROL_MARGIN_DP = 6f
        private const val SUMMARY_MARGIN_DP = 4f
        private const val TIMER_CAPTION_GAP_DP = 4f
        private const val MINI_ROW_GAP_DP = 8f
        /** 按钮最小高度 / 上下 padding，必须与 XML 的 minHeight、paddingTop/Bottom 一致。 */
        private const val CONTROL_MIN_HEIGHT_DP = 27f
        private const val CONTROL_VERTICAL_PADDING_DP = 4f
        private const val CAPTION_SP = 11f
        private const val CONTROL_SP = 12f
        private const val SUMMARY_SP = 10f
        private const val CONTROL_ENABLED_ALPHA = 1f
        private const val CONTROL_DISABLED_ALPHA = 0.45f
        /** Chronometer 最长显示占位（h:mm:ss），用于每档字号的实际宽度校验。 */
        private const val CHRONOMETER_WIDEST_TEXT = "00:00:00"
        /** base 上限，避免异常 ends_at 让 elapsedRealtime + delta 溢出。 */
        private const val MAX_CHRONOMETER_MILLIS = 7L * 24L * 60L * 60L * 1000L
        private const val URI_SCHEME = "duoyi"
        private const val URI_AUTHORITY = "action"
        private const val ACTION_START = "start_pomodoro"
        private const val ACTION_PAUSE = "pause_pomodoro"
        private const val ACTION_STOP = "stop_pomodoro"
        /** 左侧主数 / 右两行数值的字号档位，按整块预算依次降档。 */
        private val TIMER_SP_CANDIDATES = floatArrayOf(32f, 26f, 20f, 16f, 12f)
        private val VALUE_SP_CANDIDATES = floatArrayOf(16f, 14f, 12f, 12f, 12f)
        private const val TIMER_SP = 32f
        /** 右侧两行 mini stats 的最小水平占位（用于判断长 HH:MM:SS 是否需要降档）。 */
        private const val MINI_STATS_WIDTH_DP = 80f
        private const val VALUE_SP = 16f
        /** Trigger update from Flutter via HomeWidget.updateWidget or package upgrade. */
        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "focus")
        }
    }
}

/** 原生侧只读的计时快照状态；真正的 owner / session / rev 判定由 Dart 后台完成。 */
private enum class FocusTimerState(val wire: String) {
    IDLE("idle"),
    RUNNING("running"),
    PAUSED("paused"),
    ;
    companion object {
        fun byWire(value: String): FocusTimerState? =
            FocusTimerState.entries.firstOrNull { it.wire == value }
    }
}
