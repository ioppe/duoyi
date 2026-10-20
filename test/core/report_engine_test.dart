import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/report_engine.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';

void main() {
  group('ReportEngine 周报', () {
    test('完成统计应基于完成时间', () {
      final start = DateTime(2026, 5, 11);
      final end = DateTime(2026, 5, 17);
      final todos = <TodoItem>[
        TodoItem(
          id: 't1',
          title: '完成于周内',
          date: DateTime(2026, 5, 13),
          createdAt: DateTime(2026, 5, 12),
          isCompleted: true,
          completedAt: DateTime(2026, 5, 14, 10),
        ),
        TodoItem(
          id: 't2',
          title: '完成于周外',
          date: DateTime(2026, 5, 1),
          createdAt: DateTime(2026, 5, 1),
          isCompleted: true,
          completedAt: DateTime(2026, 5, 2),
        ),
      ];

      final report = ReportEngine.buildReport(
        start: start,
        end: end,
        todos: todos,
        habits: const [],
        sessions: const [],
        timeEntries: const [],
      );

      expect(report.todosCompleted, 1);
      // 周内创建的只有 t1
      expect(report.todosCreated, 1);
    });

    test('番茄专注秒数累加', () {
      final start = DateTime(2026, 5, 11);
      final end = DateTime(2026, 5, 17);
      final sessions = [
        PomodoroSession(
          id: 's1',
          startTime: DateTime(2026, 5, 12, 9),
          endTime: DateTime(2026, 5, 12, 9, 25),
          durationSeconds: 1500,
          type: PomodoroType.focus,
        ),
        PomodoroSession(
          id: 's2',
          startTime: DateTime(2026, 5, 13, 9),
          endTime: DateTime(2026, 5, 13, 9, 25),
          durationSeconds: 1500,
          type: PomodoroType.focus,
        ),
        // 范围外
        PomodoroSession(
          id: 's3',
          startTime: DateTime(2026, 5, 8, 9),
          endTime: DateTime(2026, 5, 8, 9, 25),
          durationSeconds: 1500,
          type: PomodoroType.focus,
        ),
        // 短休息不计入
        PomodoroSession(
          id: 's4',
          startTime: DateTime(2026, 5, 12, 9, 25),
          endTime: DateTime(2026, 5, 12, 9, 30),
          durationSeconds: 300,
          type: PomodoroType.shortBreak,
        ),
      ];
      final report = ReportEngine.buildReport(
        start: start,
        end: end,
        todos: const [],
        habits: const [],
        sessions: sessions,
        timeEntries: const [],
      );
      expect(report.focusSessions, 2);
      expect(report.focusSeconds, 3000);
      expect(report.focusMinutes, 50);
    });

    test('时间足迹按类别聚合', () {
      final start = DateTime(2026, 5, 11);
      final end = DateTime(2026, 5, 17);
      final entries = [
        TimeEntry(
          id: 'e1',
          title: '阅读',
          startAt: DateTime(2026, 5, 12, 10),
          endAt: DateTime(2026, 5, 12, 11),
          category: TimeEntryCategory.study,
          source: TimeEntrySource.manual,
        ),
        TimeEntry(
          id: 'e2',
          title: '运动',
          startAt: DateTime(2026, 5, 13, 7),
          endAt: DateTime(2026, 5, 13, 8),
          category: TimeEntryCategory.life,
          source: TimeEntrySource.manual,
        ),
      ];
      final report = ReportEngine.buildReport(
        start: start,
        end: end,
        todos: const [],
        habits: const [],
        sessions: const [],
        timeEntries: entries,
      );
      expect(report.timeEntrySeconds, 7200);
      expect(report.timeEntryByCategory[TimeEntryCategory.study], 3600);
      expect(report.timeEntryByCategory[TimeEntryCategory.life], 3600);
    });

    test('todoCompletionRate 计算', () {
      final report = ReportEngine.buildReport(
        start: DateTime(2026, 5, 11),
        end: DateTime(2026, 5, 17),
        todos: [
          TodoItem(
            id: 'a',
            title: 'a',
            date: DateTime(2026, 5, 12),
            createdAt: DateTime(2026, 5, 12),
            isCompleted: true,
            completedAt: DateTime(2026, 5, 12),
          ),
          TodoItem(
            id: 'b',
            title: 'b',
            date: DateTime(2026, 5, 12),
            createdAt: DateTime(2026, 5, 12),
          ),
        ],
        habits: const [],
        sessions: const [],
        timeEntries: const [],
      );
      expect(report.todosCreated, 2);
      expect(report.todosCompleted, 1);
      expect(report.todoCompletionRate, 0.5);
    });
  });

  group('ReportEngine 习惯打卡', () {
    test('计入本周打卡总数', () {
      final habit = Habit(
        id: 'h1',
        name: '阅读',
        completions: {
          '2026-05-12': 1,
          '2026-05-13': 1,
          '2026-05-08': 1, // 范围外
        },
      );
      final report = ReportEngine.buildReport(
        start: DateTime(2026, 5, 11),
        end: DateTime(2026, 5, 17),
        todos: const [],
        habits: [habit],
        sessions: const [],
        timeEntries: const [],
      );
      expect(report.habitCheckIns, 2);
    });

    test('不计入习惯起止周期外的打卡次数', () {
      final habit = Habit(
        id: 'range',
        name: '阶段阅读',
        startDate: DateTime(2026, 5, 10),
        endDate: DateTime(2026, 5, 12),
        completions: {
          '2026-05-09': 10,
          '2026-05-10': 1,
          '2026-05-12': 2,
          '2026-05-13': 10,
        },
      );

      final report = ReportEngine.buildReport(
        start: DateTime(2026, 5, 8),
        end: DateTime(2026, 5, 14),
        todos: const [],
        habits: [habit],
        sessions: const [],
        timeEntries: const [],
      );

      expect(report.habitCheckIns, 2);
    });

    test(
      'counts successful target days instead of quantities or partial days',
      () {
        final habit = Habit(
          id: 'water',
          name: 'Water',
          targetCount: 8,
          currentStreak: 9,
          completions: {
            '2026-05-10': 8,
            '2026-05-11': 7,
            '2026-05-12': 8,
            '2026-05-13': 16,
            '2026-05-14': 0,
          },
        );
        final report = ReportEngine.buildReport(
          start: DateTime(2026, 5, 11),
          end: DateTime(2026, 5, 17),
          todos: const [],
          habits: [habit],
          sessions: const [],
          timeEntries: const [],
        );

        expect(report.habitCheckIns, 2);
        expect(report.longestHabitStreak, 2);
      },
    );

    test('counts each successful flexible week once', () {
      final habit = Habit(
        id: 'exercise',
        name: 'Exercise',
        flexPeriod: HabitFlexPeriod.week,
        flexTarget: 2,
        completions: {
          '2026-05-04': 3,
          '2026-05-06': 4,
          '2026-05-08': 1,
          '2026-05-11': 8,
          '2026-05-18': 2,
          '2026-05-19': 2,
        },
      );
      final report = ReportEngine.buildReport(
        start: DateTime(2026, 5, 4),
        end: DateTime(2026, 5, 24),
        todos: const [],
        habits: [habit],
        sessions: const [],
        timeEntries: const [],
      );

      expect(report.habitCheckIns, 2);
    });

    test(
      'reuses monthly success dates across weekly buckets without repeats',
      () {
        final start = DateTime(2026, 5, 1);
        final end = DateTime(2026, 5, 31);
        final habit = Habit(
          id: 'monthly',
          name: 'Monthly exercise',
          flexPeriod: HabitFlexPeriod.month,
          flexTarget: 2,
          completions: {
            '2026-05-04': 1,
            '2026-05-06': 1,
            '2026-05-14': 1,
            '2026-05-25': 1,
          },
        );
        final completionDates = habit.completionDatesInRange(start, end);
        final report = ReportEngine.buildReport(
          start: start,
          end: end,
          todos: const [],
          habits: [habit],
          sessions: const [],
          timeEntries: const [],
        );
        final bucketCounts = [
          for (final (first, last) in [
            (1, 3),
            (4, 10),
            (11, 17),
            (18, 24),
            (25, 31),
          ])
            ReportEngine.buildReport(
              start: DateTime(2026, 5, first),
              end: DateTime(2026, 5, last),
              todos: const [],
              habits: [habit],
              sessions: const [],
              timeEntries: const [],
              habitCompletionDates: completionDates,
            ).habitCheckIns,
        ];

        expect(report.habitCheckIns, 1);
        expect(bucketCounts, [0, 0, 0, 0, 1]);
        expect(
          bucketCounts.fold<int>(0, (sum, count) => sum + count),
          report.habitCheckIns,
        );
      },
    );

    test(
      'supplied dates override habits and retain floating inclusive dates',
      () {
        final habit = Habit(
          id: 'override',
          name: 'Override',
          completions: {'2026-05-12': 1},
        );
        PeriodReport build(Iterable<DateTime> dates) =>
            ReportEngine.buildReport(
              start: DateTime(2026, 5, 11),
              end: DateTime(2026, 5, 17),
              todos: const [],
              habits: [habit],
              sessions: const [],
              timeEntries: const [],
              habitCompletionDates: dates,
            );

        expect(build(const []).habitCheckIns, 0);
        expect(
          build([
            DateTime.utc(2026, 5, 10, 23, 59),
            DateTime.utc(2026, 5, 11),
            DateTime.utc(2026, 5, 17, 23, 59),
            DateTime.utc(2026, 5, 17, 12), // A second habit on the same day.
            DateTime.utc(2026, 5, 18),
          ]).habitCheckIns,
          3,
        );
      },
    );
  });
}
