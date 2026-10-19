import 'package:flutter/material.dart';

import '../models/anniversary.dart';
import '../models/calendar_event.dart';
import '../models/countdown.dart';
import '../models/course_schedule.dart';
import '../models/diary_entry.dart';
import '../models/goal.dart';
import '../models/habit.dart';
import '../models/pomodoro.dart';
import '../models/time_entry.dart';
import '../models/todo.dart';
import 'app_clock.dart';
import 'completion_visibility_policy.dart';

class CalendarAggregator {
  CalendarAggregator._();

  static List<CalendarEvent> buildEvents({
    required List<TodoItem> todos,
    required List<Habit> habits,
    required List<PomodoroSession> pomodoroSessions,
    required ColorScheme colorScheme,
    List<Anniversary>? anniversaries,
    List<CourseItem>? courses,
    ScheduleSettings? courseSettings,
    List<DiaryEntry>? diaries,
    List<CountdownItem>? countdowns,
    List<GoalItem>? goals,
    List<TimeEntry>? timeEntries,
    DateTime? now,
  }) {
    final reference = now ?? AppClock.now();
    final events = <CalendarEvent>[
      ..._todoEvents(todos, colorScheme, reference),
      ..._habitEvents(habits),
      ..._pomodoroEvents(pomodoroSessions),
      ..._timeEntryEvents(timeEntries ?? const <TimeEntry>[]),
      ..._anniversaryEvents(anniversaries ?? const <Anniversary>[]),
      ..._countdownEvents(countdowns ?? const <CountdownItem>[]),
      ..._courseEvents(courses ?? const <CourseItem>[], courseSettings),
      ..._goalEvents(goals ?? const <GoalItem>[]),
    ];
    events.sort(_compareEvents);
    return _markConflicts(events);
  }

  static List<CalendarEvent> _todoEvents(
    List<TodoItem> todos,
    ColorScheme colorScheme,
    DateTime now,
  ) => [for (final t in todos) _todoEvent(t, colorScheme, now)];

  static CalendarEvent _todoEvent(
    TodoItem t,
    ColorScheme colorScheme,
    DateTime now,
  ) {
    final anchor = _todoCalendarAnchor(t);
    return CalendarEvent(
      id: 'todo_${t.id}',
      title: t.title,
      subtitle: t.localDueDate == null
          ? null
          : '截止 ${_formatDateTime(t.localDueDate!)}',
      date: anchor.date,
      endDate: _todoVisibleEndDate(t, now),
      type: CalendarEventType.todo,
      color: colorScheme.primary,
      isCompleted: t.isCompleted,
      sourceId: t.id,
      projectId: t.listGroupId,
      projectName: t.listGroupName,
      workspaceId: t.workspaceId,
      time: anchor.time,
    );
  }

  static _TodoCalendarAnchor _todoCalendarAnchor(TodoItem t) {
    final plan = t.reminderPlan;
    final rule = plan.enabled ? plan.primaryRule : null;
    if (rule != null &&
        rule.enabled &&
        rule.kind != ReminderKind.off &&
        _validClock(rule.hour, rule.minute)) {
      final hour = rule.hour!;
      final minute = rule.minute!;
      switch (rule.type) {
        case ReminderRuleType.dailyTime:
        case ReminderRuleType.weeklyTime:
          return _timedAnchor(t.date, hour, minute);
        case ReminderRuleType.relativeToDue:
          final due = t.localDueDate;
          if (due != null) {
            return _timedAnchor(
              due,
              hour,
              minute,
              offsetMinutes: rule.offsetMinutes,
            );
          }
          break;
        case ReminderRuleType.absolute:
          final reminderAt = t.reminderAt;
          if (reminderAt != null) return _timedAnchorFromDateTime(reminderAt);
          return _timedAnchor(t.localDueDate ?? t.date, hour, minute);
      }
    }

    final legacyReminderAt = t.reminderAt;
    if (legacyReminderAt != null) {
      return _timedAnchorFromDateTime(legacyReminderAt);
    }

    final legacy = t.reminder;
    if (legacy.enabled && _validClock(legacy.hour, legacy.minute)) {
      return _timedAnchor(
        t.localDueDate ?? t.date,
        legacy.hour!,
        legacy.minute!,
      );
    }

    final due = t.localDueDate;
    if (due != null && _hasClockTime(due)) {
      return _TodoCalendarAnchor(
        CompletionVisibilityPolicy.dateOnly(t.date),
        TimeOfDay.fromDateTime(due),
      );
    }

    final created = AppClock.toLocal(t.createdAt);
    return _timedAnchor(t.date, created.hour, created.minute);
  }

