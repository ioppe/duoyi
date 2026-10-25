import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/app_motion.dart';
import '../providers/theme_provider.dart';

/// 当前主题的表面观感档位。
///
/// 仅默认主题注册了 [AppSurfaceStyle.ios]；re0..botw 未注册，返回 null，
/// 调用点沿用下方 `_standard*` 既有默认值，观感保持不变。
AppSurfaceStyle? appSurfaceStyleOf(BuildContext context) =>
    Theme.of(context).extension<AppSurfaceStyle>();

// 既有通用档（未注册 AppSurfaceStyle 的主题沿用），与改造前逐值一致。
const BorderRadius _standardCardRadius = BorderRadius.all(
  Radius.circular(DesignTokens.radiusCard),
);
const BorderRadius _standardMetricTileRadius = BorderRadius.all(
  Radius.circular(DesignTokens.radiusMd),
);
const double _standardSheetTopRadius = 20;
const BorderRadius _standardSettingsSectionRadius = BorderRadius.all(
  Radius.circular(8),
);

class AppSurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;

  /// null 时取主题观感档位（默认主题 iOS 档 16，其余主题 radiusCard 12）。
  final BorderRadius? borderRadius;
  final Border? border;
  final double elevation;

  const AppSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.color,
    this.gradient,
    this.borderRadius,
    this.border,
    this.elevation = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceStyle = appSurfaceStyleOf(context);
    final effectiveRadius =
        borderRadius ??
        (surfaceStyle == null
            ? _standardCardRadius
            : BorderRadius.circular(surfaceStyle.cardRadius));
    ThemeProvider? themeProvider;
    try {
      themeProvider = context.watch<ThemeProvider>();
    } catch (_) {
      themeProvider = null;
    }
    final cardSkin = themeProvider?.activeCardSkin;
    final useCardSkin =
        cardSkin != null &&
        cardSkin.id != ThemeProvider.defaultCardSkinId &&
        color == null &&
        gradient == null;
    final surfaceColor = color ?? cs.surface;
    // 液态玻璃主题：默认填充换成半透明白玻璃（调用方传 color 时豁免——
    // 选中态 / 横幅等语义色优先；性能优先走伪玻璃填充，不做逐卡模糊）。
    final effectiveFillColor =
        (color == null ? surfaceStyle?.cardFillColor : null) ?? surfaceColor;
    final cardBorderColor = isDark
        ? cs.outlineVariant.withValues(alpha: 0.18)
        : (Color.lerp(DesignTokens.defaultBorder, cs.outlineVariant, 0.35) ??
                  DesignTokens.defaultBorder)
              .withValues(alpha: 0.72);
    final skinGradient = useCardSkin
        ? LinearGradient(
            colors: [
              cardSkin.colors.first.withValues(alpha: isDark ? 0.22 : 0.18),
              cardSkin.colors.last.withValues(alpha: isDark ? 0.18 : 0.12),
              cs.surface.withValues(alpha: isDark ? 0.94 : 0.96),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : null;
    final decoration = BoxDecoration(
      color: gradient == null && skinGradient == null
          ? effectiveFillColor
          : null,
      gradient: gradient ?? skinGradient,
      borderRadius: effectiveRadius,
      // 默认主题 iOS 档：去描边，改由 cardShadow 提供极淡层次；
      // 液态玻璃主题：白色高光描边；其余主题沿用 defaultBorder 淡描边。
      border:
          border ??
          (useCardSkin
              ? Border.all(
                  color: cardSkin.colors.first.withValues(alpha: 0.10),
                  width: 0.55,
                )
              : surfaceStyle?.cardBorder ??
                    Border.all(color: cardBorderColor, width: 0.55)),
      boxShadow: elevation <= 0
          ? (surfaceStyle?.cardShadow ?? const [])
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.05),
                blurRadius: 7 + elevation,
                offset: const Offset(0, 2),
              ),
            ],
    );

    final content = Ink(
      decoration: decoration,
      child: Padding(padding: padding, child: child),
    );

    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                borderRadius: effectiveRadius,
                child: content,
              ),
      ),
    );
  }
}

TextStyle appSecondaryControlTextStyle(BuildContext context) {
  final theme = Theme.of(context);
  return (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
    fontSize: DesignTokens.fontSizeBody,
    fontWeight: DesignTokens.fontWeightRegular,
    height: 1.4,
  );
}

TextStyle appSecondaryControlLabelStyle(BuildContext context) {
  final theme = Theme.of(context);
  return (theme.textTheme.labelMedium ?? const TextStyle()).copyWith(
    fontSize: DesignTokens.fontSizeSecondary,
    fontWeight: DesignTokens.fontWeightRegular,
    height: 1.4,
  );
}

TextStyle appSecondaryMenuItemTextStyle(BuildContext context) {
  final theme = Theme.of(context);
  return (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
    fontSize: DesignTokens.fontSizeBody,
    fontWeight: DesignTokens.fontWeightMedium,
    height: 1.4,
  );
}

TextStyle appSecondaryRouteTitleTextStyle(BuildContext context) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  return (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
    fontSize: DesignTokens.fontSizePageTitle,
    fontWeight: DesignTokens.fontWeightStrong,
    color: cs.onSurface,
    height: 1.2,
  );
}

Color _appSecondaryActionBackground(ColorScheme cs, {required bool isDark}) {
  final base = cs.primary;
  const darkForeground = Color(0xFF111827);
  if (_appContrastRatio(base, Colors.white) >= 4.5 ||
      _appContrastRatio(base, darkForeground) >= 4.5) {
    return base;
  }
  final target = isDark ? Colors.white : Colors.black;
  for (final amount in const [0.10, 0.16, 0.22, 0.30, 0.38]) {
    final candidate = Color.lerp(base, target, amount) ?? base;
    if (_appContrastRatio(candidate, Colors.white) >= 4.5 ||
        _appContrastRatio(candidate, darkForeground) >= 4.5) {
      return candidate;
    }
  }
  return Color.lerp(base, target, isDark ? 0.38 : 0.30) ?? base;
}

Color _appSecondaryActionForeground(Color background) {
  return _appReadableForeground(background, Colors.white);
}

Color _appReadableForeground(Color background, Color preferred) {
  if (_appContrastRatio(background, preferred) >= 4.5) return preferred;
  const dark = Color(0xFF111827);
  final darkContrast = _appContrastRatio(background, dark);
  final whiteContrast = _appContrastRatio(background, Colors.white);
  return darkContrast >= whiteContrast ? dark : Colors.white;
}

double _appContrastRatio(Color a, Color b) {
  final aLum = a.computeLuminance();
  final bLum = b.computeLuminance();
  final lighter = aLum > bLum ? aLum : bLum;
  final darker = aLum > bLum ? bLum : aLum;
  return (lighter + 0.05) / (darker + 0.05);
}

