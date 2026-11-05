import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/services/focus_timer_notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 专注通知按钮的真实链路：Provider 同步 → 原生按钮 URI → Dart 解析 →
/// 复用 `applyWidgetControl` 的 session/revision/state 校验。
const _brand = FocusTimerNotificationBrand(
  appTitle: '多仪',
  focusLabel: '专注中',
  shortBreakLabel: '短休息',
  longBreakLabel: '长休息',
  pausedLabel: '已暂停',
  noTaskLabel: '无关联任务',
  channelName: '专注计时',
  remainingLabel: '剩余',
  elapsedLabel: '已计时',
  startActionLabel: '开始',
  pauseActionLabel: '暂停',
  resetActionLabel: '重置',
  accentColorArgb: 0xFFC85656,
);

const MethodChannel _focusChannel = MethodChannel('duoyi/focus_timer');

final List<MethodCall> _focusCalls = <MethodCall>[];

Future<Object?> _handleFocusCall(MethodCall call) async {
  _focusCalls.add(call);
  return null;
}

List<Map<String, dynamic>> _syncPayloads() => <Map<String, dynamic>>[
  for (final call in _focusCalls)
    if (call.method == 'sync' && call.arguments is Map)
      Map<String, dynamic>.from(call.arguments as Map),
];

Map<String, dynamic> _lastSync() => _syncPayloads().last;

bool _stoppedNotification() =>
    _focusCalls.isNotEmpty && _focusCalls.last.method == 'stop';

Future<PomodoroProvider> _pomodoro() async {
  final provider = PomodoroProvider();
  await provider.loadFromStorage();
  addTearDown(provider.dispose);
  return provider;
}

/// 模拟原生按钮：用当前绑定拼出与 `FocusTimerNotificationModel.controlUri` 相同的 URI。
String _controlUri(String action, Map<String, dynamic> sync) =>
    'duoyi://focus-timer/$action'
    '?session=${sync['controlSessionId']}'
    '&revision=${sync['controlRevision']}'
    '&state=${sync['controlState']}';

