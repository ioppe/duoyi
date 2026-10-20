import 'package:duoyi/models/habit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily report completions include every date across spring DST', () {
    final habit = Habit(
      id: 'daily',
      name: 'daily',
      completions: {'2026-03-07': 1, '2026-03-08': 1, '2026-03-09': 1},
    );
    final dates = habit.completionDatesInRange(
      DateTime(2026, 3, 7),
      DateTime(2026, 3, 9),
    );
    expect(dates.map((day) => day.day).toList(), [7, 8, 9]);
    expect(
      habit.completionCountInRange(DateTime(2026, 3, 7), DateTime(2026, 3, 9)),
      3,
    );
  });

  test(
    'flexible-week reports and prior week preserve calendar midnights across DST',
    () {
      final habit = Habit(
        id: 'weekly',
        name: 'weekly',
        flexPeriod: HabitFlexPeriod.week,
        flexTarget: 2,
        completions: {
          '2026-03-07': 1,
          '2026-03-08': 1,
          '2026-03-14': 1,
          '2026-03-15': 1,
        },
      );
      final dates = habit.completionDatesInRange(
        DateTime(2026, 3, 2),
        DateTime(2026, 3, 15),
      );
      expect(dates.map((day) => day.day).toList(), [8, 15]);
      final prior = habit.previousPeriodBounds(
        habit.periodBoundsForDate(DateTime(2026, 3, 9)),
      );
      expect(prior.start, DateTime(2026, 3, 2));
      expect(prior.end, DateTime(2026, 3, 8));
    },
  );
}
