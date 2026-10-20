import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'page_tab_style.dart';

/// The approved home palette is scoped to the default theme. Branded themes
/// keep their own accents and body text, including image-background contrast.
class HomePageStyle {
  final Color text;
  final Color muted;
  final Color subtle;
  final Color accent;
  final Color divider;
  final Color category;
  final bool usesReferencePalette;

  const HomePageStyle._({
    required this.text,
    required this.muted,
    required this.subtle,
    required this.accent,
    required this.divider,
    required this.category,
    required this.usesReferencePalette,
  });

  factory HomePageStyle.of(BuildContext context) =>
      HomePageStyle.fromTheme(Theme.of(context));

  factory HomePageStyle.fromTheme(ThemeData theme) {
    final reference = theme.extension<AppSurfaceStyle>() == AppSurfaceStyle.ios;
    final cs = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.color ?? cs.onSurfaceVariant;
    return HomePageStyle._(
      text: reference ? DesignTokens.homeText : cs.onSurface,
      muted: reference ? DesignTokens.homeMuted : muted,
      subtle: reference ? DesignTokens.homeSubtle : muted,
      accent: reference ? DesignTokens.homeAccent : cs.primary,
      divider: reference
          ? DesignTokens.homeDivider
          : cs.outlineVariant.withValues(alpha: 0.5),
      category: reference ? DesignTokens.homeCategory : cs.primary,
      usesReferencePalette: reference,
    );
  }

  TextStyle typography(
    ThemeData theme, {
    required double size,
    Color? color,
    double height = 1.5,
  }) => (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
    fontSize: size,
    fontWeight: DesignTokens.fontWeightStrong,
    color: color ?? text,
    height: height,
    letterSpacing: 0,
  );
}

/// Compatibility name for the indicator now shared by all subpage tabs.
typedef HomeTabIndicator = PageTabIndicator;

/// Keeps the creation button on the content edge at both phone and desktop sizes.
class HomeFabLocation extends FloatingActionButtonLocation {
  const HomeFabLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry geometry) {
    final fallback = FloatingActionButtonLocation.endFloat.getOffset(geometry);
    final right =
        (geometry.scaffoldSize.width +
            math.min(
              geometry.scaffoldSize.width,
              DesignTokens.homeContentMaxWidth,
            )) /
        2;
    return Offset(
      math.min(
        fallback.dx,
        right - DesignTokens.spaceXxl - geometry.floatingActionButtonSize.width,
      ),
      fallback.dy,
    );
  }
}
