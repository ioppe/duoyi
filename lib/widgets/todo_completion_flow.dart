import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/i18n.dart';

import '../models/time_entry.dart';
import '../models/todo.dart';
import '../providers/time_audit_provider.dart';
import '../providers/todo_provider.dart';
import 'surface_components.dart';

final Set<String> _completionFlowInFlightTodoIds = <String>{};

Future<void> completeTodoWithOptionalTimeRecord(
  BuildContext context,
  TodoItem todo,
) async {
  if (!_completionFlowInFlightTodoIds.add(todo.id)) return;
  try {
    await _completeTodoWithOptionalTimeRecord(context, todo);
  } finally {
    _completionFlowInFlightTodoIds.remove(todo.id);
  }
}

Future<void> _completeTodoWithOptionalTimeRecord(
  BuildContext context,
  TodoItem todo,
) async {
  final todoProvider = context.read<TodoProvider>();
  final timeAuditProvider = context.read<TimeAuditProvider?>();
  final messenger = ScaffoldMessenger.of(context);
  TodoItem currentTodo;
  try {
    currentTodo = todoProvider.todos.firstWhere((t) => t.id == todo.id);
  } on StateError {
    currentTodo = todo;
  }

  if (currentTodo.isCompleted) return;
  // 有未完成子任务时，父任务完成态只能由子任务推导。
  if (currentTodo.subtasks.any((subtask) => !subtask.isCompleted)) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(I18n.tr('todo.complete.blocked_by_subtasks')),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AppDialog(
      icon: const Icon(Icons.task_alt_outlined),
      title: const Text('确认完成任务'),
      content: Text('现在完成“${currentTodo.title}”吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogCtx).pop(true),
          child: const Text('继续'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final recordMinutes = await _showRecordPrompt(
    context,
    currentTodo.title,
    initialMinutes: _initialMinutes(currentTodo),
  );

  final changed = await todoProvider.completeTodos([
    todo.id,
  ], recordCompletionTime: false);
  if (changed == 0) return;
  if (!context.mounted) return;

  if (recordMinutes != null && recordMinutes > 0 && timeAuditProvider != null) {
    final completedTodo = todoProvider.todos.firstWhere(
      (t) => t.id == todo.id,
      orElse: () => currentTodo,
    );
    final completedAt = completedTodo.completedAt ?? DateTime.now();
    await timeAuditProvider.add(
      TimeEntry(
        title: completedTodo.title,
        startAt: completedAt.subtract(Duration(minutes: recordMinutes)),
        endAt: completedAt,
        category: TimeEntryCategory.todo,
        source: TimeEntrySource.todo,
        sourceId: todo.id,
        dedupeKey: TimeAuditProvider.todoCompletionDedupeKey(
          todo.id,
          completedAt,
        ),
        note: '手动记录耗时：$recordMinutes 分钟',
      ),
    );
  } else if (timeAuditProvider != null) {
    final completedTodo = todoProvider.todos.firstWhere(
      (t) => t.id == todo.id,
      orElse: () => currentTodo,
    );
    await timeAuditProvider.recordTodoCompletion(
      completedTodo,
      completedAt: completedTodo.completedAt,
    );
  }

  messenger.showSnackBar(
    SnackBar(
      content: Text('已完成：${currentTodo.title}'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

Future<int?> _showRecordPrompt(
  BuildContext context,
  String todoTitle, {
  required int initialMinutes,
}) async {
  final controller = TextEditingController(
    text: initialMinutes.clamp(1, 1440).toString(),
  );
  final minutes = await showDialog<int?>(
    context: context,
    builder: (dialogCtx) => AppDialog(
      icon: const Icon(Icons.schedule_outlined),
      title: const Text('记录耗时'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('要不要顺手记录一下“$todoTitle”这次花了多久？'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '耗时',
              suffixText: '分钟',
              hintText: '留空则跳过',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(null),
          child: const Text('跳过'),
        ),
        FilledButton(
          onPressed: () {
            final parsed = int.tryParse(controller.text.trim());
            if (parsed == null || parsed <= 0) {
              Navigator.of(dialogCtx).pop(null);
            } else {
              Navigator.of(dialogCtx).pop(parsed);
            }
          },
          child: const Text('记录'),
        ),
      ],
    ),
  );
  controller.dispose();
  return minutes;
}

int _initialMinutes(TodoItem todo) {
  final sec = todo.timeTargetSeconds;
  if (sec != null && sec > 0) {
    return (sec / 60).round().clamp(1, 1440);
  }
  return 30;
}
