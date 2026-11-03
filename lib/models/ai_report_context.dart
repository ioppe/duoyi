import '../core/statistics_period.dart';

/// 一次统计周期解读的存档身份：周期类型 + 完整自然周期边界 + 生成时的 IANA 时区。
///
/// 日期是“浮动日历日”（Y/M/D 归一为 UTC 午夜），因此更换语言、更换展示时区或
/// 在同一周期的不同日期（例如周二、周三）再次生成，都会落到同一个存档分组。
/// [end] 永远是完整自然周期的结束日，不包含“数据截止到哪天”的语义；
/// 截止日属于条目自身的快照元数据（`AiReviewEntry.dataThrough`）。
class AiReportContext {
  final StatisticsPeriod period;
  final DateTime start;
  final DateTime end;
  final String timeZone;

  factory AiReportContext({
    required StatisticsPeriod period,
    required DateTime start,
    required DateTime end,
    required String timeZone,
  }) {
    final normalizedStart = _calendarDate(start);
    final normalizedEnd = _calendarDate(end);
    return AiReportContext._(
      period: period,
      start: normalizedStart,
      end: normalizedEnd.isBefore(normalizedStart)
          ? normalizedStart
          : normalizedEnd,
      timeZone: timeZone.trim(),
    );
  }

  const AiReportContext._({
    required this.period,
    required this.start,
    required this.end,
    required this.timeZone,
  });

  /// 用统计页的真实窗口构造：结束日必须取完整自然周期边界（`calendarEnd`），
  /// 不能取“截止到今天”的 `window.end`。
  factory AiReportContext.fromWindow(
    StatisticsWindow window, {
    required String timeZone,
  }) {
    return AiReportContext(
      period: window.period,
      start: window.start,
      end: window.calendarEnd,
      timeZone: timeZone,
    );
  }

  /// 稳定分组键：只看周期与边界/时区，与标题、语言、dataThrough 无关。
  String get key =>
      '${period.name}|${_dateKey(start)}|'
      '${_dateKey(end)}|$timeZone';

  Map<String, dynamic> toJson() => {
    'period': period.name,
    'start': _dateKey(start),
    'end': _dateKey(end),
    'timeZone': timeZone,
  };

  /// 宽松解析：缺失或损坏的元数据返回 null，调用方继续保留正文内容。
  static AiReportContext? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final data = raw is Map<String, dynamic>
        ? raw
        : Map<String, dynamic>.from(raw);
    final period = _periodFromName(data['period']);
    final start = _parseCalendarDate(data['start']);
    final end = _parseCalendarDate(data['end']);
    if (period == null || start == null || end == null) return null;
    return AiReportContext(
      period: period,
      start: start,
      end: end,
      timeZone: (data['timeZone'] ?? '').toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AiReportContext &&
      other.period == period &&
      other.start == start &&
      other.end == end &&
      other.timeZone == timeZone;

  @override
  int get hashCode => Object.hash(period, start, end, timeZone);

  @override
  String toString() => 'AiReportContext($key)';
}

/// 一次周期解读任务所处阶段。只有存档成功后才进入“完成”（任务被移除）。
enum AiReportReviewPhase { generating, saving, failed }

/// 内存中的（未完成的）周期解读任务。应用退出后不会恢复，也不代表后台执行。
class AiReportReviewJob {
  final AiReportContext context;

  /// 真实时刻（不是浮动日历日），用于展示真实已用时长。
  final DateTime startedAt;
  final AiReportReviewPhase phase;
  final String? error;

  /// 模型已返回但存档失败时的正文，供复制或“仅重试保存”使用。
  final String? unsavedContent;

  const AiReportReviewJob({
    required this.context,
    required this.startedAt,
    this.phase = AiReportReviewPhase.generating,
    this.error,
    this.unsavedContent,
  });

  bool get isRunning =>
      phase == AiReportReviewPhase.generating ||
      phase == AiReportReviewPhase.saving;

  AiReportReviewJob copyWith({
    AiReportReviewPhase? phase,
    String? error,
    String? unsavedContent,
    bool clearError = false,
    bool clearUnsavedContent = false,
  }) {
    return AiReportReviewJob(
      context: context,
      startedAt: startedAt,
      phase: phase ?? this.phase,
      error: clearError ? null : (error ?? this.error),
      unsavedContent: clearUnsavedContent
          ? null
          : (unsavedContent ?? this.unsavedContent),
    );
  }

  @override
  String toString() =>
      'AiReportReviewJob(${context.key}, ${phase.name}, started: $startedAt)';
}

DateTime _calendarDate(DateTime value) => StatisticsSpan.calendarDate(value);

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime? _parseCalendarDate(Object? raw) {
  if (raw == null) return null;
  final text = raw.toString().trim();
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return StatisticsSpan.calendarDate(parsed);
}

StatisticsPeriod? _periodFromName(Object? raw) {
  final name = (raw ?? '').toString().trim().toLowerCase();
  for (final period in StatisticsPeriod.values) {
    if (period.name == name) return period;
  }
  return null;
}
