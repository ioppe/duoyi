import 'package:flutter/material.dart';

/// 全局设计 Token。
///
/// 所有新写 UI 应从这里取颜色 / 圆角 / 间距 / 字阶 / 阴影。
/// 业务色（主题色 / AppBar 色等）仍然走 `Theme.of(ctx).colorScheme`；
/// 这里只定义"跨主题通用"的语义色与度量。
///
/// 对应 `Requirement 10.1`。
class DesignTokens {
  DesignTokens._();

  // ----- Spacing（4 的倍数，保持节奏一致） -----
  static const double spaceXxs = 2;
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 20;
  static const double spaceXxl = 24;
  static const double space3xl = 32;
  static const double space4xl = 40;
  static const double space5xl = 48;

  // ----- Account form fields -----
  static const double formFieldMinHeight = 56;
  static const double formContentMaxWidth = 840;
  static const double creationFormMaxWidth = 720;
  static const double controlMinHeight = 44;
  static const double controlIconSize = 20;

  // Keeps the last scrollable item clear of the lower-right creation action.
  static const double pageFabBottomPadding = 88;

  // ----- Shared authentication pages -----
  static const double authPageMaxWidth = 1120;
  static const double authFormMaxWidth = 440;
  static const double authWideBreakpoint = 960;
  static const double authHeroSize = 36;
  static const double authLogoSize = 44;
  static const double authCardHeightMobile = 484;
  static const double authCardHeightWide = 508;
  static const double authCardMinHeight = 420;
  static const Duration authFlipDuration = Duration(milliseconds: 480);
  static const double authCardTextScaleFactor = 0.75;

  // ----- Habit heatmap -----
  static const double habitHeatmapWidthFactor = 0.8;
  static const double habitWorkspaceMaxWidth = 960;

  // ----- Home preview specification -----
  static const double homeContentMaxWidth = 720;
  static const double homeTopInset = 28;
  static const double homeHeadingSize = fontSizePageTitle;
  static const double homeTaskTitleSize = fontSizeBody;
  static const double homeCaptionSize = fontSizeCaption;
  static const double homeCounterSize = fontSizeCaption;
  static const double homeTabIndicatorWidth = 22;
  static const double homeStatusSize = fontSizePageTitle;
  static const double homeItemLeadingGap = space3xl;
  static const double homeQuadrantDotSize = 10;
  static const double homeQuadrantTitleGap = spaceSm;
  static const Color homeText = appleText;
  static const Color homeMuted = appleTextMuted;
  static const Color homeSubtle = appleSubtle;
  static const Color homeAccent = applePrimary;
  static const Color homeDivider = appleBorder;
  static const Color homeCategory = appleCategory;

  // ----- Modal bottom sheets -----
  // 初始高度为半屏至三分之二屏；用户浏览后可展开到安全区内整页。
  // 键盘弹出时，以键盘上方可用高度为基准。
  static const double modalSheetMinHeightFactor = 1 / 2;
  static const double modalSheetMaxHeightFactor = 2 / 3;
  static const double modalSheetDragThreshold = 24;

  // ----- Default palette -----
  static const Color defaultPageBackground = Color(0xFFF6F7F9);
  static const Color defaultSurface = Color(0xFFFFFFFF);
  static const Color defaultSurfaceMuted = Color(0xFFF1F3F6);
  static const Color defaultText = Color(0xFF1F2933);
  static const Color defaultTextMuted = Color(0xFF667085);
  static const Color defaultBorder = Color(0xFFD9E0E8);
  static const Color defaultPrimary = Color(0xFFC85656);
  static const Color defaultPrimarySoft = Color(0xFFF7E3E3);
  static const Color defaultPrimaryPressed = Color(0xFFA94444);
  static const Color defaultAccent = Color(0xFF2F8F83);
  static const Color defaultInfo = Color(0xFF2F6FAE);
  static const Color defaultSuccess = Color(0xFF2E7D62);
  static const Color defaultWarning = Color(0xFFB7791F);
  static const Color defaultError = Color(0xFFC64747);

  // ----- Radius -----
  static const double radiusXs = 4;
  static const double radiusSm = 8;
  static const double radiusControl = 10;
  static const double radiusMd = 10;
  static const double radiusCard = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;
  static const double radiusXxl = 28;
  static const double radiusPill = 999;