ButtonStyle appSecondaryFilledButtonStyle(BuildContext context) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final background = _appSecondaryActionBackground(
    cs,
    isDark: theme.brightness == Brightness.dark,
  );
  final disabledBackground =
      Color.lerp(
        cs.surfaceContainerHighest,
        background,
        theme.brightness == Brightness.dark ? 0.22 : 0.18,
      ) ??
      cs.surfaceContainerHighest;
  return FilledButton.styleFrom(
    backgroundColor: background,
    foregroundColor: _appSecondaryActionForeground(background),
    disabledBackgroundColor: disabledBackground,
    disabledForegroundColor: _appReadableForeground(
      disabledBackground,
      cs.onSurfaceVariant,
    ).withValues(alpha: 0.70),
    side: BorderSide(color: background.withValues(alpha: 0.16), width: 0.45),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.padded,
    minimumSize: const Size(0, DesignTokens.controlMinHeight),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    textStyle: appSecondaryControlTextStyle(context).copyWith(
      fontSize: DesignTokens.fontSizeButton,
      fontWeight: DesignTokens.fontWeightMedium,
    ),
  );
}

class AppSecondaryControlTheme extends StatelessWidget {
  final Widget child;

  const AppSecondaryControlTheme({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final controlText = appSecondaryControlTextStyle(context);
    final labelText = appSecondaryControlLabelStyle(context);
    final buttonText = controlText.copyWith(
      fontSize: DesignTokens.fontSizeButton,
      fontWeight: DesignTokens.fontWeightMedium,
    );
    OutlineInputBorder inputBorder(Color color, {double width = 0.35}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    final subtleBorder = cs.outlineVariant.withValues(
      alpha: isDark ? 0.12 : 0.16,
    );
    final selectedControlBackground = Color.alphaBlend(
      cs.primary.withValues(alpha: isDark ? 0.14 : 0.09),
      cs.surface,
    );
    final selectedControlRenderedBackground = Color.alphaBlend(
      selectedControlBackground,
      cs.surface,
    );
    final selectedControlForeground = _appReadableForeground(
      selectedControlRenderedBackground,
      cs.onSurface,
    );
    final selectedControlIcon = _appReadableForeground(
      selectedControlRenderedBackground,
      cs.primary,
    );
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          titleMedium: controlText.copyWith(color: cs.onSurface),
          titleSmall: controlText.copyWith(color: cs.onSurface),
          bodyLarge: controlText.copyWith(color: cs.onSurface),
          bodyMedium: controlText.copyWith(color: cs.onSurface),
          bodySmall: labelText.copyWith(color: cs.onSurfaceVariant),
          labelLarge: labelText.copyWith(color: cs.onSurface),
          labelMedium: labelText.copyWith(color: cs.onSurface),
        ),
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          prefixIconConstraints: const BoxConstraints.tightFor(
            width: 34,
            height: 34,
          ),
          suffixIconConstraints: const BoxConstraints.tightFor(
            width: 34,
            height: 34,
          ),
          labelStyle: labelText.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: DesignTokens.fontWeightRegular,
          ),
          floatingLabelStyle: labelText.copyWith(
            color: cs.primary,
            fontWeight: DesignTokens.fontWeightMedium,
          ),
          hintStyle: controlText.copyWith(
            color: cs.onSurfaceVariant.withValues(alpha: 0.68),
            fontWeight: DesignTokens.fontWeightRegular,
          ),
          border: inputBorder(subtleBorder),
          enabledBorder: inputBorder(subtleBorder),
          disabledBorder: inputBorder(
            cs.outlineVariant.withValues(alpha: isDark ? 0.045 : 0.06),
          ),
          focusedBorder: inputBorder(
            cs.primary.withValues(alpha: isDark ? 0.16 : 0.12),
            width: 0.4,
          ),
          errorBorder: inputBorder(cs.error.withValues(alpha: 0.24)),
          focusedErrorBorder: inputBorder(
            cs.error.withValues(alpha: 0.30),
            width: 0.4,
          ),
        ),
        listTileTheme: theme.listTileTheme.copyWith(
          dense: true,
          titleTextStyle: controlText.copyWith(color: cs.onSurface),
          subtitleTextStyle: labelText.copyWith(color: cs.onSurfaceVariant),
        ),
        dropdownMenuTheme: theme.dropdownMenuTheme.copyWith(
          textStyle: controlText.copyWith(color: cs.onSurface),
          inputDecorationTheme: theme.inputDecorationTheme.copyWith(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
          ),
        ),
        popupMenuTheme: theme.popupMenuTheme.copyWith(
          textStyle: controlText.copyWith(color: cs.onSurface),
          labelTextStyle: WidgetStatePropertyAll(
            controlText.copyWith(color: cs.onSurface),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            textStyle: buttonText,
            minimumSize: const Size(0, DesignTokens.controlMinHeight),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            textStyle: buttonText,
            minimumSize: const Size(0, DesignTokens.controlMinHeight),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            textStyle: buttonText,
            minimumSize: const Size(0, DesignTokens.controlMinHeight),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.padded,
            side: BorderSide(color: subtleBorder, width: 0.4),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: appSecondaryFilledButtonStyle(
            context,
          ).copyWith(textStyle: WidgetStatePropertyAll(buttonText)),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            textStyle: WidgetStatePropertyAll(buttonText),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return cs.onSurface.withValues(alpha: 0.38);
              }
              if (states.contains(WidgetState.selected)) {
                return selectedControlForeground;
              }
              return cs.onSurface;
            }),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return selectedControlBackground;
              }
              return Colors.transparent;
            }),
            side: WidgetStateProperty.resolveWith((states) {
              final color = states.contains(WidgetState.selected)
                  ? cs.primary.withValues(alpha: isDark ? 0.34 : 0.30)
                  : subtleBorder;
              return BorderSide(color: color, width: 0.4);
            }),
            minimumSize: const WidgetStatePropertyAll(
              Size(0, DesignTokens.controlMinHeight),
            ),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
        ),
        chipTheme: theme.chipTheme.copyWith(
          labelStyle: labelText.copyWith(color: cs.onSurface),
          secondaryLabelStyle: labelText.copyWith(
            color: selectedControlForeground,
          ),
          selectedColor: selectedControlBackground,
          checkmarkColor: selectedControlIcon,
          iconTheme: IconThemeData(size: 16, color: selectedControlIcon),
          side: BorderSide(color: subtleBorder, width: 0.4),
        ),
      ),
      child: DefaultTextStyle.merge(style: controlText, child: child),
    );
  }
}

/// Readable account forms, with room for touch input and multiline helpers.
class AppFormFieldTheme extends StatelessWidget {
  final Widget child;

