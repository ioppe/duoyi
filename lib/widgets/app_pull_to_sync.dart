import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../providers/sync_status_presenter.dart';

/// Android content pages share the same manual sync action as the status card.
/// The bounded outer viewport also makes empty and non-scrolling views pullable.
class AppPullToSync extends StatelessWidget {
  const AppPullToSync({super.key, required this.child});

  final Widget child;

  bool _acceptNotification(ScrollNotification notification) {
    if (notification.metrics.axisDirection != AxisDirection.down) return false;
    // A nested list reaching its own top must not refresh a page that is still
    // scrolled down. Horizontal viewports (page tabs) do not affect this check.
    var scrollable = notification.context == null
        ? null
        : Scrollable.maybeOf(notification.context!);
    while (scrollable != null) {
      if (scrollable.position.axis == Axis.vertical &&
          scrollable.position.extentBefore > 0) {
        return false;
      }
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    return true;
  }

  Future<void> _refresh(
    BuildContext context,
    SyncStatusController controller,
  ) async {
    await controller.requestSync();
    if (!context.mounted ||
        !identical(context.read<SyncStatusController?>(), controller) ||
        (ModalRoute.of(context)?.isCurrent == false)) {
      return;
    }
    if (controller.syncRequestFailed || controller.lastError != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(controller.lastError ?? I18n.tr('sync.state.failed')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return child;
    final controller = context.watch<SyncStatusController?>();
    if (controller == null || !controller.hasSyncAction) return child;

    final behavior = ScrollConfiguration.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => RefreshIndicator(
        edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
        semanticsLabel: I18n.tr('sync.action.sync_now'),
        onRefresh: () => _refresh(context, controller),
        notificationPredicate: _acceptNotification,
        child: ScrollConfiguration(
          behavior: behavior.copyWith(
            physics: AlwaysScrollableScrollPhysics(
              parent: behavior.getScrollPhysics(context),
            ),
          ),
          child: SingleChildScrollView(
            primary: false,
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
