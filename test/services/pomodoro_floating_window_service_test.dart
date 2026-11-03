import 'dart:async';

import 'package:duoyi/core/pomodoro_floating_window_size.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/services/pomodoro_floating_window_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/pomodoro_floating_window');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late Completer<Object?>? pendingShow;
  late Object? handlerError;
  late PomodoroProvider provider;
  late PomodoroFloatingWindowService service;

  Map<String, Object?> args(MethodCall call) =>
      (call.arguments as Map<Object?, Object?>).cast<String, Object?>();

  Iterable<MethodCall> named(String method) =>
      calls.where((call) => call.method == method);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    calls = <MethodCall>[];
    pendingShow = null;
    handlerError = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (handlerError != null) throw handlerError!;
      if (call.method == 'show' && pendingShow != null) {
        return pendingShow!.future;
      }
      return null;
    });

    provider = PomodoroProvider();
    service = PomodoroFloatingWindowService(supported: true, channel: channel);
    service.attach(provider);
    service.configure(
      available: true,
      sessionIdentity: 'local|',
      windowTitle: '专注',
      playLabel: '开始专注',
      pauseLabel: '暂停',
      closeLabel: '关闭悬浮窗',
    );
  });

  tearDown(() {
    service.detach();
    provider.dispose();
    service.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('timeText 与计时页一致且不截断三位分钟', () {
    expect(PomodoroFloatingWindowService.formatTime(1500), '25:00');
    expect(PomodoroFloatingWindowService.formatTime(0), '00:00');
    expect(PomodoroFloatingWindowService.formatTime(59), '00:59');
    expect(PomodoroFloatingWindowService.formatTime(6000), '100:00');
    expect(PomodoroFloatingWindowService.formatTime(-5), '00:00');
  });

  test('每秒 tick 更新快照但不自动 show', () {
    fakeAsync((async) {
      provider.startIfIdle();
      async.flushMicrotasks();
      calls.clear();

      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(named('show'), isEmpty);
      final updates = named('update');
      expect(updates, isNotEmpty);
      final snapshot = args(updates.last);
      expect(snapshot['isRunning'], isTrue);
      expect(snapshot['timeText'], '24:59');
      expect(snapshot['windowTitle'], '专注');
      expect(snapshot['playLabel'], '开始专注');
      expect(snapshot['pauseLabel'], '暂停');
      expect(snapshot['closeLabel'], '关闭悬浮窗');

      provider.toggleTimer();
      async.flushMicrotasks();
    });
  });

  test('原生 toggle 驱动真实 Provider 且不依赖 show 刷新', () async {
    expect(await service.open(), isTrue);
    expect(service.isVisible, isTrue);
    expect(args(named('show').single)['timeText'], '25:00');

    await service.handleNativeCall(const MethodCall('toggle'));
    await Future<void>.delayed(Duration.zero);
    expect(provider.state.isRunning, isTrue);
    expect(named('show'), hasLength(1), reason: 'toggle 只发送 update');
    expect(args(named('update').last)['isRunning'], isTrue);

    await service.handleNativeCall(const MethodCall('toggle'));
    await Future<void>.delayed(Duration.zero);
    expect(provider.state.isRunning, isFalse);
  });

  test('原生 closed 只隐藏，不暂停计时', () async {
    await service.open();
    provider.startIfIdle();
    await Future<void>.delayed(Duration.zero);

    await service.handleNativeCall(const MethodCall('closed'));

    expect(service.isVisible, isFalse);
    expect(provider.state.isRunning, isTrue);
    expect(named('hide'), isEmpty, reason: '原生已自行隐藏，无需回传 hide');
  });

  test('hide 仅隐藏，不暂停计时', () async {
    await service.open();
    provider.startIfIdle();
    await Future<void>.delayed(Duration.zero);

    expect(await service.hide(), isTrue);

    expect(service.isVisible, isFalse);
    expect(provider.state.isRunning, isTrue);
    expect(named('hide'), hasLength(1));
  });

  test('休息与正计时快照表达 type / isBreak / 累计时长', () async {
    provider.skipSession();
    expect(await service.open(), isTrue);
    expect(args(named('show').last)['isBreak'], isTrue);
    expect(args(named('show').last)['timeText'], '05:00');

    provider.setCountUpMode(true);
    expect(provider.state.isCountUp, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(args(named('update').last)['isBreak'], isFalse);
    expect(args(named('update').last)['timeText'], '00:00');
  });

  test('正计时运行中累计时长按 MM:SS 递增', () {
    fakeAsync((async) {
      provider.setCountUpMode(true);
      provider.startIfIdle();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();

      expect(args(named('update').last)['timeText'], '00:02');
      expect(args(named('update').last)['isRunning'], isTrue);
      provider.toggleTimer();
      async.flushMicrotasks();
    });
  });

  test('不可用（锁屏/强更）隐藏且拒绝原生 toggle，恢复不自动重开', () async {
    await service.open();
    await service.handleNativeCall(const MethodCall('toggle'));
    expect(provider.state.isRunning, isTrue);
    await service.handleNativeCall(const MethodCall('toggle'));
    expect(provider.state.isRunning, isFalse);

    service.configure(
      available: false,
      sessionIdentity: 'local|',
      windowTitle: '专注',
      playLabel: '开始专注',
      pauseLabel: '暂停',
      closeLabel: '关闭悬浮窗',
    );
    await Future<void>.delayed(Duration.zero);
    expect(service.isVisible, isFalse);
    expect(named('hide'), isNotEmpty);
    expect(args(named('update').last)['canToggle'], isFalse);

    await service.handleNativeCall(const MethodCall('toggle'));
    expect(provider.state.isRunning, isFalse, reason: '不可用时忽略原生 toggle');
    final blockedShows = named('show').length;
    expect(await service.open(), isFalse, reason: '锁定期间不能重新打开面板');
    expect(named('show'), hasLength(blockedShows));
    expect(service.isVisible, isFalse);

    final showsBefore = named('show').length;
    service.configure(
      available: true,
      sessionIdentity: 'local|',
      windowTitle: '专注',
      playLabel: '开始专注',
      pauseLabel: '暂停',
      closeLabel: '关闭悬浮窗',
    );
    await Future<void>.delayed(Duration.zero);
    expect(named('show'), hasLength(showsBefore), reason: '恢复后不自动打开');
    expect(service.isVisible, isFalse);
  });

  test('账号或服务器身份变化隐藏面板', () async {
    await service.open();
    expect(service.isVisible, isTrue);

    service.configure(
      available: true,
      sessionIdentity: 'https://b.example|user-b',
      windowTitle: '专注',
      playLabel: '开始专注',
      pauseLabel: '暂停',
      closeLabel: '关闭悬浮窗',
    );
    await Future<void>.delayed(Duration.zero);

    expect(service.isVisible, isFalse);
    expect(named('hide'), isNotEmpty);
  });

  test('解绑 Provider 后 tick 不再发送', () {
    fakeAsync((async) {
      service.detach();
      calls.clear();

      provider.startIfIdle();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();

      expect(calls, isEmpty, reason: '解绑后 Provider 的监听必须已移除');
      provider.toggleTimer();
      async.flushMicrotasks();
    });
  });

  test('MissingPluginException 不崩溃并上报按钮失败', () async {
    messenger.setMockMethodCallHandler(channel, null);

    final opened = await service.open();

    expect(opened, isFalse);
    expect(service.isVisible, isFalse);
    expect(service.takeFailure(), isA<MissingPluginException>());
    expect(await service.hide(), isFalse);
    expect(service.isVisible, isFalse, reason: '缺少插件时不能凭空恢复可见状态');
  });

  test('PlatformException 隐藏失败恢复可见并上报', () async {
    await service.open();
    expect(service.isVisible, isTrue);
    handlerError = PlatformException(code: 'hide_failed');

    final hidden = await service.hide();

    expect(hidden, isFalse);
    expect(service.isVisible, isTrue, reason: '原生隐藏失败时面板可能仍在显示');
    expect(service.takeFailure(), isA<PlatformException>());
    handlerError = null;
  });

  test('show 迟到成功不能覆盖后续 hide', () async {
    pendingShow = Completer<Object?>();
    final openFuture = service.open();
    await Future<void>.delayed(Duration.zero);

    expect(await service.hide(), isTrue);
    pendingShow!.complete(null);
    expect(await openFuture, isFalse);

    expect(service.isVisible, isFalse);
    expect(
      named('hide').length,
      greaterThanOrEqualTo(2),
      reason: '迟到的 show 成功需要补发 hide',
    );
    pendingShow = null;
  });

  test('show 迟到成功不能覆盖原生 closed', () async {
    pendingShow = Completer<Object?>();
    final openFuture = service.open();
    await Future<void>.delayed(Duration.zero);

    await service.handleNativeCall(const MethodCall('closed'));
    pendingShow!.complete(null);

    expect(await openFuture, isFalse);
    expect(service.isVisible, isFalse);
    pendingShow = null;
  });

  test('show 迟到成功不能覆盖 detach', () async {
    pendingShow = Completer<Object?>();
    final openFuture = service.open();
    await Future<void>.delayed(Duration.zero);

    service.detach();
    pendingShow!.complete(null);

    expect(await openFuture, isFalse);
    expect(service.isVisible, isFalse);
    expect(named('hide'), isNotEmpty);
    pendingShow = null;
  });

  test('替换 Provider 使旧 show 失效并解除旧监听', () async {
    pendingShow = Completer<Object?>();
    final openFuture = service.open();
    await Future<void>.delayed(Duration.zero);
    final replacement = PomodoroProvider();
    service.attach(replacement);
    pendingShow!.complete(null);
    expect(await openFuture, isFalse);
    expect(service.isVisible, isFalse);
    service.detach();
    replacement.dispose();
    pendingShow = null;
  });

  test('show 期间变为不可用会补发 hide 且不标记可见', () async {
    pendingShow = Completer<Object?>();
    final openFuture = service.open();
    await Future<void>.delayed(Duration.zero);

    service.configure(
      available: false,
      sessionIdentity: 'local|',
      windowTitle: '专注',
      playLabel: '开始专注',
      pauseLabel: '暂停',
      closeLabel: '关闭悬浮窗',
    );
    pendingShow!.complete(null);

    expect(await openFuture, isFalse);
    expect(service.isVisible, isFalse);
    expect(named('hide').length, greaterThanOrEqualTo(2));
    pendingShow = null;
  });
  test('暂停冻结剩余时间，继续沿用本次计时而不是重新开始', () {
    fakeAsync((async) {
      service.configure(
        available: true,
        sessionIdentity: 'local|',
        windowTitle: '专注',
        playLabel: '开始',
        pauseLabel: '暂停',
        closeLabel: '隐藏',
        resumeLabel: '继续',
        pausedLabel: '已暂停',
        readyLabel: '待开始',
        focusLabel: '专注中',
      );
      var opened = false;
      service.open().then((value) => opened = value);
      async.flushMicrotasks();
      expect(opened, isTrue);
      expect(args(named('show').last)['stateLabel'], '待开始');

      service.handleNativeCall(const MethodCall('toggle'));
      async.flushMicrotasks();
      provider.toggleTimer();
      async.flushMicrotasks();
      expect(provider.state.remainingSeconds, 1500);
      expect(provider.isPaused, isTrue);
      expect(args(named('update').last)['stateLabel'], '已暂停');
      provider.resetTimer();
      async.flushMicrotasks();
      expect(provider.isPaused, isFalse);
      expect(args(named('update').last)['stateLabel'], '待开始');

      service.handleNativeCall(const MethodCall('toggle'));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(args(named('update').last)['stateLabel'], '专注中');

      provider.toggleTimer();
      async.flushMicrotasks();
      final remaining = provider.state.remainingSeconds;
      expect(remaining, 1498);
      expect(args(named('update').last)['isPaused'], isTrue);
      expect(args(named('update').last)['stateLabel'], '已暂停');
      expect(args(named('update').last)['resumeLabel'], '继续');
      async.elapse(const Duration(seconds: 30));
      async.flushMicrotasks();
      expect(provider.state.remainingSeconds, remaining);

      service.handleNativeCall(const MethodCall('toggle'));
      async.flushMicrotasks();
      expect(provider.state.isRunning, isTrue);
      expect(provider.state.remainingSeconds, remaining);
      expect(args(named('update').last)['isPaused'], isFalse);
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(provider.state.remainingSeconds, remaining - 1);
      expect(provider.sessions, isEmpty);
      provider.toggleTimer();
      async.flushMicrotasks();
    });
  });

  test('默认 large，configure 传入 compact 后快照携带尺寸且不新增 show', () async {
    expect(args(named('update').last)['windowSize'], 'large');

    service.configure(
      available: true,
      sessionIdentity: 'local|',
      windowTitle: '专注',
      playLabel: '开始专注',
      pauseLabel: '暂停',
      closeLabel: '关闭悬浮窗',
      windowSize: PomodoroFloatingWindowSize.compact,
    );
    await Future<void>.delayed(Duration.zero);

    expect(args(named('update').last)['windowSize'], 'compact');
    expect(named('show'), isEmpty, reason: '尺寸变化只发 update，不自动打开面板');
  });
}
