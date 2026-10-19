import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('CalendarProvider indexes CalendarEvent endDate spans', () {
    final source = File(
      'lib/providers/calendar_provider.dart',
    ).readAsStringSync();

    expect(source, contains('_eventOccursOnDate(e, key)'));
    expect(source, contains('dates.addAll(_eventDates(e))'));
    expect(source, contains('for (final key in _eventDateKeys(e))'));
    expect(source, contains('List<DateTime> _eventDates(CalendarEvent event)'));
    expect(
      source,
      contains('List<String> _eventDateKeys(CalendarEvent event)'),
    );
    expect(source, contains('DateTime _eventVisibleEndDate('));
    expect(source, contains('event.endDate'));
    // 逐日递增而非 Duration(days: n) 累加：跨夏令时切换日不会漏/重日期。
    expect(source, contains('day = DateTime(day.year, day.month, day.day + 1)'));
  });

  test('CalendarProvider handles all-day midnight DTEND as exclusive', () {
    final source = File(
      'lib/providers/calendar_provider.dart',
    ).readAsStringSync();

    expect(source, contains('final endsAtMidnight'));
    expect(source, contains('endDate.hour == 0'));
    expect(source, contains('endDate.minute == 0'));
    expect(source, contains('endDate.second == 0'));
    expect(source, contains('endDate.millisecond == 0'));
    expect(source, contains('endDate.microsecond == 0'));
    expect(source, contains('end = DateTime(end.year, end.month, end.day - 1)'));
  });

  test('CalendarProvider supports shared workspace calendar filters', () {
    final provider = File(
      'lib/providers/calendar_provider.dart',
    ).readAsStringSync();
    final model = File('lib/models/calendar_event.dart').readAsStringSync();
    final aggregator = File(
      'lib/core/calendar_aggregator.dart',
    ).readAsStringSync();

    expect(model, contains('final String? workspaceId;'));
    expect(model, contains("'workspaceId': workspaceId"));
    expect(aggregator, contains('workspaceId: t.workspaceId'));
    expect(aggregator, contains('workspaceId: g.workspaceId'));
    expect(provider, contains('String? workspaceId'));
    expect(provider, contains('bool _matchesWorkspace('));
    expect(provider, contains('final eventWorkspaceId = event.workspaceId;'));
    expect(provider, contains("if (workspaceId == 'private')"));
    expect(provider, contains('event.workspaceId'));
    expect(provider, contains('return eventWorkspaceId == workspaceId;'));
  });
}
