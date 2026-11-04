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
  final int accentColorArgb;

  const FocusTimerNotificationBrand({
    required this.appTitle,
    required this.focusLabel,
    required this.shortBreakLabel,
    required this.longBreakLabel,
    required this.pausedLabel,
    required this.noTaskLabel,
    required this.channelName,
    required this.accentColorArgb,
  });

  bool get isUsable =>
      appTitle.trim().isNotEmpty &&
      channelName.trim().isNotEmpty &&
      focusLabel.trim().isNotEmpty &&
      noTaskLabel.trim().isNotEmpty;

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
    accentColorArgb,
  );
}

/// 一次同步给原生前台服务的通知内容。
///
/// 秒级跳动由系统 chronometer 驱动（原生用 `SystemClock.elapsedRealtime` 作为
/// 基准），Dart 不为此维持额外 timer；暂停时原生冻结计时并停止到期调度。
@immutable
class FocusTimerNotificationPayload {
  /// 通知点击后的返回入口（现有深链路由：`duoyi://tab/focus`）。
  static const String returnUri = 'duoyi://tab/focus';

  final String phase;
  final String phaseLabel;
  final String appTitle;
  final String channelName;
  final String? taskLabel;
  final String noTaskLabel;
  final String pausedLabel;
  final bool paused;
  final bool isCountUp;
  final int remainingMillis;
  final int totalMillis;
  final int progressPermille;
  final int accentColorArgb;

  const FocusTimerNotificationPayload({
    required this.phase,
    required this.phaseLabel,
    required this.appTitle,
    required this.channelName,
    required this.taskLabel,
    required this.noTaskLabel,
    required this.pausedLabel,
    required this.paused,
    required this.isCountUp,
    required this.remainingMillis,
    required this.totalMillis,
    required this.progressPermille,
    required this.accentColorArgb,
  });

  factory FocusTimerNotificationPayload.fromState({
    required PomodoroState state,
    required bool paused,
    required FocusTimerNotificationBrand brand,
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
    return FocusTimerNotificationPayload(
      phase: phase,
      phaseLabel: phaseLabel.trim(),
      appTitle: brand.appTitle.trim(),
      channelName: brand.channelName.trim(),
      taskLabel: task.isEmpty ? null : task,
      noTaskLabel: brand.noTaskLabel.trim(),
      pausedLabel: brand.pausedLabel.trim(),
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
    'paused': paused,
    'isCountUp': isCountUp,
    'remainingMillis': remainingMillis,
    'totalMillis': totalMillis,
    'progressPermille': progressPermille,
    'accentColorArgb': accentColorArgb,
    'returnUri': returnUri,
  };
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
  bool _active = false;
  bool _handlerAttached = false;

  /// 原生倒计时到期回调（原生已清理通知）。Dart 计时器仍自行结算，
  /// 这里只用于“原生先到期”时补一次结算，避免负计时残留。
  Future<void> Function()? onExpired;

  bool get isActive => _active;

  /// 注入品牌文案与主题色；主题/语言切换后立即用最近一次状态重推。
  void setBrand(FocusTimerNotificationBrand brand) {
    if (_brand == brand) return;
    _brand = brand;
    if (!_active) return;
    final state = _lastState;
    if (state == null) return;
    unawaited(sync(state, paused: _lastPaused));
  }

  /// 同步当前计时状态到原生通知；[paused] 为 true 时冻结显示时间。
  Future<void> sync(PomodoroState state, {required bool paused}) async {
    _lastState = state;
    _lastPaused = paused;
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
    );
    await _invoke('sync', payload.toMap());
  }

  /// 停止并清理运行通知（结束/重置/dispose/冷启动无运行态）。
  Future<void> stop() async {
    _active = false;
    _lastState = null;
    _lastPaused = false;
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
