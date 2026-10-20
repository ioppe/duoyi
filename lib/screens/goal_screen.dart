import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/goal_icons.dart';
import '../models/goal.dart';
import '../providers/goal_provider.dart';
import '../providers/share_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';
import 'goal_edit_screen.dart';
import 'recommended_goals_picker.dart';

class GoalScreen extends StatelessWidget {
  const GoalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GoalProvider>();
    final goals = provider.goals;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(goalFeatureIconAsset, width: 24, height: 24),
            const SizedBox(width: 8),
            Text(I18n.tr('goal.title')),
          ],
        ),
        actions: [
          IconButton(
            tooltip: I18n.tr('goal.recommended_templates'),
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => _openRecommended(context),
          ),
        ],
      ),
      body: goals.isEmpty
          ? EmptyState(
              icon: Icons.flag_circle_outlined,
              iconWidget: Image.asset(
                goalFeatureIconAsset,
                width: 40,
                height: 40,
              ),
              message: I18n.tr('goal.empty'),
              actionLabel: I18n.tr('goal.create'),
              onAction: () => _openEdit(context),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: goals.length,
              itemBuilder: (_, i) => _GoalCard(goal: goals[i]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(context),
        icon: const Icon(Icons.add),
        label: Text(I18n.tr('goal.new')),
      ),
    );
  }

  void _openEdit(BuildContext context, {GoalItem? goal}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GoalEditScreen(goal: goal)),
    );
  }

  void _openRecommended(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecommendedGoalsPicker()),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final GoalItem goal;
  const _GoalCard({required this.goal});

  Color _statusColor() => switch (goal.status) {
    GoalStatus.active => const Color(0xFF66BB6A),
    GoalStatus.paused => Colors.grey,
    GoalStatus.achieved => const Color(0xFFFFA726),
    GoalStatus.abandoned => Colors.red.shade300,
  };

  String _statusText() => switch (goal.status) {
    GoalStatus.active => I18n.tr('goal.status.active'),
    GoalStatus.paused => I18n.tr('goal.status.paused'),
    GoalStatus.achieved => I18n.tr('goal.status.achieved'),
    GoalStatus.abandoned => I18n.tr('goal.status.abandoned'),
  };

  @override
  Widget build(BuildContext context) {
    final color = Color(goal.colorValue);
    final progress = goal.computedProgress;
    final days = goal.daysRemaining;
    final hasDeadline = goal.targetDate != null;
    final deadlineLabel = hasDeadline
        ? (days >= 0
              ? '${I18n.tr('goal.days_remaining.prefix')}$days'
                    '${I18n.tr('goal.days_remaining.suffix')}'
              : '${I18n.tr('goal.overdue.prefix')}${-days}'
                    '${I18n.tr('goal.overdue.suffix')}')
        : '无期限';
    final deadlineColor = !hasDeadline || days >= 0
        ? Colors.grey.shade600
        : Colors.red;
    final shareProvider = context.watch<ShareProvider?>();
    final isShared =
        goal.workspaceId.trim().isNotEmpty &&
        goal.workspaceId.trim() != 'private';

    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GoalEditScreen(goal: goal)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(goalIconFromName(goal.icon), color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            goal.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: DesignTokens.fontWeightStrong,
                            ),
                          ),
                        ),
                        if (isShared) ...[
                          const SizedBox(width: 6),
                          _SharedGoalBadge(
                            label: _workspaceLabel(
                              shareProvider,
                              goal.workspaceId.trim(),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (goal.description.isNotEmpty)
                      Text(
                        goal.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor().withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _statusText(),
                  style: TextStyle(
                    fontSize: 11,
                    color: _statusColor(),
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: color.withValues(alpha: 0.1),
                    color: color,
                    minHeight: 8,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: color,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _GoalMetaChip(
                icon: Icons.check_circle_outline,
                label:
                    '${I18n.tr('goal.milestone.prefix')}'
                    '${goal.milestones.where((m) => m.isCompleted).length}/'
                    '${goal.milestones.length}',
                color: Colors.grey.shade600,
              ),
              _GoalMetaChip(
                icon: hasDeadline ? Icons.schedule : Icons.all_inclusive,
                label: deadlineLabel,
                color: deadlineColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _workspaceLabel(ShareProvider? provider, String workspaceId) {
    for (final workspace in provider?.workspaces ?? const []) {
      if (workspace.id == workspaceId) return workspace.name;
    }
    return '共享';
  }
}

class _GoalMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _GoalMetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _SharedGoalBadge extends StatelessWidget {
  final String label;

  const _SharedGoalBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 96),
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceXs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_2_outlined, size: 12, color: cs.primary),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                color: cs.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
