import 'package:flutter/material.dart';
import 'goal_icons.dart';
import 'i18n.dart';
import '../models/todo.dart';
import '../models/habit.dart';
import '../models/note.dart';
import '../models/diary_entry.dart';
import '../models/anniversary.dart';
import '../models/goal.dart';
import '../models/course_schedule.dart';
import '../models/countdown.dart';
import '../models/time_entry.dart';
import '../models/calendar_event.dart';

enum SearchKind {
  todo,
  habit,
  note,
  anniversary,
  countdown,
  goal,
  course,
  calendarEvent,
  timeEntry,
}

class SearchHit {
  final SearchKind kind;
  final String title;
  final String? subtitle;
  final String sourceId;
  final DateTime? when;
  final IconData? iconOverride;

  const SearchHit({
    required this.kind,
    required this.title,
    this.subtitle,
    required this.sourceId,
    this.when,
    this.iconOverride,
  });

  IconData get icon => switch (kind) {
    SearchKind.todo => Icons.check_circle_outline,
    SearchKind.habit => Icons.repeat,
    SearchKind.note => Icons.edit_note,
    SearchKind.anniversary => Icons.celebration_outlined,
    SearchKind.countdown => Icons.hourglass_bottom,
    SearchKind.goal => iconOverride ?? Icons.flag_circle_outlined,
    SearchKind.course => Icons.class_outlined,
    SearchKind.calendarEvent => Icons.event_available_outlined,
    SearchKind.timeEntry => Icons.timelapse_outlined,
  };

  String get kindLabel => switch (kind) {
    SearchKind.todo => I18n.tr('search.kind.todo'),
    SearchKind.habit => I18n.tr('search.kind.habit'),
    SearchKind.note => I18n.tr('search.kind.note'),
    SearchKind.anniversary => I18n.tr('search.kind.anniversary'),
    SearchKind.countdown => I18n.tr('search.kind.countdown'),
    SearchKind.goal => I18n.tr('search.kind.goal'),
    SearchKind.course => I18n.tr('search.kind.course'),
    SearchKind.calendarEvent => I18n.tr('search.kind.event'),
    SearchKind.timeEntry => I18n.tr('search.kind.time_entry'),
  };
}

/// 跨实体模糊搜索；纯内存，不进网络。
class GlobalSearch {
  static List<SearchHit> run({
    required String query,
    required List<TodoItem> todos,
    required List<Habit> habits,
    required List<NoteItem> notes,
    List<DiaryEntry> diaries = const [], // Legacy callers; never indexed.
    required List<Anniversary> anniversaries,
    required List<CountdownItem> countdowns,
    required List<GoalItem> goals,
    required List<CourseItem> courses,
    List<CalendarEvent> calendarEvents = const [],
    List<TimeEntry> timeEntries = const [],
    int maxPerKind = 10,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    bool hit(String? s) => s != null && s.toLowerCase().contains(q);

    final hits = <SearchHit>[];

    hits.addAll(
      todos
          .where((t) => hit(t.title) || hit(t.notes) || hit(t.listGroupName))
          .take(maxPerKind)
          .map(
            (t) => SearchHit(
              kind: SearchKind.todo,
              title: t.title,
              subtitle: t.listGroupName ?? t.notes,
              sourceId: t.id,
              when: t.date,
            ),
          ),
    );

    hits.addAll(
      habits
          .where((h) => hit(h.name) || hit(h.category))
          .take(maxPerKind)
          .map(
            (h) => SearchHit(
              kind: SearchKind.habit,
              title: h.name,
              subtitle: h.category,
              sourceId: h.id,
            ),
          ),
    );

    hits.addAll(
      notes
          .where((n) => hit(n.content))
          .take(maxPerKind)
          .map(
            (n) => SearchHit(
              kind: SearchKind.note,
              title: n.title,
              subtitle: n.preview,
              sourceId: n.id,
              when: n.updatedAt,
            ),
          ),
    );

    hits.addAll(
      anniversaries
          .where((a) => hit(a.title) || hit(a.description))
          .take(maxPerKind)
          .map(
            (a) => SearchHit(
              kind: SearchKind.anniversary,
              title: a.title,
              subtitle: a.description,
              sourceId: a.id,
              when: a.nextOccurrence,
            ),
          ),
    );

    hits.addAll(
      countdowns
          .where((c) => hit(c.title))
          .take(maxPerKind)
          .map(
            (c) => SearchHit(
              kind: SearchKind.countdown,
              title: c.title,
              sourceId: c.id,
              when: c.targetDate,
            ),
          ),
    );

    hits.addAll(
      goals
          .where((g) => hit(g.title) || hit(g.description))
          .take(maxPerKind)
          .map(
            (g) => SearchHit(
              kind: SearchKind.goal,
              title: g.title,
              subtitle: g.description.isEmpty ? null : g.description,
              sourceId: g.id,
              when: g.targetDate,
              iconOverride: goalIconFromName(g.icon),
            ),
          ),
    );

    hits.addAll(
      courses
          .where(
            (c) =>
                hit(c.name) || hit(c.teacher) || hit(c.location) || hit(c.note),
          )
          .take(maxPerKind)
          .map(
            (c) => SearchHit(
              kind: SearchKind.course,
              title: c.name,
              subtitle:
                  '${c.teacher.isEmpty ? '' : '${c.teacher} · '}${c.location}',
              sourceId: c.id,
            ),
          ),
    );

    hits.addAll(
      calendarEvents
          .where((event) => event.type == CalendarEventType.event)
          .where(
            (event) =>
                hit(event.title) ||
                hit(event.subtitle) ||
                hit(event.note) ||
                hit(event.projectName),
          )
          .take(maxPerKind)
          .map(
            (event) => SearchHit(
              kind: SearchKind.calendarEvent,
              title: event.title,
              subtitle: event.subtitle ?? event.note ?? event.projectName,
              sourceId: event.sourceId?.isNotEmpty == true
                  ? event.sourceId!
                  : event.id,
              when: event.date,
            ),
          ),
    );

    hits.addAll(
      timeEntries
          .where((e) => hit(e.title) || hit(e.note))
          .take(maxPerKind)
          .map(
            (e) => SearchHit(
              kind: SearchKind.timeEntry,
              title: e.title,
              subtitle: e.note,
              sourceId: e.id,
              when: e.startAt,
            ),
          ),
    );

    return hits;
  }
}
