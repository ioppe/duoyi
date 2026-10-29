import 'dart:convert';

import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/home_widget_calendar.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/todo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 构造最小 TodoItem：默认 date=2026-06-01、createdAt=2026-06-01 09:00、
/// updatedAt=2026-06-05 12:00，各测试按需覆盖。
TodoItem _todo(
  String id, {
  DateTime? dueDate,
  DateTime? createdAt,
  DateTime? date,
  DateTime? updatedAt,
  bool isCompleted = false,
  bool archived = false,
  List<Subtask> subtasks = const <Subtask>[],
}) => TodoItem(
  id: id,
  title: id,
  dueDate: dueDate,
  createdAt: createdAt ?? DateTime(2026, 6, 1, 9),
  date: date ?? DateTime(2026, 6, 1),
  updatedAt: updatedAt ?? DateTime(2026, 6, 5, 12),
  isCompleted: isCompleted,
  isArchivedAfterRollover: archived,
  subtasks: subtasks,
);

Future<void> _useZone(String name) =>
    LocalTimezoneResolver.setApplicationTimeZone(name);

List<DateTime> _days(List<List<DateTime?>> weeks) => <DateTime>[
  for (final week in weeks)
    for (final day in week) ?day,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // 系统时区固定为 UTC，应用时区由各用例显式切换。
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async => 'UTC';
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = () async => 'UTC';
  });

  tearDownAll(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = null;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalTimezoneResolver.init();
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() async {
    AppClock.debugNow = null;
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalTimezoneResolver.init();
  });

  group('homeWidgetCalendarDayKey', () {
    test('formats the floating date with zero padding and no zone shift', () {
      expect(homeWidgetCalendarDayKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(homeWidgetCalendarDayKey(DateTime(2026, 12, 31)), '2026-12-31');
      expect(homeWidgetCalendarDayKey(DateTime(2026, 2, 1)), '2026-02-01');
    });
  });

  group('buildHomeWidgetCalendarDayCounts', () {
    test('due date wins and each todo is counted only once', () {
      final counts = buildHomeWidgetCalendarDayCounts(<TodoItem>[
        // date 在 6/1，截止 6/10：不能沿 date..due 在多天各计 1 次。
        _todo(
          'long',
          date: DateTime(2026, 6, 1),
          dueDate: DateTime(2026, 6, 10),
        ),
      ]);

      expect(counts, <String, int>{'2026-06-10': 1});
      expect(counts.containsKey('2026-06-01'), isFalse);
    });

    test('without a due date the creation day is used, not date or now', () {
      AppClock.debugNow = () => DateTime.utc(2026, 9, 9, 12);
      final counts = buildHomeWidgetCalendarDayCounts(<TodoItem>[
        _todo(
          'no-due',
          date: DateTime(2026, 6, 20),
          createdAt: DateTime(2026, 6, 3, 8),
          updatedAt: DateTime(2026, 6, 25, 18),
        ),
      ]);

      expect(counts, <String, int>{'2026-06-03': 1});
    });

    test('completed tasks still count while rollover-archived ones do not', () {
      final counts = buildHomeWidgetCalendarDayCounts(<TodoItem>[
        _todo('open', dueDate: DateTime(2026, 7, 1)),
        _todo('done', dueDate: DateTime(2026, 7, 1), isCompleted: true),
        _todo('archived', dueDate: DateTime(2026, 7, 1), archived: true),
      ]);

      expect(counts, <String, int>{'2026-07-01': 2});
    });

    test('nested subtasks never add extra counts', () {
      final counts = buildHomeWidgetCalendarDayCounts(<TodoItem>[
        _todo(
          'parent',
          dueDate: DateTime(2026, 7, 2),
          subtasks: <Subtask>[
            Subtask(title: 's1'),
            Subtask(title: 's2'),
            Subtask(title: 's3'),
          ],
        ),
      ]);

      expect(counts, <String, int>{'2026-07-02': 1});
    });

    test('a removed todo leaves nothing behind', () {
      final todos = <TodoItem>[
        _todo('keep', dueDate: DateTime(2026, 7, 3)),
        _todo('drop', dueDate: DateTime(2026, 7, 3)),
      ];
      expect(buildHomeWidgetCalendarDayCounts(todos), <String, int>{
        '2026-07-03': 2,
      });

      // 删除在 provider 层物理移除：重建统计后不应残留。
      todos.removeWhere((todo) => todo.id == 'drop');
      expect(buildHomeWidgetCalendarDayCounts(todos), <String, int>{
        '2026-07-03': 1,
      });
    });

    test('empty input yields an empty object', () {
      expect(buildHomeWidgetCalendarDayCounts(const <TodoItem>[]), isEmpty);
      expect(homeWidgetCalendarDayCountsJson(const <String, int>{}), '{}');
    });

    test('a floating due date keeps its day in both time zones', () async {
      final todo = _todo('floating', dueDate: DateTime(2026, 7, 1));

      await _useZone('Asia/Shanghai');
      expect(buildHomeWidgetCalendarDayCounts(<TodoItem>[todo]), <String, int>{
        '2026-07-01': 1,
      });

      await _useZone('America/New_York');
      expect(buildHomeWidgetCalendarDayCounts(<TodoItem>[todo]), <String, int>{
        '2026-07-01': 1,
      });
    });

    test(
      'a UTC due instant follows the app zone across a day boundary',
      () async {
        final todo = _todo(
          'utc-due',
          dueDate: DateTime.utc(2026, 6, 30, 16, 30),
        );

        await _useZone('Asia/Shanghai');
        expect(
          buildHomeWidgetCalendarDayCounts(<TodoItem>[todo]),
          <String, int>{'2026-07-01': 1},
        );

        await _useZone('America/New_York');
        expect(
          buildHomeWidgetCalendarDayCounts(<TodoItem>[todo]),
          <String, int>{'2026-06-30': 1},
        );
      },
    );

    test('a UTC creation instant converts once into the app zone', () async {
      final todo = _todo(
        'utc-created',
        createdAt: DateTime.utc(2026, 6, 30, 23, 30),
      );

      await _useZone('Asia/Shanghai');
      expect(buildHomeWidgetCalendarDayCounts(<TodoItem>[todo]), <String, int>{
        '2026-07-01': 1,
      });

      await _useZone('America/New_York');
      expect(buildHomeWidgetCalendarDayCounts(<TodoItem>[todo]), <String, int>{
        '2026-06-30': 1,
      });
    });

    test('an offset-free wall clock timestamp is not shifted twice', () async {
      // createdAt 的序列化形态：设备墙钟、无偏移。旧实现无条件 toLocal 会把
      // 23:30 当成 instant 再换算，跨到次日。
      final todo = _todo(
        'wall-clock',
        createdAt: DateTime(2026, 6, 30, 23, 30),
      );

      await _useZone('Asia/Shanghai');
      expect(buildHomeWidgetCalendarDayCounts(<TodoItem>[todo]), <String, int>{
        '2026-06-30': 1,
      });

      await _useZone('America/New_York');
      expect(buildHomeWidgetCalendarDayCounts(<TodoItem>[todo]), <String, int>{
        '2026-06-30': 1,
      });
    });

    test('end-of-day wall clock keeps its own day', () async {
      final todo = _todo(
        'end-of-day',
        dueDate: DateTime(2026, 7, 1, 23, 59, 59, 999),
      );

      await _useZone('Asia/Shanghai');
      expect(buildHomeWidgetCalendarDayCounts(<TodoItem>[todo]), <String, int>{
        '2026-07-01': 1,
      });

      await _useZone('America/New_York');
      expect(buildHomeWidgetCalendarDayCounts(<TodoItem>[todo]), <String, int>{
        '2026-07-01': 1,
      });
    });

    test('keys stay sorted across months and years', () async {
      final counts = buildHomeWidgetCalendarDayCounts(<TodoItem>[
        _todo('c', dueDate: DateTime(2026, 2, 1)),
        _todo('a', dueDate: DateTime(2025, 12, 31)),
        _todo('b', dueDate: DateTime(2026, 1, 1)),
      ]);

      expect(counts.keys.toList(), <String>[
        '2025-12-31',
        '2026-01-01',
        '2026-02-01',
      ]);
      expect(
        homeWidgetCalendarDayCountsJson(counts),
        '{"2025-12-31":1,"2026-01-01":1,"2026-02-01":1}',
      );
    });

    test('json encoding is canonical for unsorted input', () {
      final json = homeWidgetCalendarDayCountsJson(<String, int>{
        '2026-10-05': 2,
        '2026-01-09': 1,
        '2025-12-31': 3,
      });

      expect(json, '{"2025-12-31":3,"2026-01-09":1,"2026-10-05":2}');
      expect(jsonDecode(json), <String, dynamic>{
        '2025-12-31': 3,
        '2026-01-09': 1,
        '2026-10-05': 2,
      });
    });
  });

  group('buildHomeWidgetCalendarWeeks', () {
    test('October 2026 starts on Thursday and spans five rows', () {
      final weeks = buildHomeWidgetCalendarWeeks(DateTime(2026, 10));

      expect(weeks.length, 5);
      // 周一..周三为前导空位，周四（下标 3）是 1 号。
      expect(weeks.first.sublist(0, 3), everyElement(isNull));
      expect(weeks.first[3], DateTime(2026, 10, 1));
      expect(_days(weeks).length, 31);
      expect(_days(weeks).first, DateTime(2026, 10, 1));
      expect(_days(weeks).last, DateTime(2026, 10, 31));
    });

    test('February 2024 keeps the leap day in five rows', () {
      final weeks = buildHomeWidgetCalendarWeeks(DateTime(2024, 2));
      final days = _days(weeks);

      expect(weeks.length, 5);
      expect(days.length, 29);
      expect(days.contains(DateTime(2024, 2, 29)), isTrue);
      expect(days.last, DateTime(2024, 2, 29));
    });

    test('February 2021 starts on Monday and needs exactly four rows', () {
      final weeks = buildHomeWidgetCalendarWeeks(DateTime(2021, 2));

      expect(weeks.length, 4);
      expect(weeks.expand((week) => week).every((day) => day != null), isTrue);
      expect(_days(weeks).length, 28);
      expect(weeks.first.first, DateTime(2021, 2, 1));
      expect(weeks.last.last, DateTime(2021, 2, 28));
    });

    test('August 2020 ends with a single day in its sixth row', () {
      final weeks = buildHomeWidgetCalendarWeeks(DateTime(2020, 8));

      expect(weeks.length, 6);
      expect(weeks.last.first, DateTime(2020, 8, 31));
      expect(weeks.last.sublist(1), everyElement(isNull));
      expect(_days(weeks).length, 31);
    });

    test('every day appears once, rows are seven wide and never empty', () {
      for (final month in <DateTime>[
        DateTime(2026, 10),
        DateTime(2024, 2),
        DateTime(2021, 2),
        DateTime(2020, 8),
        DateTime(2025, 12),
      ]) {
        final weeks = buildHomeWidgetCalendarWeeks(month);
        final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
        final days = _days(weeks);

        expect(weeks, hasLength(inInclusiveRange(4, 6)), reason: '$month');
        expect(weeks.every((week) => week.length == 7), isTrue);
        expect(weeks.every((week) => week.any((day) => day != null)), isTrue);
        expect(days.length, daysInMonth, reason: '$month');
        expect(days.map((day) => day.day).toSet(), <int>{
          for (var day = 1; day <= daysInMonth; day++) day,
        }, reason: '$month 每天恰好出现一次');
        // 返回浮动日期，不带时区信息。
        expect(days.every((day) => !day.isUtc), isTrue);
      }
    });

    test('any day of the month anchors on that month', () {
      final weeks = buildHomeWidgetCalendarWeeks(DateTime(2026, 10, 17, 23, 5));

      expect(weeks.first[3], DateTime(2026, 10, 1));
      expect(_days(weeks).last, DateTime(2026, 10, 31));
    });
  });

  group('homeWidgetCalendarWeekdayLabels', () {
    test('follows the active language', () {
      I18n.setLocale(AppLocale.zh);
      expect(homeWidgetCalendarWeekdayLabels(), <String>[
        '一',
        '二',
        '三',
        '四',
        '五',
        '六',
        '日',
      ]);

      I18n.setLocale(AppLocale.en);
      expect(homeWidgetCalendarWeekdayLabels(), <String>[
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ]);
    });

    test('serializes to a seven element JSON array', () {
      I18n.setLocale(AppLocale.zh);
      expect(jsonDecode(homeWidgetCalendarWeekdayLabelsJson()), <String>[
        '一',
        '二',
        '三',
        '四',
        '五',
        '六',
        '日',
      ]);
    });
  });
}
