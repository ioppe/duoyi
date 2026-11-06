/// 同账号多端专注的根级协调器。
///
/// 职责：
/// - 按服务器 / 用户 / 凭证代际绑定 [AuthProvider]，旧代际的 HTTP / WS 响应
///   与持久写入一律丢弃；
/// - 判定能力：`GET /api/config` 的 `features.focus_runtime_sync`。未知 /
///   加载中 / 网络失败时保持“等待权威状态”，不冒充旧后端；只有明确关闭
///   或明确 404 才回退设备本地专注；
/// - 维护唯一一条 WS 连接（`/ws/focus/runtime/events`），断开后走有界退避
///   重连，同时用 HTTP 轮询兜底；不制造多套连接；
/// - 把权威快照交给 [PomodoroProvider] 投影，并把 Provider 的显式控制动作
///   转成命令；控制失败只补拉快照，绝不盲重放旧命令。
///
/// 生命周期由应用根部持有（不随页面销毁）。main 在认证关键存储加载后、
/// Provider 延迟加载前调用 [start]；账号清理开始时先 await
/// [resetForAccountChange]。
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/feature_flags.dart';
import '../models/focus_runtime.dart';
import '../providers/auth_provider.dart';
import '../providers/pomodoro_provider.dart';
import 'api_client.dart';
import 'focus_runtime_api.dart';

