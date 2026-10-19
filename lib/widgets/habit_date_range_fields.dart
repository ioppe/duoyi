import 'package:flutter/material.dart';

import '../core/app_clock.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import 'app_date_picker.dart';
import 'surface_components.dart';

DateTime habitDateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool habitDateRangeIsValid(DateTime? startDate, DateTime? endDate) {
  if (startDate == null || endDate == null) return true;
  return !habitDateOnly(endDate).isBefore(habitDateOnly(startDate));
}

String habitDateRangeLabel(DateTime? startDate, DateTime? endDate) {
  if (startDate == null && endDate == null) {
    return I18n.tr('habit.date_range.long_term');
  }
  if (startDate != null && endDate != null) {
    return '${I18nDateFormat.date(startDate)} - ${I18nDateFormat.date(endDate)}';
  }
  if (startDate != null) {
    return _dateWithRangeSuffix(
      I18nDateFormat.date(startDate),
      'habit.date_range.from_suffix',
    );
  }
  return _dateWithRangeSuffix(
    I18nDateFormat.date(endDate!),
    'habit.date_range.until_suffix',
  );
}

/// 单日期 + 起/止标记：zh 为后缀（「2026-01-01 起」）；en 的 from/until 是
/// 前置介词，suffix 键结构无法表达，按语言调整语序（「from 2026-01-01」）。
String _dateWithRangeSuffix(String date, String suffixKey) {
  final suffix = I18n.tr(suffixKey);
  return I18n.current == AppLocale.en ? '$suffix $date' : '$date $suffix';
}

class HabitDateRangeFields extends StatelessWidget {
  final DateTime? startDate;
  final DateTime? endDate;
  final ValueChanged<DateTime?> onStartChanged;
  final ValueChanged<DateTime?> onEndChanged;

  const HabitDateRangeFields({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.onStartChanged,
    required this.onEndChanged,
  });

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.date_range_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(I18n.tr('habit.date_range.title'))),
            ],
          ),
          const SizedBox(height: 8),
          _HabitDateRow(
            label: I18n.tr('habit.date_range.start'),
            value: startDate,
            emptyLabel: I18n.tr('habit.date_range.start_empty'),
            onPick: () => _pickStart(context),
            onClear: startDate == null ? null : () => onStartChanged(null),
          ),
          const Divider(height: 12),
          _HabitDateRow(
            label: I18n.tr('habit.date_range.end'),
            value: endDate,
            emptyLabel: I18n.tr('habit.date_range.end_empty'),
            onPick: () => _pickEnd(context),
            onClear: endDate == null ? null : () => onEndChanged(null),
          ),
        ],
      ),
    );
  }

  Future<void> _pickStart(BuildContext context) async {
    final first = DateTime(2000);
    final last = endDate == null
        ? DateTime(2100, 12, 31)
        : habitDateOnly(endDate!);
    final initial = _clampDay(startDate ?? AppClock.now(), first, last);
    final picked = await AppDatePicker.pickSolar(
      context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      title: I18n.tr('habit.date_range.pick_start'),
    );
    if (picked != null) onStartChanged(habitDateOnly(picked));
  }

  Future<void> _pickEnd(BuildContext context) async {
    final first = startDate == null
        ? DateTime(2000)
        : habitDateOnly(startDate!);
    final last = DateTime(2100, 12, 31);
    final initial = _clampDay(
      endDate ?? startDate ?? AppClock.now(),
      first,
      last,
    );
    final picked = await AppDatePicker.pickSolar(
      context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      title: I18n.tr('habit.date_range.pick_end'),
    );
    if (picked != null) onEndChanged(habitDateOnly(picked));
  }

  DateTime _clampDay(DateTime value, DateTime first, DateTime last) {
    final day = habitDateOnly(value);
    if (day.isBefore(first)) return first;
    if (day.isAfter(last)) return last;
    return day;
  }
}

class _HabitDateRow extends StatelessWidget {
  final String label;
  final DateTime? value;
  final String emptyLabel;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  const _HabitDateRow({
    required this.label,
    required this.value,
    required this.emptyLabel,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onPick,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value == null ? emptyLabel : I18nDateFormat.date(value!),
                    style: TextStyle(
                      fontSize: 14,
                      color: value == null ? cs.onSurfaceVariant : cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                tooltip: I18n.tr('action.clear'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClear,
              ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}
