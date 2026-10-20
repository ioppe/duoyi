import '../models/pomodoro.dart';
import 'app_clock.dart';

class FocusTagStat {
  final String tag;
  final int sessionCount;
  final int totalSeconds;
  final double share;

  const FocusTagStat({
    required this.tag,
    required this.sessionCount,
    required this.totalSeconds,
    required this.share,
  });

  int get totalMinutes => totalSeconds ~/ 60;

  int get averageMinutes =>
      sessionCount == 0 ? 0 : (totalSeconds ~/ sessionCount) ~/ 60;
}

enum FocusTagTrendBucket { day, week, month }

class FocusTagTrendPoint {
  final String label;
  final int minutes;

  const FocusTagTrendPoint({required this.label, required this.minutes});
}

class FocusTagTrendSeries {
  final String tag;
  final List<FocusTagTrendPoint> points;

  const FocusTagTrendSeries({required this.tag, required this.points});

  int get totalMinutes =>
      points.fold<int>(0, (sum, point) => sum + point.minutes);

  int get maxMinutes => points.fold<int>(
    0,
    (max, point) => point.minutes > max ? point.minutes : max,
  );
}

class FocusTagStats {
  FocusTagStats._();

  static const untaggedLabel = '未标记';

  static List<FocusTagStat> build({
    required Iterable<PomodoroSession> sessions,
    int limit = 6,
  }) {
    final buckets = <String, _FocusTagBucket>{};

    for (final session in sessions) {
      if (session.type != PomodoroType.focus || session.durationSeconds <= 0) {
        continue;
      }
      final tag = _normalizeTag(session.tag);
      final bucket = buckets.putIfAbsent(tag, () => _FocusTagBucket());
      bucket
        ..sessionCount += 1
        ..totalSeconds += session.durationSeconds;
    }

    final totalSeconds = buckets.values.fold<int>(
      0,
      (sum, bucket) => sum + bucket.totalSeconds,
    );
    if (totalSeconds <= 0) return const [];

    final stats =
        [
          for (final entry in buckets.entries)
            FocusTagStat(
              tag: entry.key,
              sessionCount: entry.value.sessionCount,
              totalSeconds: entry.value.totalSeconds,
              share: entry.value.totalSeconds / totalSeconds,
            ),
        ]..sort((a, b) {
          final bySeconds = b.totalSeconds.compareTo(a.totalSeconds);
          if (bySeconds != 0) return bySeconds;
          final byCount = b.sessionCount.compareTo(a.sessionCount);
          if (byCount != 0) return byCount;
          return a.tag.compareTo(b.tag);
        });

    return List<FocusTagStat>.unmodifiable(stats.take(limit));
  }

  static List<FocusTagTrendSeries> buildTrend({
    required Iterable<PomodoroSession> sessions,
    required DateTime start,
    required DateTime end,
    required Iterable<String> tags,
    required FocusTagTrendBucket bucket,
  }) {
    final orderedTags = {for (final tag in tags) _normalizeTag(tag)}.toList();
    if (orderedTags.isEmpty) return const [];

    final bucketDefs = _buildBuckets(start: start, end: end, bucket: bucket);
    if (bucketDefs.isEmpty) return const [];

    final secondsByTag = {
      for (final tag in orderedTags)
        tag: {for (final b in bucketDefs) b.key: 0},
    };
    final startInstant = AppClock.date(start.year, start.month, start.day);
    final endExclusive = AppClock.date(end.year, end.month, end.day + 1);

    for (final session in sessions) {
      if (session.type != PomodoroType.focus || session.durationSeconds <= 0) {
        continue;
      }
      if (session.endTime.isBefore(startInstant) ||
          !session.endTime.isBefore(endExclusive)) {
        continue;
      }
      final tag = _normalizeTag(session.tag);
      final tagBuckets = secondsByTag[tag];
      if (tagBuckets == null) continue;
      final key = _bucketKey(AppClock.toLocal(session.endTime), bucket);
      if (!tagBuckets.containsKey(key)) continue;
      tagBuckets[key] = tagBuckets[key]! + session.durationSeconds;
    }

    return List<FocusTagTrendSeries>.unmodifiable([
      for (final tag in orderedTags)
        FocusTagTrendSeries(
          tag: tag,
          points: List<FocusTagTrendPoint>.unmodifiable([
            for (final b in bucketDefs)
              FocusTagTrendPoint(
                label: b.label,
                minutes: (secondsByTag[tag]![b.key] ?? 0) ~/ 60,
              ),
          ]),
        ),
    ]);
  }

  static String _normalizeTag(String? raw) {
    final tag = raw?.trim().replaceFirst(RegExp(r'^#'), '') ?? '';
    return tag.isEmpty ? untaggedLabel : tag;
  }

  static List<_FocusTagTrendBucketDef> _buildBuckets({
    required DateTime start,
    required DateTime end,
    required FocusTagTrendBucket bucket,
  }) {
    final defs = <_FocusTagTrendBucketDef>[];
    final startDate = AppClock.dateOnly(start);
    final endDate = AppClock.dateOnly(end);
    if (endDate.isBefore(startDate)) return defs;
    switch (bucket) {
      case FocusTagTrendBucket.day:
        for (
          var cursor = DateTime(start.year, start.month, start.day);
          !cursor.isAfter(DateTime(end.year, end.month, end.day));
          cursor = DateTime(cursor.year, cursor.month, cursor.day + 1)
        ) {
          defs.add(
            _FocusTagTrendBucketDef(
              key: _bucketKey(cursor, bucket),
              label: '${cursor.month}/${cursor.day}',
            ),
          );
        }
      case FocusTagTrendBucket.week:
        for (
          var cursor = _weekStart(startDate);
          !cursor.isAfter(endDate);
          cursor = DateTime(cursor.year, cursor.month, cursor.day + 7)
        ) {
          final lastDay = DateTime(cursor.year, cursor.month, cursor.day + 6);
          final bucketStart = cursor.isBefore(startDate) ? startDate : cursor;
          final bucketEnd = lastDay.isAfter(endDate) ? endDate : lastDay;
          defs.add(
            _FocusTagTrendBucketDef(
              key: _bucketKey(cursor, bucket),
              label:
                  '${bucketStart.month}/${bucketStart.day}–${bucketEnd.month}/${bucketEnd.day}',
            ),
          );
        }
      case FocusTagTrendBucket.month:
        for (
          var cursor = DateTime(start.year, start.month);
          !cursor.isAfter(DateTime(end.year, end.month));
          cursor = DateTime(cursor.year, cursor.month + 1)
        ) {
          defs.add(
            _FocusTagTrendBucketDef(
              key: _bucketKey(cursor, bucket),
              label: '${cursor.month}月',
            ),
          );
        }
    }
    return defs;
  }

  static String _bucketKey(DateTime date, FocusTagTrendBucket bucket) {
    final month = date.month.toString().padLeft(2, '0');
    return switch (bucket) {
      FocusTagTrendBucket.day =>
        '${date.year}-$month-${date.day.toString().padLeft(2, '0')}',
      FocusTagTrendBucket.week => _bucketKey(
        _weekStart(date),
        FocusTagTrendBucket.day,
      ),
      FocusTagTrendBucket.month => '${date.year}-$month',
    };
  }

  static DateTime _weekStart(DateTime date) =>
      DateTime(date.year, date.month, date.day - date.weekday + 1);
}

class _FocusTagBucket {
  int sessionCount = 0;
  int totalSeconds = 0;
}

class _FocusTagTrendBucketDef {
  final String key;
  final String label;

  const _FocusTagTrendBucketDef({required this.key, required this.label});
}
