import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_clock.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/iterable_extensions.dart';
import '../models/calendar_event.dart';
import '../models/habit.dart';
import '../providers/anniversary_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/course_provider.dart';
import '../providers/countdown_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/time_audit_provider.dart';
import '../providers/todo_provider.dart';
import '../screens/anniversary_screen.dart';
import '../screens/countdown_screen.dart';
import '../screens/course_schedule_screen.dart';
import '../screens/habit_detail_screen.dart';
import '../screens/pomodoro_screen.dart';
import '../screens/time_audit_screen.dart';
import '../screens/today_detail_router.dart';
import '../widgets/brand_background.dart';
import '../widgets/todo_completion_flow.dart';
import 'app_date_picker.dart';
import 'app_time_picker.dart';
import 'surface_components.dart';

Future<void> showCalendarEventSheet(BuildContext context, CalendarEvent event) {
  return showAppModalSheet<void>(
    context: context,
    builder: (_) => CalendarEventSheet(event: event),
  );
}

Future<void> showLocalCalendarEventEditor(
  BuildContext context, {
  DateTime? initialDate,
  CalendarEvent? event,
  String? workspaceId,
}) async {
  if (event != null && !event.type.isVisible) {
    return showCalendarEventSheet(context, event);
  }
  final provider = context.read<CalendarProvider>();
  event = event?.inAppTimeZone();
  final titleCtrl = TextEditingController(text: event?.title ?? '');
  final noteCtrl = TextEditingController(text: event?.note ?? '');
  var startDate = _dateOnly(initialDate ?? event?.date ?? AppClock.now());
  var endDate = _localEventInclusiveEndDate(event) ?? startDate;
  var allDay = event?.time == null;
  var startTime = event?.time ?? const TimeOfDay(hour: 9, minute: 0);
  var endTime = event?.endDate == null
      ? const TimeOfDay(hour: 10, minute: 0)
      : TimeOfDay.fromDateTime(event!.endDate!);
  var color = event?.color ?? const Color(0xFF5B6EE1);

  try {
    final saved = await showAppModalSheet<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          AppClock.watch(dialogContext);
          return AppModalSheet(
            key: const ValueKey('calendar_event_create_sheet'),
            title: event == null ? '新建日程' : '编辑日程',
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('保存'),
              ),
            ],
            child: AppFormFieldTheme(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: '日程标题',
                      prefixIcon: Icon(Icons.event_note_outlined),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.today_outlined),
                    title: const Text('全天'),
                    subtitle: const Text('适合假期、出差、生日等跨天安排'),
                    value: allDay,
                    onChanged: (value) => setDialogState(() => allDay = value),
                  ),
                  _DatePickTile(
                    icon: Icons.event_available_outlined,
                    title: '开始日期',
                    value: startDate,
                    onTap: () async {
                      final picked = await AppDatePicker.pickSolar(
                        dialogContext,
                        initialDate: startDate,
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2100),
                        title: '开始日期',
                      );
                      if (picked == null || !dialogContext.mounted) return;
                      setDialogState(() {
                        startDate = _dateOnly(picked);
                        if (endDate.isBefore(startDate)) {
                          endDate = startDate;
                        }
                      });
                    },
                  ),
                  _DatePickTile(
                    icon: Icons.event_busy_outlined,
                    title: '结束日期',
                    value: endDate,
                    onTap: () async {
                      final picked = await AppDatePicker.pickSolar(
                        dialogContext,
                        initialDate: endDate,
                        firstDate: startDate,
                        lastDate: DateTime(2100),
                        title: '结束日期',
                      );
                      if (picked == null || !dialogContext.mounted) return;
                      setDialogState(() => endDate = _dateOnly(picked));
                    },
                  ),
                  if (!allDay) ...[
                    _TimePickTile(
                      icon: Icons.schedule_outlined,
                      title: '开始时间',
                      value: startTime,
                      onTap: () async {
                        final picked = await AppTimePicker.show(
                          dialogContext,
                          initialTime: startTime,
                          title: '开始时间',
                          minuteStep: 5,
                        );
                        if (picked == null || !dialogContext.mounted) return;
                        setDialogState(() => startTime = picked);
                      },
                    ),
                    _TimePickTile(
                      icon: Icons.timelapse_outlined,
                      title: '结束时间',
                      value: endTime,
                      onTap: () async {
                        final picked = await AppTimePicker.show(
                          dialogContext,
                          initialTime: endTime,
                          title: '结束时间',
                          minuteStep: 5,
                        );
                        if (picked == null || !dialogContext.mounted) return;
                        setDialogState(() => endTime = picked);
                      },
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option in _localEventColors)
                          _ColorChoice(
                            color: option,
                            selected: color == option,
                            onTap: () => setDialogState(() => color = option),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: '备注',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (saved != true || !context.mounted) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty) return;

    final normalized = _normalizeLocalEventTime(
      startDate: startDate,
      endDate: endDate,
      allDay: allDay,
      startTime: startTime,
      endTime: endTime,
    );
    final effectiveWorkspaceId = workspaceId ?? event?.workspaceId;
    final next = CalendarEvent(
      id: event?.id ?? '',
      title: title,
      date: normalized.start,
      endDate: normalized.end,
      type: CalendarEventType.event,
      color: color,
      sourceId: event?.sourceId,
      subtitle: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      workspaceId: effectiveWorkspaceId,
      time: allDay ? null : startTime,
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      updatedAt: DateTime.now(),
    );
    if (event == null) {
      await provider.addLocalEvent(next);
    } else {
      await provider.updateLocalEvent(next);
    }
  } finally {
    titleCtrl.dispose();
    noteCtrl.dispose();
  }
}

