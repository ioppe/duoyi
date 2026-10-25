package com.duoyi.duoyi

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** "专注" 小组件。类名保留用于兼容已安装的旧小组件。 */
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
            val views = RemoteViews(context.packageName, R.layout.duoyi_focus_habit_widget)
            DuoyiWidgetTheme.applyContainer(
                context = context,
                views = views,
                prefs = prefs,
                rootId = R.id.widget_focus_habit_root,
                navId = R.id.widget_focus_habit_bottom_nav,
                appWidgetId = id,
            )
            DuoyiWidgetTheme.applyTextColors(
                views,
                prefs,
                primaryIds = intArrayOf(
                    R.id.widget_focus_habit_title,
                    R.id.widget_focus_count,
                    R.id.widget_focus_habit_progress,
                    R.id.widget_focus_streak_count,
                    R.id.widget_focus_nav_focus,
                ),
                bodyIds = intArrayOf(
                    R.id.widget_focus_summary,
                    R.id.widget_focus_habit_summary,
                    R.id.widget_focus_streak_summary,
                ),
                mutedIds = intArrayOf(
                    R.id.widget_focus_habit_date,
                    R.id.widget_focus_timer_caption,
                    R.id.widget_focus_nav_todo,
                    R.id.widget_focus_nav_habit,
                    R.id.widget_focus_nav_calendar,
                ),
                onPrimaryIds = intArrayOf(R.id.widget_focus_quick_start),
            )
            DuoyiWidgetTheme.applyButtonSurfaces(
                views,
                prefs,
                primaryIds = intArrayOf(R.id.widget_focus_quick_start),
            )
            val today = SimpleDateFormat("MM/dd", Locale.getDefault()).format(Date())

            views.setTextViewText(
                R.id.widget_focus_habit_title,
                "专注"
            )
            views.setTextViewText(R.id.widget_focus_habit_date, today)
            val pomodoroToday = prefs.getInt("pomodoro_today", 0)
            val focusMinutesToday = prefs.getInt("focus_minutes_today", pomodoroToday * 25)
            val nextFocusLabel = prefs.getString("next_focus_label", "25 分钟专注") ?: "25 分钟专注"
            val timerRunning = getBooleanCompat(prefs, "focus_timer_running")
            val timerRemainingSeconds = currentTimerRemainingSeconds(prefs, timerRunning)
            val timerLabel = prefs.getString("focus_timer_label", "专注倒计时") ?: "专注倒计时"
            val timerText = if (timerRunning) {
                formatTimer(timerRemainingSeconds)
            } else {
                extractFirstNumber(nextFocusLabel)
            }
            val timerCaption = if (timerRunning) "倒计时" else "下一轮"
            val timerSummary = if (timerRunning) {
                "$timerLabel：${formatTimer(timerRemainingSeconds)}"
            } else {
                "下一轮：$nextFocusLabel"
            }
            val timerHint = if (timerRunning) {
                val endsAtMillis = getLongCompat(prefs, "focus_timer_ends_at_millis")
                if (endsAtMillis > 0L) {
                    "预计 ${SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(endsAtMillis))} 结束"
                } else {
                    "正在专注中"
                }
            } else {
                "结束后提醒休息"
            }
            val quickStartText = if (timerRunning) "查看倒计时" else "开始$nextFocusLabel"
            views.setTextViewText(
                R.id.widget_focus_count,
                pomodoroToday.toString()
            )
            views.setTextViewText(
                R.id.widget_focus_habit_progress,
                focusMinutesToday.toString()
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
            views.setViewVisibility(
                R.id.widget_focus_quick_start,
                DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_focus_habit_summary,
                DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_focus_streak_summary,
                DuoyiWidgetDisplayMode.detailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_focus_habit_bottom_nav,
                DuoyiWidgetDisplayMode.bottomNavVisibility(prefs, id)
            )

            val tabTodo = prefs.getString("nav_todo", "待办") ?: "待办"
            val tabHabit = prefs.getString("nav_habit", "习惯") ?: "习惯"
            val tabCalendar = prefs.getString("nav_calendar", "日历") ?: "日历"
            val tabFocus = prefs.getString("nav_focus", "专注") ?: "专注"
            views.setTextViewText(R.id.widget_focus_nav_todo, tabTodo)
            views.setTextViewText(R.id.widget_focus_nav_habit, tabHabit)
            views.setTextViewText(R.id.widget_focus_nav_calendar, tabCalendar)
            views.setTextViewText(R.id.widget_focus_nav_focus, tabFocus)

            val openFocus = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/focus")
            )
            val openHabit = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/habit")
            )
            val openTodo = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/todo")
            )
            val openCalendar = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/calendar")
            )
            // “开始专注”直接在后台启动，不打开 App；其余区域仍是浏览入口。
            val startFocus: PendingIntent = HomeWidgetBackgroundIntent.getBroadcast(
                context,
                Uri.parse("duoyi://action/start_pomodoro")
            )

            views.setOnClickPendingIntent(R.id.widget_focus_habit_root, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_habit_title, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_habit_date, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_count, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_summary, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_quick_start, startFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_habit_progress, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_streak_count, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_timer_caption, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_habit_summary, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_streak_summary, openFocus)
            views.setOnClickPendingIntent(R.id.widget_focus_nav_todo, openTodo)
            views.setOnClickPendingIntent(R.id.widget_focus_nav_habit, openHabit)
            views.setOnClickPendingIntent(R.id.widget_focus_nav_calendar, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_focus_nav_focus, openFocus)

            appWidgetManager.updateAppWidget(id, views)
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

    companion object {
        /** Trigger update from Flutter via HomeWidget.updateWidget or package upgrade. */
        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "focus")
        }
    }
}
