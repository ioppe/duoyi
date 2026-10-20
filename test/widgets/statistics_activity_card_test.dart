import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/statistics_period.dart';
import 'package:duoyi/widgets/habit_heatmap.dart';
import 'package:duoyi/widgets/statistics_activity_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    I18n.setLocale(AppLocale.zh);
    AppClock.debugNow = () => DateTime.utc(2026, 6, 17, 12);
  });
  tearDown(() => AppClock.debugNow = null);

  Future<void> open(
    WidgetTester tester,
    StatisticsPeriod period, {
    double scale = 1,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppBrands.defaultBrand.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatisticsActivityCard(
              window: StatisticsWindow(period),
              heatmapData: const {
                '2025-12-31': 5,
                '2026-01-10': 3,
                '2026-06-04': 2,
                '2026-06-16': 4,
                '2026-06-20': 5,
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'week and month contain exactly their own dates and exclude future activity',
    (tester) async {
      await open(tester, StatisticsPeriod.week);
      expect(find.text('本周活动分布'), findsOneWidget);
      expect(find.text('活跃 1 天'), findsOneWidget);
      expect(find.byType(HabitHeatmap), findsNothing);
      expect(
        find.byKey(const ValueKey('statistics_activity_2026-06-15')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('statistics_activity_2026-06-21')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('statistics_activity_2026-06-14')),
        findsNothing,
      );
      await open(tester, StatisticsPeriod.month);
      expect(find.text('本月活动日历'), findsOneWidget);
      expect(find.text('活跃 2 天'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('statistics_activity_2026-06-01')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('statistics_activity_2026-06-30')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('statistics_activity_2026-05-31')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'yearly heatmap is Jan-Dec in the selected year with no adjacent-year tooltips',
    (tester) async {
      await open(tester, StatisticsPeriod.year);
      expect(find.text('年度活动热力图'), findsOneWidget);
      expect(find.text('活跃 3 天'), findsOneWidget);
      final map = tester.widget<HabitHeatmap>(find.byType(HabitHeatmap));
      expect(map.startDate, DateTime.utc(2026));
      expect(map.endDate, DateTime.utc(2026, 12, 31));
      expect(
        find.byKey(const ValueKey('habit_heatmap_date_2026-01-01')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('habit_heatmap_date_2026-12-31')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('habit_heatmap_date_2025-12-31')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('habit_heatmap_date_2027-01-01')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'three activity views remain readable at 320px, 2x text and dark theme',
    (tester) async {
      for (final period in StatisticsPeriod.values) {
        await open(tester, period, scale: 2, theme: AppBrands.starRail.theme);
        expect(tester.takeException(), isNull, reason: period.name);
      }
    },
  );
}