  const AppFormFieldTheme({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AppSecondaryControlTheme(
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final cs = theme.colorScheme;
          final inputText = (theme.textTheme.bodyLarge ?? const TextStyle())
              .copyWith(fontSize: DesignTokens.fontSizeMd, height: 1.5);
          final labelText = inputText.copyWith(
            fontSize: DesignTokens.fontSizeSecondary,
            height: 1.4,
            color: cs.onSurfaceVariant,
          );
          OutlineInputBorder border(Color color, {double width = 1}) =>
              OutlineInputBorder(
                borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
                borderSide: BorderSide(color: color, width: width),
              );
          final decoration = theme.inputDecorationTheme.copyWith(
            isDense: false,
            constraints: const BoxConstraints(
              minHeight: DesignTokens.formFieldMinHeight,
            ),
            contentPadding: const EdgeInsets.all(DesignTokens.spaceLg),
            prefixIconConstraints: const BoxConstraints.tightFor(
              width: DesignTokens.formFieldMinHeight,
              height: DesignTokens.formFieldMinHeight,
            ),
            suffixIconConstraints: const BoxConstraints.tightFor(
              width: DesignTokens.formFieldMinHeight,
              height: DesignTokens.formFieldMinHeight,
            ),
            labelStyle: labelText,
            // InputDecorator scales floating labels to 75% of this size.
            floatingLabelStyle: labelText.copyWith(
              fontSize: DesignTokens.fontSizeSecondary / 0.75,
              color: cs.primary,
            ),
            hintStyle: inputText.copyWith(color: cs.onSurfaceVariant),
            helperStyle: labelText,
            helperMaxLines: 3,
            errorMaxLines: 3,
            alignLabelWithHint: true,
            enabledBorder: border(cs.outlineVariant.withValues(alpha: 0.55)),
            focusedBorder: border(
              cs.primary.withValues(alpha: 0.80),
              width: 1.5,
            ),
            errorBorder: border(cs.error),
            focusedErrorBorder: border(cs.error, width: 1.5),
          );
          return Theme(
            data: theme.copyWith(
              textTheme: theme.textTheme.copyWith(
                bodyLarge: inputText.copyWith(color: cs.onSurface),
                titleMedium: inputText.copyWith(color: cs.onSurface),
              ),
              inputDecorationTheme: decoration,
              dropdownMenuTheme: theme.dropdownMenuTheme.copyWith(
                textStyle: inputText.copyWith(color: cs.onSurface),
                inputDecorationTheme: decoration,
              ),
            ),
            child: child,
          );
        },
      ),
    );
  }
}

class AppSecondaryMenuText extends StatelessWidget {
  final String text;
  final Color? color;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const AppSecondaryMenuText(
    this.text, {
    super.key,
    this.color,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      text,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      style: appSecondaryMenuItemTextStyle(context).copyWith(
        color: color ?? cs.onSurface,
        fontWeight: DesignTokens.fontWeightMedium,
      ),
    );
  }
}

class AppSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;
  final TextStyle? titleStyle;
  final TextStyle? actionTextStyle;
  final CrossAxisAlignment crossAxisAlignment;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 12, 8),
    this.titleStyle,
    this.actionTextStyle,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final titleColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style:
              titleStyle ??
              appSecondaryMenuItemTextStyle(context).copyWith(
                color: cs.onSurface,
                fontSize: DesignTokens.fontSizeSection,
              ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: appSecondaryControlLabelStyle(
              context,
            ).copyWith(color: cs.onSurface.withValues(alpha: 0.62)),
          ),
        ],
      ],
    );
    final action = onAction == null || actionLabel == null
        ? null
        : TextButton.icon(
            onPressed: onAction,
            icon: Icon(actionIcon ?? Icons.chevron_right, size: 16),
            label: Text(
              actionLabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: cs.primary,
              textStyle:
                  actionTextStyle ??
                  theme.textTheme.labelMedium?.copyWith(
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          );
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (action == null) return titleColumn;
          if (constraints.maxWidth < 340) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleColumn,
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                    child: action,
                  ),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: crossAxisAlignment,
            children: [
              Expanded(child: titleColumn),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: (constraints.maxWidth * 0.42).clamp(96.0, 180.0),
                ),
                child: action,
              ),
            ],
          );
        },
      ),
    );
  }
}

class AppStatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool filled;
  final EdgeInsetsGeometry padding;
  final double maxWidth;

  const AppStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.maxWidth = 180,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = filled ? color : color.withValues(alpha: 0.12);
    final fg = _appReadableForeground(bg, filled ? Colors.white : color);
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
        border: filled
            ? null
            : Border.all(color: color.withValues(alpha: 0.12), width: 0.45),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: DesignTokens.fontWeightStrong,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppInfoBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final String? title;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const AppInfoBanner({
    super.key,
    required this.icon,
    required this.message,
    required this.color,
    this.title,
    this.onTap,
    this.padding = const EdgeInsets.all(12),
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AppSurfaceCard(
      margin: margin,
      padding: padding,
      onTap: onTap,
      color: color.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.16 : 0.08,
      ),
      border: Border.all(color: color.withValues(alpha: 0.10), width: 0.45),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null && title!.isNotEmpty) ...[
                  Text(
                    title!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: DesignTokens.fontWeightStrong,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.72),
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String? unit;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  /// null 时取主题观感档位（默认主题 iOS 控件档 12，其余主题 radiusMd 10）。
  final BorderRadius? borderRadius;
  final TextStyle? valueStyle;
  final TextStyle? unitStyle;
  final TextStyle? titleStyle;
  final double iconBoxSize;
  final double iconSize;

  const AppMetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.unit,
    this.onTap,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.fromLTRB(12, 10, 12, 10),
    this.borderRadius,
    this.valueStyle,
    this.unitStyle,
    this.titleStyle,
    this.iconBoxSize = 28,
    this.iconSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceStyle = appSurfaceStyleOf(context);
    final effectiveRadius =
        borderRadius ??
        (surfaceStyle == null
            ? _standardMetricTileRadius
            : BorderRadius.circular(surfaceStyle.smallTileRadius));
    // 液态玻璃档：小卡与卡面（AppSurfaceCard）、Material Card 共用同一
    // 玻璃填充档（cardFillColor = 白@glassFillLightAlpha），三类卡面质感
    // 一致。其余主题未注册 cardFillColor（null）、暗色无玻璃档，均维持
    // 既有实底档，观感不变。
    final fill =
        (!isDark ? surfaceStyle?.cardFillColor : null) ??
        (isDark
            ? cs.surface.withValues(alpha: 0.68)
            : cs.surface.withValues(alpha: 0.85));
    // 玻璃体系统一：亮色下小卡描边/阴影与卡面、Material Card 同走
    // AppSurfaceStyle 玻璃档（cardBorder / cardShadow），三类卡面同屏
    // 同质感；未注册主题与暗色维持既有灰描边、无阴影档，观感不变。
    final tileBorder =
        (!isDark ? surfaceStyle?.cardBorder : null) ??
        Border.all(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.15 : 0.18),
          width: 0.5,
        );
    final tileShadow = (!isDark ? surfaceStyle?.cardShadow : null) ?? const [];
    final tile = Ink(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: effectiveRadius,
        border: tileBorder,
        boxShadow: tileShadow,
      ),
      child: Padding(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: iconBoxSize,
              height: iconBoxSize,
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              ),
              child: Icon(icon, color: color, size: iconSize),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        titleStyle ??
                        theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.62),
                          fontWeight: DesignTokens.fontWeightStrong,
                          height: 1.1,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: value,
                          style:
                              valueStyle ??
                              theme.textTheme.titleMedium?.copyWith(
                                fontSize: DesignTokens.fontSizeMd,
                                fontWeight: DesignTokens.fontWeightStrong,
                                color: cs.onSurface,
                                height: 1.1,
                              ),
                        ),
                        if (unit != null && unit!.isNotEmpty)
                          TextSpan(
                            text: ' $unit',
                            style:
                                unitStyle ??
                                theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  fontWeight: DesignTokens.fontWeightStrong,
                                  color: cs.onSurface.withValues(alpha: 0.62),
                                  height: 1.08,
                                ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        child: onTap == null
            ? tile
            : InkWell(onTap: onTap, borderRadius: effectiveRadius, child: tile),
      ),
    );
  }
}

class AppActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const AppActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 14, 12),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        fontWeight: DesignTokens.fontWeightStrong,
                        color: cs.onSurface,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: cs.onSurface.withValues(alpha: 0.38),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppSettingsSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final Border? border;
  final double elevation;

  const AppSettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.margin = EdgeInsets.zero,
    this.padding = const EdgeInsets.all(16),
    this.border,
    this.elevation = 0,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceStyle = appSurfaceStyleOf(context);
    return AppSurfaceCard(
      margin: margin,
      padding: padding,
      border: border,
      elevation: elevation,
      // 默认主题 iOS 档取卡片圆角 16，其余主题沿用既有 8。
      borderRadius: surfaceStyle == null
          ? _standardSettingsSectionRadius
          : BorderRadius.circular(surfaceStyle.cardRadius),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: title,
            subtitle: subtitle,
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class AppSettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const AppSettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget trailingWidget(double maxWidth) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          minHeight: DesignTokens.controlMinHeight,
        ),
        child: Align(
          alignment: Alignment.centerRight,
          widthFactor: 1,
          heightFactor: 1,
          child:
              trailing ??
              Icon(
                Icons.chevron_right,
                size: DesignTokens.controlIconSize,
                color: cs.onSurface.withValues(alpha: 0.38),
              ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        child: Padding(
          padding: padding,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const leadingWidth = 34.0;
              const leadingGap = DesignTokens.spaceMd;
              final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
              final stackAction =
                  trailing != null &&
                  (constraints.maxWidth < 420 ||
                      MediaQuery.textScalerOf(context).scale(16) > 20);
              final leading = Container(
                width: leadingWidth,
                height: leadingWidth,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(
                    DesignTokens.radiusControl,
                  ),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: DesignTokens.controlIconSize,
                ),
              );
              final text = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: appSecondaryMenuItemTextStyle(
                      context,
                    ).copyWith(color: cs.onSurface),
                  ),
                  if (hasSubtitle) ...[
                    const SizedBox(height: DesignTokens.spaceXs),
                    Text(
                      subtitle!,
                      style: appSecondaryControlLabelStyle(
                        context,
                      ).copyWith(color: cs.onSurface.withValues(alpha: 0.62)),
                    ),
                  ],
                ],
              );
              final row = Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  leading,
                  const SizedBox(width: leadingGap),
                  Expanded(child: text),
                  if (!stackAction) ...[
                    const SizedBox(width: DesignTokens.spaceSm),
                    trailingWidget(
                      trailing == null ? 24 : constraints.maxWidth * 0.45,
                    ),
                  ],
                ],
              );
              return ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: DesignTokens.controlMinHeight,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    row,
                    if (stackAction)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: leadingWidth + leadingGap,
                          top: DesignTokens.spaceSm,
                        ),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: trailingWidget(
                            (constraints.maxWidth - leadingWidth - leadingGap)
                                .clamp(0.0, constraints.maxWidth),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class AppListTileCard extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry contentPadding;
  final bool dense;
  final bool isThreeLine;
  final Border? border;
  final double elevation;

  const AppListTileCard({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.margin = EdgeInsets.zero,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 4,
    ),
    this.dense = false,
    this.isThreeLine = false,
    this.border,
    this.elevation = 0,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceStyle = appSurfaceStyleOf(context);
    return AppSurfaceCard(
      margin: margin,
      padding: EdgeInsets.zero,
      onTap: onTap,
      border: border,
      elevation: elevation,
      child: Material(
        color: Colors.transparent,
        borderRadius: surfaceStyle == null
            ? _standardCardRadius
            : BorderRadius.circular(surfaceStyle.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: dense,
          isThreeLine: isThreeLine,
          contentPadding: contentPadding,
          leading: leading,
          title: title,
          subtitle: subtitle,
          trailing: trailing,
        ),
      ),
    );
  }
}

class AppSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry padding;

  const AppSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: appSecondaryMenuItemTextStyle(
                        context,
                      ).copyWith(color: cs.onSurface),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: appSecondaryControlLabelStyle(
                          context,
                        ).copyWith(color: cs.onSurface.withValues(alpha: 0.62)),
                      ),
                    ],
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

Future<T?> showAppModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool shiftForKeyboard = true,
}) {
  _beginDropdownKeyboardDismiss(context);
  return showModalBottomSheet<T>(
    context: context,
    sheetAnimationStyle: AppMotion.overlayStyle(context),
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    requestFocus: false,
    useSafeArea: true,
    // 路由层的 Material 会和 AppModalSheet 自己的卡片叠加：它把
    // bottomSheetTheme.showDragHandle 默认打开后，会在卡片外额外占用
    // kMinInteractiveDimension 高度并再画一个拖动手柄，于是出现
    // 「卡片上方浮着一个拖动条」；modalElevation: 4 又让它的投影比实际
    // 卡片更大。这里把这两项都关掉，拖动条与阴影统一交给 AppModalSheet。
    showDragHandle: false,
    elevation: 0,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final child = builder(sheetContext);
      if (shiftForKeyboard) return child;
      return MediaQuery.removeViewInsets(
        context: sheetContext,
        removeBottom: true,
        child: child,
      );
    },
  );
}

class AppDialog extends StatelessWidget {
  final Widget title;
  final Widget? content;
  final List<Widget> actions;
  final Widget? icon;
  final EdgeInsetsGeometry? contentPadding;
  final double maxWidth;
  final bool shiftForKeyboard;

  const AppDialog({
    super.key,
    required this.title,
    this.content,
    this.actions = const [],
    this.icon,
    this.contentPadding,
    this.maxWidth = 420,
    this.shiftForKeyboard = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final media = MediaQuery.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final availableHeight = (media.size.height - viewInsets.bottom).clamp(
      280.0,
      media.size.height,
    );
    final horizontalInset = media.size.width < 360 ? 12.0 : 20.0;
    final availableWidth = media.size.width - horizontalInset * 2;
    final effectiveMaxWidth = availableWidth.isFinite
        ? availableWidth.clamp(0.0, maxWidth).toDouble()
        : maxWidth;
    final effectiveMinWidth = effectiveMaxWidth < 320
        ? effectiveMaxWidth
        : 320.0;
    final dialog = AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: 24,
      ),
      constraints: BoxConstraints(
        minWidth: effectiveMinWidth,
        maxWidth: effectiveMaxWidth,
        maxHeight: availableHeight * 0.86,
      ),
      scrollable: true,
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding:
          contentPadding ?? const EdgeInsets.fromLTRB(24, 16, 24, 8),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconTheme(
                data: IconThemeData(color: cs.primary, size: 20),
                child: icon!,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: DefaultTextStyle(
              style: (theme.textTheme.titleMedium ?? const TextStyle())
                  .copyWith(
                    color: cs.onSurface,
                    fontSize: DesignTokens.fontSizeBody,
                    fontWeight: DesignTokens.fontWeightStrong,
                    height: 1.2,
                  ),
              child: title,
            ),
          ),
        ],
      ),
      content: content == null
          ? null
          : ConstrainedBox(
              constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
              child: AppSecondaryControlTheme(child: content!),
            ),
      actions: actions.isEmpty
          ? null
          : [
              AppSecondaryControlTheme(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ),
            ],
    );
    final keyboardLift = viewInsets.bottom <= 0
        ? 0.0
        : (viewInsets.bottom * 0.42).clamp(56.0, 128.0).toDouble();
    final scopedDialog = MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: dialog,
    );
    if (!shiftForKeyboard) return scopedDialog;

    return AnimatedPadding(
      duration: AppMotion.feedback(context),
      curve: AppMotion.enterCurve,
      padding: EdgeInsets.only(bottom: keyboardLift),
      child: Align(
        alignment: viewInsets.bottom > 0
            ? const Alignment(0, -0.18)
            : Alignment.center,
        child: scopedDialog,
      ),
    );
  }
}

