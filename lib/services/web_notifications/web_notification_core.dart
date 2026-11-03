/// Web（浏览器）通知的纯 Dart 核心：能力/权限状态模型 + 网页内定时调度。
///
/// 设计约束（见 `docs/` 中提醒相关约定）：
/// - 本文件不直接触碰任何浏览器 API，只依赖 [WebNotificationBrowserApi]，
///   因此可以在 VM 上用假实现完整测试权限边界与调度语义；
/// - 真实浏览器调用只在 `web_notification_browser_api_web.dart` 里发生；
/// - 权限框只允许由用户手势显式触发：`requestPermission` 是同步发起原生
///   请求的函数，不能在它之前 await 初始化/探测，否则浏览器会丢失
///   user activation 并静默拒绝弹框。
library;

import 'dart:async';

/// 浏览器通知能力状态。
enum WebNotificationSupport {
  /// `Notification` 可用且处于安全上下文，可以申请与显示通知。
  supported,

  /// 页面不是安全上下文（非 HTTPS / 非 localhost），浏览器不会显示通知。
  insecureContext,

  /// 当前浏览器不提供 Notification API。
  unsupported,
}

/// 浏览器通知权限（对应 `Notification.permission`）。
enum WebNotificationPermission {
  /// `granted`。
  granted,

  /// `denied`：浏览器不再弹权限框，只能由用户在站点设置里改。
  denied,

  /// `default`：尚未决定，可在用户手势中弹框。
  prompt,
}

/// 一次显式授权请求的结果。
enum WebNotificationRequestOutcome {
  granted,

  /// 浏览器拒绝授权（含此前已拒绝、无法再次弹框）。
  denied,

  /// 权限框被关闭/未选择，仍是 `default`，用户可再次点击。
  dismissed,

  /// 浏览器不支持通知。
  unsupported,

  /// 非安全上下文。
  insecureContext,

  /// 请求过程抛出异常或返回值不可识别。
  failed,
}

/// 授权请求结果：供 `ReminderHealthHint` 等 UI 展示准确反馈。
class WebNotificationRequestResult {
  const WebNotificationRequestResult({
    required this.outcome,
    required this.permission,
    this.previouslyDenied = false,
    this.error,
  });

  final WebNotificationRequestOutcome outcome;
  final WebNotificationPermission permission;

  /// 请求前权限即为 `denied`：浏览器不会再弹框。
  final bool previouslyDenied;
  final Object? error;

  bool get isGranted => outcome == WebNotificationRequestOutcome.granted;

  /// 浏览器是否还可能再次弹框（未选择 / 请求异常时可重试）。
  bool get canPromptAgain =>
      !isGranted &&
      !previouslyDenied &&
      (outcome == WebNotificationRequestOutcome.dismissed ||
          outcome == WebNotificationRequestOutcome.failed);

  @override
  String toString() =>
      'WebNotificationRequestResult(outcome: ${outcome.name}, '
      'permission: ${permission.name}, previouslyDenied: $previouslyDenied)';
}

/// 浏览器 API 桥。平台实现只做真实调用，不做状态判断。
abstract class WebNotificationBrowserApi {
  /// `Notification` 是否存在 + `isSecureContext`。
  WebNotificationSupport supportStatus();

  /// `Notification.permission`。
  WebNotificationPermission permission();

  /// 浏览器原生 `Notification.requestPermission()`。
  ///
  /// 调用方必须在用户手势的同步链路里调用本方法（不要先 await 别的东西）。
  Future<WebNotificationPermission> requestPermission();

  /// 显示一条系统通知；失败时抛异常，由上层转换成明确错误。
  Future<void> show({
    required String title,
    required String body,
    required String tag,
    void Function()? onClick,
  });

  /// 关闭同 tag 的通知（若浏览器保留）。
  Future<void> close(String tag);

  /// 关闭本页创建的全部通知。
  Future<void> closeAll();
}

/// 权限门：把浏览器状态映射成可展示结果，并合流重复请求。
///
/// 所有读取都直接问 [api]（浏览器侧是同步属性），因此外部在站点设置里
/// 修改权限后，一次 `refresh` 就能立刻读到新状态。
class WebNotificationPermissionGate {
  WebNotificationPermissionGate({required WebNotificationBrowserApi api})
    : _api = api;

