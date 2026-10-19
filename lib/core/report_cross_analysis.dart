import 'dart:math' as math;

import 'app_clock.dart';

enum ReportCrossAnalysisBucket { day, month }

enum ReportCrossBucket { day, month }

class ReportCompletionRecord {
  final DateTime completedAt;

  const ReportCompletionRecord({required this.completedAt});
}

class ReportFocusRecord {
  final DateTime endedAt;
  final int durationSeconds;

  const ReportFocusRecord({
    required this.endedAt,
    required this.durationSeconds,
  });
}

class ReportHabitCompletionRecord {
  final DateTime completedAt;

  const ReportHabitCompletionRecord({required this.completedAt});
}

class ReportDiaryEntryRecord {
  final DateTime writtenAt;

  const ReportDiaryEntryRecord({required this.writtenAt});
}

class ReportTimeCategoryRecord {
  final DateTime startAt;
  final int durationSeconds;
  final Object category;

  const ReportTimeCategoryRecord({
    required this.startAt,
    required this.durationSeconds,
    required this.category,
  });
}

class ReportCrossTodoCompletion {
  final DateTime completedAt;

  const ReportCrossTodoCompletion(this.completedAt);
}

class ReportCrossFocusSession {
  final DateTime endedAt;
  final int durationSeconds;

  const ReportCrossFocusSession({
    required this.endedAt,
    required this.durationSeconds,
  });
}

class ReportCrossHabitCompletion {
  final DateTime completedAt;

  const ReportCrossHabitCompletion(this.completedAt);
}

class ReportCrossDiaryEntry {
  final DateTime writtenAt;

  const ReportCrossDiaryEntry(this.writtenAt);
}

class ReportCrossTimeEntry {
  final DateTime startedAt;
  final int durationSeconds;
  final String categoryKey;

  const ReportCrossTimeEntry({
    required this.startedAt,
    required this.durationSeconds,
    required this.categoryKey,
  });
}

class FocusCompletionPoint {
  final String label;
  final DateTime start;
  final DateTime end;
  final int focusMinutes;
  final int completedTodos;

  const FocusCompletionPoint({
    required this.label,
    required this.start,
    required this.end,
    required this.focusMinutes,
    required this.completedTodos,
  });

  bool get hasActivity => focusMinutes > 0 || completedTodos > 0;
}

class FocusTodoPoint {
  final String label;
  final DateTime start;
  final DateTime end;
  final int focusMinutes;
  final int completedTodos;

  const FocusTodoPoint({
    required this.label,
    required this.start,
    required this.end,
    required this.focusMinutes,
    required this.completedTodos,
  });

  bool get hasActivity => focusMinutes > 0 || completedTodos > 0;
}

class FocusTodoCorrelation {
  final List<FocusTodoPoint> points;
  final double? pearson;

  const FocusTodoCorrelation({required this.points, required this.pearson});

  List<FocusTodoPoint> get activePoints =>
      points.where((point) => point.hasActivity).toList(growable: false);

  int get maxFocusMinutes => points.fold<int>(
    0,
    (max, point) => point.focusMinutes > max ? point.focusMinutes : max,
  );

  int get maxCompletedTodos => points.fold<int>(
    0,
    (max, point) => point.completedTodos > max ? point.completedTodos : max,
  );
}

class HabitTodoPoint {
  final String label;
  final DateTime start;
  final DateTime end;
  final int habitCheckIns;
  final int completedTodos;

  const HabitTodoPoint({
    required this.label,
    required this.start,
    required this.end,
    required this.habitCheckIns,
    required this.completedTodos,
  });

  bool get hasActivity => habitCheckIns > 0 || completedTodos > 0;
}

class HabitTodoCorrelation {
  final List<HabitTodoPoint> points;
  final double? pearson;

  const HabitTodoCorrelation({required this.points, required this.pearson});

  List<HabitTodoPoint> get activePoints =>
      points.where((point) => point.hasActivity).toList(growable: false);

  int get maxHabitCheckIns => points.fold<int>(
    0,
    (max, point) => point.habitCheckIns > max ? point.habitCheckIns : max,
  );

  int get maxCompletedTodos => points.fold<int>(
    0,
    (max, point) => point.completedTodos > max ? point.completedTodos : max,
  );
}

class DiaryFocusPoint {
  final String label;
  final DateTime start;
  final DateTime end;
  final int diaryEntries;
  final int focusMinutes;

  const DiaryFocusPoint({
    required this.label,
    required this.start,
    required this.end,
    required this.diaryEntries,
    required this.focusMinutes,
  });

