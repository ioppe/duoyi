import '../models/pomodoro.dart';
import '../models/todo.dart';

class FocusTaskPart {
  final String? subtaskId;
  final String? title;
  final int seconds;
  final int sessions;

  const FocusTaskPart({
    this.subtaskId,
    this.title,
    required this.seconds,
    required this.sessions,
  });
}

class FocusTaskSummary {
  final String key;
  final String? todoId;
  final String? title;
  final int seconds;
  final int sessions;
  final List<FocusTaskPart> parts;

  const FocusTaskSummary({
    required this.key,
    this.todoId,
    this.title,
    required this.seconds,
    required this.sessions,
    required this.parts,
  });
}

/// Call with period-filtered sessions (membership is determined by endTime).
/// One session contributes once to its parent and once to its detail breakdown.
class FocusTaskStats {
  static List<FocusTaskSummary> build({
    required Iterable<PomodoroSession> sessions,
    Iterable<TodoItem> todos = const [],
  }) {
    final current = {for (final todo in todos) todo.id: todo};
    final groups = <String, List<PomodoroSession>>{};
    for (final session in sessions) {
      if (session.type != PomodoroType.focus || session.durationSeconds <= 0) {
        continue;
      }
      final id = _text(session.todoId);
      final name = _text(session.taskName);
      final key = id != null
          ? 'todo:$id'
          : name != null
          ? 'manual:$name'
          : 'unassigned';
      groups.putIfAbsent(key, () => []).add(session);
    }
    final result = <FocusTaskSummary>[];
    for (final entry in groups.entries) {
      final ordered = entry.value
        ..sort((a, b) => b.endTime.compareTo(a.endTime));
      final latest = ordered.first;
      final todoId = _text(latest.todoId);
      final todo = current[todoId];
      final title = todoId == null
          ? _text(latest.taskName)
          : _text(todo?.title) ??
                ordered
                    .map((s) => _text(s.todoTitle))
                    .whereType<String>()
                    .firstOrNull ??
                _text(latest.taskName);
      final children = <String?, List<PomodoroSession>>{};
      for (final session in ordered) {
        final childId = todoId == null ? null : _text(session.subtaskId);
        children.putIfAbsent(childId, () => []).add(session);
      }
      final parts = <FocusTaskPart>[];
      for (final child in children.entries) {
        String? childTitle;
        if (child.key != null) {
          final existing = todo?.subtasks
              .where((s) => s.id == child.key)
              .firstOrNull;
          childTitle =
              _text(existing?.title) ?? _text(child.value.first.taskName);
        }
        parts.add(
          FocusTaskPart(
            subtaskId: child.key,
            title: childTitle,
            seconds: child.value.fold(0, (sum, s) => sum + s.durationSeconds),
            sessions: child.value.length,
          ),
        );
      }
      parts.sort((a, b) => b.seconds.compareTo(a.seconds));
      result.add(
        FocusTaskSummary(
          key: entry.key,
          todoId: todoId,
          title: title,
          seconds: ordered.fold(0, (sum, s) => sum + s.durationSeconds),
          sessions: ordered.length,
          parts: List.unmodifiable(parts),
        ),
      );
    }
    result.sort((a, b) {
      final seconds = b.seconds.compareTo(a.seconds);
      return seconds != 0 ? seconds : a.key.compareTo(b.key);
    });
    return result;
  }

  static String? _text(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
}
