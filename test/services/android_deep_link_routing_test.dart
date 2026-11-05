import 'dart:async';
import 'dart:io';

import 'package:duoyi/services/deep_link_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('duoyi/deep_links');
  const codec = StandardMethodCodec();

  Future<void> dispatchLink(String value) async {
    final reply = Completer<void>();
    binding.channelBuffers.push(
      'duoyi/deep_links',
      codec.encodeMethodCall(MethodCall('onLink', value)),
      (_) => reply.complete(),
    );
    await reply.future.timeout(const Duration(seconds: 2));
  }

  tearDown(() {
    DeepLinkService.onLink = null;
    DeepLinkService.onSharedText = null;
    channel.setMethodCallHandler(null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('Android 自有深链接通道关闭默认命名路由分发', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final activity = RegExp(
      r'<activity\b[^>]*android:name="\.MainActivity"[\s\S]*?</activity>',
    ).firstMatch(manifest)?.group(0);
    expect(activity, isNotNull);
    final metadata = RegExp(
      r'<meta-data\b[^>]*android:name="flutter_deeplinking_enabled"[^>]*/>',
    ).firstMatch(activity!)?.group(0);
    expect(
      metadata,
      isNotNull,
      reason: '专注拉回和通知 URI 已由 duoyi/deep_links 消费，默认路由会重复 push 未注册名称。',
    );
    expect(metadata, contains('android:value="false"'));
    expect(activity, contains('<data android:scheme="duoyi"'));
  });

  test('专注和通知热链接在重复初始化后仍各分发一次', () async {
    final received = <Uri>[];
    DeepLinkService.onLink = received.add;
    await DeepLinkService.init();
    await DeepLinkService.init();
    await dispatchLink('duoyi://focus');
    await dispatchLink('duoyi://tab/focus');
    expect(received, [
      Uri.parse('duoyi://focus'),
      Uri.parse('duoyi://tab/focus'),
    ]);
  });

  test('关闭默认入口仍保留原生冷启动专注和 OAuth 链接', () async {
    final calls = <String>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return switch (call.method) {
        'takeInitialLink' => 'duoyi://focus',
        'takeInitialOAuthLink' => 'duoyi://oauth/calendar?state=local-fixture',
        _ => null,
      };
    });
    expect(await DeepLinkService.takeInitialLink(), Uri.parse('duoyi://focus'));
    expect(
      await DeepLinkService.takeInitialOAuthLink(),
      Uri.parse('duoyi://oauth/calendar?state=local-fixture'),
    );
    expect(calls, ['takeInitialLink', 'takeInitialOAuthLink']);
  });

  test('非多仪热链接不会进入应用分发通道', () async {
    final received = <Uri>[];
    DeepLinkService.onLink = received.add;
    await DeepLinkService.init();
    await dispatchLink('https://example.invalid/focus');
    await dispatchLink('not-a-deep-link');
    expect(received, isEmpty);
  });
}
