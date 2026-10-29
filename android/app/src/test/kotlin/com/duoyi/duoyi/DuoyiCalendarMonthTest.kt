package com.duoyi.duoyi

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import kotlin.math.ceil
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 月历纯模型的语义测试：直接断言具体日期、列偏移与周数，
 * 不复制生产实现的分支逻辑。
 */
class DuoyiCalendarMonthTest {

    private fun grid(month: YearMonth, today: LocalDate = month.atDay(1), counts: Map<String, Int> = emptyMap()) =
        DuoyiCalendarMonth.build(month, today, counts)

    @Test
    fun october2026StartsOnThursdayAndCoversEveryDayOnceInFiveWeeks() {
        val month = YearMonth.of(2026, 10)
        val result = grid(month)

        // 2026-10-01 是周四 => 列偏移 3（周一为 0），31 天 + 3 = 34 => 5 个整周。
        assertEquals(3, result.firstOffset)
        assertEquals(5, result.weekCount)
        assertEquals(35, result.cells.size)
        assertEquals(31, result.dates.size)
        assertEquals(31, result.dates.distinct().size)
        assertEquals(LocalDate.of(2026, 10, 1), result.dates.first())
        assertEquals(LocalDate.of(2026, 10, 31), result.dates.last())

        // 第 1 天必须落在第 0 行的第 3 列（周四），前 3 格是保留位。
        assertEquals(LocalDate.of(2026, 10, 1), result.cells[3].date)
        assertEquals(DayOfWeek.THURSDAY, result.cells[3].date?.dayOfWeek)
        assertTrue(result.cells[0].isBlank)
        assertTrue(result.cells[1].isBlank)
        assertTrue(result.cells[2].isBlank)
        // 31 日落在本周第 6 列（cells[33]），cells[34] 是唯一尾部保留位：不产生全空周。
        assertEquals(31, result.cells[33].dayOfMonth)
        assertTrue(result.cells[34].isBlank)
        assertEquals(listOf(26, 27, 28, 29, 30, 31), result.row(4).mapNotNull { it.dayOfMonth })
    }

    @Test
    fun leapFebruary2024IncludesThe29thInFiveWeeks() {
        val result = grid(YearMonth.of(2024, 2))

        assertEquals(3, result.firstOffset) // 2024-02-01 是周四
        assertEquals(5, result.weekCount)
        assertEquals(29, result.dates.size)
        assertTrue(result.dates.contains(LocalDate.of(2024, 2, 29)))
        assertEquals(29, result.cells[31].dayOfMonth)
    }

    @Test
    fun february2021StartsOnMondayAndIsExactlyFourWeeksWithoutEmptyWeek() {
        val result = grid(YearMonth.of(2021, 2))

        assertEquals(0, result.firstOffset)
        assertEquals(4, result.weekCount)
        assertEquals(28, result.cells.size)
        assertEquals(28, result.dates.size)
        assertFalse(result.cells.any { it.isBlank })
        assertEquals(1, result.cells[0].dayOfMonth)
        assertEquals(28, result.cells[27].dayOfMonth)
        assertEquals(DayOfWeek.MONDAY, result.cells[0].date?.dayOfWeek)
    }

    @Test
    fun august2020UsesSixWeeksAndKeepsTheLastDay() {
        val result = grid(YearMonth.of(2020, 8))

        assertEquals(5, result.firstOffset) // 2020-08-01 是周六
        assertEquals(6, result.weekCount)
        assertEquals(42, result.cells.size)
        assertEquals(31, result.dates.size)
        assertEquals(31, result.cells[35].dayOfMonth)
        assertEquals(LocalDate.of(2020, 8, 31), result.dates.last())
        // 36..41 是尾部保留位，最后一行只有 31 号一天，但整行仍保留列位置。
        (36 until 42).forEach { assertTrue(result.cells[it].isBlank) }
        assertEquals(6, result.rows.size)
        assertTrue(result.rows.all { it.size == 7 })
    }

