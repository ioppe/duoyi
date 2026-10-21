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
import '../services/ai_service.dart';
import '../services/api_client.dart';
import '../services/reminder_scheduler.dart' show preflightTodoReminderPlan;
import 'surface_components.dart';
import 'todo_subtask_editor.dart';

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
  late DateTime _referenceNow;
  int _inputRevision = 0;
  DateTime? _aiDateTime;
  bool _aiHasTimeOfDay = false;
  bool _groupManuallyChanged = false;
  bool _quadrantManuallyChanged = false;
  bool _reminderManuallyChanged = false;
  final _newListCtrl = TextEditingController();
  final _newListFocus = FocusNode();
  bool _creatingList = false;

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
    _newListCtrl.dispose();
    _newListFocus.dispose();
    super.dispose();
  }

  void _feedback(String message) {
    if (!widget.messenger.mounted) return;
    // 连续校验失败时直接替换上一条提示，避免排队等待 4 秒。
    widget.messenger.hideCurrentSnackBar();
    widget.messenger.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  String get _sourceInput =>
      _aiApplied ? _descriptionCtrl.text : _titleCtrl.text;

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
      _sourceInput,
      now: _referenceNow,
      defaultReminderKind: ReminderKind.push,
    );
    final useAiDate =
        !_parsed.isSuccess && !draft.recurrence.isActive && _aiDateTime != null;
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
    _reminderTime = at == null ? null : TimeOfDay.fromDateTime(at);
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

  /// 重命名仍用对话框（低频、需要确认原文）；新建改成就地输入 + 补全。
  Future<void> _renameListGroup(ListGroup group) async {
    final provider = context.read<ListGroupProvider?>();
    if (provider == null || _submitting) return;
    final todos = context.read<TodoProvider>();
    final shares = context.read<ShareProvider>();
    if (!shares.canEdit(group.workspaceId)) return;
    final auth = context.read<AuthProvider>();
    final connection = (auth.baseUrl, auth.state.userId);
    final result = await showDialog<ListGroup>(
      context: context,
      builder: (_) => _ListGroupNameDialog(
        provider: provider,
        group: group,
        otherNames: [
          for (final name in [
            for (final template in TodoListTemplates.all) template.name,
            ...todos.listGroupNames,
          ])
            if (ListGroupProvider.normalizedName(name) !=
                ListGroupProvider.normalizedName(group.name))
              name,
        ],
        isCurrent: () => connection == (auth.baseUrl, auth.state.userId),
      ),
    );
    if (!mounted ||
        result == null ||
        connection != (auth.baseUrl, auth.state.userId)) {
      return;
    }
    setState(() {
      if (_groupName == group.name) {
        _groupName = result.name;
        _groupManuallyChanged = true;
      }
    });
  }

  void _startCreateList() {
    setState(() {
      _creatingList = true;
      _newListCtrl.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _creatingList) _newListFocus.requestFocus();
    });
  }

  void _cancelCreateList() {
    if (!_creatingList) return;
    _newListFocus.unfocus();
    setState(() {
      _creatingList = false;
      _newListCtrl.clear();
    });
  }

  void _selectListName(String name) {
    _newListFocus.unfocus();
    setState(() {
      _groupName = name;
      _groupManuallyChanged = true;
      _creatingList = false;
      _newListCtrl.clear();
    });
  }

  /// 输入时优先补全“开头匹配”，其次“包含匹配”，方便直接选中已有清单。
  List<String> _listGroupMatches(List<String> names, String query) {
    final q = ListGroupProvider.normalizedName(query);
    if (q.isEmpty) return names.take(8).toList(growable: false);
    final startsWith = <String>[];
    final contains = <String>[];
    for (final name in names) {
      final lower = ListGroupProvider.normalizedName(name);
      if (lower == q) continue;
      if (lower.startsWith(q)) {
        startsWith.add(name);
      } else if (lower.contains(q)) {
        contains.add(name);
      }
    }
    return [...startsWith, ...contains].take(8).toList(growable: false);
  }

  Future<void> _submitNewList(
    ListGroupProvider provider,
    List<String> names,
  ) async {
    final raw = _newListCtrl.text.trim();
    final normalized = ListGroupProvider.normalizedName(raw);
    for (final name in names) {
      if (ListGroupProvider.normalizedName(name) == normalized) {
        _selectListName(name);
        return;
      }
    }
    final error = provider.validateName(raw, otherNames: names);
    if (error != null) {
      _feedback(I18n.tr(error));
      return;
    }
    try {
      final created = await provider.create(raw, provider.nextSortOrder);
      if (!mounted) return;
      _selectListName(created.name);
    } on ListGroupNameException catch (error) {
      if (mounted) _feedback(I18n.tr(error.messageKey));
    } catch (_) {
      if (mounted) _feedback(I18n.tr('list_group.save_failed'));
    }
  }

  Future<void> _showListGroupMenu(
    ListGroup group,
    LongPressStartDetails details,
  ) async {
    final auth = context.read<AuthProvider>();
    final connection = (auth.baseUrl, auth.state.userId);
    final provider = context.read<ListGroupProvider?>();
    final shares = context.read<ShareProvider>();
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = overlay.globalToLocal(details.globalPosition);
    final action = await showMenu<_ListGroupAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: _ListGroupAction.rename,
          child: Text(I18n.tr('list_group.rename')),
        ),
        PopupMenuItem(
          value: _ListGroupAction.delete,
          child: Text(I18n.tr('action.delete')),
        ),
      ],
    );
    if (!mounted ||
        action == null ||
        provider == null ||
        connection != (auth.baseUrl, auth.state.userId) ||
        !shares.canEdit(group.workspaceId)) {
      return;
    }
    if (action == _ListGroupAction.rename) {
      await _renameListGroup(group);
    } else {
      try {
        await provider.delete(group.id);
        if (mounted && connection == (auth.baseUrl, auth.state.userId)) {
          setState(() {
            if (_groupName == group.name) {
              _groupName = '';
              _groupManuallyChanged = true;
            }
          });
        }
      } catch (_) {
        if (mounted) _feedback(I18n.tr('list_group.save_failed'));
      }
    }
  }

  /// 新建入口固定在最左侧：默认是一枚 chip，点击后就地变成输入框。
  Widget _listGroupCreateEntry(
    ListGroupProvider provider,
    List<String> names,
    ColorScheme cs,
  ) {
    if (!_creatingList) {
      return Padding(
        padding: const EdgeInsets.only(right: DesignTokens.spaceSm),
        child: ActionChip(
          key: const ValueKey('todo_list_group_create'),
          avatar: Icon(
            Icons.add,
            size: DesignTokens.spaceLg,
            color: cs.primary,
          ),
          label: Text(I18n.tr('list_group.new_chip')),
          onPressed: _submitting ? null : _startCreateList,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: DesignTokens.spaceSm),
      child: SizedBox(
        width: 232,
        child: TextField(
          key: const ValueKey('todo_list_group_input'),
          controller: _newListCtrl,
          focusNode: _newListFocus,
          autofocus: true,
          enabled: !_submitting,
          textInputAction: TextInputAction.done,
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: InputDecoration(
            isDense: true,
            hintText: I18n.tr('list_group.create_hint'),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceMd,
              vertical: DesignTokens.spaceSm,
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const ValueKey('todo_list_group_create_confirm'),
                  tooltip: I18n.tr('list_group.new'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  iconSize: 18,
                  icon: const Icon(Icons.check),
                  onPressed: _submitting
                      ? null
                      : () => _submitNewList(provider, names),
                ),
                IconButton(
                  key: const ValueKey('todo_list_group_create_cancel'),
                  tooltip: I18n.tr('action.cancel'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  iconSize: 18,
                  icon: const Icon(Icons.close),
                  onPressed: _submitting ? null : _cancelCreateList,
                ),
              ],
            ),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submitNewList(provider, names),
        ),
      ),
    );
  }

  /// 输入时就地列出最相关的已有清单，直接点选即可，不必新建重名清单。
  Widget _listGroupSuggestions(
    ListGroupProvider provider,
    List<String> names,
    ColorScheme cs,
  ) {
    final matches = _listGroupMatches(names, _newListCtrl.text);
    if (matches.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: DesignTokens.spaceSm),
      child: Wrap(
        spacing: DesignTokens.spaceSm,
        runSpacing: DesignTokens.spaceXs,
        children: [
          for (final name in matches)
            ActionChip(
              key: ValueKey('todo_list_group_suggestion_$name'),
              avatar: Icon(
                Icons.folder_outlined,
                size: DesignTokens.spaceLg,
                color: cs.primary,
              ),
              label: Text(name),
              onPressed: _submitting ? null : () => _selectListName(name),
            ),
        ],
      ),
    );
  }

  Widget _listGroupChip(
    String name,
    ListGroupProvider? custom,
    ColorScheme cs,
  ) {
    TodoListTemplate? builtIn;
    for (final item in TodoListTemplates.all) {
      if (item.name == name) builtIn = item;
    }
    final template =
        builtIn ??
        TodoListTemplate(
          name: name,
          icon: Icons.folder_outlined,
          color: cs.primary,
        );
    final group = _customGroupFor(name, custom);
    return Padding(
      padding: const EdgeInsets.only(right: DesignTokens.spaceSm),
      child: GestureDetector(
        onLongPressStart: group != null && builtIn == null && !_submitting
            ? (details) => _showListGroupMenu(group, details)
            : null,
        child: ChoiceChip(
          key: ValueKey('todo_list_group_$name'),
          avatar: Icon(
            template.icon,
            size: DesignTokens.spaceLg,
            color: template.color,
          ),
          label: Text(name),
          selected: _groupName == name,
          selectedColor: template.color.withValues(alpha: 0.12),
          checkmarkColor: template.color,
          labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: _groupName == name ? template.color : null,
          ),
          onSelected: _submitting
              ? null
              : (selected) => setState(() {
                  _groupManuallyChanged = true;
                  _groupName = selected ? name : '';
                }),
        ),
      ),
    );
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
    if (_subtasks.any((task) => task.title.trim().isEmpty)) {
      _feedback(I18n.tr('todo.subtask.empty'));
      return;
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
    final todos = context.watch<TodoProvider>();
    final shares = context.watch<ShareProvider>();
    final custom = context.watch<ListGroupProvider?>();
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
          SizedBox(
            height: DesignTokens.controlMinHeight,
            child: ListView(
              key: const ValueKey('todo_list_groups'),
              scrollDirection: Axis.horizontal,
              children: [
                if (custom != null && shares.canEdit('private'))
                  _listGroupCreateEntry(custom, listGroups, cs),
                for (final name in listGroups) _listGroupChip(name, custom, cs),
              ],
            ),
          ),
          if (_creatingList && custom != null)
            _listGroupSuggestions(custom, listGroups, cs),
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

enum _ListGroupAction { rename, delete }

class _ListGroupNameDialog extends StatefulWidget {
  final ListGroupProvider provider;
  final ListGroup group;
  final List<String> otherNames;
  final bool Function() isCurrent;

  const _ListGroupNameDialog({
    required this.provider,
    required this.group,
    required this.otherNames,
    required this.isCurrent,
  });

  @override
  State<_ListGroupNameDialog> createState() => _ListGroupNameDialogState();
}

class _ListGroupNameDialogState extends State<_ListGroupNameDialog> {
  late final _controller = TextEditingController(text: widget.group.name);
  String? _errorKey;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final error = widget.isCurrent()
        ? widget.provider.validateName(
            _controller.text,
            excludingId: widget.group.id,
            otherNames: widget.otherNames,
          )
        : 'auth.connection_changed';
    if (error != null) {
      setState(() => _errorKey = error);
      return;
    }
    setState(() {
      _saving = true;
      _errorKey = null;
    });
    try {
      final result = await widget.provider.rename(
        widget.group.id,
        _controller.text,
      );
      if (mounted) Navigator.pop(context, result);
    } on ListGroupNameException catch (error) {
      if (mounted) setState(() => _errorKey = error.messageKey);
    } catch (_) {
      if (mounted) setState(() => _errorKey = 'list_group.save_failed');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: Text(I18n.tr('list_group.rename')),
    contentPadding: DesignTokens.dialogContentPadding,
    content: AppFormFieldTheme(
      child: TextField(
        key: const ValueKey('list_group_name'),
        controller: _controller,
        autofocus: true,
        enabled: !_saving,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: I18n.tr('list_group.name'),
          helperText: I18n.tr('list_group.name_hint'),
          errorText: _errorKey == null ? null : I18n.tr(_errorKey!),
          errorMaxLines: 3,
        ),
        onChanged: (_) => setState(() => _errorKey = null),
        onSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: Text(I18n.tr('action.cancel')),
      ),
      FilledButton(
        key: const ValueKey('list_group_confirm'),
        onPressed: _saving ? null : _submit,
        child: Text(I18n.tr('action.confirm')),
      ),
    ],
  );
}
