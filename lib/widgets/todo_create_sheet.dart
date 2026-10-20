import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_clock.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/smart_date_parser.dart';
import '../core/smart_todo_draft.dart';
import '../core/todo_templates.dart';
import '../models/goal.dart'
    show ReminderKind, ReminderPlan, ReminderRule, ReminderRuleType;
import '../models/todo.dart';
import '../providers/auth_provider.dart';
import '../providers/notification_service.dart';
import '../providers/share_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/todo_provider.dart';
import '../screens/todo_detail_screen.dart' show preflightTodoReminderSave;
import '../services/ai_service.dart';
import '../services/api_client.dart';
import 'surface_components.dart';

/// The same full creation form is used by Today, the todo page and its quadrants.
Future<void> showTodoCreateSheet(
  BuildContext context, {
  EisenhowerQuadrant? initialQuadrant,
}) async {
  final result = await showAppModalSheet<_TodoCreateResult>(
    context: context,
    builder: (_) => _TodoCreateSheet(
      initialQuadrant: initialQuadrant,
      messenger: ScaffoldMessenger.of(context),
    ),
  );
  if (result == null || !context.mounted) return;
  final message = result.hasReminder && result.reminderIssue != null
      ? '${I18n.tr('todo.quick_add.reminder_sync_failed_prefix')}${result.reminderIssue}'
      : I18n.tr(
          result.hasReminder
              ? 'todo.create.created_reminder'
              : 'todo.create.created',
        );
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

class _TodoCreateResult {
  final bool hasReminder;
  final String? reminderIssue;

  const _TodoCreateResult({required this.hasReminder, this.reminderIssue});
}

class _TodoCreateSheet extends StatefulWidget {
  final EisenhowerQuadrant? initialQuadrant;
  final ScaffoldMessengerState messenger;

  const _TodoCreateSheet({this.initialQuadrant, required this.messenger});

  @override
  State<_TodoCreateSheet> createState() => _TodoCreateSheetState();
}

class _TodoCreateSheetState extends State<_TodoCreateSheet> {
  final _titleCtrl = TextEditingController();
  SmartDateParseResult _parsed = SmartDateParseResult.empty;
  late EisenhowerQuadrant _quadrant;
  TodoPriority _priority = TodoPriority.none;
  String _groupName = '';
  bool _aiBusy = false;
  bool _submitting = false;
  List<String> _aiSubtasks = [];
  String? _aiError;
  bool _enableReminder = false;
  TimeOfDay? _reminderTime;

  @override
  void initState() {
    super.initState();
    _quadrant = widget.initialQuadrant ?? EisenhowerQuadrant.notUrgentImportant;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  void _feedback(String message) {
    if (!widget.messenger.mounted) return;
    widget.messenger.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _breakDownTask() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _aiBusy) return;
    final ai = context.read<AiService>();
    setState(() {
      _aiBusy = true;
      _aiError = null;
    });
    try {
      final subtasks = await ai.breakDownTask(title);
      if (mounted) setState(() => _aiSubtasks = subtasks);
    } catch (_) {
      if (mounted) setState(() => _aiError = I18n.tr('todo.create.ai_failed'));
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _save() async {
    if (_submitting || _titleCtrl.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      final todos = context.read<TodoProvider>();
      final shares = context.read<ShareProvider>();
      final auth = context.read<AuthProvider>().state;
      final notifications = context.read<NotificationService?>();
      final workspaceId = _groupName.isEmpty
          ? 'private'
          : todos.workspaceForListGroup(_groupName) ?? 'private';
      if (!shares.canEdit(workspaceId)) {
        _feedback(I18n.tr('todo.create.read_only'));
        return;
      }
      final draft = SmartTodoDraftBuilder.fromText(
        _titleCtrl.text.trim(),
        defaultReminderKind: ReminderKind.push,
      );
      var todo = draft.toTodo(
        quadrant: _quadrant,
        priority: _priority,
        listGroupName: _groupName.isEmpty ? null : _groupName,
        workspaceId: workspaceId,
        createdBy: auth.userId,
        updatedBy: auth.userId,
        subtasks: _aiSubtasks.map((title) => Subtask(title: title)).toList(),
      );
      // Explicitly selected reminder time takes precedence over smart parsing.
      final reminderTime = _reminderTime;
      if (_enableReminder && reminderTime != null) {
        final plan = ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: reminderTime.hour,
              minute: reminderTime.minute,
            ),
          ],
        );
        final legacy = plan.toLegacyReminderConfig(fallback: todo.reminder);
        final now = AppClock.now();
        final base = todo.date;
        var mirroredAt = AppClock.date(
          base.year,
          base.month,
          base.day,
          reminderTime.hour,
          reminderTime.minute,
        );
        if (!mirroredAt.isAfter(now)) {
          mirroredAt = mirroredAt.add(const Duration(days: 1));
        }
        // ignore: deprecated_member_use_from_same_package
        todo = todo.copyWith(
          reminder: legacy,
          reminderPlan: plan,
          hasReminder: true,
          reminderAt: mirroredAt,
        );
      }
      final hasReminder =
          draft.hasReminder || (_enableReminder && reminderTime != null);
      if (hasReminder) {
        bool ready;
        try {
          ready = await preflightTodoReminderSave(
            context,
            todo: todo,
            notificationService: notifications,
            issueTitle: I18n.tr('todo.create.reminder_issue_title'),
          );
        } catch (error, stackTrace) {
          debugPrint(
            '[TodoCreateSheet] reminder preflight failed: $error\n$stackTrace',
          );
          if (mounted) {
            _feedback(
              '${I18n.tr('todo.quick_add.reminder_preflight_failed_prefix')}$error',
            );
          }
          return;
        }
        if (!mounted || !ready) return;
      }
      await todos.addTodo(todo, reportReminderScheduleFailure: hasReminder);
      if (!mounted) return;
      Navigator.pop(
        context,
        _TodoCreateResult(
          hasReminder: hasReminder,
          reminderIssue:
              todos.lastReminderSyncIssue ?? todos.lastReminderScheduleIssue,
        ),
      );
    } on StateError catch (error) {
      if (mounted) {
        _feedback(
          error.message.isEmpty ? I18n.tr('todo.create.failed') : error.message,
        );
      }
    } catch (error) {
      if (mounted) {
        _feedback(
          userVisibleApiError(
            error,
            fallbackMessage: I18n.tr('todo.create.failed'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<ThemeProvider>().brand.strings;
    final aiEnabled = context.watch<AiService>().enabled;
    final cs = Theme.of(context).colorScheme;
    return AppModalSheet(
      key: const ValueKey('todo_create_sheet'),
      title: strings.todoCreateTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppFormFieldTheme(
            child: TextField(
              key: const ValueKey('todo_create_title'),
              controller: _titleCtrl,
              decoration: InputDecoration(
                hintText: I18n.tr('todo.create.hint'),
              ),
              autofocus: true,
              onChanged: (text) =>
                  setState(() => _parsed = SmartDateParser.parse(text)),
            ),
          ),
          if (_parsed.isSuccess) ...[
            const SizedBox(height: 8),
            _SmartDatePreview(parsed: _parsed),
          ],
          if (aiEnabled) ...[
            const SizedBox(height: 12),
            ActionChip(
              avatar: _aiBusy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.auto_awesome, size: 16, color: cs.primary),
              label: Text(I18n.tr('todo.create.ai')),
              onPressed: _aiBusy ? null : _breakDownTask,
            ),
          ],
          if (_aiError != null) ...[
            const SizedBox(height: 8),
            Text(
              _aiError!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ],
          if (_aiSubtasks.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final title in _aiSubtasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.subdirectory_arrow_right,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(title)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 20),
          Text(
            I18n.tr('todo.create.list_type'),
            style: appSecondaryControlLabelStyle(context),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final template in TodoListTemplates.all)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(
                        template.icon,
                        size: 16,
                        color: template.color,
                      ),
                      label: Text(template.name),
                      selected: _groupName == template.name,
                      selectedColor: template.color.withValues(alpha: 0.12),
                      checkmarkColor: template.color,
                      labelStyle: TextStyle(
                        color: _groupName == template.name
                            ? template.color
                            : null,
                      ),
                      onSelected: (selected) => setState(
                        () => _groupName = selected ? template.name : '',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            I18n.tr('todo.create.quadrant'),
            style: appSecondaryControlLabelStyle(context),
          ),
          const SizedBox(height: 12),
          AppDropdownField<EisenhowerQuadrant>(
            key: const ValueKey('todo_create_quadrant'),
            initialValue: _quadrant,
            items: [
              for (final quadrant in EisenhowerQuadrant.values)
                DropdownMenuItem(
                  value: quadrant,
                  child: Text(
                    '${[strings.quadrantQ1Label, strings.quadrantQ2Label, strings.quadrantQ3Label, strings.quadrantQ4Label][quadrant.index]} (Q${quadrant.index + 1})',
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _quadrant = value);
            },
          ),
          const SizedBox(height: 16),
          Text(
            I18n.tr('todo.create.priority'),
            style: appSecondaryControlLabelStyle(context),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (final priority in TodoPriority.values)
                ChoiceChip(
                  label: Text(priority.label),
                  selected: _priority == priority,
                  onSelected: (_) => setState(() => _priority = priority),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            I18n.tr('todo.create.reminder'),
            style: appSecondaryControlLabelStyle(context),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch(
                value: _enableReminder,
                onChanged: (value) => setState(() {
                  _enableReminder = value;
                  if (value && _reminderTime == null) {
                    _reminderTime = TimeOfDay.fromDateTime(AppClock.now());
                  }
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _enableReminder && _reminderTime != null
                      ? '${I18n.tr('todo.create.at_time')} · ${_reminderTime!.format(context)}'
                      : I18n.tr('todo.create.no_reminder'),
                ),
              ),
              if (_enableReminder)
                TextButton.icon(
                  icon: const Icon(Icons.access_time, size: 18),
                  label: Text(_reminderTime!.format(context)),
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _reminderTime!,
                      helpText: I18n.tr('todo.create.pick_time'),
                    );
                    if (mounted && picked != null) {
                      setState(() => _reminderTime = picked);
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(I18n.tr('action.cancel')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('todo_create_submit'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                  onPressed: _submitting ? null : _save,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(I18n.tr('todo.create.submit')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmartDatePreview extends StatelessWidget {
  final SmartDateParseResult parsed;

  const _SmartDatePreview({required this.parsed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${I18n.tr('quick.todo.parsed_prefix')}${I18nDateFormat.smartDate(parsed.dateTime!, includeTime: parsed.hasTimeOfDay)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.primary),
            ),
          ),
        ],
      ),
    );
  }
}
