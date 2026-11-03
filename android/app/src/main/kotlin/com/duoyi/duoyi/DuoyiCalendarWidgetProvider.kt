package com.duoyi.duoyi

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Typeface
import android.net.Uri
import android.text.StaticLayout
import android.text.TextPaint
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import java.time.LocalDate
import java.time.YearMonth
import kotlin.math.max
import org.json.JSONArray
import org.json.JSONObject

/**
 * "月历" 小组件（单月、原尺寸）。
 *
 * 正文是应用本月的完整 4~6 周网格：`widget_calendar_weekday_row` 写 7 个星期标签，
 * `widget_calendar_month_grid` 里按周 addView `duoyi_calendar_week_row`，每行等分
 * 剩余高度；每格是 `duoyi_calendar_day_cell`（日期在下、事项数角标在上，互不重叠）。
 * 1 日到 lastDay 全显示，绝不按周截断，也绝不为放下而删周。
 *
 * 横向翻月未实现：RemoteViews 没有标准水平滑动手势控件（ViewFlipper 虽可 inflate，
 * 但 showNext/showPrevious 不是 @RemotableViewMethod；ViewPager 不在允许的远程视图
 * 类里），因此这里不伪装手势、也不放左右箭头。
 *
 * "今天" 是本地按钮：只重绘本实例的应用本月，不启动 App、不切 tab。
 * 纵向集合（`widget_calendar_list` + CalendarCollectionFactory）只保留兼容：
 * ID/类型与 renderMonthItem 都还在，但本小组件不再绑定 adapter，ListView 隐藏且
 * 不占高度。
 *
 * 数据协议（Dart 侧写入 HomeWidget prefs，语义未变）：
 * - `calendar_day_counts_json`：`{"YYYY-MM-DD": 非负整数}`，该天事项数；
 * - `calendar_timezone`：应用 IANA 时区，决定"今天"高亮；
 * - `calendar_weekdays_json`：周一至周日 7 个标签的 JSON 数组；
 * - `calendar_day_count_label`：含 `{date}` / `{count}` 占位符的无障碍模板；
 * - `calendar_month_title`：月份标题模板（zh `{year}年{month}月` / en `{year}-{month}`）。
 */
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

        // 时区与"今天"在整个刷新里只读一次：横竖两套 RemoteViews 与所有实例
        // 使用同一个 today，跨午夜刷新时不会出现两个不同的"今天"。
        val zone = DuoyiCalendarMonth.zoneOrDefault(prefs.getString(KEY_TIMEZONE, null))
        val today = LocalDate.now(zone)
        // 单月小组件只画"应用本月"：月份与标题都取自同一个 today。
        val month = YearMonth.from(today)
        val weekdayLabels = readWeekdayLabels(prefs)
        val dayCounts = readDayCounts(prefs)
        val monthTitle =
            DuoyiCalendarMonth.formatMonthTitle(monthTitleTemplate(prefs), month.atDay(1))
        val countLabelTemplate = dayCountLabelTemplate(prefs)

        appWidgetIds.forEach { id ->
            DuoyiWidgetProviderRegistry.styleForProvider(this::class.java.name)?.let { style ->
                DuoyiWidgetDisplayMode.saveForWidgetIfMissing(prefs, id, style)
            }
            val navTarget = DuoyiWidgetNavigation.targetFor(context, id)
            // 同时产出横屏 / 竖屏两套 RemoteViews（宿主旋转后直接复用对应方向）。
            val views = DuoyiWidgetLayout.forOrientations(context) { context ->
                val views = RemoteViews(context.packageName, R.layout.duoyi_calendar_widget)
                val profile = DuoyiWidgetLayout.resolve(context, appWidgetManager, id)
                DuoyiWidgetTheme.applyContainer(
                    context = context,
                    views = views,
                    prefs = prefs,
                    rootId = R.id.widget_calendar_root,
                    navId = R.id.widget_calendar_bottom_nav,
                    appWidgetId = id,
                    appleStyle = true,
                )
                DuoyiWidgetTheme.applyTextColors(
                    views,
                    prefs,
                    primaryIds = intArrayOf(
                        R.id.widget_calendar_summary,
                        R.id.widget_calendar_today_button,
                    ),
                    bodyIds = intArrayOf(
                        R.id.widget_calendar_month,
                        R.id.widget_calendar_grid,
                    ),
                    mutedIds = WEEKDAY_VIEW_IDS,
                    appleStyle = true,
                )
                // 「今天」用轻灰 track 小圆角 + accent 字，和分段底栏同一套语言。
                DuoyiWidgetTheme.applyButtonSurfaces(
                    views,
                    prefs,
                    secondaryIds = intArrayOf(R.id.widget_calendar_today_button),
                    appleStyle = true,
                )
                // 左上品牌文字已由 logo 图片取代：旧标题任何密度下都保持隐藏。
                views.setViewVisibility(R.id.widget_calendar_title, View.GONE)
                views.setTextViewText(
                    R.id.widget_calendar_title,
                    prefs.getString("brand_app_title", "多仪") ?: "多仪"
                )
                // 顶部粒度回到"应用本月"的整月标题（不再是集合项自己的标题）。
                views.setTextViewText(R.id.widget_calendar_month, monthTitle)
                views.setTextViewText(
                    R.id.widget_calendar_today_button,
                    prefs.getString("widget_today_label", "今天") ?: "今天"
                )
                views.setTextViewText(
                    R.id.widget_calendar_summary,
                    prefs.getString("calendar_month_summary", "本月日期 · 今日已标记")
                        ?: "本月日期 · 今日已标记"
                )

                val tabTodo = prefs.getString("nav_todo", "待办") ?: "待办"
                val tabHabit = prefs.getString("nav_habit", "习惯") ?: "习惯"
                val tabCalendar = prefs.getString("nav_calendar", "日历") ?: "日历"
                val tabFocus = prefs.getString("nav_focus", "专注") ?: "专注"
                views.setTextViewText(R.id.widget_calendar_nav_todo, tabTodo)
                views.setTextViewText(R.id.widget_calendar_nav_habit, tabHabit)
                views.setTextViewText(R.id.widget_calendar_nav_calendar, tabCalendar)
                views.setTextViewText(R.id.widget_calendar_nav_focus, tabFocus)

                // 顶部区域（logo / 模块名 / 星期表头 / 整月网格）进入 App 日历页。
                val openCalendarPage = appPageIntent(context, Uri.parse("duoyi://tab/calendar"))
                intArrayOf(
                    R.id.widget_calendar_root,
                    R.id.widget_brand_logo,
                    R.id.widget_calendar_title,
                    R.id.widget_calendar_month,
                    R.id.widget_calendar_grid,
                    R.id.widget_calendar_summary,
                    R.id.widget_calendar_today_button,
                    R.id.widget_calendar_weekday_row,
                    R.id.widget_calendar_month_grid,
                    R.id.widget_calendar_weekday_0,
                    R.id.widget_calendar_weekday_1,
                    R.id.widget_calendar_weekday_2,
                    R.id.widget_calendar_weekday_3,
                    R.id.widget_calendar_weekday_4,
                    R.id.widget_calendar_weekday_5,
                    R.id.widget_calendar_weekday_6,
                ).forEach { views.setOnClickPendingIntent(it, openCalendarPage) }
                // 「今天」最后覆盖：本地重绘本实例的应用本月，不启动 App。
                DuoyiWidgetNavigation.bindCalendarToday(
                    context = context,
                    views = views,
                    target = navTarget,
                    viewId = R.id.widget_calendar_today_button,
                )
                // 旧多行文本 / 摘要永远隐藏；纵向集合 ListView 保留 ID/类型但隐藏且
                // 不占高度（不再 setRemoteAdapter），单月内容由 weekday_row + month_grid 承载。
                views.setViewVisibility(R.id.widget_calendar_grid, View.GONE)
                views.setViewVisibility(R.id.widget_calendar_summary, View.GONE)
                views.setViewVisibility(R.id.widget_calendar_list, View.GONE)
                views.setViewVisibility(R.id.widget_calendar_weekday_row, View.VISIBLE)
                views.setViewVisibility(R.id.widget_calendar_month_grid, View.VISIBLE)
                applyHeaderGeometry(views, profile)
                renderSingleMonth(
                    context = context,
                    views = views,
                    profile = profile,
                    grid = DuoyiCalendarMonth.build(month, today, dayCounts),
                    weekdayLabels = weekdayLabels,
                    countLabelTemplate = countLabelTemplate,
                    openPage = openCalendarPage,
                )

                // 底部四项直接切换小组件内容。
                DuoyiWidgetNavigation.bindBottomTabs(
                    context = context,
                    views = views,
                    prefs = prefs,
                    target = navTarget,
                    appWidgetId = id,
                    navId = R.id.widget_calendar_bottom_nav,
                    // 核心四页底栏始终可见；实例内切页行为仍由 bindBottomTabs 保留。
                    defaultNavVisibility = View.VISIBLE,
                    tabViewIds = mapOf(
                        DuoyiWidgetNavigation.TAB_TODO to R.id.widget_calendar_nav_todo,
                        DuoyiWidgetNavigation.TAB_HABIT to R.id.widget_calendar_nav_habit,
                        DuoyiWidgetNavigation.TAB_CALENDAR to R.id.widget_calendar_nav_calendar,
                        DuoyiWidgetNavigation.TAB_FOCUS to R.id.widget_calendar_nav_focus,
                    ),
                )
                // 分段底栏最后上色：选中白/深灰小圆角 + accent 字，未选清背景防残留。
                DuoyiWidgetTheme.applySegmentedNavigation(
                    context = context,
                    views = views,
                    prefs = prefs,
                    tabViewIds = intArrayOf(
                        R.id.widget_calendar_nav_todo,
                        R.id.widget_calendar_nav_habit,
                        R.id.widget_calendar_nav_calendar,
                        R.id.widget_calendar_nav_focus,
                    ),
                    selectedId = R.id.widget_calendar_nav_calendar,
                    profile = profile,
                )

                views
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    /** 头部只保留 logo + 模块名 + 「今天」：按实例真实内边距调整内容区 padding。 */
    private fun applyHeaderGeometry(views: RemoteViews, profile: DuoyiWidgetProfile) {
        val padded = profile.withPadding(profile.calendarPaddingDp)
        val paddingPx = padded.px(padded.paddingDp)
        views.setViewPadding(
            R.id.widget_calendar_content,
            paddingPx,
            paddingPx,
            paddingPx,
            paddingPx,
        )
    }

    private fun appPageIntent(context: Context, uri: Uri): PendingIntent {
        return HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri)
    }

    companion object {

        // 与 duoyi_calendar_widget.xml 一致的几何参数。
        private const val KEY_DAY_COUNTS = "calendar_day_counts_json"
        private const val KEY_TIMEZONE = "calendar_timezone"
        private const val KEY_WEEKDAYS = "calendar_weekdays_json"
        private const val KEY_DAY_COUNT_LABEL = "calendar_day_count_label"
        private const val KEY_MONTH_TITLE = "calendar_month_title"
        /** 集合标题行 11sp、星期表头 8.5sp（与 item XML 初值一致）。 */
        private const val MONTH_CAPTION_SP = 11f
        private const val MONTH_WEEKDAY_SP = 8.5f
        private const val MONTH_CAPTION_MARGIN_DP = 3f
        private const val MONTH_WEEKDAY_MARGIN_DP = 2f

        /** 单月网格：星期表头 8.5sp，短实例/大字体沿用同一紧凑档。 */
        private const val WEEKDAY_SP = 8.5f
        private const val WEEKDAY_COMPACT_SP = 8.5f
        private const val WEEKDAY_MARGIN_DP = 4f
        private const val GRID_MARGIN_DP = 2f
        /** 「今天」按钮 minHeight=22dp，顶栏高度至少这么高。 */
        private const val TODAY_BUTTON_MIN_DP = 22f

        /** 单月格子里角标自身的上边距（与 duoyi_calendar_day_cell.xml 的 1dp 一致）。 */
        private const val BADGE_TOP_MARGIN_DP = 1f

        /**
         * 集合项里月份标题占用的整块高度（dp）。service 用它从可见高度里扣除。
         */
        fun monthCaptionHeightDp(profile: DuoyiWidgetProfile): Float =
            profile.lineDp(MONTH_CAPTION_SP) + MONTH_CAPTION_MARGIN_DP

        /** 集合项里星期表头占用的整块高度（dp）。 */
        fun monthWeekdayHeightDp(profile: DuoyiWidgetProfile): Float =
            profile.lineDp(MONTH_WEEKDAY_SP) + MONTH_WEEKDAY_MARGIN_DP

        /**
         * 纯数字行高（dp，含 fontScale 与 density）：日期/角标只含 ASCII 数字，
         * 分别实测普通与粗体，避免套用中文表头行高。
         */
        fun numericLineDp(context: Context, sp: Float): Float {
            val metrics = context.resources.displayMetrics
            val density = metrics.density.takeIf { it.isFinite() && it > 0f } ?: 1f
            val paint = TextPaint().apply {
                textSize = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, sp, metrics)
                typeface = Typeface.DEFAULT
            }
            val sample = "0123456789"
            fun heightPx(): Int = StaticLayout.Builder
                .obtain(sample, 0, sample.length, paint, 100000)
                .setIncludePad(false)
                .setMaxLines(1)
                .build().height
            val regular = heightPx()
            paint.typeface = Typeface.DEFAULT_BOLD
            return max(regular, heightPx()).toFloat() / density
        }

        /**
         * 单月网格可用高度（dp）：内容区高度扣除顶栏、星期表头行、网格上边距、
         * 底栏上边距与底栏本身。与 duoyi_calendar_widget.xml 的 margin / weight 一一对应，
         * 供 [DuoyiCalendarMonth.chooseTextSizes] 用真实完整 weekCount 判字
         * （标准 5 周 11/8sp、6 周 10/7sp；放不下再按真实行高等比缩小）。
         */
        fun singleMonthGridHeightDp(profile: DuoyiWidgetProfile, weekdaySp: Float): Float {
            val padded = profile.withPadding(profile.calendarPaddingDp)
            val header = max(
                padded.headerDp(DuoyiWidgetLayout.MODULE_TITLE_SP),
                TODAY_BUTTON_MIN_DP,
            )
            val weekday = padded.lineDp(weekdaySp) + WEEKDAY_MARGIN_DP
            val fixed = header +
                weekday +
                GRID_MARGIN_DP +
                DuoyiWidgetLayout.NAV_MARGIN_DP +
                padded.navDp(padded.navLabelSp)
            return (padded.contentHeightDp - fixed).coerceAtLeast(0f)
        }

        /** 星期表头字号：标准 9sp；短实例 / 大字体沿用紧凑档 8.5sp。 */
        fun weekdaySpFor(profile: DuoyiWidgetProfile): Float =
            if (profile.isShort || profile.fontScale > DuoyiWidgetLayout.TIGHT_FONT_SCALE) {
                WEEKDAY_COMPACT_SP
            } else {
                WEEKDAY_SP
            }

        /**
         * 单月格子的字号：先取模型标准档（<=5 周日期 11sp / 角标 8sp，6 周 10sp / 7sp），
         * 按真实字体度量检查整月 [weekCount] 行是否放得下；只有确实放不下才回退
         * [DuoyiCalendarMonth.chooseTextSizes] 等比缩小，绝不删周。
         *
         * 单月格子是 FrameLayout：角标 top|end、日期 bottom|center，两者在垂直方向
         * 重叠，因此每行需要的高度是 `max(日期行高, 角标行高 + 角标上边距)`，
         * 而不是日期行 + 角标行的简单相加。
         */
        fun singleMonthTextSizes(
            context: Context,
            profile: DuoyiWidgetProfile,
            weekCount: Int,
            weekdaySp: Float,
        ): DuoyiCalendarTextSizes {
            val preferred = DuoyiCalendarMonth.preferredTextSizes(weekCount)
            if (weekCount <= 0) return preferred
            val availableDp = singleMonthGridHeightDp(profile, weekdaySp)
            val rowNeededDp = max(
                numericLineDp(context, preferred.dateSp),
                numericLineDp(context, preferred.badgeSp) + BADGE_TOP_MARGIN_DP,
            )
            if (weekCount * rowNeededDp <= availableDp + DuoyiWidgetLayout.EPSILON_DP) {
                return preferred
            }
            return DuoyiCalendarMonth.chooseTextSizes(
                availableDp = availableDp,
                weekCount = weekCount,
                badgeGapDp = DuoyiCalendarMonth.BADGE_GAP_DP,
                lineDp = { sp -> numericLineDp(context, sp) },
            )
        }

        /**
         * 单月小组件正文：星期表头 7 标签 + `widget_calendar_month_grid` 里按周 addView
         * 的 `duoyi_calendar_week_row`，每格 `duoyi_calendar_day_cell`。
         *
         * 行高由 weight 等分（weekCount 行吃掉底栏以上全部剩余高度），格子内部日期在下、
         * 角标在上；日期 / 角标字号按真实完整 weekCount 与真实可用高度选择，绝不删周，
         * 也不截断 1..lastDay。格子与根视图只做 App 日历深链（[openPage]），
         * 不加任何组件内业务动作。
         */
        fun renderSingleMonth(
            context: Context,
            views: RemoteViews,
            profile: DuoyiWidgetProfile,
            grid: DuoyiCalendarMonthGrid,
            weekdayLabels: List<String>,
            countLabelTemplate: String?,
            openPage: PendingIntent,
        ) {
            val weekdaySp = weekdaySpFor(profile)
            WEEKDAY_VIEW_IDS.forEachIndexed { index, id ->
                views.setTextViewText(
                    id,
                    weekdayLabels.getOrElse(index) {
                        DuoyiCalendarMonth.FALLBACK_WEEKDAY_LABELS[index]
                    },
                )
                views.setTextViewTextSize(id, TypedValue.COMPLEX_UNIT_SP, weekdaySp)
            }
            val sizes = singleMonthTextSizes(
                context = context,
                profile = profile,
                weekCount = grid.weekCount,
                weekdaySp = weekdaySp,
            )
            val apple = DuoyiWidgetTheme.applePalette(
                DuoyiWidgetTheme.read(HomeWidgetPlugin.getData(context)),
            )
            views.removeAllViews(R.id.widget_calendar_month_grid)
            grid.rows.forEach { row ->
                val rowViews = RemoteViews(context.packageName, R.layout.duoyi_calendar_week_row)
                row.forEach { cell ->
                    val cellViews = RemoteViews(
                        context.packageName,
                        R.layout.duoyi_calendar_day_cell,
                    )
                    applySingleMonthCell(
                        cellViews = cellViews,
                        cell = cell,
                        apple = apple,
                        countLabelTemplate = countLabelTemplate,
                        dateSp = sizes.dateSp,
                        badgeSp = sizes.badgeSp,
                        openPage = openPage,
                    )
                    rowViews.addView(R.id.widget_calendar_week_row, cellViews)
                }
                views.addView(R.id.widget_calendar_month_grid, rowViews)
            }
        }

        /** 单月格子：日期固定在下半区、事项数角标在上半区右侧，0 事项时角标 GONE。 */
        private fun applySingleMonthCell(
            cellViews: RemoteViews,
            cell: DuoyiCalendarDayCell,
            apple: DuoyiApplePalette,
            countLabelTemplate: String?,
            dateSp: Float,
            badgeSp: Float,
            openPage: PendingIntent,
        ) {
            val cellId = R.id.widget_calendar_day_cell
            val numberId = R.id.widget_calendar_day_number
            val badgeId = R.id.widget_calendar_day_badge
            cellViews.setOnClickPendingIntent(cellId, openPage)
            cellViews.setTextViewTextSize(numberId, TypedValue.COMPLEX_UNIT_SP, dateSp)
            if (cell.isBlank) {
                cellViews.setViewVisibility(numberId, View.INVISIBLE)
                cellViews.setViewVisibility(badgeId, View.GONE)
                cellViews.setTextViewText(numberId, "")
                cellViews.setTextViewText(badgeId, "")
                cellViews.setContentDescription(cellId, "")
                return
            }
            cellViews.setViewVisibility(numberId, View.VISIBLE)
            cellViews.setTextViewText(numberId, (cell.dayOfMonth ?: 0).toString())
            cellViews.setTextColor(numberId, if (cell.isToday) apple.accent else apple.label)
            if (cell.hasBadge) {
                // 正数精确显示（不做 99+），0 事项隐藏角标。
                cellViews.setViewVisibility(badgeId, View.VISIBLE)
                cellViews.setTextViewText(badgeId, cell.count.toString())
                cellViews.setTextViewTextSize(badgeId, TypedValue.COMPLEX_UNIT_SP, badgeSp)
                cellViews.setTextColor(badgeId, apple.accent)
            } else {
                cellViews.setViewVisibility(badgeId, View.GONE)
                cellViews.setTextViewText(badgeId, "")
            }
            cellViews.setContentDescription(
                cellId,
                DuoyiCalendarMonth.formatCountLabel(
                    countLabelTemplate,
                    cell.isoDate ?: "",
                    cell.count,
                ),
            )
        }

        /**
         * 构造"一整月"集合项的 RemoteViews（service 的 factory 复用）。
         *
         * 复用 [DuoyiCalendarMonth.build] 与 [DuoyiCalendarMonth.formatMonthTitle]：
         * 月标题按该月自身计算，`isToday` 只在应用时区的当天为 true，其他月份的 1 日
         * 不会被误高亮。所有 4~6 周都在，绝不删周。
         */
        fun renderMonthItem(
            context: Context,
            month: YearMonth,
            today: LocalDate,
            counts: Map<String, Int>,
            weekdayLabels: List<String>,
            monthTitleTemplate: String?,
            countLabelTemplate: String?,
            dateSp: Float,
            badgeSp: Float,
        ): RemoteViews {
            val grid = DuoyiCalendarMonth.build(month, today, counts)
            val views = RemoteViews(context.packageName, R.layout.duoyi_widget_calendar_month_item)
            val theme = DuoyiWidgetTheme.read(HomeWidgetPlugin.getData(context))
            val apple = DuoyiWidgetTheme.applePalette(theme)
            views.setTextViewText(
                R.id.widget_calendar_month_item_title,
                DuoyiCalendarMonth.formatMonthTitle(monthTitleTemplate, month.atDay(1)),
            )
            views.setTextColor(R.id.widget_calendar_month_item_title, apple.label)
            views.setTextViewTextSize(
                R.id.widget_calendar_month_item_title,
                TypedValue.COMPLEX_UNIT_SP,
                MONTH_CAPTION_SP,
            )
            MONTH_WEEKDAY_IDS.forEachIndexed { index, id ->
                views.setTextViewText(id, weekdayLabels[index])
                views.setTextColor(id, apple.secondary)
                views.setTextViewTextSize(
                    id,
                    TypedValue.COMPLEX_UNIT_SP,
                    MONTH_WEEKDAY_SP,
                )
            }
            views.removeAllViews(R.id.widget_calendar_month_grid)
            // 每行固定为"日期行 + 角标行 + 间隔"，0 事项的日子行高也不塌陷。
            val density = context.resources.displayMetrics.density
                .takeIf { it.isFinite() && it > 0f } ?: 1f
            val cellMinHeightPx = (
                numericLineDp(context, dateSp) +
                    numericLineDp(context, badgeSp) +
                    DuoyiCalendarMonth.BADGE_GAP_DP
                ) * density
            val cellMinHeight = cellMinHeightPx.toInt().coerceAtLeast(1)
            grid.rows.forEach { row ->
                val rowViews = RemoteViews(
                    context.packageName,
                    R.layout.duoyi_widget_calendar_week_row,
                )
                row.forEach { cell ->
                    val cellViews = RemoteViews(
                        context.packageName,
                        R.layout.duoyi_widget_calendar_day_cell,
                    )
                    cellViews.setInt(
                        R.id.widget_calendar_item_day_cell,
                        "setMinimumHeight",
                        cellMinHeight,
                    )
                    applyDayCell(
                        cellViews = cellViews,
                        cell = cell,
                        apple = apple,
                        countLabelTemplate = countLabelTemplate,
                        dateSp = dateSp,
                        badgeSp = badgeSp,
                    )
                    rowViews.addView(R.id.widget_calendar_week_row_item, cellViews)
                }
                views.addView(R.id.widget_calendar_month_grid, rowViews)
            }
            views.setOnClickFillInIntent(
                R.id.widget_calendar_month_item,
                DuoyiWidgetNavigation.calendarFillInIntent(),
            )
            return views
        }

        /** 单日格：右上方正数角标（0 隐藏），只高亮应用时区里的当天。 */
        private fun applyDayCell(
            cellViews: RemoteViews,
            cell: DuoyiCalendarDayCell,
            apple: DuoyiApplePalette,
            countLabelTemplate: String?,
            dateSp: Float,
            badgeSp: Float,
        ) {
            val cellId = R.id.widget_calendar_item_day_cell
            val numberId = R.id.widget_calendar_item_day_number
            val badgeId = R.id.widget_calendar_item_day_badge
            cellViews.setOnClickFillInIntent(
                cellId,
                DuoyiWidgetNavigation.calendarFillInIntent(),
            )
            if (cell.isBlank) {
                cellViews.setViewVisibility(numberId, View.INVISIBLE)
                cellViews.setViewVisibility(badgeId, View.INVISIBLE)
                cellViews.setTextViewText(numberId, "")
                cellViews.setTextViewText(badgeId, "")
                cellViews.setContentDescription(cellId, "")
                return
            }
            cellViews.setViewVisibility(numberId, View.VISIBLE)
            cellViews.setTextViewText(numberId, (cell.dayOfMonth ?: 0).toString())
            cellViews.setTextViewTextSize(numberId, TypedValue.COMPLEX_UNIT_SP, dateSp)
            cellViews.setTextColor(numberId, if (cell.isToday) apple.accent else apple.label)
            if (cell.hasBadge) {
                // 正数精确显示（不做 99+），0 事项隐藏角标。
                cellViews.setViewVisibility(badgeId, View.VISIBLE)
                cellViews.setTextViewText(badgeId, cell.count.toString())
                cellViews.setTextViewTextSize(badgeId, TypedValue.COMPLEX_UNIT_SP, badgeSp)
                cellViews.setTextColor(badgeId, apple.accent)
            } else {
                cellViews.setViewVisibility(badgeId, View.GONE)
                cellViews.setTextViewText(badgeId, "")
            }
            cellViews.setContentDescription(
                cellId,
                DuoyiCalendarMonth.formatCountLabel(
                    countLabelTemplate,
                    cell.isoDate ?: "",
                    cell.count,
                ),
            )
        }

        private val MONTH_WEEKDAY_IDS = intArrayOf(
            R.id.widget_calendar_month_item_weekday_0,
            R.id.widget_calendar_month_item_weekday_1,
            R.id.widget_calendar_month_item_weekday_2,
            R.id.widget_calendar_month_item_weekday_3,
            R.id.widget_calendar_month_item_weekday_4,
            R.id.widget_calendar_month_item_weekday_5,
            R.id.widget_calendar_month_item_weekday_6,
        )

        /** 单月小组件顶部的旧星期表头（XML 里保留 7 个 TextView）。 */
        private val WEEKDAY_VIEW_IDS = intArrayOf(
            R.id.widget_calendar_weekday_0,
            R.id.widget_calendar_weekday_1,
            R.id.widget_calendar_weekday_2,
            R.id.widget_calendar_weekday_3,
            R.id.widget_calendar_weekday_4,
            R.id.widget_calendar_weekday_5,
            R.id.widget_calendar_weekday_6,
        )

        /** `calendar_day_counts_json` → canonical ISO key 的计数表。 */
        fun readDayCounts(prefs: SharedPreferences): Map<String, Int> {
            val raw = prefs.getString(KEY_DAY_COUNTS, null)?.trim().orEmpty()
            if (raw.isEmpty()) return emptyMap()
            return runCatching {
                val json = JSONObject(raw)
                val counts = HashMap<String, Int>(json.length())
                val keys = json.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    val value = json.optInt(key, 0)
                    counts[key] = if (value > 0) value else 0
                }
                counts
            }.getOrElse { emptyMap() }
        }

        /** `calendar_weekdays_json` → 恰好 7 个标签；缺失/缺位回退中文"一..日"。 */
        fun readWeekdayLabels(prefs: SharedPreferences): List<String> {
            val raw = prefs.getString(KEY_WEEKDAYS, null)?.trim().orEmpty()
            if (raw.isEmpty()) return DuoyiCalendarMonth.normalizeWeekdayLabels(null)
            val parsed = runCatching {
                val array = JSONArray(raw)
                (0 until array.length()).map { index -> array.optString(index, "") }
            }.getOrNull()
            return DuoyiCalendarMonth.normalizeWeekdayLabels(parsed)
        }

        fun dayCountLabelTemplate(prefs: SharedPreferences): String? =
            prefs.getString(KEY_DAY_COUNT_LABEL, null)

        fun monthTitleTemplate(prefs: SharedPreferences): String? =
            prefs.getString(KEY_MONTH_TITLE, null)

        /** Trigger update from Flutter via HomeWidget.updateWidget or package upgrade. */
        fun requestUpdate(context: Context) {
            DuoyiWidgetProviderRegistry.requestUpdateForKind(context, "calendar")
        }
    }
}
