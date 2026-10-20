import 'package:flutter/foundation.dart';

import 'app_config.dart';

class WebTarget {
  static const String raw = AppConfig.webTarget;

  /// 仅测试用：非 null 时强制 [isDesktopWebBuild] 返回该值。
  ///
  /// flutter test 跑在 VM 上，kIsWeb 恒为 false，桌面 web 外壳分支
  /// （NavigationRail 壳）无法用真实编译期条件触达，宽屏壳测试靠此注入。
  static bool? debugDesktopWebBuild;

  /// 测试中模拟任意 Web 构建（desktop / mobile / responsive）。
  @visibleForTesting
  static bool? debugWebBuild;

  static bool get isWebBuild =>
      debugWebBuild ?? (kIsWeb || debugDesktopWebBuild == true);

  static bool get isDesktopWebBuild =>
      debugDesktopWebBuild ?? (kIsWeb && raw == 'desktop');
  static bool get isMobileWebBuild => kIsWeb && raw == 'mobile';

  /// 宽屏桌面壳最小宽度：外壳分派按运行时宽度判定（平台无关），
  /// main.dart 的 LayoutBuilder 分派与宽屏冒烟测试共用此档位。
  static const double desktopShellBreakpoint = 900;

  /// 运行时宽度判定入口：≥[desktopShellBreakpoint] 渲染桌面壳
  /// （NavigationRail + 限宽内容区），<阈值原样回落移动壳。
  ///
  /// 一级导航的平台规则使用 [isWebBuild]，与视口宽度和构建档位独立。
  /// Android 折叠屏/平板的原生导航配置不受宽度分派影响。
  static bool isWidescreenLayout(double width) =>
      width >= desktopShellBreakpoint;

  /// Web 渲染器下 BackdropFilter 逐帧回读像素，开销显著高于原生：
  /// 底部导航毛玻璃在 web 端降档（mobile shell 是全应用唯一模糊挂点）。
  static bool get shouldReduceNavBarBlur => kIsWeb;
}
