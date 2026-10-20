import 'package:flutter/material.dart';
import 'brand_strings.dart';
import 'design_tokens.dart';
import 'i18n.dart';
import 'page_tab_style.dart';

const String _cnFontFamily = DesignTokens.fontFamilyRounded;
const List<String> _cnFontFallback = [
  'PingFang SC',
  'Hiragino Sans GB',
  'Noto Sans CJK SC',
  'Source Han Sans SC',
  'Microsoft YaHei',
  'WenQuanYi Micro Hei',
];

enum BrandStyle {
  defaultBrand,
  re0,
  genshin,
  starRail,
  wuthering,
  zzz,
  yanyun,
  botw,
  liquidGlass,
}

class AppBrand {
  final BrandStyle style;
  final String name;
  final ThemeData theme;
  final String? backgroundAsset;
  final Color backgroundOverlay;
  final double backgroundOverlayOpacity;

  const AppBrand({
    required this.style,
    required this.name,
    required this.theme,
    this.backgroundAsset,
    this.backgroundOverlay = const Color(0xFFFFFFFF),
    this.backgroundOverlayOpacity = 0.7,
  });

  String get id => style.name;

  /// 主题文案按当前 locale 分发：zh 走中文常量，en 走英文变体骨架
  /// （brand_strings_en/）。getter 签名不变，消费端（brand.strings）零改动。
  BrandStrings get strings => BrandStrings.forLocale(style, I18n.current);
}

TextTheme _textTheme({
  required Brightness brightness,
  required Color bodyColor,
  required Color mutedColor,
  required Color headingColor,
}) {
  TextStyle style(
    double size,
    Color color, {
    double height = 1.3,
    FontWeight weight = DesignTokens.fontWeightStrong,
  }) {
    return TextStyle(
      fontFamily: _cnFontFamily,
      fontFamilyFallback: _cnFontFallback,
      fontSize: size,
      height: height,
      fontWeight: weight,
      letterSpacing: 0,
      color: color,
    );
  }

  return TextTheme(
    displayLarge: style(
      38,
      headingColor,
      height: 1.12,
      weight: DesignTokens.fontWeightStrong,
    ),
    displayMedium: style(
      32,
      headingColor,
      height: 1.16,
      weight: DesignTokens.fontWeightStrong,
    ),
    displaySmall: style(
      27,
      headingColor,
      height: 1.2,
      weight: DesignTokens.fontWeightStrong,
    ),
    headlineLarge: style(
      24,
      headingColor,
      height: 1.22,
      weight: DesignTokens.fontWeightStrong,
    ),
    headlineMedium: style(
      21,
      headingColor,
      height: 1.24,
      weight: DesignTokens.fontWeightStrong,
    ),
    headlineSmall: style(
      19,
      headingColor,
      height: 1.28,
      weight: DesignTokens.fontWeightStrong,
    ),
    titleLarge: style(
      18,
      headingColor,
      height: 1.24,
      weight: DesignTokens.fontWeightStrong,
    ),
    titleMedium: style(
      15.5,
      headingColor,
      height: 1.28,
      weight: DesignTokens.fontWeightStrong,
    ),
    titleSmall: style(
      13.5,
      headingColor,
      height: 1.3,
      weight: DesignTokens.fontWeightStrong,
    ),
    bodyLarge: style(16, bodyColor, height: 1.56),
    bodyMedium: style(14, bodyColor, height: 1.58),
    bodySmall: style(12, mutedColor, height: 1.5),
    labelLarge: style(
      14,
      bodyColor,
      height: 1.2,
      weight: DesignTokens.fontWeightStrong,
    ),
    labelMedium: style(
      12,
      bodyColor,
      height: 1.2,
      weight: DesignTokens.fontWeightStrong,
    ),
    labelSmall: style(
      11,
      bodyColor,
      height: 1.2,
      weight: DesignTokens.fontWeightStrong,
    ),
  );
}

double _contrastRatio(Color a, Color b) {
  final aLum = a.computeLuminance();
  final bLum = b.computeLuminance();
  final lighter = aLum > bLum ? aLum : bLum;
  final darker = aLum > bLum ? bLum : aLum;
  return (lighter + 0.05) / (darker + 0.05);
}

Color _highContrastForeground(Color background, Color preferred) {
  if (_contrastRatio(background, preferred) >= 4.5) return preferred;
  final blackContrast = _contrastRatio(background, const Color(0xFF111827));
  final whiteContrast = _contrastRatio(background, Colors.white);
  return blackContrast >= whiteContrast
      ? const Color(0xFF111827)
      : Colors.white;
}

