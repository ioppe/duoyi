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

/// 卡内可用宽度低于该值时，趋势从分数右侧移到下方。
///
/// 320px 手机上卡片内容宽约 256px（页面 12px 边距 + 卡内 20px 内距），
/// 属于换行档；390px 手机上约 326px，与分数同行。这是排版断点，不是视觉尺寸，
/// 因此不放进 DesignTokens。
const double _trendInlineMinWidth = 300;

/// 标签字号被放大超过该倍数时，趋势同样移到分数下方，避免与分数抢同一行。
const double _trendInlineMaxLabelScale = 1.3;

/// 三栏统计每栏所需的最小宽度：设计基线 5 个标签字宽（14 × 5）。
///
/// 该基线固定在设计字号上，再按用户字号倍率放大；不直接乘当前标签令牌，
/// 否则共享令牌变小（14 → 12）时阈值被一起缩小，320px + 2x 会被判成两列。
const double _statColumnDesignMinWidth = 70;

/// “我的”页的本周效率摘要，按应用时区比较本周与上周同段。
///
/// 视觉：中性 theme surface 卡面、20px 圆角与内距、轻量 history 图标标题行、
/// 大号效率分、细分隔线后的三栏统计。所有颜色 / 字阶 / 间距 / 圆角都走
/// `Theme.of(context).colorScheme` 与 `DesignTokens`。
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
    final isDark = theme.brightness == Brightness.dark;
    final direction = comparison.productivityScore.direction;
    final difference = comparison.productivityScore.difference.round();
    final trendColor = _trendColor(cs, theme.brightness, direction);
    final trendIcon = switch (direction) {
      ReportTrendDirection.up => Icons.trending_up,
      ReportTrendDirection.down => Icons.trending_down,
      ReportTrendDirection.flat => Icons.trending_flat,
    };
    final trendValue = difference == 0
        ? I18n.tr('today.productivity.flat')
        : '${difference > 0 ? '+' : ''}$difference ${I18n.tr('today.unit.point')}';
    final scoreLabel = I18n.tr('today.productivity.score');
    final weeklyLabel = I18n.tr('today.productivity.weekly');
    final stats = <_WeeklyStat>[
      _WeeklyStat(
        label: I18n.tr('today.productivity.completion_rate'),
        value: '${(current.todoCompletionRate * 100).round()}%',
      ),
      _WeeklyStat(
        label: I18n.tr('nav.focus'),
        value: '${current.focusMinutes}${I18n.tr('unit.min')}',
      ),
      _WeeklyStat(
        label: I18n.tr('nav.habit'),
        value: '${current.habitCheckIns}${I18n.tr('today.unit.times')}',
      ),
    ];
    return Semantics(
      // 整卡是一个按钮：语义节点显式拥有 onTap，卡内文字不再各自成为
      // 可聚焦节点（ExcludeSemantics），避免读屏重复遍历与重复交互节点。
      container: true,
      button: true,
      onTap: onTap,
      label: [
        I18n.tr('today.productivity.title'),
        weeklyLabel,
        '$scoreLabel ${current.productivityScore}',
        '${I18n.tr('today.productivity.comparison')} $trendValue',
        for (final stat in stats) '${stat.label} ${stat.value}',
      ].join(' · '),
      hint: I18n.tr('today.productivity.subtitle'),
      child: ExcludeSemantics(
        child: AppSurfaceCard(
          onTap: onTap,
          borderRadius: DesignTokens.borderRadiusXl,
          padding: const EdgeInsets.all(DesignTokens.spaceXl),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScaler = MediaQuery.textScalerOf(context);
              final labelSize = textScaler.scale(
                DesignTokens.fontSizeSecondary,
              );
              final trendInline =
                  constraints.maxWidth >= _trendInlineMinWidth &&
                  labelSize <=
                      DesignTokens.fontSizeSecondary *
                          _trendInlineMaxLabelScale;
              final statMinWidth =
                  _statColumnDesignMinWidth *
                  (labelSize / DesignTokens.fontSizeSecondary);
              final columns =
                  (constraints.maxWidth - DesignTokens.spaceMd * 2) / 3 >=
                      statMinWidth
                  ? 3
                  : (constraints.maxWidth - DesignTokens.spaceMd) / 2 >=
                        statMinWidth
                  ? 2
                  : 1;
              final scoreBlock = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    weeklyLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: DesignTokens.fontSizeSecondary,
                      fontWeight: DesignTokens.fontWeightMedium,
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceXxs),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: DesignTokens.spaceSm,
                    runSpacing: DesignTokens.spaceXxs,
                    children: [
                      Text(
                        '${current.productivityScore}',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontSize: DesignTokens.fontSizeXxl,
                          fontWeight: DesignTokens.fontWeightStrong,
                          color: cs.onSurface,
                          height: 1.1,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: DesignTokens.spaceXs,
                        ),
                        child: Text(
                          scoreLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: DesignTokens.fontSizeSecondary,
                            fontWeight: DesignTokens.fontWeightRegular,
                            color: cs.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
              final trendBlock = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: trendInline
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: DesignTokens.spaceXs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Icon(
                        trendIcon,
                        size: DesignTokens.controlIconSize,
                        color: trendColor,
                      ),
                      Text(
                        trendValue,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: DesignTokens.fontSizeSecondary,
                          fontWeight: DesignTokens.fontWeightMedium,
                          color: trendColor,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: DesignTokens.spaceXxs),
                  Text(
                    I18n.tr('today.productivity.comparison'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: DesignTokens.fontSizeCaption,
                      fontWeight: DesignTokens.fontWeightRegular,
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.history,
                        size: DesignTokens.controlIconSize,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: DesignTokens.spaceSm),
                      Expanded(
                        child: Text(
                          I18n.tr('today.productivity.title'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: DesignTokens.fontSizeCardTitle,
                            fontWeight: DesignTokens.fontWeightStrong,
                            color: cs.onSurface,
                            height: 1.3,
                          ),
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
                  const SizedBox(height: DesignTokens.spaceMd),
                  if (trendInline)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: scoreBlock),
                        const SizedBox(width: DesignTokens.spaceMd),
                        trendBlock,
                      ],
                    )
                  else ...[
                    scoreBlock,
                    const SizedBox(height: DesignTokens.spaceSm),
                    trendBlock,
                  ],
                  Divider(
                    height: DesignTokens.spaceXl,
                    color: cs.onSurface.withValues(alpha: isDark ? 0.16 : 0.08),
                  ),
                  _WeeklyStatsGrid(stats: stats, columns: columns),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 趋势色沿用语义色 token；深色主题向 `onSurface` 混合，保证深底上可读。
Color _trendColor(
  ColorScheme cs,
  Brightness brightness,
  ReportTrendDirection direction,
) {
  final isDark = brightness == Brightness.dark;
  return switch (direction) {
    ReportTrendDirection.up =>
      isDark
          ? Color.lerp(DesignTokens.defaultSuccess, cs.onSurface, 0.45) ??
                cs.onSurface
          : DesignTokens.defaultSuccess,
    ReportTrendDirection.down =>
      isDark
          ? Color.lerp(DesignTokens.defaultError, cs.onSurface, 0.35) ??
                cs.onSurface
          : DesignTokens.defaultError,
    ReportTrendDirection.flat => cs.onSurfaceVariant,
  };
}

/// 三栏统计：数值在上、标签在下；可用宽度不足时按 [columns] 减列换行。
class _WeeklyStatsGrid extends StatelessWidget {
  final List<_WeeklyStat> stats;
  final int columns;

  const _WeeklyStatsGrid({required this.stats, required this.columns});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var start = 0; start < stats.length; start += columns) {
      final end = start + columns <= stats.length
          ? start + columns
          : stats.length;
      final row = stats.sublist(start, end);
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < row.length; index++) ...[
              if (index > 0) const SizedBox(width: DesignTokens.spaceMd),
              Expanded(child: row[index]),
            ],
            // 末行不足列数时补空位，保持各列宽度与满行一致。
            for (var index = row.length; index < columns; index++) ...[
              const SizedBox(width: DesignTokens.spaceMd),
              const Expanded(child: SizedBox.shrink()),
            ],
          ],
        ),
      );
      if (end < stats.length) {
        rows.add(const SizedBox(height: DesignTokens.spaceMd));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _WeeklyStat extends StatelessWidget {
  final String label;
  final String value;

  const _WeeklyStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: DesignTokens.fontSizeLg,
            fontWeight: DesignTokens.fontWeightMedium,
            color: cs.onSurface,
            height: 1.2,
          ),
        ),
        const SizedBox(height: DesignTokens.spaceXxs),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: DesignTokens.fontSizeCaption,
            fontWeight: DesignTokens.fontWeightRegular,
            color: cs.onSurfaceVariant,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}
