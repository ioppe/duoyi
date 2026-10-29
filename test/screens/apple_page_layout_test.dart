import 'dart:io';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/habit_screen.dart';
import 'package:duoyi/screens/mine_screen.dart';
import 'package:duoyi/screens/today_screen.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/app_page_tabs.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:duoyi/widgets/apple_page_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child, {ThemeData? theme, TodoProvider? todoProvider}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<TodoProvider>.value(
        value: todoProvider ?? TodoProvider(),
      ),
      ChangeNotifierProvider(create: (_) => HabitProvider()),
      ChangeNotifierProvider(create: (_) => PomodoroProvider()),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => CloudSyncProvider()),
      ChangeNotifierProvider(create: (_) => CalendarProvider()),
      ChangeNotifierProvider(create: (_) => UserProvider()),
      ChangeNotifierProvider(create: (_) => CountdownProvider()),
      ChangeNotifierProvider(create: (_) => NoteProvider()),
      ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
      ChangeNotifierProvider(create: (_) => DiaryProvider()),
      ChangeNotifierProvider(create: (_) => GoalProvider()),
      ChangeNotifierProvider(create: (_) => CourseProvider()),
      ChangeNotifierProvider(create: (_) => AppLockProvider()),
      ChangeNotifierProvider(create: (_) => PreferencesProvider()),
      ChangeNotifierProvider(create: (_) => AchievementProvider()),
      ChangeNotifierProvider(create: (_) => ShareProvider()),
      ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
      ChangeNotifierProvider(create: (_) => NotificationService()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => AiService()),
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ChangeNotifierProvider(create: (_) => LocationReminderProvider()),
      ChangeNotifierProvider(create: (_) => CalendarSyncProvider()),
      ChangeNotifierProvider(
        create: (_) => AppUpdateService(
          repo: 'dq52099/duoyi',
          currentVersion: AppVersion.name,
        ),
      ),
    ],
    child: MaterialApp(theme: theme, home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('默认主题页面统一走共享 Apple 布局组件，其余主题保持回退分支', () {
    final frame = File('lib/widgets/apple_page_frame.dart').readAsStringSync();
    expect(frame, contains('bool usesApplePageLayout(BuildContext context)'));
    expect(
      frame,
      contains('AppSurfaceStyle.isDefaultTheme(appSurfaceStyleOf(context))'),
    );
    expect(frame, contains('class ApplePageFrame extends StatelessWidget'));
    expect(frame, contains('class AppleGroup extends StatelessWidget'));
    expect(frame, contains('class AppleSectionHeader extends StatelessWidget'));
    // 三个共享组件的非默认主题分支都是原样回退，不引入新容器。
    expect(frame, contains('if (!usesApplePageLayout(context)) return child;'));

    for (final path in [
      'lib/screens/today_screen.dart',
      'lib/screens/todo_screen.dart',
      'lib/screens/habit_screen.dart',
      'lib/screens/pomodoro_screen.dart',
      'lib/screens/mine_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains("import '../widgets/apple_page_frame.dart';"));
      expect(source, contains('usesApplePageLayout(context)'));
    }
  });

  testWidgets('默认主题下今日页左对齐页头与内容列同宽并保留关键节点', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(const TodayScreen(), theme: AppBrands.defaultBrand.theme),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ApplePageFrame), findsWidgets);
    expect(find.byKey(const ValueKey('home_greeting')), findsOneWidget);
    expect(find.byKey(const ValueKey('home_date')), findsOneWidget);
    expect(find.byKey(const ValueKey('today_home_tabs')), findsOneWidget);
    expect(find.byKey(const ValueKey('today_todos_header')), findsOneWidget);
    // 默认主题：没有 AppBar，页头 / 页签 / 内容在同一条页面内容流里。
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(ApplePageHeader), findsWidgets);
    expect(find.byType(AppleGroupedList), findsWidgets);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('today_home_tabs'))).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byType(ApplePageHeader).first).dy,
      ),
      reason: '页签必须排在页头下方，与内容同列',
    );

    // 页头与内容列共用 16dp 左页边距。
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('home_greeting'))).dx,
      closeTo(ApplePageFrame.gutter, 0.5),
    );

    // 分组之间保持统一留白，没有连续堆叠。
    final groups = find.byType(AppleGroup);
    expect(groups.evaluate().length, greaterThanOrEqualTo(2));
    final gap =
        tester.getTopLeft(groups.at(1)).dy -
        tester.getBottomLeft(groups.at(0)).dy;
    expect(gap, greaterThanOrEqualTo(ApplePageFrame.sectionGap));
  });

  testWidgets('默认主题下宽屏今日页内容列限宽居中不拉满', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(const TodayScreen(), theme: AppBrands.defaultBrand.theme),
    );
    await tester.pumpAndSettle();

    final frame = find.byType(ApplePageFrame).first;
    expect(
      tester.getSize(frame).width,
      closeTo(ApplePageFrame.maxContentWidth, 0.5),
    );
    expect(
      tester.getTopLeft(frame).dx,
      closeTo((1200 - ApplePageFrame.maxContentWidth) / 2, 0.5),
    );
  });

  testWidgets('默认主题下待办页控制带合并并保留全部关键 key', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final todos = TodoProvider();
    await todos.addTodo(TodoItem(title: '苹果布局待办'));
    await tester.pumpWidget(
      _wrap(
        const TodoScreen(),
        theme: AppBrands.defaultBrand.theme,
        todoProvider: todos,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ApplePageFrame), findsWidgets);
    for (final key in [
      'todo_view_switcher',
      'todo_today_summary_card',
      'todo_filter_bar',
    ]) {
      final finder = find.byKey(ValueKey(key));
      expect(finder, findsOneWidget, reason: key);
      expect(
        find.ancestor(of: finder, matching: find.byType(AppleGroup)),
        findsWidgets,
        reason: '$key 应并入同一条控制带组面',
      );
    }
    // 默认主题：没有 AppBar，标题 / 控制带 / 结果区在同一条内容流里。
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(ApplePageHeader), findsWidgets);
    expect(find.byType(AppleControlBand), findsWidgets);
    expect(
      tester.getTopLeft(find.byType(AppleControlBand).first).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byType(ApplePageHeader).first).dy,
      ),
    );
    // 默认主题：摘要是组面内的扁平行，不再自带独立卡片。
    expect(
      tester.widget(find.byKey(const ValueKey('todo_today_summary_card'))),
      isA<Padding>(),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('默认主题下习惯页限宽并保留今日打卡关键节点', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(const HabitScreen(), theme: AppBrands.defaultBrand.theme),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('habit_today_scroll_view')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('habit_insight_before_today_list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('habit_today_empty_state_sliver')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('habit_add_action')), findsOneWidget);
    // 默认主题：没有 AppBar，页头 + 页签 + 内容同列。
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(ApplePageHeader), findsWidgets);
    expect(find.byType(AppPageTabs), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('非默认主题保留旧结构：不出现 Apple 页头 / 分组列表 / 扁平摘要', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final todos = TodoProvider();
    await todos.addTodo(TodoItem(title: '非默认主题待办'));
    await tester.pumpWidget(
      _wrap(
        const TodoScreen(),
        theme: AppBrands.starRail.theme,
        todoProvider: todos,
      ),
    );
    await tester.pumpAndSettle();

    // 非默认主题：今日摘要仍是独立卡片，不是组面内的扁平行。
    expect(
      tester.widget(find.byKey(const ValueKey('todo_today_summary_card'))),
      isA<AppSurfaceCard>(),
    );
    expect(find.byKey(const ValueKey('todo_view_switcher')), findsOneWidget);
    expect(find.byKey(const ValueKey('todo_filter_bar')), findsOneWidget);
    // 非默认主题仍使用旧 AppBar 外壳。
    expect(find.byType(AppBar), findsWidgets);

    // 今日页同样回退：没有 Apple 大标题 / 扁平分组，旧页头与页签仍在。
    await tester.pumpWidget(
      _wrap(const TodayScreen(), theme: AppBrands.starRail.theme),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ApplePageHeader), findsNothing);
    expect(find.byType(AppleGroupedList), findsNothing);
    expect(find.byKey(const ValueKey('home_greeting')), findsOneWidget);
    expect(find.byKey(const ValueKey('today_home_tabs')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('默认主题下我的页无 AppBar 且菜单为扁平分组行', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(const MineScreen(), theme: AppBrands.defaultBrand.theme),
    );
    await tester.pumpAndSettle();

    // 默认主题：没有 AppBar，标题进入页面内容流。
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(ApplePageHeader), findsWidgets);
    expect(
      find.byKey(const ValueKey('mine_weekly_productivity')),
      findsOneWidget,
    );

    final scrollable = find
        .descendant(
          of: find.byKey(const PageStorageKey<String>('mine_screen_list')),
          matching: find.byType(Scrollable),
        )
        .first;
    for (final key in [
      'mine_apps_entry',
      'mine_appearance_entry',
      'mine_settings_entry',
      'mine_support_entry',
    ]) {
      final entry = find.byKey(ValueKey(key));
      await tester.scrollUntilVisible(entry, 160, scrollable: scrollable);
      expect(entry, findsOneWidget, reason: key);
      expect(
        find.ancestor(of: entry, matching: find.byType(AppleGroupedList)),
        findsWidgets,
        reason: '$key 应在扁平菜单分组内，而不是逐卡片结构',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