Color _buttonActionBackground(Color primary, {required bool isDark}) {
  final preferredForeground = isDark ? const Color(0xFF111827) : Colors.white;
  if (_contrastRatio(primary, preferredForeground) >= 4.5) return primary;

  final target = isDark ? Colors.white : const Color(0xFF111827);
  for (final amount in const <double>[0.08, 0.14, 0.20, 0.26, 0.32, 0.38]) {
    final candidate = Color.lerp(primary, target, amount)!;
    if (_contrastRatio(candidate, preferredForeground) >= 4.5) {
      return candidate;
    }
  }
  return Color.lerp(primary, target, isDark ? 0.42 : 0.44)!;
}

/// 共享控件层的观感档位：所有字段默认值 = 既有观感。
///
/// 四条主题构造路径（_lightTheme/_darkTheme/_re0Theme/_botwTheme）都汇入
/// [_withSharedControls]；只有 [_defaultTheme] 传 [_SharedFeel.ios]，
/// 其余 7 套主题走默认值，观感保持不变（参数化差异，而非全局改档）。
class _SharedFeel {
  final double controlRadius;
  final double dialogRadius;
  final double sheetTopRadius;
  final double buttonMinHeight;
  final double inputVerticalPadding;
  final double navBarAlphaLight;
  final double dividerAlphaLight;
  final double dividerAlphaDark;

  const _SharedFeel({
    this.controlRadius = DesignTokens.radiusControl,
    this.dialogRadius = 18,
    this.sheetTopRadius = 20,
    this.buttonMinHeight = 38,
    this.inputVerticalPadding = 9,
    this.navBarAlphaLight = 0.96,
    this.dividerAlphaLight = 0.64,
    this.dividerAlphaDark = 0.52,
  });

  /// 默认主题专用 iOS 档：更大圆角、更宽松控件内边距、更柔和分隔、
  /// 半透明底导航（毛玻璃模糊由 [AppSurfaceStyle.ios.navBarBlurSigma] 驱动）。
  static const _SharedFeel ios = _SharedFeel(
    controlRadius: DesignTokens.radiusControlIos,
    dialogRadius: DesignTokens.dialogIosRadius,
    sheetTopRadius: DesignTokens.sheetIosTopRadius,
    buttonMinHeight: DesignTokens.buttonIosMinHeight,
    inputVerticalPadding: DesignTokens.inputIosVerticalPadding,
    navBarAlphaLight: DesignTokens.navBarIosBackgroundAlpha,
    dividerAlphaLight: DesignTokens.dividerIosAlpha,
    dividerAlphaDark: DesignTokens.dividerIosDarkAlpha,
  );
}

