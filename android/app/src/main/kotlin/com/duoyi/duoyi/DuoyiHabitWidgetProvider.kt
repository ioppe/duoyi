package com.duoyi.duoyi

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

/** "习惯" 小组件。 */
open class DuoyiHabitWidgetProvider : DuoyiStyledWidgetProvider() {
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
            val views = RemoteViews(context.packageName, R.layout.duoyi_habit_widget)
            DuoyiWidgetTheme.applyContainer(
                context = context,
                views = views,
                prefs = prefs,
                rootId = R.id.widget_habit_root,
                navId = R.id.widget_habit_bottom_nav,
                appWidgetId = id,
            )
            DuoyiWidgetTheme.applyTextColors(
                views,
                prefs,
                primaryIds = intArrayOf(
                    R.id.widget_habit_title,
                    R.id.widget_habit_percent,
                    R.id.widget_habit_nav_habit,
                ),
                bodyIds = intArrayOf(
                    R.id.widget_habit_summary,
                    R.id.widget_habit_streak,
                    R.id.widget_habit_hint,
                ),
                mutedIds = intArrayOf(
                    R.id.widget_habit_subtitle,
                    R.id.widget_habit_nav_todo,
                    R.id.widget_habit_nav_calendar,
                    R.id.widget_habit_nav_focus,
                ),
            )

            views.setTextViewText(
                R.id.widget_habit_title,
                prefs.getString("brand_app_title", "多仪") ?: "多仪"
            )
            views.setTextViewText(R.id.widget_habit_percent, "${prefs.getInt("habit_percent", 0)}%")
            views.setTextViewText(R.id.widget_habit_subtitle, "今日习惯")
            views.setTextViewText(
                R.id.widget_habit_summary,
                prefs.getString("habit_summary", "· 今日习惯待打卡") ?: "· 今日习惯待打卡"
            )
            views.setTextViewText(
                R.id.widget_habit_streak,
                prefs.getString("streak_summary", "· 连续记录 0 天") ?: "· 连续记录 0 天"
            )
            val habitQuickCheckId = prefs.getString("habit_quick_check_id", "") ?: ""
            val habitQuickCheckLabel = prefs.getString(
                "habit_quick_check_label",
                "点击进入习惯打卡"
            ) ?: "点击进入习惯打卡"
            views.setTextViewText(R.id.widget_habit_hint, habitQuickCheckLabel)
            views.setViewVisibility(
                R.id.widget_habit_streak,
                DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_habit_bottom_nav,
                DuoyiWidgetDisplayMode.bottomNavVisibility(prefs, id)
            )
            views.setViewVisibility(
                R.id.widget_habit_hint,
                DuoyiWidgetDisplayMode.standardOrDetailedVisibility(prefs, id)
            )

            val tabTodo = prefs.getString("nav_todo", "待办") ?: "待办"
            val tabHabit = prefs.getString("nav_habit", "习惯") ?: "习惯"
            val tabCalendar = prefs.getString("nav_calendar", "日历") ?: "日历"
            val tabFocus = prefs.getString("nav_focus", "专注") ?: "专注"
            views.setTextViewText(R.id.widget_habit_nav_todo, tabTodo)
            views.setTextViewText(R.id.widget_habit_nav_habit, tabHabit)
            views.setTextViewText(R.id.widget_habit_nav_calendar, tabCalendar)
            views.setTextViewText(R.id.widget_habit_nav_focus, tabFocus)

            val openHabit = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/habit")
            )
            val openTodo = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/todo")
            )
            val openCalendar = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/calendar")
            )
            val openFocus = HomeWidgetLaunchIntent.getActivity(
                context, MainActivity::class.java, Uri.parse("duoyi://tab/focus")
            )
            val quickCheckHabit = if (habitQuickCheckId.isNotBlank()) {
                // 有可打卡习惯时直接在后台打卡，不打开 App。
                HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("duoyi://action/checkin_habit?id=${Uri.encode(habitQuickCheckId)}")
                )
            } else {
                openHabit
            }

            views.setOnClickPendingIntent(R.id.widget_habit_root, openHabit)
            views.setOnClickPendingIntent(R.id.widget_habit_title, openHabit)
            views.setOnClickPendingIntent(R.id.widget_habit_subtitle, openHabit)
            views.setOnClickPendingIntent(R.id.widget_habit_percent, openHabit)
            views.setOnClickPendingIntent(R.id.widget_habit_summary, openHabit)
            views.setOnClickPendingIntent(R.id.widget_habit_streak, openHabit)
            views.setOnClickPendingIntent(R.id.widget_habit_hint, quickCheckHabit)
            views.setOnClickPendingIntent(R.id.widget_habit_nav_todo, openTodo)
            views.setOnClickPendingIntent(R.id.widget_habit_nav_habit, openHabit)
            views.setOnClickPendingIntent(R.id.widget_habit_nav_calendar, openCalendar)
            views.setOnClickPendingIntent(R.id.widget_habit_nav_focus, openFocus)

            appWidgetManager.updateAppWidget(id, views)
        }
    }

    companion object {
        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "habit")
        }
    }
}