  bool get hasActivity => diaryEntries > 0 || focusMinutes > 0;
}

class DiaryFocusCorrelation {
  final List<DiaryFocusPoint> points;
  final double? pearson;

  const DiaryFocusCorrelation({required this.points, required this.pearson});

  List<DiaryFocusPoint> get activePoints =>
      points.where((point) => point.hasActivity).toList(growable: false);

  int get maxDiaryEntries => points.fold<int>(
    0,
    (max, point) => point.diaryEntries > max ? point.diaryEntries : max,
  );

  int get maxFocusMinutes => points.fold<int>(
    0,
    (max, point) => point.focusMinutes > max ? point.focusMinutes : max,
  );
}

class FocusCompletionCorrelation {
  final List<FocusCompletionPoint> points;
  final double? coefficient;

  const FocusCompletionCorrelation({
    required this.points,
    required this.coefficient,
  });

  bool get hasData => points.any((point) => point.hasActivity);

  String get strengthLabel {
    final value = coefficient;
    if (value == null) return '样本不足';
    final abs = value.abs();
    if (abs >= 0.7) return value > 0 ? '强正相关' : '强负相关';
    if (abs >= 0.35) return value > 0 ? '中等正相关' : '中等负相关';
    return '相关性较弱';
  }

  String get insight {
    final value = coefficient;
    if (value == null) {
      return hasData ? '需要更多周期数据才能判断关系。' : '暂无可分析的专注和待办数据。';
    }
    final percent = (value * 100).round();
    if (value >= 0.35) {
      return '专注投入和待办完成同向变化，相关系数 $percent%。';
    }
    if (value <= -0.35) {
      return '专注投入增加时待办完成未同步增加，相关系数 $percent%。';
    }
    return '专注投入和待办完成的线性关系较弱，相关系数 $percent%。';
  }
}

class TimeCategoryShareBucket {
  final String label;
  final DateTime start;
  final DateTime end;
  final Map<Object, int> secondsByCategory;

  const TimeCategoryShareBucket({
    required this.label,
    required this.start,
    required this.end,
    required this.secondsByCategory,
  });

  int get totalSeconds =>
      secondsByCategory.values.fold(0, (sum, seconds) => sum + seconds);

  double shareFor(Object category) {
    final total = totalSeconds;
    if (total <= 0) return 0;
    return (secondsByCategory[category] ?? 0) / total;
  }

  Map<Object, double> get shareByCategory => {
    for (final category in secondsByCategory.keys) category: shareFor(category),
  };
}

class TimeCategoryShareTrend {
  final List<TimeCategoryShareBucket> buckets;
  final List<Object> categories;

  const TimeCategoryShareTrend({
    required this.buckets,
    required this.categories,
  });

  bool get hasData => buckets.any((bucket) => bucket.totalSeconds > 0);

  List<String> get categoryKeys =>
      categories.map((category) => category.toString()).toList(growable: false);
}

class TimeOutputPoint {
  final String label;
  final DateTime start;
  final DateTime end;
  final int timeMinutes;
  final int completedTodos;

  const TimeOutputPoint({
    required this.label,
    required this.start,
    required this.end,
    required this.timeMinutes,
    required this.completedTodos,
  });

  bool get hasActivity => timeMinutes > 0 || completedTodos > 0;

  double get completedTodosPerHour {
    if (timeMinutes <= 0) return 0;
    return completedTodos / (timeMinutes / 60);
  }
}

class TimeOutputEfficiencyTrend {
  final List<TimeOutputPoint> points;

  const TimeOutputEfficiencyTrend({required this.points});

  bool get hasData => points.any((point) => point.hasActivity);

  List<TimeOutputPoint> get activePoints =>
      points.where((point) => point.hasActivity).toList(growable: false);

  int get maxTimeMinutes => points.fold<int>(
    0,
    (max, point) => point.timeMinutes > max ? point.timeMinutes : max,
  );

  int get maxCompletedTodos => points.fold<int>(
    0,
    (max, point) => point.completedTodos > max ? point.completedTodos : max,
  );

  double get maxCompletedTodosPerHour => points.fold<double>(
    0,
    (max, point) =>
        point.completedTodosPerHour > max ? point.completedTodosPerHour : max,
  );
}

class ReportCrossAnalysisResult {
  final FocusTodoCorrelation focusTodo;
  final HabitTodoCorrelation habitTodo;
  final DiaryFocusCorrelation diaryFocus;
  final TimeCategoryShareTrend timeCategoryTrend;
  final TimeOutputEfficiencyTrend timeOutputEfficiency;