ThemeData _withSharedControls(
  ThemeData theme, {
  _SharedFeel feel = const _SharedFeel(),
}) {
  final cs = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;
  final surface = cs.surface;
  final primaryForeground = _highContrastForeground(cs.primary, cs.onPrimary);
  final actionBackground = _buttonActionBackground(cs.primary, isDark: isDark);
  final actionForeground = _highContrastForeground(
    actionBackground,
    isDark ? const Color(0xFF111827) : Colors.white,
  );
  final surfaceTint = Colors.transparent;
  final outline = cs.outlineVariant.withValues(alpha: isDark ? 0.12 : 0.14);
  final actionBorder = Color.alphaBlend(
    cs.outline.withValues(alpha: isDark ? 0.44 : 0.34),
    surface,
  );
  final fill = Color.alphaBlend(
    cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.52 : 0.64),
    surface,
  );
  final sheetShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(feel.sheetTopRadius),
    ),
  );
  final dialogShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(feel.dialogRadius),
  );
  final appBarForeground =
      theme.appBarTheme.titleTextStyle?.color ??
      theme.appBarTheme.foregroundColor ??
      cs.onSurface;
  final appBarTitleText = (theme.textTheme.titleMedium ?? const TextStyle())
      .copyWith(
        color: appBarForeground,
        fontSize: DesignTokens.fontSizeMd,
        fontWeight: DesignTokens.fontWeightStrong,
        height: 1.2,
        letterSpacing: 0,
      );
  final appBarToolbarText = (theme.textTheme.bodyMedium ?? const TextStyle())
      .copyWith(
        color: appBarForeground,
        fontWeight: DesignTokens.fontWeightStrong,
        letterSpacing: 0,
      );

  final body = theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface);
  final bodyMuted = theme.textTheme.bodySmall?.copyWith(
    color: cs.onSurface.withValues(alpha: 0.68),
  );
  final label = theme.textTheme.labelMedium?.copyWith(
    fontSize: DesignTokens.fontSizeBase,
    fontWeight: DesignTokens.fontWeightStrong,
  );
  final secondaryControlText = theme.textTheme.bodySmall?.copyWith(
    fontSize: DesignTokens.fontSizeSm,
    height: 1.2,
    fontWeight: DesignTokens.fontWeightStrong,
    color: cs.onSurface,
  );
  final secondaryLabelText = theme.textTheme.labelSmall?.copyWith(
    fontSize: DesignTokens.fontSizeXs,
    height: 1.16,
    fontWeight: DesignTokens.fontWeightStrong,
  );
  final selectedControlBackground = Color.alphaBlend(
    cs.primary.withValues(alpha: isDark ? 0.18 : 0.10),
    surface,
  );
  final selectedControlForeground = _highContrastForeground(
    selectedControlBackground,
    cs.onSurface,
  );
  final selectedNavigationBackground = Color.alphaBlend(
    cs.primary.withValues(alpha: isDark ? 0.18 : 0.10),
    surface,
  );
  final selectedNavigationForeground = _highContrastForeground(
    selectedNavigationBackground,
    cs.primary,
  );
  OutlineInputBorder fieldBorder(Color color, {double width = 0.4}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(feel.controlRadius),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  final inputTheme = InputDecorationTheme(
    filled: true,
    fillColor: Color.alphaBlend(
      cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.58 : 0.72),
      surface,
    ),
    isDense: true,
    contentPadding: EdgeInsets.symmetric(
      horizontal: 12,
      vertical: feel.inputVerticalPadding,
    ),
    border: fieldBorder(outline),
    enabledBorder: fieldBorder(outline),
    focusedBorder: fieldBorder(cs.primary.withValues(alpha: 0.18), width: 0.45),
    errorBorder: fieldBorder(cs.error.withValues(alpha: 0.36)),
    focusedErrorBorder: fieldBorder(
      cs.error.withValues(alpha: 0.42),
      width: 0.45,
    ),
    hintStyle: secondaryControlText?.copyWith(
      color: cs.onSurface.withValues(alpha: 0.46),
      fontWeight: DesignTokens.fontWeightStrong,
    ),
    labelStyle: secondaryLabelText?.copyWith(
      color: cs.onSurface.withValues(alpha: 0.72),
      fontWeight: DesignTokens.fontWeightStrong,
    ),
    floatingLabelStyle: secondaryLabelText?.copyWith(
      color: cs.primary,
      fontWeight: DesignTokens.fontWeightStrong,
    ),
    prefixIconColor: WidgetStateColor.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return cs.onSurface.withValues(alpha: 0.38);
      }
      return cs.onSurfaceVariant;
    }),
    suffixIconColor: WidgetStateColor.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return cs.onSurface.withValues(alpha: 0.38);
      }
      return cs.onSurfaceVariant;
    }),
    errorStyle: secondaryLabelText?.copyWith(color: cs.error),
  );

  return theme.copyWith(
    primaryTextTheme: _textTheme(
      brightness: theme.brightness,
      bodyColor: cs.onPrimary,
      mutedColor: cs.onPrimary,
      headingColor: cs.onPrimary,
    ),
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: theme.appBarTheme.copyWith(
      foregroundColor: appBarForeground,
      titleTextStyle: appBarTitleText,
      toolbarTextStyle: appBarToolbarText,
      iconTheme:
          theme.appBarTheme.iconTheme?.copyWith(color: appBarForeground) ??
          IconThemeData(color: appBarForeground),
      actionsIconTheme:
          theme.appBarTheme.actionsIconTheme?.copyWith(
            color: appBarForeground,
          ) ??
          IconThemeData(color: appBarForeground),
    ),
    inputDecorationTheme: inputTheme,
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: surfaceTint,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.34 : 0.14),
      shape: dialogShape,
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
      barrierColor: Colors.black.withValues(alpha: isDark ? 0.56 : 0.36),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      titleTextStyle: theme.textTheme.titleMedium?.copyWith(
        color: cs.onSurface,
        fontWeight: DesignTokens.fontWeightStrong,
      ),
      contentTextStyle: body,
      iconColor: cs.primary,
      clipBehavior: Clip.antiAlias,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      modalBackgroundColor: surface,
      surfaceTintColor: surfaceTint,
      modalBarrierColor: Colors.black.withValues(alpha: isDark ? 0.48 : 0.32),
      elevation: 0,
      modalElevation: 4,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
      shape: sheetShape,
      showDragHandle: true,
      dragHandleColor: cs.outlineVariant,
      dragHandleSize: const Size(40, 4),
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(maxWidth: 720),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: cs.surfaceContainerHighest,
      actionTextColor: cs.primary,
      contentTextStyle: theme.textTheme.bodyMedium?.copyWith(
        color: cs.onSurface,
        fontWeight: DesignTokens.fontWeightStrong,
      ),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
      surfaceTintColor: surfaceTint,
      textStyle: secondaryControlText?.copyWith(
        color: cs.onSurface,
        fontWeight: DesignTokens.fontWeightStrong,
      ),
      iconColor: cs.onSurfaceVariant,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: secondaryControlText?.copyWith(
        color: cs.onSurface,
        fontWeight: DesignTokens.fontWeightStrong,
      ),
      inputDecorationTheme: inputTheme,
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(surface),
        shadowColor: WidgetStatePropertyAll(
          Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(4),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 8),
        ),
      ),
      disabledColor: cs.onSurface.withValues(alpha: 0.38),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(surface),
        shadowColor: WidgetStatePropertyAll(
          Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(4),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: actionBackground,
        foregroundColor: actionForeground,
        disabledBackgroundColor: cs.onSurface.withValues(alpha: 0.08),
        disabledForegroundColor: cs.onSurface.withValues(alpha: 0.38),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        minimumSize: Size(0, feel.buttonMinHeight),
        overlayColor: actionForeground.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(feel.controlRadius),
        ),
        textStyle: label,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: actionBackground,
        foregroundColor: actionForeground,
        disabledBackgroundColor: cs.onSurface.withValues(alpha: 0.08),
        disabledForegroundColor: cs.onSurface.withValues(alpha: 0.38),
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        minimumSize: Size(0, feel.buttonMinHeight),
        overlayColor: actionForeground.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(feel.controlRadius),
        ),
        textStyle: label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: cs.onSurface,
        side: BorderSide(color: actionBorder, width: 0.7),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        minimumSize: const Size(0, 36),
        overlayColor: cs.primary.withValues(alpha: 0.07),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(feel.controlRadius),
        ),
        textStyle: label,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: actionBackground,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 34),
        overlayColor: actionBackground.withValues(alpha: 0.07),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(feel.controlRadius),
        ),
        textStyle: label,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return selectedControlBackground;
          }
          return fill;
        }),
        foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.disabled)) {
            return cs.onSurface.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.selected)) {
            return selectedControlForeground;
          }
          return cs.onSurfaceVariant;
        }),
        side: WidgetStateProperty.resolveWith<BorderSide?>((states) {
          if (states.contains(WidgetState.selected)) {
            return BorderSide(
              color: Color.alphaBlend(
                cs.primary.withValues(alpha: isDark ? 0.44 : 0.38),
                surface,
              ),
              width: 0.7,
            );
          }
          return BorderSide(color: actionBorder, width: 0.6);
        }),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(feel.controlRadius),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        textStyle: WidgetStatePropertyAll(label),
        iconColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return selectedControlForeground;
          }
          return cs.onSurfaceVariant;
        }),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(36, 36),
        padding: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(feel.controlRadius),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: fill,
      selectedColor: selectedControlBackground,
      secondarySelectedColor: selectedControlBackground,
      disabledColor: cs.onSurface.withValues(alpha: 0.08),
      deleteIconColor: cs.onSurface.withValues(alpha: 0.72),
      checkmarkColor: selectedControlForeground,
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        fontSize: 11,
        color: cs.onSurface,
        fontWeight: DesignTokens.fontWeightStrong,
      ),
      secondaryLabelStyle: theme.textTheme.labelMedium?.copyWith(
        fontSize: 11,
        color: selectedControlForeground,
        fontWeight: DesignTokens.fontWeightStrong,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      side: BorderSide(
        color: outline.withValues(alpha: isDark ? 0.64 : 0.58),
        width: 0.4,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      showCheckmark: false,
      iconTheme: IconThemeData(size: 18, color: cs.onSurfaceVariant),
      surfaceTintColor: surfaceTint,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.16 : 0.06),
      elevation: 0,
      pressElevation: 0,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return cs.onSurface.withValues(alpha: 0.38);
        }
        if (states.contains(WidgetState.selected)) {
          return cs.primary;
        }
        return cs.onSurfaceVariant.withValues(alpha: isDark ? 0.82 : 0.68);
      }),
      trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return cs.onSurface.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.selected)) {
          return Color.alphaBlend(
            cs.primary.withValues(alpha: isDark ? 0.28 : 0.18),
            surface,
          );
        }
        return Color.alphaBlend(
          cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.56 : 0.72),
          surface,
        );
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return cs.primary.withValues(alpha: isDark ? 0.20 : 0.16);
        }
        return outline.withValues(alpha: isDark ? 0.70 : 0.62);
      }),
      trackOutlineWidth: const WidgetStatePropertyAll<double>(0.45),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return Colors.transparent;
        }
        return cs.primary.withValues(alpha: 0.12);
      }),
      splashRadius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 2),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return cs.onSurface.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.selected)) {
          return cs.primary;
        }
        return Colors.transparent;
      }),
      checkColor: WidgetStatePropertyAll<Color>(primaryForeground),
      overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return Colors.transparent;
        }
        return cs.primary.withValues(alpha: 0.12);
      }),
      splashRadius: 20,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      side: BorderSide(color: outline),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return cs.onSurface.withValues(alpha: 0.12);
        }
        return cs.primary;
      }),
      overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return Colors.transparent;
        }
        return cs.primary.withValues(alpha: 0.12);
      }),
      backgroundColor: const WidgetStatePropertyAll<Color?>(Colors.transparent),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      side: BorderSide(color: outline),
      splashRadius: 20,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: cs.primary,
      inactiveTrackColor: cs.onSurface.withValues(alpha: 0.14),
      thumbColor: cs.primary,
      overlayColor: cs.primary.withValues(alpha: 0.12),
      valueIndicatorColor: cs.primary,
      valueIndicatorTextStyle: theme.textTheme.bodySmall?.copyWith(
        color: primaryForeground,
        fontWeight: DesignTokens.fontWeightStrong,
      ),
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: cs.primary,
      linearTrackColor: cs.primary.withValues(alpha: 0.16),
      circularTrackColor: cs.primary.withValues(alpha: 0.16),
    ),
    dividerTheme: DividerThemeData(
      color: cs.outlineVariant.withValues(
        alpha: isDark ? feel.dividerAlphaDark : feel.dividerAlphaLight,
      ),
      thickness: 1,
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      iconColor: cs.primary,
      textColor: cs.onSurface,
      tileColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    tabBarTheme: appPageTabTheme(theme),
    navigationBarTheme: NavigationBarThemeData(
      height: 60,
      elevation: 0,
      // 暗色主题保持既有 0.92；亮色走档位（默认主题 iOS 档 0.72）。
      backgroundColor: surface.withValues(
        alpha: isDark ? 0.92 : feel.navBarAlphaLight,
      ),
      indicatorColor: selectedNavigationBackground,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
        final selected = states.contains(WidgetState.selected);
        return theme.textTheme.labelSmall?.copyWith(
          color: selected ? selectedNavigationForeground : cs.onSurfaceVariant,
          fontWeight: DesignTokens.fontWeightStrong,
          letterSpacing: 0,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? selectedNavigationForeground : cs.onSurfaceVariant,
          size: 24,
        );
      }),
    ),
    navigationRailTheme: theme.navigationRailTheme.copyWith(
      selectedLabelTextStyle: theme.textTheme.labelMedium?.copyWith(
        fontWeight: DesignTokens.fontWeightStrong,
      ),
      unselectedLabelTextStyle: theme.textTheme.labelMedium?.copyWith(
        fontWeight: DesignTokens.fontWeightStrong,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: actionBackground,
      foregroundColor: actionForeground,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      extendedTextStyle: label,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: surface,
      surfaceTintColor: surfaceTint,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.32 : 0.12),
      shape: dialogShape,
      headerBackgroundColor: actionBackground,
      headerForegroundColor: actionForeground,
      headerHeadlineStyle: theme.textTheme.headlineSmall?.copyWith(
        color: actionForeground,
        fontWeight: DesignTokens.fontWeightStrong,
      ),
      headerHelpStyle: bodyMuted?.copyWith(
        color: actionForeground.withValues(alpha: 0.84),
      ),
      weekdayStyle: theme.textTheme.bodySmall?.copyWith(
        color: cs.onSurfaceVariant,
        fontWeight: DesignTokens.fontWeightStrong,
      ),
      dayStyle: theme.textTheme.bodySmall?.copyWith(color: cs.onSurface),
      dayForegroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.disabled)) {
          return cs.onSurface.withValues(alpha: 0.24);
        }
        if (states.contains(WidgetState.selected)) {
          return actionForeground;
        }
        return cs.onSurface;
      }),
      dayBackgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return actionBackground;
        }
        return Colors.transparent;
      }),
      dayOverlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return cs.primary.withValues(alpha: 0.15);
        }
        return cs.primary.withValues(alpha: 0.08);
      }),
      dayShape: const WidgetStatePropertyAll<OutlinedBorder?>(CircleBorder()),
      todayForegroundColor: WidgetStatePropertyAll<Color?>(cs.primary),
      todayBackgroundColor: WidgetStatePropertyAll<Color?>(
        cs.primary.withValues(alpha: 0.12),
      ),
      todayBorder: BorderSide(color: cs.primary, width: 1.4),
      yearStyle: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
      yearForegroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return actionForeground;
        }
        return cs.onSurface;
      }),
      yearBackgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) {
          return actionBackground;
        }
        return Colors.transparent;
      }),
      yearOverlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
        return cs.primary.withValues(alpha: 0.08);
      }),
      yearShape: const WidgetStatePropertyAll<OutlinedBorder?>(CircleBorder()),
      rangePickerBackgroundColor: surface,
      rangePickerSurfaceTintColor: surfaceTint,
      rangePickerShape: dialogShape,
      dividerColor: cs.outlineVariant.withValues(alpha: 0.52),
      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: cs.onSurfaceVariant,
        textStyle: label,
      ),
      confirmButtonStyle: FilledButton.styleFrom(
        backgroundColor: actionBackground,
        foregroundColor: actionForeground,
        minimumSize: const Size(0, 38),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(feel.controlRadius),
        ),
        textStyle: label,
      ),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: surface,
      shape: dialogShape,
      elevation: 0,
      dayPeriodBorderSide: BorderSide(color: outline),
      dayPeriodColor: cs.primary.withValues(alpha: 0.14),
      dayPeriodShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      dayPeriodTextColor: cs.onSurface,
      dialBackgroundColor: cs.surfaceContainerHighest.withValues(
        alpha: isDark ? 0.36 : 0.56,
      ),
      dialHandColor: cs.primary,
      dialTextColor: cs.onSurface,
      hourMinuteColor: cs.primary.withValues(alpha: 0.12),
      hourMinuteShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      hourMinuteTextColor: cs.onSurface,
      helpTextStyle: theme.textTheme.bodyMedium?.copyWith(
        color: cs.onSurfaceVariant,
        fontWeight: DesignTokens.fontWeightStrong,
      ),
      confirmButtonStyle: FilledButton.styleFrom(
        backgroundColor: actionBackground,
        foregroundColor: actionForeground,
        minimumSize: const Size(0, 38),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(feel.controlRadius),
        ),
        textStyle: label,
      ),
      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: cs.onSurfaceVariant,
        textStyle: label,
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStatePropertyAll<double>(isDark ? 6 : 5),
      radius: const Radius.circular(999),
      thumbVisibility: const WidgetStatePropertyAll<bool>(false),
      thumbColor: WidgetStatePropertyAll<Color?>(
        cs.onSurface.withValues(alpha: isDark ? 0.36 : 0.24),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: cs.primary,
      selectionColor: cs.primary.withValues(alpha: 0.22),
      selectionHandleColor: cs.primary,
    ),
  );
}

