// 延迟字体加载所需的浏览器能力抽象：Web 读 navigator/document/performance，
// 原生端走空实现，保证 DeferredWebFontService 在 VM 上零副作用。
export 'deferred_web_font_platform_stub.dart'
    if (dart.library.js_interop) 'deferred_web_font_platform_web.dart';
