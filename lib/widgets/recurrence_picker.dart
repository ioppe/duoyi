import '../core/app_clock.dart';
import 'package:flutter/material.dart';
import '../core/i18n_date_format.dart';
import '../models/recurrence.dart';
import 'app_date_picker.dart';
import 'surface_components.dart';

/// 重复规则编辑弹出层。
class RecurrencePicker extends StatefulWidget {
  final RecurrenceRule initial;
  final bool supportMaxOccurrences;
  const RecurrencePicker({
    super.key,
    required this.initial,
    this.supportMaxOccurrences = true,
  });

  static Future<RecurrenceRule?> show(
    BuildContext context, {
    required RecurrenceRule initial,
    bool supportMaxOccurrences = true,
  }) {
    return showAppModalSheet<RecurrenceRule>(
      context: context,
      builder: (_) => RecurrencePicker(
        initial: initial,
        supportMaxOccurrences: supportMaxOccurrences,
      ),
    );
  }

  @override
  State<RecurrencePicker> createState() => _RecurrencePickerState();
}

class _RecurrencePickerState extends State<RecurrencePicker> {
  late RecurrenceFrequency _freq;
  late int _interval;
  late List<int> _weekdays;
  late final TextEditingController _intervalCtrl;
  late final TextEditingController _byMonthDayCtrl;
  late final TextEditingController _maxOccurrencesCtrl;
  int? _byMonthDay;
  DateTime? _endDate;
  int? _maxOccurrences;

  @override
  void initState() {
    super.initState();
    _freq = widget.initial.frequency;
    _interval = widget.initial.interval;
    _weekdays = [...?widget.initial.byWeekdays];
    _intervalCtrl = TextEditingController(text: '$_interval');
    _byMonthDay = widget.initial.byMonthDay;
    _byMonthDayCtrl = TextEditingController(
      text: _byMonthDay?.toString() ?? '',
    );
    _maxOccurrences = widget.initial.maxOccurrences;
    _maxOccurrencesCtrl = TextEditingController(
      text: _maxOccurrences?.toString() ?? '',
    );
    _endDate = widget.initial.endDate;
  }