ThemeData _lightTheme({
  required Color primary,
  required Color secondary,
  required Color surface,
  required Color background,
  Color error = const Color(0xFFA23535),
  _SharedFeel feel = const _SharedFeel(),
  AppSurfaceStyle? surfaceStyle,
}) {
  final theme = ThemeData(
    useMaterial3: true,
    fontFamily: _cnFontFamily,
    fontFamilyFallback: _cnFontFallback,
    textTheme: _textTheme(
      brightness: Brightness.light,
      bodyColor: DesignTokens.defaultText,
      mutedColor: DesignTokens.defaultTextMuted,
      headingColor: DesignTokens.defaultText,
    ),
    colorScheme: ColorScheme.light(
      primary: primary,
      secondary: secondary,
      surface: surface,
      error: error,
      onSurface: DesignTokens.defaultText,
    ),
    // 仅默认主题注册 AppSurfaceStyle.ios；其余主题不带该 extension，
    // 共享组件在调用点回退到既有默认值，观感不变。
    extensions: surfaceStyle == null
        ? null
        : <ThemeExtension<dynamic>>[surfaceStyle],
    scaffoldBackgroundColor: background,
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          surfaceStyle?.cardRadius ?? DesignTokens.radiusCard,
        ),
        side: surfaceStyle == null
            ? BorderSide(
                color: DesignTokens.defaultBorder.withValues(alpha: 0.72),
                width: 0.55,
              )
            : BorderSide.none,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DesignTokens.defaultSurfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        borderSide: BorderSide(color: DesignTokens.defaultBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        borderSide: BorderSide(color: primary.withValues(alpha: 0.54)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: _highContrastForeground(primary, Colors.white),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        ),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: const Color(0xFF1E2532),
      titleTextStyle: const TextStyle(
        fontSize: DesignTokens.fontSizeMd,
        fontWeight: DesignTokens.fontWeightStrong,
        color: Color(0xFF1E2532),
      ),
    ),
  );
  return _withSharedControls(theme, feel: feel);
}