  // ----- Apple minimal（默认 App 主题 / Android 小组件同源）-----
  //
  // 默认主题（`AppBrands.defaultBrand`）与 Android 核心小组件共享同一套
  // 苹果简约语言：雾灰画布、白色表面、珊瑚红品牌色、低对比边界、极淡阴影、
  // 18 / 12 圆角与 28 弹层顶角。其余品牌主题不消费这些值；共享组件通过
  // `AppSurfaceStyle`（ThemeExtension）读取档位，不要在共享层直接引用这些
  // 常量，否则会波及全部主题。
  static const Color appleBackground = Color(0xFFF2F2F7); // 雾灰画布
  static const Color appleSurface = Color(0xFFFFFFFF); // 白色卡面
  static const Color appleSurfaceMuted = Color(0xFFF2F2F7); // 输入 / 分段底
  static const Color appleBorder = Color(0xFFE5E5EA); // 低对比细分隔
  static const Color appleText = Color(0xFF1C1C1E);
  static const Color appleTextMuted = Color(0xFF6E6E73);
  static const Color applePrimary = defaultPrimary; // 品牌珊瑚红
  static const Color applePrimarySoft = defaultPrimarySoft;
  static const Color appleSubtle = Color(0xFF8E8E93);
  static const Color appleCategory = Color(0xFF7A8494);
  static const double radiusCardApple = 18; // 卡片圆角（Apple minimal 档）
  static const double radiusSmallTileApple = 12; // 指标卡 / 控件圆角
  static const double radiusSheetApple = 28; // 底部弹层顶角
  static const double navBarAppleHeight = 68; // 底部导航高度（更高更宽松）
  static const double navBarAppleBackgroundAlpha = 0.72; // 半透明底导航
  // 极淡阴影：白卡面在雾灰画布上只留一档层次，不叠加硬描边。
  static const List<BoxShadow> shadowApple = [
    BoxShadow(
      color: Color(0x0F000000), // #000 6%
      blurRadius: 16,
      offset: Offset(0, 2),
    ),
  ];

  // ----- 旧默认主题 iOS 风档位（保留兼容）-----
  //
  // 默认主题已切到上面的 Apple minimal 档；这些常量继续服务
  // `AppSurfaceStyle.ios` 与 `_SharedFeel.ios`（液态玻璃主题共用）。
  static const double radiusControlIos = 12; // 控件圆角 iOS 档（≥12）
  static const double radiusCardIos = 16; // 卡片圆角 iOS 档（≥16）
  static const double dialogIosRadius = 20; // 对话框圆角 iOS 档
  static const double sheetIosTopRadius = 28; // 底部弹层顶角 iOS 档
  static const double buttonIosMinHeight = 44; // 按钮最小高度（44pt 触达）
  static const double inputIosVerticalPadding = 12; // 输入框纵向内边距
  static const double dividerIosAlpha = 0.40; // 亮色分隔线（更柔和）
  static const double dividerIosDarkAlpha = 0.44; // 暗色分隔线（更柔和）
  static const double navBarIosBackgroundAlpha = 0.72; // 底部导航半透明底色
  static const double navBarIosBlurSigma = 18; // 底部导航毛玻璃模糊半径
  // web 渲染器 BackdropFilter 开销高（逐帧回读像素）：底导航模糊在 web 端
  // 降到的轻量档（由 WebTarget.shouldReduceNavBarBlur 接线，原生不变）。
  static const double navBarWebBlurSigma = 10; // web 底部导航降级模糊档

  // ----- 液态玻璃（liquidGlass 主题）档位 -----
  //
  // 卡片走"半透明填充 + 白高光描边"的伪玻璃（性能优先：列表内不逐卡
  // BackdropFilter，无背景图场景真模糊也无视觉收益）；真模糊只用于底部
  // 导航（navBarIosBlurSigma，复用 AppSurfaceStyle.navBarBlurSigma 挂点）。
  static const double glassBlurSigma = 14; // 预留：弹层/悬浮卡真模糊档
  static const double glassFillLightAlpha = 0.45; // 亮色玻璃填充（白）下限
  static const double glassFillDarkAlpha = 0.60; // 暗色玻璃填充（深色）档
  static const double glassHighlightAlpha = 0.35; // 白色高光描边 alpha

  // Convenience shapes
  static const BorderRadius borderRadiusSm = BorderRadius.all(
    Radius.circular(radiusSm),
  );
  static const BorderRadius borderRadiusMd = BorderRadius.all(
    Radius.circular(radiusMd),
  );
  static const BorderRadius borderRadiusLg = BorderRadius.all(
    Radius.circular(radiusLg),
  );
  static const BorderRadius borderRadiusXl = BorderRadius.all(
    Radius.circular(radiusXl),
  );

