import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_clock.dart';
import '../core/domain_event_bus.dart';
import '../core/focus_sound_catalog.dart';
import '../models/focus_runtime.dart';
import '../models/pomodoro.dart';
import '../services/focus_distraction_service.dart';
import '../services/focus_dnd_service.dart';
import '../services/focus_sound_service.dart';
import '../services/focus_timer_notification_service.dart';
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

  /// 远端权威模式的持久标记：进程重启后即使还没连上服务器，也绝不把旧的
  /// 本地运行快照当成自己的运行态去逾期结算。
  static const String focusRemoteMarkerKey = 'pomodoro_focus_remote_mode';

  /// [remoteClock] 仅测试注入；生产用服务端时钟校准 + 单调 Stopwatch 推进。
  PomodoroProvider({FocusRuntimeClock? remoteClock})
    : _remoteClock = remoteClock ?? FocusRuntimeClock();

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
  bool _isPaused = false;
  final ValueNotifier<int> _timerTicks = ValueNotifier<int>(0);
  List<PomodoroSession> _sessions = [];
  List<PomodoroFocusPenalty> _penalties = [];
  int _persistedRevision = 0;
  int _storageGeneration = 0;
  int _sessionCountToday = 0;
  String? _lastDate;
  NotificationService? _notifier;
  TimeAuditProvider? _timeAudit;

  // --- 同账号多端专注（远端权威投影） ---

  final FocusRuntimeClock _remoteClock;
  FocusRuntimeController? _focusRuntimeController;
  FocusRuntimeSnapshot? _remoteSnapshot;
  String? _remoteSessionId;
  int _remoteRevision = -1;
  FocusSyncMode _focusSyncMode = FocusSyncMode.local;

  /// 运行中任务/标签/房间的本地未确认草稿：权威回执不得覆盖用户刚改的值。
  Map<String, Object?>? _remotePendingTaskFields;

  /// 本地已知的历史墓碑（`sync_deleted_items`），远端回填不得复活被删记录。
  final Set<String> _deletedSessionIds = <String>{};
  bool _tombstonesLoaded = false;
  Future<void>? _remoteStorageLoad;
  bool? _remoteIdleCountUp;

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
  final FocusTimerNotificationService _focusTimer =
      FocusTimerNotificationService.instance;

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

  /// 已消费的原生拦截事件时间戳（epoch ms），用于与使用情况轮询互相去重。
  int _lastConsumedNativeBlockAtMs = 0;

  /// 当前写入原生的 blocker 失效时刻（epoch ms）；null 表示未写入。
  int? _blockerLeaseExpiresAtMs;

  int _distractionSyncGeneration = 0;

  PomodoroState get state => _state;

  /// 用户主动暂停；即使尚未经过一秒，也区别于尚未开始或重置。
  bool get isPaused => !_state.isRunning && _isPaused;
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

  // --- 同账号多端专注：公开投影状态（供 UI / 悬浮窗 / 小组件接线） ---

  /// 由 [FocusSyncCoordinator] 在根级绑定；传 null 表示回到纯本地模式。
  void attachFocusRuntimeController(FocusRuntimeController? controller) {
    _focusRuntimeController = controller;
    final nextMode = controller?.mode ?? FocusSyncMode.local;
    if (nextMode != _focusSyncMode) applyFocusSyncMode(nextMode);
  }

  FocusRuntimeController? get focusRuntimeController => _focusRuntimeController;

  /// 当前是否把服务端运行态当作权威投影（含“已登录但权威状态还在探测”）。
  ///
  /// 访客、明确无能力的旧后端或未绑定协调器时为 false，保持既有本地行为。
  bool get focusSyncEnabled => _focusSyncMode != FocusSyncMode.local;

  /// 已拿到权威快照（可以显示真实锚点，不允许本地结算）。
  bool get focusSyncReady =>
      focusSyncEnabled && (_focusRuntimeController?.ready ?? false);

  /// 实时通道已连上（断线时可继续显示最后确认状态，但不能跨端控制）。
  bool get focusSyncConnected =>
      focusSyncEnabled && (_focusRuntimeController?.connected ?? false);

  /// 有在途命令（重复点击必须被拒绝）。
  bool get focusSyncBusy =>
      focusSyncEnabled && (_focusRuntimeController?.busy ?? false);

  /// 本地/远端统一控制闸门：远端必须在已就绪、已连接且不在途时才可控制。
  bool get canControlFocus =>
      !focusSyncEnabled ||
      (focusSyncReady && focusSyncConnected && !focusSyncBusy);

  Object? get focusSyncError =>
      focusSyncEnabled ? _focusRuntimeController?.error : null;

  String? get remoteFocusSessionId => _remoteSessionId;

  int? get remoteFocusRevision => _remoteRevision < 0 ? null : _remoteRevision;

  FocusSyncMode get focusSyncMode => _focusSyncMode;

  FocusRuntimeSnapshot? get focusRuntimeSnapshot => _remoteSnapshot;

  /// 本机无凭证设备 ID（strict 监控只在发起设备生效）。
  String? get focusDeviceId => _focusRuntimeController?.deviceId;

  bool get _remoteLocked => _focusSyncMode != FocusSyncMode.local;

  bool get _remoteControlEnabled => _focusSyncMode == FocusSyncMode.remote;

  /// strict 监控只在“本机就是本阶段发起设备”时记处罚。
  bool get _remoteIsLocalSource {
    final deviceId = _focusRuntimeController?.deviceId?.trim();
    final source = _remoteSnapshot?.runtime.sourceDeviceId.trim();
    return deviceId != null && deviceId.isNotEmpty && deviceId == source;
  }

  /// 协调器在连接/权威/忙碌状态变化时调用；不改变投影本身。
  void notifyFocusSyncStateChanged() {
    notifyListeners();
  }

  /// 切换同步模式。remote/unknown 期间本地 tick、原生到期与本地完成一律停用。
  void applyFocusSyncMode(FocusSyncMode mode) {
    final previous = _focusSyncMode;
    if (previous == mode) {
      if (mode != FocusSyncMode.local) _persistRemoteMarker();
      return;
    }
    _focusSyncMode = mode;
    _storageGeneration++;
    _remoteStorageLoad = null;
    if (mode != FocusSyncMode.local) {
      _cancelTimer();
      _activeAnchorMs = null;
      _state = _state.copyWith(isRunning: false);
      _clearRunningSnapshot();
      _persistRemoteMarker();
      unawaited(_sound.stop());
      _syncDndToState();
      _syncDistractionMonitorToState();
    } else if (mode == FocusSyncMode.local) {
      _remoteSnapshot = null;
      _remoteSessionId = null;
      _remoteRevision = -1;
      _remotePendingTaskFields = null;
      _remoteIdleCountUp = null;
      _remoteClock.reset();
      _clearRemoteMarker();
      _cancelTimer();
      _timerTicks.value = 0;
      _initState();
      // 远端身份作废：旧按钮不能再控制本地计时。
      _resetWidgetControlIdentity(PomodoroWidgetTimerState.idle);
      _syncFocusTimerNotification();
    }
    notifyListeners();
  }

  /// 账号切换/协调器销毁：清投影、停远端 tick，不写任何完成记录或处罚。
  void clearRemoteRuntime() {
    _storageGeneration++;
    _remoteStorageLoad = null;
    _remoteSnapshot = null;
    _remoteSessionId = null;
    _remoteRevision = -1;
    _remotePendingTaskFields = null;
    _remoteIdleCountUp = null;
    _remoteClock.reset();
    _clearRemoteMarker();
    _cancelTimer();
    _activeAnchorMs = null;
    _state = _state.copyWith(isRunning: false);
    unawaited(_sound.stop());
    _syncDndToState();
    _syncDistractionMonitorToState();
    unawaited(_focusTimer.stop());
  }

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
    _focusTimer.onExpired = _handleNativeFocusTimerExpired;
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
      // 从系统设置页返回时必须无条件重读授权/连接状态：
      // 离开应用期间的“提前刷新”只能反映旧状态，不能作为最终判断。
      // ignore: discarded_futures
      refreshFocusDistractionStatus();
      _syncDistractionMonitorToState();
      _syncFocusTimerNotification();
    }
  }

  /// Hydrate history before the first remote upsert so existing records survive.
  Future<void> prepareRemoteHistory() =>
      _remoteStorageLoad ??= loadFromStorage();

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
    _loadDeletedSessionIds(prefs);
    // 先过跨天重置再恢复/结算，保证逾期补结算的当日计数归属恢复当天。
    _checkDayReset();
    // 远端权威模式（含“上次是远端、这次还没连上服务器”）：只加载历史与配置，
    // 不恢复本地运行快照、不恢复小组件控制身份、不 initState，也绝不走本地
    // 逾期结算——权威状态只能来自协调器随后拉到的快照。
    final markerPresent = prefs.getBool(focusRemoteMarkerKey) == true;
    final remoteRestore =
        _remoteLocked || (markerPresent && _focusRuntimeController == null);
    if (remoteRestore) {
      if (markerPresent && _focusRuntimeController == null && !_remoteLocked) {
        _focusSyncMode = FocusSyncMode.unknown;
      }
      if (_remoteSnapshot != null) {
        _projectRemoteState();
        if (_remoteSnapshot!.runtime.status.isRunning) _startRemoteTicker();
      } else {
        _cancelTimer();
      }
      _persistedRevision++;
      notifyListeners();
      _syncFocusTimerNotification();
      return;
    }
    if (markerPresent) _clearRemoteMarker();
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
    // 冷启动/热恢复后重新同步原生通知：运行态补上，无运行态清理僵尸通知。
    _syncFocusTimerNotification();
  }

  void resetLocalState() {
    _storageGeneration++;
    _cancelTimer();
    // 账号代际已推进：远端投影、设备效果与远端 tick 一并清理，
    // 不写完成记录/处罚，也不保留旧账号的会话身份。
    clearRemoteRuntime();
    _clearRunningSnapshot();
    // 新 idle 身份：换号/重置后旧小组件按钮的 session + revision 一律失效。
    _resetWidgetControlIdentity(PomodoroWidgetTimerState.idle);
    _timerTicks.value = 0;
    _config = PomodoroConfig();
    _sessions = [];
    _penalties = [];
    _deletedSessionIds.clear();
    _tombstonesLoaded = false;
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
    _lastConsumedNativeBlockAtMs = 0;
    _blockerLeaseExpiresAtMs = null;
    _distractionSyncGeneration++;
    // ignore: discarded_futures
    _distraction.setFocusBlocker(enabled: false, packages: const []);
    _focusTimer.stop();
    notifyListeners();
    notifyListeners();
  }

  void _initState() {
    _isPaused = false;
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
    final generation = _storageGeneration;
    final sessions = List<PomodoroSession>.of(_sessions);
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration) return;
    final data = sessions.length >= _isolateEncodeMinItems
        ? await compute(_encodePomodoroSessionsPayload, sessions)
        : json.encode(sessions.map((e) => e.toJson()).toList());
    if (generation != _storageGeneration) return;
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
    final generation = _storageGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration) return;
    await prefs.setString(
      'pomodoro_focus_penalties',
      json.encode(penalties.map((e) => e.toJson()).toList()),
    );
  }

  // --- 运行态快照（进程被杀重启后的恢复路径） ---

  /// 串行执行快照落盘操作；失败静默降级，不影响计时主流程。
  void _queueSnapshotOp(Future<void> Function(SharedPreferences) op) {
    final generation = _storageGeneration;
    _snapshotOps.add((prefs) async {
      if (generation != _storageGeneration) return;
      await op(prefs);
    });
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
    // 远端权威模式下标记来源：重启时即使还没连上服务器，也绝不把这条
    // 本地快照当成可结算的本地运行态。
    'remote': _remoteLocked,
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
      // 远端权威模式写下的快照只用于显示，重启时绝不当成本地运行态结算。
      if (data != null && data['remote'] == true) {
        await prefs.remove(runningSnapshotKey);
        return false;
      }
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
    _deletedSessionIds.add(removed.id);
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

  // --- 远端权威投影（服务端快照 → 本地显示，不产生任何本地结算） ---

  /// 应用权威快照。[FocusSyncCoordinator] 每条新事件/轮询/命令回执调用。
  ///
  /// 只接受当前身份的新 revision：同 revision 仅重新校准时间（不重置
  /// widgetRevision、不重复回填历史），旧 revision 直接忽略。返回是否有
  /// 新的历史记录（lastSession / lastPenalty）被幂等回填。
  bool applyRemoteSnapshot(FocusRuntimeSnapshot snapshot) {
    if (_focusSyncMode != FocusSyncMode.remote) return false;
    final runtime = snapshot.runtime;
    final sameSession = _remoteSessionId == runtime.sessionId;
    if (runtime.revision < _remoteRevision) return false;
    if (runtime.revision == _remoteRevision &&
        _remoteSnapshot != null &&
        (snapshot.serverNowMs < _remoteSnapshot!.serverNowMs ||
            snapshot.syncVersion < _remoteSnapshot!.syncVersion)) {
      return false;
    }
    final isNewRevision = runtime.revision > _remoteRevision;
    if (!sameSession && _remoteSessionId != null) {
      _remotePendingTaskFields = null;
      _remoteIdleCountUp = null;
    }
    _remoteClock.calibrate(snapshot.serverNowMs);
    _remoteSnapshot = snapshot;
    if (isNewRevision) {
      _remoteSessionId = runtime.sessionId;
      _remoteRevision = runtime.revision;
      // widget 身份镜像远端：迟到按钮在本地即失配，服务端还会再校验一次。
      _widgetSessionId = runtime.sessionId;
      _widgetRevision = runtime.revision;
    }
    _clearAcknowledgedRemoteDrafts(runtime);
    _projectRemoteState();
    if (isNewRevision) {
      _persistRemoteMarker();
      unawaited(_writeWidgetControl());
    }
    // 历史幂等回填：不发布完成领域事件、不写时间足迹、不覆盖本地未同步历史。
    if (!_tombstonesLoaded) unawaited(_ensureTombstonesLoaded());
    final sessionChanged = _upsertRemoteSession(snapshot.sessionRecord);
    final penaltyChanged = _upsertRemotePenalty(snapshot.penaltyRecord);
    unawaited(_syncSoundToState());
    _syncDndToState();
    _syncDistractionMonitorToState();
    _syncFocusTimerNotification();
    if (runtime.status.isRunning) {
      _startRemoteTicker();
    } else {
      _stopRemoteTicker();
    }
    notifyListeners();
    return sessionChanged || penaltyChanged;
  }

  /// 投影为 [PomodoroState]：倒计时剩余 ceil，正计时已用 floor，暂停冻结。
  void _projectRemoteState() {
    final snapshot = _remoteSnapshot;
    if (snapshot == null) return;
    final runtime = snapshot.runtime;
    final serverNowMs = _remoteClock.nowMs;
    final hasIdleDraft = runtime.status.isIdle && _remoteIdleCountUp != null;
    final isCountUp = hasIdleDraft
        ? _remoteIdleCountUp!
        : runtime.mode.isCountUp;
    final elapsedMs = runtime.effectiveElapsedMs(serverNowMs);
    final durationMs = hasIdleDraft
        ? (isCountUp ? 0 : _config.focusDuration * 1000)
        : runtime.durationMs;
    final int remainingSeconds;
    final int totalSeconds;
    if (isCountUp) {
      remainingSeconds = runtime.status.isIdle ? 0 : elapsedMs ~/ 1000;
      totalSeconds = 0;
    } else {
      final remainingMs = runtime.status.isIdle
          ? durationMs
          : (durationMs - elapsedMs).clamp(0, durationMs);
      remainingSeconds = (remainingMs + 999) ~/ 1000;
      totalSeconds = (durationMs / 1000).round();
    }
    final draft = _remotePendingTaskFields;
    String? draftValue(String key, String? fallback) =>
        draft == null ? fallback : draft[key] as String?;
    _state = PomodoroState(
      remainingSeconds: remainingSeconds,
      totalSeconds: totalSeconds,
      isRunning: runtime.status.isRunning,
      isCountUp: isCountUp,
      type: hasIdleDraft ? PomodoroType.focus : runtime.phase.pomodoroType,
      completedSessions: runtime.completedSessions,
      taskName: draftValue('taskName', runtime.taskName),
      todoId: draftValue('todoId', runtime.todoId),
      subtaskId: draftValue('subtaskId', runtime.subtaskId),
      todoTitle: draftValue('todoTitle', runtime.todoTitle),
      whiteNoiseSound: _config.whiteNoiseSound,
      tag: draftValue('tag', runtime.tag),
      focusRoomId: draftValue('focusRoomId', runtime.focusRoomId),
    );
    _pausedRuntime = null;
    _isPaused = runtime.status.isPaused;
    _widgetTimerState = switch (runtime.status) {
      FocusRuntimeStatus.running => PomodoroWidgetTimerState.running,
      FocusRuntimeStatus.paused => PomodoroWidgetTimerState.paused,
      FocusRuntimeStatus.idle => PomodoroWidgetTimerState.idle,
    };
    // 原生通知/小组件要的是本地 epoch 锚点：按当前换算结果反推。
    if (!runtime.status.isRunning) {
      _activeAnchorMs = null;
    } else {
      final localNow = DateTime.now().millisecondsSinceEpoch;
      if (isCountUp) {
        _activeAnchorMs = localNow - elapsedMs;
      } else {
        final remainingMs = durationMs - elapsedMs;
        _activeAnchorMs = localNow + (remainingMs < 0 ? 0 : remainingMs);
      }
    }
  }

  void _startRemoteTicker() {
    if (_timer?.isActive == true) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onRemoteTick());
  }

  void _stopRemoteTicker() {
    if (_focusSyncMode != FocusSyncMode.remote) return;
    _timer?.cancel();
    _timer = null;
  }

  /// 每秒只用“服务器时钟 + 单调时钟”重算，不做 ++/-- 累加，因此不漂移。
  void _onRemoteTick() {
    final snapshot = _remoteSnapshot;
    if (snapshot == null || _focusSyncMode != FocusSyncMode.remote) return;
    final runtime = snapshot.runtime;
    if (runtime.status.isIdle) return;
    _projectRemoteState();
    _notifyTimerTick();
    if (runtime.status.isRunning &&
        !runtime.mode.isCountUp &&
        (runtime.isExpired(_remoteClock.nowMs) ||
            _state.remainingSeconds <= 1)) {
      // 同步模式绝不在本地结算/自动轮转，只请求服务端快照。
      _requestRemoteRefresh();
    }
  }

  int? _lastRemoteRefreshAtMs;

  void _requestRemoteRefresh() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastRemoteRefreshAtMs;
    if (last != null && now - last < 5000) return;
    _lastRemoteRefreshAtMs = now;
    _focusRuntimeController?.requestRefresh();
  }

  /// 远端控制入口：网络动作只发显式命令，投影等服务端确认后再变。
  void _sendRemoteControl(
    FocusRuntimeAction action, {
    Map<String, dynamic>? payload,
  }) {
    unawaited(_sendRemoteControlAwaited(action, payload: payload));
  }

  Future<bool> _sendRemoteControlAwaited(
    FocusRuntimeAction action, {
    Map<String, dynamic>? payload,
  }) async {
    final controller = _focusRuntimeController;
    if (controller == null) return false;
    if (!canControlFocus) {
      controller.requestRefresh();
      return false;
    }
    try {
      return await controller.send(action, payload: payload);
    } catch (_) {
      // 协调器内部已捕获错误；这里兜底，绝不留下未处理 Future。
      return false;
    }
  }

  void _sendRemoteToggle() {
    final status = _remoteSnapshot?.runtime.status;
    if (status == null) {
      _focusRuntimeController?.requestRefresh();
      return;
    }
    switch (status) {
      case FocusRuntimeStatus.running:
        _sendRemoteControl(FocusRuntimeAction.pause);
      case FocusRuntimeStatus.paused:
        _sendRemoteControl(FocusRuntimeAction.resume);
      case FocusRuntimeStatus.idle:
        _sendRemoteControl(
          FocusRuntimeAction.start,
          payload: _remoteStartPayload(),
        );
    }
  }

  /// start 载荷：计时模式 + 本机会话配置 + 任务字段（idle 草稿在这里带上）。
  Map<String, dynamic> _remoteStartPayload() =>
      FocusRuntimeCommand.startPayload(
        mode: _state.isCountUp
            ? FocusRuntimeMode.countup
            : FocusRuntimeMode.countdown,
        config: _config.toJson(),
        phase: FocusRuntimePhase.fromPomodoroType(_state.type),
        taskName: _state.taskName,
        todoId: _state.todoId,
        subtaskId: _state.subtaskId,
        todoTitle: _state.todoTitle,
        tag: _state.tag,
        focusRoomId: _state.focusRoomId,
      );

  /// 运行中的任务/标签/房间编辑 → update 命令；idle 草稿留本地。
  void _maybeSendRemoteTaskUpdate() {
    if (!_remoteControlEnabled) return;
    final runtime = _remoteSnapshot?.runtime;
    if (runtime == null) return;
    final payload = FocusRuntimeCommand.updatePayload(
      taskName: _state.taskName,
      todoId: _state.todoId,
      subtaskId: _state.subtaskId,
      todoTitle: _state.todoTitle,
      tag: _state.tag,
      focusRoomId: _state.focusRoomId,
    );
    final draft = Map<String, Object?>.from(payload);
    _remotePendingTaskFields = draft;
    if (runtime.status.isIdle) return;
    final generation = _storageGeneration;
    unawaited(() async {
      await _sendRemoteControlAwaited(
        FocusRuntimeAction.update,
        payload: payload,
      );
      if (generation != _storageGeneration ||
          !identical(_remotePendingTaskFields, draft)) {
        return;
      }
      _remotePendingTaskFields = null;
      _projectRemoteState();
      notifyListeners();
    }());
  }

  /// 回执已经等于本地草稿时清除保护，之后的权威值可以正常覆盖。
  void _clearAcknowledgedRemoteDrafts(FocusRuntimeState runtime) {
    final draft = _remotePendingTaskFields;
    if (draft == null) return;
    final matches =
        (draft['taskName'] as String?) == runtime.taskName &&
        (draft['todoId'] as String?) == runtime.todoId &&
        (draft['subtaskId'] as String?) == runtime.subtaskId &&
        (draft['todoTitle'] as String?) == runtime.todoTitle &&
        (draft['tag'] as String?) == runtime.tag &&
        (draft['focusRoomId'] as String?) == runtime.focusRoomId;
    if (matches) _remotePendingTaskFields = null;
  }

  void _persistRemoteMarker() {
    _queueSnapshotOp((prefs) => prefs.setBool(focusRemoteMarkerKey, true));
  }

  void _clearRemoteMarker() {
    _queueSnapshotOp((prefs) => prefs.remove(focusRemoteMarkerKey));
  }

  // --- 远端历史幂等回填（不产生完成事件/时间足迹） ---

  void _loadDeletedSessionIds(SharedPreferences prefs) {
    if (_tombstonesLoaded) return;
    _tombstonesLoaded = true;
    try {
      final raw = prefs.getString(CloudSyncProvider.deletedItemsStorageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = json.decode(raw);
      if (decoded is! Map) return;
      final bucket = decoded['pomodoro_sessions'];
      if (bucket is! Map) return;
      for (final key in bucket.keys) {
        final id = key.toString().trim();
        if (id.isNotEmpty) _deletedSessionIds.add(id);
      }
    } catch (_) {
      // 墓碑解析失败按“无墓碑”处理，不阻塞历史加载。
    }
  }

  Future<void> _ensureTombstonesLoaded() async {
    if (_tombstonesLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _loadDeletedSessionIds(prefs);
    } catch (_) {}
  }

  /// 按 id + updatedAt 幂等 upsert；尊重墓碑，不删本地其它历史。
  bool _upsertRemoteSession(PomodoroSession? session) {
    if (session == null) return false;
    final index = _sessions.indexWhere((s) => s.id == session.id);
    if (index >= 0) {
      if (!session.updatedAt.isAfter(_sessions[index].updatedAt)) return false;
      _sessions[index] = session;
    } else {
      if (_deletedSessionIds.contains(session.id)) return false;
      _sessions.add(session);
      _trimSessions();
    }
    _sessionCountToday = todayFocusSessions.length;
    unawaited(_saveSessions());
    _persistedRevision++;
    return true;
  }

  bool _upsertRemotePenalty(PomodoroFocusPenalty? penalty) {
    if (penalty == null) return false;
    if (_penalties.any((p) => p.id == penalty.id)) return false;
    _penalties = <PomodoroFocusPenalty>[
      penalty,
      ..._penalties,
    ].take(100).toList();
    unawaited(_savePenaltyList(_penalties));
    _persistedRevision++;
    return true;
  }

  // --- Timer controls ---

  void toggleTimer() {
    if (_remoteLocked) {
      // 同步模式：只发显式命令，投影等服务端确认。
      _sendRemoteToggle();
      return;
    }
    if (_state.isRunning) {
      unawaited(_recordStrictFocusPenalty(FocusPenaltyReason.pause));
      _pauseTimer();
    } else {
      _startTimer();
    }
  }

  void startIfIdle() {
    if (_remoteLocked) {
      if ((_remoteSnapshot?.runtime.status ?? FocusRuntimeStatus.idle) ==
          FocusRuntimeStatus.idle) {
        _sendRemoteControl(
          FocusRuntimeAction.start,
          payload: _remoteStartPayload(),
        );
      }
      return;
    }
    if (_state.isRunning) return;
    _startTimer();
  }

  void _startTimer() {
    if (_remoteLocked) return;
    _isPaused = false;
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
      _syncFocusTimerNotification();
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
    _syncFocusTimerNotification();
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
    _isPaused = false;
    _timer?.cancel();
    _timer = null;
  }

  void _pauseTimer() {
    if (_remoteLocked) return;
    _cancelTimer();
    _isPaused = true;
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
    // 暂停：原生冻结通知时间并停止到期调度，不留下继续走的倒计时。
    _syncFocusTimerNotification();
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
    if (_remoteLocked) {
      // 同步模式绝不本地结算/自动轮转：只补拉权威快照。
      _requestRemoteRefresh();
      return;
    }
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
    // 相位已切换：运行态重推通知，非运行态（含正计时结束）清理运行通知。
    _syncFocusTimerNotification();
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
    if (_remoteLocked) {
      _sendRemoteControl(FocusRuntimeAction.skip);
      return;
    }
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
    _syncFocusTimerNotification();
    notifyListeners();
  }

  void resetTimer() {
    if (_remoteLocked) {
      _sendRemoteControl(FocusRuntimeAction.reset);
      return;
    }
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
    _syncFocusTimerNotification();
    notifyListeners();
  }

  void finishCurrentSession() {
    if (_remoteLocked) {
      final status = _remoteSnapshot?.runtime.status;
      if (status == null || status.isIdle) return;
      _sendRemoteControl(FocusRuntimeAction.finish);
      return;
    }
    if (_state.type != PomodoroType.focus) return;
    if (_state.isCountUp && !_state.isRunning && _state.remainingSeconds <= 0) {
      return;
    }
    _completeSession();
  }

  void setCountUpMode(bool enabled) {
    if (_remoteLocked) {
      final runtime = _remoteSnapshot?.runtime;
      if (!_remoteControlEnabled ||
          !canControlFocus ||
          runtime == null ||
          !runtime.status.isIdle) {
        return;
      }
      _remoteIdleCountUp = enabled;
      _projectRemoteState();
      notifyListeners();
      return;
    }
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
    _syncFocusTimerNotification();
    notifyListeners();
  }

  // --- Config ---

  Future<void> setConfig(PomodoroConfig cfg) async {
    _config = cfg;
    await _touchAndSaveConfig();
    _persistedRevision++;
    // 远端权威期间计时/总时长由服务端快照决定，本机配置只作为下一次 start 的载荷。
    if (_remoteLocked && _remoteSnapshot?.runtime.status.isIdle == true) {
      _remoteIdleCountUp ??= _state.isCountUp;
      _projectRemoteState();
    }
    if (!_state.isRunning && !_remoteLocked) {
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
    _syncFocusTimerNotification();
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
    // 通知里的关联任务名同步跟随。
    _syncFocusTimerNotification();
    _maybeSendRemoteTaskUpdate();
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
    _syncFocusTimerNotification();
    _persistRunningSnapshot();
    _maybeSendRemoteTaskUpdate();
  }

  void setTag(String? tag) {
    final clean = tag?.trim();
    _state = _state.copyWith(
      tag: clean,
      clearTag: clean == null || clean.isEmpty,
    );
    notifyListeners();
    _maybeSendRemoteTaskUpdate();
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
    // 运行中改房间 → update 命令；idle 草稿本地保留，下次 start 带上。
    _maybeSendRemoteTaskUpdate();
  }

  /// 重读原生授权/拦截/前台状态，并消费可能错过的原生拦截事件。
  ///
  /// 只在原生明确 `supported` 时整体覆盖授权字段；通道失败不同步清空已知授权，
  /// 避免“从设置页返回时先失败一次”把已授权状态刷成未授权。
  Future<void> refreshFocusDistractionStatus() async {
    final latest = await _distraction.getStatus();
    if (latest.supported) {
      _distractionStatus = latest;
    } else if (latest.foregroundPackage != null) {
      _distractionStatus = _distractionStatus.withForeground(
        latest.foregroundPackage,
      );
    }
    _consumeNativeBlockEvent();
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
    if (_remoteLocked) {
      // 同步模式：pause / skip / reset 的处罚由后端按命令一次记录，
      // Provider 不再重复记；设备本地 strict（离开应用/分心应用）只在
      // 本机就是本阶段发起设备时生效，远端 follow 不后台计处罚。
      if (reason != FocusPenaltyReason.leaveApp &&
          reason != FocusPenaltyReason.distractingApp) {
        return;
      }
      if (!_remoteIsLocalSource) return;
    }
    // 先快照状态：解析应用名是异步的，不能被期间的状态变化污染。
    final storageGeneration = _storageGeneration;
    final stateSnapshot = _state;
    final generation = _distractionSyncGeneration;
    final now = DateTime.now();
    final affectedSeconds =
        (stateSnapshot.isCountUp
                ? stateSnapshot.remainingSeconds.clamp(1, 24 * 60 * 60)
                : (stateSnapshot.totalSeconds - stateSnapshot.remainingSeconds)
                      .clamp(1, stateSnapshot.totalSeconds))
            .toInt();
    final resolvedAppLabel = appPackage == null
        ? null
        : await _resolveAppLabel(appPackage);
    if (reason == FocusPenaltyReason.distractingApp &&
        (generation != _distractionSyncGeneration || !_state.isRunning)) {
      return;
    }
    final penalty = PomodoroFocusPenalty(
      id: '${now.microsecondsSinceEpoch}_${reason.key}',
      occurredAt: now,
      reason: reason,
      affectedSeconds: affectedSeconds,
      taskName: stateSnapshot.taskName,
      tag: stateSnapshot.tag,
      focusRoomId: stateSnapshot.focusRoomId,
      appPackage: appPackage,
      appLabel: resolvedAppLabel,
    );
    final nextPenalties = [penalty, ..._penalties].take(100).toList();
    await _savePenaltyList(nextPenalties);
    if (storageGeneration != _storageGeneration) return;
    _penalties = nextPenalties;
    _persistedRevision++;
    notifyListeners();
  }

  /// 分心应用显示名：优先用已安装应用缓存，缺失时问原生 `getAppLabel`。
  Future<String?> _resolveAppLabel(String packageName) async {
    final clean = packageName.trim();
    if (clean.isEmpty) return null;
    for (final app in _installedFocusAppsCache) {
      if (app.packageName != clean) continue;
      final label = app.label.trim();
      if (label.isNotEmpty) return label;
    }
    final nativeLabel = await _distraction.getAppLabel(clean);
    if (nativeLabel != null && nativeLabel.isNotEmpty) return nativeLabel;
    return null;
  }

  void _syncDistractionMonitorToState() {
    unawaited(_syncDistractionMonitor());
  }

  Future<void> _syncDistractionMonitor() async {
    final generation = ++_distractionSyncGeneration;
    final shouldMonitor =
        _config.strictFocusMode &&
        (!_remoteLocked || _remoteIsLocalSource) &&
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
    await _applyBlockerConfig(blocked);
    if (generation != _distractionSyncGeneration || !_state.isRunning) return;
    _distractionTimer ??= Timer.periodic(
      const Duration(seconds: 20),
      (_) => _checkDistractingForegroundApp(),
    );
    unawaited(_checkDistractingForegroundApp());
  }

  /// 写入原生拦截配置并带上有限失效时刻：进程被杀后不会永久拦截。
  ///
  /// 倒计时用会话结束锚点；正计时给出有限租约，由轮询定期续租。
  Future<void> _applyBlockerConfig(List<String> packages) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final expiresAtMs = FocusBlockerLease.expiresAtMs(
      isCountUp: _state.isCountUp,
      activeAnchorMs: _activeAnchorMs,
      remainingSeconds: _state.remainingSeconds,
      nowMs: nowMs,
    );
    _blockerLeaseExpiresAtMs = expiresAtMs;
    await _distraction.setFocusBlocker(
      enabled: true,
      packages: packages,
      expiresAtMs: expiresAtMs,
    );
  }

  /// 正计时租约快到期时续租；倒计时锚点即会话结束，无需续租。
  void _renewBlockerLeaseIfNeeded() {
    if (!_state.isRunning || _distractionTimer == null) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!FocusBlockerLease.needsRenewal(
      expiresAtMs: _blockerLeaseExpiresAtMs,
      nowMs: nowMs,
    )) {
      return;
    }
    final blocked = _blockedPackagesForDetection();
    if (blocked.isEmpty) return;
    unawaited(_applyBlockerConfig(blocked));
  }

  void _stopDistractionMonitor() {
    _distractionSyncGeneration++;
    _distractionTimer?.cancel();
    _distractionTimer = null;
    _lastDistractingPackage = null;
    _effectiveDistractingPackages = const <String>[];
    _blockerLeaseExpiresAtMs = null;
    // ignore: discarded_futures
    _distraction.setFocusBlocker(enabled: false, packages: const []);
  }

  /// 当前参与前台检测的包集合：白名单模式用换算结果，黑名单模式直接用配置。
  List<String> _blockedPackagesForDetection() {
    return _config.isDistractionWhitelistMode
        ? _effectiveDistractingPackages
        : _config.distractingAppPackages;
  }

  Future<void> _checkDistractingForegroundApp() async {
    if (!_config.strictFocusMode ||
        !_config.monitorDistractingApps ||
        !_state.isRunning ||
        _state.type != PomodoroType.focus) {
      return;
    }
    final generation = _distractionSyncGeneration;
    final latest = await _distraction.getStatus();
    if (generation != _distractionSyncGeneration ||
        !_state.isRunning ||
        _distractionTimer == null) {
      return;
    }
    // 轮询只更新前台包/最近拦截事件：授权与拦截配置字段绝不能被重新构造丢掉。
    if (latest.supported) {
      _distractionStatus = latest;
    } else if (latest.foregroundPackage != null) {
      _distractionStatus = _distractionStatus.withForeground(
        latest.foregroundPackage,
      );
    }
    _consumeNativeBlockEvent();
    _renewBlockerLeaseIfNeeded();
    final packageName = latest.foregroundPackage;
    if (packageName == null || packageName.isEmpty) {
      notifyListeners();
      return;
    }
    final blocked = _blockedPackagesForDetection();
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

  /// 消费原生无障碍服务“已拦截并拉回”的事件。
  ///
  /// 快速弹回时使用情况轮询看不到分心应用的前台记录，必须用它补记真实的
  /// 分心应用；与轮询共用 [_lastDistractingPackage] 去重，同一包名只记一次。
  void _consumeNativeBlockEvent() {
    if (!_state.isRunning ||
        !_config.strictFocusMode ||
        !_config.monitorDistractingApps ||
        _state.type != PomodoroType.focus) {
      return;
    }
    final event = FocusNativeBlockEvent.fromStatus(_distractionStatus);
    if (event == null) return;
    final anchor = _activeAnchorMs;
    final sessionStartedAtMs = anchor == null
        ? DateTime.now().millisecondsSinceEpoch
        : _state.isCountUp
        ? anchor
        : anchor - _state.totalSeconds * 1000;
    final shouldRecord = event.shouldRecord(
      lastConsumedBlockedAtMs: _lastConsumedNativeBlockAtMs,
      lastRecordedPackage: _lastDistractingPackage,
      blockedPackages: _blockedPackagesForDetection(),
      notBeforeMs: sessionStartedAtMs,
    );
    if (event.blockedAtMs > _lastConsumedNativeBlockAtMs) {
      _lastConsumedNativeBlockAtMs = event.blockedAtMs;
    }
    if (!shouldRecord) return;
    _lastDistractingPackage = event.packageName;
    unawaited(
      _recordStrictFocusPenalty(
        FocusPenaltyReason.distractingApp,
        appPackage: event.packageName,
      ),
    );
  }

  /// 计时状态 → 原生持续通知；非运行且非暂停时清理运行通知。
  ///
  /// 同步必须带 canonical 锚点与真实控制身份：原生据此折算时间（主题/语言重推
  /// 不会延长期限），并用 session + revision + state 生成可操作按钮。
  void _syncFocusTimerNotification() {
    if (_state.isRunning) {
      unawaited(
        _focusTimer.sync(
          _state,
          paused: false,
          anchorMillis: focusTimerAnchorMillis,
          controlSessionId: _widgetSessionId,
          controlRevision: _widgetRevision,
          controlState: _widgetTimerState.wireName,
        ),
      );
    } else if (_isPaused) {
      unawaited(
        _focusTimer.sync(
          _state,
          paused: true,
          controlSessionId: _widgetSessionId,
          controlRevision: _widgetRevision,
          controlState: _widgetTimerState.wireName,
        ),
      );
    } else {
      unawaited(_focusTimer.stop());
    }
  }

  /// 原生通知倒计时先到期：Dart 计时器可能被系统延迟，这里补一次结算。
  Future<void> _handleNativeFocusTimerExpired() async {
    if (_remoteLocked) {
      // 同步模式：原生到期只提示补拉，服务端才结算/轮转。
      _requestRemoteRefresh();
      return;
    }
    if (!_state.isRunning || _state.isCountUp) return;
    if (_state.remainingSeconds > 1) return;
    _completeSession();
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

  /// 通知同步用的 canonical 锚点（真实 instant，epoch ms）：倒计时=结束时刻，
  /// 正计时=开始时刻；暂停与非运行态为 0（原生冻结在传入的剩余值）。
  ///
  /// 与 [focusTimerEndsAtMillis] 的区别：正计时也给出锚点，原生才能按
  /// `now - anchor` 计算已计时；主题/语言重推时锚点不变，因此不会延长期限。
  int get focusTimerAnchorMillis =>
      !_state.isRunning || _isPaused ? 0 : (_activeAnchorMs ?? 0);

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
    if (_remoteLocked) {
      // 先过本地 session/revision/state 校验，再映射到远端 expected 会话版本；
      // 迟到按钮在本地就失配，服务端还会用 expectedRevision 再拒一次。
      return _applyRemoteWidgetControl(action: action, current: current);
    }
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

  /// 小组件控制 → 远端显式命令；服务端确认后投影才变化。
  Future<bool> _applyRemoteWidgetControl({
    required PomodoroWidgetControlAction action,
    required PomodoroWidgetTimerState current,
  }) async {
    final runtime = _remoteSnapshot?.runtime;
    if (runtime == null || !_remoteControlEnabled) return false;
    final FocusRuntimeAction remoteAction;
    switch (action) {
      case PomodoroWidgetControlAction.start:
        if (current == PomodoroWidgetTimerState.running) return false;
        remoteAction = current == PomodoroWidgetTimerState.paused
            ? FocusRuntimeAction.resume
            : FocusRuntimeAction.start;
      case PomodoroWidgetControlAction.pause:
        if (current != PomodoroWidgetTimerState.running) return false;
        remoteAction = FocusRuntimeAction.pause;
      case PomodoroWidgetControlAction.stop:
        if (current == PomodoroWidgetTimerState.idle) return false;
        remoteAction = FocusRuntimeAction.stop;
    }
    final generation = _storageGeneration;
    final accepted = await _sendRemoteControlAwaited(
      remoteAction,
      payload: remoteAction == FocusRuntimeAction.start
          ? _remoteStartPayload()
          : null,
    );
    if (!accepted) return false;
    if (generation != _storageGeneration) return false;
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
    // 账号代际在等待期间可能已推进：旧代际的落盘结果不再作为本次 ACK 依据。
    final generation = _storageGeneration;
    await _widgetControlWrites;
    final pendingSnapshot = _snapshotDrainDone;
    if (pendingSnapshot != null) await pendingSnapshot.future;
    if (generation != _storageGeneration) return;
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
      _isPaused = true;
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
    _focusTimer.onExpired = null;
    unawaited(_focusTimer.stop());
    unawaited(_distraction.setFocusBlocker(enabled: false, packages: const []));
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