ThemeData _darkTheme({
  required Color primary,
  required Color secondary,
  required Color surface,
  required Color background,
  Color error = const Color(0xFFFF6B6B),
}) {
  final theme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: _cnFontFamily,
    fontFamilyFallback: _cnFontFallback,
    textTheme: _textTheme(
      brightness: Brightness.dark,
      bodyColor: const Color(0xFFF3F6FA),
      mutedColor: const Color(0xFF9CA8BC),
      headingColor: const Color(0xFFFFFFFF),
    ),
    colorScheme: ColorScheme.dark(
      primary: primary,
      secondary: secondary,
      surface: surface,
      error: error,
    ),
    scaffoldBackgroundColor: background,
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        borderSide: BorderSide(color: primary.withValues(alpha: 0.60)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        ),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: primary,
    ),
  );
  return _withSharedControls(theme);
}

final _re0Theme = _withSharedControls(
  ThemeData(
    useMaterial3: true,
    fontFamily: _cnFontFamily,
    fontFamilyFallback: _cnFontFallback,
    textTheme: _textTheme(
      brightness: Brightness.light,
      bodyColor: const Color(0xFF243244),
      mutedColor: const Color(0xFF6F7C8F),
      headingColor: const Color(0xFF1C2D46),
    ),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF4682B4),
      secondary: Color(0xFFE6E6FA),
      surface: Color(0xFFFDFDFD),
      error: Color(0xFFA23535),
    ),
    scaffoldBackgroundColor: const Color(0xFFFDFDFD),
    cardTheme: CardThemeData(
      color: Colors.white.withValues(alpha: 0.9),
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        side: BorderSide(
          color: const Color(0xFF4682B4).withValues(alpha: 0.14),
          width: 0.55,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.96),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        borderSide: BorderSide(
          color: const Color(0xFF4682B4).withValues(alpha: 0.16),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        borderSide: BorderSide(
          color: const Color(0xFF4682B4).withValues(alpha: 0.30),
          width: 0.55,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF4682B4),
        foregroundColor: _highContrastForeground(
          const Color(0xFF4682B4),
          Colors.white,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        ),
        elevation: 0,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
    ),
  ),
);