    @Test
    fun todayMarkerIsSetOnlyOnTheGivenDate() {
        val month = YearMonth.of(2026, 10)
        val today = LocalDate.of(2026, 10, 15)
        val result = grid(month, today)

        val marked = result.cells.filter { it.isToday }
        assertEquals(1, marked.size)
        assertEquals(today, marked.single().date)
        assertEquals(15, marked.single().dayOfMonth)
        // 列偏移 3 + 15 号 => cells[17]，正好落在第 2 行第 3 列。
        assertEquals(3 + 15 - 1, result.cells.indexOfFirst { it.isToday })
        // 2026-10-15 是周四 => 第 3 列。
        assertEquals(3, result.cells.indexOfFirst { it.isToday } % 7)
    }

    @Test
    fun dayCountsMapToExactBadgesAndIgnoreZeroNegativeAndOtherMonths() {
        val month = YearMonth.of(2026, 10)
        val counts = mapOf(
            "2026-10-01" to 3,
            "2026-10-02" to 0,
            "2026-10-03" to -2,
            "2026-10-31" to 12,
            "2026-11-05" to 9,
        )
        val result = grid(month, counts = counts)

        assertEquals(31, result.dates.size)
        val first = result.cells[3]
        assertEquals(LocalDate.of(2026, 10, 1), first.date)
        assertEquals(3, first.count)
        assertTrue(first.hasBadge)

        val zero = result.cells[4]
        assertEquals(0, zero.count)
        assertFalse(zero.hasBadge)

        val negative = result.cells[5]
        assertEquals(0, negative.count)
        assertFalse(negative.hasBadge)

        val last = result.cells[33]
        assertEquals(12, last.count)
        assertTrue(last.hasBadge)

        // 其他月份的高计数不得泄漏到本月任何一格；只有 1 日与 31 日显示角标。
        assertEquals(0, result.cells.count { it.count == 9 })
        assertEquals(2, result.cells.count { it.hasBadge })
    }

    @Test
    fun withoutCountsTheWholeMonthStillRendersWithBadgesHidden() {
        val result = grid(YearMonth.of(2026, 10))

        assertEquals(31, result.dates.size)
        assertTrue(result.cells.none { it.hasBadge })
        assertTrue(result.cells.all { it.count == 0 })
        assertEquals(5, result.weekCount)
    }

    @Test
    fun countLabelUsesTemplateOrFallsBackAndOmitsZero() {
        assertEquals(
            "2026-10-01，3 个事项",
            DuoyiCalendarMonth.formatCountLabel("{date}，{count} 个事项", "2026-10-01", 3),
        )
        assertEquals(
            "2026-10-01，3 项",
            DuoyiCalendarMonth.formatCountLabel(null, "2026-10-01", 3),
        )
        assertEquals(
            "2026-10-02",
            DuoyiCalendarMonth.formatCountLabel("{date}，{count} 项", "2026-10-02", 0),
        )
        assertEquals(
            "2026-10-03",
            DuoyiCalendarMonth.formatCountLabel("{date}，{count} 项", "2026-10-03", 0),
        )
    }

    @Test
    fun weekdayLabelsAlwaysNormalizeToSevenEntries() {
        assertEquals(
            listOf("一", "二", "三", "四", "五", "六", "日"),
            DuoyiCalendarMonth.normalizeWeekdayLabels(null),
        )
        assertEquals(
            listOf("Mon", "二", "三", "四", "五", "六", "日"),
            DuoyiCalendarMonth.normalizeWeekdayLabels(listOf("Mon", "", "  ")),
        )
        assertEquals(
            listOf("Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"),
            DuoyiCalendarMonth.normalizeWeekdayLabels(
                listOf("Mo", "Tu", "We", "Th", "Fr", "Sa", "Su", "ignored"),
            ),
        )
        assertEquals(
            listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"),
            DuoyiCalendarMonth.normalizeWeekdayLabels(
                listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"),
            ),
        )
    }

