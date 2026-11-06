import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:duoyi/models/focus_runtime.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _t0 = 1700000000000;

class _Clock extends FocusRuntimeClock {
  int current = _t0;
  @override
  int get nowMs => current;
  @override
  void calibrate(int serverNowMs) => current = serverNowMs;
  @override
  void reset() => current = _t0;
}

class _Controller implements FocusRuntimeController {
  @override
  FocusSyncMode mode = FocusSyncMode.remote;
  @override
  bool ready = true;
  @override
  bool connected = true;
  @override
  bool busy = false;
  @override
  Object? error;
  @override
  String? deviceId = 'phone';
  @override
  FocusRuntimeSnapshot? snapshot;
  @override
  String? get runtimeSessionId => snapshot?.runtime.sessionId;
  @override
  int? get runtimeRevision => snapshot?.runtime.revision;
  final actions = <FocusRuntimeAction>[];
  Map<String, dynamic>? lastPayload;
  bool accept = true;
  int refreshes = 0;

  @override
  void requestRefresh() => refreshes++;
  @override
  Future<bool> send(
    FocusRuntimeAction action, {
    Map<String, dynamic>? payload,
  }) async {
    actions.add(action);
    lastPayload = payload;
    return accept;
  }
}

PomodoroSession _history(String id) => PomodoroSession(
  id: id,
  startTime: DateTime.utc(2026, 1, 1),
  endTime: DateTime.utc(2026, 1, 1, 0, 1),
  durationSeconds: 60,
  type: PomodoroType.focus,
);

