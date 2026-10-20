import 'app_clock.dart';

/// Report dates are floating calendar dates; instants are resolved only at the
/// filtering boundary, using the application's selected time zone.
enum StatisticsPeriod { week, month, year }

class StatisticsSpan {
  final DateTime start;
  final DateTime end;

  StatisticsSpan(DateTime start, DateTime end)
    : start = calendarDate(start),
      end = calendarDate(end);

  int get dayCount => end.difference(start).inDays + 1;

  DateTime get startInstant =>
      AppClock.date(start.year, start.month, start.day);
  DateTime get endExclusive => AppClock.date(end.year, end.month, end.day + 1);

  bool containsDate(DateTime date) {
    final day = calendarDate(date);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  bool containsInstant(DateTime instant) =>
      !instant.isBefore(startInstant) && instant.isBefore(endExclusive);

  static DateTime calendarDate(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day);
}

class StatisticsWindow extends StatisticsSpan {
  final StatisticsPeriod period;

  factory StatisticsWindow(StatisticsPeriod period, {DateTime? today}) {
    final end = StatisticsSpan.calendarDate(today ?? AppClock.today());
    final start = switch (period) {
      StatisticsPeriod.week => DateTime.utc(
        end.year,
        end.month,
        end.day - end.weekday + 1,
      ),
      StatisticsPeriod.month => DateTime.utc(end.year, end.month),
      StatisticsPeriod.year => DateTime.utc(end.year),
    };
    return StatisticsWindow._(period, start, end);
  }

  StatisticsWindow._(this.period, super.start, super.end);

  DateTime get calendarEnd => switch (period) {
    StatisticsPeriod.week => start.add(const Duration(days: 6)),
    StatisticsPeriod.month => DateTime.utc(start.year, start.month + 1, 0),
    StatisticsPeriod.year => DateTime.utc(start.year, 12, 31),
  };

  StatisticsSpan get previous {
    if (period == StatisticsPeriod.week) {
      return StatisticsSpan(
        start.subtract(const Duration(days: 7)),
        end.subtract(const Duration(days: 7)),
      );
    }
    final previousStart = period == StatisticsPeriod.month
        ? DateTime.utc(start.year, start.month - 1)
        : DateTime.utc(start.year - 1);
    final targetMonth = period == StatisticsPeriod.month
        ? previousStart.month
        : end.month;
    final lastDay = DateTime.utc(previousStart.year, targetMonth + 1, 0).day;
    final previousEnd = DateTime.utc(
      previousStart.year,
      targetMonth,
      end.day.clamp(1, lastDay),
    );
    return StatisticsSpan(previousStart, previousEnd);
  }

  /// Daily in a week, calendar weeks clipped to the month, monthly in a year.
  List<StatisticsSpan> get buckets {
    final result = <StatisticsSpan>[];
    var cursor = start;
    while (!cursor.isAfter(end)) {
      final candidate = switch (period) {
        StatisticsPeriod.week => cursor,
        StatisticsPeriod.month => DateTime.utc(
          cursor.year,
          cursor.month,
          cursor.day + 7 - cursor.weekday,
        ),
        StatisticsPeriod.year => DateTime.utc(cursor.year, cursor.month + 1, 0),
      };
      final bucketEnd = candidate.isAfter(end) ? end : candidate;
      result.add(StatisticsSpan(cursor, bucketEnd));
      cursor = bucketEnd.add(const Duration(days: 1));
    }
    return result;
  }
}
