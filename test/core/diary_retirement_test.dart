import 'dart:convert';

import 'package:duoyi/core/achievements.dart';
import 'package:duoyi/core/calendar_aggregator.dart';
import 'package:duoyi/core/global_search.dart';
import 'package:duoyi/core/productivity_challenges.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/models/note.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/services/ics_exporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  final date = DateTime(2026, 5, 18);
  final historical = DiaryEntry(
    id: 'historical',
    date: date,
    content: 'private-content',
    tags: ['private-tag'],
    mood: Mood.good,
  );
  final retiredEvent = CalendarEvent(
    id: 'diary_historical',
    title: historical.content,
    subtitle: 'private mood',
    date: date,
    type: CalendarEventType.diary,
    color: Colors.teal,
    sourceId: historical.id,
  );
  final regularEvent = CalendarEvent(
    id: 'regular',
    title: 'keep this event',
    date: date,
    type: CalendarEventType.event,
    color: Colors.blue,
    sourceId: 'regular',
  );

  test(
    'legacy JSON retains the type and records without reopening the feature',
    () {
      final record = DiaryEntry.fromJson(historical.toJson());
      expect(record.toJson(), historical.toJson());
      final parsed = CalendarEvent.fromJson(retiredEvent.toJson());
      expect(parsed.type, CalendarEventType.diary);
      expect(parsed.toJson(), retiredEvent.toJson());
      expect(parsed.canOpen, isFalse);
      expect(parsed.type.isVisible, isFalse);
    },
  );

  test(
    'global search excludes historical contents and tags while retaining notes',
    () {
      final note = NoteItem(
        id: 'note',
        content: 'private-content in a normal note',
        createdAt: date,
        updatedAt: date,
      );
      List<SearchHit> search(String query) => GlobalSearch.run(
        query: query,
        todos: [],
        habits: [],
        notes: [note],
        diaries: [historical],
        anniversaries: [],
        countdowns: [],
        goals: [],
        courses: [],
        calendarEvents: [retiredEvent],
      );
      expect(search('private-content').map((hit) => hit.kind), [
        SearchKind.note,
      ]);
      expect(search('private-tag'), isEmpty);
      expect(
        SearchKind.values.map((kind) => kind.name),
        isNot(contains('diary')),
      );
    },
  );

  test(
    'calendar aggregation and all date indexes exclude the retired type',
    () {
      expect(
        CalendarAggregator.buildEvents(
          todos: [],
          habits: [],
          pomodoroSessions: [],
          colorScheme: const ColorScheme.light(),
          diaries: [historical],
        ),
        isEmpty,
      );
      final provider = CalendarProvider();
      addTearDown(provider.dispose);
      provider.setExternalEvents([retiredEvent, regularEvent]);
      provider.rebuild(
        [],
        [],
        [],
        const ColorScheme.light(),
        diaries: [historical],
      );
      expect(provider.events, [regularEvent]);
      expect(provider.getEventsForDate(date), [regularEvent]);
      expect(
        provider.getEventsForDate(date, activeTypes: {CalendarEventType.diary}),
        isEmpty,
      );
      expect(provider.dateEventTypes['2026-05-18'], [CalendarEventType.event]);
      expect(
        provider.filteredDateEventTypes({CalendarEventType.diary}),
        isEmpty,
      );
      expect(
        provider.filteredDateEventCounts({CalendarEventType.diary}),
        isEmpty,
      );
      expect(provider.datesWithEvents, {date});
    },
  );

  test(
    'retired calendar input cannot be converted to an editable local event',
    () async {
      final provider = CalendarProvider();
      addTearDown(provider.dispose);
      await provider.addLocalEvent(retiredEvent);
      expect(provider.localEvents, isEmpty);
      final result = await provider.importLocalEvents([
        retiredEvent,
        regularEvent,
      ]);
      expect(result.inserted, 1);
      expect(provider.localEvents.single.title, regularEvent.title);
      await provider.updateLocalEvent(
        retiredEvent.copyWith(id: regularEvent.id),
      );
      expect(provider.localEvents.single.title, regularEvent.title);
    },
  );

  test('calendar export filters historical data even if passed directly', () {
    final exported = IcsExporter.fromEvents([retiredEvent, regularEvent]);
    expect(exported, contains('SUMMARY:keep this event'));
    expect(exported, isNot(contains(historical.content)));
    expect(exported, isNot(contains('CATEGORIES:diary')));
  });

  test(
    'challenge and achievement catalogs ignore historical writing activity',
    () {
      const snapshot = AchievementContext(
        totalTodos: 0,
        completedTodos: 0,
        longestHabitStreak: 0,
        habitCount: 0,
        focusMinutes: 0,
        focusSessions: 0,
        diaryStreak: 100,
        diaryCount: 100,
        todayDiaryEntries: 1,
        weeklyDiaryEntries: 7,
        goalsTotal: 0,
        goalsAchieved: 0,
        anniversaries: 0,
        courses: 0,
        notes: 0,
      );
      expect(
        Achievements.all.where((item) => item.id.startsWith('diary_')),
        isEmpty,
      );
      expect(Achievements.unlockedCount(snapshot), 0);
      final challenges = ProductivityChallenges.build(snapshot);
      expect(challenges, hasLength(7));
      expect(
        challenges.map((item) => item.id),
        isNot(contains('daily_reflection')),
      );
      expect(
        challenges.map((item) => item.id),
        isNot(contains('weekly_reflection')),
      );
      expect(challenges.where((item) => item.completed), isEmpty);
    },
  );

  test(
    'historical unlocked IDs survive loading while retired badges stay hidden',
    () async {
      final raw = jsonEncode({'diary_first': '2026-01-01T00:00:00.000Z'});
      SharedPreferences.setMockInitialValues({
        'duoyi_achievements_unlocked': raw,
      });
      final provider = AchievementProvider();
      addTearDown(provider.dispose);
      await provider.loadFromStorage();
      expect(provider.unlockedAt, contains('diary_first'));
      expect(
        provider.snapshots.where((item) => item.id.startsWith('diary_')),
        isEmpty,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('duoyi_achievements_unlocked'), raw);
    },
  );
}
