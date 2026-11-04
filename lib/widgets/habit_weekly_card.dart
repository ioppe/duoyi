import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_clock.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../providers/habit_provider.dart';
import '../providers/theme_provider.dart';
import 'surface_components.dart';

/// 七日格之间的水平间隙：连续等宽的一周条，不留 spaceBetween 式大空隙。
const double _habitWeekTileGap = 3;

/// 格内左右呼吸空间。格宽按文字实测宽度自适应，所以这里只保留最小值，
/// 避免把 100% 挤成省略号或需要 FittedBox 缩字。
const double _habitWeekTileHPadding = 1;

/// 格内上下内边距（三行文字之外的高度）。
const double _habitWeekTileVPadding = 6;

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
    final now = AppClock.now();
    final todayDOW = now.weekday - 1;
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

    final baseStyle = theme.textTheme.bodySmall ?? const TextStyle();
    final titleStyle = baseStyle.copyWith(
      fontSize: DesignTokens.fontSizeBody,
      fontWeight: DesignTokens.fontWeightStrong,
      color: cs.onSurface,
    );
    final subtitleStyle = baseStyle.copyWith(
      fontSize: DesignTokens.fontSizeSecondary,
      fontWeight: DesignTokens.fontWeightRegular,
      color: cs.onSurfaceVariant,
    );
    final weekdayStyle = baseStyle.copyWith(
      fontSize: DesignTokens.fontSizeCaption,
      fontWeight: DesignTokens.fontWeightMedium,
      color: cs.onSurfaceVariant,
    );
    final dateStyle = baseStyle.copyWith(
      fontSize: DesignTokens.fontSizeCaption,
      fontWeight: DesignTokens.fontWeightRegular,
      color: cs.onSurfaceVariant.withValues(alpha: 0.72),
    );
    final valueStyle = baseStyle.copyWith(
      fontSize: DesignTokens.fontSizeCaption,
      fontWeight: DesignTokens.fontWeightStrong,
    );
    final percentStyle = baseStyle.copyWith(
      fontSize: DesignTokens.fontSizeBody,
      fontWeight: DesignTokens.fontWeightStrong,
      color: primaryColor,
    );
    final percentCaptionStyle = baseStyle.copyWith(
      fontSize: DesignTokens.fontSizeCaption,
      fontWeight: DesignTokens.fontWeightRegular,
      color: cs.onSurfaceVariant,
    );

    // 本周第一天的日期：用于每格的「月/日」标签。
    final dateLabels = List.generate(7, (i) {
      final date = DateTime(now.year, now.month, now.day - todayDOW + i);
      return '${date.month}/${date.day}';
    });

    return AppSurfaceCard(
      key: const ValueKey('habit_weekly_overview_card'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      // 不传 gradient：让 AppSurfaceCard 使用主题卡片皮肤（cardSkin）。
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                key: const ValueKey('habit_weekly_overview_icon_box'),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: isDark ? 0.20 : 0.10),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                ),
                child: Icon(
                  Icons.calendar_view_week_rounded,
                  size: 16,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: DesignTokens.spaceSm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.habitWeekOverview, style: titleStyle),
                    const SizedBox(height: DesignTokens.spaceXxs),
                    Text(
                      "${I18n.tr('habit.weekly.today_prefix')}"
                      "$completedToday/$activeToday"
                      "${I18n.tr('habit.weekly.today_suffix')}",
                      style: subtitleStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DesignTokens.spaceSm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$weekPercent%',
                    key: const ValueKey('habit_weekly_overview_percent'),
                    style: percentStyle,
                  ),
                  const SizedBox(height: DesignTokens.spaceXxs),
                  Text(
                    I18n.tr('habit.weekly.progress'),
                    style: percentCaptionStyle,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          ClipRRect(
            borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
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
          const SizedBox(height: DesignTokens.spaceMd),
          LayoutBuilder(
            builder: (context, constraints) {
              final tileValues = List.generate(
                7,
                (i) => i > todayDOW ? '–' : '${(data[i] * 100).round()}%',
              );
              // 100% 一定可能出现：即使用今日不是满分，也要按最宽的百分比
              // 预留格宽，避免某天变成省略号。
              var widestText = _habitWeekTextSize(
                context,
                '100%',
                valueStyle,
              ).width;
              for (var i = 0; i < 7; i++) {
                widestText = _habitWidest(
                  widestText,
                  _habitWeekTextSize(context, labels[i], weekdayStyle).width,
                );
                widestText = _habitWidest(
                  widestText,
                  _habitWeekTextSize(context, dateLabels[i], dateStyle).width,
                );
                widestText = _habitWidest(
                  widestText,
                  _habitWeekTextSize(context, tileValues[i], valueStyle).width,
                );
              }
              final minTileWidth =
                  widestText + _habitWeekTileHPadding * 2 + 0.5;
              final availableWidth = constraints.maxWidth;
              final equalShare = (availableWidth - _habitWeekTileGap * 6) / 7;
              // 放得下就七格等宽填满整行；放不下（超窄屏 / 超大字号）改成
              // 横向滚动，保留完整字号与完整百分比，绝不缩字或省略。
              final scrollable = minTileWidth > equalShare;
              final tileWidth = scrollable ? minTileWidth : equalShare;
              final tileHeight =
                  _habitWeekTextSize(
                    context,
                    labels[todayDOW],
                    weekdayStyle,
                  ).height +
                  _habitWeekTextSize(
                    context,
                    dateLabels[todayDOW],
                    dateStyle,
                  ).height +
                  _habitWeekTextSize(context, '100%', valueStyle).height +
                  DesignTokens.spaceXxs * 3 +
                  _habitWeekTileVPadding * 2 +
                  1;

              Widget buildTile(int i) {
                final value = data[i];
                final isToday = i == todayDOW;
                final isFuture = i > todayDOW;
                final completed = !isFuture && value >= 1.0;
                final success = isDark
                    ? DesignTokens.habitCompletedDark
                    : DesignTokens.habitCompletedLight;
                final tint = completed
                    ? success
                    : DesignTokens.habitPendingTint;
                final fill = Color.alphaBlend(
                  tint.withValues(alpha: isFuture ? 0.055 : 0.15),
                  cs.surface,
                );
                final valueColor = isFuture
                    ? cs.onSurface.withValues(alpha: 0.48)
                    : completed
                    ? success
                    : cs.onSurface;
                return Container(
                  key: ValueKey('habit_weekly_overview_day_$i'),
                  width: tileWidth,
                  height: tileHeight,
                  padding: const EdgeInsets.symmetric(
                    horizontal: _habitWeekTileHPadding,
                    vertical: _habitWeekTileVPadding,
                  ),
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  ),
                  foregroundDecoration: isToday
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            DesignTokens.radiusMd,
                          ),
                          border: Border.all(
                            color: primaryColor.withValues(
                              alpha: isDark ? 0.62 : 0.50,
                            ),
                            width: 1.2,
                          ),
                        )
                      : null,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        labels[i],
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: weekdayStyle.copyWith(
                          color: isToday ? primaryColor : weekdayStyle.color,
                        ),
                      ),
                      const SizedBox(height: DesignTokens.spaceXxs),
                      Text(
                        dateLabels[i],
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: dateStyle,
                      ),
                      const SizedBox(height: DesignTokens.spaceXxs),
                      Text(
                        tileValues[i],
                        key: ValueKey('habit_weekly_overview_value_$i'),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: valueStyle.copyWith(color: valueColor),
                      ),
                    ],
                  ),
                );
              }

              if (!scrollable) {
                // 等宽填满：用 Expanded 让 7 格严格同宽，避免固定宽度累积
                // 亚像素后撑出屏幕。
                return Row(
                  children: [
                    for (var i = 0; i < 7; i++) ...[
                      if (i > 0) const SizedBox(width: _habitWeekTileGap),
                      Expanded(child: buildTile(i)),
                    ],
                  ],
                );
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < 7; i++) ...[
                      if (i > 0) const SizedBox(width: _habitWeekTileGap),
                      buildTile(i),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

double _habitWidest(double current, double candidate) =>
    candidate > current ? candidate : current;

Size _habitWeekTextSize(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final size = Size(painter.width, painter.height);
  painter.dispose();
  return size;
}
