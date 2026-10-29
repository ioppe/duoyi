import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/home_widget_action.dart';
import 'package:duoyi/services/home_widget_action_bridge.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `home_widget` 插件的原生通道（与 `package:home_widget` 保持一致）。
const MethodChannel _widgetChannel = MethodChannel('home_widget');

/// 记录所有小组件原生调用，用于断言 payload 内容与刷新顺序。
final List<MethodCall> _widgetCalls = [];

Future<Object?> _handleWidgetCall(MethodCall call) async {
  _widgetCalls.add(call);
  return true;
}

/// 当前账号登录态 + 数据 owner（与 `AuthProvider` 落盘格式一致）。
Map<String, Object> _accountPrefs({String userId = 'u1', String? ownerUserId}) {
  const server = 'https://example.test';
  return <String, Object>{
    'auth_state': jsonEncode(<String, dynamic>{
      'user_id': userId,
      'username': 'alice',
      'token': 'token-$userId',
    }),
    AuthProvider.sessionServerStorageKey: server,
    AccountLocalDataCleaner.accountDataOwnerKey: jsonEncode(<String>[
      server,
      'id:${ownerUserId ?? userId}',
    ]),
  };
}

Future<HomeWidgetLiveProviders> _loadProviders() async {
  final providers = HomeWidgetLiveProviders(
    todos: TodoProvider(),
    habits: HabitProvider(),
    pomodoro: PomodoroProvider(),
  );
  await providers.todos.loadFromStorage();
  await providers.habits.loadFromStorage();
  await providers.pomodoro.loadFromStorage();
  return providers;
}

Future<void> _seedTodo(String id, String title) async {
  final todos = TodoProvider();
  await todos.loadFromStorage();
  await todos.addTodo(
    TodoItem(id: id, title: title),
    waitForReminderSync: false,
  );
}

Object? _savedValue(String key) {
  final saves = _widgetCalls.where(
    (call) =>
        call.method == 'saveWidgetData' && (call.arguments as Map)['id'] == key,
  );
  if (saves.isEmpty) return null;
  return (saves.last.arguments as Map)['data'];
}

List<String> _updatedAndroidNames() => [
  for (final call in _widgetCalls)
    if (call.method == 'updateWidget') '${(call.arguments as Map)['android']}',
];

