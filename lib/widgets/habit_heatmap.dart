import 'package:flutter/material.dart';

import '../core/app_clock.dart';
import '../core/design_tokens.dart';
import '../core/i18n_date_format.dart';

class HabitHeatmap extends StatelessWidget {
  final Map<String, int> heatmapData; // dateKey -> intensity 0-5
  final int weeks;
  final bool fitToWidth;

  const HabitHeatmap({
    super.key,
    required this.heatmapData,
    this.weeks = 12,
    this.fitToWidth = false,
  });

  Color _cellColor({
    required int intensity,
    required ColorScheme cs,
    required bool isDark,
    required bool isFuture,
  }) {
    if (isFuture) {
      return cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.12 : 0.22);
    }
    if (intensity <= 0) {
      return Color.alphaBlend(
        cs.primary.withValues(alpha: isDark ? 0.08 : 0.055),
        cs.surface,
      );
    }
    if (intensity >= 5) return const Color(0xFF2E7D32);
    final palette = <Color>[
      const Color(0xFFFFF3D7),
      const Color(0xFFFFD58A),
      const Color(0xFFFFAF54),
      const Color(0xFF71B77A),
    ];
    return Color.lerp(
          palette[intensity.clamp(1, 4) - 1],
          cs.primary,
          isDark ? 0.22 : 0.08,
        ) ??
        palette[intensity.clamp(1, 4) - 1];
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final today = AppClock.today();
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    final startDate = thisMonday.subtract(Duration(days: (weeks - 1) * 7));
    final columns = weeks;
    final rows = 7;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        const horizontalPadding = 10.0;
        final weekdayWidth = fitToWidth ? 28.0 : 24.0;
        final reservedWidth = fitToWidth
            ? horizontalPadding * 2 + weekdayWidth
            : 38.0;
        final minimumCell = fitToWidth
            ? (MediaQuery.textScalerOf(context).scale(9.5) - 3).clamp(
                10.0,
                double.infinity,
              )
            : 10.0;
        final cell = ((available - reservedWidth - columns * 3.0) / columns)
            .clamp(minimumCell, fitToWidth ? double.infinity : 18.0);
        final cellRadius = BorderRadius.circular(
          cell >= 15 ? DesignTokens.radiusXs : 3,
        );
        final grid = Column(
          crossAxisAlignment: fitToWidth
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 28),
                ...List.generate(columns, (c) {
                  final w = startDate.add(Duration(days: c * 7));
                  return SizedBox(
                    width: cell + 3,
                    child: c % 4 == 0
                        ? Text(
                            '${w.month}月',
                            maxLines: fitToWidth ? 1 : null,
                            softWrap: !fitToWidth,
                            overflow: fitToWidth
                                ? TextOverflow.visible
                                : TextOverflow.clip,
                            style: TextStyle(
                              fontSize: 9.5,
                              height: 1,
                              color: cs.onSurface.withValues(alpha: 0.48),
                            ),
                          )
                        : const SizedBox(),
                  );
                }),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Column(
                  children: const ['一', '', '三', '', '五', '', '日']
                      .map(
                        (s) => SizedBox(
                          height: cell + 3,
                          width: weekdayWidth,
                          child: s.isEmpty
                              ? null
                              : Center(
                                  child: Text(
                                    s,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      height: 1,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.46,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      )
                      .toList(),
                ),
                ...List.generate(columns, (c) {
                  return Column(
                    children: List.generate(rows, (r) {
                      final date = startDate.add(Duration(days: c * 7 + r));
                      final key =
                          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                      final intensity = heatmapData[key] ?? 0;
                      final isToday = date == today;
                      final isFuture = date.isAfter(today);
                      final cellColor = _cellColor(
                        intensity: intensity,
                        cs: cs,
                        isDark: isDark,
                        isFuture: isFuture,
                      );
                      return Tooltip(
                        message: '${I18nDateFormat.date(date)} · $intensity 次',
                        child: Container(
                          width: cell,
                          height: cell,
                          margin: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(
                            color: cellColor,
                            borderRadius: cellRadius,
                            border: Border.all(
                              color: isToday
                                  ? cs.primary.withValues(alpha: 0.76)
                                  : intensity == 0 || isFuture
                                  ? cs.outlineVariant.withValues(alpha: 0.20)
                                  : cellColor.withValues(alpha: 0.72),
                              width: isToday ? 1.15 : 0.55,
                            ),
                            boxShadow: intensity > 0 && !isFuture
                                ? [
                                    BoxShadow(
                                      color: cellColor.withValues(
                                        alpha: isDark ? 0.18 : 0.22,
                                      ),
                                      blurRadius: 5,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      );
                    }),
                  );
                }),
              ],
            ),
            const SizedBox(height: 10),
            _HabitHeatmapLegend(cs: cs, isDark: isDark),
          ],
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            10,
            horizontalPadding,
            14,
          ),
          child: fitToWidth
              ? SizedBox(
                  width: weekdayWidth + columns * (cell + 3),
                  child: grid,
                )
              : grid,
        );
      },
    );
  }
}

class _HabitHeatmapLegend extends StatelessWidget {
  final ColorScheme cs;
  final bool isDark;

  const _HabitHeatmapLegend({required this.cs, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final samples = [0, 1, 2, 3, 5];
    Color sampleColor(int value) {
      if (value == 0) {
        return Color.alphaBlend(
          cs.primary.withValues(alpha: isDark ? 0.08 : 0.055),
          cs.surface,
        );
      }
      if (value >= 5) return const Color(0xFF2E7D32);
      final palette = <Color>[
        const Color(0xFFFFF3D7),
        const Color(0xFFFFD58A),
        const Color(0xFFFFAF54),
      ];
      return Color.lerp(palette[value - 1], cs.primary, isDark ? 0.22 : 0.08) ??
          palette[value - 1];
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '少',
          style: TextStyle(
            fontSize: 10,
            color: cs.onSurface.withValues(alpha: 0.48),
            height: 1,
          ),
        ),
        const SizedBox(width: 6),
        ...samples.map(
          (value) => Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: sampleColor(value),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.18),
                width: 0.45,
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        Text(
          '多',
          style: TextStyle(
            fontSize: 10,
            color: cs.onSurface.withValues(alpha: 0.48),
            height: 1,
          ),
        ),
      ],
    );
  }
}
