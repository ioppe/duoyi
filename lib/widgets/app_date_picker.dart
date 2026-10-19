import 'package:flutter/material.dart';

import '../core/app_clock.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/lunar_calendar.dart';
import 'surface_components.dart';

enum AppDatePickerMode { solar, lunar }

class AppDatePickerResult {
  final DateTime date;
  final AppDatePickerMode mode;
  final bool ignoreYear;

  const AppDatePickerResult({
    required this.date,
    required this.mode,
    this.ignoreYear = false,
  });

  String get solarText => I18nDateFormat.date(date);

  String get lunarText {
    final lunar = LunarCalendar.fromSolar(date);
    final text =
        '${LunarCalendar.ganzhiOf(lunar.year)}年（${date.year}）'
        '${LunarCalendar.monthName(lunar.month, isLeap: lunar.isLeapMonth)} '
        '${LunarCalendar.dayName(lunar.day)}';
    if (I18n.current == AppLocale.zh) return text;
    return '${I18n.tr('calendar.chinese_lunar_calendar')}: $text';
  }
}

class AppDatePicker {
  AppDatePicker._();

  static Future<DateTime?> pickSolar(
    BuildContext context, {
    required DateTime initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
    String title = '选择日期',
    String? subtitle,
  }) async {
    final result = await show(
      context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
      subtitle: subtitle,
      initialMode: AppDatePickerMode.solar,
    );
    return result?.date;
  }

  static Future<AppDatePickerResult?> show(
    BuildContext context, {
    required DateTime initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
    String title = '选择日期',
    String? subtitle,
    AppDatePickerMode initialMode = AppDatePickerMode.solar,
    bool allowIgnoreYear = false,
    bool initialIgnoreYear = false,
  }) {
    return showAppModalSheet<AppDatePickerResult>(
      context: context,
      builder: (_) => _AppDatePickerSheet(
        initialDate: initialDate,
        firstDate: firstDate ?? DateTime(1900),
        lastDate: lastDate ?? DateTime(2099, 12, 31),
        title: title,
        subtitle: subtitle,
        initialMode: initialMode,
        allowIgnoreYear: allowIgnoreYear,
        initialIgnoreYear: initialIgnoreYear,
      ),
    );
  }
}

class _AppDatePickerSheet extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;
  final String? subtitle;
  final AppDatePickerMode initialMode;
  final bool allowIgnoreYear;
  final bool initialIgnoreYear;

  const _AppDatePickerSheet({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.title,
    required this.subtitle,
    required this.initialMode,
    required this.allowIgnoreYear,
    required this.initialIgnoreYear,
  });

  @override
  State<_AppDatePickerSheet> createState() => _AppDatePickerSheetState();
}

class _AppDatePickerSheetState extends State<_AppDatePickerSheet> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  late AppDatePickerMode _mode;
  late LunarDate _lunar;
  bool _ignoreYear = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = _clamp(widget.initialDate);
    _focusedDay = _selectedDay;
    _mode = widget.initialMode;
    _lunar = LunarCalendar.fromSolar(_selectedDay);
    _ignoreYear = widget.initialIgnoreYear && widget.allowIgnoreYear;
  }

  DateTime _clamp(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    if (d.isBefore(widget.firstDate)) return widget.firstDate;
    if (d.isAfter(widget.lastDate)) return widget.lastDate;
    return d;
  }

  void _setSolar(DateTime day) {
    setState(() {
      _selectedDay = _clamp(day);
      _focusedDay = DateTime(_selectedDay.year, _selectedDay.month);
      _lunar = LunarCalendar.fromSolar(_selectedDay);
    });
  }

  void _setLunar({int? year, int? month, int? day}) {
    final nextYear = year ?? _lunar.year;
    final nextMonth = month ?? _lunar.month;
    final maxDay = LunarCalendar.daysInMonth(
      nextYear,
      nextMonth,
      isLeap: _lunar.isLeapMonth,
    );
    final nextDay = (day ?? _lunar.day).clamp(1, maxDay).toInt();
    final solar = LunarCalendar.toSolar(nextYear, nextMonth, nextDay);
    setState(() {
      _selectedDay = _clamp(solar);
      _focusedDay = DateTime(_selectedDay.year, _selectedDay.month);
      _lunar = LunarCalendar.fromSolar(_selectedDay);
    });
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final result = AppDatePickerResult(
      date: _selectedDay,
      mode: _mode,
      ignoreYear: _ignoreYear,
    );
    return AppModalSheet(
      title: widget.title,
      subtitle: widget.subtitle,
      actions: [
        TextButton.icon(
          onPressed: () => _setSolar(AppClock.now()),
          icon: const Icon(Icons.today_outlined, size: 18),
          label: const Text('今天'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, result),
          child: const Text('确定'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<AppDatePickerMode>(
            segments: [
              ButtonSegment(
                value: AppDatePickerMode.solar,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(I18n.tr('calendar.solar')),
              ),
              ButtonSegment(
                value: AppDatePickerMode.lunar,
                icon: const Icon(Icons.brightness_2_outlined),
                label: Text(I18n.tr('calendar.lunar')),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 12),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                cs.primary.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.12 : 0.06,
                ),
                cs.surface,
              ),
              borderRadius: DesignTokens.borderRadiusLg,
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.16),
                width: 0.45,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: DesignTokens.borderRadiusMd,
                  ),
                  child: Icon(
                    _mode == AppDatePickerMode.solar
                        ? Icons.calendar_month_outlined
                        : Icons.brightness_2_outlined,
                    color: cs.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.solarText,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        result.lunarText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (widget.allowIgnoreYear) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _ignoreYear,
              title: const Text('忽略年份'),
              subtitle: const Text('适合生日、纪念日每年重复'),
              onChanged: (v) => setState(() => _ignoreYear = v),
            ),
          ],
          const SizedBox(height: 12),
          if (_mode == AppDatePickerMode.solar)
            _SolarCalendar(
              focusedDay: _focusedDay,
              selectedDay: _selectedDay,
              firstDay: widget.firstDate,
              lastDay: widget.lastDate,
              onDaySelected: _setSolar,
              onPageChanged: (day) => setState(() => _focusedDay = day),
            )
          else
            _LunarPicker(lunar: _lunar, onChanged: _setLunar),
        ],
      ),
    );
  }
}