class AppModalSheet extends StatefulWidget {
  final String? title;
  final String? subtitle;
  final Widget child;
  final List<Widget> leadingActions;
  final List<Widget> actions;
  final ScrollController? scrollController;
  final bool scrollable;
  final bool showDragHandle;
  final EdgeInsetsGeometry padding;
  final double maxWidth;
  final bool shiftForKeyboard;

  const AppModalSheet({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
    this.leadingActions = const [],
    this.actions = const [],
    this.scrollController,
    this.scrollable = true,
    this.showDragHandle = true,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 18),
    this.maxWidth = DesignTokens.creationFormMaxWidth,
    this.shiftForKeyboard = true,
  });

  @override
  State<AppModalSheet> createState() => _AppModalSheetState();
}

class _AppModalSheetState extends State<AppModalSheet> {
  bool _expanded = false;
  bool _startedAtTop = false;
  bool _changedDuringDrag = false;
  double _dragDistance = 0;
  double _wheelDistance = 0;
  ScrollMetrics? _metrics;
  PointerScrollEvent? _pointerScrollEvent;
  bool _pointerStartedAtTop = false;

  bool get _atTop => (_metrics?.extentBefore ?? 0) <= 0.5;

  void _setExpanded(bool value) {
    if (_expanded == value) return;
    setState(() => _expanded = value);
  }

  bool _onScroll(ScrollNotification notification) {
    // 只跟随内容的第一层竖向滚动，忽略推荐项横滑、输入框内部滚动。
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    _metrics = notification.metrics;
    if (notification is ScrollStartNotification) {
      _startedAtTop = _atTop;
      _changedDuringDrag = false;
      _dragDistance = 0;
    }
    final delta = switch (notification) {
      ScrollUpdateNotification(:final scrollDelta) => scrollDelta,
      OverscrollNotification(:final overscroll) => overscroll,
      _ => null,
    };
    if (delta == null) return false;
    final dragDetails = switch (notification) {
      ScrollUpdateNotification(:final dragDetails) => dragDetails,
      OverscrollNotification(:final dragDetails) => dragDetails,
      _ => null,
    };
    if (dragDetails == null) {
      if (_pointerScrollEvent != null) {
        _onWheelDelta(delta, canCollapse: _pointerStartedAtTop && _atTop);
      }
      return false;
    }
    // 程序定位、键盘避让和惯性滚动不能切换弹窗高度。
    if (_changedDuringDrag) return false;
    // 弹性滚动会缩小内容位移；阈值按手指位移，避免桌面短列表拉不回。
    final dragDelta =
        axisDirectionIsReversed(notification.metrics.axisDirection)
        ? dragDetails.delta.dy
        : -dragDetails.delta.dy;
    if (!_expanded && dragDelta > 0) {
      _dragDistance += dragDelta;
    } else if (_expanded && _startedAtTop && _atTop && dragDelta < 0) {
      _dragDistance -= dragDelta;
    } else {
      _dragDistance = 0;
    }
    if (_dragDistance >= DesignTokens.modalSheetDragThreshold) {
      _changedDuringDrag = true;
      _setExpanded(!_expanded);
    }
    return false;
  }

