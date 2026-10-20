/// Pure data models for productivity reports.
///
/// Keep this file free of Flutter/model imports so report scoring and period
/// comparison can be verified with the Dart VM test runner.
library;

enum ReportTrendDirection { up, down, flat }

enum PeriodReportKind { daily, weekly, monthly, yearly }

class PeriodReport {
  /// 报告覆盖范围起点（含）。
  final DateTime start;

  /// 报告覆盖范围终点（含）。
  final DateTime end;

  /// 周期内创建的待办数。
  final int todosCreated;

  /// 周期内完成的待办数。
  final int todosCompleted;

  /// 周期内成功的习惯天数 / 弹性周期完成次数。
  final int habitCheckIns;

  /// 周期内已坚持的最长习惯连续天数。
  final int longestHabitStreak;

  /// 周期内完成的番茄数。
  final int focusSessions;

  /// 周期内累计专注秒数。
  final int focusSeconds;

  /// 周期内累计时间足迹秒数。
  final int timeEntrySeconds;

  /// 各类别时间足迹秒数。
  ///
  /// Key intentionally stays as [Object] so Flutter-facing code may use
  /// `TimeEntryCategory` enum keys while pure Dart tests can build reports
  /// without importing Flutter-dependent model files.
  final Map<Object, int> timeEntryByCategory;

  /// 完成率（完成 / 创建）。
  double get todoCompletionRate {
    if (todosCreated == 0) return 0;
    return (todosCompleted / todosCreated).clamp(0.0, 1.0);
  }

  /// 专注分钟。
  int get focusMinutes => focusSeconds ~/ 60;

  /// 时间足迹分钟。
  int get timeEntryMinutes => timeEntrySeconds ~/ 60;

  int get dayCount {
    final startDate = DateTime.utc(start.year, start.month, start.day);
    final endDate = DateTime.utc(end.year, end.month, end.day);
    final days = endDate.difference(startDate).inDays + 1;
    return days < 1 ? 1 : days;
  }

  bool get hasAnyActivity =>
      todosCreated > 0 ||
      todosCompleted > 0 ||
      habitCheckIns > 0 ||
      focusSessions > 0 ||
      timeEntrySeconds > 0;

  /// 0-100 综合效率分，用于周报/月报/年报和周期对比。
  ///
  /// 权重：待办完成率 35、专注时长 25、习惯打卡 20、最长连续 10、
  /// 时间足迹覆盖 10。时长目标按周期天数线性放大，避免周报和月报不可比。
  int get productivityScore {
    final focusTargetMinutes = dayCount * 60;
    final habitTarget = dayCount;
    final streakTarget = dayCount < 7 ? dayCount : 7;
    final timeEntryTargetMinutes = dayCount * 60;

    final score =
        _scoreShare(todoCompletionRate, 35) +
        _scoreShare(focusMinutes / focusTargetMinutes, 25) +
        _scoreShare(habitCheckIns / habitTarget, 20) +
        _scoreShare(longestHabitStreak / streakTarget, 10) +
        _scoreShare(timeEntryMinutes / timeEntryTargetMinutes, 10);
    return score.clamp(0, 100);
  }

  const PeriodReport({
    required this.start,
    required this.end,
    required this.todosCreated,
    required this.todosCompleted,
    required this.habitCheckIns,
    required this.longestHabitStreak,
    required this.focusSessions,
    required this.focusSeconds,
    required this.timeEntrySeconds,
    this.timeEntryByCategory = const {},
  });

  static int _scoreShare(double ratio, int maxScore) {
    return (ratio.clamp(0.0, 1.0) * maxScore).round();
  }
}

class ReportMetricDelta {
  final double current;
  final double previous;
  final double difference;
  final double? percentChange;

  const ReportMetricDelta._({
    required this.current,
    required this.previous,
    required this.difference,
    required this.percentChange,
  });

  factory ReportMetricDelta({required num current, required num previous}) {
    final currentValue = current.toDouble();
    final previousValue = previous.toDouble();
    final difference = currentValue - previousValue;
    return ReportMetricDelta._(
      current: currentValue,
      previous: previousValue,
      difference: difference,
      percentChange: previousValue == 0 ? null : difference / previousValue,
    );
  }

  bool get hasBaseline => percentChange != null;