/// 冷后台动作后必须重绘的全部可切页宿主（核心 4 页 × 三档样式 + 历史综合）。
const Set<String> _switchableWidgetHosts = <String>{
  'DuoyiTodoWidgetProvider',
  'DuoyiTodoCompactWidgetProvider',
  'DuoyiTodoDetailedWidgetProvider',
  'DuoyiHabitWidgetProvider',
  'DuoyiHabitCompactWidgetProvider',
  'DuoyiHabitDetailedWidgetProvider',
  'DuoyiCalendarWidgetProvider',
  'DuoyiCalendarCompactWidgetProvider',
  'DuoyiCalendarDetailedWidgetProvider',
  'DuoyiFocusHabitWidgetProvider',
  'DuoyiFocusHabitCompactWidgetProvider',
  'DuoyiFocusHabitDetailedWidgetProvider',
  'DuoyiWidgetProvider',
};
HomeWidgetActionRequest _request(String uri) =>
    HomeWidgetActionRequest.parse(Uri.parse(uri))!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // 让应用时区解析在测试里完全可控：默认系统时区固定为 UTC。
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async => 'UTC';
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = () async => 'UTC';
  });

  tearDownAll(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = null;
  });

  setUp(() {
    _widgetCalls.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    HomeWidgetService.debugForceSupported = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_widgetChannel, _handleWidgetCall);
  });

  tearDown(() async {
    HomeWidgetService.debugForceSupported = false;
    HomeWidgetActionBridge.unregisterMainHandler();
    AppClock.debugNow = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_widgetChannel, null);
    // 把上一测试可能固定的应用时区恢复成系统（debug 注入的 UTC）。
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalTimezoneResolver.init();
  });

  group('live action (main isolate providers)', () {
    test('writes the surviving provider and survives the next edit', () async {
      SharedPreferences.setMockInitialValues(_accountPrefs());
      await _seedTodo('t1', '写报告');
      final providers = await _loadProviders();

      final changed = await HomeWidgetService.runBackgroundAction(
        _request('duoyi://action/complete_todo?id=t1'),
        live: providers,
        signedIn: true,
      );

      expect(changed, isTrue);
      expect(
        providers.todos.todos.firstWhere((todo) => todo.id == 't1').isCompleted,
        isTrue,
      );
      // 转发路径不自己刷小组件：payload 交给主 isolate 的常规推送。
      expect(_widgetCalls, isEmpty);

      // 后续普通编辑不能把后台动作的完成态写回旧值。
      await providers.todos.addTodo(
        TodoItem(id: 't3', title: '新的任务'),
        waitForReminderSync: false,
      );
      final reloaded = TodoProvider();
      await reloaded.loadFromStorage();
      expect(
        reloaded.todos.firstWhere((todo) => todo.id == 't1').isCompleted,
        isTrue,
      );
      expect(reloaded.todos.any((todo) => todo.id == 't3'), isTrue);
    });

    test('second click on a completed todo is a no-op', () async {
      SharedPreferences.setMockInitialValues(_accountPrefs());
      await _seedTodo('t1', '写报告');
      final providers = await _loadProviders();
      final request = _request('duoyi://action/complete_todo?id=t1');

      expect(
        await HomeWidgetService.runBackgroundAction(
          request,
          live: providers,
          signedIn: true,
        ),
        isTrue,
      );
      final completedAt = providers.todos.todos.single.completedAt;

      expect(
        await HomeWidgetService.runBackgroundAction(
          request,
          live: providers,
          signedIn: true,
        ),
        isFalse,
      );
      expect(providers.todos.todos.single.completedAt, completedAt);
    });

    test('signed out or owner mismatch writes nothing', () async {
      await _seedTodo('t1', '写报告');
      final signedOut = await _loadProviders();
      final request = _request('duoyi://action/complete_todo?id=t1');

      expect(
        await HomeWidgetService.runBackgroundAction(
          request,
          live: signedOut,
          signedIn: false,
        ),
        isFalse,
      );
      expect(signedOut.todos.todos.single.isCompleted, isFalse);

      // 新账号登录但本地 owner 仍是上一账号：不能写旧账号数据。
      SharedPreferences.setMockInitialValues(
        _accountPrefs(userId: 'u2', ownerUserId: 'u1'),
      );
      await _seedTodo('t1', '写报告');
      final mismatch = await _loadProviders();
      expect(
        await HomeWidgetService.runBackgroundAction(
          request,
          live: mismatch,
          signedIn: true,
        ),
        isFalse,
      );
      expect(mismatch.todos.todos.single.isCompleted, isFalse);

      final reloaded = TodoProvider();
      await reloaded.loadFromStorage();
      expect(reloaded.todos.single.isCompleted, isFalse);
    });
  });

  group('cold action (background isolate)', () {
    test(
      'checkin uses the application time-zone day, then refreshes payload',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          ..._accountPrefs(),
          LocalTimezoneResolver.modePreferenceKey:
              LocalTimezoneResolver.fixedValue,
          LocalTimezoneResolver.preferenceKey: 'Pacific/Kiritimati',
        });
        // UTC 2024-03-10 20:00 == 应用时区（UTC+14）2024-03-11 10:00。
        AppClock.debugNow = () => DateTime.utc(2024, 3, 10, 20);
        final seed = HabitProvider();
        await seed.loadFromStorage();
        await seed.addHabit(Habit(id: 'h1', name: '阅读'));

        final changed = await HomeWidgetService.runBackgroundAction(
          _request('duoyi://action/checkin_habit?id=h1'),
        );

        expect(changed, isTrue);
        final reloaded = HabitProvider();
        await reloaded.loadFromStorage();
        final habit = reloaded.habits.single;
        expect(habit.completions.keys, contains('2024-03-11'));
        expect(habit.completions.keys, isNot(contains('2024-03-10')));

        // payload 按新数据重算，且写入早于原生刷新。
        expect(_savedValue('habit_percent'), 100);
        expect(_savedValue('habit_quick_check_id'), '');
        expect(_savedValue('habit_summary'), I18n.tr('widget.habit_all_done'));
        final saveIndexes = [
          for (var i = 0; i < _widgetCalls.length; i++)
            if (_widgetCalls[i].method == 'saveWidgetData') i,
        ];
        final updateIndexes = [
          for (var i = 0; i < _widgetCalls.length; i++)
            if (_widgetCalls[i].method == 'updateWidget') i,
        ];
        expect(saveIndexes, isNotEmpty);
        expect(updateIndexes, isNotEmpty);
        expect(saveIndexes.reduce(max), lessThan(updateIndexes.reduce(min)));
        expect(_updatedAndroidNames(), contains('DuoyiHabitWidgetProvider'));
        // 实例内切页让每个宿主都可能正在显示习惯页：13 个宿主都要刷新。
        expect(_updatedAndroidNames().toSet(), _switchableWidgetHosts);

        // 冷后台留下本地待同步标记（不启动网络同步）。
        await pumpEventQueue();
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('sync_pending_local_changes'), isTrue);
      },
    );

    test(
      'every cold action repaints all switchable hosts, including legacy and calendar',
      () async {
        SharedPreferences.setMockInitialValues(_accountPrefs());
        final seedTodos = TodoProvider();
        await seedTodos.loadFromStorage();
        await seedTodos.addTodo(
          TodoItem(id: 't1', title: '写报告'),
          waitForReminderSync: false,
        );
        final seedHabits = HabitProvider();
        await seedHabits.loadFromStorage();
        await seedHabits.addHabit(Habit(id: 'h1', name: '阅读'));
        final seedPomodoro = PomodoroProvider();
        await seedPomodoro.loadFromStorage();
        seedPomodoro.dispose();

        // 四个动作的刷新列表必须完全一致：任一宿主都可能正在显示被动作修改的页。
        for (final kind in HomeWidgetActionKind.values) {
          final names = HomeWidgetService.androidProviderNamesForAction(kind);
          expect(names, hasLength(13), reason: '${kind.name} 需要刷新全部可切页宿主');
          expect(names.toSet(), _switchableWidgetHosts, reason: kind.name);
        }

        // 真实冷后台动作同样覆盖历史综合与月历宿主。
        _widgetCalls.clear();
        expect(
          await HomeWidgetService.runBackgroundAction(
            _request('duoyi://action/complete_todo?id=t1'),
          ),
          isTrue,
        );
        final refreshed = _updatedAndroidNames();
        expect(refreshed, hasLength(13));
        expect(refreshed.toSet(), _switchableWidgetHosts);
        expect(refreshed, contains('DuoyiWidgetProvider'));
        expect(refreshed, contains('DuoyiCalendarWidgetProvider'));
      },
    );
  });

  group('action payload builders', () {
    test(
      'todo payload follows today ordering and clears empty slots',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final todos = TodoProvider();
        await todos.loadFromStorage();
        for (final todo in [
          TodoItem(id: 'low', title: '低', priority: TodoPriority.low),
          TodoItem(
            id: 'high2',
            title: '高2',
            priority: TodoPriority.high,
            sortOrder: 2,
          ),
          TodoItem(
            id: 'high1',
            title: '高1',
            priority: TodoPriority.high,
            sortOrder: 1,
          ),
        ]) {
          await todos.addTodo(todo, waitForReminderSync: false);
        }

        final payload = HomeWidgetService.todoHomeWidgetActionPayload(todos);

        expect(payload['todo_count'], 3);
        expect(payload['todo_top3_count'], 3);
        // 优先级倒序，其次 sortOrder 升序（与 `_pushHomeWidget` 一致）。
        expect(payload['todo_top3_1_id'], 'high1');
        expect(payload['todo_top3_2_id'], 'high2');
        expect(payload['todo_top3_3_id'], 'low');

        await todos.completeTodos(['low', 'high2', 'high1']);
        final empty = HomeWidgetService.todoHomeWidgetActionPayload(todos);
        expect(empty['todo_count'], 0);
        expect(empty['todo_top3_1'], I18n.tr('widget.todo_top3_empty'));
        expect(empty['todo_top3_1_id'], '');
        expect(empty['todo_top3_2_id'], '');
        expect(empty['todo_top3_3_id'], '');
      },
    );

    test('habit payload points at the next pending habit', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final habits = HabitProvider();
      await habits.loadFromStorage();
      await habits.addHabit(Habit(id: 'h2', name: '拉伸', sortOrder: 2));
      await habits.addHabit(Habit(id: 'h1', name: '阅读', sortOrder: 1));

      final before = HomeWidgetService.habitHomeWidgetActionPayload(habits);
      expect(before['habit_percent'], 0);
      expect(before['habit_quick_check_id'], 'h1');
      expect(before['habit_highlight_1'], '· 阅读 0%');
      expect(before['habit_highlight_1_id'], 'h1');
      expect(before['habit_highlight_2'], '· 拉伸 0%');
      expect(before['habit_highlight_2_id'], 'h2');
      expect(
        before['habit_quick_check_label'],
        '${I18n.tr('widget.habit_checkin_prefix')}阅读',
      );

      await habits.incrementHabit('h1');
      final after = HomeWidgetService.habitHomeWidgetActionPayload(habits);
      expect(after['habit_percent'], 50);
      expect(after['habit_quick_check_id'], 'h2');
      expect(after['habit_highlight_1'], '· 阅读 100%');
      expect(after['habit_highlight_1_id'], 'h1');
    });

    test('计数型习惯打卡会更新具体习惯进度 payload', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final habits = HabitProvider();
      await habits.loadFromStorage();
      addTearDown(habits.dispose);
      await habits.addHabit(Habit(id: 'counting', name: '喝水', targetCount: 3));

      final before = HomeWidgetService.habitHomeWidgetActionPayload(habits);
      await habits.incrementHabit('counting');
      final after = HomeWidgetService.habitHomeWidgetActionPayload(habits);

      expect(before['habit_percent'], 0);
      expect(after['habit_percent'], 0);
      expect(before['habit_highlight_1'], '· 喝水 0%');
      expect(after['habit_highlight_1'], '· 喝水 33%');
      expect(after['habit_highlight_1_id'], 'counting');
    });

    test(
      'focus payload keeps the absolute end time of the new state',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final pomodoro = PomodoroProvider();
        await pomodoro.loadFromStorage();
        pomodoro.startIfIdle();
        try {
          expect(pomodoro.state.isRunning, isTrue);
          final payload = HomeWidgetService.focusHomeWidgetActionPayload(
            pomodoro,
          );

          expect(payload['focus_timer_running'], isTrue);
          expect(payload['focus_timer_remaining_seconds'], greaterThan(0));
          expect(
            payload['focus_timer_total_seconds'],
            pomodoro.state.totalSeconds,
          );
          expect(
            payload['focus_timer_label'],
            I18n.tr('widget.focus_countdown'),
          );
          expect(payload['focus_summary'], I18n.tr('widget.focus_not_started'));
          final endsAt = payload['focus_timer_ends_at_millis'] as int;
          final expected = DateTime.now()
              .add(Duration(seconds: pomodoro.state.remainingSeconds))
              .millisecondsSinceEpoch;
          expect((endsAt - expected).abs(), lessThan(5000));
        } finally {
          pomodoro.dispose();
        }
      },
    );
  });

  group('background action forwarding', () {
    test('main handler registration is single instance', () {
      HomeWidgetActionBridge.unregisterMainHandler();
      expect(HomeWidgetActionBridge.hasMainHandler, isFalse);

      HomeWidgetActionBridge.registerMainHandler(
        (_) async => HomeWidgetActionAck.done,
      );
      HomeWidgetActionBridge.registerMainHandler(
        (_) async => HomeWidgetActionAck.failed,
      );

      expect(HomeWidgetActionBridge.hasMainHandler, isTrue);
      HomeWidgetActionBridge.unregisterMainHandler();
      expect(HomeWidgetActionBridge.hasMainHandler, isFalse);
    });

    test(
      'ack timeout still counts as takeover, and only one send happens',
      () async {
        final mainPort = ReceivePort();
        final received = <Object?>[];
        mainPort.listen(received.add);
        final originalLookup = HomeWidgetActionBridge.debugLookupPort;
        HomeWidgetActionBridge.debugLookupPort = (name) =>
            name == HomeWidgetActionBridge.portName ? mainPort.sendPort : null;
        try {
          final uri = Uri.parse('duoyi://action/complete_todo?id=t1');
          final forwarded = await HomeWidgetActionBridge.forwardToMainIsolate(
            uri,
            timeout: const Duration(milliseconds: 50),
          );

          expect(forwarded, isTrue);
          await pumpEventQueue();
          expect(received, hasLength(1));
          final message = received.single! as List;
          // 只传 primitive URI 字符串 + 回信端口。
          expect(message[0], uri.toString());
          expect(message[1], isA<SendPort>());
        } finally {
          HomeWidgetActionBridge.debugLookupPort = originalLookup;
          mainPort.close();
        }
      },
    );

    test('no registered port means the cold path runs', () async {
      final originalLookup = HomeWidgetActionBridge.debugLookupPort;
      HomeWidgetActionBridge.debugLookupPort = (_) => null;
      try {
        expect(
          await HomeWidgetActionBridge.forwardToMainIsolate(
            Uri.parse('duoyi://action/checkin_habit?id=h1'),
            timeout: const Duration(milliseconds: 50),
          ),
          isFalse,
        );
      } finally {
        HomeWidgetActionBridge.debugLookupPort = originalLookup;
      }
    });

    test('entry never runs locally once the main isolate took over', () async {
      var localRuns = 0;
      Future<bool> runLocally(HomeWidgetActionRequest request) async {
        localRuns++;
        return true;
      }

      await handleHomeWidgetBackgroundUri(
        Uri.parse('duoyi://action/checkin_habit?id=h1'),
        // ACK 失败或超时在 bridge 里都表现为“已接管”。
        forwardToMain: (_) async => true,
        runLocally: runLocally,
      );
      expect(localRuns, 0);

      await handleHomeWidgetBackgroundUri(
        Uri.parse('duoyi://action/checkin_habit?id=h1'),
        forwardToMain: (_) async => false,
        runLocally: runLocally,
      );
      expect(localRuns, 1);
    });

    test('entry ignores URIs that are not background actions', () async {
      var forwarded = 0;
      var localRuns = 0;
      await handleHomeWidgetBackgroundUri(
        Uri.parse('duoyi://todo/abc'),
        forwardToMain: (_) async {
          forwarded++;
          return true;
        },
        runLocally: (_) async {
          localRuns++;
          return true;
        },
      );
      await handleHomeWidgetBackgroundUri(
        null,
        forwardToMain: (_) async {
          forwarded++;
          return true;
        },
        runLocally: (_) async {
          localRuns++;
          return true;
        },
      );
      expect(forwarded, 0);
      expect(localRuns, 0);
    });
  });

  group('push snapshot signature caching', () {
    // 与 accountPayloadDefaults 对齐的最小主题：只为触发 push 的 signature 计算。
    const theme = HomeWidgetThemePayload(
      brandId: 'defaultBrand',
      cardSkinId: 'plain_card',
      dark: false,
      primary: Color(0xFFFF6B6B),
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFFFFFFF),
      navBackground: Color(0xFFFFF6F2),
      border: Color(0x22FF6B6B),
      text: Color(0xFF333333),
      mutedText: Color(0xFF666666),
      onPrimary: Color(0xFFFFFFFF),
      accentStart: Color(0xFFFF6B6B),
      accentEnd: Color(0xFFFFB088),
      backgroundAssetKey: '',
      cornerRadiusDp: 13,
      controlRadiusDp: 8,
      borderWidthDp: 0,
    );

    Future<bool> pushSnapshot() => HomeWidgetService.push(
      todoCount: 3,
      habitPercent: 50,
      pomodoroToday: 1,
      focusMinutesToday: 25,
      strings: AppBrands.defaultBrand.strings,
      theme: theme,
    );

    test('原生 0 命中不算成功，同 payload 必须重试，真刷新后才去重', () async {
      var refreshes = 0;
      HomeWidgetService.debugRefreshAllWidgetsOverride = () async {
        refreshes++;
        // 第一次原生 0 命中（无桌面实例被重建），之后真正刷到实例。
        return refreshes == 1 ? 0 : 2;
      };
      addTearDown(
        () => HomeWidgetService.debugRefreshAllWidgetsOverride = null,
      );

      expect(
        await pushSnapshot(),
        isFalse,
        reason: '0 命中说明没有实例被刷新，不能当成功（否则会缓存 signature）',
      );
      expect(refreshes, 1);

      expect(
        await pushSnapshot(),
        isTrue,
        reason: '0 命中之后同 payload 必须重试而不是被 signature 去重',
      );
      expect(refreshes, 2);

      expect(await pushSnapshot(), isTrue);
      expect(refreshes, 2, reason: '真正刷新成功后，同 payload 才允许走 signature 去重');
    });
  });
}
