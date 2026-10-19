import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_clock.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/report_engine.dart';
import '../models/time_entry.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/time_audit_provider.dart';
import '../providers/todo_provider.dart';
import 'surface_components.dart';

/// “我的”页的本周效率摘要，按应用时区比较本周与上周同段。
class WeeklyProductivityCard extends StatelessWidget {
  final VoidCallback onTap;

  const WeeklyProductivityCard({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final todos = context.watch<TodoProvider>().todos;
    final habits = context.watch<HabitProvider>().habits;
    context.select<PomodoroProvider, int>(
      (provider) => provider.persistedRevision,
    );
    final sessions = context.read<PomodoroProvider>().sessions;
    final timeEntries =
        context.watch<TimeAuditProvider?>()?.entries ?? const <TimeEntry>[];
    final now = AppClock.now();
    // ReportEngine interprets these calendar fields in the application zone.
    // UTC date values keep scoring day counts independent of device DST/zone.
    final end = DateTime.utc(now.year, now.month, now.day);
    final start = DateTime.utc(now.year, now.month, now.day - now.weekday + 1);
    final previousStart = DateTime.utc(start.year, start.month, start.day - 7);
    final previousEnd = DateTime.utc(end.year, end.month, end.day - 7);
    final current = ReportEngine.buildReport(
      start: start,
      end: end,
      todos: todos,
      habits: habits,
      sessions: sessions,
      timeEntries: timeEntries,
    );
    final previous = ReportEngine.buildReport(
      start: previousStart,
      end: previousEnd,
      todos: todos,
      habits: habits,
      sessions: sessions,
      timeEntries: timeEntries,
    );
    final comparison = ReportEngine.compare(
      current: current,
      previous: previous,
    );
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final direction = comparison.productivityScore.direction;
    final difference = comparison.productivityScore.difference.round();
    final trendColor = switch (direction) {
      ReportTrendDirection.up => DesignTokens.defaultSuccess,
      ReportTrendDirection.down => DesignTokens.defaultError,
      ReportTrendDirection.flat => cs.onSurfaceVariant,
    };
    final scaler = MediaQuery.textScalerOf(context);
    final scoreSize =
        (scaler.scale(DesignTokens.fontSizeXl) +
                scaler.scale(DesignTokens.fontSizeXs) * 1.4 +
                DesignTokens.spaceSm)
            .clamp(64.0, double.infinity);
    return AppSurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(DesignTokens.spaceLg),
      gradient: LinearGradient(
        colors: [
          Color.alphaBlend(cs.primary.withValues(alpha: 0.05), cs.surface),
          cs.surface,
        ],
      ),
      child: Row(
        children: [
          Container(
            width: scoreSize,
            height: scoreSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withValues(alpha: 0.10),
              border: Border.all(color: cs.primary.withValues(alpha: 0.28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  current.productivityScore.toString(),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: DesignTokens.fontSizeXl,
                    color: cs.primary,
                    height: 1,
                    fontWeight: DesignTokens.fontWeightRegular,
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceXxs),
                Text(
                  I18n.tr('today.productivity.score'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: DesignTokens.fontSizeXs,
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DesignTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        I18n.tr('today.productivity.weekly'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: DesignTokens.fontSizeMd,
                          color: cs.onSurface,
                          fontWeight: DesignTokens.fontWeightRegular,
                        ),
                      ),
                    ),
                    const SizedBox(width: DesignTokens.spaceXs),
                    Icon(
                      switch (direction) {
                        ReportTrendDirection.up => Icons.trending_up,
                        ReportTrendDirection.down => Icons.trending_down,
                        ReportTrendDirection.flat => Icons.trending_flat,
                      },
                      color: trendColor,
                      size: DesignTokens.fontSizeMd,
                    ),
                    const SizedBox(width: DesignTokens.spaceXs),
                    Flexible(
                      child: Text(
                        difference == 0
                            ? I18n.tr('today.productivity.flat')
                            : '${difference > 0 ? '+' : ''}$difference ${I18n.tr('today.unit.point')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: DesignTokens.fontSizeSecondary,
                          color: trendColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DesignTokens.spaceXs),
                Text(
                  I18n.tr('today.productivity.subtitle'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: DesignTokens.fontSizeSecondary,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceSm),
                Wrap(
                  spacing: DesignTokens.spaceSm,
                  runSpacing: DesignTokens.spaceXs,
                  children: [
                    _WeeklyMetric(
                      label: I18n.tr('today.productivity.completion_rate'),
                      value: '${(current.todoCompletionRate * 100).round()}%',
                    ),
                    _WeeklyMetric(
                      label: I18n.tr('nav.focus'),
                      value: '${current.focusMinutes}${I18n.tr('unit.min')}',
                    ),
                    _WeeklyMetric(
                      label: I18n.tr('nav.habit'),
                      value:
                          '${current.habitCheckIns}${I18n.tr('today.unit.times')}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: DesignTokens.spaceXs),
          Icon(
            Icons.chevron_right,
            size: DesignTokens.controlIconSize,
            color: cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _WeeklyMetric extends StatelessWidget {
  final String label;
  final String value;

  const _WeeklyMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceSm,
        vertical: DesignTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: DesignTokens.borderRadiusSm,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            TextSpan(
              text: value,
              style: TextStyle(color: cs.onSurface),
            ),
          ],
        ),
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: DesignTokens.fontSizeSecondary,
        ),
      ),
    );
  }
}
