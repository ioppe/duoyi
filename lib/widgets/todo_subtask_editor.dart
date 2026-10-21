import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../models/todo.dart';

/// Controlled subtask draft: mutations are synchronous; the caller owns saving.
class TodoSubtaskEditor extends StatefulWidget {
  final List<Subtask> subtasks;
  final ValueChanged<List<Subtask>> onChanged;
  final bool enabled;
  final bool showCompletion;
  final String? helperText;

  const TodoSubtaskEditor({
    super.key,
    required this.subtasks,
    required this.onChanged,
    this.enabled = true,
    this.showCompletion = true,
    this.helperText,
  });

  @override
  State<TodoSubtaskEditor> createState() => _TodoSubtaskEditorState();
}

class _TodoSubtaskEditorState extends State<TodoSubtaskEditor> {
  final _newTask = TextEditingController();

  @override
  void initState() {
    super.initState();
    _newTask.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _newTask.removeListener(_refresh);
    _newTask.dispose();
    super.dispose();
  }

  void _emit(List<Subtask> items) {
    if (!widget.enabled) return;
    widget.onChanged([
      for (final (index, task) in items.indexed)
        Subtask(
          id: task.id,
          title: task.title,
          isCompleted: task.isCompleted,
          sortOrder: index,
        ),
    ]);
  }

  void _add() {
    final text = _newTask.text.trim();
    if (!widget.enabled || text.isEmpty) return;
    _emit([...widget.subtasks, Subtask(title: text)]);
    _newTask.clear();
  }

  void _replace(String id, {String? title, bool? isCompleted}) => _emit([
    for (final task in widget.subtasks)
      if (task.id == id)
        Subtask(
          id: task.id,
          title: title ?? task.title,
          isCompleted: isCompleted ?? task.isCompleted,
        )
      else
        task,
  ]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                I18n.tr('todo.subtasks'),
                style: theme.textTheme.titleSmall,
              ),
            ),
            Text(
              '${widget.subtasks.where((task) => task.isCompleted).length}/${widget.subtasks.length}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (widget.helperText != null) ...[
          const SizedBox(height: DesignTokens.spaceXs),
          Text(
            widget.helperText!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
        if (widget.subtasks.isNotEmpty) ...[
          const SizedBox(height: DesignTokens.spaceSm),
          ReorderableListView(
            key: const ValueKey('todo_subtask_list'),
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            proxyDecorator: (child, index, animation) =>
                Material(color: cs.surface, child: child),
            onReorderStart: (_) =>
                FocusManager.instance.primaryFocus?.unfocus(),
            // ignore: deprecated_member_use
            onReorder: (oldIndex, newIndex) {
              if (!widget.enabled) return;
              if (newIndex > oldIndex) newIndex--;
              final items = [...widget.subtasks];
              final moved = items.removeAt(oldIndex);
              items.insert(newIndex, moved);
              _emit(items);
            },
            children: [
              for (final (index, task) in widget.subtasks.indexed)
                _SubtaskDraftRow(
                  key: ValueKey(task.id),
                  task: task,
                  index: index,
                  enabled: widget.enabled,
                  showCompletion: widget.showCompletion,
                  onTitleChanged: (value) => _replace(task.id, title: value),
                  onCompleted: (value) => _replace(task.id, isCompleted: value),
                  onDelete: () => _emit(
                    widget.subtasks
                        .where((item) => item.id != task.id)
                        .toList(),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: DesignTokens.spaceSm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('todo_subtask_add_input'),
                controller: _newTask,
                enabled: widget.enabled,
                minLines: 1,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: I18n.tr('todo.subtask.new'),
                ),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: DesignTokens.spaceXs),
            _SubtaskAction(
              key: const ValueKey('todo_subtask_add'),
              tooltip: I18n.tr('todo.subtask.add'),
              icon: Icons.add_circle_outline,
              onPressed: widget.enabled && _newTask.text.trim().isNotEmpty
                  ? _add
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _SubtaskDraftRow extends StatefulWidget {
  final Subtask task;
  final int index;
  final bool enabled;
  final bool showCompletion;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<bool> onCompleted;
  final VoidCallback onDelete;

  const _SubtaskDraftRow({
    super.key,
    required this.task,
    required this.index,
    required this.enabled,
    required this.showCompletion,
    required this.onTitleChanged,
    required this.onCompleted,
    required this.onDelete,
  });

  @override
  State<_SubtaskDraftRow> createState() => _SubtaskDraftRowState();
}

class _SubtaskDraftRowState extends State<_SubtaskDraftRow> {
  late final _text = TextEditingController(text: widget.task.title);

  @override
  void didUpdateWidget(_SubtaskDraftRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_text.text != widget.task.title) {
      _text.value = TextEditingValue(
        text: widget.task.title,
        selection: TextSelection.collapsed(offset: widget.task.title.length),
      );
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceXs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showCompletion)
          SizedBox(
            width: DesignTokens.controlMinHeight,
            height: DesignTokens.formFieldMinHeight,
            child: Checkbox(
              key: ValueKey('todo_subtask_complete_${widget.task.id}'),
              value: widget.task.isCompleted,
              onChanged: widget.enabled
                  ? (value) => widget.onCompleted(value ?? false)
                  : null,
            ),
          ),
        Expanded(
          child: TextField(
            key: ValueKey('todo_subtask_text_${widget.task.id}'),
            controller: _text,
            enabled: widget.enabled,
            minLines: 1,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: I18n.tr('todo.subtask.content'),
              contentPadding: const EdgeInsets.all(DesignTokens.spaceMd),
            ),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              height: 1.5,
              decoration: widget.task.isCompleted
                  ? TextDecoration.lineThrough
                  : null,
            ),
            onChanged: widget.onTitleChanged,
          ),
        ),
        _SubtaskAction(
          key: ValueKey('todo_subtask_delete_${widget.task.id}'),
          tooltip: I18n.tr('todo.subtask.delete'),
          icon: Icons.close_rounded,
          onPressed: widget.enabled ? widget.onDelete : null,
        ),
        ReorderableDragStartListener(
          key: ValueKey('todo_subtask_drag_${widget.task.id}'),
          index: widget.index,
          enabled: widget.enabled,
          child: Tooltip(
            message: I18n.tr('todo.subtask.reorder'),
            child: SizedBox(
              width: DesignTokens.controlMinHeight,
              height: DesignTokens.formFieldMinHeight,
              child: Icon(
                Icons.drag_handle_rounded,
                size: DesignTokens.controlIconSize,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _SubtaskAction extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  const _SubtaskAction({
    super.key,
    required this.tooltip,
    required this.icon,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: DesignTokens.formFieldMinHeight,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: const BoxConstraints.tightFor(
        width: DesignTokens.controlMinHeight,
        height: DesignTokens.controlMinHeight,
      ),
      visualDensity: VisualDensity.standard,
      icon: Icon(icon, size: DesignTokens.controlIconSize),
    ),
  );
}
