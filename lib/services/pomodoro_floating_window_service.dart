import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/platform_info.dart';
import '../core/pomodoro_floating_window_size.dart';
import '../models/pomodoro.dart';
import '../providers/pomodoro_provider.dart';

/// macOS 番茄计时悬浮窗的 Dart 端桥接。
///
/// - 原生面板（`NSPanel`）不抢主窗口焦点，Dart 只负责快照同步与控制入口。
/// - 同时监听 [PomodoroProvider] 与 `timerTicks`：普通每秒 tick 不触发
///   Provider 的常规通知，缺一不可。
/// - 原生 `toggle` 不在这里本地改状态，统一交给 [PomodoroProvider.toggleTimer]，
///   随后再发送最新快照。
/// - 计时器始终只有 `PomodoroProvider` 一个，本类不新建、不重置。
class PomodoroFloatingWindowService extends ChangeNotifier {
  PomodoroFloatingWindowService({bool? supported, MethodChannel? channel})
    : _supported = supported ?? (PlatformInfo.isMacOS && !kIsWeb),
      _channel = channel ?? defaultChannel {
    _registerNativeHandler();
  }

  /// 原生端（`macos/Runner/MainFlutterWindow.swift`）使用的通道名。
  static const MethodChannel defaultChannel = MethodChannel(
    'com.duoyi/pomodoro_floating_window',
  );

  /// 生产入口：全局只有一个实例，计时页与全局 Host 共享可见状态。
  static final PomodoroFloatingWindowService instance =
      PomodoroFloatingWindowService();

  final bool _supported;
  final MethodChannel _channel;

  PomodoroProvider? _provider;
  bool _available = true;
  String? _sessionIdentity;
  String _windowTitle = '';
  String _playLabel = '';
  String _pauseLabel = '';
  String _closeLabel = '';
  String _resumeLabel = '';
  String _pausedLabel = '';
  String _readyLabel = '';
  String _focusLabel = '';
  String _shortBreakLabel = '';
  String _longBreakLabel = '';
  Map<String, Object?> _appearance = const {};
  PomodoroFloatingWindowSize _windowSize =
      PomodoroFloatingWindowSize.defaultSize;

  bool _visible = false;
  bool _desiredVisible = false;

  /// 每次显隐/身份/可用性变化都递增，用于丢弃迟到的原生成功回调。
  int _generation = 0;
  Map<String, Object?>? _lastSentSnapshot;
  bool _disposed = false;

  final ValueNotifier<Object?> _failure = ValueNotifier<Object?>(null);

  /// 原生端是否可用（macOS 非 Web 平台）。测试可注入固定值。
  bool get isSupported => _supported;

  /// 面板当前是否可见。入口按钮据此切换打开/隐藏提示。
  bool get isVisible => _visible;

  /// 最近一次打开/关闭/原生按钮失败；消费后由调用方 [takeFailure]。
  ValueListenable<Object?> get failure => _failure;

  /// 绑定计时 Provider。替换绑定时先移除旧监听，再立即同步一次快照。
  void attach(PomodoroProvider provider) {
    if (_disposed || identical(_provider, provider)) return;
    if (_provider != null) detach();
    _lastSentSnapshot = null;
    _provider = provider;
    provider.addListener(_handleProviderChanged);
    provider.timerTicks.addListener(_handleTimerTick);
    _pushSnapshot();
  }

  /// 移除监听。计时器与 Provider 本身不受影响；在途 show 一并失效。
  void detach() {
    _detachListeners();
    _provider = null;
    if (_desiredVisible || _visible) {
      _requestHide();
      return;
    }
    _desiredVisible = false;
    _generation++;
    _setVisible(false);
  }

