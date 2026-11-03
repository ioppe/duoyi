package com.duoyi.duoyi

import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId

/**
 * 月历网格的单格（纯数据）。
 *
 * - [date] / [dayOfMonth] 为 null 表示 leading / trailing 的保留空格位（仍占列位置）。
 * - [count] 是该天的事项数：0 表示不显示角标，正数精确显示（不做 99+）。
 * - [isToday] 只在应用时区里"今天"那一格为 true。
 *
 * 该类型不引用 Android 或 org.json，可直接在 JVM 单元测试里断言。
 */
data class DuoyiCalendarDayCell(
    val date: LocalDate?,
    val dayOfMonth: Int?,
    val count: Int,
    val isToday: Boolean,
) {
    /** leading / trailing 保留位。 */
    val isBlank: Boolean get() = date == null

    /** 角标只在正整数时显示，0 隐藏。 */
    val hasBadge: Boolean get() = !isBlank && count > 0

    /** canonical ISO 日期（`LocalDate.toString`），同时用作计数 key 与无障碍描述。 */
    val isoDate: String? get() = date?.toString()
}

/**
 * 一个自然月的完整 7 列网格：`weekCount * 7` 个格子，按周一为第一列排列。
 *
 * 永远包含当月 1 日到 lastDay 的每个日期且恰好一次；不追加全空周，
 * 也不存在 compact / detailed / weekRows 之类的截断参数。
 */
data class DuoyiCalendarMonthGrid(
    val month: YearMonth,
    /** 1 日相对周一的列偏移（0 = 周一 … 6 = 周日）。 */
    val firstOffset: Int,
    val weekCount: Int,
    val cells: List<DuoyiCalendarDayCell>,
) {
    /** 逐周切好的行（每行恰好 7 格）。 */
    val rows: List<List<DuoyiCalendarDayCell>> = cells.chunked(DuoyiCalendarMonth.COLUMNS)

    fun row(index: Int): List<DuoyiCalendarDayCell> = rows.getOrElse(index) { emptyList() }

    /** 当月真实日期（按顺序，每个日期恰好一次）。 */
    val dates: List<LocalDate> get() = cells.mapNotNull { it.date }
}

/** 日期行与角标行的字号组合（sp）。两者始终为正。 */
data class DuoyiCalendarTextSizes(
    val dateSp: Float,
    val badgeSp: Float,
)

/** 月历模型的构造入口：只读取调用方传入的时区/今天/计数快照，自身不读偏好。 */
object DuoyiCalendarMonth {
    const val COLUMNS = 7

    /** `calendar_day_count_label` 缺失或占位符不全时的无障碍文案回退。 */
    const val DAY_COUNT_LABEL_FALLBACK = "{date}，{count} 项"

    /** `calendar_weekdays_json` 缺失/不完整时的既有中文回退（周一至周日）。 */
    val FALLBACK_WEEKDAY_LABELS: List<String> = listOf("一", "二", "三", "四", "五", "六", "日")

    /**
     * 生成 [month] 的完整月网格。
     *
     * [today] 由调用方按应用时区只读一次后传入，保证同一次刷新内跨方向/跨实例一致；
     * [countsByIso] 的 key 必须是 canonical ISO 日期，负值/缺失一律按 0 处理，
     * 其他月份的计数不会泄漏到本月。
     */
    fun build(
        month: YearMonth,
        today: LocalDate,
        countsByIso: Map<String, Int> = emptyMap(),
    ): DuoyiCalendarMonthGrid {
        val length = month.lengthOfMonth()
        val firstOffset = month.atDay(1).dayOfWeek.value - 1
        val weekCount = (firstOffset + length + COLUMNS - 1) / COLUMNS
        val cells = ArrayList<DuoyiCalendarDayCell>(weekCount * COLUMNS)
        for (index in 0 until weekCount * COLUMNS) {
            val dayOfMonth = index - firstOffset + 1
            if (dayOfMonth < 1 || dayOfMonth > length) {
                cells += DuoyiCalendarDayCell(null, null, 0, false)
                continue
            }
            val date = month.atDay(dayOfMonth)
            val raw = countsByIso[date.toString()]
            val count = if (raw == null || raw < 0) 0 else raw
            cells += DuoyiCalendarDayCell(date, dayOfMonth, count, date == today)
        }
        return DuoyiCalendarMonthGrid(month, firstOffset, weekCount, cells)
    }