Future<bool> _applyNotificationControl(
  PomodoroProvider provider,
  Map<String, dynamic> sync,
  String action,
) async {
  final control = FocusTimerNotificationControl.parse(
    Uri.parse(_controlUri(action, sync)),
  );
  expect(control, isNotNull, reason: 'native URI must parse: $action');
  return provider.applyWidgetControl(
    action: control!.action,
    sessionId: control.sessionId,
    revision: control.revision,
    expectedState: control.expectedState,
  );
}

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
    _focusCalls.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_focusChannel, _handleFocusCall);
    FocusTimerNotificationService.instance.setBrand(_brand);
  });

  tearDown(() async {
    await FocusTimerNotificationService.instance.stop();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_focusChannel, null);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalTimezoneResolver.init();
  });

  test('运行态同步携带 canonical 锚点与真实控制身份', () async {
    final provider = await _pomodoro();
    provider.setTaskName('整理周报');
    provider.startIfIdle();
    await pumpEventQueue();

    final sync = _lastSync();
    expect(sync['paused'], isFalse);
    expect(sync['isCountUp'], isFalse);
    expect(sync['taskLabel'], '整理周报');
    // 倒计时锚点是 Provider 的 canonical 结束时刻，而不是 now + 剩余。
    expect(sync['anchorMillis'], provider.focusTimerAnchorMillis);
    expect(
      sync['anchorMillis'] as int,
      greaterThan(DateTime.now().millisecondsSinceEpoch),
    );
    expect(sync['controlSessionId'], provider.focusControlSessionId);
    expect(sync['controlRevision'], provider.focusControlRevision);
    expect(sync['controlState'], 'running');
    // 锚点与“此刻 + 剩余”一致（不是 now + 上次剩余的重算漂移）。
    final now = DateTime.now().millisecondsSinceEpoch;
    expect(
      (sync['anchorMillis'] as int) - now,
      closeTo(sync['remainingMillis'] as int, 5000),
    );
  });

  test('正计时同步把开始时刻作为锚点，且不显示进度', () async {
    final provider = await _pomodoro();
    provider.setCountUpMode(true);
    provider.startIfIdle();
    await pumpEventQueue();

    final sync = _lastSync();
    expect(sync['isCountUp'], isTrue);
    expect(sync['progressPermille'], 0);
    expect(sync['controlState'], 'running');
    final anchor = sync['anchorMillis'] as int;
    expect(anchor, greaterThan(0));
    expect(anchor, provider.focusTimerAnchorMillis);
    // 正计时锚点在“现在”之前（已计时从 0 起算，不会虚构剩余）。
    expect(anchor, lessThanOrEqualTo(DateTime.now().millisecondsSinceEpoch));
  });

  test('暂停同步清空锚点、冻结剩余并保留暂停绑定', () async {
    final provider = await _pomodoro();
    provider.startIfIdle();
    await pumpEventQueue();
    final running = _lastSync();

    expect(await _applyNotificationControl(provider, running, 'pause'), isTrue);
    await pumpEventQueue();

    final paused = _lastSync();
    expect(paused['paused'], isTrue);
    expect(paused['anchorMillis'], 0);
    expect(paused['controlState'], 'paused');
    expect(paused['controlSessionId'], running['controlSessionId']);
    expect(paused['remainingMillis'], provider.state.remainingSeconds * 1000);
    expect(
      paused['controlRevision'],
      greaterThan(running['controlRevision'] as int),
    );
    // 暂停不应保留会继续走的原始锚点。
    expect(provider.focusTimerAnchorMillis, 0);
  });

  test('通知按钮 pause → start 延续同一任务、相位与剩余，不新建会话', () async {
    final provider = await _pomodoro();
    provider.setTaskName('阅读');
    provider.startIfIdle();
    await pumpEventQueue();
    final session = provider.focusControlSessionId;
    final phase = provider.state.type;

    expect(
      await _applyNotificationControl(provider, _lastSync(), 'pause'),
      isTrue,
    );
    await pumpEventQueue();
    final paused = _lastSync();
    final remaining = provider.state.remainingSeconds;
    final total = provider.state.totalSeconds;
    expect(remaining, greaterThan(0));

    // 暂停态通知只提供“开始/重置”；开始必须回到运行态同一会话。
    expect(await _applyNotificationControl(provider, paused, 'start'), isTrue);
    await pumpEventQueue();

    expect(provider.state.isRunning, isTrue);
    expect(provider.focusControlSessionId, session);
    expect(provider.state.taskName, '阅读');
    expect(provider.state.type, phase);
    expect(provider.state.remainingSeconds, remaining);
    expect(provider.state.totalSeconds, total);
    // 续跑不是新的完成记录，也不是新会话。
    expect(provider.sessions, isEmpty);
    final resumed = _lastSync();
    expect(resumed['paused'], isFalse);
    expect(resumed['controlState'], 'running');
    expect(resumed['controlSessionId'], session);
    expect(resumed['anchorMillis'], greaterThan(0));
  });

  test('重新加载暂停会话后恢复通知并可继续原任务', () async {
    final first = PomodoroProvider();
    late final Map<String, dynamic> paused;
    try {
      await first.loadFromStorage();
      first.setTaskName('重启后继续阅读');
      first.startIfIdle();
      await pumpEventQueue();
      expect(
        await _applyNotificationControl(first, _lastSync(), 'pause'),
        isTrue,
      );
      await first.flushPersistence();
      await pumpEventQueue();
      paused = _lastSync();
    } finally {
      first.dispose();
    }
    await pumpEventQueue();

    final restored = await _pomodoro();
    await pumpEventQueue();
    expect(restored.isPaused, isTrue);
    expect(restored.state.isRunning, isFalse);
    expect(restored.state.taskName, '重启后继续阅读');
    expect(restored.focusControlSessionId, paused['controlSessionId']);
    expect(restored.focusControlRevision, paused['controlRevision']);
    expect(restored.state.remainingSeconds * 1000, paused['remainingMillis']);
    final restoredNotification = _lastSync();
    expect(restoredNotification['paused'], isTrue);
    expect(restoredNotification['controlState'], 'paused');
    expect(restoredNotification['anchorMillis'], 0);
    expect(
      await _applyNotificationControl(restored, restoredNotification, 'start'),
      isTrue,
    );
    expect(restored.isPaused, isFalse);
    expect(restored.state.isRunning, isTrue);
    expect(restored.state.taskName, '重启后继续阅读');
    expect(restored.state.remainingSeconds * 1000, paused['remainingMillis']);
    expect(restored.sessions, isEmpty);
  });

  test('通知重置回满时长、不产生完成记录，并清理原生通知', () async {
    final provider = await _pomodoro();
    provider.setTaskName('工作');
    provider.startIfIdle();
    await pumpEventQueue();
    final sync = _lastSync();

    expect(await _applyNotificationControl(provider, sync, 'reset'), isTrue);
    await pumpEventQueue();

    expect(provider.state.isRunning, isFalse);
    expect(provider.isPaused, isFalse);
    expect(provider.state.type, PomodoroType.focus);
    expect(provider.state.remainingSeconds, provider.config.focusDuration);
    expect(provider.state.completedSessions, 0);
    expect(provider.sessions, isEmpty);
    expect(provider.sessionCountToday, 0);
    expect(provider.focusTimerState, PomodoroWidgetTimerState.idle);
    // 新 idle 身份：旧通知按钮立刻失效。
    expect(provider.focusControlSessionId, isNot(sync['controlSessionId']));
    expect(provider.focusControlRevision, 0);
    expect(_stoppedNotification(), isTrue);
  });

  test('旧 revision 与重复重置被拒绝，且不重复记惩罚', () async {
    final provider = await _pomodoro();
    provider.startIfIdle();
    await pumpEventQueue();
    final sync = _lastSync();

    expect(await _applyNotificationControl(provider, sync, 'reset'), isTrue);
    await pumpEventQueue();
    final resetPenalties = provider.penalties
        .where((penalty) => penalty.reason == FocusPenaltyReason.reset)
        .length;

    // 陈旧按钮（同一 session/revision/state）再点一次：无状态变化、无重复惩罚。
    expect(await _applyNotificationControl(provider, sync, 'reset'), isFalse);
    await pumpEventQueue();
    expect(provider.state.isRunning, isFalse);
    expect(provider.sessions, isEmpty);
    expect(
      provider.penalties
          .where((penalty) => penalty.reason == FocusPenaltyReason.reset)
          .length,
      resetPenalties,
    );
  });

  test('跨会话或状态不符的通知按钮被拒绝且不改状态', () async {
    final provider = await _pomodoro();
    provider.startIfIdle();
    await pumpEventQueue();
    final running = _lastSync();

    // 别的会话号（例如另一个账号/旧安装残留的通知）。
    final foreign = FocusTimerNotificationControl.parse(
      Uri.parse(
        'duoyi://focus-timer/pause?session=focus-999999&revision='
        '${running['controlRevision']}&state=running',
      ),
    )!;
    expect(
      await provider.applyWidgetControl(
        action: foreign.action,
        sessionId: foreign.sessionId,
        revision: foreign.revision,
        expectedState: foreign.expectedState,
      ),
      isFalse,
    );
    // 状态不符：运行中却发 paused 的“开始”。
    final staleState = FocusTimerNotificationControl.parse(
      Uri.parse(
        _controlUri(
          'pause',
          running,
        ).replaceFirst('state=running', 'state=paused'),
      ),
    );
    expect(staleState, isNull);
    expect(provider.state.isRunning, isTrue);
    expect(provider.focusControlSessionId, running['controlSessionId']);
  });

  test('暂停态的 pause 深链在解析阶段即被拒绝（动作与状态不匹配）', () {
    expect(
      FocusTimerNotificationControl.parse(
        Uri.parse(
          'duoyi://focus-timer/pause?session=focus-1&revision=2&state=paused',
        ),
      ),
      isNull,
    );
    expect(
      FocusTimerNotificationControl.parse(
        Uri.parse(
          'duoyi://focus-timer/start?session=focus-1&revision=2&state=running',
        ),
      ),
      isNull,
    );
  });
}