  @override
  void dispose() {
    _intervalCtrl.dispose();
    _byMonthDayCtrl.dispose();
    _maxOccurrencesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final cs = Theme.of(context).colorScheme;
    final controlText = appSecondaryControlTextStyle(context);
    final labelText = appSecondaryControlLabelStyle(context);
    return AppModalSheet(
      title: '重复',
      subtitle: widget.supportMaxOccurrences
          ? '设置循环频率、间隔、结束日期和重复次数'
          : '设置循环频率、间隔和结束日期',
      leadingActions: [
        TextButton(
          onPressed: () => Navigator.pop(context, const RecurrenceRule()),
          child: const Text('清除'),
        ),
      ],
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            RecurrenceRule(
              frequency: _freq,
              interval: _interval < 1 ? 1 : _interval,
              byWeekdays:
                  _freq == RecurrenceFrequency.weekly && _weekdays.isNotEmpty
                  ? [..._weekdays]
                  : null,
              byMonthDay: _freq == RecurrenceFrequency.monthly
                  ? _byMonthDay
                  : null,
              endDate: _endDate,
              maxOccurrences:
                  _freq == RecurrenceFrequency.none ||
                      !widget.supportMaxOccurrences
                  ? null
                  : _maxOccurrences,
            ),
          ),
          child: const Text('保存'),
        ),
      ],
      child: AppSecondaryControlTheme(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in RecurrenceFrequency.values)
                  ChoiceChip(
                    label: Text(_freqLabel(f)),
                    selected: _freq == f,
                    labelStyle: controlText,
                    onSelected: (_) => setState(() => _freq = f),
                  ),
              ],
            ),
            if (_freq != RecurrenceFrequency.none) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('每', style: controlText),
                  SizedBox(
                    width: 72,
                    child: TextField(
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      controller: _intervalCtrl,
                      style: controlText,
                      decoration: const InputDecoration(isDense: true),
                      onChanged: (v) {
                        final n = int.tryParse(v);
                        if (n != null && n > 0) {
                          setState(() => _interval = n);
                        }
                      },
                    ),
                  ),
                  Text(' ${_unitLabel(_freq)}', style: controlText),
                ],
              ),
            ],
            if (_freq == RecurrenceFrequency.weekly) ...[
              const SizedBox(height: 12),
              Text(
                '每周哪几天',
                style: labelText.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.62),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: List.generate(7, (i) {
                  const names = ['一', '二', '三', '四', '五', '六', '日'];
                  final selected = _weekdays.contains(i);
                  return FilterChip(
                    label: Text(names[i]),
                    selected: selected,
                    showCheckmark: false,
                    labelStyle: controlText,
                    onSelected: (_) => setState(() {
                      if (selected) {
                        _weekdays.remove(i);
                      } else {
                        _weekdays.add(i);
                      }
                    }),
                  );
                }),
              ),
            ],
            if (_freq == RecurrenceFrequency.monthly) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('每月第几天 ', style: controlText),
                  SizedBox(
                    width: 72,
                    child: TextField(
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      controller: _byMonthDayCtrl,
                      style: controlText,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '留空=同日',
                      ),
                      onChanged: (v) => setState(() {
                        final n = int.tryParse(v);
                        if (n != null && n >= 1 && n <= 31) _byMonthDay = n;
                        if (v.isEmpty) _byMonthDay = null;
                      }),
                    ),
                  ),
                  Text(' 日', style: controlText),
                ],
              ),
            ],
            if (_freq != RecurrenceFrequency.none) ...[
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.event_busy, size: 18),
                title: const Text('结束日期 (可选)'),
                subtitle: Text(
                  _endDate == null ? '永不结束' : I18nDateFormat.date(_endDate!),
                ),
                trailing: _endDate == null
                    ? const Icon(Icons.chevron_right)
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _endDate = null),
                      ),
                onTap: () async {
                  final picked = await AppDatePicker.pickSolar(
                    context,
                    initialDate:
                        _endDate ??
                        AppClock.today().add(const Duration(days: 90)),
                    firstDate: AppClock.today(),
                    lastDate: DateTime(2099, 12, 31),
                    title: '结束日期',
                  );
                  if (!mounted) return;
                  if (picked != null) setState(() => _endDate = picked);
                },
              ),
              if (widget.supportMaxOccurrences) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.repeat_one, size: 18),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _maxOccurrencesCtrl,
                        keyboardType: TextInputType.number,
                        style: controlText,
                        decoration: const InputDecoration(
                          labelText: '重复次数 (可选)',
                          helperText: '留空表示不限次数；例如 10 表示共 10 次',
                        ),
                        onChanged: (v) {
                          final text = v.trim();
                          final n = int.tryParse(text);
                          setState(() {
                            _maxOccurrences = text.isEmpty || n == null || n < 1
                                ? null
                                : n;
                          });
                        },
                      ),
                    ),
                    if (_maxOccurrences != null)
                      IconButton(
                        tooltip: '清除重复次数',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _maxOccurrences = null;
                          _maxOccurrencesCtrl.clear();
                        }),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _freqLabel(RecurrenceFrequency f) => switch (f) {
    RecurrenceFrequency.none => '不重复',
    RecurrenceFrequency.daily => '每天',
    RecurrenceFrequency.weekly => '每周',
    RecurrenceFrequency.monthly => '每月',
    RecurrenceFrequency.yearly => '每年',
  };

  String _unitLabel(RecurrenceFrequency f) => switch (f) {
    RecurrenceFrequency.daily => '天',
    RecurrenceFrequency.weekly => '周',
    RecurrenceFrequency.monthly => '月',
    RecurrenceFrequency.yearly => '年',
    RecurrenceFrequency.none => '',
  };
}
