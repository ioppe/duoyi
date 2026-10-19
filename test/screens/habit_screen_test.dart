import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/habit_screen.dart';
import 'package:duoyi/widgets/surface_components.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpHabitScreen(
    WidgetTester tester,
    HabitProvider habitProvider,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HabitProvider>.value(value: habitProvider),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: const MaterialApp(home: HabitScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('新建习惯至多三分之二屏，表单可滚到保存且遮罩可关闭', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final habitProvider = HabitProvider();
    await pumpHabitScreen(tester, habitProvider);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    final card = tester.getRect(
      find.descendant(
        of: find.byType(AppModalSheet),
        matching: find.byType(Material),
      ).first,
    );
    expect(card.height, closeTo(844 * 2 / 3, 0.5));
    final saveButton = find.widgetWithText(ElevatedButton, '开启新习惯');
    // 使用真实拖动手势核验表单滚动，避免只验证 ensureVisible 的程序跳转。
    for (var i = 0; i < 5; i++) {
      await tester.dragFrom(const Offset(10, 760), const Offset(0, -350));
      await tester.pumpAndSettle();
    }
    expect(saveButton.hitTestable(), findsOneWidget);
    await tester.tapAt(Offset(card.center.dx, card.top - 20));
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsNothing);
    expect(habitProvider.habits, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('negative habit count uses custom unit on main habit card', (
    tester,
  ) async {
    final habitProvider = HabitProvider();
    final dateKey = Habit(id: 'key-helper', name: 'helper').todayKey();
    await habitProvider.addHabit(
      Habit(
        id: 'coffee',
        name: '少喝咖啡',
        kind: HabitKind.negative,
        icon: Icons.local_cafe_outlined.codePoint.toString(),
        unit: '杯',
        completions: {dateKey: 1},
      ),
    );

    await pumpHabitScreen(tester, habitProvider);

    expect(find.textContaining('1 杯'), findsOneWidget);
    expect(find.textContaining('1 次'), findsNothing);
    expect(find.byIcon(Icons.local_cafe_outlined), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    expect(find.byIcon(Icons.shield_outlined), findsNothing);
  });

  testWidgets('weekly overview refreshes after today check-in', (tester) async {
    final habitProvider = HabitProvider();
    await habitProvider.addHabit(
      Habit(id: 'read', name: '阅读', icon: Icons.book.codePoint.toString()),
    );
    final expectedAfter = (100 / DateTime.now().weekday).round();

    await pumpHabitScreen(tester, habitProvider);

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('habit_weekly_overview_percent')),
          )
          .data,
      '0%',
    );
    expect(find.text('进度'), findsOneWidget);
    expect(find.byIcon(Icons.book), findsOneWidget);

    await tester.tap(find.text('打卡').first);
    await tester.pumpAndSettle();

    expect(habitProvider.habits.single.todayCount(), 1);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('habit_weekly_overview_percent')),
          )
          .data,
      '$expectedAfter%',
    );
    expect(find.text('进度'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'weekly overview remains first even when there is no active habit',
    (tester) async {
      final habitProvider = HabitProvider();

      await pumpHabitScreen(tester, habitProvider);

      expect(
        find.byKey(const ValueKey('habit_weekly_overview_card')),
        findsOneWidget,
      );
      expect(find.text('本周概览'), findsOneWidget);
      expect(find.text('添加习惯'), findsOneWidget);
    },
  );

  testWidgets('new habit reminder defaults to popup plan', (tester) async {
    final habitProvider = HabitProvider();

    await pumpHabitScreen(tester, habitProvider);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '习惯名称'), '喝水');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(Switch).first);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(ElevatedButton, '开启新习惯');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    final stored = habitProvider.habits.single;
    expect(stored.remind, isTrue);
    expect(stored.reminderPlan.enabled, isTrue);
    expect(stored.reminderPlan.rules, hasLength(1));
    expect(stored.reminderPlan.rules.single.type, ReminderRuleType.dailyTime);
    expect(stored.reminderPlan.rules.single.kind, ReminderKind.popup);
  });

  testWidgets('weekly overview keeps expanded readable metrics', (
    tester,
  ) async {
    final habitProvider = HabitProvider();
    await habitProvider.addHabit(
      Habit(id: 'read', name: '阅读', icon: Icons.book.codePoint.toString()),
    );

    await pumpHabitScreen(tester, habitProvider);

    expect(
      find.byKey(const ValueKey('habit_weekly_overview_card')),
      findsOneWidget,
    );
    expect(find.text('本周概览'), findsOneWidget);

    final iconRect = tester.getRect(
      find.byKey(const ValueKey('habit_weekly_overview_icon_box')),
    );
    expect(iconRect.width, closeTo(30, 0.001));
    expect(iconRect.height, closeTo(30, 0.001));

    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('habit_weekly_overview_progress_bar')),
    );
    expect(progress.minHeight, 3);

    final todayIndex = DateTime.now().weekday - 1;
    final dayRect = tester.getRect(
      find.byKey(ValueKey('habit_weekly_overview_day_$todayIndex')),
    );
    expect(dayRect.width, closeTo(25, 0.001));
    expect(dayRect.height, closeTo(25, 0.001));
  });

  testWidgets('habit insights render above today check-in list', (
    tester,
  ) async {
    final habitProvider = HabitProvider();
    final now = DateTime.now();
    final completions = <String, int>{};
    for (var i = 0; i < 8; i++) {
      final day = now.subtract(Duration(days: i));
      completions[Habit(id: 'tmp', name: 'tmp').dateKey(day)] = 1;
    }
    await habitProvider.addHabit(
      Habit(
        id: 'read',
        name: '阅读',
        icon: Icons.book.codePoint.toString(),
        completions: completions,
      ),
    );

    await pumpHabitScreen(tester, habitProvider);

    expect(
      find.byKey(const ValueKey('habit_insight_before_today_list')),
      findsOneWidget,
    );
    expect(find.text('智能习惯洞察'), findsOneWidget);
    expect(find.byIcon(Icons.insights_outlined), findsOneWidget);
    expect(find.textContaining('30天'), findsWidgets);

    final insightTop = tester
        .getTopLeft(find.byKey(const ValueKey('habit_insight_card')))
        .dy;
    final listTop = tester
        .getTopLeft(find.byKey(const ValueKey('habit_checkin_card_read')))
        .dy;
    expect(insightTop, lessThan(listTop));
  });

  testWidgets('flex period target text does not repeat target prefix', (
    tester,
  ) async {
    final habitProvider = HabitProvider();
    await habitProvider.addHabit(
      Habit(
        id: 'weekly-flex',
        name: '阅读',
        flexPeriod: HabitFlexPeriod.week,
        flexTarget: 3,
        targetCount: 1,
      ),
    );

    await pumpHabitScreen(tester, habitProvider);

    expect(find.textContaining('目标: 周期目标:'), findsNothing);
    expect(find.textContaining('每周目标: 3 次'), findsOneWidget);
    expect(find.textContaining('单次目标: 1 次'), findsOneWidget);
  });

  testWidgets('monthly flex period target text uses period goal copy', (
    tester,
  ) async {
    final habitProvider = HabitProvider();
    await habitProvider.addHabit(
      Habit(
        id: 'monthly-flex',
        name: '整理复盘',
        flexPeriod: HabitFlexPeriod.month,
        flexTarget: 4,
        targetCount: 1,
      ),
    );

    await pumpHabitScreen(tester, habitProvider);

    expect(find.textContaining('目标: 周期目标:'), findsNothing);
    expect(find.textContaining('每月目标: 4 次'), findsOneWidget);
    expect(find.textContaining('单次目标: 1 次'), findsOneWidget);
  });

  testWidgets('completed flex period disables check-in with period copy', (
    tester,
  ) async {
    final habitProvider = HabitProvider();
    final todayKey = Habit(id: 'key-helper', name: 'helper').todayKey();
    await habitProvider.addHabit(
      Habit(
        id: 'weekly-flex-done',
        name: '本周阅读',
        flexPeriod: HabitFlexPeriod.week,
        flexTarget: 1,
        targetCount: 1,
        completions: {todayKey: 1},
      ),
    );
    await habitProvider.addHabit(
      Habit(
        id: 'monthly-flex-done',
        name: '本月复盘',
        flexPeriod: HabitFlexPeriod.month,
        flexTarget: 1,
        targetCount: 1,
        completions: {todayKey: 1},
      ),
    );

    await pumpHabitScreen(tester, habitProvider);

    final weeklyButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '本周完成'),
    );
    final monthlyButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '本月完成'),
    );
    expect(weeklyButton.onPressed, isNull);
    expect(monthlyButton.onPressed, isNull);
    expect(find.text('本周达标'), findsOneWidget);
    expect(find.text('本月达标'), findsOneWidget);
    expect(find.text('完成'), findsNothing);
  });

  testWidgets('habit card uses stored creation icon instead of fallback star', (
    tester,
  ) async {
    final habitProvider = HabitProvider();
    await habitProvider.addHabit(
      Habit(
        id: 'run',
        name: '跑步',
        icon: Icons.directions_run.codePoint.toString(),
      ),
    );

    await pumpHabitScreen(tester, habitProvider);

    expect(find.byIcon(Icons.directions_run), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNothing);
  });

  testWidgets('custom habit without icon uses neutral target icon', (
    tester,
  ) async {
    final habitProvider = HabitProvider();
    await habitProvider.addHabit(Habit(id: 'custom', name: '自定义习惯'));

    await pumpHabitScreen(tester, habitProvider);

    expect(find.byIcon(Icons.track_changes_outlined), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
  });

  testWidgets(
    'template habit falls back to template icon for legacy check icon',
    (tester) async {
      final habitProvider = HabitProvider();
      await habitProvider.addHabit(
        Habit(id: 'water', name: '每日喝水', icon: 'check_circle_outline'),
      );

      await pumpHabitScreen(tester, habitProvider);

      expect(find.byIcon(Icons.local_drink), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    },
  );

  testWidgets('habit row keeps edit end and delete behind left swipe', (
    tester,
  ) async {
    final habitProvider = HabitProvider();
    await habitProvider.addHabit(
      Habit(id: 'read', name: '阅读', icon: Icons.book.codePoint.toString()),
    );

    await pumpHabitScreen(tester, habitProvider);

    expect(find.byTooltip('编辑'), findsNothing);
    expect(
      find.byKey(const ValueKey('habit_inline_edit_button')),
      findsNothing,
    );
    expect(find.byTooltip('习惯操作'), findsNothing);
    expect(find.byKey(const ValueKey('habit_swipe_edit_button')), findsNothing);
    expect(find.byKey(const ValueKey('habit_swipe_end_button')), findsNothing);
    expect(
      find.byKey(const ValueKey('habit_swipe_delete_button')),
      findsNothing,
    );

    await tester.drag(find.text('阅读').first, const Offset(-180, 0));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('habit_swipe_edit_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('habit_swipe_end_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('habit_swipe_delete_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('habit_swipe_end_button')));
    await tester.pumpAndSettle();

    expect(habitProvider.habits.single.isActiveToday(), isFalse);
    expect(find.text('阅读'), findsNothing);
  });

  testWidgets('ending a completed habit removes it from today', (tester) async {
    final habitProvider = HabitProvider();
    final todayKey = Habit(id: 'key-helper', name: 'helper').todayKey();
    await habitProvider.addHabit(
      Habit(
        id: 'read',
        name: '阅读',
        icon: Icons.book.codePoint.toString(),
        completions: {todayKey: 1},
      ),
    );

    await pumpHabitScreen(tester, habitProvider);

    await tester.drag(find.text('阅读').first, const Offset(-180, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('habit_swipe_end_button')));
    await tester.pumpAndSettle();

    expect(habitProvider.habits.single.isActiveToday(), isFalse);
    expect(habitProvider.habits.single.isCompletedToday(), isFalse);
    expect(find.byKey(const ValueKey('habit_checkin_card_read')), findsNothing);
    expect(find.text('阅读'), findsNothing);
    expect(find.text('已达标'), findsNothing);
  });

  testWidgets('ended habit summary row keeps end action hidden behind swipe', (
    tester,
  ) async {
    final habitProvider = HabitProvider();
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await habitProvider.addHabit(
      Habit(
        id: 'ended',
        name: '已结束习惯',
        icon: Icons.book.codePoint.toString(),
        endDate: DateTime(yesterday.year, yesterday.month, yesterday.day),
      ),
    );

    await pumpHabitScreen(tester, habitProvider);
    await tester.tap(find.text('热度图'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('habit_swipe_end_button')), findsNothing);

    await tester.drag(find.text('已结束习惯').first, const Offset(-180, 0));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('habit_swipe_edit_button')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('habit_swipe_end_button')), findsNothing);
    expect(
      find.byKey(const ValueKey('habit_swipe_delete_button')),
      findsOneWidget,
    );
  });

  testWidgets('active heatmap habit keeps actions behind left swipe', (
    tester,
  ) async {
    final habitProvider = HabitProvider();
    await habitProvider.addHabit(
      Habit(id: 'focus', name: '专注', icon: Icons.timer.codePoint.toString()),
    );

    await pumpHabitScreen(tester, habitProvider);
    await tester.tap(find.text('热度图'));
    await tester.pumpAndSettle();

    expect(find.text('专注'), findsOneWidget);
    expect(find.byIcon(Icons.timer), findsOneWidget);
    expect(find.byKey(const ValueKey('habit_swipe_edit_button')), findsNothing);
    expect(find.byKey(const ValueKey('habit_swipe_end_button')), findsNothing);
    expect(
      find.byKey(const ValueKey('habit_swipe_delete_button')),
      findsNothing,
    );

    await tester.drag(find.text('专注').first, const Offset(160, 0));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('habit_swipe_edit_button')), findsNothing);
    expect(find.byKey(const ValueKey('habit_swipe_end_button')), findsNothing);
    expect(
      find.byKey(const ValueKey('habit_swipe_delete_button')),
      findsNothing,
    );

    await tester.drag(find.text('专注').first, const Offset(-180, 0));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('habit_swipe_edit_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('habit_swipe_end_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('habit_swipe_delete_button')),
      findsOneWidget,
    );
  });

  testWidgets('habit row delete action confirms and removes habit', (
    tester,
  ) async {
    final habitProvider = HabitProvider();
    await habitProvider.addHabit(
      Habit(
        id: 'walk',
        name: '散步',
        icon: Icons.directions_walk.codePoint.toString(),
      ),
    );

    await pumpHabitScreen(tester, habitProvider);

    await tester.drag(find.text('散步').first, const Offset(-180, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('habit_swipe_delete_button')));
    await tester.pumpAndSettle();

    expect(find.text('删除习惯？'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(habitProvider.habits, isEmpty);
  });

  testWidgets('habit row tap opens detail without duplicate swipe detail', (
    tester,
  ) async {
    final habitProvider = HabitProvider();
    await habitProvider.addHabit(
      Habit(id: 'read', name: '阅读', icon: Icons.book.codePoint.toString()),
    );

    await pumpHabitScreen(tester, habitProvider);

    await tester.tap(find.text('阅读').first);
    await tester.pumpAndSettle();

    expect(find.byType(HabitScreen), findsNothing);
    expect(find.text('阅读'), findsWidgets);
    expect(find.byTooltip('更多操作'), findsOneWidget);
  });

  testWidgets('habit row left swipe can end habit', (tester) async {
    final habitProvider = HabitProvider();
    await habitProvider.addHabit(
      Habit(id: 'read', name: '阅读', icon: Icons.book.codePoint.toString()),
    );

    await pumpHabitScreen(tester, habitProvider);

    await tester.drag(find.text('阅读').first, const Offset(-180, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('habit_swipe_end_button')));
    await tester.pumpAndSettle();

    expect(habitProvider.habits.single.isActiveToday(), isFalse);
    expect(find.text('阅读'), findsNothing);
  });

  testWidgets('habit row left swipe delete confirms and removes habit', (
    tester,
  ) async {
    final habitProvider = HabitProvider();
    await habitProvider.addHabit(
      Habit(
        id: 'walk',
        name: '散步',
        icon: Icons.directions_walk.codePoint.toString(),
      ),
    );

    await pumpHabitScreen(tester, habitProvider);

    await tester.drag(find.text('散步').first, const Offset(-180, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('habit_swipe_delete_button')));
    await tester.pumpAndSettle();

    expect(find.text('删除习惯？'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(habitProvider.habits, isEmpty);
  });
}
