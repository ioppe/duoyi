import 'web_notification_core.dart';

/// 非 Web 平台的浏览器 API 桥：能力一律为不支持。
///
/// 原生平台的本地通知走 `local_notifications_io.dart`，这个实现只用于让
/// `WebNotificationService` 在 VM / 原生上也能安全构造（不进权限分支）。
WebNotificationBrowserApi createWebNotificationBrowserApi() =>
    const UnsupportedWebNotificationBrowserApi();

class UnsupportedWebNotificationBrowserApi
    implements WebNotificationBrowserApi {
  const UnsupportedWebNotificationBrowserApi();

  @override
  WebNotificationSupport supportStatus() => WebNotificationSupport.unsupported;

  @override
  WebNotificationPermission permission() => WebNotificationPermission.prompt;

  @override
  Future<WebNotificationPermission> requestPermission() async =>
      WebNotificationPermission.prompt;

  @override
  Future<void> show({
    required String title,
    required String body,
    required String tag,
    void Function()? onClick,
  }) async {
    throw UnsupportedError('当前平台不支持浏览器通知');
  }

  @override
  Future<void> close(String tag) async {}

  @override
  Future<void> closeAll() async {}
}