  final WebNotificationBrowserApi _api;
  Future<WebNotificationRequestResult>? _inFlight;

  bool get hasPendingRequest => _inFlight != null;

  WebNotificationSupport get support => _api.supportStatus();

  WebNotificationPermission get permission => _api.permission();

  bool get isGranted =>
      support == WebNotificationSupport.supported &&
      permission == WebNotificationPermission.granted;

  /// 不弹框，只读取当前状态（启动/刷新/恢复前台时用）。
  WebNotificationPermission refresh() => _api.permission();

  /// 在用户手势中申请权限。
  ///
  /// 注意：本方法不是 `async`。它会**同步**调用
  /// [WebNotificationBrowserApi.requestPermission]，然后才把 Future 交给调用方，
  /// 从而保住浏览器的 user activation 判定。
  Future<WebNotificationRequestResult> requestPermission() {
    final support = _api.supportStatus();
    if (support != WebNotificationSupport.supported) {
      return Future<WebNotificationRequestResult>.value(
        WebNotificationRequestResult(
          outcome: support == WebNotificationSupport.insecureContext
              ? WebNotificationRequestOutcome.insecureContext
              : WebNotificationRequestOutcome.unsupported,
          permission: _safePermission(),
        ),
      );
    }
    final current = _api.permission();
    if (current == WebNotificationPermission.granted) {
      return Future<WebNotificationRequestResult>.value(
        const WebNotificationRequestResult(
          outcome: WebNotificationRequestOutcome.granted,
          permission: WebNotificationPermission.granted,
        ),
      );
    }
    if (current == WebNotificationPermission.denied) {
      // 已拒绝时浏览器不会再弹框，重复请求只会无效，直接给可解释结果。
      return Future<WebNotificationRequestResult>.value(
        const WebNotificationRequestResult(
          outcome: WebNotificationRequestOutcome.denied,
          permission: WebNotificationPermission.denied,
          previouslyDenied: true,
        ),
      );
    }
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final request = _runNativeRequest();
    // 单飞：清理 _inFlight 必须"有处理"地完成。原实现丢弃了 whenComplete
    // 的派生 Future，底层报错时会变成 unhandled async error。
    late final Future<WebNotificationRequestResult> guarded;
    guarded = request.then<WebNotificationRequestResult>(
      (result) {
        if (identical(_inFlight, guarded)) _inFlight = null;
        return result;
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_inFlight, guarded)) _inFlight = null;
        return WebNotificationRequestResult(
          outcome: WebNotificationRequestOutcome.failed,
          permission: _safePermission(),
          error: error,
        );
      },
    );
    _inFlight = guarded;
    return guarded;
  }

  /// 读取权限属性；个别实现可能在异常态抛错，这里降级为 prompt。
  WebNotificationPermission _safePermission() {
    try {
      return _api.permission();
    } catch (_) {
      return WebNotificationPermission.prompt;
    }
  }

  Future<WebNotificationRequestResult> _runNativeRequest() async {
    // 关键顺序：真实 API 必须在任何 await 之前被**同步**调用，以保住
    // 浏览器的 user activation 判定。
    final Future<WebNotificationPermission> nativeRequest;
    try {
      nativeRequest = _api.requestPermission();
    } catch (error) {
      // 同步抛错（例如浏览器判定本次不在用户手势中）也是"请求失败"，
      // 必须转换成 failed 结果而不是 Future.error。
      return WebNotificationRequestResult(
        outcome: WebNotificationRequestOutcome.failed,
        permission: _safePermission(),
        error: error,
      );
    }
    WebNotificationPermission resolved;
    try {
      resolved = await nativeRequest;
    } catch (error) {
      return WebNotificationRequestResult(
        outcome: WebNotificationRequestOutcome.failed,
        permission: _safePermission(),
        error: error,
      );
    }
    final outcome = switch (resolved) {
      WebNotificationPermission.granted =>
        WebNotificationRequestOutcome.granted,
      WebNotificationPermission.denied => WebNotificationRequestOutcome.denied,
      WebNotificationPermission.prompt =>
        WebNotificationRequestOutcome.dismissed,
    };
    return WebNotificationRequestResult(outcome: outcome, permission: resolved);
  }
}

