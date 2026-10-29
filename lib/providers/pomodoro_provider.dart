import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_clock.dart';
import '../core/domain_event_bus.dart';
import '../core/focus_sound_catalog.dart';
import '../models/pomodoro.dart';
import '../services/focus_distraction_service.dart';
import '../services/focus_dnd_service.dart';
import '../services/focus_sound_service.dart';
import 'cloud_sync_provider.dart';
import 'notification_service.dart';
import 'time_audit_provider.dart';

class PomodoroProvider extends ChangeNotifier with WidgetsBindingObserver {
  /// 运行态快照的持久化键：进程被杀重启后据此恢复进行中的专注。
  /// Android 小组件的 `focus_timer_ends_at_millis` 与 `endsAtMs` 同源。
  static const String runningSnapshotKey = 'pomodoro_running_snapshot';

  /// 桌面小组件控制身份与暂停态（session + revision + idle/running/paused）。
  /// 与 [runningSnapshotKey] 分开保存：运行快照只表达“进程被杀时在跑”，
  /// 暂停后的剩余时长必须能跨重启与冷/热切换继续。
  static const String widgetControlKey = 'pomodoro_widget_control';

  PomodoroState _state = PomodoroState(
    remainingSeconds: 1500,
    totalSeconds: 1500,
    isRunning: false,
    isCountUp: false,
    type: PomodoroType.focus,
    completedSessions: 0,
  );

  PomodoroConfig _config = PomodoroConfig();
  Timer? _timer;
  final ValueNotifier<int> _timerTicks = ValueNotifier<int>(0);
  List<PomodoroSession> _sessions = [];
  List<PomodoroFocusPenalty> _penalties = [];
  int _persistedRevision = 0;
  int _storageGeneration = 0;
  int _sessionCountToday = 0;
  String? _lastDate;
  NotificationService? _notifier;
  TimeAuditProvider? _timeAudit;

  /// 运行态时间锚点（epoch ms）：倒计时 = 预计结束时刻 `endsAt`，
  /// 正计时 = 本次累计的开始时刻。暂停/停止/完成/重置后置空。
  int? _activeAnchorMs;

  /// 上次写入的快照 payload（去重：锚点不变时 tick 重复调用零成本跳过）。
  String? _lastSnapshotPayload;

  /// 快照落盘串行队列：完成旧相位（删）与续跑新相位（写）在同一帧发生，
  /// 按入队顺序 drain 保证 remove 先于新 setString 落盘。不用 Future 链——
  /// 链首 future 的回调会固定在其创建 zone 调度，fakeAsync 测试驱动不到。
  final List<Future<void> Function(SharedPreferences)> _snapshotOps = [];
  bool _snapshotDraining = false;
  Completer<void>? _snapshotDrainDone;

  /// 真实白噪音服务。Task 16 接入：番茄钟状态 ↔ 音频播放。
  final FocusSoundService _sound = FocusSoundService.instance;
  final FocusDndService _dnd = FocusDndService.instance;
  final FocusDistractionService _distraction = FocusDistractionService.instance;

  /// 是否监听了 WidgetsBinding 生命周期（保证 `dispose` 时对称移除）。
  bool _lifecycleAttached = false;
  FocusDndStatus _dndStatus = const FocusDndStatus.unavailable();
  int? _dndPreviousFilter;
  bool _dndActive = false;
  bool _dndEnableInFlight = false;
  bool _dndRestoreInFlight = false;
  Timer? _distractionTimer;
  FocusDistractionStatus _distractionStatus =
      const FocusDistractionStatus.unavailable();
  String? _lastDistractingPackage;

  /// 白名单模式下最终交给原生拦截/前台检测的包集合；黑名单模式直接读配置。
  List<String> _effectiveDistractingPackages = const <String>[];

  /// 最近一次可启动应用扫描结果，供白名单换算复用，轮询时不重复扫描。
  List<InstalledFocusApp> _installedFocusAppsCache =
      const <InstalledFocusApp>[];

  /// 白名单模式扫描失败；此时保留旧拦截集合或禁用拦截，不静默放行。
  bool _distractionScanFailed = false;

  int _distractionSyncGeneration = 0;

  PomodoroState get state => _state;
  PomodoroConfig get config => _config;
  List<PomodoroSession> get sessions => _sessions;
  List<PomodoroFocusPenalty> get penalties => List.unmodifiable(_penalties);
  int get persistedRevision => _persistedRevision;
  int get sessionCountToday => todayFocusSessions.length;
  FocusDndStatus get focusDndStatus => _dndStatus;
  bool get focusDndActive => _dndActive;
  FocusDistractionStatus get focusDistractionStatus => _distractionStatus;

  /// 白名单模式无法扫描已安装应用时为 true（UI 用它提示拦截已暂停）。
  bool get focusDistractionAppScanFailed => _distractionScanFailed;
  ValueListenable<int> get timerTicks => _timerTicks;

  /// 小组件控制身份：不透明 session id + 单调 revision + 当前状态；
  /// `idle` 也持久化，停止后旧 start 绑定会因 session 失配被拒绝。
  String _widgetSessionId = '';
  int _widgetRevision = 0;
  PomodoroWidgetTimerState _widgetTimerState = PomodoroWidgetTimerState.idle;

  /// 暂停态运行数据（跨重启/冷热切换恢复同一剩余时长）。
  PomodoroPausedRuntime? _pausedRuntime;

  /// 控制记录写入串行链：保证后入队的状态不会被先发起的写覆盖。
  Future<void> _widgetControlWrites = Future<void>.value();

  void attachNotifier(NotificationService n) {
    _notifier = n;
  }

  void attachTimeAudit(TimeAuditProvider provider) {
    _timeAudit = provider;
  }

  /// 由 `main.dart` 在 runApp 之前调用。幂等。
  ///
  /// - 绑定 `WidgetsBindingObserver`，在 `resumed` 时按 `state.isRunning` 恢复
  ///   白噪音播放；在 `paused / inactive` 时按策略保持（Android 前台服务
  ///   由 audioplayers 与 manifest 的 `foregroundServiceType=mediaPlayback`
  ///   保证锁屏不被 kill）。
  void attachLifecycle() {
    if (_lifecycleAttached) return;
    WidgetsBinding.instance.addObserver(this);
    _sound.bindLifecycle(WidgetsBinding.instance);
    _sound.onForegroundStopRequested = handleFocusForegroundStopRequested;
    _lifecycleAttached = true;
  }

