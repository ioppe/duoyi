import 'package:flutter/material.dart';

import '../core/app_clock.dart';
import '../core/app_motion.dart';
import '../core/design_tokens.dart';
import '../core/i18n_date_format.dart';
import 'surface_components.dart';

class AppTimePicker {
  AppTimePicker._();

  static Future<TimeOfDay?> show(
    BuildContext context, {
    required TimeOfDay initialTime,
    String title = '选择时间',
    String? subtitle,
    int minuteStep = 5,
  }) {
    return showAppModalSheet<TimeOfDay>(
      context: context,
      builder: (_) => _AppTimePickerSheet(
        initialTime: initialTime,
        title: title,
        subtitle: subtitle,
        minuteStep: minuteStep,
      ),
    );
  }

  static String format(TimeOfDay time) {
    return I18nDateFormat.timeOfDay(hour: time.hour, minute: time.minute);
  }

  static TimeOfDay nextHalfHour([DateTime? from]) {
    final now = from ?? AppClock.now();
    if (now.minute < 30) return TimeOfDay(hour: now.hour, minute: 30);
    return TimeOfDay(hour: (now.hour + 1) % 24, minute: 0);
  }
}

class _AppTimePickerSheet extends StatefulWidget {
  final TimeOfDay initialTime;
  final String title;
  final String? subtitle;
  final int minuteStep;

  const _AppTimePickerSheet({
    required this.initialTime,
    required this.title,
    required this.subtitle,
    required this.minuteStep,
  });

  @override
  State<_AppTimePickerSheet> createState() => _AppTimePickerSheetState();
}

class _AppTimePickerSheetState extends State<_AppTimePickerSheet> {
  late int _hour;
  late int _minute;
  late List<int> _minutes;
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;

  @override
  void initState() {
    super.initState();
    final step = _normalizedStep(widget.minuteStep);
    _minutes = [for (var m = 0; m < 60; m += step) m];
    final rounded = _roundedTime(widget.initialTime);
    _hour = rounded.hour;
    _minute = rounded.minute;
    _hourController = FixedExtentScrollController(initialItem: _hour);
    _minuteController = FixedExtentScrollController(
      initialItem: _minutes.indexOf(_minute).clamp(0, _minutes.length - 1),
    );
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  int _normalizedStep(int step) {
    if (step <= 0 || 60 % step != 0) return 5;
    return step;
  }

  TimeOfDay _roundedTime(TimeOfDay time) {
    final step = _normalizedStep(widget.minuteStep);
    final rounded = ((time.minute + step - 1) ~/ step * step)
        .clamp(0, 60)
        .toInt();
    if (rounded == 60) {
      return TimeOfDay(hour: (time.hour + 1) % 24, minute: 0);
    }
    return TimeOfDay(hour: time.hour, minute: rounded);
  }

  TimeOfDay get _value => TimeOfDay(hour: _hour, minute: _minute);

  void _setValue(TimeOfDay value) {
    final rounded = _roundedTime(value);
    setState(() {
      _hour = rounded.hour;
      _minute = rounded.minute;
    });
    if (AppMotion.reduced(context)) {
      _hourController.jumpToItem(_hour);
      _minuteController.jumpToItem(_minutes.indexOf(_minute));
      return;
    }
    _hourController.animateToItem(
      _hour,
      duration: AppMotion.feedback(context),
      curve: AppMotion.enterCurve,
    );
    _minuteController.animateToItem(
      _minutes.indexOf(_minute).clamp(0, _minutes.length - 1),
      duration: AppMotion.feedback(context),
      curve: AppMotion.enterCurve,
    );
  }

  void _shiftMinutes(int delta) {
    final total = (_hour * 60 + _minute + delta) % (24 * 60);
    final normalized = total < 0 ? total + 24 * 60 : total;
    _setValue(TimeOfDay(hour: normalized ~/ 60, minute: normalized % 60));
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AppModalSheet(
      title: widget.title,
      subtitle: widget.subtitle,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _value),
          child: const Text('确定'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.42),
              borderRadius: DesignTokens.borderRadiusLg,
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.12),
                width: 0.45,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              AppTimePicker.format(_value),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontSize: 24,
                fontWeight: DesignTokens.fontWeightStrong,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: cs.primary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _shiftMinutes(-30),
                  icon: const Icon(Icons.keyboard_arrow_left_rounded),
                  label: const Text('提前 30 分'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _shiftMinutes(30),
                  icon: const Icon(Icons.keyboard_arrow_right_rounded),
                  label: const Text('延后 30 分'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PresetChip(
                label: '上午 09:00',
                onTap: () => _setValue(const TimeOfDay(hour: 9, minute: 0)),
              ),
              _PresetChip(
                label: '中午 12:00',
                onTap: () => _setValue(const TimeOfDay(hour: 12, minute: 0)),
              ),
              _PresetChip(
                label: '晚上 20:00',
                onTap: () => _setValue(const TimeOfDay(hour: 20, minute: 0)),
              ),
              _PresetChip(label: '现在', onTap: () => _setValue(TimeOfDay.now())),
              _PresetChip(
                label: '下一提醒点',
                onTap: () => _setValue(AppTimePicker.nextHalfHour()),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            height: 190,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.32),
              borderRadius: DesignTokens.borderRadiusLg,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _Wheel(
                    controller: _hourController,
                    count: 24,
                    labelBuilder: (i) => i.toString().padLeft(2, '0'),
                    onSelectedItemChanged: (i) => setState(() => _hour = i),
                  ),
                ),
                Text(
                  ':',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                Expanded(
                  child: _Wheel(
                    controller: _minuteController,
                    count: _minutes.length,
                    labelBuilder: (i) => _minutes[i].toString().padLeft(2, '0'),
                    onSelectedItemChanged: (i) =>
                        setState(() => _minute = _minutes[i]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      avatar: const Icon(Icons.schedule, size: 16),
      onPressed: onTap,
    );
  }
}

class _Wheel extends StatelessWidget {
  final FixedExtentScrollController controller;
  final int count;
  final String Function(int index) labelBuilder;
  final ValueChanged<int> onSelectedItemChanged;

  const _Wheel({
    required this.controller,
    required this.count,
    required this.labelBuilder,
    required this.onSelectedItemChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListWheelScrollView.useDelegate(
      controller: controller,
      itemExtent: 44,
      physics: const FixedExtentScrollPhysics(),
      perspective: 0.003,
      overAndUnderCenterOpacity: 0.42,
      onSelectedItemChanged: onSelectedItemChanged,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: count,
        builder: (context, index) {
          return Center(
            child: Text(
              labelBuilder(index),
              style: theme.textTheme.titleLarge?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: cs.onSurface,
              ),
            ),
          );
        },
      ),
    );
  }
}
