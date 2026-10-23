import 'dart:convert';
import 'dart:io';

import 'package:duoyi/models/todo.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/home_page_style.dart';
import 'package:duoyi/screens/goal_edit_screen.dart';
import 'package:duoyi/widgets/surface_components.dart';
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
import 'package:duoyi/providers/list_group_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/screens/mine_screen.dart';
import 'package:duoyi/screens/more_apps_screen.dart';
import 'package:duoyi/screens/profile_screen.dart';
import 'package:duoyi/screens/today_screen.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/screens/preferences_screen.dart';
import 'package:duoyi/screens/statistics_screen.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/core/web_target.dart';
import 'package:duoyi/widgets/weekly_productivity_card.dart';
import 'package:duoyi/screens/calendar_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/screens/anniversary_screen.dart';
import 'package:duoyi/screens/countdown_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(
  Widget child, {
  AuthProvider? authProvider,
  TodoProvider? todoProvider,
  GoalProvider? goalProvider,
  PreferencesProvider? preferencesProvider,
  ListGroupProvider? listGroupProvider,
  ShareProvider? shareProvider,
  ThemeData? theme,
  double textScale = 1,
}) {
  return MultiProvider(
    providers: [
      if (todoProvider == null)
        ChangeNotifierProvider(create: (_) => TodoProvider())
      else
        ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
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
      if (goalProvider == null)
        ChangeNotifierProvider(create: (_) => GoalProvider())
      else
        ChangeNotifierProvider<GoalProvider>.value(value: goalProvider),
      ChangeNotifierProvider(create: (_) => CourseProvider()),
      ChangeNotifierProvider(create: (_) => AppLockProvider()),
      if (preferencesProvider == null)
        ChangeNotifierProvider(create: (_) => PreferencesProvider())
      else
        ChangeNotifierProvider<PreferencesProvider>.value(
          value: preferencesProvider,
        ),
      ChangeNotifierProvider(create: (_) => AchievementProvider()),
      if (shareProvider == null)
        ChangeNotifierProvider(create: (_) => ShareProvider())
      else
        ChangeNotifierProvider<ShareProvider>.value(value: shareProvider),
      ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
      if (listGroupProvider != null)
        ChangeNotifierProvider<ListGroupProvider>.value(
          value: listGroupProvider,
        ),
      ChangeNotifierProvider(create: (_) => NotificationService()),
      if (authProvider == null)
        ChangeNotifierProvider(create: (_) => AuthProvider())
      else
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
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
    child: MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: child,
    ),
  );
}

