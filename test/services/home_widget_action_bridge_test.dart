import 'dart:convert';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:duoyi/services/home_widget_action_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

const String _startUri =
    'duoyi://action/start_pomodoro?session=s1&revision=0&state=idle&scope=local';
const String _pauseUri =
    'duoyi://action/pause_pomodoro?session=s1&revision=1&state=running&scope=local';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    HomeWidgetActionBridge.unregisterMainHandler();
    HomeWidgetActionBridge.debugLookupPort = (name) =>
        IsolateNameServer.lookupPortByName(name);
  });

  tearDown(() {
    HomeWidgetActionBridge.unregisterMainHandler();
    HomeWidgetActionBridge.debugLookupPort = (name) =>
        IsolateNameServer.lookupPortByName(name);
  });

  test('两条并发转发在主 isolate 串行执行并按顺序 ACK', () async {
    final order = <String>[];
    var inFlight = 0;
    var maxInFlight = 0;
    HomeWidgetActionBridge.registerMainHandler((uri) async {
      inFlight++;
      if (inFlight > maxInFlight) maxInFlight = inFlight;
      order.add(uri.pathSegments.first);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      inFlight--;
      return HomeWidgetActionAck.done;
    });
    expect(HomeWidgetActionBridge.hasMainHandler, isTrue);

    final results = await Future.wait(<Future<bool>>[
      HomeWidgetActionBridge.forwardToMainIsolate(Uri.parse(_startUri)),
      HomeWidgetActionBridge.forwardToMainIsolate(Uri.parse(_pauseUri)),
    ]);

    expect(results, <bool>[true, true]);
    expect(order, <String>['start_pomodoro', 'pause_pomodoro']);
    // 串行：任何时刻只有一个动作在跑，连点不会并发双写。
    expect(maxInFlight, 1);
  });

  test('主 isolate 处理器异常仍算被接管（后台不重跑）', () async {
    HomeWidgetActionBridge.registerMainHandler(
      (_) async => throw StateError('boom'),
    );
    final forwarded = await HomeWidgetActionBridge.forwardToMainIsolate(
      Uri.parse(_startUri),
      timeout: const Duration(seconds: 2),
    );
    expect(forwarded, isTrue);
  });

  test('没有主 isolate 端口时回落到冷路径', () async {
    HomeWidgetActionBridge.debugLookupPort = (_) => null;
    expect(
      await HomeWidgetActionBridge.forwardToMainIsolate(
        Uri.parse(_pauseUri),
        timeout: const Duration(milliseconds: 50),
      ),
      isFalse,
    );
  });

  test('回信只传 ACK 名称字符串', () async {
    final mainPort = ReceivePort();
    final received = <Object?>[];
    mainPort.listen(received.add);
    HomeWidgetActionBridge.debugLookupPort = (name) =>
        name == HomeWidgetActionBridge.portName ? mainPort.sendPort : null;
    try {
      await HomeWidgetActionBridge.forwardToMainIsolate(
        Uri.parse(_startUri),
        timeout: const Duration(milliseconds: 50),
      );
      await pumpEventQueue();
      final message = received.single! as List;
      expect(message, hasLength(2));
      expect(jsonEncode(message[0]), jsonEncode(_startUri));
      expect(message[1], isA<SendPort>());
    } finally {
      mainPort.close();
    }
  });
}
