import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_clock.dart';
import '../core/local_timezone_resolver.dart';
import '../core/calendar_aggregator.dart';
import '../models/calendar_event.dart';
import '../models/todo.dart';
import '../models/habit.dart';
import '../models/pomodoro.dart';
import '../models/anniversary.dart';
import '../models/course_schedule.dart';
import '../models/diary_entry.dart';
import '../models/countdown.dart';
import '../models/goal.dart';
import '../models/time_entry.dart';
import 'cloud_sync_provider.dart';

class CalendarProvider extends ChangeNotifier {
  static const _localEventsKey = 'duoyi_local_calendar_events_v1';

  final List<CalendarEvent> _events = [];
  final List<CalendarEvent> _localEvents = [];
  List<CalendarEvent> _externalEvents = const <CalendarEvent>[];
  Object? _lastRebuildSignature;
  int _sourceRevision = 0;
  int _storageGeneration = 0;
  VoidCallback? onLocalEventsChanged;
  Future<void> Function(String id)? localEventReminderCanceller;

  List<CalendarEvent> get events => _events;
  List<CalendarEvent> get localEvents => List.unmodifiable(_localEvents);
  int get sourceRevision => _sourceRevision;

  Future<void> loadFromStorage() async {
    final generation = _storageGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration) return;
    final data = prefs.getStringList(_localEventsKey) ?? const <String>[];
    _localEvents
      ..clear()
      ..addAll(
        data
            .map((raw) {
              final json = jsonDecode(raw) as Map<String, dynamic>;
              return CalendarEvent.fromJson(json);
            })
            .where((event) => event.type == CalendarEventType.event),
      );
    _lastRebuildSignature = null;
    _sourceRevision++;
    notifyListeners();
  }

  void resetLocalState() {
    _storageGeneration++;
    _events.clear();
    _localEvents.clear();
    _externalEvents = const <CalendarEvent>[];
    _lastRebuildSignature = null;
    _sourceRevision++;
    notifyListeners();
  }

  Future<void> addLocalEvent(CalendarEvent event) async {
    if (!event.type.isVisible) return;
    _localEvents.add(_asLocalEvent(event));
    await _saveLocalEvents();
  }

  Future<CalendarEventImportSummary> importLocalEvents(
    Iterable<CalendarEvent> events,
  ) async {
    var inserted = 0;
    var skippedDuplicates = 0;
    final seen = _localEvents.map(_importDuplicateKey).toSet();
    for (final event in events) {
      if (!event.type.isVisible) continue;
      if (event.title.trim().isEmpty) continue;
      final key = _importDuplicateKey(event);
      if (seen.contains(key)) {
        skippedDuplicates++;
        continue;
      }
      seen.add(key);
      _localEvents.add(_asLocalEvent(event));
      inserted++;
    }
    if (inserted > 0) {
      await _saveLocalEvents();
    }
    return CalendarEventImportSummary(
      inserted: inserted,
      skippedDuplicates: skippedDuplicates,
    );
  }

  Future<void> updateLocalEvent(CalendarEvent event) async {
    if (!event.type.isVisible) return;
    final index = _localEvents.indexWhere((e) => e.id == event.id);
    if (index == -1) return;
    _localEvents[index] = _asLocalEvent(event);
    await _saveLocalEvents();
  }

  Future<void> deleteLocalEvent(String id) async {
    try {
      await localEventReminderCanceller?.call(id);
    } catch (e, st) {
      debugPrint(
        '[CalendarProvider] local event reminder cancel failed: $e\n$st',
      );
    }
    await CloudSyncProvider.recordDeletedItem('calendar_events', id);
    _localEvents.removeWhere((event) => event.id == id);
    await _saveLocalEvents();
  }

  Future<void> _saveLocalEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _localEvents
        .map((event) => jsonEncode(event.toJson()))
        .toList(growable: false);
    await prefs.setStringList(_localEventsKey, data);
    _lastRebuildSignature = null;
    _sourceRevision++;
    onLocalEventsChanged?.call();
    _notifyListenersSafely();
  }

  CalendarEvent _asLocalEvent(CalendarEvent event) {
    final id = event.id.isEmpty
        ? 'local_${DateTime.now().microsecondsSinceEpoch}'
        : event.id;
    return event.copyWith(
      id: id,
      type: CalendarEventType.event,
      sourceId: event.sourceId?.isNotEmpty == true ? event.sourceId : id,
      updatedAt: event.updatedAt ?? DateTime.now(),
    );
  }

  /// 设置外部订阅事件（来自 ICS 订阅）。会触发下次 rebuild 时合并。
  // ignore: use_setters_to_change_properties
  void setExternalEvents(List<CalendarEvent> events) {
    final next = List<CalendarEvent>.unmodifiable(
      events.where((event) => event.type.isVisible),
    );
    if (_eventsEqual(_externalEvents, next)) return;
    _externalEvents = next;
    _lastRebuildSignature = null;
    _sourceRevision++;
    _notifyListenersSafely();
  }

  /// 重建所有事件索引。
  /// 新增的 anniversaries/courses/diaries/countdowns/goals 均以可选参数传入，保证调用方兼容。
  void rebuild(
    List<TodoItem> todos,
    List<Habit> habits,
    List<PomodoroSession> pomodoroSessions,
    ColorScheme colorScheme, {
    List<Anniversary>? anniversaries,
    List<CourseItem>? courses,
    ScheduleSettings? courseSettings,
    List<DiaryEntry>? diaries,
    List<CountdownItem>? countdowns,
    List<GoalItem>? goals,
    List<TimeEntry>? timeEntries,
  }) {
    final signature = _buildSignature(
      todos,
      habits,
      pomodoroSessions,
      colorScheme,
      anniversaries: anniversaries,
      courses: courses,
      courseSettings: courseSettings,
      countdowns: countdowns,
      goals: goals,
      timeEntries: timeEntries,
    );
    if (_lastRebuildSignature == signature) return;

    final previousEvents = List<CalendarEvent>.of(_events);
    final nextEvents = CalendarAggregator.buildEvents(
      todos: todos,
      habits: habits,
      pomodoroSessions: pomodoroSessions,
      colorScheme: colorScheme,
      anniversaries: anniversaries,
      courses: courses,
      courseSettings: courseSettings,
      countdowns: countdowns,
      goals: goals,
      timeEntries: timeEntries,
    );
    _events
      ..clear()
      ..addAll(nextEvents.map(_inAppTimeZone))
      ..addAll(_localEvents.map(_inAppTimeZone))
      ..addAll(_externalEvents.map(_inAppTimeZone));

    if (!_eventsEqual(previousEvents, _events)) {
      _lastRebuildSignature = signature;
      _notifyListenersSafely();
      return;
    }
    _lastRebuildSignature = signature;
  }

  CalendarEvent _inAppTimeZone(CalendarEvent event) =>
      LocalTimezoneResolver.isInitialized ? event.inAppTimeZone() : event;

  int _buildSignature(
    List<TodoItem> todos,
    List<Habit> habits,
    List<PomodoroSession> pomodoroSessions,
    ColorScheme colorScheme, {
    List<Anniversary>? anniversaries,
    List<CourseItem>? courses,
    ScheduleSettings? courseSettings,
    List<CountdownItem>? countdowns,
    List<GoalItem>? goals,
    List<TimeEntry>? timeEntries,
  }) {
    final now = AppClock.now();
    final todayKey = '${now.year}-${now.month}-${now.day}';
    return Object.hashAll([
      todayKey,
      LocalTimezoneResolver.isInitialized
          ? LocalTimezoneResolver.currentIana
          : 'system',
      colorScheme.primary,
      _hashTodos(todos),
      _hashHabits(habits),
      _hashPomodoroSessions(pomodoroSessions),
      _hashAnniversaries(anniversaries),
      _hashCourses(courses, courseSettings),
      _hashCountdowns(countdowns),
      _hashGoals(goals),
      _hashTimeEntries(timeEntries),
      _hashCalendarEvents(_localEvents),
    ]);
  }

  int _hashTodos(List<TodoItem> todos) {
    return Object.hashAll(
      todos.map((t) {
        final rule = t.reminderPlan.primaryRule;
        return Object.hashAll([
          t.id,
          t.title,
          t.date.millisecondsSinceEpoch,
          t.dueDate?.millisecondsSinceEpoch,
          t.reminderAt?.millisecondsSinceEpoch,
          // ignore: deprecated_member_use_from_same_package
          t.hasReminder,
          t.reminder.enabled,
          t.reminder.kind.index,
          t.reminder.hour,
          t.reminder.minute,
          t.reminder.daysBefore,
          t.reminderPlan.enabled,
          rule?.enabled,
          rule?.type.index,
          rule?.kind.index,
          rule?.hour,
          rule?.minute,
          rule?.offsetMinutes,
          Object.hashAll(rule?.weekdays ?? const <int>[]),
          t.isCompleted,
          t.listGroupId,
          t.listGroupName,
          t.workspaceId,
        ]);
      }),
    );
  }

  int _hashHabits(List<Habit> habits) {
    return Object.hashAll(
      habits.map((h) {
        final completions = h.completions.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        return Object.hashAll([
          h.id,
          h.name,
          h.colorValue,
          h.kind.index,
          h.targetCount,
          h.unit,
          Object.hashAll(h.activeWeekdays),
          h.weeklyTarget,
          h.startDate?.millisecondsSinceEpoch,
          h.endDate?.millisecondsSinceEpoch,
          Object.hashAll(completions.map((e) => Object.hash(e.key, e.value))),
        ]);
      }),
    );
  }

  int _hashPomodoroSessions(List<PomodoroSession> sessions) {
    return Object.hashAll(
      sessions.map(
        (s) => Object.hash(
          s.id,
          s.startTime.millisecondsSinceEpoch,
          s.endTime.millisecondsSinceEpoch,
          s.durationSeconds,
          s.type.index,
          s.taskName,
          s.whiteNoiseSound,
        ),
      ),
    );
  }

  int _hashAnniversaries(List<Anniversary>? anniversaries) {
    if (anniversaries == null) return 0;
    return Object.hashAll(
      anniversaries.map(
        (a) => Object.hash(
          a.id,
          a.title,
          a.originDate.millisecondsSinceEpoch,
          a.type.index,
          a.calendarType.index,
          a.colorValue,
          a.lunarYear,
          a.lunarMonth,
          a.lunarDay,
          a.lunarIsLeap,
          a.ignoreYear,
          a.updatedAt.millisecondsSinceEpoch,
        ),
      ),
    );
  }

  int _hashCourses(List<CourseItem>? courses, ScheduleSettings? settings) {
    if (courses == null || settings == null) return 0;
    return Object.hashAll([
      settings.termStart.millisecondsSinceEpoch,
      settings.totalWeeks,
      settings.sessionsPerDay,
      settings.sessionMinutes,
      Object.hashAll(
        courses.map(
          (c) => Object.hash(
            c.id,
            c.name,
            c.weekday,
            c.startSection,
            c.sectionCount,
            c.colorValue,
            Object.hashAll(c.weeks),
          ),
        ),
      ),
    ]);
  }

  int _hashCountdowns(List<CountdownItem>? countdowns) {
    if (countdowns == null) return 0;
    return Object.hashAll(
      countdowns.map(
        (c) => Object.hash(
          c.id,
          c.title,
          c.targetDate.millisecondsSinceEpoch,
          c.isPinned,
        ),
      ),
    );
  }

  int _hashGoals(List<GoalItem>? goals) {
    if (goals == null) return 0;
    return Object.hashAll(
      goals.map(
        (g) => Object.hash(
          g.id,
          g.title,
          g.targetDate?.millisecondsSinceEpoch,
          g.status.index,
          g.colorValue,
          g.autoProgress,
          g.computedProgress,
          g.workspaceId,
        ),
      ),
    );
  }

  int _hashTimeEntries(List<TimeEntry>? entries) {
    if (entries == null) return 0;
    return Object.hashAll(
      entries.map(
        (e) => Object.hash(
          e.id,
          e.title,
          e.startAt.millisecondsSinceEpoch,
          e.endAt.millisecondsSinceEpoch,
          e.category.index,
          e.source.index,
          e.sourceId,
        ),
      ),
    );
  }

  int _hashCalendarEvents(List<CalendarEvent> events) {
    return Object.hashAll(
      events.map(
        (event) => Object.hashAll([
          event.id,
          event.title,
          event.date.millisecondsSinceEpoch,
          event.endDate?.millisecondsSinceEpoch,
          event.type.index,
          event.color,
          event.subtitle,
          event.workspaceId,
          event.note,
          event.updatedAt?.millisecondsSinceEpoch,
          event.time == null
              ? null
              : Object.hash(event.time!.hour, event.time!.minute),
        ]),
      ),
    );
  }

  void _notifyListenersSafely() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (hasListeners) notifyListeners();
      });
      return;
    }
    notifyListeners();
  }

  bool _eventsEqual(List<CalendarEvent> a, List<CalendarEvent> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_eventEqual(a[i], b[i])) return false;
    }
    return true;
  }

  bool _eventEqual(CalendarEvent a, CalendarEvent b) {
    return a.id == b.id &&
        a.title == b.title &&
        a.date == b.date &&
        a.type == b.type &&
        a.color == b.color &&
        a.isCompleted == b.isCompleted &&
        a.sourceId == b.sourceId &&
        a.subtitle == b.subtitle &&
        a.projectId == b.projectId &&
        a.projectName == b.projectName &&
        a.workspaceId == b.workspaceId &&
        a.endDate == b.endDate &&
        a.hasConflict == b.hasConflict &&
        a.conflictCount == b.conflictCount &&
        a.note == b.note &&
        a.updatedAt == b.updatedAt &&
        _timeEqual(a.time, b.time);
  }

  bool _timeEqual(TimeOfDay? a, TimeOfDay? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return a.hour == b.hour && a.minute == b.minute;
  }

  List<CalendarEvent> getEventsForDate(
    DateTime date, {
    Set<CalendarEventType>? activeTypes,
    String? projectKey,
    String? workspaceId,
  }) {
    final key = _dateKey(date);
    return _events.where((e) {
      if (!e.type.isVisible) return false;
      if (!_eventOccursOnDate(e, key)) return false;
      if (activeTypes != null && !activeTypes.contains(e.type)) return false;
      if (!_matchesProject(e, projectKey)) return false;
      if (!_matchesWorkspace(e, workspaceId)) return false;
      return true;
    }).toList();
  }

  Set<DateTime> get datesWithEvents {
    final dates = <DateTime>{};
    for (final e in _events) {
      if (!e.type.isVisible) continue;
      dates.addAll(_eventDates(e));
    }
    return dates;
  }

  Map<String, List<CalendarEventType>> get dateEventTypes {
    final map = <String, Set<CalendarEventType>>{};
    for (final e in _events) {
      if (!e.type.isVisible) continue;
      for (final key in _eventDateKeys(e)) {
        map.putIfAbsent(key, () => {}).add(e.type);
      }
    }
    return map.map((k, v) => MapEntry(k, v.toList()));
  }

  /// Filtered variant: only include event types in [activeTypes].
  Map<String, List<CalendarEventType>> filteredDateEventTypes(
    Set<CalendarEventType>? activeTypes, {
    String? projectKey,
    String? workspaceId,
  }) {
    if (activeTypes == null && projectKey == null && workspaceId == null) {
      return dateEventTypes;
    }
    final map = <String, Set<CalendarEventType>>{};
    for (final e in _events) {
      if (!e.type.isVisible) continue;
      if (activeTypes != null && !activeTypes.contains(e.type)) continue;
      if (!_matchesProject(e, projectKey)) continue;
      if (!_matchesWorkspace(e, workspaceId)) continue;
      for (final key in _eventDateKeys(e)) {
        map.putIfAbsent(key, () => {}).add(e.type);
      }
    }
    return map.map((k, v) => MapEntry(k, v.toList()));
  }

  Map<String, int> filteredDateEventCounts(
    Set<CalendarEventType>? activeTypes, {
    String? projectKey,
    String? workspaceId,
  }) {
    final map = <String, int>{};
    for (final e in _events) {
      if (!e.type.isVisible) continue;
      if (activeTypes != null && !activeTypes.contains(e.type)) continue;
      if (!_matchesProject(e, projectKey)) continue;
      if (!_matchesWorkspace(e, workspaceId)) continue;
      for (final key in _eventDateKeys(e)) {
        map[key] = (map[key] ?? 0) + 1;
      }
    }
    return map;
  }

  bool _matchesProject(CalendarEvent event, String? projectKey) {
    if (projectKey == null) return true;
    if (event.type != CalendarEventType.todo) return false;
    return (event.projectKey ?? '') == projectKey;
  }

  bool _matchesWorkspace(CalendarEvent event, String? workspaceId) {
    if (workspaceId == null) return true;
    final eventWorkspaceId = event.workspaceId;
    if (workspaceId == 'private') {
      return eventWorkspaceId == null ||
          eventWorkspaceId.isEmpty ||
          eventWorkspaceId == 'private';
    }
    return eventWorkspaceId == workspaceId;
  }

  bool _eventOccursOnDate(CalendarEvent event, String dateKey) {
    return _eventDateKeys(event).contains(dateKey);
  }

  List<DateTime> _eventDates(CalendarEvent event) {
    final start = _dateOnly(event.date);
    final end = _eventVisibleEndDate(event, start);
    if (end.isBefore(start)) return <DateTime>[start];
    final dates = <DateTime>[];
    for (
      var day = start;
      !day.isAfter(end);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      dates.add(day);
    }
    return dates;
  }

  List<String> _eventDateKeys(CalendarEvent event) {
    return _eventDates(event).map(_dateKey).toList(growable: false);
  }

  DateTime _eventVisibleEndDate(CalendarEvent event, DateTime start) {
    final endDate = event.endDate;
    if (endDate == null || !endDate.isAfter(event.date)) return start;

    var end = _dateOnly(endDate);
    final endsAtMidnight =
        endDate.hour == 0 &&
        endDate.minute == 0 &&
        endDate.second == 0 &&
        endDate.millisecond == 0 &&
        endDate.microsecond == 0;
    if (endsAtMidnight && end.isAfter(start)) {
      end = DateTime(end.year, end.month, end.day - 1);
    }
    return end;
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class CalendarEventImportSummary {
  final int inserted;
  final int skippedDuplicates;

  const CalendarEventImportSummary({
    required this.inserted,
    required this.skippedDuplicates,
  });
}

String _importDuplicateKey(CalendarEvent event) {
  final end = event.endDate;
  final time = event.time;
  return [
    event.title.trim().toLowerCase(),
    event.date.toIso8601String(),
    end?.toIso8601String() ?? '',
    time == null ? '' : '${time.hour}:${time.minute}',
    event.projectName?.trim().toLowerCase() ?? '',
  ].join('|');
}
