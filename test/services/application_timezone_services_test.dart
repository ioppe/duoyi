import 'dart:convert';

import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/focus_report.dart';
import 'package:duoyi/core/focus_tag_stats.dart';
import 'package:duoyi/core/habit_trend.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/report_cross_analysis.dart';
import 'package:duoyi/core/report_engine.dart';
import 'package:duoyi/core/smart_date_parser.dart';
import 'package:duoyi/core/smart_todo_draft.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/services/foreground_reminder_popup_sink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final instant = DateTime.utc(2026, 1, 1, 2, 15, 40);
  final first = DateTime.utc(2025, 12, 31, 15);
  final second = DateTime.utc(2025, 12, 31, 17);

  List<PomodoroSession> sessions() => [
    for (final start in [first, second])
      PomodoroSession(
        id: start.toIso8601String(),
        startTime: start,
        endTime: start.add(const Duration(minutes: 25)),
        durationSeconds: 1500,
        type: PomodoroType.focus,
        tag: 'study',
      ),
  ];
  List<PomodoroFocusPenalty> penalties() => [
    for (final at in [first, second])
      PomodoroFocusPenalty(
        id: at.toIso8601String(),
        occurredAt: at,
        reason: FocusPenaltyReason.leaveApp,
        affectedSeconds: 60,
      ),
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppClock.debugNow = () => instant;
  });
  tearDown(() => AppClock.debugNow = null);

  test(
    'parser uses the app date but keeps date-only results floating',
    () async {
      for (final zone in ['America/New_York', 'Asia/Shanghai']) {
        await LocalTimezoneResolver.setApplicationTimeZone(zone);
        final local = AppClock.now();
        final tomorrow = DateTime(local.year, local.month, local.day + 1);
        final date = SmartDateParser.parse('明天');
        final timed = SmartDateParser.parse('明天9:30');
        final expected = tz.TZDateTime(
          tz.local,
          tomorrow.year,
          tomorrow.month,
          tomorrow.day,
          9,
          30,
        );
        expect(date.dateTime, tomorrow);
        expect(date.dateTime, isNot(isA<tz.TZDateTime>()));
        expect(
          timed.dateTime!.millisecondsSinceEpoch,
          expected.millisecondsSinceEpoch,
        );
        expect((timed.dateTime as tz.TZDateTime).location.name, zone);
        final draft = SmartTodoDraftBuilder.fromText('明天9:30 study');
        // 草稿的 date 保留时分（沿用既有语义），时区取自应用时区。
        expect(
          draft.date,
          tz.TZDateTime(tz.local, tomorrow.year, tomorrow.month, tomorrow.day, 9, 30),
        );
        expect(draft.date.isAtSameMomentAs(expected), isTrue);
        expect(draft.dueDate!.isAtSameMomentAs(expected), isTrue);
        final explicit = SmartDateParser.parse('明天9:30', now: instant);
        expect(explicit.dateTime!.isAtSameMomentAs(expected), isTrue);
      }
    },
  );

  test(
    'pomodoro re-buckets today without changing remaining or stored metadata',
    () async {
      final rawSessions = jsonEncode(
        sessions().map((s) => s.toJson()).toList(),
      );
      final rawPenalties = jsonEncode(
        penalties().map((p) => p.toJson()).toList(),
      );
      SharedPreferences.setMockInitialValues({
        'pomodoro_sessions': rawSessions,
        'pomodoro_focus_penalties': rawPenalties,
        'pomodoro_count_today': 19,
        'pomodoro_last_date': '2026-1-1',
      });
      await LocalTimezoneResolver.setApplicationTimeZone('America/New_York');
      final provider = PomodoroProvider();
      await provider.loadFromStorage();
      expect(provider.sessionCountToday, 2);
      expect(provider.todayPenalties.length, 2);
      provider.startIfIdle();
      await Future<void>.delayed(Duration.zero);
      final remaining = provider.state.remainingSeconds;
      final revision = provider.persistedRevision;
      final prefs = await SharedPreferences.getInstance();
      final snapshot = prefs.getString(PomodoroProvider.runningSnapshotKey);
      await LocalTimezoneResolver.setApplicationTimeZone('Asia/Shanghai');
      expect(provider.state.remainingSeconds, remaining);
      expect(provider.state.isRunning, isTrue);
      expect(provider.sessionCountToday, 1);
      expect(provider.todayFocusSessions.single.startTime, second);
      expect(provider.todayPenalties.single.occurredAt, second);
      expect(provider.persistedRevision, revision);
      expect(prefs.getString(PomodoroProvider.runningSnapshotKey), snapshot);
      expect(prefs.getInt('pomodoro_count_today'), 19);
      expect(prefs.getString('pomodoro_sessions'), rawSessions);
      expect(prefs.getString('pomodoro_focus_penalties'), rawPenalties);
      await LocalTimezoneResolver.setApplicationTimeZone('America/New_York');
      expect(provider.sessionCountToday, 2);
      provider.dispose();
    },
  );

  test(
    'calendar cache follows app zone and preserves all-day exclusive end',
    () async {
      final provider = CalendarProvider();
      provider.setExternalEvents([
        CalendarEvent(
          id: 'timed',
          title: 'meeting',
          date: DateTime.utc(2026, 1, 1, 2),
          endDate: DateTime.utc(2026, 1, 1, 4),
          type: CalendarEventType.event,
          color: Colors.blue,
          time: const TimeOfDay(hour: 2, minute: 0),
        ),
        CalendarEvent(
          id: 'all-day',
          title: 'holiday',
          date: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 3),
          type: CalendarEventType.event,
          color: Colors.green,
        ),
      ]);
      await LocalTimezoneResolver.setApplicationTimeZone('America/New_York');
      provider.rebuild([], [], [], const ColorScheme.light());
      final ny = provider.events.singleWhere((e) => e.id == 'timed');
      expect(ny.dateKey, '2025-12-31');
      expect(ny.time, const TimeOfDay(hour: 21, minute: 0));
      expect(
        provider.getEventsForDate(DateTime(2025, 12, 31)).map((e) => e.id),
        ['timed'],
      );
      await LocalTimezoneResolver.setApplicationTimeZone('Asia/Shanghai');
      provider.rebuild([], [], [], const ColorScheme.light());
      final sh = provider.events.singleWhere((e) => e.id == 'timed');
      expect(sh.dateKey, '2026-01-01');
      expect(sh.time, const TimeOfDay(hour: 10, minute: 0));
      expect(sh.date.isAtSameMomentAs(ny.date), isTrue);
      expect(provider.getEventsForDate(DateTime(2025, 12, 31)), isEmpty);
      expect(provider.getEventsForDate(DateTime(2026, 1, 2)).map((e) => e.id), [
        'all-day',
      ]);
      expect(provider.getEventsForDate(DateTime(2026, 1, 3)), isEmpty);
      provider.dispose();
    },
  );

  test(
    'reports project instants while habit and diary dates stay floating',
    () async {
      final habit = Habit(
        id: 'h',
        name: 'habit',
        completions: {'2025-12-31': 3, '2026-01-01': 5},
      );
      final todos = [
        for (final at in [first, second])
          TodoItem(
            title: 'done',
            createdAt: at,
            isCompleted: true,
            completedAt: at,
          ),
      ];
      for (final zone in ['America/New_York', 'Asia/Shanghai']) {
        await LocalTimezoneResolver.setApplicationTimeZone(zone);
        final expected = zone == 'America/New_York' ? 2 : 1;
        // Zoned input dates carry wall-date semantics, not their midnight epoch.
        final day = AppClock.date(2025, 12, 31);
        final report = ReportEngine.buildReport(
          start: day,
          end: day,
          todos: todos,
          habits: [habit],
          sessions: sessions(),
          timeEntries: [],
        );
        expect(report.todosCompleted, expected);
        expect(report.focusSessions, expected);
        expect(report.habitCheckIns, 1);
        final cross = ReportCrossAnalysis.build(
          start: day,
          end: AppClock.date(2026, 1, 1),
          bucket: ReportCrossBucket.day,
          todoCompletions: [
            for (final at in [first, second]) ReportCrossTodoCompletion(at),
          ],
          focusSessions: [
            for (final s in sessions())
              ReportCrossFocusSession(
                endedAt: s.endTime,
                durationSeconds: s.durationSeconds,
              ),
          ],
          habitCompletions: [
            ReportCrossHabitCompletion(DateTime.utc(2025, 12, 31)),
          ],
          diaryEntries: [ReportCrossDiaryEntry(DateTime.utc(2025, 12, 31))],
          timeEntries: [],
        );
        expect(cross.habitTodo.points.first.habitCheckIns, 1);
        expect(cross.diaryFocus.points.first.diaryEntries, 1);
        expect(cross.focusTodo.points.first.completedTodos, expected);
        final trend = FocusTagStats.buildTrend(
          sessions: sessions(),
          start: day,
          end: AppClock.date(2026, 1, 1),
          tags: ['study'],
          bucket: FocusTagTrendBucket.day,
        );
        expect(trend.single.points.first.minutes, expected * 25);
        final habitTrend = buildHabitTrendSummary(
          habit,
          today: day,
          window: HabitTrendWindow.days14,
        );
        expect(habitTrend.points.last.count, 3);
        final focus = FocusReportBuilder.build(
          sessions: sessions(),
          penalties: penalties(),
          period: FocusReportPeriod.month,
        );
        expect(focus.sessionCount, expected);
        expect(focus.penaltyCount, expected);
      }
    },
  );

  test(
    'time audit splits at application midnight across a 23-hour DST day',
    () async {
      await LocalTimezoneResolver.setApplicationTimeZone('America/New_York');
      final provider = TimeAuditProvider();
      final entry = TimeEntry(
        title: 'DST work',
        startAt: DateTime.utc(2026, 3, 8, 4, 30),
        endAt: DateTime.utc(2026, 3, 9, 4, 30),
      );
      await provider.add(entry);
      expect(entry.dayKey, '2026-03-07');
      expect(provider.entriesForDate(DateTime(2026, 3, 8)), [entry]);
      expect(
        provider.secondsByDay(
          AppClock.date(2026, 3, 7),
          AppClock.date(2026, 3, 10),
        ),
        {'2026-03-07': 1800, '2026-03-08': 23 * 3600, '2026-03-09': 1800},
      );
      await LocalTimezoneResolver.setApplicationTimeZone('Asia/Shanghai');
      expect(entry.dayKey, '2026-03-08');
      expect(entry.durationSeconds, 24 * 3600);
      provider.dispose();
    },
  );

  test(
    'habit time-audit dedupe and undo keep their original storage key',
    () async {
      final provider = TimeAuditProvider();
      final habit = Habit(id: 'minutes', name: 'reading', unit: 'min');
      await LocalTimezoneResolver.setApplicationTimeZone('America/New_York');
      await provider.recordHabitCheckIn(habit, cumulativeCount: 1, at: second);
      final key = provider.entries.single.dedupeKey;
      await LocalTimezoneResolver.setApplicationTimeZone('Asia/Shanghai');
      await provider.recordHabitCheckIn(habit, cumulativeCount: 1, at: second);
      expect(provider.entries.length, 1);
      expect(provider.entries.single.dedupeKey, key);
      expect(
        provider.habitCheckInRecordedAmount(habit, count: 1, at: second),
        1,
      );
      await provider.removeHabitCheckIn(habit, count: 1, at: second);
      expect(provider.entries, isEmpty);
      provider.dispose();
    },
  );

  test(
    'diary month and streak follow app today without moving stored dates',
    () async {
      final provider = DiaryProvider();
      await provider.addOrUpdate(DiaryEntry(date: DateTime(2025, 12, 30)));
      await provider.addOrUpdate(DiaryEntry(date: DateTime.utc(2025, 12, 31)));
      await provider.addOrUpdate(DiaryEntry(date: DateTime(2026, 1, 1)));
      await LocalTimezoneResolver.setApplicationTimeZone('America/New_York');
      expect(provider.thisMonthCount, 2);
      expect(provider.currentStreak, 2);
      await LocalTimezoneResolver.setApplicationTimeZone('Asia/Shanghai');
      expect(provider.thisMonthCount, 1);
      expect(provider.currentStreak, 3);
      expect(provider.entryForDate(DateTime(2025, 12, 31))!.date.day, 31);
      provider.dispose();
    },
  );

  test('goal days remaining counts app calendar dates across DST', () async {
    await LocalTimezoneResolver.setApplicationTimeZone('America/New_York');
    AppClock.debugNow = () => DateTime.utc(2026, 3, 8, 5, 30);
    expect(
      GoalItem(title: 'goal', targetDate: DateTime(2026, 3, 9)).daysRemaining,
      1,
    );
  });

  for (final transition in [
    (DateTime.utc(2026, 3, 7, 15), DateTime.utc(2026, 3, 8, 13, 30)),
    (DateTime.utc(2026, 10, 31, 14), DateTime.utc(2026, 11, 1, 14, 30)),
  ]) {
    testWidgets('popup repeats at 09:30 across DST ${transition.$1.month}', (
      tester,
    ) async {
      await LocalTimezoneResolver.setApplicationTimeZone('America/New_York');
      var now = transition.$1;
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const Scaffold()),
      );
      final sink = ForegroundReminderPopupSink(
        contextGetter: () => navigator.currentContext,
        isForegroundGetter: () => true,
        nowGetter: () => now,
      );
      await sink.scheduleRepeating(
        id: 1,
        title: 'DST popup',
        body: '09:30',
        hour: 9,
        minute: 30,
      );
      final delay = transition.$2.difference(now);
      now = transition.$2.subtract(const Duration(seconds: 1));
      await tester.pump(delay - const Duration(seconds: 1));
      expect(find.text('DST popup'), findsNothing);
      now = transition.$2;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('DST popup'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await sink.cancel(1);
    });
  }
}
