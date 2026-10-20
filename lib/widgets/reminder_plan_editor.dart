import '../core/app_clock.dart';
import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/i18n_date_format.dart';
import '../models/goal.dart';
import 'app_time_picker.dart';
import 'surface_components.dart';

class ReminderPlanEditor extends StatelessWidget {
  final ReminderPlan plan;
  final ValueChanged<ReminderPlan> onChanged;
  final String title;
  final String? subtitle;
  final bool showHeader;
  final bool allowAlarm;
  final bool allowRelativeToDue;
  final bool allowWeekly;
  final bool allowSnooze;
  final bool hasAnchorDate;
  final int? maxRules;
  final ReminderKind defaultKind;
  final bool showTypeSelector;
  final bool showKindSelector;

  const ReminderPlanEditor({
    super.key,
    required this.plan,
    required this.onChanged,
    this.title = '提醒',
    this.subtitle,
    this.showHeader = true,
    this.allowAlarm = true,
    this.allowRelativeToDue = true,
    this.allowWeekly = true,
    this.allowSnooze = true,
    this.hasAnchorDate = true,
    this.maxRules,
    this.defaultKind = ReminderKind.push,
    this.showTypeSelector = true,
    this.showKindSelector = true,
  });

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final rules = plan.rules;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) ...[
          _ReminderSwitchTile(
            value: plan.enabled,
            title: title,
            subtitle: subtitle ?? reminderPlanSummary(plan),
            onChanged: _toggleEnabled,
          ),
        ] else
          _ReminderSwitchTile(
            value: plan.enabled,
            title: '开启提醒',
            subtitle: reminderPlanSummary(plan),
            onChanged: _toggleEnabled,
          ),
        if (plan.enabled) ...[
          if (rules.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: DesignTokens.spaceSm,
              ),
              child: Text(
                '未添加提醒',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.58),
                  fontSize: DesignTokens.fontSizeSm,
                ),
              ),
            )
          else
            ...rules.map(
              (rule) => Padding(
                padding: const EdgeInsets.only(bottom: DesignTokens.spaceXs),
                child: _ReminderRuleTile(
                  rule: rule,
                  onTap: () => _editRule(context, rule),
                  onDelete: () => _deleteRule(rule.id),
                ),
              ),
            ),
          if (maxRules == null || rules.length < maxRules!)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _editRule(context, null),
                icon: const Icon(Icons.add_alarm, size: 18),
                label: const Text('添加提醒'),
              ),
            ),
        ],
      ],
    );
  }

  void _toggleEnabled(bool enabled) {
    if (!enabled) {
      onChanged(plan.copyWith(enabled: false));
      return;
    }
    final rules = plan.rules.isEmpty ? [_defaultRule()] : plan.rules;
    onChanged(ReminderPlan(enabled: true, rules: rules));
  }

  ReminderRule _defaultRule() {
    final defaultTime = nextHalfHourTimeOfDay();
    final type = hasAnchorDate && allowRelativeToDue
        ? ReminderRuleType.absolute
        : ReminderRuleType.dailyTime;
    return ReminderRule(
      type: type,
      kind: defaultKind,
      hour: defaultTime.hour,
      minute: defaultTime.minute,
      fullScreen: allowAlarm && defaultKind == ReminderKind.alarm,
      weekdays: type == ReminderRuleType.weeklyTime
          ? [AppClock.now().weekday]
          : const <int>[],
    );
  }

  Future<void> _editRule(BuildContext context, ReminderRule? rule) async {
    final edited = await showAppModalSheet<ReminderRule>(
      context: context,
      builder: (_) => _ReminderRuleSheet(
        initial: rule,
        allowAlarm: allowAlarm,
        allowRelativeToDue: allowRelativeToDue,
        allowWeekly: allowWeekly,
        allowSnooze: allowSnooze,
        hasAnchorDate: hasAnchorDate,
        defaultKind: defaultKind,
        showTypeSelector: showTypeSelector,
        showKindSelector: showKindSelector,
      ),
    );
    if (edited == null) return;
    final nextRules = [...plan.rules];
    final index = nextRules.indexWhere((r) => r.id == edited.id);
    if (index >= 0) {
      nextRules[index] = edited;
    } else {
      nextRules.add(edited);
    }
    onChanged(ReminderPlan(enabled: true, rules: nextRules));
  }

  void _deleteRule(String ruleId) {
    final nextRules = plan.rules.where((r) => r.id != ruleId).toList();
    onChanged(ReminderPlan(enabled: nextRules.isNotEmpty, rules: nextRules));
  }
}

