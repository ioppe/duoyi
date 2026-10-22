import '../core/app_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/design_tokens.dart';
import '../core/focus_sound_catalog.dart';
import '../core/goal_icons.dart';
import '../core/goal_validation.dart';
import '../core/i18n_date_format.dart';
import '../core/i18n.dart';
import '../models/goal.dart';
import '../models/recurrence.dart';
import '../models/workspace.dart';
import '../providers/custom_focus_sound_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/notification_service.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/share_provider.dart';
import '../services/alarm_service.dart';
import '../services/focus_sound_service.dart';
import '../services/recurrence_engine.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/recurrence_picker.dart';
import '../widgets/reminder_health_hint.dart';
import '../widgets/reminder_plan_editor.dart';
import '../widgets/surface_components.dart';

const List<int> _presetColors = <int>[
  0xFFFFA726,
  0xFF66BB6A,
  0xFF42A5F5,
  0xFFAB47BC,
  0xFFEF5350,
  0xFF26A69A,
];

const List<String> _weekdayNames = <String>['一', '二', '三', '四', '五', '六', '日'];

const List<int> _focusMinutePresets = <int>[15, 25, 30, 45, 60, 90];

Future<void> showGoalCreateSheet(BuildContext context) async {
  await showAppModalSheet<void>(
    context: context,
    builder: (_) => const GoalEditScreen(),
  );
}

class GoalEditScreen extends StatefulWidget {
  final GoalItem? goal;
  const GoalEditScreen({super.key, this.goal});

  @override
  State<GoalEditScreen> createState() => _GoalEditScreenState();
}

class _GoalEditScreenState extends State<GoalEditScreen> {
  // ---- Basic ----
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  DateTime? _startDate;
  DateTime? _targetDate;
  GoalStatus _status = GoalStatus.active;
  int _colorValue = 0xFFFFA726;
  late String _iconName;

  // ---- Recurrence ----
  RecurrenceRule _recurrence = const RecurrenceRule();

  // ---- Scheduling ----
  GoalScheduling _scheduling = const GoalScheduling.fixed();
  late final TextEditingController _minGapCtrl;
  late final TextEditingController _maxPerWeekCtrl;
  late final TextEditingController _maxPerMonthCtrl;

  // ---- Skip holidays ----
  bool _skipHolidays = false;

  // ---- Focus ----
  FocusLink _focus = const FocusLink.disabled();
  late final TextEditingController _focusMinutesCtrl;

  // ---- Reminder ----
  ReminderConfig _reminder = const ReminderConfig.disabled();
  ReminderPlan _reminderPlan = const ReminderPlan.disabled();

  // ---- Time target ----
  late final TextEditingController _timeTargetCtrl;

  // ---- Daily count ----
  late final TextEditingController _dailyCountCtrl;

  // ---- Milestones & auto progress ----
  bool _autoProgress = true;
  double _manualProgress = 0;
  List<GoalMilestone> _milestones = <GoalMilestone>[];
  late final TextEditingController _milestoneCtrl;

  /// 若为编辑模式则为原始 id；为新建模式时首次保存后赋值，
  /// 这样后续模块保存可直接走 `GoalProvider.update`。
  String? _editingId;

  /// 保留 createdAt，避免新建后再次 update 时时间被刷新。
  DateTime? _createdAt;
  String _workspaceId = 'private';

  bool _persisting = false;

  bool get _isExisting => _editingId != null;

