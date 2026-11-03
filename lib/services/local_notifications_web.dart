/// Web 环境本地通知实现：走浏览器 Notifications API（网页内定时），
/// 与 `local_notifications_stub.dart` 保持同一套公开接口。
///
/// 明确的支持边界：
/// - 只有用户显式点击授权后才显示系统通知；`init`/`refresh`/`ensure` 不弹框；
/// - 定时提醒是「网页内 timer」：关闭页面后不会触发，后台标签页受浏览器节流；
/// - 没有 Web Push、后端调度与新的 Service Worker：浏览器构造器不可用时只用
///   已激活的 service worker 投递，否则抛明确异常，不假装成功；
/// - Android 专有接口（quickAdd ongoing / 渠道 / 铃声）在这里是兼容性空操作。
library;

import 'notification_permission_exception.dart';
import 'web_notifications/web_notification_service.dart';

class LocalNotifications {
  static final LocalNotifications instance = LocalNotifications._();
  LocalNotifications._();

  static const int quickAddNotificationId = 880016;
  static const int diagnosticNotificationId = 919003;
  static const int scheduledDiagnosticNotificationId = 919004;
  static const String quickAddChannelId = 'duoyi_quick_add_ongoing_v2';
  static const Set<int> reservedNotificationIds = <int>{
    quickAddNotificationId,
    880017,
    880018,
    880019,
    880020,
    880021,
    880022,
    880023,
    919001,
    919002,
    diagnosticNotificationId,
    scheduledDiagnosticNotificationId,
  };

  WebNotificationService get _service => WebNotificationService.instance;

  bool get permissionGranted => _service.permissionGranted;

  /// Tap 回调(payload)——由主入口注册处理 deep link。
  ///
  /// 网页通知只能在本页存活期间被点击；关闭页面后点击不保证唤起应用。
  void Function(String payload)? onTap;

  Future<void> init() async {
    await _service.init();
    _service.onTap = (payload) => onTap?.call(payload);
  }

  Future<void> initForLaunchPayload() async {}

  /// 只读当前浏览器权限并记录结果，不弹权限框。
  Future<bool> refreshPermission() async => _service.refreshPermission();

  /// 只读当前权限；Web 侧绝不在此弹权限框（避免丢失 user activation）。
  Future<bool> ensurePermission() async => _service.refreshPermission();

  /// 用户手势触发的显式授权。
  ///
  /// 调用方必须在点击链路里同步调用本方法（内部会同步发起浏览器原生请求）。
  Future<bool> requestPermission() async {
    final result = await _service.requestPermission();
    return result.isGranted;
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
    String? channelId,
  }) async {
    if (!permissionGranted) {
      throw const NotificationPermissionDeniedException('浏览器通知未授权，通知未显示');
    }
    await _service.show(id: id, title: title, body: body, payload: payload);
  }

  Future<void> showQuickAddOngoing({
    String? title,
    String? body,
    bool enableQuickActions = true,
    bool requestIfNeeded = false,
    bool force = false,
  }) async {}

  Future<void> cancelQuickAddOngoing() async {}

  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    String? channelId,
    bool requestIfNeeded = false,
  }) async {
    if (!permissionGranted) {
      throw const NotificationPermissionDeniedException('浏览器通知未授权，提醒未注册');
    }
    await _service.scheduleOnce(
      id: id,
      title: title,
      body: body,
      when: when,
      payload: payload,
    );
  }

  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
    String? channelId,
    List<int>? weekdays,
    bool requestIfNeeded = false,
  }) async {
    if (!permissionGranted) {
      throw const NotificationPermissionDeniedException('浏览器通知未授权，提醒未注册');
    }
    await _service.scheduleDaily(
      id: id,
      title: title,
      body: body,
      hour: hour,
      minute: minute,
      weekdays: weekdays,
      payload: payload,
    );
  }

  Future<void> cancel(int id) async {
    await _service.cancel(id);
  }

  Future<void> cancelAll() async {
    await _service.cancelAll();
  }

  Future<List<int>> pendingIds() async => _service.pendingIds();

  Future<Set<String>?> notificationChannelIds() async => const <String>{};

  Future<void> refreshAndroidRingtoneChannels() async {}

  String? takeLaunchPayload() => null;
}