class _SolarCalendar extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime selectedDay;
  final DateTime firstDay;
  final DateTime lastDay;
  final ValueChanged<DateTime> onDaySelected;
  final ValueChanged<DateTime> onPageChanged;

  const _SolarCalendar({
    required this.focusedDay,
    required this.selectedDay,
    required this.firstDay,
    required this.lastDay,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final month = DateTime(focusedDay.year, focusedDay.month);
    final firstMonth = DateTime(firstDay.year, firstDay.month);
    final lastMonth = DateTime(lastDay.year, lastDay.month);
    final canGoPrevious = month.isAfter(firstMonth);
    final canGoNext = month.isBefore(lastMonth);
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final leadingBlankCount = firstOfMonth.weekday - 1;
    final calendarFill = Color.alphaBlend(
      cs.primary.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.06 : 0.025,
      ),
      cs.surface,
    );
    const rows = 6;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: calendarFill,
        borderRadius: DesignTokens.borderRadiusLg,
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.16),
          width: 0.45,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '上个月',
                  visualDensity: VisualDensity.compact,
                  onPressed: canGoPrevious
                      ? () =>
                            onPageChanged(DateTime(month.year, month.month - 1))
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '${month.year}年${month.month}月',
                      style:
                          theme.textTheme.titleMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.normal,
                          ) ??
                          TextStyle(
                            color: cs.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.normal,
                          ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '下个月',
                  visualDensity: VisualDensity.compact,
                  onPressed: canGoNext
                      ? () =>
                            onPageChanged(DateTime(month.year, month.month + 1))
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: const ['一', '二', '三', '四', '五', '六', '日']
                  .map(
                    (label) => Expanded(
                      child: Center(child: _WeekdayLabel(label: label)),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 4),
            for (var row = 0; row < rows; row++)
              Row(
                children: [
                  for (var col = 0; col < 7; col++)
                    Expanded(
                      child: _SolarDayCell(
                        cell: _dateForCell(
                          month: month,
                          index: row * 7 + col,
                          leadingBlankCount: leadingBlankCount,
                        ),
                        selectedDay: selectedDay,
                        firstDay: firstDay,
                        lastDay: lastDay,
                        onSelected: onDaySelected,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  static _SolarCalendarCell _dateForCell({
    required DateTime month,
    required int index,
    required int leadingBlankCount,
  }) {
    final day = index - leadingBlankCount + 1;
    final date = DateTime(month.year, month.month, day);
    return _SolarCalendarCell(
      date: date,
      inCurrentMonth: date.year == month.year && date.month == month.month,
    );
  }
}

class _SolarCalendarCell {
  final DateTime date;
  final bool inCurrentMonth;

  const _SolarCalendarCell({required this.date, required this.inCurrentMonth});
}

class _WeekdayLabel extends StatelessWidget {
  final String label;

  const _WeekdayLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: cs.primary.withValues(alpha: 0.82),
          fontWeight: FontWeight.normal,
        ),
      ),
    );
  }
}

class _SolarDayCell extends StatelessWidget {
  final _SolarCalendarCell cell;
  final DateTime selectedDay;
  final DateTime firstDay;
  final DateTime lastDay;
  final ValueChanged<DateTime> onSelected;

  const _SolarDayCell({
    required this.cell,
    required this.selectedDay,
    required this.firstDay,
    required this.lastDay,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final day = DateTime(cell.date.year, cell.date.month, cell.date.day);
    final today = AppClock.now();
    final isToday = _sameDate(day, today);
    final isSelected = _sameDate(day, selectedDay);
    final disabled =
        day.isBefore(_dateOnly(firstDay)) || day.isAfter(_dateOnly(lastDay));
    final isEnabledCurrentMonth = !disabled && cell.inCurrentMonth;
    final currentMonthFill = Color.alphaBlend(
      cs.primary.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.10 : 0.07,
      ),
      cs.surface,
    );
    final todayFill = Color.alphaBlend(
      cs.primary.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.18 : 0.13,
      ),
      cs.surface,
    );
    final selectedFill = Color.alphaBlend(
      cs.primary.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.20 : 0.13,
      ),
      cs.surface,
    );
    final background = isSelected
        ? selectedFill
        : isToday
        ? todayFill
        : isEnabledCurrentMonth
        ? currentMonthFill
        : Colors.transparent;
    final foreground = disabled
        ? cs.onSurface.withValues(alpha: 0.30)
        : isSelected
        ? cs.onSurface
        : isToday
        ? cs.primary
        : cell.inCurrentMonth
        ? cs.onSurface
        : cs.onSurfaceVariant.withValues(alpha: 0.36);
    final border = isSelected
        ? Border.all(color: cs.primary.withValues(alpha: 0.26), width: 0.45)
        : isToday
        ? Border.all(color: cs.primary.withValues(alpha: 0.26), width: 0.45)
        : isEnabledCurrentMonth
        ? Border.all(color: cs.primary.withValues(alpha: 0.14), width: 0.45)
        : null;

    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        key: ValueKey(
          'solar-day-${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
        ),
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: disabled ? null : () => onSelected(day),
          child: Container(
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: border,
            ),
            child: Text(
              '${day.day}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _LunarPicker extends StatelessWidget {
  final LunarDate lunar;
  final void Function({int? year, int? month, int? day}) onChanged;

  const _LunarPicker({required this.lunar, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _NumberWheel(
            value: lunar.year,
            min: 1900,
            max: 2099,
            labelBuilder: (v) => '${LunarCalendar.ganzhiOf(v)}年（$v）',
            onChanged: (v) => onChanged(year: v),
          ),
        ),
        Expanded(
          child: _NumberWheel(
            value: lunar.month,
            min: 1,
            max: 12,
            labelBuilder: (v) => LunarCalendar.monthName(v),
            onChanged: (v) => onChanged(month: v),
          ),
        ),
        Expanded(
          child: _NumberWheel(
            value: lunar.day,
            min: 1,
            max: LunarCalendar.daysInMonth(lunar.year, lunar.month),
            labelBuilder: (v) => LunarCalendar.dayName(v),
            onChanged: (v) => onChanged(day: v),
          ),
        ),
      ],
    );
  }
}

