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
  static const double controlMinHeight = 44;
  static const double controlIconSize = 20;

  // ----- Modal bottom sheets -----
  // 键盘弹出时，以键盘上方可用高度为基准。
  static const double modalSheetMinHeightFactor = 1 / 2;
  static const double modalSheetMaxHeightFactor = 2 / 3;

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

  // ----- 默认主题 iOS 风档位 -----
  //
  // 仅 `defaultBrand`（_defaultTheme）消费，用于把默认主题调向 iOS 观感；
  // 其余 7 套主题（re0..botw）继续沿用上方通用档位，观感保持不变。
  // 共享组件通过 `AppSurfaceStyle.ios`（ThemeExtension）读取，不要在共享层
  // 直接引用这些常量，否则会波及全部主题。
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
  static const double fontSizeSection = 15;
  static const double fontSizeMd = 16;
  static const double fontSizeLg = 18;
  static const double fontSizeXl = 22;
  static const double fontSizeXxl = 28;

  static const double fontSizeCaption = fontSizeXs;
  static const double fontSizeSecondary = fontSizeSm;
  static const double fontSizeBody = fontSizeBase;
  static const double fontSizeListTitle = fontSizeSection;
  static const double fontSizeCardTitle = fontSizeMd;
  static const double fontSizeNavigationTitle = fontSizeMd;
  static const double fontSizePageTitle = fontSizeLg;
  static const double fontSizeNumericHighlight = 26;
  static const double fontSizeButton = 13;
  static const double fontSizeBottomNavLabel = 11;

  static const FontWeight fontWeightRegular = FontWeight.normal;

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
/// 仅默认主题在 `_defaultTheme` 注册 [AppSurfaceStyle.ios]：共享组件
/// （AppSurfaceCard / AppModalSheet / AppMetricCard / AppSettingsSection /
/// 主底部导航）据此取 iOS 档圆角、去描边留极淡阴影、半透明底导航与毛玻璃。
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

  /// 默认主题（defaultBrand）专用：iOS 风 / 液态玻璃档。
  ///
  /// cardFillColor 显式注册为页面 surface 纯色：三类卡面（Material Card /
  /// AppSurfaceCard / AppMetricCard）在默认主题同走一个填充档——此前
  /// MetricCard 回退 surface@0.85，与另两类卡面的实底 surface 不同源。
  static const AppSurfaceStyle ios = AppSurfaceStyle(
    cardRadius: DesignTokens.radiusCardIos,
    smallTileRadius: DesignTokens.radiusControlIos,
    cardFillColor: DesignTokens.defaultSurface,
    cardBorder: Border(),
    cardShadow: DesignTokens.shadowXs,
    sheetTopRadius: DesignTokens.sheetIosTopRadius,
    navBarBlurSigma: DesignTokens.navBarIosBlurSigma,
  );

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
