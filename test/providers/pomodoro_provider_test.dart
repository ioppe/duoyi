import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('PomodoroProvider updates and deletes paired time audit records', () {
    final provider = File(
      'lib/providers/pomodoro_provider.dart',
    ).readAsStringSync();
    final model = File('lib/models/pomodoro.dart').readAsStringSync();
    final audit = File(
      'lib/providers/time_audit_provider.dart',
    ).readAsStringSync();

    expect(
      provider,
      contains('Future<bool> updateSession(PomodoroSession updated) async'),
    );
    expect(provider, contains('final previous = _sessions[idx];'));
    expect(provider, contains('_sessions[idx] = updated;'));
    expect(provider, contains('_affectsTodayFocusCount(previous)'));
    expect(provider, contains('_affectsTodayFocusCount(updated)'));
    expect(provider, contains('await _refreshTodayFocusMeta();'));
    expect(
      provider,
      contains(
        'final dedupeKey = TimeAuditProvider.pomodoroDedupeKey(updated.id);',
      ),
    );
    expect(provider, contains('await _timeAudit?.recordPomodoroSession('));
    expect(
      provider,
      contains('await _timeAudit?.deleteByDedupeKey(dedupeKey);'),
    );
    expect(provider, contains('await _saveSessions();'));
    expect(provider, contains('notifyListeners();'));

    expect(provider, contains('Future<bool> deleteSession(String id) async'));
    expect(provider, contains('await _timeAudit?.deleteByDedupeKey('));
    expect(provider, contains('TimeAuditProvider.pomodoroDedupeKey(id)'));
    expect(provider, contains('_sessionCountToday = _sessions'));

    expect(model, contains('PomodoroSession copyWith('));
    expect(model, contains('bool clearTaskName = false'));
    expect(model, contains('bool clearTag = false'));
    expect(model, contains('bool clearFocusRoomId = false'));

    expect(audit, contains('Future<void> recordPomodoroSession('));
    expect(audit, contains('dedupeKey: pomodoroDedupeKey(sessionId),'));
    expect(
      audit,
      contains('static String pomodoroDedupeKey(String sessionId)'),
    );
  });

  test('PomodoroProvider start/completion code guards timer handoff', () {
    final provider = File(
      'lib/providers/pomodoro_provider.dart',
    ).readAsStringSync();

    expect(provider, contains('if (_timer?.isActive ?? false)'));
    final activeTimerBranch = provider.substring(
      provider.indexOf('if (_timer?.isActive ?? false)'),
      provider.indexOf(
        'return;',
        provider.indexOf('if (_timer?.isActive ?? false)'),
      ),
    );
    expect(activeTimerBranch, contains('unawaited(_syncSoundToState());'));
    expect(activeTimerBranch, contains('_syncDndToState();'));
    expect(activeTimerBranch, contains('_syncDistractionMonitorToState();'));
    expect(provider, contains('final completedState = _state;'));
    expect(provider, contains('final completedType = completedState.type;'));
    expect(
      provider,
      contains(
        'final shouldAutoStartNext = completedType == PomodoroType.focus',
      ),
    );
    expect(provider, contains('? _config.autoStartBreaks'));
    expect(provider, contains(': _config.autoStartFocus'));
    // 写元数据前必须先按应用时区刷新“今天”，再用已刷新的键持久化，
    // 避免跨日/换时区后仍写入旧日期。
    expect(provider, contains('_lastDate = _todayKey();'));
    expect(provider, contains('final lastDate = _lastDate!;'));
    expect(
      provider,
      isNot(
        contains(
          'isRunning: _config.autoStartBreaks || _config.autoStartFocus',
        ),
      ),
    );
  });

  test('white-noise changes preview at full focus volume when idle', () {
    final provider = File(
      'lib/providers/pomodoro_provider.dart',
    ).readAsStringSync();

    expect(
      provider,
      contains(
        'Future<bool> setWhiteNoiseSound(String sound, {bool preview = true})',
      ),
    );
    expect(provider, isNot(contains('_soundPreviewGeneration')));
    expect(provider, contains('if (preview &&'));
    expect(provider, contains('normalized != FocusSoundCatalog.none'));
    expect(provider, contains('!_state.isRunning'));
    expect(provider, contains('_previewWhiteNoiseSound(normalized)'));
    expect(provider, contains('Future<bool> _previewWhiteNoiseSound'));
    expect(provider, contains('Future<bool> _syncSoundToState()'));
    expect(provider, contains('return _sound.preview(sound)'));
    expect(provider, contains('Future<bool> _playFocusSound(String sound)'));
    expect(provider, contains('_state.isRunning'));
    final setter = provider.substring(
      provider.indexOf(
        'Future<bool> setWhiteNoiseSound(String sound, {bool preview = true})',
      ),
      provider.indexOf('Future<bool> setFocusSoundVolume('),
    );
    expect(setter, contains('final playbackOk = await _syncSoundToState();'));
    expect(
      setter,
      matches(RegExp(r'if\s*\(\s*!playbackOk\s*&&\s*_state\.isRunning')),
    );
    expect(
      setter,
      contains('_config.whiteNoiseSound = FocusSoundCatalog.none;'),
    );
    expect(setter, isNot(contains('return _playFocusSound(normalized);')));
    expect(
      provider,
      contains('await _sound.setVolume(_config.focusSoundVolume)'),
    );
    expect(provider, contains('return _sound.play(sound)'));

    final service = File(
      'lib/services/focus_sound_service.dart',
    ).readAsStringSync();
    expect(service, contains('static const double defaultVolume = 1.0'));
    expect(service, contains('Future<bool> play(String sound)'));
    expect(service, contains('Future<bool> preview('));
    expect(service, contains('Future<void>.delayed(duration).then'));
    expect(service, contains('return false;'));
    expect(service, contains('if (assets.isEmpty)'));
    expect(
      service,
      contains('assets.map(AssetSource.new).toList(growable: false)'),
    );
  });

  test('focus sound volume setting previews current or fallback sound', () {
    final provider = File(
      'lib/providers/pomodoro_provider.dart',
    ).readAsStringSync();
    final screen = File('lib/screens/pomodoro_screen.dart').readAsStringSync();

    expect(provider, contains('Future<bool> setFocusSoundVolume('));
    expect(provider, contains('FocusSoundService.minimumAudibleVolume'));
    expect(provider, contains('_focusSoundPreviewFallback'));
    expect(provider, contains('FocusSoundCatalog.tracks.first.id'));
    expect(
      provider,
      contains('return _previewWhiteNoiseSound(_focusSoundPreviewFallback);'),
    );
    expect(screen, contains('ChoiceChip('));
    expect(screen, contains('.setFocusSoundVolume(value)'));
    expect(screen, contains('点击声音会自动试听，也可以先点试听确认音量。'));
    expect(screen, contains('final VoidCallback? onPreview;'));
    expect(screen, contains("tooltip: '试听'"));
    expect(screen, contains('onPreview: () async'));
    expect(screen, contains('专注声音试听启动失败，请检查系统音量或音频资源'));
  });

  test('goal focus noise choices preview and report failures', () {
    final goalEdit = File(
      'lib/screens/goal_edit_screen.dart',
    ).readAsStringSync();

    expect(
      goalEdit,
      contains("import '../services/focus_sound_service.dart';"),
    );
    expect(goalEdit, contains('Future<void> _pickFocusNoise(String id)'));
    expect(
      goalEdit,
      contains('context.read<PomodoroProvider?>()?.config.focusSoundVolume'),
    );
    expect(goalEdit, contains('FocusSoundService.defaultVolume'));
    expect(goalEdit, contains('FocusSoundService.instance.preview(id)'));
    expect(goalEdit, contains('专注声音预览启动失败'));
    expect(goalEdit, contains('onPickNoise: _pickFocusNoise'));
  });

  test('editing focus session sound also previews without saving globally', () {
    final screen = File('lib/screens/pomodoro_screen.dart').readAsStringSync();
    final editorStart = screen.indexOf(
      'Future<void> showPomodoroSessionEditor',
    );
    final screenStart = screen.indexOf('class PomodoroScreen', editorStart);
    expect(editorStart, greaterThanOrEqualTo(0));
    expect(screenStart, greaterThan(editorStart));
    final editor = screen.substring(editorStart, screenStart);

    expect(screen, contains("import '../services/focus_sound_service.dart';"));
    expect(editor, contains('Future<void> previewSound(String value)'));
    expect(editor, contains('setSt(() => selectedSound = value)'));
    expect(editor, contains('FocusSoundService.instance.stop()'));
    expect(editor, contains('provider.config.focusSoundVolume'));
    expect(editor, contains('FocusSoundService.instance.preview(value)'));
    expect(editor, contains('专注声音预览启动失败'));
    expect(editor, contains('previewSound(value ?? FocusSoundCatalog.none)'));
    expect(editor, isNot(contains('provider.setWhiteNoiseSound(')));
  });

  test('startIfIdle does not create duplicate active timers', () async {
    final provider = PomodoroProvider();
    await provider.setConfig(PomodoroConfig(focusDuration: 5));
    var listenerNotifications = 0;
    var timerTicks = 0;
    provider.addListener(() => listenerNotifications++);
    provider.timerTicks.addListener(() => timerTicks++);

    fakeAsync((async) {
      provider.startIfIdle();
      provider.startIfIdle();

      expect(provider.state.isRunning, isTrue);
      expect(async.periodicTimerCount, 1);
      expect(listenerNotifications, 1);

      async.elapse(const Duration(seconds: 1));
      expect(provider.state.remainingSeconds, 4);
      expect(async.periodicTimerCount, 1);
      expect(timerTicks, 1);
      expect(
        listenerNotifications,
        1,
        reason: 'second ticks must not rebuild the whole app shell',
      );

      provider.dispose();
      expect(async.periodicTimerCount, 0);
    });
  });

  test(
    'strict focus switch notifies before async persistence completes',
    () async {
      final provider = PomodoroProvider();
      var notifications = 0;
      provider.addListener(() => notifications++);

      final future = provider.setStrictFocusMode(true);

      expect(provider.config.strictFocusMode, isTrue);
      expect(notifications, 1);

      await future;
      provider.dispose();
    },
  );

  test(
    'focus room selection is idempotent to avoid room-tab flicker',
    () async {
      final provider = PomodoroProvider();
      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.setFocusRoomId('deep_work_room');
      final firstRevision = provider.persistedRevision;

      await provider.setFocusRoomId('deep_work_room');

      expect(provider.state.focusRoomId, 'deep_work_room');
      expect(provider.config.focusRoomId, 'deep_work_room');
      expect(provider.persistedRevision, firstRevision);
      expect(notifications, 1);

      provider.dispose();
    },
  );

  test('focus completion auto-starts break only when enabled', () async {
    final provider = PomodoroProvider();
    await provider.setConfig(
      PomodoroConfig(
        focusDuration: 1,
        shortBreakDuration: 5,
        autoStartBreaks: true,
        autoStartFocus: false,
      ),
    );

    fakeAsync((async) {
      provider.startIfIdle();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(provider.sessions, hasLength(1));
      expect(provider.sessions.single.type, PomodoroType.focus);
      expect(provider.state.type, PomodoroType.shortBreak);
      expect(provider.state.isRunning, isTrue);
      expect(provider.state.remainingSeconds, 5);
      expect(async.periodicTimerCount, 1);

      provider.dispose();
      expect(async.periodicTimerCount, 0);
    });
  });

  test(
    'manual focus start does not bounce into break when break auto-start is off',
    () async {
      final provider = PomodoroProvider();
      await provider.setConfig(
        PomodoroConfig(
          focusDuration: 1,
          shortBreakDuration: 5,
          autoStartBreaks: false,
          autoStartFocus: true,
        ),
      );

      fakeAsync((async) {
        provider.startIfIdle();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(provider.sessions, hasLength(1));
        expect(provider.sessions.single.type, PomodoroType.focus);
        expect(provider.state.type, PomodoroType.shortBreak);
        expect(provider.state.isRunning, isFalse);
        expect(async.periodicTimerCount, 0);

        provider.dispose();
      });
    },
  );

  test('break completion auto-starts focus only when enabled', () async {
    final provider = PomodoroProvider();
    await provider.setConfig(
      PomodoroConfig(
        focusDuration: 1,
        shortBreakDuration: 1,
        autoStartBreaks: false,
        autoStartFocus: true,
      ),
    );

    fakeAsync((async) {
      provider.startIfIdle();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(provider.state.type, PomodoroType.shortBreak);
      expect(provider.state.isRunning, isFalse);
      expect(async.periodicTimerCount, 0);

      provider.startIfIdle();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(provider.sessions, hasLength(2));
      expect(provider.sessions.last.type, PomodoroType.shortBreak);
      expect(provider.state.type, PomodoroType.focus);
      expect(provider.state.isRunning, isTrue);
      expect(provider.state.remainingSeconds, 1);
      expect(async.periodicTimerCount, 1);

      provider.dispose();
      expect(async.periodicTimerCount, 0);
    });
  });

  test(
    'break completion does not auto-start focus from stale autoStartBreaks flag',
    () async {
      final provider = PomodoroProvider();
      await provider.setConfig(
        PomodoroConfig(
          focusDuration: 1,
          shortBreakDuration: 1,
          autoStartBreaks: true,
          autoStartFocus: false,
        ),
      );

      fakeAsync((async) {
        provider.startIfIdle();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(provider.state.type, PomodoroType.shortBreak);
        expect(provider.state.isRunning, isTrue);
        expect(async.periodicTimerCount, 1);

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(provider.sessions, hasLength(2));
        expect(provider.sessions.last.type, PomodoroType.shortBreak);
        expect(provider.state.type, PomodoroType.focus);
        expect(provider.state.isRunning, isFalse);
        expect(async.periodicTimerCount, 0);

        provider.dispose();
      });
    },
  );

  group('session 有界增长与 isolate 编码持久化', () {
    PomodoroSession session(int i) {
      final start = DateTime(2026, 1, 1).add(Duration(minutes: 30 * i));
      return PomodoroSession(
        id: 'session-$i',
        startTime: start,
        endTime: start.add(const Duration(minutes: 25)),
        durationSeconds: 25 * 60,
        type: PomodoroType.focus,
      );
    }

    test('超过上限时丢弃最旧记录，保留最新 500 条并落盘', () async {
      final provider = PomodoroProvider();
      // 520 条 > _maxPomodoroSessions(500)，且达到 _isolateEncodeMinItems(500)
      // —— 持久化走 compute 后台 isolate 编码路径，一并覆盖。
      await provider.debugAddSessionsForTest([
        for (var i = 0; i < 520; i++) session(i),
      ]);

      expect(provider.sessions, hasLength(500));
      expect(provider.sessions.first.id, 'session-20', reason: '最旧的 20 条应被丢弃');
      expect(provider.sessions.last.id, 'session-519');

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('pomodoro_sessions');
      expect(stored, isNotNull);
      expect(
        jsonDecode(stored!) as List,
        hasLength(500),
        reason: '持久化内容应与内存裁剪结果一致',
      );
      provider.dispose();
    });

    test('未超上限时不裁剪，小列表走同步编码路径', () async {
      final provider = PomodoroProvider();
      await provider.debugAddSessionsForTest([
        session(1),
        session(2),
        session(3),
      ]);

      expect(provider.sessions, hasLength(3));
      expect(provider.sessions.first.id, 'session-1');

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('pomodoro_sessions');
      expect(stored, isNotNull);
      expect(jsonDecode(stored!) as List, hasLength(3));
      provider.dispose();
    });
  });

  group('运行态快照落盘与进程被杀重启恢复', () {
    Map<String, dynamic> snapshotPayload({
      required int endsAtMs,
      int totalSeconds = 1500,
      PomodoroType type = PomodoroType.focus,
      bool isCountUp = false,
      int completedSessions = 0,
      String? taskName,
      String? todoId,
      String? subtaskId,
      String? todoTitle,
    }) => <String, dynamic>{
      'isRunning': true,
      'type': type.index,
      'isCountUp': isCountUp,
      'totalSeconds': totalSeconds,
      'endsAtMs': endsAtMs,
      'completedSessions': completedSessions,
      'taskName': ?taskName,
      'todoId': ?todoId,
      'subtaskId': ?subtaskId,
      'todoTitle': ?todoTitle,
    };

    test('计时启动即落盘运行快照，暂停后清除', () async {
      final provider = PomodoroProvider();
      await provider.setConfig(PomodoroConfig(focusDuration: 60));

      fakeAsync((async) {
        provider.startIfIdle();
        async.flushMicrotasks();
        async.flushMicrotasks();

        Map<String, dynamic>? runningSnapshot;
        SharedPreferences.getInstance().then((prefs) {
          final raw = prefs.getString(PomodoroProvider.runningSnapshotKey);
          if (raw != null) {
            runningSnapshot = jsonDecode(raw) as Map<String, dynamic>;
          }
        });
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(runningSnapshot, isNotNull, reason: '运行中快照应随计时落盘');
        expect(runningSnapshot?['isRunning'], isTrue);
        expect(runningSnapshot?['type'], PomodoroType.focus.index);
        expect(runningSnapshot?['isCountUp'], isFalse);
        expect(runningSnapshot?['totalSeconds'], 60);
        final endsAtMs = runningSnapshot?['endsAtMs'] as int?;
        expect(endsAtMs, isNotNull);
        expect(
          endsAtMs!,
          greaterThan(DateTime.now().millisecondsSinceEpoch),
          reason: '倒计时锚点应为未来的结束时刻',
        );

        provider.toggleTimer(); // 暂停 → 快照应被清除
        async.flushMicrotasks();
        async.flushMicrotasks();

        String? afterPause;
        SharedPreferences.getInstance().then((prefs) {
          afterPause = prefs.getString(PomodoroProvider.runningSnapshotKey);
        });
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(afterPause, isNull, reason: '暂停后运行快照应被删除');

        provider.dispose();
      });
    });

    test('未逾期的进行中专注按剩余时间恢复计时', () async {
      final endsAtMs = DateTime.now()
          .add(const Duration(seconds: 10))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues(<String, Object>{
        PomodoroProvider.runningSnapshotKey: jsonEncode(
          snapshotPayload(
            endsAtMs: endsAtMs,
            completedSessions: 2,
            taskName: '写周报',
          ),
        ),
      });

      final provider = PomodoroProvider();
      fakeAsync((async) {
        unawaited(provider.loadFromStorage());
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(provider.state.isRunning, isTrue, reason: '未逾期应静默恢复运行');
        final restored = provider.state.remainingSeconds;
        expect(restored, inInclusiveRange(8, 10), reason: '按 endsAt-now 恢复');
        expect(provider.state.totalSeconds, 1500);
        expect(provider.state.type, PomodoroType.focus);
        expect(provider.state.isCountUp, isFalse);
        expect(provider.state.completedSessions, 2);
        expect(provider.state.taskName, '写周报');
        expect(provider.sessions, isEmpty, reason: '恢复不产生新结算');
        expect(async.periodicTimerCount, 1, reason: 'Timer 应已重启');

        async.elapse(const Duration(seconds: 2));
        expect(provider.state.remainingSeconds, restored - 2);

        provider.dispose();
      });
    });

    test('逾期恢复只结算一次：补一条 session 且不重复计次', () async {
      final endsAtMs = DateTime.now()
          .subtract(const Duration(seconds: 5))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues(<String, Object>{
        PomodoroProvider.runningSnapshotKey: jsonEncode(
          snapshotPayload(endsAtMs: endsAtMs),
        ),
      });

      final provider = PomodoroProvider();
      fakeAsync((async) {
        unawaited(provider.loadFromStorage());
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(provider.sessions, hasLength(1), reason: '逾期应补一条自然完成');
        expect(provider.sessions.single.type, PomodoroType.focus);
        expect(provider.sessions.single.durationSeconds, 1500);
        expect(provider.sessionCountToday, 1, reason: '当日计数 +1');
        // autoStartBreaks 默认 false：结算后停在 break 相位等待手动开始。
        expect(provider.state.type, PomodoroType.shortBreak);
        expect(provider.state.isRunning, isFalse);
        expect(async.periodicTimerCount, 0);

        String? snapshotAfterSettle;
        var persistedSessionCount = 0;
        SharedPreferences.getInstance().then((prefs) {
          snapshotAfterSettle = prefs.getString(
            PomodoroProvider.runningSnapshotKey,
          );
          final raw = prefs.getString('pomodoro_sessions');
          persistedSessionCount = raw == null
              ? 0
              : (jsonDecode(raw) as List).length;
        });
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(snapshotAfterSettle, isNull, reason: '结算后快照必须立即删除');
        expect(persistedSessionCount, 1);

        // 再次 loadFromStorage（等同又一次重启）：快照已删，不得重复结算。
        unawaited(provider.loadFromStorage());
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(provider.sessions, hasLength(1), reason: '只结算一次');
        expect(provider.sessionCountToday, 1, reason: '不重复计次');

        provider.dispose();
      });
    });

    test('正计时运行快照按累计时长恢复（totalSeconds=0 不视为损坏）', () async {
      // 正计时运行态 totalSeconds 恒为 0（累计时长用 remainingSeconds 表达），
      // 快照必须按「开始锚点 + elapsed」恢复，而不是当损坏清掉。
      final startMs = DateTime.now()
          .subtract(const Duration(seconds: 30))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues(<String, Object>{
        PomodoroProvider.runningSnapshotKey: jsonEncode(
          snapshotPayload(
            endsAtMs: startMs,
            totalSeconds: 0,
            isCountUp: true,
            completedSessions: 1,
            taskName: '正计时任务',
          ),
        ),
      });

      final provider = PomodoroProvider();
      fakeAsync((async) {
        unawaited(provider.loadFromStorage());
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(provider.state.isRunning, isTrue, reason: '正计时快照应恢复运行');
        expect(provider.state.isCountUp, isTrue);
        final elapsed = provider.state.remainingSeconds;
        expect(elapsed, inInclusiveRange(28, 32), reason: '按开始锚点累计恢复');
        expect(provider.state.totalSeconds, 0, reason: '正计时 totalSeconds 恒为 0');
        expect(provider.state.type, PomodoroType.focus);
        expect(provider.state.completedSessions, 1);
        expect(provider.state.taskName, '正计时任务');
        expect(provider.sessions, isEmpty, reason: '恢复不产生新结算');
        expect(async.periodicTimerCount, 1, reason: 'Timer 应已重启');

        async.elapse(const Duration(seconds: 2));
        expect(provider.state.remainingSeconds, elapsed + 2, reason: '正计时向上累计');

        provider.dispose();
      });
    });

    test('正计时恢复 clamp 到 24h 上限，完成结算时长对齐', () async {
      // 锚点在 25h 前：elapsed=90000s，恢复与结算都应被 clamp 到 86400s。
      final startMs = DateTime.now()
          .subtract(const Duration(hours: 25))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues(<String, Object>{
        PomodoroProvider.runningSnapshotKey: jsonEncode(
          snapshotPayload(endsAtMs: startMs, totalSeconds: 0, isCountUp: true),
        ),
      });

      final provider = PomodoroProvider();
      fakeAsync((async) {
        unawaited(provider.loadFromStorage());
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(provider.state.isRunning, isTrue);
        expect(provider.state.isCountUp, isTrue);
        expect(
          provider.state.remainingSeconds,
          24 * 60 * 60,
          reason: 'elapsed 超过 24h 应 clamp 到 86400s',
        );
        expect(provider.sessions, isEmpty, reason: '恢复不产生新结算');

        provider.finishCurrentSession();
        expect(provider.sessions, hasLength(1));
        expect(
          provider.sessions.single.durationSeconds,
          24 * 60 * 60,
          reason: '结算时长与恢复 clamp 对齐（clamp(1, 24h)）',
        );

        async.flushMicrotasks();
        async.flushMicrotasks();
        String? afterFinish;
        SharedPreferences.getInstance().then((prefs) {
          afterFinish = prefs.getString(PomodoroProvider.runningSnapshotKey);
        });
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(afterFinish, isNull, reason: '结算后快照应删除');

        provider.dispose();
      });
    });

    test('损坏/非运行态快照被清除并回退到空闲 focus 态，不误结算', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PomodoroProvider.runningSnapshotKey: '{bad json',
      });

      final provider = PomodoroProvider();
      fakeAsync((async) {
        unawaited(provider.loadFromStorage());
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(provider.state.isRunning, isFalse, reason: '损坏快照回退空闲态');
        expect(provider.state.type, PomodoroType.focus);
        expect(
          provider.state.totalSeconds,
          provider.config.focusDuration,
          reason: '回退应重置为完整 focus 时长',
        );
        expect(provider.sessions, isEmpty, reason: '损坏快照不得触发结算');

        String? after;
        SharedPreferences.getInstance().then((prefs) {
          after = prefs.getString(PomodoroProvider.runningSnapshotKey);
        });
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(after, isNull, reason: '损坏快照键应被清除');

        // 第二轮：合法 JSON 但 isRunning != true，同样走清键回退分支。
        SharedPreferences.getInstance().then((prefs) {
          return prefs.setString(
            PomodoroProvider.runningSnapshotKey,
            jsonEncode(<String, dynamic>{'isRunning': false}),
          );
        });
        async.flushMicrotasks();
        async.flushMicrotasks();
        unawaited(provider.loadFromStorage());
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(provider.state.isRunning, isFalse);
        SharedPreferences.getInstance().then((prefs) {
          after = prefs.getString(PomodoroProvider.runningSnapshotKey);
        });
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(after, isNull, reason: '非运行态快照键应被清除');

        provider.dispose();
      });
    });

    test('resetTimer 与 skipSession 离开运行态时清除快照', () async {
      final provider = PomodoroProvider();
      await provider.setConfig(PomodoroConfig(focusDuration: 60));

      fakeAsync((async) {
        String? readSnapshot() {
          String? snapshot;
          SharedPreferences.getInstance().then((prefs) {
            snapshot = prefs.getString(PomodoroProvider.runningSnapshotKey);
          });
          async.flushMicrotasks();
          async.flushMicrotasks();
          return snapshot;
        }

        provider.startIfIdle();
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(readSnapshot(), isNotNull, reason: '运行中应有快照');

        provider.resetTimer();
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(readSnapshot(), isNull, reason: 'resetTimer 应清除运行快照');

        provider.startIfIdle();
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(readSnapshot(), isNotNull);

        provider.skipSession();
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(readSnapshot(), isNull, reason: 'skipSession 应清除运行快照');

        provider.dispose();
      });
    });

    test('resetLocalState 清除运行快照', () async {
      final provider = PomodoroProvider();
      await provider.setConfig(PomodoroConfig(focusDuration: 60));

      fakeAsync((async) {
        provider.startIfIdle();
        async.flushMicrotasks();
        async.flushMicrotasks();

        String? snapshot;
        SharedPreferences.getInstance().then((prefs) {
          snapshot = prefs.getString(PomodoroProvider.runningSnapshotKey);
        });
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(snapshot, isNotNull);

        provider.resetLocalState();
        async.flushMicrotasks();
        async.flushMicrotasks();

        SharedPreferences.getInstance().then((prefs) {
          snapshot = prefs.getString(PomodoroProvider.runningSnapshotKey);
        });
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(snapshot, isNull, reason: 'resetLocalState 应清除运行快照');

        provider.dispose();
      });
    });

    test('dispose 不清除运行快照：进程被杀后仍可恢复', () async {
      final provider = PomodoroProvider();
      await provider.setConfig(PomodoroConfig(focusDuration: 60));

      fakeAsync((async) {
        provider.startIfIdle();
        async.flushMicrotasks();
        async.flushMicrotasks();

        provider.dispose();
        async.flushMicrotasks();
        async.flushMicrotasks();

        String? snapshot;
        SharedPreferences.getInstance().then((prefs) {
          snapshot = prefs.getString(PomodoroProvider.runningSnapshotKey);
        });
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(snapshot, isNotNull, reason: 'dispose 不清快照是崩溃恢复的前提');
      });
    });

    test('倒计时快照锚点异常超前（remaining > total）视为损坏清键回退', () async {
      // 时钟回拨 / 快照写入异常值：remaining 会远超 totalSeconds，
      // 必须按损坏清键回退，而不是恢复出超长倒计时。
      final anchorMs = DateTime.now()
          .add(const Duration(hours: 25))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues(<String, Object>{
        PomodoroProvider.runningSnapshotKey: jsonEncode(
          snapshotPayload(endsAtMs: anchorMs),
        ),
      });

      final provider = PomodoroProvider();
      fakeAsync((async) {
        unawaited(provider.loadFromStorage());
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(provider.state.isRunning, isFalse, reason: '锚点异常超前应回退空闲态');
        expect(provider.state.type, PomodoroType.focus);
        expect(
          provider.state.totalSeconds,
          provider.config.focusDuration,
          reason: '回退应重置为完整 focus 时长',
        );
        expect(provider.sessions, isEmpty, reason: '不误结算');

        String? after;
        SharedPreferences.getInstance().then((prefs) {
          after = prefs.getString(PomodoroProvider.runningSnapshotKey);
        });
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(after, isNull, reason: '异常快照键应被清除');

        provider.dispose();
      });
    });
    test('运行中选择子任务即时改写快照，切父任务后快照不再残留旧 subtaskId', () async {
      final provider = PomodoroProvider();
      await provider.setConfig(PomodoroConfig(focusDuration: 60));

      fakeAsync((async) {
        provider.startIfIdle();
        async.flushMicrotasks();
        async.flushMicrotasks();

        provider.setTaskTarget(
          todoId: ' todo-1 ',
          todoTitle: ' 周报整理 ',
          taskName: ' 写总结 ',
          subtaskId: ' sub-1 ',
        );
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(provider.state.todoId, 'todo-1', reason: 'todoId 应 trim');
        expect(provider.state.todoTitle, '周报整理', reason: 'todoTitle 应 trim');
        expect(provider.state.taskName, '写总结', reason: 'taskName 应 trim');
        expect(provider.state.subtaskId, 'sub-1', reason: 'subtaskId 应 trim');

        var snapshot = readRunningSnapshot(async);
        expect(snapshot, isNotNull, reason: '运行中应有快照');
        expect(snapshot?['todoId'], 'todo-1');
        expect(snapshot?['subtaskId'], 'sub-1');
        expect(snapshot?['todoTitle'], '周报整理');
        expect(snapshot?['taskName'], '写总结');

        // 切到父任务：运行中的快照必须同步丢弃旧 subtaskId。
        provider.setTaskTarget(
          todoId: 'todo-1',
          todoTitle: '周报整理',
          taskName: '周报整理',
        );
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(provider.state.subtaskId, isNull);
        expect(provider.state.taskLabel, '周报整理');
        snapshot = readRunningSnapshot(async);
        expect(snapshot?['subtaskId'], isNull, reason: '切父任务后快照不得残留旧子任务');
        expect(snapshot?['todoId'], 'todo-1');
        expect(snapshot?['todoTitle'], '周报整理');

        provider.dispose();
      });
    });

    test('重启恢复保留待办/子任务关联，完成结算带入会话与时间足迹标题', () async {
      final endsAtMs = DateTime.now()
          .add(const Duration(seconds: 30))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues(<String, Object>{
        PomodoroProvider.runningSnapshotKey: jsonEncode(
          snapshotPayload(
            endsAtMs: endsAtMs,
            completedSessions: 1,
            taskName: '写总结',
            todoId: 'todo-1',
            subtaskId: 'sub-1',
            todoTitle: '周报整理',
          ),
        ),
      });

      final audit = TimeAuditProvider();
      final provider = PomodoroProvider()..attachTimeAudit(audit);
      fakeAsync((async) {
        unawaited(provider.loadFromStorage());
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(provider.state.isRunning, isTrue, reason: '未逾期应恢复运行');
        expect(provider.state.todoId, 'todo-1');
        expect(provider.state.subtaskId, 'sub-1');
        expect(provider.state.todoTitle, '周报整理');
        expect(provider.state.taskName, '写总结');
        expect(provider.state.taskLabel, '周报整理 / 写总结');

        provider.finishCurrentSession();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();

        final session = provider.sessions.single;
        expect(session.todoId, 'todo-1');
        expect(session.subtaskId, 'sub-1');
        expect(session.todoTitle, '周报整理');
        expect(session.taskName, '写总结');
        expect(session.taskLabel, '周报整理 / 写总结');
        expect(
          audit.entries.single.title,
          '周报整理 / 写总结',
          reason: '时间足迹标题改用 session.taskLabel，父任务名可见',
        );

        provider.dispose();
      });
    });
  });

  group('番茄专注与待办/子任务关联', () {
    test('setTaskTarget 选子任务后切父任务清旧 subtaskId，setTaskName 清全部关联', () {
      final provider = PomodoroProvider();

      provider.setTaskTarget(
        todoId: 'todo-1',
        todoTitle: '周报整理',
        taskName: '写总结',
        subtaskId: 'sub-1',
      );
      expect(provider.state.todoId, 'todo-1');
      expect(provider.state.subtaskId, 'sub-1');
      expect(provider.state.todoTitle, '周报整理');
      expect(provider.state.taskName, '写总结');
      expect(provider.state.taskLabel, '周报整理 / 写总结');

      // 切到父任务本身：旧子任务必须清掉，父任务名仍是快照。
      provider.setTaskTarget(
        todoId: 'todo-2',
        todoTitle: '季度复盘',
        taskName: '季度复盘',
      );
      expect(provider.state.todoId, 'todo-2');
      expect(provider.state.subtaskId, isNull, reason: '无子任务目标必须清旧 subtaskId');
      expect(provider.state.todoTitle, '季度复盘');
      expect(provider.state.taskLabel, '季度复盘');

      // 手动/预设任务名入口：清全部关联并 trim。
      provider.setTaskName('  自定义任务  ');
      expect(provider.state.taskName, '自定义任务');
      expect(provider.state.todoId, isNull);
      expect(provider.state.subtaskId, isNull);
      expect(provider.state.todoTitle, isNull);
      expect(provider.state.taskLabel, '自定义任务');

      provider.setTaskName('   ');
      expect(provider.state.taskName, isNull, reason: 'trim 空串归 null');

      provider.dispose();
    });

    test('正计时完成把关联写入会话与时间足迹，标题用 taskLabel', () async {
      final audit = TimeAuditProvider();
      final provider = PomodoroProvider()..attachTimeAudit(audit);
      await provider.setConfig(PomodoroConfig(focusDuration: 1500));

      fakeAsync((async) {
        provider.setCountUpMode(true);
        provider.setTaskTarget(
          todoId: ' todo-9 ',
          todoTitle: ' 胶囊计划 ',
          taskName: ' 写第一节 ',
          subtaskId: ' sub-9 ',
        );
        provider.startIfIdle();
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();

        provider.finishCurrentSession();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();

        final session = provider.sessions.single;
        expect(session.type, PomodoroType.focus);
        expect(session.durationSeconds, greaterThanOrEqualTo(1));
        expect(session.todoId, 'todo-9');
        expect(session.subtaskId, 'sub-9');
        expect(session.todoTitle, '胶囊计划');
        expect(session.taskName, '写第一节');
        expect(session.taskLabel, '胶囊计划 / 写第一节');
        expect(
          audit.entries.single.title,
          '胶囊计划 / 写第一节',
          reason: '时间足迹标题改用 session.taskLabel',
        );
        expect(
          audit.entries.single.dedupeKey,
          TimeAuditProvider.pomodoroDedupeKey(session.id),
        );

        provider.dispose();
      });
    });

    test('resetLocalState 清空关联字段并删除含关联的运行快照', () async {
      final provider = PomodoroProvider();
      await provider.setConfig(PomodoroConfig(focusDuration: 60));

      fakeAsync((async) {
        provider.setTaskTarget(
          todoId: 'todo-1',
          todoTitle: '周报整理',
          taskName: '写总结',
          subtaskId: 'sub-1',
        );
        provider.startIfIdle();
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(provider.state.todoId, 'todo-1');
        expect(
          readRunningSnapshot(async)?['todoId'],
          'todo-1',
          reason: '运行快照应带关联',
        );

        provider.resetLocalState();
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(provider.state.todoId, isNull);
        expect(provider.state.subtaskId, isNull);
        expect(provider.state.todoTitle, isNull);
        expect(provider.state.taskName, isNull);
        expect(provider.state.taskLabel, isNull);
        expect(
          readRunningSnapshot(async),
          isNull,
          reason: 'resetLocalState 仍应删除运行快照',
        );

        provider.dispose();
      });
    });
    test('逾期补结算的快照同样保留关联，补写会话 taskLabel 可见', () async {
      final endsAtMs = DateTime.now()
          .subtract(const Duration(seconds: 5))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues(<String, Object>{
        PomodoroProvider.runningSnapshotKey: jsonEncode(<String, dynamic>{
          'isRunning': true,
          'type': PomodoroType.focus.index,
          'isCountUp': false,
          'totalSeconds': 1500,
          'endsAtMs': endsAtMs,
          'completedSessions': 0,
          'taskName': '写总结',
          'todoId': 'todo-1',
          'subtaskId': 'sub-1',
          'todoTitle': '周报整理',
        }),
      });

      final provider = PomodoroProvider();
      fakeAsync((async) {
        unawaited(provider.loadFromStorage());
        async.flushMicrotasks();
        async.flushMicrotasks();
        async.flushMicrotasks();

        final session = provider.sessions.single;
        expect(session.type, PomodoroType.focus);
        expect(session.todoId, 'todo-1', reason: '逾期结算不得丢弃待办关联');
        expect(session.subtaskId, 'sub-1');
        expect(session.todoTitle, '周报整理');
        expect(session.taskLabel, '周报整理 / 写总结');
        expect(provider.sessionCountToday, 1, reason: '仍只结算一次');

        provider.dispose();
      });
    });
  });

  test('distraction selection mode normalizes and persists', () async {
    final provider = PomodoroProvider();
    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.setDistractingAppSelectionMode(' WHITELIST ');
    expect(
      provider.config.distractingAppSelectionMode,
      PomodoroConfig.distractionModeWhitelist,
    );
    expect(provider.config.isDistractionWhitelistMode, isTrue);

    await provider.setDistractingAppSelectionMode('nonsense');
    expect(
      provider.config.distractingAppSelectionMode,
      PomodoroConfig.distractionModeBlacklist,
    );
    expect(notifications, 2);

    final prefs = await SharedPreferences.getInstance();
    final saved =
        jsonDecode(prefs.getString('pomodoro_config')!) as Map<String, dynamic>;
    expect(
      saved['distractingAppSelectionMode'],
      PomodoroConfig.distractionModeBlacklist,
    );
    expect(saved['distractingAppPackages'], isEmpty);
    provider.dispose();
  });

  test('whitelist mode fails safe when the app scan is unavailable', () async {
    final provider = PomodoroProvider();
    await provider.setConfig(
      PomodoroConfig(
        focusDuration: 60,
        strictFocusMode: true,
        monitorDistractingApps: true,
        distractingAppSelectionMode: PomodoroConfig.distractionModeWhitelist,
        distractingAppPackages: const ['com.tencent.mm'],
      ),
    );

    provider.startIfIdle();
    await pumpEventQueue();

    expect(provider.focusDistractionAppScanFailed, isTrue);
    provider.dispose();
  });
}

/// 读取运行态快照（崩溃恢复路径的落盘内容）。
Map<String, dynamic>? readRunningSnapshot(FakeAsync async) {
  Map<String, dynamic>? snapshot;
  SharedPreferences.getInstance().then((prefs) {
    final raw = prefs.getString(PomodoroProvider.runningSnapshotKey);
    if (raw != null) snapshot = jsonDecode(raw) as Map<String, dynamic>;
  });
  async.flushMicrotasks();
  async.flushMicrotasks();
  return snapshot;
}
