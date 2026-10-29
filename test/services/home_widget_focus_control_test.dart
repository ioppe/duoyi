import 'dart:convert';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/home_widget_todos.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/home_widget_action.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `home_widget` 插件的原生通道。
const MethodChannel _widgetChannel = MethodChannel('home_widget');

final List<MethodCall> _widgetCalls = <MethodCall>[];

Future<Object?> _handleWidgetCall(MethodCall call) async {
  _widgetCalls.add(call);
  return true;
}

Object? _savedValue(String key) {
  final saves = _widgetCalls.where(
    (call) =>
        call.method == 'saveWidgetData' && (call.arguments as Map)['id'] == key,
  );
  if (saves.isEmpty) return null;
  return (saves.last.arguments as Map)['data'];
}

List<String> _updatedAndroidNames() => <String>[
  for (final call in _widgetCalls)
    if (call.method == 'updateWidget') '${(call.arguments as Map)['android']}',
];

Map<String, Object> _signedInPrefs({String userId = 'u1'}) {
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
      'id:$userId',
    ]),
  };
}

String _controlRecord({
  required String sessionId,
  required int revision,
  required String state,
  Map<String, dynamic>? paused,
}) {
  final result = <String, dynamic>{
    'sessionId': sessionId,
    'revision': revision,
    'state': state,
  };
  if (paused != null) result['paused'] = paused;
  return jsonEncode(result);
}

HomeWidgetActionRequest _parse(String uri) =>
    HomeWidgetActionRequest.parse(Uri.parse(uri))!;

Future<PomodoroProvider> _pomodoro({bool disposeOnTearDown = true}) async {
  final provider = PomodoroProvider();
  await provider.loadFromStorage();
  if (disposeOnTearDown) addTearDown(provider.dispose);
  return provider;
}

