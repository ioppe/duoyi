import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_clock.dart';
import '../core/design_tokens.dart';
import '../providers/calendar_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/anniversary_provider.dart';
import '../providers/course_provider.dart';
import '../providers/time_audit_provider.dart';
import '../providers/todo_provider.dart';
import '../core/completion_visibility_policy.dart';
import '../core/todo_templates.dart';
import '../models/calendar_event.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../models/todo.dart';
import '../core/lunar_calendar.dart';
import 'calendar_event_sheet.dart';

class CalendarDayAgenda extends StatelessWidget {
  final DateTime date;
  final CalendarProvider calendarProvider;
  final Set<CalendarEventType>? activeTypes;
  final String? projectKey;
  final String? workspaceId;
  final double horizontalPadding;
  final bool scrollable;
  final int? previewLimit;

  const CalendarDayAgenda({
    super.key,
    required this.date,
    required this.calendarProvider,
    this.activeTypes,
    this.projectKey,
    this.workspaceId,
    this.horizontalPadding = 16,
    this.scrollable = true,
    this.previewLimit,
  });

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final s = context.watch<ThemeProvider>().brand.strings;
    final anniversaries = context.watch<AnniversaryProvider>();
    final courses = context.watch<CourseProvider>();
    final events = calendarProvider.getEventsForDate(
      date,
      activeTypes: activeTypes,
      projectKey: projectKey,
      workspaceId: workspaceId,
    );
    final todoById = {
      for (final todo in context.read<TodoProvider>().todos) todo.id: todo,
    };
    final visibleEvents = previewLimit == null
        ? events
        : events.take(previewLimit!.clamp(0, events.length)).toList();
    final hiddenEventCount = events.length - visibleEvents.length;
    final timedEvents = visibleEvents.where((e) => e.time != null).toList()
      ..sort(
        (a, b) =>
            _eventStartOnDay(a, date).compareTo(_eventStartOnDay(b, date)),
      );
    final untimedEvents = visibleEvents.where((e) => e.time == null).toList();

    final lunar = LunarCalendar.fromSolar(date);
    final term = LunarCalendar.solarTerm(date);
    final solarFes = LunarCalendar.solarFestival(date);
    final lunarFes = LunarCalendar.lunarFestival(lunar);

    // 纪念日命中
    final hitAnniversaries = anniversaries.items.where((a) {
      final n = a.nextOccurrence;
      return n.year == date.year && n.month == date.month && n.day == date.day;
    }).toList();

    // 课表
    final todayCourses = courses.coursesOfDate(date);