class _NumberWheel extends StatefulWidget {
  final int value;
  final int min;
  final int max;
  final String Function(int value) labelBuilder;
  final ValueChanged<int> onChanged;

  const _NumberWheel({
    required this.value,
    required this.min,
    required this.max,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  State<_NumberWheel> createState() => _NumberWheelState();
}

class _NumberWheelState extends State<_NumberWheel> {
  late FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(
      initialItem: (widget.value - widget.min)
          .clamp(0, widget.max - widget.min)
          .toInt(),
    );
  }

  @override
  void didUpdateWidget(covariant _NumberWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.min != widget.min ||
        oldWidget.max != widget.max) {
      _controller.jumpToItem(
        (widget.value - widget.min).clamp(0, widget.max - widget.min).toInt(),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 190,
      child: ListWheelScrollView.useDelegate(
        controller: _controller,
        itemExtent: 42,
        physics: const FixedExtentScrollPhysics(),
        overAndUnderCenterOpacity: 0.45,
        onSelectedItemChanged: (i) => widget.onChanged(widget.min + i),
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: widget.max - widget.min + 1,
          builder: (context, index) {
            final value = widget.min + index;
            return Center(
              child: Text(
                widget.labelBuilder(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cs.onSurface),
              ),
            );
          },
        ),
      ),
    );
  }
}