    /** `calendar_timezone` 的 IANA 时区；缺失或非法时回落系统默认时区。 */
    fun zoneOrDefault(id: String?): ZoneId {
        val trimmed = id?.trim().orEmpty()
        if (trimmed.isEmpty()) return ZoneId.systemDefault()
        return runCatching { ZoneId.of(trimmed) }.getOrElse { ZoneId.systemDefault() }
    }

    /** 把外部标签数组规范成恰好 7 个非空标签，缺位用中文回退。 */
    fun normalizeWeekdayLabels(labels: List<String>?): List<String> =
        (0 until COLUMNS).map { index ->
            val label = labels?.getOrNull(index)?.trim().orEmpty()
            if (label.isEmpty()) FALLBACK_WEEKDAY_LABELS[index] else label
        }

    /** 无障碍文案：0 事项只报日期；正数按模板替换 `{date}` / `{count}`。 */
    fun formatCountLabel(template: String?, isoDate: String, count: Int): String {
        if (count <= 0) return isoDate
        val usable = template
            ?.takeIf { it.contains("{date}") && it.contains("{count}") }
            ?: DAY_COUNT_LABEL_FALLBACK
        return usable.replace("{date}", isoDate).replace("{count}", count.toString())
    }

    // ---------------------------------------------------------------- 字号选择

    /** 常规档：日期 11sp / 角标 8sp。 */
    const val DEFAULT_DATE_SP = 11f
    const val DEFAULT_BADGE_SP = 8f
    /** 6 周月优先档：日期 10sp / 角标 7sp。 */
    const val SIX_WEEK_DATE_SP = 10f
    const val SIX_WEEK_BADGE_SP = 7f
    /** 首选下限：低于此值改用"按可用高度等比缩小"路径。 */
    const val MIN_DATE_SP = 7f
    const val MIN_BADGE_SP = 6f
    /** 日期行与角标行之间的固定间隔（与 day cell XML 的 marginTop 一致）。 */
    const val BADGE_GAP_DP = 1f
    /** 极端回退的最小正字号：物理预算不足时仍返回 1sp，绝不返回 0/负值。 */
    const val MIN_RENDERABLE_SP = 1f
    const val SIX_WEEK_THRESHOLD = 6
    /** 月份标题模板缺失或非法时的中文回退。 */
    const val MONTH_TITLE_FALLBACK = "{year}年{month}月"
    private const val SIZE_STEP_SP = 0.5f
    /** 角标字号相对日期字号的常规差值（11/8、10/7）。 */
    private const val BADGE_DELTA_SP = 3f
    /** 等比缩小时每步的比例（配合实测回检，处理整像素非线性）。 */
    private const val SHRINK_FACTOR = 0.92f
    /** 等比缩小后预留的安全边界，保证实测合计严格 <= 可用高度。 */
    private const val SHRINK_SAFETY = 0.97f
    /** 有限迭代上限：到顶即进入安全回退，不会死循环。 */
    private const val MAX_SHRINK_STEPS = 64
    private const val FIT_EPSILON_DP = 0.01f
    private const val STEP_EPSILON = 0.001f

    /** 常规优先字号：<=5 周 11/8，6 周 10/7。 */
    fun preferredTextSizes(weekCount: Int): DuoyiCalendarTextSizes =
        if (weekCount >= SIX_WEEK_THRESHOLD) {
            DuoyiCalendarTextSizes(SIX_WEEK_DATE_SP, SIX_WEEK_BADGE_SP)
        } else {
            DuoyiCalendarTextSizes(DEFAULT_DATE_SP, DEFAULT_BADGE_SP)
        }