/// 一条将在网页内定时显示的通知。
class WebNotificationScheduledNotification {
  const WebNotificationScheduledNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
    this.payload,
  });

  final int id;
  final String title;
  final String body;
  final DateTime when;
  final String? payload;
}

/// 定时器句柄：调用即取消。
typedef WebNotificationTimerHandle = void Function();

typedef WebNotificationTimerFactory =
    WebNotificationTimerHandle Function(Duration delay, void Function() fire);

typedef WebNotificationNow = DateTime Function();

/// 用应用时区构造墙上时间；默认按本地 `DateTime` 语义。
typedef WebNotificationDateBuilder =
    DateTime Function(int year, int month, int day, int hour, int minute);

DateTime _defaultDateBuilder(
  int year,
  int month,
  int day,
  int hour,
  int minute,
) => DateTime(year, month, day, hour, minute);

typedef WebNotificationDisplay =
    Future<void> Function(WebNotificationScheduledNotification notification);

WebNotificationTimerHandle _defaultTimerFactory(
  Duration delay,
  void Function() fire,
) {
  final timer = Timer(delay, fire);
  return timer.cancel;
}

class _WebNotificationScheduleEntry {
  _WebNotificationScheduleEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
    required this.generation,
    required this.when,
    this.dailyHour,
    this.dailyMinute,
    this.weekdays,
    this.nextFireAt,
  });

  final int id;
  final String title;
  final String body;
  final String? payload;
  final int generation;
  final DateTime when;
  final int? dailyHour;
  final int? dailyMinute;
  final List<int>? weekdays;
  DateTime? nextFireAt;
  WebNotificationTimerHandle? timer;

  bool get isDaily => dailyHour != null && dailyMinute != null;

  void cancelTimer() {
    timer?.call();
    timer = null;
  }
}

/// 网页内调度器：只在当前页面存活期间有效。
///
/// Web 没有可靠的后台唤醒能力，因此这里明确按「网页内 timer」实现：
/// - 同一 id 再次调度会替换旧条目（只保留最后一次）；
/// - [cancel]/[cancelAll] 立即停止计时，[pendingIds] 反映真实待触发集合；
/// - [invalidate] 递增代际，账号清理后旧代际的回调不会再显示任何内容，
///   也不会把私有 payload 留在内存里。
class WebNotificationScheduler {
  WebNotificationScheduler({
    required WebNotificationDisplay display,
    WebNotificationNow? now,
    WebNotificationTimerFactory? timerFactory,
    WebNotificationDateBuilder? dateBuilder,
  }) : _display = display,
       _now = now ?? DateTime.now,
       _timerFactory = timerFactory ?? _defaultTimerFactory,
       _dateBuilder = dateBuilder ?? _defaultDateBuilder;

  final WebNotificationDisplay _display;
  final WebNotificationNow _now;
  final WebNotificationTimerFactory _timerFactory;
  final WebNotificationDateBuilder _dateBuilder;
  final Map<int, _WebNotificationScheduleEntry> _entries =
      <int, _WebNotificationScheduleEntry>{};

  int _generation = 0;
  Object? _lastDeliveryError;

  int get generation => _generation;
  Object? get lastDeliveryError => _lastDeliveryError;

