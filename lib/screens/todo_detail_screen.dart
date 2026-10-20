import '../core/app_clock.dart';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../models/goal.dart' show ReminderKind, ReminderPlan;
import '../models/location_reminder.dart';
import '../models/note.dart' show NoteAttachment, NoteBlock, NoteBlockType;
import '../models/todo.dart';
import '../models/workspace.dart';
import '../services/api_client.dart';
import '../services/alarm_service.dart';
import '../services/local_notifications.dart';
import '../services/note_attachment_picker.dart';
import '../services/reminder_scheduler.dart';
import '../providers/location_reminder_provider.dart';
import '../providers/notification_service.dart';
import '../providers/share_provider.dart';
import '../providers/todo_provider.dart';
import '../widgets/recurrence_picker.dart';
import '../widgets/reminder_health_hint.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/reminder_plan_editor.dart';
import '../widgets/surface_components.dart';

/// Todo 详情页 / 编辑页。
///
/// Todo 详情页 / 编辑页状态机。
///
/// - `_EditState` 四档：`clean / editing / saving / confirmDiscard`；
/// - AppBar 的 check 按钮保存成功后返回上一页；
/// - 返回键在 `editing` 下会弹"放弃修改"对话框；
/// - 用 `PopScope` + `onPopInvoked` 统一拦截路由 pop，`Clean` 状态直接放行。
///
/// 同时保留 Task 7 的视觉对齐：token 化间距 / 圆角、优先级 ChoiceChip、提醒
/// 分段、目标时长模块、标签 / 子任务 / 重复 / 截止日 等模块。
class TodoDetailScreen extends StatefulWidget {
  final String todoId;

  const TodoDetailScreen({super.key, required this.todoId});

  @override
  State<TodoDetailScreen> createState() => _TodoDetailScreenState();
}

/// "保存不返回" 状态机的四档状态。
///
/// - `clean`    ：与基线一致，无未保存改动；返回键直接 pop；
/// - `editing`  ：至少有一处与基线不同，点击保存会 → `saving`，点击返回会
///                → `confirmDiscard`；
/// - `saving`   ：正在写入 provider / 持久化；期间不应再触发另一次保存；
/// - `confirmDiscard`：正在展示"放弃修改"对话框，用户选择后回到
///                `editing`（取消）或 `clean` → pop（放弃）。
enum _EditState { clean, editing, saving, confirmDiscard }

class _TodoDetailScreenState extends State<TodoDetailScreen> {
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _subtaskCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final _timeTargetCtrl = TextEditingController();
  late TodoItem _todo;
  bool _missingTodo = false;
  bool _notesPreview = false;
  bool _subtaskAdding = false;
  final Set<String> _busySubtaskIds = <String>{};
  String? _commentsLoadedForWorkspaceId;

  /// "保存不返回"状态机当前状态。
  _EditState _state = _EditState.clean;

  /// 基线快照：`_load()` 与成功保存后都会刷新。任何与基线偏离的改动
  /// 都会把状态抬升到 `editing`。用 JSON 化的字符串表示，避免深比较。
  late String _baseline;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 把当前 `_todo` + 文本控制器中的可编辑字段序列化为快照字符串。
  ///
  /// 这里只关心"UI 可编辑"的字段，不包括 `createdAt / id / sortOrder` 等
  /// 由系统维护的元字段，也不包括 `subtasks` 的完成状态（子任务勾选会直接
  /// 调 provider，不走本页的 save 路径）。
  String _snapshot(TodoItem t) {
    final tags = [...t.tags]..sort();
    return <String, dynamic>{
      'title': _titleCtrl.text.trim(),
      'notes': _notesCtrl.text.trim(),
      'quadrant': t.quadrant.index,
      'priority': t.priority.index,
      'listGroupId': t.listGroupId,
      'tags': tags,
      'dueDate': t.dueDate?.toIso8601String(),
      'reminderPlan': t.reminderPlan.toJson(),
      'focusLink': t.focusLink.toJson(),
      'timeTargetSeconds': t.timeTargetSeconds,
      'recurrence': t.recurrence.toJson(),
      'autoToggleByChildren': t.autoToggleByChildren,
      'workspaceId': t.workspaceId,
      'assigneeId': t.assigneeId,
      'attachments': t.attachments.map((a) => a.toJson()).toList(),
    }.toString();
  }

  bool _reminderSchedulingFieldsChanged(TodoItem before, TodoItem after) {
    // ignore: deprecated_member_use_from_same_package
    final beforeHasReminder = before.hasReminder;
    // ignore: deprecated_member_use_from_same_package
    final afterHasReminder = after.hasReminder;
    // ignore: deprecated_member_use_from_same_package
    final beforeReminderAt = before.reminderAt;
    // ignore: deprecated_member_use_from_same_package
    final afterReminderAt = after.reminderAt;
    final legacyChanged =
        beforeHasReminder != afterHasReminder ||
        beforeReminderAt != afterReminderAt;
    return before.dueDate != after.dueDate ||
        legacyChanged ||
        before.reminder.toJson().toString() !=
            after.reminder.toJson().toString() ||
        before.reminderPlan.toJson().toString() !=
            after.reminderPlan.toJson().toString();
  }

  void _load() {
    final provider = context.read<TodoProvider>();
    final matches = provider.todos.where((t) => t.id == widget.todoId);
    if (matches.isEmpty) {
      _todo = TodoItem(id: widget.todoId, title: '');
      _baseline = '';
      _missingTodo = true;
      _state = _EditState.clean;
      return;
    }
    final todo = matches.first;
    _missingTodo = false;
    _syncDraftFromProvider(todo);
    _baseline = _snapshot(_todo);
    _state = _EditState.clean;
  }

  void _syncDraftFromProvider(TodoItem todo) {
    _todo = todo;
    if (_titleCtrl.text != todo.title) {
      _titleCtrl.text = todo.title;
    }
    if (_notesCtrl.text != todo.notes) {
      _notesCtrl.text = todo.notes;
    }
    final sec = todo.timeTargetSeconds;
    final minutesText = sec != null && sec > 0 ? (sec ~/ 60).toString() : '';
    if (_timeTargetCtrl.text != minutesText) {
      _timeTargetCtrl.text = minutesText;
    }
  }

  /// 任一可编辑字段变动时调用；根据是否偏离基线切换状态。
  ///
  /// - 若当前已经是 `saving`，保持不动（在途保存不应被抢占）；
  /// - 若当前与基线一致，回到 `clean`；否则升到 `editing`。
  void _markEditing() {
    if (_state == _EditState.saving) return;
    final dirty = _snapshot(_todo) != _baseline;
    final next = dirty ? _EditState.editing : _EditState.clean;
    if (_state != next) {
      setState(() => _state = next);
    }
  }

