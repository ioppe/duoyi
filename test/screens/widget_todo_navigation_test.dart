import 'dart:async';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/i18n.dart' show LocaleProvider;
import 'package:duoyi/l10n/generated/app_localizations.dart';
import 'package:duoyi/main.dart';
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
import 'package:duoyi/screens/todo_detail_screen.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/screens/today_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 小组件待办深链（`duoyi://todo[/<id>]`、`duoyi://tab/todo`）的返回链回归：
///
/// 期望栈固定为 主页面 → 普通应用内待办清单 → 详情/兜底页。
/// - 返回一次看到的是 `TodoScreen`，而不是“隐藏应用 / 返回我的”隐藏页；
/// - 再返回一次回到主页面；
/// - 重复点击不会叠加清单。
///
/// Provider harness 与 `desktop_web_shell_widescreen_test.dart` 的
/// `_wrapShell` 保持一致，用真实 `MainShell` 驱动，不 mock 外壳。
Widget _wrapShell(TodoProvider todos, PreferencesProvider prefs) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<TodoProvider>.value(value: todos),
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
      ChangeNotifierProvider<PreferencesProvider>.value(value: prefs),
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
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      theme: AppBrands.defaultBrand.theme,
      home: const MainShell(),
    ),
  );
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required TodoProvider todos,
  PreferencesProvider? prefs,
}) async {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrapShell(todos, prefs ?? PreferencesProvider()));
  await tester.pumpAndSettle();
}

MainShellState _shell(WidgetTester tester) =>
    tester.state<MainShellState>(find.byType(MainShell, skipOffstage: false));

Future<TodoProvider> _todosWithTask() async {
  final todos = TodoProvider();
  await todos.addTodo(
    TodoItem(
      id: 'widget-todo-1',
      title: '小组件任务',
      date: DateTime(2026, 5, 20, 9),
    ),
  );
  return todos;
}

Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

/// 主页面 = 今日页 + 可见底栏，且没有任何隐藏页返回条。
void _expectMainPage() {
  expect(find.byType(TodayScreen), findsOneWidget);
  expect(find.byType(NavigationBar), findsOneWidget);
  expect(find.byType(TodoScreen), findsNothing);
  expect(find.byType(TodoDetailScreen), findsNothing);
  expect(find.text('隐藏应用'), findsNothing);
  expect(find.text('返回我的'), findsNothing);
}

