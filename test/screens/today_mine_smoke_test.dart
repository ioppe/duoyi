import 'dart:convert';
import 'dart:io';

import 'package:duoyi/models/todo.dart';
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
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/screens/mine_screen.dart';
import 'package:duoyi/screens/more_apps_screen.dart';
import 'package:duoyi/screens/profile_screen.dart';
import 'package:duoyi/screens/today_screen.dart';
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
      ChangeNotifierProvider(create: (_) => GoalProvider()),
      ChangeNotifierProvider(create: (_) => CourseProvider()),
      ChangeNotifierProvider(create: (_) => AppLockProvider()),
      ChangeNotifierProvider(create: (_) => PreferencesProvider()),
      ChangeNotifierProvider(create: (_) => AchievementProvider()),
      ChangeNotifierProvider(create: (_) => ShareProvider()),
      ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
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
          await tester.ensureVisible(entry);
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
        final isDesktopLayout = width >= 1100;
        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        expect(list, findsOneWidget);
        if (isDesktopLayout) {
          expect(appBar, findsNothing);
          expect(find.text('今日'), findsWidgets);
        } else {
          expect(appBar, findsOneWidget);
        }
        expect(find.text('今日待办'), findsOneWidget);
        expect(find.text('今日待办长标题需要省略但不能遮挡完成按钮和右侧内容'), findsWidgets);
        expect(find.text('无截止日期'), findsWidgets);
        expect(tester.takeException(), isNull);

        if (scrollable.position.maxScrollExtent > 0) {
          scrollable.position.jumpTo(0);
          await _pumpTodayLayoutFrame(tester);
          final appBarTop = isDesktopLayout
              ? null
              : tester.getTopLeft(appBar).dy;
          final beforePixels = scrollable.position.pixels;
          await tester.drag(list, const Offset(0, -280));
          await _pumpTodayLayoutFrame(tester);

          if (!isDesktopLayout) {
            expect(tester.getTopLeft(appBar).dy, closeTo(appBarTop!, 0.1));
          }
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

    expect(today, contains('constraints.maxWidth < (desktop ? 640 : 520)'));
    expect(today, contains('? (useTwoColumns ? 2.75 : 2.85)'));
    expect(today, contains(': (useTwoColumns ? 2.55 : 3.65)'));
    expect(mine, contains('class _MineStatsGrid extends StatelessWidget'));
    expect(mine, contains("ValueKey('mine_stats_stable_grid')"));
    expect(mine, contains('height: baseHeight + fontGrowth * 2'));
    expect(mine, contains('RepaintBoundary('));
    expect(mine, isNot(contains('GridView.count(')));
    expect(surface, contains('fontSize: 12'));
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
    expect(find.text('日记'), findsWidgets);
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
      find.byKey(const ValueKey('today_todo_template_icon_工作')),
      findsWidgets,
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
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(reminderToggle, findsOneWidget);

    await tester.tap(reminderToggle);
    await tester.pumpAndSettle();
    final suggestionsHeader = find.text(I18n.tr('today.suggestions'));
    await tester.scrollUntilVisible(
      suggestionsHeader,
      240,
      scrollable: find.byType(Scrollable).first,
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