    @Test
    fun timezoneFallsBackToSystemDefaultWhenMissingOrInvalid() {
        assertEquals(ZoneId.systemDefault(), DuoyiCalendarMonth.zoneOrDefault(null))
        assertEquals(ZoneId.systemDefault(), DuoyiCalendarMonth.zoneOrDefault("  "))
        assertEquals(ZoneId.systemDefault(), DuoyiCalendarMonth.zoneOrDefault("Not/AZone"))
        assertEquals(ZoneId.of("Asia/Shanghai"), DuoyiCalendarMonth.zoneOrDefault("Asia/Shanghai"))
    }

    // ------------------------------------------------- 字号几何（110dp 6 周等边界）

    /** 连续度量：fontScale × 行高比（不取整），用于验证等比缩小本身。 */
    private fun continuousLineDp(fontScale: Float = 1f): (Float) -> Float =
        { sp -> sp * fontScale * LINE_RATIO }

    /** 真实度量近似：先乘 fontScale/density 再 ceil 成整像素，回检必须处理这种非线性。 */
    private fun pixelLineDp(fontScale: Float = 1f, density: Float = 2.75f): (Float) -> Float =
        { sp -> ceil(sp * fontScale * LINE_RATIO * density) / density }

    @Test
    fun sixWeekTinyBudgetShrinksBelowPreferredFloorAndStillFits() {
        val lineDp = continuousLineDp(fontScale = 1.2f)
        // 110dp 旧实例 6 周：扣掉顶栏/星期行/底栏后只剩约 29.5dp。
        val sizes = DuoyiCalendarMonth.chooseTextSizes(
            availableDp = 29.5f,
            weekCount = 6,
            lineDp = lineDp,
        )

        assertTrue("日期字号必须为正: ${sizes.dateSp}", sizes.dateSp > 0f)
        assertTrue("角标字号必须为正: ${sizes.badgeSp}", sizes.badgeSp > 0f)
        // 必须低于首选下限 7/6，而不是假装放得下。
        assertTrue(sizes.dateSp < DuoyiCalendarMonth.MIN_DATE_SP)
        assertTrue(sizes.badgeSp < DuoyiCalendarMonth.MIN_BADGE_SP)
        val total = 6 * (
            lineDp(sizes.dateSp) + lineDp(sizes.badgeSp) +
                DuoyiCalendarMonth.BADGE_GAP_DP
            )
        assertTrue("实测合计 $total 必须 <= 29.5dp", total <= 29.5f)
    }

    @Test
    fun sixWeekNormalBudgetKeepsReasonableReadableSize() {
        val lineDp = continuousLineDp()
        val available = 117f
        val sizes = DuoyiCalendarMonth.chooseTextSizes(
            availableDp = available,
            weekCount = 6,
            lineDp = lineDp,
        )

        // 117dp 足够支持接近首选的档位，不能直接跌到 1sp。
        assertTrue("日期字号 ${sizes.dateSp} 不应低于 8sp", sizes.dateSp >= 8f)
        assertTrue(sizes.dateSp <= DuoyiCalendarMonth.SIX_WEEK_DATE_SP)
        assertTrue(sizes.badgeSp > 0f)
        val total = 6 * (
            lineDp(sizes.dateSp) + lineDp(sizes.badgeSp) +
                DuoyiCalendarMonth.BADGE_GAP_DP
            )
        assertTrue("实测合计 $total 必须 <= $available", total <= available)
    }

    @Test
    fun fourAndFiveWeekMonthsKeepPreferredSizes() {
        val lineDp = continuousLineDp()
        val available = 117f

        for (weeks in intArrayOf(4, 5)) {
            val sizes = DuoyiCalendarMonth.chooseTextSizes(
                availableDp = available,
                weekCount = weeks,
                lineDp = lineDp,
            )
            assertTrue(
                "第 $weeks 周应保持首选 11sp，实际 ${sizes.dateSp}",
                abs(sizes.dateSp - DuoyiCalendarMonth.DEFAULT_DATE_SP) < TOLERANCE_SP,
            )
            assertTrue(
                "第 $weeks 周应保持首选 8sp，实际 ${sizes.badgeSp}",
                abs(sizes.badgeSp - DuoyiCalendarMonth.DEFAULT_BADGE_SP) < TOLERANCE_SP,
            )
            val total = weeks * (
                lineDp(sizes.dateSp) + lineDp(sizes.badgeSp) +
                    DuoyiCalendarMonth.BADGE_GAP_DP
                )
            assertTrue("实测合计 $total 必须 <= $available", total <= available)
        }
    }

