import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/pomodoro.dart';

/// 专注计时通知需要的品牌文案与主题色。
///
/// 全部由 Dart 注入（`main.dart` 的 `pushBrandStringsToNotifiers`），原生只负责
/// 拼装系统通知模板，不硬编码任何品牌/中文文案。
@immutable
class FocusTimerNotificationBrand {
  final String appTitle;
  final String focusLabel;
  final String shortBreakLabel;
  final String longBreakLabel;
  final String pausedLabel;
  final String noTaskLabel;
  final String channelName;

  /// 紧凑正文的时间前缀，如 `剩余` / `已计时`。
  final String remainingLabel;
  final String elapsedLabel;

  /// 通知按钮文案（`开始` / `暂停` / `重置`）。
  final String startActionLabel;
  final String pauseActionLabel;
  final String resetActionLabel;
  final int accentColorArgb;

  const FocusTimerNotificationBrand({
    required this.appTitle,
    required this.focusLabel,
    required this.shortBreakLabel,
    required this.longBreakLabel,
    required this.pausedLabel,
    required this.noTaskLabel,
    required this.channelName,
    required this.remainingLabel,
    required this.elapsedLabel,
    required this.startActionLabel,
    required this.pauseActionLabel,
    required this.resetActionLabel,
    required this.accentColorArgb,
  });

  bool get isUsable =>
      appTitle.trim().isNotEmpty &&
      channelName.trim().isNotEmpty &&
      focusLabel.trim().isNotEmpty &&
      noTaskLabel.trim().isNotEmpty &&
      // 时间前缀是“剩余 24:53”式正文的必要条件，缺失就不推空壳通知。
      remainingLabel.trim().isNotEmpty &&
      elapsedLabel.trim().isNotEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FocusTimerNotificationBrand &&
        other.appTitle == appTitle &&
        other.focusLabel == focusLabel &&
        other.shortBreakLabel == shortBreakLabel &&
        other.longBreakLabel == longBreakLabel &&
        other.pausedLabel == pausedLabel &&
        other.noTaskLabel == noTaskLabel &&
        other.channelName == channelName &&
        other.remainingLabel == remainingLabel &&
        other.elapsedLabel == elapsedLabel &&
        other.startActionLabel == startActionLabel &&
        other.pauseActionLabel == pauseActionLabel &&
        other.resetActionLabel == resetActionLabel &&
        other.accentColorArgb == accentColorArgb;
  }

  @override
  int get hashCode => Object.hash(
    appTitle,
    focusLabel,
    shortBreakLabel,
    longBreakLabel,
    pausedLabel,
    noTaskLabel,
    channelName,
    remainingLabel,
    elapsedLabel,
    startActionLabel,
    pauseActionLabel,
    resetActionLabel,
    accentColorArgb,
  );
}

/// 一次同步给原生前台服务的通知内容。
///
/// 秒级跳动由原生 Handler 用 `SystemClock.elapsedRealtime` 推进，Dart 不为此维持
/// 额外 timer。[anchorMillis] 是 Provider 的 canonical 锚点（真实 instant），原生
/// 首次收到时用它折算当前剩余/已计时，因此主题/语言重推不会延长期限。
/// [controlSessionId]/[controlRevision]/[controlState] 是通知按钮的绑定身份，
/// 点击后由 [FocusTimerNotificationControl] 解析并交回 `applyWidgetControl` 校验。
@immutable
class FocusTimerNotificationPayload {
  /// 通知点击后的返回入口（现有深链路由：`duoyi://tab/focus`）。
  static const String returnUri = 'duoyi://tab/focus';

  static const Set<String> controlStates = <String>{'running', 'paused'};

  final String phase;
  final String phaseLabel;
  final String appTitle;
  final String channelName;
  final String? taskLabel;
  final String noTaskLabel;
  final String pausedLabel;
  final String remainingLabel;
  final String elapsedLabel;
  final String startActionLabel;
  final String pauseActionLabel;
  final String resetActionLabel;
  final bool paused;
  final bool isCountUp;
  final int remainingMillis;
  final int totalMillis;
  final int progressPermille;
  final int accentColorArgb;

  /// 倒计时=结束时刻，正计时=开始时刻（epoch ms）；暂停或缺失时为 0。
  final int anchorMillis;
  final String controlSessionId;
  final int controlRevision;
  final String controlState;

