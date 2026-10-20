import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/statistics_period.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => AppClock.debugNow = null);

  test(
    'week, month and year start at their calendar boundary and end today',
    () {
      final day = DateTime(2026, 6, 17);
      final starts = [
        DateTime.utc(2026, 6, 15),
        DateTime.utc(2026, 6),
        DateTime.utc(2026),
      ];
      for (var i = 0; i < StatisticsPeriod.values.length; i++) {
        final window = StatisticsWindow(StatisticsPeriod.values[i], today: day);
        expect(window.start, starts[i]);
        expect(window.end, DateTime.utc(2026, 6, 17));
      }
    },
  );

  test(
    'week compares Monday through Wednesday with the previous Monday through Wednesday',
    () {
      final previous = StatisticsWindow(
        StatisticsPeriod.week,
        today: DateTime(2026, 6, 17),
      ).previous;
      expect(previous.start, DateTime.utc(2026, 6, 8));
      expect(previous.end, DateTime.utc(2026, 6, 10));
    },
  );

  test('month compares the same dates in the previous natural month', () {
    final previous = StatisticsWindow(
      StatisticsPeriod.month,
      today: DateTime(2026, 6, 20),
    ).previous;
    expect(previous.start, DateTime.utc(2026, 5));
    expect(previous.end, DateTime.utc(2026, 5, 20));
  });

  test('month and year comparisons clamp short months and leap days', () {
    for (final (period, today, expectedStart, expectedEnd) in [
      (
        StatisticsPeriod.month,
        DateTime(2026, 3, 31),
        DateTime.utc(2026, 2),
        DateTime.utc(2026, 2, 28),
      ),
      (
        StatisticsPeriod.month,
        DateTime(2024, 3, 31),
        DateTime.utc(2024, 2),
        DateTime.utc(2024, 2, 29),
      ),
      (
        StatisticsPeriod.month,
        DateTime(2026, 1, 20),
        DateTime.utc(2025, 12),
        DateTime.utc(2025, 12, 20),
      ),
      (
        StatisticsPeriod.year,
        DateTime(2024, 2, 29),
        DateTime.utc(2023),
        DateTime.utc(2023, 2, 28),
      ),
    ]) {
      final previous = StatisticsWindow(period, today: today).previous;
      expect(previous.start, expectedStart);
      expect(previous.end, expectedEnd);
    }
  });

  test(
    'week buckets are individual days, including a one-day Monday report',
    () {
      final window = StatisticsWindow(
        StatisticsPeriod.week,
        today: DateTime(2026, 6, 17),
      );
      expect(window.buckets.length, 3);
      expect(window.buckets.every((bucket) => bucket.dayCount == 1), isTrue);
      expect(
        StatisticsWindow(
          StatisticsPeriod.week,
          today: DateTime(2026, 6, 15),
        ).buckets.length,
        1,
      );
    },
  );

  test(
    'month buckets follow calendar weeks clipped to the month and today',
    () {
      final window = StatisticsWindow(
        StatisticsPeriod.month,
        today: DateTime(2026, 10, 20),
      );
      expect(
        window.buckets
            .map((bucket) => [bucket.start.day, bucket.end.day])
            .toList(),
        [
          [1, 4],
          [5, 11],
          [12, 18],
          [19, 20],
        ],
      );
    },
  );

  test('year buckets include only months in this year through today', () {
    final window = StatisticsWindow(
      StatisticsPeriod.year,
      today: DateTime(2026, 6, 17),
    );
    expect(window.buckets.length, 6);
    expect(window.buckets.first.start, DateTime.utc(2026));
    expect(window.buckets[1].dayCount, 28);
    expect(window.buckets.last.end, DateTime.utc(2026, 6, 17));
    expect(window.calendarEnd, DateTime.utc(2026, 12, 31));
  });

  test(
    'all buckets cover the selected range exactly once without future days',
    () {
      for (final year in [2024, 2026]) {
        for (var month = 1; month <= 12; month++) {
          for (final day in [1, 17, DateTime.utc(year, month + 1, 0).day]) {
            for (final period in StatisticsPeriod.values) {
              final window = StatisticsWindow(
                period,
                today: DateTime(year, month, day),
              );
              final buckets = window.buckets;
              expect(buckets.first.start, window.start);
              expect(buckets.last.end, window.end);
              expect(
                buckets.fold<int>(
                  0,
                  (total, bucket) => total + bucket.dayCount,
                ),
                window.dayCount,
              );
              for (var i = 1; i < buckets.length; i++) {
                expect(
                  buckets[i].start.difference(buckets[i - 1].end).inDays,
                  1,
                );
              }
            }
          }
        }
      }
    },
  );

  test(
    'application zone determines today; DST does not alter calendar buckets',
    () async {
      AppClock.debugNow = () => DateTime.utc(2026, 3, 9, 2, 30);
      await LocalTimezoneResolver.setApplicationTimeZone('America/New_York');
      final newYork = StatisticsWindow(StatisticsPeriod.week);
      expect(newYork.end, DateTime.utc(2026, 3, 8));
      expect(newYork.buckets.length, 7);
      expect(newYork.containsInstant(DateTime.utc(2026, 3, 9, 3, 59)), isTrue);
      expect(newYork.containsInstant(DateTime.utc(2026, 3, 9, 4)), isFalse);
      expect(newYork.containsDate(DateTime(2026, 3, 8)), isTrue);
      await LocalTimezoneResolver.setApplicationTimeZone('Asia/Shanghai');
      final shanghai = StatisticsWindow(StatisticsPeriod.week);
      expect(shanghai.end, DateTime.utc(2026, 3, 9));
      expect(shanghai.buckets.length, 1);
    },
  );
}