    @Test
    fun integerPixelMeasurementsStillPassTheFitCheck() {
        val lineDp = pixelLineDp()
        for (available in floatArrayOf(29.5f, 60f, 117f)) {
            val sizes = DuoyiCalendarMonth.chooseTextSizes(
                availableDp = available,
                weekCount = 6,
                lineDp = lineDp,
            )
            assertTrue(sizes.dateSp > 0f)
            assertTrue(sizes.badgeSp > 0f)
            // 每行按整像素 ceil 后回检，合计仍不得超过可用高度。
            val total = 6 * (
                lineDp(sizes.dateSp) + lineDp(sizes.badgeSp) +
                    DuoyiCalendarMonth.BADGE_GAP_DP
                )
            assertTrue("整像素合计 $total 必须 <= $available", total <= available + 0.001f)
        }
    }

    @Test
    fun impossibleBudgetReturnsPositiveFloorInsteadOfPretendingToFit() {
        val lineDp = continuousLineDp(fontScale = 2f)
        val sizes = DuoyiCalendarMonth.chooseTextSizes(
            availableDp = 2f,
            weekCount = 6,
            lineDp = lineDp,
        )

        // 连 1sp+1sp+gap 都放不下：明确的安全回退，仍为正字号，不返回 0/负值。
        assertTrue(
            "极端预算应回退到最小正字号，实际 ${sizes.dateSp}",
            abs(sizes.dateSp - DuoyiCalendarMonth.MIN_RENDERABLE_SP) < TOLERANCE_SP,
        )
        assertTrue(
            "极端预算应回退到最小正字号，实际 ${sizes.badgeSp}",
            abs(sizes.badgeSp - DuoyiCalendarMonth.MIN_RENDERABLE_SP) < TOLERANCE_SP,
        )
        assertTrue(sizes.dateSp > 0f && sizes.badgeSp > 0f)
    }

    // ------------------------------------------------------------ 月份标题

    @Test
    fun monthTitleUsesFlutterTemplateWithFallback() {
        val may2026 = LocalDate.of(2026, 5, 20)
        assertEquals("2026年5月", DuoyiCalendarMonth.formatMonthTitle(null, may2026))
        assertEquals(
            "2026年5月",
            DuoyiCalendarMonth.formatMonthTitle("{year}年{month}月", may2026),
        )
        assertEquals("2026-5", DuoyiCalendarMonth.formatMonthTitle("{year}-{month}", may2026))
        // 模板必须同时含两个占位符，否则回退中文格式。
        assertEquals("2026年5月", DuoyiCalendarMonth.formatMonthTitle("{year}年", may2026))
        assertEquals("2026年5月", DuoyiCalendarMonth.formatMonthTitle("  ", may2026))
        // 跨年：用传入日期替换，不能沿用当前时间。
        val jan2027 = LocalDate.of(2027, 1, 3)
        assertEquals(
            "2027年1月",
            DuoyiCalendarMonth.formatMonthTitle("{year}年{month}月", jan2027),
        )
        assertEquals("2027-1", DuoyiCalendarMonth.formatMonthTitle("{year}-{month}", jan2027))
    }

    private companion object {
        /** 与真实 CJK 行高比例一致，仅用于构造可解释的几何度量。 */
        const val LINE_RATIO = 1.17f
        /** 字号浮点比较容差（sp）。 */
        const val TOLERANCE_SP = 0.0001f
    }
}