final _genshinTheme = _lightTheme(
  primary: const Color(0xFF2E8B57),
  secondary: const Color(0xFFC5892F),
  surface: const Color(0xFFFFFFFF),
  background: const Color(0xFFF8F9F0),
);

final _starRailTheme = _darkTheme(
  primary: const Color(0xFF7EA2FF),
  secondary: const Color(0xFFD0A43A),
  surface: const Color(0xFF161C30),
  background: const Color(0xFF080B16),
);

final _wutheringTheme = _lightTheme(
  primary: const Color(0xFF1B8C8F),
  secondary: const Color(0xFFE6A73A),
  surface: const Color(0xFFFFFFFF),
  background: const Color(0xFFF0F7F6),
);

final _zzzTheme = _darkTheme(
  primary: const Color(0xFFE6C229),
  secondary: const Color(0xFFFF6B35),
  surface: const Color(0xFF181818),
  background: const Color(0xFF0D0D0D),
);

final _yanyunTheme = _lightTheme(
  primary: const Color(0xFF7D4E2D),
  secondary: const Color(0xFFB86F32),
  surface: const Color(0xFFFFFCF6),
  background: const Color(0xFFF5F0E8),
);

final _botwTheme = _withSharedControls(
  ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: _cnFontFamily,
    fontFamilyFallback: _cnFontFallback,
    scaffoldBackgroundColor: const Color(0xFF121212),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF00D2FF),
      secondary: Color(0xFFFF9600),
      surface: Color(0xFF2A2A2A),
    ),
    textTheme: _textTheme(
      brightness: Brightness.dark,
      bodyColor: Colors.white70,
      mutedColor: Colors.white54,
      headingColor: const Color(0xFF7DEBFF),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF2A2A2A).withValues(alpha: 0.8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: Color(0xFF00D2FF), width: 0.5),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.58),
      border: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF00D2FF)),
      ),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white24),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF00D2FF), width: 2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF00D2FF),
        side: const BorderSide(color: Color(0xFF00D2FF), width: 1.5),
        shape: const BeveledRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(10),
            bottomRight: Radius.circular(10),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
    ),
  ),
);

