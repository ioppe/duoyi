import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../providers/theme_provider.dart';
import 'brand_background.dart';
import 'surface_components.dart';

/// One visual system for password, registration and token entry on all devices.
class AuthPageFrame extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final bool allowBack;

  const AuthPageFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.allowBack = true,
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
              final header = Row(
                children: [
                  if (canGoBack) ...[
                    IconButton(
                      tooltip: I18n.tr('action.back'),
                      onPressed: () => Navigator.of(context).maybePop(),
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
                          style: theme.textTheme.bodySmall?.copyWith(
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
              );
              final form = ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesignTokens.authFormMaxWidth,
                ),
                child: Container(
                  key: const ValueKey('auth_form_surface'),
                  padding: EdgeInsets.all(
                    wide ? DesignTokens.space3xl : DesignTokens.spaceXl,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusXxl),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.45),
                    ),
                    boxShadow: DesignTokens.shadowXs,
                  ),
                  child: AutofillGroup(
                    child: AppFormFieldTheme(
                      child: Column(
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
                        ],
                      ),
                    ),
                  ),
                ),
              );
              return SingleChildScrollView(
                key: const ValueKey('auth_page_scroll'),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.all(inset),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - inset * 2).clamp(
                      0,
                      double.infinity,
                    ),
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
                          header,
                          SizedBox(
                            height: wide
                                ? DesignTokens.space5xl
                                : DesignTokens.space3xl,
                          ),
                          if (wide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Expanded(child: _AuthIntroduction()),
                                const SizedBox(width: DesignTokens.space5xl),
                                Flexible(child: form),
                              ],
                            )
                          else
                            Align(alignment: Alignment.topCenter, child: form),
                          const SizedBox(height: DesignTokens.spaceXxl),
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
