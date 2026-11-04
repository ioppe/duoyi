import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/i18n.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/app_clock.dart';
import '../core/app_motion.dart';
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

/// 详情页主滚动列表的稳定 key：趋势卡片被回收重建后列表身份不变。
const Key habitDetailListKey = ValueKey<String>('habit_detail_list');

/// 趋势卡片 key：范围选择器随卡片滚动进出，状态由详情页持有。
const Key habitTrendCardKey = ValueKey<String>('habit_trend_card');

/// 趋势范围选择器 key。
const Key habitTrendWindowSelectorKey = ValueKey<String>(
  'habit_trend_window_selector',
);

/// 补卡日历卡片 key（沿用原「最近记录 / 补卡」卡片的稳定 key）。
const Key habitRecentRecordsCardKey = ValueKey<String>(
  'habit_recent_records_card',
);

/// 补卡日历展开/收起入口 key。
const Key habitCalendarToggleKey = ValueKey<String>('habit_calendar_toggle');

/// 补卡日历上/下个月按钮 key。
const Key habitCalendarPrevMonthKey = ValueKey<String>(
  'habit_calendar_prev_month',
);
const Key habitCalendarNextMonthKey = ValueKey<String>(
  'habit_calendar_next_month',
);

/// 当日详情浮层、关闭按钮与两个写入按钮 key。
const Key habitDayDetailsCardKey = ValueKey<String>('habit_day_details_card');
const Key habitDayDetailsCloseKey = ValueKey<String>('habit_day_details_close');
const Key habitDayDetailsPrimaryKey = ValueKey<String>(
  'habit_day_details_primary',
);
const Key habitDayDetailsUndoKey = ValueKey<String>('habit_day_details_undo');

/// 日期格 key 前缀：趋势格 `habit_trend_day_yyyy-MM-dd`、
/// 日历格 `habit_calendar_day_yyyy-MM-dd`。
const String habitTrendDayKeyPrefix = 'habit_trend_day_';
const String habitCalendarDayKeyPrefix = 'habit_calendar_day_';

/// 补卡日历日格的行高倍数与状态点直径。
const double _habitCalendarLineHeight = 1.25;
const double _habitCalendarDotSize = 5;

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
                      duration: AppMotion.feedback(sheetCtx),
                      switchInCurve: AppMotion.enterCurve,
                      switchOutCurve: AppMotion.exitCurve,
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
                        duration: AppMotion.feedback(sheetCtx),
                        curve: AppMotion.enterCurve,
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
  /// 趋势范围是详情页状态：趋势卡片滚出缓存被销毁后不能回退到默认值。
  HabitTrendWindow _trendWindow = HabitTrendWindow.days14;

  /// 补卡日历同样默认收起，展开状态与所在月份都由详情页持有：
  /// 卡片滚出缓存重建、provider 更新都不会把用户折叠回默认视图。
  bool _calendarExpanded = false;
  DateTime _calendarMonth = _currentHabitCalendarMonth();

  static DateTime _currentHabitCalendarMonth() {
    final today = AppClock.today();
    return DateTime(today.year, today.month);
  }

  @override
  void didUpdateWidget(covariant HabitDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只有真正切到另一个习惯才回到默认 14 天与收起的当月日历；provider
    // 更新（打卡、编辑保存、提醒同步）都不会重置用户选中的范围。
    if (oldWidget.habitId != widget.habitId) {
      _trendWindow = HabitTrendWindow.days14;
      _calendarExpanded = false;
      _calendarMonth = _currentHabitCalendarMonth();
    }
  }

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
        key: habitDetailListKey,
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, DesignTokens.spaceMd),
            child: _HabitTrendCard(
              key: habitTrendCardKey,
              habit: habit,
              window: _trendWindow,
              onWindowChanged: (window) =>
                  setState(() => _trendWindow = window),
            ),
          ),
          Padding(
            // 左右各 12：给 7 列月历留出 320dp 屏也够用的网格宽度。
            padding: const EdgeInsets.fromLTRB(12, 0, 12, DesignTokens.spaceLg),
            child: _HabitBackfillCalendarCard(
              key: habitRecentRecordsCardKey,
              habit: habit,
              expanded: _calendarExpanded,
              month: _calendarMonth,
              onExpandedChanged: (expanded) =>
                  setState(() => _calendarExpanded = expanded),
              onMonthChanged: (month) => setState(() => _calendarMonth = month),
            ),
          ),
        ],
      ),
    );
  }
}

