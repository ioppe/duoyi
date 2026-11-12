import 'dart:convert';

import 'package:duoyi/models/focus_runtime.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _t0 = 1700000000000;

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

  @override
  void requestRefresh() {}

  @override
  Future<bool> send(
    FocusRuntimeAction action, {
    Map<String, dynamic>? payload,
  }) async {
    actions.add(action);
    lastPayload = payload;
    return true;
  }
}

FocusRuntimeSnapshot _idleSnapshot({int revision = 4}) => FocusRuntimeSnapshot(
  serverNowMs: _t0,
  runtime: FocusRuntimeState(
    sessionId: 'shared',
    revision: revision,
    status: FocusRuntimeStatus.idle,
    mode: FocusRuntimeMode.countdown,
    phase: FocusRuntimePhase.focus,
    durationMs: 1500000,
    elapsedMs: 0,
    anchorAtMs: null,
    startedAtMs: _t0,
    sourceDeviceId: 'desktop',
    taskName: null,
  ),
);

class _FailingConfigStore extends InMemorySharedPreferencesStore {
  _FailingConfigStore({required this.throwOnFailure})
    : super.withData(<String, Object>{});

  final bool throwOnFailure;
  bool failWrites = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (failWrites && key == 'flutter.pomodoro_config') {
      return throwOnFailure
          ? Future<bool>.error(StateError('storage failed'))
          : Future<bool>.value(false);
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<PomodoroProvider> loadedProvider() async {
    final provider = PomodoroProvider();
    addTearDown(provider.dispose);
    await provider.loadFromStorage();
    return provider;
  }

  Future<Map<String, dynamic>?> storedConfigJson() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('pomodoro_config');
    return raw == null ? null : json.decode(raw) as Map<String, dynamic>;
  }

