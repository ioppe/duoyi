/// 周报 / 月报生成引擎（Task T-43）。
///
/// 离线汇总本地数据，输出可在"我的"页面查看的报告。不依赖 AI 服务。
library;

import '../models/habit.dart';
import '../models/pomodoro.dart';
import '../models/time_entry.dart';
import '../models/todo.dart';
import 'app_clock.dart';
import 'period_report.dart';

export 'period_report.dart';

class ReportEngine {
  ReportEngine._();

  static ReportComparison compare({
    required PeriodReport current,
    required PeriodReport previous,
  }) {
    return ReportComparison.compare(current: current, previous: previous);
  }

  /// 生成 [start, end] 区间的报告。
  ///
  /// [start]/[end] 应为日期对齐（hour=0），end 含当日。
  static PeriodReport buildReport({
    required DateTime start,
    required DateTime end,
    required List<TodoItem> todos,
    required List<Habit> habits,
    required List<PomodoroSession> sessions,
    required List<TimeEntry> timeEntries,
  }) {
    final startInstant = AppClock.date(start.year, start.month, start.day);
    final endExclusive = AppClock.date(end.year, end.month, end.day + 1);
    final startDate = AppClock.dateOnly(start);
    final endDate = DateTime(end.year, end.month, end.day + 1);

    bool inRange(DateTime d) =>
        !d.isBefore(startInstant) && d.isBefore(endExclusive);
    bool dateInRange(DateTime d) =>
        !d.isBefore(startDate) && d.isBefore(endDate);

    final created = todos.where((t) => inRange(t.createdAt)).length;
    final completed = todos.where((t) {
      final c = t.completedAt;
      return t.isCompleted && c != null && inRange(c);
    }).length;

    var habitCheckIns = 0;
    var longestStreak = 0;
    for (final h in habits) {
      for (final entry in h.completions.entries) {
        final d = _parseDateKey(entry.key);
        if (d != null && dateInRange(d) && h.activeForDate(d)) {
          habitCheckIns += entry.value;
        }
      }
      longestStreak = longestStreak > h.currentStreak
          ? longestStreak
          : h.currentStreak;
    }

    final focusSessions = sessions
        .where((s) => s.type == PomodoroType.focus && inRange(s.endTime))
        .toList();
    final focusSeconds = focusSessions.fold<int>(
      0,
      (a, s) => a + s.durationSeconds,
    );

    final periodEntries = timeEntries.where((e) => inRange(e.startAt)).toList();
    final timeEntrySeconds = periodEntries.fold<int>(
      0,
      (a, e) => a + e.durationSeconds,
    );
    final byCategory = <TimeEntryCategory, int>{};
    for (final e in periodEntries) {
      byCategory[e.category] =
          (byCategory[e.category] ?? 0) + e.durationSeconds;
    }

    return PeriodReport(
      start: start,
      end: end,
      todosCreated: created,
      todosCompleted: completed,
      habitCheckIns: habitCheckIns,
      longestHabitStreak: longestStreak,
      focusSessions: focusSessions.length,
      focusSeconds: focusSeconds,
      timeEntrySeconds: timeEntrySeconds,
      timeEntryByCategory: byCategory,
    );
  }

  /// 本周（周一—周日）。
  static PeriodReport thisWeek({
    required List<TodoItem> todos,
    required List<Habit> habits,
    required List<PomodoroSession> sessions,
    required List<TimeEntry> timeEntries,
    DateTime? now,
  }) {
    final base = now == null ? AppClock.now() : AppClock.toLocal(now);
    final start = DateTime(base.year, base.month, base.day - base.weekday + 1);
    final end = DateTime(start.year, start.month, start.day + 6);
    return buildReport(
      start: start,
      end: end,
      todos: todos,
      habits: habits,
      sessions: sessions,
      timeEntries: timeEntries,
    );
  }

  /// 本月（自然月）。
  static PeriodReport thisMonth({
    required List<TodoItem> todos,
    required List<Habit> habits,
    required List<PomodoroSession> sessions,
    required List<TimeEntry> timeEntries,
    DateTime? now,
  }) {
    final base = now == null ? AppClock.now() : AppClock.toLocal(now);
    final start = DateTime(base.year, base.month, 1);
    final end = DateTime(base.year, base.month + 1, 0);
    return buildReport(
      start: start,
      end: end,
      todos: todos,
      habits: habits,
      sessions: sessions,
      timeEntries: timeEntries,
    );
  }

  static DateTime? _parseDateKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }
}
