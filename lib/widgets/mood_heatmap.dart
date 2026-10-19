import 'package:flutter/material.dart';
import '../core/app_clock.dart';
import '../core/i18n_date_format.dart';
import '../models/diary_entry.dart';

/// 近 N 周心情热图：每格代表一天，颜色由当天日记的心情决定；无日记则中性灰。
class MoodHeatmap extends StatelessWidget {
  final Map<String, DiaryEntry> entriesByDate;
  final int weeks;

  const MoodHeatmap({super.key, required this.entriesByDate, this.weeks = 12});

  /// 五档心情语义色：亮色档沿用既有取值；暗色档换用更亮的同色相档，
  /// 避免暗色主题下沿用亮色档的深色值在深背景上发闷、难以分辨。
  Color _moodColor(Mood m, bool isDark) {
    if (!isDark) {
      return switch (m) {
        Mood.awesome => const Color(0xFF2E7D32),
        Mood.good => const Color(0xFF66BB6A),
        Mood.okay => const Color(0xFFFFCA28),
        Mood.bad => const Color(0xFFEF6C00),
        Mood.terrible => const Color(0xFFD32F2F),
      };
    }
    return switch (m) {
      Mood.awesome => const Color(0xFF4CAF50),
      Mood.good => const Color(0xFF81C784),
      // bad 用 orange400 而非 orange300：与 okay(amber300) 色相只差约 10°，
      // 10px 小色块主要靠明度区分，300 档两档明度几乎相同难以分辨。
      Mood.okay => const Color(0xFFFFD54F),
      Mood.bad => const Color(0xFFFFA726),
      Mood.terrible => const Color(0xFFE57373),
    };
  }

  /// 空格取主题中性容器色，跟随亮暗主题，不再固定亮灰刺眼。
  Color _emptyColor(ColorScheme cs, bool isDark) {
    return cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.12 : 0.22);
  }

  Color _colorFor(Mood? m, ColorScheme cs, bool isDark) {
    if (m == null) return _emptyColor(cs, isDark);
    return _moodColor(m, isDark);
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final now = AppClock.now();
    // 对齐到周一
    final thisMonday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final startMonday = thisMonday.subtract(Duration(days: (weeks - 1) * 7));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cell = ((constraints.maxWidth - 4 - 18) / weeks).clamp(
              6.0,
              14.0,
            );
            return Row(
              children: [
                SizedBox(
                  width: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final d in const ['一', '三', '五', '日'])
                        Padding(
                          padding: EdgeInsets.only(top: cell * 0.4),
                          child: Text(
                            d,
                            style: TextStyle(
                              fontSize: 9,
                              color: cs.onSurface.withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: List.generate(weeks, (w) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Column(
                          children: List.generate(7, (dow) {
                            final date = startMonday.add(
                              Duration(days: w * 7 + dow),
                            );
                            if (date.isAfter(
                              DateTime(now.year, now.month, now.day),
                            )) {
                              return SizedBox(width: cell, height: cell);
                            }
                            final key =
                                '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                            final entry = entriesByDate[key];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Tooltip(
                                message:
                                    '${I18nDateFormat.date(date)} · ${entry?.mood?.label ?? '无记录'}',
                                child: Container(
                                  width: cell,
                                  height: cell,
                                  decoration: BoxDecoration(
                                    color: _colorFor(entry?.mood, cs, isDark),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              '少',
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(width: 4),
            ...Mood.values.map(
              (m) => Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _colorFor(m, cs, isDark),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '多',
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
