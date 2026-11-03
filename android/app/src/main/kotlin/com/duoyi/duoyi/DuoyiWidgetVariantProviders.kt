package com.duoyi.duoyi

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import es.antonborri.home_widget.HomeWidgetPlugin

class DuoyiTodoCompactWidgetProvider : DuoyiTodoWidgetProvider()
class DuoyiTodoDetailedWidgetProvider : DuoyiTodoWidgetProvider()

class DuoyiFocusHabitCompactWidgetProvider : DuoyiFocusHabitWidgetProvider()
class DuoyiFocusHabitDetailedWidgetProvider : DuoyiFocusHabitWidgetProvider()

class DuoyiHabitCompactWidgetProvider : DuoyiHabitWidgetProvider()
class DuoyiHabitDetailedWidgetProvider : DuoyiHabitWidgetProvider()

class DuoyiCalendarCompactWidgetProvider : DuoyiCalendarWidgetProvider()
class DuoyiCalendarDetailedWidgetProvider : DuoyiCalendarWidgetProvider()

class DuoyiScheduleCompactWidgetProvider : DuoyiScheduleWidgetProvider()
class DuoyiScheduleDetailedWidgetProvider : DuoyiScheduleWidgetProvider()

class DuoyiGoalCompactWidgetProvider : DuoyiGoalWidgetProvider()
class DuoyiGoalDetailedWidgetProvider : DuoyiGoalWidgetProvider()

class DuoyiCourseCompactWidgetProvider : DuoyiCourseWidgetProvider()
class DuoyiCourseDetailedWidgetProvider : DuoyiCourseWidgetProvider()

class DuoyiNoteCompactWidgetProvider : DuoyiNoteWidgetProvider()
class DuoyiNoteDetailedWidgetProvider : DuoyiNoteWidgetProvider()

class DuoyiAnniversaryCompactWidgetProvider : DuoyiAnniversaryWidgetProvider()
class DuoyiAnniversaryDetailedWidgetProvider : DuoyiAnniversaryWidgetProvider()

class DuoyiDiaryCompactWidgetProvider : DuoyiDiaryWidgetProvider()
class DuoyiDiaryDetailedWidgetProvider : DuoyiDiaryWidgetProvider()

object DuoyiWidgetProviderRegistry {
    private const val tag = "DuoyiWidgetPin"
    private const val pendingPrefsName = "duoyi_widget_pin_state"
    private const val pendingVariantProvidersKey = "pending_variant_providers"
    private const val activeVariantProvidersKey = "active_variant_providers"
    private const val pendingEntrySeparator = "|"
    private const val pendingFieldSeparator = "||"
    private const val pendingVariantProviderTtlMillis = 4 * 60 * 1000L

    /**
     * 应用内"添加小组件"只固定核心 4 类的标准入口。
     *
     * 系统小组件列表现在只暴露这 4 个 provider（其余注册项以
     * `android:widgetFeatures="hide_from_picker"` 隐藏，仍保留给已添加的旧实例使用）：
     * DuoyiTodoWidgetProvider / DuoyiHabitWidgetProvider /
     * DuoyiCalendarWidgetProvider / DuoyiFocusHabitWidgetProvider。
     *
     * 密度（compact/standard/detailed）不再决定 provider：请求尺寸仍由 Pin 流程写进
     * 实例的 DisplayMode 与 options，宿主调整大小后由布局按物理容量自适应。
     * 已存在的 compact/detailed/次级品类实例继续按原组件刷新、不做禁用或迁移，
     * 因此 [style] 只影响 DisplayMode，不参与 provider 选择。
     */
    @Suppress("UNUSED_PARAMETER")
    fun componentFor(context: Context, kind: String, style: String): ComponentName? {
        if (kind !in standardCatalogKinds) return null
        val family = widgetFamilies.firstOrNull { it.kind == kind } ?: return null
        return ComponentName(context, family.standard)
    }

    fun rememberPendingVariantProvider(
        context: Context,
        requestId: String,
        component: ComponentName,
    ) {
        if (!isVariantProvider(component.className)) return
        val prefs = context.getSharedPreferences(pendingPrefsName, Context.MODE_PRIVATE)
        val pending = prefs.getStringSet(pendingVariantProvidersKey, emptySet())
            ?.toMutableSet()
            ?: mutableSetOf()
        pending.add(pendingEntry(requestId, component, System.currentTimeMillis()))
        Log.i(
            tag,
            "remember_pending requestId=$requestId provider=${component.className} pendingCount=${pending.size}",
        )
        prefs.edit()
            .putStringSet(pendingVariantProvidersKey, pending)
            .apply()
        scheduleExpiredPendingVariantProviderCleanup(context)
    }

