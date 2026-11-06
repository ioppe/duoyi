import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../providers/pomodoro_provider.dart';

/// A compact account-focus indicator beside the current phase title.
class FocusSyncStatus extends StatelessWidget {
  const FocusSyncStatus({
    super.key,
    required this.provider,
    required this.isLoggedIn,
  });

  final PomodoroProvider provider;
  final bool isLoggedIn;

  @override
  Widget build(BuildContext context) {
    final synced =
        isLoggedIn &&
        provider.focusSyncEnabled &&
        provider.focusSyncReady &&
        provider.focusSyncConnected &&
        provider.focusSyncError == null;
    final message = I18n.tr(
      !isLoggedIn
          ? 'focus.sync.login_required'
          : synced
          ? 'focus.sync.connected'
          : 'focus.sync.offline',
    );
    final outline = Theme.of(context).colorScheme.onSurfaceVariant;

    return IconButton(
      key: const ValueKey('focus_sync_status_button'),
      tooltip: message,
      constraints: const BoxConstraints(
        minWidth: DesignTokens.controlMinHeight,
        minHeight: DesignTokens.controlMinHeight,
      ),
      padding: const EdgeInsets.all(DesignTokens.spaceSm),
      iconSize: DesignTokens.controlIconSize,
      icon: ExcludeSemantics(
        child: SizedBox.square(
          dimension: DesignTokens.controlIconSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.cloud, color: DesignTokens.defaultSurface),
              Icon(
                synced ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                color: outline,
              ),
            ],
          ),
        ),
      ),
      onPressed: () {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
            ),
          );
      },
    );
  }
}
