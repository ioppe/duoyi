import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_clock.dart';
import '../core/design_tokens.dart';
import '../core/local_timezone_resolver.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/smart_date_parser.dart';
import '../core/smart_todo_draft.dart';
import '../core/todo_templates.dart';
import '../core/web_target.dart';
import '../models/goal.dart'
    show
        ReminderConfig,
        ReminderKind,
        ReminderPlan,
        ReminderRule,
        ReminderRuleType;
import '../models/todo.dart';
import '../providers/auth_provider.dart';
import '../providers/notification_service.dart';
import '../providers/share_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/todo_provider.dart';
import '../screens/todo_detail_screen.dart' show preflightTodoReminderSave;
import '../services/ai_service.dart';
import '../services/api_client.dart';
import '../services/reminder_scheduler.dart' show preflightTodoReminderPlan;
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
  final message = result.hasReminder && WebTarget.isWebBuild
      ? I18n.tr('todo.create.created_web_reminder')
      : result.hasReminder && result.reminderIssue != null
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
  String _groupName = '';
  bool _aiBusy = false;
  bool _submitting = false;
  List<String> _aiSubtasks = [];
  String? _aiError;
  bool _enableReminder = false;
  TimeOfDay? _reminderTime;
  late DateTime _referenceNow;
  int _inputRevision = 0;
  DateTime? _aiDateTime;
  bool _aiHasTimeOfDay = false;
  bool _groupManuallyChanged = false;
  bool _quadrantManuallyChanged = false;
  bool _reminderManuallyChanged = false;

  @override
  void initState() {
    super.initState();
    _quadrant = widget.initialQuadrant ?? EisenhowerQuadrant.notUrgentImportant;
    _quadrantManuallyChanged = widget.initialQuadrant != null;
    _referenceNow = AppClock.now();
    LocalTimezoneResolver.timezoneListenable.addListener(_onTimezoneChanged);
  }

  @override
  void dispose() {
    LocalTimezoneResolver.timezoneListenable.removeListener(_onTimezoneChanged);
    _titleCtrl.dispose();
    super.dispose();
  }

  void _feedback(String message) {
    if (!widget.messenger.mounted) return;
    widget.messenger.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  SmartDateParseResult get _effectiveParsed {
    final draft = _buildDraft();
    if (!_parsed.isSuccess &&
        !draft.recurrence.isActive &&
        _aiDateTime == null) {
      return SmartDateParseResult.empty;
    }
    return SmartDateParseResult(
      dateTime: draft.date,
      matchedText: _parsed.matchedText,
      hasTimeOfDay:
          _parsed.hasTimeOfDay || (!_parsed.isSuccess && _aiHasTimeOfDay),
    );
  }

  SmartTodoDraft _buildDraft() {
    final draft = SmartTodoDraftBuilder.fromText(
      _titleCtrl.text.trim(),
      now: _referenceNow,
      defaultReminderKind: ReminderKind.push,
    );
    if (_parsed.isSuccess || _aiDateTime == null) return draft;
    return SmartTodoDraft(
      title: draft.title,
      date: _aiDateTime!,
      dueDate: _aiHasTimeOfDay ? _aiDateTime : null,
      reminder: const ReminderConfig.disabled(),
      reminderPlan: const ReminderPlan.disabled(),
      recurrence: draft.recurrence,
    );
  }

  void _syncAutomaticReminder() {
    if (_reminderManuallyChanged) return;
    final parsed = _effectiveParsed;
    final at = parsed.hasTimeOfDay ? parsed.dateTime : null;
    _enableReminder = at != null && at.isAfter(AppClock.now());
    _reminderTime = at == null ? null : TimeOfDay.fromDateTime(at);
  }

  void _onTitleChanged(String text) {
    setState(() {
      _inputRevision++;
      _referenceNow = AppClock.now();
      _parsed = SmartDateParser.parse(text, now: _referenceNow);
      _aiDateTime = null;
      _aiHasTimeOfDay = false;
      _aiSubtasks = [];
      _aiError = null;
      _syncAutomaticReminder();
    });
  }

  void _onTimezoneChanged() {
    if (!mounted) return;
    setState(() {
      _inputRevision++;
      _referenceNow = AppClock.now();
      _parsed = SmartDateParser.parse(_titleCtrl.text, now: _referenceNow);
      _aiDateTime = null;
      _aiHasTimeOfDay = false;
      _syncAutomaticReminder();
    });
  }

  Future<void> _breakDownTask() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _aiBusy || _submitting) return;
    final ai = context.read<AiService>();
    final revision = _inputRevision;
    final zone = LocalTimezoneResolver.currentIana;
    final auth = context.read<AuthProvider>();
    final connection = (auth.baseUrl, auth.state.userId);
    final todos = context.read<TodoProvider>();
    final shares = context.read<ShareProvider>();
    final listGroups = [
      for (final template in TodoListTemplates.all)
        if (shares.canEdit(
          todos.workspaceForListGroup(template.name) ?? 'private',
        ))
          template.name,
    ];
    bool isCurrent() =>
        mounted &&
        revision == _inputRevision &&
        zone == LocalTimezoneResolver.currentIana &&
        connection == (auth.baseUrl, auth.state.userId);
    setState(() {
      _aiBusy = true;
      _aiError = null;
    });
    try {
      final result = await ai.breakDownTodo(
        title,
        listGroups: listGroups,
        now: _referenceNow,
      );
      if (!isCurrent()) return;
      setState(() {
        _aiSubtasks = result.subtasks;
        if (!_groupManuallyChanged &&
            listGroups.contains(result.listGroupName)) {
          _groupName = result.listGroupName!;
        }
        if (!_quadrantManuallyChanged && result.quadrant != null) {
          _quadrant = result.quadrant!;
        }
        if (!_parsed.isSuccess) {
          _aiDateTime = result.dateTime;
          _aiHasTimeOfDay = result.hasTimeOfDay;
        }
        _syncAutomaticReminder();
      });
    } catch (_) {
      if (isCurrent()) {
        setState(() => _aiError = I18n.tr('todo.create.ai_failed'));
      }
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _save() async {
    if (_submitting || _aiBusy || _titleCtrl.text.trim().isEmpty) return;
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
      final draft = _buildDraft();
      var todo = draft.toTodo(
        quadrant: _quadrant,
        listGroupName: _groupName.isEmpty ? null : _groupName,
        workspaceId: workspaceId,
        createdBy: auth.userId,
        updatedBy: auth.userId,
        subtasks: [
          for (final (index, title) in _aiSubtasks.indexed)
            Subtask(title: title, sortOrder: index),
        ],
      );
      // The visible switch is authoritative, including explicit opt-out.
      todo = todo.copyWith(
        reminder: const ReminderConfig.disabled(),
        reminderPlan: const ReminderPlan.disabled(),
        hasReminder: false,
        reminderAt: null,
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
        var mirroredAt =
            _effectiveParsed.hasTimeOfDay &&
                base.hour == reminderTime.hour &&
                base.minute == reminderTime.minute
            ? base
            : AppClock.date(
                base.year,
                base.month,
                base.day,
                reminderTime.hour,
                reminderTime.minute,
              );
        if (!_effectiveParsed.isSuccess && !mirroredAt.isAfter(now)) {
          mirroredAt = AppClock.date(
            base.year,
            base.month,
            base.day + 1,
            reminderTime.hour,
            reminderTime.minute,
          );
        }
        // ignore: deprecated_member_use_from_same_package
        todo = todo.copyWith(
          reminder: legacy,
          reminderPlan: plan,
          hasReminder: true,
          reminderAt: mirroredAt,
        );
      }
      final hasReminder = _enableReminder && reminderTime != null;
      if (hasReminder && WebTarget.isWebBuild) {
        final blocking = preflightTodoReminderPlan(todo).blockingIssue;
        if (blocking != null) {
          _feedback('${blocking.title}：${blocking.message}');
          return;
        }
      }
      if (hasReminder && !WebTarget.isWebBuild) {
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
    final parsed = _effectiveParsed;
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
              enabled: !_submitting,
              onChanged: _onTitleChanged,
            ),
          ),
          if (parsed.isSuccess) ...[
            const SizedBox(height: 8),
            _SmartDatePreview(parsed: parsed),
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
              onPressed: _aiBusy || _submitting ? null : _breakDownTask,
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
                      onSelected: _submitting
                          ? null
                          : (selected) => setState(() {
                              _groupManuallyChanged = true;
                              _groupName = selected ? template.name : '';
                            }),
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
          KeyedSubtree(
            key: ValueKey('todo_create_quadrant_value_${_quadrant.index}'),
            child: AppDropdownField<EisenhowerQuadrant>(
              key: const ValueKey('todo_create_quadrant'),
              initialValue: _quadrant,
              enabled: !_submitting,
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
                if (value != null) {
                  setState(() {
                    _quadrantManuallyChanged = true;
                    _quadrant = value;
                  });
                }
              },
            ),
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
                key: const ValueKey('todo_create_reminder'),
                value: _enableReminder,
                onChanged: _submitting
                    ? null
                    : (value) => setState(() {
                        _reminderManuallyChanged = true;
                        _enableReminder = value;
                        if (value && _reminderTime == null) {
                          _reminderTime = TimeOfDay.fromDateTime(
                            parsed.dateTime ?? AppClock.now(),
                          );
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
                  onPressed: _submitting
                      ? null
                      : () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _reminderTime!,
                            helpText: I18n.tr('todo.create.pick_time'),
                          );
                          if (mounted && picked != null) {
                            setState(() {
                              _reminderManuallyChanged = true;
                              _reminderTime = picked;
                            });
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
                  onPressed: _submitting || _aiBusy ? null : _save,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${I18n.tr('quick.todo.parsed_prefix')}${I18nDateFormat.smartDate(parsed.dateTime!, includeTime: parsed.hasTimeOfDay)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.primary),
                ),
                const SizedBox(height: DesignTokens.spaceXs),
                Text(
                  '${I18n.tr('todo.create.timezone')} ${LocalTimezoneResolver.currentIana}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
