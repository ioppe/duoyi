import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_clock.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/lunar_calendar.dart';
import '../models/anniversary.dart';
import '../models/countdown.dart';
import '../providers/anniversary_provider.dart';
import '../providers/countdown_provider.dart';
import '../services/holiday_calendar.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/surface_components.dart';

enum AlmanacEntryMode { calendar, almanac }

/// 万年历页面。保留 `almanac` 枚举用于兼容旧深链/测试，入口统一展示万年历。
class AlmanacScreen extends StatefulWidget {
  final DateTime? initialDate;
  final AlmanacEntryMode initialMode;

  const AlmanacScreen({
    super.key,
    this.initialDate,
    this.initialMode = AlmanacEntryMode.calendar,
  });

  @override
  State<AlmanacScreen> createState() => _AlmanacScreenState();
}

class _AlmanacScreenState extends State<AlmanacScreen> {
  static final DateTime _firstSupportedDate = DateTime(1900);
  static final DateTime _lastSupportedDate = DateTime(2099, 12, 31);

  late DateTime _date;
  DateTime _lastToday = AppClock.today();
  final Map<String, _MonthCalendarData> _monthDataCache =
      <String, _MonthCalendarData>{};
  final Map<String, List<_MonthHighlight>> _fixedMonthHighlightCache =
      <String, List<_MonthHighlight>>{};

  @override
  void initState() {
    super.initState();
    _date = _clampDate(widget.initialDate ?? AppClock.now());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppClock.watch(context);
    final today = AppClock.today();
    if (today != _lastToday && _date == _lastToday) _date = _clampDate(today);
    _lastToday = today;
  }

  DateTime _clampDate(DateTime value) {
    final day = DateTime(value.year, value.month, value.day);
    if (day.isBefore(_firstSupportedDate)) return _firstSupportedDate;
    if (day.isAfter(_lastSupportedDate)) return _lastSupportedDate;
    return day;
  }

  Future<void> _pickDate() async {
    final picked = await AppDatePicker.pickSolar(
      context,
      initialDate: _clampDate(_date),
      firstDate: _firstSupportedDate,
      lastDate: _lastSupportedDate,
      title: '万年历',
    );
    if (!mounted) return;
    if (picked != null) setState(() => _date = _clampDate(picked));
  }

