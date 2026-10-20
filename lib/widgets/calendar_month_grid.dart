import 'package:flutter/material.dart';
import '../core/app_clock.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/lunar_calendar.dart';
import '../models/calendar_event.dart';

class CalendarMonthGrid extends StatelessWidget {
  final DateTime focusedMonth;
  final DateTime selectedDay;
  final Map<String, List<CalendarEventType>> dateEventTypes;
  final Map<String, int> dateEventCounts;
  final void Function(DateTime) onDaySelected;

  /// 是否显示农历/节气/节日
  final bool showLunar;

  const CalendarMonthGrid({
    super.key,
    required this.focusedMonth,
    required this.selectedDay,
    required this.dateEventTypes,
    this.dateEventCounts = const {},
    required this.onDaySelected,
    this.showLunar = true,
  });

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final today = AppClock.now();
    final firstDay = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final lastDay = DateTime(focusedMonth.year, focusedMonth.month + 1, 0);
    final startOffset = (firstDay.weekday - 1) % 7; // 周一起
    final cs = Theme.of(context).colorScheme;
    final selectedDotColor = cs.onSurface.withValues(alpha: 0.72);
    final totalCells = startOffset + lastDay.day;
    final rows = (totalCells / 7).ceil();
    final preferredRowHeight = showLunar ? 58.0 : 48.0;
    final maxRowHeight = showLunar ? 72.0 : 62.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        const verticalPadding = 12.0;
        const weekdayHeight = 20.0;
        const weekdayGap = 4.0;
        final bounded = constraints.hasBoundedHeight;
        final availableRowHeight = bounded
            ? (constraints.maxHeight -
                      verticalPadding -
                      weekdayHeight -
                      weekdayGap) /
                  rows
            : preferredRowHeight;
        final rowSlotHeight = bounded
            ? availableRowHeight.clamp(30.0, maxRowHeight)
            : preferredRowHeight;
        final cellHeight = (rowSlotHeight - 4).clamp(28.0, maxRowHeight);
        final showSubText = showLunar && cellHeight >= 44;
        final showDots = cellHeight >= 36;
        final canShowEventCount = cellHeight >= 40;