    fun clearPendingVariantProvider(context: Context, requestId: String, component: ComponentName) {
        val prefs = context.getSharedPreferences(pendingPrefsName, Context.MODE_PRIVATE)
        val pending = prefs.getStringSet(pendingVariantProvidersKey, emptySet())
            ?.toMutableSet()
            ?: mutableSetOf()
        val removed = pending.removeAll {
            pendingRequestId(it) == requestId && pendingComponent(it) == component
        } || pending.remove(component.flattenToString())
        if (removed) {
            Log.i(
                tag,
                "clear_pending requestId=$requestId provider=${component.className} pendingCount=${pending.size}",
            )
            prefs.edit()
                .putStringSet(pendingVariantProvidersKey, pending)
                .apply()
        }
    }

    fun cleanupPendingVariantProvider(context: Context, requestId: String) {
        if (requestId.isBlank()) return
        val prefs = context.getSharedPreferences(pendingPrefsName, Context.MODE_PRIVATE)
        val pending = prefs.getStringSet(pendingVariantProvidersKey, emptySet())
            ?.toMutableSet()
            ?: mutableSetOf()
        val match = pending.firstOrNull { pendingRequestId(it) == requestId } ?: return
        val component = pendingComponent(match)
        if (component != null && isVariantProvider(component.className)) {
            disableVariantProviderIfUnused(context, component)
        }
        pending.remove(match)
        Log.i(
            tag,
            "cleanup_pending requestId=$requestId provider=${component?.className.orEmpty()} pendingCount=${pending.size}",
        )
        prefs.edit()
            .putStringSet(pendingVariantProvidersKey, pending)
            .apply()
    }

    fun cleanupPendingVariantProviders(context: Context) {
        cleanupExpiredPendingVariantProviders(context)
    }

    fun cleanupExpiredPendingVariantProviders(context: Context) {
        val prefs = context.getSharedPreferences(pendingPrefsName, Context.MODE_PRIVATE)
        val pending = prefs.getStringSet(pendingVariantProvidersKey, emptySet())
            ?.toMutableSet()
            ?: mutableSetOf()
        if (pending.isEmpty()) return

        val now = System.currentTimeMillis()
        for (flattened in pending.toList()) {
            val component = pendingComponent(flattened)
            if (component == null || !isVariantProvider(component.className)) {
                pending.remove(flattened)
                continue
            }
            val createdAt = pendingCreatedAt(flattened)
            if (createdAt != null && now - createdAt < pendingVariantProviderTtlMillis) {
                continue
            }
            Log.i(
                tag,
                "cleanup_expired_pending requestId=${pendingRequestId(flattened)} provider=${component.className} ageMs=${createdAt?.let { now - it } ?: -1}",
            )
            disableVariantProviderIfUnused(context, component, respectPending = false)
            pending.remove(flattened)
        }
        prefs.edit()
            .putStringSet(pendingVariantProvidersKey, pending)
            .apply()
    }

    fun markVariantProviderActive(context: Context, component: ComponentName): Boolean {
        if (!isVariantProvider(component.className)) return false
        val prefs = context.getSharedPreferences(pendingPrefsName, Context.MODE_PRIVATE)
        val active = prefs.getStringSet(activeVariantProvidersKey, emptySet())
            ?.toMutableSet()
            ?: mutableSetOf()
        val flattened = component.flattenToString()
        if (!active.add(flattened)) return false
        prefs.edit()
            .putStringSet(activeVariantProvidersKey, active)
            .apply()
        Log.i(tag, "mark_active_variant_provider provider=${component.className} activeCount=${active.size}")
        return true
    }

    private fun clearActiveVariantProvider(context: Context, component: ComponentName): Boolean {
        if (!isVariantProvider(component.className)) return false
        val prefs = context.getSharedPreferences(pendingPrefsName, Context.MODE_PRIVATE)
        val active = prefs.getStringSet(activeVariantProvidersKey, emptySet())
            ?.toMutableSet()
            ?: mutableSetOf()
        if (!active.remove(component.flattenToString())) return false
        prefs.edit()
            .putStringSet(activeVariantProvidersKey, active)
            .apply()
        Log.i(tag, "clear_active_variant_provider provider=${component.className} activeCount=${active.size}")
        return true
    }

