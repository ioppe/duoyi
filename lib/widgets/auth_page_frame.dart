import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../providers/theme_provider.dart';
import 'brand_background.dart';
import 'surface_components.dart';

/// Shared, stable-size authentication surface for Web and installed clients.
class AuthPageFrame extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;
  final bool allowBack;
  final Object formModeKey;
  final double additionalHeight;

  const AuthPageFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.footer,
    this.allowBack = true,
    this.formModeKey = 'login',
    this.additionalHeight = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.watch<ThemeProvider>().brand.strings;
    final canGoBack = allowBack && Navigator.of(context).canPop();
    return BrandBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide =
                  constraints.maxWidth >= DesignTokens.authWideBreakpoint;
              final inset = wide ? DesignTokens.space5xl : DesignTokens.spaceXl;
              // Both faces share a policy-sized card. Large text grows the
              // entire card; only the surrounding page can scroll.
              final baseHeight =
                  (wide
                      ? DesignTokens.authCardHeightWide
                      : DesignTokens.authCardHeightMobile) +
                  additionalHeight;
              final textScale = math.max(
                1.0,
                MediaQuery.textScalerOf(
                      context,
                    ).scale(DesignTokens.fontSizeBody) /
                    DesignTokens.fontSizeBody,
              );
              final cardHeight = math.max(
                DesignTokens.authCardMinHeight,
                baseHeight *
                    (1 +
                        (textScale - 1) * DesignTokens.authCardTextScaleFactor),
              );
              final padding = wide
                  ? DesignTokens.space3xl
                  : DesignTokens.spaceXl;
              final face = Container(
                key: ValueKey(formModeKey),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusXxl),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.45),
                  ),
                  boxShadow: DesignTokens.shadowXs,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusXxl),
                  child: AuthFormFieldTheme(
                    child: Padding(
                      padding: EdgeInsets.all(padding),
                      child: Center(
                        child: AutofillGroup(
                          child: Column(
                            key: const ValueKey('auth_form_content'),
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                title,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontSize: DesignTokens.fontSizeXxl,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: DesignTokens.spaceSm),
                              Text(
                                subtitle,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  height: 1.6,
                                ),
                              ),
                              const SizedBox(height: DesignTokens.spaceXxl),
                              child,
                              if (footer != null) ...[
                                const SizedBox(height: DesignTokens.spaceXxl),
                                footer!,
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              final form = ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesignTokens.authFormMaxWidth,
                ),
                child: SizedBox(
                  key: const ValueKey('auth_form_surface'),
                  height: cardHeight,
                  child: _AuthFlipCard(mode: formModeKey, child: face),
                ),
              );
              return SingleChildScrollView(
                key: const ValueKey('auth_outer_scroll'),
                padding: EdgeInsets.all(inset),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(0, constraints.maxHeight - inset * 2),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: DesignTokens.authPageMaxWidth,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              if (canGoBack) ...[
                                IconButton(
                                  tooltip: I18n.tr('action.back'),
                                  onPressed: () =>
                                      Navigator.of(context).maybePop(),
                                  icon: const Icon(Icons.arrow_back_rounded),
                                ),
                                const SizedBox(width: DesignTokens.spaceSm),
                              ],
                              Container(
                                width: DesignTokens.authLogoSize,
                                height: DesignTokens.authLogoSize,
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  borderRadius: DesignTokens.borderRadiusLg,
                                ),
                                child: Icon(
                                  Icons.space_dashboard_rounded,
                                  color: cs.onPrimary,
                                ),
                              ),
                              const SizedBox(width: DesignTokens.spaceMd),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      strings.appTitle,
                                      style: theme.textTheme.titleLarge,
                                    ),
                                    Text(
                                      I18n.tr('auth.design.tagline'),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              if (wide)
                                Text(
                                  I18n.tr('auth.design.everyday'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(
                            height: wide
                                ? DesignTokens.space5xl
                                : DesignTokens.spaceXxl,
                          ),
                          if (wide)
                            Row(
                              children: [
                                const Expanded(child: _AuthIntroduction()),
                                const SizedBox(width: DesignTokens.space5xl),
                                Flexible(child: form),
                              ],
                            )
                          else
                            Align(alignment: Alignment.topCenter, child: form),
                          const SizedBox(height: DesignTokens.spaceLg),
                          Text(
                            I18n.tr('auth.design.footer'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Single-line auth inputs share a fixed, text-scale-aware row extent.
/// Icon-free confirmation fields and code actions use the same geometry.
class AuthFormFieldTheme extends StatelessWidget {
  final Widget child;

  const AuthFormFieldTheme({super.key, required this.child});

  static double heightOf(BuildContext context) {
    final contentHeight =
        MediaQuery.textScalerOf(context).scale(DesignTokens.fontSizeMd) * 1.5 +
        DesignTokens.spaceLg * 2;
    // Whole logical pixels keep Linux text metrics and visible borders aligned
    // when a text scale would otherwise produce a fractional row height.
    return math
        .max(DesignTokens.formFieldMinHeight, contentHeight)
        .ceilToDouble();
  }

  @override
  Widget build(BuildContext context) => AppFormFieldTheme(
    child: Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final height = heightOf(context);
        final scaledFontSize = MediaQuery.textScalerOf(
          context,
        ).scale(DesignTokens.fontSizeMd);
        // InputDecorator sizes icon-free borders from the content line, not
        // from its minimum constraint. Keep that line inside the shared row.
        final inputLineHeight = scaledFontSize > 0
            ? (height - DesignTokens.spaceLg * 2) / scaledFontSize
            : 1.5;
        return Theme(
          data: theme.copyWith(
            textTheme: theme.textTheme.copyWith(
              bodyLarge: theme.textTheme.bodyLarge?.copyWith(
                height: inputLineHeight,
              ),
              titleMedium: theme.textTheme.titleMedium?.copyWith(
                height: inputLineHeight,
              ),
            ),
            inputDecorationTheme: theme.inputDecorationTheme.copyWith(
              constraints: BoxConstraints.tightFor(height: height),
              // Compact desktop density otherwise shortens icon-free borders.
              visualDensity: VisualDensity.standard,
              filled: true,
              fillColor: theme.colorScheme.surface,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              prefixIconConstraints: BoxConstraints.tightFor(
                width: DesignTokens.formFieldMinHeight,
                height: height,
              ),
              suffixIconConstraints: BoxConstraints.tightFor(
                width: DesignTokens.formFieldMinHeight,
                height: height,
              ),
            ),
          ),
          child: child,
        );
      },
    ),
  );
}

/// Only one face is mounted at a time: controllers, focus and autofill never
/// belong to simultaneous outgoing/incoming forms. Motion follows the toggle.
class _AuthFlipCard extends StatefulWidget {
  final Object mode;
  final Widget child;
  const _AuthFlipCard({required this.mode, required this.child});

  @override
  State<_AuthFlipCard> createState() => _AuthFlipCardState();
}

class _AuthFlipCardState extends State<_AuthFlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: DesignTokens.authFlipDuration,
    value: 1,
  );
  Widget? _outgoing;
  bool _reduceMotion = false;
  double _direction = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _controller.value = 1;
  }

  @override
  void didUpdateWidget(_AuthFlipCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _direction = -_direction;
      _outgoing = oldWidget.child;
      _controller.forward(from: _reduceMotion ? 1 : 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final progress = Curves.easeInOutCubic.transform(_controller.value);
      final front = progress < 0.5 && _outgoing != null;
      final angle = (front ? progress : progress - 1) * math.pi * _direction;
      return IgnorePointer(
        ignoring: _controller.isAnimating,
        child: ExcludeSemantics(
          excluding: _controller.isAnimating,
          child: Transform(
            key: const ValueKey('auth_card_flip'),
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: front ? _outgoing! : widget.child,
          ),
        ),
      );
    },
  );
}

enum AuthMethod { password, emailCode, token }

/// Selected and unselected methods share exactly the same text and box metrics.
class AuthMethodSelector extends StatelessWidget {
  final AuthMethod selected;
  final bool showEmailCode;
  final bool showToken;
  final ValueChanged<AuthMethod>? onChanged;

  const AuthMethodSelector({
    super.key,
    required this.selected,
    required this.showEmailCode,
    required this.showToken,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = theme.textTheme.labelLarge!.copyWith(
      fontSize: DesignTokens.fontSizeButton,
      fontWeight: DesignTokens.fontWeightStrong,
      height: 1.3,
    );
    final options = <(AuthMethod, String)>[
      (AuthMethod.password, I18n.tr('auth.password_login')),
      if (showEmailCode)
        (AuthMethod.emailCode, I18n.tr('auth.email_code_login')),
      if (showToken) (AuthMethod.token, I18n.tr('auth.token.login')),
    ];
    final scaler = MediaQuery.textScalerOf(context);
    var labelWidth = 0.0;
    var labelHeight = 0.0;
    for (final option in options) {
      final painter = TextPainter(
        text: TextSpan(text: option.$2, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      labelWidth = math.max(labelWidth, painter.width);
      labelHeight = math.max(labelHeight, painter.height);
      painter.dispose();
    }
    final height = math.max(
      DesignTokens.controlMinHeight,
      labelHeight + DesignTokens.spaceLg,
    );
    return SizedBox(
      key: const ValueKey('auth_method_selector'),
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.max(
            constraints.maxWidth,
            (labelWidth + DesignTokens.spaceXxl) * options.length,
          );
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Row(
                children: [
                  for (var index = 0; index < options.length; index++) ...[
                    if (index > 0) const SizedBox(width: DesignTokens.spaceXs),
                    Expanded(
                      child: Semantics(
                        selected: selected == options[index].$1,
                        child: TextButton(
                          key: ValueKey(
                            'auth-method-${options[index].$1.name}',
                          ),
                          onPressed: onChanged == null
                              ? null
                              : () => onChanged!(options[index].$1),
                          style: TextButton.styleFrom(
                            textStyle: style,
                            minimumSize: Size(0, height),
                            padding: const EdgeInsets.symmetric(
                              horizontal: DesignTokens.spaceSm,
                            ),
                            foregroundColor: selected == options[index].$1
                                ? cs.primary
                                : cs.onSurfaceVariant,
                            backgroundColor: selected == options[index].$1
                                ? cs.primary.withValues(alpha: 0.10)
                                : Colors.transparent,
                            shape: const RoundedRectangleBorder(
                              borderRadius: DesignTokens.borderRadiusMd,
                            ),
                            side: BorderSide(
                              color: selected == options[index].$1
                                  ? cs.primary.withValues(alpha: 0.3)
                                  : cs.outlineVariant,
                            ),
                          ),
                          child: Text(options[index].$2, maxLines: 1),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AuthIntroduction extends StatelessWidget {
  const _AuthIntroduction();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.watch<ThemeProvider>().brand.strings;
    return Padding(
      key: const ValueKey('auth_desktop_introduction'),
      padding: const EdgeInsets.only(right: DesignTokens.space3xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: DesignTokens.space3xl,
            height: DesignTokens.spaceXs,
            color: cs.primary,
          ),
          const SizedBox(height: DesignTokens.spaceXxl),
          Text(
            I18n.tr('auth.design.headline'),
            style: theme.textTheme.displaySmall?.copyWith(
              fontSize: DesignTokens.authHeroSize,
              height: 1.4,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: DesignTokens.spaceLg),
          Text(
            I18n.tr('auth.design.description'),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.8,
            ),
          ),
          const SizedBox(height: DesignTokens.space4xl),
          _AuthFeature(
            icon: Icons.check_circle_outline_rounded,
            title: strings.navTodo,
            description: I18n.tr('auth.design.tasks'),
          ),
          const SizedBox(height: DesignTokens.spaceXl),
          _AuthFeature(
            icon: Icons.repeat_rounded,
            title: strings.navHabit,
            description: I18n.tr('auth.design.habits'),
          ),
          const SizedBox(height: DesignTokens.spaceXl),
          _AuthFeature(
            icon: Icons.timelapse_rounded,
            title: strings.navFocus,
            description: I18n.tr('auth.design.focus'),
          ),
        ],
      ),
    );
  }
}

class _AuthFeature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  const _AuthFeature({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: DesignTokens.controlMinHeight,
          height: DesignTokens.controlMinHeight,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.09),
            borderRadius: DesignTokens.borderRadiusMd,
          ),
          child: Icon(
            icon,
            color: cs.primary,
            size: DesignTokens.controlIconSize,
          ),
        ),
        const SizedBox(width: DesignTokens.spaceLg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: DesignTokens.spaceXs),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AuthNotice extends StatelessWidget {
  final String message;
  final bool isError;
  const AuthNotice({super.key, required this.message, this.isError = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = isError ? cs.error : cs.primary;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(DesignTokens.spaceMd),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: DesignTokens.borderRadiusMd,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.info_outline_rounded,
              size: DesignTokens.controlIconSize,
              color: color,
            ),
            const SizedBox(width: DesignTokens.spaceSm),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: color, height: 1.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