final _defaultTheme = _lightTheme(
  primary: DesignTokens.defaultPrimary,
  secondary: DesignTokens.defaultAccent,
  surface: DesignTokens.defaultSurface,
  background: DesignTokens.defaultPageBackground,
  error: DesignTokens.defaultError,
  // 默认主题专属 iOS 档：更大圆角 / 更宽松控件 / 更柔和分隔 / 半透明底导航。
  // 其余 7 套主题不传 feel / surfaceStyle，走既有默认值，观感不变。
  feel: _SharedFeel.ios,
  surfaceStyle: AppSurfaceStyle.ios,
);

/// 液态玻璃主题：浅色 iOS 基底（iOS 蓝），玻璃质感卡片。
///
/// 卡片走"半透明白填充 + 白高光描边"伪玻璃（由 AppSurfaceStyle.liquidGlass
/// 驱动，列表内不做逐卡 BackdropFilter）；底部导航启用真模糊。无背景图，
/// overlay 为浅色近白纯色。控件层复用 iOS 档（_SharedFeel.ios）。
final _liquidGlassTheme = _withSharedControls(
  ThemeData(
    useMaterial3: true,
    fontFamily: _cnFontFamily,
    fontFamilyFallback: _cnFontFallback,
    textTheme: _textTheme(
      brightness: Brightness.light,
      bodyColor: const Color(0xFF17233B),
      mutedColor: const Color(0xFF5B6B82),
      headingColor: const Color(0xFF101B2D),
    ),
    colorScheme: const ColorScheme.light(
      // iOS 蓝系（#0A84FF 同色相深阶）：保证按钮前景对 surface 对比 ≥4.5。
      primary: Color(0xFF0A6CDB),
      secondary: Color(0xFF5AC8FA),
      surface: Color(0xFFF7F9FC),
      error: Color(0xFFC64747),
      onSurface: Color(0xFF17233B),
    ),
    extensions: <ThemeExtension<dynamic>>[AppSurfaceStyle.liquidGlass],
    scaffoldBackgroundColor: const Color(0xFFE9EEF6),
    cardTheme: CardThemeData(
      // 白玻璃填充：与 AppSurfaceCard / AppMetricCard 共用同一档
      // （DesignTokens.glassFillLightAlpha），保证三类卡面质感一致。
      color: Colors.white.withValues(alpha: DesignTokens.glassFillLightAlpha),
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shadowColor: Colors.transparent,
      // 白高光描边与 AppSurfaceStyle.liquidGlass.cardBorder 同源
      // （Colors.white@glassHighlightAlpha、0.55），三类卡面同屏同质感。
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(
          Radius.circular(DesignTokens.radiusCardIos),
        ),
        side: BorderSide(
          color: Colors.white.withValues(
            alpha: DesignTokens.glassHighlightAlpha,
          ),
          width: 0.55,
        ),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: Color(0xFF101B2D),
      titleTextStyle: TextStyle(
        fontSize: DesignTokens.fontSizeMd,
        fontWeight: DesignTokens.fontWeightStrong,
        color: Color(0xFF101B2D),
      ),
    ),
  ),
  feel: _SharedFeel.ios,
);