    final children = [
      // 农历 / 节日 / 节气头
      _dayHeader(context, lunar, term, solarFes, lunarFes),

      if (hitAnniversaries.isNotEmpty) ...[
        const SizedBox(height: 8),
        _sectionTitle('🎉 今日纪念'),
        ...hitAnniversaries.map(
          (a) => _AnniversaryTile(
            title: a.title,
            color: Color(a.colorValue),
            subtitle: a.yearsPassed != null
                ? '第 ${a.yearsPassed! + 1} 次'
                : null,
          ),
        ),
      ],

      if (todayCourses.isNotEmpty) ...[
        const SizedBox(height: 12),
        _sectionTitle('📚 今日课程'),
        ...todayCourses.map(
          (c) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Color(c.colorValue).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Color(c.colorValue).withValues(alpha: 0.2),
                width: 0.45,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.class_outlined,
                  color: Color(c.colorValue),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        style: const TextStyle(
                          fontWeight: DesignTokens.fontWeightStrong,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '第${c.startSection}-${c.endSection}节${c.location.isNotEmpty ? ' · ${c.location}' : ''}${c.teacher.isNotEmpty ? ' · ${c.teacher}' : ''}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],

      if (timedEvents.isNotEmpty) ...[
        const SizedBox(height: 12),
        _sectionTitle('🕘 时间线'),
        _CalendarDayTimeGrid(
          date: date,
          events: timedEvents,
          todoById: todoById,
        ),
      ],

      if (untimedEvents.isNotEmpty) ...[
        const SizedBox(height: 12),
        _sectionTitle('📝 全天/无时间'),
        ..._buildTimeline(context, untimedEvents, todoById),
      ],

      if (hiddenEventCount > 0)
        _AgendaOverflowNotice(hiddenCount: hiddenEventCount),

      if (events.isEmpty && hitAnniversaries.isEmpty && todayCourses.isEmpty)
        Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_busy, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text(
                  s.calendarEmpty,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 24),
    ];

    if (!scrollable) {
      return Padding(
        key: const ValueKey('calendar_day_agenda_inline_content'),
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
    }

    return Scrollbar(
      child: ListView(
        key: const ValueKey('calendar_day_agenda_scroll_view'),
        primary: false,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        children: children,
      ),
    );
  }

  Widget _dayHeader(
    BuildContext context,
    LunarDate lunar,
    String? term,
    String? solarFes,
    String? lunarFes,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.wb_sunny_outlined, size: 16, color: cs.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${I18n.tr('calendar.chinese_lunar_calendar')} ${lunar.chineseText}',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.primary,
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
                if (term != null)
                  _dayBadge(
                    term,
                    Colors.green,
                    Colors.green.withValues(alpha: 0.12),
                  ),
                if (solarFes != null)
                  _dayBadge(
                    solarFes,
                    Colors.red,
                    Colors.red.withValues(alpha: 0.12),
                  ),
                if (lunarFes != null)
                  _dayBadge(
                    lunarFes,
                    Colors.deepOrange,
                    Colors.deepOrange.withValues(alpha: 0.12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayBadge(String text, Color color, Color backgroundColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: color)),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: Colors.grey.shade600,
        fontWeight: DesignTokens.fontWeightStrong,
      ),
    ),
  );

  List<Widget> _buildTimeline(
    BuildContext context,
    List<CalendarEvent> events,
    Map<String, TodoItem> todoById,
  ) {
    return List.generate(events.length, (index) {
      final e = events[index];
      final isLast = index == events.length - 1;
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 24,
              child: Column(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: e.color.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Builder(
                      builder: (context) {
                        final visual = _calendarEventVisual(e, todoById);
                        return Icon(visual.icon, color: visual.color, size: 14);
                      },
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(width: 2, color: Colors.grey.shade200),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DraggableEventCard(event: e, todoById: todoById),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _CalendarDayTimeGrid extends StatelessWidget {
  static const double _hourHeight = 54;
  static const double _timeColumnWidth = 48;

  final DateTime date;
  final List<CalendarEvent> events;
  final Map<String, TodoItem> todoById;

  const _CalendarDayTimeGrid({
    required this.date,
    required this.events,
    required this.todoById,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: _hourHeight * 24,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.10),
          width: 0.45,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          for (var hour = 0; hour < 24; hour++)
            Positioned(
              top: hour * _hourHeight,
              left: 0,
              right: 0,
              height: _hourHeight,
              child: _TimelineHourRow(hour: hour),
            ),
          for (var i = 0; i < events.length; i++)
            _positionedEvent(context, events[i], i),
        ],
      ),
    );
  }

  Widget _positionedEvent(
    BuildContext context,
    CalendarEvent event,
    int index,
  ) {
    final start = _eventStartOnDay(event, date);
    final end = _eventEndOnDay(event, date);
    final top = _minutesFromDayStart(start) / 60 * _hourHeight;
    final durationMinutes = math.max(30, end.difference(start).inMinutes);
    final height = math.max(44.0, durationMinutes / 60 * _hourHeight);
    final overlapLane = _overlapLane(event, index);
    final left = _timeColumnWidth + 8 + overlapLane * 10.0;
    final clampedTop = top.clamp(0.0, _hourHeight * 24 - 44).toDouble();
    final clampedHeight = height
        .clamp(44.0, _hourHeight * 24 - clampedTop)
        .toDouble();
    return Positioned(
      top: clampedTop,
      left: left,
      right: 8,
      height: clampedHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: _DraggableEventCard(
          event: event,
          compact: clampedHeight < 88,
          todoById: todoById,
        ),
      ),
    );
  }

  int _overlapLane(CalendarEvent event, int index) {
    final start = _eventStartOnDay(event, date);
    final end = _eventEndOnDay(event, date);
    var overlaps = 0;
    for (var i = 0; i < index; i++) {
      final other = events[i];
      final otherStart = _eventStartOnDay(other, date);
      final otherEnd = _eventEndOnDay(other, date);
      if (start.isBefore(otherEnd) && end.isAfter(otherStart)) overlaps++;
    }
    return overlaps.clamp(0, 2);
  }
}

class _AgendaOverflowNotice extends StatelessWidget {
  final int hiddenCount;

  const _AgendaOverflowNotice({required this.hiddenCount});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        '还有 $hiddenCount 项，请切换到日视图查看完整日程',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          color: cs.onSurfaceVariant.withValues(alpha: 0.72),
        ),
      ),
    );
  }
}

