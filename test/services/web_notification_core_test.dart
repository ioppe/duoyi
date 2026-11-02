import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/services/web_notifications/web_notification_core.dart';

class _FakeBrowserApi implements WebNotificationBrowserApi {
  _FakeBrowserApi({
    this.support = WebNotificationSupport.supported,
    this.permissionValue = WebNotificationPermission.prompt,
  });

  WebNotificationSupport support;
  WebNotificationPermission permissionValue;
  int requestCount = 0;
  Object? requestError;
  Completer<WebNotificationPermission>? pending;
  final List<String> shownTags = <String>[];
  bool closeAllCalled = false;

  @override
  WebNotificationSupport supportStatus() => support;

  @override
  WebNotificationPermission permission() => permissionValue;

  @override
  Future<WebNotificationPermission> requestPermission() {
    requestCount++;
    final error = requestError;
    if (error != null) return Future<WebNotificationPermission>.error(error);
    final pendingRequest = pending;
    if (pendingRequest != null) return pendingRequest.future;
    return Future<WebNotificationPermission>.value(permissionValue);
  }

  @override
  Future<void> show({
    required String title,
    required String body,
    required String tag,
    void Function()? onClick,
  }) async {
    shownTags.add(tag);
  }

  @override
  Future<void> close(String tag) async {}

  @override
  Future<void> closeAll() async {
    closeAllCalled = true;
  }
}

/// 同步抛错的浏览器桥：模拟"本次不在用户手势中"时原生直接 throw 的实现。
class _SyncThrowingApi extends _FakeBrowserApi {
  bool throwSync = true;

  @override
  Future<WebNotificationPermission> requestPermission() {
    requestCount++;
    if (throwSync) throw StateError('sync boom');
    return Future<WebNotificationPermission>.value(permissionValue);
  }
}

class _FakeTimer {
  _FakeTimer(this.delay, this.fire);

  final Duration delay;
  final void Function() fire;
  bool cancelled = false;

  void cancel() => cancelled = true;
}

class _FakeTimers {
  final List<_FakeTimer> timers = <_FakeTimer>[];

  WebNotificationTimerHandle create(Duration delay, void Function() fire) {
    final timer = _FakeTimer(delay, fire);
    timers.add(timer);
    return timer.cancel;
  }

  List<_FakeTimer> get active =>
      timers.where((timer) => !timer.cancelled).toList(growable: false);
}

class _DisplayRecorder {
  final List<WebNotificationScheduledNotification> shown =
      <WebNotificationScheduledNotification>[];