double? _topOrScrolledAway(WidgetTester tester, Finder finder) {
  if (finder.evaluate().isEmpty) return null;
  return tester.getTopLeft(finder).dy;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('我的不再显示登录按钮，账号信息与管理入口跟随实际角色', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final admin in [false, true]) {
      final username = admin ? 'admin' : 'ordinary-user';
      final auth = AuthProvider(
        initialState: AuthState(
          userId: username,
          username: username,
          token: 'test-session',
          isAdmin: admin,
        ),
      );
      await tester.pumpWidget(_wrap(const MineScreen(), authProvider: auth));
      await tester.pumpAndSettle();
      final header = find.byKey(const ValueKey('mine_user_info_row'));
      expect(
        find.descendant(of: header, matching: find.text(username)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: header, matching: find.text('@$username')),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, I18n.tr('auth.login')),
        findsNothing,
      );
      expect(
        find.text(I18n.tr('mine.badge.admin')),
        admin ? findsOneWidget : findsNothing,
      );
      final settings = find.byKey(const ValueKey('mine_settings_entry'));
      await tester.ensureVisible(settings);
      await tester.tap(settings);
      await tester.pumpAndSettle();
      expect(
        find.text(I18n.tr('mine.tile.admin')),
        admin ? findsOneWidget : findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('我的首页仅保留四个分类入口，窄屏放大字体与主题不溢出', (tester) async {
    addTearDown(tester.view.reset);
    for (final size in const [
      Size(320, 720),
      Size(390, 844),
      Size(1440, 900),
    ]) {
      for (final theme in [
        AppBrands.defaultBrand.theme,
        AppBrands.starRail.theme,
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          _wrap(const MineScreen(), theme: theme, textScale: 1.5),
        );
        await tester.pumpAndSettle();
        for (final key in [
          'mine_apps_entry',
          'mine_appearance_entry',
          'mine_settings_entry',
          'mine_support_entry',
        ]) {
          await tester.scrollUntilVisible(
            find.byKey(ValueKey(key)),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.byKey(ValueKey(key)), findsOneWidget);
        }
        expect(find.text('日程日期'), findsNothing);
        expect(find.text('通知设置'), findsNothing);
        expect(find.text('备份'), findsNothing);
        expect(find.text('万年历'), findsNothing);
        expect(find.textContaining('时光币'), findsNothing);
        expect(tester.takeException(), isNull);
        for (final key in [
          'mine_apps_entry',
          'mine_settings_entry',
          'mine_support_entry',
        ]) {
          final entry = find.byKey(ValueKey(key));
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .jumpTo(0);
          await tester.pump();
          await tester.scrollUntilVisible(
            entry,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(entry);
          await tester.pumpAndSettle();
          expect(find.text('日程日期'), findsNothing);
          expect(find.textContaining('时光币'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pageBack();
          await tester.pumpAndSettle();
        }
      }
    }
  });
  testWidgets('Web小组件从设置打开并保存样式', (tester) async {
    WebTarget.debugWebBuild = true;
    WebTarget.debugDesktopWebBuild = true;
    addTearDown(() {
      WebTarget.debugWebBuild = null;
      WebTarget.debugDesktopWebBuild = null;
    });
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(const MineScreen(), theme: AppBrands.defaultBrand.theme),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mine_widget_settings_entry')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('mine_settings_entry')));
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('mine_widget_settings_entry'));
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    final page = tester.widget<WidgetScreen>(find.byType(WidgetScreen));
    expect(page.asSettings, isTrue);
    expect(find.text(I18n.tr('mine.tile.widget_settings')), findsOneWidget);
    expect(find.byType(SegmentedButton<WidgetDisplayMode>), findsOneWidget);
    final detailed = find.text(
      '${WidgetDisplayMode.detailed.label} ${WidgetDisplayMode.detailed.launcherRequestLabel}',
    );
    await tester.ensureVisible(detailed);
    await tester.pumpAndSettle();
    await tester.tap(detailed);
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getString(
        'duoyi_widget_display_mode',
      ),
      'detailed',
    );
    expect(find.text(I18n.tr('widget.style.saved')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页新建待办复用完整添加表单', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(
        const TodayScreen(showCaptureFab: true),
        theme: AppBrands.defaultBrand.theme,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home_create_button')));
    await tester.pumpAndSettle();
    expect(find.text(I18n.tr('quick.todo.title')), findsNothing);
    expect(find.text('清单类型'), findsOneWidget);
    expect(find.text('优先级标记'), findsNothing);
    expect(find.byType(AppModalSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('todo_create_title')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('todo_subtask_add_input')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    final homeSheet = tester.getSize(find.byType(AppModalSheet));
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _wrap(const TodoScreen(), theme: AppBrands.defaultBrand.theme),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text(I18n.tr('quick.todo.title')), findsNothing);
    expect(find.byKey(const ValueKey('todo_create_title')), findsOneWidget);
    expect(find.text('清单类型'), findsOneWidget);
    expect(find.text('优先级标记'), findsNothing);
    expect(tester.getSize(find.byType(AppModalSheet)), homeSheet);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页快速创建首次打开即载入持久化自定义清单并选中保存', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final previous = ListGroupProvider();
    final travel = await previous.create('旅行', 0);
    previous.dispose();
    final groups = ListGroupProvider();
    final todos = TodoProvider();
    addTearDown(groups.dispose);
    addTearDown(todos.dispose);
    expect(groups.groups, isEmpty);
    await tester.pumpWidget(
      _wrap(
        const TodayScreen(showCaptureFab: true),
        theme: AppBrands.defaultBrand.theme,
        todoProvider: todos,
        listGroupProvider: groups,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home_create_button')));
    await tester.pumpAndSettle();
    expect(groups.groups.single.id, travel.id);
    await tester.enterText(
      find.byKey(const ValueKey('todo_create_title')),
      '行程准备',
    );
    final selector = find.byKey(const ValueKey('todo_list_group_selector'));
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('todo_list_group_search'));
    await tester.ensureVisible(search);
    await tester.enterText(search, '旅行');
    await tester.pumpAndSettle();
    final option = find.byKey(const ValueKey('todo_list_group_旅行'));
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('todo_list_group_selected_name')),
          )
          .data,
      '旅行',
    );
    expect(search, findsNothing);
    final submit = find.byKey(const ValueKey('todo_create_submit'));
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(todos.todos.single.listGroupName, '旅行');
    expect(todos.todos.single.listGroupId, travel.id);
    expect(tester.takeException(), isNull);
  });

  for (final (size, textScale) in [
    (const Size(320, 844), 1.6),
    (const Size(1440, 1000), 1.0),
  ]) {
    testWidgets('今日任务标题圆点与待办四象限配色一致 $size ×$textScale', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const palette = [
        (EisenhowerQuadrant.urgentImportant, Color(0xFFE53935)),
        (EisenhowerQuadrant.notUrgentImportant, Color(0xFF8E5CC6)),
        (EisenhowerQuadrant.urgentNotImportant, Color(0xFFF6A339)),
        (EisenhowerQuadrant.notUrgentNotImportant, Color(0xFF43A047)),
      ];
      final todos = TodoProvider();
      for (final (quadrant, _) in palette) {
        await todos.addTodo(
          TodoItem(
            id: 'quadrant-dot-${quadrant.index}',
            title: '四象限任务${quadrant.index + 1}',
            quadrant: quadrant,
            // 清单颜色不能覆盖象限颜色。
            listGroupName: '工作',
            subtasks: [
              if (quadrant.index.isEven) Subtask(title: '子任务', sortOrder: 0),
            ],
          ),
        );
      }
      await tester.pumpWidget(
        _wrap(
          const TodayScreen(),
          todoProvider: todos,
          theme: AppBrands.defaultBrand.theme,
          textScale: textScale,
        ),
      );
      await tester.pumpAndSettle();
      final vertical = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      );
      for (final (quadrant, color) in palette) {
        final dot = find.byKey(
          ValueKey('today_todo_quadrant_dot_quadrant-dot-${quadrant.index}'),
        );
        await tester.scrollUntilVisible(dot, 160, scrollable: vertical.first);
        await tester.pumpAndSettle();
        final decoration =
            tester.widget<Container>(dot).decoration! as BoxDecoration;
        expect(decoration.shape, BoxShape.circle);
        expect(decoration.color, color);
        expect(tester.getSize(dot), const Size.square(10));
        expect(
          tester.getCenter(dot).dx,
          lessThan(
            tester.getTopLeft(find.text('四象限任务${quadrant.index + 1}')).dx,
          ),
        );
        expect(
          tester.getTopLeft(find.text('四象限任务${quadrant.index + 1}')).dx -
              tester.getTopRight(dot).dx,
          closeTo(8, 0.01),
          reason: '圆点与任务名之间应留出8px间距',
        );
        final card = find.byKey(
          ValueKey('today_todo_quadrant-dot-${quadrant.index}'),
        );
        final leadingEnd =
            tester.getTopLeft(card).dx + DesignTokens.controlMinHeight;
        expect(
          tester.getTopLeft(dot).dx - leadingEnd,
          greaterThanOrEqualTo(DesignTokens.spaceMd),
          reason: '象限圆点不能贴住左侧完成控件或子任务进度',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('首页可直接勾选子任务并在全部完成时聚合父任务', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final todos = TodoProvider();
    final parent = TodoItem(
      title: '首页子任务',
      subtasks: [
        Subtask(id: 's1', title: '第一步', sortOrder: 0),
        Subtask(id: 's2', title: '第二步', sortOrder: 1),
      ],
    );
    await todos.addTodo(parent);
    await tester.pumpWidget(
      _wrap(
        const TodayScreen(),
        todoProvider: todos,
        theme: AppBrands.defaultBrand.theme,
      ),
    );
    await tester.pumpAndSettle();
    // 有子任务时不再提供整任务勾选，改为显示“已完成/总数”进度。
    expect(find.bySemanticsLabel('标记为完成'), findsNothing);
    expect(
      find.byKey(ValueKey('today_subtask_progress_${parent.id}')),
      findsOneWidget,
    );
    final first = find.byKey(const ValueKey('today_subtask_toggle_s1'));
    expect(first, findsOneWidget);
    await tester.tap(first);
    await tester.pumpAndSettle();
    expect(todos.todos.single.subtasks.first.isCompleted, isTrue);
    expect(todos.todos.single.isCompleted, isFalse);

    await tester.tap(find.byKey(const ValueKey('today_subtask_toggle_s2')));
    await tester.pumpAndSettle();
    expect(todos.todos.single.subtasks.last.isCompleted, isTrue);
    // 全部子任务完成后按 autoToggle 规则自动完成父任务。
    expect(todos.todos.single.isCompleted, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('首页显示全部6个子任务并能完成第4至6条 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final todos = TodoProvider();
      final parent = TodoItem(
        id: 'all-home-subtasks',
        title: '完成全部子任务',
        subtasks: [
          for (var i = 1; i <= 6; i++)
            Subtask(
              id: 'all-s$i',
              title: '第$i步',
              isCompleted: i <= 3,
              sortOrder: i - 1,
            ),
        ],
      );
      await todos.addTodo(parent);
      await tester.pumpWidget(
        _wrap(
          const TodayScreen(),
          todoProvider: todos,
          theme: AppBrands.defaultBrand.theme,
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 1; i <= 6; i++) {
        expect(
          find.byKey(ValueKey('today_subtask_toggle_all-s$i')),
          findsOneWidget,
          reason: '第$i条子任务必须能在首页操作',
        );
      }
      final progress = find.byKey(
        const ValueKey('today_subtask_progress_all-home-subtasks'),
      );
      expect(tester.widget<Text>(progress).data, '3/6');
      for (var i = 4; i <= 6; i++) {
        final row = find.byKey(ValueKey('today_subtask_toggle_all-s$i'));
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(
          todos.todos.single.subtasks.where((item) => item.isCompleted),
          hasLength(i),
        );
        expect(todos.todos.single.isCompleted, i == 6);
        if (i < 6) expect(tester.widget<Text>(progress).data, '$i/6');
      }
      final reloaded = TodoProvider();
      await reloaded.loadFromStorage();
      expect(reloaded.todos.single.isCompleted, isTrue);
      expect(
        reloaded.todos.single.subtasks.every((item) => item.isCompleted),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('无子任务的任务保留整任务勾选', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final todos = TodoProvider();
    final plain = TodoItem(title: '无子任务任务');
    await todos.addTodo(plain);
    await tester.pumpWidget(
      _wrap(
        const TodayScreen(),
        todoProvider: todos,
        theme: AppBrands.defaultBrand.theme,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('标记为完成'), findsOneWidget);
    expect(
      find.byKey(ValueKey('today_subtask_progress_${plain.id}')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('只读共享空间的子任务不能勾选', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final todos = TodoProvider();
    await todos.addTodo(
      TodoItem(
        title: '共享子任务',
        subtasks: [Subtask(id: 'ro1', title: '只读步骤', sortOrder: 0)],
      ),
    );
    await tester.pumpWidget(
      _wrap(
        const TodayScreen(),
        todoProvider: todos,
        shareProvider: _ReadOnlyShareProvider(),
        theme: AppBrands.defaultBrand.theme,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('today_subtask_toggle_ro1')));
    await tester.pumpAndSettle();
    expect(todos.todos.single.subtasks.single.isCompleted, isFalse);
    expect(find.text(I18n.tr('today.subtask.read_only')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('外层应用壳下的首页提示条避让创建按钮', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(
        const Scaffold(
          body: TodayScreen(showCaptureFab: true),
          bottomNavigationBar: SizedBox(height: 64),
        ),
        theme: AppBrands.defaultBrand.theme,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home_create_button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('todo_create_title')),
      '验收任务',
    );
    final submit = find.byKey(const ValueKey('todo_create_submit'));
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      tester.getBottomLeft(find.byType(SnackBar)).dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const ValueKey('home_create_button'))).dy,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('实际首页落实预览字阶、灰度、数量和创建按钮', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final todos = TodoProvider();
    final goals = GoalProvider();
    await todos.addTodo(TodoItem(title: '工作', listGroupName: '工作'));
    for (final title in ['读完6本书', '完成个人项目']) {
      await goals.add(GoalItem(title: title, autoProgress: false));
    }
    await tester.pumpWidget(
      _wrap(
        const TodayScreen(showCaptureFab: true),
        todoProvider: todos,
        goalProvider: goals,
        theme: AppBrands.defaultBrand.theme,
      ),
    );
    await tester.pumpAndSettle();
    final greeting = find.byKey(const ValueKey('home_greeting'));
    final date = find.byKey(const ValueKey('home_date'));
    expect(
      tester.widget<Text>(greeting).style?.fontSize,
      DesignTokens.homeHeadingSize,
    );
    expect(tester.getTopLeft(greeting).dy, closeTo(28, 2));
    expect(
      tester.widget<Text>(date).style?.fontSize,
      DesignTokens.homeCaptionSize,
    );
    expect(tester.widget<Text>(date).style?.color, DesignTokens.homeMuted);
    expect(
      tester.widget<Text>(find.text('工作').first).style?.fontSize,
      DesignTokens.homeTaskTitleSize,
    );
    for (final pair in [('today_todos_tab', '1'), ('today_goals_tab', '2')]) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey(pair.$1)),
          matching: find.text(pair.$2),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('0 分'), findsOneWidget);
    final quote = find.descendant(
      of: find.byKey(const ValueKey('today_quiet_quote')),
      matching: find.byType(Text),
    );
    expect(tester.widget<Text>(quote).style?.color, DesignTokens.homeSubtle);
    expect(find.byIcon(Icons.refresh), findsNothing);
    expect(find.text('新建待办'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home_create_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('todo_create_title')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('todo_subtask_add_input')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.widgetWithText(TextButton, I18n.tr('action.cancel')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, I18n.tr('action.cancel')));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const ValueKey('home_create_button')));
    await tester.pumpAndSettle();
    expect(find.text(I18n.tr('quick.menu.note')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home_create_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('today_goals_tab')));
    await tester.pumpAndSettle();
    expect(find.text('新建目标'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home_create_button')));
    await tester.pumpAndSettle();
    expect(find.byType(GoalEditScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页各主题统一文字页签与扁平列表，窄屏放大字体保持对齐', (tester) async {
    addTearDown(tester.view.reset);
    for (final brand in AppBrands.all) {
      for (final width in [320.0, 1440.0]) {
        SharedPreferences.setMockInitialValues({});
        final todos = TodoProvider();
        final goals = GoalProvider();
        await todos.addTodo(TodoItem(title: '统一样式任务', listGroupName: '工作'));
        final goal = GoalItem(
          title: '统一样式目标',
          autoProgress: false,
          progress: 0.42,
        );
        await goals.add(goal);
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          _wrap(
            const TodayScreen(),
            todoProvider: todos,
            goalProvider: goals,
            theme: brand.theme,
            textScale: 1.5,
          ),
        );
        await tester.pumpAndSettle();
        final tabs = tester.widget<TabBar>(
          find.byKey(const ValueKey('today_home_tabs')),
        );
        expect(tabs.indicator, isA<HomeTabIndicator>());
        expect(tabs.isScrollable, isTrue);
        expect(tabs.tabAlignment, TabAlignment.start);
        expect(tabs.labelColor, HomePageStyle.fromTheme(brand.theme).accent);
        expect(find.text(I18n.tr('today.todos')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('today_todo_template_icon_工作')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('today_todo_list_icon_工作')),
          findsOneWidget,
        );
        expect(find.byType(AppMetricCard), findsNothing);
        final list = find.byKey(const ValueKey('today_screen_list'));
        expect(
          find.descendant(of: list, matching: find.byType(AppSurfaceCard)),
          findsNothing,
        );
        final taskLeft = tester.getTopLeft(find.text('统一样式任务')).dx;
        expect(
          tester.widget<Text>(find.text('统一样式任务')).style?.fontSize,
          DesignTokens.homeTaskTitleSize,
        );
        await tester.tap(find.byKey(const ValueKey('today_goals_tab')));
        await tester.pumpAndSettle();
        final goalList = find.byKey(const ValueKey('today_goals_list'));
        expect(
          find.descendant(of: goalList, matching: find.byType(AppSurfaceCard)),
          findsNothing,
        );
        expect(
          tester.getTopLeft(find.text('统一样式目标')).dx,
          closeTo(taskLeft, 0.5),
        );
        expect(find.text('42%'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: '${brand.style} width=$width',
        );
        await tester.pumpWidget(const SizedBox());
        todos.dispose();
        goals.dispose();
      }
    }
  });

  testWidgets('紧凑统计保持任务习惯和专注跳转', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(const TodayScreen()));
    await tester.pumpAndSettle();
    final summary = find.byKey(const ValueKey('today_metrics_summary'));
    for (final label in [
      I18n.tr('nav.todo'),
      I18n.tr('nav.habit'),
      I18n.tr('nav.focus'),
    ]) {
      final entry = find.descendant(of: summary, matching: find.text(label));
      await tester.ensureVisible(entry);
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('today_metrics_summary')), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页默认显示待办且任务卡片位于顶部，目标可以往返切换', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final todos = TodoProvider();
    final goals = GoalProvider();
    await todos.addTodo(TodoItem(title: '进入首页立即看到的任务'));
    for (var i = 1; i <= 3; i++) {
      await goals.add(GoalItem(title: '进行中的目标 $i', autoProgress: false));
    }
    await tester.pumpWidget(
      _wrap(const TodayScreen(), todoProvider: todos, goalProvider: goals),
    );
    await tester.pumpAndSettle();
    final tabs = tester.element(find.byKey(const ValueKey('today_home_tabs')));
    expect(DefaultTabController.of(tabs).index, 0);
    final list = find.byKey(const ValueKey('today_screen_list'));
    final sectionTitle = find.byKey(const ValueKey('today_todos_header'));
    expect(
      tester.getTopLeft(sectionTitle).dy - tester.getTopLeft(list).dy,
      lessThan(DesignTokens.space4xl),
    );
    expect(find.text('进入首页立即看到的任务').hitTestable(), findsOneWidget);
    expect(find.byType(WeeklyProductivityCard), findsNothing);
    expect(find.textContaining('万年历'), findsNothing);
    expect(find.text('日记'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('today_goals_tab')));
    await tester.pumpAndSettle();
    expect(DefaultTabController.of(tabs).index, 1);
    for (var i = 1; i <= 3; i++) {
      expect(find.text('进行中的目标 $i'), findsOneWidget);
    }
    expect(find.text('进入首页立即看到的任务'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('today_todos_tab')));
    await tester.pumpAndSettle();
    expect(find.text('进入首页立即看到的任务').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页日历默认不显示，设置开关可以开启并在待办后显示', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final preferences = PreferencesProvider();
    expect(preferences.showHomeCalendar, isFalse);
    await tester.pumpWidget(
      _wrap(
        const PersonalizationSettingsScreen(),
        preferencesProvider: preferences,
      ),
    );
    await tester.pumpAndSettle();
    final setting = find.byKey(
      const ValueKey('preferences_home_calendar_switch'),
    );
    await tester.ensureVisible(setting);
    await tester.pumpAndSettle();
    final toggle = find.descendant(of: setting, matching: find.byType(Switch));
    expect(tester.widget<Switch>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(preferences.showHomeCalendar, isTrue);
    await tester.pumpWidget(
      _wrap(const TodayScreen(), preferencesProvider: preferences),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining(I18n.tr('today.almanac.title')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(I18n.tr('today.todos.empty'))).dy,
      lessThan(
        tester
            .getTopLeft(find.textContaining(I18n.tr('today.almanac.title')))
            .dy,
      ),
    );
    await preferences.setShowHomeCalendar(false);
    await tester.pumpAndSettle();
    expect(find.textContaining(I18n.tr('today.almanac.title')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('本周效率位于我的用户部件下方并可进入统计报表', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(const MineScreen(), theme: AppBrands.defaultBrand.theme),
    );
    await tester.pumpAndSettle();
    final header = find.byKey(const ValueKey('mine_header_stable_box'));
    final efficiency = find.byKey(const ValueKey('mine_weekly_productivity'));
    final stats = find.byKey(const ValueKey('mine_stats_stable_grid'));
    expect(find.text(I18n.tr('today.productivity.weekly')), findsOneWidget);
    expect(
      tester.getBottomLeft(header).dy,
      lessThanOrEqualTo(tester.getTopLeft(efficiency).dy),
    );
    expect(
      tester.getBottomLeft(efficiency).dy,
      lessThanOrEqualTo(tester.getTopLeft(stats).dy),
    );
    await tester.tap(efficiency);
    await tester.pumpAndSettle();
    expect(find.byType(StatisticsScreen), findsOneWidget);
    expect(find.text('日记'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Today keeps todo section visible when there is no task', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const TodayScreen()));
    await tester.pumpAndSettle();

    expect(find.text('今日待办'), findsOneWidget);
    expect(find.text('今天暂无待办，点击查看或添加任务'), findsOneWidget);
  });

  testWidgets('今日目标空状态与待办对齐并使用统一字号', (tester) async {
    tester.view.physicalSize = const Size(720, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(const TodayScreen(), theme: AppBrands.defaultBrand.theme),
    );
    await tester.pumpAndSettle();
    final todo = find.text(I18n.tr('today.todos.empty'));
    final todoLeft = tester.getTopLeft(todo).dx;
    TextStyle textStyle(Finder finder) => DefaultTextStyle.of(
      tester.element(finder),
    ).style.merge(tester.widget<Text>(finder).style);
    expect(textStyle(todo).fontSize, DesignTokens.fontSizeBody);
    await tester.tap(find.byKey(const ValueKey('today_goals_tab')));
    await tester.pumpAndSettle();
    final title = find.text(I18n.tr('goal.new')).last;
    final subtitle = find.text(I18n.tr('today.goal.create.subtitle'));
    expect(textStyle(title).fontSize, DesignTokens.fontSizeBody);
    expect(textStyle(subtitle).fontSize, DesignTokens.homeCaptionSize);
    expect(find.text(I18n.tr('today.todos.empty')), findsNothing);
    expect(tester.getTopLeft(title).dx, closeTo(todoLeft, 0.5));
    expect(
      tester.widget<Icon>(find.byIcon(Icons.flag_circle_outlined)).size,
      DesignTokens.controlIconSize,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('今日目标标题与右侧操作垂直居中', (tester) async {
    tester.view.physicalSize = const Size(720, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(const TodayScreen(), theme: AppBrands.defaultBrand.theme),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('today_goals_tab')));
    await tester.pumpAndSettle();
    final header = find.byKey(const ValueKey('today_goals_header'));
    final title = find
        .descendant(of: header, matching: find.byType(Text))
        .first;
    expect(header, findsOneWidget);
    final action = find.widgetWithText(TextButton, I18n.tr('goal.new'));
    expect(
      tester.getCenter(title).dy,
      closeTo(tester.getCenter(action).dy, 0.5),
    );
  });

  testWidgets('今日目标区域窄屏和深色主题放大字体不溢出', (tester) async {
    addTearDown(tester.view.reset);
    for (final size in const [
      Size(320, 844),
      Size(390, 844),
      Size(1280, 900),
    ]) {
      for (final theme in [
        AppBrands.defaultBrand.theme,
        AppBrands.starRail.theme,
      ]) {
        for (final populated in [false, true]) {
          final goals = GoalProvider();
          const longTitle = '完成本周项目资料整理并核对所有交付内容与下一阶段计划';
          if (populated) {
            await goals.add(
              GoalItem(title: longTitle, autoProgress: false, progress: 0.42),
            );
          }
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            _wrap(
              const TodayScreen(),
              goalProvider: goals,
              theme: theme,
              textScale: 1.5,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('today_goals_tab')));
          await tester.pumpAndSettle();
          final target = find.text(
            populated ? longTitle : I18n.tr('today.goal.create.subtitle'),
          );
          await tester.ensureVisible(target);
          final title = find
              .text(populated ? longTitle : I18n.tr('goal.new'))
              .last;
          await tester.pumpAndSettle();
          if (populated) {
            final text = tester.widget<Text>(title);
            expect(text.maxLines, 2);
            expect(text.style?.fontSize, DesignTokens.homeTaskTitleSize);
            expect(find.text('42%'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          goals.dispose();
        }
      }
    }
  });

  testWidgets('宽屏首页创建入口与其他页面一致位于页面右下角', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(const TodayScreen(showCaptureFab: true)));
    await tester.pumpAndSettle();
    final rect = tester.getRect(
      find.byKey(const ValueKey('home_create_button')),
    );
    expect(rect.right, closeTo(1584, 1));
    expect(rect.bottom, closeTo(984, 1));
    await tester.tap(find.byKey(const ValueKey('home_create_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('todo_create_sheet')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('今日目标标题按钮和空状态都能打开新建目标', (tester) async {
    tester.view.physicalSize = const Size(720, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(const TodayScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('today_goals_tab')));
    await tester.pumpAndSettle();
    for (final header in [true, false]) {
      final entry = header
          ? find.widgetWithText(TextButton, I18n.tr('goal.new'))
          : find.text(I18n.tr('goal.new')).last;
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(GoalEditScreen), findsOneWidget);
      expect(find.byType(AppModalSheet), findsOneWidget);
      Navigator.of(tester.element(find.byType(GoalEditScreen))).pop();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Today todo shows no-due and not-overdue tasks', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final todoProvider = TodoProvider();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));

    await todoProvider.addTodo(TodoItem(title: '无截止任务', date: tomorrow));
    await todoProvider.addTodo(
      TodoItem(title: '今天截止任务', date: yesterday, dueDate: today),
    );
    await todoProvider.addTodo(
      TodoItem(
        title: '昨天截止任务',
        date: today,
        dueDate: yesterday.add(const Duration(hours: 18)),
      ),
    );
    await todoProvider.addTodo(
      TodoItem(
        title: '明天截止任务',
        date: today,
        dueDate: tomorrow.add(const Duration(hours: 9)),
      ),
    );
    await todoProvider.addTodo(
      TodoItem(
        title: '已完成任务',
        date: today,
        dueDate: today.add(const Duration(hours: 10)),
        isCompleted: true,
        completedAt: now,
      ),
    );

    await tester.pumpWidget(
      _wrap(const TodayScreen(), todoProvider: todoProvider),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日待办'), findsOneWidget);
    expect(find.text('无截止任务'), findsOneWidget);
    expect(find.text('无截止日期'), findsOneWidget);
    expect(find.text('今天截止任务'), findsOneWidget);
    expect(find.text('昨天截止任务'), findsNothing);
    expect(find.text('明天截止任务'), findsOneWidget);
    expect(find.text('已完成任务'), findsNothing);
  });

  testWidgets(
    'Today homepage layout fits audited widths and scrolls as content',
    (tester) async {
      addTearDown(tester.view.reset);
      final widths = <double>[320, 390, 430, 1440];

      for (final width in widths) {
        tester.view.physicalSize = Size(width, width >= 900 ? 900 : 820);
        tester.view.devicePixelRatio = 1.0;

        final todoProvider = TodoProvider();
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        await todoProvider.addTodo(
          TodoItem(
            title: '今日待办长标题需要省略但不能遮挡完成按钮和右侧内容',
            date: today,
            dueDate: now.add(const Duration(hours: 4)),
            priority: TodoPriority.high,
            quadrant: EisenhowerQuadrant.notUrgentImportant,
            listGroupName: '工作',
          ),
        );
        await todoProvider.addTodo(
          TodoItem(title: '无截止布局任务', date: today.add(const Duration(days: 3))),
        );

        await tester.pumpWidget(
          _wrap(const TodayScreen(), todoProvider: todoProvider),
        );
        await _pumpTodayLayoutFrame(tester);

        final list = find.byKey(const ValueKey('today_screen_list'));
        final appBar = find.byType(AppBar);
        final scrollable = tester.state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        );
        expect(list, findsOneWidget);
        expect(appBar, findsOneWidget);
        expect(find.byKey(const ValueKey('today_home_tabs')), findsOneWidget);
        expect(find.text('今日待办'), findsOneWidget);
        expect(find.text('今日待办长标题需要省略但不能遮挡完成按钮和右侧内容'), findsWidgets);
        expect(find.text('无截止日期'), findsWidgets);
        expect(tester.takeException(), isNull);

        if (scrollable.position.maxScrollExtent > 0) {
          scrollable.position.jumpTo(0);
          await _pumpTodayLayoutFrame(tester);
          final appBarTop = tester.getTopLeft(appBar).dy;
          final beforePixels = scrollable.position.pixels;
          await tester.drag(list, const Offset(0, -280));
          await _pumpTodayLayoutFrame(tester);

          expect(tester.getTopLeft(appBar).dy, closeTo(appBarTop, 0.1));
          expect(scrollable.position.pixels, greaterThan(beforePixels));
        }
        expect(tester.takeException(), isNull);
      }

      tester.view.reset();
    },
  );

  test('今日和我的概览/入口样式保持独立且不过度放大', () {
    final today = File('lib/screens/today_screen.dart').readAsStringSync();
    final mine = File('lib/screens/mine_screen.dart').readAsStringSync();
    final surface = File(
      'lib/widgets/surface_components.dart',
    ).readAsStringSync();

    expect(today, contains("ValueKey('today_metrics_summary')"));
    expect(today, contains('WrapAlignment.spaceBetween'));
    expect(today, isNot(contains('AppMetricCard(')));
    expect(mine, contains('class _MineStatsGrid extends StatelessWidget'));
    expect(mine, contains("ValueKey('mine_stats_stable_grid')"));
    expect(mine, contains('height: baseHeight + fontGrowth * 2'));
    expect(mine, contains('RepaintBoundary('));
    expect(mine, isNot(contains('GridView.count(')));
    expect(surface, contains('fontSize: DesignTokens.fontSizeBody'));
    expect(surface, contains('fontSize: 11'));
    expect(surface, contains('fontSize: DesignTokens.fontSizeMd'));
    expect(surface, contains('iconBoxSize = 28'));

    expect(mine, contains('class _TileGroup'));
    expect(mine, contains('AppSurfaceCard('));
    expect(mine, contains('Divider('));
    expect(
      mine,
      contains(
        'borderRadius: BorderRadius.circular(DesignTokens.radiusControl)',
      ),
    );
    expect(mine, contains('final compact = constraints.maxWidth < 360'));
    expect(mine, contains("label: I18n.tr('goal.title')"));
    expect(mine, contains("label: I18n.tr('anniversary.birthday')"));
    expect(mine, contains("label: I18n.tr('anniversary.title')"));
    expect(mine, contains('child: anniversary.MemorialAnniversaryScreen()'));
    expect(mine, contains('child: anniversary.BirthdayScreen()'));
    expect(mine, contains("label: I18n.tr('countdown.title')"));
    expect(mine, contains('child: CountdownScreen()'));
    expect(mine, contains("label: I18n.tr('mine.tile.backup')"));
    expect(mine, contains("label: I18n.tr('mine.tile.restore')"));
    expect(mine, contains("label: I18n.tr('mine.tile.feedback')"));
    expect(mine, contains('FeedbackScreen(initialCategory: category)'));
    expect(mine, contains("label: I18n.tr('mine.tile.integrations')"));
    expect(mine, isNot(contains('AlmanacEntryMode.almanac')));
    expect(mine, contains('AlmanacEntryMode.calendar'));
    expect(mine, contains('BackupEntryMode.backup'));
    expect(mine, contains('BackupEntryMode.restore'));
    expect(mine, isNot(contains("label: '纪念日 · 生日 · 倒数'")));
    expect(mine, isNot(contains("label: '黄历 · 万年历'")));
    expect(mine, isNot(contains("label: '备份 · 恢复'")));
    expect(mine, isNot(contains("label: '功能建议'")));
    expect(mine, isNot(contains("label: '问题反馈'")));
    expect(mine, isNot(contains("label: '许愿池'")));

    expect(
      mine.indexOf("title: I18n.tr('mine.group.action_plan')"),
      lessThan(mine.indexOf("title: I18n.tr('mine.group.review')")),
    );
    expect(
      mine.indexOf("title: I18n.tr('mine.group.review')"),
      lessThan(mine.indexOf("title: I18n.tr('mine.group.tools')")),
    );
    expect(
      mine.indexOf("title: I18n.tr('mine.group.personal')"),
      lessThan(mine.indexOf("title: I18n.tr('mine.group.data')")),
    );
  });

  testWidgets('TodayScreen and MineScreen render on desktop width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const TodayScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(find.text('待办'), findsWidgets);
    expect(find.text('习惯'), findsWidgets);
    expect(find.text('专注'), findsWidgets);
    expect(find.text('日记'), findsNothing);
    expect(find.text('今日代表'), findsNothing);

    await tester.pumpWidget(_wrap(const MineScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(MineScreen), findsOneWidget);
    expect(find.text('应用与记录'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('帮助与关于'), findsOneWidget);
    expect(find.text('日程日期'), findsNothing);
    expect(find.text('通知设置'), findsNothing);
    expect(find.text('备份'), findsNothing);
    expect(find.text('效率评分'), findsOneWidget);
    expect(find.textContaining('时光币'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mine_apps_entry')));
    await tester.pumpAndSettle();
    expect(find.text('行动计划'), findsOneWidget);
    expect(find.text('记录回顾'), findsOneWidget);
    expect(find.text('实用工具'), findsOneWidget);
    expect(find.text('纪念日'), findsOneWidget);
    expect(find.text('生日'), findsOneWidget);
    expect(find.text('倒数日'), findsOneWidget);
    expect(find.text('万年历'), findsOneWidget);
    expect(find.text('日程日期'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mine_settings_entry')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('通知支持'),
      600,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('数据协作'), findsOneWidget);
    expect(find.text('通知支持'), findsOneWidget);
    expect(find.text('导出为日历 (.ics)'), findsOneWidget);
    expect(find.text('备份'), findsOneWidget);
    expect(find.text('恢复数据'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mine_support_entry')));
    await tester.pumpAndSettle();
    expect(find.text('许愿与反馈'), findsOneWidget);
    expect(find.text('纪念日 · 生日 · 倒数'), findsNothing);
    expect(find.text('黄历 · 万年历'), findsNothing);
    expect(find.text('备份 · 恢复'), findsNothing);
    expect(find.text('功能建议'), findsNothing);
    expect(find.text('问题反馈'), findsNothing);
    expect(find.text('许愿池'), findsNothing);
  });

  testWidgets('Mine keeps top bar fixed while content scrolls on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 390);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const MineScreen()));
    await tester.pumpAndSettle();

    final title = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('我的'),
    );
    final header = find.byKey(const ValueKey('mine_header_stable_box'));
    final scrollableFinder = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.restorationId == 'mine_screen_list',
    );

    expect(
      find.byKey(const ValueKey('mine_desktop_fixed_overview_layout')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('mine_fixed_overview_panel')),
      findsNothing,
    );
    expect(find.byType(AppBar), findsOneWidget);
    expect(title, findsOneWidget);
    expect(scrollableFinder, findsOneWidget);

    final scrollable = tester.state<ScrollableState>(scrollableFinder);
    final targetOffset = scrollable.position.maxScrollExtent < 260
        ? scrollable.position.maxScrollExtent
        : 260.0;
    expect(targetOffset, greaterThan(0));

    final stats = find.text('待办完成');
    final menuEntry = find.byKey(const ValueKey('mine_apps_entry'));
    final beforeTitleTop = tester.getTopLeft(title).dy;
    final beforeHeaderTop = tester.getTopLeft(header).dy;
    final beforeStatsTop = tester.getTopLeft(stats).dy;
    final beforeMenuTop = tester.getTopLeft(menuEntry).dy;

    scrollable.position.jumpTo(targetOffset);
    await tester.pump();

    expect(scrollable.position.pixels, closeTo(targetOffset, 0.1));
    expect(tester.getTopLeft(title).dy, closeTo(beforeTitleTop, 0.1));
    expect(
      _topOrScrolledAway(tester, header),
      anyOf(isNull, lessThan(beforeHeaderTop)),
    );
    expect(
      _topOrScrolledAway(tester, stats),
      anyOf(isNull, lessThan(beforeStatsTop)),
    );
    expect(
      _topOrScrolledAway(tester, menuEntry),
      anyOf(isNull, lessThan(beforeMenuTop)),
    );
  });

  testWidgets('Mine avatar preview and profile info navigation are distinct', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const MineScreen()));
    await tester.pumpAndSettle();

    final avatarButton = find.byKey(
      const ValueKey('mine_avatar_preview_button'),
    );
    await tester.tapAt(tester.getTopLeft(avatarButton) + const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('头像'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(ProfileScreen), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();

    final editRect = tester.getRect(
      find.byKey(const ValueKey('mine_avatar_edit_button')),
    );
    expect(editRect.width, greaterThan(43.5));
    expect(editRect.height, greaterThan(43.5));

    await tester.tap(find.text('用户').first);
    await tester.pumpAndSettle();

    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('个人资料'), findsOneWidget);
  });

  testWidgets('MineScreen exposes logout in the top user info row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final requests = <String>[];
    final auth = AuthProvider(
      initialState: const AuthState(
        userId: 'u-1',
        username: 'old-user',
        displayName: '旧昵称',
        token: 'token-1',
      ),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'POST' &&
              request.url.path == '/api/auth/logout') {
            return http.Response(
              json.encode({'status': 'ok'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
      ),
    );

    await tester.pumpWidget(_wrap(const MineScreen(), authProvider: auth));
    await tester.pumpAndSettle();

    final userInfoRow = find.byKey(const ValueKey('mine_user_info_row'));
    final logoutButton = find.descendant(
      of: userInfoRow,
      matching: find.byKey(const ValueKey('mine_top_logout_button')),
    );
    expect(userInfoRow, findsOneWidget);
    expect(logoutButton, findsOneWidget);

    await tester.tap(logoutButton);
    await tester.pumpAndSettle();

    expect(find.text('退出登录？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '退出登录'));
    await tester.pumpAndSettle();

    expect(requests, ['POST /api/auth/logout']);
    expect(auth.state.isLoggedIn, isFalse);
    expect(find.textContaining('已退出登录'), findsOneWidget);
    expect(find.textContaining('本机账号数据已清理'), findsOneWidget);
  });

  testWidgets('Today todo left swipe exposes detail and delete actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final todoProvider = TodoProvider();
    final today = DateTime.now();
    await todoProvider.addTodo(
      TodoItem(
        title: '今日左滑删除',
        date: DateTime(today.year, today.month, today.day),
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
          ChangeNotifierProvider(create: (_) => HabitProvider()),
          ChangeNotifierProvider(create: (_) => PomodoroProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => PreferencesProvider()),
          ChangeNotifierProvider(create: (_) => DiaryProvider()),
          ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
          ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
          ChangeNotifierProvider(create: (_) => CourseProvider()),
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => UserProvider()),
        ],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日左滑删除'), findsOneWidget);
    await tester.ensureVisible(find.text('今日左滑删除'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('today_todo_swipe_detail_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('today_todo_swipe_delete_button')),
      findsNothing,
    );

    await tester.drag(find.text('今日左滑删除'), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('today_todo_swipe_detail_button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('today_todo_swipe_delete_button')),
      findsNothing,
    );

    await tester.drag(find.text('今日左滑删除'), const Offset(-180, 0));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('today_todo_swipe_detail_button')),
      findsNothing,
    );
    expect(
      find
          .byKey(const ValueKey('today_todo_swipe_delete_button'))
          .hitTestable(),
      findsOneWidget,
    );
    expect(todoProvider.todos, hasLength(1));

    await tester.tap(
      find
          .byKey(const ValueKey('today_todo_swipe_delete_button'))
          .hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(find.text('删除任务？'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(todoProvider.todos, isEmpty);
    expect(find.text('今日左滑删除'), findsNothing);
  });

  testWidgets('Today reminders visually separate overdue and normal items', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final todoProvider = TodoProvider();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await todoProvider.addTodo(
      TodoItem(
        title: '逾期提醒任务',
        date: today.subtract(const Duration(days: 1)),
        dueDate: now.subtract(const Duration(hours: 1)),
      ),
    );
    await todoProvider.addTodo(
      TodoItem(
        title: '正常提醒任务',
        date: today.add(const Duration(days: 1)),
        dueDate: now.add(const Duration(minutes: 45)),
      ),
    );
    await todoProvider.addTodo(
      TodoItem(
        title: '已完成提醒任务',
        date: today,
        dueDate: now.add(const Duration(minutes: 30)),
        isCompleted: true,
        completedAt: now,
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TodoProvider>.value(value: todoProvider),
          ChangeNotifierProvider(create: (_) => HabitProvider()),
          ChangeNotifierProvider(create: (_) => PomodoroProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => PreferencesProvider()),
          ChangeNotifierProvider(create: (_) => DiaryProvider()),
          ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
          ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
          ChangeNotifierProvider(create: (_) => CourseProvider()),
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => UserProvider()),
          ChangeNotifierProvider(create: (_) => ShareProvider()),
        ],
        child: const MaterialApp(home: TodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日提醒'), findsOneWidget);
    expect(find.text('已逾期事项'), findsNothing);
    expect(find.text('逾期提醒任务'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('today_reminder_header_toggle')),
    );
    await tester.pumpAndSettle();

    expect(find.text('已逾期事项'), findsOneWidget);
    expect(
      find.text('今日待提醒事项').evaluate().isNotEmpty ||
          find.text('即将开始事项').evaluate().isNotEmpty,
      isTrue,
    );
    expect(find.text('逾期提醒任务'), findsOneWidget);
    expect(find.text('正常提醒任务'), findsWidgets);
    expect(find.text('已完成提醒任务'), findsWidgets);
    expect(find.text('逾期'), findsWidgets);

    final overdueTitle = tester.widget<Text>(find.text('逾期提醒任务'));
    final normalTitle = tester.widgetList<Text>(find.text('正常提醒任务')).last;
    final completedTitle = tester
        .widgetList<Text>(find.text('已完成提醒任务'))
        .firstWhere(
          (widget) => widget.style?.decoration == TextDecoration.lineThrough,
        );
    expect(overdueTitle.style?.color, isNot(equals(normalTitle.style?.color)));
    expect(completedTitle.style?.decoration, TextDecoration.lineThrough);
    expect(
      completedTitle.style?.color,
      isNot(equals(normalTitle.style?.color)),
    );

    bool reminderTileDecoration(Widget widget) {
      if (widget is! Container) return false;
      return widget.margin ==
              const EdgeInsets.symmetric(horizontal: 8, vertical: 3) &&
          widget.decoration is BoxDecoration;
    }

    final overdueDecoratedTile = find.ancestor(
      of: find.text('逾期提醒任务'),
      matching: find.byWidgetPredicate(reminderTileDecoration),
    );
    final normalDecoratedTile = find.ancestor(
      of: find.text('正常提醒任务'),
      matching: find.byWidgetPredicate(reminderTileDecoration),
    );
    expect(overdueDecoratedTile, findsOneWidget);
    expect(normalDecoratedTile, findsWidgets);
  });

  testWidgets('Future not-overdue todo appears directly in today', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final todoProvider = TodoProvider();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await todoProvider.addTodo(
      TodoItem(
        title: '明天未逾期待办',
        date: today.add(const Duration(days: 1)),
        dueDate: today.add(const Duration(days: 1, hours: 18)),
        priority: TodoPriority.high,
        quadrant: EisenhowerQuadrant.notUrgentImportant,
        listGroupName: '工作',
      ),
    );

    await tester.pumpWidget(
      _wrap(const TodayScreen(), todoProvider: todoProvider),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日待办'), findsOneWidget);
    expect(find.text('明天未逾期待办'), findsOneWidget);

    final stored = todoProvider.todos.single;
    expect(
      DateTime(stored.date.year, stored.date.month, stored.date.day),
      today.add(const Duration(days: 1)),
    );
    expect(stored.dueDate, isNotNull);
    expect(
      DateTime(
        stored.dueDate!.year,
        stored.dueDate!.month,
        stored.dueDate!.day,
      ),
      today.add(const Duration(days: 1)),
    );
    expect(find.text('今日待办'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('today_todo_list_icon_工作')),
      findsOneWidget,
    );
    expect(find.text(I18n.tr('today.add_to_today')), findsNothing);
  });

  testWidgets(
    'More applications opens as a real route and hidden apps render',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const MineScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('mine_apps_entry')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('更多应用'));
      await tester.pumpAndSettle();

      expect(find.byType(MoreApplicationsScreen), findsOneWidget);
      expect(find.text('隐藏入口'), findsOneWidget);
      expect(find.text('日历'), findsOneWidget);
      expect(find.text('番茄专注'), findsNothing);

      await tester.tap(find.text('日历'));
      await tester.pumpAndSettle();

      expect(find.byType(CalendarScreen), findsOneWidget);
      expect(find.text('日历'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Today suggestions keep add button inside narrow tiles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final todoProvider = TodoProvider();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final later = today.add(const Duration(days: 2));
    await todoProvider.addTodo(
      TodoItem(
        title: '非常非常长的今日建议任务标题需要省略但按钮不能遮挡',
        date: later,
        priority: TodoPriority.urgent,
        quadrant: EisenhowerQuadrant.urgentImportant,
      ),
    );

    await tester.pumpWidget(
      _wrap(const TodayScreen(), todoProvider: todoProvider),
    );
    await tester.pumpAndSettle();

    final reminderToggle = find.byKey(
      const ValueKey('today_reminder_header_toggle'),
    );
    await tester.scrollUntilVisible(
      reminderToggle,
      360,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('today_screen_list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(reminderToggle, findsOneWidget);

    await tester.tap(reminderToggle);
    await tester.pumpAndSettle();
    final suggestionsHeader = find.text(I18n.tr('today.suggestions'));
    await tester.scrollUntilVisible(
      suggestionsHeader,
      240,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('today_screen_list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(suggestionsHeader);
    await tester.pumpAndSettle();

    final addButton = find.byKey(
      ValueKey('today_suggestion_add_${todoProvider.todos.single.id}'),
    );
    expect(addButton, findsOneWidget);
    expect(tester.getRect(addButton).right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AnniversaryScreen can open a specific tab directly', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const AnniversaryScreen(initialTab: 1)));
    await tester.pumpAndSettle();

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller?.index, 1);
    expect(find.text('生日'), findsWidgets);
    expect(find.text('纪念日 · 生日 · 倒数'), findsNothing);
  });

  testWidgets('Birthday and countdown entries use independent pages', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const BirthdayScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(BirthdayScreen), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('生日'), findsWidgets);

    await tester.pumpWidget(_wrap(const CountdownScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(CountdownScreen), findsOneWidget);
    expect(find.text('倒数日'), findsWidgets);
    expect(find.byType(AnniversaryScreen), findsNothing);
  });

  testWidgets('CountdownScreen can add countdowns from the empty state', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const CountdownScreen()));
    await tester.pumpAndSettle();

    expect(find.text('暂无倒数日记录'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byIcon(Icons.add), findsWidgets);
    final provider = Provider.of<CountdownProvider>(
      tester.element(find.byType(CountdownScreen)),
      listen: false,
    );
    expect(provider.items, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Mine notification records open as a scalable page separate from preferences',
    (tester) async {
      final now = DateTime(2026, 5, 22, 8, 30);
      final storedHistory = List.generate(55, (i) {
        return jsonEncode({
          'id': 'history-$i',
          'title': '通知标题 $i',
          'body': i == 54 ? '最后一页记录' : '通知内容 $i',
          'scheduledTime': now.subtract(Duration(minutes: i)).toIso8601String(),
          'type': i.isEven
              ? NotificationType.todo.index
              : NotificationType.general.index,
          'relatedId': 'related-$i',
        });
      });
      SharedPreferences.setMockInitialValues({
        'duoyi_notif_history': storedHistory,
      });

      final notificationService = NotificationService();
      await notificationService.loadHistoryForTest();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => TodoProvider()),
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
            ChangeNotifierProvider<NotificationService>.value(
              value: notificationService,
            ),
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
          child: const MaterialApp(home: MineScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('mine_settings_entry')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('通知支持'),
        700,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('通知记录'), findsOneWidget);
      expect(find.text('通知设置'), findsOneWidget);
      expect(find.text('55 条'), findsWidgets);

      final historyEntry = find.byKey(
        const ValueKey('mine_notification_history_entry'),
      );
      await tester.ensureVisible(historyEntry);
      await tester.tap(historyEntry);
      await tester.pumpAndSettle();

      expect(find.text('通知记录'), findsWidgets);
      expect(find.byTooltip('上一页'), findsOneWidget);
      expect(find.byTooltip('下一页'), findsOneWidget);
      expect(find.textContaining('第 1 / 2 页'), findsOneWidget);
      expect(find.textContaining('每页 50 条'), findsOneWidget);
      expect(find.text('通知标题 0'), findsOneWidget);
      expect(find.text('最后一页记录'), findsNothing);

      await tester.scrollUntilVisible(
        find.byTooltip('下一页'),
        500,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('通知标题 54'),
        500,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('通知标题 54'), findsOneWidget);
      expect(find.text('最后一页记录'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'related-54');
      await tester.pumpAndSettle();
      expect(find.text('通知标题 54'), findsOneWidget);
      expect(find.textContaining('已筛出 1 / 55 条'), findsOneWidget);
    },
  );

  testWidgets('ProfileScreen edits and persists local profile fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final userProvider = UserProvider();
    await userProvider.updateProfile(
      username: '旧昵称',
      displayName: '旧显示名',
      email: 'old@example.com',
      avatarUrl: 'https://example.com/old.png',
      bio: '旧简介',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('个人资料'), findsOneWidget);
    expect(find.text('登录账号'), findsOneWidget);
    expect(find.text('旧显示名'), findsWidgets);

    await tester.enterText(find.widgetWithText(TextField, '显示名'), '新显示名');
    await tester.enterText(find.widgetWithText(TextField, '本地昵称'), '新昵称');
    await tester.enterText(
      find.widgetWithText(TextField, '邮箱（仅本地展示，不用于登录或找回）'),
      'new@example.com',
    );
    await tester.enterText(find.widgetWithText(TextField, '简介'), '新的个人简介');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(userProvider.profile.username, '旧昵称');
    expect(userProvider.profile.displayName, '新显示名');
    expect(userProvider.profile.avatarInitials, '新');
    expect(userProvider.profile.avatarUrl, 'https://example.com/old.png');
    expect(userProvider.profile.email, 'new@example.com');
    expect(userProvider.profile.bio, '新的个人简介');
    expect(find.text('本地资料已更新'), findsWidgets);
  });

  testWidgets('ProfileScreen edits account profile through auth API', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final requests = <String>[];
    final requestBodies = <Map<String, dynamic>>[];
    var serverEmail = 'old@example.com';
    var serverDisplayName = '旧昵称';
    var serverBio = '旧简介';
    final auth = AuthProvider(
      initialState: const AuthState(
        userId: 'u-1',
        username: 'old-user',
        email: 'old@example.com',
        emailVerified: true,
        displayName: '旧昵称',
        avatar: 'https://example.com/old.png',
        bio: '旧简介',
        token: 'token-1',
        coinBalance: 88,
        lifetimeCoins: 144,
      ),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'POST' &&
              request.url.path == '/api/me/profile') {
            expect(request.headers['authorization'], 'Bearer token-1');
            final body = json.decode(request.body) as Map<String, dynamic>;
            requestBodies.add(body);
            if (body.containsKey('display_name')) {
              serverDisplayName = body['display_name'] as String;
            }
            if (body.containsKey('bio')) {
              serverBio = body['bio'] as String;
            }
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'old-user',
                'email': serverEmail,
                'email_verified': false,
                'display_name': serverDisplayName,
                'avatar': 'https://example.com/old.png',
                'bio': serverBio,
                'is_admin': false,
                'coin_balance': 88,
                'lifetime_coins': 144,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'POST' && request.url.path == '/api/me/email') {
            expect(request.headers['authorization'], 'Bearer token-1');
            final body = json.decode(request.body) as Map<String, dynamic>;
            requestBodies.add(body);
            serverEmail = body['email'] as String;
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'old-user',
                'email': serverEmail,
                'email_verified': true,
                'display_name': serverDisplayName,
                'avatar': 'https://example.com/old.png',
                'bio': serverBio,
                'is_admin': false,
                'coin_balance': 88,
                'lifetime_coins': 144,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
      ),
    );
    final userProvider = UserProvider();
    await userProvider.updateProfile(username: '旧本地昵称');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('个人资料'), findsOneWidget);
    expect(find.text('修改登录密码'), findsOneWidget);
    expect(find.text('old@example.com'), findsOneWidget);
    expect(find.text('已验证'), findsWidgets);
    expect(find.textContaining('时光币'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, '昵称'), '新昵称');
    final usernameField = tester.widget<TextField>(
      find.widgetWithText(TextField, '用户名'),
    );
    expect(usernameField.readOnly, isTrue);
    await tester.enterText(find.widgetWithText(TextField, '简介'), '新的账号简介');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '邮箱'), findsNothing);
    expect(find.widgetWithText(TextField, '邮箱验证码'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, '邮箱绑定'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '邮箱'),
      'new@example.com',
    );
    await tester.enterText(find.widgetWithText(TextField, '邮箱验证码'), '123456');
    await tester.tap(find.widgetWithText(FilledButton, '邮箱绑定'));
    await tester.pumpAndSettle();

    expect(requests, contains('POST /api/me/profile'));
    expect(requests, contains('POST /api/me/email'));
    expect(requestBodies, [
      {'display_name': '新昵称', 'displayName': '新昵称', 'bio': '新的账号简介'},
      {
        'email': 'new@example.com',
        'code': '123456',
        'email_code': '123456',
        'emailCode': '123456',
      },
    ]);
    expect(auth.state.username, 'old-user');
    expect(auth.state.email, 'new@example.com');
    expect(auth.state.emailVerified, isTrue);
    expect(auth.state.displayName, '新昵称');
    expect(auth.state.avatar, 'https://example.com/old.png');
    expect(auth.state.bio, '新的账号简介');
    expect(auth.state.coinBalance, 88);
    expect(auth.state.lifetimeCoins, 144);
    expect(userProvider.profile.username, 'old-user');
    expect(userProvider.profile.displayName, '新昵称');
    expect(userProvider.profile.email, 'new@example.com');
    expect(userProvider.profile.emailVerified, isTrue);
    expect(userProvider.profile.avatarUrl, 'https://example.com/old.png');
    expect(userProvider.profile.bio, '新的账号简介');
    expect(find.text('资料已更新'), findsWidgets);
  });
}

Future<void> _pumpTodayLayoutFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

class _ReadOnlyShareProvider extends ShareProvider {
  @override
  bool canEdit(String? workspaceId) => false;
}