class AppBrands {
  static final defaultBrand = AppBrand(
    style: BrandStyle.defaultBrand,
    name: '多仪',
    theme: _defaultTheme,
    backgroundOverlay: DesignTokens.defaultPageBackground,
    backgroundOverlayOpacity: 1.0,
  );
  static final re0 = AppBrand(
    style: BrandStyle.re0,
    name: '从零开始',
    theme: _re0Theme,
    backgroundAsset: 'assets/backgrounds/re0.png',
    backgroundOverlay: const Color(0xFFF8FBFF),
    backgroundOverlayOpacity: 0.72,
  );
  static final genshin = AppBrand(
    style: BrandStyle.genshin,
    name: '原神',
    theme: _genshinTheme,
    backgroundAsset: 'assets/backgrounds/genshin.png',
    backgroundOverlay: const Color(0xFFFFFEF6),
    backgroundOverlayOpacity: 0.70,
  );
  static final starRail = AppBrand(
    style: BrandStyle.starRail,
    name: '星穹铁道',
    theme: _starRailTheme,
    backgroundAsset: 'assets/backgrounds/star_rail.png',
    backgroundOverlay: const Color(0xFF060A18),
    backgroundOverlayOpacity: 0.70,
  );
  static final wuthering = AppBrand(
    style: BrandStyle.wuthering,
    name: '鸣潮',
    theme: _wutheringTheme,
    backgroundAsset: 'assets/backgrounds/wuthering.png',
    backgroundOverlay: const Color(0xFFF7FCFB),
    backgroundOverlayOpacity: 0.68,
  );
  static final zzz = AppBrand(
    style: BrandStyle.zzz,
    name: '绝区零',
    theme: _zzzTheme,
    backgroundAsset: 'assets/backgrounds/zzz.png',
    backgroundOverlay: const Color(0xFF090909),
    backgroundOverlayOpacity: 0.70,
  );
  static final yanyun = AppBrand(
    style: BrandStyle.yanyun,
    name: '燕云十六声',
    theme: _yanyunTheme,
    backgroundAsset: 'assets/backgrounds/yanyun.png',
    backgroundOverlay: const Color(0xFFFFFBF4),
    backgroundOverlayOpacity: 0.72,
  );
  static final botw = AppBrand(
    style: BrandStyle.botw,
    name: '希卡之石',
    theme: _botwTheme,
    backgroundAsset: 'assets/backgrounds/botw.png',
    backgroundOverlay: const Color(0xFF061417),
    backgroundOverlayOpacity: 0.68,
  );
  static final liquidGlass = AppBrand(
    style: BrandStyle.liquidGlass,
    name: '液态玻璃',
    theme: _liquidGlassTheme,
    // 无背景图主题：浅色近白 overlay 全幅铺底，衬托半透明玻璃卡片。
    backgroundOverlay: const Color(0xFFE9EEF6),
    backgroundOverlayOpacity: 1.0,
  );

  static List<AppBrand> get all => [
    defaultBrand,
    re0,
    genshin,
    starRail,
    wuthering,
    zzz,
    yanyun,
    botw,
    liquidGlass,
  ];

  static AppBrand byId(String? id) {
    return all.firstWhere((b) => b.id == id, orElse: () => defaultBrand);
  }
}