  const ReportCrossAnalysisResult({
    required this.focusTodo,
    required this.habitTodo,
    required this.diaryFocus,
    required this.timeCategoryTrend,
    required this.timeOutputEfficiency,
  });
}

class ReportCrossAnalysis {
  ReportCrossAnalysis._();

  static const otherCategoryKey = '__other__';

  static ReportCrossAnalysisResult build({
    required DateTime start,
    required DateTime end,
    required ReportCrossBucket bucket,
    required Iterable<ReportCrossTodoCompletion> todoCompletions,
    required Iterable<ReportCrossFocusSession> focusSessions,
    Iterable<ReportCrossHabitCompletion> habitCompletions = const [],
    Iterable<ReportCrossDiaryEntry> diaryEntries = const [],
    required Iterable<ReportCrossTimeEntry> timeEntries,
  }) {
    final todoCompletionRecords = [
      for (final item in todoCompletions)
        ReportCompletionRecord(completedAt: item.completedAt),
    ];
    final focusRecords = [
      for (final item in focusSessions)
        ReportFocusRecord(
          endedAt: item.endedAt,
          durationSeconds: item.durationSeconds,
        ),
    ];
    final timeRecords = [
      for (final item in timeEntries)
        ReportTimeCategoryRecord(
          startAt: item.startedAt,
          durationSeconds: item.durationSeconds,
          category: item.categoryKey,
        ),
    ];
    final analysisBucket = switch (bucket) {
      ReportCrossBucket.day => ReportCrossAnalysisBucket.day,
      ReportCrossBucket.month => ReportCrossAnalysisBucket.month,
    };
    final focusCompletion = buildFocusCompletionCorrelation(
      start: start,
      end: end,
      bucket: analysisBucket,
      completions: todoCompletionRecords,
      focusRecords: focusRecords,
    );
    final habitTodo = buildHabitTodoCorrelation(
      start: start,
      end: end,
      bucket: analysisBucket,
      completions: todoCompletionRecords,
      habitCompletions: [
        for (final item in habitCompletions)
          ReportHabitCompletionRecord(completedAt: item.completedAt),
      ],
    );
    final diaryFocus = buildDiaryFocusCorrelation(
      start: start,
      end: end,
      bucket: analysisBucket,
      diaryEntries: [
        for (final item in diaryEntries)
          ReportDiaryEntryRecord(writtenAt: item.writtenAt),
      ],
      focusRecords: focusRecords,
    );
    return ReportCrossAnalysisResult(
      focusTodo: FocusTodoCorrelation(
        points: [
          for (final point in focusCompletion.points)
            FocusTodoPoint(
              label: point.label,
              start: point.start,
              end: point.end,
              focusMinutes: point.focusMinutes,
              completedTodos: point.completedTodos,
            ),
        ],
        pearson: focusCompletion.coefficient,
      ),
      habitTodo: habitTodo,
      diaryFocus: diaryFocus,
      timeCategoryTrend: buildTimeCategoryShareTrend(
        start: start,
        end: end,
        bucket: analysisBucket,
        records: timeRecords,
      ),
      timeOutputEfficiency: buildTimeOutputEfficiencyTrend(
        start: start,
        end: end,
        bucket: analysisBucket,
        completions: todoCompletionRecords,
        records: timeRecords,
      ),
    );
  }

  static FocusCompletionCorrelation buildFocusCompletionCorrelation({
    required DateTime start,
    required DateTime end,
    required ReportCrossAnalysisBucket bucket,
    required List<ReportCompletionRecord> completions,
    required List<ReportFocusRecord> focusRecords,
  }) {
    final buckets = _buildBuckets(start: start, end: end, bucket: bucket);
    final points = [
      for (final item in buckets)
        FocusCompletionPoint(
          label: item.label,
          start: item.start,
          end: item.end,
          focusMinutes:
              focusRecords
                  .where(
                    (record) =>
                        _isInRange(record.endedAt, item.start, item.end),
                  )
                  .fold<int>(
                    0,
                    (sum, record) => sum + record.durationSeconds,
                  ) ~/
              60,
          completedTodos: completions
              .where(
                (record) =>
                    _isInRange(record.completedAt, item.start, item.end),
              )
              .length,
        ),
    ];

    return FocusCompletionCorrelation(
      points: points,
      coefficient: _pearson(
        points.map((point) => point.focusMinutes.toDouble()).toList(),
        points.map((point) => point.completedTodos.toDouble()).toList(),
      ),
    );
  }

