package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import java.time.LocalDate
import java.time.YearMonth
import kotlin.math.max

/**
 * 待办 / 月历两个 framework 集合组件共用的 [RemoteViewsService]。
 *
 * 协议与边界：
 * - 每个实例 + 方向是一个独立的 Intent 身份（scheme `duoyi-widget-collection`），
 *   横竖两套 RemoteViews 各用各的 factory 缓存，不会串用对方的度量；
 * - [CollectionSpec.from] 先解析 Intent，再用 [DuoyiWidgetNavigation.targetFor]
 *   校验 appWidgetId 的真实系统归属，最后核对声明的 provider 与 kind。渲染类不能
 *   冒充宿主，无归属 ID 一律返回 0 项工厂；
 * - `onDataSetChanged` 重新读 HomeWidget prefs；`getViewAt` 只构造当前一项，
 *   241 个月绝不预构造 RemoteViews；
 * - 不新增权限 / receiver / 依赖；Manifest 里是 exported=false +
 *   android.permission.BIND_REMOTEVIEWS。
 */
class DuoyiWidgetCollectionService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        val spec = CollectionSpec.from(this, intent)
            ?: return EmptyCollectionFactory()
        val context = orientationContext(this, spec.landscape)
        return when (spec.kind) {
            KIND_TODO -> TodoCollectionFactory(context, spec)
            else -> CalendarCollectionFactory(context, spec)
        }
    }

    companion object {
        const val KIND_TODO = "todo"
        const val KIND_CALENDAR = "calendar"

        /** 待办正文与 header 的 8dp 间距（与 XML marginTop 一致）。 */
        const val TODO_BODY_MARGIN_DP = 8f

        /** 日历列表与 header 的 2dp 间距（与 XML marginTop 一致）。 */
        const val CALENDAR_LIST_MARGIN_DP = 2f

        /** 小号「今天」按钮最小高度 22dp。 */
        const val TODAY_BUTTON_MIN_DP = 22f

        private const val uriScheme = "duoyi-widget-collection"
        private const val queryProvider = "provider"
        private const val queryOrientation = "orientation"
        private const val orientationLandscape = "landscape"
        private const val orientationPortrait = "portrait"

        /** 待办集合的 adapter Intent：data 编码 kind / 实例 / 真实 provider / 方向。 */
        fun todoAdapterIntent(
            context: Context,
            appWidgetId: Int,
            providerName: String,
            landscape: Boolean,
        ): Intent = adapterIntent(context, KIND_TODO, appWidgetId, providerName, landscape)

        /** 月历集合的 adapter Intent；与待办共用同一套校验与身份编码。 */
        fun calendarAdapterIntent(
            context: Context,
            appWidgetId: Int,
            providerName: String,
            landscape: Boolean,
        ): Intent = adapterIntent(context, KIND_CALENDAR, appWidgetId, providerName, landscape)

        private fun adapterIntent(
            context: Context,
            kind: String,
            appWidgetId: Int,
            providerName: String,
            landscape: Boolean,
        ): Intent {
            val data = Uri.Builder()
                .scheme(uriScheme)
                .authority(kind)
                .appendPath(appWidgetId.toString())
                .appendQueryParameter(queryProvider, providerName)
                .appendQueryParameter(
                    queryOrientation,
                    if (landscape) orientationLandscape else orientationPortrait,
                )
                .build()
            return Intent(context, DuoyiWidgetCollectionService::class.java).apply {
                this.data = data
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            }
        }

        /**
         * 列表可见高度（dp）：待办 header 文本 + 8dp 正文间距 + 6dp nav 间距 + 底栏。
         * 与 provider 的整行预算同一套输入，避免两边各算一份。
         */
        fun todoListHeightDp(profile: DuoyiWidgetProfile, headerTextSp: Float): Float {
            val padded = profile.withPadding(profile.applePaddingDp)
            val fixed = padded.headerDp(headerTextSp) +
                TODO_BODY_MARGIN_DP +
                DuoyiWidgetLayout.NAV_MARGIN_DP +
                padded.navDp(padded.navLabelSp)
            return (padded.contentHeightDp - fixed).coerceAtLeast(0f)
        }

        /** 列表可见高度（dp）：日历 header（含「今天」）+ 2dp 间距 + 6dp nav 间距 + 底栏。 */
        fun calendarListHeightDp(profile: DuoyiWidgetProfile): Float {
            val padded = profile.withPadding(profile.calendarPaddingDp)
            val fixed = max(
                padded.headerDp(DuoyiWidgetLayout.MODULE_TITLE_SP), TODAY_BUTTON_MIN_DP,
            ) +
                CALENDAR_LIST_MARGIN_DP +
                DuoyiWidgetLayout.NAV_MARGIN_DP +
                padded.navDp(padded.navLabelSp)
            return (padded.contentHeightDp - fixed).coerceAtLeast(0f)
        }

        /** 只按方向派生配置：度量 / 颜色 / 字体与 provider 对应方向完全一致。 */
        private fun orientationContext(base: Context, landscape: Boolean): Context {
            val configuration = Configuration(base.resources.configuration).apply {
                orientation = if (landscape) {
                    Configuration.ORIENTATION_LANDSCAPE
                } else {
                    Configuration.ORIENTATION_PORTRAIT
                }
            }
            return base.createConfigurationContext(configuration)
        }
    }

    /** 已校验的集合请求：kind + 实例 + 真实 provider + 方向。 */
    data class CollectionSpec(
        val kind: String,
        val appWidgetId: Int,
        val providerName: String,
        val landscape: Boolean,
    ) {
        companion object {
            /**
             * 解析并校验：scheme / kind(host) / 实例 ID 必须合法，声明的 provider 必须
             * 等于系统确认的真实宿主。任何一步失败返回 null（调用方渲染空列表，不会
             * 借用别家实例数据）。
             *
             * 有意不要求"宿主 family == 请求 kind"：4 页可在同一实例内切页，
             * habit / focus / 历史综合实例也可能渲染待办或月历布局，host family 与
             * 当前内容页本来就可以不同；真实归属与声明一致性仍然强制。
             */
            fun from(context: Context, intent: Intent): CollectionSpec? {
                val data = intent.data ?: return null
                if (data.scheme != DuoyiWidgetCollectionService.uriScheme) return null
                val kind = data.host?.takeIf {
                    it == DuoyiWidgetCollectionService.KIND_TODO ||
                        it == DuoyiWidgetCollectionService.KIND_CALENDAR
                } ?: return null
                val appWidgetId = data.lastPathSegment?.toIntOrNull() ?: return null
                if (appWidgetId <= 0) return null
                val declaredProvider = data.getQueryParameter(
                    DuoyiWidgetCollectionService.queryProvider,
                )
                if (declaredProvider.isNullOrBlank()) return null
                // targetFor 只接受系统确认归属、且渲染类不能冒充宿主的实例。
                val target = DuoyiWidgetNavigation.targetFor(context, appWidgetId) ?: return null
                if (target.providerName != declaredProvider) return null
                val landscape = when (
                    data.getQueryParameter(DuoyiWidgetCollectionService.queryOrientation)
                ) {
                    DuoyiWidgetCollectionService.orientationLandscape -> true
                    DuoyiWidgetCollectionService.orientationPortrait -> false
                    else -> return null
                }
                return CollectionSpec(kind, appWidgetId, target.providerName, landscape)
            }
        }
    }

    /** 校验失败时的空工厂：不渲染任何行。 */
    private class EmptyCollectionFactory : RemoteViewsFactory {
        override fun onCreate() {}
        override fun onDataSetChanged() {}
        override fun onDestroy() {}
        override fun getCount(): Int = 0
        override fun getViewAt(position: Int): RemoteViews? = null
        override fun getLoadingView(): RemoteViews? = null
        override fun getViewTypeCount(): Int = 1
        override fun getItemId(position: Int): Long = position.toLong()
        override fun hasStableIds(): Boolean = false
    }

    /** 两个工厂共用的只读上下文 / 偏好 / 几何档案。 */
    private abstract class BaseCollectionFactory(
        protected val context: Context,
        protected val spec: CollectionSpec,
    ) : RemoteViewsFactory {

        protected val prefs: SharedPreferences = HomeWidgetPlugin.getData(context)
        protected var profile: DuoyiWidgetProfile = DuoyiWidgetLayout.resolve(
            context,
            AppWidgetManager.getInstance(context),
            spec.appWidgetId,
        )

        override fun onCreate() {}

        override fun getViewTypeCount(): Int = 1

        override fun getLoadingView(): RemoteViews? = null

        override fun onDestroy() {}

        protected fun refreshProfile() {
            profile = DuoyiWidgetLayout.resolve(
                context, AppWidgetManager.getInstance(context), spec.appWidgetId,
            )
        }
    }

    /** 待办：完整今日未完成列表，一行一条；密度只影响行高与内边距。 */
    private class TodoCollectionFactory(
        context: Context,
        spec: CollectionSpec,
    ) : BaseCollectionFactory(context, spec) {

        private val items = ArrayList<DuoyiTodoWidgetItem>()
        private var markerPrimary = 0
        private var markerSecondary = 0
        private var titleColor = 0
        private var rowMinHeightPx = 0
        private var rowPaddingPx = 0

        override fun onDataSetChanged() {
            refreshProfile()
            val palette = DuoyiWidgetTheme.applePalette(DuoyiWidgetTheme.read(prefs))
            markerPrimary = palette.accent
            markerSecondary = palette.secondary
            titleColor = palette.label
            items.clear()
            items.addAll(readTodoItems())
            // 至少 32dp 的完整单行；大字体时按真实行高继续增高，绝不压成半行。
            val rowMinDp = max(MIN_ROW_HEIGHT_DP, profile.lineDp(TITLE_SP) + TITLE_VERTICAL_MARGIN_DP)
            rowMinHeightPx = profile.px(rowMinDp)
            rowPaddingPx = profile.px(if (profile.isShort) ROW_PADDING_COMPACT_DP else ROW_PADDING_DP)
        }

        override fun getCount(): Int = items.size

        override fun getViewAt(position: Int): RemoteViews? {
            val item = items.getOrNull(position) ?: return null
            val views = RemoteViews(context.packageName, R.layout.duoyi_widget_todo_row)
            views.setTextViewText(R.id.widget_todo_row_title, item.title)
            views.setTextColor(R.id.widget_todo_row_title, titleColor)
            views.setTextViewTextSize(
                R.id.widget_todo_row_title,
                TypedValue.COMPLEX_UNIT_SP,
                TITLE_SP,
            )
            // 轻 marker：Q1/Q2（重要）用 accent，其余用 secondary；不做完成圈。
            val important = item.quadrant == QUADRANT_URGENT_IMPORTANT ||
                item.quadrant == QUADRANT_IMPORTANT
            views.setInt(
                R.id.widget_todo_row_marker,
                "setBackgroundColor",
                if (important) markerPrimary else markerSecondary,
            )
            views.setInt(R.id.widget_todo_row_item, "setMinimumHeight", rowMinHeightPx)
            views.setViewPadding(R.id.widget_todo_row_item, 0, rowPaddingPx, 0, rowPaddingPx)
            // 详情链接完全由本地可信数据构造，data 由 provider 的可变模板填入。
            views.setOnClickFillInIntent(
                R.id.widget_todo_row_item,
                DuoyiWidgetNavigation.todoFillInIntent(item.id),
            )
            return views
        }

        override fun getItemId(position: Int): Long =
            items.getOrNull(position)?.let { DuoyiWidgetCollections.stableTodoItemId(it.id) } ?: 0L

        override fun hasStableIds(): Boolean = true

        /**
         * 新协议优先：`widget_todo_items_json` 存在时只用它，解析为空也绝不回退旧 key。
         * 只有该 key 完全不存在（旧 Dart 尚未推送）时才用三条旧文字 + 非空 ID 回退。
         */
        private fun readTodoItems(): List<DuoyiTodoWidgetItem> {
            val key = DuoyiWidgetCollections.KEY_TODO_ITEMS_JSON
            // null = 新 key 完全不存在；存在则只用它（解析为空也不回退旧任务）。
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
            /** 完整单行的最小高度（dp）。 */
            private const val MIN_ROW_HEIGHT_DP = 32f
            private const val TITLE_SP = 12f
            private const val TITLE_VERTICAL_MARGIN_DP = 12f
            private const val ROW_PADDING_DP = 3f
            private const val ROW_PADDING_COMPACT_DP = 1.5f
            private const val QUADRANT_URGENT_IMPORTANT = 0
            private const val QUADRANT_IMPORTANT = 1
        }
    }

    /** 月历：一项一整月（自身月份标题 + 星期 + 完整 4~6 周），懒构造。 */
    private class CalendarCollectionFactory(
        context: Context,
        spec: CollectionSpec,
    ) : BaseCollectionFactory(context, spec) {

        private var anchor: YearMonth = YearMonth.now()
        private var today: LocalDate = LocalDate.now()
        private var counts: Map<String, Int> = emptyMap()
        private var weekdayLabels: List<String> = DuoyiCalendarMonth.normalizeWeekdayLabels(null)
        private var countLabelTemplate: String? = null
        private var monthTitleTemplate: String? = null
        private var dateSp = DuoyiCalendarMonth.DEFAULT_DATE_SP
        private var badgeSp = DuoyiCalendarMonth.DEFAULT_BADGE_SP
        private var monthHeightPx = profile.px(max(96f, calendarListHeightDp(profile)))

        override fun onDataSetChanged() {
            refreshProfile()
            val zone = DuoyiCalendarMonth.zoneOrDefault(prefs.getString(KEY_TIMEZONE, null))
            today = LocalDate.now(zone)
            counts = DuoyiCalendarWidgetProvider.readDayCounts(prefs)
            weekdayLabels = DuoyiCalendarWidgetProvider.readWeekdayLabels(prefs)
            countLabelTemplate = DuoyiCalendarWidgetProvider.dayCountLabelTemplate(prefs)
            monthTitleTemplate = DuoyiCalendarWidgetProvider.monthTitleTemplate(prefs)
            anchor = DuoyiWidgetNavigation.calendarAnchor(prefs, spec.appWidgetId, today)
            // 整月字号按"6 周也能完整放下"的 viewport 预算选取；短尺寸整体滚动，
            // 绝不删周、绝不裁日期。度量与 provider 的纯数字行高完全一致。
            val monthHeightDp = max(96f, DuoyiWidgetCollectionService.calendarListHeightDp(profile))
            monthHeightPx = profile.px(monthHeightDp)
            val availableDp = monthHeightDp - 10f -
                DuoyiCalendarWidgetProvider.monthCaptionHeightDp(profile) -
                DuoyiCalendarWidgetProvider.monthWeekdayHeightDp(profile)
            val fitted = DuoyiCalendarMonth.chooseTextSizes(
                availableDp = availableDp.coerceAtLeast(0f),
                weekCount = SIX_WEEK_COUNT,
                badgeGapDp = DuoyiCalendarMonth.BADGE_GAP_DP,
                lineDp = { sp -> DuoyiCalendarWidgetProvider.numericLineDp(context, sp) },
            )
            dateSp = fitted.dateSp
            badgeSp = fitted.badgeSp
            scheduleInitialScroll()
        }

        private fun scheduleInitialScroll() {
            val key = "duoyi_widget_calendar_pending_scroll_${spec.appWidgetId}"
            if (!prefs.contains(key)) return
            val actualLandscape = context.applicationContext.resources.configuration.orientation ==
                Configuration.ORIENTATION_LANDSCAPE
            if (actualLandscape != spec.landscape) return
            val index = prefs.getInt(key, -1)
            if (index !in 0 until DuoyiWidgetCollections.CALENDAR_MONTH_COUNT) return
            // 远程 adapter 数据先返回给 Launcher，再补一次定位，避免首次未绑定时丢失。
            Handler(Looper.getMainLooper()).postDelayed({
                if (!prefs.contains(key) || prefs.getInt(key, -1) != index) return@postDelayed
                val target = DuoyiWidgetNavigation.targetFor(context, spec.appWidgetId)
                if (target?.providerName != spec.providerName) return@postDelayed
                prefs.edit().remove(key).apply()
                val scroll = RemoteViews(context.packageName, R.layout.duoyi_calendar_widget)
                scroll.setScrollPosition(R.id.widget_calendar_list, index)
                AppWidgetManager.getInstance(context).partiallyUpdateAppWidget(spec.appWidgetId, scroll)
            }, 750L)
        }

        override fun getCount(): Int = DuoyiWidgetCollections.CALENDAR_MONTH_COUNT

        override fun getLoadingView(): RemoteViews =
            RemoteViews(context.packageName, R.layout.duoyi_widget_calendar_month_item).apply {
                setInt(R.id.widget_calendar_month_item, "setMinimumHeight", monthHeightPx)
            }

        override fun getViewAt(position: Int): RemoteViews? {
            val month = DuoyiWidgetCollections.monthAt(anchor, position) ?: return null
            // 复用 provider 的整月渲染原语：同一套 cell / 角标 / 无障碍逻辑。
            return DuoyiCalendarWidgetProvider.renderMonthItem(
                context = context,
                month = month,
                today = today,
                counts = counts,
                weekdayLabels = weekdayLabels,
                monthTitleTemplate = monthTitleTemplate,
                countLabelTemplate = countLabelTemplate,
                dateSp = dateSp,
                badgeSp = badgeSp,
            ).apply {
                setInt(R.id.widget_calendar_month_item, "setMinimumHeight", monthHeightPx)
            }
        }

        override fun getItemId(position: Int): Long {
            val month = DuoyiWidgetCollections.monthAt(anchor, position) ?: return position.toLong()
            return DuoyiWidgetCollections.monthItemId(month)
        }

        override fun hasStableIds(): Boolean = true

        companion object {
            private const val KEY_TIMEZONE = "calendar_timezone"
            /** 字号统一按 6 周（最高月份）预算，任何月份都完整。 */
            private const val SIX_WEEK_COUNT = 6
        }
    }
}