String reminderPlanSummary(ReminderPlan plan) {
  if (!plan.enabled) return '已关闭';
  final enabledRules = plan.rules.where((r) => r.enabled).toList();
  if (enabledRules.isEmpty) return '无启用规则';
  if (enabledRules.length == 1) return _ruleSummary(enabledRules.single);
  return '${enabledRules.length} 条提醒';
}

class _ReminderSwitchTile extends StatelessWidget {
  final bool value;
  final String title;
  final String subtitle;
  final ValueChanged<bool> onChanged;

  const _ReminderSwitchTile({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: DesignTokens.borderRadiusSm,
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceXs),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: DesignTokens.fontWeightStrong,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.62),
                        fontSize: DesignTokens.fontSizeSm,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DesignTokens.spaceSm),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReminderRuleTile extends StatelessWidget {
  final ReminderRule rule;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ReminderRuleTile({
    required this.rule,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = rule.kind == ReminderKind.alarm
        ? DesignTokens.priorityMedium
        : cs.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: DesignTokens.borderRadiusSm,
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
            borderRadius: DesignTokens.borderRadiusSm,
            border: Border.all(
              color: cs.outline.withValues(alpha: 0.18),
              width: 0.45,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.only(left: 12, right: 4),
            leading: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: DesignTokens.borderRadiusSm,
              ),
              child: Icon(_ruleIcon(rule), color: color, size: 19),
            ),
            title: Text(
              _ruleTitle(rule),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: DesignTokens.fontWeightStrong),
            ),
            subtitle: Text(
              _ruleSummary(rule),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.close, size: 18),
              onPressed: onDelete,
            ),
          ),
        ),
      ),
    );
  }
}

class _ReminderRuleSheet extends StatefulWidget {
  final ReminderRule? initial;
  final bool allowAlarm;
  final bool allowRelativeToDue;
  final bool allowWeekly;
  final bool allowSnooze;
  final bool hasAnchorDate;
  final ReminderKind defaultKind;
  final bool showTypeSelector;
  final bool showKindSelector;

  const _ReminderRuleSheet({
    required this.initial,
    required this.allowAlarm,
    required this.allowRelativeToDue,
    required this.allowWeekly,
    required this.allowSnooze,
    required this.hasAnchorDate,
    required this.defaultKind,
    required this.showTypeSelector,
    required this.showKindSelector,
  });

  @override
  State<_ReminderRuleSheet> createState() => _ReminderRuleSheetState();
}

class _ReminderRuleSheetState extends State<_ReminderRuleSheet> {
  late bool _enabled;
  late ReminderRuleType _type;
  late ReminderKind _kind;
  late TimeOfDay _time;
  late int _offsetMinutes;
  late List<int> _weekdays;
  late bool _vibrate;
  late bool _fullScreen;
  late int _snoozeMinutes;
  late int _repeatCount;

