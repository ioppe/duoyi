import '../models/habit.dart';
import 'app_clock.dart';

enum HabitTrendDirection { up, down, flat }

enum HabitTrendWindow {
  days14(label: '14天', days: 14),
  days30(label: '30天', days: 30),
  days90(label: '90天', days: 90),
  days365(label: '一年', days: 365);

  final String label;
  final int days;

  const HabitTrendWindow({required this.label, required this.days});
}

class HabitTrendPoint {
  final DateTime date;
  final bool active;
  final int count;
  final double progress;
  final bool completed;

  const HabitTrendPoint({
    required this.date,
    required this.active,
    required this.count,
    required this.progress,
    required this.completed,
  });
}

class HabitTrendBucket {
  final String label;
  final DateTime start;
  final DateTime end;
  final int activeDays;
  final int completedDays;
  final int totalCount;

  const HabitTrendBucket({
    required this.label,
    required this.start,
    required this.end,
    required this.activeDays,
    required this.completedDays,
    required this.totalCount,
  });

  double get completionRate => activeDays == 0 ? 0 : completedDays / activeDays;

  double get averageCount => activeDays == 0 ? 0 : totalCount / activeDays;
}

class HabitTrendSummary {
  final HabitTrendWindow window;
  final List<HabitTrendPoint> points;
  final List<HabitTrendBucket> buckets;
  final int activeDays;
  final int completedDays;
  final int totalCount;
  final int longestCompletedStreak;
  final double previousCompletionRate;

  const HabitTrendSummary({
    required this.window,
    required this.points,
    required this.buckets,
    required this.activeDays,
    required this.completedDays,
    required this.totalCount,
    required this.longestCompletedStreak,
    required this.previousCompletionRate,
  });

  double get completionRate => activeDays == 0 ? 0 : completedDays / activeDays;

  double get averageCount => activeDays == 0 ? 0 : totalCount / activeDays;

  double get completionRateDelta => completionRate - previousCompletionRate;

  HabitTrendDirection get direction {
    if (completionRateDelta.abs() < 0.001) return HabitTrendDirection.flat;
    return completionRateDelta > 0
        ? HabitTrendDirection.up
        : HabitTrendDirection.down;
  }
}

HabitTrendSummary buildHabitTrendSummary(
  Habit habit, {
  HabitTrendWindow window = HabitTrendWindow.days30,
  DateTime? today,
}) {
  final end = _dateOnly(today ?? AppClock.today());
  final start = DateTime(end.year, end.month, end.day - window.days + 1);
  final previousEnd = DateTime(start.year, start.month, start.day - 1);
  final previousStart = DateTime(
    previousEnd.year,
    previousEnd.month,
    previousEnd.day - window.days + 1,
  );
  final points = _buildTrendPoints(habit, start, end);
  final previousPoints = _buildTrendPoints(habit, previousStart, previousEnd);
  final activePoints = points.where((point) => point.active).toList();
  final completedDays = activePoints.where((point) => point.completed).length;
  final totalCount = activePoints.fold<int>(
    0,
    (sum, point) => sum + point.count,
  );

  return HabitTrendSummary(
    window: window,
    points: List.unmodifiable(points),
    buckets: List.unmodifiable(_buildBuckets(points, window)),
    activeDays: activePoints.length,
    completedDays: completedDays,
    totalCount: totalCount,
    longestCompletedStreak: _longestCompletedStreak(points),
    previousCompletionRate: _completionRate(previousPoints),
  );
}

List<HabitTrendPoint> _buildTrendPoints(
  Habit habit,
  DateTime start,
  DateTime end,
) {
  final points = <HabitTrendPoint>[];
  for (
    var date = start;
    !date.isAfter(end);
    date = DateTime(date.year, date.month, date.day + 1)
  ) {
    final active = habit.activeForDate(date);
    points.add(
      HabitTrendPoint(
        date: date,
        active: active,
        count: habit.countForDate(date),
        progress: active ? habit.progressForDate(date) : 0,
        completed: active && habit.isCompletedForDate(date),
      ),
    );
  }
  return points;
}

List<HabitTrendBucket> _buildBuckets(
  List<HabitTrendPoint> points,
  HabitTrendWindow window,
) {
  if (window == HabitTrendWindow.days365) {
    return _buildMonthBuckets(points);
  }
  final size = window == HabitTrendWindow.days90 ? 7 : 1;
  final buckets = <HabitTrendBucket>[];
  for (var i = 0; i < points.length; i += size) {
    final slice = points.skip(i).take(size).toList();
    buckets.add(
      _bucketFor(slice, _bucketLabel(slice.first.date, slice.last.date)),
    );
  }
  return buckets;
}

List<HabitTrendBucket> _buildMonthBuckets(List<HabitTrendPoint> points) {
  final buckets = <HabitTrendBucket>[];
  var cursor = <HabitTrendPoint>[];
  for (final point in points) {
    if (cursor.isNotEmpty &&
        (cursor.first.date.year != point.date.year ||
            cursor.first.date.month != point.date.month)) {
      buckets.add(_bucketFor(cursor, _monthLabel(cursor.first.date)));
      cursor = <HabitTrendPoint>[];
    }
    cursor.add(point);
  }
  if (cursor.isNotEmpty) {
    buckets.add(_bucketFor(cursor, _monthLabel(cursor.first.date)));
  }
  return buckets;
}

HabitTrendBucket _bucketFor(List<HabitTrendPoint> points, String label) {
  final active = points.where((point) => point.active).toList();
  return HabitTrendBucket(
    label: label,
    start: points.first.date,
    end: points.last.date,
    activeDays: active.length,
    completedDays: active.where((point) => point.completed).length,
    totalCount: active.fold<int>(0, (sum, point) => sum + point.count),
  );
}

int _longestCompletedStreak(List<HabitTrendPoint> points) {
  var current = 0;
  var best = 0;
  for (final point in points) {
    if (!point.active) continue;
    if (point.completed) {
      current += 1;
      if (current > best) best = current;
    } else {
      current = 0;
    }
  }
  return best;
}

double _completionRate(List<HabitTrendPoint> points) {
  final active = points.where((point) => point.active).toList();
  if (active.isEmpty) return 0;
  return active.where((point) => point.completed).length / active.length;
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _bucketLabel(DateTime start, DateTime end) {
  if (start.year == end.year &&
      start.month == end.month &&
      start.day == end.day) {
    return '${start.month}/${start.day}';
  }
  return '${start.month}/${start.day}-${end.month}/${end.day}';
}

String _monthLabel(DateTime date) => '${date.year}/${date.month}';
