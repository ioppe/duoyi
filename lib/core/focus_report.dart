import '../models/pomodoro.dart';
import 'app_clock.dart';
import 'focus_tag_stats.dart';

enum FocusReportPeriod { week, month, all }

class FocusReport {
  final FocusReportPeriod period;
  final DateTime start;
  final DateTime end;
  final int sessionCount;
  final int totalSeconds;
  final int averageSeconds;
  final int longestSeconds;
  final int activeDays;
  final List<FocusTagStat> topTags;
  final int penaltyCount;
  final int penaltyAffectedSeconds;

  const FocusReport({
    required this.period,
    required this.start,
    required this.end,
    required this.sessionCount,
    required this.totalSeconds,
    required this.averageSeconds,
    required this.longestSeconds,
    required this.activeDays,
    required this.topTags,
    required this.penaltyCount,
    required this.penaltyAffectedSeconds,
  });

  int get totalMinutes => totalSeconds ~/ 60;

  int get averageMinutes => averageSeconds ~/ 60;

  int get longestMinutes => longestSeconds ~/ 60;

  int get penaltyAffectedMinutes => penaltyAffectedSeconds ~/ 60;

  String get title => switch (period) {
    FocusReportPeriod.week => '本周专注报告',
    FocusReportPeriod.month => '本月专注报告',
    FocusReportPeriod.all => '全部专注报告',
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# $title')
      ..writeln()
      ..writeln('- 周期：${_dateLabel(start)} - ${_dateLabel(end)}')
      ..writeln('- 专注总时长：$totalMinutes 分钟')
      ..writeln('- 专注次数：$sessionCount 次')
      ..writeln('- 平均单次：$averageMinutes 分钟')
      ..writeln('- 最长单次：$longestMinutes 分钟')
      ..writeln('- 活跃天数：$activeDays 天')
      ..writeln('- 严格专注中断：$penaltyCount 次，影响 $penaltyAffectedMinutes 分钟');
    if (topTags.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## 标签投入');
      for (final tag in topTags) {
        buffer.writeln(
          '- ${tag.tag}：${tag.totalMinutes} 分钟 / ${tag.sessionCount} 次，占比 ${(tag.share * 100).round()}%',
        );
      }
    }
    return buffer.toString();
  }

  static String _dateLabel(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class FocusReportBuilder {
  const FocusReportBuilder._();

  static FocusReport build({
    required Iterable<PomodoroSession> sessions,
    required Iterable<PomodoroFocusPenalty> penalties,
    required FocusReportPeriod period,
    DateTime? now,
  }) {
    final end = now == null ? AppClock.now() : AppClock.toLocal(now);
    final start = switch (period) {
      FocusReportPeriod.week => AppClock.date(
        end.year,
        end.month,
        end.day - end.weekday + 1,
      ),
      FocusReportPeriod.month => AppClock.date(end.year, end.month),
      FocusReportPeriod.all => DateTime.fromMillisecondsSinceEpoch(0),
    };
    final endExclusive = AppClock.date(end.year, end.month, end.day + 1);
    final focusSessions =
        sessions
            .where(
              (session) =>
                  session.type == PomodoroType.focus &&
                  session.durationSeconds > 0 &&
                  !session.startTime.isBefore(start) &&
                  session.startTime.isBefore(endExclusive),
            )
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final periodPenalties = penalties.where(
      (penalty) =>
          !penalty.occurredAt.isBefore(start) &&
          penalty.occurredAt.isBefore(endExclusive),
    );
    final totalSeconds = focusSessions.fold<int>(
      0,
      (sum, session) => sum + session.durationSeconds,
    );
    final longestSeconds = focusSessions.fold<int>(
      0,
      (max, session) =>
          session.durationSeconds > max ? session.durationSeconds : max,
    );
    final activeDays = {
      for (final session in focusSessions)
        _dateKey(AppClock.toLocal(session.startTime)),
    }.length;
    final penaltyList = periodPenalties.toList();
    return FocusReport(
      period: period,
      start: start,
      end: end,
      sessionCount: focusSessions.length,
      totalSeconds: totalSeconds,
      averageSeconds: focusSessions.isEmpty
          ? 0
          : totalSeconds ~/ focusSessions.length,
      longestSeconds: longestSeconds,
      activeDays: activeDays,
      topTags: FocusTagStats.build(sessions: focusSessions, limit: 5),
      penaltyCount: penaltyList.length,
      penaltyAffectedSeconds: penaltyList.fold<int>(
        0,
        (sum, penalty) => sum + penalty.affectedSeconds,
      ),
    );
  }

  static String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