  @override
  void initState() {
    super.initState();
    final g = widget.goal;
    _editingId = g?.id;
    _createdAt = g?.createdAt;
    _workspaceId = _normalizeWorkspaceId(g?.workspaceId);

    _titleCtrl = TextEditingController(text: g?.title ?? '');
    _descCtrl = TextEditingController(text: g?.description ?? '');
    _startDate = g?.startDate;
    _targetDate = g?.targetDate;
    _status = g?.status ?? GoalStatus.active;
    _colorValue = g?.colorValue ?? 0xFFFFA726;
    _iconName = g?.icon ?? 'flag';
    _recurrence = g?.recurrence ?? const RecurrenceRule();
    _scheduling = g?.scheduling ?? const GoalScheduling.fixed();
    _skipHolidays = g?.skipHolidays ?? false;
    _focus = g?.focusLink ?? const FocusLink.disabled();
    _reminder = g?.reminder ?? const ReminderConfig.disabled();
    _reminderPlan = g?.reminderPlan ?? ReminderPlan.fromLegacy(_reminder);
    _autoProgress = g?.autoProgress ?? true;
    _manualProgress = g?.autoProgress == true
        ? g?.computedProgress ?? 0
        : g?.progress ?? 0;
    _milestones = <GoalMilestone>[...?g?.milestones];

    _minGapCtrl = TextEditingController(
      text: _scheduling.randomMinGapDays?.toString() ?? '',
    );
    _maxPerWeekCtrl = TextEditingController(
      text: _scheduling.randomMaxPerWeek?.toString() ?? '',
    );
    _maxPerMonthCtrl = TextEditingController(
      text: _scheduling.randomMaxPerMonth?.toString() ?? '',
    );
    _focusMinutesCtrl = TextEditingController(
      text: _focus.focusSeconds != null
          ? (_focus.focusSeconds! ~/ 60).toString()
          : '',
    );
    _timeTargetCtrl = TextEditingController(
      text: g?.timeTargetSeconds != null
          ? (g!.timeTargetSeconds! ~/ 60).toString()
          : '',
    );
    _dailyCountCtrl = TextEditingController(
      text: g?.dailyTargetCount?.toString() ?? '',
    );
    _milestoneCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _minGapCtrl.dispose();
    _maxPerWeekCtrl.dispose();
    _maxPerMonthCtrl.dispose();
    _focusMinutesCtrl.dispose();
    _timeTargetCtrl.dispose();
    _dailyCountCtrl.dispose();
    _milestoneCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  GoalItem _composeItem() {
    return GoalItem(
      id: _editingId,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      icon: _iconName,
      colorValue: _colorValue,
      startDate: _startDate,
      targetDate: _targetDate,
      status: _status,
      autoProgress: _autoProgress,
      progress: _autoProgress ? _currentAutoProgress() : _manualProgress,
      milestones: _milestones,
      category: widget.goal?.category ?? GoalCategory.custom,
      recurrence: _recurrence,
      scheduling: _scheduling,
      skipHolidays: _skipHolidays,
      focusLink: _focus,
      reminder: _reminderPlan.toLegacyReminderConfig(fallback: _reminder),
      reminderPlan: _reminderPlan,
      timeTargetSeconds: _parsePositiveInt(
        _timeTargetCtrl.text,
      ).let((min) => min * 60),
      dailyTargetCount: _parsePositiveInt(_dailyCountCtrl.text),
      sortOrder: widget.goal?.sortOrder ?? 0,
      workspaceId: _workspaceId,
      createdAt: _createdAt,
    );
  }

  Future<bool> _persist({required bool pop}) async {
    if (_persisting) return false;
    setState(() => _persisting = true);
    try {
      if (_titleCtrl.text.trim().isEmpty) {
        _showError('请填写目标标题');
        return false;
      }
      final item = _composeItem();
      final issues = validateGoal(item);
      if (issues.isNotEmpty) {
        _showError(issues.first.message);
        return false;
      }
      if (!_canEditWorkspace(_workspaceId)) {
        _showError('你在这个共享空间中只有查看权限');
        return false;
      }
      final provider = context.read<GoalProvider>();
      if (!_isExisting) {
        await provider.add(item);
        if (!mounted) return true;
        setState(() {
          _editingId = item.id;
          _createdAt = item.createdAt;
        });
      } else {
        await provider.update(item);
      }
      if (!mounted) return true;
      if (pop) {
        Navigator.pop(context);
      } else {
        _showSaved();
      }
      return true;
    } finally {
      if (mounted) {
        setState(() => _persisting = false);
      }
    }
  }

  Future<void> _pickFocusNoise(String id) async {
    setState(() => _focus = _focus.copyWith(whiteNoise: id));
    if (id == FocusSoundCatalog.none) {
      await FocusSoundService.instance.stop();
      return;
    }
    final volume =
        context.read<PomodoroProvider?>()?.config.focusSoundVolume ??
        FocusSoundService.defaultVolume;
    await FocusSoundService.instance.setVolume(volume);
    final started = await FocusSoundService.instance.preview(id);
    if (!mounted || started) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('专注声音预览启动失败，请检查系统音量或音频资源'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSaved() {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('已保存'),
          duration: Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          backgroundColor: DesignTokens.resultError,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  bool _canEditWorkspace(String workspaceId) {
    return context.read<ShareProvider?>()?.canEdit(workspaceId) ?? true;
  }

  Future<void> _deleteCurrentGoal() async {
    if (!_canEditWorkspace(_workspaceId)) {
      _showError('你在这个共享空间中只有查看权限');
      return;
    }
    final navigator = Navigator.of(context);
    await context.read<GoalProvider>().delete(_editingId!);
    if (!mounted) return;
    navigator.pop();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final shareProvider = context.watch<ShareProvider?>();
    final canEditCurrentWorkspace =
        shareProvider?.canEdit(_workspaceId) ?? true;
    final formChildren = <Widget>[
      _BasicSection(
        titleCtrl: _titleCtrl,
        descCtrl: _descCtrl,
        startDate: _startDate,
        targetDate: _targetDate,
        status: _status,
        colorValue: _colorValue,
        iconName: _iconName,
        onPickStart: (d) => setState(() => _startDate = d),
        onPickTarget: (d) => setState(() => _targetDate = d),
        onStatus: (s) => setState(() => _status = s),
        onColor: (v) => setState(() => _colorValue = v),
        onIcon: (v) => setState(() => _iconName = v),
        onSave: () => _persist(pop: false),
      ),
      _WorkspaceSection(
        workspaceId: _workspaceId,
        shareProvider: shareProvider,
        onChanged: (value) => setState(() {
          _workspaceId = _normalizeWorkspaceId(value);
        }),
        onSave: () => _persist(pop: false),
      ),
      _RecurrenceSection(
        rule: _recurrence,
        nextDispatchLabel: _nextDispatchLabel(),
        onPick: () async {
          final r = await RecurrencePicker.show(
            context,
            initial: _recurrence,
            supportMaxOccurrences: false,
          );
          if (r != null) setState(() => _recurrence = r);
        },
        onSave: () => _persist(pop: false),
      ),
      _SchedulingSection(
        scheduling: _scheduling,
        recurrence: _recurrence,
        minGapCtrl: _minGapCtrl,
        maxPerWeekCtrl: _maxPerWeekCtrl,
        maxPerMonthCtrl: _maxPerMonthCtrl,
        onModeChange: (mode) => setState(() {
          _scheduling = _scheduling.copyWith(mode: mode);
        }),
        onWeekdaysChange: (days) => setState(() {
          _scheduling = GoalScheduling(
            mode: _scheduling.mode,
            fixedWeekdays: days.isEmpty ? null : List<int>.unmodifiable(days),
            fixedMonthDays: _scheduling.fixedMonthDays,
            randomMinGapDays: _scheduling.randomMinGapDays,
            randomMaxPerWeek: _scheduling.randomMaxPerWeek,
            randomMaxPerMonth: _scheduling.randomMaxPerMonth,
          );
        }),
        onMonthDaysChange: (days) => setState(() {
          _scheduling = GoalScheduling(
            mode: _scheduling.mode,
            fixedWeekdays: _scheduling.fixedWeekdays,
            fixedMonthDays: days.isEmpty ? null : List<int>.unmodifiable(days),
            randomMinGapDays: _scheduling.randomMinGapDays,
            randomMaxPerWeek: _scheduling.randomMaxPerWeek,
            randomMaxPerMonth: _scheduling.randomMaxPerMonth,
          );
        }),
        onRandomChange: () => setState(() {
          _scheduling = GoalScheduling(
            mode: SchedulingMode.random,
            fixedWeekdays: _scheduling.fixedWeekdays,
            fixedMonthDays: _scheduling.fixedMonthDays,
            randomMinGapDays: _parsePositiveInt(_minGapCtrl.text),
            randomMaxPerWeek: _parsePositiveInt(_maxPerWeekCtrl.text),
            randomMaxPerMonth: _parsePositiveInt(_maxPerMonthCtrl.text),
          );
        }),
        onSave: () {
          // 随机模式下,输入框的改动尚未提交到 _scheduling,先同步一次。
          if (_scheduling.mode == SchedulingMode.random) {
            _scheduling = GoalScheduling(
              mode: SchedulingMode.random,
              fixedWeekdays: _scheduling.fixedWeekdays,
              fixedMonthDays: _scheduling.fixedMonthDays,
              randomMinGapDays: _parsePositiveInt(_minGapCtrl.text),
              randomMaxPerWeek: _parsePositiveInt(_maxPerWeekCtrl.text),
              randomMaxPerMonth: _parsePositiveInt(_maxPerMonthCtrl.text),
            );
          }
          _persist(pop: false);
        },
      ),
      _SkipHolidaysSection(
        enabled: _skipHolidays,
        onChange: (v) => setState(() => _skipHolidays = v),
        onSave: () => _persist(pop: false),
      ),
      _FocusSection(
        focus: _focus,
        minutesCtrl: _focusMinutesCtrl,
        onToggle: (v) => setState(() {
          _focus = _focus.copyWith(enabled: v);
        }),
        onPickPreset: (min) => setState(() {
          _focusMinutesCtrl.text = min.toString();
          _focus = _focus.copyWith(focusSeconds: min * 60);
        }),
        onMinutesChange: (v) {
          final min = _parsePositiveInt(v);
          setState(() {
            _focus = FocusLink(
              enabled: _focus.enabled,
              presetId: _focus.presetId,
              focusSeconds: min == null ? null : min * 60,
              whiteNoise: _focus.whiteNoise,
            );
          });
        },
        onPickNoise: _pickFocusNoise,
        onSave: () => _persist(pop: false),
      ),
      _SectionCard(
        title: '提醒',
        icon: Icons.notifications_active_outlined,
        subtitle: reminderPlanSummary(_reminderPlan),
        onSave: () => _persist(pop: false),
        children: [
          ReminderPlanEditor(
            plan: _reminderPlan,
            showHeader: false,
            allowAlarm: true,
            allowRelativeToDue: true,
            allowWeekly: true,
            hasAnchorDate: _targetDate != null,
            defaultKind: ReminderKind.push,
            onChanged: (plan) => setState(() {
              _reminderPlan = plan;
              _reminder = plan.toLegacyReminderConfig(fallback: _reminder);
            }),
          ),
          const SizedBox(height: DesignTokens.spaceSm),
          Builder(
            builder: (context) {
              final notif = context.watch<NotificationService?>();
              if (notif == null) return const SizedBox.shrink();
              final kind = _reminderPlan.primaryRule?.kind ?? _reminder.kind;
              return ReminderHealthHint(
                reminderKind: kind,
                onOpenSystemSettings: () => openAppSettings(),
                onRequestNotificationPermission: () async {
                  await context.read<NotificationService>().requestPermission();
                },
                onRequestExactAlarmPermission: () async {
                  await AlarmService.instance.requestExactAlarmPermission();
                },
                onRequestFullScreenIntentPermission: () async {
                  await AlarmService.instance
                      .requestFullScreenIntentPermission();
                },
              );
            },
          ),
        ],
      ),
      _TimeTargetSection(
        controller: _timeTargetCtrl,
        onClear: () {
          setState(() {
            _timeTargetCtrl.clear();
          });
        },
        onSave: () => _persist(pop: false),
      ),
      _DailyCountSection(
        controller: _dailyCountCtrl,
        onInc: () {
          final v = _parsePositiveInt(_dailyCountCtrl.text) ?? 0;
          setState(() {
            _dailyCountCtrl.text = (v + 1).toString();
          });
        },
        onDec: () {
          final v = _parsePositiveInt(_dailyCountCtrl.text) ?? 0;
          final next = v - 1;
          setState(() {
            _dailyCountCtrl.text = next <= 0 ? '' : next.toString();
          });
        },
        onChanged: (_) => setState(() {}),
        onSave: () => _persist(pop: false),
      ),
      _MilestonesSection(
        milestones: _milestones,
        controller: _milestoneCtrl,
        autoProgress: _autoProgress,
        manualProgress: _manualProgress,
        onToggle: (m, v) => setState(() {
          m.isCompleted = v;
          m.completedAt = v ? DateTime.now() : null;
        }),
        onRemove: (i) => setState(() {
          _milestones.removeAt(i);
        }),
        onAdd: (title) => setState(() {
          _milestones.add(GoalMilestone(title: title));
          _milestoneCtrl.clear();
        }),
        onAutoChange: (v) => setState(() {
          if (!v) {
            _manualProgress = _currentAutoProgress();
          }
          _autoProgress = v;
        }),
        onManualChange: (v) => setState(() => _manualProgress = v),
      ),
      const SizedBox(height: DesignTokens.spaceMd),
      Row(
        children: [
          TextButton(
            key: const ValueKey('goal_form_cancel'),
            onPressed: _persisting ? null : () => Navigator.pop(context),
            child: Text(I18n.tr('action.cancel')),
          ),
          const SizedBox(width: DesignTokens.spaceMd),
          Expanded(
            child: FilledButton(
              key: const ValueKey('goal_form_submit'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
              onPressed: canEditCurrentWorkspace && !_persisting
                  ? () => _persist(pop: true)
                  : null,
              child: _persisting
                  ? const SizedBox.square(
                      dimension: DesignTokens.controlIconSize,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(I18n.tr('action.save')),
            ),
          ),
        ],
      ),
    ];
    if (widget.goal == null) {
      return AppModalSheet(
        key: const ValueKey('goal_create_sheet'),
        title: I18n.tr('goal.create'),
        child: Column(
          key: const ValueKey('goal_form_content'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: formChildren,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑目标'),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        actions: [
          if (_isExisting)
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline),
              onPressed: canEditCurrentWorkspace ? _deleteCurrentGoal : null,
            ),
          IconButton(
            tooltip: '保存并返回',
            icon: _persisting
                ? const SizedBox.square(
                    dimension: DesignTokens.controlIconSize,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            onPressed: canEditCurrentWorkspace && !_persisting
                ? () => _persist(pop: true)
                : null,
          ),
        ],
      ),
      body: AppSecondaryControlTheme(
        child: Center(
          child: ConstrainedBox(
            key: const ValueKey('goal_form_content'),
            constraints: const BoxConstraints(
              maxWidth: DesignTokens.creationFormMaxWidth,
            ),
            child: ListView(
              key: const ValueKey('goal_form_scroll'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.spaceLg,
                DesignTokens.spaceMd,
                DesignTokens.spaceLg,
                DesignTokens.space3xl,
              ),
              children: formChildren,
            ),
          ),
        ),
      ),
    );
  }

  double _currentAutoProgress() {
    if (_milestones.isEmpty) {
      return _status == GoalStatus.achieved ? 1.0 : 0.0;
    }
    final done = _milestones.where((m) => m.isCompleted).length;
    return (done / _milestones.length).clamp(0.0, 1.0);
  }

  String _nextDispatchLabel() {
    if (_recurrence.frequency == RecurrenceFrequency.none) return '不重复';
    final now = AppClock.now();
    final today = DateTime(now.year, now.month, now.day);
    final effectiveStart = _goalEffectiveStartDay(
      startDate: _startDate,
      createdAt: _createdAt,
      fallback: now,
    );
    final searchFrom = effectiveStart.isAfter(today) ? effectiveStart : today;
    final anchor = searchFrom.subtract(const Duration(days: 1));
    final next = RecurrenceEngine.nextOccurrence(
      rule: _recurrence,
      scheduling: _scheduling,
      skipHolidays: _skipHolidays,
      anchor: anchor,
      goalId: _editingId,
    );
    if (next == null) return '无（已到终止日）';
    return _formatDate(next);
  }
}

// ---------------------------------------------------------------------------
// Section: 基础信息
// ---------------------------------------------------------------------------

class _BasicSection extends StatelessWidget {
  final TextEditingController titleCtrl;
  final TextEditingController descCtrl;
  final DateTime? startDate;
  final DateTime? targetDate;
  final GoalStatus status;
  final int colorValue;
  final String iconName;
  final ValueChanged<DateTime?> onPickStart;
  final ValueChanged<DateTime?> onPickTarget;
  final ValueChanged<GoalStatus> onStatus;
  final ValueChanged<int> onColor;
  final ValueChanged<String> onIcon;
  final VoidCallback onSave;

  const _BasicSection({
    required this.titleCtrl,
    required this.descCtrl,
    required this.startDate,
    required this.targetDate,
    required this.status,
    required this.colorValue,
    required this.iconName,
    required this.onPickStart,
    required this.onPickTarget,
    required this.onStatus,
    required this.onColor,
    required this.onIcon,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '基础信息',
      icon: Icons.flag_outlined,
      initiallyExpanded: true,
      onSave: onSave,
      children: [
        TextField(
          key: const ValueKey('goal_form_title'),
          controller: titleCtrl,
          minLines: 1,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            labelText: '目标',
            hintText: '如：今年读 24 本书',
          ),
        ),
        const SizedBox(height: DesignTokens.spaceLg),
        TextField(
          key: const ValueKey('goal_form_description'),
          controller: descCtrl,
          minLines: 3,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            labelText: '描述 (可选)',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: DesignTokens.spaceLg),
        _GoalDateFields(
          startDate: startDate,
          targetDate: targetDate,
          onPickStart: onPickStart,
          onPickTarget: onPickTarget,
        ),
        const SizedBox(height: DesignTokens.spaceLg),
        Text('颜色', style: _subtleLabel(context)),
        const SizedBox(height: DesignTokens.spaceXs),
        Wrap(
          spacing: DesignTokens.spaceSm,
          runSpacing: DesignTokens.spaceSm,
          children: _presetColors.map((v) {
            final selected = v == colorValue;
            return GestureDetector(
              onTap: () => onColor(v),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(v),
                  shape: BoxShape.circle,
                  border: selected
                      ? Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.58),
                          width: 0.45,
                        )
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: DesignTokens.spaceLg),
        Text('图标', style: _subtleLabel(context)),
        const SizedBox(height: DesignTokens.spaceXs),
        _GoalIconField(
          iconName: iconName,
          colorValue: colorValue,
          onPick: onIcon,
        ),
        const SizedBox(height: DesignTokens.spaceLg),
        Text('状态', style: _subtleLabel(context)),
        const SizedBox(height: DesignTokens.spaceXs),
        Wrap(
          spacing: DesignTokens.spaceXs,
          runSpacing: DesignTokens.spaceSm,
          children: GoalStatus.values.map((s) {
            final label = switch (s) {
              GoalStatus.active => '进行中',
              GoalStatus.paused => '暂停',
              GoalStatus.achieved => '已达成',
              GoalStatus.abandoned => '放弃',
            };
            return ChoiceChip(
              label: Text(label),
              selected: status == s,
              onSelected: (_) => onStatus(s),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _WorkspaceSection extends StatelessWidget {
  final String workspaceId;
  final ShareProvider? shareProvider;
  final ValueChanged<String> onChanged;
  final VoidCallback onSave;

  const _WorkspaceSection({
    required this.workspaceId,
    required this.shareProvider,
    required this.onChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final options = _workspaceOptions(shareProvider, workspaceId);
    final current = options.any((option) => option.id == workspaceId)
        ? workspaceId
        : 'private';
    final role = shareProvider?.roleFor(current) ?? WorkspaceRole.owner;
    final canEdit = shareProvider?.canEdit(current) ?? true;
    final subtitle = current == 'private'
        ? '个人空间'
        : '${_workspaceLabel(options, current)} · ${role.label}';

    return _SectionCard(
      title: '空间归属',
      icon: Icons.groups_2_outlined,
      subtitle: subtitle,
      onSave: canEdit ? onSave : null,
      children: [
        AppFormFieldTheme(
          child: AppDropdownField<String>(
            initialValue: current,
            decoration: const InputDecoration(
              labelText: '保存到',
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            items: options.map((option) {
              final optionRole = option.id == 'private'
                  ? WorkspaceRole.owner
                  : shareProvider?.roleFor(option.id) ?? WorkspaceRole.owner;
              final enabled =
                  canEdit && (option.id == 'private' || optionRole.canEdit);
              return DropdownMenuItem<String>(
                value: option.id,
                enabled: enabled,
                child: _WorkspaceOptionLabel(option: option, role: optionRole),
              );
            }).toList(),
            enabled: canEdit,
            onChanged: (value) {
              if (value == null) return;
              final nextRole = value == 'private'
                  ? WorkspaceRole.owner
                  : shareProvider?.roleFor(value) ?? WorkspaceRole.owner;
              if (!nextRole.canEdit) return;
              onChanged(value);
            },
          ),
        ),
        if (!canEdit) ...[
          const SizedBox(height: DesignTokens.spaceSm),
          Text(
            '你在这个共享空间中只有查看权限',
            style: TextStyle(
              fontSize: DesignTokens.fontSizeSm,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

class _WorkspaceChoice {
  final String id;
  final String name;

  const _WorkspaceChoice({required this.id, required this.name});
}

class _WorkspaceOptionLabel extends StatelessWidget {
  final _WorkspaceChoice option;
  final WorkspaceRole role;

  const _WorkspaceOptionLabel({required this.option, required this.role});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPrivate = option.id == 'private';
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Icon(
          isPrivate ? Icons.person_outline : Icons.groups_2_outlined,
          size: 18,
        ),
        const SizedBox(width: DesignTokens.spaceXs),
        Expanded(
          child: Text(
            option.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!isPrivate) ...[
          const SizedBox(width: DesignTokens.spaceXs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 48),
            child: Text(
              role.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                color: cs.onSurface.withValues(alpha: 0.56),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _GoalIconField extends StatelessWidget {
  final String iconName;
  final int colorValue;
  final ValueChanged<String> onPick;

  const _GoalIconField({
    required this.iconName,
    required this.colorValue,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = Color(colorValue);
    final icon = goalIconFromName(iconName);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: DesignTokens.borderRadiusSm,
        onTap: () async {
          final picked = await _showGoalIconPicker(context, iconName);
          if (picked != null) onPick(picked);
        },
        child: Ink(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.55),
              width: 0.45,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceMd,
              vertical: DesignTokens.spaceSm,
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: DesignTokens.borderRadiusMd,
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: DesignTokens.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goalIconLabel(iconName),
                        style: appSecondaryControlTextStyle(context),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '点击更换',
                        style: appSecondaryControlLabelStyle(
                          context,
                        ).copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: cs.onSurface.withValues(alpha: 0.46),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoalDateFields extends StatelessWidget {
  final DateTime? startDate;
  final DateTime? targetDate;
  final ValueChanged<DateTime?> onPickStart;
  final ValueChanged<DateTime?> onPickTarget;

  const _GoalDateFields({
    required this.startDate,
    required this.targetDate,
    required this.onPickStart,
    required this.onPickTarget,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 460;
        return Row(
          children: [
            Expanded(
              child: _DateField(
                key: const ValueKey('goal_start_date_field'),
                label: '开始日期',
                date: startDate,
                emptyText: '创建即开启',
                compact: compact,
                onPick: onPickStart,
              ),
            ),
            SizedBox(width: compact ? 6 : DesignTokens.spaceSm),
            Expanded(
              child: _DateField(
                key: const ValueKey('goal_target_date_field'),
                label: '目标日期',
                date: targetDate,
                emptyText: '无期限',
                compact: compact,
                onPick: onPickTarget,
              ),
            ),
          ],
        );
      },
    );
  }
}

Future<String?> _showGoalIconPicker(BuildContext context, String selected) {
  return showAppModalSheet<String>(
    context: context,
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return AppModalSheet(
        title: '选择图标',
        scrollable: false,
        child: SizedBox(
          height: 420,
          child: GridView.builder(
            padding: EdgeInsets.zero,
            itemCount: goalIconChoices.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: DesignTokens.spaceSm,
              crossAxisSpacing: DesignTokens.spaceSm,
              childAspectRatio: 0.92,
            ),
            itemBuilder: (context, index) {
              final choice = goalIconChoices[index];
              final isSelected = choice.name == selected;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: DesignTokens.borderRadiusMd,
                  onTap: () => Navigator.pop(context, choice.name),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? choice.color.withValues(alpha: 0.14)
                          : cs.surfaceContainerHighest.withValues(alpha: 0.36),
                      borderRadius: DesignTokens.borderRadiusMd,
                      border: Border.all(
                        color: isSelected
                            ? choice.color
                            : cs.outline.withValues(alpha: 0.16),
                        width: 0.45,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(choice.icon, color: choice.color, size: 24),
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Text(
                                  choice.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: DesignTokens.fontSizeXs,
                                    fontWeight: DesignTokens.fontWeightStrong,
                                    color: cs.onSurface.withValues(alpha: 0.76),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Icon(
                              Icons.check_circle,
                              size: 16,
                              color: choice.color,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Section: 重复规则
// ---------------------------------------------------------------------------

class _RecurrenceSection extends StatelessWidget {
  final RecurrenceRule rule;
  final String nextDispatchLabel;
  final VoidCallback onPick;
  final VoidCallback onSave;

  const _RecurrenceSection({
    required this.rule,
    required this.nextDispatchLabel,
    required this.onPick,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '重复规则',
      icon: Icons.repeat,
      subtitle: rule.label,
      onSave: onSave,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.tune),
          title: const Text('编辑重复规则'),
          subtitle: Text(rule.label),
          trailing: const Icon(Icons.chevron_right),
          onTap: onPick,
        ),
        const SizedBox(height: DesignTokens.spaceXs),
        Container(
          padding: const EdgeInsets.all(DesignTokens.spaceMd),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.06),
            borderRadius: DesignTokens.borderRadiusSm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.event_available,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: DesignTokens.spaceSm),
              Text(
                '下一次派发日：',
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeSm,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(width: DesignTokens.spaceXs),
              Expanded(
                child: Text(
                  nextDispatchLabel,
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeBase,
                    fontWeight: DesignTokens.fontWeightStrong,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: 调度模式
// ---------------------------------------------------------------------------

class _SchedulingSection extends StatelessWidget {
  final GoalScheduling scheduling;
  final RecurrenceRule recurrence;
  final TextEditingController minGapCtrl;
  final TextEditingController maxPerWeekCtrl;
  final TextEditingController maxPerMonthCtrl;
  final ValueChanged<SchedulingMode> onModeChange;
  final ValueChanged<List<int>> onWeekdaysChange;
  final ValueChanged<List<int>> onMonthDaysChange;
  final VoidCallback onRandomChange;
  final VoidCallback onSave;

  const _SchedulingSection({
    required this.scheduling,
    required this.recurrence,
    required this.minGapCtrl,
    required this.maxPerWeekCtrl,
    required this.maxPerMonthCtrl,
    required this.onModeChange,
    required this.onWeekdaysChange,
    required this.onMonthDaysChange,
    required this.onRandomChange,
    required this.onSave,
  });

  String _subtitle() {
    if (scheduling.mode == SchedulingMode.random) return '随机派发';
    if (recurrence.frequency == RecurrenceFrequency.weekly &&
        (scheduling.fixedWeekdays?.isNotEmpty ?? false)) {
      final days = ([...scheduling.fixedWeekdays!]..sort())
          .where((d) => d >= 0 && d < 7)
          .map((d) => '周${_weekdayNames[d]}')
          .join('/');
      return '固定 · $days';
    }
    if (recurrence.frequency == RecurrenceFrequency.monthly &&
        (scheduling.fixedMonthDays?.isNotEmpty ?? false)) {
      final days = ([...scheduling.fixedMonthDays!]..sort()).join('/');
      return '固定 · 每月 $days 号';
    }
    return '固定派发';
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '调度模式',
      icon: Icons.tune,
      subtitle: _subtitle(),
      onSave: onSave,
      children: [
        SegmentedButton<SchedulingMode>(
          segments: const [
            ButtonSegment(
              value: SchedulingMode.fixed,
              label: Text('固定'),
              icon: Icon(Icons.calendar_view_week),
            ),
            ButtonSegment(
              value: SchedulingMode.random,
              label: Text('随机'),
              icon: Icon(Icons.shuffle),
            ),
          ],
          selected: {scheduling.mode},
          onSelectionChanged: (s) => onModeChange(s.first),
        ),
        const SizedBox(height: DesignTokens.spaceMd),
        if (scheduling.mode == SchedulingMode.fixed)
          _FixedScheduling(
            scheduling: scheduling,
            recurrence: recurrence,
            onWeekdaysChange: onWeekdaysChange,
            onMonthDaysChange: onMonthDaysChange,
          )
        else
          _RandomScheduling(
            minGapCtrl: minGapCtrl,
            maxPerWeekCtrl: maxPerWeekCtrl,
            maxPerMonthCtrl: maxPerMonthCtrl,
            onChanged: onRandomChange,
          ),
      ],
    );
  }
}

class _FixedScheduling extends StatelessWidget {
  final GoalScheduling scheduling;
  final RecurrenceRule recurrence;
  final ValueChanged<List<int>> onWeekdaysChange;
  final ValueChanged<List<int>> onMonthDaysChange;

  const _FixedScheduling({
    required this.scheduling,
    required this.recurrence,
    required this.onWeekdaysChange,
    required this.onMonthDaysChange,
  });

  @override
  Widget build(BuildContext context) {
    if (recurrence.frequency == RecurrenceFrequency.weekly) {
      final selected = <int>{...?scheduling.fixedWeekdays};
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('每周派发日', style: _subtleLabel(context)),
          const SizedBox(height: DesignTokens.spaceXs),
          Wrap(
            spacing: DesignTokens.spaceXs,
            children: List.generate(7, (i) {
              final isSel = selected.contains(i);
              return FilterChip(
                label: Text('周${_weekdayNames[i]}'),
                selected: isSel,
                showCheckmark: false,
                onSelected: (_) {
                  final next = {...selected};
                  if (isSel) {
                    next.remove(i);
                  } else {
                    next.add(i);
                  }
                  onWeekdaysChange(next.toList()..sort());
                },
              );
            }),
          ),
        ],
      );
    }
    if (recurrence.frequency == RecurrenceFrequency.monthly) {
      final selected = <int>{...?scheduling.fixedMonthDays};
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('每月派发日（1~31）', style: _subtleLabel(context)),
          const SizedBox(height: DesignTokens.spaceXs),
          Wrap(
            spacing: DesignTokens.spaceXs,
            runSpacing: DesignTokens.spaceXs,
            children: List.generate(31, (i) {
              final day = i + 1;
              final isSel = selected.contains(day);
              return FilterChip(
                label: Text('$day'),
                selected: isSel,
                showCheckmark: false,
                onSelected: (_) {
                  final next = {...selected};
                  if (isSel) {
                    next.remove(day);
                  } else {
                    next.add(day);
                  }
                  onMonthDaysChange(next.toList()..sort());
                },
              );
            }),
          ),
        ],
      );
    }
    return Text(
      '当前重复规则下无需额外配置固定派发日。',
      style: TextStyle(
        fontSize: DesignTokens.fontSizeSm,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
      ),
    );
  }
}

class _RandomScheduling extends StatelessWidget {
  final TextEditingController minGapCtrl;
  final TextEditingController maxPerWeekCtrl;
  final TextEditingController maxPerMonthCtrl;
  final VoidCallback onChanged;

  const _RandomScheduling({
    required this.minGapCtrl,
    required this.maxPerWeekCtrl,
    required this.maxPerMonthCtrl,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RandomRow(
          label: '最小间隔天数',
          hint: '≥ 1',
          controller: minGapCtrl,
          onChanged: onChanged,
        ),
        const SizedBox(height: DesignTokens.spaceSm),
        _RandomRow(
          label: '每周最多派发次数',
          hint: '留空 = 不限',
          controller: maxPerWeekCtrl,
          onChanged: onChanged,
        ),
        const SizedBox(height: DesignTokens.spaceSm),
        _RandomRow(
          label: '每月最多派发次数',
          hint: '留空 = 不限',
          controller: maxPerMonthCtrl,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _RandomRow extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _RandomRow({
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 3, child: Text(label, style: _subtleLabel(context))),
        Expanded(
          flex: 2,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(hintText: hint),
            onChanged: (_) => onChanged(),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: 跳过节假日
// ---------------------------------------------------------------------------

class _SkipHolidaysSection extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChange;
  final VoidCallback onSave;

  const _SkipHolidaysSection({
    required this.enabled,
    required this.onChange,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '跳过节假日',
      icon: Icons.beach_access,
      subtitle: enabled ? '已开启' : '已关闭',
      onSave: onSave,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: enabled,
          title: const Text('遇法定节假日顺延'),
          subtitle: const Text('派发日遇节假日时自动跳到下一个工作日'),
          onChanged: onChange,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: 专注联动
// ---------------------------------------------------------------------------

class _FocusSection extends StatelessWidget {
  final FocusLink focus;
  final TextEditingController minutesCtrl;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onPickPreset;
  final ValueChanged<String> onMinutesChange;
  final ValueChanged<String> onPickNoise;
  final VoidCallback onSave;

  const _FocusSection({
    required this.focus,
    required this.minutesCtrl,
    required this.onToggle,
    required this.onPickPreset,
    required this.onMinutesChange,
    required this.onPickNoise,
    required this.onSave,
  });

  String _subtitle(BuildContext context) {
    if (!focus.enabled) return '已关闭';
    final sec = focus.focusSeconds;
    final min = (sec == null || sec <= 0) ? null : sec ~/ 60;
    final custom = context.watch<CustomFocusSoundProvider>();
    final noise = custom.isCustomSound(focus.whiteNoise)
        ? custom.labelFor(focus.whiteNoise)
        : FocusSoundCatalog.labelFor(focus.whiteNoise);
    if (min == null) return '已开启 · $noise';
    return '$min 分钟 · $noise';
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '专注联动',
      icon: Icons.timer_outlined,
      subtitle: _subtitle(context),
      onSave: onSave,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: focus.enabled,
          title: const Text('开启专注联动'),
          subtitle: const Text('派发时自动跳转番茄钟,并播放白噪音'),
          onChanged: onToggle,
        ),
        if (focus.enabled) ...[
          const SizedBox(height: DesignTokens.spaceSm),
          Text('专注时长', style: _subtleLabel(context)),
          const SizedBox(height: DesignTokens.spaceXs),
          Wrap(
            spacing: DesignTokens.spaceXs,
            children: _focusMinutePresets.map((m) {
              final selected = focus.focusSeconds == m * 60;
              return ChoiceChip(
                label: Text('$m 分钟'),
                selected: selected,
                onSelected: (_) => onPickPreset(m),
              );
            }).toList(),
          ),
          const SizedBox(height: DesignTokens.spaceSm),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('自定义分钟', style: _subtleLabel(context)),
              ),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: minutesCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(hintText: '留空 = 未设定'),
                  onChanged: onMinutesChange,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          Text('白噪音', style: _subtleLabel(context)),
          const SizedBox(height: DesignTokens.spaceXs),
          Wrap(
            spacing: DesignTokens.spaceXs,
            runSpacing: DesignTokens.spaceXs,
            children: [
              for (final opt in FocusSoundCatalog.options)
                ChoiceChip(
                  label: Text(opt.label),
                  selected: focus.whiteNoise == opt.id,
                  onSelected: (_) => onPickNoise(opt.id),
                ),
              for (final sound
                  in context.watch<CustomFocusSoundProvider>().sounds)
                ChoiceChip(
                  avatar: const Icon(Icons.audio_file_outlined, size: 16),
                  label: Text(sound.label),
                  selected: focus.whiteNoise == sound.id,
                  onSelected: (_) => onPickNoise(sound.id),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: 目标时长
// ---------------------------------------------------------------------------

class _TimeTargetSection extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onClear;
  final VoidCallback onSave;

  const _TimeTargetSection({
    required this.controller,
    required this.onClear,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final min = int.tryParse(controller.text.trim());
    final subtitle = (min == null || min <= 0) ? '未设置' : '$min 分钟 / 每次';
    return _SectionCard(
      title: '目标时长',
      icon: Icons.hourglass_bottom,
      subtitle: subtitle,
      onSave: onSave,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Text('每次时长（分钟）', style: _subtleLabel(context)),
            ),
            Expanded(
              flex: 2,
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(hintText: '0 或留空 = 清除'),
              ),
            ),
            IconButton(
              tooltip: '清除',
              icon: const Icon(Icons.clear),
              onPressed: onClear,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: 每日次数
// ---------------------------------------------------------------------------

class _DailyCountSection extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onInc;
  final VoidCallback onDec;
  final ValueChanged<String> onChanged;
  final VoidCallback onSave;

  const _DailyCountSection({
    required this.controller,
    required this.onInc,
    required this.onDec,
    required this.onChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final n = int.tryParse(controller.text.trim());
    final subtitle = (n == null || n <= 0) ? '未设置' : '每日 $n 次';
    return _SectionCard(
      title: '每日次数',
      icon: Icons.format_list_numbered,
      subtitle: subtitle,
      onSave: onSave,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: Text('每日目标次数', style: _subtleLabel(context)),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: onDec,
            ),
            SizedBox(
              width: 72,
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(hintText: '0'),
                onChanged: onChanged,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: onInc,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section: 里程碑 + 自动进度
// ---------------------------------------------------------------------------

class _MilestonesSection extends StatelessWidget {
  final List<GoalMilestone> milestones;
  final TextEditingController controller;
  final bool autoProgress;
  final double manualProgress;
  final void Function(GoalMilestone, bool) onToggle;
  final ValueChanged<int> onRemove;
  final ValueChanged<String> onAdd;
  final ValueChanged<bool> onAutoChange;
  final ValueChanged<double> onManualChange;

  const _MilestonesSection({
    required this.milestones,
    required this.controller,
    required this.autoProgress,
    required this.manualProgress,
    required this.onToggle,
    required this.onRemove,
    required this.onAdd,
    required this.onAutoChange,
    required this.onManualChange,
  });

  @override
  Widget build(BuildContext context) {
    final completed = milestones.where((m) => m.isCompleted).length;
    return _SectionCard(
      title: '里程碑与进度',
      icon: Icons.flag_circle_outlined,
      subtitle:
          '$completed/${milestones.length} · '
          '${autoProgress ? '自动' : '手动 ${(manualProgress * 100).toInt()}%'}',
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: autoProgress,
          title: const Text('按里程碑自动计算进度'),
          subtitle: Text(autoProgress ? '完成度 = 已完成里程碑 / 总里程碑' : '手动设置当前进度'),
          onChanged: onAutoChange,
        ),
        if (!autoProgress)
          Row(
            children: [
              const Text('进度:'),
              Expanded(
                child: Slider(
                  value: manualProgress,
                  onChanged: onManualChange,
                  label: '${(manualProgress * 100).toInt()}%',
                  divisions: 100,
                ),
              ),
              Text('${(manualProgress * 100).toInt()}%'),
            ],
          ),
        const SizedBox(height: DesignTokens.spaceSm),
        ...milestones.asMap().entries.map(
          (e) => Dismissible(
            key: ValueKey(e.value.id),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => onRemove(e.key),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: DesignTokens.spaceLg),
              color: DesignTokens.resultError,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            child: CheckboxListTile(
              value: e.value.isCompleted,
              onChanged: (v) => onToggle(e.value, v ?? false),
              title: Text(
                e.value.title,
                style: TextStyle(
                  decoration: e.value.isCompleted
                      ? TextDecoration.lineThrough
                      : null,
                  color: e.value.isCompleted ? Colors.grey : null,
                ),
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: '添加里程碑',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) onAdd(v.trim());
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                final v = controller.text.trim();
                if (v.isNotEmpty) onAdd(v);
              },
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final bool initiallyExpanded;
  final VoidCallback? onSave;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
    this.subtitle,
    this.initiallyExpanded = false,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: DesignTokens.spaceMd),
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        borderRadius: DesignTokens.borderRadiusLg,
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: ExpansionTile(
            minTileHeight: DesignTokens.formFieldMinHeight,
            initiallyExpanded: initiallyExpanded,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceLg,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(
              DesignTokens.spaceLg,
              DesignTokens.spaceSm,
              DesignTokens.spaceLg,
              DesignTokens.spaceLg,
            ),
            leading: Icon(
              icon,
              color: cs.primary,
              size: DesignTokens.controlIconSize,
            ),
            title: Text(title, style: appSecondaryMenuItemTextStyle(context)),
            subtitle: subtitle == null
                ? null
                : Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appSecondaryControlLabelStyle(
                      context,
                    ).copyWith(color: cs.onSurfaceVariant),
                  ),
            children: [
              AppFormFieldTheme(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final String emptyText;
  final bool compact;
  final ValueChanged<DateTime?> onPick;

  const _DateField({
    super.key,
    required this.label,
    required this.date,
    required this.emptyText,
    this.compact = false,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasDate = date != null;
    final labelText = compact ? _compactDateFieldLabel(label) : label;
    final valueText = date == null
        ? emptyText
        : _formatGoalDateFieldValue(date!);
    final leadingIconSize = compact ? (hasDate ? 14.0 : 12.0) : 18.0;
    return GestureDetector(
      onTap: () async {
        final picked = await AppDatePicker.pickSolar(
          context,
          initialDate: date ?? AppClock.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2099, 12, 31),
          title: label,
        );
        if (!context.mounted) return;
        if (picked != null) onPick(picked);
      },
      child: Container(
        constraints: const BoxConstraints(
          minHeight: DesignTokens.formFieldMinHeight,
        ),
        padding: compact
            ? const EdgeInsets.fromLTRB(6, 7, 4, 7)
            : const EdgeInsets.fromLTRB(10, 8, 8, 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.55),
            width: 0.45,
          ),
        ),
        child: Row(
          children: [
            if (compact && hasDate)
              Tooltip(
                message: '清除日期',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(null),
                  child: SizedBox.square(
                    dimension: leadingIconSize,
                    child: Icon(
                      Icons.close,
                      size: leadingIconSize,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              )
            else
              Icon(
                Icons.calendar_today_outlined,
                size: leadingIconSize,
                color: cs.primary,
              ),
            SizedBox(width: compact ? 3 : DesignTokens.spaceXs),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    labelText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appSecondaryControlLabelStyle(
                      context,
                    ).copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: DesignTokens.spaceXxs),
                  Text(
                    valueText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appSecondaryControlTextStyle(context),
                  ),
                ],
              ),
            ),
            if (date != null && !compact)
              IconButton(
                iconSize: compact ? 12 : 14,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(
                  width: compact ? 18 : 24,
                  height: compact ? 18 : 24,
                ),
                icon: const Icon(Icons.close),
                onPressed: () => onPick(null),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

TextStyle _subtleLabel(BuildContext context) =>
    appSecondaryControlLabelStyle(context);

String _formatDate(DateTime d) => I18nDateFormat.date(d);

String _formatGoalDateFieldValue(DateTime d) => '${d.year}/${d.month}/${d.day}';

String _compactDateFieldLabel(String label) {
  if (label.startsWith('开始')) return '开始';
  if (label.startsWith('目标')) return '目标';
  return label;
}

DateTime _goalEffectiveStartDay({
  required DateTime? startDate,
  required DateTime? createdAt,
  required DateTime fallback,
}) {
  final raw = startDate ?? createdAt ?? fallback;
  return DateTime(raw.year, raw.month, raw.day);
}

String _normalizeWorkspaceId(String? raw) {
  final value = raw?.trim();
  return value == null || value.isEmpty ? 'private' : value;
}

List<_WorkspaceChoice> _workspaceOptions(
  ShareProvider? shareProvider,
  String currentWorkspaceId,
) {
  final options = <_WorkspaceChoice>[
    const _WorkspaceChoice(id: 'private', name: '个人空间'),
  ];
  final known = <String>{'private'};
  for (final workspace in shareProvider?.workspaces ?? const <Workspace>[]) {
    if (workspace.isPrivate || workspace.id.isEmpty) continue;
    known.add(workspace.id);
    options.add(_WorkspaceChoice(id: workspace.id, name: workspace.name));
  }
  if (!known.contains(currentWorkspaceId) && currentWorkspaceId != 'private') {
    options.add(_WorkspaceChoice(id: currentWorkspaceId, name: '共享空间'));
  }
  return options;
}

String _workspaceLabel(List<_WorkspaceChoice> options, String workspaceId) {
  for (final option in options) {
    if (option.id == workspaceId) return option.name;
  }
  return '共享空间';
}

/// 解析正整数输入；空串或非正整数返回 null。
int? _parsePositiveInt(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final n = int.tryParse(s);
  if (n == null || n <= 0) return null;
  return n;
}

extension _NullableIntMap on int? {
  /// `1.let((x) => x * 60)` → 60；`null.let(...)` → null。
  T? let<T>(T Function(int) fn) {
    final v = this;
    if (v == null) return null;
    return fn(v);
  }
}