  bool _onMetrics(ScrollMetricsNotification notification) {
    if (notification.depth == 0 && notification.metrics.axis == Axis.vertical) {
      _metrics = notification.metrics;
    }
    return false;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dy.abs() <= event.scrollDelta.dx.abs()) {
      return;
    }
    // pointerScroll 会先更新 pixels 再发 ScrollStart，须保存事件前的位置。
    _pointerStartedAtTop = _atTop;
    _pointerScrollEvent = event;
    scheduleMicrotask(() {
      if (_pointerScrollEvent == event) _pointerScrollEvent = null;
    });
    // 内层时间滚轮等先消费事件；只有没人接收的边界滚动才交给弹窗。
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _onWheelDelta(event.scrollDelta.dy, canCollapse: _atTop);
    });
  }

  void _onWheelDelta(double delta, {required bool canCollapse}) {
    if (!_expanded && delta > 0) {
      _wheelDistance = _wheelDistance.clamp(0.0, double.infinity) + delta;
      if (_wheelDistance >= DesignTokens.modalSheetDragThreshold) {
        _wheelDistance = 0;
        _setExpanded(true);
      }
    } else if (_expanded && canCollapse && delta < 0) {
      _wheelDistance =
          _wheelDistance.clamp(double.negativeInfinity, 0.0) + delta;
      if (-_wheelDistance >= DesignTokens.modalSheetDragThreshold) {
        _wheelDistance = 0;
        _setExpanded(false);
      }
    } else {
      _wheelDistance = 0;
    }
  }

  void _onHandleDrag(DragUpdateDetails details) {
    if (!_atTop || details.delta.dy <= 0) {
      _dragDistance = 0;
      return;
    }
    _dragDistance += details.delta.dy;
    if (_dragDistance >= DesignTokens.modalSheetDragThreshold) {
      _setExpanded(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final subtitle = widget.subtitle;
    final child = widget.child;
    final leadingActions = widget.leadingActions;
    final actions = widget.actions;
    final scrollController = widget.scrollController;
    final scrollable = widget.scrollable;
    final showDragHandle = widget.showDragHandle;
    final padding = widget.padding;
    final maxWidth = widget.maxWidth;
    final shiftForKeyboard = widget.shiftForKeyboard;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final scrollBehavior = ScrollConfiguration.of(context);
    final media = MediaQuery.of(context);
    final viewInsets = shiftForKeyboard ? media.viewInsets : EdgeInsets.zero;
    final availableHeight = (media.size.height - viewInsets.bottom).clamp(
      0.0,
      media.size.height,
    );
    final resolvedPadding = padding.resolve(Directionality.of(context));
    // 卡片现在贴住屏幕底边（不再让 SafeArea 在下方留白），所以底部安全区
    // 要由内部 padding 自己补上，否则全面屏上内容会压到系统手势条。
    final bottomSafeInset = media.padding.bottom;
    final sheetPadding = EdgeInsets.fromLTRB(
      resolvedPadding.left,
      resolvedPadding.top,
      resolvedPadding.right,
      resolvedPadding.bottom + bottomSafeInset,
    );

    final children = <Widget>[
      if (showDragHandle) ...[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: _expanded ? (_) => _dragDistance = 0 : null,
          onVerticalDragUpdate: _expanded ? _onHandleDrag : null,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant.withValues(
                    alpha: isDark ? 0.28 : 0.34,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ),
      ],
      if (title != null || subtitle != null) ...[
        AppSectionHeader(
          title: title ?? '',
          subtitle: subtitle,
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 12),
      ],
      // 自带 ListView/GridView 的内容必须拿到扣除标题和操作区后的高度，
      // 否则缩小卡片后仍按原始固定高度布局，底部操作会溢出。
      if (!scrollable && scrollController == null)
        Flexible(
          fit: _expanded ? FlexFit.tight : FlexFit.loose,
          child: ScrollConfiguration(
            behavior: scrollBehavior.copyWith(
              physics: AlwaysScrollableScrollPhysics(
                parent: scrollBehavior.getScrollPhysics(context),
              ),
            ),
            child: AppSecondaryControlTheme(child: child),
          ),
        )
      else
        AppSecondaryControlTheme(child: child),
      if (leadingActions.isNotEmpty || actions.isNotEmpty) ...[
        const SizedBox(height: 14),
        AppSecondaryControlTheme(
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [...leadingActions, ...actions],
          ),
        ),
      ],
    ];

    Widget body;
    if (scrollController != null) {
      body = ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: sheetPadding,
        children: children,
      );
    } else if (scrollable) {
      body = SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: sheetPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
    } else {
      body = Padding(
        padding: sheetPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
    }

    body = Listener(
      onPointerSignal: _onPointerSignal,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onMetrics,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: body,
        ),
      ),
    );
    final initialConstraints = BoxConstraints(
      minHeight: availableHeight * DesignTokens.modalSheetMinHeightFactor,
      maxHeight: availableHeight * DesignTokens.modalSheetMaxHeightFactor,
    );

    // 卡片要贴住屏幕底边：bottom 交给内部 padding 处理。若这里保留
    // bottom: true，卡片会在安全区之上，而路由层的形状/阴影画在下面，
    // 于是弹窗与它的阴影之间会出现一条错位的缝。
    return SafeArea(
      top: false,
      bottom: false,
      child: AnimatedPadding(
        duration: AppMotion.feedback(context),
        curve: AppMotion.enterCurve,
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          // 不占用卡片上方的透明区域，让点击交给路由的遮罩关闭。
          heightFactor: 1,
          widthFactor: 1,
          child: AnimatedContainer(
            duration: AppMotion.transition(context),
            curve: AppMotion.enterCurve,
            constraints:
                (_expanded
                        ? BoxConstraints.tightFor(height: availableHeight)
                        : initialConstraints)
                    .copyWith(maxWidth: maxWidth),
            child: SizedBox(
              width: double.infinity,
              child: Material(
                color: cs.surface,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(
                      appSurfaceStyleOf(context)?.sheetTopRadius ??
                          _standardSheetTopRadius,
                    ),
                  ),
                ),
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppPickerOption<T> {
  final T value;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? color;
  final bool enabled;

  const AppPickerOption({
    required this.value,
    required this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.enabled = true,
  });
}

class AppPickerSheet<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<AppPickerOption<T>> options;
  final T? selectedValue;
  final ValueChanged<T>? onSelected;
  final Widget? empty;
  final bool closeOnSelect;

  const AppPickerSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.options,
    this.selectedValue,
    this.onSelected,
    this.empty,
    this.closeOnSelect = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppModalSheet(
      title: title,
      subtitle: subtitle,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final cs = theme.colorScheme;
          return options.isEmpty
              ? (empty ??
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          '暂无可选项',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.62),
                          ),
                        ),
                      ),
                    ))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final option in options) _optionTile(context, option),
                  ],
                );
        },
      ),
    );
  }

  Widget _optionTile(BuildContext context, AppPickerOption<T> option) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = selectedValue == option.value;
    final accent = option.color ?? cs.primary;
    final borderColor = selected
        ? accent.withValues(alpha: 0.22)
        : cs.outlineVariant.withValues(alpha: 0.12);
    final textColor = option.enabled
        ? cs.onSurface
        : cs.onSurface.withValues(alpha: 0.38);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? accent.withValues(alpha: 0.08)
            : cs.surfaceContainerHighest.withValues(alpha: 0.22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor, width: 0.45),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          enabled: option.enabled,
          dense: true,
          minLeadingWidth: 30,
          horizontalTitleGap: 10,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 2,
          ),
          leading: option.icon == null
              ? null
              : Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(option.icon, color: accent, size: 17),
                ),
          title: Text(
            option.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: appSecondaryControlTextStyle(context).copyWith(
              color: textColor,
              fontWeight: DesignTokens.fontWeightStrong,
            ),
          ),
          subtitle: option.subtitle == null
              ? null
              : Text(
                  option.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appSecondaryControlLabelStyle(context).copyWith(
                    color: cs.onSurface.withValues(
                      alpha: option.enabled ? 0.62 : 0.38,
                    ),
                  ),
                ),
          trailing: selected
              ? Icon(Icons.check_circle, color: accent, size: 18)
              : null,
          onTap: option.enabled
              ? () {
                  onSelected?.call(option.value);
                  if (closeOnSelect) {
                    Navigator.pop<T>(context, option.value);
                  }
                }
              : null,
        ),
      ),
    );
  }
}

String _dropdownItemLabel<T>(DropdownMenuItem<T> item) {
  final widgetText = _dropdownWidgetText(item.child);
  if (widgetText != null && widgetText.trim().isNotEmpty) {
    return widgetText.trim();
  }
  final value = item.value;
  return value == null ? '未设置' : value.toString();
}

String? _dropdownWidgetText(Widget widget) {
  if (widget is Text) {
    final data = widget.data;
    if (data != null && data.trim().isNotEmpty) return data.trim();
    final spanText = widget.textSpan?.toPlainText();
    if (spanText != null && spanText.trim().isNotEmpty) {
      return spanText.trim();
    }
    return null;
  }
  if (widget is RichText) {
    final text = widget.text.toPlainText();
    return text.trim().isEmpty ? null : text.trim();
  }
  if (widget is Row || widget is Column || widget is Wrap) {
    final children = switch (widget) {
      Row(:final children) => children,
      Column(:final children) => children,
      Wrap(:final children) => children,
      _ => const <Widget>[],
    };
    final parts = <String>[];
    for (final child in children) {
      final text = _dropdownWidgetText(child);
      if (text != null && text.trim().isNotEmpty) parts.add(text.trim());
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }
  if (widget is Flexible) return _dropdownWidgetText(widget.child);
  if (widget is Padding && widget.child != null) {
    return _dropdownWidgetText(widget.child!);
  }
  if (widget is Align && widget.child != null) {
    return _dropdownWidgetText(widget.child!);
  }
  if (widget is SizedBox && widget.child != null) {
    return _dropdownWidgetText(widget.child!);
  }
  if (widget is ConstrainedBox && widget.child != null) {
    return _dropdownWidgetText(widget.child!);
  }
  if (widget is DecoratedBox && widget.child != null) {
    return _dropdownWidgetText(widget.child!);
  }
  return null;
}

Future<void> _hideKeyboardBeforePicker(BuildContext context) async {
  final hadKeyboard = _effectiveDropdownBottomInset(context) > 1.0;
  _beginDropdownKeyboardDismiss(context);
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  if (!context.mounted) return;
  await _waitForDropdownInsetsToSettle(context);

  if (!context.mounted) return;
  if (hadKeyboard) {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!context.mounted) return;
    await _waitForDropdownAnchorLayoutToSettle(context);
  }
  if (!context.mounted) return;
  if (!_dropdownAnchorIsVisible(context)) {
    await Scrollable.ensureVisible(
      context,
      duration: Duration.zero,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
  }
  if (!context.mounted) return;
  await _waitForDropdownAnchorLayoutToSettle(context);
  await WidgetsBinding.instance.endOfFrame;
}

Future<void> _waitForDropdownInsetsToSettle(BuildContext context) async {
  double? previousInset;
  var closedStableFrames = 0;
  var unchangedFrames = 0;
  for (var i = 0; i < 18; i += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 32));
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;

    final inset = _effectiveDropdownBottomInset(context);
    if (inset <= 1.0) {
      closedStableFrames += 1;
      if (closedStableFrames >= 3) {
        await WidgetsBinding.instance.endOfFrame;
        return;
      }
    } else {
      closedStableFrames = 0;
    }

    if (previousInset != null && (inset - previousInset).abs() <= 0.5) {
      unchangedFrames += 1;
      if (unchangedFrames >= 4) return;
    } else {
      unchangedFrames = 0;
    }
    previousInset = inset;
  }
}

