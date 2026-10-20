import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import 'surface_components.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final Widget? iconWidget;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    this.iconWidget,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth.isFinite
            ? constraints.maxWidth < 320
            : false;
        final compact =
            narrow ||
            (constraints.maxHeight.isFinite
                ? constraints.maxHeight < 280
                : false);
        final outerPadding = narrow ? 8.0 : (compact ? 12.0 : 24.0);
        final cardPadding = narrow
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 14)
            : compact
            ? const EdgeInsets.symmetric(horizontal: 18, vertical: 14)
            : const EdgeInsets.symmetric(horizontal: 32, vertical: 28);
        final iconSize = compact ? 44.0 : 72.0;
        final iconGlyphSize = compact ? 24.0 : 36.0;
        final gap = compact ? 10.0 : 20.0;
        final maxCardWidth = constraints.maxWidth.isFinite
            ? math.max(
                0.0,
                math.min(520.0, constraints.maxWidth - outerPadding * 2),
              )
            : 520.0;
        return Center(
          child: Padding(
            padding: EdgeInsets.all(outerPadding),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxCardWidth),
              child: AppSurfaceCard(
                padding: cardPadding,
                borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: iconSize,
                      height: iconSize,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(compact ? 14 : 20),
                      ),
                      child:
                          iconWidget ??
                          Icon(icon, size: iconGlyphSize, color: cs.primary),
                    ),
                    SizedBox(height: gap),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      maxLines: compact ? 3 : null,
                      overflow: compact ? TextOverflow.ellipsis : null,
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.72),
                        fontSize: compact ? 13 : 15,
                        height: compact ? 1.35 : 1.55,
                        fontWeight: DesignTokens.fontWeightStrong,
                      ),
                    ),
                    if (actionLabel != null && onAction != null) ...[
                      SizedBox(height: gap),
                      SizedBox(
                        width: narrow ? double.infinity : null,
                        child: FilledButton.tonalIcon(
                          onPressed: onAction,
                          icon: const Icon(Icons.add, size: 18),
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
            ),
          ),
        );
      },
    );
  }
}
