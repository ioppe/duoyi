import '../core/app_clock.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/ai_command.dart';
import '../core/i18n.dart';
import '../core/design_tokens.dart';
import '../core/home_page_style.dart';
import '../models/goal.dart'
    show ReminderKind, ReminderPlan, ReminderRule, ReminderRuleType;
import '../models/note.dart';
import '../models/quick_capture_template.dart';
import '../models/todo.dart';
import '../providers/habit_provider.dart';
import '../providers/note_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/quick_capture_template_provider.dart';
import '../providers/todo_provider.dart';
import '../services/ai_service.dart';
import '../services/local_notifications.dart';
import '../providers/notification_service.dart';
import '../services/reminder_scheduler.dart';
import '../screens/ai_schedule_screen.dart';
import 'surface_components.dart';
import 'todo_create_sheet.dart';

/// 展开式快速捕获 FAB：3 个子按钮 + 一个搜索入口。
class QuickCaptureFab extends StatefulWidget {
  final String? label;
  final VoidCallback? onCreate;

  const QuickCaptureFab({super.key, this.label, this.onCreate});

  @override
  State<QuickCaptureFab> createState() => _QuickCaptureFabState();
}

class _QuickCaptureFabState extends State<QuickCaptureFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  void _closeIfOpen() {
    if (!_open) return;
    setState(() => _open = false);
    _ctrl.reverse();
  }

  Future<void> _quickTodo() async {
    _closeIfOpen();
    await showTodoCreateSheet(context);
  }

  Future<void> _quickAiTodo() async {
    _toggle();
    if (!mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AiScheduleScreen()),
    );
  }

  Future<void> _quickAiCommand() async {
    _toggle();
    final ctrl = TextEditingController();
    var batch = const AiCommandBatch(rawText: '', commands: []);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AppDialog(
          title: const Text('AI 指令'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: '例如：添加待办 明天下午3点买菜；记笔记 项目想法；开始专注',
                  ),
                  onChanged: (value) {
                    setSt(() => batch = AiCommandParser.parseBatch(value));
                  },
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    batch.preview,
                    style: TextStyle(
                      fontSize: 12,
                      color: batch.executable
                          ? Theme.of(ctx).colorScheme.onSurface
                          : Theme.of(ctx).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton.icon(
              onPressed: batch.executable
                  ? () => Navigator.pop(ctx, true)
                  : null,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('执行'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    batch = AiCommandParser.parseBatch(ctrl.text);
    await _executeAiCommands(batch.commands);
  }

  Future<void> _executeAiCommands(List<AiCommand> commands) async {
    var executed = 0;
    var reminderTodos = 0;
    for (final command in commands) {
      final outcome = await _executeAiCommand(command, showSnackBar: false);
      if (!outcome.executed) continue;
      executed++;
      if (outcome.createdReminderTodo) reminderTodos++;
    }
    if (!mounted || executed == 0) return;
    final baseMessage = executed == 1 && commands.length == 1
        ? '${commands.single.title}已执行'
        : executed == commands.length
        ? '已执行 ${commands.length} 条 AI 指令'
        : '已执行 $executed/${commands.length} 条 AI 指令';
    final message = reminderTodos == 0
        ? baseMessage
        : '$baseMessage，$reminderTodos 条提醒状态可在通知设置/待办详情检查';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<_AiCommandOutcome> _executeAiCommand(
    AiCommand command, {
    bool showSnackBar = true,
  }) async {
    switch (command.type) {
      case AiCommandType.addTodo:
        final draft = command.todoDraft;
        if (draft == null) return const _AiCommandOutcome.skipped();
        final outcome = await _createTodoWithReminderFeedback(
          draft.toTodo(),
          showSnackBar: showSnackBar,
          issueTitle: '待办提醒注册失败',
        );
        return _AiCommandOutcome(
          executed: outcome.created,
          createdReminderTodo: outcome.created && outcome.hasReminder,
        );
      case AiCommandType.addNote:
        final note = command.note;
        if (note == null) return const _AiCommandOutcome.skipped();
        context.read<NoteProvider>().addOrUpdateNote(note);
      case AiCommandType.startFocus:
        final pomodoro = context.read<PomodoroProvider>();
        if (!pomodoro.state.isRunning) pomodoro.toggleTimer();
      case AiCommandType.unknown:
        return const _AiCommandOutcome.skipped();
    }
    if (!mounted || !showSnackBar) {
      return const _AiCommandOutcome(executed: true);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${command.title}已执行'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return const _AiCommandOutcome(executed: true);
  }

  Future<_TodoCreateOutcome> _createTodoWithReminderFeedback(
    TodoItem todo, {
    bool showSnackBar = true,
    String issueTitle = '待办提醒注册失败',
  }) async {
    final preflight = preflightTodoReminderPlan(todo);
    final hasReminder = preflight.hasEnabledPlan;
    if (hasReminder &&
        !await _preflightTodoReminder(todo, preflight, issueTitle)) {
      return _TodoCreateOutcome(created: false, hasReminder: hasReminder);
    }
    if (!mounted) {
      return _TodoCreateOutcome(created: false, hasReminder: hasReminder);
    }
    await context.read<TodoProvider>().addTodo(todo);
    if (!mounted) {
      return _TodoCreateOutcome(created: true, hasReminder: hasReminder);
    }
    if (showSnackBar) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_todoCreatedMessage(hasReminder)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return _TodoCreateOutcome(created: true, hasReminder: hasReminder);
  }

  Future<bool> _preflightTodoReminder(
    TodoItem todo,
    TodoReminderPreflightResult preflight,
    String issueTitle,
  ) async {
    final blocking = preflight.blockingIssue;
    if (blocking != null) {
      _showReminderFailure('${blocking.title}：${blocking.message}');
      return false;
    }

    final usesPush = preflight.kinds.contains(ReminderKind.push);
    final usesPopup = preflight.kinds.contains(ReminderKind.popup);
    final usesAlarm = preflight.kinds.contains(ReminderKind.alarm);
    if (!usesPush && !usesPopup && !usesAlarm) return true;
    final notification = context.read<NotificationService?>();
    if (notification != null && (usesPush || usesPopup)) {
      final ready = await notification.ensureReadyForReminder(
        scheduledTime: preflight.firstScheduledTime,
        issueTitle: issueTitle,
        relatedId: todo.id,
      );
      if (!mounted) return false;
      if (ready) return true;
      final issue = notification.lastScheduleIssue;
      _showReminderFailure(
        issue == null
            ? '$issueTitle：提醒未注册，请检查通知权限、渠道声音和提醒时间。'
            : '${issue.title}：${issue.message}',
      );
      return false;
    }
    if (usesAlarm) {
      final granted = await LocalNotifications.instance.ensurePermission();
      if (!mounted) return false;
      if (granted) return true;
      _showReminderFailure('$issueTitle：系统通知权限未开启，闹钟提醒未注册。请开启通知权限后重新保存提醒。');
      return false;
    }
    return true;
  }

  void _showReminderFailure(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _todoCreatedMessage(bool hasReminder) {
    return hasReminder ? '待办已创建，提醒状态可在通知设置/待办详情检查' : '待办已创建';
  }

  Future<void> _quickNote() async {
    _toggle();
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text(I18n.tr('quick.note.title')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 5,
          decoration: InputDecoration(hintText: I18n.tr('quick.note.hint')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(I18n.tr('action.save')),
          ),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      if (!mounted) return;
      final now = DateTime.now();
      context.read<NoteProvider>().addOrUpdateNote(
        NoteItem(
          id: now.millisecondsSinceEpoch.toString(),
          content: ctrl.text.trim(),
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  }

  Future<void> _showTemplateSheet() async {
    _closeIfOpen();
    final provider = context.read<QuickCaptureTemplateProvider?>();
    final selected = await showAppModalSheet<QuickCaptureTemplate>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final templates =
              provider?.templates ?? QuickCaptureTemplate.builtIns();
          return AppModalSheet(
            title: I18n.tr('quick.template.title'),
            subtitle: I18n.tr('quick.template.subtitle'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (provider != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await _showSaveTemplateDialog();
                      },
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: Text(I18n.tr('quick.template.save')),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (templates.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(I18n.tr('quick.template.empty')),
                  )
                else
                  ...templates.map(
                    (template) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _TemplateTile(
                        template: template,
                        onTap: () => Navigator.of(ctx).pop(template),
                        onDelete: template.builtIn || provider == null
                            ? null
                            : () async {
                                await provider.deleteTemplate(template.id);
                                setSheetState(() {});
                              },
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
    if (selected != null) await _applyTemplate(selected);
  }

  Future<void> _showSaveTemplateDialog() async {
    final provider = context.read<QuickCaptureTemplateProvider?>();
    if (provider == null || !mounted) return;
    final nameCtrl = TextEditingController();
    final prefixCtrl = TextEditingController();
    final tagsCtrl = TextEditingController();
    final listCtrl = TextEditingController();
    final habitCategoryCtrl = TextEditingController();
    final habitTargetCtrl = TextEditingController(text: '1');
    final habitUnitCtrl = TextEditingController(text: '次');
    var kind = QuickCaptureTemplateKind.todo;
    var priority = TodoPriority.none;
    var todoReminder = false;
    var habitReminder = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AppDialog(
          title: Text(I18n.tr('quick.template.save')),
          content: SingleChildScrollView(
            child: AppSecondaryControlTheme(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: Text(I18n.tr('quick.template.kind.todo')),
                          selected: kind == QuickCaptureTemplateKind.todo,
                          onSelected: (_) => setDialogState(
                            () => kind = QuickCaptureTemplateKind.todo,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: Text(I18n.tr('quick.template.kind.habit')),
                          selected: kind == QuickCaptureTemplateKind.habit,
                          onSelected: (_) => setDialogState(
                            () => kind = QuickCaptureTemplateKind.habit,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: I18n.tr('quick.template.name'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: prefixCtrl,
                    decoration: InputDecoration(
                      labelText: I18n.tr('quick.template.prefix'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: tagsCtrl,
                    decoration: InputDecoration(
                      labelText: I18n.tr('quick.template.tags'),
                    ),
                  ),
                  if (kind == QuickCaptureTemplateKind.todo) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: listCtrl,
                      decoration: InputDecoration(
                        labelText: I18n.tr('quick.template.list'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    AppDropdownField<TodoPriority>(
                      initialValue: priority,
                      decoration: InputDecoration(
                        labelText: I18n.tr('quick.template.priority'),
                      ),
                      items: [
                        for (final item in TodoPriority.values)
                          DropdownMenuItem(
                            value: item,
                            child: Text(item.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => priority = value);
                        }
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: todoReminder,
                      onChanged: (value) {
                        setDialogState(() => todoReminder = value);
                      },
                      title: Text(I18n.tr('quick.template.reminder15')),
                    ),
                  ] else ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: habitCategoryCtrl,
                      decoration: InputDecoration(
                        labelText: I18n.tr('quick.template.habit_category'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: habitTargetCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: I18n.tr('quick.template.habit_target'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 92,
                          child: TextField(
                            controller: habitUnitCtrl,
                            decoration: InputDecoration(
                              labelText: I18n.tr('quick.template.habit_unit'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: habitReminder,
                      onChanged: (value) {
                        setDialogState(() => habitReminder = value);
                      },
                      title: Text(I18n.tr('quick.template.habit_reminder')),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(dialogContext, true);
              },
              child: Text(I18n.tr('action.save')),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;

    final reminderPlan = todoReminder
        ? ReminderPlan(
            enabled: true,
            rules: [
              ReminderRule(
                type: ReminderRuleType.relativeToDue,
                kind: ReminderKind.push,
                offsetMinutes: -15,
              ),
            ],
          )
        : const ReminderPlan.disabled();
    await provider.saveTemplate(
      QuickCaptureTemplate(
        name: nameCtrl.text.trim(),
        kind: kind,
        titlePrefix: prefixCtrl.text.trim(),
        tags: tagsCtrl.text.split(RegExp(r'[,，\s]+')),
        priority: priority,
        listGroupName: listCtrl.text.trim().isEmpty ? null : listCtrl.text,
        reminderPlan: reminderPlan,
        habitCategory: habitCategoryCtrl.text.trim().isEmpty
            ? null
            : habitCategoryCtrl.text,
        habitTargetCount: int.tryParse(habitTargetCtrl.text) ?? 1,
        habitUnit: habitUnitCtrl.text.trim().isEmpty
            ? null
            : habitUnitCtrl.text,
        habitRemind: habitReminder,
        habitRemindHour: habitReminder ? 21 : null,
        habitRemindMinute: habitReminder ? 0 : null,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(I18n.tr('quick.template.saved')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _applyTemplate(QuickCaptureTemplate template) async {
    if (!mounted) return;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: Text(template.name),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: template.kind == QuickCaptureTemplateKind.todo ? 2 : 1,
          decoration: InputDecoration(
            hintText: I18n.tr('quick.template.apply_hint'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(I18n.tr('action.create')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final input = ctrl.text.trim();
    if (input.isEmpty && template.displayTitlePrefix.isEmpty) return;
    if (template.kind == QuickCaptureTemplateKind.todo) {
      final outcome = await _createTodoWithReminderFeedback(
        template.toTodo(input),
        showSnackBar: false,
        issueTitle: '待办提醒注册失败',
      );
      if (!outcome.created) return;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            outcome.hasReminder
                ? _todoCreatedMessage(true)
                : I18n.tr('quick.template.todo_done'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final habitProvider = context.read<HabitProvider?>();
      if (habitProvider == null) return;
      await habitProvider.addHabit(template.toHabit(input));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(I18n.tr('quick.template.habit_done')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _mini({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ScaleTransition(
      scale: _ctrl,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Text(label, style: const TextStyle(fontSize: 12)),
            ),
            FloatingActionButton(
              heroTag: label,
              mini: true,
              backgroundColor: color,
              foregroundColor: Colors.white,
              onPressed: onTap,
              child: Icon(icon),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final cs = Theme.of(context).colorScheme;
    final aiEnabled = context.watch<AiService>().enabled;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_open) ...[
          _mini(
            icon: Icons.bookmark_add_outlined,
            label: I18n.tr('quick.menu.template'),
            color: Colors.indigo,
            onTap: _showTemplateSheet,
          ),
          if (aiEnabled)
            _mini(
              icon: Icons.assistant_outlined,
              label: 'AI 指令',
              color: Colors.deepPurple,
              onTap: _quickAiCommand,
            ),
          if (aiEnabled)
            _mini(
              icon: Icons.auto_awesome,
              label: I18n.tr('quick.menu.ai_schedule'),
              color: Colors.purple,
              onTap: _quickAiTodo,
            ),
          _mini(
            icon: Icons.edit_note,
            label: I18n.tr('quick.menu.note'),
            color: Colors.amber.shade700,
            onTap: _quickNote,
          ),
          _mini(
            icon: Icons.check_circle_outline,
            label: I18n.tr('quick.menu.todo'),
            color: cs.primary,
            onTap: _quickTodo,
          ),
        ],
        Tooltip(
          message: widget.label == null ? '' : I18n.tr('today.capture.tooltip'),
          triggerMode: TooltipTriggerMode.manual,
          child: GestureDetector(
            onLongPress: widget.label == null ? _showTemplateSheet : _toggle,
            child: widget.label == null
                ? FloatingActionButton(
                    heroTag: 'quick_capture',
                    onPressed: _toggle,
                    child: AnimatedRotation(
                      turns: _open ? 0.125 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: const Icon(Icons.add),
                    ),
                  )
                : SizedBox(
                    height: DesignTokens.controlMinHeight,
                    child: FloatingActionButton.extended(
                      key: const ValueKey('home_create_button'),
                      heroTag: 'quick_capture',
                      elevation: 0,
                      backgroundColor: HomePageStyle.of(context).accent,
                      foregroundColor: Theme.of(
                        context,
                      ).floatingActionButtonTheme.foregroundColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          DesignTokens.radiusCard,
                        ),
                      ),
                      extendedPadding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spaceLg,
                      ),
                      extendedIconLabelSpacing: DesignTokens.spaceSm,
                      extendedTextStyle: HomePageStyle.of(context).typography(
                        Theme.of(context),
                        size: DesignTokens.fontSizeSm,
                        color: Theme.of(
                          context,
                        ).floatingActionButtonTheme.foregroundColor,
                      ),
                      onPressed: _open
                          ? _toggle
                          : widget.onCreate ?? _quickTodo,
                      icon: Icon(
                        _open ? Icons.close : Icons.add,
                        size: DesignTokens.controlIconSize,
                      ),
                      label: Text(widget.label!),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _TodoCreateOutcome {
  final bool created;
  final bool hasReminder;

  const _TodoCreateOutcome({required this.created, required this.hasReminder});
}

class _AiCommandOutcome {
  final bool executed;
  final bool createdReminderTodo;

  const _AiCommandOutcome({
    required this.executed,
    this.createdReminderTodo = false,
  });

  const _AiCommandOutcome.skipped()
    : executed = false,
      createdReminderTodo = false;
}

class _TemplateTile extends StatelessWidget {
  final QuickCaptureTemplate template;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _TemplateTile({
    required this.template,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isHabit = template.kind == QuickCaptureTemplateKind.habit;
    final icon = isHabit ? Icons.repeat_rounded : Icons.checklist_rounded;
    final color = isHabit ? Colors.teal : cs.primary;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: color.withValues(alpha: 0.14),
          foregroundColor: color,
          child: Icon(icon, size: 18),
        ),
        title: Text(
          template.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          template.previewSummary(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: onDelete == null
            ? const Icon(Icons.chevron_right)
            : IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: I18n.tr('action.delete'),
                onPressed: onDelete,
              ),
        onTap: onTap,
      ),
    );
  }
}