class FocusSyncCoordinator
    with WidgetsBindingObserver
    implements FocusRuntimeController {
  /// 无凭证的设备本地偏好；普通账号清理时保留。
  static const String deviceIdStorageKey = 'duoyi_focus_sync_device_id';

  /// WS 重连退避上限（有界，不无限翻倍）。
  static const List<Duration> defaultReconnectBackoff = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 30),
  ];

  FocusSyncCoordinator({
    required this.auth,
    required this.pomodoro,
    this.onHistoryChanged,
    FocusRuntimeSocketFactory? socketFactory,
    this.pollInterval = const Duration(seconds: 15),
    this.probeRetryDelay = const Duration(seconds: 5),
    this.minRefreshInterval = const Duration(seconds: 2),
    List<Duration> reconnectBackoff = defaultReconnectBackoff,
  }) : _socketFactory = socketFactory ?? defaultFocusRuntimeSocketFactory,
       _reconnectBackoff = reconnectBackoff.isEmpty
           ? defaultReconnectBackoff
           : reconnectBackoff;

  final AuthProvider auth;
  final PomodoroProvider pomodoro;

  /// 远端回填 lastSession / lastPenalty 后触发，供主会话补全时间足迹/云同步。
  final Future<void> Function()? onHistoryChanged;

  /// 断线期间 HTTP 轮询兜底间隔。
  final Duration pollInterval;

  /// 能力探测失败后的重试间隔（保持 unknown，不回退本地）。
  final Duration probeRetryDelay;

  /// 主动补拉的最小间隔（避免到期/按钮风暴打爆接口）。
  final Duration minRefreshInterval;

  final FocusRuntimeSocketFactory _socketFactory;
  final List<Duration> _reconnectBackoff;

  int _generation = 0;
  _FocusIdentity? _identity;
  String? _suspendedIdentityKey;
  FocusSyncMode _mode = FocusSyncMode.unknown;
  FocusRuntimeSnapshot? _snapshot;
  FocusRuntimeApi? _api;
  String? _apiIdentityKey;
  FocusRuntimeSocket? _socket;
  StreamSubscription<Object?>? _socketSubscription;
  Timer? _reconnectTimer;
  Timer? _pollTimer;
  Timer? _probeTimer;
  int _reconnectAttempt = 0;
  bool _connected = false;
  bool _ready = false;
  bool _busy = false;
  bool _started = false;
  bool _disposed = false;
  bool _lifecycleAttached = false;
  Object? _error;
  String? _deviceId;
  DateTime? _lastRefreshAt;
  int? _probeGeneration;

  // --- FocusRuntimeController ---

  @override
  FocusSyncMode get mode => _mode;

  @override
  bool get ready => _ready;

  @override
  bool get connected => _connected;

  @override
  bool get busy => _busy;

  @override
  Object? get error => _error;

  @override
  String? get deviceId => _deviceId;

  @override
  String? get runtimeSessionId => _snapshot?.runtime.sessionId;

  @override
  int? get runtimeRevision => _snapshot?.runtime.revision;

  @override
  FocusRuntimeSnapshot? get snapshot => _snapshot;

  /// 已登录账号的稳定身份（server + user + token），用于代际比对。
  String? get identityKey => _identity?.key;

  // --- 生命周期 ---

  /// 应用根部调用；幂等。离开专注页不停止连接。
  void start() {
    if (_started || _disposed) return;
    _started = true;
    auth.addListener(_handleAuthChanged);
    pomodoro.attachFocusRuntimeController(this);
    try {
      WidgetsBinding.instance.addObserver(this);
      _lifecycleAttached = true;
    } catch (_) {
      // 纯 Dart 环境（单测/后台）没有 WidgetsBinding：跳过生命周期监听。
      _lifecycleAttached = false;
    }
    unawaited(_ensureDeviceId());
    _handleAuthChanged();
  }

  /// 账号清理开始：先同步失效代际、断开连接、停止重连，等新身份再重启。
  Future<void> resetForAccountChange() async {
    _suspendedIdentityKey = _identity?.key;
    _generation++;
    _cancelTimers();
    final socket = _socket;
    _socket = null;
    _cancelSocketSubscription();
    if (socket != null) await socket.close();
    _identity = null;
    _api = null;
    _apiIdentityKey = null;
    _snapshot = null;
    _ready = false;
    _connected = false;
    _busy = false;
    _error = null;
    _reconnectAttempt = 0;
    _lastRefreshAt = null;
    _mode = FocusSyncMode.unknown;
    pomodoro.clearRemoteRuntime();
    pomodoro.applyFocusSyncMode(FocusSyncMode.unknown);
    _notifyPomodoro();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    if (_started) auth.removeListener(_handleAuthChanged);
    if (_lifecycleAttached) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
      _lifecycleAttached = false;
    }
    _cancelTimers();
    final socket = _socket;
    _socket = null;
    _cancelSocketSubscription();
    if (socket != null) unawaited(socket.close());
    pomodoro.attachFocusRuntimeController(null);
    pomodoro.clearRemoteRuntime();
    _snapshot = null;
    _ready = false;
    _connected = false;
    _busy = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_mode != FocusSyncMode.remote) {
      if (_identity != null) _resolveCapability();
      return;
    }
    if (!_connected) {
      _reconnectAttempt = 0;
      _connectSocket();
    }
    unawaited(_refreshSnapshot(force: true));
  }

  // --- 身份 / 能力 ---

  void _handleAuthChanged() {
    if (_disposed) return;
    final identity = _currentIdentity();
    final suspended = _suspendedIdentityKey;
    if (suspended != null) {
      if (identity?.key == suspended) return; // 仍在旧身份，等待换号结束
      _suspendedIdentityKey = null;
    }
    if (identity == null) {
      _identity = null;
      if (_mode != FocusSyncMode.local) _enterLocal();
      return;
    }
    if (identity.key == _identity?.key) {
      if (_mode == FocusSyncMode.remote) {
        // 同一身份下配置加载完成/刷新：不重连，只在从未就绪时补一次快照。
        if (!_ready) unawaited(_refreshSnapshot());
        return;
      }
      _resolveCapability();
      return;
    }
    _beginIdentity(identity);
  }

  void _beginIdentity(_FocusIdentity identity) {
    _generation++;
    _cancelTimers();
    _cancelSocketSubscription();
    final socket = _socket;
    _socket = null;
    if (socket != null) unawaited(socket.close());
    _identity = identity;
    _api = null;
    _apiIdentityKey = null;
    _snapshot = null;
    _ready = false;
    _connected = false;
    _busy = false;
    _error = null;
    _reconnectAttempt = 0;
    _lastRefreshAt = null;
    _mode = FocusSyncMode.unknown;
    pomodoro.clearRemoteRuntime();
    pomodoro.applyFocusSyncMode(FocusSyncMode.unknown);
    _notifyPomodoro();
    _resolveCapability();
  }

  void _resolveCapability() {
    final identity = _identity;
    if (identity == null || _disposed) return;
    if (!FeatureFlags.cloudSyncV2) {
      // 个人数据边界关闭：不发个人专注请求，退回本地。
      _enterLocal();
      return;
    }
    final generation = _generation;
    switch (focusRuntimeFeatureState(auth.serverConfig)) {
      case FocusRuntimeFeatureState.disabled:
        _enterLocal();
      case FocusRuntimeFeatureState.enabled:
        _enterRemote();
      case FocusRuntimeFeatureState.unknown:
        // 已登录且能力未知：探测权威状态，绝不假装旧后端。
        unawaited(_probeCapability(generation));
    }
  }

  Future<void> _probeCapability(int generation) async {
    final identity = _identity;
    if (identity == null ||
        _mode == FocusSyncMode.remote ||
        _probeGeneration == generation) {
      return;
    }
    _probeGeneration = generation;
    try {
      final api = _apiFor(identity);
      final snapshot = await api.fetchRuntime();
      if (!_isCurrent(generation)) return;
      _enterRemote();
      await _applySnapshot(snapshot);
    } catch (error) {
      if (!_isCurrent(generation)) return;
      if (_mode == FocusSyncMode.remote) return;
      if (isFocusRuntimeRouteMissing(error)) {
        _enterLocal();
        return;
      }
      // 网络失败/超时：保持未知，稍后重试；不得退回独立本地。
      _error = error;
      _ready = false;
      _notifyPomodoro();
      _scheduleProbeRetry(generation);
    } finally {
      if (_probeGeneration == generation) _probeGeneration = null;
    }
  }

  void _scheduleProbeRetry(int generation) {
    _probeTimer?.cancel();
    _probeTimer = Timer(probeRetryDelay, () {
      if (_disposed || generation != _generation) return;
      if (_mode == FocusSyncMode.remote) return;
      _resolveCapability();
    });
  }

  void _enterLocal() {
    _generation++;
    _cancelTimers();
    _cancelSocketSubscription();
    final socket = _socket;
    _socket = null;
    if (socket != null) unawaited(socket.close());
    _api = null;
    _apiIdentityKey = null;
    _snapshot = null;
    _ready = false;
    _connected = false;
    _busy = false;
    _error = null;
    _reconnectAttempt = 0;
    _lastRefreshAt = null;
    final changed = _mode != FocusSyncMode.local;
    _mode = FocusSyncMode.local;
    if (changed) {
      pomodoro.applyFocusSyncMode(FocusSyncMode.local);
      if (_identity != null) unawaited(pomodoro.prepareRemoteHistory());
    }
    _notifyPomodoro();
  }

  void _enterRemote() {
    if (_disposed || _identity == null || _mode == FocusSyncMode.remote) return;
    _mode = FocusSyncMode.remote;
    pomodoro.applyFocusSyncMode(FocusSyncMode.remote);
    _notifyPomodoro();
    _connectSocket();
    unawaited(_refreshSnapshot(force: true));
  }

  _FocusIdentity? _currentIdentity() {
    final state = auth.state;
    if (!state.isLoggedIn) return null;
    final token = state.token?.trim();
    if (token == null || token.isEmpty) return null;
    return _FocusIdentity(
      server: auth.baseUrl.trim(),
      userId: state.userId,
      token: token,
      client: auth.client,
    );
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _generation && _identity != null;

  FocusRuntimeApi _apiFor(_FocusIdentity identity) {
    final cached = _api;
    if (cached != null && _apiIdentityKey == identity.key) return cached;
    final api = FocusRuntimeApi(
      identity.client,
      socketFactory: _socketFactory,
      tokenOverride: identity.token,
    );
    _api = api;
    _apiIdentityKey = identity.key;
    return api;
  }

  // --- 快照 ---

  /// 补拉权威快照（到期、断线、控制失败、生命周期恢复）。
  @override
  void requestRefresh() {
    if (_mode != FocusSyncMode.remote) return;
    unawaited(_refreshSnapshot());
  }

  Future<void> _refreshSnapshot({bool force = false}) async {
    if (_disposed || _mode != FocusSyncMode.remote) return;
    final identity = _identity;
    if (identity == null) return;
    final now = DateTime.now();
    final last = _lastRefreshAt;
    if (!force && last != null && now.difference(last) < minRefreshInterval) {
      return;
    }
    _lastRefreshAt = now;
    final generation = _generation;
    try {
      final snapshot = await _apiFor(identity).fetchRuntime();
      if (!_isCurrent(generation)) return;
      await _applySnapshot(snapshot);
    } catch (error) {
      if (!_isCurrent(generation)) return;
      if (isFocusRuntimeRouteMissing(error)) {
        // 后端明确没有该路由：这才是旧后端，回退本地。
        _enterLocal();
        return;
      }
      _error = error;
      _notifyPomodoro();
    }
  }

  Future<void> _applySnapshot(FocusRuntimeSnapshot snapshot) async {
    final generation = _generation;
    try {
      await pomodoro.prepareRemoteHistory();
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _error = error;
      _notifyPomodoro();
      return;
    }
    if (!_isCurrent(generation) || _mode != FocusSyncMode.remote) return;
    final current = _snapshot;
    if (current != null &&
        (snapshot.runtime.revision < current.runtime.revision ||
            (snapshot.runtime.revision == current.runtime.revision &&
                (snapshot.serverNowMs < current.serverNowMs ||
                    snapshot.syncVersion < current.syncVersion)))) {
      return;
    }
    _snapshot = snapshot;
    _ready = true;
    _error = null;
    final historyChanged = pomodoro.applyRemoteSnapshot(snapshot);
    _notifyPomodoro();
    if (historyChanged) unawaited(_notifyHistoryChanged());
  }

  Future<void> _notifyHistoryChanged() async {
    final callback = onHistoryChanged;
    if (callback == null) return;
    try {
      await callback();
    } catch (_) {
      // 云同步补全失败不影响权威投影；下次事件会再触发。
    }
  }

  // --- 命令 ---

  @override
  Future<bool> send(
    FocusRuntimeAction action, {
    Map<String, dynamic>? payload,
  }) async {
    if (_disposed || _mode != FocusSyncMode.remote) return false;
    final identity = _identity;
    final snapshot = _snapshot;
    if (identity == null || snapshot == null) return false;
    if (_busy || !_ready || !_connected) return false;
    final generation = _generation;
    final deviceId = await _ensureDeviceId();
    if (!_isCurrent(generation) || _mode != FocusSyncMode.remote) return false;
    if (_busy) return false;
    if (auth.state.token?.trim() != identity.token) return false;
    final command = FocusRuntimeCommand.create(
      deviceId: deviceId,
      sessionId: snapshot.runtime.sessionId,
      expectedRevision: snapshot.runtime.revision,
      action: action,
      payload: payload,
    );
    _busy = true;
    _error = null;
    _notifyPomodoro();
    try {
      final next = await _apiFor(identity).sendCommand(command);
      if (!_isCurrent(generation)) return false;
      await _applySnapshot(next);
      return true;
    } catch (error) {
      if (!_isCurrent(generation)) return false;
      _error = error;
      // 控制错误（409/网络）：不重放旧命令，直接读取权威快照。
      if (isFocusRuntimeRouteMissing(error)) {
        _enterLocal();
        return false;
      }
      await _refreshSnapshot(force: true);
      return false;
    } finally {
      if (generation == _generation) {
        _busy = false;
        _notifyPomodoro();
      }
    }
  }

  // --- WebSocket ---

  void _connectSocket() {
    if (_disposed || _mode != FocusSyncMode.remote) return;
    final identity = _identity;
    if (identity == null) return;
    final generation = _generation;
    _cancelSocketSubscription();
    final previous = _socket;
    _socket = null;
    if (previous != null) unawaited(previous.close());
    final api = _apiFor(identity);
    final uri = api.eventsUri();
    if (uri == null) {
      _handleSocketLost(generation);
      return;
    }
    FocusRuntimeSocket socket;
    try {
      socket = _socketFactory(uri);
    } catch (error) {
      FocusRuntimeApi.debugRealtimeError(
        'connect',
        error,
        token: identity.token,
      );
      _handleSocketLost(generation);
      return;
    }
    _socket = socket;
    _socketSubscription = socket.messages.listen(
      (raw) {
        if (!identical(_socket, socket)) return;
        final snapshot = FocusRuntimeApi.parseEventMessage(raw);
        if (snapshot == null) return;
        if (!_isCurrent(generation)) return;
        if (!_connected) {
          _connected = true;
          _reconnectAttempt = 0;
          _stopPolling();
          _error = null;
          _notifyPomodoro();
        }
        unawaited(_applySnapshot(snapshot));
      },
      onError: (Object error) {
        if (!identical(_socket, socket)) return;
        FocusRuntimeApi.debugRealtimeError(
          'socket',
          error,
          token: identity.token,
        );
        _handleSocketLost(generation);
      },
      onDone: () {
        if (identical(_socket, socket)) _handleSocketLost(generation);
      },
      cancelOnError: true,
    );
  }

  void _handleSocketLost(int generation) {
    if (_disposed || generation != _generation) return;
    if (_mode != FocusSyncMode.remote) return;
    _connected = false;
    _cancelSocketSubscription();
    final socket = _socket;
    _socket = null;
    if (socket != null) unawaited(socket.close());
    _notifyPomodoro();
    _startPolling();
    _scheduleReconnect(generation);
  }

  void _scheduleReconnect(int generation) {
    _reconnectTimer?.cancel();
    final index = _reconnectAttempt < _reconnectBackoff.length
        ? _reconnectAttempt
        : _reconnectBackoff.length - 1;
    final delay = _reconnectBackoff[index];
    if (_reconnectAttempt < _reconnectBackoff.length) _reconnectAttempt++;
    _reconnectTimer = Timer(delay, () {
      if (_disposed || generation != _generation) return;
      if (_mode != FocusSyncMode.remote) return;
      _connectSocket();
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) {
      if (_mode != FocusSyncMode.remote) return;
      unawaited(_refreshSnapshot(force: true));
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _cancelSocketSubscription() {
    final subscription = _socketSubscription;
    _socketSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  void _cancelTimers() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _probeTimer?.cancel();
    _probeTimer = null;
    _stopPolling();
  }

  // --- 设备 ID ---

  Future<String> _ensureDeviceId() async {
    final cached = _deviceId;
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(deviceIdStorageKey)?.trim();
      if (existing != null && existing.isNotEmpty) {
        _deviceId = existing;
        return existing;
      }
      final created = newFocusCommandId();
      await prefs.setString(deviceIdStorageKey, created);
      _deviceId = created;
      return created;
    } catch (_) {
      // 存储不可用：本次进程内仍给出稳定 ID，不阻塞控制。
      final created = _deviceId ?? newFocusCommandId();
      _deviceId = created;
      return created;
    }
  }

  void _notifyPomodoro() {
    if (_disposed) return;
    pomodoro.notifyFocusSyncStateChanged();
  }
}

class _FocusIdentity {
  const _FocusIdentity({
    required this.server,
    required this.userId,
    required this.token,
    required this.client,
  });

  final String server;
  final String? userId;
  final String token;
  final ApiClient client;

  String get key => '$server|${userId ?? ''}|$token';
}
