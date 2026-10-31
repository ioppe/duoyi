import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';

import '../core/design_tokens.dart';
import 'deferred_web_font_platform.dart';

/// 读取字体字节（默认 [rootBundle.load] 完整字体资产）。
typedef DeferredFontBytesLoader = Future<ByteData> Function(String assetKey);

/// 把字体字节注册到引擎（默认 [FontLoader] + fontsChange 刷新）。
typedef DeferredFontRegistrar = Future<void> Function(ByteData bytes);

/// 延迟等待（默认 [Future.delayed]）。
typedef DeferredFontWait = Future<void> Function(Duration duration);

/// 空闲调度（默认浏览器 requestIdleCallback，退化短定时器）。
typedef DeferredFontIdleWait = Future<void> Function(Duration timeout);

/// 浏览器 Performance 标记（失败必须静默）。
typedef DeferredFontMarker = void Function(String name);

/// Web 完整字体延迟加载：首屏只用同源轻量变量子集，首帧空闲后再拉完整字体。
///
/// 设计约束：
/// - 原生平台（[isWeb] 为 false）零副作用：不调度、不读资产、不打标记。
/// - 一个会话最多加载一次；失败只记录标记，不外抛、不重试、不弹 UI。
/// - 仅在联网、页面可见、非省流、非 slow-2g/2g 时加载；
///   15 秒延时结束与空闲回调返回后各复查一次，受限环境直接放弃本会话。
/// - 加载成功后必须触发 `flutter/system` 的 `fontsChange`：
///   CanvasKit 的 `loadFontFromList` 不会自动重排已上屏的缺字文本。
class DeferredWebFontService {
  DeferredWebFontService({
    bool? isWeb,
    DeferredWebFontPlatform? platform,
    DeferredFontBytesLoader? loadFontBytes,
    DeferredFontRegistrar? registerFont,
    DeferredFontWait? wait,
    DeferredFontIdleWait? waitForIdle,
    DeferredFontMarker? mark,
    void Function()? notifyFontsChanged,
    this.delay = defaultDelay,
    this.idleTimeout = defaultIdleTimeout,
  }) : _isWeb = isWeb ?? kIsWeb,
       _platform = platform ?? const DeferredWebFontPlatform(),
       _loadFontBytes = loadFontBytes ?? _loadFromRootBundle,
       _registerFont = registerFont ?? _registerWithFontLoader,
       _wait = wait ?? _delay,
       _idleWait = waitForIdle,
       _marker = mark ?? (platform ?? const DeferredWebFontPlatform()).mark,
       _notifyFontsChanged = notifyFontsChanged ?? _notifySystemFontsChanged;

  /// 应用级共享实例：Web 启动入口调用 [schedule]，保证整会话最多加载一次。
  static final DeferredWebFontService instance = DeferredWebFontService();

  /// 完整（全字符集）Noto Sans SC 变量字体资产路径，仍随 bundle 发布供延迟请求。
  static const String fontAssetKey = 'assets/fonts/NotoSansSC-Variable.ttf';

  /// 复用同一字体家族，避免延迟加载后出现两套字体。
  static const String fontFamily = DesignTokens.fontFamily;

  /// 首帧后静置时长：等启动任务（Provider 预热、远端刷新）先跑完。
  static const Duration defaultDelay = Duration(seconds: 15);

  /// 空闲回调兜底上限。
  static const Duration defaultIdleTimeout = Duration(seconds: 1);

  /// 后台字节加载不能无限悬挂；超时仍使用首屏字库，不自动重试。
  static const Duration downloadTimeout = Duration(seconds: 60);

  /// 浏览器 Performance 验收标记。
  static const String firstFrameMark = 'duoyi-font-first-frame';
  static const String downloadStartMark = 'duoyi-font-download-start';
  static const String loadedMark = 'duoyi-font-loaded';
  static const String errorMark = 'duoyi-font-error';
  static const String skippedMark = 'duoyi-font-skipped';

  /// 这些连接类型视为受限网络，跳过完整字体下载。
  static const Set<String> _slowConnectionTypes = {'slow-2g', '2g'};

  final bool _isWeb;
  final DeferredWebFontPlatform _platform;
  final DeferredFontBytesLoader _loadFontBytes;
  final DeferredFontRegistrar _registerFont;
  final DeferredFontWait _wait;
  final DeferredFontIdleWait? _idleWait;
  final DeferredFontMarker _marker;
  final void Function() _notifyFontsChanged;

  /// 首帧后的静置时长。
  final Duration delay;

  /// 空闲回调兜底上限。
  final Duration idleTimeout;

  Future<void>? _pending;
  bool _didLoad = false;
  Object? _lastError;

  bool get isWeb => _isWeb;

  /// 是否已成功注册完整字体。
  bool get didLoad => _didLoad;

  /// 本次调度对应的异步流程；原生平台恒为 null。
  @visibleForTesting
  Future<void>? get pending => _pending;

  /// 最近一次被吞掉的错误（加载或验收标记失败），仅用于诊断与测试。
  @visibleForTesting
  Object? get lastError => _lastError;

  /// 首帧回调里调用：立即返回，不等待下载，不阻塞启动流程。
  ///
  /// 重复或并发调用最多触发一次加载。
  void schedule() {
    if (!_isWeb) return;
    if (_pending != null) return;
    _mark(firstFrameMark);
    _pending = _run();
  }

  Future<void> _run() async {
    try {
      await _wait(delay);
      if (!_eligible) {
        _mark(skippedMark);
        return;
      }

      await (_idleWait ?? _platform.whenIdle)(idleTimeout);
      if (!_eligible) {
        _mark(skippedMark);
        return;
      }

      _mark(downloadStartMark);
      final bytes = await _loadFontBytes(fontAssetKey).timeout(downloadTimeout);
      await _registerFont(bytes);
      _didLoad = true;
      _notifyFontsChanged();
      _mark(loadedMark);
    } catch (error) {
      // 完整字体不可用只是排版回落，绝不能拖垮启动：记录后放弃本会话。
      _lastError = error;
      _mark(errorMark);
    }
  }

  /// 联网 + 可见 + 未省流 + 非慢网，才允许后台下载。
  bool get _eligible {
    final platform = _platform;
    if (!platform.isOnline) return false;
    if (!platform.isVisible) return false;
    if (platform.saveData) return false;
    final type = platform.effectiveConnectionType?.trim().toLowerCase();
    return type == null || !_slowConnectionTypes.contains(type);
  }

  void _mark(String name) {
    try {
      _marker(name);
    } catch (error) {
      // 验收标记失败不影响字体加载。
      _lastError = error;
    }
  }

  static Future<ByteData> _loadFromRootBundle(String assetKey) =>
      rootBundle.load(assetKey);

  static Future<void> _registerWithFontLoader(ByteData bytes) {
    final loader = FontLoader(fontFamily)
      ..addFont(Future<ByteData>.value(bytes));
    return loader.load();
  }

  static Future<void> _delay(Duration duration) =>
      Future<void>.delayed(duration);

  /// 通过公开的 channel buffer 走一遍 `flutter/system` 的 fontsChange，
  /// 让 PaintingBinding 通知已上屏文本重排（不触碰 @protected 的 handler）。
  static void _notifySystemFontsChanged() {
    ServicesBinding.instance.channelBuffers.push(
      SystemChannels.system.name,
      const JSONMessageCodec().encodeMessage(<String, Object?>{
        'type': 'fontsChange',
      }),
      (ByteData? _) {},
    );
  }
}