  List<ReminderRuleType> get _availableTypes {
    final types = <ReminderRuleType>[
      if (widget.allowRelativeToDue) ReminderRuleType.absolute,
      if (widget.allowRelativeToDue) ReminderRuleType.relativeToDue,
      ReminderRuleType.dailyTime,
      if (widget.allowWeekly) ReminderRuleType.weeklyTime,
    ];
    return types;
  }

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _enabled = r?.enabled ?? true;
    _type =
        r?.type ??
        (widget.hasAnchorDate
            ? ReminderRuleType.absolute
            : ReminderRuleType.dailyTime);
    if (!_availableTypes.contains(_type)) {
      _type = _availableTypes.first;
    }
    _kind = widget.showKindSelector && widget.allowAlarm
        ? normalizeUserSelectableReminderKind(r?.kind ?? widget.defaultKind)
        : widget.defaultKind;
    final defaultTime = nextHalfHourTimeOfDay();
    _time = TimeOfDay(
      hour: r?.hour ?? defaultTime.hour,
      minute: r?.minute ?? defaultTime.minute,
    );
    _offsetMinutes = r?.offsetMinutes ?? -30;
    _weekdays = r?.weekdays.isNotEmpty == true
        ? [...r!.weekdays]
        : [AppClock.now().weekday];
    _vibrate = r?.vibrate ?? true;
    _fullScreen = r?.fullScreen ?? _kind == ReminderKind.alarm;
    _snoozeMinutes = r?.snoozeMinutes ?? 0;
    _repeatCount = r?.repeatCount ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    return AppModalSheet(
      title: widget.initial == null ? '添加提醒' : '编辑提醒',
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            title: const Text('启用'),
            onChanged: (v) => setState(() {
              _enabled = v;
              if (v && _kind == ReminderKind.off) {
                _kind = widget.defaultKind == ReminderKind.off
                    ? ReminderKind.push
                    : widget.defaultKind;
              }
            }),
          ),
          if (widget.showTypeSelector) ...[
            AppDropdownField<ReminderRuleType>(
              initialValue: _type,
              labelText: '提醒类型',
              prefixIcon: const Icon(Icons.tune, size: 20),
              items: [
                for (final type in _availableTypes)
                  DropdownMenuItem(value: type, child: Text(_typeLabel(type))),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _type = v);
              },
            ),
            const SizedBox(height: DesignTokens.spaceMd),
          ],
          _ReminderTimeField(time: _time, onTap: _pickTime),
          if (_type == ReminderRuleType.relativeToDue) ...[
            const SizedBox(height: DesignTokens.spaceSm),
            Text('提前时间', style: _labelStyle(context)),
            const SizedBox(height: DesignTokens.spaceXs),
            Wrap(
              spacing: DesignTokens.spaceXs,
              runSpacing: DesignTokens.spaceXs,
              children: ReminderRule.relativeOffsetPresetMinutes.map((minutes) {
                final offset = minutes.abs();
                final selected = _offsetMinutes == minutes;
                return ChoiceChip(
                  label: Text(_durationLabel(offset)),
                  selected: selected,
                  selectedColor: _selectedControlColor(context),
                  checkmarkColor: _selectedControlTextColor(context),
                  labelStyle: _selectedChipLabelStyle(context, selected),
                  onSelected: (_) => setState(() => _offsetMinutes = minutes),
                );
              }).toList(),
            ),
          ],
          if (_type == ReminderRuleType.weeklyTime) ...[
            const SizedBox(height: DesignTokens.spaceSm),
            Text('每周', style: _labelStyle(context)),
            const SizedBox(height: DesignTokens.spaceXs),
            Wrap(
              spacing: DesignTokens.spaceXs,
              runSpacing: DesignTokens.spaceXs,
              children: List.generate(7, (i) {
                final day = i + 1;
                final selected = _weekdays.contains(day);
                return FilterChip(
                  label: Text(_weekdayNames[i]),
                  selected: selected,
                  selectedColor: _selectedControlColor(context),
                  checkmarkColor: _selectedControlTextColor(context),
                  labelStyle: _selectedChipLabelStyle(context, selected),
                  showCheckmark: false,
                  onSelected: (_) {
                    final next = {..._weekdays};
                    if (selected) {
                      next.remove(day);
                    } else {
                      next.add(day);
                    }
                    if (next.isEmpty) next.add(day);
                    setState(() => _weekdays = next.toList()..sort());
                  },
                );
              }),
            ),
          ],
          const SizedBox(height: DesignTokens.spaceMd),
          if (widget.allowAlarm && widget.showKindSelector) ...[
            Text('提醒方式', style: _labelStyle(context)),
            const SizedBox(height: DesignTokens.spaceXs),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<ReminderKind>(
                style: _selectedSegmentStyle(context),
                segments: const [
                  ButtonSegment(
                    value: ReminderKind.push,
                    label: Text('通知'),
                    icon: Icon(Icons.notifications_outlined),
                  ),
                  ButtonSegment(
                    value: ReminderKind.popup,
                    label: Text('弹出框'),
                    icon: Icon(Icons.open_in_new_outlined),
                  ),
                  ButtonSegment(
                    value: ReminderKind.alarm,
                    label: Text('闹钟'),
                    icon: Icon(Icons.alarm_outlined),
                  ),
                  ButtonSegment(
                    value: ReminderKind.off,
                    label: Text('关闭'),
                    icon: Icon(Icons.notifications_off_outlined),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() {
                  _kind = s.first;
                  _enabled = _kind != ReminderKind.off;
                }),
              ),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _vibrate,
            title: const Text('震动'),
            onChanged: (v) => setState(() => _vibrate = v),
          ),
          if (_kind == ReminderKind.alarm)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _fullScreen,
              title: const Text('全屏提醒'),
              subtitle: const Text('仅闹钟方式生效'),
              onChanged: (v) => setState(() => _fullScreen = v),
            ),
          if (widget.allowSnooze) ...[
            const SizedBox(height: DesignTokens.spaceXs),
            Text('稍后提醒', style: _labelStyle(context)),
            const SizedBox(height: DesignTokens.spaceXs),
            Wrap(
              spacing: DesignTokens.spaceXs,
              runSpacing: DesignTokens.spaceXs,
              children:
                  const [
                    (0, '关闭'),
                    (5, '5 分钟'),
                    (10, '10 分钟'),
                    (15, '15 分钟'),
                    (30, '30 分钟'),
                  ].map((preset) {
                    final selected = _snoozeMinutes == preset.$1;
                    return ChoiceChip(
                      label: Text(preset.$2),
                      selected: selected,
                      selectedColor: _selectedControlColor(context),
                      checkmarkColor: _selectedControlTextColor(context),
                      labelStyle: _selectedChipLabelStyle(context, selected),
                      onSelected: (_) =>
                          setState(() => _snoozeMinutes = preset.$1),
                    );
                  }).toList(),
            ),
            const SizedBox(height: DesignTokens.spaceSm),
            Text('重复次数', style: _labelStyle(context)),
            const SizedBox(height: DesignTokens.spaceXs),
            Wrap(
              spacing: DesignTokens.spaceXs,
              children: [0, 1, 2, 3].map((count) {
                final selected = _repeatCount == count;
                return ChoiceChip(
                  label: Text(count == 0 ? '不重复' : '$count 次'),
                  selected: selected,
                  selectedColor: _selectedControlColor(context),
                  checkmarkColor: _selectedControlTextColor(context),
                  labelStyle: _selectedChipLabelStyle(context, selected),
                  onSelected: (_) => setState(() => _repeatCount = count),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await AppTimePicker.show(
      context,
      initialTime: _time,
      title: '提醒时间',
      subtitle: '上下滚动选择，或用快捷按钮调整半小时',
      minuteStep: 5,
    );
    if (picked != null) setState(() => _time = picked);
  }

  void _save() {
    final type = _type;
    final kind = widget.showKindSelector && widget.allowAlarm
        ? _kind
        : widget.defaultKind;
    final rule = ReminderRule(
      id: widget.initial?.id,
      enabled: _enabled,
      type: type,
      kind: kind,
      hour: _time.hour,
      minute: _time.minute,
      offsetMinutes: type == ReminderRuleType.relativeToDue
          ? _offsetMinutes
          : null,
      weekdays: type == ReminderRuleType.weeklyTime ? _weekdays : const <int>[],
      vibrate: _vibrate,
      fullScreen: widget.allowAlarm && kind == ReminderKind.alarm
          ? _fullScreen
          : false,
      snoozeMinutes: _snoozeMinutes,
      repeatCount: _repeatCount,
    );
    Navigator.pop(context, rule);
  }
}

class _ReminderTimeField extends StatelessWidget {
  final TimeOfDay time;
  final VoidCallback onTap;

  const _ReminderTimeField({required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final borderColor = cs.outlineVariant.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.16 : 0.22,
    );

    return Semantics(
      key: const ValueKey('reminder_time_compact_field'),
      button: true,
      label: '提醒时间 ${_formatTimeOfDay(time)}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
              border: Border.all(color: borderColor, width: 0.45),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 20, color: cs.onSurfaceVariant),
                  const SizedBox(width: DesignTokens.spaceSm),
                  Expanded(
                    child: Text(
                      '提醒时间',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spaceXs),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 96),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        _formatTimeOfDay(time),
                        maxLines: 1,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _labelStyle(BuildContext context) {
  return TextStyle(
    fontSize: DesignTokens.fontSizeSm,
    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.68),
    fontWeight: DesignTokens.fontWeightStrong,
  );
}

ButtonStyle _selectedSegmentStyle(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final selectedBackground = _selectedControlColor(context);
  final selectedForeground = _selectedControlTextColor(context);
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return selectedBackground;
      return null;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return selectedForeground;
      if (states.contains(WidgetState.disabled)) {
        return cs.onSurface.withValues(alpha: 0.38);
      }
      return cs.onSurface;
    }),
    iconColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return selectedForeground;
      if (states.contains(WidgetState.disabled)) {
        return cs.onSurface.withValues(alpha: 0.38);
      }
      return cs.onSurfaceVariant;
    }),
  );
}

