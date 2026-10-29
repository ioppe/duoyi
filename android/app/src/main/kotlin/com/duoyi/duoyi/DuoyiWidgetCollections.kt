package com.duoyi.duoyi

import java.time.YearMonth
import org.json.JSONArray
import org.json.JSONObject

/**
 * 待办集合的一行（纯数据）。
 *
 * 顺序即 Flutter 推送顺序：Dart 侧已按 Q1 → Q3 → Q2 → Q4 排好并推全部今日可见未完成
 * 事项，native 绝不再按 quadrant 序重排，只在渲染时原样使用 [quadrant] 做轻标记。
 * [id] 为空的行不创建（空白不产生任务）；标题只做一次 trim。
 */
data class DuoyiTodoWidgetItem(
    val id: String,
    val title: String,
    val quadrant: Int,
)

/**
 * 桌面集合组件的纯数据层：待办条目解析 + 月历月份范围/稳定 ID。
 *
 * 该 object 不持有 Context、不读 SharedPreferences、不引用 Android 视图类型，
 * 因此可以在纯 JVM 单元测试里直接断言（偏好读写留在两个 Provider / Service 里）。
 */
object DuoyiWidgetCollections {

    // ---------------------------------------------------------------- 待办协议

    /** Flutter 写入的完整今日待办数组（Q1→Q3→Q2→Q4 顺序、已排序）。 */
    const val KEY_TODO_ITEMS_JSON = "widget_todo_items_json"

    /** 旧协议：今日未完成总数（仍是全部计数，不只 top3）。 */
    const val KEY_TODO_COUNT = "todo_top3_count"

    /** 旧协议三条文字 / ID；只在新 key 完全不存在时用于回退。 */
    const val KEY_TODO_LEGACY_TITLE_PREFIX = "todo_top3_"
    const val KEY_TODO_LEGACY_ID_SUFFIX = "_id"

    private const val FIELD_ID = "id"
    private const val FIELD_TITLE = "title"
    private const val FIELD_QUADRANT = "quadrant"

    /**
     * 标题清洗：去掉旧代码遗留的「· 」前缀与首尾空白。
     * 返回空串表示该行没有可用标题，调用方应跳过（不创建空任务）。
     */
    fun cleanTodoTitle(raw: String?): String {
        if (raw.isNullOrEmpty()) return ""
        return raw.trim().removePrefix("·").trim()
    }

    /**
     * 解析 `widget_todo_items_json`。
     *
     * - 空串 / 非法 JSON → 空列表（调用方据此显示空态，不回退旧 key）；
     * - 缺 `id` 或标题清洗后为空的行直接丢弃；
     * - `quadrant` 缺失或非法按 0 处理（只影响 marker，不影响排序）。
     */
    fun parseTodoItems(raw: String?): List<DuoyiTodoWidgetItem> {
        val text = raw?.trim().orEmpty()
        if (text.isEmpty()) return emptyList()
        val array = runCatching { JSONArray(text) }.getOrNull() ?: return emptyList()
        val items = ArrayList<DuoyiTodoWidgetItem>(array.length())
        for (index in 0 until array.length()) {
            val obj: JSONObject = array.optJSONObject(index) ?: continue
            val id = obj.optString(FIELD_ID, "").trim()
            if (id.isEmpty()) continue
            val title = cleanTodoTitle(obj.optString(FIELD_TITLE, ""))
            if (title.isEmpty()) continue
            items += DuoyiTodoWidgetItem(
                id = id,
                title = title,
                quadrant = obj.optInt(FIELD_QUADRANT, 0),
            )
        }
        return items
    }

    /**
     * 旧三键回退：只在 `widget_todo_items_json` 完全不存在时使用。
     *
     * 三条旧文字/ID 里没有非空 ID 的行同样丢弃，保证回退路径也不会产生空任务。
     */
    fun legacyTodoItems(
        titles: List<String?>,
        ids: List<String?>,
    ): List<DuoyiTodoWidgetItem> {
        val items = ArrayList<DuoyiTodoWidgetItem>(titles.size)
        for (index in titles.indices) {
            val id = ids.getOrNull(index)?.trim().orEmpty()
            if (id.isEmpty()) continue
            val title = cleanTodoTitle(titles[index])
            if (title.isEmpty()) continue
            items += DuoyiTodoWidgetItem(id = id, title = title, quadrant = 0)
        }
        return items
    }

    /**
     * 待办行稳定 ID：64 位 FNV-1a，避免 32 位 `String.hashCode()` 已知的
     * "Aa" / "BB" 碰撞导致 ListView 复用错行。同 ID 永远同值、跨刷新稳定。
     */
    fun stableTodoItemId(id: String): Long {
        var hash = FNV_OFFSET_BASIS_64
        for (byte in id.toByteArray(Charsets.UTF_8)) {
            hash = hash xor (byte.toLong() and 0xFFL)
            hash *= FNV_PRIME_64
        }
        return hash
    }

    /**
     * 统一入口：[newJson] 为 null 表示新 key 完全不存在（旧 Dart 尚未推送），此时才用
     * 三条旧键 + 非空 ID 回退；新 key 存在但内容为空 / 解析为空时一律返回空列表，
     * 绝不回退旧任务。
     */
    fun todoItems(
        newJson: String?,
        legacyTitles: List<String?>,
        legacyIds: List<String?>,
    ): List<DuoyiTodoWidgetItem> {
        if (newJson != null) return parseTodoItems(newJson)
        return legacyTodoItems(legacyTitles, legacyIds)
    }

    private const val FNV_OFFSET_BASIS_64 = -3750763034362895579L // 0xCBF29CE484222325
    private const val FNV_PRIME_64 = 1099511628211L // 0x100000001B3

    // ---------------------------------------------------------------- 月历范围

    /** 以首次当前月为 anchor 的前后各 120 个月，共 241 项（不预构造 RemoteViews）。 */
    const val CALENDAR_MONTH_RADIUS = 120
    const val CALENDAR_MONTH_COUNT = CALENDAR_MONTH_RADIUS * 2 + 1

    /** anchor 月（列表正中）的下标。 */
    const val CALENDAR_ANCHOR_INDEX = CALENDAR_MONTH_RADIUS

    /** 第 [index] 项对应的自然月；越界返回 null（lazy getViewAt 只算当前项）。 */
    fun monthAt(anchor: YearMonth, index: Int): YearMonth? {
        if (index < 0 || index >= CALENDAR_MONTH_COUNT) return null
        return anchor.plusMonths((index - CALENDAR_MONTH_RADIUS).toLong())
    }

    /** [month] 在 anchor ±120 范围内的下标；不在范围内返回 null。 */
    fun indexOfMonth(anchor: YearMonth, month: YearMonth): Int? {
        val offset = monthIndex(month) - monthIndex(anchor)
        val index = offset + CALENDAR_MONTH_RADIUS
        return if (index in 0 until CALENDAR_MONTH_COUNT) index else null
    }

    /** 稳定月份 ID：`year * 100 + month`，跨刷新/跨方向恒定。 */
    fun monthItemId(month: YearMonth): Long =
        month.year.toLong() * 100L + month.monthValue.toLong()

    private fun monthIndex(month: YearMonth): Int = month.year * 12 + (month.monthValue - 1)
}