class CalendarEventSheet extends StatelessWidget {
  final CalendarEvent event;

  const CalendarEventSheet({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    if (!this.event.type.isVisible) {
      return AppModalSheet(
        title: I18n.tr('feature.unavailable'),
        child: Text(I18n.tr('feature.unavailable')),
      );
    }
    AppClock.watch(context);
    final event = this.event.inAppTimeZone();
    final cs = Theme.of(context).colorScheme;
    return AppModalSheet(
      title: event.title,
      maxWidth: 860,
      scrollable: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.68,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: icon + type tag + time + conflict warning
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: event.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_icon(event.type), color: event.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppStatusBadge(
                        label: event.type.label,
                        color: event.color,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _timeText(event),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: DesignTokens.fontWeightStrong,
                        ),
                      ),
                    ],
                  ),
                ),
                if (event.hasConflict)
                  Tooltip(
                    message: '同一时间段还有 ${event.conflictCount} 个事项',
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: cs.error,
                      size: 20,
                    ),
                  ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                key: const ValueKey('calendar_event_detail_scroll_region'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (event.subtitle != null &&
                        event.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        event.subtitle!,
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.68),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Type-specific action buttons
            Wrap(spacing: 8, runSpacing: 8, children: _buildActions(context)),
          ],
        ),
      ),
    );
  }

  /// Build action buttons based on event type.
  List<Widget> _buildActions(BuildContext context) {
    switch (event.type) {
      case CalendarEventType.event:
        return [
          _actionButton(
            context,
            icon: Icons.edit_outlined,
            label: '编辑',
            onPressed: () => _editLocalEvent(context),
          ),
          _actionButton(
            context,
            icon: Icons.delete_outline,
            label: '删除',
            onPressed: () => _delete(context),
            tonal: true,
          ),
        ];
      case CalendarEventType.todo:
        return [
          if (!event.isCompleted)
            _actionButton(
              context,
              icon: Icons.done,
              label: '完成',
              onPressed: () => _completeTodo(context),
            ),
          _actionButton(
            context,
            icon: Icons.event_repeat,
            label: '改期',
            onPressed: () => _reschedule(context),
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.schedule_outlined,
            label: '调整时间',
            onPressed: () => _adjustTodoTime(context),
          ),
          _actionButton(
            context,
            icon: Icons.edit_outlined,
            label: '编辑',
            onPressed: () => _openDetail(context),
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: '跳转详情',
            onPressed: event.canOpen ? () => _openDetail(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.delete_outline,
            label: '删除',
            onPressed: () => _delete(context),
            tonal: true,
          ),
        ];
      case CalendarEventType.habit:
        final habit = event.sourceId == null
            ? null
            : context
                  .read<HabitProvider>()
                  .habits
                  .where((h) => h.id == event.sourceId)
                  .firstOrNull;
        final isNegative = habit?.kind == HabitKind.negative;
        return [
          if (!event.isCompleted)
            _actionButton(
              context,
              icon: isNegative ? Icons.add_circle_outline : Icons.check,
              label: isNegative ? '记录一次' : '打卡',
              onPressed: () => _checkInHabit(context),
            ),
          _actionButton(
            context,
            icon: Icons.edit_outlined,
            label: '编辑',
            onPressed: () => _editSourceEvent(context),
          ),
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: '跳转详情',
            onPressed: event.canOpen ? () => _openDetail(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.delete_outline,
            label: '删除',
            onPressed: () => _delete(context),
            tonal: true,
          ),
        ];
      case CalendarEventType.pomodoro:
        return [
          _actionButton(
            context,
            icon: Icons.play_arrow,
            label: '开始专注',
            onPressed: () => _startFocus(context),
          ),
          _actionButton(
            context,
            icon: Icons.edit_outlined,
            label: '编辑',
            onPressed: () => _editSourceEvent(context),
          ),
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: '跳转详情',
            onPressed: event.canOpen ? () => _openDetail(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.delete_outline,
            label: '删除',
            onPressed: () => _delete(context),
            tonal: true,
          ),
        ];
      case CalendarEventType.goal:
        return [
          _actionButton(
            context,
            icon: Icons.event_repeat,
            label: '改期',
            onPressed: () => _reschedule(context),
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: '跳转详情',
            onPressed: event.canOpen ? () => _openDetail(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.delete_outline,
            label: '删除',
            onPressed: () => _delete(context),
            tonal: true,
          ),
        ];
      case CalendarEventType.course:
        return [
          _actionButton(
            context,
            icon: Icons.edit_outlined,
            label: '编辑',
            onPressed: () => _editSourceEvent(context),
          ),
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: '跳转详情',
            onPressed: event.canOpen ? () => _openDetail(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.delete_outline,
            label: '删除',
            onPressed: () => _delete(context),
            tonal: true,
          ),
        ];
      case CalendarEventType.anniversary:
        return [
          _actionButton(
            context,
            icon: Icons.event_repeat,
            label: '改期',
            onPressed: () => _reschedule(context),
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.edit_outlined,
            label: '编辑',
            onPressed: () => _editSourceEvent(context),
          ),
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: '跳转详情',
            onPressed: event.canOpen ? () => _openDetail(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.delete_outline,
            label: '删除',
            onPressed: () => _delete(context),
            tonal: true,
          ),
        ];
      case CalendarEventType.countdown:
        return [
          _actionButton(
            context,
            icon: Icons.event_repeat,
            label: '改期',
            onPressed: () => _reschedule(context),
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.edit_outlined,
            label: '编辑',
            onPressed: () => _editSourceEvent(context),
          ),
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: '跳转详情',
            onPressed: event.canOpen ? () => _openDetail(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.delete_outline,
            label: '删除',
            onPressed: () => _delete(context),
            tonal: true,
          ),
        ];
      case CalendarEventType.diary:
        return const <Widget>[];
      case CalendarEventType.timeEntry:
        if (event.sourceId == null) return const <Widget>[];
        return [
          _actionButton(
            context,
            icon: Icons.event_repeat,
            label: '改期',
            onPressed: () => _reschedule(context),
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.schedule_outlined,
            label: '调整开始',
            onPressed: () => _adjustTimeEntryStart(context),
          ),
          _actionButton(
            context,
            icon: Icons.timer_outlined,
            label: '调整时长',
            onPressed: () => _adjustTimeEntryDuration(context),
          ),
          _actionButton(
            context,
            icon: Icons.open_in_new,
            label: '跳转详情',
            onPressed: event.canOpen ? () => _openDetail(context) : null,
            tonal: true,
          ),
          _actionButton(
            context,
            icon: Icons.delete_outline,
            label: '删除',
            onPressed: () => _delete(context),
            tonal: true,
          ),
        ];
    }
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    VoidCallback? onPressed,
    bool tonal = false,
  }) {
    final compactStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      textStyle: WidgetStatePropertyAll(appSecondaryControlTextStyle(context)),
    );
    if (tonal) {
      return FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: compactStyle,
      );
    }
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: compactStyle,
    );
  }

  // ---- CalendarActionRouter: dispatches actions back to source providers ----

  Future<void> _completeTodo(BuildContext context) async {
    final sourceId = event.sourceId;
    if (sourceId == null) return;
    final todo = context
        .read<TodoProvider>()
        .todos
        .where((t) => t.id == sourceId)
        .firstOrNull;
    if (todo == null) return;
    await completeTodoWithOptionalTimeRecord(context, todo);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _checkInHabit(BuildContext context) async {
    final sourceId = event.sourceId;
    if (sourceId == null) return;
    await context.read<HabitProvider>().incrementHabitForDate(
      sourceId,
      event.date,
    );
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _startFocus(BuildContext context) async {
    final navigator = Navigator.of(context);
    navigator.pop();
    if (!navigator.mounted) return;
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => const BrandRouteSurface(
          child: PomodoroScreen(useShellBackground: true),
        ),
      ),
    );
  }

  Future<void> _openDetail(BuildContext context) async {
    final sourceId = event.sourceId;
    if (sourceId == null) return;
    final navigator = Navigator.of(context);
    final navigationContext = navigator.context;
    navigator.pop();
    if (!navigationContext.mounted) return;
    switch (event.type) {
      case CalendarEventType.todo:
        await TodayDetailRouter.open(
          navigationContext,
          TodaySectionKind.todos,
          id: sourceId,
        );
      case CalendarEventType.habit:
        await TodayDetailRouter.open(
          navigationContext,
          TodaySectionKind.habits,
          id: sourceId,
        );
      case CalendarEventType.goal:
        await TodayDetailRouter.open(
          navigationContext,
          TodaySectionKind.goals,
          id: sourceId,
        );
      case CalendarEventType.anniversary:
        await TodayDetailRouter.open(
          navigationContext,
          TodaySectionKind.anniversaries,
          id: sourceId,
        );
      case CalendarEventType.course:
        await TodayDetailRouter.open(
          navigationContext,
          TodaySectionKind.courses,
          id: sourceId,
        );
      case CalendarEventType.diary:
        return;
      case CalendarEventType.countdown:
        if (!navigator.mounted) return;
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => BrandRouteSurface(
              child: CountdownScreen(initialCountdownId: sourceId),
            ),
          ),
        );
      case CalendarEventType.timeEntry:
      case CalendarEventType.pomodoro:
        if (!navigator.mounted) return;
        await navigator.push(
          MaterialPageRoute(
            builder: (_) => const BrandRouteSurface(child: TimeAuditScreen()),
          ),
        );
      case CalendarEventType.event:
        break;
    }
  }

  Future<void> _reschedule(BuildContext context) async {
    final sourceId = event.sourceId;
    if (sourceId == null) return;
    final picked = await AppDatePicker.pickSolar(
      context,
      initialDate: event.date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      title: '调整日期',
    );
    if (picked == null || !context.mounted) return;

    switch (event.type) {
      case CalendarEventType.todo:
        final provider = context.read<TodoProvider>();
        final todo = provider.todos.where((t) => t.id == sourceId).firstOrNull;
        if (todo != null) {
          await provider.updateTodo(
            todo.id,
            todo.copyWith(
              date: picked,
              dueDate: todo.dueDate == null
                  ? null
                  : _sameTime(picked, todo.dueDate!),
            ),
          );
        }
      case CalendarEventType.goal:
        final provider = context.read<GoalProvider>();
        final goal = provider.goals.where((g) => g.id == sourceId).firstOrNull;
        if (goal != null) {
          goal.targetDate = picked;
          await provider.update(goal);
        }
      case CalendarEventType.anniversary:
        final provider = context.read<AnniversaryProvider>();
        final item = provider.items.where((a) => a.id == sourceId).firstOrNull;
        if (item != null) {
          item.originDate = picked;
          await provider.update(item);
        }
      case CalendarEventType.countdown:
        final provider = context.read<CountdownProvider>();
        final item = provider.items.where((c) => c.id == sourceId).firstOrNull;
        if (item != null) {
          await provider.updateItem(item.copyWith(targetDate: picked));
        }
      case CalendarEventType.timeEntry:
        final provider = context.read<TimeAuditProvider>();
        final entry = provider.entries
            .where((e) => e.id == sourceId)
            .firstOrNull;
        if (entry != null) {
          final duration = entry.endAt.difference(entry.startAt);
          final start = _sameTime(picked, entry.startAt);
          await provider.update(
            entry.copyWith(startAt: start, endAt: start.add(duration)),
          );
        }
      case CalendarEventType.event:
        final provider = context.read<CalendarProvider>();
        final original = provider.localEvents
            .where((local) => local.id == event.id)
            .firstOrNull;
        if (original != null) {
          final duration = (original.endDate ?? original.date).difference(
            original.date,
          );
          final start = _sameTime(picked, original.date);
          await provider.updateLocalEvent(
            original.copyWith(date: start, endDate: start.add(duration)),
          );
        }
      default:
        break;
    }
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _adjustTimeEntryDuration(BuildContext context) async {
    final sourceId = event.sourceId;
    if (sourceId == null) return;
    final provider = context.read<TimeAuditProvider>();
    final entry = provider.entries.where((e) => e.id == sourceId).firstOrNull;
    if (entry == null) return;

    final minutes = await showAppModalSheet<int>(
      context: context,
      builder: (_) => AppPickerSheet<int>(
        title: '调整时长',
        subtitle: '保留开始时间，快速调整结束时间',
        selectedValue: (entry.durationSeconds / 60).round(),
        options: const [
          AppPickerOption(value: 15, title: '15 分钟'),
          AppPickerOption(value: 30, title: '30 分钟'),
          AppPickerOption(value: 45, title: '45 分钟'),
          AppPickerOption(value: 60, title: '60 分钟'),
          AppPickerOption(value: 90, title: '90 分钟'),
          AppPickerOption(value: 120, title: '120 分钟'),
        ],
      ),
    );
    if (minutes == null || !context.mounted) return;
    await provider.update(
      entry.copyWith(endAt: entry.startAt.add(Duration(minutes: minutes))),
    );
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _adjustTimeEntryStart(BuildContext context) async {
    final sourceId = event.sourceId;
    if (sourceId == null) return;
    final provider = context.read<TimeAuditProvider>();
    final entry = provider.entries.where((e) => e.id == sourceId).firstOrNull;
    if (entry == null) return;

    final localStart = AppClock.toLocal(entry.startAt);
    final picked = await AppTimePicker.show(
      context,
      initialTime: TimeOfDay.fromDateTime(localStart),
      title: '调整开始时间',
      subtitle: '保留当前日期和时长，自动更新结束时间',
    );
    if (picked == null || !context.mounted) return;

    final startAt = AppClock.date(
      localStart.year,
      localStart.month,
      localStart.day,
      picked.hour,
      picked.minute,
    );
    final duration = entry.endAt.difference(entry.startAt);
    await provider.update(
      entry.copyWith(startAt: startAt, endAt: startAt.add(duration)),
    );
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _adjustTodoTime(BuildContext context) async {
    final sourceId = event.sourceId;
    if (sourceId == null) return;
    final provider = context.read<TodoProvider>();
    final todo = provider.todos.where((t) => t.id == sourceId).firstOrNull;
    if (todo == null) return;

    final base = todo.localDueDate ?? todo.date;
    final picked = await AppTimePicker.show(
      context,
      initialTime: TimeOfDay.fromDateTime(base),
      title: '调整时间',
      subtitle: '保留当前日期，只调整当天截止时间',
    );
    if (picked == null || !context.mounted) return;

    final dueDate = AppClock.date(
      todo.date.year,
      todo.date.month,
      todo.date.day,
      picked.hour,
      picked.minute,
    );
    await provider.updateTodo(todo.id, todo.copyWith(dueDate: dueDate));
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _editLocalEvent(BuildContext context) async {
    final navigator = Navigator.of(context);
    final navigationContext = navigator.context;
    navigator.pop();
    if (!navigationContext.mounted) return;
    await showLocalCalendarEventEditor(navigationContext, event: event);
  }

  Future<void> _editSourceEvent(BuildContext context) async {
    final sourceId = event.sourceId;
    if (sourceId == null) return;
    final navigator = Navigator.of(context);
    final navigationContext = navigator.context;
    switch (event.type) {
      case CalendarEventType.anniversary:
        final item = context
            .read<AnniversaryProvider>()
            .items
            .where((a) => a.id == sourceId)
            .firstOrNull;
        if (item == null) return;
        navigator.pop();
        if (!navigationContext.mounted) return;
        await showAnniversaryEditor(navigationContext, item: item);
      case CalendarEventType.countdown:
        final item = context
            .read<CountdownProvider>()
            .items
            .where((c) => c.id == sourceId)
            .firstOrNull;
        if (item == null) return;
        navigator.pop();
        if (!navigationContext.mounted) return;
        await showCountdownEditor(navigationContext, item: item);
      case CalendarEventType.course:
        final item = context
            .read<CourseProvider>()
            .courses
            .where((c) => c.id == sourceId)
            .firstOrNull;
        if (item == null) return;
        navigator.pop();
        if (!navigationContext.mounted) return;
        await showCourseEditor(navigationContext, course: item);
      case CalendarEventType.habit:
        final item = context
            .read<HabitProvider>()
            .habits
            .where((h) => h.id == sourceId)
            .firstOrNull;
        if (item == null) return;
        navigator.pop();
        if (!navigationContext.mounted) return;
        await showHabitEditor(navigationContext, item);
      case CalendarEventType.pomodoro:
        final item = context
            .read<PomodoroProvider>()
            .sessions
            .where((s) => s.id == sourceId)
            .firstOrNull;
        if (item == null) return;
        navigator.pop();
        if (!navigationContext.mounted) return;
        await showPomodoroSessionEditor(navigationContext, item);
      default:
        break;
    }
  }

  Future<void> _delete(BuildContext context) async {
    if (event.type == CalendarEventType.event) {
      await context.read<CalendarProvider>().deleteLocalEvent(event.id);
      if (context.mounted) Navigator.pop(context);
      return;
    }
    final sourceId = event.sourceId;
    if (sourceId == null) return;
    switch (event.type) {
      case CalendarEventType.todo:
        await context.read<TodoProvider>().deleteTodo(sourceId);
      case CalendarEventType.habit:
        await context.read<HabitProvider>().deleteHabit(sourceId);
      case CalendarEventType.goal:
        await context.read<GoalProvider>().delete(sourceId);
      case CalendarEventType.anniversary:
        await context.read<AnniversaryProvider>().delete(sourceId);
      case CalendarEventType.countdown:
        await context.read<CountdownProvider>().deleteItem(sourceId);
      case CalendarEventType.course:
        await context.read<CourseProvider>().delete(sourceId);
      case CalendarEventType.diary:
        return;
      case CalendarEventType.timeEntry:
        await context.read<TimeAuditProvider>().delete(sourceId);
      case CalendarEventType.pomodoro:
        await context.read<PomodoroProvider>().deleteSession(sourceId);
      default:
        break;
    }
    if (context.mounted) Navigator.pop(context);
  }

  DateTime _sameTime(DateTime date, DateTime time) {
    return AppClock.date(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
  }

  String _timeText(CalendarEvent event) {
    final start = event.time;
    if (start == null) return _allDayText(event);
    final startText = I18nDateFormat.timeOfDay(
      hour: start.hour,
      minute: start.minute,
    );
    final dateText = I18nDateFormat.monthDay(event.date);
    if (event.endDate == null) {
      return '$dateText $startText';
    }
    final end = TimeOfDay.fromDateTime(event.endDate!);
    final endText = I18nDateFormat.timeOfDay(
      hour: end.hour,
      minute: end.minute,
    );
    final endDateText = I18nDateFormat.monthDay(event.endDate!);
    if (_dateOnly(event.date) == _dateOnly(event.endDate!)) {
      return '$dateText $startText-$endText';
    }
    return '$dateText $startText - $endDateText $endText';
  }

  IconData _icon(CalendarEventType t) {
    return switch (t) {
      CalendarEventType.event => Icons.event_note_outlined,
      CalendarEventType.todo => Icons.check_circle_outline,
      CalendarEventType.habit => Icons.repeat,
      CalendarEventType.pomodoro => Icons.timer,
      CalendarEventType.anniversary => Icons.celebration_outlined,
      CalendarEventType.course => Icons.class_outlined,
      CalendarEventType.diary => Icons.book_outlined,
      CalendarEventType.countdown => Icons.hourglass_bottom,
      CalendarEventType.goal => Icons.flag_circle_outlined,
      CalendarEventType.timeEntry => Icons.timelapse_outlined,
    };
  }

  String _allDayText(CalendarEvent event) {
    final start = I18nDateFormat.monthDay(event.date);
    final visibleEnd = _localEventInclusiveEndDate(event);
    if (visibleEnd == null || _dateOnly(event.date) == visibleEnd) {
      return '$start 全天';
    }
    return '$start - ${I18nDateFormat.monthDay(visibleEnd)} 全天';
  }
}

class _LocalEventTimeRange {
  final DateTime start;
  final DateTime end;

  const _LocalEventTimeRange({required this.start, required this.end});
}

class _DatePickTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final DateTime value;
  final VoidCallback onTap;

  const _DatePickTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(I18nDateFormat.date(value)),
      onTap: onTap,
    );
  }
}

class _TimePickTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final TimeOfDay value;
  final VoidCallback onTap;

  const _TimePickTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(AppTimePicker.format(value)),
      onTap: onTap,
    );
  }
}

