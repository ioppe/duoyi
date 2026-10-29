package com.duoyi.duoyi

import android.os.Build
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import java.time.LocalDate
import java.time.YearMonth
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * 4 个核心内容页（待办 / 习惯 / 日历 / 专注）在桌面小组件内部的本地切换器。
 *
 * 边界：
 * - 只做原生切页：不发 Activity（不打开 App），也不触发 Flutter 后台动作回调；
 * - 每个实例的 tab 和“真实拥有者 provider”写在 home_widget prefs 的独立键里，
 *   不写业务 JSON、账号信息或应用内全局导航状态；
 * - 旧完成 / 打卡 / 专注后台动作继续由 Flutter 兼容；当前上方入口进入 App；
 *
 * 广播目标必须来自系统确认的真实宿主：优先 getAppWidgetInfo，暂缺时核验
 * getAppWidgetIds 的实例归属；当前内容页渲染类不能作为物理宿主。
 */
object DuoyiWidgetNavigation {
    const val ACTION_NAVIGATE = "com.duoyi.duoyi.action.WIDGET_NAVIGATE"
    const val ACTION_REFRESH = "com.duoyi.duoyi.action.WIDGET_REFRESH"
    /** 「今天」：只在同一个实例里把月历列表滚回应用本月，不启动 App。 */
    const val ACTION_CALENDAR_TODAY = "com.duoyi.duoyi.action.WIDGET_CALENDAR_TODAY"

    const val TAB_TODO = "todo"
    const val TAB_HABIT = "habit"
    const val TAB_CALENDAR = "calendar"
    const val TAB_FOCUS = "focus"

    private const val tag = "DuoyiWidgetNav"
    private const val extraAppWidgetId = "duoyi_widget_nav_app_widget_id"
    private const val extraTab = "duoyi_widget_nav_tab"
    private const val extraProvider = "duoyi_widget_nav_provider"
    private const val queryProvider = "provider"
    private const val queryTab = "tab"
    private const val tabKeyPrefix = "duoyi_widget_nav_tab_"
    private const val providerKeyPrefix = "duoyi_widget_nav_provider_"
    private const val uriScheme = "duoyi-widget"
    private const val hostNavigate = "navigate"
    private const val hostRefresh = "refresh"
    private const val hostCalendarToday = "calendar-today"
    private const val calendarTodaySlot = 5
    private const val collectionSlot = 6
    private const val anchorKeyPrefix = "duoyi_widget_calendar_anchor_"
    private const val resetKeyPrefix = "duoyi_widget_calendar_reset_"
    private const val collectionCategoryPrefix = "com.duoyi.duoyi.category.widget_collection"
    private const val refreshSlot = 7
    private const val maxRequestCodeWidgetId = 0x3FFFF

    private val supportedTabs = listOf(TAB_TODO, TAB_HABIT, TAB_CALENDAR, TAB_FOCUS)
    private val coreKinds = setOf(TAB_TODO, TAB_HABIT, TAB_CALENDAR, TAB_FOCUS)

    /** 一个实例的真实拥有者：广播目标 + per-ID 样式初始化都用它。 */
    data class Target(val appWidgetId: Int, val providerName: String)

    private data class Resolved(val target: Target, val tab: String?)

    // ---------------------------------------------------------------- 接收入口

