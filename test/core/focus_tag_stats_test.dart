import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/focus_tag_stats.dart';
import 'package:duoyi/core/report_engine.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:test/test.dart';

void main() {
  PomodoroSession session({
    required String id,
    required String? tag,
    required int minutes,
    PomodoroType type = PomodoroType.focus,
    DateTime? startAt,
  }) {
    final start = startAt ?? DateTime(2026, 5, 20, 9, 35);
    final end = start.add(Duration(minutes: minutes));
    return PomodoroSession(
      id: id,
      startTime: start,
      endTime: end,
      durationSeconds: minutes * 60,
      type: type,
      tag: tag,
    );
  }

  test(
    'groups focus sessions by normalized tag and ranks by total minutes',
    () {
      final stats = FocusTagStats.build(
        sessions: [
          session(id: '1', tag: '学习', minutes: 25),
          session(id: '2', tag: '#学习', minutes: 30),
          session(id: '3', tag: '工作', minutes: 40),
          session(id: '4', tag: ' ', minutes: 15),
          session(
            id: '5',
            tag: '学习',
            minutes: 5,
            type: PomodoroType.shortBreak,
          ),
        ],
      );

      expect(stats.map((s) => s.tag), [
        '学习',
        '工作',
        FocusTagStats.untaggedLabel,
      ]);
      expect(stats.first.totalMinutes, 55);
      expect(stats.first.sessionCount, 2);
      expect(stats.first.averageMinutes, 27);
      expect(stats.first.share, closeTo(55 / 110, 0.001));
    },
  );

  test('respects limit after sorting', () {
    final stats = FocusTagStats.build(
      limit: 2,
      sessions: [
        session(id: '1', tag: 'A', minutes: 10),
        session(id: '2', tag: 'B', minutes: 30),
        session(id: '3', tag: 'C', minutes: 20),
      ],
    );

    expect(stats.map((s) => s.tag), ['B', 'C']);
  });

  test('builds day trend for selected focus tags', () {
    final trend = FocusTagStats.buildTrend(
      start: DateTime(2026, 5, 18),
      end: DateTime(2026, 5, 20),
      tags: const ['学习', '工作'],
      bucket: FocusTagTrendBucket.day,
      sessions: [
        session(
          id: '1',
          tag: '学习',
          minutes: 25,
          startAt: DateTime(2026, 5, 18, 9),
        ),
        session(
          id: '2',
          tag: '#学习',
          minutes: 30,
          startAt: DateTime(2026, 5, 20, 9),
        ),
        session(
          id: '3',
          tag: '工作',
          minutes: 40,
          startAt: DateTime(2026, 5, 19, 9),
        ),
        session(
          id: '4',
          tag: '阅读',
          minutes: 50,
          startAt: DateTime(2026, 5, 20, 10),
        ),
      ],
    );

    expect(trend.map((s) => s.tag), ['学习', '工作']);
    expect(trend.first.points.map((p) => p.label), ['5/18', '5/19', '5/20']);
    expect(trend.first.points.map((p) => p.minutes), [25, 0, 30]);
    expect(trend.last.points.map((p) => p.minutes), [0, 40, 0]);
  });

  test('builds month trend for year range', () {
    final trend = FocusTagStats.buildTrend(
      start: DateTime(2026),
      end: DateTime(2026, 3, 20),
      tags: const ['学习'],
      bucket: FocusTagTrendBucket.month,
      sessions: [
        session(
          id: '1',
          tag: '学习',
          minutes: 25,
          startAt: DateTime(2026, 1, 10, 9),
        ),
        session(
          id: '2',
          tag: '学习',
          minutes: 30,
          startAt: DateTime(2026, 3, 1, 9),
        ),
      ],
    );

    expect(trend.single.points.map((p) => p.label), ['1月', '2月', '3月']);
    expect(trend.single.points.map((p) => p.minutes), [25, 0, 30]);
  });

  test('uses focus end times for midnight range and daily membership', () {
    final sessions = [
      session(
        id: 'ends-at-start',
        tag: 'study',
        minutes: 1,
        startAt: AppClock.date(2026, 5, 18, 23, 59),
      ),
      session(
        id: 'crosses-midnight',
        tag: 'study',
        minutes: 1,
        startAt: AppClock.date(2026, 5, 19, 23, 59),
      ),
      session(
        id: 'ends-at-exclusive-end',
        tag: 'study',
        minutes: 1,
        startAt: AppClock.date(2026, 5, 20, 23, 59),
      ),
    ];
    final start = DateTime(2026, 5, 19);
    final end = DateTime(2026, 5, 20);
    final trend = FocusTagStats.buildTrend(
      start: start,
      end: end,
      tags: const ['study'],
      bucket: FocusTagTrendBucket.day,
      sessions: sessions,
    );
    final report = ReportEngine.buildReport(
      start: start,
      end: end,
      todos: const [],
      habits: const [],
      sessions: sessions,
      timeEntries: const [],
    );

    expect(trend.single.points.map((point) => point.minutes), [1, 1]);
    expect(report.focusSessions, 2);
    expect(trend.single.totalMinutes, report.focusMinutes);
  });

  test('aggregates sub-minute seconds before converting every bucket kind', () {
    final sessions = [
      for (final (index, seconds) in [30, 35].indexed)
        PomodoroSession(
          id: 'short-$index',
          startTime: AppClock.date(2026, 5, 19, 9, index),
          endTime: AppClock.date(2026, 5, 19, 9, index, seconds),
          durationSeconds: seconds,
          type: PomodoroType.focus,
          tag: 'study',
        ),
    ];

    for (final bucket in FocusTagTrendBucket.values) {
      final trend = FocusTagStats.buildTrend(
        start: DateTime(2026, 5, 18),
        end: DateTime(2026, 5, 20),
        tags: const ['study'],
        bucket: bucket,
        sessions: sessions,
      );
      expect(trend.single.totalMinutes, 1, reason: bucket.name);
    }
  });

  test('clips natural Monday-Sunday buckets across a year boundary', () {
    final trend = FocusTagStats.buildTrend(
      start: DateTime(2026, 12, 30),
      end: DateTime(2027, 1, 12),
      tags: const ['study'],
      bucket: FocusTagTrendBucket.week,
      sessions: [
        for (final (index, date, minutes) in [
          (0, DateTime(2026, 12, 29, 10), 99),
          (1, DateTime(2026, 12, 30, 10), 5),
          (2, DateTime(2027, 1, 3, 10), 7),
          (3, DateTime(2027, 1, 4, 10), 11),
          (4, DateTime(2027, 1, 10, 10), 13),
          (5, DateTime(2027, 1, 11, 10), 17),
          (6, DateTime(2027, 1, 12, 10), 19),
          (7, DateTime(2027, 1, 13, 10), 99),
        ])
          session(id: '$index', tag: 'study', minutes: minutes, startAt: date),
      ],
    );

    expect(trend.single.points.map((point) => point.label), [
      '12/30–1/3',
      '1/4–1/10',
      '1/11–1/12',
    ]);
    expect(trend.single.points.map((point) => point.minutes), [12, 24, 36]);
  });
}