class _ColorChoice extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorChoice({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check,
                color: color.computeLuminance() > 0.55
                    ? Colors.black
                    : Colors.white,
                size: 18,
              )
            : null,
      ),
    );
  }
}

const _localEventColors = <Color>[
  Color(0xFF5B6EE1),
  Color(0xFF26A69A),
  Color(0xFFFF9800),
  Color(0xFFE91E63),
  Color(0xFF7E57C2),
  Color(0xFF607D8B),
];

_LocalEventTimeRange _normalizeLocalEventTime({
  required DateTime startDate,
  required DateTime endDate,
  required bool allDay,
  required TimeOfDay startTime,
  required TimeOfDay endTime,
}) {
  if (allDay) {
    return _LocalEventTimeRange(
      start: startDate,
      end: endDate.add(const Duration(days: 1)),
    );
  }
  final start = AppClock.date(
    startDate.year,
    startDate.month,
    startDate.day,
    startTime.hour,
    startTime.minute,
  );
  var end = AppClock.date(
    endDate.year,
    endDate.month,
    endDate.day,
    endTime.hour,
    endTime.minute,
  );
  if (!end.isAfter(start)) {
    end = start.add(const Duration(minutes: 30));
  }
  return _LocalEventTimeRange(start: start, end: end);
}

DateTime? _localEventInclusiveEndDate(CalendarEvent? event) {
  final endDate = event?.endDate;
  if (event == null || endDate == null) return null;
  if (event.time != null) return _dateOnly(endDate);
  final end = _dateOnly(endDate);
  if (end.isAfter(_dateOnly(event.date))) {
    return end.subtract(const Duration(days: 1));
  }
  return end;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
