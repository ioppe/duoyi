import 'dart:convert';

import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _two(int value) => value.toString().padLeft(2, '0');

String _stamp(int year, int month, int day) =>
    '$year-${_two(month)}-${_two(day)}';

Finder _dateCell(int year, int month, int day) =>
    find.byKey(ValueKey('widget-calendar-date-${_stamp(year, month, day)}'));

Finder _badge(int year, int month, int day) =>
    find.byKey(ValueKey('widget-calendar-badge-${_stamp(year, month, day)}'));

Future<void> _pumpCalendar(
  WidgetTester tester, {
  required WidgetDisplayMode mode,
  TodoProvider? todos,
  Size surface = const Size(320, 720),
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  Widget card = WidgetPreviewCard.calendar(displayMode: mode);
  if (todos != null) {
    card = ChangeNotifierProvider<TodoProvider>.value(
      value: todos,
      child: card,
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: card,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<TodoProvider> _providerWithTodos(List<TodoItem> items) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'todos': jsonEncode(<Map<String, dynamic>>[
      for (final todo in items) todo.toJson(),
    ]),
  });
  final provider = TodoProvider();
  await provider.loadFromStorage();
  addTearDown(provider.dispose);
  return provider;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalTimezoneResolver.setApplicationTimeZone('UTC');
  });

  tearDown(() {
    AppClock.debugNow = null;
  });

  testWidgets('三种密度都完整渲染当月 1..31，无事项时不显示角标', (tester) async {
    AppClock.debugNow = () => DateTime.utc(2026, 10, 26, 8);
    for (final mode in WidgetDisplayMode.values) {
      await _pumpCalendar(tester, mode: mode);
      expect(tester.takeException(), isNull, reason: '${mode.id} 预览不应溢出');
      for (var day = 1; day <= 31; day++) {
        expect(
          _dateCell(2026, 10, day),
          findsOneWidget,
          reason: '${mode.id} 缺少 10 月 $day 日',
        );
        expect(
          _badge(2026, 10, day),
          findsNothing,
          reason: '${mode.id} 没有事项的 10 月 $day 日不应有角标',
        );
      }
      expect(_dateCell(2026, 9, 30), findsNothing, reason: '不应混入上月日期');
      expect(_dateCell(2026, 11, 1), findsNothing, reason: '不应混入下月日期');
      // 2026 年 10 月 1 日是周四：前导 3 格 + 31 天 = 5 行。
      for (var week = 0; week < 5; week++) {
        expect(
          find.byKey(ValueKey('widget-calendar-week-$week')),
          findsOneWidget,
          reason: '${mode.id} 缺少第 $week 行',
        );
      }
      expect(
        find.byKey(const ValueKey('widget-calendar-week-5')),
        findsNothing,
      );

      final todayCell = tester.widget<Container>(_dateCell(2026, 10, 26));
      final otherCell = tester.widget<Container>(_dateCell(2026, 10, 20));
      expect(
        (todayCell.decoration! as BoxDecoration).color,
        isNot(Colors.transparent),
        reason: '${mode.id} 今日需要突出显示',
      );
      expect(
        (otherCell.decoration! as BoxDecoration).color,
        Colors.transparent,
      );
    }
  });

  testWidgets('闰年 2024 年 2 月显示 29 天且不出现 30 日', (tester) async {
    AppClock.debugNow = () => DateTime.utc(2024, 2, 10, 8);
    await _pumpCalendar(tester, mode: WidgetDisplayMode.standard);
    expect(tester.takeException(), isNull);
    for (var day = 1; day <= 29; day++) {
      expect(_dateCell(2024, 2, day), findsOneWidget, reason: '缺少 2 月 $day 日');
    }
    expect(_dateCell(2024, 2, 30), findsNothing);
    expect(_dateCell(2024, 3, 1), findsNothing);
  });

  testWidgets('2020 年 8 月渲染完整六周共 31 天', (tester) async {
    AppClock.debugNow = () => DateTime.utc(2020, 8, 15, 8);
    await _pumpCalendar(tester, mode: WidgetDisplayMode.detailed);
    expect(tester.takeException(), isNull);
    for (var week = 0; week < 6; week++) {
      expect(
        find.byKey(ValueKey('widget-calendar-week-$week')),
        findsOneWidget,
        reason: '缺少第 $week 行',
      );
    }
    expect(find.byKey(const ValueKey('widget-calendar-week-6')), findsNothing);
    for (var day = 1; day <= 31; day++) {
      expect(_dateCell(2020, 8, day), findsOneWidget, reason: '缺少 8 月 $day 日');
    }
    expect(_dateCell(2020, 9, 1), findsNothing);
  });

  testWidgets('角标显示 TodoProvider 真实到期事项数，0 项不显示', (tester) async {
    AppClock.debugNow = () => DateTime.utc(2026, 10, 26, 8);
    final todos = await _providerWithTodos(<TodoItem>[
      TodoItem(
        id: 'due-1a',
        title: '截止 10/1 A',
        dueDate: DateTime(2026, 10, 1),
      ),
      TodoItem(
        id: 'due-1b',
        title: '截止 10/1 B',
        dueDate: DateTime(2026, 10, 1),
      ),
      TodoItem(
        id: 'done-2',
        title: '已完成 10/2',
        dueDate: DateTime(2026, 10, 2),
        isCompleted: true,
      ),
      TodoItem(id: 'today', title: '今天截止', dueDate: DateTime(2026, 10, 26)),
      TodoItem(
        id: 'created-31',
        title: '无截止，10/31 创建',
        createdAt: DateTime(2026, 10, 31, 9),
      ),
      TodoItem(
        id: 'archived-5',
        title: '跨日归档 10/5',
        dueDate: DateTime(2026, 10, 5),
        isArchivedAfterRollover: true,
      ),
    ]);
    expect(todos.todos, hasLength(6));

    await _pumpCalendar(tester, mode: WidgetDisplayMode.standard, todos: todos);
    expect(tester.takeException(), isNull);

    expect(
      find.descendant(of: _badge(2026, 10, 1), matching: find.text('2')),
      findsOneWidget,
      reason: '10/1 有两项到期事项',
    );
    expect(
      find.descendant(of: _badge(2026, 10, 2), matching: find.text('1')),
      findsOneWidget,
      reason: '已完成但未归档的事项仍占当天',
    );
    expect(
      find.descendant(of: _badge(2026, 10, 26), matching: find.text('1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _badge(2026, 10, 31), matching: find.text('1')),
      findsOneWidget,
      reason: '无截止日期时按创建日归属',
    );
    expect(_badge(2026, 10, 5), findsNothing, reason: '跨日归档事项不再计数');
    expect(_badge(2026, 10, 3), findsNothing, reason: '当天没有事项');

    // 有真实数据时仍展示完整月份。
    for (var day = 1; day <= 31; day++) {
      expect(_dateCell(2026, 10, day), findsOneWidget);
    }
  });

  testWidgets('五周和六周月份的三种密度都不重叠日期与角标', (tester) async {
    for (final (year, month) in const [(2026, 10), (2020, 8)]) {
      AppClock.debugNow = () => DateTime.utc(year, month, 15, 8);
      final todos = await _providerWithTodos(<TodoItem>[
        TodoItem(
          id: 'due-1a',
          title: '月初事项',
          dueDate: DateTime(year, month, 1),
        ),
      ]);
      for (final mode in WidgetDisplayMode.values) {
        await _pumpCalendar(tester, mode: mode, todos: todos);
        expect(tester.takeException(), isNull);
        final dayCell = tester.getRect(_dateCell(year, month, 1));
        final badge = tester.getRect(_badge(year, month, 1));
        final weekRow = tester.getRect(
          find.byKey(const ValueKey('widget-calendar-week-0')),
        );
        expect(badge.center.dy, lessThan(dayCell.center.dy), reason: '角标在上方');
        expect(
          badge.center.dx,
          greaterThan(dayCell.center.dx),
          reason: '角标在右侧',
        );
        expect(
          badge.bottom,
          lessThanOrEqualTo(dayCell.top + 0.5),
          reason: '两段区域不相交',
        );
        expect(badge.top, greaterThanOrEqualTo(weekRow.top - 0.5));
        expect(badge.right, lessThanOrEqualTo(weekRow.right + 0.5));
        expect(dayCell.top, greaterThanOrEqualTo(weekRow.top - 0.5));
        expect(dayCell.bottom, lessThanOrEqualTo(weekRow.bottom + 0.5));
      }
    }
  });
}
