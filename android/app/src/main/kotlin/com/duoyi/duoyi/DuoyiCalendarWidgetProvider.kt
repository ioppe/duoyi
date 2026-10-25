package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/** "月历" 小组件。 */
open class DuoyiCalendarWidgetProvider : DuoyiStyledWidgetProvider() {
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
            val views = RemoteViews(context.packageName, R.layout.duoyi_calendar_widget)
            DuoyiWidgetTheme.applyContainer(
                context = context,
                views = views,
                prefs = prefs,
                rootId = R.id.widget_calendar_root,
                navId = R.id.widget_calendar_bottom_nav,
                appWidgetId = id,
            )
            DuoyiWidgetTheme.applyTextColors(
                views,
                prefs,
                primaryIds = intArrayOf(
                    R.id.widget_calendar_title,
                    R.id.widget_calendar_summary,
                    R.id.widget_calendar_today_button,
                    R.id.widget_calendar_nav_calendar,
                ),
                bodyIds = intArrayOf(R.id.widget_calendar_grid),
                mutedIds = intArrayOf(
                    R.id.widget_calendar_month,
                    R.id.widget_calendar_nav_todo,
                    R.id.widget_calendar_nav_habit,
                    R.id.widget_calendar_nav_focus,
                ),
            )
            DuoyiWidgetTheme.applyButtonSurfaces(
                views,
                prefs,
                secondaryIds = intArrayOf(R.id.widget_calendar_today_button),
            )
            val now = Calendar.getInstance()
            val compact = DuoyiWidgetDisplayMode.isCompact(prefs, id)
            val detailed = DuoyiWidgetDisplayMode.isDetailed(prefs, id)
            val monthPattern = if (compact) "M月" else "yyyy年M月"
            val monthTitle = SimpleDateFormat(monthPattern, Locale.getDefault()).format(now.time)

            views.setViewVisibility(
                R.id.widget_calendar_title,
                if (compact) View.GONE else View.VISIBLE
            )
            views.setTextViewText(
                R.id.widget_calendar_title,
                prefs.getString("brand_app_title", "多仪") ?: "多仪"
            )
            views.setTextViewText(R.id.widget_calendar_month, monthTitle)
            views.setTextViewText(R.id.widget_calendar_grid, buildMonthGrid(now, compact, detailed))
            views.setTextViewTextSize(
                R.id.widget_calendar_grid,
                TypedValue.COMPLEX_UNIT_SP,
                if (compact) 8.5f else if (detailed) 12f else 11f
            )
            views.setTextViewText(
                R.id.widget_calendar_summary,
                prefs.getString("calendar_month_summary", "本月日期 · 今日已标记") ?: "本月日期 · 今日已标记"
            )
            views.setViewVisibility(
                R.id.widget_calendar_summary,
                DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
            )

            val tabTodo = prefs.getString("nav_todo", "待办") ?: "待办"
            val tabHabit = prefs.getString("nav_habit", "习惯") ?: "习惯"
            val tabCalendar = prefs.getString("nav_calendar", "日历") ?: "日历"
            val tabFocus = prefs.getString("nav_focus", "专注") ?: "专注"
            views.setTextViewText(R.id.widget_calendar_nav_todo, tabTodo)
            views.setTextViewText(R.id.widget_calendar_nav_habit, tabHabit)
            views.setTextViewText(R.id.widget_calendar_nav_calendar, tabCalendar)
            views.setTextViewText(R.id.widget_calendar_nav_focus, tabFocus)

            val navTarget = DuoyiWidgetNavigation.targetFor(context, id)
            // 只有空白 root 打开 App 的日历页。
            val openCalendar = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/calendar")
            )
            views.setOnClickPendingIntent(R.id.widget_calendar_root, openCalendar)
            // 底部四项直接切换小组件内容。
            DuoyiWidgetNavigation.bindBottomTabs(
                context = context,
                views = views,
                prefs = prefs,
                target = navTarget,
                appWidgetId = id,
                navId = R.id.widget_calendar_bottom_nav,
                defaultNavVisibility = DuoyiWidgetDisplayMode.bottomNavVisibility(prefs, id),
                tabViewIds = mapOf(
                    DuoyiWidgetNavigation.TAB_TODO to R.id.widget_calendar_nav_todo,
                    DuoyiWidgetNavigation.TAB_HABIT to R.id.widget_calendar_nav_habit,
                    DuoyiWidgetNavigation.TAB_CALENDAR to R.id.widget_calendar_nav_calendar,
                    DuoyiWidgetNavigation.TAB_FOCUS to R.id.widget_calendar_nav_focus,
                ),
            )
            // 标题 / 月份 / 网格 / 摘要 / “今天”都只本地重绘当前实例。
            DuoyiWidgetNavigation.bindRefresh(
                context,
                views,
                navTarget,
                intArrayOf(
                    R.id.widget_calendar_title,
                    R.id.widget_calendar_month,
                    R.id.widget_calendar_grid,
                    R.id.widget_calendar_summary,
                    R.id.widget_calendar_today_button,
                ),
            )

            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun buildMonthGrid(now: Calendar, compact: Boolean, detailed: Boolean): String {
        val cal = now.clone() as Calendar
        val today = cal.get(Calendar.DAY_OF_MONTH)
        cal.set(Calendar.DAY_OF_MONTH, 1)
        val firstWeekday = (cal.get(Calendar.DAY_OF_WEEK) + 5) % 7
        val maxDay = cal.getActualMaximum(Calendar.DAY_OF_MONTH)
        val cells = MutableList(42) { "  " }
        for (day in 1..maxDay) {
            cells[firstWeekday + day - 1] = day.toString().padStart(2, ' ')
        }
        val currentWeek = ((firstWeekday + today - 1) / 7).coerceIn(0, 5)
        val visibleWeeks = when {
            compact -> currentWeek..currentWeek
            detailed -> 0..5
            else -> maxOf(0, currentWeek - 1)..minOf(5, currentWeek + 2)
        }
        val lines = mutableListOf("一 二 三 四 五 六 日")
        for (week in visibleWeeks) {
            lines += cells.subList(week * 7, week * 7 + 7).joinToString(" ")
        }
        return lines.joinToString("\n")
    }

    companion object {
        /** Trigger update from Flutter via HomeWidget.updateWidget or package upgrade. */
        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "calendar")
        }
    }
}
