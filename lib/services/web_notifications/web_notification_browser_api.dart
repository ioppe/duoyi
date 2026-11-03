// 浏览器通知 API 桥；Web 构建使用 `dart:js_interop`，其它平台退化到 stub。
//
// 只有真正调用浏览器 API 的代码在这里，权限/调度判断都在
// `web_notification_core.dart`（纯 Dart，可在 VM 测试）。
export 'web_notification_browser_api_stub.dart'
    if (dart.library.js_interop) 'web_notification_browser_api_web.dart';
