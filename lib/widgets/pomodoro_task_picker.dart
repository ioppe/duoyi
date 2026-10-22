import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../models/todo.dart';
import 'surface_components.dart';

/// Picks existing tasks first; it does not change their completion state.
class PomodoroTaskPicker extends StatefulWidget {
  final List<TodoItem> todos;
  final String title;
  final String? selectedTodoId;
  final String? selectedSubtaskId;
  final bool hasSelection;
  final void Function(TodoItem todo, Subtask? subtask) onSelected;
  final ValueChanged<String> onPreset;
  final VoidCallback onManual;
  final VoidCallback onClear;

  const PomodoroTaskPicker({
    super.key,
    required this.todos,
    required this.title,
    this.selectedTodoId,
    this.selectedSubtaskId,
    required this.hasSelection,
    required this.onSelected,
    required this.onPreset,
    required this.onManual,
    required this.onClear,
  });

  @override
  State<PomodoroTaskPicker> createState() => _PomodoroTaskPickerState();
}

class _PomodoroTaskPickerState extends State<PomodoroTaskPicker> {
  final _search = TextEditingController();
  final _expanded = <String>{};
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (widget.selectedTodoId != null && widget.selectedSubtaskId != null) {
      _expanded.add(widget.selectedTodoId!);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active =
        widget.todos
            .where((todo) => !todo.isCompleted && !todo.isArchivedAfterRollover)
            .toList()
          ..sort((a, b) {
            final date = a.date.compareTo(b.date);
            return date != 0 ? date : a.sortOrder.compareTo(b.sortOrder);
          });
    bool matches(String text) => text.toLowerCase().contains(_query);
    final filtered = active.where(
      (todo) =>
          matches(todo.title) ||
          todo.subtasks.any(
            (child) => !child.isCompleted && matches(child.title),
          ),
    );
    return AppModalSheet(
      title: widget.title,
      subtitle: I18n.tr('focus.tasks.picker_hint'),
      actions: [
        TextButton(
          key: const ValueKey('focus_task_manual'),
          onPressed: widget.onManual,
          child: Text(I18n.tr('focus.tasks.manual')),
        ),
        if (widget.hasSelection)
          TextButton(
            key: const ValueKey('focus_task_clear'),
            onPressed: widget.onClear,
            child: Text(I18n.tr('focus.tasks.clear')),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('focus_task_search'),
            controller: _search,
            decoration: InputDecoration(
              hintText: I18n.tr('focus.tasks.search'),
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                I18n.tr(
                  active.isEmpty
                      ? 'focus.tasks.empty'
                      : 'focus.tasks.no_matches',
                ),
              ),
            ),
          for (final todo in filtered) ...[
            Builder(
              builder: (context) {
                final children =
                    todo.subtasks.where((child) => !child.isCompleted).toList()
                      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
                final selected =
                    widget.selectedTodoId == todo.id &&
                    widget.selectedSubtaskId == null;
                return ListTile(
                  key: ValueKey('focus_task_${todo.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  title: Text(todo.title),
                  subtitle: todo.listGroupName?.isNotEmpty == true
                      ? Text(todo.listGroupName!)
                      : null,
                  selected: selected,
                  onTap: () => widget.onSelected(todo, null),
                  trailing: children.isEmpty
                      ? null
                      : IconButton(
                          key: ValueKey('focus_task_expand_${todo.id}'),
                          tooltip: I18n.tr('focus.tasks.subtasks'),
                          onPressed: () => setState(() {
                            if (!_expanded.add(todo.id)) {
                              _expanded.remove(todo.id);
                            }
                          }),
                          icon: Icon(
                            _expanded.contains(todo.id) || _query.isNotEmpty
                                ? Icons.expand_less
                                : Icons.expand_more,
                          ),
                        ),
                );
              },
            ),
            if (_expanded.contains(todo.id) || _query.isNotEmpty)
              ...(todo.subtasks
                      .where(
                        (child) =>
                            !child.isCompleted &&
                            (matches(todo.title) || matches(child.title)),
                      )
                      .toList()
                    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
                  .map((child) {
                    final selected =
                        widget.selectedTodoId == todo.id &&
                        widget.selectedSubtaskId == child.id;
                    return Padding(
                      padding: const EdgeInsets.only(left: 24),
                      child: ListTile(
                        key: ValueKey('focus_subtask_${todo.id}_${child.id}'),
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.subdirectory_arrow_right,
                        ),
                        title: Text(child.title),
                        selected: selected,
                        onTap: () => widget.onSelected(todo, child),
                      ),
                    );
                  }),
          ],
          const Divider(height: 24),
          Text(
            I18n.tr('focus.tasks.presets'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in [
                'deep_work',
                'reading',
                'writing',
                'review',
                'exercise',
                'study',
              ])
                ActionChip(
                  label: Text(I18n.tr('focus.tasks.preset.$name')),
                  onPressed: () =>
                      widget.onPreset(I18n.tr('focus.tasks.preset.$name')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
