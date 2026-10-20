import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import 'surface_components.dart';

/// Habit.activeWeekdays 的星期标签键，0=周一 … 6=周日。
const List<String> habitWeekdayLabelKeys = <String>[
  'weekday.mon',
  'weekday.tue',
  'weekday.wed',
  'weekday.thu',
  'weekday.fri',
  'weekday.sat',
  'weekday.sun',
];

/// 习惯"生效星期"多选控件（7 个 chip，0=周一 … 6=周日）。
///
/// 空选择会让习惯永远不活跃、统计失去意义，因此取消最后一个
/// 生效日时保持原状；其余切换按升序回传给 [onChanged]。
///
/// [warning] 用于额外提示（例如"每周提醒与生效星期相互独立"）。
class HabitActiveWeekdayPicker extends StatelessWidget {
  final List<int> weekdays;
  final ValueChanged<List<int>> onChanged;
  final String? warning;

  const HabitActiveWeekdayPicker({
    super.key,
    required this.weekdays,
    required this.onChanged,
    this.warning,
  });

  void _toggle(int weekday) {
    final next = List<int>.from(weekdays);
    if (next.contains(weekday)) {
      if (next.length <= 1) return;
      next.remove(weekday);
    } else {
      next.add(weekday);
    }
    next.sort();
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          I18n.tr('habit.active_weekdays'),
          style: const TextStyle(
            fontSize: DesignTokens.fontSizeSm,
            fontWeight: DesignTokens.fontWeightStrong,
          ),
        ),
        const SizedBox(height: DesignTokens.spaceXs),
        Text(
          I18n.tr('habit.active_weekdays.hint'),
          style: TextStyle(
            fontSize: DesignTokens.fontSizeXs,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: DesignTokens.spaceSm),
        Wrap(
          spacing: DesignTokens.spaceSm,
          runSpacing: DesignTokens.spaceSm,
          children: [
            for (var i = 0; i < habitWeekdayLabelKeys.length; i++)
              FilterChip(
                key: ValueKey('habit_active_weekday_chip_$i'),
                label: Text(I18n.tr(habitWeekdayLabelKeys[i])),
                labelStyle: appSecondaryControlTextStyle(context),
                selected: weekdays.contains(i),
                showCheckmark: false,
                onSelected: (_) => _toggle(i),
              ),
          ],
        ),
        if (warning != null && warning!.isNotEmpty) ...[
          const SizedBox(height: DesignTokens.spaceXs),
          Text(
            warning!,
            style: TextStyle(
              fontSize: DesignTokens.fontSizeXs,
              color: cs.tertiary,
            ),
          ),
        ],
      ],
    );
  }
}
