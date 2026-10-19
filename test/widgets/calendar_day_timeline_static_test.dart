import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('日视图按时间线和全天无时间事件分区展示', () {
    final source = File(
      'lib/widgets/calendar_day_agenda.dart',
    ).readAsStringSync();

    expect(source, contains("import 'dart:math' as math;"));
    expect(source, contains('final timedEvents = visibleEvents.where'));
    expect(source, contains('final untimedEvents = visibleEvents.where'));
    expect(source, contains('Expanded('));
    expect(source, contains('Wrap('));
    expect(source, contains('runSpacing: 5'));
    expect(source, contains('Widget _dayBadge('));
    expect(source, contains('_sectionTitle(\'🕘 时间线\')'));
    expect(source, contains('_sectionTitle(\'📝 全天/无时间\')'));
    expect(source, contains('_CalendarDayTimeGrid('));
    expect(source, contains('todoById: todoById'));
    expect(
      source,
      contains('..._buildTimeline(context, untimedEvents, todoById)'),
    );
  });

  test('日视图时间线提供 24 小时刻度和按分钟定位的事件块', () {
    final source = File(
      'lib/widgets/calendar_day_agenda.dart',
    ).readAsStringSync();

    expect(source, contains('class _CalendarDayTimeGrid'));
    expect(source, contains('static const double _hourHeight'));
    expect(source, contains('static const double _timeColumnWidth'));
    expect(source, contains('for (var hour = 0; hour < 24; hour++)'));
    expect(source, contains('class _TimelineHourRow'));
    expect(source, contains('alpha: 0.10'));
    expect(source, contains('alpha: 0.08'));
    expect(source, contains('Positioned('));
    expect(source, contains('top: clampedTop'));
    expect(source, contains('height: clampedHeight'));
    expect(source, contains('_minutesFromDayStart(start) / 60 * _hourHeight'));
    expect(source, contains('_overlapLane(event, index)'));
    expect(source, contains('overlapLane * 10.0'));
  });

  test('时间线事件支持跨日边界裁剪和短块紧凑卡片', () {
    final source = File(
      'lib/widgets/calendar_day_agenda.dart',
    ).readAsStringSync();

    expect(source, contains('DateTime _eventStartOnDay('));
    expect(source, contains('DateTime _eventEndOnDay('));
    expect(source, contains('int _minutesFromDayStart(DateTime value)'));
    expect(source, contains('final dayEnd = AppClock.date('));
    expect(source, contains('math.max(30, end.difference(start).inMinutes)'));
    expect(source, contains('compact: clampedHeight < 88'));
    expect(source, contains('final bool compact'));
    expect(source, contains('_buildCompactContent(context, e)'));
    expect(source, contains('_buildRegularContent(context, e)'));
    expect(source, contains('_DraggableEventCard('));
  });

  test('日历日程中的待办按完成和逾期状态区分显示', () {
    final agenda = File(
      'lib/widgets/calendar_day_agenda.dart',
    ).readAsStringSync();
    final week = File(
      'lib/widgets/calendar_week_strip.dart',
    ).readAsStringSync();

    for (final source in [agenda, week]) {
      expect(source, contains('TodoVisualState.completed'));
      expect(source, contains('TodoVisualState.overdue'));
      expect(source, contains("label: isCompleted ? '已完成' : '逾期'"));
      expect(source, contains('dueAt.isBefore(AppClock.now())'));
      expect(source, contains('Color.alphaBlend('));
      expect(source, contains('statusColor.withValues(alpha: 0.24)'));
    }
    expect(
      agenda,
      contains(
        'if (event.type != CalendarEventType.todo) return TodoVisualState.normal',
      ),
    );
    expect(agenda, contains("import '../core/todo_templates.dart';"));
    expect(agenda, contains('_CalendarTodoVisual _calendarEventVisual('));
    expect(agenda, contains('Map<String, TodoItem> todoById'));
    expect(agenda, contains('final todo = todoById[event.sourceId]'));
    expect(agenda, isNot(contains('for (final todo in todos)')));
    expect(agenda, contains('TodoListTemplates.all'));
    expect(agenda, contains('EisenhowerQuadrant.urgentImportant'));
    expect(agenda, contains('class _CalendarAgendaStatusBadge'));
    expect(week, contains('class _WeekEventStatusBadge'));
    expect(week, contains("import '../models/calendar_event.dart';"));
    expect(week, contains("import '../providers/calendar_provider.dart';"));
  });
}
