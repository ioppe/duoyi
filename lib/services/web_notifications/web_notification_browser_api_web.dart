import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'web_notification_core.dart';

/// Web 端浏览器 API 桥：只用 `dart:js_interop` 调真实浏览器 API，无额外依赖。
WebNotificationBrowserApi createWebNotificationBrowserApi() =>
    WebNotificationBrowserApiWeb();

/// 直接调用浏览器 Notifications API 的实现。
///
/// 投递顺序是固定的：
/// 1. `new Notification(...)`：能构造就优先用它，`onclick` 接回应用内 deep link；
///    Chrome Android 会在这里抛 "Illegal constructor"，此时退化到第 2 步。
/// 2. 已注册的 service worker registration：用
///    `navigator.serviceWorker.getRegistration()` 有界等待（2 秒），只接受
///    `.active` 且具备 `showNotification` 的 registration；**绝不**
///    `await navigator.serviceWorker.ready`，也绝不注册新的 service worker。
///    这条路径的点击由浏览器 service worker 处理，本页无法挂钩子。
/// 3. 两条都不可用或投递失败时抛明确异常，绝不假装成功。
///
/// 异步退化的取消语义：
/// - `close(tag)` / `closeAll()` 会**同步**推进每 tag 版本号 / 全局 epoch，
///   因此已排队但尚未发出的 show 在 await 之后会复核代际并放弃投递；
/// - 已经发出的 show 在完成时若发现已失效，会按 tag 再关一次，避免迟到显示；
/// - 所有 JS Promise 都在这里挂好成功/失败处理器，并有超时兜底，
///   不会留下未处理的派生 Future。
/// - 关闭只针对本应用自己的通知：构造器创建的对象，或
///   `registration.getNotifications({tag})`（天然限定在这份 service worker 注册内）。
///   这里只记录 tag → 浏览器对象，不保存标题/正文等私有内容。
class WebNotificationBrowserApiWeb implements WebNotificationBrowserApi {
  WebNotificationBrowserApiWeb();

  /// registration 有界等待上限，同时也是通知投递/关闭的兜底超时。
  static const Duration _registrationTimeout = Duration(seconds: 2);

  /// `tag` → 构造器创建的通知对象。
  final Map<String, JSObject> _activeNotifications = <String, JSObject>{};

  /// `tag` → 实际投递过该 tag 的 registration。
  final Map<String, JSObject> _activeRegistrations = <String, JSObject>{};

  /// `close(tag)` 递增对应 tag 版本；`closeAll()` 递增 [_epoch] 作废全部在途 show。
  final Map<String, int> _tagVersions = <String, int>{};
  int _epoch = 0;

  int _versionOf(String tag) => _tagVersions[tag] ?? 0;

  void _invalidateTag(String tag) {
    _tagVersions[tag] = _versionOf(tag) + 1;
  }

  bool _isCurrent(String tag, int epoch, int version) =>
      epoch == _epoch && version == _versionOf(tag);

  static JSFunction? get _notificationConstructor {
    final value = globalContext['Notification'];
    if (value == null || !value.isA<JSFunction>()) return null;
    return value as JSFunction;
  }

  static bool get _isSecureContext =>
      _readBool(globalContext, 'isSecureContext', fallback: true);

  static JSObject? _readObject(JSObject? root, String name) {
    if (root == null) return null;
    if (!root.has(name)) return null;
    final value = root[name];
    if (value == null || !value.isA<JSObject>()) return null;
    return value as JSObject;
  }

  static bool _readBool(JSObject? root, String name, {required bool fallback}) {
    if (root == null || !root.has(name)) return fallback;
    final value = root[name];
    if (value == null || !value.isA<JSBoolean>()) return fallback;
    return (value as JSBoolean).toDart;
  }

  static String? _readString(JSObject? root, String name) {
    if (root == null || !root.has(name)) return null;
    final value = root[name];
    if (value == null || !value.isA<JSString>()) return null;
    return (value as JSString).toDart;
  }

  static WebNotificationPermission _permissionFromString(String? raw) {
    return switch (raw) {
      'granted' => WebNotificationPermission.granted,
      'denied' => WebNotificationPermission.denied,
      _ => WebNotificationPermission.prompt,
    };
  }

