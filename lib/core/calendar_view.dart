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
import '../providers/calendar_provider.dart';
import 'calendar_aggregator.dart';

/// A disposable calendar index for the current view. Rebuild it when the app
/// zone changes without mutating stored events or their synchronization stamps.
CalendarProvider buildCalendarView({
  required CalendarProvider source,
  required List<TodoItem> todos,
  required List<Habit> habits,
  required List<PomodoroSession> sessions,
  required ColorScheme colorScheme,
  required List<Anniversary> anniversaries,
  required List<CountdownItem> countdowns,
  required List<CourseItem> courses,
  required ScheduleSettings courseSettings,
  List<DiaryEntry> diaries = const [], // Legacy input; excluded from the view.
  required List<GoalItem> goals,
  required List<TimeEntry> timeEntries,
}) {
  final customEvents = <String, CalendarEvent>{
    for (final event in source.events)
      if (event.type == CalendarEventType.event) event.id: event,
    for (final event in source.localEvents) event.id: event,
  };
  final events = CalendarAggregator.buildEvents(
    todos: todos,
    habits: habits,
    pomodoroSessions: sessions,
    colorScheme: colorScheme,
    anniversaries: anniversaries,
    countdowns: countdowns,
    courses: courses,
    courseSettings: courseSettings,
    goals: goals,
    timeEntries: timeEntries,
  );
  final view = CalendarProvider();
  view.setExternalEvents([
    ...events,
    for (final event in customEvents.values) event.inAppTimeZone(),
  ]);
  view.rebuild(const [], const [], const [], colorScheme);
  return view;
}