class _HabitTrendCard extends StatelessWidget {
  final Habit habit;
  final HabitTrendWindow window;
  final ValueChanged<HabitTrendWindow> onWindowChanged;

  const _HabitTrendCard({
    super.key,
    required this.habit,
    required this.window,
    required this.onWindowChanged,
  });

  @override
  Widget build(BuildContext context) {
    final summary = buildHabitTrendSummary(habit, window: window);
    final cs = Theme.of(context).colorScheme;
    final color = Color(habit.colorValue);
    final unit = habitUnit(habit);
    final trendColor = _directionColor(summary.direction, cs);
    final delta = (summary.completionRateDelta * 100).round();

    return AppSurfaceCard(
      // 不传 color/gradient：保留用户选择的 cardSkin / 明暗玻璃皮肤。
      padding: const EdgeInsets.all(DesignTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up, size: 18, color: color),
              const SizedBox(width: DesignTokens.spaceSm),
              Expanded(
                child: Text(
                  I18n.tr('habit.trend.title'),
                  style: const TextStyle(
                    fontWeight: DesignTokens.fontWeightStrong,
                    fontSize: DesignTokens.fontSizeSecondary,
                  ),
                ),
              ),
              Text(
                '${(summary.completionRate * 100).round()}%',
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeSecondary,
                  color: color,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          // 2x 字体 / 320px 下四段放不进一行时横向滚动，不压缩字号也不溢出。
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<HabitTrendWindow>(
              key: habitTrendWindowSelectorKey,
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: WidgetStateProperty.all(
                  const TextStyle(
                    fontSize: DesignTokens.fontSizeCaption,
                    fontWeight: DesignTokens.fontWeightMedium,
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
              selected: {window},
              onSelectionChanged: (value) => onWindowChanged(value.first),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          _HabitTrendMetrics(
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
          const SizedBox(height: DesignTokens.spaceMd),
          Text(
            I18n.tr('habit.trend.bucket_details'),
            style: TextStyle(
              fontSize: DesignTokens.fontSizeCaption,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: DesignTokens.spaceSm),
          _HabitTrendBreakdown(summary: summary, habit: habit, unit: unit),
        ],
      ),
    );
  }
}

/// 区间明细：14 天每日明细、30 天日期格、90/365 天周/月聚合。
///
/// 展示层统一倒序（最近日期在最前），不改 core 聚合的早到晚顺序。
class _HabitTrendBreakdown extends StatelessWidget {
  final HabitTrendSummary summary;
  final Habit habit;
  final String unit;

  const _HabitTrendBreakdown({
    required this.summary,
    required this.habit,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(habit.colorValue);
    final points = summary.points.reversed.toList(growable: false);
    switch (summary.window) {
      case HabitTrendWindow.days14:
        return Column(
          children: [
            for (final point in points)
              _HabitTrendDayRow(habit: habit, point: point, color: color),
          ],
        );
      case HabitTrendWindow.days30:
        return _HabitTrendDayGrid(habit: habit, points: points);
      case HabitTrendWindow.days90:
      case HabitTrendWindow.days365:
        return Column(
          children: [
            for (final bucket in summary.buckets.reversed)
              _HabitTrendBucketRow(bucket: bucket, color: color, unit: unit),
          ],
        );
    }
  }
}

/// 指标区：手机 2×2、宽屏 4 列，用留白而不是四层嵌套描边卡片区分。
class _HabitTrendMetrics extends StatelessWidget {
  final List<Widget> children;

  const _HabitTrendMetrics({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 480.0;
        final columns = width >= 520 ? 4 : 2;
        const gap = DesignTokens.spaceSm;
        final itemWidth = (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

/// 单个指标：12 号标签 + 16 号数值，文字自然换行，不加独立描边。
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
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceSm,
        vertical: DesignTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: DesignTokens.fontSizeCaption,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: DesignTokens.spaceXxs + 1),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: effectiveColor),
                const SizedBox(width: DesignTokens.spaceXxs + 1),
              ],
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeBase,
                    color: effectiveColor,
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 14 天视图的一天：主题色日期徽标 + 细进度 + 已有本地化数值。
class _HabitTrendDayRow extends StatelessWidget {
  final Habit habit;
  final HabitTrendPoint point;
  final Color color;

  const _HabitTrendDayRow({
    required this.habit,
    required this.point,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = point.active;
    final progress = active ? point.progress.clamp(0.0, 1.0) : 0.0;
    final accent = !active
        ? cs.onSurfaceVariant
        : point.completed
        ? color
        : cs.primary;
    final label = active
        ? localizedHabitCountForDate(habit, point.date)
        : I18n.tr('habit.records.inactive');

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.spaceSm),
      child: Row(
        children: [
          _HabitDateBadge(date: point.date, color: color, muted: !active),
          const SizedBox(width: DesignTokens.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeCaption,
                    color: active ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceXxs + 2),
                _HabitTrendProgressBar(
                  progress: progress,
                  color: accent,
                  trackColor: (active ? color : cs.outlineVariant).withValues(
                    alpha: 0.16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DesignTokens.spaceSm),
          Text(
            '${(progress * 100).round()}%',
            style: TextStyle(
              fontSize: DesignTokens.fontSizeCaption,
              fontWeight: DesignTokens.fontWeightMedium,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// 30 天视图：响应式日期格，宽度随文字缩放增长，最少 44 触控格。
/// 30 天日期格的两行文本行高：日期一行 + 数量一行，全部格子共用。
const double _habitTrendCellLineHeight = 1.25;

Size _measureTrendDayText(
  BuildContext context,
  String text,
  FontWeight weight,
) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.copyWith(
        fontSize: DesignTokens.fontSizeCaption,
        height: _habitTrendCellLineHeight,
        fontWeight: weight,
      ),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final size = painter.size;
  painter.dispose();
  return size;
}

/// 30 天视图：30 个等宽等高的日期格，最近日期在最前（points 已倒序）。
class _HabitTrendDayGrid extends StatelessWidget {
  final Habit habit;
  final List<HabitTrendPoint> points;

  const _HabitTrendDayGrid({required this.habit, required this.points});

  @override
  Widget build(BuildContext context) {
    final today = AppClock.today();
    const gap = DesignTokens.spaceXs + 2;
    var minCellWidth = DesignTokens.controlMinHeight;
    var cellHeight = DesignTokens.controlMinHeight;
    for (final point in points) {
      final date = _measureTrendDayText(
        context,
        '${point.date.month}/${point.date.day}',
        DesignTokens.fontWeightMedium,
      );
      final count = _measureTrendDayText(
        context,
        point.active ? '${point.count}' : '–',
        DesignTokens.fontWeightStrong,
      );
      minCellWidth = math.max(
        minCellWidth,
        math.max(date.width, count.width) + DesignTokens.spaceXs * 2 + 2,
      );
      cellHeight = math.max(
        cellHeight,
        date.height +
            count.height +
            DesignTokens.spaceXxs +
            DesignTokens.spaceXs * 2 +
            1,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : minCellWidth * 7;
        final columns = ((maxWidth + gap) / (minCellWidth + gap))
            .floor()
            .clamp(1, 10)
            .toInt();
        final cellWidth = (maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final point in points)
              _HabitTrendDayCell(
                key: ValueKey<String>(
                  '$habitTrendDayKeyPrefix${habit.dateKey(point.date)}',
                ),
                habit: habit,
                point: point,
                width: cellWidth,
                height: cellHeight,
                isToday:
                    point.date.year == today.year &&
                    point.date.month == today.month &&
                    point.date.day == today.day,
              ),
          ],
        );
      },
    );
  }
}

/// 单个日期格：上「M/d」下「count 或 –」，两行都是同字号 [Text]。
class _HabitTrendDayCell extends StatelessWidget {
  final Habit habit;
  final HabitTrendPoint point;
  final bool isToday;
  final double width;
  final double height;

  const _HabitTrendDayCell({
    super.key,
    required this.habit,
    required this.point,
    required this.isToday,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = point.active;
    final completed = point.completed;
    final recordedOccurrence =
        active && habit.kind == HabitKind.negative && point.count > 0;
    final accent = !active
        ? cs.onSurfaceVariant
        : recordedOccurrence
        ? cs.error
        : completed
        ? _habitCompletedColor(context)
        : cs.onSurfaceVariant;
    final description = _habitTrendPointDescription(habit, point);
    // 趋势区只读：写入入口在下方补卡日历里。
    void openDetails() => _showHabitDayDetails(
      context,
      habitId: habit.id,
      date: point.date,
      allowRecordActions: false,
    );

    return SizedBox(
      width: width,
      height: height,
      child: Semantics(
        container: true,
        label: description,
        button: true,
        excludeSemantics: true,
        onTap: openDetails,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              color:
                  (completed || recordedOccurrence
                          ? accent
                          : DesignTokens.habitPendingTint)
                      .withValues(alpha: active ? 0.15 : 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isToday
                    ? cs.primary.withValues(alpha: 0.72)
                    : cs.outlineVariant.withValues(alpha: 0.24),
                width: isToday ? 1 : 0.5,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: openDetails,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spaceXs,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${point.date.month}/${point.date.day}',
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeCaption,
                        height: _habitTrendCellLineHeight,
                        fontWeight: DesignTokens.fontWeightMedium,
                        color: active ? cs.onSurface : cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spaceXxs),
                    Text(
                      active ? '${point.count}' : '–',
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeCaption,
                        height: _habitTrendCellLineHeight,
                        fontWeight: DesignTokens.fontWeightStrong,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 90 天 / 一年：周、月聚合，主题色日期徽章 + 淡底容器 + 进度。
class _HabitTrendBucketRow extends StatelessWidget {
  final HabitTrendBucket bucket;
  final Color color;
  final String unit;

  const _HabitTrendBucketRow({
    required this.bucket,
    required this.color,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rate = bucket.completionRate;
    final hasActiveDays = bucket.activeDays > 0;
    final accent = !hasActiveDays
        ? cs.onSurfaceVariant
        : rate >= 0.5
        ? color
        : cs.primary;
    final stats =
        '${bucket.completedDays}/${bucket.activeDays} · ${bucket.totalCount} $unit';

    return Semantics(
      label: '${bucket.label} · $stats',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: DesignTokens.spaceSm),
        padding: const EdgeInsets.all(DesignTokens.spaceSm + 2),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: DesignTokens.spaceSm,
              runSpacing: DesignTokens.spaceXs,
              children: [
                _HabitTrendRangeBadge(label: bucket.label, color: accent),
                Text(
                  stats,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeCaption,
                    color: hasActiveDays ? accent : cs.onSurfaceVariant,
                    fontWeight: DesignTokens.fontWeightMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.spaceSm),
            _HabitTrendProgressBar(
              progress: rate,
              color: accent,
              trackColor: color.withValues(alpha: 0.12),
            ),
          ],
        ),
      ),
    );
  }
}

class _HabitTrendRangeBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _HabitTrendRangeBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceSm,
        vertical: DesignTokens.spaceXxs + 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        maxLines: 2,
        style: TextStyle(
          fontSize: DesignTokens.fontSizeCaption,
          fontWeight: DesignTokens.fontWeightMedium,
          color: cs.onSurface,
        ),
      ),
    );
  }
}

class _HabitTrendProgressBar extends StatelessWidget {
  final double progress;
  final Color color;
  final Color trackColor;
  static const double _height = 5;

  const _HabitTrendProgressBar({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: progress.clamp(0.0, 1.0),
        minHeight: _height,
        color: color,
        backgroundColor: trackColor,
      ),
    );
  }
}

class _HabitDateBadge extends StatelessWidget {
  final DateTime date;
  final Color color;
  final bool muted;

  const _HabitDateBadge({
    required this.date,
    required this.color,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey<String>(
        'habit_date_badge_${date.year}-${date.month}-${date.day}',
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceSm,
        vertical: DesignTokens.spaceXxs + 2,
      ),
      decoration: BoxDecoration(
        color: muted
            ? cs.surfaceContainerHighest.withValues(alpha: 0.28)
            : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.28),
          width: 0.5,
        ),
      ),
      child: Text(
        '${date.month}/${date.day}',
        maxLines: 1,
        style: TextStyle(
          fontSize: DesignTokens.fontSizeCaption,
          fontWeight: DesignTokens.fontWeightMedium,
          color: muted ? cs.onSurfaceVariant : cs.onSurface,
        ),
      ),
    );
  }
}

/// 补卡日历：默认收起，展开后按月查看并点选日期补卡。
///
/// 它取代了原先 30 条「最近记录 / 补卡」长列表（原 i18n key 'habit.records.title'）：
/// 那套逐日进度已经在趋势区重复一遍，既拉长页面又没有补卡入口以外的信息。
class _HabitBackfillCalendarCard extends StatelessWidget {
  final Habit habit;
  final bool expanded;

  /// 当前展示月份（该月 1 号），由详情页持有，滚出缓存不会丢。
  final DateTime month;
  final ValueChanged<bool> onExpandedChanged;
  final ValueChanged<DateTime> onMonthChanged;

  const _HabitBackfillCalendarCard({
    super.key,
    required this.habit,
    required this.expanded,
    required this.month,
    required this.onExpandedChanged,
    required this.onMonthChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = Color(habit.colorValue);

    return AppSurfaceCard(
      padding: const EdgeInsets.all(DesignTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            label: expanded
                ? I18n.tr('habit.calendar.collapse')
                : I18n.tr('habit.calendar.expand'),
            child: InkWell(
              key: habitCalendarToggleKey,
              borderRadius: BorderRadius.circular(12),
              onTap: () => onExpandedChanged(!expanded),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: DesignTokens.controlMinHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: DesignTokens.spaceXs,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_month_outlined,
                        size: 18,
                        color: color,
                      ),
                      const SizedBox(width: DesignTokens.spaceSm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              I18n.tr('habit.calendar.title'),
                              style: const TextStyle(
                                fontWeight: DesignTokens.fontWeightStrong,
                                fontSize: DesignTokens.fontSizeSecondary,
                              ),
                            ),
                            const SizedBox(height: DesignTokens.spaceXxs + 1),
                            Text(
                              expanded
                                  ? I18n.tr('habit.calendar.expanded_hint')
                                  : I18n.tr('habit.calendar.hint'),
                              style: TextStyle(
                                fontSize: DesignTokens.fontSizeCaption,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spaceSm),
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 收起时完全不构建月历：详情页不出现 30 行重复的每日进度。
          AnimatedSize(
            duration: AppMotion.duration(context, DesignTokens.durationBase),
            curve: AppMotion.enterCurve,
            alignment: Alignment.topCenter,
            child: expanded
                ? _HabitBackfillCalendar(
                    habit: habit,
                    month: month,
                    onMonthChanged: onMonthChanged,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// 月历本体：完整本月日期 + 周一为首列的 leading/trailing 空位。
///
/// 月历按正常周历正序排列（趋势区的 30 天格才是倒序），只读的未来日
/// 不能打开写入入口，但历史月份可以一直往前翻（不截断历史）。
class _HabitBackfillCalendar extends StatelessWidget {
  final Habit habit;
  final DateTime month;
  final ValueChanged<DateTime> onMonthChanged;

  const _HabitBackfillCalendar({
    required this.habit,
    required this.month,
    required this.onMonthChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = AppClock.today();
    final currentMonth = DateTime(today.year, today.month);
    final canGoNext = month.isBefore(currentMonth);
    // 本月天数与首日星期用日历算术，不碰 Duration（避免夏令时漂移）。
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingBlanks =
        DateTime(month.year, month.month, 1).weekday - DateTime.monday;
    final lineHeight =
        MediaQuery.textScalerOf(context).scale(DesignTokens.fontSizeCaption) *
        _habitCalendarLineHeight;
    // 日格统一高度：日期一行 + 状态点，且不小于 44 触控尺寸。
    final dayHeight = math.max(
      DesignTokens.controlMinHeight,
      lineHeight +
          DesignTokens.spaceXxs +
          _habitCalendarDotSize +
          DesignTokens.spaceXs * 2 +
          1,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: DesignTokens.spaceSm),
        Divider(
          height: 1,
          thickness: 0.5,
          color: cs.outlineVariant.withValues(alpha: 0.28),
        ),
        Row(
          children: [
            IconButton(
              key: habitCalendarPrevMonthKey,
              tooltip: I18n.tr('habit.calendar.previous_month'),
              onPressed: () =>
                  onMonthChanged(DateTime(month.year, month.month - 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                MaterialLocalizations.of(context).formatMonthYear(month),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: DesignTokens.fontWeightMedium,
                  fontSize: DesignTokens.fontSizeSecondary,
                ),
              ),
            ),
            IconButton(
              key: habitCalendarNextMonthKey,
              tooltip: I18n.tr('habit.calendar.next_month'),
              // 未来月份没有可补卡的日期，最多只能停在当前月。
              onPressed: canGoNext
                  ? () => onMonthChanged(DateTime(month.year, month.month + 1))
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: DesignTokens.spaceXxs),
        LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : DesignTokens.controlMinHeight * 7;
            // 7 列每列至少 44：放不下时（320dp + 2x 字体）横向滚动而不缩字。
            final fits = available >= DesignTokens.controlMinHeight * 7;
            final cellWidth = fits
                ? available / 7
                : DesignTokens.controlMinHeight;
            final cells = <Widget>[
              for (var i = 0; i < leadingBlanks; i++)
                SizedBox(width: cellWidth, height: dayHeight),
              for (var day = 1; day <= daysInMonth; day++)
                _HabitCalendarDayCell(
                  key: ValueKey<String>(
                    '$habitCalendarDayKeyPrefix'
                    '${habit.dateKey(DateTime(month.year, month.month, day))}',
                  ),
                  habit: habit,
                  date: DateTime(month.year, month.month, day),
                  today: today,
                  width: cellWidth,
                  height: dayHeight,
                ),
            ];
            // 补齐尾部空位，保证每周都是完整 7 列，且不重复其他月份的日号。
            while (cells.length % 7 != 0) {
              cells.add(SizedBox(width: cellWidth, height: dayHeight));
            }
            final grid = SizedBox(
              width: cellWidth * 7,
              child: Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var weekday = 1; weekday <= 7; weekday++)
                        SizedBox(
                          width: cellWidth,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              bottom: DesignTokens.spaceXxs,
                            ),
                            child: Text(
                              I18n.tr('habit.weekday.$weekday'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: DesignTokens.fontSizeCaption,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  for (var start = 0; start < cells.length; start += 7)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: cells.sublist(start, start + 7),
                    ),
                ],
              ),
            );
            if (fits) return grid;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: grid,
            );
          },
        ),
      ],
    );
  }
}

/// 月历日格：日期正序、统一宽高，未来日不可点。
class _HabitCalendarDayCell extends StatelessWidget {
  final Habit habit;
  final DateTime date;
  final DateTime today;
  final double width;
  final double height;

  const _HabitCalendarDayCell({
    super.key,
    required this.habit,
    required this.date,
    required this.today,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final future = date.isAfter(today);
    final active = habit.activeForDate(date);
    final completed = active && !future && habit.isCompletedForDate(date);
    final recordedOccurrence =
        active &&
        !future &&
        habit.kind == HabitKind.negative &&
        habit.countForDate(date) > 0;
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final accent = future
        ? cs.onSurfaceVariant.withValues(alpha: 0.54)
        : !active
        ? cs.onSurfaceVariant
        : recordedOccurrence
        ? cs.error
        : completed
        ? _habitCompletedColor(context)
        : cs.onSurfaceVariant;
    final statusLabel = future
        ? I18n.tr('habit.day.future')
        : !active
        ? I18n.tr('habit.records.inactive')
        : completed
        ? I18n.tr('habit.trend.completed')
        : recordedOccurrence
        ? I18n.tr('habit.day.recorded')
        : I18n.tr('habit.day.pending');
    final semanticsLabel =
        '${date.year}/${date.month}/${date.day} · $statusLabel';
    final fill = future
        ? Colors.transparent
        : (completed || recordedOccurrence
                  ? accent
                  : DesignTokens.habitPendingTint)
              .withValues(alpha: active ? 0.15 : 0.06);
    void openDetails() => _showHabitDayDetails(
      context,
      habitId: habit.id,
      date: date,
      allowRecordActions: true,
    );

    return SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Semantics(
          container: true,
          label: semanticsLabel,
          button: !future,
          enabled: !future,
          excludeSemantics: true,
          onTap: future ? null : openDetails,
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(8),
                border: isToday
                    ? Border.all(color: cs.primary.withValues(alpha: 0.72))
                    : null,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: future ? null : openDetails,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${date.day}',
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeCaption,
                        height: _habitCalendarLineHeight,
                        fontWeight: DesignTokens.fontWeightMedium,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spaceXxs),
                    SizedBox(
                      width: _habitCalendarDotSize,
                      height: _habitCalendarDotSize,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: active && !future
                              ? accent
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _habitCompletedColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? DesignTokens.habitCompletedDark
    : DesignTokens.habitCompletedLight;

/// 统一的当日详情浮层入口：淡入 + 0.96→1 缩放，减少动效时立即完成。
///
/// 趋势区传 [allowRecordActions] = false（只读），补卡日历传 true。
Future<void> _showHabitDayDetails(
  BuildContext context, {
  required String habitId,
  required DateTime date,
  required bool allowRecordActions,
}) {
  final provider = context.read<HabitProvider>();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: I18n.tr('habit.day.details'),
    barrierColor: Colors.black.withValues(alpha: 0.16),
    transitionDuration: AppMotion.duration(context, DesignTokens.durationBase),
    pageBuilder: (dialogContext, _, _) => InheritedTheme.captureAll(
      context,
      ChangeNotifierProvider.value(
        value: provider,
        child: _HabitDayDetailsCard(
          habitId: habitId,
          date: AppClock.dateOnly(date),
          allowRecordActions: allowRecordActions,
        ),
      ),
    ),
    transitionBuilder: (dialogContext, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.enterCurve,
        reverseCurve: AppMotion.exitCurve,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

enum _HabitDayAction { primary, undo }

/// 当日详情卡：主题 surface + 极淡阴影，短内容不套半屏底部弹层。
///
/// 卡片直接从 provider 读取当前习惯（不持有过期快照），异步写入后浮层与
/// 日历都立即刷新。
class _HabitDayDetailsCard extends StatefulWidget {
  final String habitId;
  final DateTime date;
  final bool allowRecordActions;

  const _HabitDayDetailsCard({
    required this.habitId,
    required this.date,
    required this.allowRecordActions,
  });

  @override
  State<_HabitDayDetailsCard> createState() => _HabitDayDetailsCardState();
}

class _HabitDayDetailsCardState extends State<_HabitDayDetailsCard> {
  _HabitDayAction? _pending;

  Future<void> _run(_HabitDayAction action) async {
    if (_pending != null) return;
    final provider = context.read<HabitProvider>();
    final habit = provider.habits
        .where((habit) => habit.id == widget.habitId)
        .firstOrNull;
    if (!widget.allowRecordActions ||
        habit == null ||
        _habitDateIsFuture(widget.date) ||
        !habit.activeForDate(widget.date)) {
      return;
    }
    setState(() => _pending = action);
    try {
      if (action == _HabitDayAction.primary) {
        await provider.incrementHabitForDate(widget.habitId, widget.date);
      } else {
        await provider.decrementHabitForDate(widget.habitId, widget.date);
      }
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final matches = context.watch<HabitProvider>().habits.where(
      (habit) => habit.id == widget.habitId,
    );
    if (matches.isEmpty) return const SizedBox.shrink();
    final habit = matches.first;
    final date = widget.date;
    final unit = habitUnit(habit);
    final positive = habit.kind == HabitKind.positive;
    final future = _habitDateIsFuture(date);
    final active = habit.activeForDate(date);
    final count = habit.countForDate(date);
    final completed = active && habit.isCompletedForDate(date);
    final recordedOccurrence = !positive && active && !future && count > 0;
    final accent = future || !active
        ? cs.onSurfaceVariant
        : recordedOccurrence
        ? cs.error
        : completed
        ? _habitCompletedColor(context)
        : cs.onSurfaceVariant;
    final statusLabel = future
        ? I18n.tr('habit.day.future')
        : !active
        ? I18n.tr('habit.records.inactive')
        : completed
        ? I18n.tr('habit.trend.completed')
        : recordedOccurrence
        ? I18n.tr('habit.day.recorded')
        : I18n.tr('habit.day.pending');
    final flexLabel = habit.hasFlexRule
        ? _localizedFlexProgressLabel(habit.flexProgressForDate(date))
        : null;
    final canWrite = widget.allowRecordActions && active && !future;
    final cardWidth = media.size.width >= 400 ? 360.0 : 340.0;

    final card = Container(
      key: habitDayDetailsCardKey,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  MaterialLocalizations.of(context).formatFullDate(date),
                  style: const TextStyle(
                    fontWeight: DesignTokens.fontWeightStrong,
                    fontSize: DesignTokens.fontSizeBase,
                  ),
                ),
              ),
              const SizedBox(width: DesignTokens.spaceXs),
              IconButton(
                key: habitDayDetailsCloseKey,
                tooltip: I18n.tr('action.close'),
                autofocus: true,
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spaceXxs),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceSm,
              vertical: DesignTokens.spaceXxs + 1,
            ),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: DesignTokens.fontSizeCaption,
                fontWeight: DesignTokens.fontWeightMedium,
                color: accent,
              ),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          Divider(
            height: 1,
            thickness: 0.5,
            color: cs.outlineVariant.withValues(alpha: 0.32),
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          _HabitDayDetailRow(
            label: I18n.tr('habit.day.count'),
            value: _habitCountWithUnit(count, unit),
            accent: accent,
          ),
          const SizedBox(height: DesignTokens.spaceSm),
          _HabitDayDetailRow(
            label: I18n.tr('habit.day.target'),
            // 负向习惯的“目标”就是当日不发生，因此目标值恒为 0。
            value: _habitCountWithUnit(positive ? habit.targetCount : 0, unit),
            accent: cs.onSurface,
          ),
          if (flexLabel != null) ...[
            const SizedBox(height: DesignTokens.spaceSm),
            _HabitDayDetailRow(
              label: localizedFlexPeriodGoalLabel(habit),
              value: flexLabel,
              accent: cs.onSurface,
            ),
          ],
          if (canWrite) ...[
            const SizedBox(height: DesignTokens.spaceLg),
            Wrap(
              spacing: DesignTokens.spaceSm,
              runSpacing: DesignTokens.spaceSm,
              children: [
                if (count > 0)
                  TextButton.icon(
                    key: habitDayDetailsUndoKey,
                    onPressed: _pending == null
                        ? () => _run(_HabitDayAction.undo)
                        : null,
                    icon: _pending == _HabitDayAction.undo
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.undo, size: 18),
                    label: Text(I18n.tr('habit.records.undo_once')),
                  ),
                FilledButton.icon(
                  key: habitDayDetailsPrimaryKey,
                  // 正向已达标日不再可加（provider 同样拒绝超过目标）。
                  onPressed: _pending == null && !(positive && completed)
                      ? () => _run(_HabitDayAction.primary)
                      : null,
                  icon: _pending == _HabitDayAction.primary
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          positive
                              ? Icons.add_circle_outline
                              : Icons.remove_circle_outline,
                          size: 18,
                        ),
                  label: Text(
                    I18n.tr(
                      positive
                          ? 'habit.records.make_up_once'
                          : 'habit.records.record_once',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: cardWidth),
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              label: I18n.tr('habit.day.details'),
              explicitChildNodes: true,
              child: Material(
                type: MaterialType.transparency,
                child: FocusTraversalGroup(child: card),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 详情卡里的「标签 + 数值」两行块：2x 字体下自然换行，不挤成一条灰条。
class _HabitDayDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _HabitDayDetailRow({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: DesignTokens.fontSizeCaption,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: DesignTokens.spaceXxs),
        Text(
          value,
          style: TextStyle(
            fontSize: DesignTokens.fontSizeBase,
            fontWeight: DesignTokens.fontWeightStrong,
            color: accent,
          ),
        ),
      ],
    );
  }
}

/// 是否早于/晚于应用墙钟的今天（只比较年月日，避免时区与 Duration 误差）。
bool _habitDateIsFuture(DateTime date) {
  final today = AppClock.today();
  return DateTime(
    date.year,
    date.month,
    date.day,
  ).isAfter(DateTime(today.year, today.month, today.day));
}

String _habitTrendPointDescription(Habit habit, HabitTrendPoint point) {
  final date = '${point.date.year}/${point.date.month}/${point.date.day}';
  if (!point.active) {
    return '$date · ${I18n.tr('habit.records.inactive')}';
  }
  final details = localizedHabitCountForDate(habit, point.date);
  final status = point.completed
      ? I18n.tr('habit.trend.completed')
      : habit.kind == HabitKind.negative && point.count > 0
      ? I18n.tr('habit.day.recorded')
      : I18n.tr('habit.day.pending');
  return '$date · $status · $details';
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