  int? get percentChangeRounded =>
      percentChange == null ? null : (percentChange! * 100).round();

  ReportTrendDirection get direction {
    if (difference > 0) return ReportTrendDirection.up;
    if (difference < 0) return ReportTrendDirection.down;
    return ReportTrendDirection.flat;
  }
}

class ReportComparison {
  final PeriodReport current;
  final PeriodReport previous;
  final ReportMetricDelta todosCreated;
  final ReportMetricDelta todosCompleted;
  final ReportMetricDelta todoCompletionRate;
  final ReportMetricDelta habitCheckIns;
  final ReportMetricDelta longestHabitStreak;
  final ReportMetricDelta focusSessions;
  final ReportMetricDelta focusMinutes;
  final ReportMetricDelta timeEntryMinutes;
  final ReportMetricDelta productivityScore;

  const ReportComparison._({
    required this.current,
    required this.previous,
    required this.todosCreated,
    required this.todosCompleted,
    required this.todoCompletionRate,
    required this.habitCheckIns,
    required this.longestHabitStreak,
    required this.focusSessions,
    required this.focusMinutes,
    required this.timeEntryMinutes,
    required this.productivityScore,
  });

  factory ReportComparison.compare({
    required PeriodReport current,
    required PeriodReport previous,
  }) {
    return ReportComparison._(
      current: current,
      previous: previous,
      todosCreated: ReportMetricDelta(
        current: current.todosCreated,
        previous: previous.todosCreated,
      ),
      todosCompleted: ReportMetricDelta(
        current: current.todosCompleted,
        previous: previous.todosCompleted,
      ),
      todoCompletionRate: ReportMetricDelta(
        current: current.todoCompletionRate,
        previous: previous.todoCompletionRate,
      ),
      habitCheckIns: ReportMetricDelta(
        current: current.habitCheckIns,
        previous: previous.habitCheckIns,
      ),
      longestHabitStreak: ReportMetricDelta(
        current: current.longestHabitStreak,
        previous: previous.longestHabitStreak,
      ),
      focusSessions: ReportMetricDelta(
        current: current.focusSessions,
        previous: previous.focusSessions,
      ),
      focusMinutes: ReportMetricDelta(
        current: current.focusMinutes,
        previous: previous.focusMinutes,
      ),
      timeEntryMinutes: ReportMetricDelta(
        current: current.timeEntryMinutes,
        previous: previous.timeEntryMinutes,
      ),
      productivityScore: ReportMetricDelta(
        current: current.productivityScore,
        previous: previous.productivityScore,
      ),
    );
  }
}

class PeriodReportDigest {
  final PeriodReportKind kind;
  final PeriodReport report;
  final ReportComparison comparison;
  final DateTime generatedAt;

  const PeriodReportDigest({
    required this.kind,
    required this.report,
    required this.comparison,
    required this.generatedAt,
  });

  String get title => switch (kind) {
    PeriodReportKind.daily => '每日复盘',
    PeriodReportKind.weekly => '本周周报',
    PeriodReportKind.monthly => '本月月报',
    PeriodReportKind.yearly => '年度报告',
  };

  String get subtitle {
    final days = report.dayCount;
    return switch (kind) {
      PeriodReportKind.daily => '今天的效率复盘',
      PeriodReportKind.weekly => '最近 $days 天的效率复盘',
      PeriodReportKind.monthly => '本月 $days 天的时间投入',
      PeriodReportKind.yearly => '全年成长轨迹与关键成果',
    };
  }

  List<String> get highlights {
    final lines = <String>[
      '综合效率 ${report.productivityScore} 分，${_scoreLabel(report.productivityScore)}',
      '完成待办 ${report.todosCompleted} 项，${_deltaText(comparison.todosCompleted, unit: '项')}',
      '专注 ${report.focusMinutes} 分钟，${_deltaText(comparison.focusMinutes, unit: '分钟')}',
      '习惯打卡 ${report.habitCheckIns} 次，最长连续 ${report.longestHabitStreak} 天',
    ];
    if (report.timeEntryMinutes > 0) {
      lines.add(
        '记录时间足迹 ${report.timeEntryMinutes} 分钟，覆盖 ${report.timeEntryByCategory.length} 类投入',
      );
    }
    return lines;
  }

