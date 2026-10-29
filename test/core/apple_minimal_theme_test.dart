import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/home_page_style.dart';
import 'package:duoyi/core/page_tab_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final theme = AppBrands.defaultBrand.theme;

  test('默认主题使用 Apple minimal 表面档位', () {
    final style = theme.extension<AppSurfaceStyle>();
    expect(style, AppSurfaceStyle.appleMinimal);
    expect(style!.cardRadius, DesignTokens.radiusCardApple);
    expect(style.smallTileRadius, DesignTokens.radiusSmallTileApple);
    expect(style.sheetTopRadius, DesignTokens.radiusSheetApple);
    expect(style.cardFillColor, DesignTokens.appleSurface);
    expect(style.cardShadow, DesignTokens.shadowApple);
    // 无硬描边：仅保留极淡阴影提供层次。
    expect(style.cardBorder!.top.style, BorderStyle.none);
    expect(style.cardBorder!.top.width, 0);
    // 底栏沿用现有低成本模糊档，不给列表卡片引入 BackdropFilter。
    expect(style.navBarBlurSigma, DesignTokens.navBarIosBlurSigma);
    expect(AppSurfaceStyle.isDefaultTheme(style), isTrue);
  });

  test('默认主题画布 / 表面 / 导航使用苹果简约令牌', () {
    expect(theme.scaffoldBackgroundColor, DesignTokens.appleBackground);
    expect(
      AppBrands.defaultBrand.backgroundOverlay,
      DesignTokens.appleBackground,
    );
    expect(theme.colorScheme.primary, DesignTokens.applePrimary);
    expect(theme.colorScheme.surface, DesignTokens.appleSurface);
    expect(theme.cardTheme.color, DesignTokens.appleSurface);
    expect(theme.cardTheme.elevation, 0);
    expect(
      theme.cardTheme.margin,
      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
    expect(
      theme.inputDecorationTheme.fillColor,
      DesignTokens.appleSurfaceMuted,
    );
    expect(
      (theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder)
          .borderSide
          .color,
      DesignTokens.appleBorder,
    );
    // Material Card 与共享卡面同走"无描边"档。
    final cardSide = (theme.cardTheme.shape! as RoundedRectangleBorder).side;
    expect(cardSide.width, 0);
    // 更高、半透明的底栏（模糊由 main.dart 按 navBarBlurSigma 包裹）。
    expect(theme.navigationBarTheme.height, DesignTokens.navBarAppleHeight);
    expect(
      theme.navigationBarTheme.backgroundColor!.a,
      closeTo(DesignTokens.navBarAppleBackgroundAlpha, 0.001),
    );
    expect(
      (theme.bottomSheetTheme.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.vertical(
        top: Radius.circular(DesignTokens.radiusSheetApple),
      ),
    );
  });

  test('默认主题 AppBar 左对齐且字体仍是随包变量字体', () {
    expect(theme.appBarTheme.centerTitle, isFalse);
    expect(DesignTokens.fontFamily, 'ResourceHanRounded');
    expect(
      theme.appBarTheme.titleTextStyle?.fontFamily,
      DesignTokens.fontFamily,
    );
    expect(DesignTokens.homeText, DesignTokens.appleText);
    expect(DesignTokens.homeMuted, DesignTokens.appleTextMuted);
    expect(DesignTokens.homeSubtle, DesignTokens.appleSubtle);
    expect(DesignTokens.homeAccent, DesignTokens.applePrimary);
    expect(DesignTokens.homeDivider, DesignTokens.appleBorder);
    expect(DesignTokens.homeCategory, DesignTokens.appleCategory);
    expect(theme.textTheme.bodyMedium?.fontFamily, DesignTokens.fontFamily);
    expect(theme.textTheme.titleLarge?.fontFamily, DesignTokens.fontFamily);
  });

  test('首页与页签跟随默认档位，液态玻璃仍是独立玻璃档', () {
    expect(HomePageStyle.fromTheme(theme).usesReferencePalette, isTrue);
    expect(HomePageStyle.fromTheme(theme).accent, DesignTokens.homeAccent);
    expect(appPageTabTheme(theme).labelColor, DesignTokens.homeAccent);
    expect(
      appPageTabTheme(theme).labelStyle?.fontFamily,
      DesignTokens.fontFamily,
    );

    final glassTheme = AppBrands.liquidGlass.theme;
    final glassStyle = glassTheme.extension<AppSurfaceStyle>();
    expect(glassStyle, AppSurfaceStyle.liquidGlass);
    expect(glassStyle, isNot(AppSurfaceStyle.appleMinimal));
    expect(AppSurfaceStyle.isDefaultTheme(glassStyle), isFalse);
    expect(glassTheme.appBarTheme.centerTitle, isTrue);
  });

  test('其余品牌主题不带默认档 extension 且观感不变', () {
    for (final brand in AppBrands.all.where(
      (brand) => brand.style != BrandStyle.defaultBrand,
    )) {
      final style = brand.theme.extension<AppSurfaceStyle>();
      expect(AppSurfaceStyle.isDefaultTheme(style), isFalse, reason: brand.id);
      expect(brand.theme.appBarTheme.centerTitle, isTrue, reason: brand.id);
      expect(
        brand.theme.navigationBarTheme.height,
        60,
        reason: '${brand.id} 底栏高度保持 60',
      );
    }
    expect(AppBrands.re0.theme.extension<AppSurfaceStyle>(), isNull);
    expect(AppBrands.all.first, same(AppBrands.defaultBrand));
    expect(AppBrands.byId(null), same(AppBrands.defaultBrand));
  });
}
