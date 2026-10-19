import 'package:timezone/timezone.dart' as tz;

import 'app_clock.dart';

const Object _unset = Object();
const String ungroupedTodoListName = '未分组';

enum TodoDueFilter { all, overdue, dueToday, next7Days, noDue }

enum TodoCompletionFilter { all, active, completed }

class TodoFilterState<Q, P> {
  final Q? quadrant;
  final P? priority;
  final String? tag;
  final String? listGroupName;
  final TodoDueFilter due;
  final TodoCompletionFilter completion;
  final bool includeArchived;

  const TodoFilterState({
    this.quadrant,
    this.priority,
    this.tag,
    this.listGroupName,
    this.due = TodoDueFilter.all,
    this.completion = TodoCompletionFilter.all,
    this.includeArchived = false,
  });

  bool get hasActiveFilters =>
      quadrant != null ||
      priority != null ||
      tag != null ||
      listGroupName != null ||
      due != TodoDueFilter.all ||
      completion != TodoCompletionFilter.all ||
      includeArchived;

  TodoFilterState<Q, P> copyWith({
    Object? quadrant = _unset,
    Object? priority = _unset,
    Object? tag = _unset,
    Object? listGroupName = _unset,
    TodoDueFilter? due,
    TodoCompletionFilter? completion,
    bool? includeArchived,
  }) {
    return TodoFilterState<Q, P>(
      quadrant: identical(quadrant, _unset) ? this.quadrant : quadrant as Q?,
      priority: identical(priority, _unset) ? this.priority : priority as P?,
      tag: identical(tag, _unset) ? this.tag : _normalizedFilterText(tag),
      listGroupName: identical(listGroupName, _unset)
          ? this.listGroupName
          : _normalizedFilterText(listGroupName),
      due: due ?? this.due,
      completion: completion ?? this.completion,
      includeArchived: includeArchived ?? this.includeArchived,
    );
  }
}

List<T> filterTodos<T, Q, P>(
  Iterable<T> todos,
  TodoFilterState<Q, P> filter, {
  DateTime? now,
  required Q Function(T todo) quadrantOf,
  required P Function(T todo) priorityOf,
  required Iterable<String> Function(T todo) tagsOf,
  required String? Function(T todo) listGroupNameOf,
  required DateTime? Function(T todo) dueDateOf,
  required bool Function(T todo) isCompletedOf,
  required bool Function(T todo) isArchivedAfterRolloverOf,
}) {
  final reference = now ?? AppClock.now();
  final today = _dateOnly(reference);
  final next7Days = today.add(const Duration(days: 6));

  return todos.where((todo) {
    if (!filter.includeArchived && isArchivedAfterRolloverOf(todo)) {
      return false;
    }

    switch (filter.completion) {
      case TodoCompletionFilter.all:
        break;
      case TodoCompletionFilter.active:
        if (isCompletedOf(todo)) return false;
        break;
      case TodoCompletionFilter.completed:
        if (!isCompletedOf(todo)) return false;
        break;
    }

    final quadrant = filter.quadrant;
    if (quadrant != null && quadrantOf(todo) != quadrant) return false;

    final priority = filter.priority;
    if (priority != null && priorityOf(todo) != priority) return false;

    final tag = filter.tag;
    if (tag != null && !tagsOf(todo).contains(tag)) return false;

    final listGroupName = filter.listGroupName;
    if (listGroupName != null &&
        todoListGroupName(listGroupNameOf(todo)) != listGroupName) {
      return false;
    }

    final rawDue = dueDateOf(todo);
    final due = rawDue == null ? null : todoDateInAppZone(rawDue);
    switch (filter.due) {
      case TodoDueFilter.all:
        return true;
      case TodoDueFilter.overdue:
        return due != null &&
            !isCompletedOf(todo) &&
            todoDueAt(due).isBefore(reference);
      case TodoDueFilter.dueToday:
        return due != null && _dateOnly(due) == today;
      case TodoDueFilter.next7Days:
        if (due == null) return false;
        final dueDay = _dateOnly(due);
        return !dueDay.isBefore(today) && !dueDay.isAfter(next7Days);
      case TodoDueFilter.noDue:
        return due == null;
    }
  }).toList();
}

Map<Q, List<T>> groupTodosByQuadrant<T, Q>(
  Iterable<T> todos, {
  required Iterable<Q> quadrants,
  required Q Function(T todo) quadrantOf,
}) {
  final groups = <Q, List<T>>{};
  for (final quadrant in quadrants) {
    groups[quadrant] = <T>[];
  }
  for (final todo in todos) {
    groups.putIfAbsent(quadrantOf(todo), () => <T>[]).add(todo);
  }
  return groups;
}

Map<String, List<T>> groupTodosByList<T>(
  Iterable<T> todos,
  String? Function(T todo) listGroupNameOf,
) {
  final groups = <String, List<T>>{};
  for (final todo in todos) {
    groups
        .putIfAbsent(todoListGroupName(listGroupNameOf(todo)), () => <T>[])
        .add(todo);
  }
  return groups;
}

List<String> collectTodoTags<T>(
  Iterable<T> todos,
  Iterable<String> Function(T todo) tagsOf,
) {
  final tags = <String>{};
  for (final todo in todos) {
    for (final tag in tagsOf(todo)) {
      final normalized = _normalizedFilterText(tag);
      if (normalized != null) tags.add(normalized);
    }
  }
  return tags.toList()..sort();
}

List<String> collectTodoListGroups<T>(
  Iterable<T> todos,
  String? Function(T todo) listGroupNameOf,
) {
  final groups = <String>{};
  for (final todo in todos) {
    groups.add(todoListGroupName(listGroupNameOf(todo)));
  }
  return groups.toList()..sort();
}

String todoListGroupName(String? listGroupName) {
  final name = listGroupName?.trim();
  if (name == null || name.isEmpty) return ungroupedTodoListName;
  return name;
}

String? _normalizedFilterText(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Date-only deadlines float; timestamps keep their instant, while legacy
/// offset-free times are wall times in the selected application zone.
DateTime todoDateInAppZone(DateTime value) {
  if (value.isUtc || value is tz.TZDateTime) return AppClock.toLocal(value);
  if (_isDateOnly(value)) return AppClock.dateOnly(value);
  return AppClock.date(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
    value.second,
    value.millisecond,
    value.microsecond,
  );
}

DateTime todoDueAt(DateTime value) {
  final local = todoDateInAppZone(value);
  return !value.isUtc && value is! tz.TZDateTime && _isDateOnly(value)
      ? AppClock.date(local.year, local.month, local.day, 23, 59, 59, 999, 999)
      : local;
}

bool _isDateOnly(DateTime value) =>
    value.hour == 0 &&
    value.minute == 0 &&
    value.second == 0 &&
    value.millisecond == 0 &&
    value.microsecond == 0;

String serializeTodoDueDate(DateTime value) =>
    !value.isUtc && value is! tz.TZDateTime && _isDateOnly(value)
    ? AppClock.dateOnly(value).toIso8601String()
    : todoDateInAppZone(value).toUtc().toIso8601String();