  test('updateRestSettings persists choices and keeps other fields', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pomodoro_config': json.encode(
        PomodoroConfig(
          focusDuration: 1800,
          shortBreakDuration: 420,
          longBreakDuration: 1200,
          sessionsPerLongBreak: 3,
          whiteNoiseSound: 'rain',
          autoEnableDnd: true,
          strictFocusMode: true,
          monitorDistractingApps: true,
          distractingAppPackages: const ['com.tencent.mm'],
          distractingAppSelectionMode: PomodoroConfig.distractionModeWhitelist,
          focusRoomId: 'deep_work_room',
          focusSoundVolume: 0.8,
          playSoundInBreak: true,
        ).toJson(),
      ),
    });
    final provider = await loadedProvider();
    final revision = provider.persistedRevision;

    final ok = await provider.updateRestSettings(
      shortBreakDuration: 600,
      longBreakDuration: 1500,
      sessionsPerLongBreak: 5,
      linkShortBreakToFocus: false,
      autoStartBreaks: true,
      autoStartFocus: true,
      expectedStorageGeneration: provider.configStorageGeneration,
    );

    expect(ok, isTrue);
    expect(provider.persistedRevision, revision + 1);
    final config = provider.config;
    expect(config.shortBreakDuration, 600);
    expect(config.longBreakDuration, 1500);
    expect(config.sessionsPerLongBreak, 5);
    expect(config.linkShortBreakToFocus, isFalse);
    expect(config.autoStartBreaks, isTrue);
    expect(config.autoStartFocus, isTrue);
    // 未请求的字段保持最新配置里的原值（不是旧模态快照）。
    expect(config.focusDuration, 1800);
    expect(config.whiteNoiseSound, 'rain');
    expect(config.autoEnableDnd, isTrue);
    expect(config.strictFocusMode, isTrue);
    expect(config.monitorDistractingApps, isTrue);
    expect(config.distractingAppPackages, ['com.tencent.mm']);
    expect(
      config.distractingAppSelectionMode,
      PomodoroConfig.distractionModeWhitelist,
    );
    expect(config.focusRoomId, 'deep_work_room');
    expect(config.focusSoundVolume, 0.8);
    expect(config.playSoundInBreak, isTrue);

    final stored = await storedConfigJson();
    expect(stored, isNotNull);
    expect(stored!['shortBreakDuration'], 600);
    expect(stored['longBreakDuration'], 1500);
    expect(stored['sessionsPerLongBreak'], 5);
    expect(stored['autoStartBreaks'], isTrue);
    expect(stored['autoStartFocus'], isTrue);
    expect(stored['whiteNoiseSound'], 'rain');
  });

  test('linked rest settings derive short break from latest focus', () async {
    final provider = await loadedProvider();
    await provider.setConfig(
      PomodoroConfig(
        focusDuration: 1800,
        shortBreakDuration: 420,
        whiteNoiseSound: 'forest',
      ),
    );

    final ok = await provider.updateRestSettings(
      shortBreakDuration: 60,
      longBreakDuration: 900,
      sessionsPerLongBreak: 4,
      linkShortBreakToFocus: true,
      autoStartBreaks: false,
      autoStartFocus: false,
      expectedStorageGeneration: provider.configStorageGeneration,
    );

    expect(ok, isTrue);
    // 30 分钟专注 → 6 分钟短休，忽略传入的旧选项。
    expect(provider.config.shortBreakDuration, 360);
    expect(provider.config.linkShortBreakToFocus, isTrue);
    final stored = await storedConfigJson();
    expect(stored!['shortBreakDuration'], 360);
    expect(stored['linkShortBreakToFocus'], isTrue);
  });

  test('invalid durations or session counts are rejected', () async {
    final provider = await loadedProvider();
    final revision = provider.persistedRevision;
    final generation = provider.configStorageGeneration;

    Future<bool> attempt({
      int shortBreakDuration = 600,
      int longBreakDuration = 900,
      int sessionsPerLongBreak = 4,
    }) => provider.updateRestSettings(
      shortBreakDuration: shortBreakDuration,
      longBreakDuration: longBreakDuration,
      sessionsPerLongBreak: sessionsPerLongBreak,
      linkShortBreakToFocus: false,
      autoStartBreaks: false,
      autoStartFocus: false,
      expectedStorageGeneration: generation,
    );

    expect(await attempt(shortBreakDuration: 59), isFalse);
    expect(await attempt(shortBreakDuration: 43201), isFalse);
    expect(await attempt(longBreakDuration: 0), isFalse);
    expect(await attempt(longBreakDuration: 43201), isFalse);
    expect(await attempt(sessionsPerLongBreak: 0), isFalse);
    expect(await attempt(sessionsPerLongBreak: 21), isFalse);
    expect(provider.config.shortBreakDuration, 300);
    expect(provider.persistedRevision, revision);
    expect(await storedConfigJson(), isNull);
  });

  test('stale generation is rejected before any mutation', () async {
    final provider = await loadedProvider();
    final generation = provider.configStorageGeneration;

    final ok = await provider.updateRestSettings(
      shortBreakDuration: 600,
      longBreakDuration: 900,
      sessionsPerLongBreak: 4,
      linkShortBreakToFocus: false,
      autoStartBreaks: false,
      autoStartFocus: false,
      expectedStorageGeneration: generation - 1,
    );

    expect(ok, isFalse);
    expect(provider.config.shortBreakDuration, 300);
    expect(await storedConfigJson(), isNull);
  });

  test('account reset during save drops the late config write', () async {
    final provider = await loadedProvider();
    final generation = provider.configStorageGeneration;

    final pending = provider.updateRestSettings(
      shortBreakDuration: 600,
      longBreakDuration: 900,
      sessionsPerLongBreak: 4,
      linkShortBreakToFocus: false,
      autoStartBreaks: false,
      autoStartFocus: false,
      expectedStorageGeneration: generation,
    );
    // 写入 await 期间切换账号：代际推进，旧账号的写入必须失效。
    provider.resetLocalState();

    expect(await pending, isFalse);
    expect(provider.configStorageGeneration, greaterThan(generation));
    expect(provider.config.shortBreakDuration, 300);
    expect(await storedConfigJson(), isNull);
  });

  for (final throwing in <bool>[false, true]) {
    test('failed storage ($throwing) keeps previous rest settings', () async {
      final store = _FailingConfigStore(throwOnFailure: throwing);
      SharedPreferencesStorePlatform.instance = store;
      final provider = await loadedProvider();
      await provider.setConfig(PomodoroConfig(shortBreakDuration: 420));
      final revision = provider.persistedRevision;
      store.failWrites = true;

      await expectLater(
        provider.updateRestSettings(
          shortBreakDuration: 600,
          longBreakDuration: 1800,
          sessionsPerLongBreak: 6,
          linkShortBreakToFocus: false,
          autoStartBreaks: true,
          autoStartFocus: true,
          expectedStorageGeneration: provider.configStorageGeneration,
        ),
        throwsStateError,
      );

      expect(provider.config.shortBreakDuration, 420);
      expect(provider.config.longBreakDuration, 900);
      expect(provider.config.autoStartBreaks, isFalse);
      expect(provider.persistedRevision, revision);
      expect((await storedConfigJson())!['shortBreakDuration'], 420);
      await provider.loadFromStorage();
      expect(provider.config.shortBreakDuration, 420);
    });
  }

  test('running, paused and break state survive rest edits', () async {
    final provider = await loadedProvider();
    provider.setTaskName('Deep work');
    provider.startIfIdle();
    expect(provider.state.isRunning, isTrue);
    final runningRemaining = provider.state.remainingSeconds;
    final runningTotal = provider.state.totalSeconds;

    expect(
      await provider.updateRestSettings(
        shortBreakDuration: 600,
        longBreakDuration: 1500,
        sessionsPerLongBreak: 5,
        linkShortBreakToFocus: false,
        autoStartBreaks: true,
        autoStartFocus: true,
        expectedStorageGeneration: provider.configStorageGeneration,
      ),
      isTrue,
    );
    expect(provider.state.isRunning, isTrue);
    expect(provider.isPaused, isFalse);
    expect(provider.state.type, PomodoroType.focus);
    expect(provider.state.remainingSeconds, runningRemaining);
    expect(provider.state.totalSeconds, runningTotal);
    expect(provider.state.taskName, 'Deep work');

    provider.toggleTimer();
    expect(provider.state.isRunning, isFalse);
    expect(provider.isPaused, isTrue);
    final pausedRemaining = provider.state.remainingSeconds;

    expect(
      await provider.updateRestSettings(
        shortBreakDuration: 900,
        longBreakDuration: 1800,
        sessionsPerLongBreak: 3,
        linkShortBreakToFocus: false,
        autoStartBreaks: false,
        autoStartFocus: false,
        expectedStorageGeneration: provider.configStorageGeneration,
      ),
      isTrue,
    );
    expect(provider.isPaused, isTrue);
    expect(provider.state.isRunning, isFalse);
    expect(provider.state.type, PomodoroType.focus);
    expect(provider.state.remainingSeconds, pausedRemaining);
    expect(provider.state.taskName, 'Deep work');

    provider.skipSession();
    expect(provider.state.type, PomodoroType.shortBreak);
    final breakRemaining = provider.state.remainingSeconds;
    expect(breakRemaining, 900);

    expect(
      await provider.updateRestSettings(
        shortBreakDuration: 1200,
        longBreakDuration: 2400,
        sessionsPerLongBreak: 2,
        linkShortBreakToFocus: false,
        autoStartBreaks: false,
        autoStartFocus: false,
        expectedStorageGeneration: provider.configStorageGeneration,
      ),
      isTrue,
    );
    expect(provider.state.type, PomodoroType.shortBreak);
    expect(provider.state.remainingSeconds, breakRemaining);
    expect(provider.state.isRunning, isFalse);
    expect(provider.state.taskName, 'Deep work');
  });

  test(
    'remote mode edit sends no commands and next start carries rest',
    () async {
      final provider = await loadedProvider();
      final controller = _Controller();
      provider.attachFocusRuntimeController(controller);
      await provider.prepareRemoteHistory();
      final snapshot = _idleSnapshot();
      controller.snapshot = snapshot;
      // The result reports inserted history; an idle snapshot has no record.
      provider.applyRemoteSnapshot(snapshot);
      expect(provider.focusControlSessionId, 'shared');
      expect(provider.focusControlRevision, 4);
      final widgetRevision = provider.focusControlRevision;
      final stateBefore = provider.state;

      final ok = await provider.updateRestSettings(
        shortBreakDuration: 720,
        longBreakDuration: 1800,
        sessionsPerLongBreak: 6,
        linkShortBreakToFocus: false,
        autoStartBreaks: true,
        autoStartFocus: false,
        expectedStorageGeneration: provider.configStorageGeneration,
      );

      expect(ok, isTrue);
      // 保存设置不产生任何远端计时命令，也不改变运行态或控制身份。
      expect(controller.actions, isEmpty);
      expect(provider.focusControlRevision, widgetRevision);
      expect(provider.state.type, stateBefore.type);
      expect(provider.state.remainingSeconds, stateBefore.remainingSeconds);
      expect(provider.state.isRunning, stateBefore.isRunning);
      expect(provider.state.taskName, stateBefore.taskName);
      expect((await storedConfigJson())!['shortBreakDuration'], 720);

      provider.startIfIdle();
      expect(controller.actions, [FocusRuntimeAction.start]);
      final payloadConfig =
          controller.lastPayload!['config'] as Map<String, dynamic>;
      expect(payloadConfig['shortBreakDuration'], 720);
      expect(payloadConfig['longBreakDuration'], 1800);
      expect(payloadConfig['sessionsPerLongBreak'], 6);
      expect(payloadConfig['autoStartBreaks'], isTrue);
      expect(payloadConfig['linkShortBreakToFocus'], isFalse);
    },
  );

  group('按需水合（快速重启后进入专注页）', () {
    test('成功加载后再 prepare 不重读存储、不重置任务与配置', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'pomodoro_config': json.encode(
          PomodoroConfig(
            shortBreakDuration: 420,
            longBreakDuration: 1200,
            sessionsPerLongBreak: 3,
            autoStartBreaks: true,
          ).toJson(),
        ),
      });
      final provider = await loadedProvider();
      expect(provider.storageHydrated, isTrue);
      provider.setTaskName('写代码');
      final revision = provider.persistedRevision;

      // 另一个写入方随后改了磁盘：同代际的 prepare 不得把新值读回来。
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'pomodoro_config',
        json.encode(PomodoroConfig(shortBreakDuration: 600).toJson()),
      );

      await provider.prepareRemoteHistory();
      await provider.prepareRemoteHistory();

      expect(provider.config.shortBreakDuration, 420);
      expect(provider.config.longBreakDuration, 1200);
      expect(provider.state.taskName, '写代码');
      expect(provider.persistedRevision, revision);
    });

    test('加载失败后允许重试，成功后同代际不再读盘', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'pomodoro_config': 'not-json',
      });
      final provider = PomodoroProvider();
      addTearDown(provider.dispose);

      await expectLater(
        provider.prepareRemoteHistory(),
        throwsA(isA<FormatException>()),
      );
      expect(provider.storageHydrated, isFalse);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'pomodoro_config',
        json.encode(
          PomodoroConfig(
            shortBreakDuration: 420,
            longBreakDuration: 1200,
            sessionsPerLongBreak: 3,
          ).toJson(),
        ),
      );
      await provider.prepareRemoteHistory();
      expect(provider.storageHydrated, isTrue);
      expect(provider.config.shortBreakDuration, 420);
      expect(provider.config.sessionsPerLongBreak, 3);
    });

    test('代际在加载途中推进时旧加载不会标记就绪', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'pomodoro_config': json.encode(
          PomodoroConfig(shortBreakDuration: 420).toJson(),
        ),
      });
      final provider = PomodoroProvider();
      addTearDown(provider.dispose);

      final pending = provider.prepareRemoteHistory();
      // 账号切换/重置：代际推进，在途的旧加载结果必须作废。
      provider.resetLocalState();
      await pending;

      expect(provider.storageHydrated, isFalse);
      expect(provider.config.shortBreakDuration, 300);

      await provider.prepareRemoteHistory();
      expect(provider.storageHydrated, isTrue);
      expect(provider.config.shortBreakDuration, 420);
    });
  });
}
