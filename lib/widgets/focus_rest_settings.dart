import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../models/pomodoro.dart';
import '../providers/pomodoro_provider.dart';
import 'surface_components.dart';
import 'app_modal_presentation.dart';

/// 专注页休息安排的稳定测试锚点。
abstract final class FocusRestKeys {
  static const Key summary = Key('focus_rest_summary');
  static const Key sheet = Key('focus_rest_settings_sheet');
  static const Key shortInput = Key('focus_rest_short_input');
  static const Key longInput = Key('focus_rest_long_input');
  static const Key intervalInput = Key('focus_rest_interval_input');
  static const Key linkSwitch = Key('focus_rest_link_switch');
  static const Key autoBreakSwitch = Key('focus_rest_auto_break_switch');
  static const Key autoFocusSwitch = Key('focus_rest_auto_focus_switch');
  static const Key shortMinus = Key('focus_rest_short_minus');
  static const Key shortPlus = Key('focus_rest_short_plus');
  static const Key save = Key('focus_rest_save');
  static const Key cancel = Key('focus_rest_cancel');
  static const Key error = Key('focus_rest_error');
  static const Key saveNote = Key('focus_rest_save_note');
}

String _minutes(int seconds) => (seconds ~/ 60).toString();

/// 计时卡内的整行休息摘要：短休 / 长休 / 长休息间隔，点击打开设置面板。
class FocusRestPlanSummary extends StatelessWidget {
  const FocusRestPlanSummary({
    super.key,
    required this.shortBreakDuration,
    required this.longBreakDuration,
    required this.sessionsPerLongBreak,
    required this.autoStartBreaks,
    required this.isCountUp,
    required this.onTap,
  });

  final int shortBreakDuration;
  final int longBreakDuration;
  final int sessionsPerLongBreak;
  final bool autoStartBreaks;
  final bool isCountUp;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rest = cs.secondary;
    final minuteUnit = I18n.tr('focus.rest.unit_minutes');
    final planLine =
        '${I18n.tr('focus.rest.summary_short')} '
        '${_minutes(shortBreakDuration)} $minuteUnit · '
        '${I18n.tr('focus.rest.summary_long')} '
        '${_minutes(longBreakDuration)} $minuteUnit';
    final caption = isCountUp
        ? I18n.tr('focus.rest.countup_note')
        : '${I18n.tr('focus.rest.every')}'
              '$sessionsPerLongBreak'
              '${I18n.tr('focus.rest.rounds_long')} · '
              '${autoStartBreaks ? I18n.tr('focus.rest.auto_break_summary') : I18n.tr('focus.rest.manual_after')}';

