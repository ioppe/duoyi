import 'package:test/test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:duoyi/core/period_report.dart';

void main() {
  group('PeriodReport productivityScore', () {
    test(
      'combines completion, focus, habit, streak, and time-entry signals',
      () {
        final report = PeriodReport(
          start: DateTime(2026, 5, 11),
          end: DateTime(2026, 5, 17),
          todosCreated: 10,
          todosCompleted: 7,
          habitCheckIns: 7,
          longestHabitStreak: 7,
          focusSessions: 12,
          focusSeconds: 300 * 60,
          timeEntrySeconds: 210 * 60,
        );

        expect(report.dayCount, 7);
        expect(report.todoCompletionRate, 0.7);
        expect(report.focusMinutes, 300);
        expect(report.timeEntryMinutes, 210);
        expect(report.productivityScore, 78);
      },
    );

    test('caps score at 100 for saturated activity', () {
      final report = PeriodReport(
        start: DateTime(2026, 5, 11),
        end: DateTime(2026, 5, 17),
        todosCreated: 5,
        todosCompleted: 10,
        habitCheckIns: 30,
        longestHabitStreak: 30,
        focusSessions: 40,
        focusSeconds: 3000 * 60,
        timeEntrySeconds: 3000 * 60,
      );

      expect(report.todoCompletionRate, 1);
      expect(report.productivityScore, 100);
    });
  });

  group('ReportComparison', () {
    test(
      'returns metric deltas and percent changes against previous period',
      () {
        final current = PeriodReport(
          start: DateTime(2026, 5, 11),
          end: DateTime(2026, 5, 17),
          todosCreated: 10,
          todosCompleted: 7,
          habitCheckIns: 7,
          longestHabitStreak: 7,
          focusSessions: 12,
          focusSeconds: 300 * 60,
          timeEntrySeconds: 210 * 60,
        );
        final previous = PeriodReport(
          start: DateTime(2026, 5, 4),
          end: DateTime(2026, 5, 10),
          todosCreated: 10,
          todosCompleted: 5,
          habitCheckIns: 3,
          longestHabitStreak: 3,
          focusSessions: 5,
          focusSeconds: 120 * 60,
          timeEntrySeconds: 60 * 60,
        );

        final comparison = ReportComparison.compare(
          current: current,
          previous: previous,
        );

        expect(comparison.todosCompleted.difference, 2);
        expect(comparison.todosCompleted.percentChangeRounded, 40);
        expect(comparison.todoCompletionRate.difference, closeTo(0.2, 0.0001));
        expect(comparison.focusMinutes.difference, 180);
        expect(comparison.timeEntryMinutes.direction, ReportTrendDirection.up);
        expect(comparison.productivityScore.current, 78);
        expect(comparison.productivityScore.previous, 39);
        expect(comparison.productivityScore.percentChangeRounded, 100);
      },
    );

    test('keeps percent change empty when previous period has no baseline', () {
      final current = PeriodReport(
        start: DateTime(2026, 5, 11),
        end: DateTime(2026, 5, 17),
        todosCreated: 2,
        todosCompleted: 1,
        habitCheckIns: 0,
        longestHabitStreak: 0,
        focusSessions: 0,
        focusSeconds: 0,
        timeEntrySeconds: 0,
      );
      final previous = PeriodReport(
        start: DateTime(2026, 5, 4),
        end: DateTime(2026, 5, 10),
        todosCreated: 0,
        todosCompleted: 0,
        habitCheckIns: 0,
        longestHabitStreak: 0,
        focusSessions: 0,
        focusSeconds: 0,
        timeEntrySeconds: 0,
      );

      final comparison = ReportComparison.compare(
        current: current,
        previous: previous,
      );

      expect(comparison.todosCreated.hasBaseline, isFalse);
      expect(comparison.todosCreated.percentChangeRounded, isNull);
      expect(comparison.todosCreated.direction, ReportTrendDirection.up);
      expect(comparison.habitCheckIns.direction, ReportTrendDirection.flat);
    });

    test(
      'uses equal calendar-day targets when a compared week crosses DST',
      () {
        tzdata.initializeTimeZones();
        final zone = tz.getLocation('America/New_York');
        PeriodReport report(DateTime start, DateTime end) => PeriodReport(
          start: start,
          end: end,
          todosCreated: 14,
          todosCompleted: 7,
          habitCheckIns: 3,
          longestHabitStreak: 3,
          focusSessions: 7,
          focusSeconds: 210 * 60,
          timeEntrySeconds: 210 * 60,
        );
        final current = report(
          tz.TZDateTime(zone, 2026, 3, 8),
          tz.TZDateTime(zone, 2026, 3, 14),
        );
        final previous = report(
          tz.TZDateTime(zone, 2026, 3, 1),
          tz.TZDateTime(zone, 2026, 3, 7),
        );
        final fall = report(
          tz.TZDateTime(zone, 2026, 11, 1),
          tz.TZDateTime(zone, 2026, 11, 7),
        );
        final comparison = ReportComparison.compare(
          current: current,
          previous: previous,
        );

        expect(current.end.difference(current.start).inHours, 143);
        expect(previous.end.difference(previous.start).inHours, 144);
        expect(fall.end.difference(fall.start).inHours, 145);
        expect(current.dayCount, 7);
        expect(previous.dayCount, 7);
        expect(fall.dayCount, 7);
        expect(current.productivityScore, previous.productivityScore);
        expect(fall.productivityScore, previous.productivityScore);
        expect(comparison.productivityScore.difference, 0);
      },
    );
  });

  group('PeriodReportDigest', () {
    test('builds weekly highlights and markdown from report comparison', () {
      final current = PeriodReport(
        start: DateTime(2026, 5, 11),
        end: DateTime(2026, 5, 17),
        todosCreated: 10,
        todosCompleted: 7,
        habitCheckIns: 7,
        longestHabitStreak: 7,
        focusSessions: 12,
        focusSeconds: 300 * 60,
        timeEntrySeconds: 210 * 60,
        timeEntryByCategory: const {'work': 120 * 60, 'study': 90 * 60},
      );
      final previous = PeriodReport(
        start: DateTime(2026, 5, 4),
        end: DateTime(2026, 5, 10),
        todosCreated: 10,
        todosCompleted: 5,
        habitCheckIns: 3,
        longestHabitStreak: 3,
        focusSessions: 5,
        focusSeconds: 120 * 60,
        timeEntrySeconds: 60 * 60,
      );
      final digest = PeriodReportDigest(
        kind: PeriodReportKind.weekly,
        report: current,
        comparison: ReportComparison.compare(
          current: current,
          previous: previous,
        ),
        generatedAt: DateTime(2026, 5, 18),
      );

      expect(digest.title, '本周周报');
      expect(digest.subtitle, contains('7 天'));
      expect(digest.highlights.first, contains('综合效率 78 分'));
      expect(digest.highlights, contains(contains('完成待办 7 项')));
      expect(
        digest.notificationBody,
        '效率 78 分 · 完成 7/10 项 · 专注 5 小时 · 习惯 7 次 · 足迹 3 小时 30 分 · 较上期 +39 分',
      );

      final markdown = digest.toMarkdown(
        formatCategory: (category) => category == 'work' ? '工作' : '学习',
      );
      expect(markdown, contains('# 本周周报'));
      expect(markdown, contains('## 摘要'));
      expect(markdown, contains('## 关键指标'));
      expect(markdown, contains('## 环比变化'));
      expect(markdown, contains('## 时间投入 TOP'));
      expect(markdown, contains('工作：120 分钟'));
      expect(markdown, contains('学习：90 分钟'));
    });

    test('labels yearly digest as annual report', () {
      final report = PeriodReport(
        start: DateTime(2026),
        end: DateTime(2026, 12, 31),
        todosCreated: 100,
        todosCompleted: 80,
        habitCheckIns: 200,
        longestHabitStreak: 45,
        focusSessions: 120,
        focusSeconds: 3000 * 60,
        timeEntrySeconds: 4200 * 60,
      );
      final digest = PeriodReportDigest(
        kind: PeriodReportKind.yearly,
        report: report,
        comparison: ReportComparison.compare(current: report, previous: report),
        generatedAt: DateTime(2026, 12, 31),
      );

      expect(digest.title, '年度报告');
      expect(digest.subtitle, contains('全年成长轨迹'));
      expect(digest.toMarkdown(), contains('# 年度报告'));
    });

    test('builds empty-state notification body per report kind', () {
      PeriodReport empty(DateTime start, DateTime end) => PeriodReport(
        start: start,
        end: end,
        todosCreated: 0,
        todosCompleted: 0,
        habitCheckIns: 0,
        longestHabitStreak: 0,
        focusSessions: 0,
        focusSeconds: 0,
        timeEntrySeconds: 0,
      );

      final weekly = empty(DateTime(2026, 5, 11), DateTime(2026, 5, 17));
      final monthly = empty(DateTime(2026, 5, 1), DateTime(2026, 5, 31));

      expect(
        PeriodReportDigest(
          kind: PeriodReportKind.weekly,
          report: weekly,
          comparison: ReportComparison.compare(
            current: weekly,
            previous: weekly,
          ),
          generatedAt: DateTime(2026, 5, 18),
        ).notificationBody,
        '上周暂无记录，打开多仪规划本周节奏',
      );
      expect(
        PeriodReportDigest(
          kind: PeriodReportKind.monthly,
          report: monthly,
          comparison: ReportComparison.compare(
            current: monthly,
            previous: monthly,
          ),
          generatedAt: DateTime(2026, 6, 1),
        ).notificationBody,
        '上月暂无记录，打开多仪规划本月目标',
      );
    });
  });
}
