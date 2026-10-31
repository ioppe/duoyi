/// 非 Web 平台占位：没有浏览器能力，[DeferredWebFontService] 因此永不加载。
///
/// 原生端的字体由 pubspec 的 NotoSansSC 变量字体直接提供，不存在延迟加载场景。
class DeferredWebFontPlatform {
  const DeferredWebFontPlatform();

  /// 原生端无网络策略：视为联网。
  bool get isOnline => true;

  /// 原生端无标签页概念：视为可见。
  bool get isVisible => true;

  /// 原生端无语义化省流开关。
  bool get saveData => false;

  /// 原生端无 NetworkInformation 连接类型。
  String? get effectiveConnectionType => null;

  /// 原生端没有 requestIdleCallback，退化为一次性延时（服务在原生端不会走到这里）。
  Future<void> whenIdle(Duration timeout) => Future<void>.delayed(timeout);

  /// 原生端没有 Performance API，标记直接丢弃。
  void mark(String name) {}
}