  @override
  WebNotificationSupport supportStatus() {
    if (!_isSecureContext) return WebNotificationSupport.insecureContext;
    if (_notificationConstructor == null) {
      return WebNotificationSupport.unsupported;
    }
    return WebNotificationSupport.supported;
  }

  @override
  WebNotificationPermission permission() {
    final constructor = _notificationConstructor;
    if (constructor == null) return WebNotificationPermission.prompt;
    return _permissionFromString(_readString(constructor, 'permission'));
  }

  @override
  Future<WebNotificationPermission> requestPermission() {
    final constructor = _notificationConstructor;
    if (constructor == null) {
      // 没有 Notification 构造器时无法申请权限，只能回读当前状态。
      return Future<WebNotificationPermission>.value(permission());
    }
    final result = constructor.callMethod<JSAny?>('requestPermission'.toJS);
    if (result == null || !result.isA<JSPromise<JSAny?>>()) {
      // 老实现（回调式）没有 Promise：直接读权限属性。
      return Future<WebNotificationPermission>.value(permission());
    }
    final promise = result as JSPromise<JSAny?>;
    return promise.toDart.then((value) {
      if (value != null && value.isA<JSString>()) {
        return _permissionFromString((value as JSString).toDart);
      }
      return permission();
    });
  }

  @override
  Future<void> show({
    required String title,
    required String body,
    required String tag,
    void Function()? onClick,
  }) async {
    final epoch = _epoch;
    final version = _versionOf(tag);
    final options = <String, Object?>{'body': body, 'tag': tag}.jsify();

    if (_showWithConstructor(
      title: title,
      options: options,
      tag: tag,
      epoch: epoch,
      version: version,
      onClick: onClick,
    )) {
      return;
    }

    final registration = await _activeRegistrationWithin(_registrationTimeout);
    if (!_isCurrent(tag, epoch, version)) {
      // 等待期间被取消或切换账号：旧内容不能发出去。
      if (registration != null) await _closeRegistrationTag(registration, tag);
      return;
    }
    if (registration == null) {
      throw StateError(
        '浏览器通知不可用：Notification 构造器不可用，且没有已激活的 Service Worker 注册',
      );
    }
    final delivered = await _callShowNotification(
      registration,
      title,
      options,
      onDelivered: () async {
        // timeout 不能撤回浏览器原 Promise；它晚到时仍须收尾旧代际通知。
        if (!_isCurrent(tag, epoch, version)) {
          await _closeRegistrationTag(registration, tag);
        } else {
          _activeRegistrations[tag] = registration;
        }
      },
    );
    if (!delivered) {
      throw StateError('Service Worker 通知投递失败');
    }
    _activeRegistrations[tag] = registration;
    if (!_isCurrent(tag, epoch, version)) {
      // show 已经发出之后才被取消：完成时再关一次，避免迟到显示。
      _activeRegistrations.remove(tag);
      await _closeRegistrationTag(registration, tag);
    }
  }

  /// 优先用 `new Notification(...)`；不可构造（如 Chrome Android）返回 false。
  bool _showWithConstructor({
    required String title,
    required JSAny? options,
    required String tag,
    required int epoch,
    required int version,
    void Function()? onClick,
  }) {
    final constructor = _notificationConstructor;
    if (constructor == null) return false;
    final JSObject notification;
    try {
      notification = constructor.callAsConstructor<JSObject>(
        title.toJS,
        options,
      );
    } catch (_) {
      return false;
    }
    if (onClick != null) {
      notification['onclick'] = (() {
        // 已取消或旧代际的 payload 不得再触发新身份下的动作。
        if (!_isCurrent(tag, epoch, version)) return;
        onClick();
      }).toJS;
    }
    _activeNotifications[tag] = notification;
    return true;
  }