    private fun activeVariantProviderComponents(context: Context): List<ComponentName> {
        val prefs = context.getSharedPreferences(pendingPrefsName, Context.MODE_PRIVATE)
        val active = prefs.getStringSet(activeVariantProvidersKey, emptySet()) ?: return emptyList()
        return active.mapNotNull { ComponentName.unflattenFromString(it) }
            .filter { isVariantProvider(it.className) }
    }

    private fun isActiveVariantProvider(context: Context, component: ComponentName): Boolean {
        if (!isVariantProvider(component.className)) return false
        val prefs = context.getSharedPreferences(pendingPrefsName, Context.MODE_PRIVATE)
        val active = prefs.getStringSet(activeVariantProvidersKey, emptySet()) ?: return false
        return active.contains(component.flattenToString())
    }

    fun restoreEnabledProvidersForExistingWidgets(context: Context): Int {
        val manager = AppWidgetManager.getInstance(context)
        var restoredCount = 0
        for (component in activeVariantProviderComponents(context)) {
            val enabled = ensureProviderEnabled(context, component)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isEmpty()) {
                Log.i(
                    tag,
                    "restore_keep_active_variant_without_visible_ids provider=${component.className}",
                )
                continue
            }
            if (enabled) {
                restoredCount += 1
            }
        }
        for (providerClass in allWidgetProviderClasses()) {
            val component = ComponentName(context, providerClass)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isEmpty()) continue
            markVariantProviderActive(context, component)
            if (ensureProviderEnabled(context, component)) {
                restoredCount += 1
            }
        }
        if (restoredCount > 0) {
            Log.i(tag, "restore_enabled_providers count=$restoredCount")
        }
        return restoredCount
    }

    private fun pendingEntry(requestId: String, component: ComponentName): String {
        return pendingEntry(requestId, component, null)
    }

    private fun pendingEntry(requestId: String, component: ComponentName, createdAt: Long?): String {
        val base = "$requestId$pendingEntrySeparator${component.flattenToString()}"
        return if (createdAt == null) base else "$base$pendingFieldSeparator$createdAt"
    }

    private fun pendingRequestId(entry: String): String {
        return entry.substringBefore(pendingEntrySeparator, "")
    }

    private fun pendingComponent(entry: String): ComponentName? {
        val withoutMetadata = entry.substringBefore(pendingFieldSeparator)
        val flattened = if (entry.contains(pendingEntrySeparator)) {
            withoutMetadata.substringAfter(pendingEntrySeparator)
        } else {
            withoutMetadata
        }
        return ComponentName.unflattenFromString(flattened)
    }

    private fun pendingCreatedAt(entry: String): Long? {
        return entry.substringAfter(pendingFieldSeparator, "").toLongOrNull()
    }

    fun kindForProvider(providerClassName: String?): String? {
        return widgetFamilies.firstOrNull { family ->
            family.providerClasses.any { it.name == providerClassName }
        }?.kind
    }

    fun styleForProvider(providerClassName: String?): String? {
        val family = widgetFamilies.firstOrNull { widgetFamily ->
            widgetFamily.providerClasses.any { it.name == providerClassName }
        } ?: return null
        return when (providerClassName) {
            family.compact.name -> "compact"
            family.standard.name -> "standard"
            family.detailed.name -> "detailed"
            else -> null
        }
    }

    fun isVariantProvider(providerClassName: String?): Boolean {
        val family = widgetFamilies.firstOrNull { widgetFamily ->
            widgetFamily.providerClasses.any { it.name == providerClassName }
        } ?: return false
        return providerClassName == family.compact.name ||
            providerClassName == family.detailed.name
    }

    fun disableVariantProviderIfUnused(context: Context, component: ComponentName): Boolean {
        return disableVariantProviderIfUnused(context, component, respectPending = true)
    }

    private fun disableVariantProviderIfUnused(
        context: Context,
        component: ComponentName,
        respectPending: Boolean,
    ): Boolean {
        if (!isVariantProvider(component.className)) return false
        ensureProviderEnabled(context, component)
        if (respectPending && hasPendingVariantProvider(context, component)) {
            Log.i(tag, "keep_variant_provider_pending provider=${component.className}")
            return false
        }
        if (isActiveVariantProvider(context, component)) {
            Log.i(tag, "keep_active_variant_provider provider=${component.className}")
            return false
        }
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(component)
        if (ids.isNotEmpty()) {
            markVariantProviderActive(context, component)
            Log.i(
                tag,
                "keep_variant_provider provider=${component.className} widgetCount=${ids.size}",
            )
            return false
        }
        Log.i(tag, "keep_system_visible_variant_provider provider=${component.className}")
        return false
    }

    fun scheduleDisableVariantProviderIfUnused(
        context: Context,
        component: ComponentName,
        delayMillis: Long = 5 * 60_000L,
    ) {
        if (!isVariantProvider(component.className)) return
        val appContext = context.applicationContext
        Log.i(
            tag,
            "schedule_disable_variant_provider provider=${component.className} delayMs=$delayMillis",
        )
        Handler(Looper.getMainLooper()).postDelayed({
            disableVariantProviderIfUnused(appContext, component)
        }, delayMillis)
    }

    fun requestUpdateForProvider(context: Context, providerClassName: String?) {
        if (providerClassName == DuoyiWidgetProvider::class.java.name) {
            requestUpdate(context, legacyProviderClasses)
            return
        }
        val kind = kindForProvider(providerClassName) ?: return
        requestUpdateForKind(context, kind)
    }

    fun requestUpdateForKind(context: Context, kind: String) {
        val family = widgetFamilies.firstOrNull { it.kind == kind } ?: return
        requestUpdate(context, family.providerClasses)
    }

    fun requestUpdateForAllWidgets(context: Context): Int {
        return requestUpdate(context, allWidgetProviderClasses())
    }

    /** info 暂缺时从系统实例列表恢复真实宿主，不使用当前内容页渲染器推断。 */
    fun findProviderForWidget(context: Context, appWidgetId: Int): ComponentName? {
        if (appWidgetId <= 0) return null
        val manager = AppWidgetManager.getInstance(context)
        return allWidgetProviderClasses()
            .asSequence()
            .map { ComponentName(context, it) }
            .firstOrNull { component -> manager.getAppWidgetIds(component).contains(appWidgetId) }
    }

    fun requestUpdate(context: Context, providerClasses: List<Class<out AppWidgetProvider>>): Int {
        val components = providerClasses.map { ComponentName(context, it) }
        return requestUpdateComponents(context, components)
    }

    fun requestUpdateForComponent(context: Context, component: ComponentName): Int {
        return requestUpdateComponents(context, listOf(component))
    }

    private fun requestUpdateComponents(context: Context, components: List<ComponentName>): Int {
        val manager = AppWidgetManager.getInstance(context)
        var updatedCount = 0
        for (component in components) {
            val ids = manager.getAppWidgetIds(component)
            if (ids.isEmpty()) continue
            ensureProviderEnabled(context, component)
            val intent = Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).apply {
                setComponent(component)
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
            context.sendBroadcast(intent)
            updatedCount += ids.size
        }
        return updatedCount
    }

    private fun hasPendingVariantProvider(context: Context, component: ComponentName): Boolean {
        val prefs = context.getSharedPreferences(pendingPrefsName, Context.MODE_PRIVATE)
        return prefs.getStringSet(pendingVariantProvidersKey, emptySet())
            ?.any { pendingComponent(it) == component }
            ?: false
    }

    private fun scheduleExpiredPendingVariantProviderCleanup(context: Context) {
        val appContext = context.applicationContext
        Handler(Looper.getMainLooper()).postDelayed({
            cleanupExpiredPendingVariantProviders(appContext)
        }, pendingVariantProviderTtlMillis + 5_000L)
    }

    private fun ensureProviderEnabled(context: Context, component: ComponentName): Boolean {
        val current = context.packageManager.getComponentEnabledSetting(component)
        if (current == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) return false
        context.packageManager.setComponentEnabledSetting(
            component,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        Log.i(tag, "enable_widget_provider provider=${component.className} previousState=$current")
        return true
    }

    fun applyDisplayModeToExistingWidgets(context: Context, styleId: String?): Int {
        val style = DuoyiWidgetPinStyle.fromId(styleId)
        val manager = AppWidgetManager.getInstance(context)
        val prefs = HomeWidgetPlugin.getData(context)
        var appliedCount = 0
        for (providerClass in legacyProviderClasses) {
            val component = ComponentName(context, providerClass)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isEmpty()) continue
            for (id in ids) {
                if (id == AppWidgetManager.INVALID_APPWIDGET_ID) continue
                DuoyiWidgetDisplayMode.saveForWidget(prefs, id, style.id)
                manager.updateAppWidgetOptions(id, style.toOptions())
                appliedCount += 1
                Log.i(
                    tag,
                    "apply_display_mode widgetId=$id provider=${component.className} normalizedStyle=${style.id}",
                )
            }
        }
        for (family in widgetFamilies) {
            for (providerClass in family.providerClasses) {
                val component = ComponentName(context, providerClass)
                val ids = manager.getAppWidgetIds(component)
                if (ids.isEmpty()) continue
                for (id in ids) {
                    if (id == AppWidgetManager.INVALID_APPWIDGET_ID) continue
                    DuoyiWidgetDisplayMode.saveForWidget(prefs, id, style.id)
                    manager.updateAppWidgetOptions(id, style.toOptions())
                    appliedCount += 1
                    Log.i(
                        tag,
                        "apply_display_mode widgetId=$id provider=${component.className} normalizedStyle=${style.id}",
                    )
                }
            }
            requestUpdate(context, family.providerClasses)
        }
        requestUpdate(context, legacyProviderClasses)
        return appliedCount
    }

    private data class WidgetFamily(
        val kind: String,
        val standard: Class<out AppWidgetProvider>,
        val compact: Class<out AppWidgetProvider>,
        val detailed: Class<out AppWidgetProvider>,
    ) {
        val providerClasses: List<Class<out AppWidgetProvider>>
            get() = listOf(standard, compact, detailed)
        val variantProviderClasses: List<Class<out AppWidgetProvider>>
            get() = listOf(compact, detailed)
    }

    /** 系统小组件列表可见的 4 个标准品类；其余 family 仅保留给旧实例刷新与宿主查找。 */
    private val standardCatalogKinds = setOf("todo", "focus", "habit", "calendar")

    private val widgetFamilies = listOf(
        WidgetFamily(
            "todo",
            DuoyiTodoWidgetProvider::class.java,
            DuoyiTodoCompactWidgetProvider::class.java,
            DuoyiTodoDetailedWidgetProvider::class.java,
        ),
        WidgetFamily(
            "focus",
            DuoyiFocusHabitWidgetProvider::class.java,
            DuoyiFocusHabitCompactWidgetProvider::class.java,
            DuoyiFocusHabitDetailedWidgetProvider::class.java,
        ),
        WidgetFamily(
            "habit",
            DuoyiHabitWidgetProvider::class.java,
            DuoyiHabitCompactWidgetProvider::class.java,
            DuoyiHabitDetailedWidgetProvider::class.java,
        ),
        WidgetFamily(
            "calendar",
            DuoyiCalendarWidgetProvider::class.java,
            DuoyiCalendarCompactWidgetProvider::class.java,
            DuoyiCalendarDetailedWidgetProvider::class.java,
        ),
        WidgetFamily(
            "schedule",
            DuoyiScheduleWidgetProvider::class.java,
            DuoyiScheduleCompactWidgetProvider::class.java,
            DuoyiScheduleDetailedWidgetProvider::class.java,
        ),
        WidgetFamily(
            "goal",
            DuoyiGoalWidgetProvider::class.java,
            DuoyiGoalCompactWidgetProvider::class.java,
            DuoyiGoalDetailedWidgetProvider::class.java,
        ),
        WidgetFamily(
            "course",
            DuoyiCourseWidgetProvider::class.java,
            DuoyiCourseCompactWidgetProvider::class.java,
            DuoyiCourseDetailedWidgetProvider::class.java,
        ),
        WidgetFamily(
            "note",
            DuoyiNoteWidgetProvider::class.java,
            DuoyiNoteCompactWidgetProvider::class.java,
            DuoyiNoteDetailedWidgetProvider::class.java,
        ),
        WidgetFamily(
            "anniversary",
            DuoyiAnniversaryWidgetProvider::class.java,
            DuoyiAnniversaryCompactWidgetProvider::class.java,
            DuoyiAnniversaryDetailedWidgetProvider::class.java,
        ),
    )

    private val legacyProviderClasses = listOf<Class<out AppWidgetProvider>>(
        DuoyiWidgetProvider::class.java,
    )

    private fun allWidgetProviderClasses(): List<Class<out AppWidgetProvider>> {
        return legacyProviderClasses + widgetFamilies.flatMap { it.providerClasses }
    }
}
