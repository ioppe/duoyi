/// 同账号多端专注的客户端投影模型。
///
/// 协议见 `docs/focus-runtime-sync.md`：服务端是唯一权威，Provider 只做投影，
/// 所有字段名与后端快照保持一致（camelCase），不得在客户端重命名。
library;

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'pomodoro.dart';

/// 服务端运行态状态。
enum FocusRuntimeStatus {
  idle,
  running,
  paused;

  static FocusRuntimeStatus fromWire(Object? raw) {
    final value = raw?.toString().trim().toLowerCase();
    for (final status in FocusRuntimeStatus.values) {
      if (status.name == value) return status;
    }
    return FocusRuntimeStatus.idle;
  }

  String get wireName => name;

  bool get isRunning => this == FocusRuntimeStatus.running;
  bool get isPaused => this == FocusRuntimeStatus.paused;
  bool get isIdle => this == FocusRuntimeStatus.idle;
}

/// 计时模式：倒计时 / 正计时。
enum FocusRuntimeMode {
  countdown,
  countup;

  static FocusRuntimeMode fromWire(Object? raw) {
    final value = raw?.toString().trim().toLowerCase();
    return value == 'countup'
        ? FocusRuntimeMode.countup
        : FocusRuntimeMode.countdown;
  }

  String get wireName => name;

  bool get isCountUp => this == FocusRuntimeMode.countup;
}

/// 阶段：专注 / 短休 / 长休。
enum FocusRuntimePhase {
  focus,
  shortBreak,
  longBreak;

  static FocusRuntimePhase fromWire(Object? raw) {
    final value = raw?.toString().trim().toLowerCase();
    for (final phase in FocusRuntimePhase.values) {
      if (phase.name.toLowerCase() == value) return phase;
    }
    return FocusRuntimePhase.focus;
  }

  String get wireName => name;

  PomodoroType get pomodoroType {
    switch (this) {
      case FocusRuntimePhase.focus:
        return PomodoroType.focus;
      case FocusRuntimePhase.shortBreak:
        return PomodoroType.shortBreak;
      case FocusRuntimePhase.longBreak:
        return PomodoroType.longBreak;
    }
  }

  static FocusRuntimePhase fromPomodoroType(PomodoroType type) {
    switch (type) {
      case PomodoroType.focus:
        return FocusRuntimePhase.focus;
      case PomodoroType.shortBreak:
        return FocusRuntimePhase.shortBreak;
      case PomodoroType.longBreak:
        return FocusRuntimePhase.longBreak;
    }
  }
}

/// 显式控制动作。协议只接受这些动作，未知值一律丢弃。
enum FocusRuntimeAction {
  start,
  pause,
  resume,
  stop,
  reset,
  finish,
  skip,
  update;

  static FocusRuntimeAction? fromWire(Object? raw) {
    final value = raw?.toString().trim().toLowerCase();
    for (final action in FocusRuntimeAction.values) {
      if (action.name == value) return action;
    }
    return null;
  }

  String get wireName => name;

  /// 只保护运行态的三段控制（开始/暂停/停止）是否等价于本地控制。
  bool get isControl => this != FocusRuntimeAction.update;
}

/// 客户端与服务端之间同步连接/权威状态。
enum FocusSyncMode {
  /// 已登录且能力未知：等待/探测权威快照，期间不得退回独立本地专注。
  unknown,

  /// 访客或明确不支持/明确 404 的旧后端：沿用设备本地专注。
  local,

  /// 服务端权威运行态。
  remote,
}

/// 快照里的运行态。
@immutable
class FocusRuntimeState {
  final String sessionId;
  final int revision;
  final FocusRuntimeStatus status;
  final FocusRuntimeMode mode;
  final FocusRuntimePhase phase;
  final int durationMs;
  final int elapsedMs;
  final int? anchorAtMs;
  final int? startedAtMs;
  final int completedSessions;
  final String sourceDeviceId;

  /// 服务端会话计时配置（PomodoroConfig 形状）；只用于计时，不覆盖本机配置。
  final Map<String, dynamic> config;
  final String? taskName;
  final String? todoId;
  final String? subtaskId;
  final String? todoTitle;
  final String? tag;
  final String? focusRoomId;

  const FocusRuntimeState({
    required this.sessionId,
    required this.revision,
    required this.status,
    required this.mode,
    required this.phase,
    required this.durationMs,
    required this.elapsedMs,
    this.anchorAtMs,
    this.startedAtMs,
    this.completedSessions = 0,
    this.sourceDeviceId = '',
    this.config = const <String, dynamic>{},
    this.taskName,
    this.todoId,
    this.subtaskId,
    this.todoTitle,
    this.tag,
    this.focusRoomId,
  });