  const FocusTimerNotificationPayload({
    required this.phase,
    required this.phaseLabel,
    required this.appTitle,
    required this.channelName,
    required this.taskLabel,
    required this.noTaskLabel,
    required this.pausedLabel,
    required this.remainingLabel,
    required this.elapsedLabel,
    required this.startActionLabel,
    required this.pauseActionLabel,
    required this.resetActionLabel,
    required this.paused,
    required this.isCountUp,
    required this.remainingMillis,
    required this.totalMillis,
    required this.progressPermille,
    required this.accentColorArgb,
    this.anchorMillis = 0,
    this.controlSessionId = '',
    this.controlRevision = 0,
    this.controlState = '',
  });

  factory FocusTimerNotificationPayload.fromState({
    required PomodoroState state,
    required bool paused,
    required FocusTimerNotificationBrand brand,
    int anchorMillis = 0,
    String controlSessionId = '',
    int controlRevision = 0,
    String controlState = '',
  }) {
    final phase = switch (state.type) {
      PomodoroType.focus => 'focus',
      PomodoroType.shortBreak => 'shortBreak',
      PomodoroType.longBreak => 'longBreak',
    };
    final phaseLabel = switch (state.type) {
      PomodoroType.focus => brand.focusLabel,
      PomodoroType.shortBreak => brand.shortBreakLabel,
      PomodoroType.longBreak => brand.longBreakLabel,
    };
    final remainingMillis = state.remainingSeconds <= 0
        ? 0
        : state.remainingSeconds * 1000;
    final totalMillis = state.totalSeconds <= 0 ? 0 : state.totalSeconds * 1000;
    final task = state.taskLabel?.trim() ?? '';
    final bindingUsable =
        controlSessionId.trim().isNotEmpty &&
        controlRevision >= 0 &&
        controlStates.contains(controlState) &&
        (controlState == 'paused') == paused;
    return FocusTimerNotificationPayload(
      phase: phase,
      phaseLabel: phaseLabel.trim(),
      appTitle: brand.appTitle.trim(),
      channelName: brand.channelName.trim(),
      taskLabel: task.isEmpty ? null : task,
      noTaskLabel: brand.noTaskLabel.trim(),
      pausedLabel: brand.pausedLabel.trim(),
      remainingLabel: brand.remainingLabel.trim(),
      elapsedLabel: brand.elapsedLabel.trim(),
      startActionLabel: brand.startActionLabel.trim(),
      pauseActionLabel: brand.pauseActionLabel.trim(),
      resetActionLabel: brand.resetActionLabel.trim(),
      paused: paused,
      isCountUp: state.isCountUp,
      remainingMillis: remainingMillis,
      totalMillis: totalMillis,
      progressPermille: _progressPermille(
        isCountUp: state.isCountUp,
        remainingMillis: remainingMillis,
        totalMillis: totalMillis,
      ),
      accentColorArgb: brand.accentColorArgb,
      // 暂停必须冻结在传入的剩余值，原生不得再按锚点重算。
      anchorMillis: paused ? 0 : (anchorMillis < 0 ? 0 : anchorMillis),
      controlSessionId: bindingUsable ? controlSessionId.trim() : '',
      controlRevision: bindingUsable ? controlRevision : 0,
      controlState: bindingUsable ? controlState : '',
    );
  }

  /// 进度千分比：正计时/总时长缺失时为 0（原生隐藏进度条），其余钳制在 0..1000。
  static int _progressPermille({
    required bool isCountUp,
    required int remainingMillis,
    required int totalMillis,
  }) {
    if (isCountUp || totalMillis <= 0) return 0;
    final elapsed = (totalMillis - remainingMillis).clamp(0, totalMillis);
    return (elapsed * 1000 ~/ totalMillis).clamp(0, 1000);
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'phase': phase,
    'phaseLabel': phaseLabel,
    'appTitle': appTitle,
    'channelName': channelName,
    'taskLabel': taskLabel,
    'noTaskLabel': noTaskLabel,
    'pausedLabel': pausedLabel,
    'remainingLabel': remainingLabel,
    'elapsedLabel': elapsedLabel,
    'startActionLabel': startActionLabel,
    'pauseActionLabel': pauseActionLabel,
    'resetActionLabel': resetActionLabel,
    'paused': paused,
    'isCountUp': isCountUp,
    'remainingMillis': remainingMillis,
    'totalMillis': totalMillis,
    'progressPermille': progressPermille,
    'accentColorArgb': accentColorArgb,
    'returnUri': returnUri,
    'anchorMillis': anchorMillis,
    'controlSessionId': controlSessionId,
    'controlRevision': controlRevision,
    'controlState': controlState,
  };
}

