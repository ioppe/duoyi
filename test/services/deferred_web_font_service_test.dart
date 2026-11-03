import 'dart:async';
import 'dart:typed_data';

import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/services/deferred_web_font_platform.dart';
import 'package:duoyi/services/deferred_web_font_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// 让挂起的微任务/零延时定时器先跑完，用于断言「还没发生」的中间态。
Future<void> _settle([int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _FakePlatform extends DeferredWebFontPlatform {
  _FakePlatform();

  @override
  bool isOnline = true;

  @override
  bool isVisible = true;

  @override
  bool saveData = false;

  @override
  String? effectiveConnectionType;

  @override
  Future<void> whenIdle(Duration timeout) => Future<void>.value();
}

/// 记录服务行为的最小测试替身：标记、等待、资产、注册与通知全部可断言。
class _Recorder {
  final List<String> events = <String>[];
  final List<Duration> waits = <Duration>[];
  final List<Duration> idleWaits = <Duration>[];
  final List<String> assetKeys = <String>[];
  final List<ByteData?> registeredBytes = <ByteData?>[];
  int notifications = 0;
  bool failMark = false;

  void mark(String name) {
    if (failMark) throw StateError('performance.mark unavailable');
    events.add(name);
  }

  DeferredWebFontService service({
    bool isWeb = true,
    DeferredWebFontPlatform? platform,
    DeferredFontWait? wait,
    DeferredFontIdleWait? waitForIdle,
    DeferredFontBytesLoader? loadFontBytes,
    DeferredFontRegistrar? registerFont,
  }) {
    return DeferredWebFontService(
      isWeb: isWeb,
      platform: platform,
      wait:
          wait ??
          (duration) {
            waits.add(duration);
            return Future<void>.value();
          },
      waitForIdle:
          waitForIdle ??
          (timeout) {
            idleWaits.add(timeout);
            return Future<void>.value();
          },
      loadFontBytes:
          loadFontBytes ??
          (assetKey) async {
            assetKeys.add(assetKey);
            return ByteData(4);
          },
      registerFont:
          registerFont ??
          (bytes) async {
            registeredBytes.add(bytes);
          },
      mark: mark,
      notifyFontsChanged: () => notifications++,
    );
  }
}

void main() {
  test('原生平台不调度、不读资产、不打标记', () async {
    final recorder = _Recorder();
    final service = recorder.service(isWeb: false);

    service.schedule();
    expect(service.pending, isNull, reason: '原生端不应产生任何异步流程');

    await _settle();
    expect(service.pending, isNull);
    expect(recorder.events, isEmpty);
    expect(recorder.waits, isEmpty);
    expect(recorder.idleWaits, isEmpty);
    expect(recorder.assetKeys, isEmpty);
    expect(recorder.registeredBytes, isEmpty);
    expect(recorder.notifications, 0);
    expect(service.didLoad, isFalse);
  });

  test('默认等待 15 秒，延时结束前不读取字体', () async {
    final recorder = _Recorder();
    final gate = Completer<void>();
    final service = recorder.service(
      wait: (duration) {
        recorder.waits.add(duration);
        return gate.future;
      },
    );

    service.schedule();
    await _settle();

    expect(recorder.waits, [const Duration(seconds: 15)]);
    expect(recorder.events, [DeferredWebFontService.firstFrameMark]);
    expect(recorder.idleWaits, isEmpty);
    expect(recorder.assetKeys, isEmpty);

    gate.complete();
    await service.pending!;

    expect(recorder.assetKeys, [DeferredWebFontService.fontAssetKey]);
    expect(recorder.events, contains(DeferredWebFontService.downloadStartMark));
  });

  test('等浏览器空闲回调返回后才发起下载，兜底上限 1 秒', () async {
    final recorder = _Recorder();
    final idleGate = Completer<void>();
    final service = recorder.service(
      waitForIdle: (timeout) {
        recorder.idleWaits.add(timeout);
        return idleGate.future;
      },
    );

    service.schedule();
    await _settle();

    expect(recorder.idleWaits, [const Duration(seconds: 1)]);
    expect(recorder.assetKeys, isEmpty);
    expect(
      recorder.events,
      isNot(contains(DeferredWebFontService.downloadStartMark)),
    );

    idleGate.complete();
    await service.pending!;

    expect(recorder.assetKeys, [DeferredWebFontService.fontAssetKey]);
  });

  test('重复与并发 schedule 至多加载一次', () async {
    final recorder = _Recorder();
    final service = recorder.service();

    service.schedule();
    service.schedule();
    await _settle();
    service.schedule();
    await service.pending!;
    service.schedule();
    await _settle();

    expect(recorder.assetKeys.length, 1);
    expect(recorder.registeredBytes.length, 1);
    expect(
      recorder.events
          .where((event) => event == DeferredWebFontService.firstFrameMark)
          .length,
      1,
    );
    expect(
      recorder.events
          .where((event) => event == DeferredWebFontService.loadedMark)
          .length,
      1,
    );
    expect(service.didLoad, isTrue);
  });

  test('延时结束后复查网络，转成离线则跳过本会话', () async {
    final recorder = _Recorder();
    final platform = _FakePlatform();
    final service = recorder.service(
      platform: platform,
      wait: (duration) {
        recorder.waits.add(duration);
        platform.isOnline = false;
        return Future<void>.value();
      },
    );

    service.schedule();
    await service.pending!;

    expect(recorder.events, [
      DeferredWebFontService.firstFrameMark,
      DeferredWebFontService.skippedMark,
    ]);
    expect(recorder.idleWaits, isEmpty, reason: '受限环境不再申请空闲窗口');
    expect(recorder.assetKeys, isEmpty);
  });

  test('空闲回调结束后复查可见性，转后台则跳过', () async {
    final recorder = _Recorder();
    final platform = _FakePlatform();
    final service = recorder.service(
      platform: platform,
      waitForIdle: (timeout) {
        recorder.idleWaits.add(timeout);
        platform.isVisible = false;
        return Future<void>.value();
      },
    );

    service.schedule();
    await service.pending!;

    expect(recorder.events, [
      DeferredWebFontService.firstFrameMark,
      DeferredWebFontService.skippedMark,
    ]);
    expect(recorder.assetKeys, isEmpty);
    expect(recorder.notifications, 0);
  });

  test('离线、隐藏、省流、slow-2g/2g 都不下载完整字体', () async {
    final cases = <String, void Function(_FakePlatform)>{
      'offline': (platform) => platform.isOnline = false,
      'hidden': (platform) => platform.isVisible = false,
      'saveData': (platform) => platform.saveData = true,
      'slow-2g': (platform) => platform.effectiveConnectionType = 'slow-2g',
      '2g': (platform) => platform.effectiveConnectionType = '2g',
    };

    for (final entry in cases.entries) {
      final recorder = _Recorder();
      final platform = _FakePlatform();
      entry.value(platform);
      final service = recorder.service(platform: platform);

      service.schedule();
      await service.pending!;

      expect(
        recorder.events.last,
        DeferredWebFontService.skippedMark,
        reason: entry.key,
      );
      expect(recorder.assetKeys, isEmpty, reason: entry.key);
      expect(service.didLoad, isFalse, reason: entry.key);
    }
  });

  test('加载失败被吞掉，不重试、不通知、不留未处理异常', () async {
    final recorder = _Recorder();
    var attempts = 0;
    final service = recorder.service(
      loadFontBytes: (assetKey) async {
        attempts++;
        throw StateError('asset unavailable');
      },
    );

    service.schedule();
    await service.pending!;

    expect(attempts, 1);
    expect(recorder.registeredBytes, isEmpty);
    expect(recorder.notifications, 0);
    expect(service.didLoad, isFalse);
    expect(service.lastError, isA<StateError>());
    expect(recorder.events.last, DeferredWebFontService.errorMark);

    service.schedule();
    await _settle();
    expect(attempts, 1, reason: '失败后本会话不再重试');
  });

  test('成功后只通知一次 fontsChange，资产路径与字体家族正确', () async {
    final recorder = _Recorder();
    final platform = _FakePlatform()..effectiveConnectionType = '4g';
    final bytes = ByteData(8);
    final service = recorder.service(
      platform: platform,
      loadFontBytes: (assetKey) async {
        recorder.assetKeys.add(assetKey);
        return bytes;
      },
    );

    service.schedule();
    await service.pending!;

    expect(
      DeferredWebFontService.fontAssetKey,
      'assets/fonts/NotoSansSC-Variable.ttf',
    );
    expect(recorder.assetKeys, [DeferredWebFontService.fontAssetKey]);
    expect(DeferredWebFontService.fontFamily, DesignTokens.fontFamily);
    expect(
      DeferredWebFontService.fontAssetKey,
      contains(DeferredWebFontService.fontFamily),
    );
    expect(recorder.registeredBytes.single, same(bytes));
    expect(recorder.registeredBytes.length, 1);
    expect(recorder.notifications, 1);
    expect(service.didLoad, isTrue);
    expect(service.lastError, isNull);
    expect(recorder.events, [
      DeferredWebFontService.firstFrameMark,
      DeferredWebFontService.downloadStartMark,
      DeferredWebFontService.loadedMark,
    ]);
  });

  test('浏览器标记失败不影响字体加载', () async {
    final recorder = _Recorder()..failMark = true;
    final service = recorder.service();

    service.schedule();
    await service.pending!;

    expect(service.didLoad, isTrue);
    expect(recorder.registeredBytes.length, 1);
    expect(recorder.notifications, 1);
    expect(service.lastError, isA<StateError>());
  });
  test('下载长期无响应时超时退出，不延迟注册或重试', () {
    fakeAsync((clock) {
      final recorder = _Recorder();
      final bytes = Completer<ByteData>();
      final service = recorder.service(loadFontBytes: (_) => bytes.future);
      service.schedule();
      clock.flushMicrotasks();
      clock.elapse(DeferredWebFontService.downloadTimeout);
      clock.flushMicrotasks();
      expect(service.lastError, isA<TimeoutException>());
      expect(recorder.events.last, DeferredWebFontService.errorMark);
      expect(recorder.notifications, 0);
      bytes.complete(ByteData(4));
      clock.flushMicrotasks();
      expect(recorder.registeredBytes, isEmpty);
      expect(service.didLoad, isFalse);
    });
  });
}