        final horizontalPadding = constraints.maxWidth < 360 ? 6.0 : 12.0;
        final showEventCount = canShowEventCount && cellHeight >= 56;

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 6.0,
          ),
          child: Column(
            children: [
              SizedBox(
                height: weekdayHeight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: ['一', '二', '三', '四', '五', '六', '日']
                      .map(
                        (d) => Expanded(
                          child: Center(
                            child: Text(
                              d,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                                fontWeight: DesignTokens.fontWeightStrong,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: weekdayGap),
              ...List.generate(rows, (row) {
                return SizedBox(
                  height: rowSlotHeight,
                  child: Row(
                    children: List.generate(7, (col) {
                      final dayNum = row * 7 + col - startOffset + 1;
                      if (dayNum < 1 || dayNum > lastDay.day) {
                        return const Expanded(child: SizedBox.expand());
                      }
                      final date = DateTime(
                        focusedMonth.year,
                        focusedMonth.month,
                        dayNum,
                      );
                      final key =
                          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                      final types = dateEventTypes[key] ?? [];
                      final eventCount = dateEventCounts[key] ?? types.length;
                      final countIsVisible =
                          canShowEventCount && eventCount > 0;
                      final showEventCountBadge =
                          countIsVisible && showEventCount && eventCount > 1;
                      final hasTodo = types.contains(CalendarEventType.todo);
                      final isSelected =
                          date.year == selectedDay.year &&
                          date.month == selectedDay.month &&
                          date.day == selectedDay.day;
                      final isToday =
                          date.year == today.year &&
                          date.month == today.month &&
                          date.day == today.day;
                      final selectedBackground = Color.alphaBlend(
                        cs.primary.withValues(
                          alpha: Theme.of(context).brightness == Brightness.dark
                              ? 0.20
                              : 0.13,
                        ),
                        cs.surface,
                      );
                      final selectedForeground = cs.onSurface;
                      final dayFontSize = cellHeight < 14
                          ? (cellHeight * 0.72).clamp(6.0, 9.0).toDouble()
                          : cellHeight < 28
                          ? 11.0
                          : cellHeight < 36
                          ? 12.0
                          : 13.0;

                      // 农历/节气/节日 小字
                      String? subText;
                      Color? subColor;
                      if (showSubText && I18n.current == AppLocale.zh) {
                        final lunar = LunarCalendar.fromSolar(date);
                        final term = LunarCalendar.solarTerm(date);
                        final solarFes = LunarCalendar.solarFestival(date);
                        final lunarFes = LunarCalendar.lunarFestival(lunar);
                        if (solarFes != null) {
                          subText = solarFes;
                          subColor = Colors.red.shade400;
                        } else if (lunarFes != null) {
                          subText = lunarFes;
                          subColor = Colors.red.shade400;
                        } else if (term != null) {
                          subText = term;
                          subColor = Colors.green.shade600;
                        } else {
                          subText = lunar.shortDayOrMonth;
                          subColor = Colors.grey.shade500;
                        }
                      }

                      final semanticLabel = _daySemanticLabel(
                        date,
                        isToday: isToday,
                        isSelected: isSelected,
                        eventCount: eventCount,
                        subText: subText,
                      );

                      return Expanded(
                        child: Semantics(
                          button: true,
                          selected: isSelected,
                          label: semanticLabel,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                DesignTokens.radiusControl,
                              ),
                              onTap: () => onDaySelected(date),
                              child: Center(
                                child: Container(
                                  width: double.infinity,
                                  height: cellHeight,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? selectedBackground
                                        : (isToday
                                              ? cs.primary.withValues(
                                                  alpha: 0.1,
                                                )
                                              : Colors.transparent),
                                    borderRadius: BorderRadius.circular(
                                      DesignTokens.radiusControl,
                                    ),
                                    border: isSelected
                                        ? Border.all(
                                            color: cs.primary.withValues(
                                              alpha: 0.26,
                                            ),
                                            width: 0.45,
                                          )
                                        : null,
                                  ),
                                  child: ClipRect(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          '$dayNum',
                                          style: TextStyle(
                                            fontSize: dayFontSize,
                                            height: cellHeight < 14
                                                ? 0.95
                                                : 1.05,
                                            fontWeight:
                                                DesignTokens.fontWeightStrong,
                                            color: isSelected
                                                ? selectedForeground
                                                : (isToday
                                                      ? cs.primary
                                                      : cs.onSurface),
                                          ),
                                        ),
                                        if (subText != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 1,
                                            ),
                                            child: Text(
                                              subText,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 10,
                                                height: 1,
                                                color: isSelected
                                                    ? selectedForeground
                                                          .withValues(
                                                            alpha: 0.64,
                                                          )
                                                    : subColor,
                                              ),
                                            ),
                                          ),
                                        if (showDots &&
                                            types.isNotEmpty &&
                                            !showEventCountBadge)
                                          Padding(
                                            padding: EdgeInsets.only(
                                              top: subText == null ? 3 : 2,
                                            ),
                                            child: _eventDots(
                                              context,
                                              types: types,
                                              isSelected: isSelected,
                                              selectedColor: selectedDotColor,
                                            ),
                                          ),
                                        if (showEventCountBadge)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 1,
                                            ),
                                            child: _eventCountBadge(
                                              context,
                                              count: eventCount,
                                              color: hasTodo
                                                  ? cs.primary
                                                  : cs.tertiary,
                                              foreground: isSelected
                                                  ? selectedForeground
                                                  : null,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
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
        );
      },
    );
  }

  Widget _eventCountBadge(
    BuildContext context, {
    required int count,
    required Color color,
    Color? foreground,
  }) {
    final textColor = foreground ?? color;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.20), width: 0.45),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          '$count项',
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(fontSize: 10, height: 1, color: textColor),
        ),
      ),
    );
  }

  Widget _eventDots(
    BuildContext context, {
    required List<CalendarEventType> types,
    required bool isSelected,
    required Color selectedColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: types
          .take(3)
          .map(
            (type) =>
                _dot(isSelected ? selectedColor : _colorForType(type, cs)),
          )
          .toList(),
    );
  }

  Color _colorForType(CalendarEventType type, ColorScheme cs) => switch (type) {
    CalendarEventType.event => const Color(0xFF5B6EE1),
    CalendarEventType.todo => cs.primary,
    CalendarEventType.habit => cs.tertiary,
    CalendarEventType.pomodoro => Colors.red.shade400,
    CalendarEventType.anniversary => const Color(0xFFE91E63),
    CalendarEventType.countdown => const Color(0xFFFF8A65),
    CalendarEventType.course => const Color(0xFF42A5F5),
    CalendarEventType.diary => const Color(0xFF26A69A),
    CalendarEventType.goal => const Color(0xFFFFA726),
    CalendarEventType.timeEntry => const Color(0xFF78909C),
  };

  Widget _dot(Color color) => Container(
    width: 4,
    height: 4,
    margin: const EdgeInsets.only(left: 1),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  String _daySemanticLabel(
    DateTime date, {
    required bool isToday,
    required bool isSelected,
    required int eventCount,
    required String? subText,
  }) {
    final parts = <String>[
      '${date.year}年${date.month}月${date.day}日',
      if (isToday) '今天',
      if (isSelected) '已选中',
      if (subText != null && subText.isNotEmpty) subText,
      eventCount > 0 ? '$eventCount 个事项' : '无事项',
    ];
    return parts.join('，');
  }
}
