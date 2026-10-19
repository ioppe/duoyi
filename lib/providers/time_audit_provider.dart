import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_clock.dart';
import '../models/goal.dart';
import '../models/habit.dart';
import '../models/time_entry.dart';
import '../models/todo.dart';
import 'cloud_sync_provider.dart';

class TimeEntryImportSummary {
  final int inserted;
  final int skippedDuplicates;

  const TimeEntryImportSummary({
    required this.inserted,
    required this.skippedDuplicates,
  });
}

class TimeAuditProvider extends ChangeNotifier {
  static const storageKey = 'duoyi_time_entries';

  List<TimeEntry> _entries = [];
  int _storageGeneration = 0;

  List<TimeEntry> get entries {
    final sorted = [..._entries]
      ..sort((a, b) => b.startAt.compareTo(a.startAt));
    return List.unmodifiable(sorted);
  }

  Future<void> loadFromStorage() async {
    final generation = _storageGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration) return;
    final raw = prefs.getStringList(storageKey) ?? const <String>[];
    _entries = raw
        .map((e) {
          try {
            return TimeEntry.fromJson(jsonDecode(e) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<TimeEntry>()
        .toList();
    notifyListeners();
  }

  void resetLocalState() {
    _storageGeneration++;
    _entries = [];
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    // 大列表的 JSON 编码会阻塞主 isolate，挪到后台 isolate 执行（对齐
    // todo_provider 的做法）；小列表直接同步编码，省去 isolate 往返。
    final data = _entries.length >= _isolateEncodeMinItems
        ? await compute(_encodeTimeAuditPayload, List<TimeEntry>.of(_entries))
        : _entries.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(storageKey, data);
  }

  Future<void> add(TimeEntry entry) async {
    _entries.add(entry);
    await _save();
    notifyListeners();
  }

  Future<TimeEntryImportSummary> importTimeEntries(
    Iterable<TimeEntry> entries,
  ) async {
    var inserted = 0;
    var skippedDuplicates = 0;
    final seen = _entries.map(_importDuplicateKey).toSet();
    for (final entry in entries) {
      final key = _importDuplicateKey(entry);
      if (seen.contains(key)) {
        skippedDuplicates++;
        continue;
      }
      seen.add(key);
      _entries.add(entry);
      inserted++;
    }
    if (inserted > 0) {
      await _save();
      notifyListeners();
    }
    return TimeEntryImportSummary(
      inserted: inserted,
      skippedDuplicates: skippedDuplicates,
    );
  }

  Future<void> upsertAuto(TimeEntry entry) async {
    final key = entry.dedupeKey;
    if (key != null && key.isNotEmpty) {
      final idx = _entries.indexWhere((e) => e.dedupeKey == key);
      if (idx >= 0) {
        _entries[idx] = entry.copyWith();
        await _save();
        notifyListeners();
        return;
      }
    }
    await add(entry);
  }

  Future<void> deleteByDedupeKey(String dedupeKey) async {
    final removedIds = _entries
        .where((e) => e.dedupeKey == dedupeKey)
        .map((e) => e.id)
        .toList();
    if (removedIds.isEmpty) return;
    _entries.removeWhere((e) => e.dedupeKey == dedupeKey);
    await CloudSyncProvider.recordDeletedItems('time_entries', removedIds);
    await _save();
    notifyListeners();
  }

  Future<void> deleteWhere(bool Function(TimeEntry entry) test) async {
    final removedIds = _entries.where(test).map((e) => e.id).toList();
    if (removedIds.isEmpty) return;
    _entries.removeWhere(test);
    await CloudSyncProvider.recordDeletedItems('time_entries', removedIds);
    await _save();
    notifyListeners();
  }

  Future<void> deleteBySource(TimeEntrySource source, String sourceId) async {
    await deleteWhere(
      (entry) => entry.source == source && entry.sourceId == sourceId,
    );
  }

  Future<void> deleteGoalEntries(String goalId) async {
    await deleteWhere((entry) {
      if (entry.source != TimeEntrySource.goal) return false;
      final sourceId = entry.sourceId;
      if (sourceId == null) return false;
      return sourceId == goalId || sourceId.startsWith('$goalId:');
    });
  }

  Future<void> update(TimeEntry entry) async {
    final idx = _entries.indexWhere((e) => e.id == entry.id);
    if (idx < 0) return;
    _entries[idx] = entry;
    await _save();
    notifyListeners();
  }

  Future<void> delete(String id) async {
    final exists = _entries.any((e) => e.id == id);
    if (!exists) return;
    _entries.removeWhere((e) => e.id == id);
    await CloudSyncProvider.recordDeletedItem('time_entries', id);
    await _save();
    notifyListeners();
  }

  Future<void> recordPomodoroSession({
    required String sessionId,
    required String title,
    required DateTime startAt,
    required DateTime endAt,
    String? note,
  }) async {
    await upsertAuto(
      TimeEntry(
        title: title,
        startAt: startAt,
        endAt: endAt,
        category: TimeEntryCategory.focus,
        source: TimeEntrySource.pomodoro,
        sourceId: sessionId,
        dedupeKey: pomodoroDedupeKey(sessionId),
        note: note ?? '',
      ),
    );
  }

  Future<void> recordTodoCompletion(
    TodoItem todo, {
    DateTime? completedAt,
  }) async {
    final durationSeconds = _todoDurationSeconds(todo);
    if (durationSeconds == null || durationSeconds <= 0) return;
    final endAt = completedAt ?? todo.completedAt ?? DateTime.now();
    await upsertAuto(
      TimeEntry(
        title: todo.title,
        startAt: endAt.subtract(Duration(seconds: durationSeconds)),
        endAt: endAt,
        category: TimeEntryCategory.todo,
        source: TimeEntrySource.todo,
        sourceId: todo.id,
        dedupeKey: todoCompletionDedupeKey(todo.id, endAt),
        note: todo.dueDate == null ? '' : '截止：${todo.dueDate}',
      ),
    );
  }

  Future<void> removeTodoCompletion(
    TodoItem todo, {
    DateTime? completedAt,
  }) async {
    final at = completedAt ?? todo.completedAt;
    if (at == null) return;
    await deleteByDedupeKey(todoCompletionDedupeKey(todo.id, at));
  }

  Future<void> recordHabitCheckIn(
    Habit habit, {
    required int cumulativeCount,
    int amount = 1,
    DateTime? at,
  }) async {
    final seconds = _habitDurationSeconds(habit, amount);
    if (seconds == null || seconds <= 0) return;
    final endAt = at ?? DateTime.now();
    final dayKey = _dateKey(endAt);
    await upsertAuto(
      TimeEntry(
        title: habit.name,
        startAt: endAt.subtract(Duration(seconds: seconds)),
        endAt: endAt,
        category: TimeEntryCategory.habit,
        source: TimeEntrySource.habit,
        sourceId: habit.id,
        dedupeKey: habitCheckInDedupeKey(habit.id, dayKey, cumulativeCount),
        note: habit.unit == null ? '' : '单位：${habit.unit}',
      ),
    );
  }

  Future<void> removeHabitCheckIn(
    Habit habit, {
    required int count,
    DateTime? at,
  }) async {
    final endAt = at ?? DateTime.now();
    await deleteByDedupeKey(
      habitCheckInDedupeKey(habit.id, _dateKey(endAt), count),
    );
  }

  int? habitCheckInRecordedAmount(
    Habit habit, {
    required int count,
    DateTime? at,
  }) {
    final unitSeconds = habitUnitSeconds(habit);
    if (unitSeconds == null || unitSeconds <= 0) return null;
    final endAt = at ?? DateTime.now();
    final key = habitCheckInDedupeKey(habit.id, _dateKey(endAt), count);
    for (final entry in _entries) {
      if (entry.dedupeKey == key && entry.durationSeconds > 0) {
        final amount = entry.durationSeconds ~/ unitSeconds;
        return amount > 0 ? amount : null;
      }
    }
    return null;
  }

  Future<void> recordGoalMilestone(
    GoalItem goal,
    GoalMilestone milestone, {
    DateTime? completedAt,
  }) async {
    final durationSeconds = _goalDurationSeconds(goal);
    if (durationSeconds == null || durationSeconds <= 0) return;
    final endAt = completedAt ?? milestone.completedAt ?? DateTime.now();
    await upsertAuto(
      TimeEntry(
        title: '${goal.title} · ${milestone.title}',
        startAt: endAt.subtract(Duration(seconds: durationSeconds)),
        endAt: endAt,
        category: TimeEntryCategory.goal,
        source: TimeEntrySource.goal,
        sourceId: '${goal.id}:${milestone.id}',
        dedupeKey: goalMilestoneDedupeKey(goal.id, milestone.id),
        note: goal.timeTargetSeconds != null
            ? '目标时长：${goal.timeTargetSeconds! ~/ 60} 分钟'
            : '',
      ),
    );
  }

  Future<void> removeGoalMilestone(
    GoalItem goal,
    GoalMilestone milestone,
  ) async {
    await deleteByDedupeKey(goalMilestoneDedupeKey(goal.id, milestone.id));
  }

  List<TimeEntry> entriesInRange(DateTime start, DateTime end) {
    return entries.where((e) => e.overlaps(start, end)).toList();
  }

  List<TimeEntry> entriesForDate(DateTime date) {
    final start = AppClock.date(date.year, date.month, date.day);
    final end = AppClock.date(date.year, date.month, date.day + 1);
    return entriesInRange(start, end);
  }

  int totalSecondsInRange(DateTime start, DateTime end) {
    return entriesInRange(
      start,
      end,
    ).fold<int>(0, (sum, entry) => sum + _durationWithin(entry, start, end));
  }

  Map<TimeEntryCategory, int> secondsByCategory(DateTime start, DateTime end) {
    final result = <TimeEntryCategory, int>{
      for (final c in TimeEntryCategory.values) c: 0,
    };
    for (final entry in entriesInRange(start, end)) {
      result[entry.category] =
          (result[entry.category] ?? 0) + _durationWithin(entry, start, end);
    }
    return result;
  }

  Map<String, int> secondsByDay(DateTime start, DateTime end) {
    final result = <String, int>{};
    for (final entry in entriesInRange(start, end)) {
      var cursor = entry.startAt.isBefore(start) ? start : entry.startAt;
      final clippedEnd = entry.endAt.isAfter(end) ? end : entry.endAt;
      while (cursor.isBefore(clippedEnd)) {
        final day = AppClock.toLocal(cursor);
        final midnight = AppClock.date(day.year, day.month, day.day + 1);
        final segmentEnd = midnight.isBefore(clippedEnd)
            ? midnight
            : clippedEnd;
        final key = _dateKey(day);
        result[key] =
            (result[key] ?? 0) + segmentEnd.difference(cursor).inSeconds;
        cursor = segmentEnd;
      }
    }
    return result;
  }

  Map<String, int> secondsBySource(DateTime start, DateTime end) {
    final result = <String, int>{};
    for (final entry in entriesInRange(start, end)) {
      final key = entry.source.label;
      result[key] = (result[key] ?? 0) + _durationWithin(entry, start, end);
    }
    return result;
  }

  static String pomodoroDedupeKey(String sessionId) => 'pomodoro:$sessionId';

  static String todoCompletionDedupeKey(String todoId, DateTime completedAt) =>
      'todo:$todoId:${completedAt.millisecondsSinceEpoch}';

  static String habitCheckInDedupeKey(
    String habitId,
    String dateKey,
    int count,
  ) => 'habit:$habitId:$dateKey:$count';

  static String goalMilestoneDedupeKey(String goalId, String milestoneId) =>
      'goal:$goalId:milestone:$milestoneId';

  static int? habitUnitSeconds(Habit habit) {
    final unit = habit.unit?.trim();
    if (unit == null || unit.isEmpty) return null;
    final lower = unit.toLowerCase();
    if (unit.contains('小时') || lower.contains('hour') || lower == 'h') {
      return 3600;
    }
    if (unit.contains('分钟') ||
        unit.contains('分') ||
        lower.contains('min') ||
        lower == 'm') {
      return 60;
    }
    return null;
  }

  int? _todoDurationSeconds(TodoItem todo) {
    if (todo.timeTargetSeconds != null && todo.timeTargetSeconds! > 0) {
      return todo.timeTargetSeconds;
    }
    if (todo.focusLink.enabled &&
        todo.focusLink.focusSeconds != null &&
        todo.focusLink.focusSeconds! > 0) {
      return todo.focusLink.focusSeconds;
    }
    return null;
  }

  int? _habitDurationSeconds(Habit habit, int count) {
    final unitSeconds = habitUnitSeconds(habit);
    return unitSeconds == null ? null : count * unitSeconds;
  }

  int? _goalDurationSeconds(GoalItem goal) {
    if (goal.timeTargetSeconds != null && goal.timeTargetSeconds! > 0) {
      return goal.timeTargetSeconds;
    }
    if (goal.focusLink.enabled &&
        goal.focusLink.focusSeconds != null &&
        goal.focusLink.focusSeconds! > 0) {
      return goal.focusLink.focusSeconds;
    }
    return null;
  }

  int _durationWithin(TimeEntry entry, DateTime start, DateTime end) {
    final clippedStart = entry.startAt.isBefore(start) ? start : entry.startAt;
    final clippedEnd = entry.endAt.isAfter(end) ? end : entry.endAt;
    return math.max(0, clippedEnd.difference(clippedStart).inSeconds);
  }

  String _importDuplicateKey(TimeEntry entry) {
    final normalizedTitle = entry.title.trim().toLowerCase();
    final source = entry.sourceId?.trim().isNotEmpty == true
        ? '${entry.source.name}:${entry.sourceId}'
        : entry.source.name;
    return [
      normalizedTitle,
      entry.startAt.toIso8601String(),
      entry.endAt.toIso8601String(),
      entry.category.name,
      source,
    ].join('|');
  }

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// 单文件本地持久化的 JSON 编码条数阈值：超过后挪到后台 isolate 编码。
const int _isolateEncodeMinItems = 500;

List<String> _encodeTimeAuditPayload(List<TimeEntry> entries) =>
    entries.map((e) => jsonEncode(e.toJson())).toList();
