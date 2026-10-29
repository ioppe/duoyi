import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Shared visual contract for switching between pages inside one screen.
TabBarThemeData appPageTabTheme(ThemeData theme) {
  final reference = AppSurfaceStyle.isDefaultTheme(
    theme.extension<AppSurfaceStyle>(),
  );
  final accent = reference
      ? DesignTokens.homeAccent
      : theme.colorScheme.primary;
  final muted = reference
      ? DesignTokens.homeMuted
      : theme.textTheme.bodySmall?.color ?? theme.colorScheme.onSurfaceVariant;
  final text = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
    fontSize: DesignTokens.fontSizeSm,
    fontWeight: DesignTokens.fontWeightMedium,
    height: 1.5,
    letterSpacing: 0,
  );
  return TabBarThemeData(
    dividerColor: Colors.transparent,
    indicatorSize: TabBarIndicatorSize.label,
    indicator: PageTabIndicator(color: accent),
    labelColor: accent,
    unselectedLabelColor: muted,
    labelPadding: const EdgeInsets.symmetric(horizontal: DesignTokens.spaceMd),
    labelStyle: text.copyWith(color: accent),
    unselectedLabelStyle: text.copyWith(color: muted),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  );
}

/// A short, rounded mark at the start of the selected label (including RTL).
class PageTabIndicator extends Decoration {
  final Color color;

  const PageTabIndicator({required this.color});

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _PageTabIndicatorPainter(color, onChanged);
}

class _PageTabIndicatorPainter extends BoxPainter {
  final Color color;

  _PageTabIndicatorPainter(this.color, super.onChanged);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final width = math.min(DesignTokens.homeTabIndicatorWidth, size.width);
    final x = configuration.textDirection == TextDirection.rtl
        ? offset.dx + size.width - width
        : offset.dx;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x,
          offset.dy + size.height - DesignTokens.spaceXxs,
          width,
          DesignTokens.spaceXxs,
        ),
        const Radius.circular(DesignTokens.spaceXxs),
      ),
      Paint()..color = color,
    );
  }
}