  String get notificationBody {
    if (!report.hasAnyActivity) {
      return switch (kind) {
        PeriodReportKind.daily => '今天暂无记录，打开多仪整理明日计划',
        PeriodReportKind.weekly => '上周暂无记录，打开多仪规划本周节奏',
        PeriodReportKind.monthly => '上月暂无记录，打开多仪规划本月目标',
        PeriodReportKind.yearly => '年度暂无记录，打开多仪开始新的时间计划',
      };
    }

    final pieces = <String>[
      '效率 ${report.productivityScore} 分',
      '完成 ${report.todosCompleted}/${report.todosCreated} 项',
    ];
    if (report.focusMinutes > 0) {
      pieces.add('专注 ${_compactMinutes(report.focusMinutes)}');
    }
    if (report.habitCheckIns > 0) {
      pieces.add('习惯 ${report.habitCheckIns} 次');
    }
    if (report.timeEntryMinutes > 0) {
      pieces.add('足迹 ${_compactMinutes(report.timeEntryMinutes)}');
    }

    final scoreDelta = comparison.productivityScore.difference.round();
    if (scoreDelta != 0) {
      pieces.add('较上期 ${scoreDelta > 0 ? '+' : '-'}${scoreDelta.abs()} 分');
    }
    return pieces.join(' · ');
  }

  String toMarkdown({
    String Function(DateTime date)? formatDate,
    String Function(Object category)? formatCategory,
  }) {
    final dateText = formatDate ?? _defaultDateText;
    final categoryText = formatCategory ?? (category) => category.toString();
    final categories =
        report.timeEntryByCategory.entries
            .where((entry) => entry.value > 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final sb = StringBuffer()
      ..writeln('# $title')
      ..writeln()
      ..writeln('范围：${dateText(report.start)} - ${dateText(report.end)}')
      ..writeln('生成时间：${dateText(generatedAt)}')
      ..writeln()
      ..writeln('## 摘要');
    for (final line in highlights) {
      sb.writeln('- $line');
    }
    sb
      ..writeln()
      ..writeln('## 关键指标')
      ..writeln('- 待办创建：${report.todosCreated} 项')
      ..writeln('- 待办完成：${report.todosCompleted} 项')
      ..writeln('- 完成率：${(report.todoCompletionRate * 100).round()}%')
      ..writeln('- 专注次数：${report.focusSessions} 次')
      ..writeln('- 专注时长：${report.focusMinutes} 分钟')
      ..writeln('- 习惯打卡：${report.habitCheckIns} 次')
      ..writeln('- 最长习惯连续：${report.longestHabitStreak} 天')
      ..writeln('- 时间足迹：${report.timeEntryMinutes} 分钟')
      ..writeln()
      ..writeln('## 环比变化')
      ..writeln('- 待办完成：${_deltaText(comparison.todosCompleted, unit: '项')}')
      ..writeln('- 专注时长：${_deltaText(comparison.focusMinutes, unit: '分钟')}')
      ..writeln('- 习惯打卡：${_deltaText(comparison.habitCheckIns, unit: '次')}')
      ..writeln('- 效率分：${_deltaText(comparison.productivityScore, unit: '分')}');

    if (categories.isNotEmpty) {
      sb
        ..writeln()
        ..writeln('## 时间投入 TOP');
      for (final entry in categories.take(5)) {
        sb.writeln(
          '- ${categoryText(entry.key)}：${(entry.value / 60).round()} 分钟',
        );
      }
    }
    return sb.toString();
  }

  static String _scoreLabel(int score) {
    if (score >= 85) return '状态很强';
    if (score >= 65) return '保持稳定';
    if (score >= 40) return '仍有提升空间';
    return '需要降低摩擦，从小步恢复节奏';
  }

  static String _deltaText(ReportMetricDelta delta, {required String unit}) {
    final value = delta.difference.round();
    if (value == 0) return '与上期持平';
    final direction = value > 0 ? '比上期多' : '比上期少';
    final absValue = value.abs();
    final percent = delta.percentChangeRounded;
    if (percent == null) return '$direction $absValue $unit';
    return '$direction $absValue $unit（${percent.abs()}%）';
  }

  static String _compactMinutes(int minutes) {
    if (minutes < 60) return '$minutes 分钟';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (rest == 0) return '$hours 小时';
    return '$hours 小时 $rest 分';
  }

  static String _defaultDateText(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
