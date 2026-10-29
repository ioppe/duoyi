package com.duoyi.duoyi

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.net.Uri
import android.util.TypedValue
import android.view.View
import android.appwidget.AppWidgetManager
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import kotlin.math.max

/**
 * "今日待办" 小组件。
 *
 * 数据协议（Flutter 写入 HomeWidget prefs）：
 *   widget_todo_items_json  ：JSON 数组 [{'id':String,'title':String,'quadrant':int}]，
 *                             Dart 已按 Q1 → Q3 → Q2 → Q4 排好并推送全部今日可见未完成
 *                             事项；native 原样使用顺序，绝不按 quadrant 重排。
 *   todo_top3_count         ：今日未完成总数（仍是全部计数，不只前三条）。
 *   todo_top3_1..3 (+_id)   ：旧协议；只在新 key 完全不存在时回退。
 *   widget_todo_count_unit  ：数量单位（缺省「项」）
 *   widget_todo_empty_hint  ：空状态提示文案
 *
 * 视觉（Apple 风，未改动）：24dp 圆角外框、14dp 内边距、18dp logo + 13sp 模块名 +
 * 右侧大数量。正文是 framework 集合（ListView `widget_todo_list` + RemoteViewsService），
 * 与居中 emptyGroup 二选一；底栏不参与滚动。旧三行容器与 done_/marker_/row_ ID 仍保留
 * 在 XML 里但永远 GONE，只为升级兼容，不再参与可见布局。
 */
