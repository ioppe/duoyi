import 'package:duoyi/core/focus_task_stats.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/models/todo.dart';
import 'package:flutter_test/flutter_test.dart';

PomodoroSession session(
  String id,
  int seconds, {
  String? todoId,
  String? subtaskId,
  String? name,
  String? parent,
  PomodoroType type = PomodoroType.focus,
}) => PomodoroSession(
  id: id,
  startTime: DateTime.utc(2026, 10, 22, 10),
  endTime: DateTime.utc(2026, 10, 22, 10).add(Duration(seconds: seconds)),
  durationSeconds: seconds,
  type: type,
  taskName: name,
  todoId: todoId,
  subtaskId: subtaskId,
  todoTitle: parent,
);

void main() {
  test(
    'parent totals include each child session once and keep direct focus separate',
    () {
      final result = FocusTaskStats.build(
        sessions: [
          session('parent', 60, todoId: 'a', name: '计划', parent: '计划'),
          session(
            'child-1',
            45,
            todoId: 'a',
            subtaskId: 'c',
            name: '调研',
            parent: '计划',
          ),
          session(
            'child-2',
            45,
            todoId: 'a',
            subtaskId: 'c',
            name: '调研',
            parent: '计划',
          ),
          session(
            'rest',
            300,
            todoId: 'a',
            name: '计划',
            type: PomodoroType.shortBreak,
          ),
        ],
      );
      final task = result.single;
      expect(task.seconds, 150);
      expect(task.sessions, 3);
      expect(task.parts.fold<int>(0, (sum, part) => sum + part.seconds), 150);
      expect(task.parts.first.subtaskId, 'c');
      expect(task.parts.first.seconds, 90);
      expect(task.parts.first.sessions, 2);
      expect(task.parts.last.subtaskId, isNull);
    },
  );

  test('same titles do not merge distinct tasks or legacy free-form names', () {
    final result = FocusTaskStats.build(
      sessions: [
        session('1', 60, todoId: 'a', name: '阅读'),
        session('2', 60, todoId: 'b', name: '阅读'),
        session('3', 60, name: '阅读'),
        session('4', 60),
      ],
    );
    expect(result.map((stat) => stat.key).toSet(), {
      'todo:a',
      'todo:b',
      'manual:阅读',
      'unassigned',
    });
    expect(result.fold<int>(0, (sum, stat) => sum + stat.seconds), 240);
  });

  test(
    'renames use stable IDs and deleted tasks retain their stored names',
    () {
      final saved = session(
        'a',
        90,
        todoId: 'a',
        subtaskId: 'child',
        name: '旧子任务',
        parent: '旧父任务',
      );
      final current = FocusTaskStats.build(
        sessions: [saved],
        todos: [
          TodoItem(
            id: 'a',
            title: '新父任务',
            subtasks: [Subtask(id: 'child', title: '新子任务')],
          ),
        ],
      ).single;
      expect(current.title, '新父任务');
      expect(current.parts.single.title, '新子任务');
      final deleted = FocusTaskStats.build(sessions: [saved]).single;
      expect(deleted.title, '旧父任务');
      expect(deleted.parts.single.title, '旧子任务');
    },
  );

  test(
    'zero and negative durations are excluded from time and session count',
    () {
      expect(
        FocusTaskStats.build(
          sessions: [session('zero', 0), session('negative', -1)],
        ),
        isEmpty,
      );
    },
  );
}
