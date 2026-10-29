package com.duoyi.duoyi

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.util.TypedValue
import android.widget.RemoteViews
import android.view.View
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * "习惯" 小组件。
 *
 * 视觉（Apple 风）：顶栏只留 18dp logo + 13sp 模块名；百分比搬到 body 做主视觉
 * （34sp，短实例降档），下面 12sp「今日完成率」（键 widget_habit_today_label）与
 * 现有 streak 12sp。hasHint 时才按整行预算显示具体 habitQuickCheckLabel，仍进
 * 该习惯详情。旧 widget_habit_title 保留但始终 GONE。
 */
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
            // 同时产出横屏 / 竖屏两套 RemoteViews（宿主旋转后直接复用对应方向）。
            // lambda 的 context 有意遮蔽外层，使 resolve / 主题 / 底栏 / PendingIntent
            // 全部基于同一方向配置生成；以下渲染逻辑原样保留。
            val views = DuoyiWidgetLayout.forOrientations(context) { context ->
            val views = RemoteViews(context.packageName, R.layout.duoyi_habit_widget)
            val profile = DuoyiWidgetLayout.resolve(context, appWidgetManager, id)
            val apple = DuoyiWidgetTheme.applePaletteOf(prefs)
            DuoyiWidgetTheme.applyContainer(
                context = context,
                views = views,
                prefs = prefs,
                rootId = R.id.widget_habit_root,
                navId = R.id.widget_habit_bottom_nav,
                appWidgetId = id,
                appleStyle = true,
            )
            DuoyiWidgetTheme.applyTextColors(
                views,
                prefs,
                primaryIds = intArrayOf(R.id.widget_habit_percent),
                bodyIds = intArrayOf(
                    R.id.widget_module_title,
                    R.id.widget_habit_streak,
                    R.id.widget_habit_item_1,
                    R.id.widget_habit_item_2,
                    R.id.widget_habit_item_3,
                    R.id.widget_habit_summary,
                ),
                mutedIds = intArrayOf(
                    R.id.widget_habit_today_label,
                    R.id.widget_habit_hint,
                    R.id.widget_habit_subtitle,
                ),
                appleStyle = true,
            )

            views.setTextViewText(
                R.id.widget_module_title,
                prefs.getString("nav_habit", "习惯") ?: "习惯"
            )
            val percent = prefs.getInt("habit_percent", 0)
            views.setTextViewText(R.id.widget_habit_percent, "$percent%")
            // 0% 用主 label/secondary 更安静，正数才用 accent。
            views.setTextColor(
                R.id.widget_habit_percent,
                if (percent > 0) apple.accent else apple.label
            )
            views.setTextViewText(
                R.id.widget_habit_today_label,
                prefs.getString("widget_habit_today_label", "今日完成率") ?: "今日完成率"
            )
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
            val habitHighlightLabels = HABIT_HIGHLIGHT_KEYS.map { key ->
                prefs.getString(key, "") ?: ""
            }
            val habitHighlightIds = HABIT_HIGHLIGHT_ID_KEYS.map { key ->
                prefs.getString(key, "") ?: ""
            }
            HABIT_ITEM_VIEW_IDS.forEachIndexed { index, viewId ->
                views.setTextViewText(viewId, habitHighlightLabels[index])
            }
            // 旧的「今日习惯」副标题与新 label 语义重复，保持 GONE（ID 保留）。
            views.setViewVisibility(R.id.widget_habit_subtitle, View.GONE)

            val tabTodo = prefs.getString("nav_todo", "待办") ?: "待办"
            val tabHabit = prefs.getString("nav_habit", "习惯") ?: "习惯"
            val tabCalendar = prefs.getString("nav_calendar", "日历") ?: "日历"
            val tabFocus = prefs.getString("nav_focus", "专注") ?: "专注"
            views.setTextViewText(R.id.widget_habit_nav_todo, tabTodo)
            views.setTextViewText(R.id.widget_habit_nav_habit, tabHabit)
            views.setTextViewText(R.id.widget_habit_nav_calendar, tabCalendar)
            views.setTextViewText(R.id.widget_habit_nav_focus, tabFocus)

            val navTarget = DuoyiWidgetNavigation.targetFor(context, id)
            // 顶部区域（品牌 logo / 模块名 / 百分比 / 聚合摘要 / 连续天数）进入 App 习惯页。
            val openHabitPage = appPageIntent(context, Uri.parse("duoyi://tab/habit"))
            intArrayOf(
                R.id.widget_habit_root,
                R.id.widget_brand_logo,
                R.id.widget_habit_title,
                R.id.widget_habit_subtitle,
                R.id.widget_module_title,
                R.id.widget_habit_percent,
                R.id.widget_habit_today_label,
                R.id.widget_habit_summary,
                R.id.widget_habit_streak,
                R.id.widget_habit_item_1,
                R.id.widget_habit_item_2,
                R.id.widget_habit_item_3,
                R.id.widget_habit_hint,
            ).forEach { views.setOnClickPendingIntent(it, openHabitPage) }
            // 底部四项直接切换小组件内容。
            DuoyiWidgetNavigation.bindBottomTabs(
                context = context,
                views = views,
                prefs = prefs,
                target = navTarget,
                appWidgetId = id,
                navId = R.id.widget_habit_bottom_nav,
                // 核心四页底栏始终可见；实例内切页行为仍由 bindBottomTabs 保留。
                defaultNavVisibility = View.VISIBLE,
                tabViewIds = mapOf(
                    DuoyiWidgetNavigation.TAB_TODO to R.id.widget_habit_nav_todo,
                    DuoyiWidgetNavigation.TAB_HABIT to R.id.widget_habit_nav_habit,
                    DuoyiWidgetNavigation.TAB_CALENDAR to R.id.widget_habit_nav_calendar,
                    DuoyiWidgetNavigation.TAB_FOCUS to R.id.widget_habit_nav_focus,
                ),
            )
            if (habitQuickCheckId.isNotBlank()) {
                // 具体习惯提示进入该习惯的打卡详情，不发后台打卡广播。
                val habitDetailPage = appPageIntent(
                    context,
                    Uri.parse("duoyi://habit/${Uri.encode(habitQuickCheckId)}")
                )
                views.setOnClickPendingIntent(R.id.widget_habit_hint, habitDetailPage)
            }
            HABIT_ITEM_VIEW_IDS.forEachIndexed { index, viewId ->
                val habitId = habitHighlightIds[index]
                val habitPage = if (habitId.isBlank()) {
                    openHabitPage
                } else {
                    appPageIntent(
                        context,
                        Uri.parse("duoyi://habit/${Uri.encode(habitId)}")
                    )
                }
                views.setOnClickPendingIntent(viewId, habitPage)
            }
            // 容量优先：百分比整块必出，label / streak / habit rows / 摘要按整行预算取舍。
            applyCapacity(
                views,
                prefs,
                id,
                profile,
                habitHighlightIds.count { it.isNotBlank() },
                habitQuickCheckId.isNotBlank(),
            )
            DuoyiWidgetTheme.applySegmentedNavigation(
                context = context,
                views = views,
                prefs = prefs,
                tabViewIds = intArrayOf(
                    R.id.widget_habit_nav_todo,
                    R.id.widget_habit_nav_habit,
                    R.id.widget_habit_nav_calendar,
                    R.id.widget_habit_nav_focus,
                ),
                selectedId = R.id.widget_habit_nav_habit,
                profile = profile,
            )

                views
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    /**
     * 按真实高度决定习惯页显示几行：百分比主视觉先放，放不下就整档缩小；
     * label / streak 必跟百分比同进同出；hint 只在存在具体习惯 ID、密度允许且
     * 整行放得下时出现，因此不会把原本 GONE 的提示错误显示出来。
     */
    private fun applyCapacity(
        views: RemoteViews,
        prefs: SharedPreferences,
        appWidgetId: Int,
        profile: DuoyiWidgetProfile,
        itemCount: Int,
        hasHint: Boolean,
    ) {
        val padded = profile.withPadding(profile.applePaddingDp)
        val paddingPx = padded.px(padded.paddingDp)
        views.setViewPadding(
            R.id.widget_habit_content,
            paddingPx,
            paddingPx,
            paddingPx,
            paddingPx,
        )
        val budget = padded.budget(
            padded.headerDp(DuoyiWidgetLayout.MODULE_TITLE_SP) +
                BODY_MARGIN_DP +
                DuoyiWidgetLayout.NAV_MARGIN_DP +
                padded.navDp(padded.navLabelSp)
        )
        var percentSp = 0f
        var percentShown = false
        for (candidate in PERCENT_SP_CANDIDATES) {
            if (budget.reserve(padded.lineDp(candidate))) {
                percentSp = candidate
                percentShown = true
                break
            }
        }
        if (percentShown) {
            views.setTextViewTextSize(
                R.id.widget_habit_percent,
                TypedValue.COMPLEX_UNIT_SP,
                percentSp,
            )
        }
        views.setViewVisibility(
            R.id.widget_habit_percent,
            if (percentShown) View.VISIBLE else View.GONE
        )
        val labelShown = percentShown &&
            budget.reserve(LABEL_MARGIN_DP + padded.lineDp(LABEL_SP))
        views.setViewVisibility(
            R.id.widget_habit_today_label,
            if (labelShown) View.VISIBLE else View.GONE
        )
        val streakShown = percentShown &&
            budget.reserve(STREAK_MARGIN_DP + padded.lineDp(STREAK_SP))
        views.setViewVisibility(
            R.id.widget_habit_streak,
            if (streakShown) View.VISIBLE else View.GONE
        )
        val dense = !DuoyiWidgetDisplayMode.isCompact(prefs, appWidgetId)
        val detailed = DuoyiWidgetDisplayMode.isDetailed(prefs, appWidgetId)
        var canShowItems = percentShown
        var shownItemCount = 0
        HABIT_ITEM_VIEW_IDS.forEachIndexed { index, viewId ->
            val itemShown = canShowItems && index < itemCount &&
                budget.reserve(HABIT_ITEM_MARGIN_DP + padded.lineDp(HABIT_ITEM_SP))
            views.setViewVisibility(
                viewId,
                if (itemShown) View.VISIBLE else View.GONE,
            )
            if (itemShown) {
                shownItemCount++
            } else {
                canShowItems = false
            }
        }
        val hintShown = percentShown && shownItemCount == 0 && hasHint && dense &&
            budget.reserve(HINT_MARGIN_DP + padded.lineDp(HINT_SP))
        views.setViewVisibility(
            R.id.widget_habit_hint,
            if (hintShown) View.VISIBLE else View.GONE
        )
        // 摘要与百分比信息重复：只在没有可见具体习惯且 detailed 时补一行。
        val summaryShown = percentShown && shownItemCount == 0 && detailed &&
            budget.reserve(SUMMARY_MARGIN_DP + padded.lineDp(SUMMARY_SP))
        views.setViewVisibility(
            R.id.widget_habit_summary,
            if (summaryShown) View.VISIBLE else View.GONE
        )
    }

    private fun appPageIntent(context: Context, uri: Uri): PendingIntent {
        return HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri)
    }

    companion object {

        // 与 duoyi_habit_widget.xml 一致的段落间距：body marginTop=6dp。
        private const val BODY_MARGIN_DP = 6f
        private const val LABEL_MARGIN_DP = 5f
        private const val STREAK_MARGIN_DP = 12f
        private const val HABIT_ITEM_MARGIN_DP = 6f
        private const val HABIT_ITEM_SP = 11f
        private const val HINT_MARGIN_DP = 8f
        private const val SUMMARY_MARGIN_DP = 6f
        private const val LABEL_SP = 12f
        private const val STREAK_SP = 12f
        private const val HINT_SP = 11f
        private const val SUMMARY_SP = 12f
        /** 百分比主视觉：34sp 优先，短实例/大字体依次降档，最后 28sp。 */
        private val PERCENT_SP_CANDIDATES = floatArrayOf(34f, 32f, 28f)
        private val HABIT_HIGHLIGHT_KEYS = arrayOf(
            "habit_highlight_1",
            "habit_highlight_2",
            "habit_highlight_3",
        )
        private val HABIT_HIGHLIGHT_ID_KEYS = arrayOf(
            "habit_highlight_1_id",
            "habit_highlight_2_id",
            "habit_highlight_3_id",
        )
        private val HABIT_ITEM_VIEW_IDS = intArrayOf(
            R.id.widget_habit_item_1,
            R.id.widget_habit_item_2,
            R.id.widget_habit_item_3,
        )
        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "habit")
        }
    }
}
