import 'package:flutter/material.dart';
import '../core/app_clock.dart';
import '../core/completion_visibility_policy.dart';
import '../core/i18n_date_format.dart';
import '../models/calendar_event.dart';
import '../providers/calendar_provider.dart';
import 'calendar_event_sheet.dart';
import 'surface_components.dart';

class CalendarWeekStrip extends StatelessWidget {
  final DateTime selectedDay;
  final Map<String, List<CalendarEventType>> dateEventTypes;
  final CalendarProvider calendarProvider;
  final void Function(DateTime) onDaySelected;
  final Set<CalendarEventType>? activeTypes;
  final String? projectKey;
  final String? workspaceId;

  const CalendarWeekStrip({
    super.key,
    required this.selectedDay,
    required this.dateEventTypes,
    required this.calendarProvider,
    required this.onDaySelected,
    this.activeTypes,
    this.projectKey,
    this.workspaceId,
  });

  static Color _colorFor(CalendarEventType t, ColorScheme cs) {
    switch (t) {
      case CalendarEventType.event:
        return const Color(0xFF5B6EE1);
      case CalendarEventType.todo:
        return cs.primary;
      case CalendarEventType.habit:
        return cs.tertiary;
      case CalendarEventType.pomodoro:
        return Colors.red;
      case CalendarEventType.anniversary:
        return const Color(0xFFE91E63);
      case CalendarEventType.course:
        return const Color(0xFF42A5F5);
      case CalendarEventType.diary:
        return const Color(0xFF26A69A);
      case CalendarEventType.countdown:
        return Colors.orange;
      case CalendarEventType.goal:
        return const Color(0xFFFFA726);
      case CalendarEventType.timeEntry:
        return const Color(0xFF78909C);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final cs = Theme.of(context).colorScheme;
    final monday = selectedDay.subtract(
      Duration(days: selectedDay.weekday - 1),
    );
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));
    final today = AppClock.now();
    final weekEvents = [
      for (final d in days)
        _WeekDayEvents(
          date: d,
          events: calendarProvider.getEventsForDate(
            d,
            activeTypes: activeTypes,
            projectKey: projectKey,
            workspaceId: workspaceId,
          )..sort(_compareEvents),
        ),
    ];

