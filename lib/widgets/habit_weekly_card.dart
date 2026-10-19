import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_clock.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../providers/habit_provider.dart';
import '../providers/theme_provider.dart';
import 'surface_components.dart';

class HabitWeeklyCard extends StatelessWidget {
  const HabitWeeklyCard({super.key});

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final provider = context.watch<HabitProvider>();
    final s = context.watch<ThemeProvider>().brand.strings;
    final data = provider.currentWeekProgress();
    final labels = [
      I18n.tr('habit.weekday.1'),
      I18n.tr('habit.weekday.2'),
      I18n.tr('habit.weekday.3'),
      I18n.tr('habit.weekday.4'),
      I18n.tr('habit.weekday.5'),
      I18n.tr('habit.weekday.6'),
      I18n.tr('habit.weekday.7'),
    ];
    final todayDOW = AppClock.now().weekday - 1;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = cs.primary;
    final elapsed = todayDOW + 1;
    final weekAverage =
        data.take(elapsed).fold<double>(0, (sum, value) => sum + value) /
        elapsed;
    final activeToday = provider.habits.where((h) => h.isActiveToday()).length;
    final completedToday = provider.habits
        .where((h) => h.isActiveToday() && h.isCompletedToday())
        .length;
    final weekPercent = (weekAverage * 100).round();

    return AppSurfaceCard(
      key: const ValueKey('habit_weekly_overview_card'),
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
      borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(
            primaryColor.withValues(alpha: isDark ? 0.16 : 0.08),
            cs.surface,
          ),
          Color.alphaBlend(
            cs.tertiary.withValues(alpha: isDark ? 0.10 : 0.045),
            cs.surface,
          ),
        ],
      ),
      border: Border.all(
        color: primaryColor.withValues(alpha: isDark ? 0.22 : 0.16),
        width: 0.65,
      ),
      elevation: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                key: const ValueKey('habit_weekly_overview_icon_box'),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: isDark ? 0.18 : 0.11),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  border: Border.all(
                    color: primaryColor.withValues(alpha: 0.12),
                    width: 0.5,
                  ),
                ),
                child: Icon(
                  Icons.calendar_view_week_rounded,
                  size: 18,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.habitWeekOverview,
                      style: appSecondaryRouteTitleTextStyle(context).copyWith(
                        fontSize: 13,
                        fontWeight: DesignTokens.fontWeightRegular,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "${I18n.tr('habit.weekly.today_prefix')}$completedToday/$activeToday${I18n.tr('habit.weekly.today_suffix')}",
                      style: appSecondaryControlLabelStyle(context).copyWith(
                        fontSize: DesignTokens.fontSizeCaption,
                        color: cs.onSurface.withValues(alpha: 0.58),
                        height: 1.12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: isDark ? 0.26 : 0.70),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: primaryColor.withValues(alpha: 0.14),
                    width: 0.6,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$weekPercent%',
                      key: const ValueKey('habit_weekly_overview_percent'),
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: 15,
                        height: 1.0,
                        fontWeight: DesignTokens.fontWeightRegular,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      I18n.tr('habit.weekly.progress'),
                      style: appSecondaryControlLabelStyle(context).copyWith(
                        fontSize: 10,
                        color: cs.onSurface.withValues(alpha: 0.62),
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              key: const ValueKey('habit_weekly_overview_progress_bar'),
              value: weekAverage.clamp(0.0, 1.0).toDouble(),
              minHeight: 3,
              backgroundColor: cs.surfaceContainerHighest.withValues(
                alpha: isDark ? 0.20 : 0.42,
              ),
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 7),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final val = data[i];
              final isToday = i == todayDOW;
              Color bg;
              Color textColor = cs.onSurface;
              Color borderColor = Colors.transparent;

              if (i > todayDOW) {
                bg = cs.surfaceContainerHighest.withValues(
                  alpha: isDark ? 0.15 : 0.34,
                );
                textColor = cs.onSurface.withValues(alpha: 0.36);
                borderColor = cs.outlineVariant.withValues(alpha: 0.12);
              } else if (val >= 1.0) {
                bg = const Color(0xFF2E7D32);
                textColor = Colors.white;
              } else if (val > 0) {
                bg = const Color(0xFFFFB74D);
                textColor = const Color(0xFF2D1F0F);
              } else {
                bg = cs.surface.withValues(alpha: isDark ? 0.28 : 0.70);
                textColor = cs.onSurface.withValues(alpha: 0.52);
                borderColor = cs.outlineVariant.withValues(alpha: 0.18);
              }

              return Container(
                width: 30,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: isToday
                      ? primaryColor.withValues(alpha: isDark ? 0.13 : 0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Column(
                  children: [
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeCaption,
                        fontWeight: DesignTokens.fontWeightRegular,
                        color: isToday
                            ? primaryColor
                            : cs.onSurface.withValues(alpha: 0.56),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      key: ValueKey('habit_weekly_overview_day_$i'),
                      width: 25,
                      height: 25,
                      decoration: BoxDecoration(
                        color: bg,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isToday
                              ? primaryColor.withValues(alpha: 0.46)
                              : borderColor,
                          width: isToday ? 1.05 : 0.55,
                        ),
                        boxShadow: isToday && val > 0
                            ? [
                                BoxShadow(
                                  color: bg.withValues(
                                    alpha: isDark ? 0.20 : 0.26,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          i > todayDOW ? '-' : '${(val * 100).round()}%',
                          style: TextStyle(
                            fontSize: 8.5,
                            color: textColor,
                            fontWeight: DesignTokens.fontWeightRegular,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