/// 通知按钮深链的解析结果。
///
/// 专用形态 `duoyi://focus-timer/<action>?session=&revision=&state=`：
/// - scheme 必须是 `duoyi`，host 必须是 `focus-timer`，路径只有一段；
/// - action ∈ {`pause`, `start`, `reset`}；
/// - session 非空且为 URI 安全的短标识，revision 为非负整数；
/// - state ∈ {`running`, `paused`}，且与动作匹配：`start` 只接受 paused，
///   `pause` 只接受 running，`reset` 接受 running/paused。
///
/// `reset` 映射为 [PomodoroWidgetControlAction.stop]，与小组件“重置”同一语义。
@immutable
class FocusTimerNotificationControl {
  static const String scheme = 'duoyi';
  static const String host = 'focus-timer';

  /// session 长度上限，与原生 `FocusTimerNotificationModel` 的校验一致。
  static const int maxSessionIdLength = 128;

  static final RegExp _sessionPattern = RegExp(r'^[A-Za-z0-9._~-]+$');

  final PomodoroWidgetControlAction action;
  final String sessionId;
  final int revision;
  final PomodoroWidgetTimerState expectedState;

  const FocusTimerNotificationControl._({
    required this.action,
    required this.sessionId,
    required this.revision,
    required this.expectedState,
  });

  /// 通知按钮动作 → 既有小组件控制动作。
  PomodoroWidgetControlAction get widgetAction => action;

  static PomodoroWidgetControlAction? _actionForPath(String path) =>
      switch (path) {
        'start' => PomodoroWidgetControlAction.start,
        'pause' => PomodoroWidgetControlAction.pause,
        'reset' => PomodoroWidgetControlAction.stop,
        _ => null,
      };

  static Set<PomodoroWidgetTimerState> _allowedStates(
    PomodoroWidgetControlAction action,
  ) => switch (action) {
    PomodoroWidgetControlAction.start => const <PomodoroWidgetTimerState>{
      PomodoroWidgetTimerState.paused,
    },
    PomodoroWidgetControlAction.pause => const <PomodoroWidgetTimerState>{
      PomodoroWidgetTimerState.running,
    },
    PomodoroWidgetControlAction.stop => const <PomodoroWidgetTimerState>{
      PomodoroWidgetTimerState.running,
      PomodoroWidgetTimerState.paused,
    },
  };

  /// 解析通知按钮深链；任何畸形/不匹配都返回 null（调用方不执行任何动作）。
  static FocusTimerNotificationControl? parse(Uri? uri) {
    if (uri == null || uri.scheme != scheme || uri.host != host) return null;
    if (uri.pathSegments.length != 1) return null;
    final action = _actionForPath(uri.pathSegments.first);
    if (action == null) return null;
    final query = uri.queryParameters;
    final sessionId = query['session']?.trim() ?? '';
    if (sessionId.isEmpty ||
        sessionId.length > maxSessionIdLength ||
        !_sessionPattern.hasMatch(sessionId)) {
      return null;
    }
    final rawRevision = query['revision']?.trim() ?? '';
    if (rawRevision.isEmpty) return null;
    final revision = int.tryParse(rawRevision);
    if (revision == null || revision < 0) return null;
    final expectedState = PomodoroWidgetTimerState.fromWire(query['state']);
    if (expectedState == null) return null;
    if (!_allowedStates(action).contains(expectedState)) return null;
    return FocusTimerNotificationControl._(
      action: action,
      sessionId: sessionId,
      revision: revision,
      expectedState: expectedState,
    );
  }
}

/// Android 专注计时持续通知（独立前台服务，specialUse 类型）。
///
/// 与 `local_notifications` 相互独立：不写入普通提醒历史，也不受
/// `cancelAllReminders` 影响。非 Android 平台全部是 no-op。
class FocusTimerNotificationService {
  FocusTimerNotificationService._();

