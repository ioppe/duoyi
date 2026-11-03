import 'dart:async';

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Web 端实现：只用 `dart:js_interop` 读浏览器全局对象，不引入额外依赖。
///
/// 所有能力都按「读不到就当不受限」的保守策略处理：
/// 缺失的 API 只会让判断回落到默认值，不会抛出异常。
class DeferredWebFontPlatform {
  const DeferredWebFontPlatform();

  static const String _requestIdleCallback = 'requestIdleCallback';

  /// requestIdleCallback 缺失时的退化延时：足够让首帧后的一次任务间隙出现。
  static const Duration _idleFallbackDelay = Duration(milliseconds: 250);

  /// `navigator.onLine`；读取不到时按联网处理，避免误跳过。
  bool get isOnline => _readBool(_navigator, 'onLine', fallback: true);

  /// `document.visibilityState == 'visible'`：后台标签页不下载完整字体。
  bool get isVisible {
    final state = _readString(
      _object(globalContext, 'document'),
      'visibilityState',
    );
    return state == null || state == 'visible';
  }

  /// `navigator.connection.saveData`：省流模式不下载。
  bool get saveData => _readBool(_connection, 'saveData', fallback: false);

  /// `navigator.connection.effectiveType`：`slow-2g` / `2g` 由服务层判定跳过。
  String? get effectiveConnectionType =>
      _readString(_connection, 'effectiveType');

  /// 浏览器空闲回调；不支持或长时间不回调时退化为一次性短延时。
  Future<void> whenIdle(Duration timeout) {
    final completer = Completer<void>();

    void complete() {
      if (!completer.isCompleted) completer.complete();
    }

    final idleCallback = globalContext[_requestIdleCallback];
    if (idleCallback == null || !idleCallback.isA<JSFunction>()) {
      Timer(_idleFallbackDelay, complete);
      return completer.future;
    }

    // 标签页持续忙碌时 requestIdleCallback 可能迟迟不触发，
    // 用定时器兜底保证最多只等待一次 timeout。
    final guard = Timer(timeout, complete);
    void onIdle() {
      guard.cancel();
      complete();
    }

    try {
      globalContext.callMethod<JSAny?>(_requestIdleCallback.toJS, onIdle.toJS);
    } catch (_) {
      guard.cancel();
      Timer(_idleFallbackDelay, complete);
    }
    return completer.future;
  }

  /// `performance.mark(name)`：供浏览器 Performance 面板验收；失败静默。
  void mark(String name) {
    final performance = _object(globalContext, 'performance');
    if (performance == null) return;
    try {
      performance.callMethod<JSAny?>('mark'.toJS, name.toJS);
    } catch (_) {
      // 标记失败不影响字体加载。
      return;
    }
  }

  JSObject? get _navigator => _object(globalContext, 'navigator');

  JSObject? get _connection => _object(_navigator, 'connection');

  static JSObject? _object(JSObject? root, String name) {
    if (root == null) return null;
    final value = root[name];
    if (value == null || !value.isA<JSObject>()) return null;
    return value as JSObject;
  }

  static bool _readBool(JSObject? root, String name, {required bool fallback}) {
    if (root == null) return fallback;
    final value = root[name];
    if (value == null || !value.isA<JSBoolean>()) return fallback;
    return (value as JSBoolean).toDart;
  }

  static String? _readString(JSObject? root, String name) {
    if (root == null) return null;
    final value = root[name];
    if (value == null || !value.isA<JSString>()) return null;
    return (value as JSString).toDart;
  }
}
