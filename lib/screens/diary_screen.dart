import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../models/diary_entry.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

/// Compatibility entry for old routes. Stored records remain untouched.
Future<void> showDiaryEditor(
  BuildContext context, {
  DiaryEntry? entry,
  DateTime? initialDate,
}) => Navigator.push<void>(
  context,
  MaterialPageRoute(builder: (_) => const DiaryScreen()),
);

/// Retired route: no records, editing controls, or creation actions.
class DiaryScreen extends StatelessWidget {
  const DiaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(I18n.tr('feature.unavailable')),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppSecondaryControlTheme(
        child: EmptyState(
          icon: Icons.block_outlined,
          message: I18n.tr('feature.unavailable'),
        ),
      ),
    );
  }
}

/// Kept so old constructors remain safe while older launchers still reference it.
class DiaryEditScreen extends StatelessWidget {
  final DiaryEntry? entry;
  final DateTime? initialDate;

  const DiaryEditScreen({super.key, this.entry, this.initialDate});

  @override
  Widget build(BuildContext context) => const DiaryScreen();
}
