import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

/// Page-level creation action. Place in Scaffold.floatingActionButton so the
/// primary entry stays at the lower end on phones and desktop layouts alike.
class AppCreateFab extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final String? tooltip;
  final Color? backgroundColor;

  const AppCreateFab({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.add,
    this.tooltip,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final maxLabelWidth =
        (MediaQuery.sizeOf(context).width - DesignTokens.space5xl * 2).clamp(
          0.0,
          double.infinity,
        );
    return FloatingActionButton.extended(
      onPressed: onPressed,
      tooltip: tooltip ?? label,
      backgroundColor: backgroundColor,
      extendedTextStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        fontSize: DesignTokens.fontSizeButton,
        fontWeight: DesignTokens.fontWeightStrong,
      ),
      icon: Icon(icon),
      label: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxLabelWidth),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