open class DuoyiTodoWidgetProvider : DuoyiStyledWidgetProvider() {
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
            val items = readTodoItems(prefs)
            val navTarget = DuoyiWidgetNavigation.targetFor(context, id)
            // 同时产出横屏 / 竖屏两套 RemoteViews（宿主旋转后直接复用对应方向）。
            // lambda 的 context 有意遮蔽外层，使 resolve / 主题 / 底栏 / 集合适配器
            // 全部基于同一方向配置生成。
            val views = DuoyiWidgetLayout.forOrientations(context) { context ->
            val views = RemoteViews(context.packageName, R.layout.duoyi_todo_widget)
            val profile = DuoyiWidgetLayout.resolve(context, appWidgetManager, id)
            val apple = DuoyiWidgetTheme.applePaletteOf(prefs)
            DuoyiWidgetTheme.applyContainer(
                context = context,
                views = views,
                prefs = prefs,
                rootId = R.id.widget_todo_root,
                navId = R.id.widget_todo_bottom_nav,
                appWidgetId = id,
                appleStyle = true,
            )
            DuoyiWidgetTheme.applyTextColors(
                views,
                prefs,
                primaryIds = intArrayOf(R.id.widget_todo_count),
                bodyIds = intArrayOf(
                    R.id.widget_module_title,
                    R.id.widget_todo_item_1,
                    R.id.widget_todo_item_2,
                    R.id.widget_todo_item_3,
                    R.id.widget_todo_empty_title,
                ),
                mutedIds = intArrayOf(
                    R.id.widget_todo_count_unit,
                    R.id.widget_todo_today_summary,
                    R.id.widget_todo_empty_hint,
                ),
                appleStyle = true,
            )
            DuoyiWidgetTheme.applyButtonSurfaces(
                views,
                prefs,
                secondaryIds = intArrayOf(
                    R.id.widget_todo_quick_add,
                    R.id.widget_todo_done_1,
                    R.id.widget_todo_done_2,
                    R.id.widget_todo_done_3,
                ),
                appleStyle = true,
            )
            // 模块名沿用既有 nav_* 文案，旧 brand_app_title 只留在 GONE 的 widget_todo_title 上。
            views.setTextViewText(
                R.id.widget_module_title,
                prefs.getString("nav_todo", "待办") ?: "待办"
            )
            val todoCount = prefs.getInt(DuoyiWidgetCollections.KEY_TODO_COUNT, 0)
                .coerceAtLeast(0)
            views.setTextViewText(R.id.widget_todo_count, todoCount.toString())
            views.setTextViewText(
                R.id.widget_todo_count_unit,
                prefs.getString("widget_todo_count_unit", "项") ?: "项"
            )
            // 0 不报警告色：数量用 secondary，只有正数才用品牌 accent。
            views.setTextColor(
                R.id.widget_todo_count,
                if (todoCount > 0) apple.accent else apple.secondary
            )
            // 空状态文案：优先复用已有 todo_top3_1，缺失时用内置中文兜底。
            val emptyTitle = cleanTodoTitle(prefs.getString("todo_top3_1", "") ?: "")
            views.setTextViewText(
                R.id.widget_todo_empty_title,
                emptyTitle.ifBlank { DEFAULT_EMPTY_TITLE }
            )
            views.setTextViewText(
                R.id.widget_todo_empty_hint,
                prefs.getString("widget_todo_empty_hint", DEFAULT_EMPTY_HINT)
                    ?: DEFAULT_EMPTY_HINT
            )
            // 装饰性灰 check：只上色，不绑定任何点击（不是完成按钮）。
            views.setInt(R.id.widget_todo_empty_check, "setColorFilter", apple.secondary)
            views.setTextViewText(
                R.id.widget_todo_item_1,
                cleanTodoTitle(prefs.getString("todo_top3_1", "") ?: "")
            )
            views.setTextViewText(
                R.id.widget_todo_item_2,
                cleanTodoTitle(prefs.getString("todo_top3_2", "") ?: "")
            )
            views.setTextViewText(
                R.id.widget_todo_item_3,
                cleanTodoTitle(prefs.getString("todo_top3_3", "") ?: "")
            )
            views.setTextViewText(
                R.id.widget_todo_today_summary,
                "今日待办 · $todoCount 项"
            )
            // 左侧细 marker 用 accent 上色（纯色块，无圆角，可安全 setBackgroundColor）。
            intArrayOf(
                R.id.widget_todo_marker_1,
                R.id.widget_todo_marker_2,
                R.id.widget_todo_marker_3,
            ).forEach { views.setInt(it, "setBackgroundColor", apple.accent) }

            // 顶部区域（品牌 logo / 模块名 / 数量 / 空状态）进入 App 待办页。
            val openTodoPage = appPageIntent(context, Uri.parse("duoyi://tab/todo"))
            intArrayOf(
                R.id.widget_todo_root,
                R.id.widget_brand_logo,
                R.id.widget_todo_title,
                R.id.widget_module_title,
                R.id.widget_todo_count,
                R.id.widget_todo_count_unit,
                R.id.widget_todo_today_summary,
                R.id.widget_todo_empty_group,
                R.id.widget_todo_empty_title,
                R.id.widget_todo_empty_hint,
            ).forEach { views.setOnClickPendingIntent(it, openTodoPage) }
            // 行详情最后绑定：具体任务覆盖上面的整页跳转，避免通用绑定遮蔽详情。
            bindTodoRow(
                context, views, prefs, openTodoPage, 1,
                intArrayOf(R.id.widget_todo_row_1, R.id.widget_todo_item_1),
                R.id.widget_todo_done_1
            )
            bindTodoRow(
                context, views, prefs, openTodoPage, 2,
                intArrayOf(R.id.widget_todo_row_2, R.id.widget_todo_item_2),
                R.id.widget_todo_done_2
            )
            bindTodoRow(
                context, views, prefs, openTodoPage, 3,
                intArrayOf(R.id.widget_todo_row_3, R.id.widget_todo_item_3),
                R.id.widget_todo_done_3
            )
            // 容量优先：正文 ListView 与空状态互斥，旧三行容器永远不参与可见布局。
            applyCapacity(views, profile, todoCount, items.size)

            // 集合：每个实例 + 方向一个独立 adapter 身份；模板负责把行 fill-in 变成详情跳转。
            val landscape = context.resources.configuration.orientation ==
                Configuration.ORIENTATION_LANDSCAPE
            views.setRemoteAdapter(
                R.id.widget_todo_list,
                DuoyiWidgetCollectionService.todoAdapterIntent(
                    context = context,
                    appWidgetId = id,
                    providerName = navTarget?.providerName ?: this::class.java.name,
                    landscape = landscape,
                ),
            )
            DuoyiWidgetNavigation.collectionTemplate(
                context,
                navTarget,
                DuoyiWidgetCollectionService.KIND_TODO,
            )?.let { views.setPendingIntentTemplate(R.id.widget_todo_list, it) }

            val tabTodo = prefs.getString("nav_todo", "待办") ?: "待办"
            val tabHabit = prefs.getString("nav_habit", "习惯") ?: "习惯"
            val tabCalendar = prefs.getString("nav_calendar", "日历") ?: "日历"
            val tabFocus = prefs.getString("nav_focus", "专注") ?: "专注"
            views.setTextViewText(R.id.widget_todo_nav_todo, tabTodo)
            views.setTextViewText(R.id.widget_todo_nav_habit, tabHabit)
            views.setTextViewText(R.id.widget_todo_nav_calendar, tabCalendar)
            views.setTextViewText(R.id.widget_todo_nav_focus, tabFocus)

            // 底部四项直接切换小组件内容；切过页的实例即使 compact 也保留底栏。
            DuoyiWidgetNavigation.bindBottomTabs(
                context = context,
                views = views,
                prefs = prefs,
                target = navTarget,
                appWidgetId = id,
                navId = R.id.widget_todo_bottom_nav,
                // 核心四页底栏始终可见；实例内切页行为仍由 bindBottomTabs 保留。
                defaultNavVisibility = View.VISIBLE,
                tabViewIds = mapOf(
                    DuoyiWidgetNavigation.TAB_TODO to R.id.widget_todo_nav_todo,
                    DuoyiWidgetNavigation.TAB_HABIT to R.id.widget_todo_nav_habit,
                    DuoyiWidgetNavigation.TAB_CALENDAR to R.id.widget_todo_nav_calendar,
                    DuoyiWidgetNavigation.TAB_FOCUS to R.id.widget_todo_nav_focus,
                ),
            )
            // 分段底栏必须最后上色：选中白/深灰小圆角 + accent 字，未选清背景防残留。
            DuoyiWidgetTheme.applySegmentedNavigation(
                context = context,
                views = views,
                prefs = prefs,
                tabViewIds = intArrayOf(
                    R.id.widget_todo_nav_todo,
                    R.id.widget_todo_nav_habit,
                    R.id.widget_todo_nav_calendar,
                    R.id.widget_todo_nav_focus,
                ),
                selectedId = R.id.widget_todo_nav_todo,
                profile = profile,
            )
            // “+ 添加”需要完整表单：收起按钮（资源 ID 保留），编辑从待办页进入。
            views.setViewVisibility(R.id.widget_todo_quick_add, View.GONE)

                views
            }
            // 先通知集合刷新，再应用包含 adapter/template 的 RemoteViews；通知放在 update 后
            // 会让部分 Launcher 将 ListView 重置回首项。
            appWidgetManager.notifyAppWidgetViewDataChanged(id, R.id.widget_todo_list)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    /**
     * 正文（ListView）与空状态二选一；旧三行容器 / 汇总行 / 旧完成圈始终 GONE。
     *
     * 空状态内部仍按预算整块取舍：主文案 > hint > 装饰 check，短高度先放弃装饰，
     * 不裁文字、不产生空白行。
     */
    private fun applyCapacity(
        views: RemoteViews,
        profile: DuoyiWidgetProfile,
        todoCount: Int,
        itemCount: Int,
    ) {
        val padded = profile.withPadding(profile.applePaddingDp)
        val paddingPx = padded.px(padded.paddingDp)
        views.setViewPadding(
            R.id.widget_todo_content,
            paddingPx,
            paddingPx,
            paddingPx,
            paddingPx,
        )
        // 数量 28sp 为主；短实例/大字体降到 26sp，仍给底栏留足空间。
        val countSp = if (padded.isShort || padded.fontScale > DuoyiWidgetLayout.TIGHT_FONT_SCALE) {
            COUNT_COMPACT_SP
        } else {
            COUNT_SP
        }
        views.setTextViewTextSize(R.id.widget_todo_count, TypedValue.COMPLEX_UNIT_SP, countSp)
        val budget = padded.budget(
            padded.headerDp(max(countSp, DuoyiWidgetLayout.MODULE_TITLE_SP)) +
                BODY_MARGIN_DP +
                DuoyiWidgetLayout.NAV_MARGIN_DP +
                padded.navDp(padded.navLabelSp)
        )
        // 数量与真实条目任一为 0 都按空态处理：绝不显示"0 项 + 空列表"的空壳。
        val empty = todoCount <= 0 || itemCount <= 0
        views.setViewVisibility(
            R.id.widget_todo_list,
            if (empty) View.GONE else View.VISIBLE
        )
        views.setViewVisibility(
            R.id.widget_todo_empty_group,
            if (empty) View.VISIBLE else View.GONE
        )
        // 旧三行容器与旧汇总行不参与可见布局（ID/类型继续保留给升级兼容）。
        views.setViewVisibility(R.id.widget_todo_data_list, View.GONE)
        ROW_IDS.forEach { views.setViewVisibility(it, View.GONE) }
        views.setViewVisibility(R.id.widget_todo_today_summary, View.GONE)
        if (!empty) return

        val titleLineDp = padded.lineDp(EMPTY_TITLE_SP)
        val titleShown = budget.reserve(titleLineDp)
        // 第二行只在整行放得下时开放，避免空文案被裁。
        val secondLine = titleShown && budget.reserve(titleLineDp)
        views.setInt(
            R.id.widget_todo_empty_title,
            "setMaxLines",
            if (secondLine) 2 else 1
        )
        views.setViewVisibility(
            R.id.widget_todo_empty_title,
            if (titleShown) View.VISIBLE else View.GONE
        )
        val hintShown = titleShown &&
            budget.reserve(EMPTY_HINT_GAP_DP + padded.lineDp(EMPTY_HINT_SP))
        views.setViewVisibility(
            R.id.widget_todo_empty_hint,
            if (hintShown) View.VISIBLE else View.GONE
        )
        val checkShown = titleShown && budget.reserve(EMPTY_CHECK_GAP_DP + EMPTY_CHECK_DP)
        views.setViewVisibility(
            R.id.widget_todo_empty_check,
            if (checkShown) View.VISIBLE else View.GONE
        )
    }