  /// 同步入口状态：应用锁、强制更新、账号/服务器身份、语言与主题文案。
  ///
  /// 只更新闭包外的标量；相同快照会被 [update] 去重，避免每秒重复发送。
  void configure({
    required bool available,
    required String sessionIdentity,
    required String windowTitle,
    required String playLabel,
    required String pauseLabel,
    required String closeLabel,
    String? resumeLabel,
    String? pausedLabel,
    String? readyLabel,
    String? focusLabel,
    String? shortBreakLabel,
    String? longBreakLabel,
    Map<String, Object?>? appearance,
    PomodoroFloatingWindowSize windowSize =
        PomodoroFloatingWindowSize.defaultSize,
  }) {
    final availabilityChanged = _available != available;
    final identityChanged =
        _sessionIdentity != null && _sessionIdentity != sessionIdentity;
    _available = available;
    _sessionIdentity = sessionIdentity;
    _windowTitle = windowTitle;
    _playLabel = playLabel;
    _pauseLabel = pauseLabel;
    _closeLabel = closeLabel;
    _resumeLabel = resumeLabel ?? _resumeLabel;
    _pausedLabel = pausedLabel ?? _pausedLabel;
    _readyLabel = readyLabel ?? _readyLabel;
    _focusLabel = focusLabel ?? _focusLabel;
    _shortBreakLabel = shortBreakLabel ?? _shortBreakLabel;
    _longBreakLabel = longBreakLabel ?? _longBreakLabel;
    if (appearance != null && !mapEquals(appearance, _appearance)) {
      _appearance = Map<String, Object?>.unmodifiable(appearance);
    }
    _windowSize = windowSize;

    if ((availabilityChanged && !available) || identityChanged) {
      // 锁定/强更/切换账号或服务器：仅隐藏，恢复后由用户重新打开。
      _requestHide();
    }
    // 隐藏时也要同步状态，原生据此决定是否抑制 App Nap。
    _pushSnapshot();
  }

  /// 打开或刷新面板。`show` 总是携带调用时刻的最新快照。
  Future<bool> open() async {
    if (_disposed) return false;
    final provider = _provider;
    if (!_supported || !_available || provider == null) return false;
    _desiredVisible = true;
    final generation = ++_generation;
    final snapshot = _snapshot(provider);
    final ok = await _invoke('show', arguments: snapshot, reportFailure: true);
    if (generation != _generation) {
      // 期间发生了隐藏/关闭/锁屏：本次成功回调不能让面板留在屏幕上。
      if (!_desiredVisible) {
        await _invoke('hide');
      }
      return false;
    }
    if (!ok) {
      _desiredVisible = false;
      _setVisible(false);
      return false;
    }
    _lastSentSnapshot = snapshot;
    _setVisible(true);
    return true;
  }

  /// 仅隐藏面板，不暂停计时。
  Future<bool> hide() async {
    if (_disposed) return false;
    final wasVisible = _visible;
    _desiredVisible = false;
    final generation = ++_generation;
    _setVisible(false);
    final ok = await _invoke('hide', reportFailure: true);
    if (!ok && _supported && generation == _generation) {
      // 原生隐藏失败，面板大概率仍在屏幕上：恢复可见标记，避免入口误导。
      _desiredVisible = wasVisible;
      _setVisible(wasVisible);
    }
    return ok;
  }

  /// 应用退出/宿主销毁时清理原生资源。
  Future<void> disposeWindow() async {
    if (_disposed) return;
    _desiredVisible = false;
    _generation++;
    _setVisible(false);
    _lastSentSnapshot = null;
    if (!_supported) return;
    await _invoke('dispose');
  }

  /// 取走一次失败并清空，避免同一错误重复弹提示。
  Object? takeFailure() {
    final current = _failure.value;
    if (current != null) _failure.value = null;
    return current;
  }

  /// 与计时页 `_formatTime` 一致：MM:SS，分钟不截断（100:00 合法）。
  static String formatTime(int seconds) {
    final total = seconds < 0 ? 0 : seconds;
    final minutes = total ~/ 60;
    final remainder = total % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${remainder.toString().padLeft(2, '0')}';
  }