Color _selectedControlColor(BuildContext context) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  return Color.alphaBlend(
    cs.primary.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.14 : 0.09,
    ),
    cs.surface,
  );
}

Color _selectedControlTextColor(BuildContext context) {
  final theme = Theme.of(context);
  return _readableForeground(
    _selectedControlColor(context),
    theme.colorScheme.onSurface,
  );
}

TextStyle _selectedChipLabelStyle(BuildContext context, bool selected) {
  final cs = Theme.of(context).colorScheme;
  return TextStyle(
    color: selected ? _selectedControlTextColor(context) : cs.onSurface,
  );
}

Color _readableForeground(Color background, Color preferred) {
  final preferredContrast = _contrastRatio(background, preferred);
  final blackContrast = _contrastRatio(background, Colors.black);
  final whiteContrast = _contrastRatio(background, Colors.white);
  if (preferredContrast >= 4.5 ||
      (preferredContrast >= blackContrast &&
          preferredContrast >= whiteContrast)) {
    return preferred;
  }
  return blackContrast >= whiteContrast ? Colors.black : Colors.white;
}

double _contrastRatio(Color a, Color b) {
  final l1 = a.computeLuminance() + 0.05;
  final l2 = b.computeLuminance() + 0.05;
  return l1 > l2 ? l1 / l2 : l2 / l1;
}