    private fun appPageIntent(context: Context, uri: Uri): PendingIntent {
        return HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri)
    }

    private fun bindTodoRow(
        context: Context,
        views: RemoteViews,
        prefs: SharedPreferences,
        openTodoPage: PendingIntent,
        index: Int,
        rowViewIds: IntArray,
        doneViewId: Int
    ) {
        val todoId = prefs.getString("todo_top3_${index}_id", "") ?: ""
        if (todoId.isBlank()) {
            views.setViewVisibility(doneViewId, View.GONE)
            // 没有有效 ID 的占位行：整行进入 App 待办页。
            rowViewIds.forEach { views.setOnClickPendingIntent(it, openTodoPage) }
            return
        }
        val encodedTodoId = Uri.encode(todoId)
        views.setViewVisibility(doneViewId, View.GONE)
        // 具体任务（含原完成圈）进入 App 详情：不带 confirm 参数，也不在后台直接完成。
        val todoDetailPage = appPageIntent(context, Uri.parse("duoyi://todo/$encodedTodoId"))
        rowViewIds.forEach { views.setOnClickPendingIntent(it, todoDetailPage) }
        views.setOnClickPendingIntent(doneViewId, todoDetailPage)
    }

    private fun cleanTodoTitle(raw: String): String = DuoyiWidgetCollections.cleanTodoTitle(raw)

    /**
     * 读今日待办：新 key 存在就只用它（解析为空也不回退）；只有 key 完全缺失时才用
     * 三条旧键 + 非空 ID 回退。与集合 factory 共用同一份解析逻辑。
     */
    private fun readTodoItems(prefs: SharedPreferences): List<DuoyiTodoWidgetItem> {
        val key = DuoyiWidgetCollections.KEY_TODO_ITEMS_JSON
        val newJson = if (prefs.contains(key)) prefs.getString(key, null) else null
        val prefix = DuoyiWidgetCollections.KEY_TODO_LEGACY_TITLE_PREFIX
        val titles = (1..3).map { index -> prefs.getString("$prefix$index", null) }
        val ids = (1..3).map { index ->
            prefs.getString(
                "$prefix$index${DuoyiWidgetCollections.KEY_TODO_LEGACY_ID_SUFFIX}",
                null,
            )
        }
        return DuoyiWidgetCollections.todoItems(newJson, titles, ids)
    }

    companion object {

        private const val BODY_MARGIN_DP = 8f
        private const val COUNT_SP = 28f
        private const val COUNT_COMPACT_SP = 26f
        private const val EMPTY_TITLE_SP = 14f
        private const val EMPTY_HINT_SP = 11f
        private const val EMPTY_CHECK_DP = 26f
        private const val EMPTY_CHECK_GAP_DP = 8f
        private const val EMPTY_HINT_GAP_DP = 4f
        private const val DEFAULT_EMPTY_TITLE = "今天没有未完成待办"
        private const val DEFAULT_EMPTY_HINT = "打开待办，安排下一件事"
        private val ROW_IDS = intArrayOf(
            R.id.widget_todo_row_1,
            R.id.widget_todo_row_2,
            R.id.widget_todo_row_3,
        )

        /** Trigger update from Flutter via HomeWidget.updateWidget or package upgrade. */
        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "todo")
        }
    }
}