  /// 注册一次性提醒。时间已过去时抛 [StateError]（与原生实现一致）。
  void scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) {
    final now = _now();
    if (!when.isAfter(now)) {
      throw StateError('提醒时间已过去，未注册到系统通知');
    }
    _replace(
      _WebNotificationScheduleEntry(
        id: id,
        title: title,
        body: body,
        payload: payload,
        generation: _generation,
        when: when,
        nextFireAt: when,
      ),
    );
  }

  /// 注册每日（可限定星期）提醒。
  void scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) {
    final normalizedWeekdays = (weekdays == null || weekdays.isEmpty)
        ? null
        : List<int>.unmodifiable(weekdays);
    final now = _now();
    final next = nextDailyFireAt(
      now: now,
      hour: hour,
      minute: minute,
      weekdays: normalizedWeekdays,
    );
    _replace(
      _WebNotificationScheduleEntry(
        id: id,
        title: title,
        body: body,
        payload: payload,
        generation: _generation,
        when: next,
        dailyHour: hour,
        dailyMinute: minute,
        weekdays: normalizedWeekdays,
        nextFireAt: next,
      ),
    );
  }

  /// 下一次每日提醒的墙上时间（按 [WebNotificationDateBuilder] 的时区）。
  DateTime nextDailyFireAt({
    required DateTime now,
    required int hour,
    required int minute,
    List<int>? weekdays,
  }) {
    DateTime build(int dayOffset) =>
        _dateBuilder(now.year, now.month, now.day + dayOffset, hour, minute);
    if (weekdays == null || weekdays.isEmpty) {
      final today = build(0);
      if (today.isAfter(now)) return today;
      return build(1);
    }
    for (var offset = 0; offset <= 7; offset++) {
      final candidate = build(offset);
      if (weekdays.contains(candidate.weekday) && candidate.isAfter(now)) {
        return candidate;
      }
    }
    return build(1);
  }

  bool cancel(int id) {
    final entry = _entries.remove(id);
    if (entry == null) return false;
    entry.cancelTimer();
    return true;
  }

  /// 取消全部提醒：停止计时并推进代际，任何在途回调都不会再显示。
  void cancelAll() {
    for (final entry in _entries.values) {
      entry.cancelTimer();
    }
    _entries.clear();
    _generation++;
  }

  /// 账号清理：停止全部计时并作废旧代际（见 [cancelAll]）。
  void invalidate() {
    cancelAll();
    _lastDeliveryError = null;
  }

  List<int> pendingIds() => _entries.keys.toList(growable: false);

  DateTime? nextFireAt(int id) => _entries[id]?.nextFireAt;

  void _replace(_WebNotificationScheduleEntry entry) {
    _entries.remove(entry.id)?.cancelTimer();
    _entries[entry.id] = entry;
    _arm(entry);
  }

  /// 单次唤醒上限：JS 计时器最大约 2^31-1ms，长未来必须分段等待。
  static const Duration maxSingleTimerDelay = Duration(days: 1);

  void _arm(_WebNotificationScheduleEntry entry) {
    final target = entry.nextFireAt;
    if (target == null) return;
    entry.cancelTimer();
    entry.timer = _timerFactory(
      _waitFor(target),
      () => unawaited(_wake(entry)),
    );
  }

  /// 到 [target] 的等待时长，按 [maxSingleTimerDelay] 分段封顶。
  Duration _waitFor(DateTime target) {
    final delay = target.difference(_now());
    if (delay.isNegative) return Duration.zero;
    if (delay > maxSingleTimerDelay) return maxSingleTimerDelay;
    return delay;
  }

  /// 分段唤醒：只有真正到达绝对目标才显示，未到则继续分段等待。
  Future<void> _wake(_WebNotificationScheduleEntry entry) async {
    if (entry.generation != _generation) return;
    if (!identical(_entries[entry.id], entry)) return;
    entry.timer = null;
    final target = entry.nextFireAt;
    if (target == null) return;
    if (_now().isBefore(target)) {
      // 只是分段计时到了：不能提前显示，也不能忙循环（delay 仍为正）。
      _arm(entry);
      return;
    }
    await _fire(entry);
  }

  Future<void> _fire(_WebNotificationScheduleEntry entry) async {
    if (entry.generation != _generation) return;
    if (!identical(_entries[entry.id], entry)) return;
    entry.timer = null;
    try {
      await _display(
        WebNotificationScheduledNotification(
          id: entry.id,
          title: entry.title,
          body: entry.body,
          when: entry.nextFireAt ?? entry.when,
          payload: entry.payload,
        ),
      );
      _lastDeliveryError = null;
    } catch (error) {
      _lastDeliveryError = error;
    }
    if (entry.generation != _generation) return;
    if (!identical(_entries[entry.id], entry)) return;
    if (!entry.isDaily) {
      _entries.remove(entry.id);
      return;
    }
    final now = _now();
    entry.nextFireAt = nextDailyFireAt(
      now: now,
      hour: entry.dailyHour!,
      minute: entry.dailyMinute!,
      weekdays: entry.weekdays,
    );
    _arm(entry);
  }
}