IconData _ruleIcon(ReminderRule rule) {
  final kind = normalizeUserSelectableReminderKind(rule.kind);
  if (kind == ReminderKind.off) return Icons.notifications_off_outlined;
  if (kind == ReminderKind.alarm) return Icons.alarm_outlined;
  if (kind == ReminderKind.popup) return Icons.open_in_new_outlined;
  return switch (rule.type) {
    ReminderRuleType.absolute => Icons.event_available_outlined,
    ReminderRuleType.relativeToDue => Icons.timelapse_outlined,
    ReminderRuleType.dailyTime => Icons.today_outlined,
    ReminderRuleType.weeklyTime => Icons.calendar_view_week_outlined,
  };
}

String _ruleTitle(ReminderRule rule) {
  final mode = switch (normalizeUserSelectableReminderKind(rule.kind)) {
    ReminderKind.alarm => '闹钟',
    ReminderKind.popup => '弹出框',
    ReminderKind.off => '关闭',
    ReminderKind.push => '通知',
    ReminderKind.email => '通知',
  };
  return '${_typeLabel(rule.type)} · $mode';
}

String _ruleSummary(ReminderRule rule) {
  final pieces = <String>[_formatHm(rule.hour, rule.minute)];
  if (rule.type == ReminderRuleType.relativeToDue) {
    pieces.add('提前 ${_durationLabel((rule.offsetMinutes ?? 0).abs())}');
  }
  if (rule.type == ReminderRuleType.weeklyTime && rule.weekdays.isNotEmpty) {
    pieces.add(rule.weekdays.map(_weekdayLabel).join('/'));
  }
  if (rule.snoozeMinutes > 0) {
    pieces.add('稍后 ${rule.snoozeMinutes} 分钟');
  }
  if (rule.repeatCount > 0) {
    pieces.add('重复 ${rule.repeatCount} 次');
  }
  if (!rule.enabled) pieces.add('已停用');
  return pieces.join(' · ');
}

String _typeLabel(ReminderRuleType type) => switch (type) {
  ReminderRuleType.absolute => '到期提醒',
  ReminderRuleType.relativeToDue => '提前提醒',
  ReminderRuleType.dailyTime => '每日提醒',
  ReminderRuleType.weeklyTime => '每周提醒',
};

String _formatHm(int? hour, int? minute) {
  if (hour == null || minute == null) return '未设置时间';
  return I18nDateFormat.timeOfDay(hour: hour, minute: minute);
}

String _formatTimeOfDay(TimeOfDay time) {
  return I18nDateFormat.timeOfDay(hour: time.hour, minute: time.minute);
}

TimeOfDay nextHalfHourTimeOfDay([DateTime? from]) {
  final now = from ?? AppClock.now();
  if (now.minute < 30) {
    return TimeOfDay(hour: now.hour, minute: 30);
  }
  return TimeOfDay(hour: (now.hour + 1) % 24, minute: 0);
}

String _durationLabel(int minutes) {
  if (minutes >= 1440 && minutes % 1440 == 0) {
    return '${minutes ~/ 1440} 天';
  }
  if (minutes >= 60 && minutes % 60 == 0) return '${minutes ~/ 60} 小时';
  return '$minutes 分钟';
}

String _weekdayLabel(int day) {
  if (day < 1 || day > 7) return '周?';
  return '周${_weekdayNames[day - 1]}';
}

const _weekdayNames = <String>['一', '二', '三', '四', '五', '六', '日'];
