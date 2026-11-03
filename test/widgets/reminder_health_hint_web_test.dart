import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/models/goal.dart' show ReminderKind;
import 'package:duoyi/services/permission_health_service.dart';
import 'package:duoyi/services/web_notifications/web_notification_core.dart';
import 'package:duoyi/services/web_notifications/web_notification_service.dart';
import 'package:duoyi/widgets/reminder_health_hint.dart';

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
  WebNotificationPermission? resolveAs;

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
    final resolved = resolveAs;
    if (resolved != null) {
      permissionValue = resolved;
      return Future<WebNotificationPermission>.value(resolved);
    }
    return Future<WebNotificationPermission>.value(permissionValue);
  }

  @override
  Future<void> show({
    required String title,
    required String body,
    required String tag,
    void Function()? onClick,
  }) async {}

  @override
  Future<void> close(String tag) async {}

  @override
  Future<void> closeAll() async {}
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

Future<void> _pumpHint(
  WidgetTester tester, {
  required WebNotificationService service,
  required Future<void> Function() onRequest,
  bool? forceWebBranch,
}) async {
  await tester.pumpWidget(
    _host(
      ReminderHealthHint(
        reminderKind: ReminderKind.push,
        onOpenSystemSettings: () {},
        onRequestNotificationPermission: onRequest,
        onRequestExactAlarmPermission: () async {},
        onRequestFullScreenIntentPermission: () async {},
        webNotifications: service,
        forceWebBranch: forceWebBranch ?? true,
      ),
    ),
  );
}