/// 普通应用内待办清单：无隐藏返回条。
void _expectPlainTodoList() {
  expect(find.byType(TodoScreen), findsOneWidget);
  expect(find.byType(TodoDetailScreen), findsNothing);
  expect(find.text('隐藏应用'), findsNothing);
  expect(find.text('返回我的'), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('有效待办：返回一次是普通待办清单，再返回回主页面', (tester) async {
    final todos = await _todosWithTask();
    await _pumpShell(tester, todos: todos);

    _shell(tester).openTodoFromWidget(id: 'widget-todo-1');
    await tester.pumpAndSettle();

    expect(find.byType(TodoDetailScreen), findsOneWidget);
    expect(find.text('隐藏应用'), findsNothing);
    expect(find.text('返回我的'), findsNothing);

    await _systemBack(tester);
    _expectPlainTodoList();

    await _systemBack(tester);
    _expectMainPage();
  });

  testWidgets('旧保存底栏偏好含待办槽位 1 时仍走普通返回链', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_bottom_nav_order': <String>['0', '1', '2', '3', '4', '5', '6'],
      'pref_bottom_nav_visible': <String>['0', '1', '2', '4', '6'],
    });
    final prefs = PreferencesProvider();
    await tester.runAsync(prefs.loadFromStorage);
    expect(prefs.visibleBottomNavTabs, isNot(contains(1)));

    final todos = await _todosWithTask();
    await _pumpShell(tester, todos: todos, prefs: prefs);

    _shell(tester).openTodoFromWidget(id: 'widget-todo-1');
    await tester.pumpAndSettle();
    expect(find.byType(TodoDetailScreen), findsOneWidget);

    await _systemBack(tester);
    _expectPlainTodoList();

    await _systemBack(tester);
    _expectMainPage();
  });

  testWidgets('无 id：只打开待办清单', (tester) async {
    final todos = await _todosWithTask();
    await _pumpShell(tester, todos: todos);

    _shell(tester).openTodoFromWidget();
    await tester.pumpAndSettle();
    _expectPlainTodoList();

    await _systemBack(tester);
    _expectMainPage();
  });

  testWidgets('无效 id：兜底页返回一次到清单，再返回回主页面', (tester) async {
    final todos = await _todosWithTask();
    await _pumpShell(tester, todos: todos);

    _shell(tester).openTodoFromWidget(id: 'missing-todo');
    await tester.pumpAndSettle();

    expect(find.text('这个待办不存在或已被删除'), findsOneWidget);
    expect(find.byType(TodoScreen, skipOffstage: false), findsOneWidget);

    await _systemBack(tester);
    _expectPlainTodoList();

    await _systemBack(tester);
    _expectMainPage();
  });

  testWidgets('重复点击同一任务：栈仍是 主页面 → 清单 → 详情，不叠清单', (tester) async {
    final todos = await _todosWithTask();
    await _pumpShell(tester, todos: todos);

    _shell(tester).openTodoFromWidget(id: 'widget-todo-1');
    await tester.pumpAndSettle();
    _shell(tester).openTodoFromWidget(id: 'widget-todo-1');
    await tester.pumpAndSettle();

    expect(find.byType(TodoDetailScreen), findsOneWidget);
    expect(find.byType(TodoScreen, skipOffstage: false), findsOneWidget);

    await _systemBack(tester);
    _expectPlainTodoList();

    await _systemBack(tester);
    _expectMainPage();
  });

  testWidgets('未保存编辑期间再次打开待办保留草稿，保存后可以正常重入', (tester) async {
    final todos = await _todosWithTask();
    await _pumpShell(tester, todos: todos);
    _shell(tester).openTodoFromWidget(id: 'widget-todo-1');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '保留未保存的修改');
    await tester.pump();
    _shell(tester).openTodoFromWidget(id: 'widget-todo-1');
    await tester.pump();
    expect(find.byType(TodoDetailScreen), findsOneWidget);
    expect(find.text('保留未保存的修改'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(todos.todos.single.title, '保留未保存的修改');
    _shell(tester).openTodoFromWidget(id: 'widget-todo-1');
    await tester.pumpAndSettle();
    expect(find.text('保留未保存的修改'), findsOneWidget);
    expect(find.byType(TodoScreen, skipOffstage: false), findsOneWidget);

    await _systemBack(tester);
    _expectPlainTodoList();
    await _systemBack(tester);
    _expectMainPage();
  });

  testWidgets('已有二级页面时点击：旧二级页被清理，只保留清单与详情', (tester) async {
    final todos = await _todosWithTask();
    await _pumpShell(tester, todos: todos);

    Navigator.of(tester.element(find.byType(MainShell))).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('旧二级页')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('旧二级页'), findsOneWidget);

    _shell(tester).openTodoFromWidget(id: 'widget-todo-1');
    await tester.pumpAndSettle();

    expect(find.text('旧二级页'), findsNothing);
    expect(find.byType(TodoDetailScreen), findsOneWidget);
    expect(find.byType(TodoScreen, skipOffstage: false), findsOneWidget);

    await _systemBack(tester);
    _expectPlainTodoList();

    await _systemBack(tester);
    _expectMainPage();
  });

  testWidgets('confirm=1：清单之上弹完成确认，不直接叠详情', (tester) async {
    final todos = await _todosWithTask();
    await _pumpShell(tester, todos: todos);

    _shell(tester).openTodoFromWidget(id: 'widget-todo-1', confirm: true);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('确认完成任务'), findsOneWidget);
    expect(find.byType(TodoScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(TodoDetailScreen), findsNothing);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    _expectPlainTodoList();

    await _systemBack(tester);
    _expectMainPage();
  });
  testWidgets('冷启动未水合：打开磁盘里的真实任务而不是“不存在”，两次返回回主页面', (tester) async {
    // 进程被杀后重启：磁盘已有任务（A/B），内存里的待办列表还没读出来。
    await _todosWithTask();
    final coldTodos = TodoProvider();
    expect(coldTodos.isHydrated, isFalse);
    expect(coldTodos.todos, isEmpty);

    await _pumpShell(tester, todos: coldTodos);
    expect(coldTodos.isHydrated, isFalse, reason: '外壳启动不应抢先水合待办');

    _shell(tester).openTodoFromWidget(id: 'widget-todo-1');
    await tester.pump();
    // 水合还没落地时不能把真实任务报成“不存在”。
    expect(find.text('这个待办不存在或已被删除'), findsNothing);

    await tester.pumpAndSettle();
    expect(coldTodos.isHydrated, isTrue);
    expect(find.byType(TodoDetailScreen), findsOneWidget);
    expect(find.text('小组件任务'), findsWidgets);
    expect(find.text('这个待办不存在或已被删除'), findsNothing);

    await _systemBack(tester);
    _expectPlainTodoList();

    await _systemBack(tester);
    _expectMainPage();
  });

  testWidgets('等待水合期间的新导航让旧链接作废', (tester) async {
    await _todosWithTask();
    final todos = _GatedHydrationTodoProvider();
    await _pumpShell(tester, todos: todos);

    _shell(tester).openTodoFromWidget(id: 'widget-todo-1');
    await tester.pump();
    expect(todos.loadCalls, 1);
    expect(todos.isHydrated, isFalse);

    // 用户没等就自己切了页面：旧链接不能再把用户弹进详情。
    _shell(tester).navigateTo(0, allowHidden: true);
    await tester.pump();

    todos.gate.complete();
    await tester.pumpAndSettle();

    expect(todos.isHydrated, isTrue);
    expect(find.byType(TodoDetailScreen), findsNothing);
    expect(find.byType(TodoScreen, skipOffstage: false), findsNothing);
    expect(find.text('这个待办不存在或已被删除'), findsNothing);
    _expectMainPage();
  });

  testWidgets('等待水合期间账号数据代际变化时放弃旧链接', (tester) async {
    await _todosWithTask();
    final todos = _GatedHydrationTodoProvider();
    await _pumpShell(tester, todos: todos);

    _shell(tester).openTodoFromWidget(id: 'widget-todo-1');
    await tester.pump();
    expect(todos.loadCalls, 1);

    // 切号/退出会让在途读写作废，旧链接同样不能落地。
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();

    todos.gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(TodoDetailScreen), findsNothing);
    expect(find.byType(TodoScreen, skipOffstage: false), findsNothing);
    expect(find.text('这个待办不存在或已被删除'), findsNothing);
    _expectMainPage();
  });
}

/// 受控的慢水合：真实读盘被 gate 挡住，用来模拟“冷启动仍在等本地存储”。
class _GatedHydrationTodoProvider extends TodoProvider {
  final Completer<void> gate = Completer<void>();
  int loadCalls = 0;

  @override
  Future<void> loadFromStorage({bool force = false}) async {
    loadCalls++;
    await gate.future;
    await super.loadFromStorage(force: force);
  }
}
