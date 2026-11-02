import 'package:flutter/foundation.dart';

import '../../core/app_clock.dart';
import '../notification_permission_exception.dart';
import 'web_notification_browser_api.dart';
import 'web_notification_core.dart';

/// Web（浏览器）通知服务：权限状态 + 网页内定时提醒。
///
/// 这是 Web 侧唯一的通知入口，`local_notifications_web.dart`、
/// `ReminderHealthHint` 与 VM 测试共用同一套状态与调度语义：
/// - 权限只在用户手势的显式调用里申请；`init`/`refresh`/`ensure` 永不弹框；
/// - `permissionGranted` 直接读浏览器当前状态，用户在站点设置里外部改动后
///   一次刷新即可读到；
/// - 定时提醒只在当前页面存活期间有效（网页内 timer），不承诺关闭页面后的
///   后台唤起，也没有 Web Push / 后端调度。
class WebNotificationService {
  WebNotificationService({
    WebNotificationBrowserApi? api,
    bool? isWeb,
    WebNotificationNow? now,
    WebNotificationTimerFactory? timerFactory,
    WebNotificationDateBuilder? dateBuilder,
  }) : _api = api ?? createWebNotificationBrowserApi(),
       _isWeb = isWeb ?? kIsWeb,
       _now = now ?? AppClock.now,
       _dateBuilder = dateBuilder ?? _appClockDate {
    _gate = WebNotificationPermissionGate(api: _api);
    _scheduler = WebNotificationScheduler(
      display: _deliverScheduled,
      now: _now,
      timerFactory: timerFactory,
      dateBuilder: _dateBuilder,
    );
  }

  static final WebNotificationService instance = WebNotificationService();

  final WebNotificationBrowserApi _api;
  final bool _isWeb;
  final WebNotificationNow _now;
  final WebNotificationDateBuilder _dateBuilder;
  late final WebNotificationPermissionGate _gate;
  late final WebNotificationScheduler _scheduler;
  WebNotificationRequestResult? _lastRequest;

  /// 每次账号清理/全部取消递增：在途权限请求的结果不得跨代际回写。
  int _requestGeneration = 0;

  /// 与 `LocalNotifications.onTap` 同义的 deep link 回调。
  void Function(String payload)? onTap;

  /// 当前构建是不是 Web（VM 测试可用构造参数覆盖）。
  bool get isWeb => _isWeb;

  WebNotificationSupport get support => _gate.support;

  WebNotificationPermission get permission => _gate.permission;

  bool get isSupported => support == WebNotificationSupport.supported;

  bool get permissionGranted => _isWeb && _gate.isGranted;

  bool get hasPendingRequest => _gate.hasPendingRequest;

  /// 最近一次显式授权请求的结果（供共享 hint 显示准确反馈）。
  WebNotificationRequestResult? get lastRequest => _lastRequest;

  int get pendingCount => _scheduler.pendingIds().length;

  List<int> pendingIds() => _scheduler.pendingIds();

  /// 只读状态，不弹权限框。
  Future<void> init() async {
    _gate.refresh();
  }

  /// 只读状态，不弹权限框（应用回到前台时用）。
  Future<bool> refreshPermission() async {
    _gate.refresh();
    return permissionGranted;
  }

  /// 在用户手势中申请通知权限。
  ///
  /// 本方法不是 `async`：先同步发起浏览器原生请求，再返回合流后的 Future，
  /// 保证 user activation 不丢失。重复点击会复用同一次请求。
  Future<WebNotificationRequestResult> requestPermission() {
    final generation = _requestGeneration;
    final pending = _gate.requestPermission();
    return pending.then((result) {
      // 只有仍属于当前账号代际的请求才回写：旧代际的迟到结果依旧可作为浏览器
      // 全局权限被读取，但不能恢复上一个身份的 lastRequest。
      if (generation == _requestGeneration) _lastRequest = result;
      return result;
    });
  }

  void clearLastRequest() {
    _lastRequest = null;
  }

  String _tagFor(int id) => 'duoyi-$id';

  void _requirePermission(String operation) {
    if (permissionGranted) return;
    debugPrint(
      '[WebNotificationService] $operation skipped: browser notification '
      'permission not granted',
    );
    throw const NotificationPermissionDeniedException('浏览器通知未授权，提醒不会显示');
  }

  /// 立即显示一条系统通知；未授权时抛 [NotificationPermissionDeniedException]。
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
    void Function()? onTap,
  }) async {
    _requirePermission('show');
    final callback =
        onTap ?? (payload == null ? null : () => this.onTap?.call(payload));
    await _api.show(
      title: title,
      body: body,
      tag: _tagFor(id),
      onClick: callback,
    );
  }

  Future<void> _deliverScheduled(
    WebNotificationScheduledNotification notification,
  ) async {
    await show(
      id: notification.id,
      title: notification.title,
      body: notification.body,
      payload: notification.payload,
    );
  }

  /// 网页内一次性提醒。
  ///
  /// [requestIfNeeded] 只保留签名兼容：Web 侧不会在非手势链路弹权限框，
  /// 未授权时抛明确异常，由 `ReminderScheduler` 记录到提醒健康状态。
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    bool requestIfNeeded = false,
  }) async {
    _requirePermission('scheduleOnce');
    _scheduler.scheduleOnce(
      id: id,
      title: title,
      body: body,
      when: when,
      payload: payload,
    );
  }

  /// 网页内每日（可限定星期）提醒。
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
    bool requestIfNeeded = false,
  }) async {
    _requirePermission('scheduleDaily');
    _scheduler.scheduleDaily(
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
    _scheduler.cancel(id);
    await _api.close(_tagFor(id));
  }

  /// 取消全部提醒：与 [invalidateAccount] 是同一条清理语义，避免两套路径分叉。
  Future<void> cancelAll() => invalidateAccount();

  /// 账号清理 / 全部取消：
  /// 1. 同步作废在途权限结果与旧调度代际（停止全部网页内计时、清 lastRequest）；
  /// 2. 再关闭浏览器侧已经显示的通知。
  Future<void> invalidateAccount() async {
    _requestGeneration++;
    _lastRequest = null;
    _scheduler.invalidate();
    await _api.closeAll();
  }
}

/// 用应用时区构造墙上时间（保持 AppClock / IANA 语义）。
DateTime _appClockDate(int year, int month, int day, int hour, int minute) =>
    AppClock.date(year, month, day, hour, minute);