  void _goToday() {
    final today = _clampDate(AppClock.now());
    final alreadyToday =
        _date.year == today.year &&
        _date.month == today.month &&
        _date.day == today.day;
    if (!alreadyToday) {
      setState(() => _date = today);
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(alreadyToday ? '已经是今天' : '已回到今天'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _shiftMonth(int months) {
    final targetMonth = DateTime(_date.year, _date.month + months, 1);
    final lastDay = DateTime(targetMonth.year, targetMonth.month + 1, 0).day;
    final nextDay = _date.day <= lastDay ? _date.day : lastDay;
    setState(() {
      _date = _clampDate(
        DateTime(targetMonth.year, targetMonth.month, nextDay),
      );
    });
  }

  void _shiftDay(int days) {
    setState(() => _date = _clampDate(_date.add(Duration(days: days))));
  }

  void _showSelectedDateDetail() {
    _openAlmanacDetail(_date);
  }

  void _onDatePicked(DateTime date) {
    final selectedDate = _clampDate(date);
    setState(() => _date = selectedDate);
    // 仅更新选中日期，不自动打开黄历详情
  }

  Future<void> _openAlmanacDetail(DateTime selectedDate) async {
    final returnedDate = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute<DateTime>(
        builder: (_) => _AlmanacDetailPage(date: selectedDate),
      ),
    );
    if (!mounted || returnedDate == null) return;
    setState(() => _date = _clampDate(returnedDate));
  }

  _MonthCalendarData _monthDataFor(DateTime month) {
    final key = '${I18n.current.name}-${month.year}-${month.month}';
    return _monthDataCache.putIfAbsent(
      key,
      () => _MonthCalendarData.fromMonth(month),
    );
  }

  List<_MonthHighlight> _monthHighlightsFor({
    required DateTime month,
    required Iterable<CountdownItem> countdowns,
    required Iterable<Anniversary> anniversaries,
  }) {
    final key = '${I18n.current.name}-${month.year}-${month.month}';
    final fixed = _fixedMonthHighlightCache.putIfAbsent(
      key,
      () => _buildFixedMonthHighlights(monthData: _monthDataFor(month)),
    );
    return _mergeMonthHighlights([
      ...fixed,
      ..._buildUserMonthHighlights(
        month: month,
        countdowns: countdowns,
        anniversaries: anniversaries,
      ),
    ]);
  }

  List<(String, Color)> _dateBadges({
    required String? term,
    required String? solarFestival,
    required String? lunarFestival,
    required bool isHoliday,
    required bool isWorkMakeupDay,
  }) {
    return <(String, Color)>[
      if (term != null) ('节气 $term', const Color(0xFF2E7D32)),
      if (solarFestival != null) ('公历 $solarFestival', const Color(0xFFEF6C00)),
      if (lunarFestival != null && I18n.current == AppLocale.zh)
        ('农历 $lunarFestival', const Color(0xFFC2185B)),
      if (isHoliday) ('法定假日', const Color(0xFF00897B)),
      if (isWorkMakeupDay) ('调休上班', const Color(0xFF5E35B1)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    const pageTitle = '万年历';
    final selectedDate = _date;
    final almanacDetail = LunarCalendar.almanacDetail(selectedDate);
    final lunar = almanacDetail.lunarDate;
    final term = LunarCalendar.solarTerm(selectedDate);
    final solarFes = LunarCalendar.solarFestival(selectedDate);
    final lunarFes = LunarCalendar.lunarFestival(lunar);
    final isHoliday = HolidayCalendar.isHoliday(selectedDate);
    final isWorkMakeupDay = HolidayCalendar.isWorkMakeupDay(selectedDate);
    final dateBadges = _dateBadges(
      term: term,
      solarFestival: solarFes,
      lunarFestival: lunarFes,
      isHoliday: isHoliday,
      isWorkMakeupDay: isWorkMakeupDay,
    );
    final countdownProvider = context.watch<CountdownProvider?>();
    final anniversaryProvider = context.watch<AnniversaryProvider?>();
    final monthData = _monthDataFor(selectedDate);
    final monthHighlights = _monthHighlightsFor(
      month: selectedDate,
      countdowns: countdownProvider?.items ?? const <CountdownItem>[],
      anniversaries: anniversaryProvider?.items ?? const <Anniversary>[],
    );
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final routeBackground = theme.brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(pageTitle),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '前一天',
            onPressed: _date == _firstSupportedDate
                ? null
                : () => _shiftDay(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: '后一天',
            onPressed: _date == _lastSupportedDate ? null : () => _shiftDay(1),
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: '回到今天',
            onPressed: _goToday,
            icon: const Icon(Icons.today_outlined),
          ),
        ],
      ),
      body: ColoredBox(
        color: routeBackground.withValues(alpha: 0.92),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 940;
            final monthCalendar = _MonthCalendar(
              date: selectedDate,
              monthData: monthData,
              highlights: monthHighlights,
              onPick: _onDatePicked,
              onPreviousMonth: () => _shiftMonth(-1),
              onNextMonth: () => _shiftMonth(1),
              onTitleTap: _pickDate,
            );
            final summary = _SelectedDateSummaryCard(
              detail: almanacDetail,
              badges: dateBadges,
              onOpenAlmanac: _showSelectedDateDetail,
            );
            final highlights = _MonthHighlightsCard(
              selectedDate: selectedDate,
              highlights: monthHighlights,
            );
            return Scrollbar(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  wide ? 24 : 14,
                  6,
                  wide ? 24 : 14,
                  22 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        monthCalendar,
                        SizedBox(height: wide ? 16 : 12),
                        summary,
                        SizedBox(height: wide ? 22 : 18),
                        highlights,
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MonthCalendarData {
  final int year;
  final int month;
  final int daysInMonth;
  final int firstWeekdayOffset;
  final int rowCount;
  final List<_MonthDayData> days;

  const _MonthCalendarData({
    required this.year,
    required this.month,
    required this.daysInMonth,
    required this.firstWeekdayOffset,
    required this.rowCount,
    required this.days,
  });

  factory _MonthCalendarData.fromMonth(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    final offset = first.weekday - 1; // 周一为 0
    final days = <_MonthDayData>[];
    for (
      var day = first;
      !day.isAfter(last);
      day = day.add(const Duration(days: 1))
    ) {
      final lunar = I18n.current == AppLocale.zh
          ? LunarCalendar.fromSolar(day)
          : null;
      final term = LunarCalendar.solarTerm(day);
      final solarFestival = LunarCalendar.solarFestival(day);
      final lunarFestival = lunar == null
          ? null
          : LunarCalendar.lunarFestival(lunar);
      days.add(
        _MonthDayData(
          date: day,
          day: day.day,
          label:
              term ??
              solarFestival ??
              lunarFestival ??
              lunar?.shortDayOrMonth ??
              '',
          term: term,
          solarFestival: solarFestival,
          lunarFestival: lunarFestival,
          isWeekend: day.weekday >= DateTime.saturday,
          isHoliday: HolidayCalendar.isHoliday(day),
          isWorkMakeupDay: HolidayCalendar.isWorkMakeupDay(day),
        ),
      );
    }
    return _MonthCalendarData(
      year: month.year,
      month: month.month,
      daysInMonth: last.day,
      firstWeekdayOffset: offset,
      rowCount: ((last.day + offset) / 7).ceil(),
      days: List.unmodifiable(days),
    );
  }

  _MonthDayData? dayAt(int day) {
    if (day < 1 || day > daysInMonth) return null;
    return days[day - 1];
  }
}

class _MonthDayData {
  final DateTime date;
  final int day;
  final String label;
  final String? term;
  final String? solarFestival;
  final String? lunarFestival;
  final bool isWeekend;
  final bool isHoliday;
  final bool isWorkMakeupDay;

  const _MonthDayData({
    required this.date,
    required this.day,
    required this.label,
    required this.term,
    required this.solarFestival,
    required this.lunarFestival,
    required this.isWeekend,
    required this.isHoliday,
    required this.isWorkMakeupDay,
  });
}

List<_MonthHighlight> _buildFixedMonthHighlights({
  required _MonthCalendarData monthData,
}) {
  final labelsByDay = <int, List<_HighlightLabel>>{};

  void add(_MonthDayData day, String label, IconData icon, Color color) {
    labelsByDay
        .putIfAbsent(day.day, () => <_HighlightLabel>[])
        .add(_HighlightLabel(label: label, icon: icon, color: color));
  }

  for (final day in monthData.days) {
    final term = day.term;
    final solarFestival = day.solarFestival;
    final lunarFestival = day.lunarFestival;
    if (term != null) {
      add(day, '节气 · $term', Icons.eco_outlined, const Color(0xFF43A047));
    }
    if (solarFestival != null) {
      add(
        day,
        '节日 · $solarFestival',
        Icons.celebration_outlined,
        const Color(0xFFEF6C00),
      );
    }
    if (lunarFestival != null) {
      add(
        day,
        '农历 · $lunarFestival',
        Icons.local_florist_outlined,
        const Color(0xFFE91E63),
      );
    }
    if (day.isHoliday) {
      add(day, '法定假日', Icons.beach_access_outlined, const Color(0xFF00897B));
    }
    if (day.isWorkMakeupDay) {
      add(day, '调休上班', Icons.work_outline, const Color(0xFF5E35B1));
    }
  }

  return _highlightsFromLabels(
    year: monthData.year,
    month: monthData.month,
    labelsByDay: labelsByDay,
  );
}

List<_MonthHighlight> _buildUserMonthHighlights({
  required DateTime month,
  required Iterable<CountdownItem> countdowns,
  required Iterable<Anniversary> anniversaries,
}) {
  final first = DateTime(month.year, month.month, 1);
  final labelsByDay = <int, List<_HighlightLabel>>{};

  void add(DateTime date, String label, IconData icon, Color color) {
    if (date.year != month.year || date.month != month.month) return;
    labelsByDay
        .putIfAbsent(date.day, () => <_HighlightLabel>[])
        .add(_HighlightLabel(label: label, icon: icon, color: color));
  }

  for (final item in countdowns) {
    add(
      item.targetDate,
      '倒数日 · ${item.title}',
      Icons.hourglass_bottom_outlined,
      const Color(0xFF5E35B1),
    );
  }

  for (final item in anniversaries) {
    final occurrence = _anniversaryOccurrenceInMonth(
      item,
      month.year,
      month.month,
    );
    if (occurrence == null) continue;
    final (label, icon, color) = switch (item.type) {
      AnniversaryType.birthday => (
        '生日 · ${item.title}',
        Icons.cake_outlined,
        const Color(0xFFD81B60),
      ),
      AnniversaryType.memorial => (
        '纪念日 · ${item.title}',
        Icons.favorite_border,
        const Color(0xFFE53935),
      ),
      AnniversaryType.custom => (
        '纪念日 · ${item.title}',
        Icons.event_available_outlined,
        const Color(0xFF3949AB),
      ),
      AnniversaryType.normal => (
        '倒数日 · ${item.title}',
        Icons.hourglass_bottom_outlined,
        const Color(0xFF5E35B1),
      ),
    };
    add(occurrence, label, icon, color);
  }

  return _highlightsFromLabels(
    year: first.year,
    month: first.month,
    labelsByDay: labelsByDay,
  );
}

List<_MonthHighlight> _mergeMonthHighlights(List<_MonthHighlight> highlights) {
  final labelsByDay = <int, List<_HighlightLabel>>{};
  for (final highlight in highlights) {
    labelsByDay
        .putIfAbsent(highlight.date.day, () => <_HighlightLabel>[])
        .addAll(highlight.labels);
  }
  if (highlights.isEmpty) return const <_MonthHighlight>[];
  final sample = highlights.first.date;
  return _highlightsFromLabels(
    year: sample.year,
    month: sample.month,
    labelsByDay: labelsByDay,
  );
}

List<_MonthHighlight> _highlightsFromLabels({
  required int year,
  required int month,
  required Map<int, List<_HighlightLabel>> labelsByDay,
}) {
  final highlights = labelsByDay.entries.map((entry) {
    return _MonthHighlight(
      date: DateTime(year, month, entry.key),
      labels: entry.value,
    );
  }).toList();
  highlights.sort((a, b) => a.date.compareTo(b.date));
  return highlights;
}

DateTime? _anniversaryOccurrenceInMonth(Anniversary item, int year, int month) {
  if (item.type == AnniversaryType.normal) {
    return _isSameMonth(item.originDate, year, month) ? item.originDate : null;
  }
  if (item.calendarType == AnniversaryCalendarType.lunar) {
    final lunarMonth = item.lunarMonth;
    final lunarDay = item.lunarDay;
    if (lunarMonth == null || lunarDay == null) return null;
    try {
      final solar = LunarCalendar.toSolar(
        year,
        lunarMonth,
        lunarDay,
        isLeap: item.lunarIsLeap,
      );
      return _isSameMonth(solar, year, month) ? solar : null;
    } catch (_) {
      return null;
    }
  }
  final solar = DateTime(year, item.originDate.month, item.originDate.day);
  if (solar.month != item.originDate.month ||
      solar.day != item.originDate.day) {
    return null;
  }
  return _isSameMonth(solar, year, month) ? solar : null;
}

bool _isSameMonth(DateTime date, int year, int month) =>
    date.year == year && date.month == month;

class _HighlightLabel {
  final String label;
  final IconData icon;
  final Color color;

  const _HighlightLabel({
    required this.label,
    required this.icon,
    required this.color,
  });
}

class _MonthHighlight {
  final DateTime date;
  final List<_HighlightLabel> labels;

  const _MonthHighlight({required this.date, required this.labels});
}

class _MonthHighlightsCard extends StatelessWidget {
  final DateTime selectedDate;
  final List<_MonthHighlight> highlights;

  const _MonthHighlightsCard({
    required this.selectedDate,
    required this.highlights,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(
            cs.primary.withValues(alpha: isDark ? 0.050 : 0.026),
            cs.surface,
          ),
          cs.surface,
        ],
      ),
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: isDark ? 0.14 : 0.18),
        width: 0.55,
      ),
      elevation: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                '本月重点日期',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontSize: 13,
                  fontWeight: DesignTokens.fontWeightStrong,
                  color: cs.onSurface.withValues(alpha: 0.78),
                ),
              ),
              const Spacer(),
              Text(
                '${selectedDate.month} 月',
                style: appSecondaryControlLabelStyle(
                  context,
                ).copyWith(color: cs.onSurface.withValues(alpha: 0.54)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (highlights.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.16),
                    width: 0.45,
                  ),
                ),
              ),
              child: Text(
                '本月暂无重点日期',
                style: appSecondaryControlTextStyle(
                  context,
                ).copyWith(color: cs.onSurface.withValues(alpha: 0.62)),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.14),
                    width: 0.45,
                  ),
                ),
              ),
              child: Column(
                children: highlights
                    .take(12)
                    .map(
                      (highlight) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 34,
                              child: Text(
                                '${highlight.date.day}',
                                style: appSecondaryControlTextStyle(context)
                                    .copyWith(
                                      fontSize: 13,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.64,
                                      ),
                                    ),
                              ),
                            ),
                            Expanded(
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: highlight.labels.take(3).map((label) {
                                  return _SoftAlmanacTag(label: label);
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          if (highlights.length > 12)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '还有 ${highlights.length - 12} 个重点日期',
                style: appSecondaryControlLabelStyle(
                  context,
                ).copyWith(color: cs.onSurface.withValues(alpha: 0.52)),
              ),
            ),
        ],
      ),
    );
  }
}