HomeWidgetThemePayload _theme() => const HomeWidgetThemePayload(
  brandId: 'b',
  cardSkinId: 'plain_card',
  dark: false,
  primary: Colors.red,
  background: Colors.white,
  surface: Colors.white,
  navBackground: Colors.white,
  border: Colors.grey,
  text: Colors.black,
  mutedText: Colors.grey,
  onPrimary: Colors.white,
  accentStart: Colors.red,
  accentEnd: Colors.orange,
  backgroundAssetKey: '',
  cornerRadiusDp: 13,
  controlRadiusDp: 8,
  borderWidthDp: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
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
    HomeWidgetService.debugRefreshAllWidgetsOverride = () async => 1;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_widgetChannel, _handleWidgetCall);
  });

  tearDown(() async {
    HomeWidgetService.debugForceSupported = false;
    HomeWidgetService.debugRefreshAllWidgetsOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_widgetChannel, null);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalTimezoneResolver.init();
  });

  group('绑定 URI 解析', () {
    test('完全无绑定字段的 legacy start 仍然可解析', () {
      final request = _parse('duoyi://action/start_pomodoro');
      expect(request.kind, HomeWidgetActionKind.startPomodoro);
      expect(request.isBoundFocusControl, isFalse);
      // legacy 不能拿到匿名权限。
      expect(request.allowsSignedOutExecution, isFalse);
    });

    test('四段齐全的 start / pause / stop 解析出完整绑定字段', () {
      final start = _parse(
        'duoyi://action/start_pomodoro'
        '?session=s1&revision=2&state=idle&scope=local',
      );
      expect(start.kind, HomeWidgetActionKind.startPomodoro);
      expect(start.focusSessionId, 's1');
      expect(start.focusRevision, 2);
      expect(start.focusState, PomodoroWidgetTimerState.idle);
      expect(start.focusScope, 'local');
      expect(start.isBoundFocusControl, isTrue);
      expect(start.allowsSignedOutExecution, isTrue);

      final pause = _parse(
        'duoyi://action/pause_pomodoro'
        '?session=s1&revision=2&state=running&scope=local',
      );
      expect(pause.kind, HomeWidgetActionKind.pausePomodoro);
      expect(pause.focusState, PomodoroWidgetTimerState.running);

      final stop = _parse(
        'duoyi://action/stop_pomodoro'
        '?session=s1&revision=2&state=paused&scope=local',
      );
      expect(stop.kind, HomeWidgetActionKind.stopPomodoro);
      expect(stop.focusState, PomodoroWidgetTimerState.paused);
    });

    test('部分缺失 / 非法 revision / 非法 state 一律拒绝解析', () {
      // 只有 session，缺其余三段。
      expect(
        HomeWidgetActionRequest.parse(
          Uri.parse('duoyi://action/start_pomodoro?session=s1'),
        ),
        isNull,
      );
      // revision 非数字 / 负数。
      expect(
        HomeWidgetActionRequest.parse(
          Uri.parse(
            'duoyi://action/pause_pomodoro'
            '?session=s1&revision=x&state=running&scope=local',
          ),
        ),
        isNull,
      );
      expect(
        HomeWidgetActionRequest.parse(
          Uri.parse(
            'duoyi://action/pause_pomodoro'
            '?session=s1&revision=-1&state=running&scope=local',
          ),
        ),
        isNull,
      );
      // state 不在协议里。
      expect(
        HomeWidgetActionRequest.parse(
          Uri.parse(
            'duoyi://action/pause_pomodoro'
            '?session=s1&revision=1&state=stopped&scope=local',
          ),
        ),
        isNull,
      );
      // 空 session / 空 scope。
      expect(
        HomeWidgetActionRequest.parse(
          Uri.parse(
            'duoyi://action/pause_pomodoro'
            '?session=&revision=1&state=running&scope=local',
          ),
        ),
        isNull,
      );
      expect(
        HomeWidgetActionRequest.parse(
          Uri.parse(
            'duoyi://action/pause_pomodoro'
            '?session=s1&revision=1&state=running&scope=',
          ),
        ),
        isNull,
      );
      // 过长的 session / scope。
      expect(
        HomeWidgetActionRequest.parse(
          Uri.parse(
            'duoyi://action/pause_pomodoro?session='
            '${'s' * (HomeWidgetActionRequest.maxFocusSessionIdLength + 1)}'
            '&revision=1&state=running&scope=local',
          ),
        ),
        isNull,
      );
      expect(
        HomeWidgetActionRequest.parse(
          Uri.parse(
            'duoyi://action/pause_pomodoro?session=s1&revision=1'
            '&state=running&scope='
            '${'q' * (HomeWidgetActionRequest.maxFocusScopeLength + 1)}',
          ),
        ),
        isNull,
      );
    });

    test('状态与动作不匹配时拒绝：paused 发 pause、idle 发 stop', () {
      expect(
        HomeWidgetActionRequest.parse(
          Uri.parse(
            'duoyi://action/pause_pomodoro'
            '?session=s1&revision=1&state=paused&scope=local',
          ),
        ),
        isNull,
      );
      expect(
        HomeWidgetActionRequest.parse(
          Uri.parse(
            'duoyi://action/stop_pomodoro'
            '?session=s1&revision=1&state=idle&scope=local',
          ),
        ),
        isNull,
      );
      // start 只接受 idle / paused。
      expect(
        HomeWidgetActionRequest.parse(
          Uri.parse(
            'duoyi://action/start_pomodoro'
            '?session=s1&revision=1&state=running&scope=local',
          ),
        ),
        isNull,
      );
      // pause / stop 没有 legacy 形式。
      expect(
        HomeWidgetActionRequest.parse(
          Uri.parse('duoyi://action/pause_pomodoro'),
        ),
        isNull,
      );
      expect(
        HomeWidgetActionRequest.parse(
          Uri.parse('duoyi://action/stop_pomodoro'),
        ),
        isNull,
      );
    });
  });

  group('focus 控制 scope 身份', () {
    test('已登录且 owner/服务器/账号匹配时返回 canonical 身份', () {
      final scope = HomeWidgetAccountScope.fromValues(
        authStateJson: jsonEncode(<String, dynamic>{
          'user_id': 'u1',
          'token': 't',
        }),
        storedOwner: jsonEncode(<String>['https://example.test', 'id:u1']),
        sessionServer: 'https://example.test',
      );
      expect(
        scope.focusControlScope,
        jsonEncode(<String>[
          jsonEncode(<String>['https://example.test', 'id:u1']),
          'https://example.test',
        ]),
      );
    });

    test('未登录且无 owner/账号残留时返回本地匿名身份', () {
      final scope = HomeWidgetAccountScope.fromValues(
        authStateJson: null,
        storedOwner: null,
        sessionServer: null,
      );
      expect(scope.blockReason, HomeWidgetActionBlockReason.signedOut);
      expect(
        scope.focusControlScope,
        HomeWidgetAccountScope.localFocusControlScope,
      );
    });

    test('owner 残留或换号后旧 scope 失效', () {
      // 未登录但残留 owner：既不是登录态，也不允许匿名。
      final residual = HomeWidgetAccountScope.fromValues(
        authStateJson: null,
        storedOwner: 'id:u1',
        sessionServer: null,
      );
      expect(residual.focusControlScope, isNull);

      // 已登录 u2 但 owner 还是 u1：ownerMismatch。
      final switched = HomeWidgetAccountScope.fromValues(
        authStateJson: jsonEncode(<String, dynamic>{
          'user_id': 'u2',
          'token': 't2',
        }),
        storedOwner: jsonEncode(<String>['https://example.test', 'id:u1']),
        sessionServer: 'https://example.test',
      );
      expect(switched.blockReason, HomeWidgetActionBlockReason.ownerMismatch);
      expect(switched.focusControlScope, isNull);
    });
  });

  group('Provider 绑定控制', () {
    test('start → pause → resume 保留同一 session 并推进 revision', () async {
      final provider = await _pomodoro();
      expect(provider.focusTimerState, PomodoroWidgetTimerState.idle);
      final session = provider.focusControlSessionId;
      final revision = provider.focusControlRevision;
      expect(session, isNotEmpty);

      expect(
        await provider.applyWidgetControl(
          action: PomodoroWidgetControlAction.start,
          sessionId: session,
          revision: revision,
          expectedState: PomodoroWidgetTimerState.idle,
        ),
        isTrue,
      );
      expect(provider.state.isRunning, isTrue);
      expect(provider.focusTimerState, PomodoroWidgetTimerState.running);
      expect(provider.focusControlSessionId, session);
      final runningRevision = provider.focusControlRevision;
      expect(runningRevision, greaterThan(revision));

      // 重复 start（旧 revision）不改状态。
      expect(
        await provider.applyWidgetControl(
          action: PomodoroWidgetControlAction.start,
          sessionId: session,
          revision: revision,
          expectedState: PomodoroWidgetTimerState.running,
        ),
        isFalse,
      );

      expect(
        await provider.applyWidgetControl(
          action: PomodoroWidgetControlAction.pause,
          sessionId: session,
          revision: runningRevision,
          expectedState: PomodoroWidgetTimerState.running,
        ),
        isTrue,
      );
      expect(provider.state.isRunning, isFalse);
      expect(provider.focusTimerState, PomodoroWidgetTimerState.paused);
      final remainingAtPause = provider.state.remainingSeconds;
      expect(remainingAtPause, greaterThan(0));

      // 重复 pause 同一条绑定是 no-op。
      expect(
        await provider.applyWidgetControl(
          action: PomodoroWidgetControlAction.pause,
          sessionId: session,
          revision: runningRevision,
          expectedState: PomodoroWidgetTimerState.running,
        ),
        isFalse,
      );

      final pausedRevision = provider.focusControlRevision;
      expect(
        await provider.applyWidgetControl(
          action: PomodoroWidgetControlAction.start,
          sessionId: session,
          revision: pausedRevision,
          expectedState: PomodoroWidgetTimerState.paused,
        ),
        isTrue,
      );
      expect(provider.state.isRunning, isTrue);
      // 续跑同一剩余时长，不新开一次专注。
      expect(provider.focusControlSessionId, session);
      expect(provider.state.remainingSeconds, remainingAtPause);
      expect(provider.sessions, isEmpty);
    });

    test('stop 回到满时长、不产生完成记录且生成新 idle 身份', () async {
      final provider = await _pomodoro();
      final session = provider.focusControlSessionId;
      final revision = provider.focusControlRevision;
      await provider.applyWidgetControl(
        action: PomodoroWidgetControlAction.start,
        sessionId: session,
        revision: revision,
        expectedState: PomodoroWidgetTimerState.idle,
      );
      final runningRevision = provider.focusControlRevision;

      expect(
        await provider.applyWidgetControl(
          action: PomodoroWidgetControlAction.stop,
          sessionId: session,
          revision: runningRevision,
          expectedState: PomodoroWidgetTimerState.running,
        ),
        isTrue,
      );
      expect(provider.state.isRunning, isFalse);
      expect(provider.state.type, PomodoroType.focus);
      expect(provider.state.remainingSeconds, provider.config.focusDuration);
      expect(provider.state.completedSessions, 0);
      expect(provider.sessions, isEmpty);
      expect(provider.sessionCountToday, 0);
      expect(provider.focusTimerState, PomodoroWidgetTimerState.idle);
      expect(provider.focusControlSessionId, isNot(session));
      expect(provider.focusControlRevision, 0);

      // 旧身份（含旧 revision）的 start 已失效。
      expect(
        await provider.applyWidgetControl(
          action: PomodoroWidgetControlAction.start,
          sessionId: session,
          revision: runningRevision,
          expectedState: PomodoroWidgetTimerState.running,
        ),
        isFalse,
      );
      expect(provider.state.isRunning, isFalse);
    });

    test('严格模式暂停惩罚只记录一次', () async {
      final provider = await _pomodoro();
      final config = provider.config;
      config.strictFocusMode = true;
      await provider.setConfig(config);

      final session = provider.focusControlSessionId;
      final revision = provider.focusControlRevision;
      await provider.applyWidgetControl(
        action: PomodoroWidgetControlAction.start,
        sessionId: session,
        revision: revision,
        expectedState: PomodoroWidgetTimerState.idle,
      );
      final runningRevision = provider.focusControlRevision;

      await provider.applyWidgetControl(
        action: PomodoroWidgetControlAction.pause,
        sessionId: session,
        revision: runningRevision,
        expectedState: PomodoroWidgetTimerState.running,
      );
      // 重复/陈旧请求不再触发第二次惩罚。
      await provider.applyWidgetControl(
        action: PomodoroWidgetControlAction.pause,
        sessionId: session,
        revision: runningRevision,
        expectedState: PomodoroWidgetTimerState.running,
      );
      await pumpEventQueue();
      expect(
        provider.penalties.where((p) => p.reason == FocusPenaltyReason.pause),
        hasLength(1),
      );
    });

    test('暂停态跨重启保留剩余时长与同一身份', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final provider = await _pomodoro(disposeOnTearDown: false);
      final session = provider.focusControlSessionId;
      await provider.applyWidgetControl(
        action: PomodoroWidgetControlAction.start,
        sessionId: session,
        revision: provider.focusControlRevision,
        expectedState: PomodoroWidgetTimerState.idle,
      );
      await provider.applyWidgetControl(
        action: PomodoroWidgetControlAction.pause,
        sessionId: session,
        revision: provider.focusControlRevision,
        expectedState: PomodoroWidgetTimerState.running,
      );
      final pausedRemaining = provider.state.remainingSeconds;
      final pausedTotal = provider.state.totalSeconds;
      final pausedRevision = provider.focusControlRevision;
      provider.dispose();
      await pumpEventQueue();

      final reloaded = await _pomodoro();
      expect(reloaded.state.isRunning, isFalse);
      expect(reloaded.focusTimerState, PomodoroWidgetTimerState.paused);
      expect(reloaded.state.remainingSeconds, pausedRemaining);
      expect(reloaded.state.totalSeconds, pausedTotal);
      expect(reloaded.focusControlSessionId, session);
      expect(reloaded.focusControlRevision, pausedRevision);
    });

    test('正计时也能 start / pause / resume，结束时刻为 0', () async {
      final provider = await _pomodoro();
      provider.setCountUpMode(true);
      expect(provider.focusTimerState, PomodoroWidgetTimerState.idle);
      final session = provider.focusControlSessionId;

      await provider.applyWidgetControl(
        action: PomodoroWidgetControlAction.start,
        sessionId: session,
        revision: provider.focusControlRevision,
        expectedState: PomodoroWidgetTimerState.idle,
      );
      expect(provider.state.isCountUp, isTrue);
      expect(provider.state.isRunning, isTrue);
      expect(provider.focusTimerEndsAtMillis, 0);

      await provider.applyWidgetControl(
        action: PomodoroWidgetControlAction.pause,
        sessionId: session,
        revision: provider.focusControlRevision,
        expectedState: PomodoroWidgetTimerState.running,
      );
      expect(provider.focusTimerState, PomodoroWidgetTimerState.paused);
      expect(provider.state.isCountUp, isTrue);
    });
  });

  group('服务层账号边界与匿名 focus', () {
    test('冷后台绑定 start：匿名本地专注可执行并刷新 13 个宿主', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'pomodoro_widget_control': _controlRecord(
          sessionId: 's1',
          revision: 3,
          state: 'idle',
        ),
      });
      final request = _parse(
        'duoyi://action/start_pomodoro'
        '?session=s1&revision=3&state=idle&scope=local',
      );

      expect(await HomeWidgetService.runBackgroundAction(request), isTrue);

      expect(_savedValue('focus_timer_state'), 'running');
      expect(_savedValue('focus_timer_session_id'), 's1');
      expect(_savedValue('focus_timer_revision') as int, greaterThan(3));
      expect(_savedValue('focus_control_scope'), 'local');
      expect(_savedValue('widget_todo_items_json'), isNotNull);
      expect(_savedValue('widget_focus_pause_label'), isNotNull);
      expect(_savedValue('focus_timer_count_up'), isFalse);
      expect(_updatedAndroidNames(), containsAll(_switchableHosts));

      // 同一条绑定再来一次（旧 revision）必须被拒绝，不重复启动/惩罚。
      expect(await HomeWidgetService.runBackgroundAction(request), isFalse);
    });

    test('legacy start 与外地 scope 在未登录时都被拒绝', () async {
      expect(
        await HomeWidgetService.runBackgroundAction(
          _parse('duoyi://action/start_pomodoro'),
        ),
        isFalse,
      );
      expect(
        await HomeWidgetService.runBackgroundAction(
          _parse(
            'duoyi://action/start_pomodoro'
            '?session=s1&revision=0&state=idle&scope=someone-else',
          ),
        ),
        isFalse,
      );
      expect(_savedValue('focus_timer_state'), isNull);
    });

    test('换号后旧 scope 的绑定按钮不能操作新账号', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ..._signedInPrefs(userId: 'u2'),
        'pomodoro_widget_control': _controlRecord(
          sessionId: 's2',
          revision: 1,
          state: 'idle',
        ),
      });
      final staleScope = jsonEncode(<String>[
        '["https://example.test","id:u1"]',
        'https://example.test',
      ]);
      final stale = HomeWidgetActionRequest.parse(
        Uri.parse(
          'duoyi://action/start_pomodoro'
          '?session=s2&revision=1&state=idle'
          '&scope=${Uri.encodeQueryComponent(staleScope)}',
        ),
      );
      expect(stale, isNotNull);
      expect(
        await HomeWidgetService.runBackgroundAction(stale!, signedIn: true),
        isFalse,
      );

      final canonicalScope = HomeWidgetAccountScope.fromPreferences(
        await SharedPreferences.getInstance(),
      ).focusControlScope;
      expect(canonicalScope, isNotNull);
      final fresh = HomeWidgetActionRequest.parse(
        Uri.parse(
          'duoyi://action/start_pomodoro'
          '?session=s2&revision=1&state=idle'
          '&scope=${Uri.encodeQueryComponent(canonicalScope!)}',
        ),
      );
      expect(
        await HomeWidgetService.runBackgroundAction(fresh!, signedIn: true),
        isTrue,
      );
    });
  });

  group('推送签名与 payload 形状', () {
    test('今日待办数组包含全部项，第 4 项变化会改变 payload', () async {
      final todos = TodoProvider();
      await todos.loadFromStorage();
      addTearDown(todos.dispose);
      for (var index = 0; index < 4; index++) {
        await todos.addTodo(
          TodoItem(id: 't$index', title: '任务 $index', sortOrder: index),
          waitForReminderSync: false,
        );
      }
      final first = HomeWidgetService.todoHomeWidgetActionPayload(todos);
      expect(first['todo_top3_count'], 4);
      final decoded =
          jsonDecode(first['widget_todo_items_json']! as String) as List;
      expect(decoded, hasLength(4));

      // 第 4 项（不在旧 Top3 里）变化也必须改变 payload → 触发签名刷新。
      final target = todos.todos.firstWhere((todo) => todo.id == 't3');
      await todos.updateTodo(
        't3',
        target.copyWith(title: '任务 3 改名'),
        waitForReminderSync: false,
      );
      final second = HomeWidgetService.todoHomeWidgetActionPayload(todos);
      expect(
        second['widget_todo_items_json'],
        isNot(first['widget_todo_items_json']),
      );
      expect(second['todo_top3_1'], first['todo_top3_1']);
    });

    test('push 携带 5 个控制文案与 5 个控制元数据', () async {
      final strings = AppBrands.defaultBrand.strings;
      Future<void> push(String todoJson) => HomeWidgetService.push(
        todoCount: 1,
        habitPercent: 0,
        pomodoroToday: 0,
        focusMinutesToday: 0,
        strings: strings,
        theme: _theme(),
        todoItemsJson: todoJson,
        focusTimerState: 'running',
        focusTimerSessionId: 's9',
        focusTimerRevision: 7,
        focusControlScope: 'local',
        focusTimerCountUp: false,
      );

      await push('[{"id":"a","title":"A","quadrant":0}]');
      expect(_savedValue('focus_timer_state'), 'running');
      expect(_savedValue('focus_timer_session_id'), 's9');
      expect(_savedValue('focus_timer_revision'), 7);
      expect(_savedValue('focus_control_scope'), 'local');
      expect(_savedValue('focus_timer_count_up'), isFalse);
      expect(_savedValue('widget_todo_items_json'), contains('"a"'));
      for (final key in <String>[
        'widget_focus_start_label',
        'widget_focus_resume_label',
        'widget_focus_pause_label',
        'widget_focus_stop_label',
        'widget_focus_paused_label',
      ]) {
        expect(_savedValue(key), isNotNull, reason: '缺少 $key');
      }
      // 原有 10 个展示文案一个都不能少。
      for (final key in <String>[
        'widget_todo_empty_hint',
        'widget_todo_count_unit',
        'widget_habit_today_label',
        'widget_focus_count_label',
        'widget_focus_minutes_label',
        'widget_focus_next_label',
        'widget_focus_remaining_label',
        'widget_focus_open_label',
        'widget_focus_running_label',
        'widget_today_label',
      ]) {
        expect(_savedValue(key), isNotNull, reason: '缺少 $key');
      }
      expect(
        _savedValue('widget_focus_start_label'),
        I18n.tr('widget.focus_start_label'),
      );
      expect(
        _savedValue('widget_focus_paused_label'),
        I18n.tr('widget.focus_paused_label'),
      );

      // debug refresh override deliberately returns a count without invoking the plugin;
      // verify the changed fourth item is nevertheless persisted in the payload.
      await push(
        '[{"id":"a","title":"A","quadrant":0},{"id":"d","title":"D","quadrant":0}]',
      );
      expect(_savedValue('widget_todo_items_json'), contains('"d"'));
    });

    test('习惯打卡次数变化会穿过 push 去重签名', () async {
      final strings = AppBrands.defaultBrand.strings;
      Future<void> push(int totalCompletions) => HomeWidgetService.push(
        todoCount: 0,
        habitPercent: 0,
        pomodoroToday: 0,
        focusMinutesToday: 0,
        strings: strings,
        theme: _theme(),
        todoItemsJson: '[]',
        habitTotalCompletions: totalCompletions,
        habitHighlights: const ['· 阅读 0%'],
        habitHighlightIds: const ['h1'],
      );

      await push(0);
      _widgetCalls.clear();
      await push(1);

      expect(_savedValue('habit_highlight_1'), '· 阅读 0%');
      expect(_savedValue('habit_highlight_1_id'), 'h1');
    });

    test('账号清理默认值包含新 key 与 idle 控制身份', () {
      final defaults = HomeWidgetService.accountPayloadDefaults;
      expect(defaults['widget_todo_items_json'], '[]');
      expect(defaults['focus_timer_state'], 'idle');
      expect(defaults['focus_timer_session_id'], '');
      expect(defaults['focus_timer_revision'], 0);
      expect(defaults['focus_control_scope'], '');
      expect(defaults['focus_timer_count_up'], isFalse);
      for (final key in <String>[
        'widget_focus_start_label',
        'widget_focus_resume_label',
        'widget_focus_pause_label',
        'widget_focus_stop_label',
        'widget_focus_paused_label',
      ]) {
        expect(defaults[key], isNotNull, reason: '缺少 $key');
      }
      // 旧 Top3 与 calendar 5 keys 语义不变。
      expect(defaults['todo_top3_count'], 0);
      expect(defaults['calendar_day_counts_json'], '{}');
      expect(defaults.containsKey('calendar_timezone'), isTrue);
    });
  });

  group('home_widget_todos 与 payload 一致性', () {
    test('todo 数组按 Q1→Q3→Q2→Q4 排序，旧 Top3 取新排序前 3', () async {
      final todos = TodoProvider();
      await todos.loadFromStorage();
      addTearDown(todos.dispose);
      for (final (id, quadrant) in <(String, EisenhowerQuadrant)>[
        ('q4', EisenhowerQuadrant.notUrgentNotImportant),
        ('q3', EisenhowerQuadrant.urgentNotImportant),
        ('q2', EisenhowerQuadrant.notUrgentImportant),
        ('q1', EisenhowerQuadrant.urgentImportant),
      ]) {
        await todos.addTodo(
          TodoItem(id: id, title: id, quadrant: quadrant),
          waitForReminderSync: false,
        );
      }
      final payload = HomeWidgetService.todoHomeWidgetActionPayload(todos);
      final ids =
          (jsonDecode(payload['widget_todo_items_json']! as String) as List)
              .map((item) => (item as Map)['id'])
              .toList();
      expect(ids, <String>['q1', 'q3', 'q2', 'q4']);
      expect(payload['todo_top3_1_id'], 'q1');
      expect(payload['todo_top3_2_id'], 'q3');
      expect(payload['todo_top3_3_id'], 'q2');
      expect(payload['todo_top3_count'], 4);
      expect(
        buildHomeWidgetTodoItems(todos.todos, now: DateTime.now()).length,
        4,
      );
    });
  });
}

const Set<String> _switchableHosts = <String>{
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
