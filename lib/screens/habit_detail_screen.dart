import 'package:flutter/material.dart';
import '../core/i18n.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/app_clock.dart';
import '../core/design_tokens.dart';
import '../core/habit_grouping.dart';
import '../core/habit_icons.dart';
import '../core/habit_trend.dart';
import '../models/goal.dart'
    show ReminderKind, ReminderPlan, ReminderRule, ReminderRuleType;
import '../models/habit.dart';
import '../providers/habit_provider.dart';
import '../providers/notification_service.dart';
import '../services/alarm_service.dart';
import '../widgets/habit_active_weekday_picker.dart';
import '../widgets/habit_date_range_fields.dart';
import '../widgets/habit_heatmap.dart';
import '../widgets/reminder_health_hint.dart';
import '../widgets/reminder_plan_editor.dart';
import '../widgets/surface_components.dart';

const List<int> _habitEditColors = <int>[
  0xFF4CAF50,
  0xFF2196F3,
  0xFFFF9800,
  0xFFE91E63,
  0xFF9C27B0,
  0xFF00BCD4,
  0xFFFF5722,
  0xFF607D8B,
];

ButtonStyle _habitDangerFilledButtonStyle(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(
    backgroundColor: cs.error,
    foregroundColor: cs.onError,
    textStyle: appSecondaryMenuItemTextStyle(context),
    minimumSize: const Size(0, 36),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

ButtonStyle _habitDetailActionButtonStyle(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return OutlinedButton.styleFrom(
    foregroundColor: cs.onSurface,
    side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.32)),
    textStyle: appSecondaryControlTextStyle(context),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  );
}

ButtonStyle _habitDangerOutlinedButtonStyle(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return OutlinedButton.styleFrom(
    foregroundColor: cs.error,
    side: BorderSide(color: cs.error.withValues(alpha: 0.42), width: 0.45),
    textStyle: appSecondaryControlTextStyle(context),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  );
}

