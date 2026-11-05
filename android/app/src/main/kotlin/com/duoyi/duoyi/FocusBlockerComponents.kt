package com.duoyi.duoyi

/**
 * 无障碍服务组件名匹配（纯 Kotlin，无 Android 依赖，便于 JVM 单测）。
 *
 * 系统 `ENABLED_ACCESSIBILITY_SERVICES` 里的条目既可能是
 * `com.duoyi.duoyi/com.duoyi.duoyi.DuoyiFocusBlockerAccessibilityService`
 * （`flattenToString()` 全名），也可能是 `com.duoyi.duoyi/.DuoyiFocusBlockerAccessibilityService`
 * （短名，小米/部分 ROM 实测会这样存）。两者都必须判定为已启用，否则
 * “已在设置里开启”会被误报成未授权。
 */
object FocusBlockerComponents {

    /** 逗号/冒号分隔的启用列表 → 去空条目。 */
    fun settingEntries(raw: String?): List<String> =
        raw.orEmpty()
            .split(':', ',')
            .map { it.trim() }
            .filter { it.isNotEmpty() }

    /** `pkg/Class` → (pkg, Class)；格式非法返回 null。 */
    fun splitEntry(entry: String): Pair<String, String>? {
        val slash = entry.indexOf('/')
        if (slash <= 0 || slash == entry.lastIndex) return null
        val packageName = entry.substring(0, slash).trim()
        val className = entry.substring(slash + 1).trim()
        if (packageName.isEmpty() || className.isEmpty()) return null
        return packageName to className
    }

    /** `.Cls` 短名补全为全名；其它形式原样返回。 */
    fun normalizeClassName(className: String, packageName: String): String {
        val clean = className.trim()
        if (clean.isEmpty()) return clean
        return if (clean.startsWith(".")) packageName + clean else clean
    }

    /**
     * 判断系统启用列表里是否包含指定组件。
     *
     * 比较前统一把短名补全，因此全名/短名写法都能命中；包名必须完全一致。
     */
    fun matches(raw: String?, expectedPackage: String, expectedClassName: String): Boolean {
        val pkg = expectedPackage.trim()
        if (pkg.isEmpty()) return false
        val expectedClass = normalizeClassName(expectedClassName, pkg)
        if (expectedClass.isEmpty()) return false
        return settingEntries(raw).any { entry ->
            val parsed = splitEntry(entry) ?: return@any false
            if (parsed.first != pkg) return@any false
            normalizeClassName(parsed.second, parsed.first) == expectedClass
        }
    }
}
