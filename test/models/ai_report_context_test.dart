import 'package:duoyi/core/statistics_period.dart';
import 'package:duoyi/models/ai_report_context.dart';
import 'package:flutter_test/flutter_test.dart';

AiReportContext _fromWindow(StatisticsPeriod period, DateTime today) {
  return AiReportContext.fromWindow(
    StatisticsWindow(period, today: today),
    timeZone: 'Asia/Shanghai',
  );
}

void main() {
  group('AiReportContext.fromWindow', () {
    test(
      'week bounds are the full natural week, not the through-today end',
      () {
        final tuesday = _fromWindow(
          StatisticsPeriod.week,
          DateTime(2026, 5, 26),
        );
        final wednesday = _fromWindow(
          StatisticsPeriod.week,
          DateTime(2026, 5, 27),
        );

        expect(tuesday.start, DateTime.utc(2026, 5, 25));
        expect(tuesday.end, DateTime.utc(2026, 5, 31));
        expect(wednesday.end, DateTime.utc(2026, 5, 31));
        expect(tuesday.end, isNot(DateTime.utc(2026, 5, 26)));
      },
    );

    test('same natural period on different days keeps one stable key', () {
      final tuesday = _fromWindow(StatisticsPeriod.week, DateTime(2026, 5, 26));
      final wednesday = _fromWindow(
        StatisticsPeriod.week,
        DateTime(2026, 5, 27, 23, 59),
      );

      expect(wednesday.key, tuesday.key);
      expect(wednesday, tuesday);
      expect(wednesday.hashCode, tuesday.hashCode);
    });

    test('month and year bounds end at the full calendar period end', () {
      final month = _fromWindow(StatisticsPeriod.month, DateTime(2026, 5, 13));
      final year = _fromWindow(StatisticsPeriod.year, DateTime(2026, 5, 13));

      expect(month.start, DateTime.utc(2026, 5, 1));
      expect(month.end, DateTime.utc(2026, 5, 31));
      expect(year.start, DateTime.utc(2026, 1, 1));
      expect(year.end, DateTime.utc(2026, 12, 31));
    });

    test(
      'week, month, different weeks and different zones never share a key',
      () {
        final week = _fromWindow(StatisticsPeriod.week, DateTime(2026, 5, 26));
        final month = _fromWindow(
          StatisticsPeriod.month,
          DateTime(2026, 5, 26),
        );
        final year = _fromWindow(StatisticsPeriod.year, DateTime(2026, 5, 26));
        final nextWeek = _fromWindow(
          StatisticsPeriod.week,
          DateTime(2026, 6, 2),
        );
        final shanghai = _fromWindow(
          StatisticsPeriod.week,
          DateTime(2026, 5, 26),
        );
        final tokyo = AiReportContext.fromWindow(
          StatisticsWindow(StatisticsPeriod.week, today: DateTime(2026, 5, 26)),
          timeZone: 'Asia/Tokyo',
        );

        final keys = <String>{
          week.key,
          month.key,
          year.key,
          nextWeek.key,
          shanghai.key,
          tokyo.key,
        };
        expect(keys, hasLength(5));
        expect(tokyo.key, isNot(shanghai.key));
        expect(week.key, contains('Asia/Shanghai'));
      },
    );

    test('key ignores localized labels and does not shift floating dates', () {
      final context = _fromWindow(
        StatisticsPeriod.month,
        DateTime(2026, 5, 13),
      );

      expect(context.key, 'month|2026-05-01|2026-05-31|Asia/Shanghai');
      expect(context.key, isNot(contains('5月')));
    });
  });

  group('AiReportContext JSON', () {
    test('round-trips through JSON without time-shifting dates', () {
      final context = _fromWindow(StatisticsPeriod.week, DateTime(2026, 5, 26));
      final restored = AiReportContext.tryFromJson(
        Map<String, dynamic>.from(context.toJson()),
      );

      expect(restored, context);
      expect(restored!.start, DateTime.utc(2026, 5, 25));
      expect(restored.end, DateTime.utc(2026, 5, 31));
      expect(restored.timeZone, 'Asia/Shanghai');
    });

    test('normalizes time-of-day and non-UTC input dates', () {
      final context = AiReportContext(
        period: StatisticsPeriod.week,
        start: DateTime(2026, 5, 25, 18, 30),
        end: DateTime.utc(2026, 5, 31, 23),
        timeZone: ' Asia/Shanghai ',
      );

      expect(context.start, DateTime.utc(2026, 5, 25));
      expect(context.end, DateTime.utc(2026, 5, 31));
      expect(context.timeZone, 'Asia/Shanghai');
    });

    test('malformed or missing metadata yields null instead of throwing', () {
      expect(AiReportContext.tryFromJson(null), isNull);
      expect(AiReportContext.tryFromJson('week'), isNull);
      expect(AiReportContext.tryFromJson(<String, dynamic>{}), isNull);
      expect(
        AiReportContext.tryFromJson({
          'period': 'quarter',
          'start': '2026-05-25',
          'end': '2026-05-31',
        }),
        isNull,
      );
      expect(
        AiReportContext.tryFromJson({
          'period': 'week',
          'start': 'not-a-date',
          'end': '2026-05-31',
        }),
        isNull,
      );
      expect(
        AiReportContext.tryFromJson({
          'period': 'week',
          'start': '2026-05-25',
          'end': '2026-05-31',
          'timeZone': '',
        }),
        isNotNull,
      );
    });
  });

  group('AiReportReviewJob', () {
    test('running phases are only generating and saving', () {
      final context = _fromWindow(StatisticsPeriod.week, DateTime(2026, 5, 26));
      final startedAt = DateTime(2026, 5, 26, 9, 30);

      for (final phase in AiReportReviewPhase.values) {
        final job = AiReportReviewJob(
          context: context,
          startedAt: startedAt,
          phase: phase,
        );
        expect(
          job.isRunning,
          phase == AiReportReviewPhase.generating ||
              phase == AiReportReviewPhase.saving,
          reason: phase.name,
        );
      }
    });

    test('copyWith keeps context/startedAt and can clear the error', () {
      final context = _fromWindow(StatisticsPeriod.month, DateTime(2026, 6, 2));
      final job = AiReportReviewJob(
        context: context,
        startedAt: DateTime(2026, 6, 2, 8),
        phase: AiReportReviewPhase.failed,
        error: '存档失败',
        unsavedContent: '正文',
      );
      final saving = job.copyWith(
        phase: AiReportReviewPhase.saving,
        clearError: true,
      );

      expect(saving.context, context);
      expect(saving.startedAt, job.startedAt);
      expect(saving.phase, AiReportReviewPhase.saving);
      expect(saving.error, isNull);
      expect(saving.unsavedContent, '正文');
    });
  });
}