class _SoftAlmanacTag extends StatelessWidget {
  final _HighlightLabel label;

  const _SoftAlmanacTag({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = Color.lerp(label.color, cs.onSurface, 0.28) ?? label.color;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.12), width: 0.45),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(label.icon, size: 12, color: color.withValues(alpha: 0.82)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: appSecondaryControlLabelStyle(
                  context,
                ).copyWith(color: cs.onSurface.withValues(alpha: 0.70)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedDateSummaryCard extends StatelessWidget {
  final LunarAlmanacDetail detail;
  final List<(String, Color)> badges;
  final VoidCallback onOpenAlmanac;

  const _SelectedDateSummaryCard({
    required this.detail,
    required this.badges,
    required this.onOpenAlmanac,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = Color.alphaBlend(
      cs.primary.withValues(alpha: isDark ? 0.08 : 0.045),
      cs.surface,
    );
    return Material(
      key: const ValueKey('selected_date_almanac_summary_card'),
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.14 : 0.18),
          width: 0.55,
        ),
      ),
      elevation: isDark ? 0 : 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: '查看黄历详情',
        child: Tooltip(
          message: '查看黄历详情',
          child: InkWell(
            onTap: onOpenAlmanac,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              detail.lunarDate.chineseText,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontSize: 16,
                                    fontWeight: DesignTokens.fontWeightStrong,
                                    color: cs.onSurface,
                                  ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _spacedGanzhiLine(detail.ganzhiLine),
                              style: appSecondaryControlTextStyle(context)
                                  .copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.62),
                                    height: 1.25,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: cs.onSurface.withValues(alpha: 0.42),
                      ),
                    ],
                  ),
                  if (badges.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: badges
                          .map(
                            (badge) =>
                                _AlmanacBadge(text: badge.$1, color: badge.$2),
                          )
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surface.withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? 0.32
                            : 0.62,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.14),
                        width: 0.45,
                      ),
                    ),
                    child: Column(
                      children: [
                        _SummaryYijiLine(
                          label: '宜',
                          text: _summaryTerms(detail.suitable),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Divider(
                            height: 1,
                            thickness: 0.45,
                            color: cs.outlineVariant.withValues(alpha: 0.20),
                          ),
                        ),
                        _SummaryYijiLine(
                          label: '忌',
                          text: _summaryTerms(detail.avoid),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryYijiLine extends StatelessWidget {
  final String label;
  final String text;

  const _SummaryYijiLine({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = label == '宜'
        ? const Color(0xFF2E7D32)
        : const Color(0xFFC62828);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: DesignTokens.fontWeightStrong,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: appSecondaryControlTextStyle(context).copyWith(
              color: cs.onSurface.withValues(alpha: 0.76),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _AlmanacDetailPage extends StatefulWidget {
  final DateTime date;

  const _AlmanacDetailPage({required this.date});

  @override
  State<_AlmanacDetailPage> createState() => _AlmanacDetailPageState();
}

class _AlmanacDetailPageState extends State<_AlmanacDetailPage> {
  static final DateTime _firstSupportedDate = DateTime(1900);
  static final DateTime _lastSupportedDate = DateTime(2099, 12, 31);
  late final PageController _pageController;
  late DateTime _date;
  final Map<int, LunarAlmanacDetail> _detailCache = <int, LunarAlmanacDetail>{};
  bool _allowPopWithResult = false;

  @override
  void initState() {
    super.initState();
    _date = _clampDate(widget.date);
    _pageController = PageController(initialPage: _pageForDate(_date));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DateTime _clampDate(DateTime value) {
    final day = _dateOnly(value);
    if (day.isBefore(_firstSupportedDate)) return _firstSupportedDate;
    if (day.isAfter(_lastSupportedDate)) return _lastSupportedDate;
    return day;
  }

  int get _pageCount => _pageForDate(_lastSupportedDate) + 1;

  int _pageForDate(DateTime date) {
    final day = _clampDate(date);
    // Calendar pages count civil dates, independent of local DST offsets.
    return DateTime.utc(day.year, day.month, day.day)
        .difference(
          DateTime.utc(
            _firstSupportedDate.year,
            _firstSupportedDate.month,
            _firstSupportedDate.day,
          ),
        )
        .inDays;
  }

  DateTime _dateForPage(int page) => _clampDate(
    DateTime(
      _firstSupportedDate.year,
      _firstSupportedDate.month,
      _firstSupportedDate.day + page,
    ),
  );

  LunarAlmanacDetail _detailFor(DateTime date) {
    final day = _dateOnly(date);
    final key = day.year * 10000 + day.month * 100 + day.day;
    return _detailCache.putIfAbsent(
      key,
      () => LunarCalendar.almanacDetail(day),
    );
  }

  void _popWithCurrentDate() {
    if (_allowPopWithResult) return;
    setState(() => _allowPopWithResult = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop(_date);
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detailFor(_date);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final pageBackground = isDark
        ? Color.alphaBlend(
            const Color(0xFFB39162).withValues(alpha: 0.05),
            cs.surface,
          )
        : const Color(0xFFFFFEFC);
    final title = _fullDateTitle(detail.solarDate);

    return PopScope<DateTime>(
      canPop: _allowPopWithResult,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _popWithCurrentDate();
      },
      child: Scaffold(
        backgroundColor: pageBackground,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: _AlmanacDetailNavBar(
            title: title,
            backgroundColor: pageBackground,
            onBack: _popWithCurrentDate,
          ),
        ),
        body: ColoredBox(
          color: pageBackground,
          child: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontal = constraints.maxWidth <= 420 ? 20.0 : 24.0;
                return PageView.builder(
                  controller: _pageController,
                  itemCount: _pageCount,
                  onPageChanged: (page) {
                    setState(() => _date = _dateForPage(page));
                  },
                  itemBuilder: (context, page) {
                    final pageDate = _dateForPage(page);
                    final pageDetail = _detailFor(pageDate);
                    return Scrollbar(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          horizontal,
                          12,
                          horizontal,
                          28,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 620),
                            child: _ClassicalAlmanacCard(detail: pageDetail),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AlmanacDetailNavBar extends StatelessWidget {
  final String title;
  final Color backgroundColor;
  final VoidCallback onBack;

  const _AlmanacDetailNavBar({
    required this.title,
    required this.backgroundColor,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Container(
        height: 56,
        color: backgroundColor,
        child: NavigationToolbar(
          leading: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: IconButton(
              tooltip: '返回',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_ios_new),
              iconSize: 20,
              color: cs.onSurface.withValues(alpha: 0.86),
            ),
          ),
          middle: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                maxLines: 1,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 18,
                  fontWeight: DesignTokens.fontWeightStrong,
                  letterSpacing: 0,
                  color: cs.onSurface,
                ),
              ),
            ),
          ),
          trailing: const SizedBox(width: 56),
        ),
      ),
    );
  }
}

class _ClassicalAlmanacCard extends StatelessWidget {
  final LunarAlmanacDetail detail;

  const _ClassicalAlmanacCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gold = const Color(0xFFB39162);
    final lineColor = gold.withValues(alpha: isDark ? 0.62 : 0.55);
    final cardColor = isDark
        ? Color.alphaBlend(
            gold.withValues(alpha: 0.04),
            theme.colorScheme.surface,
          )
        : Colors.white;
    final paperTint = Color.alphaBlend(
      gold.withValues(alpha: isDark ? 0.030 : 0.018),
      cardColor,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final textScale = _clampDouble(
          MediaQuery.textScalerOf(context).scale(1.0),
          1.0,
          1.28,
        );
        final pengZuLineCount = _splitPengZuLines(detail.pengZu).length;
        final fiveElementLineCount = _splitFiveElementLines(
          detail.fiveElements,
        ).length;
        final clashLineCount = _splitClashLines(detail.clash).length;
        final sideLineCount = fiveElementLineCount > clashLineCount
            ? fiveElementLineCount
            : clashLineCount;
        final topMinHeight = _clampDouble(width * 0.66 * textScale, 246, 370);
        final tableHeight = _clampDouble(
          width * 0.62 +
              (pengZuLineCount > 4 ? (pengZuLineCount - 4) * 15 : 0) +
              (sideLineCount > 2 ? (sideLineCount - 2) * 9 : 0) +
              ((textScale - 1) * 80),
          236,
          390,
        );
        final hourHeight = _clampDouble(width * 0.17 * textScale, 58, 76);

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [paperTint, cardColor],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: lineColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.075),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: topMinHeight,
                  child: _AlmanacTopVisual(
                    detail: detail,
                    lineColor: lineColor,
                    gold: gold,
                  ),
                ),
                _ClassicalDivider(color: lineColor),
                SizedBox(
                  height: tableHeight,
                  child: _ClassicalInfoTable(
                    detail: detail,
                    lineColor: lineColor,
                  ),
                ),
                _ClassicalDivider(color: lineColor),
                SizedBox(
                  height: hourHeight,
                  child: _ClassicalHourRow(
                    fortunes: detail.hourFortuneItems,
                    lineColor: lineColor,
                    gold: gold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AlmanacTopVisual extends StatelessWidget {
  final LunarAlmanacDetail detail;
  final Color lineColor;
  final Color gold;

  const _AlmanacTopVisual({
    required this.detail,
    required this.lineColor,
    required this.gold,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 32,
          child: _VerticalYijiPanel(
            suitable: detail.suitable,
            avoid: detail.avoid,
            gold: gold,
            lineColor: lineColor,
          ),
        ),
        _ClassicalVerticalDivider(color: lineColor),
        Expanded(
          flex: 68,
          child: _DateHeroPanel(detail: detail, gold: gold),
        ),
      ],
    );
  }
}

class _VerticalYijiPanel extends StatelessWidget {
  static const int _visibleTermLimit = 5;

  final String suitable;
  final String avoid;
  final Color gold;
  final Color lineColor;

  const _VerticalYijiPanel({
    required this.suitable,
    required this.avoid,
    required this.gold,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final darkText = cs.onSurface.withValues(alpha: 0.86);
    final suitableTerms = _splitAlmanacTerms(
      suitable,
    ).take(_visibleTermLimit).toList(growable: false);
    final avoidTerms = _splitAlmanacTerms(
      avoid,
    ).take(_visibleTermLimit).toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth =
            (constraints.maxWidth - 1).clamp(0, double.infinity) / 2;
        final textSize = columnWidth < 66 ? 13.0 : 14.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 13, 8, 10),
                child: _VerticalYijiColumn(
                  key: const ValueKey('almanac_vertical_suitable_column'),
                  keyName: 'suitable',
                  title: '宜',
                  terms: suitableTerms,
                  color: gold,
                  fontSize: textSize,
                ),
              ),
            ),
            _ClassicalVerticalDivider(color: lineColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 13, 10, 10),
                child: _VerticalYijiColumn(
                  key: const ValueKey('almanac_vertical_avoid_column'),
                  keyName: 'avoid',
                  title: '忌',
                  terms: avoidTerms,
                  color: darkText,
                  fontSize: textSize,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VerticalYijiColumn extends StatelessWidget {
  final String keyName;
  final String title;
  final List<String> terms;
  final Color color;
  final double fontSize;

  const _VerticalYijiColumn({
    super.key,
    required this.keyName,
    required this.title,
    required this.terms,
    required this.color,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: 0.62),
              width: 0.7,
            ),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: DesignTokens.fontWeightStrong,
              height: 1.0,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: FittedBox(
              key: ValueKey('almanac_vertical_${keyName}_terms_box'),
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: Column(
                key: ValueKey('almanac_vertical_${keyName}_terms'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final term in terms)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: _VerticalTerm(
                        term: term,
                        color: color,
                        fontSize: fontSize,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _VerticalTerm extends StatelessWidget {
  final String term;
  final Color color;
  final double fontSize;

  const _VerticalTerm({
    required this.term,
    required this.color,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fontSize + 6,
      child: Text(
        _verticalAlmanacTerm(term),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color.withValues(alpha: 0.90),
          fontSize: fontSize,
          height: 1.18,
        ),
        strutStyle: StrutStyle(
          fontSize: fontSize,
          height: 1.18,
          forceStrutHeight: true,
        ),
      ),
    );
  }
}

class _DateHeroPanel extends StatelessWidget {
  final LunarAlmanacDetail detail;
  final Color gold;

  const _DateHeroPanel({required this.detail, required this.gold});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final daySize = _clampDouble(constraints.maxWidth * 0.36, 76, 106);
        final lunarSize = _clampDouble(constraints.maxWidth * 0.13, 26, 36);
        final ganzhiSize = _clampDouble(constraints.maxWidth * 0.052, 13.5, 16);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${detail.solarDate.day}',
                maxLines: 1,
                style: TextStyle(
                  fontSize: daySize,
                  height: 0.92,
                  color: cs.onSurface,
                  letterSpacing: 0,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                detail.lunarDate.chineseText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: lunarSize,
                  height: 1.1,
                  color: cs.onSurface,
                  letterSpacing: 0,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                _spacedGanzhiLine(detail.ganzhiLine),
                maxLines: 3,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: ganzhiSize,
                  height: 1.35,
                  color: cs.onSurface.withValues(alpha: 0.58),
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ClassicalInfoTable extends StatelessWidget {
  final LunarAlmanacDetail detail;
  final Color lineColor;

  const _ClassicalInfoTable({required this.detail, required this.lineColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 32,
          child: Column(
            children: [
              Expanded(
                child: _ClassicalInfoCell(title: '胎神', value: detail.fetalGod),
              ),
              _ClassicalDivider(color: lineColor),
              Expanded(
                child: _ClassicalInfoCell(title: '星宿', value: detail.mansion),
              ),
            ],
          ),
        ),
        _ClassicalVerticalDivider(color: lineColor),
        Expanded(
          flex: 36,
          child: _ClassicalInfoCell(title: '彭祖', value: detail.pengZu),
        ),
        _ClassicalVerticalDivider(color: lineColor),
        Expanded(
          flex: 32,
          child: Column(
            children: [
              Expanded(
                child: _ClassicalInfoCell(
                  title: '五行',
                  value: detail.fiveElements,
                ),
              ),
              _ClassicalDivider(color: lineColor),
              Expanded(
                child: _ClassicalInfoCell(title: '冲煞', value: detail.clash),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ClassicalInfoCell extends StatelessWidget {
  final String title;
  final String value;

  const _ClassicalInfoCell({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPengZu = title == '彭祖';
    final isFiveElement = title == '五行';
    final isClash = title == '冲煞';
    final valueLines = isPengZu
        ? _splitPengZuLines(value)
        : isFiveElement
        ? _splitFiveElementLines(value)
        : isClash
        ? _splitClashLines(value)
        : [value.trim()];
    final titleSize = 16.0;
    final valueSize = 12.4;
    final valueHeight = isPengZu ? 1.48 : 1.36;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isPengZu ? 8 : 8,
        vertical: isPengZu ? 12 : 10,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: titleSize,
              height: 1.1,
              fontWeight: DesignTokens.fontWeightStrong,
              color: cs.onSurface,
            ),
          ),
          SizedBox(height: isPengZu ? 8 : 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final line in valueLines)
                if (line.isEmpty)
                  SizedBox(height: valueSize * 0.62)
                else if (isClash)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      textAlign: TextAlign.center,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: valueSize,
                        height: valueHeight,
                        color: cs.onSurface.withValues(alpha: 0.66),
                      ),
                    ),
                  )
                else
                  Text(
                    line,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: valueSize,
                      height: valueHeight,
                      color: cs.onSurface.withValues(alpha: 0.66),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClassicalHourRow extends StatelessWidget {
  final List<AlmanacHourFortune> fortunes;
  final Color lineColor;
  final Color gold;

  const _ClassicalHourRow({
    required this.fortunes,
    required this.lineColor,
    required this.gold,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: fortunes.asMap().entries.map((entry) {
        final index = entry.key;
        final fortune = entry.value;
        return Expanded(
          child: _ClassicalHourCell(
            fortune: fortune,
            lineColor: lineColor,
            gold: gold,
            showRightBorder: index != fortunes.length - 1,
          ),
        );
      }).toList(),
    );
  }
}

class _ClassicalHourCell extends StatelessWidget {
  final AlmanacHourFortune fortune;
  final Color lineColor;
  final Color gold;
  final bool showRightBorder;

  const _ClassicalHourCell({
    required this.fortune,
    required this.lineColor,
    required this.gold,
    required this.showRightBorder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final luckColor = fortune.isAuspicious
        ? gold
        : cs.onSurface.withValues(alpha: 0.78);
    final cellFill = fortune.isAuspicious
        ? gold.withValues(alpha: isDark ? 0.055 : 0.040)
        : Colors.transparent;
    return InkWell(
      onTap: () => _showHourFortuneDialog(context, fortune),
      child: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          color: cellFill,
          border: Border(
            right: showRightBorder
                ? BorderSide(color: lineColor, width: 0.55)
                : BorderSide.none,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final branchSize = constraints.maxWidth < 28 ? 11.0 : 12.5;
            final luckSize = constraints.maxWidth < 28 ? 10.5 : 12.0;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  fortune.branch,
                  maxLines: 1,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.86),
                    fontSize: branchSize,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  fortune.isAuspicious ? '吉' : '凶',
                  maxLines: 1,
                  style: TextStyle(
                    color: luckColor,
                    fontSize: luckSize,
                    height: 1.05,
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ClassicalDivider extends StatelessWidget {
  final Color color;

  const _ClassicalDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(height: 0.7, color: color);
  }
}

class _ClassicalVerticalDivider extends StatelessWidget {
  final Color color;

  const _ClassicalVerticalDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(width: 0.7, color: color);
  }
}

void _showHourFortuneDialog(BuildContext context, AlmanacHourFortune fortune) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final gold = const Color(0xFFB39162);
  final lineColor = gold.withValues(
    alpha: theme.brightness == Brightness.dark ? 0.62 : 0.55,
  );
  final cardColor = theme.brightness == Brightness.dark
      ? Color.alphaBlend(gold.withValues(alpha: 0.04), cs.surface)
      : Colors.white;
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: cardColor,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: lineColor, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${fortune.branch}时 · ${fortune.isAuspicious ? '吉' : '凶'}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 18,
                  fontWeight: DesignTokens.fontWeightStrong,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 14),
              _HourDetailLine(label: '时间', value: fortune.range),
              _HourDetailLine(label: '干支', value: fortune.ganzhi),
              _HourDetailLine(label: '神煞', value: fortune.deity),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('知道了'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _HourDetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _HourDetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.52),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: cs.onSurface.withValues(alpha: 0.82),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlmanacBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _AlmanacBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.14), width: 0.45),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: DesignTokens.fontWeightStrong,
          ),
        ),
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  final DateTime date;
  final _MonthCalendarData monthData;
  final List<_MonthHighlight> highlights;
  final ValueChanged<DateTime> onPick;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onTitleTap;

  const _MonthCalendar({
    required this.date,
    required this.monthData,
    required this.highlights,
    required this.onPick,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onTitleTap,
  });

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final now = AppClock.now();
    final today = DateTime(now.year, now.month, now.day);
    final compact = MediaQuery.sizeOf(context).width < 380;
    final cellHeight = compact ? 46.0 : 48.0;
    final cellRadius = compact ? 10.0 : 12.0;
    final cellMargin = compact ? 0.5 : 1.5;
    final dayFontSize = compact ? 13.0 : 14.0;
    final labelFontSize = compact ? 8.5 : 9.0;
    final highlightByDay = {for (final item in highlights) item.date.day: item};
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  cs.primary.withValues(alpha: isDark ? 0.10 : 0.045),
                  cs.surface,
                ),
                Color.alphaBlend(
                  const Color(
                    0xFFB39162,
                  ).withValues(alpha: isDark ? 0.08 : 0.035),
                  cs.surface,
                ),
              ],
            ),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: isDark ? 0.18 : 0.22),
              width: 0.6,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.10 : 0.045),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
                child: Row(
                  children: [
                    _MonthNavButton(
                      tooltip: '上个月',
                      icon: Icons.chevron_left,
                      onPressed: onPreviousMonth,
                    ),
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: '选择日期',
                        child: Tooltip(
                          message: '选择日期',
                          child: GestureDetector(
                            onTap: onTitleTap,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 14,
                                  color: cs.onSurface.withValues(alpha: 0.46),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${date.month}月',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        fontSize: 24,
                                        fontWeight:
                                            DesignTokens.fontWeightStrong,
                                        letterSpacing: 0,
                                        color: cs.onSurface,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${date.year}年',
                                  style: appSecondaryControlLabelStyle(context)
                                      .copyWith(
                                        color: cs.onSurface.withValues(
                                          alpha: 0.48,
                                        ),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    _MonthNavButton(
                      tooltip: '下个月',
                      icon: Icons.chevron_right,
                      onPressed: onNextMonth,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: const ['一', '二', '三', '四', '五', '六', '日']
                    .map(
                      (d) => Expanded(
                        child: Center(
                          child: Text(
                            d,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: DesignTokens.fontWeightStrong,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              ...List.generate(monthData.rowCount, (row) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: List.generate(7, (col) {
                      final d =
                          row * 7 + col - monthData.firstWeekdayOffset + 1;
                      final dayData = monthData.dayAt(d);
                      if (dayData == null) {
                        return Expanded(child: SizedBox(height: cellHeight));
                      }
                      final day = dayData.date;
                      final dayLabel = dayData.label;
                      final isSelected =
                          day.year == date.year &&
                          day.month == date.month &&
                          day.day == date.day;
                      final highlight = highlightByDay[d];
                      final hasHighlight = highlight != null;
                      final isToday = day == today;
                      final isWeekend = dayData.isWeekend;
                      final isHoliday = dayData.isHoliday;
                      final isWorkMakeupDay = dayData.isWorkMakeupDay;
                      final selectedFill = Color.alphaBlend(
                        cs.primary.withValues(alpha: isDark ? 0.20 : 0.12),
                        cs.surface,
                      );
                      final selectedText = cs.onSurface;
                      final festivalColor = Color.lerp(
                        const Color(0xFFEF6C00),
                        cs.onSurface,
                        isDark ? 0.20 : 0.30,
                      )!;
                      final termColor = Color.lerp(
                        const Color(0xFF2E7D32),
                        cs.onSurface,
                        isDark ? 0.20 : 0.24,
                      )!;
                      final restColor = Color.lerp(
                        const Color(0xFFC62828),
                        cs.onSurface,
                        0.28,
                      )!;
                      final workColor = Color.lerp(
                        const Color(0xFF5E35B1),
                        cs.onSurface,
                        0.30,
                      )!;

                      return Expanded(
                        child: Semantics(
                          button: true,
                          selected: isSelected,
                          label: '${day.year}年${day.month}月$d日 $dayLabel',
                          child: Container(
                            height: cellHeight,
                            margin: EdgeInsets.symmetric(
                              horizontal: cellMargin,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? selectedFill
                                  : isToday
                                  ? cs.primary.withValues(
                                      alpha: isDark ? 0.10 : 0.06,
                                    )
                                  : hasHighlight
                                  ? cs.surfaceContainerHighest.withValues(
                                      alpha: isDark ? 0.12 : 0.22,
                                    )
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(cellRadius),
                              border: Border.all(
                                color: isSelected
                                    ? cs.primary.withValues(alpha: 0.24)
                                    : isToday
                                    ? cs.primary.withValues(alpha: 0.16)
                                    : hasHighlight
                                    ? cs.outlineVariant.withValues(
                                        alpha: isDark ? 0.14 : 0.18,
                                      )
                                    : Colors.transparent,
                                width: isSelected ? 0.7 : 0.45,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: cs.primary.withValues(
                                          alpha: isDark ? 0.16 : 0.10,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Material(
                              type: MaterialType.transparency,
                              child: InkWell(
                                onTap: () => onPick(day),
                                borderRadius: BorderRadius.circular(cellRadius),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            '$d',
                                            style: TextStyle(
                                              fontSize: dayFontSize,
                                              fontWeight:
                                                  DesignTokens.fontWeightStrong,
                                              color: isSelected
                                                  ? selectedText
                                                  : isWorkMakeupDay
                                                  ? workColor
                                                  : isHoliday || isWeekend
                                                  ? restColor
                                                  : (isToday
                                                        ? cs.primary
                                                        : cs.onSurface
                                                              .withValues(
                                                                alpha: 0.88,
                                                              )),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            dayLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: labelFontSize,
                                              color: isSelected
                                                  ? selectedText.withValues(
                                                      alpha: 0.60,
                                                    )
                                                  : dayData.term != null
                                                  ? termColor
                                                  : dayData.solarFestival !=
                                                            null ||
                                                        dayData.lunarFestival !=
                                                            null
                                                  ? festivalColor
                                                  : cs.onSurface.withValues(
                                                      alpha: 0.42,
                                                    ),
                                            ),
                                          ),
                                          if (hasHighlight)
                                            Container(
                                              width: 3.5,
                                              height: 3.5,
                                              margin: const EdgeInsets.only(
                                                top: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? selectedText.withValues(
                                                        alpha: 0.70,
                                                      )
                                                    : cs.primary.withValues(
                                                        alpha: 0.58,
                                                      ),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (isHoliday || isWorkMakeupDay)
                                      Positioned(
                                        top: 3,
                                        right: 4,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 3,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                (isWorkMakeupDay
                                                        ? workColor
                                                        : restColor)
                                                    .withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(
                                              5,
                                            ),
                                          ),
                                          child: Text(
                                            isWorkMakeupDay ? '班' : '休',
                                            style: TextStyle(
                                              color:
                                                  (isWorkMakeupDay
                                                          ? workColor
                                                          : restColor)
                                                      .withValues(alpha: 0.82),
                                              fontSize: 8,
                                              height: 1,
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (highlight != null &&
                                        highlight.labels.length > 1)
                                      Positioned(
                                        bottom: 4,
                                        right: 5,
                                        child: Text(
                                          '+${highlight.labels.length - 1}',
                                          style: TextStyle(
                                            color: cs.onSurface.withValues(
                                              alpha: 0.34,
                                            ),
                                            fontSize: 8,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

class _MonthNavButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _MonthNavButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.padded,
        foregroundColor: cs.onSurface.withValues(alpha: 0.62),
        backgroundColor: cs.surface.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.20 : 0.58,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      ),
    );
  }
}

String _summaryTerms(String value) {
  final terms = value
      .split(RegExp(r'\s+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .take(6)
      .toList(growable: false);
  return terms.isEmpty ? value : terms.join(' ');
}

String _spacedGanzhiLine(String value) {
  return value.replaceFirst('年', '年 ').replaceFirst('月', '月 ').trim();
}

String _fullDateTitle(DateTime date) {
  const weekNames = ['一', '二', '三', '四', '五', '六', '日'];
  return '${date.year}年${date.month}月${date.day}日星期${weekNames[date.weekday - 1]}';
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

List<String> _splitAlmanacTerms(String value) {
  final terms = value
      .split(RegExp(r'[\s、，,；;。]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  return terms.isEmpty ? [value] : terms;
}

String _verticalAlmanacTerm(String value) {
  return value.runes.map((rune) => String.fromCharCodes([rune])).join('\n');
}

List<String> _splitPengZuLines(String value) {
  final seed = value
      .trim()
      .split(RegExp(r'[；;，,。]+'))
      .map((item) => item.replaceAll(RegExp(r'\s+'), '').trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  final lines = <String>[];
  for (final item in seed) {
    if (item.runes.length <= 4) {
      lines.add(item);
      continue;
    }
    final parts = RegExp(r'.{1,4}', unicode: true)
        .allMatches(item)
        .map((match) => match.group(0) ?? '')
        .where((part) => part.isNotEmpty);
    lines.addAll(parts);
  }
  if (lines.length >= 4) {
    return <String>[...lines.take(2), '', ...lines.skip(2)];
  }
  return lines.isEmpty ? [value.trim()] : lines;
}

List<String> _splitFiveElementLines(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return const <String>[];
  final tokens = normalized
      .split(' ')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  final lines = <String>[];
  if (tokens.length >= 2) {
    _addFiveElementPart(lines, tokens.join(''));
    return lines.isEmpty ? [tokens.join('  ')] : lines;
  }

  for (final token in tokens.isEmpty ? [normalized] : tokens) {
    _addFiveElementPart(lines, token);
  }
  return lines.isEmpty ? [normalized] : lines;
}

List<String> _splitClashLines(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), '');
  if (normalized.isEmpty) return const <String>[];
  final lines = <String>[];
  final directionMatch = RegExp(r'^(.*?)(煞[东南西北中]+方?)$').firstMatch(normalized);
  if (directionMatch != null) {
    final prefix = directionMatch.group(1) ?? '';
    final direction = directionMatch.group(2) ?? '';
    if (prefix.isNotEmpty) lines.add(prefix);
    if (direction.isNotEmpty) lines.add(direction);
    return lines;
  }
  return [normalized];
}

void _addFiveElementPart(List<String> lines, String value) {
  final text = value.trim();
  if (text.isEmpty) return;

  final zhiXingMatch = RegExp(r'^(.+?)([建除满平定执破危成收开闭]执位)$').firstMatch(text);
  if (zhiXingMatch != null) {
    final prefix = zhiXingMatch.group(1) ?? '';
    final zhiXing = zhiXingMatch.group(2) ?? '';
    final parts = [prefix, zhiXing].where((part) => part.isNotEmpty);
    if (parts.isNotEmpty) lines.add(parts.join('  '));
    return;
  }

  lines.add(text);
}

double _clampDouble(double value, double min, double max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}
