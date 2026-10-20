import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/statistics_period.dart';
import 'habit_heatmap.dart';
import 'surface_components.dart';

class StatisticsActivityCard extends StatelessWidget {
  final StatisticsWindow window;
  final Map<String, int> heatmapData;

  const StatisticsActivityCard({
    super.key,
    required this.window,
    required this.heatmapData,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeDays = heatmapData.entries.where((entry) {
      final date = DateTime.tryParse(entry.key);
      return date != null && window.containsDate(date) && entry.value > 0;
    }).length;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(DesignTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: DesignTokens.spaceMd,
            runSpacing: DesignTokens.spaceXs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                I18n.tr('statistics.activity.${window.period.name}'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                I18n.tr(
                  'statistics.activity.days',
                ).replaceAll('{days}', '$activeDays'),
                key: const ValueKey('statistics_activity_days'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.primary),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spaceXs),
          Text(
            I18n.tr('statistics.activity.description'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          if (window.period == StatisticsPeriod.year)
            HabitHeatmap(
              heatmapData: heatmapData,
              startDate: window.start,
              endDate: window.calendarEnd,
            )
          else
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: _calendar(context),
              ),
            ),
          const SizedBox(height: DesignTokens.spaceSm),
          Text(
            I18n.tr('statistics.activity.hint'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _calendar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final monthly = window.period == StatisticsPeriod.month;
    final leading = monthly ? window.start.weekday - 1 : 0;
    final count = window.calendarEnd.difference(window.start).inDays + 1;
    final rows = ((leading + count) / 7).ceil();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (var day = 1; day <= 7; day++)
              Expanded(
                child: Text(
                  I18n.tr('habit.weekday.$day'),
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
        const SizedBox(height: DesignTokens.spaceSm),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rows * 7,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: DesignTokens.spaceXs,
            crossAxisSpacing: DesignTokens.spaceXs,
          ),
          itemBuilder: (context, index) {
            final offset = index - leading;
            if (offset < 0 || offset >= count) return const SizedBox.shrink();
            final date = window.start.add(Duration(days: offset));
            final key =
                '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
            final future = date.isAfter(window.end);
            final intensity = future ? 0 : (heatmapData[key] ?? 0).clamp(0, 5);
            final color = future
                ? cs.surfaceContainerHighest.withValues(alpha: 0.22)
                : intensity == 0
                ? cs.surfaceContainerHighest.withValues(alpha: 0.5)
                : Color.lerp(
                    cs.surface,
                    cs.primaryContainer,
                    0.22 + intensity * 0.15,
                  )!;
            final cell = Container(
              key: ValueKey('statistics_activity_$key'),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color,
                borderRadius: DesignTokens.borderRadiusSm,
                border: Border.all(
                  color: date == window.end
                      ? cs.primary
                      : cs.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                '${date.day}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: future
                      ? cs.onSurface.withValues(alpha: 0.3)
                      : intensity > 0
                      ? cs.onPrimaryContainer
                      : cs.onSurfaceVariant,
                ),
              ),
            );
            return future
                ? ExcludeSemantics(child: cell)
                : Tooltip(
                    message: '${I18nDateFormat.date(date)} · $intensity',
                    child: cell,
                  );
          },
        ),
      ],
    );
  }
}