  static _TodoCalendarAnchor _timedAnchor(
    DateTime date,
    int hour,
    int minute, {
    int? offsetMinutes,
  }) {
    final base = AppClock.date(date.year, date.month, date.day, hour, minute);
    final shifted = offsetMinutes == null
        ? base
        : base.add(Duration(minutes: offsetMinutes));
    return _timedAnchorFromDateTime(shifted);
  }

  static _TodoCalendarAnchor _timedAnchorFromDateTime(DateTime date) {
    final local = AppClock.toLocal(date);
    return _TodoCalendarAnchor(local, TimeOfDay.fromDateTime(local));
  }

  static bool _validClock(int? hour, int? minute) {
    return hour != null &&
        minute != null &&
        hour >= 0 &&
        hour <= 23 &&
        minute >= 0 &&
        minute <= 59;
  }

  static bool _hasClockTime(DateTime date) {
    return date.hour != 0 ||
        date.minute != 0 ||
        date.second != 0 ||
        date.millisecond != 0 ||
        date.microsecond != 0;
  }

  static DateTime? _todoVisibleEndDate(TodoItem todo, DateTime now) {
    final start = CompletionVisibilityPolicy.dateOnly(todo.date);
    final today = CompletionVisibilityPolicy.dateOnly(now);
    final due = todo.localDueDate;
    if (due == null) {
      if (!todo.isCompleted) {
        if (today.isBefore(start)) return null;
        return _endOfLocalDay(today);
      }
      final completed = todo.completedAt == null
          ? start
          : CompletionVisibilityPolicy.dateOnly(
              AppClock.toLocal(todo.completedAt!),
            );
      final visibleEnd = completed.isBefore(start) ? start : completed;
      return _endOfLocalDay(visibleEnd);
    }

    final dueDay = CompletionVisibilityPolicy.dateOnly(due);
    if (dueDay.isBefore(start)) return null;
    if (CompletionVisibilityPolicy.isDateOnly(due)) {
      return _endOfLocalDay(dueDay);
    }
    return due;
  }

  static List<CalendarEvent> _habitEvents(List<Habit> habits) {
    final events = <CalendarEvent>[];
    for (final h in habits) {
      for (final entry in h.completions.entries) {
        final date = _parseDateKey(entry.key);
        if (date == null) continue;
        if (!h.activeForDate(date)) continue;
        events.add(
          CalendarEvent(
            id: 'habit_${h.id}_${entry.key}',
            title: h.name,
            subtitle: h.formatCountForDate(date),
            date: date,
            type: CalendarEventType.habit,
            color: Color(h.colorValue),
            isCompleted: h.isCompletedForDate(date),
            sourceId: h.id,
          ),
        );
      }
    }
    return events;
  }

  static List<CalendarEvent> _pomodoroEvents(List<PomodoroSession> sessions) {
    return [
      for (final s in sessions)
        if (s.type == PomodoroType.focus)
          CalendarEvent(
            id: 'pomodoro_${s.id}',
            title: s.taskName ?? '专注 ${s.durationSeconds ~/ 60} 分钟',
            subtitle: _formatDuration(s.durationSeconds),
            date: AppClock.toLocal(s.startTime),
            endDate: AppClock.toLocal(s.endTime),
            type: CalendarEventType.pomodoro,
            color: const Color(0xFFE53935),
            isCompleted: true,
            sourceId: s.id,
            time: TimeOfDay.fromDateTime(AppClock.toLocal(s.startTime)),
          ),
    ];
  }