    /**
     * 选出整月 [weekCount] 行都放得下的日期 / 角标字号。
     *
     * 1. 先按常规档（11/8，6 周 10/7）每 0.5sp 递减到 7/6 下限；
     * 2. 下限仍放不下（110dp 旧实例 6 周只剩约 29.5dp）时，用每行实测预算
     *    `availableDp / weekCount - badgeGapDp` 对 date/badge 等比缩小，随后每步都用
     *    [lineDp] 重新实测回检，专门处理 ceil / 整像素度量造成的非线性；
     * 3. 连 1sp+1sp+gap 都放不下时返回 [MIN_RENDERABLE_SP]，属于明确的安全回退，
     *    由容器裁剪，绝不返回 0/负值，也绝不通过删周掩盖。
     *
     * 迭代次数有上限（[MAX_SHRINK_STEPS]），不会死循环。[lineDp] 必须是真实字体度量
     * （自身已包含 fontScale 与 density），返回 0 会被视为放不下。
     */
    fun chooseTextSizes(
        availableDp: Float,
        weekCount: Int,
        badgeGapDp: Float = BADGE_GAP_DP,
        lineDp: (Float) -> Float,
    ): DuoyiCalendarTextSizes {
        val preferred = preferredTextSizes(weekCount)
        if (weekCount <= 0) return preferred
        val gapDp = if (badgeGapDp.isFinite() && badgeGapDp > 0f) badgeGapDp else BADGE_GAP_DP
        if (!availableDp.isFinite() || availableDp <= 0f) return preferred

        var dateSp = preferred.dateSp
        var badgeSp = preferred.badgeSp
        while (dateSp >= MIN_DATE_SP - STEP_EPSILON) {
            if (fits(dateSp, badgeSp, availableDp, weekCount, gapDp, lineDp)) {
                return DuoyiCalendarTextSizes(dateSp, badgeSp)
            }
            if (dateSp <= MIN_DATE_SP + STEP_EPSILON) break
            dateSp = (dateSp - SIZE_STEP_SP).coerceAtLeast(MIN_DATE_SP)
            badgeSp = (dateSp - BADGE_DELTA_SP).coerceAtLeast(MIN_BADGE_SP)
        }

        // 首选下限放不下：按每行可用高度等比缩小，再逐步实测回检。
        val perRowDp = availableDp / weekCount - gapDp
        val floorRowDp = lineDp(MIN_DATE_SP) + lineDp(MIN_BADGE_SP)
        var scale = if (perRowDp > 0f && floorRowDp.isFinite() && floorRowDp > 0f) {
            (perRowDp / floorRowDp * SHRINK_SAFETY).coerceIn(0f, 1f)
        } else {
            0f
        }
        if (scale <= 0f) scale = SHRINK_SAFETY
        var smallDate = (MIN_DATE_SP * scale).coerceAtLeast(MIN_RENDERABLE_SP)
        var smallBadge = (MIN_BADGE_SP * scale).coerceAtLeast(MIN_RENDERABLE_SP)
        var steps = 0
        while (steps < MAX_SHRINK_STEPS) {
            if (fits(smallDate, smallBadge, availableDp, weekCount, gapDp, lineDp)) {
                return DuoyiCalendarTextSizes(smallDate, smallBadge)
            }
            val atFloor = smallDate <= MIN_RENDERABLE_SP + STEP_EPSILON &&
                smallBadge <= MIN_RENDERABLE_SP + STEP_EPSILON
            if (atFloor) break
            smallDate = (smallDate * SHRINK_FACTOR).coerceAtLeast(MIN_RENDERABLE_SP)
            smallBadge = (smallBadge * SHRINK_FACTOR).coerceAtLeast(MIN_RENDERABLE_SP)
            steps++
        }
        // 物理预算连 1sp + 1sp + gap 都放不下：返回最小正字号（明确的安全回退）。
        return DuoyiCalendarTextSizes(MIN_RENDERABLE_SP, MIN_RENDERABLE_SP)
    }

    /**
     * 月份标题：优先用 Flutter 传来的模板（zh `{year}年{month}月` / en `{year}-{month}`），
     * 有效模板必须同时含 `{year}` 与 `{month}`；模板缺失/非法时回退中文格式。
     * 月份不补零，与 Flutter 预览保持一致。
     */
    fun formatMonthTitle(template: String?, today: LocalDate): String {
        val usable = template
            ?.trim()
            ?.takeIf { it.contains("{year}") && it.contains("{month}") }
            ?: MONTH_TITLE_FALLBACK
        return usable
            .replace("{year}", today.year.toString())
            .replace("{month}", today.monthValue.toString())
    }

    /** 按真实度量回检：整月每行 = 日期行高 + 角标行高 + 固定间隔。 */
    private fun fits(
        dateSp: Float,
        badgeSp: Float,
        availableDp: Float,
        weekCount: Int,
        gapDp: Float,
        lineDp: (Float) -> Float,
    ): Boolean {
        val dateDp = lineDp(dateSp)
        val badgeDp = lineDp(badgeSp)
        if (!dateDp.isFinite() || !badgeDp.isFinite() || dateDp <= 0f || badgeDp <= 0f) return false
        return weekCount * (dateDp + badgeDp + gapDp) <= availableDp + FIT_EPSILON_DP
    }
}