  static final FocusTimerNotificationService instance =
      FocusTimerNotificationService._();

  static const MethodChannel _channel = MethodChannel('duoyi/focus_timer');

  FocusTimerNotificationBrand? _brand;
  PomodoroState? _lastState;
  bool _lastPaused = false;
  int _lastAnchorMillis = 0;
  String _lastControlSessionId = '';
  int _lastControlRevision = 0;
  String _lastControlState = '';
  bool _active = false;
  bool _handlerAttached = false;

  /// 原生倒计时到期回调（原生已清理通知）。Dart 计时器仍自行结算，
  /// 这里只用于“原生先到期”时补一次结算，避免负计时残留。
  Future<void> Function()? onExpired;

  bool get isActive => _active;

  /// 注入品牌文案与主题色；主题/语言切换后立即用最近一次状态重推。
  ///
  /// 重推必须带上同一个锚点与控制绑定，否则会重新按“当前剩余”起算而延长期限，
  /// 或让运行中的通知丢掉按钮。
  void setBrand(FocusTimerNotificationBrand brand) {
    if (_brand == brand) return;
    _brand = brand;
    if (!_active) return;
    final state = _lastState;
    if (state == null) return;
    unawaited(
      sync(
        state,
        paused: _lastPaused,
        anchorMillis: _lastAnchorMillis,
        controlSessionId: _lastControlSessionId,
        controlRevision: _lastControlRevision,
        controlState: _lastControlState,
      ),
    );
  }

  /// 同步当前计时状态到原生通知。
  ///
  /// [paused] 为 true 时原生冻结显示时间；[anchorMillis] 是 Provider 的 canonical
  /// 锚点（暂停传 0）；控制三件套原样透传给原生按钮。
  Future<void> sync(
    PomodoroState state, {
    required bool paused,
    int anchorMillis = 0,
    String controlSessionId = '',
    int controlRevision = 0,
    String controlState = '',
  }) async {
    _lastState = state;
    _lastPaused = paused;
    _lastAnchorMillis = paused || anchorMillis < 0 ? 0 : anchorMillis;
    _lastControlSessionId = controlSessionId;
    _lastControlRevision = controlRevision;
    _lastControlState = controlState;
    _active = true;
    final brand = _brand;
    if (brand == null || !brand.isUsable) {
      // 品牌尚未注入：不阻断计时，等 setBrand 后补发。
      debugPrint('[FocusTimerNotificationService] brand not ready, skip sync');
      return;
    }
    if (!_isAndroid) return;
    _attachHandler();
    final payload = FocusTimerNotificationPayload.fromState(
      state: state,
      paused: paused,
      brand: brand,
      anchorMillis: _lastAnchorMillis,
      controlSessionId: _lastControlSessionId,
      controlRevision: _lastControlRevision,
      controlState: _lastControlState,
    );
    await _invoke('sync', payload.toMap());
  }

  /// 停止并清理运行通知（结束/重置/dispose/冷启动无运行态）。
  Future<void> stop() async {
    _active = false;
    _lastState = null;
    _lastPaused = false;
    _lastAnchorMillis = 0;
    _lastControlSessionId = '';
    _lastControlRevision = 0;
    _lastControlState = '';
    if (!_isAndroid) return;
    await _invoke('stop', null);
  }

  /// 首次真正使用原生通道时再注册回调：纯逻辑测试不需要 WidgetsBinding。
  void _attachHandler() {
    if (_handlerAttached) return;
    _channel.setMethodCallHandler(_handleNativeCall);
    _handlerAttached = true;
  }

  Future<void> _invoke(String method, Object? arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } catch (e, st) {
      // 通知失败绝不反向打断计时。
      debugPrint('[FocusTimerNotificationService] $method failed: $e\n$st');
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'expired') {
      _active = false;
      _lastState = null;
      _lastAnchorMillis = 0;
      _lastControlSessionId = '';
      _lastControlRevision = 0;
      _lastControlState = '';
      final handler = onExpired;
      if (handler != null) await handler();
      return;
    }
    throw MissingPluginException(
      '[FocusTimerNotificationService] unknown method ${call.method}',
    );
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