void main() {
  testWidgets('点击“通知授权”真正调用浏览器请求并显示拒绝反馈', (tester) async {
    final api = _FakeBrowserApi()..resolveAs = WebNotificationPermission.denied;
    final service = WebNotificationService(api: api, isWeb: true);
    var callbackCount = 0;

    await _pumpHint(
      tester,
      service: service,
      onRequest: () async {
        callbackCount++;
        await service.requestPermission();
      },
    );

    expect(find.text('通知授权'), findsOneWidget);

    await tester.tap(find.text('通知授权'));
    await tester.pump();
    await tester.pump();

    expect(callbackCount, 1);
    expect(api.requestCount, 1);
    // 拒绝后必须给出「去站点设置」的可执行说明。
    expect(find.textContaining('站点设置'), findsWidgets);
  });

  testWidgets('请求期间显示忙态并阻止重复请求', (tester) async {
    final pending = Completer<WebNotificationPermission>();
    final api = _FakeBrowserApi()..pending = pending;
    final service = WebNotificationService(api: api, isWeb: true);

    await _pumpHint(
      tester,
      service: service,
      onRequest: () async {
        await service.requestPermission();
      },
    );

    await tester.tap(find.text('通知授权'));
    await tester.pump();

    expect(api.requestCount, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('正在等待浏览器'), findsOneWidget);
    // 忙态下按钮不再出现，无法重复触发。
    expect(find.text('通知授权'), findsNothing);

    // 浏览器授权成功后权限属性同步变为 granted（真实浏览器行为）。
    api.permissionValue = WebNotificationPermission.granted;
    pending.complete(WebNotificationPermission.granted);
    await tester.pump();
    await tester.pump();

    expect(api.requestCount, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('需保持网页打开'), findsOneWidget);
  });

  testWidgets('已拒绝时不再提供无效的重复请求按钮', (tester) async {
    final api = _FakeBrowserApi(
      permissionValue: WebNotificationPermission.denied,
    );
    final service = WebNotificationService(api: api, isWeb: true);

    await _pumpHint(
      tester,
      service: service,
      onRequest: () async {
        await service.requestPermission();
      },
    );

    expect(find.textContaining('站点设置'), findsWidgets);
    expect(find.text('通知授权'), findsNothing);
  });

  testWidgets('浏览器不支持通知时给出准确说明', (tester) async {
    final api = _FakeBrowserApi(support: WebNotificationSupport.unsupported);
    final service = WebNotificationService(api: api, isWeb: true);

    await _pumpHint(
      tester,
      service: service,
      onRequest: () async {
        await service.requestPermission();
      },
    );

    expect(find.textContaining('不支持网页通知'), findsOneWidget);
    expect(find.text('通知授权'), findsNothing);
  });

  testWidgets('非安全上下文时说明需要 HTTPS 或 localhost', (tester) async {
    final api = _FakeBrowserApi(
      support: WebNotificationSupport.insecureContext,
    );
    final service = WebNotificationService(api: api, isWeb: true);

    await _pumpHint(
      tester,
      service: service,
      onRequest: () async {
        await service.requestPermission();
      },
    );

    expect(find.textContaining('安全上下文'), findsOneWidget);
    expect(find.text('通知授权'), findsNothing);
  });

  testWidgets('已授权时说明网页内提醒的真实边界', (tester) async {
    final api = _FakeBrowserApi(
      permissionValue: WebNotificationPermission.granted,
    );
    final service = WebNotificationService(api: api, isWeb: true);

    await _pumpHint(
      tester,
      service: service,
      onRequest: () async {
        await service.requestPermission();
      },
    );

    expect(find.textContaining('需保持网页打开'), findsOneWidget);
    expect(find.textContaining('关闭网页后不能保证'), findsOneWidget);
    expect(find.textContaining('native'), findsNothing);
  });

  testWidgets('请求异常后仍可再次尝试', (tester) async {
    final api = _FakeBrowserApi()..requestError = StateError('boom');
    final service = WebNotificationService(api: api, isWeb: true);

    await _pumpHint(
      tester,
      service: service,
      onRequest: () async {
        await service.requestPermission();
      },
    );

    await tester.tap(find.text('通知授权'));
    await tester.pump();
    await tester.pump();

    expect(api.requestCount, 1);
    expect(find.textContaining('请求失败'), findsOneWidget);
    expect(find.text('通知授权'), findsOneWidget);

    api.requestError = null;
    api.resolveAs = WebNotificationPermission.granted;
    await tester.tap(find.text('通知授权'));
    await tester.pump();
    await tester.pump();

    expect(api.requestCount, 2);
    expect(find.textContaining('需保持网页打开'), findsOneWidget);
  });

  testWidgets('非 Web 构建仍走原生提醒健康分支', (tester) async {
    final api = _FakeBrowserApi();
    final service = WebNotificationService(api: api, isWeb: false);

    await _pumpHint(
      tester,
      service: service,
      onRequest: () async {},
      forceWebBranch: false,
    );

    // 原生分支仍由 FutureBuilder 读取系统提醒健康，且不出现 Web 分支文案。
    expect(
      find.byType(FutureBuilder<NotificationHealthReport>),
      findsOneWidget,
    );
    expect(find.textContaining('需保持网页打开'), findsNothing);
    expect(find.textContaining('安全上下文'), findsNothing);
    expect(find.textContaining('不支持网页通知'), findsNothing);
  });

  test('原生提醒健康文案守卫保持不变', () {
    final hint = File(
      'lib/widgets/reminder_health_hint.dart',
    ).readAsStringSync();
    expect(hint, contains("actionLabel = '通知授权'"));
    expect(hint, contains("actionLabel = '精准闹钟'"));
    expect(hint, contains("actionLabel = '弹屏权限'"));
    expect(hint, isNot(contains("actionLabel = '去授权'")));
    // 原生分支仍把点击交给传入的回调，并保留系统设置入口。
    expect(hint, contains('action = _handleNotificationPermission;'));
    expect(hint, contains('onTap: widget.onOpenSystemSettings'));
    expect(hint, contains('await widget.onRequestNotificationPermission();'));

    final export = File(
      'lib/services/local_notifications.dart',
    ).readAsStringSync();
    expect(
      export,
      contains("if (dart.library.js_interop) 'local_notifications_web.dart'"),
    );
    // 原生 io 实现仍是第一优先级，行为未变。
    expect(
      export,
      contains("if (dart.library.io) 'local_notifications_io.dart'"),
    );
  });
}
