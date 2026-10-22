import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import 'surface_components.dart';

/// Shared empty/error message treatment for pages and card sections. The
/// surrounding page owns its surface, so a state never adds a nested card.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final Widget? iconWidget;
  final Color? iconColor;
  final String message;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData actionIcon;

  const EmptyState({
    super.key,
    required this.icon,
    this.iconWidget,
    this.iconColor,
    required this.message,
    this.description,
    this.actionLabel,
    this.onAction,
    this.actionIcon = Icons.add,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = iconColor ?? cs.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            (constraints.maxWidth.isFinite && constraints.maxWidth < 320) ||
            (constraints.maxHeight.isFinite && constraints.maxHeight < 280);
        final padding = compact ? DesignTokens.spaceMd : DesignTokens.spaceXxl;
        final iconSize = compact
            ? DesignTokens.controlMinHeight
            : DesignTokens.formFieldMinHeight;
        final gap = compact ? DesignTokens.spaceSm : DesignTokens.spaceLg;
        final availableWidth = constraints.maxWidth.isFinite
            ? math.max(0.0, constraints.maxWidth - padding * 2)
            : 480.0;
        final content = Padding(
          padding: EdgeInsets.all(padding),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(480, availableWidth),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: iconSize,
                  height: iconSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                  ),
                  child:
                      iconWidget ??
                      Icon(icon, size: compact ? 24 : 28, color: accent),
                ),
                SizedBox(height: gap),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.onSurface,
                    fontSize: DesignTokens.fontSizeBody,
                    fontWeight: DesignTokens.fontWeightStrong,
                    height: 1.4,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: DesignTokens.spaceSm),
                  Text(
                    description!,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
                if (actionLabel != null && onAction != null) ...[
                  SizedBox(height: gap),
                  AppSecondaryControlTheme(
                    child: FilledButton.tonalIcon(
                      onPressed: onAction,
                      icon: Icon(
                        actionIcon,
                        size: DesignTokens.controlIconSize,
                      ),
                      label: Text(
                        actionLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
        // Short landscape viewports retain readable text and a reachable action.
        return Center(
          child: constraints.hasBoundedHeight
              ? SingleChildScrollView(child: content)
              : content,
        );
      },
    );
  }
}