  static List<CalendarEvent> _timeEntryEvents(List<TimeEntry> entries) {
    return [
      for (final entry in entries)
        CalendarEvent(
          id: 'time_${entry.id}',
          title: entry.title,
          subtitle:
              '${entry.category.label} · ${_formatDuration(entry.durationSeconds)}',
          date: AppClock.toLocal(entry.startAt),
          endDate: AppClock.toLocal(entry.endAt),
          type: CalendarEventType.timeEntry,
          color: _timeEntryColor(entry.category),
          sourceId: entry.id,
          time: TimeOfDay.fromDateTime(AppClock.toLocal(entry.startAt)),
        ),
    ];
  }

  static List<CalendarEvent> _anniversaryEvents(
    List<Anniversary> anniversaries,
  ) {
    return [
      for (final a in anniversaries)
        CalendarEvent(
          id: 'anniversary_${a.id}',
          title: a.title,
          subtitle: a.yearsPassed == null
              ? '还有 ${a.daysRemaining} 天'
              : '第 ${a.yearsPassed! + 1} 次',
          date: a.nextOccurrence,
          type: CalendarEventType.anniversary,
          color: Color(a.colorValue),
          sourceId: a.id,
        ),
    ];
  }

  static List<CalendarEvent> _countdownEvents(List<CountdownItem> countdowns) {
    return [
      for (final c in countdowns)
        CalendarEvent(
          id: 'countdown_${c.id}',
          title: c.title,
          subtitle: c.daysRemaining >= 0
              ? '还有 ${c.daysRemaining} 天'
              : '已过 ${-c.daysRemaining} 天',
          date: c.targetDate,
          type: CalendarEventType.countdown,
          color: const Color(0xFFE91E63),
          isCompleted: c.daysRemaining < 0,
          sourceId: c.id,
        ),
    ];
  }

  static List<CalendarEvent> _courseEvents(
    List<CourseItem> courses,
    ScheduleSettings? settings,
  ) {
    if (settings == null) return const <CalendarEvent>[];
    final events = <CalendarEvent>[];
    for (final course in courses) {
      for (final week in course.weeks) {
        final dayOffset = (week - 1) * 7 + (course.weekday - 1);
        final date = settings.termStart.add(Duration(days: dayOffset));
        final wallStart = settings.sectionStart(date, course.startSection);
        final wallEnd = settings.sectionEnd(
          date,
          course.startSection,
          course.sectionCount,
        );
        final start = AppClock.date(
          wallStart.year,
          wallStart.month,
          wallStart.day,
          wallStart.hour,
          wallStart.minute,
        );
        final end = AppClock.date(
          wallEnd.year,
          wallEnd.month,
          wallEnd.day,
          wallEnd.hour,
          wallEnd.minute,
        );
        events.add(
          CalendarEvent(
            id: 'course_${course.id}_${week}_${course.weekday}',
            title: course.name,
            subtitle: _courseSubtitle(course, week, settings),
            date: start,
            endDate: end,
            type: CalendarEventType.course,
            color: Color(course.colorValue),
            sourceId: course.id,
            time: TimeOfDay.fromDateTime(start),
          ),
        );
      }
    }
    return events;
  }

  static List<CalendarEvent> _goalEvents(List<GoalItem> goals) {
    return [
      for (final g in goals)
        if (g.targetDate != null)
          CalendarEvent(
            id: 'goal_${g.id}',
            title: g.title,
            subtitle: g.status == GoalStatus.achieved
                ? '已达成'
                : '进度 ${(g.computedProgress * 100).round()}%',
            date: g.targetDate!,
            type: CalendarEventType.goal,
            color: Color(g.colorValue),
            isCompleted: g.status == GoalStatus.achieved,
            sourceId: g.id,
            workspaceId: g.workspaceId,
          ),
    ];
  }

