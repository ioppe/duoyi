import 'package:duoyi/core/report_engine.dart';
import 'package:duoyi/models/habit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('longest streak is limited to completed dates inside the report', () {
    final habit = Habit(
      id: 'one',
      name: 'one',
      completions: {for (var day = 13; day <= 19; day++) '2026-06-$day': 1},
    );
    final report = ReportEngine.buildReport(
      start: DateTime(2026, 6, 15),
      end: DateTime(2026, 6, 17),
      todos: [],
      habits: [habit],
      sessions: [],
      timeEntries: [],
    );
    expect(report.habitCheckIns, 3);
    expect(report.longestHabitStreak, 3);
    final previous = ReportEngine.buildReport(
      start: DateTime(2026, 6, 8),
      end: DateTime(2026, 6, 10),
      todos: [],
      habits: [habit],
      sessions: [],
      timeEntries: [],
    );
    expect(previous.longestHabitStreak, 0);
  });

  test(
    'supplied completions remain grouped by habit when computing a bucket streak',
    () {
      final report = ReportEngine.buildReport(
        start: DateTime(2026, 6, 15),
        end: DateTime(2026, 6, 17),
        todos: [],
        habits: [],
        sessions: [],
        timeEntries: [],
        habitCompletionDatesById: {
          'a': [DateTime(2026, 6, 15), DateTime(2026, 6, 17)],
          'b': [DateTime(2026, 6, 16)],
        },
      );
      expect(report.habitCheckIns, 3);
      expect(report.longestHabitStreak, 1);
    },
  );
}