void _beginDropdownKeyboardDismiss(BuildContext context) {
  FocusScope.of(context, createDependency: false).unfocus();
  FocusManager.instance.primaryFocus?.unfocus();
  SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
}

double _effectiveDropdownBottomInset(BuildContext context) {
  final mediaInset = MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0.0;
  final view = View.maybeOf(context);
  final viewInset = view == null
      ? 0.0
      : view.viewInsets.bottom / view.devicePixelRatio;
  return viewInset > mediaInset ? viewInset : mediaInset;
}

RenderBox? _dropdownOverlayBox(BuildContext context) {
  final overlay = Navigator.of(context).overlay?.context.findRenderObject();
  if (overlay is! RenderBox || !overlay.attached || !overlay.hasSize) {
    return null;
  }
  return overlay;
}

Rect? _dropdownAnchorRectInOverlay(BuildContext context) {
  final box = context.findRenderObject();
  final overlay = _dropdownOverlayBox(context);
  if (box is! RenderBox || overlay == null || !box.attached || !box.hasSize) {
    return null;
  }
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final bottomRight = box.localToGlobal(
    box.size.bottomRight(Offset.zero),
    ancestor: overlay,
  );
  return Rect.fromPoints(topLeft, bottomRight);
}

Future<void> _waitForDropdownAnchorLayoutToSettle(BuildContext context) async {
  Rect? previous;
  var stableFrames = 0;
  for (var i = 0; i < 14; i += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;
    final rect = _dropdownAnchorRectInOverlay(context);
    if (rect == null) return;
    final stable =
        previous != null &&
        (rect.topLeft - previous.topLeft).distance <= 0.5 &&
        (rect.bottomRight - previous.bottomRight).distance <= 0.5;
    if (stable) {
      stableFrames += 1;
      if (stableFrames >= 2) return;
    } else {
      stableFrames = 0;
    }
    previous = rect;
  }
}

bool _dropdownAnchorIsVisible(BuildContext context) {
  final rect = _dropdownAnchorRectInOverlay(context);
  final overlay = _dropdownOverlayBox(context);
  if (rect == null || overlay == null) {
    return true;
  }
  final media = MediaQuery.maybeOf(context);
  if (media == null) return true;
  final visibleTop = media.padding.top + 8;
  final visibleBottom = overlay.size.height - media.viewInsets.bottom - 8;
  return rect.top >= visibleTop && rect.bottom <= visibleBottom;
}