  Future<void> handleFocusForegroundStopRequested() async {
    await setWhiteNoiseSound(FocusSoundCatalog.none, preview: false);
    await _sound.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(_recordStrictFocusPenalty(FocusPenaltyReason.leaveApp));
    }
    if (state == AppLifecycleState.resumed) {
      // 回到前台：若番茄钟正在跑 + 已选择白噪音，但服务静音了，补上。
      final expected = _state.whiteNoiseSound;
      if (_state.isRunning && expected != 'none' && !_sound.isPlaying) {
        _sound.play(expected);
      }
      if (_config.autoEnableDnd) {
        // ignore: discarded_futures
        refreshFocusDndStatus();
        _syncDndToState();
      }
      if (_config.monitorDistractingApps) {
        // ignore: discarded_futures
        refreshFocusDistractionStatus();
        _syncDistractionMonitorToState();
      }
    }
  }

  Future<void> loadFromStorage() async {
    final generation = _storageGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration) return;

    final configData = prefs.getString('pomodoro_config');
    if (configData != null) {
      _config = PomodoroConfig.fromJson(json.decode(configData));
    }

    final sessionsData = prefs.getString('pomodoro_sessions');
    if (sessionsData != null) {
      _sessions = (json.decode(sessionsData) as List)
          .map((e) => PomodoroSession.fromJson(e))
          .toList();
    }

    final penaltiesData = prefs.getString('pomodoro_focus_penalties');
    if (penaltiesData != null) {
      _penalties = (json.decode(penaltiesData) as List)
          .whereType<Map>()
          .map((e) => PomodoroFocusPenalty.fromJson(Map.from(e)))
          .toList();
    }

    _sessionCountToday = prefs.getInt('pomodoro_count_today') ?? 0;
    _lastDate = prefs.getString('pomodoro_last_date');
    // 先过跨天重置再恢复/结算，保证逾期补结算的当日计数归属恢复当天。
    _checkDayReset();
    final snapshotHandled = await _restoreRunningFromSnapshot(prefs);
    // 控制身份/暂停态：暂停后重启或冷/主切换要能继续同一剩余时长。
    final pausedRestored = _restoreWidgetControl(
      prefs.getString(widgetControlKey),
      snapshotHandled: snapshotHandled,
    );
    if (_state.isRunning) {
      _state = _state.copyWith(
        whiteNoiseSound: _config.whiteNoiseSound,
        focusRoomId: _config.focusRoomId,
        clearFocusRoom: _config.focusRoomId == null,
      );
      unawaited(_syncSoundToState());
      _syncDndToState();
      _syncDistractionMonitorToState();
    } else if (!snapshotHandled && !pausedRestored) {
      // 无快照/暂停态且不在运行：重置为完整 focusDuration。
      // 有快照但逾期且未续跑时，保留结算后的 break 相位，不重置。
      _initState();
    }
    _persistedRevision++;
    notifyListeners();
  }

  void resetLocalState() {
    _storageGeneration++;
    _cancelTimer();
    _clearRunningSnapshot();
    // 新 idle 身份：换号/重置后旧小组件按钮的 session + revision 一律失效。
    _resetWidgetControlIdentity(PomodoroWidgetTimerState.idle);
    _timerTicks.value = 0;
    _config = PomodoroConfig();
    _sessions = [];
    _penalties = [];
    _sessionCountToday = 0;
    _lastDate = null;
    _persistedRevision++;
    _initState();
    // ignore: discarded_futures
    _sound.stop();
    // ignore: discarded_futures
    _restoreFocusDndIfNeeded(notify: false);
    _dndStatus = const FocusDndStatus.unavailable();
    _dndActive = false;
    _dndEnableInFlight = false;
    _distractionTimer?.cancel();
    _distractionTimer = null;
    _distractionStatus = const FocusDistractionStatus.unavailable();
    _lastDistractingPackage = null;
    _effectiveDistractingPackages = const <String>[];
    _installedFocusAppsCache = const <InstalledFocusApp>[];
    _distractionScanFailed = false;
    _distractionSyncGeneration++;
    // ignore: discarded_futures
    _distraction.setFocusBlocker(enabled: false, packages: const []);
    notifyListeners();
  }

  void _initState() {
    _state = PomodoroState(
      remainingSeconds: _config.focusDuration,
      totalSeconds: _config.focusDuration,
      isRunning: false,
      isCountUp: false,
      type: PomodoroType.focus,
      completedSessions: 0,
      whiteNoiseSound: _config.whiteNoiseSound,
      focusRoomId: _config.focusRoomId,
    );
  }

  void _checkDayReset() {
    // Today's count is a view of the stored instants, including after a zone change.
    // Reading a different day must not write sync metadata or erase its history.
    _sessionCountToday = todayFocusSessions.length;
    _lastDate = _todayKey();
  }

  String _todayKey() {
    final n = AppClock.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    final localA = AppClock.toLocal(a);
    final localB = AppClock.toLocal(b);
    return localA.year == localB.year &&
        localA.month == localB.month &&
        localA.day == localB.day;
  }

  Future<void> _saveMeta() async {
    _checkDayReset();
    final lastDate = _lastDate!;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pomodoro_count_today', _sessionCountToday);
    await prefs.setString('pomodoro_last_date', lastDate);
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pomodoro_config', json.encode(_config.toJson()));
  }

  Future<void> _touchAndSaveConfig() async {
    _config.touch();
    await _saveConfig();
  }

  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    // 大列表的 JSON 编码会阻塞主 isolate，挪到后台 isolate 执行（对齐
    // todo_provider 的做法）；小列表直接同步编码，省去 isolate 往返。
    final data = _sessions.length >= _isolateEncodeMinItems
        ? await compute(
            _encodePomodoroSessionsPayload,
            List<PomodoroSession>.of(_sessions),
          )
        : json.encode(_sessions.map((e) => e.toJson()).toList());
    await prefs.setString('pomodoro_sessions', data);
  }

  /// 会话记录有界增长：超出上限时丢弃最旧的记录（机制对齐 penalties
  /// 的 take(100)；上限放宽到 500 以保留统计页/日历/报告的近月历史）。
  void _trimSessions() {
    if (_sessions.length > _maxPomodoroSessions) {
      _sessions.removeRange(0, _sessions.length - _maxPomodoroSessions);
    }
  }

  /// 测试专用：批量注入历史会话（触发上限裁剪与持久化）。
  @visibleForTesting
  Future<void> debugAddSessionsForTest(List<PomodoroSession> sessions) async {
    _sessions.addAll(sessions);
    _trimSessions();
    await _saveSessions();
    notifyListeners();
  }

  Future<void> _savePenaltyList(List<PomodoroFocusPenalty> penalties) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'pomodoro_focus_penalties',
      json.encode(penalties.map((e) => e.toJson()).toList()),
    );
  }

  // --- 运行态快照（进程被杀重启后的恢复路径） ---

  /// 串行执行快照落盘操作；失败静默降级，不影响计时主流程。
  void _queueSnapshotOp(Future<void> Function(SharedPreferences) op) {
    _snapshotOps.add(op);
    if (_snapshotDraining) return;
    _snapshotDraining = true;
    _snapshotDrainDone = Completer<void>();
    unawaited(_drainSnapshotOps());
  }

  Future<void> _drainSnapshotOps() async {
    try {
      while (_snapshotOps.isNotEmpty) {
        final op = _snapshotOps.removeAt(0);
        try {
          final prefs = await SharedPreferences.getInstance();
          await op(prefs);
        } catch (_) {
          // 快照持久化失败可容忍：下次 tick / 退出运行态会重新同步。
        }
      }
    } finally {
      _snapshotDraining = false;
      _snapshotDrainDone?.complete();
      _snapshotDrainDone = null;
    }
  }

  Map<String, dynamic> _runningSnapshot() => <String, dynamic>{
    'isRunning': true,
    'type': _state.type.index,
    'isCountUp': _state.isCountUp,
    'totalSeconds': _state.totalSeconds,
    'endsAtMs': _activeAnchorMs,
    'completedSessions': _state.completedSessions,
    'taskName': _state.taskName,
    'todoId': _state.todoId,
    'subtaskId': _state.subtaskId,
    'todoTitle': _state.todoTitle,
    'tag': _state.tag,
  };

  /// 把当前运行态写入快照。在启动与每个计时 tick 调用；锚点不变时
  /// payload 相同，直接跳过落盘（快照内容与 `endsAt` 无关的秒级推进）。
  void _persistRunningSnapshot() {
    if (!_state.isRunning || _activeAnchorMs == null) return;
    final payload = json.encode(_runningSnapshot());
    if (payload == _lastSnapshotPayload) return;
    _lastSnapshotPayload = payload;
    _queueSnapshotOp((prefs) => prefs.setString(runningSnapshotKey, payload));
  }

  /// 离开运行态（暂停 / 手动停止 / 完成 / 重置 / 重置本地数据）时清快照。
  void _clearRunningSnapshot() {
    _activeAnchorMs = null;
    _lastSnapshotPayload = null;
    _queueSnapshotOp((prefs) => prefs.remove(runningSnapshotKey));
  }

  /// 启动时重建：进程被杀后唯一恢复路径（不做后台计时）。
  ///
  /// - 未逾期 → 按 `endsAt - now` 恢复 remainingSeconds 并重启 Timer；
  ///   正计时按累计时长恢复。
  /// - 逾期（elapsed ≥ total）→ 删除快照后走既有自然完成结算
  ///   （写一条 session、当日计数 +1、autoStartBreaks），保证只结算一次。
  ///
  /// 返回是否处理过快照（恢复运行或完成结算）；调用方据此决定是否回退
  /// 到 [_initState]（逾期结算后不续跑时，应保留 break 相位而非重置）。
  Future<bool> _restoreRunningFromSnapshot(SharedPreferences prefs) async {
    final raw = prefs.getString(runningSnapshotKey);
    if (raw == null) return false;

    Map<String, dynamic>? data;
    try {
      final decoded = json.decode(raw);
      if (decoded is Map) data = Map<String, dynamic>.from(decoded);
    } on FormatException {
      data = null;
    }
    final anchorMs = data == null ? null : (data['endsAtMs'] as num?)?.toInt();
    final totalSeconds = data == null
        ? null
        : (data['totalSeconds'] as num?)?.toInt();
    final isCountUp = data?['isCountUp'] == true;
    if (data == null ||
        data['isRunning'] != true ||
        anchorMs == null ||
        totalSeconds == null ||
        // 正计时运行态 totalSeconds 恒为 0（累计时长用 remainingSeconds 表达），
        // 不能按损坏快照清除；只有倒计时才要求 totalSeconds > 0。
        (!isCountUp && totalSeconds <= 0)) {
      // 快照损坏 / 非运行态：清理后按无快照处理。
      await prefs.remove(runningSnapshotKey);
      return false;
    }

    final typeIndex = (data['type'] as num?)?.toInt() ?? 0;
    final type = typeIndex >= 0 && typeIndex < PomodoroType.values.length
        ? PomodoroType.values[typeIndex]
        : PomodoroType.focus;
    final completedSessions = (data['completedSessions'] as num?)?.toInt() ?? 0;
    final taskName = data['taskName']?.toString();
    final tag = data['tag']?.toString();
    final todoId = data['todoId']?.toString();
    final subtaskId = data['subtaskId']?.toString();
    final todoTitle = data['todoTitle']?.toString();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    if (!isCountUp) {
      // 倒计时：快照锚点即结束时刻，向上取整避免恢复瞬间吞掉不足 1 秒。
      final remainingSeconds = ((anchorMs - nowMs) / 1000).ceil();
      if (remainingSeconds <= 0) {
        // 逾期：先删快照（结算只此一次），再走既有自然完成结算。
        _activeAnchorMs = null;
        _lastSnapshotPayload = null;
        await prefs.remove(runningSnapshotKey);
        _state = PomodoroState(
          // 结算时长取 totalSeconds，与 remainingSeconds 无关；
          // 置 1 表达「倒计时走完」的完成语义。
          remainingSeconds: 1,
          totalSeconds: totalSeconds,
          isRunning: true,
          type: type,
          completedSessions: completedSessions,
          taskName: taskName,
          todoId: todoId,
          subtaskId: subtaskId,
          todoTitle: todoTitle,
          whiteNoiseSound: _config.whiteNoiseSound,
          tag: tag,
          focusRoomId: _config.focusRoomId,
        );
        _completeSession();
        return true;
      }
      // 快照锚点异常超前（时钟回拨 / 写入异常值）：真实运行态剩余永远
      // ≤ totalSeconds，remaining > total 只能是损坏，按损坏清键回退，
      // 避免恢复出远超配置时长的倒计时（与正计时的 clamp 对称）。
      if (remainingSeconds > totalSeconds) {
        _activeAnchorMs = null;
        _lastSnapshotPayload = null;
        await prefs.remove(runningSnapshotKey);
        return false;
      }
      _state = PomodoroState(
        remainingSeconds: remainingSeconds,
        totalSeconds: totalSeconds,
        isRunning: true,
        type: type,
        completedSessions: completedSessions,
        taskName: taskName,
        todoId: todoId,
        subtaskId: subtaskId,
        todoTitle: todoTitle,
        whiteNoiseSound: _config.whiteNoiseSound,
        tag: tag,
        focusRoomId: _config.focusRoomId,
      );
      // 保留原锚点续跑：完成时刻仍对齐快照里的 endsAt，不白送时间。
      _activeAnchorMs = anchorMs;
      _lastSnapshotPayload = null;
      _startTimer();
      return true;
    }

    // 正计时：快照锚点为开始时刻，按累计时长恢复（上限对齐完成时的
    // clamp(1, 24h) 语义）。
    final elapsed = ((nowMs - anchorMs) / 1000).floor().clamp(
      0,
      _maxCountUpSnapshotSeconds,
    );
    _state = PomodoroState(
      remainingSeconds: elapsed,
      totalSeconds: totalSeconds,
      isRunning: true,
      isCountUp: true,
      type: type,
      completedSessions: completedSessions,
      taskName: taskName,
      todoId: todoId,
      subtaskId: subtaskId,
      todoTitle: todoTitle,
      whiteNoiseSound: _config.whiteNoiseSound,
      tag: tag,
      focusRoomId: _config.focusRoomId,
    );
    _activeAnchorMs = nowMs - elapsed * 1000;
    _lastSnapshotPayload = null;
    _startTimer();
    return true;
  }

  Future<bool> deleteSession(String id) async {
    final idx = _sessions.indexWhere((s) => s.id == id);
    if (idx < 0) return false;

    final removed = _sessions.removeAt(idx);
    await CloudSyncProvider.recordDeletedItem('pomodoro_sessions', removed.id);
    if (removed.type == PomodoroType.focus &&
        _isSameDay(removed.startTime, AppClock.now())) {
      await _refreshTodayFocusMeta();
    }

    await _timeAudit?.deleteByDedupeKey(
      TimeAuditProvider.pomodoroDedupeKey(id),
    );
    await _saveSessions();
    _persistedRevision++;
    notifyListeners();
    return true;
  }

  Future<bool> updateSession(PomodoroSession updated) async {
    final idx = _sessions.indexWhere((s) => s.id == updated.id);
    if (idx < 0) return false;

    final previous = _sessions[idx];
    _sessions[idx] = updated;
    if (_affectsTodayFocusCount(previous) || _affectsTodayFocusCount(updated)) {
      await _refreshTodayFocusMeta();
    }

    final dedupeKey = TimeAuditProvider.pomodoroDedupeKey(updated.id);
    if (updated.type == PomodoroType.focus) {
      await _timeAudit?.recordPomodoroSession(
        sessionId: updated.id,
        // 子任务父名可见：时间足迹标题用 taskLabel（父任务 / 子任务）。
        title: updated.taskLabel?.isNotEmpty == true
            ? updated.taskLabel!
            : '番茄专注',
        startAt: updated.startTime,
        endAt: updated.endTime,
        note: updated.whiteNoiseSound == 'none'
            ? ''
            : '白噪音：${updated.whiteNoiseSound}',
      );
    } else {
      await _timeAudit?.deleteByDedupeKey(dedupeKey);
    }

    await _saveSessions();
    _persistedRevision++;
    notifyListeners();
    return true;
  }

  bool _affectsTodayFocusCount(PomodoroSession session) {
    return session.type == PomodoroType.focus &&
        _isSameDay(session.startTime, AppClock.now());
  }

  Future<void> _refreshTodayFocusMeta() async {
    final now = AppClock.now();
    _sessionCountToday = _sessions
        .where(
          (s) => s.type == PomodoroType.focus && _isSameDay(s.startTime, now),
        )
        .length;
    _lastDate = _todayKey();
    await _saveMeta();
  }

  // --- Timer controls ---

  void toggleTimer() {
    if (_state.isRunning) {
      unawaited(_recordStrictFocusPenalty(FocusPenaltyReason.pause));
      _pauseTimer();
    } else {
      _startTimer();
    }
  }

  void startIfIdle() {
    if (_state.isRunning) return;
    _startTimer();
  }

  void _startTimer() {
    if (_timer?.isActive ?? false) {
      if (!_state.isRunning) {
        _state = _state.copyWith(isRunning: true);
        // 身份推进只在“进入运行”这一帧发生，tick 绝不改 revision。
        _markTimerStarted();
        notifyListeners();
      }
      unawaited(_syncSoundToState());
      _syncDndToState();
      _syncDistractionMonitorToState();
      return;
    }
    if (!_state.isRunning) {
      _state = _state.copyWith(isRunning: true);
      _markTimerStarted();
      notifyListeners();
    }
    // 新启动（含暂停续跑）计算锚点；崩溃恢复路径已带原锚点，不重算。
    _activeAnchorMs ??= _state.isCountUp
        ? DateTime.now().millisecondsSinceEpoch - _state.remainingSeconds * 1000
        : DateTime.now().millisecondsSinceEpoch +
              _state.remainingSeconds * 1000;
    _persistRunningSnapshot();
    unawaited(_syncSoundToState());
    _syncDndToState();
    _syncDistractionMonitorToState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state.isCountUp) {
        _state = _state.copyWith(remainingSeconds: _state.remainingSeconds + 1);
        _notifyTimerTick();
        _persistRunningSnapshot();
        return;
      }
      if (_state.remainingSeconds <= 1) {
        _completeSession();
        return;
      }
      _state = _state.copyWith(remainingSeconds: _state.remainingSeconds - 1);
      _notifyTimerTick();
      _persistRunningSnapshot();
    });
  }

  void _notifyTimerTick() {
    _timerTicks.value++;
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _pauseTimer() {
    _cancelTimer();
    // 暂停前先记录完整相位：重启/冷热切换后可继续同一剩余时长。
    _capturePausedRuntime();
    _clearRunningSnapshot();
    _state = _state.copyWith(isRunning: false);
    _widgetTimerState = PomodoroWidgetTimerState.paused;
    _widgetRevision++;
    unawaited(_writeWidgetControl());
    notifyListeners();
    _syncDndToState();
    _syncDistractionMonitorToState();
    // ignore: discarded_futures
    _sound.fadeOut(const Duration(milliseconds: 300));
  }

  /// 依据当前 [_state]（`isRunning`、`type`、`whiteNoiseSound`）与
  /// [_config.playSoundInBreak] 决定播放 / 停止白噪音。
  ///
  /// 调用点：`_startTimer` 与 `_completeSession` 的相位切换后。
  Future<bool> _syncSoundToState() async {
    final sound = _state.whiteNoiseSound;
    final shouldPlay =
        _state.isRunning &&
        sound != 'none' &&
        (_state.type == PomodoroType.focus || _config.playSoundInBreak);
    if (shouldPlay) {
      if (!_sound.isPlaying || _sound.currentSound != sound) {
        return _playFocusSound(sound);
      } else {
        await _sound.setVolume(_config.focusSoundVolume);
        return true;
      }
    } else {
      if (_sound.isPlaying) {
        await _sound.stop();
      }
      return true;
    }
  }

  Future<bool> _playFocusSound(String sound) async {
    await _sound.setVolume(_config.focusSoundVolume);
    return _sound.play(sound);
  }

  Future<bool> _previewWhiteNoiseSound(String sound) async {
    if (sound == FocusSoundCatalog.none || _state.isRunning) return true;
    await _sound.setVolume(_config.focusSoundVolume);
    return _sound.preview(sound);
  }

  String get _focusSoundPreviewFallback {
    final current = _state.whiteNoiseSound;
    if (current != FocusSoundCatalog.none) return current;
    return FocusSoundCatalog.tracks.first.id;
  }

  void _completeSession() {
    _cancelTimer();
    // 结算即清旧快照（自然完成与崩溃后的逾期补结算共用）；若按
    // autoStart 续跑，_startTimer 会以新相位锚点重新落盘。
    _clearRunningSnapshot();
    final completedState = _state;
    final completedType = completedState.type;
    final durationSeconds = completedState.isCountUp
        ? completedState.remainingSeconds.clamp(1, 24 * 60 * 60).toInt()
        : completedState.totalSeconds;
    final completedAt = DateTime.now();
    final session = PomodoroSession(
      id: completedAt.microsecondsSinceEpoch.toString(),
      startTime: completedAt.subtract(Duration(seconds: durationSeconds)),
      endTime: completedAt,
      durationSeconds: durationSeconds,
      type: completedType,
      taskName: completedState.taskName,
      todoId: completedState.todoId,
      subtaskId: completedState.subtaskId,
      todoTitle: completedState.todoTitle,
      whiteNoiseSound: completedState.whiteNoiseSound,
      tag: completedState.tag,
      focusRoomId: completedState.focusRoomId,
    );
    _trimSessions();
    _sessions.add(session);

    int newCount = completedState.completedSessions;
    final shouldSaveMeta = completedType == PomodoroType.focus;
    if (completedType == PomodoroType.focus) {
      newCount++;
      _sessionCountToday++;
    }

    PomodoroType nextType;
    int nextDuration;
    if (completedType == PomodoroType.focus) {
      if (newCount % _config.sessionsPerLongBreak == 0) {
        nextType = PomodoroType.longBreak;
        nextDuration = _config.longBreakDuration;
      } else {
        nextType = PomodoroType.shortBreak;
        nextDuration = _config.shortBreakDuration;
      }
    } else {
      nextType = PomodoroType.focus;
      nextDuration = _config.focusDuration;
    }
    final shouldAutoStartNext = completedType == PomodoroType.focus
        ? _config.autoStartBreaks
        : _config.autoStartFocus;

    if (completedState.isCountUp) {
      _state = completedState.copyWith(
        remainingSeconds: 0,
        totalSeconds: 0,
        isRunning: false,
        isCountUp: true,
        type: PomodoroType.focus,
        completedSessions: newCount,
      );
    } else {
      _state = completedState.copyWith(
        remainingSeconds: nextDuration,
        totalSeconds: nextDuration,
        isRunning: shouldAutoStartNext,
        type: nextType,
        completedSessions: newCount,
      );
    }

    if (_state.isRunning) {
      _startTimer();
    } else {
      // 本相位不自动续跑：立刻把声音停掉（focus→break 过渡，或已到末尾）。
      // ignore: discarded_futures
      _sound.stop();
      _syncDndToState();
      _syncDistractionMonitorToState();
    }
    // 自然完成即“结束当前 session”：生成新身份（含 idle/自动续跑），
    // 旧按钮的 session/revision 不再能暂停或停止新的相位。
    _resetWidgetControlIdentity(
      _state.isRunning
          ? PomodoroWidgetTimerState.running
          : PomodoroWidgetTimerState.idle,
    );
    notifyListeners();
    unawaited(
      _persistCompletedSession(
        session: session,
        completedState: completedState,
        completedType: completedType,
        saveMeta: shouldSaveMeta,
      ),
    );
  }

  Future<void> _persistCompletedSession({
    required PomodoroSession session,
    required PomodoroState completedState,
    required PomodoroType completedType,
    required bool saveMeta,
  }) async {
    await _saveSessions();

    if (completedType == PomodoroType.focus) {
      await _timeAudit?.recordPomodoroSession(
        sessionId: session.id,
        // 子任务父名可见：时间足迹标题用 taskLabel（父任务 / 子任务）。
        title: session.taskLabel?.isNotEmpty == true
            ? session.taskLabel!
            : '番茄专注',
        startAt: session.startTime,
        endAt: session.endTime,
        note: session.whiteNoiseSound == 'none'
            ? ''
            : '白噪音：${session.whiteNoiseSound}',
      );
      DomainEventBus.instance.publish(
        DomainEvent(
          type: DomainEventType.pomodoroCompleted,
          objectId: session.id,
          metadata: {'durationSeconds': session.durationSeconds},
        ),
      );
    }

    // Fire desktop notification
    if (completedType == PomodoroType.focus) {
      _notifier?.notifyPomodoroComplete(taskName: completedState.taskName);
    } else {
      _notifier?.notifyBreakComplete();
    }

    if (saveMeta) {
      await _saveMeta();
    }

    _persistedRevision++;
    notifyListeners();
  }

  void skipSession() {
    _cancelTimer();
    _clearRunningSnapshot();
    unawaited(_recordStrictFocusPenalty(FocusPenaltyReason.skip));
    if (_state.type == PomodoroType.focus) {
      _state = _state.copyWith(
        remainingSeconds: _config.shortBreakDuration,
        totalSeconds: _config.shortBreakDuration,
        isRunning: false,
        type: PomodoroType.shortBreak,
      );
    } else {
      _state = _state.copyWith(
        remainingSeconds: _config.focusDuration,
        totalSeconds: _config.focusDuration,
        isRunning: false,
        type: PomodoroType.focus,
      );
    }
    // 跳过同样是相位切换：旧按钮不能暂停/停止新相位。
    _resetWidgetControlIdentity(PomodoroWidgetTimerState.idle);
    // ignore: discarded_futures
    _sound.stop();
    _syncDndToState();
    _syncDistractionMonitorToState();
    notifyListeners();
  }

  void resetTimer() {
    _cancelTimer();
    _clearRunningSnapshot();
    unawaited(_recordStrictFocusPenalty(FocusPenaltyReason.reset));
    _state = _state.copyWith(
      remainingSeconds: _state.isCountUp ? 0 : _config.focusDuration,
      totalSeconds: _state.isCountUp ? 0 : _config.focusDuration,
      isRunning: false,
      type: PomodoroType.focus,
      completedSessions: 0,
    );
    // stop 语义：回到满时长、不产生完成记录，并生成新 idle 身份。
    _resetWidgetControlIdentity(PomodoroWidgetTimerState.idle);
    // ignore: discarded_futures
    _sound.stop();
    _syncDndToState();
    _syncDistractionMonitorToState();
    notifyListeners();
  }

  void finishCurrentSession() {
    if (_state.type != PomodoroType.focus) return;
    if (_state.isCountUp && !_state.isRunning && _state.remainingSeconds <= 0) {
      return;
    }
    _completeSession();
  }

  void setCountUpMode(bool enabled) {
    if (_state.isRunning) return;
    _cancelTimer();
    _state = _state.copyWith(
      remainingSeconds: enabled ? 0 : _config.focusDuration,
      totalSeconds: enabled ? 0 : _config.focusDuration,
      isRunning: false,
      isCountUp: enabled,
      type: PomodoroType.focus,
    );
    _resetWidgetControlIdentity(PomodoroWidgetTimerState.idle);
    // ignore: discarded_futures
    _sound.stop();
    _syncDndToState();
    _syncDistractionMonitorToState();
    notifyListeners();
  }

  // --- Config ---

  Future<void> setConfig(PomodoroConfig cfg) async {
    _config = cfg;
    await _touchAndSaveConfig();
    _persistedRevision++;
    if (!_state.isRunning) {
      _state = _state.copyWith(
        remainingSeconds: _state.isCountUp ? 0 : cfg.focusDuration,
        totalSeconds: _state.isCountUp ? 0 : cfg.focusDuration,
        whiteNoiseSound: cfg.whiteNoiseSound,
        focusRoomId: cfg.focusRoomId,
      );
    }
    notifyListeners();
    _syncDndToState();
    _syncDistractionMonitorToState();
  }

  Future<void> setAutoEnableDnd(bool enabled) async {
    if (_config.autoEnableDnd == enabled) return;
    _config.autoEnableDnd = enabled;
    _persistedRevision++;
    notifyListeners();
    await _touchAndSaveConfig();
    if (enabled) {
      await refreshFocusDndStatus();
    } else {
      await _restoreFocusDndIfNeeded();
    }
    notifyListeners();
    _syncDndToState();
  }

  Future<void> setStrictFocusMode(bool enabled) async {
    if (_config.strictFocusMode == enabled) return;
    _config.strictFocusMode = enabled;
    _persistedRevision++;
    notifyListeners();
    await _touchAndSaveConfig();
    _syncDistractionMonitorToState();
  }

  Future<FocusDndStatus> refreshFocusDndStatus() async {
    _dndStatus = await _dnd.getStatus();
    notifyListeners();
    return _dndStatus;
  }

  Future<bool> openFocusDndSettings() => _dnd.openPolicyAccessSettings();

  bool get _shouldEnableDnd =>
      _config.autoEnableDnd &&
      _state.isRunning &&
      _state.type == PomodoroType.focus;

  void _syncDndToState() {
    if (_shouldEnableDnd) {
      if (!_dndActive && !_dndEnableInFlight) {
        // ignore: discarded_futures
        _enableFocusDndIfPossible();
      }
      return;
    }
    if ((_dndActive || _dndPreviousFilter != null) && !_dndRestoreInFlight) {
      // ignore: discarded_futures
      _restoreFocusDndIfNeeded();
    }
  }

  Future<void> _enableFocusDndIfPossible() async {
    _dndEnableInFlight = true;
    try {
      final status = await _dnd.getStatus();
      _dndStatus = status;
      if (!_shouldEnableDnd || !status.supported || !status.accessGranted) {
        notifyListeners();
        return;
      }

      final result = await _dnd.enable();
      if (result.enabled) {
        _dndPreviousFilter ??= result.previousFilter;
        _dndActive = true;
        _dndStatus = FocusDndStatus(
          supported: true,
          accessGranted: true,
          currentFilter: result.currentFilter,
        );
      }
      if (!_shouldEnableDnd) {
        await _restoreFocusDndIfNeeded();
      }
      notifyListeners();
    } finally {
      _dndEnableInFlight = false;
    }
  }

  Future<void> _restoreFocusDndIfNeeded({bool notify = true}) async {
    if (_dndRestoreInFlight) return;
    final previous = _dndPreviousFilter;
    if (previous == null) {
      _dndActive = false;
      return;
    }
    _dndRestoreInFlight = true;
    _dndPreviousFilter = null;
    _dndActive = false;
    try {
      await _dnd.restore(previous);
      _dndStatus = await _dnd.getStatus();
      if (notify) notifyListeners();
    } finally {
      _dndRestoreInFlight = false;
    }
  }

  /// 手动 / 预设任务名入口：改名字即视为不再指向具体待办或子任务，
  /// 因此同时清空关联字段（要保留关联请走 [setTaskTarget]）。
  void setTaskName(String? name) {
    final clean = name?.trim();
    final next = clean == null || clean.isEmpty ? null : clean;
    _state = _state.copyWith(
      taskName: next,
      clearTaskName: next == null,
      clearTaskLink: true,
    );
    notifyListeners();
    // 运行中改任务名必须同步快照，否则重启后恢复出旧任务名。
    _persistRunningSnapshot();
  }

  /// 待办 / 子任务选择入口：一次性写入父任务 id、父任务名称快照与
  /// （可选的）子任务 id；`taskName` 仍是被选择对象本身的名称
  /// （选子任务时是子任务名，父任务名进 `todoTitle`）。
  ///
  /// 先 `clearTaskLink` 全清再赋值：`copyWith` 的 `subtaskId ?? this.subtaskId`
  /// 会保留旧值，从子任务切回父任务时必须显式丢弃旧 `subtaskId`。
  void setTaskTarget({
    required String todoId,
    required String todoTitle,
    required String taskName,
    String? subtaskId,
  }) {
    final parentId = todoId.trim();
    final parentTitle = todoTitle.trim();
    final target = taskName.trim();
    final childId = subtaskId?.trim();
    _state = _state
        .copyWith(clearTaskLink: true)
        .copyWith(
          taskName: target.isEmpty ? null : target,
          clearTaskName: target.isEmpty,
          todoId: parentId.isEmpty ? null : parentId,
          todoTitle: parentTitle.isEmpty ? null : parentTitle,
          subtaskId: childId == null || childId.isEmpty ? null : childId,
        );
    notifyListeners();
    // 运行中选择任务需要立刻落盘，保证崩溃重启后恢复出同一关联。
    _persistRunningSnapshot();
  }

  void setTag(String? tag) {
    final clean = tag?.trim();
    _state = _state.copyWith(
      tag: clean,
      clearTag: clean == null || clean.isEmpty,
    );
    notifyListeners();
  }

  Future<void> setFocusRoomId(String? roomId) async {
    final clean = roomId?.trim();
    final nextRoomId = clean == null || clean.isEmpty ? null : clean;
    if (_config.focusRoomId == nextRoomId && _state.focusRoomId == nextRoomId) {
      return;
    }
    _config.focusRoomId = nextRoomId;
    _state = _state.copyWith(
      focusRoomId: _config.focusRoomId,
      clearFocusRoom: _config.focusRoomId == null,
    );
    await _touchAndSaveConfig();
    _persistedRevision++;
    notifyListeners();
  }

  Future<void> refreshFocusDistractionStatus() async {
    _distractionStatus = await _distraction.getStatus();
    notifyListeners();
  }

  Future<bool> openFocusUsageAccessSettings() {
    return _distraction.openUsageAccessSettings();
  }

  Future<bool> openFocusAccessibilitySettings() {
    return _distraction.openAccessibilitySettings();
  }

  Future<void> setMonitorDistractingApps(bool enabled) async {
    if (_config.monitorDistractingApps == enabled) return;
    _config.monitorDistractingApps = enabled;
    _persistedRevision++;
    notifyListeners();
    await _touchAndSaveConfig();
    // ignore: discarded_futures
    refreshFocusDistractionStatus();
    _syncDistractionMonitorToState();
  }

  Future<void> setDistractingAppPackages(List<String> packages) async {
    final normalized =
        packages
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (_config.distractingAppPackages.length == normalized.length &&
        _config.distractingAppPackages.every(normalized.contains)) {
      return;
    }
    _config.distractingAppPackages = normalized;
    await _touchAndSaveConfig();
    _persistedRevision++;
    notifyListeners();
    _syncDistractionMonitorToState();
  }

  Future<void> setDistractingAppSelectionMode(String mode) async {
    final normalized = PomodoroConfig.normalizeDistractionSelectionMode(mode);
    if (_config.distractingAppSelectionMode == normalized) return;
    _config.distractingAppSelectionMode = normalized;
    await _touchAndSaveConfig();
    _persistedRevision++;
    notifyListeners();
    _syncDistractionMonitorToState();
  }

  /// 扫描可启动的已安装应用供选择器展示；成功结果同时刷新白名单换算缓存。
  Future<List<InstalledFocusApp>> loadInstalledFocusApps() async {
    final apps = await _distraction.getInstalledApps();
    if (apps.isEmpty) return apps;
    final recovered = _distractionScanFailed;
    _installedFocusAppsCache = apps;
    _distractionScanFailed = false;
    if (recovered) {
      notifyListeners();
      _syncDistractionMonitorToState();
    }
    return apps;
  }

  Future<bool> setWhiteNoiseSound(String sound, {bool preview = true}) async {
    final normalized = sound.startsWith('custom:')
        ? sound
        : FocusSoundCatalog.normalizeForPlayback(sound);
    if (_config.whiteNoiseSound == normalized &&
        _state.whiteNoiseSound == normalized) {
      if (preview &&
          normalized != FocusSoundCatalog.none &&
          !_state.isRunning) {
        return _previewWhiteNoiseSound(normalized);
      }
      return true;
    }
    _state = _state.copyWith(whiteNoiseSound: normalized);
    _config.whiteNoiseSound = normalized;
    await _touchAndSaveConfig();
    _persistedRevision++;
    notifyListeners();
    final playbackOk = await _syncSoundToState();
    if (!playbackOk &&
        _state.isRunning &&
        normalized != FocusSoundCatalog.none) {
      _state = _state.copyWith(whiteNoiseSound: FocusSoundCatalog.none);
      _config.whiteNoiseSound = FocusSoundCatalog.none;
      await _touchAndSaveConfig();
      _persistedRevision++;
      notifyListeners();
      return false;
    }
    if (preview && normalized != FocusSoundCatalog.none && !_state.isRunning) {
      return _previewWhiteNoiseSound(normalized);
    }
    return true;
  }

  Future<bool> setFocusSoundVolume(double volume, {bool preview = true}) async {
    final normalized = volume
        .clamp(FocusSoundService.minimumAudibleVolume, 1.0)
        .toDouble();
    if (_config.focusSoundVolume == normalized) {
      if (preview && !_state.isRunning) {
        return _previewWhiteNoiseSound(_focusSoundPreviewFallback);
      }
      return true;
    }
    _config.focusSoundVolume = normalized;
    await _touchAndSaveConfig();
    _persistedRevision++;
    notifyListeners();
    await _sound.setVolume(normalized);
    if (preview && !_state.isRunning) {
      return _previewWhiteNoiseSound(_focusSoundPreviewFallback);
    }
    return true;
  }

  void recordFocusLeaveAppPenalty() {
    unawaited(_recordStrictFocusPenalty(FocusPenaltyReason.leaveApp));
  }

  Future<void> _recordStrictFocusPenalty(
    FocusPenaltyReason reason, {
    String? appPackage,
  }) async {
    if (!_config.strictFocusMode ||
        !_state.isRunning ||
        _state.type != PomodoroType.focus) {
      return;
    }
    final now = DateTime.now();
    final affectedSeconds =
        (_state.isCountUp
                ? _state.remainingSeconds.clamp(1, 24 * 60 * 60)
                : (_state.totalSeconds - _state.remainingSeconds).clamp(
                    1,
                    _state.totalSeconds,
                  ))
            .toInt();
    final penalty = PomodoroFocusPenalty(
      id: '${now.microsecondsSinceEpoch}_${reason.key}',
      occurredAt: now,
      reason: reason,
      affectedSeconds: affectedSeconds,
      taskName: _state.taskName,
      tag: _state.tag,
      focusRoomId: _state.focusRoomId,
      appPackage: appPackage,
    );
    final nextPenalties = [penalty, ..._penalties].take(100).toList();
    await _savePenaltyList(nextPenalties);
    _penalties = nextPenalties;
    _persistedRevision++;
    notifyListeners();
  }

  void _syncDistractionMonitorToState() {
    unawaited(_syncDistractionMonitor());
  }

  Future<void> _syncDistractionMonitor() async {
    final generation = ++_distractionSyncGeneration;
    final shouldMonitor =
        _config.strictFocusMode &&
        _config.monitorDistractingApps &&
        _state.isRunning &&
        _state.type == PomodoroType.focus;
    if (!shouldMonitor) {
      _distractionScanFailed = false;
      _stopDistractionMonitor();
      return;
    }
    final List<String> blocked;
    if (_config.isDistractionWhitelistMode) {
      if (_installedFocusAppsCache.isEmpty) {
        final apps = await _distraction.getInstalledApps();
        if (generation != _distractionSyncGeneration) return;
        if (apps.isNotEmpty) {
          _installedFocusAppsCache = apps;
          _distractionScanFailed = false;
        }
      }
      if (_installedFocusAppsCache.isEmpty) {
        // 扫描不可用：保留上次成功换算出的集合；没有旧集合就禁用拦截，
        // 绝不把空扫描结果当作“全部应用都不拦截”而悄悄改变语义。
        if (!_distractionScanFailed) {
          _distractionScanFailed = true;
          notifyListeners();
        }
        if (_effectiveDistractingPackages.isEmpty) {
          _stopDistractionMonitor();
          return;
        }
        blocked = _effectiveDistractingPackages;
      } else {
        blocked = PomodoroConfig.resolveBlockedDistractionPackages(
          selectionMode: _config.distractingAppSelectionMode,
          selectedPackages: _config.distractingAppPackages,
          launchablePackages: _installedFocusAppsCache.map(
            (app) => app.packageName,
          ),
        );
      }
    } else {
      blocked = PomodoroConfig.resolveBlockedDistractionPackages(
        selectionMode: _config.distractingAppSelectionMode,
        selectedPackages: _config.distractingAppPackages,
        launchablePackages: const <String>[],
      );
    }
    if (generation != _distractionSyncGeneration) return;
    _effectiveDistractingPackages = blocked;
    if (blocked.isEmpty) {
      _stopDistractionMonitor();
      return;
    }
    _distraction.setFocusBlocker(enabled: true, packages: blocked);
    _distractionTimer ??= Timer.periodic(
      const Duration(seconds: 20),
      (_) => _checkDistractingForegroundApp(),
    );
    unawaited(_checkDistractingForegroundApp());
  }

  void _stopDistractionMonitor() {
    _distractionTimer?.cancel();
    _distractionTimer = null;
    _lastDistractingPackage = null;
    _effectiveDistractingPackages = const <String>[];
    _distraction.setFocusBlocker(enabled: false, packages: const []);
  }

  Future<void> _checkDistractingForegroundApp() async {
    if (!_config.strictFocusMode ||
        !_config.monitorDistractingApps ||
        !_state.isRunning ||
        _state.type != PomodoroType.focus) {
      return;
    }
    final packageName = await _distraction.getForegroundApp();
    if (packageName == null || packageName.isEmpty) return;
    _distractionStatus = FocusDistractionStatus(
      supported: true,
      accessGranted: true,
      foregroundPackage: packageName,
    );
    final blocked = _config.isDistractionWhitelistMode
        ? _effectiveDistractingPackages
        : _config.distractingAppPackages;
    if (!blocked.contains(packageName)) {
      _lastDistractingPackage = null;
      notifyListeners();
      return;
    }
    if (_lastDistractingPackage == packageName) return;
    _lastDistractingPackage = packageName;
    unawaited(
      _recordStrictFocusPenalty(
        FocusPenaltyReason.distractingApp,
        appPackage: packageName,
      ),
    );
  }

  // --- 桌面小组件控制（绑定 session + revision + state） ---

  /// 当前控制身份：`idle` 也持久化并带独立 session，停止后旧 start 绑定失效。
  String get focusControlSessionId => _widgetSessionId;
  int get focusControlRevision => _widgetRevision;
  PomodoroWidgetTimerState get focusTimerState => _widgetTimerState;

  /// 原生倒计时锚点：倒计时运行中取 Provider 的 canonical 结束时刻（不按
  /// `now + remaining` 漂移）；正计时与非运行态为 0（原生改用 Chronometer）。
  int get focusTimerEndsAtMillis =>
      _state.isRunning && !_state.isCountUp ? (_activeAnchorMs ?? 0) : 0;

  /// 小组件控制入口。
  ///
  /// 执行前匹配 session + revision + state，任一不符直接拒绝并保持状态不变，
  /// 因此旧按钮、重复点击与“未来 revision”都不会改状态，也不会重复记惩罚。
  Future<bool> applyWidgetControl({
    required PomodoroWidgetControlAction action,
    required String sessionId,
    required int revision,
    required PomodoroWidgetTimerState expectedState,
  }) async {
    final generation = _storageGeneration;
    if (sessionId.isEmpty || sessionId != _widgetSessionId) return false;
    if (revision < 0 || revision != _widgetRevision) return false;
    if (expectedState != _widgetTimerState) return false;
    final current = _widgetTimerState;
    switch (action) {
      case PomodoroWidgetControlAction.start:
        // start 只接受 idle / paused；运行中重复 start 不改状态。
        if (current != PomodoroWidgetTimerState.idle &&
            current != PomodoroWidgetTimerState.paused) {
          return false;
        }
        if (current == PomodoroWidgetTimerState.paused) {
          _resumeFromPausedRuntime();
        } else {
          _startTimer();
        }
      case PomodoroWidgetControlAction.pause:
        if (current != PomodoroWidgetTimerState.running) return false;
        unawaited(_recordStrictFocusPenalty(FocusPenaltyReason.pause));
        _pauseTimer();
      case PomodoroWidgetControlAction.stop:
        if (current != PomodoroWidgetTimerState.running &&
            current != PomodoroWidgetTimerState.paused) {
          return false;
        }
        // stop 复用 resetTimer 语义：记 reset 惩罚、回满时长、不产生完成记录。
        resetTimer();
    }
    if (generation != _storageGeneration) return false;
    await _writeWidgetControl();
    await flushPersistence();
    return true;
  }

  /// 运行态的身份推进：session 保留（暂停续跑继续同一任务），revision +1。
  void _markTimerStarted() {
    if (_widgetSessionId.isEmpty) {
      _widgetSessionId = _newWidgetSessionId();
    }
    _widgetTimerState = PomodoroWidgetTimerState.running;
    _widgetRevision++;
    unawaited(_writeWidgetControl());
  }

  void _capturePausedRuntime() {
    final current = _state;
    _pausedRuntime = PomodoroPausedRuntime(
      type: current.type,
      remainingSeconds: current.remainingSeconds,
      totalSeconds: current.totalSeconds,
      isCountUp: current.isCountUp,
      completedSessions: current.completedSessions,
      taskName: current.taskName,
      todoId: current.todoId,
      subtaskId: current.subtaskId,
      todoTitle: current.todoTitle,
      tag: current.tag,
    );
  }

  /// 续跑：沿用暂停时记录的相位与任务绑定，不新开一次专注。
  void _resumeFromPausedRuntime() {
    final paused = _pausedRuntime;
    _pausedRuntime = null;
    if (paused != null) {
      _activeAnchorMs = null;
      _state = PomodoroState(
        remainingSeconds: paused.remainingSeconds,
        totalSeconds: paused.totalSeconds,
        isRunning: false,
        isCountUp: paused.isCountUp,
        type: paused.type,
        completedSessions: paused.completedSessions,
        taskName: paused.taskName,
        todoId: paused.todoId,
        subtaskId: paused.subtaskId,
        todoTitle: paused.todoTitle,
        whiteNoiseSound: _config.whiteNoiseSound,
        tag: paused.tag,
        focusRoomId: _config.focusRoomId,
      );
    }
    _startTimer();
  }

  /// 结束/停止/重置产生新的 idle 身份：旧按钮的 session/revision 立即失效。
  void _resetWidgetControlIdentity(PomodoroWidgetTimerState state) {
    _pausedRuntime = null;
    _widgetSessionId = _newWidgetSessionId();
    _widgetRevision = 0;
    _widgetTimerState = state;
    unawaited(_writeWidgetControl());
  }

  String _newWidgetSessionId() =>
      'focus-${DateTime.now().microsecondsSinceEpoch}';

  Map<String, dynamic> _widgetControlJson() => <String, dynamic>{
    'sessionId': _widgetSessionId,
    'revision': _widgetRevision,
    'state': _widgetTimerState.wireName,
    if (_pausedRuntime != null) 'paused': _pausedRuntime!.toJson(),
  };

  /// 串行写入控制记录：最后入队的状态必然是磁盘上的最终状态。
  Future<void> _writeWidgetControl() {
    final payload = json.encode(_widgetControlJson());
    _widgetControlWrites = _widgetControlWrites.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(widgetControlKey, payload);
      } catch (_) {
        // 控制元数据写入失败可容忍：下一次状态变化会整条重写。
      }
    });
    return _widgetControlWrites;
  }

  /// 后台动作 ACK 前等待当前控制记录与运行快照全部落盘。
  Future<void> flushPersistence() async {
    await _widgetControlWrites;
    final pendingSnapshot = _snapshotDrainDone;
    if (pendingSnapshot != null) await pendingSnapshot.future;
  }

  /// 启动时恢复控制身份；返回是否已从暂停态恢复出 [state]（调用方不要再 init）。
  bool _restoreWidgetControl(String? raw, {required bool snapshotHandled}) {
    Map<String, dynamic>? data;
    if (raw != null) {
      try {
        final decoded = json.decode(raw);
        if (decoded is Map) data = Map<String, dynamic>.from(decoded);
      } on FormatException {
        data = null;
      }
    }
    final sessionId = data?['sessionId']?.toString().trim() ?? '';
    final revision = (data?['revision'] as num?)?.toInt() ?? 0;
    final state = PomodoroWidgetTimerState.fromWire(data?['state']);

    if (_state.isRunning) {
      // 运行快照是权威：身份沿用记录；缺失/漂移则 +1，让旧按钮立即失效。
      _pausedRuntime = null;
      _widgetSessionId = sessionId.isNotEmpty
          ? sessionId
          : _newWidgetSessionId();
      _widgetRevision = revision < 0 ? 0 : revision;
      _widgetTimerState = PomodoroWidgetTimerState.running;
      if (sessionId.isEmpty || state != PomodoroWidgetTimerState.running) {
        _widgetRevision++;
      }
      unawaited(_writeWidgetControl());
      return false;
    }
    if (snapshotHandled) {
      // 逾期补结算已经生成过新身份，不能在这里覆盖。
      return false;
    }
    final paused = state == PomodoroWidgetTimerState.paused
        ? PomodoroPausedRuntime.fromJson(data?['paused'])
        : null;
    if (paused != null && sessionId.isNotEmpty) {
      _widgetSessionId = sessionId;
      _widgetRevision = revision < 0 ? 0 : revision;
      _widgetTimerState = PomodoroWidgetTimerState.paused;
      _pausedRuntime = paused;
      _state = PomodoroState(
        remainingSeconds: paused.remainingSeconds,
        totalSeconds: paused.totalSeconds,
        isRunning: false,
        isCountUp: paused.isCountUp,
        type: paused.type,
        completedSessions: paused.completedSessions,
        taskName: paused.taskName,
        todoId: paused.todoId,
        subtaskId: paused.subtaskId,
        todoTitle: paused.todoTitle,
        whiteNoiseSound: _config.whiteNoiseSound,
        tag: paused.tag,
        focusRoomId: _config.focusRoomId,
      );
      return true;
    }
    if (state == PomodoroWidgetTimerState.idle && sessionId.isNotEmpty) {
      _widgetSessionId = sessionId;
      _widgetRevision = revision < 0 ? 0 : revision;
      _widgetTimerState = PomodoroWidgetTimerState.idle;
      _pausedRuntime = null;
      unawaited(_writeWidgetControl());
      return false;
    }
    _resetWidgetControlIdentity(PomodoroWidgetTimerState.idle);
    return false;
  }

  // --- Queries ---

  List<PomodoroSession> getSessionsForDateRange(DateTime start, DateTime end) {
    return _sessions
        .where(
          (s) =>
              s.type == PomodoroType.focus &&
              !s.startTime.isBefore(start) &&
              s.startTime.isBefore(end),
        )
        .toList();
  }

  List<PomodoroSession> get todayFocusSessions {
    final now = AppClock.now();
    final start = AppClock.date(now.year, now.month, now.day);
    final end = AppClock.date(now.year, now.month, now.day + 1);
    return getSessionsForDateRange(start, end);
  }

  int get totalFocusMinutes {
    return _sessions
            .where((s) => s.type == PomodoroType.focus)
            .fold(0, (sum, s) => sum + s.durationSeconds) ~/
        60;
  }

  List<PomodoroFocusPenalty> get todayPenalties {
    final now = AppClock.now();
    return _penalties
        .where((p) => _isSameDay(p.occurredAt, now))
        .toList(growable: false);
  }

  @override
  void dispose() {
    _cancelTimer();
    if (_lifecycleAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleAttached = false;
    }
    // 不 dispose FocusSoundService（它是进程级单例），只停播。
    // ignore: discarded_futures
    _sound.stop();
    // ignore: discarded_futures
    _restoreFocusDndIfNeeded(notify: false);
    _distractionTimer?.cancel();
    _timerTicks.dispose();
    super.dispose();
  }
}

