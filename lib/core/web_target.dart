import 'package:flutter/foundation.dart';

import 'app_config.dart';

class WebTarget {
  static const String raw = AppConfig.webTarget;

  /// 仅测试用：非 null 时强制 [isDesktopWebBuild] 返回该值。
  ///
  /// flutter test 跑在 VM 上，kIsWeb 恒为 false，桌面 web 外壳分支
  /// （NavigationRail 壳）无法用真实编译期条件触达，宽屏壳测试靠此注入。
  static bool? debugDesktopWebBuild;

  static bool get isDesktopWebBuild =>
      debugDesktopWebBuild ?? (kIsWeb && raw == 'desktop');
  static bool get isMobileWebBuild => kIsWeb && raw == 'mobile';

  /// 宽屏桌面壳最小宽度：外壳分派按运行时宽度判定（平台无关），
  /// main.dart 的 LayoutBuilder 分派与宽屏冒烟测试共用此档位。
  static const double desktopShellBreakpoint = 900;

  /// 运行时宽度判定入口：≥[desktopShellBreakpoint] 渲染桌面壳
  /// （NavigationRail + 限宽内容区），<阈值原样回落移动壳。
  ///
  /// 与编译期 [isDesktopWebBuild] 分工——外壳布局只认视口：responsive 包、
  /// dev web 与 Linux 桌面端宽屏同样获得 rail 壳；tab 集过滤等"桌面包
  /// 专属行为"（隐藏小组件 tab）仍只认编译期档位，Android 折叠屏/平板
  /// 展开时的小组件入口不受宽度分派影响。
  static bool isWidescreenLayout(double width) =>
      width >= desktopShellBreakpoint;

  /// Web 渲染器下 BackdropFilter 逐帧回读像素，开销显著高于原生：
  /// 底部导航毛玻璃在 web 端降档（mobile shell 是全应用唯一模糊挂点）。
  static bool get shouldReduceNavBarBlur => kIsWeb;
}