Future<T?> _showAnchoredDropdownMenu<T>({
  required BuildContext context,
  required List<DropdownMenuItem<T>> items,
  required T? selectedValue,
  required double? menuMaxHeight,
  required bool shiftForKeyboard,
}) async {
  final fieldBox = context.findRenderObject() as RenderBox?;
  final overlay =
      Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
  if (fieldBox == null ||
      overlay == null ||
      !fieldBox.attached ||
      !overlay.attached ||
      !fieldBox.hasSize ||
      !overlay.hasSize) {
    return null;
  }

  const menuPadding = EdgeInsets.symmetric(vertical: 8);
  const itemContentPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 7);
  final controlText = appSecondaryControlTextStyle(context);
  final scaledTextHeight =
      MediaQuery.textScalerOf(context).scale(controlText.fontSize!) *
      controlText.height!;
  final itemHeight = (scaledTextHeight + itemContentPadding.vertical)
      .clamp(36.0, double.infinity)
      .toDouble();
  // Match the rendered rows and padding: short menus must not reserve the full
  // height limit above the field and leave an empty gap below their contents.
  final contentHeight = items.length * itemHeight + menuPadding.vertical;
  final preferredMaxHeight = contentHeight
      .clamp(0.0, menuMaxHeight ?? 320.0)
      .toDouble();

  _DropdownMenuPosition positionForCurrentLayout() {
    final currentFieldBox = context.findRenderObject() as RenderBox?;
    final currentOverlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    final activeFieldBox = currentFieldBox?.attached == true
        ? currentFieldBox!
        : fieldBox;
    final activeOverlay = currentOverlay?.attached == true
        ? currentOverlay!
        : overlay;
    final fieldTopLeft = activeFieldBox.localToGlobal(
      Offset.zero,
      ancestor: activeOverlay,
    );
    final fieldBottomRight = activeFieldBox.localToGlobal(
      activeFieldBox.size.bottomRight(Offset.zero),
      ancestor: activeOverlay,
    );
    final bottomInset = shiftForKeyboard
        ? _effectiveDropdownBottomInset(context)
        : 0.0;
    final safeTop = MediaQuery.paddingOf(context).top + 8;
    final safeBottom = (activeOverlay.size.height - bottomInset - 8).clamp(
      safeTop + 48,
      activeOverlay.size.height,
    );
    final belowSpace = safeBottom - fieldBottomRight.dy - 6;
    final aboveSpace = fieldTopLeft.dy - safeTop - 6;
    final openAbove =
        belowSpace < preferredMaxHeight && aboveSpace > belowSpace;
    final availableHeight = (openAbove ? aboveSpace : belowSpace)
        .clamp(preferredMaxHeight.clamp(0.0, 96.0), preferredMaxHeight)
        .toDouble();
    final unclampedTop = openAbove
        ? fieldTopLeft.dy - availableHeight - 6
        : fieldBottomRight.dy + 6;
    final maxTop = (safeBottom - availableHeight).clamp(safeTop, safeBottom);
    final menuTop = unclampedTop.clamp(safeTop, maxTop).toDouble();
    final menuBottom = (activeOverlay.size.height - menuTop - availableHeight)
        .clamp(0.0, activeOverlay.size.height)
        .toDouble();
    final menuLeft = fieldTopLeft.dx.clamp(0.0, activeOverlay.size.width);
    final menuRight = (activeOverlay.size.width - fieldBottomRight.dx).clamp(
      0.0,
      activeOverlay.size.width,
    );
    return _DropdownMenuPosition(
      rect: RelativeRect.fromLTRB(menuLeft, menuTop, menuRight, menuBottom),
      height: availableHeight,
    );
  }

  final initialPosition = positionForCurrentLayout();
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final selectedColor = cs.primary.withValues(alpha: 0.10);

  return showMenu<T>(
    context: context,
    requestFocus: false,
    menuPadding: menuPadding,
    positionBuilder: (_, constraints) => positionForCurrentLayout().rect,
    constraints: BoxConstraints(
      minWidth: fieldBox.size.width,
      maxWidth: fieldBox.size.width,
      maxHeight: initialPosition.height,
    ),
    color: cs.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 3,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: cs.outlineVariant.withValues(alpha: 0.14),
        width: 0.45,
      ),
    ),
    items: [
      for (final item in items)
        PopupMenuItem<T>(
          value: item.value,
          enabled: item.enabled,
          height: itemHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: DefaultTextStyle.merge(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: appSecondaryControlTextStyle(context).copyWith(
              color: item.enabled
                  ? cs.onSurface
                  : cs.onSurface.withValues(alpha: 0.38),
              fontWeight: DesignTokens.fontWeightStrong,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: item.value == selectedValue
                    ? selectedColor
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: itemContentPadding,
                child: Row(
                  children: [
                    Expanded(child: item.child),
                    if (item.value == selectedValue) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check_rounded, size: 16, color: cs.primary),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _DropdownMenuPosition {
  final RelativeRect rect;
  final double height;

  const _DropdownMenuPosition({required this.rect, required this.height});
}

class AppCompactDropdown<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final double width;

  const AppCompactDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width = 112,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? cs.surfaceContainerHighest.withValues(alpha: 0.42)
        : cs.surfaceContainerHighest.withValues(alpha: 0.52);
    final borderColor = cs.outlineVariant.withValues(
      alpha: isDark ? 0.10 : 0.12,
    );
    final selectedItem = _selectedItem();
    final enabled = onChanged != null && items.any((item) => item.enabled);
    final textColor = enabled
        ? cs.onSurface
        : cs.onSurface.withValues(alpha: 0.38);
    return SizedBox(
      width: width,
      child: Builder(
        builder: (anchorContext) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTapDown: enabled
                  ? (_) => _beginDropdownKeyboardDismiss(anchorContext)
                  : null,
              onTap: enabled ? () => _openPicker(anchorContext) : null,
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: DesignTokens.controlMinHeight,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spaceMd,
                  vertical: DesignTokens.spaceSm,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor, width: 0.45),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: Text(
                        selectedItem == null
                            ? value.toString()
                            : _dropdownItemLabel(selectedItem),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: appSecondaryControlTextStyle(context).copyWith(
                          color: textColor,
                          fontWeight: DesignTokens.fontWeightMedium,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: enabled
                          ? cs.onSurfaceVariant
                          : cs.onSurface.withValues(alpha: 0.38),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  DropdownMenuItem<T>? _selectedItem() {
    for (final item in items) {
      if (item.value == value) return item;
    }
    return null;
  }

  Future<void> _openPicker(BuildContext anchorContext) async {
    await _hideKeyboardBeforePicker(anchorContext);
    if (!anchorContext.mounted) return;

    final picked = await _showAnchoredDropdownMenu<T>(
      context: anchorContext,
      items: items,
      selectedValue: value,
      menuMaxHeight: 320,
      shiftForKeyboard: false,
    );
    if (picked == null) return;
    onChanged?.call(picked);
  }
}

class AppDropdownField<T> extends StatelessWidget {
  final T? initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final InputDecoration? decoration;
  final String? labelText;
  final String? hintText;
  final Widget? prefixIcon;
  final Widget? icon;
  final bool enabled;
  final bool isExpanded;
  final double? menuMaxHeight;
  final BorderRadius? borderRadius;
  final Color? dropdownColor;
  final Color? iconEnabledColor;
  final Color? iconDisabledColor;
  final AutovalidateMode? autovalidateMode;
  final FormFieldValidator<T>? validator;
  final FormFieldSetter<T>? onSaved;
  final VoidCallback? onTap;

  const AppDropdownField({
    super.key,
    required this.initialValue,
    required this.items,
    required this.onChanged,
    this.decoration,
    this.labelText,
    this.hintText,
    this.prefixIcon,
    this.icon,
    this.enabled = true,
    this.isExpanded = true,
    this.menuMaxHeight = 320,
    this.borderRadius,
    this.dropdownColor,
    this.iconEnabledColor,
    this.iconDisabledColor,
    this.autovalidateMode,
    this.validator,
    this.onSaved,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final inputDecoration =
        decoration ??
        InputDecoration(
          labelText: labelText,
          hintText: hintText,
          prefixIcon: prefixIcon,
          isDense: true,
        );
    final effectiveBorderRadius = borderRadius ?? BorderRadius.circular(16);
    return FormField<T>(
      initialValue: initialValue,
      validator: validator,
      onSaved: onSaved,
      autovalidateMode: autovalidateMode,
      builder: (field) {
        final selectedItem = _selectedItem(field.value);
        final iconColor = enabled
            ? iconEnabledColor ?? cs.onSurfaceVariant
            : iconDisabledColor ?? cs.onSurface.withValues(alpha: 0.38);
        final effectiveDecoration = inputDecoration
            .applyDefaults(theme.inputDecorationTheme)
            .copyWith(
              enabled: enabled,
              errorText: field.errorText,
              suffixIcon:
                  inputDecoration.suffixIcon ??
                  icon ??
                  Icon(Icons.keyboard_arrow_down_rounded, color: iconColor),
            );
        final canOpen = enabled && items.any((item) => item.enabled);
        return Builder(
          builder: (anchorContext) {
            final content = selectedItem == null
                ? const SizedBox.shrink()
                : DefaultTextStyle.merge(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appSecondaryControlTextStyle(context).copyWith(
                      color: enabled
                          ? cs.onSurface
                          : cs.onSurface.withValues(alpha: 0.38),
                      fontWeight: DesignTokens.fontWeightStrong,
                    ),
                    child: IconTheme.merge(
                      data: IconThemeData(color: cs.onSurfaceVariant),
                      child: selectedItem.child,
                    ),
                  );
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: effectiveBorderRadius,
                onTapDown: canOpen
                    ? (_) => _beginDropdownKeyboardDismiss(anchorContext)
                    : null,
                onTap: canOpen
                    ? () => _openPicker(anchorContext, field, inputDecoration)
                    : null,
                child: InputDecorator(
                  decoration: effectiveDecoration,
                  isEmpty: selectedItem == null,
                  child: content,
                ),
              ),
            );
          },
        );
      },
    );
  }

  DropdownMenuItem<T>? _selectedItem(T? value) {
    for (final item in items) {
      if (item.value == value) return item;
    }
    return null;
  }

  Future<void> _openPicker(
    BuildContext anchorContext,
    FormFieldState<T> field,
    InputDecoration decoration,
  ) async {
    onTap?.call();
    await _hideKeyboardBeforePicker(anchorContext);
    if (!anchorContext.mounted || !field.mounted) return;

    final picked = await _showAnchoredDropdownMenu<T>(
      context: anchorContext,
      items: items,
      selectedValue: field.value,
      menuMaxHeight: menuMaxHeight,
      shiftForKeyboard: false,
    );
    if (!field.mounted || picked == null) return;
    field.didChange(picked);
    onChanged(picked);
  }
}