class _TimelineHourRow extends StatelessWidget {
  final int hour;

  const _TimelineHourRow({required this.hour});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = '${hour.toString().padLeft(2, '0')}:00';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _CalendarDayTimeGrid._timeColumnWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurfaceVariant.withValues(alpha: 0.72),
              ),
            ),
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(top: 10, right: 8),
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.08),
          ),
        ),
      ],
    );
  }
}

class _DraggableEventCard extends StatefulWidget {
  final CalendarEvent event;
  final bool compact;
  final Map<String, TodoItem> todoById;

  const _DraggableEventCard({
    required this.event,
    required this.todoById,
    this.compact = false,
  });

  @override
  State<_DraggableEventCard> createState() => _DraggableEventCardState();
}

class _DraggableEventCardState extends State<_DraggableEventCard> {
  double _dragDy = 0;

  bool get _canDrag =>
      widget.event.sourceId != null &&
      (widget.event.type == CalendarEventType.todo ||
          widget.event.type == CalendarEventType.timeEntry);

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final compact = widget.compact;
    final cs = Theme.of(context).colorScheme;
    final visual = _eventVisualState(e);
    final isCompleted = visual == TodoVisualState.completed;
    final isOverdue = visual == TodoVisualState.overdue;
    final statusColor = isCompleted
        ? cs.tertiary
        : isOverdue
        ? cs.error
        : null;
    final radius = BorderRadius.circular(compact ? 8 : 10);
    final card = InkWell(
      borderRadius: radius,
      onTap: () => showCalendarEventSheet(context, e),
      child: Container(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
            : const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: statusColor == null
              ? cs.surface
              : Color.alphaBlend(
                  statusColor.withValues(alpha: 0.07),
                  cs.surface,
                ),
          borderRadius: radius,
          border: Border.all(
            color: e.hasConflict
                ? cs.error.withValues(alpha: 0.36)
                : statusColor != null
                ? statusColor.withValues(alpha: 0.24)
                : Colors.grey.withValues(alpha: 0.1),
            width: 0.45,
          ),
        ),
        child: compact
            ? _buildCompactContent(context, e)
            : _buildRegularContent(context, e),
      ),
    );

    if (!_canDrag) return card;
    return GestureDetector(
      onVerticalDragStart: (_) => _dragDy = 0,
      onVerticalDragUpdate: (details) => _dragDy += details.delta.dy,
      onVerticalDragEnd: (_) => _applyDrag(context),
      child: card,
    );
  }

  Widget _buildCompactContent(BuildContext context, CalendarEvent e) {
    final visual = _eventVisualState(e);
    final eventVisual = _calendarEventVisual(e, widget.todoById);
    final cs = Theme.of(context).colorScheme;
    final isCompleted = visual == TodoVisualState.completed;
    final isOverdue = visual == TodoVisualState.overdue;
    final statusColor = isCompleted
        ? cs.tertiary
        : isOverdue
        ? cs.error
        : null;
    return Row(
      children: [
        if (_canDrag) ...[
          Icon(Icons.drag_indicator, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 3),
        ],
        Icon(eventVisual.icon, size: 14, color: eventVisual.color),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            e.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: DesignTokens.fontWeightStrong,
              color: isCompleted
                  ? Colors.grey
                  : isOverdue
                  ? cs.error
                  : null,
              decoration: isCompleted ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        if (statusColor != null) ...[
          const SizedBox(width: 6),
          _CalendarAgendaStatusBadge(
            label: isCompleted ? '已完成' : '逾期',
            color: statusColor,
          ),
        ],
        if (e.time != null) ...[
          const SizedBox(width: 6),
          Text(
            I18nDateFormat.timeOfDay(
              hour: e.time!.hour,
              minute: e.time!.minute,
            ),
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        ],
        if (e.hasConflict) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: '时间冲突',
            child: Icon(
              Icons.warning_amber_rounded,
              size: 14,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRegularContent(BuildContext context, CalendarEvent e) {
    final visual = _eventVisualState(e);
    final eventVisual = _calendarEventVisual(e, widget.todoById);
    final cs = Theme.of(context).colorScheme;
    final isCompleted = visual == TodoVisualState.completed;
    final isOverdue = visual == TodoVisualState.overdue;
    final statusColor = isCompleted
        ? cs.tertiary
        : isOverdue
        ? cs.error
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (_canDrag) ...[
              Icon(Icons.drag_indicator, size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 4),
            ],
            Icon(eventVisual.icon, size: 16, color: eventVisual.color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                e.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: DesignTokens.fontWeightStrong,
                  color: isCompleted
                      ? Colors.grey
                      : isOverdue
                      ? cs.error
                      : null,
                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (statusColor != null) ...[
              const SizedBox(width: 6),
              _CalendarAgendaStatusBadge(
                label: isCompleted ? '已完成' : '逾期',
                color: statusColor,
              ),
            ],
            if (e.hasConflict)
              Tooltip(
                message: '时间冲突',
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
          ],
        ),
        if (e.subtitle != null && e.subtitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              e.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
        if (e.time != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              I18nDateFormat.timeOfDay(
                hour: e.time!.hour,
                minute: e.time!.minute,
              ),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: Icon(
            Icons.chevron_right,
            size: 16,
            color: Colors.grey.shade500,
          ),
        ),
      ],
    );
  }

  Future<void> _applyDrag(BuildContext context) async {
    if (_dragDy.abs() < 18) return;
    final steps = (_dragDy / 24).round().clamp(-8, 8);
    if (steps == 0) return;
    final delta = Duration(minutes: steps * 15);
    final event = widget.event;
    switch (event.type) {
      case CalendarEventType.todo:
        await _adjustTodo(context, event, delta);
      case CalendarEventType.timeEntry:
        await _adjustTimeEntry(context, event, delta);
      default:
        break;
    }
  }

  Future<void> _adjustTodo(
    BuildContext context,
    CalendarEvent event,
    Duration delta,
  ) async {
    final id = event.sourceId;
    if (id == null) return;
    final provider = context.read<TodoProvider>();
    final matches = provider.todos.where((todo) => todo.id == id);
    if (matches.isEmpty) return;
    final todo = matches.first;
    final base =
        todo.localDueDate ??
        AppClock.date(event.date.year, event.date.month, event.date.day);
    final next = _clampToDay(base.add(delta), event.date);
    await provider.updateTodo(todo.id, todo.copyWith(dueDate: next));
    if (!context.mounted) return;
    _showDragResult(context, next);
  }

  Future<void> _adjustTimeEntry(
    BuildContext context,
    CalendarEvent event,
    Duration delta,
  ) async {
    final id = event.sourceId;
    if (id == null) return;
    final provider = context.read<TimeAuditProvider>();
    final matches = provider.entries.where((entry) => entry.id == id);
    if (matches.isEmpty) return;
    final entry = matches.first;
    final duration = entry.endAt.difference(entry.startAt);
    final next = _clampToDay(
      AppClock.toLocal(entry.startAt).add(delta),
      event.date,
    );
    await provider.update(
      entry.copyWith(startAt: next, endAt: next.add(duration)),
    );
    if (!context.mounted) return;
    _showDragResult(context, next);
  }

  DateTime _clampToDay(DateTime value, DateTime day) {
    final start = AppClock.date(day.year, day.month, day.day);
    final end = AppClock.date(day.year, day.month, day.day, 23, 45);
    if (value.isBefore(start)) return start;
    if (value.isAfter(end)) return end;
    return AppClock.date(
      day.year,
      day.month,
      day.day,
      value.hour,
      value.minute,
    );
  }

  void _showDragResult(BuildContext context, DateTime value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已调整到 ${I18nDateFormat.time(value)}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }
}

TodoVisualState _eventVisualState(CalendarEvent event) {
  if (event.type != CalendarEventType.todo) return TodoVisualState.normal;
  if (event.isCompleted) return TodoVisualState.completed;
  final dueAt = event.endDate;
  if (dueAt != null && dueAt.isBefore(AppClock.now())) {
    return TodoVisualState.overdue;
  }
  return TodoVisualState.normal;
}

class _CalendarTodoVisual {
  final IconData icon;
  final Color color;

  const _CalendarTodoVisual({required this.icon, required this.color});
}

_CalendarTodoVisual _calendarEventVisual(
  CalendarEvent event,
  Map<String, TodoItem> todoById,
) {
  if (event.type != CalendarEventType.todo || event.sourceId == null) {
    return _CalendarTodoVisual(
      icon: _fallbackEventIcon(event.type),
      color: event.color,
    );
  }
  final todo = todoById[event.sourceId];
  if (todo != null) return _calendarTodoVisual(todo);
  return _CalendarTodoVisual(
    icon: _fallbackEventIcon(event.type),
    color: event.color,
  );
}

_CalendarTodoVisual _calendarTodoVisual(TodoItem todo) {
  final target = todo.listGroupName?.trim();
  if (target != null && target.isNotEmpty) {
    for (final template in TodoListTemplates.all) {
      if (template.name == target) {
        return _CalendarTodoVisual(icon: template.icon, color: template.color);
      }
    }
  }
  return _CalendarTodoVisual(
    icon: switch (todo.quadrant) {
      EisenhowerQuadrant.urgentImportant => Icons.priority_high_outlined,
      EisenhowerQuadrant.notUrgentImportant => Icons.flag_outlined,
      EisenhowerQuadrant.urgentNotImportant => Icons.bolt_outlined,
      EisenhowerQuadrant.notUrgentNotImportant => Icons.checklist_rounded,
    },
    color: switch (todo.quadrant) {
      EisenhowerQuadrant.urgentImportant => const Color(0xFFE53935),
      EisenhowerQuadrant.notUrgentImportant => const Color(0xFFF6A339),
      EisenhowerQuadrant.urgentNotImportant => const Color(0xFF42A5F5),
      EisenhowerQuadrant.notUrgentNotImportant => const Color(0xFF8E8E8E),
    },
  );
}

IconData _fallbackEventIcon(CalendarEventType t) {
  return switch (t) {
    CalendarEventType.event => Icons.event_note_outlined,
    CalendarEventType.todo => Icons.check_circle_outline,
    CalendarEventType.habit => Icons.repeat,
    CalendarEventType.pomodoro => Icons.timer,
    CalendarEventType.anniversary => Icons.celebration_outlined,
    CalendarEventType.course => Icons.class_outlined,
    CalendarEventType.diary => Icons.book_outlined,
    CalendarEventType.countdown => Icons.hourglass_bottom,
    CalendarEventType.goal => Icons.flag_circle_outlined,
    CalendarEventType.timeEntry => Icons.timelapse_outlined,
  };
}

class _CalendarAgendaStatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _CalendarAgendaStatusBadge({required this.label, required this.color});

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

DateTime _eventStartOnDay(CalendarEvent event, DateTime day) {
  final dayStart = _dateOnly(day);
  final eventDay = _dateOnly(event.date);
  if (dayStart.isAfter(eventDay)) {
    return AppClock.date(day.year, day.month, day.day);
  }
  final time = event.time;
  if (time == null) return AppClock.date(day.year, day.month, day.day);
  return AppClock.date(day.year, day.month, day.day, time.hour, time.minute);
}

DateTime _eventEndOnDay(CalendarEvent event, DateTime day) {
  final start = _eventStartOnDay(event, day);
  final dayEnd = AppClock.date(day.year, day.month, day.day + 1);
  final endDate = event.endDate;
  if (endDate == null || !endDate.isAfter(start)) {
    final fallback = start.add(const Duration(hours: 1));
    return fallback.isAfter(dayEnd) ? dayEnd : fallback;
  }
  final end = endDate;
  if (end.isAfter(dayEnd)) return dayEnd;
  if (end.isBefore(start)) {
    final fallback = start.add(const Duration(hours: 1));
    return fallback.isAfter(dayEnd) ? dayEnd : fallback;
  }
  return end;
}

int _minutesFromDayStart(DateTime value) => value.hour * 60 + value.minute;

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

class _AnniversaryTile extends StatelessWidget {
  final String title;
  final Color color;
  final String? subtitle;

  const _AnniversaryTile({
    required this.title,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.18), width: 0.45),
      ),
      child: Row(
        children: [
          Icon(Icons.celebration_outlined, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: DesignTokens.fontWeightStrong,
                    fontSize: 13,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