  static HabitTodoCorrelation buildHabitTodoCorrelation({
    required DateTime start,
    required DateTime end,
    required ReportCrossAnalysisBucket bucket,
    required List<ReportCompletionRecord> completions,
    required List<ReportHabitCompletionRecord> habitCompletions,
  }) {
    final buckets = _buildBuckets(start: start, end: end, bucket: bucket);
    final points = [
      for (final item in buckets)
        HabitTodoPoint(
          label: item.label,
          start: item.start,
          end: item.end,
          habitCheckIns: habitCompletions
              .where(
                (record) => _isFloatingDateInRange(
                  record.completedAt,
                  item.start,
                  item.end,
                ),
              )
              .length,
          completedTodos: completions
              .where(
                (record) =>
                    _isInRange(record.completedAt, item.start, item.end),
              )
              .length,
        ),
    ];

    return HabitTodoCorrelation(
      points: points,
      pearson: _pearson(
        points.map((point) => point.habitCheckIns.toDouble()).toList(),
        points.map((point) => point.completedTodos.toDouble()).toList(),
      ),
    );
  }

  static DiaryFocusCorrelation buildDiaryFocusCorrelation({
    required DateTime start,
    required DateTime end,
    required ReportCrossAnalysisBucket bucket,
    required List<ReportDiaryEntryRecord> diaryEntries,
    required List<ReportFocusRecord> focusRecords,
  }) {
    final buckets = _buildBuckets(start: start, end: end, bucket: bucket);
    final points = [
      for (final item in buckets)
        DiaryFocusPoint(
          label: item.label,
          start: item.start,
          end: item.end,
          diaryEntries: diaryEntries
              .where(
                (record) => _isFloatingDateInRange(
                  record.writtenAt,
                  item.start,
                  item.end,
                ),
              )
              .length,
          focusMinutes:
              focusRecords
                  .where(
                    (record) =>
                        _isInRange(record.endedAt, item.start, item.end),
                  )
                  .fold<int>(
                    0,
                    (sum, record) => sum + record.durationSeconds,
                  ) ~/
              60,
        ),
    ];

    return DiaryFocusCorrelation(
      points: points,
      pearson: _pearson(
        points.map((point) => point.diaryEntries.toDouble()).toList(),
        points.map((point) => point.focusMinutes.toDouble()).toList(),
      ),
    );
  }

  static TimeCategoryShareTrend buildTimeCategoryShareTrend({
    required DateTime start,
    required DateTime end,
    required ReportCrossAnalysisBucket bucket,
    required List<ReportTimeCategoryRecord> records,
    int categoryLimit = 4,
  }) {
    final buckets = [
      for (final item in _buildBuckets(start: start, end: end, bucket: bucket))
        TimeCategoryShareBucket(
          label: item.label,
          start: item.start,
          end: item.end,
          secondsByCategory: _secondsByCategory(records, item.start, item.end),
        ),
    ];
    final totalByCategory = <Object, int>{};
    for (final bucket in buckets) {
      for (final entry in bucket.secondsByCategory.entries) {
        totalByCategory[entry.key] =
            (totalByCategory[entry.key] ?? 0) + entry.value;
      }
    }
    final rankedCategories = totalByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final positiveCategories = rankedCategories
        .where((entry) => entry.value > 0)
        .map((entry) => entry.key)
        .toList(growable: false);
    final visibleCategories = positiveCategories.length > categoryLimit
        ? [
            ...positiveCategories.take(
              (categoryLimit - 1).clamp(1, categoryLimit),
            ),
            otherCategoryKey,
          ]
        : positiveCategories.take(categoryLimit).toList(growable: false);
    final topCategories = visibleCategories
        .where((category) => category != otherCategoryKey)
        .toSet();
    final normalizedBuckets = visibleCategories.contains(otherCategoryKey)
        ? [
            for (final bucket in buckets)
              TimeCategoryShareBucket(
                label: bucket.label,
                start: bucket.start,
                end: bucket.end,
                secondsByCategory: _mergeOtherCategories(
                  bucket.secondsByCategory,
                  topCategories,
                ),
              ),
          ]
        : buckets;

    return TimeCategoryShareTrend(
      buckets: normalizedBuckets,
      categories: visibleCategories,
    );
  }

