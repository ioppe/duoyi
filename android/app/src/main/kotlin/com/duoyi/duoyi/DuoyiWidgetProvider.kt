package com.duoyi.duoyi

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Home screen widget for MIUI / generic Android.
 * Pulls counters that the Flutter side wrote via HomeWidget.saveWidgetData.
 */
class DuoyiWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        // 4 个核心页的本地切页 / 刷新在导航 helper 里完成；历史综合组件默认展示日历页。
        if (DuoyiWidgetNavigation.handleReceive(context, intent, this)) return
        super.onReceive(context, intent)
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            DuoyiWidgetProviderRegistry.requestUpdateForAllWidgets(context)
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val prefs = HomeWidgetPlugin.getData(context)
        appWidgetIds.forEach { DuoyiWidgetDisplayMode.clearForWidget(prefs, it) }
        DuoyiWidgetNavigation.clearForWidgets(context, appWidgetIds)
        super.onDeleted(context, appWidgetIds)
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val prefs: SharedPreferences = HomeWidgetPlugin.getData(context)

        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.duoyi_widget)
            DuoyiWidgetTheme.applyContainer(
                context = context,
                views = views,
                prefs = prefs,
                rootId = R.id.widget_root,
                navId = R.id.widget_bottom_nav,
                appWidgetId = id,
            )
            DuoyiWidgetTheme.applyTextColors(
                views,
                prefs,
                primaryIds = intArrayOf(
                    R.id.widget_title,
                    R.id.widget_todo_count,
                    R.id.widget_habit_progress,
                    R.id.widget_pomodoro_count,
                    R.id.widget_quick_open,
                    R.id.widget_nav_calendar,
                ),
                bodyIds = intArrayOf(
                    R.id.widget_today_event,
                    R.id.widget_goal_summary,
                    R.id.widget_anniversary_summary,
                    R.id.widget_course_summary,
                ),
                mutedIds = intArrayOf(
                    R.id.widget_date,
                    R.id.widget_nav_todo,
                    R.id.widget_nav_habit,
                    R.id.widget_nav_focus,
                ),
                onPrimaryIds = intArrayOf(R.id.widget_quick_pomodoro),
            )
            DuoyiWidgetTheme.applyButtonSurfaces(
                views,
                prefs,
                primaryIds = intArrayOf(R.id.widget_quick_pomodoro),
                secondaryIds = intArrayOf(R.id.widget_quick_open),
            )
            val today = SimpleDateFormat("MM/dd", Locale.getDefault()).format(Date())

            views.setTextViewText(R.id.widget_title, prefs.getString("brand_app_title", "多仪"))
            views.setTextViewText(R.id.widget_date, today)
            views.setTextViewText(R.id.widget_todo_count, prefs.getInt("todo_count", 0).toString())
            views.setTextViewText(R.id.widget_habit_progress, "${prefs.getInt("habit_percent", 0)}%")
            views.setTextViewText(R.id.widget_pomodoro_count, prefs.getInt("pomodoro_today", 0).toString())
            views.setTextViewText(
                R.id.widget_today_event,
                prefs.getString("today_event_summary", "今日没有日程") ?: "今日没有日程"
            )
            views.setTextViewText(
                R.id.widget_goal_summary,
                prefs.getString("goal_highlight_1", "暂无进行中目标") ?: "暂无进行中目标"
            )
            views.setTextViewText(
                R.id.widget_anniversary_summary,
                prefs.getString("anniversary_highlight_1", "暂无近期纪念日") ?: "暂无近期纪念日"
            )
            views.setTextViewText(
                R.id.widget_course_summary,
                prefs.getString("course_highlight_1", "今日暂无课程") ?: "今日暂无课程"
            )
            views.setViewVisibility(
                R.id.widget_quick_row,
                DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_goal_summary,
                DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_anniversary_summary,
                DuoyiWidgetDisplayMode.detailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_course_summary,
                DuoyiWidgetDisplayMode.detailedVisibility(prefs, id)
            )

            val tabTodo = prefs.getString("nav_todo", "待办") ?: "待办"
            val tabHabit = prefs.getString("nav_habit", "习惯") ?: "习惯"
            val tabCalendar = prefs.getString("nav_calendar", "日历") ?: "日历"
            val tabFocus = prefs.getString("nav_focus", "番茄") ?: "番茄"
            views.setTextViewText(R.id.widget_quick_pomodoro, "开始$tabFocus")
            views.setTextViewText(R.id.widget_quick_open, "打开 App")
            views.setTextViewText(R.id.widget_nav_todo, tabTodo)
            views.setTextViewText(R.id.widget_nav_habit, tabHabit)
            views.setTextViewText(R.id.widget_nav_calendar, tabCalendar)
            views.setTextViewText(R.id.widget_nav_focus, tabFocus)

            // 底部四项直接切换小组件内容；空白 root 才是打开 App 的入口。
            val navTarget = DuoyiWidgetNavigation.targetFor(context, id)
            DuoyiWidgetNavigation.bindBottomTabs(
                context = context,
                views = views,
                prefs = prefs,
                target = navTarget,
                appWidgetId = id,
                navId = R.id.widget_bottom_nav,
                defaultNavVisibility = DuoyiWidgetDisplayMode.bottomNavVisibility(prefs, id),
                tabViewIds = mapOf(
                    DuoyiWidgetNavigation.TAB_TODO to R.id.widget_nav_todo,
                    DuoyiWidgetNavigation.TAB_HABIT to R.id.widget_nav_habit,
                    DuoyiWidgetNavigation.TAB_CALENDAR to R.id.widget_nav_calendar,
                    DuoyiWidgetNavigation.TAB_FOCUS to R.id.widget_nav_focus,
                ),
            )
            // 只有空白区打开 App，历史综合组件默认落在日历页。
            val openAppIntent: PendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("duoyi://tab/calendar")
            )
            views.setOnClickPendingIntent(R.id.widget_root, openAppIntent)
            // 标题 / 摘要 / 统计说明是只读信息：点击只本地重绘，不开 App。
            DuoyiWidgetNavigation.bindRefresh(
                context,
                views,
                navTarget,
                intArrayOf(
                    R.id.widget_title,
                    R.id.widget_date,
                    R.id.widget_today_event,
                    R.id.widget_goal_summary,
                    R.id.widget_anniversary_summary,
                    R.id.widget_course_summary,
                    R.id.widget_todo_caption,
                    R.id.widget_habit_caption,
                    R.id.widget_pomodoro_caption,
                ),
            )
            // 三个统计也能本地切到对应内容页。
            DuoyiWidgetNavigation.bindTabButton(
                context, views, navTarget, R.id.widget_todo_count,
                DuoyiWidgetNavigation.TAB_TODO,
            )
            DuoyiWidgetNavigation.bindTabButton(
                context, views, navTarget, R.id.widget_habit_progress,
                DuoyiWidgetNavigation.TAB_HABIT,
            )
            DuoyiWidgetNavigation.bindTabButton(
                context, views, navTarget, R.id.widget_pomodoro_count,
                DuoyiWidgetNavigation.TAB_FOCUS,
            )
            // “打开 App”文案按钮收起（资源 ID 保留）：编辑仍需点空白区进 App。
            views.setViewVisibility(R.id.widget_quick_open, View.GONE)

            // Quick start pomodoro：在后台直接开始专注，不打开 App。
            val quickPomodoroIntent: PendingIntent = HomeWidgetBackgroundIntent.getBroadcast(
                context,
                Uri.parse("duoyi://action/start_pomodoro")
            )
            views.setOnClickPendingIntent(R.id.widget_quick_pomodoro, quickPomodoroIntent)

            appWidgetManager.updateAppWidget(id, views)
        }
    }

    companion object {
        /** Trigger update from Flutter via HomeWidget.updateWidget */
        fun requestUpdate(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, DuoyiWidgetProvider::class.java))
            if (ids.isNotEmpty()) {
                val intent = Intent(context, DuoyiWidgetProvider::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(intent)
            }
        }
    }
}
