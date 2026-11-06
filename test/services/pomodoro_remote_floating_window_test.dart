import 'dart:async';

import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/services/pomodoro_floating_window_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RemoteProvider extends PomodoroProvider {
  PomodoroState _rendered = const PomodoroState(
    remainingSeconds: 1500,
    totalSeconds: 1500,
    isRunning: false,
    type: PomodoroType.focus,
    completedSessions: 0,
  );
  String? session;
  int revision = 0;
  bool paused = false;
  bool connected = true;
  bool busy = false;
  int toggles = 0;

  @override
  PomodoroState get state => _rendered;
  @override
  bool get focusSyncEnabled => true;
  @override
  bool get focusSyncReady => true;
  @override
  bool get focusSyncConnected => connected;
  @override
  bool get focusSyncBusy => busy;
  @override
  bool get canControlFocus => connected && !busy;
  @override
  String? get remoteFocusSessionId => session;
  @override
  int? get remoteFocusRevision => revision;
  @override
  String get focusControlSessionId => session ?? 'idle';
  @override
  int get focusControlRevision => revision;
  @override
  bool get isPaused => paused;
  @override
  PomodoroWidgetTimerState get focusTimerState => paused
      ? PomodoroWidgetTimerState.paused
      : _rendered.isRunning
      ? PomodoroWidgetTimerState.running
      : PomodoroWidgetTimerState.idle;

  void project(
    String id,
    int rev, {
    bool running = true,
    bool isPaused = false,
  }) {
    session = id;
    revision = rev;
    paused = isPaused;
    _rendered = _rendered.copyWith(isRunning: running);
    notifyListeners();
  }

  @override
  void toggleTimer() => toggles++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/remote-floating');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _RemoteProvider provider;
  late PomodoroFloatingWindowService service;
  late List<MethodCall> calls;
  Completer<void>? showGate;

  void configure(bool available) => service.configure(
    available: available,
    sessionIdentity: 'server|account',
    windowTitle: 'Focus',
    playLabel: 'Start',
    pauseLabel: 'Pause',
    closeLabel: 'Close',
  );
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  Iterable<MethodCall> shows() => calls.where((c) => c.method == 'show');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    showGate = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'show') await showGate?.future;
      return null;
    });
    provider = _RemoteProvider();
    service = PomodoroFloatingWindowService(supported: true, channel: channel);
    service.attach(provider);
    configure(true);
  });
  tearDown(() {
    service.dispose();
    provider.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'new remote session opens once; close suppresses the same session',
    () async {
      provider.project('focus-1', 1);
      await settle();
      expect(service.isVisible, isTrue);
      expect(shows(), hasLength(1));

      await service.handleNativeCall(const MethodCall('closed'));
      provider.project('focus-1', 2, running: false, isPaused: true);
      provider.project('focus-1', 3);
      await settle();
      expect(service.isVisible, isFalse);
      expect(shows(), hasLength(1));

      provider.project('focus-2', 4);
      await settle();
      expect(service.isVisible, isTrue);
      expect(shows(), hasLength(2));
    },
  );

  test('manual hide and a tick do not reopen a remote session', () async {
    provider.project('focus-1', 1);
    await settle();
    await service.hide();
    provider.project('focus-1', 2);
    await settle();
    expect(service.isVisible, isFalse);
    expect(shows(), hasLength(1));
  });

  test(
    'native click is bound to displayed session/revision and connection',
    () async {
      provider.project('focus-1', 1);
      await settle();
      await service.handleNativeCall(
        const MethodCall('toggle', {
          'sessionId': 'old-focus',
          'revision': 1,
          'state': 'running',
        }),
      );
      await service.handleNativeCall(
        const MethodCall('toggle', {
          'sessionId': 'focus-1',
          'revision': 0,
          'state': 'running',
        }),
      );
      await service.handleNativeCall(const MethodCall('toggle'));
      expect(provider.toggles, 0);

      const valid = MethodCall('toggle', {
        'sessionId': 'focus-1',
        'revision': 1,
        'state': 'running',
      });
      await service.handleNativeCall(valid);
      expect(provider.toggles, 1);
      provider.connected = false;
      provider.project('focus-1', 1);
      await settle();
      await service.handleNativeCall(valid);
      expect(provider.toggles, 1);
      final update = calls.lastWhere((c) => c.method == 'update');
      expect((update.arguments as Map)['canToggle'], isFalse);
    },
  );

  test(
    'locked session stays hidden after unlock; next session can open',
    () async {
      configure(false);
      provider.project('focus-1', 1);
      await settle();
      configure(true);
      await settle();
      expect(shows(), isEmpty);
      provider.project('focus-2', 2);
      await settle();
      expect(shows(), hasLength(1));
    },
  );

  test(
    'late auto-show result cannot restore a window hidden by a lock',
    () async {
      showGate = Completer<void>();
      provider.project('focus-1', 1);
      await settle();
      configure(false);
      showGate!.complete();
      await settle();
      expect(service.isVisible, isFalse);
      expect(calls.where((c) => c.method == 'hide'), isNotEmpty);
    },
  );
}
