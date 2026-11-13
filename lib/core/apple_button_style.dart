import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Light controls for the default Apple minimal theme. Local layouts can keep
/// their dimensions while inheriting the same soft fill and keyboard focus.
class AppleButtonStyle {
  AppleButtonStyle._();

  static bool appliesTo(ThemeData theme) =>
      AppSurfaceStyle.isDefaultTheme(theme.extension<AppSurfaceStyle>());

  static BorderSide _border(ColorScheme colors, Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled) ||
        !states.contains(WidgetState.focused)) {
      return BorderSide.none;
    }
    return BorderSide(
      color: colors.primary.withValues(alpha: 0.42),
      width: 0.8,
    );
  }

  static WidgetStateProperty<BorderSide?> border(ThemeData theme) =>
      WidgetStateProperty.resolveWith(
        (states) => _border(theme.colorScheme, states),
      );

  /// RawChip resolves WidgetStateBorderSide itself, unlike styleFrom(side:),
  /// which wraps its argument in WidgetStatePropertyAll.
  static BorderSide chipBorder(ThemeData theme) =>
      WidgetStateBorderSide.resolveWith(
        (states) => _border(theme.colorScheme, states),
      );

  static ButtonStyle outlined(ThemeData theme, {bool? enabled}) {
    if (!(enabled ?? appliesTo(theme))) return const ButtonStyle();
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return ButtonStyle(
      side: border(theme),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        final disabled = states.contains(WidgetState.disabled);
        if (disabled) return Colors.transparent;
        final selected = states.contains(WidgetState.selected);
        return Color.alphaBlend(
          (selected ? colors.primary : colors.onSurface).withValues(
            alpha: selected
                ? 0.10
                : dark
                ? 0.08
                : 0.035,
          ),
          colors.surface,
        );
      }),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return Colors.transparent;
        if (states.contains(WidgetState.pressed)) {
          return colors.primary.withValues(alpha: 0.10);
        }
        if (states.contains(WidgetState.focused)) {
          return colors.primary.withValues(alpha: 0.075);
        }
        if (states.contains(WidgetState.hovered)) {
          return colors.primary.withValues(alpha: 0.045);
        }
        return Colors.transparent;
      }),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    );
  }

  /// Filled, text and icon actions retain their own semantic colours and
  /// interaction feedback, without inheriting an outlined variant's dark edge.
  static ButtonStyle borderless(ThemeData theme, {bool? enabled}) =>
      (enabled ?? appliesTo(theme))
      ? const ButtonStyle(side: WidgetStatePropertyAll(BorderSide.none))
      : const ButtonStyle();
}