/// 单文件本地持久化的 JSON 编码条数阈值：超过后挪到后台 isolate 编码。
const int _isolateEncodeMinItems = 500;

/// 会话记录保留上限（超出裁剪最旧记录）。
const int _maxPomodoroSessions = 500;

/// 正计时崩溃恢复的累计上限（对齐 _completeSession 的 clamp(1, 24h)）。
const int _maxCountUpSnapshotSeconds = 24 * 60 * 60;

/// 暂停态快照：暂停时记录完整计时相位与任务绑定，重启/冷热切换后可继续同一
/// 剩余时长；[PomodoroProvider.runningSnapshotKey] 仍只表达“进程被杀时在跑”。
@immutable
class PomodoroPausedRuntime {
  final PomodoroType type;
  final int remainingSeconds;
  final int totalSeconds;
  final bool isCountUp;
  final int completedSessions;
  final String? taskName;
  final String? todoId;
  final String? subtaskId;
  final String? todoTitle;
  final String? tag;

  const PomodoroPausedRuntime({
    required this.type,
    required this.remainingSeconds,
    required this.totalSeconds,
    required this.isCountUp,
    required this.completedSessions,
    this.taskName,
    this.todoId,
    this.subtaskId,
    this.todoTitle,
    this.tag,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type.index,
    'remainingSeconds': remainingSeconds,
    'totalSeconds': totalSeconds,
    'isCountUp': isCountUp,
    'completedSessions': completedSessions,
    'taskName': taskName,
    'todoId': todoId,
    'subtaskId': subtaskId,
    'todoTitle': todoTitle,
    'tag': tag,
  };

  /// 损坏/越界返回 null：调用方按“无暂停态”处理，绝不恢复出非法时长。
  static PomodoroPausedRuntime? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final typeIndex = (map['type'] as num?)?.toInt();
    final remaining = (map['remainingSeconds'] as num?)?.toInt();
    final total = (map['totalSeconds'] as num?)?.toInt();
    if (typeIndex == null || remaining == null || total == null) return null;
    if (typeIndex < 0 || typeIndex >= PomodoroType.values.length) return null;
    if (remaining < 0 || total < 0) return null;
    final isCountUp = map['isCountUp'] == true;
    if (!isCountUp && (total <= 0 || remaining > total)) return null;
    return PomodoroPausedRuntime(
      type: PomodoroType.values[typeIndex],
      remainingSeconds: remaining,
      totalSeconds: total,
      isCountUp: isCountUp,
      completedSessions: (map['completedSessions'] as num?)?.toInt() ?? 0,
      taskName: map['taskName']?.toString(),
      todoId: map['todoId']?.toString(),
      subtaskId: map['subtaskId']?.toString(),
      todoTitle: map['todoTitle']?.toString(),
      tag: map['tag']?.toString(),
    );
  }
}

String _encodePomodoroSessionsPayload(List<PomodoroSession> sessions) =>
    json.encode(sessions.map((e) => e.toJson()).toList());