  Future<void> call(WebNotificationScheduledNotification notification) async {
    shown.add(notification);
  }
}

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('WebNotificationPermissionGate', () {
    test('默认权限时在返回 Future 之前已同步调用浏览器原生请求', () async {
      final pending = Completer<WebNotificationPermission>();
      final api = _FakeBrowserApi()..pending = pending;
      final gate = WebNotificationPermissionGate(api: api);

      final future = gate.requestPermission();

      // 关键断言：调用方还没 await，底层就已经被调用（用户手势边界）。
      expect(api.requestCount, 1);

      pending.complete(WebNotificationPermission.granted);
      final result = await future;
      expect(result.outcome, WebNotificationRequestOutcome.granted);
      expect(result.isGranted, isTrue);
    });

    test('拒绝与未选择分别映射为 denied / dismissed', () async {
      final deniedApi = _FakeBrowserApi(
        permissionValue: WebNotificationPermission.denied,
      );
      final deniedGate = WebNotificationPermissionGate(api: deniedApi);
      final denied = await deniedGate.requestPermission();
      expect(denied.outcome, WebNotificationRequestOutcome.denied);
      expect(denied.previouslyDenied, isTrue);
      expect(denied.canPromptAgain, isFalse);
      // 已拒绝时浏览器不会再弹框，不能重复无效请求。
      expect(deniedApi.requestCount, 0);

      final promptApi = _FakeBrowserApi();
      final promptGate = WebNotificationPermissionGate(api: promptApi);
      final dismissed = await promptGate.requestPermission();
      expect(dismissed.outcome, WebNotificationRequestOutcome.dismissed);
      expect(dismissed.canPromptAgain, isTrue);
      expect(promptApi.requestCount, 1);
    });

    test('不支持与非安全上下文都不触发浏览器请求', () async {
      final unsupportedApi = _FakeBrowserApi(
        support: WebNotificationSupport.unsupported,
      );
      final unsupported = await WebNotificationPermissionGate(
        api: unsupportedApi,
      ).requestPermission();
      expect(unsupported.outcome, WebNotificationRequestOutcome.unsupported);
      expect(unsupportedApi.requestCount, 0);

      final insecureApi = _FakeBrowserApi(
        support: WebNotificationSupport.insecureContext,
      );
      final insecure = await WebNotificationPermissionGate(
        api: insecureApi,
      ).requestPermission();
      expect(insecure.outcome, WebNotificationRequestOutcome.insecureContext);
      expect(insecureApi.requestCount, 0);
    });

    test('请求抛异常时返回 failed 且允许再次尝试', () async {
      final api = _FakeBrowserApi()..requestError = StateError('boom');
      final gate = WebNotificationPermissionGate(api: api);

      final result = await gate.requestPermission();

      expect(result.outcome, WebNotificationRequestOutcome.failed);
      expect(result.error, isA<StateError>());
      expect(result.canPromptAgain, isTrue);
      expect(gate.hasPendingRequest, isFalse);
    });

    test('浏览器同步抛出时也返回 failed，且不留下未处理错误', () async {
      final api = _SyncThrowingApi();
      final gate = WebNotificationPermissionGate(api: api);
      final unhandled = <Object>[];

      final result =
          await runZonedGuarded<Future<WebNotificationRequestResult>>(
            () => gate.requestPermission(),
            (error, stackTrace) => unhandled.add(error),
          );
      await Future<void>.delayed(Duration.zero);

      // 同步 throw 不能变成 Future.error 或未处理的派生 Future。
      expect(unhandled, isEmpty);
      expect(result!.outcome, WebNotificationRequestOutcome.failed);
      expect(result.error, isA<StateError>());
      expect(result.canPromptAgain, isTrue);
      expect(api.requestCount, 1);
      expect(gate.hasPendingRequest, isFalse);

      // singleflight 已清理：可以再次请求，这次走正常返回路径。
      api.throwSync = false;
      final retry = await gate.requestPermission();
      expect(retry.outcome, WebNotificationRequestOutcome.dismissed);
      expect(api.requestCount, 2);
      expect(gate.hasPendingRequest, isFalse);
    });
    test('并发点击合流为一次请求', () async {
      final pending = Completer<WebNotificationPermission>();
      final api = _FakeBrowserApi()..pending = pending;
      final gate = WebNotificationPermissionGate(api: api);

      final first = gate.requestPermission();
      final second = gate.requestPermission();
      expect(api.requestCount, 1);
      expect(gate.hasPendingRequest, isTrue);

      pending.complete(WebNotificationPermission.granted);
      expect((await first).isGranted, isTrue);
      expect((await second).isGranted, isTrue);
      expect(gate.hasPendingRequest, isFalse);
    });

    test('refresh 读取外部撤权，且从不自动弹框', () async {
      final api = _FakeBrowserApi(
        permissionValue: WebNotificationPermission.granted,
      );
      final gate = WebNotificationPermissionGate(api: api);
      expect(gate.isGranted, isTrue);

      // 用户在站点设置里撤销授权。
      api.permissionValue = WebNotificationPermission.denied;
      expect(gate.isGranted, isFalse);
      expect(gate.refresh(), WebNotificationPermission.denied);
      expect(api.requestCount, 0);
    });

    test('granted 状态再次请求不会重复调用浏览器', () async {
      final api = _FakeBrowserApi(
        permissionValue: WebNotificationPermission.granted,
      );
      final gate = WebNotificationPermissionGate(api: api);

      final result = await gate.requestPermission();

      expect(result.isGranted, isTrue);
      expect(api.requestCount, 0);
    });
  });

  group('WebNotificationScheduler', () {
    late _DisplayRecorder display;
    late _FakeTimers timers;
    late DateTime now;
    late WebNotificationScheduler scheduler;

    setUp(() {
      display = _DisplayRecorder();
      timers = _FakeTimers();
      now = DateTime(2024, 1, 1, 8);
      scheduler = WebNotificationScheduler(
        display: display.call,
        now: () => now,
        timerFactory: timers.create,
      );
    });

    test('一次性提醒按真实延时注册并在触发时显示', () async {
      final when = now.add(const Duration(minutes: 30));
      scheduler.scheduleOnce(id: 7, title: 'T', body: 'B', when: when);

      expect(timers.timers.single.delay, const Duration(minutes: 30));
      expect(scheduler.pendingIds(), <int>[7]);

      now = when;
      timers.timers.single.fire();
      await _flushMicrotasks();

      expect(display.shown.single.id, 7);
      expect(display.shown.single.title, 'T');
      expect(scheduler.pendingIds(), isEmpty);
    });

    test('时间已过去时拒绝注册', () {
      expect(
        () => scheduler.scheduleOnce(
          id: 1,
          title: 'T',
          body: 'B',
          when: now.subtract(const Duration(minutes: 1)),
        ),
        throwsStateError,
      );
    });

    test('同 id 再次注册替换旧条目，只显示最后一次', () async {
      final first = now.add(const Duration(minutes: 10));
      final second = now.add(const Duration(minutes: 20));
      scheduler.scheduleOnce(id: 3, title: 'old', body: 'B', when: first);
      scheduler.scheduleOnce(id: 3, title: 'new', body: 'B', when: second);

      expect(scheduler.pendingIds(), <int>[3]);
      expect(timers.timers.first.cancelled, isTrue);

      now = second;
      for (final timer in timers.active) {
        timer.fire();
      }
      await _flushMicrotasks();

      expect(display.shown.single.title, 'new');
    });

    test('cancel 与 cancelAll 真的阻止显示', () async {
      scheduler.scheduleOnce(
        id: 11,
        title: 'T',
        body: 'B',
        when: now.add(const Duration(minutes: 5)),
      );
      scheduler.scheduleOnce(
        id: 12,
        title: 'T2',
        body: 'B',
        when: now.add(const Duration(minutes: 6)),
      );
      expect(scheduler.cancel(11), isTrue);
      expect(scheduler.cancel(99), isFalse);
      expect(scheduler.pendingIds(), <int>[12]);

      scheduler.cancelAll();
      expect(scheduler.pendingIds(), isEmpty);
      for (final timer in timers.timers) {
        timer.fire();
      }
      await _flushMicrotasks();
      expect(display.shown, isEmpty);
    });

    test('账号清理后旧代际回调不会迟到显示', () async {
      scheduler.scheduleOnce(
        id: 21,
        title: 'private',
        body: 'B',
        when: now.add(const Duration(minutes: 5)),
      );
      final staleFire = timers.timers.single.fire;

      scheduler.invalidate();

      // 模拟「定时器已触发、回调还在队列里」的时序。
      staleFire();
      await _flushMicrotasks();

      expect(display.shown, isEmpty);
      expect(scheduler.pendingIds(), isEmpty);
      expect(scheduler.generation, 1);
    });

    test('cleanup 之后重新注册仍能正常显示', () async {
      scheduler.invalidate();
      final when = now.add(const Duration(minutes: 5));
      scheduler.scheduleOnce(id: 22, title: 'after', body: 'B', when: when);

      now = when;
      timers.active.single.fire();
      await _flushMicrotasks();

      expect(display.shown.single.title, 'after');
    });

    test('每日提醒触发后按应用时区重新排期', () async {
      scheduler.scheduleDaily(
        id: 31,
        title: 'daily',
        body: 'B',
        hour: 9,
        minute: 0,
      );
      expect(timers.timers.single.delay, const Duration(hours: 1));
      expect(scheduler.nextFireAt(31), DateTime(2024, 1, 1, 9));

      now = DateTime(2024, 1, 1, 9);
      timers.timers.last.fire();
      await _flushMicrotasks();

      expect(display.shown.single.id, 31);
      expect(scheduler.pendingIds(), <int>[31]);
      expect(scheduler.nextFireAt(31), DateTime(2024, 1, 2, 9));
      expect(timers.timers.last.delay, const Duration(hours: 24));
    });

    test('限定星期时排到下一个匹配日', () {
      // 2024-01-01 是周一。
      scheduler.scheduleDaily(
        id: 41,
        title: 'weekly',
        body: 'B',
        hour: 9,
        minute: 0,
        weekdays: const <int>[3],
      );
      expect(scheduler.nextFireAt(41), DateTime(2024, 1, 3, 9));
    });

    test('显示失败记录为错误而不是假装成功', () async {
      final failing = WebNotificationScheduler(
        display: (notification) async => throw StateError('no permission'),
        now: () => now,
        timerFactory: timers.create,
      );
      final when = now.add(const Duration(minutes: 1));
      failing.scheduleOnce(id: 51, title: 'T', body: 'B', when: when);
      // 分段唤醒后必须真的到点才显示：先把模拟时钟推进到目标时间。
      now = when;
      timers.timers.single.fire();
      await _flushMicrotasks();

      expect(failing.lastDeliveryError, isA<StateError>());
      expect(failing.pendingIds(), isEmpty);
    });
  });

  group('WebNotificationScheduler 长未来分段唤醒', () {
    late _DisplayRecorder display;
    late _FakeTimers timers;
    late DateTime now;
    late WebNotificationScheduler scheduler;

    setUp(() {
      display = _DisplayRecorder();
      timers = _FakeTimers();
      now = DateTime(2024, 1, 1, 8);
      scheduler = WebNotificationScheduler(
        display: display.call,
        now: () => now,
        timerFactory: timers.create,
      );
    });

    test('单次等待有上限，提前唤醒不显示，到点只显示一次', () async {
      final when = now.add(const Duration(days: 60));
      scheduler.scheduleOnce(id: 71, title: 'far', body: 'B', when: when);

      expect(
        timers.timers.single.delay,
        WebNotificationScheduler.maxSingleTimerDelay,
      );
      expect(
        timers.timers.single.delay,
        lessThanOrEqualTo(WebNotificationScheduler.maxSingleTimerDelay),
      );

      var wakes = 0;
      while (now.isBefore(when)) {
        final remaining = when.difference(now);
        now = remaining > WebNotificationScheduler.maxSingleTimerDelay
            ? now.add(WebNotificationScheduler.maxSingleTimerDelay)
            : when;
        timers.timers.last.fire();
        await _flushMicrotasks();
        wakes++;
        expect(wakes, lessThan(70), reason: '不能无限唤醒');
        if (now.isBefore(when)) {
          expect(display.shown, isEmpty, reason: '未到真实目标不得显示');
        }
      }

      expect(display.shown, hasLength(1));
      expect(display.shown.single.title, 'far');
      expect(scheduler.pendingIds(), isEmpty);
    });

    test('分段等待过程中可以取消，残余回调不再显示', () async {
      final when = now.add(const Duration(days: 40));
      scheduler.scheduleOnce(id: 72, title: 'far', body: 'B', when: when);

      now = now.add(WebNotificationScheduler.maxSingleTimerDelay);
      timers.timers.last.fire();
      await _flushMicrotasks();
      expect(display.shown, isEmpty);
      expect(scheduler.pendingIds(), <int>[72]);

      expect(scheduler.cancel(72), isTrue);
      timers.timers.last.fire();
      await _flushMicrotasks();

      expect(display.shown, isEmpty);
      expect(scheduler.pendingIds(), isEmpty);
    });

    test('同 id 替换后只显示新目标', () async {
      final far = now.add(const Duration(days: 40));
      final near = now.add(const Duration(minutes: 5));
      scheduler.scheduleOnce(id: 73, title: 'far', body: 'B', when: far);
      scheduler.scheduleOnce(id: 73, title: 'near', body: 'B', when: near);

      expect(scheduler.pendingIds(), <int>[73]);
      expect(timers.timers.last.delay, const Duration(minutes: 5));

      now = near;
      timers.timers.last.fire();
      await _flushMicrotasks();

      expect(display.shown, hasLength(1));
      expect(display.shown.single.title, 'near');
    });
  });
}