  /// 有界获取**已激活**的 registration；超时或失败返回 null。
  Future<JSObject?> _activeRegistrationWithin(Duration timeout) async {
    final serviceWorker = _readObject(
      _readObject(globalContext, 'navigator'),
      'serviceWorker',
    );
    if (serviceWorker == null) return null;
    final JSAny? pending;
    try {
      pending = serviceWorker.callMethod<JSAny?>('getRegistration'.toJS);
    } catch (_) {
      return null;
    }
    if (pending == null || !pending.isA<JSPromise<JSAny?>>()) return null;
    final Future<JSObject?> resolved = (pending as JSPromise<JSAny?>).toDart
        .then<JSObject?>((value) {
          if (value == null || !value.isA<JSObject>()) return null;
          final registration = value as JSObject;
          return _canShowNotifications(registration) ? registration : null;
        })
        .catchError((Object _) => null);
    // 有界等待：超时后原 Promise 仍挂着受控处理器，不会产生未处理的错误。
    return resolved.timeout(timeout, onTimeout: () => null);
  }

  static bool _canShowNotifications(JSObject registration) {
    // 未激活的 registration 会让 showNotification 一直 pending，直接放弃。
    if (_readObject(registration, 'active') == null) return false;
    if (!registration.has('showNotification')) return false;
    final method = registration['showNotification'];
    return method != null && method.isA<JSFunction>();
  }

  /// 真实调用 `registration.showNotification`，返回是否确认投递成功。
  static Future<bool> _callShowNotification(
    JSObject registration,
    String title,
    JSAny? options, {
    Future<void> Function()? onDelivered,
  }) async {
    final JSAny? result;
    try {
      result = registration.callMethod<JSAny?>(
        'showNotification'.toJS,
        title.toJS,
        options,
      );
    } catch (_) {
      return false;
    }
    if (result == null || !result.isA<JSPromise<JSAny?>>()) return true;
    final delivery = (result as JSPromise<JSAny?>).toDart
        .then<bool>((_) async {
          await onDelivered?.call();
          return true;
        })
        .catchError((Object _) => false);
    return delivery.timeout(_registrationTimeout, onTimeout: () => false);
  }

  static Future<void> _closeRegistrationTag(
    JSObject registration,
    String tag,
  ) async {
    final JSAny? pending;
    try {
      pending = registration.callMethod<JSAny?>(
        'getNotifications'.toJS,
        <String, Object?>{'tag': tag}.jsify(),
      );
    } catch (_) {
      return;
    }
    if (pending == null || !pending.isA<JSPromise<JSAny?>>()) return;
    final List<JSObject> delivered;
    try {
      final value = await (pending as JSPromise<JSAny?>).toDart.timeout(
        _registrationTimeout,
        onTimeout: () => null,
      );
      if (value == null || !value.isA<JSArray<JSAny?>>()) return;
      delivered = (value as JSArray<JSAny?>).toDart
          .whereType<JSObject>()
          .toList(growable: false);
    } catch (_) {
      return;
    }
    for (final notification in delivered) {
      try {
        notification.callMethod<JSAny?>('close'.toJS);
      } catch (_) {
        // 单条关闭失败不影响其余通知。
      }
    }
  }

  @override
  Future<void> close(String tag) async {
    _invalidateTag(tag);
    final notification = _activeNotifications.remove(tag);
    if (notification != null) {
      try {
        notification.callMethod<JSAny?>('close'.toJS);
      } catch (_) {
        // 浏览器已经收起该通知；关闭失败不影响后续流程。
      }
    }
    final registration = _activeRegistrations.remove(tag);
    if (registration != null) await _closeRegistrationTag(registration, tag);
  }

  @override
  Future<void> closeAll() async {
    // 同步推进 epoch：所有在途 show 在 await 之后都会发现自己已失效。
    _epoch++;
    final notifications = _activeNotifications.values.toList(growable: false);
    _activeNotifications.clear();
    for (final notification in notifications) {
      try {
        notification.callMethod<JSAny?>('close'.toJS);
      } catch (_) {
        // 单条关闭失败不影响其余通知。
      }
    }
    final registrations = Map<String, JSObject>.of(_activeRegistrations);
    _activeRegistrations.clear();
    for (final entry in registrations.entries) {
      await _closeRegistrationTag(entry.value, entry.key);
    }
  }
}