  /// 原生 -> Dart 的 `toggle` / `closed`。
  @visibleForTesting
  Future<Object?> handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'toggle':
        _handleToggle();
        return null;
      case 'closed':
        _handleClosed();
        return null;
      default:
        throw MissingPluginException(
          'Unsupported pomodoro floating window method: ${call.method}',
        );
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    unawaited(disposeWindow());
    _disposed = true;
    _detachListeners();
    _generation++;
    if (_supported) {
      _channel.setMethodCallHandler(null);
    }
    _failure.dispose();
    super.dispose();
  }

  void _handleToggle() {
    final provider = _provider;
    if (provider == null || !_available || !_visible) return;
    // 严格模式暂停记录、声音、持久化都在 Provider 内完成。
    provider.toggleTimer();
    _pushSnapshot(provider: provider);
  }

  void _handleClosed() {
    _desiredVisible = false;
    _generation++;
    _setVisible(false);
  }

  void _handleProviderChanged() => _pushSnapshot();

  void _handleTimerTick() => _pushSnapshot();

  Map<String, Object?> _snapshot(PomodoroProvider provider) {
    final state = provider.state;
    final isPaused = provider.isPaused;
    final phaseLabel = switch (state.type) {
      PomodoroType.focus => _focusLabel,
      PomodoroType.shortBreak => _shortBreakLabel,
      PomodoroType.longBreak => _longBreakLabel,
    };
    return <String, Object?>{
      'timeText': formatTime(state.remainingSeconds),
      'isRunning': state.isRunning,
      'canToggle': _available,
      'isBreak': state.type != PomodoroType.focus,
      'isPaused': isPaused,
      'stateLabel': state.isRunning
          ? phaseLabel
          : isPaused
          ? _pausedLabel
          : _readyLabel,
      'resumeLabel': _resumeLabel,
      'appearance': _appearance,
      'playLabel': _playLabel,
      'pauseLabel': _pauseLabel,
      'closeLabel': _closeLabel,
      'windowTitle': _windowTitle,
      'windowSize': _windowSize.storageValue,
    };
  }

  void _pushSnapshot({PomodoroProvider? provider}) {
    final current = provider ?? _provider;
    if (_disposed || !_supported || current == null) return;
    final snapshot = _snapshot(current);
    if (_lastSentSnapshot != null && mapEquals(_lastSentSnapshot, snapshot)) {
      return;
    }
    _lastSentSnapshot = snapshot;
    unawaited(_invoke('update', arguments: snapshot));
  }

  void _requestHide() {
    _desiredVisible = false;
    _generation++;
    _setVisible(false);
    if (!_supported) return;
    unawaited(_invoke('hide'));
  }

  Future<bool> _invoke(
    String method, {
    Object? arguments,
    bool reportFailure = false,
  }) async {
    if (_disposed || !_supported) return false;
    try {
      await _channel.invokeMethod<void>(method, arguments);
      return true;
    } on MissingPluginException catch (error) {
      if (reportFailure) _reportFailure(error);
      return false;
    } on PlatformException catch (error) {
      if (reportFailure) _reportFailure(error);
      return false;
    }
  }

  void _reportFailure(Object error) {
    if (_disposed) return;
    if (identical(_failure.value, error)) return;
    _failure.value = error;
  }

  void _setVisible(bool value) {
    if (_disposed || _visible == value) return;
    _visible = value;
    // configure 可能在 build 期间触发隐藏：延迟到帧末再通知监听方。
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
      return;
    }
    notifyListeners();
  }

  void _detachListeners() {
    final provider = _provider;
    if (provider == null) return;
    provider.removeListener(_handleProviderChanged);
    provider.timerTicks.removeListener(_handleTimerTick);
  }

  void _registerNativeHandler() {
    if (!_supported) return;
    _channel.setMethodCallHandler(handleNativeCall);
  }
}