    /**
     * 核心页 provider（标准 / compact / detailed）和历史综合 provider 的
     * `onReceive` 第一行走这里。
     *
     * 返回 true 表示本 helper 已经接管该广播（含被拒绝的非法目标），调用方必须
     * 直接 return，避免 `super.onReceive` 再把同一批 ID 用默认内容重绘一遍。
     * 其他业务 provider 返回 false，保持原生命周期不变。
     */
    fun handleReceive(
        context: Context,
        intent: Intent,
        receivingProvider: AppWidgetProvider,
    ): Boolean {
        val action = intent.action
        if (action != ACTION_NAVIGATE &&
            action != ACTION_REFRESH &&
            action != ACTION_CALENDAR_TODAY &&
            action != AppWidgetManager.ACTION_APPWIDGET_UPDATE
        ) {
            return false
        }
        val receivingName = receivingProvider::class.java.name
        if (!isSupportedProvider(receivingName)) return false

        val manager = AppWidgetManager.getInstance(context)
        val prefs = HomeWidgetPlugin.getData(context)
        return when (action) {
            ACTION_NAVIGATE -> {
                val resolved = resolveInstance(context, intent, manager, receivingName, ACTION_NAVIGATE)
                val tab = resolved?.tab
                if (resolved != null && tab != null && isSupportedTab(tab)) {
                    val id = resolved.target.appWidgetId
                    if (tab == TAB_CALENDAR && selectionFor(prefs, id, receivingName) != TAB_CALENDAR) {
                        markCalendarReset(prefs, id)
                    }
                    saveSelection(prefs, id, tab, receivingName)
                    Log.i(tag, "navigate widgetId=$id tab=$tab provider=$receivingName")
                    renderSelection(context, manager, prefs, id, tab, receivingName)
                } else {
                    Log.i(tag, "navigate_rejected provider=$receivingName data=${intent.data}")
                }
                true
            }

            ACTION_REFRESH -> {
                val resolved = resolveInstance(context, intent, manager, receivingName, ACTION_REFRESH)
                if (resolved == null) {
                    Log.i(tag, "refresh_rejected provider=$receivingName data=${intent.data}")
                } else {
                    val id = resolved.target.appWidgetId
                    val tab = selectionFor(prefs, id, receivingName)
                    if (tab != null) {
                        Log.i(tag, "refresh widgetId=$id tab=$tab provider=$receivingName")
                        renderSelection(context, manager, prefs, id, tab, receivingName)
                    } else {
                        receivingProvider.onUpdate(context, manager, intArrayOf(id))
                    }
                }
                true
            }

            ACTION_CALENDAR_TODAY -> {
                val resolved = resolveInstance(
                    context, intent, manager, receivingName, ACTION_CALENDAR_TODAY,
                )
                if (resolved == null) {
                    Log.i(tag, "calendar_today_rejected provider=$receivingName data=${intent.data}")
                } else {
                    val id = resolved.target.appWidgetId
                    // 只在本地实例内标记"回到应用本月"，渲染时消费一次；不启动 App。
                    markCalendarReset(prefs, id)
                    Log.i(tag, "calendar_today widgetId=$id provider=$receivingName")
                    renderSelection(
                        context, manager, prefs, id, TAB_CALENDAR, receivingName,
                    )
                }
                true
            }

            else -> handleUpdate(context, manager, prefs, intent, receivingProvider, receivingName)
        }
    }