    return Semantics(
      container: true,
      button: true,
      label: '$planLine，$caption，${I18n.tr('focus.rest.open_sheet')}',
      child: Material(
        key: FocusRestKeys.summary,
        color: rest.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.18 : 0.09,
        ),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSmallTileApple),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: DesignTokens.focusRestSummaryMinHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spaceMd,
                vertical: DesignTokens.spaceSm,
              ),
              child: Row(
                children: [
                  Icon(Icons.bedtime_outlined, size: 20, color: rest),
                  const SizedBox(width: DesignTokens.spaceSm),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          planLine,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: DesignTokens.fontWeightMedium,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: DesignTokens.spaceXxs),
                        Text(
                          caption,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spaceSm),
                  Text(
                    I18n.tr('focus.rest.settings'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
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

/// 打开休息安排面板。生成号在打开瞬间捕获；编辑期间只动草稿。
Future<void> showFocusRestSettingsSheet({
  required BuildContext context,
  required PomodoroProvider provider,
}) {
  final generation = provider.configStorageGeneration;
  final timerActive = provider.state.isRunning || provider.isPaused;
  return showAppModalSheet<void>(
    context: context,
    builder: (_) => _FocusRestSettingsPanel(
      provider: provider,
      expectedStorageGeneration: generation,
      timerActive: timerActive,
    ),
  );
}

class _FocusRestSettingsPanel extends StatefulWidget {
  const _FocusRestSettingsPanel({
    required this.provider,
    required this.expectedStorageGeneration,
    required this.timerActive,
  });

  final PomodoroProvider provider;
  final int expectedStorageGeneration;
  final bool timerActive;

  @override
  State<_FocusRestSettingsPanel> createState() =>
      _FocusRestSettingsPanelState();
}

class _FocusRestSettingsPanelState extends State<_FocusRestSettingsPanel> {
  late final TextEditingController _shortCtrl;
  late final TextEditingController _longCtrl;
  late final TextEditingController _intervalCtrl;
  late bool _linkShortBreak;
  late bool _autoStartBreaks;
  late bool _autoStartFocus;
  late int _focusDurationSeconds;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final config = widget.provider.config;
    _focusDurationSeconds = config.focusDuration;
    _linkShortBreak = config.linkShortBreakToFocus;
    _autoStartBreaks = config.autoStartBreaks;
    _autoStartFocus = config.autoStartFocus;
    _shortCtrl = TextEditingController(
      text: _linkShortBreak
          ? _linkedShortMinutes(_focusDurationSeconds).toString()
          : _minutes(config.shortBreakDuration),
    );
    _longCtrl = TextEditingController(text: _minutes(config.longBreakDuration));
    _intervalCtrl = TextEditingController(
      text: config.sessionsPerLongBreak.toString(),
    );
  }

  @override
  void dispose() {
    _shortCtrl.dispose();
    _longCtrl.dispose();
    _intervalCtrl.dispose();
    super.dispose();
  }

  int _linkedShortMinutes(int focusDurationSeconds) =>
      PomodoroConfig.linkedShortBreakDuration(focusDurationSeconds) ~/ 60;

  int? _parse(TextEditingController controller, int min, int max) {
    final value = int.tryParse(controller.text.trim());
    if (value == null || value < min || value > max) return null;
    return value;
  }

  void _step(TextEditingController controller, int delta, int max) {
    if (_saving) return;
    final current = int.tryParse(controller.text.trim()) ?? 0;
    final next = (current + delta).clamp(1, max);
    setState(() {
      controller.text = next.toString();
      _error = null;
    });
  }

  void _onShortChanged(String _) => setState(() => _error = null);

  void _onLinkChanged(bool value) {
    if (_saving) return;
    // 从“当前”专注时长推导，而不是初始化时的快照。
    final currentFocus = widget.provider.config.focusDuration;
    setState(() {
      _linkShortBreak = value;
      _focusDurationSeconds = currentFocus;
      _error = null;
      if (value) {
        _shortCtrl.text = _linkedShortMinutes(currentFocus).toString();
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final shortMinutes = _linkShortBreak
        ? _linkedShortMinutes(widget.provider.config.focusDuration)
        : _parse(_shortCtrl, 1, 720);
    final longMinutes = _parse(_longCtrl, 1, 720);
    final interval = _parse(_intervalCtrl, 1, 20);

    if (shortMinutes == null) {
      setState(() => _error = I18n.tr('focus.rest.error.short'));
      return;
    }
    if (longMinutes == null) {
      setState(() => _error = I18n.tr('focus.rest.error.long'));
      return;
    }
    if (interval == null) {
      setState(() => _error = I18n.tr('focus.rest.error.interval'));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.provider.updateRestSettings(
        shortBreakDuration: shortMinutes * 60,
        longBreakDuration: longMinutes * 60,
        sessionsPerLongBreak: interval,
        linkShortBreakToFocus: _linkShortBreak,
        autoStartBreaks: _autoStartBreaks,
        autoStartFocus: _autoStartFocus,
        expectedStorageGeneration: widget.expectedStorageGeneration,
      );
      if (!mounted) return;
      if (saved) {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _saving = false;
        _error = I18n.tr('focus.rest.error.stale');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = I18n.tr('focus.rest.error.save');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rest = cs.secondary;
    final textScaler = MediaQuery.textScalerOf(context);
    final scaledBody = textScaler.scale(DesignTokens.fontSizeBody);
    final centered = AppModalPresentationScope.isCentered(context);
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(DesignTokens.radiusControlIos),
    );

    return AppModalSheet(
      key: FocusRestKeys.sheet,
      title: centered ? I18n.tr('focus.rest.title') : null,
      scrollable: false,
      maxWidth: DesignTokens.focusRestSheetMaxWidth,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: TextButton(
                  key: FocusRestKeys.cancel,
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.onSurface,
                    backgroundColor: cs.onSurface.withValues(alpha: 0.04),
                    minimumSize: const Size(0, DesignTokens.controlMinHeight),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: buttonShape,
                  ),
                  child: Text(I18n.tr('focus.rest.cancel')),
                ),
              ),
              const SizedBox(width: DesignTokens.spaceSm),
              Expanded(
                flex: 5,
                child: FilledButton(
                  key: FocusRestKeys.save,
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    minimumSize: const Size(0, DesignTokens.controlMinHeight),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: buttonShape,
                  ),
                  child: _saving
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: DesignTokens.spaceSm),
                            Text(I18n.tr('focus.rest.saving')),
                          ],
                        )
                      : Text(I18n.tr('focus.rest.save')),
                ),
              ),
            ],
          ),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!centered)
            Padding(
              padding: const EdgeInsets.only(bottom: DesignTokens.spaceMd),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      I18n.tr('focus.rest.title'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: DesignTokens.fontSizePageTitle,
                        fontWeight: DesignTokens.fontWeightStrong,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: I18n.tr('action.close'),
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: cs.onSurface.withValues(alpha: 0.04),
                      minimumSize: const Size(
                        DesignTokens.controlMinHeight,
                        DesignTokens.controlMinHeight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked =
                    constraints.maxWidth < 300 ||
                    scaledBody > DesignTokens.fontSizeBody * 1.2;
                return ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(bottom: DesignTokens.spaceSm),
                  children: [
                    _DraftSummary(restColor: rest, label: _draftSummaryLabel()),
                    _NumberField(
                      label: I18n.tr('focus.rest.short'),
                      hint: _linkShortBreak
                          ? '${I18n.tr('focus.rest.link_active_prefix')}'
                                '${widget.provider.config.focusDuration ~/ 60}'
                                '${I18n.tr('focus.rest.link_active_suffix')}'
                          : I18n.tr('focus.rest.short_hint'),
                      controller: _shortCtrl,
                      fieldKey: FocusRestKeys.shortInput,
                      minusKey: FocusRestKeys.shortMinus,
                      unit: I18n.tr('focus.rest.unit_minutes'),
                      enabled: !_saving && !_linkShortBreak,
                      stacked: stacked,
                      onChanged: _onShortChanged,
                      onStep: (delta) => _step(_shortCtrl, delta, 720),
                      stepLabel: I18n.tr('focus.rest.short'),
                    ),
                    _SwitchField(
                      label: I18n.tr('focus.rest.link'),
                      hint: I18n.tr('focus.rest.link_hint'),
                      value: _linkShortBreak,
                      switchKey: FocusRestKeys.linkSwitch,
                      enabled: !_saving,
                      stacked: stacked,
                      onChanged: _onLinkChanged,
                    ),
                    _NumberField(
                      label: I18n.tr('focus.rest.long'),
                      hint: I18n.tr('focus.rest.long_hint'),
                      controller: _longCtrl,
                      fieldKey: FocusRestKeys.longInput,
                      unit: I18n.tr('focus.rest.unit_minutes'),
                      enabled: !_saving,
                      stacked: stacked,
                      onChanged: (_) => setState(() => _error = null),
                      onStep: (delta) => _step(_longCtrl, delta, 720),
                      stepLabel: I18n.tr('focus.rest.long'),
                    ),
                    _NumberField(
                      label: I18n.tr('focus.rest.interval'),
                      hint: I18n.tr('focus.rest.interval_hint'),
                      controller: _intervalCtrl,
                      fieldKey: FocusRestKeys.intervalInput,
                      unit: I18n.tr('focus.rest.unit_rounds'),
                      enabled: !_saving,
                      stacked: stacked,
                      onChanged: (_) => setState(() => _error = null),
                      onStep: (delta) => _step(_intervalCtrl, delta, 20),
                      stepLabel: I18n.tr('focus.rest.interval'),
                    ),
                    _SwitchField(
                      label: I18n.tr('focus.rest.auto_break'),
                      hint: I18n.tr('focus.rest.auto_break_hint'),
                      value: _autoStartBreaks,
                      switchKey: FocusRestKeys.autoBreakSwitch,
                      enabled: !_saving,
                      stacked: stacked,
                      onChanged: (value) =>
                          setState(() => _autoStartBreaks = value),
                    ),
                    _SwitchField(
                      label: I18n.tr('focus.rest.auto_focus'),
                      hint: I18n.tr('focus.rest.auto_focus_hint'),
                      value: _autoStartFocus,
                      switchKey: FocusRestKeys.autoFocusSwitch,
                      enabled: !_saving,
                      stacked: stacked,
                      onChanged: (value) =>
                          setState(() => _autoStartFocus = value),
                    ),
                  ],
                );
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: DesignTokens.spaceSm),
              child: Text(
                _error!,
                key: FocusRestKeys.error,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: DesignTokens.spaceSm),
            child: Text(
              widget.timerActive
                  ? I18n.tr('focus.rest.save_note_running')
                  : I18n.tr('focus.rest.save_note_idle'),
              key: FocusRestKeys.saveNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _draftSummaryLabel() {
    final focusMinutes = widget.provider.config.focusDuration ~/ 60;
    final shortText = _linkShortBreak
        ? _linkedShortMinutes(widget.provider.config.focusDuration)
        : int.tryParse(_shortCtrl.text.trim());
    return '${I18n.tr('focus.rest.draft_prefix')} $focusMinutes '
        '${I18n.tr('focus.rest.draft_middle')} '
        '${shortText ?? '-'} ${I18n.tr('focus.rest.unit_minutes')}';
  }
}

class _DraftSummary extends StatelessWidget {
  const _DraftSummary({required this.restColor, required this.label});

  final Color restColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: DesignTokens.spaceXs),
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceMd,
        vertical: DesignTokens.spaceSm + DesignTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        color: restColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, size: 17, color: restColor),
          const SizedBox(width: DesignTokens.spaceSm),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.fieldKey,
    required this.unit,
    required this.enabled,
    required this.stacked,
    required this.onChanged,
    required this.onStep,
    required this.stepLabel,
    this.minusKey,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final Key fieldKey;
  final Key? minusKey;
  final String unit;
  final bool enabled;
  final bool stacked;
  final ValueChanged<String> onChanged;
  final ValueChanged<int> onStep;
  final String stepLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final labelBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: DesignTokens.fontWeightMedium,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: DesignTokens.spaceXxs),
        Text(
          hint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
    final control = _buildStepper(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceSm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.onSurface.withValues(alpha: 0.06)),
        ),
      ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                labelBlock,
                const SizedBox(height: DesignTokens.spaceSm),
                control,
              ],
            )
          : Row(
              children: [
                Expanded(child: labelBlock),
                const SizedBox(width: DesignTokens.spaceMd),
                control,
              ],
            ),
    );
  }

  Widget _buildStepper(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            buttonKey: minusKey,
            icon: Icons.remove,
            tooltip: stepLabel,
            onPressed: enabled ? () => onStep(-1) : null,
          ),
          SizedBox(
            width: 48,
            child: TextField(
              key: fieldKey,
              controller: controller,
              enabled: enabled,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: onChanged,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: DesignTokens.fontWeightMedium,
                color: enabled ? cs.onSurface : cs.onSurfaceVariant,
              ),
              decoration: const InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: DesignTokens.spaceSm),
            child: Text(
              unit,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add,
            tooltip: stepLabel,
            onPressed: enabled ? () => onStep(1) : null,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.buttonKey,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: buttonKey,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        minimumSize: const Size(
          DesignTokens.controlMinHeight,
          DesignTokens.controlMinHeight,
        ),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.standard,
      ),
    );
  }
}