  // ----- Typography scale（与 ThemeData TextTheme 协同，提供字号常量） -----
  static const double fontSizeXs = 11;
  static const double fontSizeSm = 12;
  static const double fontSizeBase = 14;
  static const double fontSizeSection = 14;
  static const double fontSizeMd = 14;
  static const double fontSizeLg = 16;
  static const double fontSizeXl = 20;
  static const double fontSizeXxl = 24;

  static const double fontSizeCaption = fontSizeXs;
  static const double fontSizeSecondary = fontSizeSm;
  static const double fontSizeBody = fontSizeBase;
  static const double fontSizeListTitle = fontSizeSection;
  static const double fontSizeCardTitle = fontSizeMd;
  static const double fontSizeNavigationTitle = 18;
  static const double fontSizePageTitle = 18;
  static const double fontSizeNumericHighlight = 24;

  /// 系统小组件预览的主数字层级，不参与应用正文/标题基准。
  static const double fontSizeWidgetPrimaryMetric = 34;
  static const double fontSizeWidgetCount = 26;
  static const double fontSizeButton = 12;
  static const double fontSizeBottomNavLabel = 11;

  /// 原生 Android 的正文基准字号：安卓端正文默认按逻辑字号 12 排版。
  ///
  /// 共享字号 token（[fontSizeBody] 等 14 档）与其它平台的基准保持不变；
  /// 只有原生 Android 在 `AppTypography.platformScaler` 里按
  /// `12 / 14` 的比例缩放文字，用户档位（默认 100%）与系统缩放、
  /// 非线性缩放仍原样叠加。
  static const double androidFontSizeBody = 12;

  /// 全局 UI 字体：随应用打包的 Resource Han Rounded CN Bold 字库。
  ///
  /// 圆润中文、离线可用，所有品牌 / 页面 / 共享控件统一继承该家族；同一
  /// 静态粗体资源按 400 / 500 / 600 / 700 注册，保留现有语义字重令牌。
  static const String fontFamily = 'ResourceHanRounded';

  /// 正文字重：正文、说明文字、输入提示与菜单项。
  static const FontWeight fontWeightRegular = FontWeight.w400;

  /// 标签字重：按钮文字、导航标签、chip 与浮动标签。
  static const FontWeight fontWeightMedium = FontWeight.w500;

  /// 强调字重：页面 / 卡片 / AppBar 标题。
  static const FontWeight fontWeightStrong = FontWeight.w600;

