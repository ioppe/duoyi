import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('统计页展示周期效率对比', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();

    expect(source, contains("import '../core/report_engine.dart';"));
    expect(source, contains('ReportEngine.buildReport'));
    expect(source, contains('ReportEngine.compare'));
    expect(source, contains('_ProductivityComparisonCard'));
    expect(source, contains('效率对比'));
    expect(source, contains('与上周同段对比'));
    expect(source, contains('完成率'));
    expect(source, contains('效率分'));
    expect(source, contains('较上期'));
  });

  test('统计页展示多周期效率趋势折线', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();

    expect(source, contains('_buildProductivityTrend'));
    expect(source, contains('_ProductivityTrendCard'));
    expect(source, contains('_ProductivityTrendPoint'));
    expect(source, contains('LineChart'));
    expect(source, contains('FlSpot'));
    expect(source, contains('效率趋势'));
    expect(source, contains('近 6 周同段效率分'));
    expect(source, contains('近 6 个月同段效率分'));
    expect(source, contains('近 5 年同段效率分'));
  });

  test('统计页展示趋势洞察和历史摘要', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();

    expect(source, contains('趋势洞察'));
    expect(source, contains('_insightText'));
    expect(source, contains('_bestPoint'));
    expect(source, contains('_averageScore'));
    expect(source, contains('_rankText'));
    expect(source, contains('_TrendHistoryMetric'));
    expect(source, contains('历史最佳'));
    expect(source, contains('平均分'));
    expect(source, contains('当前排名'));
  });

  test('统计页展示逐周期趋势详情 drill-down', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();

    expect(source, contains('查看趋势详情'));
    expect(source, contains('_ProductivityTrendDetailScreen'));
    expect(source, contains('MaterialPageRoute('));
    expect(source, contains("title: const Text('趋势详情')"));
    expect(
      source,
      contains('titleTextStyle: appSecondaryRouteTitleTextStyle(context)'),
    );
    expect(source, contains('趋势概览'));
    expect(source, contains('逐周期明细'));
    expect(source, contains('周期明细'));
    expect(source, contains('_TrendDetailTile'));
    expect(source, contains('_TrendDetailMetric'));
    expect(source, contains('dateRangeLabel'));
    expect(source, contains('point.completedTodos'));
    expect(source, contains('point.focusMinutes'));
    expect(source, contains('point.habitCheckIns'));
    expect(source, contains('point.timeEntryMinutes'));
    expect(source, contains("label: '待办'"));
    expect(source, contains("label: '专注'"));
    expect(source, contains("label: '习惯'"));
    expect(source, contains("label: '足迹'"));
    expect(source, contains("label: '最佳'"));
    expect(source, contains("label: '当前'"));
  });

  test('统计页展示全局活动热力图', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();

    expect(source, contains("import '../widgets/habit_heatmap.dart';"));
    expect(source, contains('_buildActivityHeatmap'));
    expect(source, contains('_ActivityHeatmapCard'));
    expect(source, contains('_HeatmapSummary'));
    expect(
      source,
      contains('HabitHeatmap(heatmapData: heatmapData, weeks: weeks)'),
    );
    expect(source, contains('年度活动热力图'));
    expect(source, contains("I18n.tr('statistics.activity.description')"));
    expect(source, isNot(contains('DiaryProvider')));
    expect(source, contains('颜色越深代表当天完成、记录或专注越多。'));
    expect(source, contains('static const int weeks = 52'));
  });

  test('统计页展示多维交叉分析', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();
    final core = File('lib/core/report_cross_analysis.dart').readAsStringSync();

    expect(source, contains("import '../core/report_cross_analysis.dart';"));
    expect(source, contains('ReportCrossAnalysis.build'));
    expect(source, contains('_buildFocusTodoCorrelationCard'));
    expect(source, contains('_buildFocusTodoScatter'));
    expect(source, contains('_buildHabitTodoCorrelationCard'));
    expect(source, contains('_buildHabitTodoScatter'));
    expect(source, isNot(contains('_buildDiaryFocus')));
    expect(source, contains('_buildTimeCategoryShareTrendCard'));
    expect(source, contains('_buildTimeCategoryShareChart'));
    expect(source, contains('_buildTimeOutputEfficiencyCard'));
    expect(source, contains('_buildTimeOutputEfficiencyChart'));
    expect(source, isNot(contains('ReportCrossDiaryEntry')));
    expect(source, isNot(contains('crossAnalysis.diaryFocus')));
    expect(source, contains('crossAnalysis.timeOutputEfficiency'));
    expect(source, contains('ScatterChart'));
    expect(source, contains('ScatterSpot'));
    expect(source, contains('BarChartRodStackItem'));
    expect(source, contains('专注 × 待办相关性'));
    expect(source, contains('横轴为专注分钟数，纵轴为待办完成数'));
    expect(source, contains('习惯 × 待办相关性'));
    expect(source, contains('横轴为习惯达标次数，纵轴为待办完成数'));
    expect(source, isNot(contains('日记')));
    expect(source, contains('时间分类占比趋势'));
    expect(source, contains('按当前周期展示各类时间投入结构变化'));
    expect(source, contains('时间投入 × 待办产出效率'));
    expect(source, contains('每小时完成'));

    expect(core, contains('class ReportCrossAnalysis'));
    expect(core, contains('class FocusTodoCorrelation'));
    expect(core, contains('class HabitTodoCorrelation'));
    expect(core, contains('class DiaryFocusCorrelation'));
    expect(core, contains('class TimeCategoryShareTrend'));
    expect(core, contains('class TimeOutputEfficiencyTrend'));
    expect(core, contains('class TimeOutputPoint'));
    expect(core, contains('timeOutputEfficiency'));
    expect(core, contains('final double? pearson'));
    expect(core, contains('otherCategoryKey'));
  });

  test('统计页按习惯达标周期聚合弹性打卡', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();

    expect(source, contains('habit.completionDatesInRange(start, end)'));
    expect(source, isNot(contains('habit.isCompletedForDate(d)')));
    expect(
      source,
      contains('final habitDoneInRange = habitCompletionDates.length'),
    );
  });

  test('统计页展示项目效率拆解', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();

    expect(source, contains("import '../core/project_efficiency.dart';"));
    expect(source, contains('context.watch<GoalProvider>()'));
    expect(source, contains('_buildProjectEfficiencyBreakdown'));
    expect(source, contains('_buildProjectEfficiencyCard'));
    expect(source, contains('_buildProjectEfficiencyChart'));
    expect(source, contains('_ProjectEfficiencyRow'));
    expect(source, contains('项目效率拆解'));
    expect(source, contains('按清单/目标汇总完成项、目标里程碑和时间投入'));
    expect(source, contains('项/时'));
  });
}
