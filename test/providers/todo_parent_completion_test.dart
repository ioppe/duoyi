import 'dart:convert';

import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TodoItem _parent({
  String id = 'parent',
  bool completed = false,
  bool autoToggle = true,
  List<Subtask>? subtasks,
}) => TodoItem(
  id: id,
  title: '父任务',
  isCompleted: completed,
  completedAt: completed ? DateTime(2026, 1, 1) : null,
  autoToggleByChildren: autoToggle,
  subtasks:
      subtasks ??
      [
        Subtask(id: 'a', title: 'A', sortOrder: 0),
        Subtask(id: 'b', title: 'B', sortOrder: 1),
      ],
);

List<Subtask> _children({required bool completed}) => [
  for (final (index, id) in ['a', 'b'].indexed)
    Subtask(id: id, title: id, isCompleted: completed, sortOrder: index),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('有未完成子任务时，任何写入都不能把父任务改成已完成', () async {
    final provider = TodoProvider();
    await provider.addTodo(
      _parent(completed: true, subtasks: _children(completed: false)),
    );

    await provider.updateTodo(
      'parent',
      provider.todos.single.copyWith(
        isCompleted: true,
        completedAt: DateTime(2026, 2, 2),
      ),
    );

    final todo = provider.todos.single;
    expect(todo.isCompleted, isFalse);
    expect(todo.completedAt, isNull);
  });

  test('子任务全完成时父任务自动完成，取消一个后重新打开', () async {
    final provider = TodoProvider();
    await provider.addTodo(_parent(subtasks: _children(completed: true)));
    expect(provider.todos.single.isCompleted, isTrue);

    await provider.updateTodo(
      'parent',
      provider.todos.single.copyWith(subtasks: _children(completed: false)),
    );
    expect(provider.todos.single.isCompleted, isFalse);

    await provider.updateTodo(
      'parent',
      provider.todos.single.copyWith(subtasks: _children(completed: true)),
    );
    expect(provider.todos.single.isCompleted, isTrue);
    expect(provider.todos.single.completedAt, isNotNull);
  });

  test('新建时父完成态与子任务保持一致（autoToggle=false 也不能绕过）', () async {
    final provider = TodoProvider();
    await provider.addTodo(
      _parent(
        completed: true,
        autoToggle: false,
        subtasks: _children(completed: false),
      ),
    );
    expect(provider.todos.single.isCompleted, isFalse);
  });

  test('批量完成跳过仍有未完成子任务的任务', () async {
    final provider = TodoProvider();
    await provider.addTodo(_parent());
    await provider.addTodo(TodoItem(id: 'plain', title: '无子任务'));

    final count = await provider.completeTodos({'parent', 'plain'});

    expect(count, 1);
    expect(provider.lastSkippedBySubtasks, 1);
    expect(
      provider.todos.firstWhere((todo) => todo.id == 'parent').isCompleted,
      isFalse,
    );
    expect(
      provider.todos.firstWhere((todo) => todo.id == 'plain').isCompleted,
      isTrue,
    );
  });

  test('批量恢复不会单独打开有子任务的父任务', () async {
    final provider = TodoProvider();
    await provider.addTodo(_parent(subtasks: _children(completed: true)));
    expect(provider.todos.single.isCompleted, isTrue);

    final count = await provider.reopenTodos({'parent'});

    expect(count, 0);
    expect(provider.lastSkippedBySubtasks, 1);
    expect(provider.todos.single.isCompleted, isTrue);
  });

  test('加载时会纠正“父已完成但子任务未全完成”的历史数据', () async {
    SharedPreferences.setMockInitialValues({
      'todos': jsonEncode([
        {
          'id': 'legacy',
          'title': '历史任务',
          'isCompleted': true,
          'completedAt': '2026-01-01T00:00:00.000',
          'date': '2026-01-01T09:00:00.000',
          'createdAt': '2026-01-01T09:00:00.000',
          'updatedAt': '2026-01-01T09:00:00.000',
          'subtasks': [
            {'id': 'a', 'title': 'A', 'isCompleted': false, 'sortOrder': 0},
            {'id': 'b', 'title': 'B', 'isCompleted': true, 'sortOrder': 1},
          ],
        },
      ]),
    });

    final provider = TodoProvider();
    await provider.loadFromStorage();

    final todo = provider.todos.single;
    expect(todo.isCompleted, isFalse);
    expect(todo.completedAt, isNull);
    // 纠正后的状态会被写回存储。
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('todos');
    expect(stored, isNot(contains('"completedAt":"2026-01-01T00:00:00.000"')));
  });
}