  // ----- Elevation / Shadow -----
  static const List<BoxShadow> shadowXs = [
    BoxShadow(
      color: Color(0x0F000000), // #000 6%
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];
  static const List<BoxShadow> shadowSm = [
    BoxShadow(
      color: Color(0x14000000), // #000 8%
      blurRadius: 7,
      offset: Offset(0, 2),
    ),
  ];
  static const List<BoxShadow> shadowMd = [
    BoxShadow(
      color: Color(0x1A000000), // #000 10%
      blurRadius: 12,
      offset: Offset(0, 3),
    ),
  ];
  static const List<BoxShadow> shadowLg = [
    BoxShadow(
      color: Color(0x24000000), // #000 14%
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];

  // ----- Durations -----
  static const Duration durationInstant = Duration(milliseconds: 80);
  static const Duration durationFast = Duration(milliseconds: 160);
  static const Duration durationBase = Duration(milliseconds: 240);
  static const Duration durationSlow = Duration(milliseconds: 320);
  static const Duration durationFade = Duration(milliseconds: 300);

  // ----- 语义色：完成态 / 过期 / 临期 / 归档 / 一般状态 -----
  //
  // 这些是跨主题通用的"语义颜色"。具体视觉状态（已完成、临期、过期、归档、普通）
  // 由 `CompletionVisibilityPolicy.visualState(...)` 决定，颜色映射用这里的 token。
  static const Color todoNormal = Color(0xDE000000); // black87 ~ onSurface
  static const Color todoDueSoon = Color(0xFFFFB74D); // orange.shade400
  static const Color todoOverdue = Color(0xFFEF5350); // red.shade400
  static const Color todoCompleted = Color(0xFF66BB6A); // green.shade400
  static const Color todoArchived = Color(0xFFBDBDBD); // grey.shade400

  /// 完成态文本的"灰度 70%"：与 `todoCompleted` 配套使用。
  static const double completedTextOpacity = 0.7;

  // ----- 结果态 -----
  static const Color resultEmpty = Color(0xFF9E9E9E); // grey.shade500
  static const Color resultError = Color(0xFFEF5350); // red.shade400
  static const Color resultLoadingShimmerBase = Color(0xFFEEEEEE);
  static const Color resultLoadingShimmerHighlight = Color(0xFFFAFAFA);

  // ----- 优先级色标（对齐 TodoItem.priority） -----
  static const Color priorityHigh = Color(0xFFE53935); // red 600
  static const Color priorityMedium = Color(0xFFFB8C00); // orange 600
  static const Color priorityLow = Color(0xFF43A047); // green 600
  static const Color priorityNone = Color(0xFFB0BEC5); // blueGrey 200

  // ----- 四象限语义色（首页 / 待办 / 日历 / 统计共用） -----
  static const Color quadrantQ1 = Color(0xFFE53935); // 紧急且重要：红
  static const Color quadrantQ2 = Color(0xFF8E5CC6); // 重要不紧急：紫
  static const Color quadrantQ3 = Color(0xFFF6A339); // 紧急不重要：黄
  static const Color quadrantQ4 = Color(0xFF43A047); // 不紧急不重要：绿

  // ----- Dialog / 二次确认 统一样式 token -----
  static const EdgeInsets dialogContentPadding = EdgeInsets.fromLTRB(
    spaceXxl,
    spaceLg,
    spaceXxl,
    spaceSm,
  );
  static const EdgeInsets dialogActionsPadding = EdgeInsets.fromLTRB(
    spaceMd,
    0,
    spaceMd,
    spaceSm,
  );
  static const BorderRadius dialogBorderRadius = borderRadiusLg;
}

/// 表面 / 控件的"观感档位"（ThemeExtension）。
///
/// 默认主题在 `_defaultTheme` 注册 [AppSurfaceStyle.appleMinimal]：共享组件
/// （AppSurfaceCard / AppModalSheet / AppMetricCard / AppSettingsSection /
/// 主底部导航）据此取 Apple minimal 档圆角、无描边 + 极淡阴影、半透明底导航
/// 与低成本毛玻璃。[AppSurfaceStyle.ios] 是改造前的默认档，保留兼容；
/// [AppSurfaceStyle.liquidGlass] 服务液态玻璃主题。
/// 未注册该 extension 的主题（re0..botw）在调用点取各自既有默认值，
/// 观感与改造前逐像素一致。
class AppSurfaceStyle extends ThemeExtension<AppSurfaceStyle> {
  final double cardRadius;

  /// 指标卡等小型卡片的圆角（控件档）。
  final double smallTileRadius;

  /// 卡片默认描边；[Border]（四边 none）表示"去描边"，null 表示沿用调用点既有描边。
  final Border? cardBorder;

  /// 卡片默认填充色（玻璃主题给半透明白/深色）；null 表示沿用 cs.surface。
  /// 调用方显式传 color 时自动豁免（选中态、横幅等语义色优先）。
  final Color? cardFillColor;

  /// `elevation <= 0` 时卡片默认阴影（默认主题给极淡阴影替代描边）。
  final List<BoxShadow> cardShadow;

  /// 底部弹层顶角。
  final double sheetTopRadius;

  /// 底部导航毛玻璃模糊半径；`<= 0` 表示不启用（ThemeData 做不出液态玻璃，
  /// 需调用点在 NavigationBar 外包 BackdropFilter）。
  final double navBarBlurSigma;

  const AppSurfaceStyle({
    required this.cardRadius,
    required this.smallTileRadius,
    required this.cardShadow,
    required this.sheetTopRadius,
    this.cardBorder,
    this.cardFillColor,
    this.navBarBlurSigma = 0,
  });

  /// 改造前的默认主题 iOS 风档（保留兼容）。
  ///
  /// cardFillColor 显式注册为页面 surface 纯色：三类卡面（Material Card /
  /// AppSurfaceCard / AppMetricCard）同走一个填充档。默认主题已改用
  /// [appleMinimal]；本档继续供既有引用使用。
  static const AppSurfaceStyle ios = AppSurfaceStyle(
    cardRadius: DesignTokens.radiusCardIos,
    smallTileRadius: DesignTokens.radiusControlIos,
    cardFillColor: DesignTokens.defaultSurface,
    cardBorder: Border(),
    cardShadow: DesignTokens.shadowXs,
    sheetTopRadius: DesignTokens.sheetIosTopRadius,
    navBarBlurSigma: DesignTokens.navBarIosBlurSigma,
  );

  /// 默认 App 主题（defaultBrand）专用：Apple minimal 档。
  ///
  /// 与 Android 核心小组件同一套视觉语言：白色卡面 + 18 圆角、无描边、
  /// 极淡阴影；底部导航沿用现有低成本模糊档（列表卡片不做 BackdropFilter）。
  static const AppSurfaceStyle appleMinimal = AppSurfaceStyle(
    cardRadius: DesignTokens.radiusCardApple,
    smallTileRadius: DesignTokens.radiusSmallTileApple,
    cardFillColor: DesignTokens.appleSurface,
    cardBorder: Border(),
    cardShadow: DesignTokens.shadowApple,
    sheetTopRadius: DesignTokens.radiusSheetApple,
    navBarBlurSigma: DesignTokens.navBarIosBlurSigma,
  );

  /// 是否为"默认主题"档位：Apple minimal 及其兼容别名 [ios]。
  ///
  /// 首页配色 / 页签等共享层用它判定默认主题；[liquidGlass] 与未注册档位的
  /// 品牌主题都返回 false，观感不变。
  static bool isDefaultTheme(AppSurfaceStyle? style) =>
      style != null && (style == appleMinimal || style == ios);

  /// 液态玻璃主题（liquidGlass）专用：半透明白填充 + 白高光描边的伪玻璃卡片，
  /// 底部导航启用真模糊（BackdropFilter）。非 const：填充/描边色由玻璃档
  /// alpha 常量派生（Colors.white.withValues）。
  static final AppSurfaceStyle liquidGlass = AppSurfaceStyle(
    cardRadius: DesignTokens.radiusCardIos,
    smallTileRadius: DesignTokens.radiusControlIos,
    // 白 @ glassFillLightAlpha（0x73 ≈ 45%）。
    cardFillColor: Colors.white.withValues(
      alpha: DesignTokens.glassFillLightAlpha,
    ),
    cardBorder: Border.fromBorderSide(
      BorderSide(
        color: Colors.white.withValues(alpha: DesignTokens.glassHighlightAlpha),
        width: 0.55,
      ),
    ),
    cardShadow: DesignTokens.shadowXs,
    sheetTopRadius: DesignTokens.sheetIosTopRadius,
    navBarBlurSigma: DesignTokens.navBarIosBlurSigma,
  );

  @override
  AppSurfaceStyle copyWith({
    double? cardRadius,
    double? smallTileRadius,
    Border? cardBorder,
    Color? cardFillColor,
    List<BoxShadow>? cardShadow,
    double? sheetTopRadius,
    double? navBarBlurSigma,
  }) {
    return AppSurfaceStyle(
      cardRadius: cardRadius ?? this.cardRadius,
      smallTileRadius: smallTileRadius ?? this.smallTileRadius,
      cardBorder: cardBorder ?? this.cardBorder,
      cardFillColor: cardFillColor ?? this.cardFillColor,
      cardShadow: cardShadow ?? this.cardShadow,
      sheetTopRadius: sheetTopRadius ?? this.sheetTopRadius,
      navBarBlurSigma: navBarBlurSigma ?? this.navBarBlurSigma,
    );
  }

  @override
  AppSurfaceStyle lerp(AppSurfaceStyle? other, double t) {
    if (other == null || t < 0.5) return this;
    return other;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppSurfaceStyle &&
            other.cardRadius == cardRadius &&
            other.smallTileRadius == smallTileRadius &&
            other.cardBorder == cardBorder &&
            other.cardFillColor == cardFillColor &&
            other.cardShadow == cardShadow &&
            other.sheetTopRadius == sheetTopRadius &&
            other.navBarBlurSigma == navBarBlurSigma;
  }

  @override
  int get hashCode => Object.hash(
    cardRadius,
    smallTileRadius,
    cardBorder,
    cardFillColor,
    cardShadow,
    sheetTopRadius,
    navBarBlurSigma,
  );

  @override
  String toString() =>
      'AppSurfaceStyle(cardRadius: $cardRadius, smallTileRadius: '
      '$smallTileRadius, cardBorder: $cardBorder, '
      'cardFillColor: $cardFillColor, cardShadow: $cardShadow, '
      'sheetTopRadius: $sheetTopRadius, navBarBlurSigma: $navBarBlurSigma)';
}