FocusRuntimeSnapshot _snapshot({
  String id = 'shared',
  int revision = 4,
  FocusRuntimeStatus status = FocusRuntimeStatus.running,
  FocusRuntimeMode mode = FocusRuntimeMode.countdown,
  FocusRuntimePhase phase = FocusRuntimePhase.focus,
  int elapsedMs = 0,
  int durationMs = 60000,
  String? task = 'Server task',
  PomodoroSession? record,
}) => FocusRuntimeSnapshot(
  serverNowMs: _t0,
  runtime: FocusRuntimeState(
    sessionId: id,
    revision: revision,
    status: status,
    mode: mode,
    phase: phase,
    durationMs: durationMs,
    elapsedMs: elapsedMs,
    anchorAtMs: status.isRunning ? _t0 : null,
    startedAtMs: _t0,
    sourceDeviceId: 'desktop',
    taskName: task,
  ),
  lastSession: record?.toJson(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PomodoroProvider provider;
  late _Controller controller;
  late _Clock clock;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> mount(PomodoroProvider value) async {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.attachRootWidget(
      binding.wrapWithDefaultView(
        ChangeNotifierProvider<PomodoroProvider>(
          create: (_) => value,
          lazy: false,
          child: const SizedBox.shrink(),
        ),
      ),
    );
    await binding.pump();
  }

  Future<void> prepare() async {
    clock = _Clock();
    provider = PomodoroProvider(remoteClock: clock);
    controller = _Controller();
    await mount(provider);
    await provider.loadFromStorage();
    provider.attachFocusRuntimeController(controller);
    await provider.prepareRemoteHistory();
  }

  bool project(FocusRuntimeSnapshot snapshot) {
    controller.snapshot = snapshot;
    return provider.applyRemoteSnapshot(snapshot);
  }

  testWidgets('server anchor and monotonic ticks project countdown', (
    tester,
  ) async {
    await prepare();
    project(_snapshot(elapsedMs: 12000));
    expect(provider.state.remainingSeconds, 48);
    clock.current += 2000;
    await tester.pump(const Duration(seconds: 2));
    expect(provider.state.remainingSeconds, 46);
    expect(provider.focusControlSessionId, 'shared');
    expect(provider.focusControlRevision, 4);
  });

  testWidgets('pause freezes elapsed time and resume preserves identity', (
    tester,
  ) async {
    await prepare();
    project(_snapshot(status: FocusRuntimeStatus.paused, elapsedMs: 15000));
    clock.current += 10000;
    await tester.pump(const Duration(seconds: 10));
    expect(provider.isPaused, isTrue);
    expect(provider.state.remainingSeconds, 45);
    provider.toggleTimer();
    await tester.pump();
    expect(controller.actions, [FocusRuntimeAction.resume]);
    expect(provider.isPaused, isTrue); // wait for server acknowledgement
    project(_snapshot(revision: 5, elapsedMs: 15000));
    expect(provider.focusControlSessionId, 'shared');
    expect(provider.isPaused, isFalse);
  });

  testWidgets('local expiry requests authority without creating completion', (
    tester,
  ) async {
    await prepare();
    project(_snapshot());
    clock.current += 61000;
    await tester.pump(const Duration(seconds: 61));
    expect(provider.state.remainingSeconds, 0);
    expect(provider.state.isRunning, isTrue);
    expect(provider.sessions, isEmpty);
    expect(controller.refreshes, greaterThan(0));
    expect(controller.actions, isEmpty);
  });

  testWidgets('older stage cannot replace newer session revision', (
    tester,
  ) async {
    await prepare();
    project(_snapshot(id: 'new-stage', revision: 8, task: 'New task'));
    project(
      _snapshot(
        id: 'old-stage',
        revision: 6,
        status: FocusRuntimeStatus.paused,
      ),
    );
    expect(provider.remoteFocusSessionId, 'new-stage');
    expect(provider.remoteFocusRevision, 8);
    expect(provider.state.taskName, 'New task');
    expect(provider.state.isRunning, isTrue);
  });

  testWidgets(
    'history reload preserves remote running ticker and pause state',
    (tester) async {
      await prepare();
      project(_snapshot(elapsedMs: 10000));
      await provider.loadFromStorage();
      clock.current += 2000;
      await tester.pump(const Duration(seconds: 2));
      expect(provider.state.remainingSeconds, 48);
      project(
        _snapshot(
          revision: 5,
          status: FocusRuntimeStatus.paused,
          elapsedMs: 12000,
        ),
      );
      await provider.loadFromStorage();
      expect(provider.isPaused, isTrue);
      expect(provider.focusTimerState, PomodoroWidgetTimerState.paused);
    },
  );

  testWidgets('bound widget controls use explicit remote commands only', (
    tester,
  ) async {
    await prepare();
    project(_snapshot());
    expect(
      await provider.applyWidgetControl(
        action: PomodoroWidgetControlAction.pause,
        sessionId: 'obsolete',
        revision: 4,
        expectedState: PomodoroWidgetTimerState.running,
      ),
      isFalse,
    );
    expect(
      await provider.applyWidgetControl(
        action: PomodoroWidgetControlAction.pause,
        sessionId: 'shared',
        revision: 4,
        expectedState: PomodoroWidgetTimerState.running,
      ),
      isTrue,
    );
    expect(controller.actions, [FocusRuntimeAction.pause]);
    expect(provider.state.isRunning, isTrue);
    controller.connected = false;
    provider.toggleTimer();
    await tester.pump();
    expect(controller.actions, hasLength(1));
    expect(provider.canControlFocus, isFalse);
  });

  testWidgets('reset skip and finish never settle locally in remote mode', (
    tester,
  ) async {
    await prepare();
    project(_snapshot());
    provider.resetTimer();
    provider.skipSession();
    provider.finishCurrentSession();
    await tester.pump();
    expect(controller.actions, [
      FocusRuntimeAction.reset,
      FocusRuntimeAction.skip,
      FocusRuntimeAction.finish,
    ]);
    expect(provider.sessions, isEmpty);
    expect(provider.state.isRunning, isTrue);
  });

  testWidgets('cold remote marker blocks an independent local timer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      PomodoroProvider.focusRemoteMarkerKey: true,
    });
    final cold = PomodoroProvider();
    await mount(cold);
    await cold.loadFromStorage();
    cold.toggleTimer();
    cold.startIfIdle();
    await tester.pump();
    expect(cold.focusSyncEnabled, isTrue);
    expect(cold.canControlFocus, isFalse);
    expect(cold.state.isRunning, isFalse);
  });

  testWidgets('remote upsert preserves history and honors local deletion', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'pomodoro_sessions': jsonEncode([_history('old').toJson()]),
    });
    await prepare();
    final snapshot = _snapshot(record: _history('server-completed'));
    expect(project(snapshot), isTrue);
    expect(project(snapshot), isFalse);
    expect(
      provider.sessions.map((s) => s.id),
      containsAll(['old', 'server-completed']),
    );
    await provider.deleteSession('server-completed');
    project(snapshot);
    expect(provider.sessions.map((s) => s.id), ['old']);
  });

  testWidgets('reset invalidates remote history writes already in flight', (
    tester,
  ) async {
    await prepare();
    project(_snapshot(record: _history('old-account')));
    provider.resetLocalState();
    await tester.pump();
    await provider.flushPersistence();
    expect(provider.sessions, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pomodoro_sessions'), isNull);
  });

  testWidgets('failed task update releases draft to authoritative task', (
    tester,
  ) async {
    await prepare();
    project(_snapshot());
    controller.accept = false;
    provider.setTaskName('Unsaved draft');
    await tester.pump();
    expect(controller.actions, [FocusRuntimeAction.update]);
    expect(provider.state.taskName, 'Server task');
  });

  testWidgets('new stage clears an idle local task draft', (tester) async {
    await prepare();
    project(_snapshot(status: FocusRuntimeStatus.idle));
    provider.setTaskName('Local draft');
    project(
      _snapshot(id: 'another-device-stage', revision: 5, task: 'Other device'),
    );
    expect(provider.state.taskName, 'Other device');
    expect(controller.actions, isEmpty);
  });

  testWidgets(
    'idle countup selection preserves server binding and survives refresh',
    (tester) async {
      await prepare();
      final idle = _snapshot(
        status: FocusRuntimeStatus.idle,
        phase: FocusRuntimePhase.shortBreak,
      );
      project(idle);
      provider.setCountUpMode(true);
      project(idle);
      expect(provider.state.isCountUp, isTrue);
      expect(provider.state.type, PomodoroType.focus);
      expect(provider.focusControlSessionId, 'shared');
      expect(provider.focusControlRevision, 4);
      provider.toggleTimer();
      await tester.pump();
      expect(controller.actions, [FocusRuntimeAction.start]);
      expect(controller.lastPayload?['mode'], 'countup');
      expect(controller.lastPayload?['phase'], 'focus');
    },
  );

  testWidgets(
    'idle duration selection previews config without changing binding',
    (tester) async {
      await prepare();
      final idle = _snapshot(status: FocusRuntimeStatus.idle);
      project(idle);
      provider.setCountUpMode(false);
      await provider.setConfig(PomodoroConfig(focusDuration: 900));
      project(idle);
      expect(provider.state.remainingSeconds, 900);
      expect(provider.state.totalSeconds, 900);
      expect(provider.focusControlSessionId, 'shared');
      expect(provider.focusControlRevision, 4);
      provider.toggleTimer();
      await tester.pump();
      expect((controller.lastPayload?['config'] as Map)['focusDuration'], 900);
    },
  );
}