class _SwitchField extends StatelessWidget {
  const _SwitchField({
    required this.label,
    required this.hint,
    required this.value,
    required this.switchKey,
    required this.enabled,
    required this.stacked,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final Key switchKey;
  final bool enabled;
  final bool stacked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final labelBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: DesignTokens.fontWeightMedium,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: DesignTokens.spaceXxs),
        Text(
          hint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
    final control = Switch(
      key: switchKey,
      value: value,
      onChanged: enabled ? onChanged : null,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceSm),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.onSurface.withValues(alpha: 0.06)),
        ),
      ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                labelBlock,
                Align(alignment: Alignment.centerLeft, child: control),
              ],
            )
          : Row(
              children: [
                Expanded(child: labelBlock),
                const SizedBox(width: DesignTokens.spaceMd),
                control,
              ],
            ),
    );
  }
}

/// Flat auxiliary rows in the approved focus card; actions remain owned by
/// the screen's existing task, sound and room pickers.
class FocusUtilityTile extends StatelessWidget {
  const FocusUtilityTile({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.inline = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = Text(
      label,
      style: theme.textTheme.bodySmall?.copyWith(
        fontWeight: DesignTokens.fontWeightMedium,
      ),
    );
    final detail = Text(
      subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: inline ? TextAlign.end : TextAlign.start,
      style: theme.textTheme.labelSmall?.copyWith(
        color: cs.onSurfaceVariant,
        fontWeight: DesignTokens.fontWeightRegular,
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: DesignTokens.controlMinHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceSm),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: DesignTokens.controlIconSize,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: DesignTokens.spaceSm),
                if (inline) ...[
                  title,
                  const SizedBox(width: DesignTokens.spaceSm),
                  Expanded(child: detail),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ] else
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: DesignTokens.spaceXxs),
                        detail,
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FocusUtilityToggle extends StatelessWidget {
  const FocusUtilityToggle({
    super.key,
    required this.icon,
    required this.label,
    required this.help,
    required this.value,
    required this.onChanged,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String help;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: help,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: DesignTokens.controlMinHeight,
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: DesignTokens.spaceSm),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: DesignTokens.fontWeightMedium,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: value,
                  onChanged: onChanged,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
