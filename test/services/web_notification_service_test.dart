import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/services/web_notifications/web_notification_core.dart';
import 'package:duoyi/services/web_notifications/web_notification_service.dart';

class _FakeBrowserApi implements WebNotificationBrowserApi {
  WebNotificationPermission permissionValue = WebNotificationPermission.granted;
  int requestCount = 0;
  int closeAllCount = 0;
  Completer<WebNotificationPermission>? pending;
  final List<String> shownTags = <String>[];

  @override
  WebNotificationSupport supportStatus() => WebNotificationSupport.supported;

  @override
  WebNotificationPermission permission() => permissionValue;

  @override
  Future<WebNotificationPermission> requestPermission() {
    requestCount++;
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
    closeAllCount++;
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
}

void main() {
  late _FakeBrowserApi api;
  late _FakeTimers timers;
  late DateTime now;

  WebNotificationService buildService() => WebNotificationService(
    api: api,
    isWeb: true,
    now: () => now,
    timerFactory: timers.create,
  );

  setUp(() {
    api = _FakeBrowserApi();
    timers = _FakeTimers();
    now = DateTime(2024, 1, 1, 8);
  });

  test('cancelAll 清空 lastRequest、停止计时并关闭浏览器通知', () async {
    final service = buildService();
    await service.scheduleOnce(
      id: 7,
      title: 'T',
      body: 'B',
      when: now.add(const Duration(hours: 1)),
    );
    expect(service.pendingIds(), <int>[7]);

    final granted = await service.requestPermission();
    expect(granted.isGranted, isTrue);
    expect(service.lastRequest, isNotNull);

    await service.cancelAll();

    expect(service.lastRequest, isNull);
    expect(service.pendingIds(), isEmpty);
    expect(api.closeAllCount, 1);

    // 清理之后残留的回调不能再投递。
    now = now.add(const Duration(hours: 1));
    timers.timers.single.fire();
    await Future<void>.delayed(Duration.zero);
    expect(api.shownTags, isEmpty);
  });

  test('账号清理时在途权限结果不回写 lastRequest', () async {
    final service = buildService();
    final pending = Completer<WebNotificationPermission>();
    api
      ..permissionValue = WebNotificationPermission.prompt
      ..pending = pending;

    final request = service.requestPermission();
    expect(api.requestCount, 1);
    expect(service.hasPendingRequest, isTrue);

    await service.cancelAll();
    expect(api.closeAllCount, 1);
    expect(service.lastRequest, isNull);

    // 权限框在清理之后才返回：结果本身仍可读，但不能恢复旧身份的 lastRequest。
    api.permissionValue = WebNotificationPermission.granted;
    pending.complete(WebNotificationPermission.granted);

    final result = await request;
    expect(result.isGranted, isTrue);
    expect(service.lastRequest, isNull);
  });

  test('清理之后的新请求仍可写入 lastRequest', () async {
    final service = buildService();
    await service.cancelAll();

    final result = await service.requestPermission();

    expect(result.isGranted, isTrue);
    expect(service.lastRequest, isNotNull);
  });
}
