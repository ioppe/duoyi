import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/widgets/focus_task_stats_card.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/statistics_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _open(WidgetTester tester, {bool populated = false}) async {
  tester.view.physicalSize = const Size(390, 12000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final todos = TodoProvider();
  final audit = TimeAuditProvider();
  final pomo = PomodoroProvider();
  if (populated) {
    for (final (id, date, minutes) in [
      ('last-year', DateTime.utc(2025, 12, 31, 12), 120),
      ('year', DateTime.utc(2026, 1, 10, 12), 90),
      ('month', DateTime.utc(2026, 6, 4, 12), 60),
      ('week', DateTime.utc(2026, 6, 16, 12), 30),
    ]) {
      await todos.addTodo(
        TodoItem(
          id: id,
          title: id,
          isCompleted: true,
          createdAt: date,
          completedAt: date,
          updatedAt: date,
        ),
      );
      await audit.add(
        TimeEntry(
          id: id,
          title: id,
          startAt: date,
          endAt: date.add(Duration(minutes: minutes)),
          category: TimeEntryCategory.work,
        ),
      );
    }
    pomo.sessions.add(
      PomodoroSession(
        id: 'cross-midnight',
        todoId: 'task-project',
        todoTitle: '项目任务',
        subtaskId: 'task-research',
        taskName: '需求调研',
        startTime: DateTime.utc(2026, 6, 14, 23, 45),
        endTime: DateTime.utc(2026, 6, 15, 0, 15),
        durationSeconds: 1800,
        type: PomodoroType.focus,
      ),
    );
  }
  if (populated) {
    pomo.sessions.add(
      PomodoroSession(
        id: 'earlier-month',
        startTime: DateTime.utc(2026, 6, 4, 11),
        endTime: DateTime.utc(2026, 6, 4, 11, 10),
        durationSeconds: 600,
        type: PomodoroType.focus,
        todoId: 'task-project',
        todoTitle: '项目任务',
        subtaskId: 'task-research',
        taskName: '需求调研',
      ),
    );
  }
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TodoProvider>.value(value: todos),
        ChangeNotifierProvider(create: (_) => GoalProvider()),
        ChangeNotifierProvider(create: (_) => HabitProvider()),
        ChangeNotifierProvider<PomodoroProvider>.value(value: pomo),
        ChangeNotifierProvider<TimeAuditProvider>.value(value: audit),
        ChangeNotifierProvider(create: (_) => AiService()),
      ],
      child: MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        home: const StatisticsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _kpi(String title) => find
    .ancestor(
      of: find.text(title),
      matching: find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_Kpi',
      ),
    )
    .first;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalTimezoneResolver.setApplicationTimeZone('UTC');
    I18n.setLocale(AppLocale.zh);
    AppClock.debugNow = () => DateTime.utc(2026, 6, 17, 12);
  });
  tearDown(() => AppClock.debugNow = null);

  testWidgets('本周只有本周活动分布，不出现年度热力图', (tester) async {
    await _open(tester);
    expect(find.text('年度活动热力图'), findsNothing);
    expect(find.text('本周活动分布'), findsOneWidget);
    expect(find.text('本周时间概览'), findsOneWidget);
    expect(find.text('近 6 周同段效率分'), findsNothing);
  });

  testWidgets('周月年切换同时改变活动形态、时间总量和待办汇总', (tester) async {
    await _open(tester, populated: true);
    for (final (range, activity, time, total, todos) in [
      ('本周', '本周活动分布', '本周时间概览', '30 分钟', '1'),
      ('本月', '本月活动日历', '本月时间概览', '1.5 小时', '2'),
      ('本年', '年度活动热力图', '本年时间概览', '3 小时', '3'),
    ]) {
      await tester.tap(
        find.descendant(of: find.byType(AppBar), matching: find.text(range)),
      );
      await tester.pumpAndSettle();
      expect(find.text(activity), findsOneWidget);
      expect(find.text(time), findsOneWidget);
      final overview = find.byKey(const ValueKey('statistics_time_overview'));
      expect(
        find.descendant(of: overview, matching: find.text(total)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _kpi('待办完成'), matching: find.text(todos)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('任务专注随周月年切换，子任务明细不重复计算', (tester) async {
    await _open(tester, populated: true);
    for (final (range, minutes, sessions) in [
      ('本周', 30, 1),
      ('本月', 40, 2),
      ('本年', 40, 2),
    ]) {
      await tester.tap(
        find.descendant(of: find.byType(AppBar), matching: find.text(range)),
      );
      await tester.pumpAndSettle();
      final card = find.byType(FocusTaskStatsCard);
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: card, matching: find.text('项目任务')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text('$minutes 分钟 · $sessions 次专注'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: card, matching: find.byType(ExpansionTile)),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: card, matching: find.text('需求调研')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('跨午夜的专注按结束日期进入本周，保持汇总一致', (tester) async {
    await _open(tester, populated: true);
    expect(
      find.descendant(of: _kpi('深度专注'), matching: find.text('30 分')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
