import 'package:flutter/material.dart';

import '../core/focus_task_stats.dart';
import '../core/i18n.dart';
import 'surface_components.dart';

class FocusTaskStatsCard extends StatelessWidget {
  final List<FocusTaskSummary> stats;

  const FocusTaskStatsCard({super.key, required this.stats});

  static String duration(int seconds) {
    if (seconds < 60) return '$seconds ${I18n.tr('focus.tasks.seconds')}';
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    final text = '$minutes ${I18n.tr('focus.tasks.minutes')}';
    return remainder == 0
        ? text
        : '$text $remainder ${I18n.tr('focus.tasks.seconds')}';
  }

  String _metrics(int seconds, int sessions) =>
      '${duration(seconds)} · $sessions ${I18n.tr('focus.tasks.sessions')}';

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            I18n.tr('focus.tasks.results'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            I18n.tr('focus.tasks.results_hint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (stats.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(I18n.tr('focus.tasks.results_empty')),
            ),
          for (final stat in stats)
            if (stat.parts.any((part) => part.subtaskId != null))
              ExpansionTile(
                key: ValueKey('focus_task_result_${stat.key}'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(left: 20),
                title: Text(stat.title ?? I18n.tr('focus.tasks.unassigned')),
                subtitle: Text(_metrics(stat.seconds, stat.sessions)),
                leading: const Icon(Icons.account_tree_outlined),
                shape: const Border(),
                collapsedShape: const Border(),
                children: [
                  for (final part in stat.parts)
                    ListTile(
                      key: ValueKey(
                        'focus_task_part_${stat.key}_${part.subtaskId ?? 'parent'}',
                      ),
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        part.title ?? I18n.tr('focus.tasks.whole_task'),
                      ),
                      subtitle: Text(_metrics(part.seconds, part.sessions)),
                    ),
                ],
              )
            else
              ListTile(
                key: ValueKey('focus_task_result_${stat.key}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  stat.todoId == null ? Icons.timer_outlined : Icons.task_alt,
                ),
                title: Text(stat.title ?? I18n.tr('focus.tasks.unassigned')),
                subtitle: Text(_metrics(stat.seconds, stat.sessions)),
              ),
        ],
      ),
    );
  }
}
