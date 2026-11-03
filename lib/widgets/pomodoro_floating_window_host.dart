import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_brand.dart';
import '../core/brand_strings.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/pomodoro_floating_window_size.dart';
import '../providers/app_lock_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/theme_provider.dart';
import '../services/app_update_service.dart';
import '../services/pomodoro_floating_window_service.dart';

/// 全局悬浮窗宿主：在 MaterialApp.builder 层绑定计时 Provider。
///
/// 离开番茄计时页后仍持续同步快照；语言、主题、应用锁、强制更新与
/// 账号/服务器身份变化都在这里转成 service 的配置。
class PomodoroFloatingWindowHost extends StatefulWidget {
  const PomodoroFloatingWindowHost({
    super.key,
    required this.child,
    this.service,
  });

  final Widget child;

  /// 测试注入；生产使用 [PomodoroFloatingWindowService.instance]。
  final PomodoroFloatingWindowService? service;

  @override
  State<PomodoroFloatingWindowHost> createState() =>
      _PomodoroFloatingWindowHostState();
}

class _PomodoroFloatingWindowHostState
    extends State<PomodoroFloatingWindowHost> {
  late PomodoroFloatingWindowService _service;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PomodoroFloatingWindowService.instance;
  }

  @override
  void didUpdateWidget(covariant PomodoroFloatingWindowHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.service ?? PomodoroFloatingWindowService.instance;
    if (!identical(next, _service)) {
      _service.detach();
      _service = next;
    }
  }

  @override
  void dispose() {
    _service.detach();
    unawaited(_service.disposeWindow());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (!service.isSupported) return widget.child;

    final pomodoro = context.read<PomodoroProvider?>();
    if (pomodoro == null) return widget.child;

    final theme = context.watch<ThemeProvider?>();
    final localeProvider = context.watch<LocaleProvider?>();
    final lock = context.watch<AppLockProvider?>();
    final update = context.watch<AppUpdateService?>();
    final auth = context.watch<AuthProvider?>();
    final preferences = context.watch<PreferencesProvider?>();

    final brand = theme?.brand ?? AppBrands.defaultBrand;
    final locale = localeProvider?.locale ?? I18n.current;
    final strings = BrandStrings.forLocale(brand.style, locale);
    final themeData = Theme.of(context);
    final cs = themeData.colorScheme;
    final surface = themeData.extension<AppSurfaceStyle>();
    final button = themeData.filledButtonTheme.style;
    final shape = button?.shape?.resolve({});
    final border = surface?.cardBorder?.top;
    final borderColor = themeData.brightness == Brightness.dark
        ? cs.outlineVariant.withValues(alpha: 0.18)
        : (Color.lerp(DesignTokens.defaultBorder, cs.outlineVariant, 0.35) ??
                  DesignTokens.defaultBorder)
              .withValues(alpha: 0.72);
    final cardFill = Color.alphaBlend(
      surface?.cardFillColor ?? cs.surface,
      cs.surface,
    );

    service.attach(pomodoro);
    service.configure(
      available: !(lock?.isLocked ?? false) && !(update?.mustUpdate ?? false),
      sessionIdentity: '${auth?.baseUrl ?? ''}|${auth?.state.userId ?? ''}',
      windowTitle: strings.focusTitle,
      playLabel: I18n.tr('focus.floating.start'),
      pauseLabel: I18n.tr('focus.pause'),
      closeLabel: I18n.tr('focus.floating.close'),
      resumeLabel: I18n.tr('focus.floating.resume'),
      pausedLabel: I18n.tr('focus.floating.paused'),
      readyLabel: I18n.tr('focus.floating.ready'),
      focusLabel: strings.focusStateFocus,
      shortBreakLabel: strings.focusStateShortBreak,
      longBreakLabel: strings.focusStateLongBreak,
      windowSize:
          preferences?.pomodoroFloatingWindowSize ??
          PomodoroFloatingWindowSize.defaultSize,
      appearance: {
        'backgroundColor': cardFill.toARGB32(),
        'foregroundColor': cs.onSurface.toARGB32(),
        'windowBackgroundColor': themeData.scaffoldBackgroundColor.toARGB32(),
        'windowForegroundColor': cs.onSurface.toARGB32(),
        'secondaryColor': cs.onSurfaceVariant.toARGB32(),
        'primaryColor': (button?.backgroundColor?.resolve({}) ?? cs.primary)
            .toARGB32(),
        'onPrimaryColor': (button?.foregroundColor?.resolve({}) ?? cs.onPrimary)
            .toARGB32(),
        'borderColor': (border?.color ?? borderColor).toARGB32(),
        'borderWidth': border == null
            ? 0.55
            : border.style == BorderStyle.none
            ? 0.0
            : border.width,
        'cornerRadius': surface?.cardRadius ?? DesignTokens.radiusCard,
        'controlRadius': shape is RoundedRectangleBorder
            ? shape.borderRadius.resolve(Directionality.of(context)).topLeft.x
            : surface?.smallTileRadius ?? DesignTokens.radiusControl,
        'timeFontSize': DesignTokens.fontSizeNumericHighlight,
        'captionFontSize': DesignTokens.fontSizeCaption,
        'buttonFontSize': DesignTokens.fontSizeButton,
      },
    );
    return widget.child;
  }
}

/// 计时页标题栏入口：macOS 上打开/仅隐藏悬浮窗。
class PomodoroFloatingWindowButton extends StatelessWidget {
  const PomodoroFloatingWindowButton({super.key, this.service});

  final PomodoroFloatingWindowService? service;

  @override
  Widget build(BuildContext context) {
    final target = service ?? PomodoroFloatingWindowService.instance;
    if (!target.isSupported) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: target,
      builder: (context, _) {
        final visible = target.isVisible;
        return IconButton(
          tooltip: I18n.tr(
            visible ? 'focus.floating.hide' : 'focus.floating.open',
          ),
          icon: Icon(
            visible
                ? Icons.picture_in_picture_alt
                : Icons.picture_in_picture_alt_outlined,
          ),
          onPressed: () async {
            final messenger = ScaffoldMessenger.maybeOf(context);
            final ok = visible ? await target.hide() : await target.open();
            if (ok || !context.mounted) return;
            final failure = target.takeFailure();
            if (failure == null) return;
            messenger?.showSnackBar(
              SnackBar(
                content: Text(I18n.tr('focus.floating.error')),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        );
      },
    );
  }
}