  static List<CalendarEvent> _markConflicts(List<CalendarEvent> events) {
    final conflicts = <String, int>{};
    final eventsByDate = <String, List<CalendarEvent>>{};
    for (final event in events) {
      if (!_canConflict(event)) continue;
      eventsByDate.putIfAbsent(event.dateKey, () => []).add(event);
    }

    for (final sameDayEvents in eventsByDate.values) {
      for (var i = 0; i < sameDayEvents.length; i++) {
        final a = sameDayEvents[i];
        final aEnd = _endOf(a);
        for (var j = i + 1; j < sameDayEvents.length; j++) {
          final b = sameDayEvents[j];
          if (!_startOf(b).isBefore(aEnd)) break;
          if (!_overlaps(a, b)) continue;
          conflicts[a.id] = (conflicts[a.id] ?? 0) + 1;
          conflicts[b.id] = (conflicts[b.id] ?? 0) + 1;
        }
      }
    }
    if (conflicts.isEmpty) return events;
    return [
      for (final event in events)
        if (conflicts.containsKey(event.id))
          event.copyWith(hasConflict: true, conflictCount: conflicts[event.id])
        else
          event,
    ];
  }

  static bool _canConflict(CalendarEvent event) {
    return event.time != null ||
        event.endDate != null ||
        event.type == CalendarEventType.course ||
        event.type == CalendarEventType.timeEntry ||
        event.type == CalendarEventType.pomodoro;
  }

  static bool _overlaps(CalendarEvent a, CalendarEvent b) {
    final aStart = _startOf(a);
    final bStart = _startOf(b);
    final aEnd = _endOf(a);
    final bEnd = _endOf(b);
    return aStart.isBefore(bEnd) && aEnd.isAfter(bStart);
  }

  static DateTime _startOf(CalendarEvent event) {
    final time = event.time;
    if (time == null) return event.date;
    return AppClock.date(
      event.date.year,
      event.date.month,
      event.date.day,
      time.hour,
      time.minute,
    );
  }

  static DateTime _endOf(CalendarEvent event) {
    if (event.endDate != null && event.endDate!.isAfter(_startOf(event))) {
      return event.endDate!;
    }
    return _startOf(event).add(const Duration(minutes: 30));
  }

  static int _compareEvents(CalendarEvent a, CalendarEvent b) {
    final dateCompare = _startOf(a).compareTo(_startOf(b));
    if (dateCompare != 0) return dateCompare;
    return a.type.index.compareTo(b.type.index);
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

  static DateTime _endOfLocalDay(DateTime day) =>
      AppClock.date(day.year, day.month, day.day, 23, 59, 59, 999, 999);

  static Color _timeEntryColor(TimeEntryCategory category) =>
      switch (category) {
        TimeEntryCategory.focus => const Color(0xFFE53935),
        TimeEntryCategory.todo => const Color(0xFF42A5F5),
        TimeEntryCategory.habit => const Color(0xFF66BB6A),
        TimeEntryCategory.goal => const Color(0xFFAB47BC),
        TimeEntryCategory.study => const Color(0xFF26A69A),
        TimeEntryCategory.work => const Color(0xFFFF9800),
        TimeEntryCategory.life => const Color(0xFF8D6E63),
        TimeEntryCategory.other => const Color(0xFF78909C),
      };

  static String _courseSubtitle(
    CourseItem course,
    int week,
    ScheduleSettings settings,
  ) {
    final parts = <String>[
      '第 $week 周',
      '第${course.startSection}-${course.endSection}节',
      settings.sectionTimeRangeLabel(course.startSection, course.sectionCount),
    ];
    if (course.location.isNotEmpty) parts.add(course.location);
    if (course.teacher.isNotEmpty) parts.add(course.teacher);
    return parts.join(' · ');
  }

  static String _formatDateTime(DateTime date) {
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '${date.month}/${date.day} $h:$m';
  }

  static String _formatDuration(int seconds) {
    if (seconds >= 3600) {
      final hours = seconds / 3600;
      return '${hours.toStringAsFixed(seconds % 3600 == 0 ? 0 : 1)}小时';
    }
    final minutes = seconds / 60;
    return '${minutes.toStringAsFixed(seconds % 60 == 0 ? 0 : 1)}分钟';
  }
}

class _TodoCalendarAnchor {
  final DateTime date;
  final TimeOfDay? time;

  const _TodoCalendarAnchor(this.date, this.time);
}