    return Column(
      children: [
        AppSurfaceCard(
          key: const ValueKey('calendar_week_strip_skin_card'),
          margin: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          padding: const EdgeInsets.symmetric(vertical: 6),
          borderRadius: BorderRadius.circular(12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: days.map((d) {
                final key =
                    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                final types = dateEventTypes[key] ?? [];
                final isSelected =
                    d.year == selectedDay.year &&
                    d.month == selectedDay.month &&
                    d.day == selectedDay.day;
                final isToday =
                    d.year == today.year &&
                    d.month == today.month &&
                    d.day == today.day;
                final labels = ['一', '二', '三', '四', '五', '六', '日'];
                final selectedBackground = Color.alphaBlend(
                  cs.primary.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.20
                        : 0.13,
                  ),
                  cs.surface,
                );
                final selectedForeground = cs.onSurface;

                final semanticLabel = _weekDaySemanticLabel(
                  d,
                  weekdayLabel: labels[d.weekday - 1],
                  isToday: isToday,
                  isSelected: isSelected,
                  eventTypeCount: types.length,
                );

                return Semantics(
                  button: true,
                  selected: isSelected,
                  label: semanticLabel,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: SizedBox(
                      width: 48,
                      height: 64,
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => onDaySelected(d),
                          child: Ink(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? selectedBackground
                                  : (isToday
                                        ? cs.primary.withValues(alpha: 0.12)
                                        : null),
                              borderRadius: BorderRadius.circular(10),
                              border: isSelected
                                  ? Border.all(
                                      color: cs.primary.withValues(alpha: 0.26),
                                      width: 0.45,
                                    )
                                  : null,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  labels[d.weekday - 1],
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isSelected
                                        ? selectedForeground.withValues(
                                            alpha: 0.70,
                                          )
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  '${d.day}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.normal,
                                    color: isSelected
                                        ? selectedForeground
                                        : null,
                                  ),
                                ),
                                if (types.isNotEmpty)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: types
                                        .take(3)
                                        .map(
                                          (t) => Container(
                                            width: 5,
                                            height: 5,
                                            margin: const EdgeInsets.only(
                                              right: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _colorFor(t, cs),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Expanded(
          child: _WeekAgendaList(
            days: weekEvents,
            onDaySelected: onDaySelected,
          ),
        ),
      ],
    );
  }

  static int _compareEvents(CalendarEvent a, CalendarEvent b) {
    final aMinutes = (a.time?.hour ?? 0) * 60 + (a.time?.minute ?? 0);
    final bMinutes = (b.time?.hour ?? 0) * 60 + (b.time?.minute ?? 0);
    final time = aMinutes.compareTo(bMinutes);
    if (time != 0) return time;
    return a.title.compareTo(b.title);
  }

  String _weekDaySemanticLabel(
    DateTime date, {
    required String weekdayLabel,
    required bool isToday,
    required bool isSelected,
    required int eventTypeCount,
  }) {
    final parts = <String>[
      '${date.year}年${date.month}月${date.day}日',
      weekdayLabel,
      if (isToday) '今天',
      if (isSelected) '已选中',
      eventTypeCount > 0 ? '$eventTypeCount 类事项' : '无事项',
    ];
    return parts.join('，');
  }
}

class _WeekDayEvents {
  final DateTime date;
  final List<CalendarEvent> events;

  const _WeekDayEvents({required this.date, required this.events});
}

class _WeekAgendaList extends StatelessWidget {
  final List<_WeekDayEvents> days;
  final void Function(DateTime) onDaySelected;

  const _WeekAgendaList({required this.days, required this.onDaySelected});

  @override
  Widget build(BuildContext context) {
    final visibleDays = days.where((day) => day.events.isNotEmpty).toList();
    if (visibleDays.isEmpty) {
      return Center(
        child: Text(
          '本周暂无日程',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      );
    }

    return Scrollbar(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        itemCount: visibleDays.length,
        itemBuilder: (context, index) {
          final day = visibleDays[index];
          return _WeekDaySection(day: day, onDaySelected: onDaySelected);
        },
      ),
    );
  }
}

class _WeekDaySection extends StatelessWidget {
  final _WeekDayEvents day;
  final void Function(DateTime) onDaySelected;

  const _WeekDaySection({required this.day, required this.onDaySelected});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = [
      '周一',
      '周二',
      '周三',
      '周四',
      '周五',
      '周六',
      '周日',
    ][day.date.weekday - 1];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onDaySelected(day.date),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Text(
                    '$label ${day.date.month}/${day.date.day}',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${day.events.length} 项',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          for (final event in day.events) _WeekEventTile(event: event),
        ],
      ),
    );
  }
}

class _WeekEventTile extends StatelessWidget {
  final CalendarEvent event;

  const _WeekEventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visual = _weekEventVisualState(event);
    final isCompleted = visual == TodoVisualState.completed;
    final isOverdue = visual == TodoVisualState.overdue;
    final statusColor = isCompleted
        ? cs.tertiary
        : isOverdue
        ? cs.error
        : null;
    final time = event.time == null
        ? null
        : I18nDateFormat.timeOfDay(
            hour: event.time!.hour,
            minute: event.time!.minute,
          );
    final subtitle = event.subtitle;
    final detail = switch ((time, subtitle)) {
      (final t?, final s?) when s.isNotEmpty => '$t · $s',
      (final t?, _) => t,
      (_, final s?) when s.isNotEmpty => s,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showCalendarEventSheet(context, event),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: statusColor == null
                ? cs.surface
                : Color.alphaBlend(
                    statusColor.withValues(alpha: 0.07),
                    cs.surface,
                  ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: event.hasConflict
                  ? cs.error.withValues(alpha: 0.35)
                  : statusColor != null
                  ? statusColor.withValues(alpha: 0.24)
                  : cs.outlineVariant.withValues(alpha: 0.12),
              width: event.hasConflict ? 0.6 : 0.45,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 34,
                decoration: BoxDecoration(
                  color: (statusColor ?? event.color).withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.normal,
                        decoration: isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        color: isCompleted
                            ? cs.onSurfaceVariant
                            : isOverdue
                            ? cs.error
                            : cs.onSurface,
                      ),
                    ),
                    if (statusColor != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: _WeekEventStatusBadge(
                          label: isCompleted ? '已完成' : '逾期',
                          color: statusColor,
                        ),
                      ),
                    if (detail != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 16, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

TodoVisualState _weekEventVisualState(CalendarEvent event) {
  if (event.isCompleted) return TodoVisualState.completed;
  final dueAt = event.endDate;
  if (event.type == CalendarEventType.todo &&
      dueAt != null &&
      dueAt.isBefore(AppClock.now())) {
    return TodoVisualState.overdue;
  }
  return TodoVisualState.normal;
}

class _WeekEventStatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _WeekEventStatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24), width: 0.7),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(label, style: TextStyle(fontSize: 10, color: color)),
      ),
    );
  }
}