  static TimeOutputEfficiencyTrend buildTimeOutputEfficiencyTrend({
    required DateTime start,
    required DateTime end,
    required ReportCrossAnalysisBucket bucket,
    required List<ReportCompletionRecord> completions,
    required List<ReportTimeCategoryRecord> records,
  }) {
    final points = [
      for (final item in _buildBuckets(start: start, end: end, bucket: bucket))
        TimeOutputPoint(
          label: item.label,
          start: item.start,
          end: item.end,
          timeMinutes:
              records
                  .where(
                    (record) =>
                        record.durationSeconds > 0 &&
                        _isInRange(record.startAt, item.start, item.end),
                  )
                  .fold<int>(
                    0,
                    (sum, record) => sum + record.durationSeconds,
                  ) ~/
              60,
          completedTodos: completions
              .where(
                (record) =>
                    _isInRange(record.completedAt, item.start, item.end),
              )
              .length,
        ),
    ];

    return TimeOutputEfficiencyTrend(points: points);
  }

  static Map<Object, int> _mergeOtherCategories(
    Map<Object, int> source,
    Set<Object> topCategories,
  ) {
    final result = <Object, int>{};
    var otherSeconds = 0;
    for (final entry in source.entries) {
      if (topCategories.contains(entry.key)) {
        result[entry.key] = entry.value;
      } else {
        otherSeconds += entry.value;
      }
    }
    if (otherSeconds > 0) result[otherCategoryKey] = otherSeconds;
    return result;
  }

  static Map<Object, int> _secondsByCategory(
    List<ReportTimeCategoryRecord> records,
    DateTime start,
    DateTime end,
  ) {
    final result = <Object, int>{};
    for (final record in records) {
      if (record.durationSeconds <= 0) continue;
      if (!_isInRange(record.startAt, start, end)) continue;
      result[record.category] =
          (result[record.category] ?? 0) + record.durationSeconds;
    }
    return result;
  }

  static List<_ReportBucket> _buildBuckets({
    required DateTime start,
    required DateTime end,
    required ReportCrossAnalysisBucket bucket,
  }) {
    final normalizedStart = DateTime(start.year, start.month, start.day);
    final normalizedEnd = DateTime(end.year, end.month, end.day);
    if (bucket == ReportCrossAnalysisBucket.month) {
      final result = <_ReportBucket>[];
      var cursor = DateTime(normalizedStart.year, normalizedStart.month);
      while (!cursor.isAfter(normalizedEnd)) {
        final lastDay = DateTime(cursor.year, cursor.month + 1, 0);
        final bucketStart = cursor.isBefore(normalizedStart)
            ? normalizedStart
            : cursor;
        final bucketEnd = lastDay.isAfter(normalizedEnd)
            ? normalizedEnd
            : lastDay;
        result.add(
          _ReportBucket(
            label: '${cursor.month}月',
            start: bucketStart,
            end: bucketEnd,
          ),
        );
        cursor = DateTime(cursor.year, cursor.month + 1);
      }
      return result;
    }

    final result = <_ReportBucket>[];
    for (
      var cursor = normalizedStart;
      !cursor.isAfter(normalizedEnd);
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1)
    ) {
      result.add(
        _ReportBucket(
          label: '${cursor.month}/${cursor.day}',
          start: cursor,
          end: cursor,
        ),
      );
    }
    return result;
  }

  static bool _isInRange(DateTime value, DateTime start, DateTime end) {
    final startInstant = AppClock.date(start.year, start.month, start.day);
    final endExclusive = AppClock.date(end.year, end.month, end.day + 1);
    return !value.isBefore(startInstant) && value.isBefore(endExclusive);
  }

  static bool _isFloatingDateInRange(
    DateTime value,
    DateTime start,
    DateTime end,
  ) {
    final day = AppClock.dateOnly(value);
    final startDate = AppClock.dateOnly(start);
    final endExclusive = DateTime(end.year, end.month, end.day + 1);
    return !day.isBefore(startDate) && day.isBefore(endExclusive);
  }

  static double? _pearson(List<double> xs, List<double> ys) {
    if (xs.length != ys.length || xs.length < 2) return null;
    final xMean = xs.reduce((a, b) => a + b) / xs.length;
    final yMean = ys.reduce((a, b) => a + b) / ys.length;
    var numerator = 0.0;
    var xSquared = 0.0;
    var ySquared = 0.0;
    for (var i = 0; i < xs.length; i++) {
      final xDelta = xs[i] - xMean;
      final yDelta = ys[i] - yMean;
      numerator += xDelta * yDelta;
      xSquared += xDelta * xDelta;
      ySquared += yDelta * yDelta;
    }
    if (xSquared == 0 || ySquared == 0) return null;
    return numerator / math.sqrt(xSquared * ySquared);
  }
}

class _ReportBucket {
  final String label;
  final DateTime start;
  final DateTime end;

  const _ReportBucket({
    required this.label,
    required this.start,
    required this.end,
  });
}