  /// 保存当前编辑结果。
  ///
  /// - `clean`：不触发任何写入，直接返回上一页；
  /// - 其他状态：`_state = saving` → `updateTodo` → 成功回到 `clean`
  ///   并刷新基线后返回上一页；失败回到 `editing`
  ///   并展示错误 snackbar。
  ///
  Future<void> _save() async {
    if (_state == _EditState.saving) return;
    if (!(context.read<ShareProvider?>()?.canEdit(_todo.workspaceId) ?? true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('你在这个共享空间中只有查看权限'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 同步基线检查：用户点了 check 但什么也没改 → 轻量反馈、不打扰。
    if (_state == _EditState.clean) {
      Navigator.of(context).maybePop();
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<TodoProvider>();
    final cs = Theme.of(context).colorScheme;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('任务名称不能为空'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: cs.error,
        ),
      );
      return;
    }

    final nextTodo = _todo.copyWith(
      title: title,
      notes: _notesCtrl.text.trim(),
    );
    setState(() => _state = _EditState.saving);

    try {
      final savedTodo = provider.todos.firstWhere(
        (t) => t.id == widget.todoId,
        orElse: () => _todo,
      );
      if (_reminderSchedulingFieldsChanged(savedTodo, nextTodo)) {
        final reminderReady = await preflightTodoReminderSave(
          context,
          todo: nextTodo,
          notificationService: context.read<NotificationService?>(),
          issueTitle: '待办提醒注册失败',
        );
        if (!mounted) return;
        if (!reminderReady) {
          _restoreEditingAfterSaveInterruption();
          return;
        }
      }
      await provider.updateTodo(widget.todoId, nextTodo);
      if (!mounted) return;

      // 刷新本地 _todo 引用与基线，便于继续编辑。
      _todo = provider.todos.firstWhere(
        (t) => t.id == widget.todoId,
        orElse: () => _todo,
      );
      _baseline = _snapshot(_todo);
      setState(() => _state = _EditState.clean);

      Navigator.of(context).maybePop(true);
    } catch (e) {
      if (!mounted) return;
      _restoreEditingAfterSaveInterruption();
      messenger.showSnackBar(
        SnackBar(
          content: Text('保存失败：${userVisibleApiError(e)}'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: cs.error,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _restoreEditingAfterSaveInterruption() {
    if (!mounted || _state != _EditState.saving) return;
    setState(() => _state = _EditState.editing);
  }

  /// 用户尝试返回时（系统返回键 / AppBar 返回按钮）。
  ///
  /// - `editing`：转到 `confirmDiscard` 并弹确认框；
  ///   - "放弃"：重置为 `clean` 后允许路由 pop；
  ///   - "取消"：保持 `editing`，不 pop。
  /// - 其他状态：放行。
  ///
  /// 返回 `true` 表示"允许 pop"，返回 `false` 表示"拦截"。
  Future<bool> _handleBack() async {
    if (_state == _EditState.saving) {
      // 正在保存期间不允许离开页面，避免 provider 写入与 pop 竞态。
      return false;
    }
    if (_state != _EditState.editing) return true;

    setState(() => _state = _EditState.confirmDiscard);
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AppDialog(
        title: const Text('放弃未保存的修改？'),
        content: const Text('当前修改尚未保存，返回将丢弃这些改动。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (!mounted) return false;

    if (discard == true) {
      setState(() => _state = _EditState.clean);
      return true;
    }
    setState(() => _state = _EditState.editing);
    return false;
  }

  Future<void> _addSubtask() async {
    if (_subtaskAdding) return;
    if (!(context.read<ShareProvider?>()?.canEdit(_todo.workspaceId) ?? true)) {
      return;
    }
    final title = _subtaskCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _subtaskAdding = true);
    try {
      await context.read<TodoProvider>().addSubtask(widget.todoId, title);
      if (!mounted) return;
      _subtaskCtrl.clear();
      _refreshTodoBaseline();
    } finally {
      if (mounted) {
        setState(() => _subtaskAdding = false);
      }
    }
  }

  void _refreshTodoBaseline() {
    setState(() {
      _todo = context.read<TodoProvider>().todos.firstWhere(
        (t) => t.id == widget.todoId,
        orElse: () => _todo,
      );
      _baseline = _snapshot(_todo);
    });
  }

  Future<void> _toggleSubtask(String subtaskId) async {
    if (!_busySubtaskIds.add(subtaskId)) return;
    setState(() {});
    try {
      await context.read<TodoProvider>().toggleSubtask(
        widget.todoId,
        subtaskId,
      );
      if (!mounted) return;
      _refreshTodoBaseline();
    } finally {
      if (mounted) {
        setState(() => _busySubtaskIds.remove(subtaskId));
      }
    }
  }

  Future<void> _deleteSubtask(String subtaskId) async {
    if (!_busySubtaskIds.add(subtaskId)) return;
    setState(() {});
    try {
      await context.read<TodoProvider>().deleteSubtask(
        widget.todoId,
        subtaskId,
      );
      if (!mounted) return;
      _refreshTodoBaseline();
    } finally {
      if (mounted) {
        setState(() => _busySubtaskIds.remove(subtaskId));
      }
    }
  }

  void _addTag(String v) {
    final value = v.trim();
    if (value.isEmpty) return;
    if (_todo.tags.contains(value)) return;
    setState(() {
      _todo = _todo.copyWith(tags: [..._todo.tags, value]);
      _tagCtrl.clear();
    });
    _markEditing();
  }

  void _removeTag(String tag) {
    setState(() {
      _todo = _todo.copyWith(tags: _todo.tags.where((x) => x != tag).toList());
    });
    _markEditing();
  }

  Future<void> _addAttachment() async {
    final picked = await NoteAttachmentPicker.pickFile();
    if (!mounted || picked == null) return;
    setState(() {
      _todo = _todo.copyWith(attachments: [..._todo.attachments, picked]);
    });
    _markEditing();
  }

  void _addManualAttachment(NoteAttachment attachment) {
    setState(() {
      _todo = _todo.copyWith(attachments: [..._todo.attachments, attachment]);
    });
    _markEditing();
  }

  Future<void> _showManualAttachmentDialog() async {
    final nameCtrl = TextEditingController();
    final uriCtrl = TextEditingController();
    final mimeCtrl = TextEditingController();
    final attachment = await showDialog<NoteAttachment>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('添加附件链接'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: '名称'),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: uriCtrl,
              decoration: const InputDecoration(labelText: '链接或本地路径'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: mimeCtrl,
              decoration: const InputDecoration(labelText: '类型（可选）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            onPressed: () {
              final uri = uriCtrl.text.trim();
              if (uri.isEmpty) return;
              Navigator.pop(
                ctx,
                NoteAttachment(
                  name: nameCtrl.text.trim().isEmpty
                      ? '附件'
                      : nameCtrl.text.trim(),
                  uri: uri,
                  mimeType: mimeCtrl.text.trim(),
                ),
              );
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (!mounted || attachment == null) return;
    _addManualAttachment(attachment);
  }

  void _removeAttachment(NoteAttachment attachment) {
    setState(() {
      _todo = _todo.copyWith(
        attachments: _todo.attachments.where((a) => a != attachment).toList(),
      );
    });
    _markEditing();
  }

  Future<void> _pickDueDate() async {
    final picked = await AppDatePicker.pickSolar(
      context,
      initialDate: _todo.localDueDate ?? AppClock.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2099, 12, 31),
      title: '截止日期',
      subtitle: '使用统一日历选择任务日期',
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() => _todo = _todo.copyWith(dueDate: picked));
      _markEditing();
    }
  }

  Future<void> _pickRecurrence() async {
    final r = await RecurrencePicker.show(context, initial: _todo.recurrence);
    if (!mounted) return;
    if (r != null) {
      setState(() => _todo = _todo.copyWith(recurrence: r));
      _markEditing();
    }
  }

  // ---- Priority ----------------------------------------------------------

  void _pickPriority(TodoPriority p) {
    setState(() => _todo = _todo.copyWith(priority: p));
    _markEditing();
  }

  // ---- Reminder ----------------------------------------------------------

  /// 同步新 `reminderPlan` 与旧 `reminder / hasReminder / reminderAt` 镜像。
  void _applyReminderPlan(ReminderPlan plan) {
    final legacy = plan.toLegacyReminderConfig(fallback: _todo.reminder);
    final nowForMirror = AppClock.now();
    DateTime? mirroredAt;
    if (legacy.enabled && legacy.hour != null && legacy.minute != null) {
      final base =
          _todo.localDueDate ??
          (_todo.reminderAt == null
              ? nowForMirror
              : AppClock.toLocal(_todo.reminderAt!));
      mirroredAt = AppClock.date(
        base.year,
        base.month,
        base.day,
        legacy.hour!,
        legacy.minute!,
      );
      if (_todo.dueDate == null && !mirroredAt.isAfter(nowForMirror)) {
        mirroredAt = mirroredAt.add(const Duration(days: 1));
      }
    }
    setState(() {
      // ignore: deprecated_member_use_from_same_package
      _todo = _todo.copyWith(
        reminder: legacy,
        reminderPlan: plan,
        hasReminder: legacy.enabled,
        reminderAt: mirroredAt,
      );
    });
    _markEditing();
  }

  // ---- Time target -------------------------------------------------------

  void _applyTimeTargetMinutes(int? minutes) {
    final seconds = (minutes == null || minutes <= 0) ? null : minutes * 60;
    setState(() {
      _todo = _todo.copyWith(timeTargetSeconds: seconds);
      _timeTargetCtrl.text = (seconds == null)
          ? ''
          : (seconds ~/ 60).toString();
    });
    _markEditing();
  }

  void _insertNotePrefix(String prefix) {
    final text = _notesCtrl.text;
    final selection = _notesCtrl.selection;
    final start = selection.isValid ? selection.start : text.length;
    final lineStart = start <= 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
    final next = text.replaceRange(lineStart, lineStart, prefix);
    _notesCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + prefix.length),
    );
    _markEditing();
  }

  void _wrapNoteSelection(String marker) {
    final text = _notesCtrl.text;
    final selection = _notesCtrl.selection;
    if (!selection.isValid || selection.isCollapsed) {
      final offset = selection.isValid ? selection.start : text.length;
      final next = text.replaceRange(offset, offset, '$marker$marker');
      _notesCtrl.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: offset + marker.length),
      );
      _markEditing();
      return;
    }

    final selected = selection.textInside(text);
    final next = text.replaceRange(
      selection.start,
      selection.end,
      '$marker$selected$marker',
    );
    _notesCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: selection.end + marker.length * 2,
      ),
    );
    _markEditing();
  }

  void _insertNoteLink() {
    final text = _notesCtrl.text;
    final selection = _notesCtrl.selection;
    final selected = selection.isValid && !selection.isCollapsed
        ? selection.textInside(text)
        : '链接';
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final replacement = '[$selected](https://)';
    final next = text.replaceRange(start, end, replacement);
    _notesCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: start + replacement.length - 1,
      ),
    );
    _markEditing();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    _subtaskCtrl.dispose();
    _tagCtrl.dispose();
    _timeTargetCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final provider = context.watch<TodoProvider>();
    if (_missingTodo || !provider.todos.any((t) => t.id == widget.todoId)) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('任务详情'),
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
                  '这个任务不存在或已被删除',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: DesignTokens.spaceLg),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('返回'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final providerTodo = provider.todos.firstWhere(
      (t) => t.id == widget.todoId,
      orElse: () => _todo,
    );
    if (_state == _EditState.clean) {
      _syncDraftFromProvider(providerTodo);
    }
    final canEdit =
        context.watch<ShareProvider?>()?.canEdit(_todo.workspaceId) ?? true;
    final shareProvider = context.watch<ShareProvider?>();
    final locationReminderProvider = context.watch<LocationReminderProvider?>();
    final linkedLocationReminders =
        locationReminderProvider?.reminders
            .where((r) => r.linkedType == 'todo' && r.linkedId == _todo.id)
            .toList() ??
        const <LocationReminder>[];
    final workspace = _workspaceFor(shareProvider, _todo.workspaceId);
    if (workspace != null &&
        _commentsLoadedForWorkspaceId != workspace.id &&
        shareProvider != null) {
      _commentsLoadedForWorkspaceId = workspace.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<ShareProvider>().loadWorkspaceCollaboration(workspace.id);
      });
    }
    final cs = Theme.of(context).colorScheme;

    // canPop 反映当前状态机是否允许直接 pop：
    // - clean：没有未保存改动，系统返回键 / AppBar 返回键直接放行；
    // - 其它：拦截，走 `_handleBack` → 弹"放弃修改"对话框的分支。
    final bool canPop = _state == _EditState.clean;
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final allow = await _handleBack();
        if (allow && mounted) {
          // `_handleBack` 已经把 state 切回 clean；再主动请求一次 pop。
          // ignore: use_build_context_synchronously
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('任务详情'),
          titleTextStyle: appSecondaryRouteTitleTextStyle(context),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              // 统一走 PopScope：clean → 直接 pop；其它 → 触发
              // `onPopInvokedWithResult` 的拦截分支。
              Navigator.of(context).maybePop();
            },
          ),
          actions: [
            IconButton(
              icon: _state == _EditState.saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              tooltip: '保存',
              onPressed: _state == _EditState.saving || !canEdit ? null : _save,
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DesignTokens.formContentMaxWidth,
              ),
              child: _TodoDetailTheme(
                child: ListView(
                  key: const ValueKey('todo-detail-form'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(DesignTokens.spaceLg),
                  children: [
                    TextField(
                      controller: _titleCtrl,
                      enabled: canEdit,
                      decoration: const InputDecoration(labelText: '任务名称'),
                      style: const TextStyle(
                        fontSize: DesignTokens.fontSizeMd,
                        fontWeight: DesignTokens.fontWeightStrong,
                      ),
                      onChanged: (_) => _markEditing(),
                    ),
                    const SizedBox(height: DesignTokens.spaceLg),
                    _TodoMarkdownDescriptionEditor(
                      controller: _notesCtrl,
                      preview: _notesPreview,
                      enabled: canEdit,
                      onPreviewChanged: (value) =>
                          setState(() => _notesPreview = value),
                      onChanged: (_) => _markEditing(),
                      onHeading: () => _insertNotePrefix('## '),
                      onBold: () => _wrapNoteSelection('**'),
                      onItalic: () => _wrapNoteSelection('*'),
                      onQuote: () => _insertNotePrefix('> '),
                      onBullet: () => _insertNotePrefix('- '),
                      onChecklist: () => _insertNotePrefix('- [ ] '),
                      onCode: () => _wrapNoteSelection('`'),
                      onLink: _insertNoteLink,
                    ),

                    const SizedBox(height: DesignTokens.spaceLg),
                    _TodoAttachmentPanel(
                      attachments: _todo.attachments,
                      enabled: canEdit,
                      onPickFile: _addAttachment,
                      onAddManual: _showManualAttachmentDialog,
                      onRemove: _removeAttachment,
                    ),

                    // ---- 四象限 --------------------------------------------------
                    const SizedBox(height: DesignTokens.spaceLg),
                    AppSurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppDropdownField<EisenhowerQuadrant>(
                            initialValue: _todo.quadrant,
                            labelText: '四象限',
                            items: const [
                              DropdownMenuItem(
                                value: EisenhowerQuadrant.urgentImportant,
                                child: Text(
                                  'Q1 重要且紧急',
                                  style: TextStyle(
                                    fontSize: DesignTokens.fontSizeBody,
                                  ),
                                ),
                              ),
                              DropdownMenuItem(
                                value: EisenhowerQuadrant.notUrgentImportant,
                                child: Text(
                                  'Q2 重要不紧急',
                                  style: TextStyle(
                                    fontSize: DesignTokens.fontSizeBody,
                                  ),
                                ),
                              ),
                              DropdownMenuItem(
                                value: EisenhowerQuadrant.urgentNotImportant,
                                child: Text(
                                  'Q3 紧急不重要',
                                  style: TextStyle(
                                    fontSize: DesignTokens.fontSizeBody,
                                  ),
                                ),
                              ),
                              DropdownMenuItem(
                                value: EisenhowerQuadrant.notUrgentNotImportant,
                                child: Text(
                                  'Q4 不重要不紧急',
                                  style: TextStyle(
                                    fontSize: DesignTokens.fontSizeBody,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (v) {
                              setState(
                                () => _todo = _todo.copyWith(quadrant: v!),
                              );
                              _markEditing();
                            },
                          ),

                          // ---- 优先级 --------------------------------------------------
                          const SizedBox(height: DesignTokens.spaceLg),
                          _SectionLabel(text: '优先级'),
                          const SizedBox(height: DesignTokens.spaceSm),
                          _PriorityChipRow(
                            selected: _todo.priority,
                            onSelected: _pickPriority,
                          ),
                        ],
                      ),
                    ),

                    // ---- 截止日 + 重复 --------------------------------------------
                    const SizedBox(height: DesignTokens.spaceLg),
                    AppSurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.event_outlined),
                            title: const Text('截止日期'),
                            subtitle: Text(
                              _todo.localDueDate == null
                                  ? '未设置'
                                  : _formatYmd(_todo.localDueDate!),
                            ),
                            trailing: _todo.dueDate == null
                                ? const Icon(Icons.chevron_right)
                                : IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () {
                                      setState(
                                        () => _todo = _todo.copyWith(
                                          dueDate: null,
                                        ),
                                      );
                                      _markEditing();
                                    },
                                  ),
                            onTap: _pickDueDate,
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.repeat),
                            title: const Text('重复'),
                            subtitle: Text(_todo.recurrence.label),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _pickRecurrence,
                          ),

                          // ---- 共享负责人 ----------------------------------------------
                          const SizedBox(height: DesignTokens.spaceSm),
                          _AssignmentEditor(
                            workspace: workspace,
                            assigneeId: _todo.assigneeId,
                            enabled: canEdit,
                            onChanged: (value) {
                              setState(
                                () => _todo = _todo.copyWith(assigneeId: value),
                              );
                              _markEditing();
                            },
                          ),
                        ],
                      ),
                    ),
                    if (workspace != null && shareProvider != null) ...[
                      const SizedBox(height: DesignTokens.spaceLg),
                      _TaskCommentsPanel(
                        workspace: workspace,
                        todoId: _todo.id,
                        comments: shareProvider.commentsForTarget(
                          workspace.id,
                          _todo.id,
                        ),
                      ),
                    ],

                    // ---- 提醒 ----------------------------------------------------
                    const SizedBox(height: DesignTokens.spaceSm),
                    ReminderPlanEditor(
                      plan: _todo.reminderPlan,
                      onChanged: _applyReminderPlan,
                      title: '提醒',
                      allowAlarm: true,
                      allowRelativeToDue: true,
                      allowWeekly: true,
                      hasAnchorDate: _todo.dueDate != null,
                      defaultKind: ReminderKind.push,
                    ),
                    const SizedBox(height: DesignTokens.spaceSm),
                    Builder(
                      builder: (context) {
                        final notif = context.watch<NotificationService?>();
                        if (notif == null) return const SizedBox.shrink();
                        final kind =
                            _todo.reminderPlan.primaryRule?.kind ??
                            _todo.reminder.kind;
                        return ReminderHealthHint(
                          reminderKind: kind,
                          onOpenSystemSettings: () =>
                              _openSystemSettings(context),
                          onRequestNotificationPermission: () async {
                            await context
                                .read<NotificationService>()
                                .requestPermission();
                          },
                          onRequestExactAlarmPermission: () async {
                            await AlarmService.instance
                                .requestExactAlarmPermission();
                          },
                          onRequestFullScreenIntentPermission: () async {
                            await AlarmService.instance
                                .requestFullScreenIntentPermission();
                          },
                        );
                      },
                    ),
                    if (locationReminderProvider != null) ...[
                      const SizedBox(height: DesignTokens.spaceSm),
                      _TodoLocationReminderCard(
                        reminders: linkedLocationReminders,
                        enabled: canEdit,
                        onAdd: canEdit
                            ? () => _addLinkedLocationReminder(
                                context,
                                locationReminderProvider,
                              )
                            : null,
                        onRemove: canEdit
                            ? (id) => locationReminderProvider.remove(id)
                            : null,
                      ),
                    ],

                    // ---- 目标时长 ------------------------------------------------
                    const SizedBox(height: DesignTokens.spaceLg),
                    _TimeTargetEditor(
                      controller: _timeTargetCtrl,
                      minutes: _todo.timeTargetSeconds == null
                          ? null
                          : (_todo.timeTargetSeconds! ~/ 60),
                      onPreset: _applyTimeTargetMinutes,
                      onChanged: (s) =>
                          _applyTimeTargetMinutes(int.tryParse(s.trim())),
                      onClear: () => _applyTimeTargetMinutes(null),
                    ),

                    // ---- 标签 ----------------------------------------------------
                    const SizedBox(height: DesignTokens.spaceLg),
                    AppSurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SectionLabel(text: '标签'),
                          const SizedBox(height: DesignTokens.spaceSm),
                          _TagsEditor(
                            tags: _todo.tags,
                            controller: _tagCtrl,
                            onAdd: _addTag,
                            onRemove: _removeTag,
                          ),
                        ],
                      ),
                    ),

                    // ---- 子任务 --------------------------------------------------
                    const SizedBox(height: DesignTokens.spaceLg),
                    AppSurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const _SectionLabel(text: '子任务'),
                              const Spacer(),
                              Text(
                                '${_todo.subtasks.where((s) => s.isCompleted).length}/${_todo.subtasks.length}',
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: DesignTokens.fontSizeSecondary,
                                  fontWeight: DesignTokens.fontWeightStrong,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: DesignTokens.spaceSm),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _subtaskCtrl,
                                  enabled: canEdit && !_subtaskAdding,
                                  decoration: const InputDecoration(
                                    labelText: '新增子任务',
                                    isDense: false,
                                  ),
                                  onSubmitted: (_) {
                                    _addSubtask();
                                  },
                                ),
                              ),
                              const SizedBox(width: DesignTokens.spaceSm),
                              IconButton(
                                onPressed: canEdit && !_subtaskAdding
                                    ? _addSubtask
                                    : null,
                                icon: _subtaskAdding
                                    ? SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: cs.primary,
                                        ),
                                      )
                                    : Icon(Icons.add_circle, color: cs.primary),
                              ),
                            ],
                          ),
                          ReorderableListView(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            // ignore: deprecated_member_use
                            onReorder: (oldI, newI) {
                              if (!canEdit) return;
                              if (newI > oldI) newI -= 1;
                              final ids = _todo.subtasks
                                  .map((e) => e.id)
                                  .toList();
                              final id = ids.removeAt(oldI);
                              ids.insert(newI, id);
                              context.read<TodoProvider>().reorderSubtasks(
                                widget.todoId,
                                ids,
                              );
                            },
                            children: [
                              for (final s in _todo.subtasks)
                                Builder(
                                  key: ValueKey(s.id),
                                  builder: (context) {
                                    final busy = _busySubtaskIds.contains(s.id);
                                    return ListTile(
                                      dense: true,
                                      leading: Checkbox(
                                        value: s.isCompleted,
                                        onChanged: canEdit && !busy
                                            ? (_) {
                                                _toggleSubtask(s.id);
                                              }
                                            : null,
                                      ),
                                      title: Text(
                                        s.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: DesignTokens.fontSizeBase,
                                          decoration: s.isCompleted
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                      trailing: IconButton(
                                        icon: busy
                                            ? const SizedBox.square(
                                                dimension: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(Icons.close, size: 16),
                                        onPressed: canEdit && !busy
                                            ? () {
                                                _deleteSubtask(s.id);
                                              }
                                            : null,
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ],
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

  Workspace? _workspaceFor(ShareProvider? provider, String workspaceId) {
    if (provider == null || workspaceId.isEmpty || workspaceId == 'private') {
      return null;
    }
    for (final workspace in provider.workspaces) {
      if (workspace.id == workspaceId) return workspace;
    }
    return null;
  }

  Future<void> _addLinkedLocationReminder(
    BuildContext context,
    LocationReminderProvider provider,
  ) async {
    final titleCtrl = TextEditingController(text: _todo.title);
    final noteCtrl = TextEditingController(text: _todo.notes);
    final latCtrl = TextEditingController();
    final lngCtrl = TextEditingController();
    final radiusCtrl = TextEditingController(text: '200');
    var trigger = LocationTrigger.enter;
    var oneShot = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AppDialog(
          title: const Text('添加位置提醒'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: '提醒标题'),
                  autofocus: true,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: '备注'),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: latCtrl,
                        decoration: const InputDecoration(labelText: '纬度'),
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: lngCtrl,
                        decoration: const InputDecoration(labelText: '经度'),
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: radiusCtrl,
                  decoration: const InputDecoration(labelText: '半径（米）'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final chipWrap = Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          label: const Text('到达'),
                          selected: trigger == LocationTrigger.enter,
                          onSelected: (_) =>
                              setSt(() => trigger = LocationTrigger.enter),
                        ),
                        ChoiceChip(
                          label: const Text('离开'),
                          selected: trigger == LocationTrigger.leave,
                          onSelected: (_) =>
                              setSt(() => trigger = LocationTrigger.leave),
                        ),
                      ],
                    );
                    if (constraints.maxWidth < 260) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('触发方向'),
                          const SizedBox(height: 4),
                          chipWrap,
                        ],
                      );
                    }
                    return Row(
                      children: [const Text('触发方向'), const Spacer(), chipWrap],
                    );
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: oneShot,
                  onChanged: (value) => setSt(() => oneShot = value),
                  title: const Text('触发后自动关闭'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(I18n.tr('action.save')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final title = titleCtrl.text.trim();
    final lat = double.tryParse(latCtrl.text.trim());
    final lng = double.tryParse(lngCtrl.text.trim());
    final radius = double.tryParse(radiusCtrl.text.trim()) ?? 200;
    if (title.isEmpty || lat == null || lng == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入标题和有效经纬度'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await provider.add(
      LocationReminder(
        title: title,
        note: noteCtrl.text.trim(),
        latitude: lat,
        longitude: lng,
        radiusMeters: radius.clamp(50, 10000).toDouble(),
        trigger: trigger,
        oneShot: oneShot,
        linkedType: 'todo',
        linkedId: _todo.id,
      ),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已添加任务位置提醒'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

Future<bool> preflightTodoReminderSave(
  BuildContext context, {
  required TodoItem todo,
  NotificationService? notificationService,
  String issueTitle = '待办提醒注册失败',
}) async {
  final result = preflightTodoReminderPlan(todo);
  if (!result.hasEnabledPlan) return true;

  final messenger = ScaffoldMessenger.of(context);
  final blocking = result.blockingIssue;
  if (blocking != null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('${blocking.title}：${blocking.message}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
    return false;
  }

  final usesPush = result.kinds.contains(ReminderKind.push);
  final usesPopup = result.kinds.contains(ReminderKind.popup);
  final usesAlarm = result.kinds.contains(ReminderKind.alarm);
  final notif = notificationService ?? context.read<NotificationService?>();
  if ((usesPush || usesPopup) && notif != null) {
    final ready = await notif
        .ensureReadyForReminder(
          scheduledTime: result.firstScheduledTime,
          issueTitle: issueTitle,
          relatedId: todo.id,
        )
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (!context.mounted) return false;
    if (!ready) {
      final issue = notif.lastScheduleIssue;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            issue == null
                ? '$issueTitle：提醒未注册，请检查通知权限、渠道声音和提醒时间。'
                : '${issue.title}：${issue.message}',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      return false;
    }
  }

  if (usesAlarm && !usesPush && !usesPopup) {
    final notificationGranted = await LocalNotifications.instance
        .ensurePermission()
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (!context.mounted) return false;
    if (!notificationGranted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('闹钟提醒注册失败：系统通知权限未开启，提醒未注册。请开启通知权限后重新保存提醒。'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
      return false;
    }
  }

  final warnings = <String>[];

  if (usesPush || usesPopup) {
    final channelIds = await LocalNotifications.instance
        .notificationChannelIds()
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (!context.mounted) return false;
    if (channelIds != null &&
        channelIds.isNotEmpty &&
        !channelIds.contains(NotificationService.channelId)) {
      warnings.add('普通提醒渠道未就绪，到点可能不会弹出系统通知');
    }
  }

  if (usesAlarm) {
    final alarmChannelIds = await AlarmService.instance
        .notificationChannelIds()
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (!context.mounted) return false;
    if (alarmChannelIds != null &&
        alarmChannelIds.isNotEmpty &&
        !alarmChannelIds.contains(AlarmService.channelId)) {
      warnings.add('强提醒渠道未就绪，到点可能不会弹出闹钟通知');
    }
    // 主动申请精准闹钟 / 全屏 intent 权限，而不只是检查后给软提示。
    // 否则首次保存的闹钟提醒会静默降级，用户必须先点一次“测试强提醒”
    // 才会触发权限申请、之后的闹钟才正常——这正是“到点没提醒”的成因。
    final exactGranted =
        (await AlarmService.instance.hasExactAlarmPermission().timeout(
          const Duration(seconds: 5),
          onTimeout: () => false,
        )) ||
        (await AlarmService.instance.requestExactAlarmPermission().timeout(
          const Duration(seconds: 8),
          onTimeout: () => false,
        ));
    if (!context.mounted) return false;
    if (!exactGranted) {
      warnings.add('精准闹钟权限未开启，闹钟提醒可能延后或降级');
    }
    final fullScreenGranted =
        (await AlarmService.instance.hasFullScreenIntentPermission().timeout(
          const Duration(seconds: 5),
          onTimeout: () => false,
        )) ||
        (await AlarmService.instance
            .requestFullScreenIntentPermission()
            .timeout(const Duration(seconds: 8), onTimeout: () => false));
    if (!context.mounted) return false;
    if (!fullScreenGranted) {
      warnings.add('全屏提醒权限未开启，锁屏弹窗可能不可用');
    }
  }

  if (warnings.isNotEmpty) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('$issueTitle：${warnings.join('；')}。'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }
  return true;
}

Future<void> _openSystemSettings(BuildContext context) async {
  final opened = await openAppSettings();
  if (!context.mounted) return;
  if (!opened) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('无法打开系统设置'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 下面是 TodoDetailScreen 拆出来的私有子组件。
// ---------------------------------------------------------------------------

/// 复用全局表单的边框与圆角，详情正文保持 14px，辅助文字 12px。
/// 只调整本页的控件密度，字体家族、卡片皮肤及配色仍随当前主题。
class _TodoDetailTheme extends StatelessWidget {
  final Widget child;

  const _TodoDetailTheme({required this.child});

  @override
  Widget build(BuildContext context) {
    return AppFormFieldTheme(
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final cs = theme.colorScheme;
          final body = (theme.textTheme.bodyMedium ?? const TextStyle())
              .copyWith(
                fontSize: DesignTokens.fontSizeBody,
                fontWeight: DesignTokens.fontWeightStrong,
                height: 1.5,
                color: cs.onSurface,
              );
          final secondary = body.copyWith(
            fontSize: DesignTokens.fontSizeSecondary,
            color: cs.onSurfaceVariant,
          );
          OutlineInputBorder border(Color color, {double width = 0.55}) =>
              OutlineInputBorder(
                borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
                borderSide: BorderSide(color: color, width: width),
              );
          return Theme(
            data: theme.copyWith(
              textTheme: theme.textTheme.copyWith(
                bodyLarge: body,
                bodyMedium: body,
                bodySmall: secondary,
                titleMedium: body,
                titleSmall: body,
                labelLarge: secondary,
                labelMedium: secondary,
              ),
              inputDecorationTheme: theme.inputDecorationTheme.copyWith(
                filled: false,
                border: border(cs.outlineVariant.withValues(alpha: 0.30)),
                enabledBorder: border(
                  cs.outlineVariant.withValues(alpha: 0.30),
                ),
                focusedBorder: border(
                  cs.primary.withValues(alpha: 0.70),
                  width: 1,
                ),
                disabledBorder: border(
                  cs.outlineVariant.withValues(alpha: 0.16),
                ),
                contentPadding: const EdgeInsets.all(DesignTokens.spaceLg),
                labelStyle: body.copyWith(color: cs.onSurfaceVariant),
                floatingLabelStyle: body.copyWith(
                  fontSize: DesignTokens.fontSizeSecondary / 0.75,
                  color: cs.onSurfaceVariant,
                ),
                hintStyle: body.copyWith(color: cs.onSurfaceVariant),
                helperStyle: secondary,
              ),
              listTileTheme: theme.listTileTheme.copyWith(
                dense: false,
                contentPadding: EdgeInsets.zero,
                minLeadingWidth: DesignTokens.controlIconSize,
                horizontalTitleGap: DesignTokens.spaceMd,
                minVerticalPadding: DesignTokens.spaceMd,
                titleTextStyle: body,
                subtitleTextStyle: secondary,
                iconColor: cs.onSurfaceVariant,
              ),
              iconButtonTheme: IconButtonThemeData(
                style: IconButton.styleFrom(
                  iconSize: DesignTokens.controlIconSize,
                  foregroundColor: cs.onSurfaceVariant,
                  minimumSize: const Size.square(DesignTokens.controlMinHeight),
                  padding: const EdgeInsets.all(DesignTokens.spaceSm),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              chipTheme: theme.chipTheme.copyWith(
                labelStyle: secondary.copyWith(color: cs.onSurface),
                secondaryLabelStyle: secondary.copyWith(color: cs.onSurface),
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.spaceSm,
                  vertical: DesignTokens.spaceXs,
                ),
              ),
            ),
            child: DefaultTextStyle.merge(style: body, child: child),
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: DesignTokens.fontSizeBody,
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: DesignTokens.fontWeightStrong,
      ),
    );
  }
}

class _TodoLocationReminderCard extends StatelessWidget {
  final List<LocationReminder> reminders;
  final bool enabled;
  final VoidCallback? onAdd;
  final ValueChanged<String>? onRemove;

  const _TodoLocationReminderCard({
    required this.reminders,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(DesignTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on_outlined, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '位置提醒',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: enabled ? onAdd : null,
                icon: const Icon(Icons.add_location_alt_outlined, size: 16),
                label: const Text('添加'),
              ),
            ],
          ),
          if (reminders.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 28, bottom: 4),
              child: Text(
                '可为这条任务设置到达或离开某地时提醒',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else
            ...reminders.map((reminder) {
              final trigger = reminder.trigger == LocationTrigger.enter
                  ? '到达'
                  : '离开';
              return Padding(
                padding: const EdgeInsets.only(left: 28, top: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${reminder.title} · $trigger · '
                        '${reminder.radiusMeters.toStringAsFixed(0)}m',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      tooltip: '删除位置提醒',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: enabled
                          ? () => onRemove?.call(reminder.id)
                          : null,
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _TodoMarkdownDescriptionEditor extends StatelessWidget {
  final TextEditingController controller;
  final bool preview;
  final bool enabled;
  final ValueChanged<bool> onPreviewChanged;
  final ValueChanged<String> onChanged;
  final VoidCallback onHeading;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onQuote;
  final VoidCallback onBullet;
  final VoidCallback onChecklist;
  final VoidCallback onCode;
  final VoidCallback onLink;

  const _TodoMarkdownDescriptionEditor({
    required this.controller,
    required this.preview,
    required this.enabled,
    required this.onPreviewChanged,
    required this.onChanged,
    required this.onHeading,
    required this.onBold,
    required this.onItalic,
    required this.onQuote,
    required this.onBullet,
    required this.onChecklist,
    required this.onCode,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spaceLg,
              DesignTokens.spaceSm,
              DesignTokens.spaceSm,
              DesignTokens.spaceSm,
            ),
            child: Row(
              children: [
                const Expanded(child: _SectionLabel(text: '任务描述')),
                IconButton(
                  tooltip: preview ? '编辑描述' : '预览描述',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onPreviewChanged(!preview),
                  icon: Icon(
                    preview ? Icons.edit_outlined : Icons.visibility_outlined,
                  ),
                ),
              ],
            ),
          ),
          if (!preview)
            _TodoMarkdownToolbar(
              enabled: enabled,
              onHeading: onHeading,
              onBold: onBold,
              onItalic: onItalic,
              onQuote: onQuote,
              onBullet: onBullet,
              onChecklist: onChecklist,
              onCode: onCode,
              onLink: onLink,
            ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: preview
                ? _TodoMarkdownPreview(
                    key: const ValueKey('todo-description-preview'),
                    content: controller.text,
                  )
                : Padding(
                    key: const ValueKey('todo-description-editor'),
                    padding: const EdgeInsets.all(DesignTokens.spaceLg),
                    child: TextField(
                      controller: controller,
                      enabled: enabled,
                      minLines: 4,
                      maxLines: 8,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: DesignTokens.fontSizeBody,
                        color: cs.onSurface,
                        height: 1.5,
                      ),
                      decoration: const InputDecoration(
                        hintText: '支持 Markdown 描述',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: onChanged,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TodoMarkdownToolbar extends StatelessWidget {
  final bool enabled;
  final VoidCallback onHeading;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onQuote;
  final VoidCallback onBullet;
  final VoidCallback onChecklist;
  final VoidCallback onCode;
  final VoidCallback onLink;

  const _TodoMarkdownToolbar({
    required this.enabled,
    required this.onHeading,
    required this.onBold,
    required this.onItalic,
    required this.onQuote,
    required this.onBullet,
    required this.onChecklist,
    required this.onCode,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      height: DesignTokens.controlMinHeight,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.36),
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.24),
            width: 0.5,
          ),
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.24),
            width: 0.5,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spaceSm),
        child: Row(
          children: [
            _TodoMarkdownToolButton(
              icon: Icons.title,
              tooltip: '标题',
              enabled: enabled,
              onPressed: onHeading,
            ),
            _TodoMarkdownToolButton(
              icon: Icons.format_bold,
              tooltip: '加粗',
              enabled: enabled,
              onPressed: onBold,
            ),
            _TodoMarkdownToolButton(
              icon: Icons.format_italic,
              tooltip: '斜体',
              enabled: enabled,
              onPressed: onItalic,
            ),
            _TodoMarkdownToolButton(
              icon: Icons.format_quote,
              tooltip: '引用',
              enabled: enabled,
              onPressed: onQuote,
            ),
            _TodoMarkdownToolButton(
              icon: Icons.format_list_bulleted,
              tooltip: '列表',
              enabled: enabled,
              onPressed: onBullet,
            ),
            _TodoMarkdownToolButton(
              icon: Icons.checklist,
              tooltip: '清单',
              enabled: enabled,
              onPressed: onChecklist,
            ),
            _TodoMarkdownToolButton(
              icon: Icons.code,
              tooltip: '代码',
              enabled: enabled,
              onPressed: onCode,
            ),
            _TodoMarkdownToolButton(
              icon: Icons.link,
              tooltip: '链接',
              enabled: enabled,
              onPressed: onLink,
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoMarkdownToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  const _TodoMarkdownToolButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: DesignTokens.controlIconSize),
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(
        width: DesignTokens.controlMinHeight,
        height: DesignTokens.controlMinHeight,
      ),
      visualDensity: VisualDensity.standard,
      onPressed: enabled ? onPressed : null,
    );
  }
}

class _TodoMarkdownPreview extends StatelessWidget {
  final String content;

  const _TodoMarkdownPreview({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final blocks = content.trim().isEmpty
        ? const <NoteBlock>[]
        : NoteBlock.fromMarkdown(content);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 132),
      padding: const EdgeInsets.all(DesignTokens.spaceLg),
      child: blocks.isEmpty
          ? Text(
              '暂无描述',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final block in blocks)
                  _TodoMarkdownPreviewBlock(block: block, colorScheme: cs),
              ],
            ),
    );
  }
}

class _TodoMarkdownPreviewBlock extends StatelessWidget {
  final NoteBlock block;
  final ColorScheme colorScheme;

  const _TodoMarkdownPreviewBlock({
    required this.block,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    if (block.type == NoteBlockType.heading) {
      final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: block.level <= 1
            ? DesignTokens.fontSizeMd
            : DesignTokens.fontSizeBody,
        color: colorScheme.onSurface,
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _TodoInlineMarkdownText(
          text: block.text,
          style: style?.copyWith(fontWeight: DesignTokens.fontWeightStrong),
        ),
      );
    }
    if (block.type == NoteBlockType.quote) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: colorScheme.primary, width: 3),
          ),
          color: colorScheme.primary.withValues(alpha: 0.06),
        ),
        child: _TodoInlineMarkdownText(
          text: block.text,
          style: TextStyle(
            fontSize: DesignTokens.fontSizeBody,
            height: 1.45,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (block.type == NoteBlockType.checklist) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              block.checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18,
              color: block.checked
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(child: _TodoInlineMarkdownText(text: block.text)),
          ],
        ),
      );
    }
    if (block.type == NoteBlockType.bullet) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Icon(
                Icons.circle,
                size: 6,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: _TodoInlineMarkdownText(text: block.text)),
          ],
        ),
      );
    }
    if (block.type == NoteBlockType.code) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          block.text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontFamily: DesignTokens.fontFamilyRounded,
            fontSize: DesignTokens.fontSizeBody,
            color: colorScheme.onSurface,
          ),
        ),
      );
    }
    if (block.type == NoteBlockType.divider) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Divider(color: colorScheme.outlineVariant),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _TodoInlineMarkdownText(text: block.text),
    );
  }
}

class _TodoInlineMarkdownText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const _TodoInlineMarkdownText({required this.text, this.style});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
        .copyWith(
          fontSize: DesignTokens.fontSizeBody,
          height: 1.5,
          color: cs.onSurface,
        )
        .merge(style);
    return Text.rich(
      TextSpan(style: base, children: _parseInline(text, base, cs)),
    );
  }

  List<InlineSpan> _parseInline(String source, TextStyle base, ColorScheme cs) {
    final spans = <InlineSpan>[];
    var i = 0;
    while (i < source.length) {
      final bold = source.indexOf('**', i);
      final italic = source.indexOf('*', i);
      final code = source.indexOf('`', i);
      final link = source.indexOf('[', i);
      final candidates = <int>[
        bold,
        italic,
        code,
        link,
      ].where((pos) => pos >= 0).toList()..sort();
      final next = candidates.isEmpty ? -1 : candidates.first;
      if (next < 0) {
        spans.add(TextSpan(text: source.substring(i)));
        break;
      }
      if (next > i) {
        spans.add(TextSpan(text: source.substring(i, next)));
        i = next;
      }
      if (source.startsWith('**', i)) {
        final end = source.indexOf('**', i + 2);
        if (end > i + 2) {
          spans.add(
            TextSpan(
              text: source.substring(i + 2, end),
              style: base.copyWith(fontWeight: DesignTokens.fontWeightStrong),
            ),
          );
          i = end + 2;
          continue;
        }
      }
      if (source.startsWith('`', i)) {
        final end = source.indexOf('`', i + 1);
        if (end > i + 1) {
          spans.add(
            TextSpan(
              text: source.substring(i + 1, end),
              style: base.copyWith(
                fontFamily: DesignTokens.fontFamilyRounded,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
          );
          i = end + 1;
          continue;
        }
      }
      if (source.startsWith('[', i)) {
        final closeLabel = source.indexOf('](', i + 1);
        final closeUrl = closeLabel < 0 ? -1 : source.indexOf(')', closeLabel);
        if (closeLabel > i + 1 && closeUrl > closeLabel + 2) {
          spans.add(
            TextSpan(
              text: source.substring(i + 1, closeLabel),
              style: base.copyWith(
                color: cs.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          );
          i = closeUrl + 1;
          continue;
        }
      }
      if (source.startsWith('*', i)) {
        final end = source.indexOf('*', i + 1);
        if (end > i + 1) {
          spans.add(
            TextSpan(
              text: source.substring(i + 1, end),
              style: base.copyWith(fontStyle: FontStyle.italic),
            ),
          );
          i = end + 1;
          continue;
        }
      }
      spans.add(TextSpan(text: source[i]));
      i++;
    }
    return spans;
  }
}

class _AssignmentEditor extends StatelessWidget {
  final Workspace? workspace;
  final String? assigneeId;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  const _AssignmentEditor({
    required this.workspace,
    required this.assigneeId,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final workspace = this.workspace;
    if (workspace == null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.person_outline),
        title: const Text('负责人'),
        subtitle: const Text(
          '私有任务无需指派；共享清单任务可选择成员',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    final members = workspace.members;
    final selected = members.any((member) => member.userId == assigneeId)
        ? assigneeId!
        : '';
    return AppDropdownField<String>(
      initialValue: selected,
      decoration: InputDecoration(
        labelText: '负责人',
        helperText: '共享空间：${workspace.name}',
        helperMaxLines: 2,
        prefixIcon: const Icon(Icons.assignment_ind_outlined),
      ),
      items: [
        const DropdownMenuItem<String>(
          value: '',
          child: Text(
            '未指派',
            style: TextStyle(fontSize: DesignTokens.fontSizeBody),
          ),
        ),
        for (final member in members)
          DropdownMenuItem<String>(
            value: member.userId,
            child: Text(
              member.username.isEmpty ? member.userId : member.username,
              style: const TextStyle(fontSize: DesignTokens.fontSizeBody),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      enabled: enabled,
      onChanged: (value) =>
          onChanged(value == null || value.isEmpty ? null : value),
    );
  }
}

class _TaskCommentsPanel extends StatefulWidget {
  final Workspace workspace;
  final String todoId;
  final List<WorkspaceComment> comments;

  const _TaskCommentsPanel({
    required this.workspace,
    required this.todoId,
    required this.comments,
  });

  @override
  State<_TaskCommentsPanel> createState() => _TaskCommentsPanelState();
}

class _TaskCommentsPanelState extends State<_TaskCommentsPanel> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(DesignTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.forum_outlined, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              const Expanded(child: _SectionLabel(text: '任务评论')),
              Text(
                '${widget.comments.length}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              isDense: true,
              hintText: '针对这个任务记录进展或风险，@用户名/邮箱/昵称 可提醒对方',
              suffixIcon: IconButton(
                tooltip: '发送评论',
                icon: const Icon(Icons.send_outlined),
                onPressed: _send,
              ),
            ),
            onSubmitted: (_) => _send(),
          ),
          const SizedBox(height: 8),
          if (widget.comments.isEmpty)
            Text(
              '暂无任务评论',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            )
          else
            ...widget.comments
                .take(4)
                .map(
                  (comment) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 13,
                      backgroundColor: cs.primary.withValues(alpha: 0.12),
                      child: Text(
                        comment.authorName.isEmpty
                            ? '?'
                            : comment.authorName.substring(0, 1),
                        style: TextStyle(fontSize: 10, color: cs.primary),
                      ),
                    ),
                    title: Text(
                      comment.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${comment.authorName.isEmpty ? comment.authorUserId : comment.authorName} · ${_formatCommentTime(comment.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    try {
      await context.read<ShareProvider>().createComment(
        widget.workspace.id,
        text,
        targetId: widget.todoId,
      );
      if (!mounted) return;
      _ctrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('评论发送失败: ${_shareError(e)}')));
    }
  }
}

String _shareError(Object error) =>
    userVisibleApiError(error, fallbackMessage: '共享空间服务暂不可用，请稍后重试或联系管理员');

String _formatCommentTime(DateTime value) {
  return I18nDateFormat.shortDateTime(AppClock.toLocal(value));
}

/// 优先级 Chip 行。
///
/// 对齐 Requirement 2.1："列表项展示优先级色标"。编辑面板用 ChoiceChip 做分段选择。
class _PriorityChipRow extends StatelessWidget {
  final TodoPriority selected;
  final ValueChanged<TodoPriority> onSelected;

  const _PriorityChipRow({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: DesignTokens.spaceXs,
      runSpacing: DesignTokens.spaceXs,
      children: [
        for (final p in TodoPriority.values)
          ChoiceChip(
            avatar: p == TodoPriority.none
                ? null
                : _PriorityDot(priority: p, size: 10),
            label: Text(p.label),
            selected: selected == p,
            onSelected: (_) => onSelected(p),
          ),
      ],
    );
  }
}

/// 目标时长编辑器：分钟输入 + 15/25/45/60 预设。
class _TimeTargetEditor extends StatelessWidget {
  final TextEditingController controller;
  final int? minutes;
  final ValueChanged<int?> onPreset;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _TimeTargetEditor({
    required this.controller,
    required this.minutes,
    required this.onPreset,
    required this.onChanged,
    required this.onClear,
  });

  static const List<int> _presets = [15, 25, 45, 60];

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionLabel(text: '目标时长'),
          const SizedBox(height: DesignTokens.spaceSm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    isDense: false,
                    hintText: '分钟（0 或空 = 清除）',
                    suffixText: '分钟',
                  ),
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: DesignTokens.spaceSm),
              IconButton(
                tooltip: '清除',
                onPressed: onClear,
                icon: const Icon(Icons.clear),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.spaceSm),
          Wrap(
            spacing: DesignTokens.spaceXs,
            runSpacing: DesignTokens.spaceXs,
            children: [
              for (final m in _presets)
                ChoiceChip(
                  label: Text('$m 分钟'),
                  selected: minutes == m,
                  onSelected: (_) => onPreset(m),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 标签编辑器：已有标签 + 新标签输入。
class _TodoAttachmentPanel extends StatelessWidget {
  final List<NoteAttachment> attachments;
  final bool enabled;
  final VoidCallback onPickFile;
  final VoidCallback onAddManual;
  final ValueChanged<NoteAttachment> onRemove;

  const _TodoAttachmentPanel({
    required this.attachments,
    required this.enabled,
    required this.onPickFile,
    required this.onAddManual,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final images = attachments.where((attachment) => attachment.isImage);
    return AppSurfaceCard(
      padding: const EdgeInsets.all(DesignTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.attach_file,
                size: DesignTokens.controlIconSize,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: DesignTokens.spaceSm),
              const Expanded(child: _SectionLabel(text: '附件')),
              IconButton(
                tooltip: '选择文件',
                onPressed: enabled ? onPickFile : null,
                icon: const Icon(Icons.upload_file_outlined),
              ),
              IconButton(
                tooltip: '添加链接',
                onPressed: enabled ? onAddManual : null,
                icon: const Icon(Icons.add_link),
              ),
            ],
          ),
          if (attachments.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: DesignTokens.spaceXs),
              child: Text(
                '暂无附件',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else ...[
            const SizedBox(height: DesignTokens.spaceXs),
            Wrap(
              spacing: DesignTokens.spaceXs,
              runSpacing: DesignTokens.spaceXs,
              children: [
                for (final attachment in attachments)
                  _TodoAttachmentChip(
                    attachment: attachment,
                    onDeleted: enabled ? () => onRemove(attachment) : null,
                  ),
              ],
            ),
          ],
          if (images.isNotEmpty) ...[
            const SizedBox(height: DesignTokens.spaceMd),
            for (final image in images)
              _TodoAttachmentImagePreview(attachment: image),
          ],
        ],
      ),
    );
  }
}

class _TodoAttachmentChip extends StatelessWidget {
  final NoteAttachment attachment;
  final VoidCallback? onDeleted;

  const _TodoAttachmentChip({required this.attachment, this.onDeleted});

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(attachment.uri);
    return InputChip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        _isWebUri(uri) ? Icons.link : Icons.insert_drive_file_outlined,
      ),
      label: Text(
        attachment.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onDeleted: onDeleted,
      onPressed: uri == null
          ? null
          : () async {
              final target = _isWebUri(uri)
                  ? uri
                  : Uri.file(attachment.uri, windows: false);
              await launchUrl(target, mode: LaunchMode.externalApplication);
            },
    );
  }

  bool _isWebUri(Uri? uri) => uri?.scheme == 'http' || uri?.scheme == 'https';
}

class _TodoAttachmentImagePreview extends StatelessWidget {
  final NoteAttachment attachment;

  const _TodoAttachmentImagePreview({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uri = Uri.tryParse(attachment.uri);
    Widget image;
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      image = Image.network(
        attachment.uri,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(cs),
      );
    } else if (uri != null && uri.scheme == 'file') {
      image = Image.file(
        File(uri.toFilePath()),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(cs),
      );
    } else if (attachment.uri.startsWith('/')) {
      image = Image.file(
        File(attachment.uri),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(cs),
      );
    } else {
      image = _fallback(cs);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.spaceSm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ColoredBox(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            child: image,
          ),
        ),
      ),
    );
  }

  Widget _fallback(ColorScheme cs) => Center(
    child: Icon(Icons.image_not_supported_outlined, color: cs.onSurfaceVariant),
  );
}

/// 标签编辑器：已有标签 + 新标签输入。
class _TagsEditor extends StatelessWidget {
  final List<String> tags;
  final TextEditingController controller;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  const _TagsEditor({
    required this.tags,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tags.isNotEmpty) ...[
          Wrap(
            spacing: DesignTokens.spaceXs,
            runSpacing: DesignTokens.spaceXs,
            children: [
              for (final t in tags)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Chip(
                    label: Text(
                      '#$t',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onDeleted: () => onRemove(t),
                  ),
                ),
            ],
          ),
          const SizedBox(height: DesignTokens.spaceSm),
        ],
        TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '+ 新标签'),
          onSubmitted: onAdd,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 共享小工具：优先级色点 / 颜色映射 / 时间格式化
// ---------------------------------------------------------------------------

/// 优先级色标（圆点）。
class _PriorityDot extends StatelessWidget {
  final TodoPriority priority;
  final double size;

  const _PriorityDot({required this.priority, this.size = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: priorityColor(priority),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// 由 TodoPriority 映射到 DesignTokens 中的语义色。
///
/// 供 `_PriorityChipRow` 与 Todo 列表项共享。
Color priorityColor(TodoPriority p) {
  switch (p) {
    case TodoPriority.urgent:
      return const Color(0xFFD32F2F); // 深红，区分于 high
    case TodoPriority.high:
      return DesignTokens.priorityHigh;
    case TodoPriority.medium:
      return DesignTokens.priorityMedium;
    case TodoPriority.low:
      return DesignTokens.priorityLow;
    case TodoPriority.none:
      return DesignTokens.priorityNone;
  }
}

String _formatYmd(DateTime d) => I18nDateFormat.date(d);