  static const FocusRuntimeState empty = FocusRuntimeState(
    sessionId: '',
    revision: 0,
    status: FocusRuntimeStatus.idle,
    mode: FocusRuntimeMode.countdown,
    phase: FocusRuntimePhase.focus,
    durationMs: PomodoroConfig.defaultFocusDuration * 1000,
    elapsedMs: 0,
  );

  /// 运行中累计毫秒：`elapsedMs + (serverNow - anchorAtMs)`（暂停冻结）。
  int effectiveElapsedMs(int serverNowMs) {
    if (!status.isRunning || anchorAtMs == null) return max(0, elapsedMs);
    final anchor = anchorAtMs!;
    return max(0, elapsedMs + max(0, serverNowMs - anchor));
  }

  /// 倒计时剩余毫秒；正计时/非倒计时为 0。
  int effectiveRemainingMs(int serverNowMs) {
    if (mode.isCountUp) return 0;
    final remaining = durationMs - effectiveElapsedMs(serverNowMs);
    return remaining <= 0 ? 0 : remaining;
  }

  /// 倒计时显示剩余秒（向上取整），正计时显示已用秒（向下取整）。
  int displaySeconds(int serverNowMs) {
    if (mode.isCountUp) {
      final elapsedMs = this.elapsedMs;
      final effective = status.isRunning
          ? effectiveElapsedMs(serverNowMs)
          : max(0, elapsedMs);
      return effective ~/ 1000;
    }
    final remaining = effectiveRemainingMs(serverNowMs);
    return (remaining + 999) ~/ 1000;
  }

  /// 正计时有效时长秒数（向上取整到秒的最少 1 秒语义由调用方决定）。
  int get countUpElapsedSeconds => max(0, elapsedMs) ~/ 1000;

  /// 倒计时到期（仅服务端可以结算）。
  bool isExpired(int serverNowMs) =>
      !mode.isCountUp &&
      durationMs > 0 &&
      effectiveElapsedMs(serverNowMs) >= durationMs;

  FocusRuntimeState copyWith({
    String? sessionId,
    int? revision,
    FocusRuntimeStatus? status,
    FocusRuntimeMode? mode,
    FocusRuntimePhase? phase,
    int? durationMs,
    int? elapsedMs,
    int? anchorAtMs,
    bool clearAnchor = false,
    int? startedAtMs,
    int? completedSessions,
    String? sourceDeviceId,
    Map<String, dynamic>? config,
    String? taskName,
    bool clearTaskName = false,
    String? todoId,
    String? subtaskId,
    String? todoTitle,
    bool clearTaskLink = false,
    String? tag,
    bool clearTag = false,
    String? focusRoomId,
    bool clearFocusRoom = false,
  }) => FocusRuntimeState(
    sessionId: sessionId ?? this.sessionId,
    revision: revision ?? this.revision,
    status: status ?? this.status,
    mode: mode ?? this.mode,
    phase: phase ?? this.phase,
    durationMs: durationMs ?? this.durationMs,
    elapsedMs: elapsedMs ?? this.elapsedMs,
    anchorAtMs: clearAnchor ? null : (anchorAtMs ?? this.anchorAtMs),
    startedAtMs: startedAtMs ?? this.startedAtMs,
    completedSessions: completedSessions ?? this.completedSessions,
    sourceDeviceId: sourceDeviceId ?? this.sourceDeviceId,
    config: config ?? this.config,
    taskName: clearTaskName ? null : (taskName ?? this.taskName),
    todoId: clearTaskLink ? null : (todoId ?? this.todoId),
    subtaskId: clearTaskLink ? null : (subtaskId ?? this.subtaskId),
    todoTitle: clearTaskLink ? null : (todoTitle ?? this.todoTitle),
    tag: clearTag ? null : (tag ?? this.tag),
    focusRoomId: clearFocusRoom ? null : (focusRoomId ?? this.focusRoomId),
  );