Future<bool> _confirmHabitDelete(BuildContext context, Habit habit) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AppDialog(
      icon: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
      title: const Text('删除习惯？'),
      content: Text('会删除“${habit.name}”和关联记录，不可恢复。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: _habitDangerFilledButtonStyle(ctx),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<void> showHabitEditor(BuildContext context, Habit habit) async {
  final nameCtrl = TextEditingController(text: habit.name);
  final targetCtrl = TextEditingController(text: habit.targetCount.toString());
  final flexTargetCtrl = TextEditingController(
    text: (habit.flexTarget ?? habit.weeklyTarget).toString(),
  );
  final unitCtrl = TextEditingController(
    text: habit.unit ?? I18n.tr('habit.unit.times'),
  );
  final categoryCtrl = TextEditingController(text: habit.category ?? '');
  var selectedColor = habit.colorValue;
  var selectedKind = habit.kind;
  var flexRuleEnabled = habit.hasFlexRule;
  var selectedFlexPeriod = habit.flexPeriod ?? HabitFlexPeriod.week;
  DateTime? startDate = habit.startDate;
  DateTime? endDate = habit.endDate;
  // 生效星期是显式配置的唯一事实来源；旧数据缺字段时 Habit 构造
  // 已回退全 7 天，这里再兜底一次空列表，避免表单出现"零生效日"。
  var selectedActiveWeekdays = habit.activeWeekdays.isEmpty
      ? List<int>.from(const [0, 1, 2, 3, 4, 5, 6])
      : List<int>.from(habit.activeWeekdays);
  var reminderPlan = _habitReminderPlan(habit);

  await showAppModalSheet(
    context: context,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (sheetCtx, setSt) {
        var saving = false;
        Future<void> save() async {
          if (saving) return;
          setSt(() => saving = true);
          try {
            final messenger = ScaffoldMessenger.of(context);
            final navigator = Navigator.of(sheetCtx);
            final habitProvider = context.read<HabitProvider>();
            final name = nameCtrl.text.trim();
            if (name.isEmpty) {
              messenger.showSnackBar(
                SnackBar(content: Text(I18n.tr('habit.error.name_required'))),
              );
              return;
            }

            final target = int.tryParse(targetCtrl.text.trim()) ?? 1;
            if (target < 1) {
              messenger.showSnackBar(
                SnackBar(content: Text(I18n.tr('habit.error.daily_target'))),
              );
              return;
            }
            final shouldUseFlex =
                flexRuleEnabled && selectedKind == HabitKind.positive;
            final flexTarget = int.tryParse(flexTargetCtrl.text.trim()) ?? 0;
            if (shouldUseFlex && flexTarget < 1) {
              messenger.showSnackBar(
                SnackBar(content: Text(I18n.tr('habit.error.flex_target'))),
              );
              return;
            }
            if (!habitDateRangeIsValid(startDate, endDate)) {
              messenger.showSnackBar(
                SnackBar(content: Text(I18n.tr('habit.error.date_range'))),
              );
              return;
            }

            final normalizedReminderPlan = _normalizeHabitReminderPlan(
              reminderPlan,
            );
            final reminderRules = _activeHabitReminderRules(
              normalizedReminderPlan,
            );
            final reminderRule = reminderRules.isEmpty
                ? null
                : reminderRules.first;
            final hasReminder =
                normalizedReminderPlan.enabled && reminderRule != null;
            // 生效星期取表单显式选择，不再由每周提醒的 weekdays 反推；
            // 提醒日与生效日相互独立，保存后互不改动。
            final nextActiveWeekdays = List<int>.from(selectedActiveWeekdays);
            if (hasReminder) {
              final notificationService = context.read<NotificationService?>();
              final granted =
                  notificationService == null ||
                  await notificationService.ensureReadyForReminder(
                    scheduledTime: _nextHabitReminderTriggerForPlan(
                      reminderRules,
                    ),
                    issueTitle: I18n.tr('habit.error.reminder_register_failed'),
                    relatedId: habit.id,
                  );
              if (!granted) {
                final issue = notificationService.lastScheduleIssue;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      issue?.message ??
                          I18n.tr('habit.error.notification_permission'),
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
            }

            final updated = habit.copyWith(
              name: name,
              targetCount: target,
              unit: unitCtrl.text.trim().isEmpty ? null : unitCtrl.text.trim(),
              clearUnit: unitCtrl.text.trim().isEmpty,
              category: habitCategoryOrNull(categoryCtrl.text),
              clearCategory:
                  normalizeHabitCategory(categoryCtrl.text) ==
                  defaultHabitCategoryName,
              colorValue: selectedColor,
              kind: selectedKind,
              flexTarget: shouldUseFlex ? flexTarget : null,
              flexPeriod: shouldUseFlex ? selectedFlexPeriod : null,
              clearFlexRule: !shouldUseFlex,
              startDate: startDate,
              endDate: endDate,
              clearStartDate: startDate == null,
              clearEndDate: endDate == null,
              activeWeekdays: nextActiveWeekdays,
              remind: hasReminder,
              remindHour: hasReminder ? reminderRule.hour : null,
              remindMinute: hasReminder ? reminderRule.minute : null,
              reminderPlan: hasReminder
                  ? ReminderPlan(enabled: true, rules: reminderRules)
                  : const ReminderPlan.disabled(),
            );

            await habitProvider.updateHabit(habit.id, updated);
            if (!context.mounted || !sheetCtx.mounted) return;
            navigator.pop();
            messenger.showSnackBar(
              SnackBar(
                content: Text(I18n.tr('habit.saved')),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(milliseconds: 1200),
              ),
            );
          } finally {
            if (sheetCtx.mounted) {
              setSt(() => saving = false);
            }
          }
        }

        return AppModalSheet(
          title: I18n.tr('habit.edit.title'),
          subtitle: habit.name,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(sheetCtx).pop(),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              onPressed: saving ? null : save,
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(I18n.tr('action.save')),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: I18n.tr('habit.field.name'),
                  prefixIcon: const Icon(Icons.edit, size: 20),
                ),
              ),
              const SizedBox(height: DesignTokens.spaceMd),
              TextField(
                controller: categoryCtrl,
                decoration: InputDecoration(
                  labelText: I18n.tr('habit.field.group'),
                  hintText: I18n.tr('habit.field.group.empty_hint'),
                  prefixIcon: const Icon(Icons.folder_outlined, size: 20),
                ),
              ),
              const SizedBox(height: DesignTokens.spaceMd),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: targetCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: I18n.tr('habit.field.daily_target_count'),
                        prefixIcon: const Icon(Icons.track_changes, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spaceSm),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: unitCtrl,
                      decoration: InputDecoration(
                        labelText: I18n.tr('habit.field.unit'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.spaceMd),
              AppSurfaceCard(
                padding: const EdgeInsets.all(DesignTokens.spaceMd),
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tune, size: 18),
                        const SizedBox(width: DesignTokens.spaceSm),
                        Expanded(child: Text(I18n.tr('habit.flex.rule'))),
                        Switch(
                          value:
                              flexRuleEnabled &&
                              selectedKind == HabitKind.positive,
                          onChanged: selectedKind == HabitKind.positive
                              ? (value) => setSt(() => flexRuleEnabled = value)
                              : null,
                        ),
                      ],
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child:
                          flexRuleEnabled && selectedKind == HabitKind.positive
                          ? Padding(
                              key: const ValueKey('habit-flex-edit-fields'),
                              padding: const EdgeInsets.only(
                                top: DesignTokens.spaceSm,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SegmentedButton<HabitFlexPeriod>(
                                    showSelectedIcon: false,
                                    segments: [
                                      ButtonSegment(
                                        value: HabitFlexPeriod.week,
                                        label: Text(
                                          I18n.tr('habit.flex.weekly'),
                                        ),
                                      ),
                                      ButtonSegment(
                                        value: HabitFlexPeriod.month,
                                        label: Text(
                                          I18n.tr('habit.flex.monthly'),
                                        ),
                                      ),
                                    ],
                                    selected: {selectedFlexPeriod},
                                    onSelectionChanged: (value) => setSt(
                                      () => selectedFlexPeriod = value.first,
                                    ),
                                  ),
                                  const SizedBox(height: DesignTokens.spaceSm),
                                  TextField(
                                    controller: flexTargetCtrl,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    decoration: InputDecoration(
                                      labelText: I18n.tr(
                                        'habit.flex.period_target',
                                      ),
                                      hintText: I18n.tr(
                                        'habit.flex.period_target_hint',
                                      ),
                                      prefixIcon: const Icon(
                                        Icons.event_repeat,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Padding(
                              key: const ValueKey('habit-daily-edit-note'),
                              padding: const EdgeInsets.only(
                                top: DesignTokens.spaceXs,
                              ),
                              child: Text(
                                selectedKind == HabitKind.positive
                                    ? I18n.tr('habit.flex.daily_note')
                                    : I18n.tr('habit.flex.negative_note'),
                                style: TextStyle(
                                  fontSize: DesignTokens.fontSizeSm,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: DesignTokens.spaceMd),
              HabitDateRangeFields(
                startDate: startDate,
                endDate: endDate,
                onStartChanged: (value) => setSt(() => startDate = value),
                onEndChanged: (value) => setSt(() => endDate = value),
              ),
              const SizedBox(height: DesignTokens.spaceMd),
              HabitActiveWeekdayPicker(
                weekdays: selectedActiveWeekdays,
                onChanged: (value) =>
                    setSt(() => selectedActiveWeekdays = value),
                warning: _habitPlanHasWeeklyReminder(reminderPlan)
                    ? I18n.tr('habit.active_weekdays.reminder_hint')
                    : null,
              ),
              const SizedBox(height: DesignTokens.spaceMd),
              Text(
                I18n.tr('habit.kind'),
                style: const TextStyle(
                  fontSize: DesignTokens.fontSizeSm,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              ),
              const SizedBox(height: DesignTokens.spaceXs),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: Text(I18n.tr('habit.kind.positive')),
                      selected: selectedKind == HabitKind.positive,
                      onSelected: (_) => setSt(() {
                        selectedKind = HabitKind.positive;
                      }),
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spaceSm),
                  Expanded(
                    child: ChoiceChip(
                      label: Text(I18n.tr('habit.kind.negative')),
                      selected: selectedKind == HabitKind.negative,
                      onSelected: (_) => setSt(() {
                        selectedKind = HabitKind.negative;
                        flexRuleEnabled = false;
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DesignTokens.spaceMd),
              Text(
                I18n.tr('habit.color'),
                style: const TextStyle(
                  fontSize: DesignTokens.fontSizeSm,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              ),
              const SizedBox(height: DesignTokens.spaceXs),
              Wrap(
                spacing: DesignTokens.spaceSm,
                runSpacing: DesignTokens.spaceSm,
                children: [
                  for (final c in _habitEditColors)
                    GestureDetector(
                      onTap: () => setSt(() => selectedColor = c),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: selectedColor == c
                              ? Border.all(color: Colors.white, width: 1.2)
                              : null,
                          boxShadow: selectedColor == c
                              ? [
                                  BoxShadow(
                                    color: Color(c).withValues(alpha: 0.35),
                                    blurRadius: 6,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: DesignTokens.spaceMd),
              ReminderPlanEditor(
                plan: reminderPlan,
                title: I18n.tr('habit.reminder'),
                allowAlarm: true,
                allowRelativeToDue: false,
                allowWeekly: true,
                allowSnooze: false,
                hasAnchorDate: false,
                maxRules: 12,
                defaultKind: ReminderKind.popup,
                showTypeSelector: false,
                showKindSelector: false,
                onChanged: (plan) => setSt(
                  () => reminderPlan = _normalizeHabitReminderPlan(plan),
                ),
              ),
              const SizedBox(height: DesignTokens.spaceSm),
              Builder(
                builder: (context) {
                  final notif = context.watch<NotificationService?>();
                  if (notif == null) return const SizedBox.shrink();
                  final reminderKind =
                      _habitPrimaryReminder(reminderPlan)?.kind ??
                      ReminderKind.push;
                  return ReminderHealthHint(
                    reminderKind: reminderKind,
                    onOpenSystemSettings: () => _openSystemSettings(context),
                    onRequestNotificationPermission: () async {
                      await context
                          .read<NotificationService>()
                          .requestPermission();
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
        );
      },
    ),
  );
}

class HabitDetailScreen extends StatefulWidget {
  final String habitId;

  const HabitDetailScreen({super.key, required this.habitId});

  @override
  State<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends State<HabitDetailScreen> {
  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final provider = context.watch<HabitProvider>();
    final matches = provider.habits.where((h) => h.id == widget.habitId);
    if (matches.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(I18n.tr('habit.detail.title')),
          titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(DesignTokens.space3xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: DesignTokens.spaceMd),
                Text(
                  I18n.tr('habit.detail.not_found'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: DesignTokens.spaceLg),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                  label: Text(I18n.tr('action.back')),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final habit = matches.first;
    final heatmapData = habit.heatmapData(20);
    final cs = Theme.of(context).colorScheme;
    final color = Color(habit.colorValue);
    final flexProgress = habit.flexProgressForDate(AppClock.now());
    final streakUnit = _localizedHabitStreakUnit(habit);
    final todayLabel = habit.kind == HabitKind.negative
        ? _habitCountLabel(habit.todayCount(), habitUnit(habit))
        : habit.hasFlexRule
        ? (_localizedFlexProgressLabel(flexProgress) ??
              '${habit.todayCount()}/${habit.targetCount}')
        : '${habit.todayCount()}/${habit.targetCount}';

    return Scaffold(
      appBar: AppBar(
        title: Text(habit.name),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (value) async {
              final provider = context.read<HabitProvider>();
              if (value == 'end') {
                await provider.endHabit(habit.id);
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('习惯已结束，历史记录已保留')));
              } else if (value == 'delete') {
                final ok = await _confirmHabitDelete(context, habit);
                if (!ok) return;
                await provider.deleteHabit(habit.id);
                if (!context.mounted) return;
                Navigator.pop(context);
              }
            },
            itemBuilder: (context) {
              final cs = Theme.of(context).colorScheme;
              return [
                const PopupMenuItem(
                  value: 'end',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.event_busy_outlined),
                    title: Text('结束习惯'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.delete_outline, color: cs.error),
                    title: Text('删除习惯', style: TextStyle(color: cs.error)),
                  ),
                ),
              ];
            },
          ),
          IconButton(
            tooltip: I18n.tr('action.edit'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showHabitEditor(context, habit),
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: AppSurfaceCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      habitDisplayIconFor(habit),
                      color: color,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    habit.name,
                    style: appSecondaryRouteTitleTextStyle(context),
                  ),
                  if (habit.hasFlexRule) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${localizedFlexPeriodGoalLabel(habit)} · ${I18n.tr('habit.daily_prefix')} ${habit.targetCount} ${habitUnit(habit)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                  if (habit.startDate != null || habit.endDate != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      habitDateRangeLabel(habit.startDate, habit.endDate),
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _StatChip(
                        label: I18n.tr('habit.stat.current_streak'),
                        value: _habitCountWithUnit(
                          habit.currentStreak,
                          streakUnit,
                        ),
                      ),
                      _StatChip(
                        label: I18n.tr('habit.stat.best_streak'),
                        value: _habitCountWithUnit(
                          habit.bestStreak,
                          streakUnit,
                        ),
                      ),
                      _StatChip(
                        label: I18n.tr('habit.stat.today'),
                        value: todayLabel,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        style: _habitDetailActionButtonStyle(context),
                        onPressed: () async {
                          final provider = context.read<HabitProvider>();
                          await provider.endHabit(habit.id);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('习惯已结束，历史记录已保留')),
                          );
                        },
                        icon: const Icon(Icons.event_busy_outlined, size: 16),
                        label: const Text('结束习惯'),
                      ),
                      OutlinedButton.icon(
                        style: _habitDangerOutlinedButtonStyle(context),
                        onPressed: () async {
                          final ok = await _confirmHabitDelete(context, habit);
                          if (!ok || !context.mounted) return;
                          await context.read<HabitProvider>().deleteHabit(
                            habit.id,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('删除'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              I18n.tr('habit.heatmap.title'),
              style: TextStyle(
                fontWeight: DesignTokens.fontWeightStrong,
                fontSize: 15,
                color: cs.onSurface,
              ),
            ),
          ),
          HabitHeatmap(heatmapData: heatmapData, weeks: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _HabitTrendCard(habit: habit),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              I18n.tr('habit.records.title'),
              style: TextStyle(
                fontWeight: DesignTokens.fontWeightStrong,
                fontSize: 15,
                color: cs.onSurface,
              ),
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 30,
            itemBuilder: (_, i) {
              final d = AppClock.today().subtract(Duration(days: i));
              final activeForDay = habit.activeForDate(d);
              final count = habit.countForDate(d);
              final progress = habit.progressForDate(d);
              final completed = habit.isCompletedForDate(d);
              final unit = habitUnit(habit);
              final countLabel = !activeForDay
                  ? I18n.tr('habit.records.inactive')
                  : habit.kind == HabitKind.negative
                  ? _habitCountLabel(count, unit)
                  : habit.hasFlexRule
                  ? localizedHabitCountForDate(habit, d)
                  : '$count/${habit.targetCount}';
              return ListTile(
                dense: true,
                leading: Text(
                  '${d.month}/${d.day}',
                  style: const TextStyle(fontSize: 13),
                ),
                title: LinearProgressIndicator(
                  value: progress,
                  color: activeForDay
                      ? (completed ? Colors.green : cs.error)
                      : cs.onSurfaceVariant,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      countLabel,
                      style: TextStyle(
                        fontSize: 12,
                        color: !activeForDay
                            ? cs.onSurfaceVariant
                            : completed
                            ? Colors.green
                            : Colors.grey,
                      ),
                    ),
                    if (count > 0 && activeForDay)
                      Tooltip(
                        message: I18n.tr('habit.records.undo_once'),
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          onPressed: () =>
                              provider.decrementHabitForDate(habit.id, d),
                          icon: const Icon(Icons.undo),
                        ),
                      ),
                    Tooltip(
                      message: !activeForDay
                          ? I18n.tr('habit.records.inactive')
                          : habit.kind == HabitKind.negative
                          ? I18n.tr('habit.records.record_once')
                          : I18n.tr('habit.records.make_up_once'),
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        onPressed: activeForDay
                            ? () => provider.incrementHabitForDate(habit.id, d)
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ),
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

class _HabitTrendCard extends StatefulWidget {
  final Habit habit;

  const _HabitTrendCard({required this.habit});

  @override
  State<_HabitTrendCard> createState() => _HabitTrendCardState();
}

class _HabitTrendCardState extends State<_HabitTrendCard> {
  HabitTrendWindow _window = HabitTrendWindow.days30;

  @override
  Widget build(BuildContext context) {
    final summary = buildHabitTrendSummary(widget.habit, window: _window);
    final cs = Theme.of(context).colorScheme;
    final color = Color(widget.habit.colorValue);
    final unit = habitUnit(widget.habit);
    final trendColor = _directionColor(summary.direction, cs);
    final delta = (summary.completionRateDelta * 100).round();

    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  I18n.tr('habit.trend.title'),
                  style: const TextStyle(
                    fontWeight: DesignTokens.fontWeightStrong,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                '${(summary.completionRate * 100).round()}%',
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<HabitTrendWindow>(
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: WidgetStateProperty.all(
                const TextStyle(
                  fontSize: 12,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              ),
            ),
            segments: [
              for (final window in HabitTrendWindow.values)
                ButtonSegment(
                  value: window,
                  label: Text(localizedHabitTrendWindowLabel(window)),
                ),
            ],
            selected: {_window},
            onSelectionChanged: (value) {
              setState(() => _window = value.first);
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HabitTrendMetric(
                label: I18n.tr('habit.trend.completed'),
                value: '${summary.completedDays}/${summary.activeDays}',
              ),
              _HabitTrendMetric(
                label: I18n.tr('habit.trend.daily_average'),
                value: '${summary.averageCount.toStringAsFixed(1)} $unit',
              ),
              _HabitTrendMetric(
                label: I18n.tr('habit.trend.longest_streak'),
                value:
                    '${summary.longestCompletedStreak} ${I18n.tr('unit.day')}',
              ),
              _HabitTrendMetric(
                label: I18n.tr('habit.trend.vs_previous'),
                value: delta == 0
                    ? I18n.tr('today.productivity.flat')
                    : '${delta > 0 ? '+' : ''}$delta%',
                color: trendColor,
                icon: _directionIcon(summary.direction),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            I18n.tr('habit.trend.bucket_details'),
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 8),
          for (final bucket in summary.buckets)
            _HabitTrendBucketRow(
              bucket: bucket,
              color: color,
              errorColor: cs.error,
              unit: unit,
            ),
        ],
      ),
    );
  }
}

class _HabitTrendMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final IconData? icon;

  const _HabitTrendMetric({
    required this.label,
    required this.value,
    this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = color ?? cs.onSurface;
    return Container(
      constraints: const BoxConstraints(minWidth: 88),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: effectiveColor),
                const SizedBox(width: 3),
              ],
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  color: effectiveColor,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HabitTrendBucketRow extends StatelessWidget {
  final HabitTrendBucket bucket;
  final Color color;
  final Color errorColor;
  final String unit;

  const _HabitTrendBucketRow({
    required this.bucket,
    required this.color,
    required this.errorColor,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rate = bucket.completionRate;
    final rowColor = rate >= 0.5 ? color : errorColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 330;
          final labelWidth = compact ? 58.0 : 76.0;
          final valueWidth = compact ? 86.0 : 100.0;
          return Row(
            children: [
              SizedBox(
                width: labelWidth,
                child: Text(
                  bucket.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          Container(
                            height: 8,
                            color: color.withValues(alpha: 0.10),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            height: 8,
                            width: constraints.maxWidth * rate,
                            color: rowColor,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: valueWidth,
                child: Text(
                  '${bucket.completedDays}/${bucket.activeDays} · ${bucket.totalCount} $unit',
                  maxLines: 1,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: bucket.completedDays > 0
                        ? rowColor
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Color _directionColor(HabitTrendDirection direction, ColorScheme cs) {
  return switch (direction) {
    HabitTrendDirection.up => const Color(0xFF4CAF50),
    HabitTrendDirection.down => cs.error,
    HabitTrendDirection.flat => cs.onSurfaceVariant,
  };
}

IconData _directionIcon(HabitTrendDirection direction) {
  return switch (direction) {
    HabitTrendDirection.up => Icons.trending_up,
    HabitTrendDirection.down => Icons.trending_down,
    HabitTrendDirection.flat => Icons.trending_flat,
  };
}

Future<void> _openSystemSettings(BuildContext context) async {
  final opened = await openAppSettings();
  if (!context.mounted) return;
  if (!opened) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(I18n.tr('preferences.notify.open_settings_failed')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

String habitUnit(Habit habit) {
  final unit = habit.unit?.trim();
  return unit == null || unit.isEmpty ? I18n.tr('habit.unit.times') : unit;
}

String localizedFlexPeriodGoalLabel(Habit habit) {
  if (!habit.hasFlexRule) return '';
  return switch (habit.flexPeriod!) {
    HabitFlexPeriod.week =>
      '${I18n.tr('habit.flex.weekly_goal_prefix')}${habit.effectiveFlexTarget} ${I18n.tr('habit.unit.times')}/${I18n.tr('habit.unit.week')}',
    HabitFlexPeriod.month =>
      '${I18n.tr('habit.flex.monthly_goal_prefix')}${habit.effectiveFlexTarget} ${I18n.tr('habit.unit.times')}/${I18n.tr('habit.unit.month')}',
  };
}

String? _localizedFlexProgressLabel(HabitFlexProgress? progress) {
  if (progress == null) return null;
  final prefix = switch (progress.period) {
    HabitFlexPeriod.week => I18n.tr('habit.flex.this_week'),
    HabitFlexPeriod.month => I18n.tr('habit.flex.this_month'),
  };
  return '$prefix ${progress.completed}/${progress.target}';
}

String localizedHabitCountForDate(Habit habit, DateTime date) {
  final count = habit.countForDate(date);
  final unit = habitUnit(habit);
  if (habit.hasFlexRule) {
    final progress = _localizedFlexProgressLabel(
      habit.flexProgressForDate(date),
    );
    return progress == null
        ? _habitCountLabel(count, unit)
        : '${_habitCountLabel(count, unit)} · $progress';
  }
  return habit.kind == HabitKind.positive
      ? '$count $unit / ${habit.targetCount} $unit'
      : _habitCountLabel(count, unit);
}

String localizedHabitTrendWindowLabel(HabitTrendWindow window) {
  return switch (window) {
    HabitTrendWindow.days14 => _habitCountWithUnit('14', I18n.tr('unit.day')),
    HabitTrendWindow.days30 => _habitCountWithUnit('30', I18n.tr('unit.day')),
    HabitTrendWindow.days90 => _habitCountWithUnit('90', I18n.tr('unit.day')),
    HabitTrendWindow.days365 => I18n.tr('habit.trend.one_year'),
  };
}

/// 数字与单位拼接：zh 习惯紧拼（「5天」「14天」），en 单位是独立单词需要
/// 空格（「5 days」「14 days」）。共享 unit 词条（unit.day 等）同时服务
/// 已带空格的拼接点（如 '${count} ${unit}'），不能在值里内置前导空格，
/// 因此空格在此处按语言补齐。
String _habitCountWithUnit(Object count, String unit) {
  if (unit.isEmpty) return '$count';
  final spaced = I18n.current == AppLocale.en && !unit.startsWith(' ');
  return spaced ? '$count $unit' : '$count$unit';
}

String _localizedHabitStreakUnit(Habit habit) {
  if (!habit.hasFlexRule) return I18n.tr('unit.day');
  return switch (habit.flexPeriod!) {
    HabitFlexPeriod.week => I18n.tr('habit.unit.week'),
    HabitFlexPeriod.month => I18n.tr('habit.unit.month'),
  };
}

String _habitCountLabel(int count, String unit) {
  return '${I18n.tr('habit.recorded_prefix')}$count $unit';
}

ReminderPlan _habitReminderPlan(Habit habit) {
  if (habit.reminderPlan.enabled && habit.reminderPlan.rules.isNotEmpty) {
    return _normalizeHabitReminderPlan(habit.reminderPlan);
  }
  if (!habit.remind || habit.remindHour == null || habit.remindMinute == null) {
    return const ReminderPlan.disabled();
  }
  final weekdays =
      habit.activeWeekdays
          .where((d) => d >= 0 && d <= 6)
          .map((d) => d + 1)
          .toList()
        ..sort();
  final fullWeek = weekdays.length == 7;
  return ReminderPlan(
    enabled: true,
    rules: [
      ReminderRule(
        id: 'habit-reminder',
        enabled: true,
        type: fullWeek
            ? ReminderRuleType.dailyTime
            : ReminderRuleType.weeklyTime,
        kind: ReminderKind.popup,
        hour: habit.remindHour,
        minute: habit.remindMinute,
        weekdays: fullWeek ? const <int>[] : weekdays,
      ),
    ],
  );
}

/// 编辑表单当前是否配置了"每周某几天"的提醒，用于提示生效星期独立。
bool _habitPlanHasWeeklyReminder(ReminderPlan plan) {
  return plan.rules.any(
    (rule) => rule.enabled && rule.type == ReminderRuleType.weeklyTime,
  );
}

ReminderPlan _normalizeHabitReminderPlan(ReminderPlan plan) {
  final rules = plan.rules.map(_normalizeHabitReminderRule).toList();
  return ReminderPlan(enabled: plan.enabled, rules: rules);
}

ReminderRule _normalizeHabitReminderRule(ReminderRule rule) {
  var type = rule.type;
  var weekdays = rule.weekdays;
  if (type == ReminderRuleType.absolute ||
      type == ReminderRuleType.relativeToDue) {
    type = ReminderRuleType.dailyTime;
    weekdays = const <int>[];
  } else if (type == ReminderRuleType.weeklyTime) {
    weekdays =
        rule.weekdays.where((day) => day >= 1 && day <= 7).toSet().toList()
          ..sort();
    if (weekdays.isEmpty) type = ReminderRuleType.dailyTime;
  } else {
    weekdays = const <int>[];
  }

  return rule.copyWith(
    type: type,
    kind: ReminderKind.popup,
    weekdays: weekdays,
    fullScreen: false,
    snoozeMinutes: 0,
    repeatCount: 0,
  );
}

List<ReminderRule> _activeHabitReminderRules(ReminderPlan plan) {
  if (!plan.enabled) return const <ReminderRule>[];
  final rules = <ReminderRule>[];
  for (final rule in plan.rules) {
    if (!rule.enabled || rule.kind == ReminderKind.off) continue;
    if (rule.hour == null || rule.minute == null) continue;
    rules.add(_normalizeHabitReminderRule(rule));
  }
  return rules;
}

ReminderRule? _habitPrimaryReminder(ReminderPlan plan) {
  final activeRules = _activeHabitReminderRules(plan);
  if (activeRules.isNotEmpty) return activeRules.first;
  return plan.rules.isEmpty
      ? null
      : _normalizeHabitReminderRule(plan.rules.first);
}

DateTime? _nextHabitReminderTriggerForPlan(List<ReminderRule> rules) {
  DateTime? next;
  for (final rule in rules) {
    final trigger = _nextHabitReminderTrigger(rule);
    if (trigger == null) continue;
    if (next == null || trigger.isBefore(next)) next = trigger;
  }
  return next;
}

DateTime? _nextHabitReminderTrigger(ReminderRule rule) {
  final hour = rule.hour;
  final minute = rule.minute;
  if (hour == null || minute == null) return null;
  final now = AppClock.now();
  final weekdays = rule.type == ReminderRuleType.weeklyTime
      ? rule.weekdays.where((day) => day >= 1 && day <= 7).toSet()
      : const <int>{};
  for (var offset = 0; offset <= 7; offset++) {
    final date = AppClock.today().add(Duration(days: offset));
    final target = AppClock.date(date.year, date.month, date.day, hour, minute);
    if (!target.isAfter(now)) continue;
    if (weekdays.isNotEmpty && !weekdays.contains(target.weekday)) continue;
    return target;
  }
  return null;
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: DesignTokens.fontWeightStrong,
              fontSize: 16,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
