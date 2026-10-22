import 'dart:async';

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
import '../models/list_group.dart';
import '../providers/auth_provider.dart';
import '../providers/list_group_provider.dart';
import '../providers/notification_service.dart';
import '../providers/share_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/todo_provider.dart';
import '../screens/todo_detail_screen.dart' show preflightTodoReminderSave;
import '../services/account_local_data_cleaner.dart';
import '../services/ai_service.dart';
import '../services/api_client.dart';
import '../services/reminder_scheduler.dart' show preflightTodoReminderPlan;
import 'surface_components.dart';
import 'app_date_picker.dart';
import 'todo_subtask_editor.dart';
import 'todo_list_group_picker.dart';

/// The same full creation form is used by Today, the todo page and its quadrants.
Future<void> showTodoCreateSheet(
  BuildContext context, {
  EisenhowerQuadrant? initialQuadrant,
}) async {
  await context.read<ListGroupProvider?>()?.loadFromStorage();
  if (!context.mounted) return;
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
  final _descriptionCtrl = TextEditingController();
  bool _aiApplied = false;
  bool _titleManuallyChanged = false;
  int _subtasksRevision = 0;
  SmartDateParseResult _parsed = SmartDateParseResult.empty;
  late EisenhowerQuadrant _quadrant;
  String _groupName = '';
  bool _aiBusy = false;
  bool _submitting = false;
  List<Subtask> _subtasks = [];
  String? _aiError;
  bool _enableReminder = false;
  TimeOfDay? _reminderTime;
  DateTime? _reminderDate;
  DateTime? _reminderExactInstant;
  String? _reminderErrorKey;
  late DateTime _referenceNow;
  int _inputRevision = 0;
  DateTime? _aiDateTime;
  bool _aiHasTimeOfDay = false;
  bool _groupManuallyChanged = false;
  bool _quadrantManuallyChanged = false;
  bool _reminderManuallyChanged = false;
  String? _feedbackMessage;
  Timer? _feedbackTimer;

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
    _descriptionCtrl.dispose();
    _feedbackTimer?.cancel();
    super.dispose();
  }

  /// 校验提示必须画在弹窗内部：底部弹窗会盖住页面的 SnackBar。
  void _feedback(String message) {
    if (!mounted) {
      if (widget.messenger.mounted) {
        widget.messenger.showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }
    _feedbackTimer?.cancel();
    setState(() => _feedbackMessage = message);
    _feedbackTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _feedbackMessage = null);
    });
  }

  String get _sourceInput =>
      _aiApplied ? _descriptionCtrl.text : _titleCtrl.text;

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _useAiDate(SmartTodoDraft draft) =>
      _aiDateTime != null &&
      !draft.recurrence.isActive &&
      (!_parsed.isSuccess ||
          (!_parsed.hasTimeOfDay &&
              _aiHasTimeOfDay &&
              _sameDay(_parsed.dateTime!, _aiDateTime!)));

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
          _parsed.hasTimeOfDay || (_useAiDate(draft) && _aiHasTimeOfDay),
    );
  }

  SmartTodoDraft _buildDraft() {
    final draft = SmartTodoDraftBuilder.fromText(
      _sourceInput,
      now: _referenceNow,
      defaultReminderKind: ReminderKind.push,
    );
    final useAiDate = _useAiDate(draft);
    return SmartTodoDraft(
      title: _aiApplied ? _titleCtrl.text.trim() : draft.title,
      date: useAiDate ? _aiDateTime! : draft.date,
      dueDate: useAiDate
          ? (_aiHasTimeOfDay ? _aiDateTime : null)
          : draft.dueDate,
      reminder: useAiDate ? const ReminderConfig.disabled() : draft.reminder,
      reminderPlan: useAiDate
          ? const ReminderPlan.disabled()
          : draft.reminderPlan,
      recurrence: draft.recurrence,
    );
  }

  void _syncAutomaticReminder() {
    if (_reminderManuallyChanged) return;
    final parsed = _effectiveParsed;
    final at = parsed.hasTimeOfDay ? parsed.dateTime : null;
    _enableReminder = at != null && at.isAfter(AppClock.now());
    _reminderDate = parsed.dateTime == null
        ? null
        : AppClock.dateOnly(parsed.dateTime!);
    _reminderTime = at == null ? null : TimeOfDay.fromDateTime(at);
    _reminderExactInstant = at;
    _reminderErrorKey = null;
  }

  void _seedManualReminder() {
    final parsed = _effectiveParsed;
    final seed =
        (parsed.hasTimeOfDay ? parsed.dateTime : null) ??
        AppClock.now().add(const Duration(minutes: 1));
    _reminderDate ??= AppClock.dateOnly(parsed.dateTime ?? seed);
    _reminderTime ??= TimeOfDay.fromDateTime(seed);
    _reminderExactInstant ??= seed;
  }

  DateTime? get _selectedReminderAt {
    final day = _reminderDate;
    final time = _reminderTime;
    if (day == null || time == null) return null;
    final exact = _reminderExactInstant == null
        ? null
        : AppClock.toLocal(_reminderExactInstant!);
    if (exact != null &&
        _sameDay(exact, day) &&
        exact.hour == time.hour &&
        exact.minute == time.minute) {
      // Preserve an explicitly parsed second occurrence during a DST fold.
      return exact;
    }
    return AppClock.date(day.year, day.month, day.day, time.hour, time.minute);
  }

  String? get _selectedReminderError {
    final at = _selectedReminderAt;
    final day = _reminderDate;
    final time = _reminderTime;
    if (at == null || day == null || time == null) {
      return 'todo.create.reminder_required';
    }
    if (!_sameDay(at, day) ||
        at.hour != time.hour ||
        at.minute != time.minute) {
      return 'todo.create.reminder_invalid_time';
    }
    return at.isAfter(AppClock.now()) ? null : 'todo.create.reminder_past';
  }

  Future<void> _pickReminderDate() async {
    final auth = context.read<AuthProvider>();
    final identity = (auth.baseUrl, auth.state.userId);
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    final zone = LocalTimezoneResolver.currentIana;
    final picked = await AppDatePicker.pickSolar(
      context,
      initialDate: _reminderDate ?? AppClock.today(),
      firstDate: AppClock.today(),
      title: I18n.tr('todo.create.pick_date'),
    );
    if (!mounted ||
        picked == null ||
        _submitting ||
        identity != (auth.baseUrl, auth.state.userId) ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation) ||
        zone != LocalTimezoneResolver.currentIana) {
      return;
    }
    setState(() {
      _reminderManuallyChanged = true;
      _reminderDate = AppClock.dateOnly(picked);
      _reminderErrorKey = null;
    });
  }

  Future<void> _pickReminderTime() async {
    final auth = context.read<AuthProvider>();
    final identity = (auth.baseUrl, auth.state.userId);
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    final zone = LocalTimezoneResolver.currentIana;
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime!,
      helpText: I18n.tr('todo.create.pick_time'),
    );
    if (!mounted ||
        picked == null ||
        _submitting ||
        identity != (auth.baseUrl, auth.state.userId) ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(generation) ||
        zone != LocalTimezoneResolver.currentIana) {
      return;
    }
    setState(() {
      _reminderManuallyChanged = true;
      _reminderTime = picked;
      _reminderErrorKey = null;
    });
  }

  void _onTitleChanged(String text) {
    setState(() {
      _inputRevision++;
      _aiError = null;
      if (_aiApplied) {
        _titleManuallyChanged = true;
      } else {
        _referenceNow = AppClock.now();
        _parsed = SmartDateParser.parse(text, now: _referenceNow);
        _aiDateTime = null;
        _aiHasTimeOfDay = false;
        if (_subtasksRevision == 0) _subtasks = [];
        _syncAutomaticReminder();
      }
    });
  }

  void _onDescriptionChanged(String text) {
    setState(() {
      _inputRevision++;
      _referenceNow = AppClock.now();
      _parsed = SmartDateParser.parse(text, now: _referenceNow);
      _aiDateTime = null;
      _aiHasTimeOfDay = false;
      _aiError = null;
      _syncAutomaticReminder();
    });
  }

  void _onTimezoneChanged() {
    if (!mounted) return;
    setState(() {
      _inputRevision++;
      _referenceNow = AppClock.now();
      _parsed = SmartDateParser.parse(_sourceInput, now: _referenceNow);
      _aiDateTime = null;
      _aiHasTimeOfDay = false;
      _reminderExactInstant = null;
      _syncAutomaticReminder();
    });
  }

  ListGroup? _customGroupFor(String name, ListGroupProvider? provider) {
    for (final group in provider?.groups ?? const <ListGroup>[]) {
      if (ListGroupProvider.normalizedName(group.name) ==
          ListGroupProvider.normalizedName(name)) {
        return group;
      }
    }
    return null;
  }

  String _workspaceForListGroup(
    String name,
    TodoProvider todos,
    ListGroupProvider? custom,
  ) =>
      todos.workspaceForListGroup(name) ??
      _customGroupFor(name, custom)?.workspaceId ??
      'private';

  List<String> _editableListGroups(
    TodoProvider todos,
    ShareProvider shares,
    ListGroupProvider? custom,
  ) {
    final names = <String, String>{};
    for (final name in [
      for (final template in TodoListTemplates.all) template.name,
      for (final group in custom?.groups ?? const <ListGroup>[]) group.name,
      ...todos.listGroupNames,
    ]) {
      final clean = name.trim();
      if (clean.isEmpty ||
          !shares.canEdit(_workspaceForListGroup(clean, todos, custom))) {
        continue;
      }
      names.putIfAbsent(ListGroupProvider.normalizedName(clean), () => clean);
    }
    return names.values.toList();
  }

  Future<void> _breakDownTask() async {
    final originalInput = _sourceInput;
    final title = originalInput.trim();
    if (title.isEmpty || _aiBusy || _submitting) return;
    final ai = context.read<AiService>();
    final revision = _inputRevision;
    final subtasksRevision = _subtasksRevision;
    final zone = LocalTimezoneResolver.currentIana;
    final auth = context.read<AuthProvider>();
    final connection = (auth.baseUrl, auth.state.userId);
    final todos = context.read<TodoProvider>();
    final shares = context.read<ShareProvider>();
    final listGroups = _editableListGroups(
      todos,
      shares,
      context.read<ListGroupProvider?>(),
    );
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
        if (!_aiApplied) _descriptionCtrl.text = originalInput;
        if (!_titleManuallyChanged) {
          final suggestedTitle = result.title ?? _buildDraft().title;
          _titleCtrl.value = TextEditingValue(
            text: suggestedTitle,
            selection: TextSelection.collapsed(offset: suggestedTitle.length),
          );
        }
        _aiApplied = true;
        if (subtasksRevision == 0 && subtasksRevision == _subtasksRevision) {
          _subtasks = [
            for (final (index, title) in result.subtasks.indexed)
              Subtask(title: title, sortOrder: index),
          ];
        }
        if (!_groupManuallyChanged &&
            _editableListGroups(
              todos,
              shares,
              context.read<ListGroupProvider?>(),
            ).contains(result.listGroupName)) {
          _groupName = result.listGroupName!;
        }
        if (!_quadrantManuallyChanged && result.quadrant != null) {
          _quadrant = result.quadrant!;
        }
        if (!_parsed.hasTimeOfDay) {
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
    if (_subtasks.any((task) => task.title.trim().isEmpty)) {
      _feedback(I18n.tr('todo.subtask.empty'));
      return;
    }
    if (_enableReminder) {
      final error = _selectedReminderError;
      if (error != null) {
        setState(() => _reminderErrorKey = error);
        return;
      }
    }
    setState(() => _submitting = true);
    try {
      final todos = context.read<TodoProvider>();
      final shares = context.read<ShareProvider>();
      final auth = context.read<AuthProvider>().state;
      final notifications = context.read<NotificationService?>();
      final workspaceId = _groupName.isEmpty
          ? 'private'
          : _workspaceForListGroup(
              _groupName,
              todos,
              context.read<ListGroupProvider?>(),
            );
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
          for (final (index, task) in _subtasks.indexed)
            Subtask(
              id: task.id,
              title: task.title.trim(),
              isCompleted: task.isCompleted,
              sortOrder: index,
            ),
        ],
      );
      // The visible switch is authoritative, including explicit opt-out.
      todo = todo.copyWith(
        listGroupId: _customGroupFor(
          _groupName,
          context.read<ListGroupProvider?>(),
        )?.id,
      );
      todo = todo.copyWith(
        notes: _aiApplied ? _descriptionCtrl.text : '',
        reminder: const ReminderConfig.disabled(),
        reminderPlan: const ReminderPlan.disabled(),
        hasReminder: false,
        reminderAt: null,
      );
      // The displayed date and time form an independent reminder anchor.
      final reminderAt = _enableReminder ? _selectedReminderAt : null;
      if (reminderAt != null) {
        final plan = ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: reminderAt.hour,
              minute: reminderAt.minute,
            ),
          ],
        );
        // ignore: deprecated_member_use_from_same_package
        todo = todo.copyWith(
          reminder: plan.toLegacyReminderConfig(fallback: todo.reminder),
          reminderPlan: plan,
          hasReminder: true,
          reminderAt: reminderAt,
        );
      }
      final hasReminder = reminderAt != null;
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
    final todos = context.watch<TodoProvider>();
    final shares = context.watch<ShareProvider>();
    final custom = context.watch<ListGroupProvider?>();
    final auth = context.watch<AuthProvider>();
    final connection = (auth.baseUrl, auth.state.userId);
    final listGroups = _editableListGroups(todos, shares, custom);
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
              minLines: 1,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: I18n.tr('todo.create.hint'),
                labelText: _aiApplied ? I18n.tr('todo.create.name') : null,
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
          const SizedBox(height: DesignTokens.spaceLg),
          AppFormFieldTheme(
            child: TodoSubtaskEditor(
              key: const ValueKey('todo_create_subtasks'),
              subtasks: _subtasks,
              enabled: !_submitting,
              showCompletion: false,
              onChanged: (items) => setState(() {
                _subtasks = items;
                _subtasksRevision++;
              }),
            ),
          ),
          if (_aiApplied) ...[
            const SizedBox(height: DesignTokens.spaceLg),
            AppFormFieldTheme(
              child: TextField(
                key: const ValueKey('todo_create_description'),
                controller: _descriptionCtrl,
                enabled: !_submitting,
                minLines: 3,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: I18n.tr('todo.create.description'),
                  helperText: I18n.tr('todo.create.description_hint'),
                ),
                onChanged: _onDescriptionChanged,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            I18n.tr('todo.create.list_type'),
            style: appSecondaryControlLabelStyle(context),
          ),
          const SizedBox(height: 12),
          KeyedSubtree(
            key: ValueKey((
              connection,
              custom,
              AccountLocalDataCleaner.accountDataGeneration,
            )),
            child: TodoListGroupPicker(
              key: const ValueKey('todo_list_group_picker'),
              value: _groupName,
              names: listGroups,
              provider: custom,
              enabled: !_submitting,
              canCreate: custom != null && shares.canEdit('private'),
              canManage: (group) => shares.canEdit(group.workspaceId),
              isCurrent: () =>
                  mounted && connection == (auth.baseUrl, auth.state.userId),
              onChanged: (value) => setState(() {
                _groupManuallyChanged = true;
                _groupName = value;
              }),
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
                        _reminderErrorKey = null;
                        if (value) _seedManualReminder();
                      }),
              ),
              const SizedBox(width: DesignTokens.spaceSm),
              Expanded(
                child: Text(
                  I18n.tr(
                    _enableReminder
                        ? 'todo.create.at_time'
                        : 'todo.create.no_reminder',
                  ),
                ),
              ),
            ],
          ),
          if (_enableReminder) ...[
            Wrap(
              spacing: DesignTokens.spaceMd,
              runSpacing: DesignTokens.spaceXs,
              children: [
                TextButton.icon(
                  key: const ValueKey('todo_create_reminder_date'),
                  icon: const Icon(
                    Icons.event_outlined,
                    size: DesignTokens.controlIconSize,
                  ),
                  label: Text(I18nDateFormat.date(_reminderDate!)),
                  onPressed: _submitting ? null : _pickReminderDate,
                ),
                TextButton.icon(
                  key: const ValueKey('todo_create_reminder_time'),
                  icon: const Icon(
                    Icons.access_time,
                    size: DesignTokens.controlIconSize,
                  ),
                  label: Text(_reminderTime!.format(context)),
                  onPressed: _submitting ? null : _pickReminderTime,
                ),
              ],
            ),
            if (_reminderErrorKey != null)
              Padding(
                padding: const EdgeInsets.only(top: DesignTokens.spaceXs),
                child: Text(
                  I18n.tr(_reminderErrorKey!),
                  key: const ValueKey('todo_create_reminder_error'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.error),
                ),
              ),
          ],
          if (_feedbackMessage != null) ...[
            Container(
              key: const ValueKey('todo_create_feedback'),
              width: double.infinity,
              margin: const EdgeInsets.only(top: DesignTokens.spaceMd),
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spaceMd,
                vertical: DesignTokens.spaceSm,
              ),
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                border: Border.all(color: cs.error.withValues(alpha: 0.24)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 18, color: cs.error),
                  const SizedBox(width: DesignTokens.spaceSm),
                  Expanded(
                    child: Text(
                      _feedbackMessage!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: cs.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