  factory FocusRuntimeState.fromJson(Map<String, dynamic> json) {
    return FocusRuntimeState(
      sessionId: _string(json['sessionId']) ?? '',
      revision: _int(json['revision']) ?? 0,
      status: FocusRuntimeStatus.fromWire(json['status']),
      mode: FocusRuntimeMode.fromWire(json['mode']),
      phase: FocusRuntimePhase.fromWire(json['phase']),
      durationMs: max(0, _int(json['durationMs']) ?? 0),
      elapsedMs: max(0, _int(json['elapsedMs']) ?? 0),
      anchorAtMs: _int(json['anchorAtMs']),
      startedAtMs: _int(json['startedAtMs']),
      completedSessions: max(0, _int(json['completedSessions']) ?? 0),
      sourceDeviceId: _string(json['sourceDeviceId']) ?? '',
      config: _map(json['config']),
      taskName: _string(json['taskName']),
      todoId: _string(json['todoId']),
      subtaskId: _string(json['subtaskId']),
      todoTitle: _string(json['todoTitle']),
      tag: _string(json['tag']),
      focusRoomId: _string(json['focusRoomId']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'sessionId': sessionId,
    'revision': revision,
    'status': status.wireName,
    'mode': mode.wireName,
    'phase': phase.wireName,
    'durationMs': durationMs,
    'elapsedMs': elapsedMs,
    'anchorAtMs': anchorAtMs,
    'startedAtMs': startedAtMs,
    'completedSessions': completedSessions,
    'sourceDeviceId': sourceDeviceId,
    'config': config,
    'taskName': taskName,
    'todoId': todoId,
    'subtaskId': subtaskId,
    'todoTitle': todoTitle,
    'tag': tag,
    'focusRoomId': focusRoomId,
  };
}

/// `GET /api/focus/runtime` / WS `focus.runtime` 事件的完整快照。
@immutable
class FocusRuntimeSnapshot {
  final int serverNowMs;
  final FocusRuntimeState runtime;

  /// 最近一次仍存在于历史中的结算记录（服务端 sessionId 为记录 id）。
  final Map<String, dynamic>? lastSession;

  /// 最近一次服务端控制处罚记录。
  final Map<String, dynamic>? lastPenalty;
  final int syncVersion;

  const FocusRuntimeSnapshot({
    required this.serverNowMs,
    required this.runtime,
    this.lastSession,
    this.lastPenalty,
    this.syncVersion = 0,
  });

  /// 解析失败返回 null（调用方丢弃该消息，不制造假状态）。
  static FocusRuntimeSnapshot? tryParse(Object? raw) {
    final map = _asMap(raw);
    if (map == null) return null;
    final runtimeJson = _asMap(map['runtime']);
    if (runtimeJson == null) return null;
    final parsed = FocusRuntimeSnapshot(
      serverNowMs: _int(map['serverNowMs']) ?? 0,
      runtime: FocusRuntimeState.fromJson(runtimeJson),
      lastSession: _asMap(map['lastSession']),
      lastPenalty: _asMap(map['lastPenalty']),
      syncVersion: _int(map['syncVersion']) ?? 0,
    );
    if (parsed.runtime.sessionId.isEmpty) return null;
    if (parsed.serverNowMs <= 0) {
      // 缺少服务器时钟：锚点推算会漂移，退化为本地时钟再校准。
      return parsed.withServerNowMs(DateTime.now().millisecondsSinceEpoch);
    }
    return parsed;
  }

  FocusRuntimeSnapshot withServerNowMs(int serverNowMs) => FocusRuntimeSnapshot(
    serverNowMs: serverNowMs,
    runtime: runtime,
    lastSession: lastSession,
    lastPenalty: lastPenalty,
    syncVersion: syncVersion,
  );

  /// 历史里仍存在的结算记录（解析失败返回 null，不复活伪造记录）。
  PomodoroSession? get sessionRecord {
    final json = lastSession;
    if (json == null) return null;
    try {
      return PomodoroSession.fromJson(Map<String, dynamic>.from(json));
    } catch (_) {
      return null;
    }
  }

  PomodoroFocusPenalty? get penaltyRecord {
    final json = lastPenalty;
    if (json == null) return null;
    try {
      return PomodoroFocusPenalty.fromJson(Map<String, dynamic>.from(json));
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'serverNowMs': serverNowMs,
    'runtime': runtime.toJson(),
    'lastSession': lastSession,
    'lastPenalty': lastPenalty,
    'syncVersion': syncVersion,
  };
}

/// 控制命令：`POST /api/focus/runtime/commands`。
@immutable
class FocusRuntimeCommand {
  final String commandId;
  final String deviceId;
  final String sessionId;
  final int expectedRevision;
  final FocusRuntimeAction action;
  final Map<String, dynamic>? payload;

  const FocusRuntimeCommand({
    required this.commandId,
    required this.deviceId,
    required this.sessionId,
    required this.expectedRevision,
    required this.action,
    this.payload,
  });

  /// 命令 ID 由客户端生成 UUID；同一命令 ID 不能换载荷。
  factory FocusRuntimeCommand.create({
    required String deviceId,
    required String sessionId,
    required int expectedRevision,
    required FocusRuntimeAction action,
    Map<String, dynamic>? payload,
  }) => FocusRuntimeCommand(
    commandId: newFocusCommandId(),
    deviceId: deviceId,
    sessionId: sessionId,
    expectedRevision: expectedRevision,
    action: action,
    payload: payload,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'commandId': commandId,
    'deviceId': deviceId,
    'sessionId': sessionId,
    'expectedRevision': expectedRevision,
    'action': action.wireName,
    if (payload != null && payload!.isNotEmpty) 'payload': payload,
  };

  /// start 载荷：计时模式 + 会话配置 + 任务字段（idle 草稿在这里带上）。
  static Map<String, dynamic> startPayload({
    required FocusRuntimeMode mode,
    required Map<String, dynamic> config,
    FocusRuntimePhase? phase,
    String? taskName,
    String? todoId,
    String? subtaskId,
    String? todoTitle,
    String? tag,
    String? focusRoomId,
  }) => <String, dynamic>{
    'mode': mode.wireName,
    'config': config,
    if (phase != null) 'phase': phase.wireName,
    'taskName': taskName,
    'todoId': todoId,
    'subtaskId': subtaskId,
    'todoTitle': todoTitle,
    'tag': tag,
    'focusRoomId': focusRoomId,
  };

  /// update 载荷白名单：只允许任务/标签/房间字段，不能改状态、计时或发起设备。
  static Map<String, dynamic> updatePayload({
    String? taskName,
    String? todoId,
    String? subtaskId,
    String? todoTitle,
    String? tag,
    String? focusRoomId,
  }) => <String, dynamic>{
    'taskName': taskName,
    'todoId': todoId,
    'subtaskId': subtaskId,
    'todoTitle': todoTitle,
    'tag': tag,
    'focusRoomId': focusRoomId,
  };
}

/// 客户端 UUID v4（命令 ID / 设备 ID）。
String newFocusCommandId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// 服务端时钟校准 + 单调 Stopwatch 推进。
///
/// 每次快照都重新校准，tick 只用 `elapsedMilliseconds` 推进，不做每秒
/// `++/--` 累加，因此长时间运行也不会累积漂移。
class FocusRuntimeClock {
  final DateTime Function() _wallClock;
  final Stopwatch _monotonic = Stopwatch();
  int _serverNowAtCalibrationMs = 0;
  bool _calibrated = false;

  FocusRuntimeClock({DateTime Function()? wallClock})
    : _wallClock = wallClock ?? DateTime.now;

  bool get isCalibrated => _calibrated;

  /// 当前服务器时刻（epoch ms）：已校准走单调时钟，未校准退化本地时钟。
  int get nowMs => _calibrated
      ? _serverNowAtCalibrationMs + _monotonic.elapsedMilliseconds
      : _wallClock().millisecondsSinceEpoch;

  /// 用快照里的 `serverNowMs` 重新校准（幂等，重复调用不产生漂移）。
  void calibrate(int serverNowMs) {
    _serverNowAtCalibrationMs = serverNowMs;
    _calibrated = true;
    _monotonic
      ..reset()
      ..start();
  }

  void reset() {
    _calibrated = false;
    _serverNowAtCalibrationMs = 0;
    _monotonic
      ..reset()
      ..stop();
  }
}

/// Provider 依赖的远端控制面：由 [FocusSyncCoordinator] 实现。
///
/// Provider 只通过这些显式动作发起远端命令，不直接持有 socket / HTTP 细节。
abstract class FocusRuntimeController {
  FocusSyncMode get mode;
  bool get ready;
  bool get connected;
  bool get busy;
  Object? get error;

  /// 本机无凭证设备 ID（用于 strict 监控只在发起设备生效）。
  String? get deviceId;

  /// 当前权威会话与版本（widget 控制映射到这里）。
  String? get runtimeSessionId;
  int? get runtimeRevision;

  /// 当前投影快照；未连上权威状态时为 null。
  FocusRuntimeSnapshot? get snapshot;

  /// 请求补拉权威快照（断线/到期/控制失败后恢复，不重放旧命令）。
  void requestRefresh();

  /// 发送显式命令；返回是否已由服务端确认并应用。
  Future<bool> send(FocusRuntimeAction action, {Map<String, dynamic>? payload});
}

Map<String, dynamic>? _asMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

Map<String, dynamic> _map(Object? raw) =>
    _asMap(raw) ?? const <String, dynamic>{};

int? _int(Object? raw) {
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim());
  return null;
}

String? _string(Object? raw) {
  final value = raw?.toString().trim();
  if (value == null || value.isEmpty || value == 'null') return null;
  return value;
}