    /**
     * `ACTION_APPWIDGET_UPDATE` 分流：没有保存 tab 的 ID 交回原 provider 的
     * `onUpdate`（保持默认内容 / 变体密度），保存了 tab 的 ID 用对应内容页
     * provider 当纯渲染器逐个重绘。
     *
     * 直接调用 `onUpdate` 不会再次进入 `onReceive`，因此不存在递归。
     */
    private fun handleUpdate(
        context: Context,
        manager: AppWidgetManager,
        prefs: SharedPreferences,
        intent: Intent,
        receivingProvider: AppWidgetProvider,
        receivingName: String,
    ): Boolean {
        if (!intent.hasExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS)) return false
        val requestedIds = intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS) ?: return false
        if (requestedIds.isEmpty()) return false

        val defaultIds = mutableListOf<Int>()
        val tabbedIds = LinkedHashMap<String, MutableList<Int>>()
        for (appWidgetId in requestedIds) {
            if (appWidgetId <= 0) continue
            // info 暂缺时仍须通过系统实例列表核验归属，再读取原有选中页。
            val ownerProvider = verifiedProviderName(
                context, manager, appWidgetId, receivingName,
            ) ?: continue
            val tab = selectionFor(prefs, appWidgetId, ownerProvider)
            if (tab == null) {
                defaultIds += appWidgetId
            } else {
                tabbedIds.getOrPut(tab) { mutableListOf() } += appWidgetId
            }
        }

        if (defaultIds.isNotEmpty()) {
            receivingProvider.onUpdate(context, manager, defaultIds.toIntArray())
        }
        for ((tab, ids) in tabbedIds) {
            prepareDisplayModeForRender(prefs, ids, receivingName)
            rendererForTab(tab).onUpdate(context, manager, ids.toIntArray())
        }
        Log.i(
            tag,
            "update provider=$receivingName requested=${requestedIds.size} " +
                "default=${defaultIds.size} tabbed=${tabbedIds.mapValues { it.value.size }}",
        )
        return true
    }

    private fun renderSelection(
        context: Context,
        manager: AppWidgetManager,
        prefs: SharedPreferences,
        appWidgetId: Int,
        tab: String,
        ownerProviderName: String,
    ) {
        prepareDisplayModeForRender(prefs, listOf(appWidgetId), ownerProviderName)
        rendererForTab(tab).onUpdate(context, manager, intArrayOf(appWidgetId))
    }

    private fun rendererForTab(tab: String): AppWidgetProvider {
        return when (tab) {
            TAB_TODO -> DuoyiTodoWidgetProvider()
            TAB_HABIT -> DuoyiHabitWidgetProvider()
            TAB_CALENDAR -> DuoyiCalendarWidgetProvider()
            else -> DuoyiFocusHabitWidgetProvider()
        }
    }

    /**
     * 切页后由别的内容页渲染时，先用实例真实 provider 的固定样式初始化 per-ID
     * 密度，避免 compact / detailed 实例被渲染成 standard。
     *
     * 历史综合 provider 没有固定样式（`styleForProvider` 返回 null），先保存
     * 它现有的全局 / per-ID 有效 mode，避免内容页的 standard 默认值覆盖旧实例。
     */
    private fun prepareDisplayModeForRender(
        prefs: SharedPreferences,
        appWidgetIds: List<Int>,
        ownerProviderName: String,
    ) {
        val style = DuoyiWidgetProviderRegistry.styleForProvider(ownerProviderName)
        if (style == null) {
            appWidgetIds.forEach { appWidgetId ->
                val effectiveMode = when {
                    DuoyiWidgetDisplayMode.isCompact(prefs, appWidgetId) -> "compact"
                    DuoyiWidgetDisplayMode.isDetailed(prefs, appWidgetId) -> "detailed"
                    else -> "standard"
                }
                DuoyiWidgetDisplayMode.saveForWidgetIfMissing(prefs, appWidgetId, effectiveMode)
            }
            return
        }
        if (style != "compact" && style != "detailed") return
        appWidgetIds.forEach { DuoyiWidgetDisplayMode.saveForWidgetIfMissing(prefs, it, style) }
    }

    // ---------------------------------------------------------------- 目标校验

    private fun resolveInstance(
        context: Context,
        intent: Intent,
        manager: AppWidgetManager,
        receivingName: String,
        expectedAction: String,
    ): Resolved? {
        if (intent.action != expectedAction) return null
        val data = intent.data ?: return null
        if (data.scheme != uriScheme) return null
        val expectedHost = when (expectedAction) {
            ACTION_NAVIGATE -> hostNavigate
            ACTION_CALENDAR_TODAY -> hostCalendarToday
            else -> hostRefresh
        }
        if (data.host != expectedHost) return null

        val uriId = data.lastPathSegment?.toIntOrNull() ?: return null
        if (uriId <= 0) return null
        val extraId = intent.getIntExtra(extraAppWidgetId, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (extraId != AppWidgetManager.INVALID_APPWIDGET_ID && extraId != uriId) return null

        // 数据 URI 里的 provider 必须和广播 extra、以及实例当前真实拥有者一致。
        val uriProvider = data.getQueryParameter(queryProvider)
        if (uriProvider.isNullOrBlank()) return null
        val extraProviderValue = intent.getStringExtra(extraProvider)
        if (!extraProviderValue.isNullOrBlank() && extraProviderValue != uriProvider) return null

        val actualProvider = verifiedProviderName(context, manager, uriId, receivingName) ?: return null
        if (actualProvider != uriProvider) return null
        if (actualProvider != receivingName) return null

        val uriTab = data.getQueryParameter(queryTab)?.takeIf { it.isNotBlank() }
        val extraTabValue = intent.getStringExtra(extraTab)?.takeIf { it.isNotBlank() }
        if (uriTab != null && extraTabValue != null && uriTab != extraTabValue) return null

        val tab = extraTabValue ?: uriTab
        if (expectedAction == ACTION_NAVIGATE && !isSupportedTab(tab)) return null
        return Resolved(Target(uriId, actualProvider), tab)
    }

    fun isSupportedTab(tab: String?): Boolean {
        return tab != null && supportedTabs.contains(tab)
    }

    fun isSupportedProvider(providerClassName: String?): Boolean {
        if (providerClassName.isNullOrBlank()) return false
        if (providerClassName == DuoyiWidgetProvider::class.java.name) return true
        val kind = DuoyiWidgetProviderRegistry.kindForProvider(providerClassName) ?: return false
        return coreKinds.contains(kind)
    }

    /** 只接受系统确认归属的实例；info 存在但不匹配时绝不降级恢复。 */
    private fun verifiedProviderName(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        expectedProviderName: String? = null,
    ): String? {
        if (appWidgetId <= 0) return null
        val info = manager.getAppWidgetInfo(appWidgetId)
        if (info != null) {
            val provider = info.provider ?: return null
            if (provider.packageName != context.packageName) return null
            val name = provider.className
            if (!isSupportedProvider(name)) return null
            if (expectedProviderName != null && name != expectedProviderName) return null
            return name
        }
        val provider = if (expectedProviderName != null) {
            if (!isSupportedProvider(expectedProviderName)) return null
            val component = ComponentName(context, expectedProviderName)
            if (!manager.getAppWidgetIds(component).contains(appWidgetId)) return null
            component
        } else {
            DuoyiWidgetProviderRegistry.findProviderForWidget(context, appWidgetId) ?: return null
        }
        val name = provider.className
        if (!isSupportedProvider(name)) return null
        Log.i(tag, "recover_owner widgetId=$appWidgetId provider=$name")
        return name
    }

    /**
     * 实例真实拥有者；不在核心 4 页 / 历史综合范围内时返回 null，调用方不绑定
     * 任何本地切页手势，其他业务小组件行为完全不变。
     */
    fun targetFor(context: Context, appWidgetId: Int): Target? {
        if (appWidgetId <= 0) return null
        val manager = AppWidgetManager.getInstance(context)
        val providerName = verifiedProviderName(context, manager, appWidgetId) ?: return null
        return Target(appWidgetId, providerName)
    }

    // ---------------------------------------------------------------- 状态持久化

    private fun saveSelection(
        prefs: SharedPreferences,
        appWidgetId: Int,
        tab: String,
        providerName: String,
    ) {
        if (appWidgetId <= 0) return
        if (!isSupportedTab(tab)) return
        if (!isSupportedProvider(providerName)) return
        prefs.edit()
            .putString(tabKey(appWidgetId), tab)
            .putString(providerKey(appWidgetId), providerName)
            .apply()
    }

    /** 已保存且仍然合法的 tab（含 provider 一致性校验）。 */
    fun selectionFor(
        prefs: SharedPreferences,
        appWidgetId: Int,
        actualProviderName: String,
    ): String? {
        if (appWidgetId <= 0) return null
        val tab = prefs.getString(tabKey(appWidgetId), null) ?: return null
        if (!isSupportedTab(tab)) return null
        val savedProvider = prefs.getString(providerKey(appWidgetId), null) ?: return null
        if (!isSupportedProvider(savedProvider)) return null
        if (savedProvider != actualProviderName) return null
        return tab
    }

    /** 只读判断“这个实例切过页”，用于保证四条 tab 始终可见。 */
    fun hasTabSelection(prefs: SharedPreferences, appWidgetId: Int): Boolean {
        if (appWidgetId <= 0) return false
        val tab = prefs.getString(tabKey(appWidgetId), null) ?: return false
        if (!isSupportedTab(tab)) return false
        val providerName = prefs.getString(providerKey(appWidgetId), null) ?: return false
        return isSupportedProvider(providerName)
    }

    /**
     * 首次 compact 仍然没有底栏；一旦实例内部切过页，任何目标页都要能看到四条
     * tab，否则切走以后回不来。
     */
    fun navVisibility(
        prefs: SharedPreferences,
        appWidgetId: Int,
        defaultVisibility: Int,
    ): Int {
        return if (hasTabSelection(prefs, appWidgetId)) View.VISIBLE else defaultVisibility
    }

    fun clearForWidgets(context: Context, appWidgetIds: IntArray) {
        if (appWidgetIds.isEmpty()) return
        val prefs = HomeWidgetPlugin.getData(context)
        val editor = prefs.edit()
        appWidgetIds.forEach { appWidgetId ->
            if (appWidgetId <= 0) return@forEach
            editor.remove(tabKey(appWidgetId))
            editor.remove(providerKey(appWidgetId))
            // 实例删除后清掉月历 anchor / 一次性 reset，避免新实例继承旧位置。
            editor.remove(anchorKey(appWidgetId))
            editor.remove(resetKey(appWidgetId))
            editor.remove("duoyi_widget_calendar_pending_scroll_$appWidgetId")
        }
        editor.apply()
    }

    // ------------------------------------------------- 月历 anchor / 「今天」重置

    /**
     * 实例的月份 anchor：首次读取时以应用本月为准落盘，之后保持不变。
     *
     * 列表范围是 anchor ±120 个月（共 241 项）。anchor 稳定意味着数据/主题刷新
     * 不会把用户正在看的月份跳回本月；只有「今天」按钮的一次性 reset 才会滚动。
     */
    fun calendarAnchor(
        prefs: SharedPreferences,
        appWidgetId: Int,
        today: LocalDate,
    ): YearMonth {
        val initial = YearMonth.from(today)
        if (appWidgetId <= 0) return initial
        storedCalendarAnchor(prefs, appWidgetId)?.let { return it }
        prefs.edit().putString(anchorKey(appWidgetId), initial.toString()).apply()
        return initial
    }

    /**
     * 需要滚动时返回目标下标，否则返回 null。
     *
     * 只在两种情况返回：本实例首次渲染（anchor 刚落盘）或收到一次「今天」。
     * 判定与消费都发生在 provider 的 onUpdate 里（`forOrientations` 之外），
     * 横竖两套 RemoteViews 因此拿到同一个初始/重置意图，不会一个方向先消费掉。
     */
    fun calendarScrollIndex(
        prefs: SharedPreferences,
        appWidgetId: Int,
        today: LocalDate,
    ): Int? {
        if (appWidgetId <= 0) return null
        val stored = storedCalendarAnchor(prefs, appWidgetId)
        val resetRequested = consumeCalendarReset(prefs, appWidgetId)
        if (stored != null && !resetRequested) return null
        val anchor = stored ?: YearMonth.from(today).also {
            prefs.edit().putString(anchorKey(appWidgetId), it.toString()).apply()
        }
        return DuoyiWidgetCollections.indexOfMonth(anchor, YearMonth.from(today))
    }

    private fun storedCalendarAnchor(
        prefs: SharedPreferences,
        appWidgetId: Int,
    ): YearMonth? {
        val raw = prefs.getString(anchorKey(appWidgetId), null) ?: return null
        return runCatching { YearMonth.parse(raw) }.getOrNull()
    }

    private fun markCalendarReset(prefs: SharedPreferences, appWidgetId: Int) {
        if (appWidgetId <= 0) return
        prefs.edit().putBoolean(resetKey(appWidgetId), true).apply()
    }

    /** 只消费一次：读取后立即清除，常规刷新不会再触发滚动。 */
    private fun consumeCalendarReset(
        prefs: SharedPreferences,
        appWidgetId: Int,
    ): Boolean {
        if (appWidgetId <= 0) return false
        if (!prefs.getBoolean(resetKey(appWidgetId), false)) return false
        prefs.edit().remove(resetKey(appWidgetId)).apply()
        return true
    }

    // ---------------------------------------------------------------- PendingIntent

    fun bindBottomTabs(
        context: Context,
        views: RemoteViews,
        prefs: SharedPreferences,
        target: Target?,
        appWidgetId: Int,
        navId: Int,
        defaultNavVisibility: Int,
        tabViewIds: Map<String, Int>,
    ): Boolean {
        if (target == null || navId == 0) return false
        views.setViewVisibility(navId, navVisibility(prefs, appWidgetId, defaultNavVisibility))
        views.setOnClickPendingIntent(navId, refreshIntent(context, target))
        var bound = false
        for (tab in supportedTabs) {
            val viewId = tabViewIds[tab] ?: continue
            views.setOnClickPendingIntent(viewId, tabIntent(context, target, tab))
            bound = true
        }
        return bound
    }

    /** 单个控件切到指定 tab（历史综合小组件的三个统计入口）。 */
    fun bindTabButton(
        context: Context,
        views: RemoteViews,
        target: Target?,
        viewId: Int,
        tab: String,
    ): Boolean {
        if (target == null || viewId == 0) return false
        if (!isSupportedTab(tab)) return false
        views.setOnClickPendingIntent(viewId, tabIntent(context, target, tab))
        return true
    }

    /**
     * 只读区域（标题 / 日期 / 统计 / 内容行 / 今天按钮）的点击：本地重绘当前
     * 实例，既不开 App，也不改 tab。
     */
    fun bindRefresh(
        context: Context,
        views: RemoteViews,
        target: Target?,
        viewIds: IntArray,
    ): Boolean {
        if (target == null) return false
        var bound = false
        val refreshPendingIntent = refreshIntent(context, target)
        for (viewId in viewIds) {
            if (viewId == 0) continue
            views.setOnClickPendingIntent(viewId, refreshPendingIntent)
            bound = true
        }
        return bound
    }

    private fun tabIntent(context: Context, target: Target, tab: String): PendingIntent {
        val uri = targetUri(target, hostNavigate, tab)
        val intent = Intent(ACTION_NAVIGATE).apply {
            setComponent(ComponentName(context.packageName, target.providerName))
            data = uri
            putExtra(extraAppWidgetId, target.appWidgetId)
            putExtra(extraProvider, target.providerName)
            putExtra(extraTab, tab)
        }
        return PendingIntent.getBroadcast(
            context,
            requestCodeFor(target.appWidgetId, tabSlot(tab)),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun refreshIntent(context: Context, target: Target): PendingIntent {
        val intent = Intent(ACTION_REFRESH).apply {
            setComponent(ComponentName(context.packageName, target.providerName))
            data = targetUri(target, hostRefresh, null)
            putExtra(extraAppWidgetId, target.appWidgetId)
            putExtra(extraProvider, target.providerName)
        }
        return PendingIntent.getBroadcast(
            context,
            requestCodeFor(target.appWidgetId, refreshSlot),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** 每个实例 / tab 都是唯一 data URI，互不覆盖 PendingIntent。 */
    private fun targetUri(target: Target, host: String, tab: String?): Uri {
        val builder = Uri.Builder()
            .scheme(uriScheme)
            .authority(host)
            .appendPath(target.appWidgetId.toString())
            .appendQueryParameter(queryProvider, target.providerName)
        if (tab != null) builder.appendQueryParameter(queryTab, tab)
        return builder.build()
    }

    private fun tabSlot(tab: String): Int {
        val index = supportedTabs.indexOf(tab)
        return if (index < 0) 0 else index
    }

    private fun requestCodeFor(appWidgetId: Int, slot: Int): Int {
        return (appWidgetId and maxRequestCodeWidgetId) * 8 + slot
    }

    private fun tabKey(appWidgetId: Int): String = "$tabKeyPrefix$appWidgetId"

    private fun providerKey(appWidgetId: Int): String = "$providerKeyPrefix$appWidgetId"
    // ---------------------------------------------------------------- 「今天」

    /**
     * 月历「今天」按钮：只发本实例的本地广播，滚回应用本月，不启动 App、不切 tab。
     */
    fun bindCalendarToday(
        context: Context,
        views: RemoteViews,
        target: Target?,
        viewId: Int,
    ): Boolean {
        if (target == null || viewId == 0) return false
        views.setOnClickPendingIntent(viewId, calendarTodayIntent(context, target))
        return true
    }

    private fun calendarTodayIntent(context: Context, target: Target): PendingIntent {
        val intent = Intent(ACTION_CALENDAR_TODAY).apply {
            setComponent(ComponentName(context.packageName, target.providerName))
            data = targetUri(target, hostCalendarToday, null)
            putExtra(extraAppWidgetId, target.appWidgetId)
            putExtra(extraProvider, target.providerName)
        }
        return PendingIntent.getBroadcast(
            context,
            requestCodeFor(target.appWidgetId, calendarTodaySlot),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    // ------------------------------------------------------------ 集合 fill-in

    /**
     * 待办行的 fill-in Intent：data 用本地可信 ID 编码成详情深链。
     *
     * fill-in 只承载 data，不携带组件 / action；真正启动 Activity 的是 provider 里
     * 唯一的模板 PendingIntent（见 [collectionTemplate]）。模板的 data 保持为空，
     * 否则 fill-in 的详情 URI 会被固定 base data 覆盖掉。
     */
    fun todoFillInIntent(todoId: String): Intent {
        val intent = Intent()
        if (todoId.isBlank()) return intent
        intent.data = Uri.parse("duoyi://todo/${Uri.encode(todoId)}")
        return intent
    }

    /** 月历格的 fill-in Intent：进入 App 日历页（Dart 只按 host 分页）。 */
    fun calendarFillInIntent(): Intent {
        return Intent().apply { data = Uri.parse("duoyi://calendar") }
    }

    /**
     * 集合 item 的固定模板：显式 MainActivity + 唯一 category（含 kind / 实例）。
     *
     * 只有这里允许 FLAG_MUTABLE（API 31+，更低版本无需该 flag），因为系统必须能把
     * item 的 fill-in data 合进模板。其余 nav / refresh / today 仍是 IMMUTABLE。
     * 模板 Intent 的 data 故意留空，避免固定 base data 盖掉 fill-in 详情 URL。
     */
    fun collectionTemplate(
        context: Context,
        target: Target?,
        kind: String,
    ): PendingIntent? {
        if (target == null) return null
        if (kind != DuoyiWidgetCollectionService.KIND_TODO &&
            kind != DuoyiWidgetCollectionService.KIND_CALENDAR
        ) {
            return null
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setComponent(ComponentName(context.packageName, MainActivity::class.java.name))
            // 固定 category 让"宿主 provider + 实例 + kind"的模板身份唯一；data 保持空，
            // 这样 item 的 fill-in 详情 URI 才能生效。
            addCategory(
                "$collectionCategoryPrefix.$kind.${target.appWidgetId}.${target.providerName}",
            )
        }
        val mutableFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            0
        }
        return PendingIntent.getActivity(
            context,
            requestCodeFor(target.appWidgetId, collectionSlot),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or mutableFlag,
        )
    }

    private fun anchorKey(appWidgetId: Int): String = "$anchorKeyPrefix$appWidgetId"

    private fun resetKey(appWidgetId: Int): String = "$resetKeyPrefix$appWidgetId"
}
