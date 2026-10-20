import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/app_clock.dart';
import '../core/desktop_tokens.dart';
import '../core/design_tokens.dart';
import '../core/focus_tag_stats.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/project_efficiency.dart';
import '../core/report_cross_analysis.dart';
import '../core/report_engine.dart';
import '../core/report_time_slices.dart';
import '../core/statistics_period.dart';
import '../models/goal.dart';
import '../models/habit.dart';
import '../models/pomodoro.dart';
import '../models/time_entry.dart';
import '../models/todo.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/time_audit_provider.dart';
import '../providers/todo_provider.dart';
import '../services/ai_service.dart';
import '../widgets/statistics_activity_card.dart';
import '../widgets/result_states.dart';
import '../widgets/surface_components.dart';
import 'ai_history_screen.dart';
import 'time_audit_screen.dart';

enum _Range { week, month, year }

enum _ReportPdfTemplate { visual, archive, briefing, dashboard, timeline }

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  _Range _range = _Range.week;
  bool _aiReportBusy = false;
  String? _aiReportReview;
  String? _aiReportError;

  StatisticsWindow get _window =>
      StatisticsWindow(StatisticsPeriod.values[_range.index]);

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final todoProv = context.watch<TodoProvider>();
    final goalProv = context.watch<GoalProvider>();
    final habitProv = context.watch<HabitProvider>();
    context.select<PomodoroProvider, int>(
      (provider) => provider.persistedRevision,
    );
    final pomoProv = context.read<PomodoroProvider>();
    final timeAuditProv = context.watch<TimeAuditProvider>();
    final ai = context.watch<AiService>();
    final cs = Theme.of(context).colorScheme;

    final window = _window;
    final start = window.start;
    final end = window.end;
    final previous = window.previous;
    final previousStart = previous.start;
    final previousEnd = previous.end;
    final habitCompletionDatesById = {
      for (final habit in habitProv.habits)
        habit.id: habit.completionDatesInRange(start, end),
    };
    final habitCompletionDates = habitCompletionDatesById.values
        .expand((dates) => dates)
        .toList();
    final report = ReportEngine.buildReport(
      start: start,
      end: end,
      todos: todoProv.todos,
      habits: habitProv.habits,
      sessions: pomoProv.sessions,
      timeEntries: timeAuditProv.entries,
      habitCompletionDatesById: habitCompletionDatesById,
    );
    final previousReport = ReportEngine.buildReport(
      start: previousStart,
      end: previousEnd,
      todos: todoProv.todos,
      habits: habitProv.habits,
      sessions: pomoProv.sessions,
      timeEntries: timeAuditProv.entries,
    );
    final comparison = ReportEngine.compare(
      current: report,
      previous: previousReport,
    );
    final digest = PeriodReportDigest(
      kind: switch (_range) {
        _Range.week => PeriodReportKind.weekly,
        _Range.month => PeriodReportKind.monthly,
        _Range.year => PeriodReportKind.yearly,
      },
      report: report,
      comparison: comparison,
      generatedAt: AppClock.now(),
    );
    final productivityTrend = _buildProductivityTrend(
      range: _range,
      start: start,
      end: end,
      todos: todoProv.todos,
      habits: habitProv.habits,
      sessions: pomoProv.sessions,
      timeEntries: timeAuditProv.entries,
    );
    final activityHeatmap = _buildActivityHeatmap(
      window: window,
      todos: todoProv.todos,
      habits: habitProv.habits,
      sessions: pomoProv.sessions,
      timeEntries: timeAuditProv.entries,
    );
    final rangeStart = window.startInstant;
    final rangeEnd = window.endExclusive;
    final auditEntries = reportTimeEntriesInRange(
      timeAuditProv.entries,
      start: start,
      end: end,
    );
    final auditTotalMinutes =
        timeAuditProv.totalSecondsInRange(rangeStart, rangeEnd) ~/ 60;
    final auditCategorySeconds = timeAuditProv.secondsByCategory(
      rangeStart,
      rangeEnd,
    );
    bool inRange(DateTime d) => !d.isBefore(rangeStart) && d.isBefore(rangeEnd);

    final completedTodos = todoProv.completedTodos.where((t) {
      final ts = t.completedAt ?? t.updatedAt;
      return inRange(ts);
    }).toList();

    final focusSessions = pomoProv.sessions
        .where((s) => s.type == PomodoroType.focus && inRange(s.endTime))
        .toList();
    final focusMinutes =
        focusSessions.fold<int>(0, (sum, s) => sum + s.durationSeconds) ~/ 60;
    final focusTagStats = FocusTagStats.build(sessions: focusSessions);
    final focusTagTrend = FocusTagStats.buildTrend(
      sessions: focusSessions,
      start: start,
      end: end,
      tags: focusTagStats.map((stat) => stat.tag).take(3),
      bucket: switch (_range) {
        _Range.week => FocusTagTrendBucket.day,
        _Range.month => FocusTagTrendBucket.week,
        _Range.year => FocusTagTrendBucket.month,
      },
    );
    final crossAnalysis = ReportCrossAnalysis.build(
      start: start,
      end: end,
      bucket: switch (_range) {
        _Range.week => ReportCrossBucket.day,
        _Range.month => ReportCrossBucket.week,
        _Range.year => ReportCrossBucket.month,
      },
      todoCompletions: completedTodos.map(
        (todo) => ReportCrossTodoCompletion(todo.completedAt ?? todo.updatedAt),
      ),
      focusSessions: focusSessions.map(
        (session) => ReportCrossFocusSession(
          endedAt: session.endTime,
          durationSeconds: session.durationSeconds,
        ),
      ),
      habitCompletions: habitCompletionDates.map(
        ReportCrossHabitCompletion.new,
      ),
      timeEntries: auditEntries.map(
        (entry) => ReportCrossTimeEntry(
          startedAt: entry.startAt,
          durationSeconds: entry.durationSeconds,
          categoryKey: entry.category.name,
        ),
      ),
    );
    final projectEfficiency = _buildProjectEfficiencyBreakdown(
      start: start,
      end: end,
      completedTodos: completedTodos,
      goals: goalProv.goals,
      timeEntries: auditEntries,
      todos: todoProv.todos,
    );

    final habitDoneInRange = habitCompletionDates.length;

    final now = AppClock.now();
    final quadrantStats = _buildQuadrantStats({
      for (final quadrant in EisenhowerQuadrant.values)
        quadrant: todoProv.getQuadrantTodos(quadrant),
    }, now: now);

    final sourceSeconds = timeAuditProv.secondsBySource(rangeStart, rangeEnd);
    final totalSeconds = timeAuditProv.totalSecondsInRange(
      rangeStart,
      rangeEnd,
    );
    final daySeconds = timeAuditProv.secondsByDay(rangeStart, rangeEnd);

    return Scaffold(
      appBar: AppBar(
        title: const Text('时光足迹'),
        actions: [
          IconButton(
            tooltip: '复制报告',
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: () => _copyReport(
              context,
              start: start,
              end: end,
              completedTodos: completedTodos,
              focusMinutes: focusMinutes,
              habitDoneInRange: habitDoneInRange,
              auditTotalMinutes: auditTotalMinutes,
              auditCategorySeconds: auditCategorySeconds,
              auditEntries: auditEntries,
            ),
          ),
          IconButton(
            tooltip: '报告分享图',
            icon: const Icon(Icons.image_outlined),
            onPressed: () => _showReportShareCard(
              context,
              start: start,
              end: end,
              completedTodos: completedTodos,
              focusMinutes: focusMinutes,
              habitDoneInRange: habitDoneInRange,
              auditTotalMinutes: auditTotalMinutes,
              auditCategorySeconds: auditCategorySeconds,
              auditEntries: auditEntries,
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SegmentedButton<_Range>(
              segments: [
                for (final range in _Range.values)
                  ButtonSegment(
                    value: range,
                    label: Text(I18n.tr('statistics.period.${range.name}')),
                  ),
              ],
              selected: {_range},
              onSelectionChanged: (s) => setState(() {
                _range = s.first;
                _aiReportReview = null;
                _aiReportError = null;
              }),
            ),
          ),
        ),
      ),
      body: _widescreenReportBody(
        isWidescreen:
            MediaQuery.widthOf(context) >= DesktopTokens.breakpointTwoColumn,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Padding(
              key: const ValueKey('statistics_period_context'),
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${I18nDateFormat.date(start)} — ${I18nDateFormat.date(end)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    I18n.tr('statistics.scope.${_range.name}'),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final crossAxisCount = width >= 720
                    ? 3
                    : width < 360
                    ? 1
                    : 2;
                final childAspectRatio = crossAxisCount == 1
                    ? 4.2
                    : width >= 720
                    ? 2.8
                    : 2.5;
                // 系统大字号（如 font_scale 2.0）下，按固定 childAspectRatio
                // 折算的瓦片高度装不下“标题+数值”两行文本，实测出现
                // BOTTOM OVERFLOWED（1/2/3 列断点全部中招）。照搬
                // today_screen 的兜底模式：按当前系统字号换算内容所需的
                // 最小高度，通过 mainAxisExtent 取两者较大者。_Kpi 竖向
                // 内容为标题 11×1.45 + 数值 16×1.45（各平台默认字体行高
                // 系数实测 1.17～1.43 不等，取上限留裕度），与不随字号
                // 缩放的图标盒 34 取大，外加卡内边距 20、描边 1、余量 6；
                // 1.0 缩放下折算高度（68.15）低于最小断点的宽高比高度
                // （320 宽单列 70.5），视觉完全不变；三个断点任意字号下
                // 都不溢出。
                final textScaler = MediaQuery.textScalerOf(context);
                final minTileExtent =
                    math.max(
                      34.0,
                      textScaler.scale(11 * 1.45) +
                          textScaler.scale(16 * 1.45) +
                          6,
                    ) +
                    23;
                // GridView 撑满 LayoutBuilder 宽度，与框架内部折算公式
                // （crossAxisExtent / aspectRatio）保持一致，1.0 缩放下
                // 视觉不变。
                final tileWidth =
                    (width - (crossAxisCount - 1) * 8) / crossAxisCount;
                final tileExtent = math.max(
                  tileWidth / childAspectRatio,
                  minTileExtent,
                );
                return GridView.count(
                  key: const ValueKey('statistics_kpi_grid'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: childAspectRatio,
                  mainAxisExtent: tileExtent,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    _Kpi(
                      icon: Icons.check_circle,
                      color: cs.primary,
                      title: '待办完成',
                      value: '${completedTodos.length}',
                    ),
                    _Kpi(
                      icon: Icons.timer,
                      color: Colors.redAccent,
                      title: '深度专注',
                      value: '$focusMinutes 分',
                    ),
                    _Kpi(
                      icon: Icons.repeat,
                      color: const Color(0xFF66BB6A),
                      title: '习惯打卡',
                      value: '$habitDoneInRange 次',
                    ),
                    _Kpi(
                      icon: Icons.timelapse_outlined,
                      color: const Color(0xFF78909C),
                      title: '时间足迹',
                      value: '$auditTotalMinutes 分',
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            _PeriodReportDigestCard(
              digest: digest,
              cs: cs,
              onCopy: () => _copyDigest(context, digest),
              aiEnabled: ai.enabled,
              aiBusy: _aiReportBusy,
              aiReview: _aiReportReview,
              aiError: _aiReportError,
              onAiReview: () => _runDigestAiReview(context, digest),
              onOpenAiHistory: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AiHistoryScreen()),
              ),
              onShareImage: () => _showReportShareCard(
                context,
                start: start,
                end: end,
                completedTodos: completedTodos,
                focusMinutes: focusMinutes,
                habitDoneInRange: habitDoneInRange,
                auditTotalMinutes: auditTotalMinutes,
                auditCategorySeconds: auditCategorySeconds,
                auditEntries: auditEntries,
              ),
            ),
            const SizedBox(height: 10),
            _ProductivityComparisonCard(
              comparison: comparison,
              range: _range,
              cs: cs,
            ),
            const SizedBox(height: 10),
            _ProductivityTrendCard(points: productivityTrend, range: _range),
            const SizedBox(height: 10),
            StatisticsActivityCard(
              key: const ValueKey('statistics_activity_card'),
              window: window,
              heatmapData: activityHeatmap,
            ),
            const SizedBox(height: 10),
            _PeriodTimeOverview(
              key: const ValueKey('statistics_time_overview'),
              window: window,
              totalSeconds: totalSeconds,
              sourceSeconds: sourceSeconds,
              daySeconds: daySeconds,
              cs: cs,
            ),
            const SizedBox(height: 10),
            _chartCard(
              '时间投入分布',
              SizedBox(
                height: 180,
                child: _buildAuditPie(
                  secondsByCategory: auditCategorySeconds,
                  cs: cs,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _chartCard('时间线', _buildAuditTimeline(auditEntries, cs)),
            const SizedBox(height: 10),
            AppSurfaceCard(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                key: ValueKey('statistics_analysis_${_range.name}'),
                title: Text(I18n.tr('statistics.analysis')),
                shape: const Border(),
                collapsedShape: const Border(),
                childrenPadding: const EdgeInsets.all(8),
                children: [
                  _buildFocusTodoCorrelationCard(
                    correlation: crossAnalysis.focusTodo,
                    cs: cs,
                  ),
                  const SizedBox(height: 10),
                  _buildHabitTodoCorrelationCard(
                    correlation: crossAnalysis.habitTodo,
                    cs: cs,
                  ),
                  const SizedBox(height: 10),
                  _buildTimeCategoryShareTrendCard(
                    trend: crossAnalysis.timeCategoryTrend,
                    cs: cs,
                  ),
                  const SizedBox(height: 10),
                  _buildTimeOutputEfficiencyCard(
                    trend: crossAnalysis.timeOutputEfficiency,
                    cs: cs,
                  ),
                  const SizedBox(height: 10),
                  _buildProjectEfficiencyCard(
                    breakdown: projectEfficiency,
                    cs: cs,
                  ),
                  const SizedBox(height: 10),
                  _chartCard(
                    I18n.tr('statistics.focus.${_range.name}'),
                    SizedBox(
                      height: 180,
                      child: _buildFocusSeries(
                        sessions: focusSessions,
                        range: _range,
                        start: start,
                        end: end,
                        cs: cs,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildFocusTagRankingCard(stats: focusTagStats, cs: cs),
                  const SizedBox(height: 10),
                  _buildFocusTagTrendCard(
                    series: focusTagTrend,
                    range: _range,
                    cs: cs,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _QuadrantDistributionCard(stats: quadrantStats, cs: cs),
          ],
        ),
      ),
    );
  }

  /// 宽屏桌面档：报告内容限宽居中（KPI 网格在 ≥720 内宽保持 3 列所需
  /// 最小外宽 960，见 [DesktopTokens.reportMaxContentWidth]）；窄屏原样。
  Widget _widescreenReportBody({
    required bool isWidescreen,
    required Widget child,
  }) {
    if (!isWidescreen) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: DesktopTokens.reportMaxContentWidth,
        ),
        child: child,
      ),
    );
  }

  List<_ProductivityTrendPoint> _buildProductivityTrend({
    required _Range range,
    required DateTime start,
    required DateTime end,
    required List<TodoItem> todos,
    required List<Habit> habits,
    required List<PomodoroSession> sessions,
    required List<TimeEntry> timeEntries,
  }) {
    final window = StatisticsWindow(
      StatisticsPeriod.values[range.index],
      today: end,
    );
    final buckets = window.buckets;
    final completions = {
      for (final habit in habits)
        habit.id: habit.completionDatesInRange(start, end),
    };
    return [
      for (var index = 0; index < buckets.length; index++)
        _productivityTrendPoint(
          label: _statisticsBucketLabel(window.period, buckets[index], index),
          start: buckets[index].start,
          end: buckets[index].end,
          todos: todos,
          habits: habits,
          sessions: sessions,
          timeEntries: timeEntries,
          habitCompletionDatesById: completions,
        ),
    ];
  }

  _ProductivityTrendPoint _productivityTrendPoint({
    required String label,
    required DateTime start,
    required DateTime end,
    required List<TodoItem> todos,
    required List<Habit> habits,
    required List<PomodoroSession> sessions,
    required List<TimeEntry> timeEntries,
    required Map<String, Iterable<DateTime>> habitCompletionDatesById,
  }) {
    final report = ReportEngine.buildReport(
      start: start,
      end: end,
      todos: todos,
      habits: habits,
      sessions: sessions,
      timeEntries: timeEntries,
      habitCompletionDatesById: habitCompletionDatesById,
    );
    return _ProductivityTrendPoint(
      label: label,
      start: start,
      end: end,
      report: report,
    );
  }

  Map<String, int> _buildActivityHeatmap({
    required StatisticsWindow window,
    required List<TodoItem> todos,
    required List<Habit> habits,
    required List<PomodoroSession> sessions,
    required List<TimeEntry> timeEntries,
  }) {
    final raw = <String, int>{};

    void add(DateTime date, int amount) {
      if (amount <= 0 || !window.containsDate(date)) return;
      final key = _dateKey(date);
      raw[key] = (raw[key] ?? 0) + amount;
    }

    for (final todo in todos) {
      final completedAt = todo.completedAt;
      if (todo.isCompleted && completedAt != null) {
        add(AppClock.toLocal(completedAt), 2);
      }
    }
    for (final habit in habits) {
      for (final entry in habit.completions.entries) {
        final date = _parseDateKey(entry.key);
        if (date != null && habit.activeForDate(date)) add(date, entry.value);
      }
    }
    for (final session in sessions) {
      if (session.type == PomodoroType.focus) {
        add(AppClock.toLocal(session.endTime), 2);
      }
    }
    for (final entry in reportTimeEntriesInRange(
      timeEntries,
      start: window.start,
      end: window.end,
    )) {
      final minutes = entry.durationSeconds ~/ 60;
      add(AppClock.toLocal(entry.startAt), minutes >= 60 ? 2 : 1);
    }

    return raw.map((key, value) => MapEntry(key, value.clamp(0, 5)));
  }

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  DateTime? _parseDateKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  Widget _chartCard(String title, Widget child) {
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: DesignTokens.fontWeightStrong,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  List<_QuadrantStat> _buildQuadrantStats(
    Map<EisenhowerQuadrant, List<TodoItem>> groups, {
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);

    _QuadrantStat stat(
      EisenhowerQuadrant quadrant, {
      required String label,
      required String action,
      required String guidance,
      required Color color,
      required IconData icon,
    }) {
      final items = groups[quadrant] ?? const <TodoItem>[];
      final active = items.where((todo) => !todo.isCompleted).length;
      final completed = items.where((todo) => todo.isCompleted).length;
      final overdue = items.where((todo) {
        final due = todo.localDueDate;
        if (todo.isCompleted || due == null) return false;
        return DateTime(due.year, due.month, due.day).isBefore(today);
      }).length;
      final dueToday = items.where((todo) {
        final due = todo.localDueDate;
        if (todo.isCompleted || due == null) return false;
        return due.year == today.year &&
            due.month == today.month &&
            due.day == today.day;
      }).length;
      return _QuadrantStat(
        label: label,
        action: action,
        guidance: guidance,
        color: color,
        icon: icon,
        totalCount: items.length,
        activeCount: active,
        completedCount: completed,
        overdueCount: overdue,
        dueTodayCount: dueToday,
      );
    }

    return [
      stat(
        EisenhowerQuadrant.urgentImportant,
        label: '重要紧急',
        action: '立即处理',
        guidance: '优先清空逾期和今天到期事项。',
        color: const Color(0xFFE53935),
        icon: Icons.priority_high_rounded,
      ),
      stat(
        EisenhowerQuadrant.notUrgentImportant,
        label: '重要不紧急',
        action: '安排计划',
        guidance: '保持推进节奏，避免滚入紧急区。',
        color: const Color(0xFFF6A339),
        icon: Icons.event_available_outlined,
      ),
      stat(
        EisenhowerQuadrant.urgentNotImportant,
        label: '紧急不重要',
        action: '委派或限时',
        guidance: '用批量处理减少被打断时间。',
        color: const Color(0xFF42A5F5),
        icon: Icons.swap_horiz_rounded,
      ),
      stat(
        EisenhowerQuadrant.notUrgentNotImportant,
        label: '不重要不紧急',
        action: '清理剔除',
        guidance: '定期归档，避免待办池膨胀。',
        color: const Color(0xFF8E8E8E),
        icon: Icons.filter_alt_off_outlined,
      ),
    ];
  }

  Widget _buildFocusTagRankingCard({
    required List<FocusTagStat> stats,
    required ColorScheme cs,
  }) {
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '专注标签排行',
            style: TextStyle(
              fontWeight: DesignTokens.fontWeightStrong,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          if (stats.isEmpty)
            const EmptyHint(icon: Icons.timer_outlined, message: '暂无专注标签数据')
          else
            for (final (index, stat) in stats.indexed)
              Padding(
                padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        '#${index + 1}',
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: DesignTokens.fontWeightStrong,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  stat.tag,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${stat.totalMinutes} 分',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          _buildFocusTagShare(stat.share, cs),
                          const SizedBox(height: 4),
                          Text(
                            '${stat.sessionCount} 次 · 平均 ${stat.averageMinutes} 分',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildFocusTagShare(double share, ColorScheme cs) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: share.clamp(0, 1),
        minHeight: 6,
        backgroundColor: cs.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
      ),
    );
  }

  Widget _buildFocusTagTrendCard({
    required List<FocusTagTrendSeries> series,
    required _Range range,
    required ColorScheme cs,
  }) {
    final activeSeries = series
        .where((item) => item.points.any((point) => point.minutes > 0))
        .toList();
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '专注标签趋势',
                  style: TextStyle(
                    fontWeight: DesignTokens.fontWeightStrong,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                I18n.tr('statistics.granularity.${range.name}'),
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (activeSeries.isEmpty)
            const EmptyHint(icon: Icons.trending_up, message: '暂无专注标签趋势')
          else ...[
            SizedBox(
              height: 190,
              child: _buildFocusTagTrendChart(activeSeries, cs),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                for (final (index, item) in activeSeries.indexed)
                  _legend(_focusTagTrendColor(index, cs), item.tag),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFocusTagTrendChart(
    List<FocusTagTrendSeries> series,
    ColorScheme cs,
  ) {
    final points = series.first.points;
    final maxMinutes = series.fold<int>(
      0,
      (max, item) => item.maxMinutes > max ? item.maxMinutes : max,
    );
    final maxY = (maxMinutes * 1.2).clamp(10, double.infinity).toDouble();

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY <= 30 ? 10 : null,
          getDrawingHorizontalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (value, _) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onSurface.withValues(alpha: 0.56),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, _) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) {
                  return const SizedBox();
                }
                if (points.length > 10 && index.isOdd) {
                  return const SizedBox();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    points[index].label,
                    style: TextStyle(
                      fontSize: 9,
                      color: cs.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            getTooltipItems: (items) => [
              for (final item in items)
                LineTooltipItem(
                  '${series[item.barIndex].tag}\n'
                  '${points[item.x.toInt()].label} · ${item.y.toInt()} 分',
                  TextStyle(
                    color: cs.onInverseSurface,
                    fontSize: 11,
                    fontFamily: DesignTokens.fontFamilyRounded,
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
            ],
          ),
        ),
        lineBarsData: [
          for (final (seriesIndex, item) in series.indexed)
            LineChartBarData(
              spots: [
                for (int i = 0; i < item.points.length; i++)
                  FlSpot(i.toDouble(), item.points[i].minutes.toDouble()),
              ],
              isCurved: true,
              preventCurveOverShooting: true,
              color: _focusTagTrendColor(seriesIndex, cs),
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: seriesIndex == 0,
                color: _focusTagTrendColor(
                  seriesIndex,
                  cs,
                ).withValues(alpha: 0.08),
              ),
            ),
        ],
      ),
    );
  }

  Color _focusTagTrendColor(int index, ColorScheme cs) {
    final colors = [
      cs.primary,
      const Color(0xFF26A69A),
      const Color(0xFFFF9800),
    ];
    return colors[index % colors.length];
  }

  Widget _buildFocusTodoCorrelationCard({
    required FocusTodoCorrelation correlation,
    required ColorScheme cs,
  }) {
    final activePoints = correlation.activePoints;
    final r = correlation.pearson;
    final rText = r == null ? '样本不足' : r.toStringAsFixed(2);
    final insight = r == null
        ? '需要至少两个有变化的周期点，才能判断专注投入与待办完成的关系。'
        : r >= 0.45
        ? '专注分钟数越高，待办完成数通常同步提升。'
        : r <= -0.45
        ? '专注投入和待办完成出现反向变化，适合检查任务粒度或专注目标。'
        : '两者关系较弱，当前周期的完成数可能更多受任务数量、难度或日程影响。';

    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '专注 × 待办相关性',
                  style: TextStyle(
                    fontWeight: DesignTokens.fontWeightStrong,
                    fontSize: 13,
                  ),
                ),
              ),
              _CrossMetricBadge(label: 'r', value: rText, cs: cs),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '横轴为专注分钟数，纵轴为待办完成数',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 190,
            child: activePoints.isEmpty
                ? const EmptyHint(icon: Icons.donut_small, message: '暂无交叉分析数据')
                : _buildFocusTodoScatter(correlation, cs),
          ),
          const SizedBox(height: 10),
          Text(
            insight,
            style: TextStyle(
              fontSize: 11,
              height: 1.45,
              color: cs.onSurface.withValues(alpha: 0.64),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusTodoScatter(
    FocusTodoCorrelation correlation,
    ColorScheme cs,
  ) {
    final activePoints = correlation.activePoints;
    final maxX = (correlation.maxFocusMinutes * 1.2)
        .clamp(10, 100000)
        .toDouble();
    final maxY = (correlation.maxCompletedTodos * 1.2)
        .clamp(3, 100000)
        .toDouble();

    FocusTodoPoint? pointFor(ScatterSpot spot) {
      for (final point in activePoints) {
        if (point.focusMinutes.toDouble() == spot.x &&
            point.completedTodos.toDouble() == spot.y) {
          return point;
        }
      }
      return null;
    }

    return ScatterChart(
      ScatterChartData(
        minX: 0,
        maxX: maxX,
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          getDrawingHorizontalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.45),
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.3),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        scatterTouchData: ScatterTouchData(
          touchSpotThreshold: 16,
          touchTooltipData: ScatterTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            getTooltipItems: (spot) {
              final point = pointFor(spot);
              return ScatterTooltipItem(
                point == null
                    ? '${spot.x.toInt()} 分 / ${spot.y.toInt()} 项'
                    : '${point.label}\n${point.focusMinutes} 分 / ${point.completedTodos} 项',
                textStyle: TextStyle(
                  color: cs.onInverseSurface,
                  fontSize: 11,
                  fontFamily: DesignTokens.fontFamilyRounded,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, _) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onSurface.withValues(alpha: 0.56),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, _) => Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    fontSize: 9,
                    color: cs.onSurface.withValues(alpha: 0.56),
                  ),
                ),
              ),
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        scatterSpots: [
          for (final point in activePoints)
            ScatterSpot(
              point.focusMinutes.toDouble(),
              point.completedTodos.toDouble(),
              dotPainter: FlDotCirclePainter(
                radius: 5,
                color: cs.primary,
                strokeWidth: 2,
                strokeColor: cs.surface,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHabitTodoCorrelationCard({
    required HabitTodoCorrelation correlation,
    required ColorScheme cs,
  }) {
    final activePoints = correlation.activePoints;
    final r = correlation.pearson;
    final rText = r == null ? '样本不足' : r.toStringAsFixed(2);
    final insight = r == null
        ? '需要至少两个有变化的周期点，才能判断习惯达标与待办完成的关系。'
        : r >= 0.45
        ? '习惯达标越稳定，待办完成数通常也更高。'
        : r <= -0.45
        ? '习惯达标和待办完成出现反向变化，适合检查当天计划是否过载。'
        : '两者关系较弱，当前周期的待办完成可能更多受任务难度或外部日程影响。';

    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '习惯 × 待办相关性',
                  style: TextStyle(
                    fontWeight: DesignTokens.fontWeightStrong,
                    fontSize: 13,
                  ),
                ),
              ),
              _CrossMetricBadge(label: 'r', value: rText, cs: cs),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '横轴为习惯达标次数，纵轴为待办完成数',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 190,
            child: activePoints.isEmpty
                ? const EmptyHint(icon: Icons.repeat, message: '暂无习惯交叉数据')
                : _buildHabitTodoScatter(correlation, cs),
          ),
          const SizedBox(height: 10),
          Text(
            insight,
            style: TextStyle(
              fontSize: 11,
              height: 1.45,
              color: cs.onSurface.withValues(alpha: 0.64),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHabitTodoScatter(
    HabitTodoCorrelation correlation,
    ColorScheme cs,
  ) {
    final activePoints = correlation.activePoints;
    final maxX = (correlation.maxHabitCheckIns * 1.2)
        .clamp(3, 100000)
        .toDouble();
    final maxY = (correlation.maxCompletedTodos * 1.2)
        .clamp(3, 100000)
        .toDouble();

    HabitTodoPoint? pointFor(ScatterSpot spot) {
      for (final point in activePoints) {
        if (point.habitCheckIns.toDouble() == spot.x &&
            point.completedTodos.toDouble() == spot.y) {
          return point;
        }
      }
      return null;
    }

    return ScatterChart(
      ScatterChartData(
        minX: 0,
        maxX: maxX,
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          getDrawingHorizontalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.45),
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.3),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        scatterTouchData: ScatterTouchData(
          touchSpotThreshold: 16,
          touchTooltipData: ScatterTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            getTooltipItems: (spot) {
              final point = pointFor(spot);
              return ScatterTooltipItem(
                point == null
                    ? '${spot.x.toInt()} 次 / ${spot.y.toInt()} 项'
                    : '${point.label}\n${point.habitCheckIns} 次 / ${point.completedTodos} 项',
                textStyle: TextStyle(
                  color: cs.onInverseSurface,
                  fontSize: 11,
                  fontFamily: DesignTokens.fontFamilyRounded,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, _) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onSurface.withValues(alpha: 0.56),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, _) => Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  value.toInt().toString(),
                  style: TextStyle(
                    fontSize: 9,
                    color: cs.onSurface.withValues(alpha: 0.56),
                  ),
                ),
              ),
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        scatterSpots: [
          for (final point in activePoints)
            ScatterSpot(
              point.habitCheckIns.toDouble(),
              point.completedTodos.toDouble(),
              dotPainter: FlDotCirclePainter(
                radius: 5,
                color: cs.tertiary,
                strokeWidth: 2,
                strokeColor: cs.surface,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeCategoryShareTrendCard({
    required TimeCategoryShareTrend trend,
    required ColorScheme cs,
  }) {
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '时间分类占比趋势',
            style: TextStyle(
              fontWeight: DesignTokens.fontWeightStrong,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '按当前周期展示各类时间投入结构变化',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 200,
            child: trend.hasData
                ? _buildTimeCategoryShareChart(trend, cs)
                : const EmptyHint(
                    icon: Icons.pie_chart_outline,
                    message: '暂无时间分类趋势',
                  ),
          ),
          if (trend.hasData) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                for (final key in trend.categoryKeys)
                  _legend(
                    _crossCategoryColor(key, cs),
                    _crossCategoryLabel(key),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeCategoryShareChart(
    TimeCategoryShareTrend trend,
    ColorScheme cs,
  ) {
    final buckets = trend.buckets;
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: 100,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.45),
            strokeWidth: 1,
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              if (groupIndex < 0 || groupIndex >= buckets.length) return null;
              final bucket = buckets[groupIndex];
              final lines = <String>[
                bucket.label,
                for (final key in trend.categoryKeys)
                  if ((bucket.secondsByCategory[key] ?? 0) > 0)
                    '${_crossCategoryLabel(key)} '
                        '${((bucket.shareByCategory[key] ?? 0) * 100).round()}%',
              ];
              return BarTooltipItem(
                lines.join('\n'),
                TextStyle(
                  color: cs.onInverseSurface,
                  fontSize: 11,
                  fontFamily: DesignTokens.fontFamilyRounded,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: 25,
              getTitlesWidget: (value, _) => Text(
                '${value.toInt()}%',
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onSurface.withValues(alpha: 0.56),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, _) {
                final index = value.toInt();
                if (index < 0 || index >= buckets.length) {
                  return const SizedBox();
                }
                if (buckets.length > 10 && index.isOdd) {
                  return const SizedBox();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    buckets[index].label,
                    style: TextStyle(
                      fontSize: 9,
                      color: cs.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (final (index, bucket) in buckets.indexed)
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: 100,
                  width: buckets.length > 14 ? 8 : 14,
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                  rodStackItems: _buildShareStackItems(bucket, trend, cs),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTimeOutputEfficiencyCard({
    required TimeOutputEfficiencyTrend trend,
    required ColorScheme cs,
  }) {
    final points = trend.points;
    final hasData = points.any((point) => point.hasActivity);
    final average = _averageCompletedTodosPerHour(points);

    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '时间投入 × 待办产出效率',
                  style: TextStyle(
                    fontWeight: DesignTokens.fontWeightStrong,
                    fontSize: 13,
                  ),
                ),
              ),
              _CrossMetricBadge(
                label: '每小时完成',
                value: average <= 0 ? '0 项' : '${average.toStringAsFixed(1)} 项',
                cs: cs,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '按当前周期展示每小时完成项',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
            child: hasData
                ? _buildTimeOutputEfficiencyChart(trend, cs)
                : const EmptyHint(icon: Icons.swap_vert, message: '暂无时间投入产出数据'),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeOutputEfficiencyChart(
    TimeOutputEfficiencyTrend trend,
    ColorScheme cs,
  ) {
    final points = trend.points;
    final peak = points.fold<double>(
      0,
      (max, point) =>
          point.completedTodosPerHour > max ? point.completedTodosPerHour : max,
    );
    final maxY = peak <= 0 ? 1.0 : peak * 1.25;
    final interval = _timeOutputAxisInterval(maxY);

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.45),
            strokeWidth: 1,
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              if (groupIndex < 0 || groupIndex >= points.length) return null;
              final point = points[groupIndex];
              return BarTooltipItem(
                '${_timeOutputPeriodLabel(point)}\n'
                '每小时完成 ${point.completedTodosPerHour.toStringAsFixed(1)} 项\n'
                '${point.timeMinutes} 分 / ${point.completedTodos} 项',
                TextStyle(
                  color: cs.onInverseSurface,
                  fontSize: 11,
                  fontFamily: DesignTokens.fontFamilyRounded,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: interval,
              getTitlesWidget: (value, _) => Text(
                _formatTimeOutputRate(value),
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onSurface.withValues(alpha: 0.56),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, _) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) {
                  return const SizedBox();
                }
                if (points.length > 10 && index.isOdd) {
                  return const SizedBox();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: SizedBox(
                    width: 38,
                    child: Text(
                      _timeOutputPeriodLabel(points[index]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        color: cs.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (final (index, point) in points.indexed)
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: point.completedTodosPerHour,
                  width: points.length > 14 ? 7 : 12,
                  color: const Color(0xFF26A69A),
                  borderRadius: BorderRadius.circular(4),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY,
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.54),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  ProjectEfficiencyBreakdown _buildProjectEfficiencyBreakdown({
    required DateTime start,
    required DateTime end,
    required List<TodoItem> completedTodos,
    required List<GoalItem> goals,
    required List<TimeEntry> timeEntries,
    required List<TodoItem> todos,
  }) {
    final todoById = {for (final todo in todos) todo.id: todo};
    final goalById = {for (final goal in goals) goal.id: goal};

    return ProjectEfficiencyAnalyzer.build(
      todoCompletions: completedTodos.map(
        (todo) => ProjectEfficiencyTodoCompletion(
          completedAt: todo.completedAt ?? todo.updatedAt,
          projectKey: _todoProjectKey(todo),
          projectLabel: _todoProjectLabel(todo),
        ),
      ),
      goalCompletions: [
        for (final goal in goals)
          for (final milestone in goal.milestones)
            if (milestone.isCompleted &&
                milestone.completedAt != null &&
                _isDateTimeInRange(milestone.completedAt!, start, end))
              ProjectEfficiencyGoalCompletion(
                completedAt: milestone.completedAt!,
                projectKey: _goalProjectKey(goal),
                projectLabel: _goalProjectLabel(goal),
              ),
      ],
      timeAllocations: [
        for (final entry in timeEntries)
          if (entry.durationSeconds > 0)
            ProjectEfficiencyTimeAllocation(
              projectKey: _timeEntryProjectKey(
                entry,
                todoById: todoById,
                goalById: goalById,
              ),
              projectLabel: _timeEntryProjectLabel(
                entry,
                todoById: todoById,
                goalById: goalById,
              ),
              durationSeconds: entry.durationSeconds,
            ),
      ],
    );
  }

  Widget _buildProjectEfficiencyCard({
    required ProjectEfficiencyBreakdown breakdown,
    required ColorScheme cs,
  }) {
    final items = breakdown.rankedItems.take(6).toList(growable: false);
    final top = breakdown.topItem;

    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '项目效率拆解',
                  style: TextStyle(
                    fontWeight: DesignTokens.fontWeightStrong,
                    fontSize: 13,
                  ),
                ),
              ),
              _CrossMetricBadge(
                label: '最高',
                value: top == null
                    ? '暂无'
                    : '${top.outputPerHour.toStringAsFixed(1)} 项/时',
                cs: cs,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '按清单/目标汇总完成项、目标里程碑和时间投入',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const EmptyHint(icon: Icons.speed, message: '暂无项目效率数据')
          else ...[
            SizedBox(
              height: 190,
              child: _buildProjectEfficiencyChart(items, cs),
            ),
            const SizedBox(height: 10),
            for (final item in items.take(4))
              _ProjectEfficiencyRow(
                item: item,
                maxOutputPerHour: breakdown.maxOutputPerHour,
                cs: cs,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildProjectEfficiencyChart(
    List<ProjectEfficiencyItem> items,
    ColorScheme cs,
  ) {
    final maxY =
        (items.fold<double>(
                  0,
                  (max, item) =>
                      item.outputPerHour > max ? item.outputPerHour : max,
                ) *
                1.25)
            .clamp(1, double.infinity)
            .toDouble();
    final interval = _timeOutputAxisInterval(maxY);

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.45),
            strokeWidth: 1,
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              if (groupIndex < 0 || groupIndex >= items.length) return null;
              final item = items[groupIndex];
              return BarTooltipItem(
                '${item.projectLabel}\n'
                '${item.outputCount} 项输出 / ${item.timeMinutes} 分\n'
                '${item.outputPerHour.toStringAsFixed(1)} 项/时',
                TextStyle(
                  color: cs.onInverseSurface,
                  fontSize: 11,
                  fontFamily: DesignTokens.fontFamilyRounded,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: interval,
              getTitlesWidget: (value, _) => Text(
                _formatTimeOutputRate(value),
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onSurface.withValues(alpha: 0.56),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: 1,
              getTitlesWidget: (value, _) {
                final index = value.toInt();
                if (index < 0 || index >= items.length) {
                  return const SizedBox();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: SizedBox(
                    width: 44,
                    child: Text(
                      items[index].projectLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        color: cs.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (final (index, item) in items.indexed)
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: item.outputPerHour,
                  width: items.length > 5 ? 10 : 14,
                  color: _projectEfficiencyColor(index, cs),
                  borderRadius: BorderRadius.circular(4),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY,
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.54),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _todoProjectKey(TodoItem todo) {
    final id = todo.listGroupId?.trim();
    if (id != null && id.isNotEmpty) return 'todo:$id';
    final name = todo.listGroupName?.trim();
    if (name != null && name.isNotEmpty) return 'todo_name:$name';
    return 'todo:inbox';
  }

  String _todoProjectLabel(TodoItem todo) {
    final name = todo.listGroupName?.trim();
    return name == null || name.isEmpty ? '收件箱' : name;
  }

  String _goalProjectKey(GoalItem goal) => 'goal:${goal.id}';

  String _goalProjectLabel(GoalItem goal) =>
      goal.title.trim().isEmpty ? '未命名目标' : goal.title.trim();

  String _timeEntryProjectKey(
    TimeEntry entry, {
    required Map<String, TodoItem> todoById,
    required Map<String, GoalItem> goalById,
  }) {
    if (entry.source == TimeEntrySource.todo && entry.sourceId != null) {
      final todo = todoById[entry.sourceId!];
      if (todo != null) return _todoProjectKey(todo);
    }
    if (entry.source == TimeEntrySource.goal && entry.sourceId != null) {
      final goalId = entry.sourceId!.split(':').first;
      final goal = goalById[goalId];
      if (goal != null) return _goalProjectKey(goal);
    }
    return 'manual:${entry.category.name}';
  }

  String _timeEntryProjectLabel(
    TimeEntry entry, {
    required Map<String, TodoItem> todoById,
    required Map<String, GoalItem> goalById,
  }) {
    if (entry.source == TimeEntrySource.todo && entry.sourceId != null) {
      final todo = todoById[entry.sourceId!];
      if (todo != null) return _todoProjectLabel(todo);
    }
    if (entry.source == TimeEntrySource.goal && entry.sourceId != null) {
      final goalId = entry.sourceId!.split(':').first;
      final goal = goalById[goalId];
      if (goal != null) return _goalProjectLabel(goal);
    }
    return entry.category.label;
  }

  bool _isDateTimeInRange(DateTime value, DateTime start, DateTime end) {
    final startDate = AppClock.date(start.year, start.month, start.day);
    final endExclusive = AppClock.date(end.year, end.month, end.day + 1);
    return !value.isBefore(startDate) && value.isBefore(endExclusive);
  }

  Color _projectEfficiencyColor(int index, ColorScheme cs) {
    final colors = [
      cs.primary,
      const Color(0xFF26A69A),
      const Color(0xFFFF9800),
      const Color(0xFFAB47BC),
      const Color(0xFF78909C),
      cs.tertiary,
    ];
    return colors[index % colors.length];
  }

  String _timeOutputPeriodLabel(TimeOutputPoint point) {
    final dynamic dynamicPoint = point;
    try {
      return dynamicPoint.periodLabel as String;
    } on NoSuchMethodError {
      return dynamicPoint.label as String;
    }
  }

  double _averageCompletedTodosPerHour(List<TimeOutputPoint> points) {
    final activePoints = points
        .where((point) => point.timeMinutes > 0 || point.completedTodos > 0)
        .toList(growable: false);
    if (activePoints.isEmpty) return 0;
    final total = activePoints.fold<double>(
      0,
      (sum, point) => sum + point.completedTodosPerHour,
    );
    return total / activePoints.length;
  }

  double _timeOutputAxisInterval(double maxY) {
    if (maxY <= 2) return 0.5;
    if (maxY <= 6) return 1;
    return (maxY / 4).ceilToDouble();
  }

  String _formatTimeOutputRate(double value) {
    if (value == 0) return '0';
    if (value >= 10) return value.toStringAsFixed(0);
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }

  List<BarChartRodStackItem> _buildShareStackItems(
    TimeCategoryShareBucket bucket,
    TimeCategoryShareTrend trend,
    ColorScheme cs,
  ) {
    var cursor = 0.0;
    final items = <BarChartRodStackItem>[];
    for (final key in trend.categoryKeys) {
      final share = ((bucket.shareByCategory[key] ?? 0) * 100).clamp(0, 100);
      if (share <= 0) continue;
      final next = (cursor + share).clamp(0, 100).toDouble();
      items.add(
        BarChartRodStackItem(cursor, next, _crossCategoryColor(key, cs)),
      );
      cursor = next;
    }
    return items;
  }

  String _crossCategoryLabel(String key) {
    if (key == ReportCrossAnalysis.otherCategoryKey) return '其他';
    final category = _timeEntryCategoryFromKey(key);
    return category?.label ?? key;
  }

  Color _crossCategoryColor(String key, ColorScheme cs) {
    if (key == ReportCrossAnalysis.otherCategoryKey) {
      return const Color(0xFF90A4AE);
    }
    final category = _timeEntryCategoryFromKey(key);
    return category == null ? cs.secondary : _auditColor(category, cs);
  }

  TimeEntryCategory? _timeEntryCategoryFromKey(String key) {
    for (final category in TimeEntryCategory.values) {
      if (category.name == key) return category;
    }
    return null;
  }

  Widget _buildAuditPie({
    required Map<TimeEntryCategory, int> secondsByCategory,
    required ColorScheme cs,
  }) {
    final values = secondsByCategory.entries
        .where((entry) => entry.value > 0)
        .toList();
    final total = values.fold<int>(0, (sum, entry) => sum + entry.value);
    if (total == 0) {
      return const EmptyHint(icon: Icons.schedule, message: '暂无时间足迹');
    }
    PieChartSectionData sec(int v, Color c) => PieChartSectionData(
      value: v.toDouble(),
      color: c,
      radius: 48,
      title: v == 0 ? '' : '${((v / total) * 100).toStringAsFixed(0)}%',
      titleStyle: const TextStyle(
        color: Colors.white,
        fontWeight: DesignTokens.fontWeightStrong,
        fontSize: 11,
      ),
    );
    final chart = PieChart(
      PieChartData(
        centerSpaceRadius: 32,
        sectionsSpace: 2,
        sections: [
          for (final entry in values)
            sec(entry.value, _auditColor(entry.key, cs)),
        ],
      ),
    );
    final legend = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in values.take(5))
          _legend(_auditColor(entry.key, cs), entry.key.label),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 320) {
          return Column(
            children: [
              SizedBox(height: 150, child: chart),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final entry in values.take(5))
                    _legend(_auditColor(entry.key, cs), entry.key.label),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: chart),
            SizedBox(width: 104, child: legend),
          ],
        );
      },
    );
  }

  Widget _legend(Color c, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 140),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildAuditTimeline(List<TimeEntry> entries, ColorScheme cs) {
    if (entries.isEmpty) {
      return const EmptyHint(icon: Icons.schedule, message: '暂无时间记录');
    }
    final sorted = [...entries]..sort((a, b) => b.startAt.compareTo(a.startAt));
    return Column(
      children: [
        for (final entry in sorted.take(6))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: _auditColor(
                entry.category,
                cs,
              ).withValues(alpha: 0.12),
              child: Icon(
                _auditIcon(entry.category),
                color: _auditColor(entry.category, cs),
                size: 16,
              ),
            ),
            title: Text(
              entry.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${entry.category.label} · ${_formatDateTime(entry.startAt)} · '
              '${_formatDuration(entry.durationSeconds)}',
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TimeAuditScreen()),
            ),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('查看全部'),
          ),
        ),
      ],
    );
  }

  Color _auditColor(TimeEntryCategory category, ColorScheme cs) =>
      switch (category) {
        TimeEntryCategory.focus => Colors.redAccent,
        TimeEntryCategory.todo => cs.primary,
        TimeEntryCategory.habit => const Color(0xFF66BB6A),
        TimeEntryCategory.goal => const Color(0xFFAB47BC),
        TimeEntryCategory.study => const Color(0xFF26A69A),
        TimeEntryCategory.work => const Color(0xFFFF9800),
        TimeEntryCategory.life => const Color(0xFF8D6E63),
        TimeEntryCategory.other => const Color(0xFF78909C),
      };

  IconData _auditIcon(TimeEntryCategory category) => switch (category) {
    TimeEntryCategory.focus => Icons.timer_outlined,
    TimeEntryCategory.todo => Icons.check_circle_outline,
    TimeEntryCategory.habit => Icons.repeat,
    TimeEntryCategory.goal => Icons.flag_outlined,
    TimeEntryCategory.study => Icons.menu_book_outlined,
    TimeEntryCategory.work => Icons.work_outline,
    TimeEntryCategory.life => Icons.favorite_outline,
    TimeEntryCategory.other => Icons.more_horiz,
  };

  String _formatDateTime(DateTime d) =>
      I18nDateFormat.shortDateTime(AppClock.toLocal(d));

  String _formatDuration(int seconds) {
    if (seconds >= 3600) {
      return '${(seconds / 3600).toStringAsFixed(seconds % 3600 == 0 ? 0 : 1)} 小时';
    }
    return '${(seconds / 60).toStringAsFixed(seconds % 60 == 0 ? 0 : 1)} 分钟';
  }

  Future<void> _copyReport(
    BuildContext context, {
    required DateTime start,
    required DateTime end,
    required List<TodoItem> completedTodos,
    required int focusMinutes,
    required int habitDoneInRange,
    required int auditTotalMinutes,
    required Map<TimeEntryCategory, int> auditCategorySeconds,
    required List<TimeEntry> auditEntries,
  }) async {
    final text = _buildReportMarkdown(
      start: start,
      end: end,
      completedTodos: completedTodos,
      focusMinutes: focusMinutes,
      habitDoneInRange: habitDoneInRange,
      auditTotalMinutes: auditTotalMinutes,
      auditCategorySeconds: auditCategorySeconds,
      auditEntries: auditEntries,
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('报告已复制，可粘贴到笔记、聊天或文档'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showReportShareCard(
    BuildContext context, {
    required DateTime start,
    required DateTime end,
    required List<TodoItem> completedTodos,
    required int focusMinutes,
    required int habitDoneInRange,
    required int auditTotalMinutes,
    required Map<TimeEntryCategory, int> auditCategorySeconds,
    required List<TimeEntry> auditEntries,
  }) async {
    final markdown = _buildReportMarkdown(
      start: start,
      end: end,
      completedTodos: completedTodos,
      focusMinutes: focusMinutes,
      habitDoneInRange: habitDoneInRange,
      auditTotalMinutes: auditTotalMinutes,
      auditCategorySeconds: auditCategorySeconds,
      auditEntries: auditEntries,
    );
    final topCategories =
        auditCategorySeconds.entries.where((entry) => entry.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    await showDialog<void>(
      context: context,
      builder: (_) => _ReportShareDialog(
        markdown: markdown,
        child: _ReportShareCard(
          range: '${_formatDate(start)} - ${_formatDate(end)}',
          completedTodos: completedTodos.length,
          focusMinutes: focusMinutes,
          habitDoneInRange: habitDoneInRange,
          auditTotalMinutes: auditTotalMinutes,
          topCategories: topCategories.take(4).toList(),
        ),
      ),
    );
  }

  Future<void> _copyDigest(
    BuildContext context,
    PeriodReportDigest digest,
  ) async {
    final text = _digestMarkdown(digest);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${digest.title}已复制'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _runDigestAiReview(
    BuildContext context,
    PeriodReportDigest digest,
  ) async {
    setState(() {
      _aiReportBusy = true;
      _aiReportError = null;
    });
    try {
      final review = await context.read<AiService>().personalizedReportReview(
        periodLabel: digest.title,
        reportMarkdown: _digestMarkdown(digest),
      );
      if (!mounted) return;
      setState(() => _aiReportReview = review);
    } on AiException catch (e) {
      if (mounted) setState(() => _aiReportError = e.message);
    } catch (e) {
      if (mounted) setState(() => _aiReportError = e.toString());
    } finally {
      if (mounted) setState(() => _aiReportBusy = false);
    }
  }

  String _digestMarkdown(PeriodReportDigest digest) {
    return digest.toMarkdown(
      formatDate: _formatDate,
      formatCategory: (category) =>
          category is TimeEntryCategory ? category.label : category.toString(),
    );
  }

  String _buildReportMarkdown({
    required DateTime start,
    required DateTime end,
    required List<TodoItem> completedTodos,
    required int focusMinutes,
    required int habitDoneInRange,
    required int auditTotalMinutes,
    required Map<TimeEntryCategory, int> auditCategorySeconds,
    required List<TimeEntry> auditEntries,
  }) {
    final categories =
        auditCategorySeconds.entries.where((entry) => entry.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final entries = [...auditEntries]
      ..sort((a, b) => b.startAt.compareTo(a.startAt));
    final sb = StringBuffer()
      ..writeln('# 多仪时光报告')
      ..writeln()
      ..writeln('范围：${_formatDate(start)} - ${_formatDate(end)}')
      ..writeln()
      ..writeln('## 概览')
      ..writeln('- 待办完成：${completedTodos.length} 项')
      ..writeln('- 深度专注：$focusMinutes 分钟')
      ..writeln('- 习惯打卡：$habitDoneInRange 次')
      ..writeln('- 时间足迹：$auditTotalMinutes 分钟')
      ..writeln();

    if (categories.isNotEmpty) {
      sb
        ..writeln('## 时间投入分布')
        ..writeln();
      for (final entry in categories) {
        sb.writeln('- ${entry.key.label}：${_formatDuration(entry.value)}');
      }
      sb.writeln();
    }

    if (entries.isNotEmpty) {
      sb
        ..writeln('## 最近时间记录')
        ..writeln();
      for (final entry in entries.take(8)) {
        sb.writeln(
          '- ${_formatDateTime(entry.startAt)} ${entry.title} · '
          '${entry.category.label} · ${_formatDuration(entry.durationSeconds)}',
        );
      }
      sb.writeln();
    }

    if (completedTodos.isNotEmpty) {
      sb
        ..writeln('## 已完成待办')
        ..writeln();
      for (final todo in completedTodos.take(12)) {
        sb.writeln('- [x] ${todo.title}');
      }
      sb.writeln();
    }

    return sb.toString();
  }

  String _formatDate(DateTime d) => I18nDateFormat.date(d);

  Widget _buildFocusSeries({
    required List<PomodoroSession> sessions,
    required _Range range,
    required DateTime start,
    required DateTime end,
    required ColorScheme cs,
  }) {
    final window = StatisticsWindow(
      StatisticsPeriod.values[range.index],
      today: end,
    );
    final spans = window.buckets;
    final buckets = <String, int>{
      for (var i = 0; i < spans.length; i++)
        _statisticsBucketLabel(window.period, spans[i], i): 0,
    };
    for (final session in sessions) {
      for (var i = 0; i < spans.length; i++) {
        if (spans[i].containsInstant(session.endTime)) {
          final label = _statisticsBucketLabel(window.period, spans[i], i);
          buckets[label] = buckets[label]! + session.durationSeconds;
          break;
        }
      }
    }
    buckets.updateAll((_, seconds) => seconds ~/ 60);

    if (buckets.values.every((v) => v == 0)) {
      return const EmptyHint(icon: Icons.timer_outlined, message: '暂无专注数据');
    }

    final entries = buckets.entries.toList();
    final maxV = buckets.values.isEmpty
        ? 1.0
        : (buckets.values.reduce((a, b) => a > b ? a : b)).toDouble();

    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        alignment: BarChartAlignment.spaceAround,
        maxY: (maxV * 1.2).clamp(10, double.infinity),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: const TextStyle(fontSize: 9),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= entries.length) return const SizedBox();
                if (entries.length > 10 && i % 2 != 0) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    entries[i].key,
                    style: const TextStyle(fontSize: 9),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (int i = 0; i < entries.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: entries[i].value.toDouble(),
                  color: cs.primary,
                  width: entries.length > 14 ? 5 : 9,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

String _statisticsBucketLabel(
  StatisticsPeriod period,
  StatisticsSpan span,
  int index,
) {
  return switch (period) {
    StatisticsPeriod.week => I18n.tr(
      'weekday.${const ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'][span.start.weekday - 1]}',
    ),
    StatisticsPeriod.month => I18n.tr(
      'statistics.bucket.week',
    ).replaceAll('{week}', '${index + 1}'),
    StatisticsPeriod.year => I18n.tr(
      'statistics.bucket.month',
    ).replaceAll('{month}', '${span.start.month}'),
  };
}

class _ReportShareDialog extends StatefulWidget {
  final String markdown;
  final Widget child;

  const _ReportShareDialog({required this.markdown, required this.child});

  @override
  State<_ReportShareDialog> createState() => _ReportShareDialogState();
}

class _ReportShareDialogState extends State<_ReportShareDialog> {
  final GlobalKey _cardKey = GlobalKey();
  _ReportPdfTemplate _pdfTemplate = _ReportPdfTemplate.visual;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: const Text('报告分享图'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RepaintBoundary(key: _cardKey, child: widget.child),
            const SizedBox(height: 14),
            const Text(
              'PDF 模板',
              style: TextStyle(
                fontSize: 12,
                fontWeight: DesignTokens.fontWeightStrong,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_ReportPdfTemplate>(
                segments: const [
                  ButtonSegment(
                    value: _ReportPdfTemplate.visual,
                    icon: Icon(Icons.image_outlined, size: 16),
                    label: Text('视觉版'),
                  ),
                  ButtonSegment(
                    value: _ReportPdfTemplate.archive,
                    icon: Icon(Icons.text_snippet_outlined, size: 16),
                    label: Text('归档版'),
                  ),
                  ButtonSegment(
                    value: _ReportPdfTemplate.briefing,
                    icon: Icon(Icons.dashboard_customize_outlined, size: 16),
                    label: Text('简报版'),
                  ),
                  ButtonSegment(
                    value: _ReportPdfTemplate.dashboard,
                    icon: Icon(Icons.space_dashboard_outlined, size: 16),
                    label: Text('仪表版'),
                  ),
                  ButtonSegment(
                    value: _ReportPdfTemplate.timeline,
                    icon: Icon(Icons.timeline_outlined, size: 16),
                    label: Text('时间线版'),
                  ),
                ],
                selected: {_pdfTemplate},
                onSelectionChanged: _saving
                    ? null
                    : (selected) {
                        setState(() => _pdfTemplate = selected.single);
                      },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        TextButton.icon(
          onPressed: _saving ? null : _copyMarkdown,
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('复制文案'),
        ),
        OutlinedButton.icon(
          onPressed: _saving ? null : _savePdf,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
          label: const Text('保存 PDF'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _savePng,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.image_outlined, size: 16),
          label: const Text('保存 PNG'),
        ),
      ],
    );
  }

  Future<void> _copyMarkdown() async {
    await Clipboard.setData(ClipboardData(text: widget.markdown));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('报告文案已复制'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _savePng() async {
    setState(() => _saving = true);
    try {
      final bytes = await _captureCardPngBytes();
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/duoyi_report_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      await Clipboard.setData(ClipboardData(text: file.path));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: widget.markdown,
          subject: '多仪时光报告',
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('分享图已保存并打开系统分享面板，路径已复制：${file.path}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _savePdf() async {
    setState(() => _saving = true);
    try {
      final imageBytes = _pdfTemplate == _ReportPdfTemplate.visual
          ? await _captureCardPngBytes()
          : null;
      if (_pdfTemplate == _ReportPdfTemplate.visual && imageBytes == null) {
        return;
      }
      final doc = await _buildPdfDocument(
        template: _pdfTemplate,
        imageBytes: imageBytes,
      );
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/duoyi_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await file.writeAsBytes(await doc.save(), flush: true);
      await Clipboard.setData(ClipboardData(text: file.path));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: widget.markdown,
          subject: '多仪时光报告 PDF',
        ),
      );
      if (!mounted) return;
      final templateLabel = _reportPdfTemplateLabel(_pdfTemplate);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$templateLabel PDF 报告已保存并打开系统分享面板，路径已复制：${file.path}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<pw.Document> _buildPdfDocument({
    required _ReportPdfTemplate template,
    Uint8List? imageBytes,
  }) async {
    final fontData = await rootBundle.load(
      'assets/fonts/DroidSansFallbackFull.ttf',
    );
    final cjkFont = pw.Font.ttf(fontData);
    final doc = pw.Document(
      title: '多仪时光报告',
      author: '多仪',
      creator: 'Duoyi',
      subject: '${_reportPdfTemplateLabel(template)} PDF',
      keywords: 'duoyi, productivity, report, markdown, searchable',
      theme: pw.ThemeData.withFont(
        base: cjkFont,
        bold: cjkFont,
        fontFallback: [cjkFont],
      ),
    );

    if (template == _ReportPdfTemplate.visual && imageBytes != null) {
      final image = pw.MemoryImage(imageBytes);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (_) =>
              pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 40),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '多仪 · ${_reportPdfTemplateLabel(template)} · ${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (_) => switch (template) {
          _ReportPdfTemplate.briefing => _buildBriefingPdfContent(),
          _ReportPdfTemplate.dashboard => _buildDashboardPdfContent(),
          _ReportPdfTemplate.timeline => _buildTimelinePdfContent(),
          _ => _buildSearchablePdfContent(template),
        },
      ),
    );
    return doc;
  }

  List<pw.Widget> _buildBriefingPdfContent() {
    final title = _markdownTitle();
    final range = _markdownLineStartsWith('范围：') ?? '范围：未指定';
    final overview = _markdownSectionItems('概览');
    final categories = _markdownSectionItems('时间投入分布').take(4).toList();
    final records = _markdownSectionItems('最近时间记录').take(5).toList();
    final todos = _markdownSectionItems('已完成待办').take(6).toList();

    return [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.fromLTRB(22, 20, 22, 20),
        decoration: pw.BoxDecoration(
          color: PdfColors.blueGrey900,
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '简报版',
              style: const pw.TextStyle(
                fontSize: 11,
                color: PdfColors.blueGrey100,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 27,
                fontWeight: pw.FontWeight.normal,
                color: PdfColors.white,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              range,
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.white),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 18),
      pw.Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in overview)
            pw.Container(
              width: 118,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Text(
                item,
                style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
              ),
            ),
        ],
      ),
      pw.SizedBox(height: 18),
      _buildBriefingSection('时间投入重点', categories),
      pw.SizedBox(height: 12),
      _buildBriefingSection('最近记录', records),
      pw.SizedBox(height: 12),
      _buildBriefingSection('完成事项', todos),
      pw.SizedBox(height: 18),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.amber50,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: PdfColors.amber200),
        ),
        child: pw.Text(
          '这份简报保留可检索文字层，适合快速复盘、转发和归档。',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800),
        ),
      ),
    ];
  }

  pw.Widget _buildBriefingSection(String title, List<String> items) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.normal),
        ),
        pw.SizedBox(height: 7),
        if (items.isEmpty)
          pw.Text(
            '暂无数据',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          )
        else
          for (final item in items)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('• ', style: const pw.TextStyle(fontSize: 10)),
                  pw.Expanded(
                    child: pw.Text(
                      item,
                      style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  List<pw.Widget> _buildDashboardPdfContent() {
    final title = _markdownTitle();
    final range = _markdownLineStartsWith('范围：') ?? '范围：未指定';
    final overview = _markdownSectionItems('概览');
    final categories = _markdownSectionItems('时间投入分布').take(5).toList();
    final records = _markdownSectionItems('最近时间记录').take(3).toList();
    final todos = _markdownSectionItems('已完成待办').take(4).toList();

    return [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
        decoration: pw.BoxDecoration(
          color: PdfColors.indigo900,
          borderRadius: pw.BorderRadius.circular(12),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '仪表版',
              style: const pw.TextStyle(
                fontSize: 11,
                color: PdfColors.indigo50,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 28,
                fontWeight: pw.FontWeight.normal,
                color: PdfColors.white,
              ),
            ),
            pw.SizedBox(height: 7),
            pw.Text(
              range,
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.white),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 18),
      pw.Text(
        '核心指标',
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.normal),
      ),
      pw.SizedBox(height: 8),
      pw.Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < overview.length; i++)
            _buildDashboardMetricCard(overview[i], i),
        ],
      ),
      pw.SizedBox(height: 18),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: _buildDashboardPanel(
              '时间投入排行',
              categories.isEmpty
                  ? [_buildPdfMutedText('暂无时间投入数据')]
                  : [
                      for (var i = 0; i < categories.length; i++)
                        _buildDashboardRankItem(categories[i], i),
                    ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: _buildDashboardPanel('近期推进', [
              ...records.map((item) => _buildPdfBullet(item)),
              if (records.isEmpty) _buildPdfMutedText('暂无最近时间记录'),
              pw.SizedBox(height: 8),
              pw.Text(
                '完成事项',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.normal,
                ),
              ),
              pw.SizedBox(height: 4),
              ...todos.map((item) => _buildPdfBullet(item)),
              if (todos.isEmpty) _buildPdfMutedText('暂无完成待办'),
            ]),
          ),
        ],
      ),
      pw.SizedBox(height: 16),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.indigo50,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: PdfColors.indigo100),
        ),
        child: pw.Text(
          '仪表版适合复盘关键指标和投入结构，保留可检索中文文字层。',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.indigo900),
        ),
      ),
    ];
  }

  pw.Widget _buildDashboardMetricCard(String item, int index) {
    final parts = item.split('：');
    final title = parts.first.trim();
    final value = parts.length > 1 ? parts.sublist(1).join('：').trim() : item;
    final colors = [
      PdfColors.indigo50,
      PdfColors.green50,
      PdfColors.amber50,
      PdfColors.pink50,
      PdfColors.cyan50,
    ];
    final borders = [
      PdfColors.indigo200,
      PdfColors.green200,
      PdfColors.amber200,
      PdfColors.pink200,
      PdfColors.cyan200,
    ];
    return pw.Container(
      width: 102,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: colors[index % colors.length],
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: borders[index % borders.length]),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.normal),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildDashboardPanel(String title, List<pw.Widget> children) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(13),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.normal),
          ),
          pw.SizedBox(height: 9),
          ...children,
        ],
      ),
    );
  }

  pw.Widget _buildDashboardRankItem(String item, int index) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 20,
            height: 20,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: PdfColors.indigo900,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Text(
              '${index + 1}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.white),
            ),
          ),
          pw.SizedBox(width: 7),
          pw.Expanded(
            child: pw.Text(
              item,
              style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
            ),
          ),
        ],
      ),
    );
  }

  List<pw.Widget> _buildTimelinePdfContent() {
    final title = _markdownTitle();
    final range = _markdownLineStartsWith('范围：') ?? '范围：未指定';
    final overview = _markdownSectionItems('概览');
    final records = _markdownSectionItems('最近时间记录').take(8).toList();
    final todos = _markdownSectionItems('已完成待办').take(10).toList();
    final categories = _markdownSectionItems('时间投入分布').take(4).toList();

    return [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(width: 5, height: 58, color: PdfColors.teal700),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '时间线版',
                  style: const pw.TextStyle(
                    fontSize: 11,
                    color: PdfColors.teal700,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 27,
                    fontWeight: pw.FontWeight.normal,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(range, style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 16),
      pw.Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final item in overview)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 9,
                vertical: 6,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.teal50,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: PdfColors.teal100),
              ),
              child: pw.Text(item, style: const pw.TextStyle(fontSize: 9)),
            ),
        ],
      ),
      pw.SizedBox(height: 18),
      pw.Text(
        '最近时间记录',
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.normal),
      ),
      pw.SizedBox(height: 9),
      if (records.isEmpty)
        _buildPdfMutedText('暂无最近时间记录')
      else
        for (final item in records) _buildTimelineItem(item),
      pw.SizedBox(height: 14),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: _buildTimelineSideSection('完成事项', todos)),
          pw.SizedBox(width: 12),
          pw.Expanded(child: _buildTimelineSideSection('时间投入', categories)),
        ],
      ),
      pw.SizedBox(height: 16),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.teal50,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(color: PdfColors.teal100),
        ),
        child: pw.Text(
          '时间线版适合按行动顺序复盘过程，兼顾记录流、完成事项和投入结构。',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.teal900),
        ),
      ),
    ];
  }

  pw.Widget _buildTimelineItem(String item) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            children: [
              pw.Container(
                width: 11,
                height: 11,
                decoration: pw.BoxDecoration(
                  color: PdfColors.teal700,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
              ),
              pw.Container(width: 1, height: 26, color: PdfColors.teal100),
            ],
          ),
          pw.SizedBox(width: 9),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(9),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Text(
                item,
                style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTimelineSideSection(String title, List<String> items) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(11),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.normal),
          ),
          pw.SizedBox(height: 7),
          if (items.isEmpty)
            _buildPdfMutedText('暂无数据')
          else
            ...items.map((item) => _buildPdfBullet(item)),
        ],
      ),
    );
  }

  pw.Widget _buildPdfBullet(String item) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('• ', style: const pw.TextStyle(fontSize: 10)),
          pw.Expanded(
            child: pw.Text(
              item,
              style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfMutedText(String text) {
    return pw.Text(
      text,
      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
    );
  }

  List<pw.Widget> _buildSearchablePdfContent(_ReportPdfTemplate template) {
    final lines = widget.markdown.split('\n');
    final widgets = <pw.Widget>[
      pw.Text(
        template == _ReportPdfTemplate.visual ? '可检索文字层' : '多仪时光报告',
        style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.normal),
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        '模板：${_reportPdfTemplateLabel(template)}',
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 14),
    ];
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        widgets.add(pw.SizedBox(height: 6));
      } else if (line.startsWith('# ')) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4, bottom: 8),
            child: pw.Text(
              line.substring(2),
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.normal,
              ),
            ),
          ),
        );
      } else if (line.startsWith('## ')) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
            child: pw.Text(
              line.substring(3),
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.normal,
              ),
            ),
          ),
        );
      } else if (line.startsWith('- ')) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('• ', style: const pw.TextStyle(fontSize: 11)),
                pw.Expanded(
                  child: pw.Text(
                    line.substring(2),
                    style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(
              line,
              style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  String _markdownTitle() {
    for (final raw in widget.markdown.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('# ')) return line.substring(2).trim();
    }
    return '多仪时光报告';
  }

  String? _markdownLineStartsWith(String prefix) {
    for (final raw in widget.markdown.split('\n')) {
      final line = raw.trim();
      if (line.startsWith(prefix)) return line;
    }
    return null;
  }

  List<String> _markdownSectionItems(String heading) {
    final result = <String>[];
    var inSection = false;
    for (final raw in widget.markdown.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('## ')) {
        inSection = line.substring(3).trim() == heading;
        continue;
      }
      if (!inSection) continue;
      if (line.startsWith('- [x] ')) {
        result.add(line.substring(6).trim());
      } else if (line.startsWith('- ')) {
        result.add(line.substring(2).trim());
      }
    }
    return result;
  }

  String _reportPdfTemplateLabel(_ReportPdfTemplate template) =>
      switch (template) {
        _ReportPdfTemplate.visual => '视觉版',
        _ReportPdfTemplate.archive => '归档版',
        _ReportPdfTemplate.briefing => '简报版',
        _ReportPdfTemplate.dashboard => '仪表版',
        _ReportPdfTemplate.timeline => '时间线版',
      };

  Future<Uint8List?> _captureCardPngBytes() async {
    final boundary =
        _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }
}

class _ReportShareCard extends StatelessWidget {
  final String range;
  final int completedTodos;
  final int focusMinutes;
  final int habitDoneInRange;
  final int auditTotalMinutes;
  final List<MapEntry<TimeEntryCategory, int>> topCategories;

  const _ReportShareCard({
    required this.range,
    required this.completedTodos,
    required this.focusMinutes,
    required this.habitDoneInRange,
    required this.auditTotalMinutes,
    required this.topCategories,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 360,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.16),
          width: 0.45,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '多仪时光报告',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: DesignTokens.fontWeightStrong,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            range,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.58),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ShareMetric(label: '待办', value: '$completedTodos 项'),
              _ShareMetric(label: '专注', value: '$focusMinutes 分'),
              _ShareMetric(label: '习惯', value: '$habitDoneInRange 次'),
              _ShareMetric(label: '足迹', value: '$auditTotalMinutes 分'),
            ],
          ),
          if (topCategories.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              '时间投入',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(height: 8),
            for (final entry in topCategories)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(_formatShareDuration(entry.value)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 14),
          Text(
            '由多仪生成',
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.44),
            ),
          ),
        ],
      ),
    );
  }

  String _formatShareDuration(int seconds) {
    if (seconds >= 3600) {
      return '${(seconds / 3600).toStringAsFixed(seconds % 3600 == 0 ? 0 : 1)} 小时';
    }
    return '${(seconds / 60).toStringAsFixed(seconds % 60 == 0 ? 0 : 1)} 分钟';
  }
}

class _ShareMetric extends StatelessWidget {
  final String label;
  final String value;

  const _ShareMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: DesignTokens.fontWeightStrong,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurface.withValues(alpha: 0.56),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuadrantStat {
  final String label;
  final String action;
  final String guidance;
  final Color color;
  final IconData icon;
  final int totalCount;
  final int activeCount;
  final int completedCount;
  final int overdueCount;
  final int dueTodayCount;

  const _QuadrantStat({
    required this.label,
    required this.action,
    required this.guidance,
    required this.color,
    required this.icon,
    required this.totalCount,
    required this.activeCount,
    required this.completedCount,
    required this.overdueCount,
    required this.dueTodayCount,
  });

  double shareOf(int total) => total == 0 ? 0 : totalCount / total;
}

class _QuadrantDistributionCard extends StatelessWidget {
  final List<_QuadrantStat> stats;
  final ColorScheme cs;

  const _QuadrantDistributionCard({required this.stats, required this.cs});

  @override
  Widget build(BuildContext context) {
    final total = stats.fold<int>(0, (sum, stat) => sum + stat.totalCount);
    final activeTotal = stats.fold<int>(
      0,
      (sum, stat) => sum + stat.activeCount,
    );
    final overdueTotal = stats.fold<int>(
      0,
      (sum, stat) => sum + stat.overdueCount,
    );
    final dueTodayTotal = stats.fold<int>(
      0,
      (sum, stat) => sum + stat.dueTodayCount,
    );

    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '四象限执行分布',
                  style: TextStyle(
                    fontWeight: DesignTokens.fontWeightStrong,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                '当前待办池',
                style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.56),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '按重要/紧急象限拆解未完成压力、今日到期和已完成沉淀。',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            I18n.tr('statistics.snapshot'),
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuadrantMetric(label: '任务总数', value: '$total', cs: cs),
              _QuadrantMetric(label: '未完成', value: '$activeTotal', cs: cs),
              _QuadrantMetric(label: '逾期', value: '$overdueTotal', cs: cs),
              _QuadrantMetric(label: '今日到期', value: '$dueTodayTotal', cs: cs),
            ],
          ),
          const SizedBox(height: 12),
          if (total == 0)
            Text(
              '当前没有可统计的待办。新增任务并设置象限后，这里会显示优先级结构。',
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.58)),
            )
          else
            Column(
              children: [
                for (final stat in stats)
                  _QuadrantDistributionRow(stat: stat, total: total, cs: cs),
              ],
            ),
        ],
      ),
    );
  }
}

class _QuadrantMetric extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;

  const _QuadrantMetric({
    required this.label,
    required this.value,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.58),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontWeight: DesignTokens.fontWeightStrong,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuadrantDistributionRow extends StatelessWidget {
  final _QuadrantStat stat;
  final int total;
  final ColorScheme cs;

  const _QuadrantDistributionRow({
    required this.stat,
    required this.total,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = stat.shareOf(total).clamp(0.0, 1.0);
    final percent = (ratio * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: stat.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(stat.icon, color: stat.color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${stat.label} · ${stat.action}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: DesignTokens.fontWeightStrong,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      '$percent%',
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.62),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Stack(
                  children: [
                    Container(
                      height: 7,
                      decoration: BoxDecoration(
                        color: stat.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: ratio,
                      child: Container(
                        height: 7,
                        decoration: BoxDecoration(
                          color: stat.color,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${stat.guidance} 未完成 ${stat.activeCount} 项，逾期 ${stat.overdueCount} 项，今日到期 ${stat.dueTodayCount} 项，完成 ${stat.completedCount} 项。',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.62),
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 34,
            child: Text(
              '${stat.totalCount}',
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontWeight: DesignTokens.fontWeightStrong,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  const _Kpi({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(10),
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodReportDigestCard extends StatelessWidget {
  final PeriodReportDigest digest;
  final ColorScheme cs;
  final VoidCallback onCopy;
  final bool aiEnabled;
  final bool aiBusy;
  final String? aiReview;
  final String? aiError;
  final VoidCallback onAiReview;
  final VoidCallback onOpenAiHistory;
  final VoidCallback onShareImage;

  const _PeriodReportDigestCard({
    required this.digest,
    required this.cs,
    required this.onCopy,
    required this.aiEnabled,
    required this.aiBusy,
    required this.aiReview,
    required this.aiError,
    required this.onAiReview,
    required this.onOpenAiHistory,
    required this.onShareImage,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.summarize_outlined, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      digest.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: DesignTokens.fontWeightStrong,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      digest.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _ScoreBadge(score: digest.report.productivityScore, cs: cs),
            ],
          ),
          const SizedBox(height: 12),
          for (final line in digest.highlights.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(child: Text(line)),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('复制报告'),
              ),
              TextButton.icon(
                onPressed: aiEnabled && !aiBusy ? onAiReview : null,
                icon: aiBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 16),
                label: const Text('AI 解读'),
              ),
              TextButton.icon(
                onPressed: onShareImage,
                icon: const Icon(Icons.image_outlined, size: 16),
                label: const Text('分享图'),
              ),
              if (aiReview != null)
                TextButton.icon(
                  onPressed: onOpenAiHistory,
                  icon: const Icon(Icons.history, size: 16),
                  label: const Text('AI 历史'),
                ),
            ],
          ),
          if (!aiEnabled) ...[
            const SizedBox(height: 4),
            Text(
              '管理员启用 AI 后可生成云端个性化解读',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          if (aiError != null) ...[
            const SizedBox(height: 8),
            Text(
              aiError!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ],
          if (aiReview != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 16, color: cs.primary),
                      const SizedBox(width: 6),
                      Text(
                        '云端个性化解读',
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: cs.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    aiReview!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(height: 1.58),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  final int score;
  final ColorScheme cs;

  const _ScoreBadge({required this.score, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: cs.primary.withValues(alpha: 0.32)),
        color: cs.primary.withValues(alpha: 0.08),
      ),
      child: Text(
        '$score',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: cs.primary,
          fontWeight: DesignTokens.fontWeightStrong,
        ),
      ),
    );
  }
}

class _CrossMetricBadge extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;

  const _CrossMetricBadge({
    required this.label,
    required this.value,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontSize: 11,
          fontWeight: DesignTokens.fontWeightStrong,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _ProjectEfficiencyRow extends StatelessWidget {
  final ProjectEfficiencyItem item;
  final double maxOutputPerHour;
  final ColorScheme cs;

  const _ProjectEfficiencyRow({
    required this.item,
    required this.maxOutputPerHour,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = maxOutputPerHour <= 0
        ? 0.0
        : (item.outputPerHour / maxOutputPerHour).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.projectLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${item.outputPerHour.toStringAsFixed(1)} 项/时',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.primary,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '输出 ${item.outputCount} 项 · 待办 ${item.completedTodos} · 目标 ${item.completedGoalSteps} · ${item.timeMinutes} 分',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: cs.surfaceContainerHighest.withValues(
                alpha: 0.64,
              ),
              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductivityTrendPoint {
  final String label;
  final DateTime start;
  final DateTime end;
  final PeriodReport report;

  const _ProductivityTrendPoint({
    required this.label,
    required this.start,
    required this.end,
    required this.report,
  });

  int get score => report.productivityScore;
  int get completedTodos => report.todosCompleted;
  int get focusMinutes => report.focusMinutes;
  int get habitCheckIns => report.habitCheckIns;
  int get timeEntryMinutes => report.timeEntryMinutes;

  String get dateRangeLabel {
    final startText = '${start.month}/${start.day}';
    final endText = '${end.month}/${end.day}';
    if (start.year == end.year) return '$startText-$endText';
    return '${start.year}/$startText-${end.year}/$endText';
  }
}

class _ProductivityTrendCard extends StatelessWidget {
  final List<_ProductivityTrendPoint> points;
  final _Range range;

  const _ProductivityTrendCard({required this.points, required this.range});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final latest = points.isEmpty ? null : points.last;
    final first = points.isEmpty ? null : points.first;
    final best = _bestPoint;
    final averageScore = _averageScore;
    final delta = latest == null || first == null
        ? 0
        : latest.score - first.score;
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '效率趋势',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: DesignTokens.fontWeightStrong,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _trendSubtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.58),
                      ),
                    ),
                  ],
                ),
              ),
              if (latest != null)
                _TrendSummaryBadge(score: latest.score, delta: delta),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '查看趋势详情',
                icon: const Icon(Icons.open_in_new, size: 18),
                onPressed: points.isEmpty
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _ProductivityTrendDetailScreen(
                            points: points,
                            range: range,
                          ),
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: points.isEmpty
                ? const EmptyHint(icon: Icons.trending_up, message: '暂无趋势数据')
                : _buildChart(context, cs),
          ),
          if (latest != null && best != null) ...[
            const SizedBox(height: 12),
            Text(
              '趋势洞察',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.72),
                fontWeight: DesignTokens.fontWeightStrong,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _insightText,
              style: TextStyle(
                fontSize: 11,
                height: 1.45,
                color: cs.onSurface.withValues(alpha: 0.64),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TrendHistoryMetric(
                  label: I18n.tr('statistics.trend.best'),
                  value: '${best.label} · ${best.score} 分',
                ),
                _TrendHistoryMetric(
                  label: I18n.tr('statistics.trend.average'),
                  value: '$averageScore 分',
                ),
                _TrendHistoryMetric(label: '当前排名', value: _rankText),
              ],
            ),
            if (range != _Range.week) ...[
              const SizedBox(height: 8),
              Text(
                I18n.tr('statistics.trend.partial'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildChart(BuildContext context, ColorScheme cs) {
    final spots = [
      for (int i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].score.toDouble()),
    ];
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) => FlLine(
            color: cs.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 25,
              reservedSize: 32,
              getTitlesWidget: (value, _) => Text(
                value.toInt().toString(),
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onSurface.withValues(alpha: 0.56),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, _) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) {
                  return const SizedBox();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    points[index].label,
                    style: TextStyle(
                      fontSize: 9,
                      color: cs.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            getTooltipItems: (items) => [
              for (final item in items)
                LineTooltipItem(
                  '${points[item.x.toInt()].label}\n${item.y.toInt()} 分',
                  TextStyle(
                    color: cs.onInverseSurface,
                    fontSize: 11,
                    fontFamily: DesignTokens.fontFamilyRounded,
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: cs.primary,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(
                    radius: 3,
                    color: cs.primary,
                    strokeWidth: 2,
                    strokeColor: cs.surface,
                  ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: cs.primary.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }

  String get _trendSubtitle => I18n.tr('statistics.trend.${range.name}');

  _ProductivityTrendPoint? get _bestPoint {
    if (points.isEmpty) return null;
    var best = points.first;
    for (final point in points.skip(1)) {
      if (point.score > best.score) best = point;
    }
    return best;
  }

  int get _averageScore {
    if (points.isEmpty) return 0;
    final total = points.fold<int>(0, (sum, point) => sum + point.score);
    return (total / points.length).round();
  }

  String get _rankText {
    if (points.isEmpty) return '暂无';
    final latest = points.last;
    final higherCount = points
        .where((point) => point.score > latest.score)
        .length;
    return '第 ${higherCount + 1}/${points.length}';
  }

  String get _insightText {
    if (points.length < 2) return '趋势样本不足，继续记录后会生成更稳定的解读。';
    final latest = points.last;
    final previous = points[points.length - 2];
    final best = _bestPoint;
    final delta = latest.score - previous.score;
    final average = _averageScore;
    final direction = delta > 0
        ? '提升了 $delta 分'
        : delta < 0
        ? '回落了 ${delta.abs()} 分'
        : '保持稳定';
    final bestText = best == null
        ? ''
        : '${I18n.tr('statistics.trend.best')}：${best.label}，${best.score} 分。';
    final averageText = latest.score >= average
        ? '当前高于最近平均 $average 分。'
        : '当前低于最近平均 $average 分。';
    return '较上一周期$direction，$bestText$averageText';
  }
}

class _ProductivityTrendDetailScreen extends StatelessWidget {
  final List<_ProductivityTrendPoint> points;
  final _Range range;

  const _ProductivityTrendDetailScreen({
    required this.points,
    required this.range,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final latest = points.isEmpty ? null : points.last;
    final best = _bestPoint;
    return Scaffold(
      appBar: AppBar(
        title: const Text('趋势详情'),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          AppSurfaceCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            borderRadius: BorderRadius.circular(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.insights_outlined, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '趋势概览',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: DesignTokens.fontWeightStrong,
                            ),
                          ),
                          Text(
                            _rangeSubtitle,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withValues(alpha: 0.58),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (latest != null)
                      _TrendSummaryBadge(
                        score: latest.score,
                        delta: points.length < 2
                            ? 0
                            : latest.score - points.first.score,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _insightText,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _TrendHistoryMetric(
                      label: I18n.tr('statistics.trend.best'),
                      value: best == null
                          ? '暂无'
                          : '${best.label} · ${best.score} 分',
                    ),
                    _TrendHistoryMetric(
                      label: I18n.tr('statistics.trend.average'),
                      value: '$_averageScore 分',
                    ),
                    _TrendHistoryMetric(label: '当前排名', value: _rankText),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '逐周期明细',
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.72),
              fontWeight: DesignTokens.fontWeightStrong,
            ),
          ),
          const SizedBox(height: 8),
          for (final point in points.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TrendDetailTile(
                point: point,
                previous: _previousPoint(point),
                isLatest: point == latest,
                isBest: point == best,
              ),
            ),
        ],
      ),
    );
  }

  String get _rangeSubtitle => I18n.tr('statistics.trend.${range.name}');

  _ProductivityTrendPoint? get _bestPoint {
    if (points.isEmpty) return null;
    var best = points.first;
    for (final point in points.skip(1)) {
      if (point.score > best.score) best = point;
    }
    return best;
  }

  int get _averageScore {
    if (points.isEmpty) return 0;
    final total = points.fold<int>(0, (sum, point) => sum + point.score);
    return (total / points.length).round();
  }

  String get _rankText {
    if (points.isEmpty) return '暂无';
    final latest = points.last;
    final higherCount = points
        .where((point) => point.score > latest.score)
        .length;
    return '第 ${higherCount + 1}/${points.length}';
  }

  String get _insightText {
    if (points.length < 2) return '趋势样本不足，继续记录后会生成更稳定的解读。';
    final latest = points.last;
    final previous = points[points.length - 2];
    final best = _bestPoint;
    final delta = latest.score - previous.score;
    final average = _averageScore;
    final direction = delta > 0
        ? '提升了 $delta 分'
        : delta < 0
        ? '回落了 ${delta.abs()} 分'
        : '保持稳定';
    final bestText = best == null
        ? ''
        : '${I18n.tr('statistics.trend.best')}：${best.label}，${best.score} 分。';
    final averageText = latest.score >= average
        ? '当前高于最近平均 $average 分。'
        : '当前低于最近平均 $average 分。';
    return '较上一周期$direction，$bestText$averageText';
  }

  _ProductivityTrendPoint? _previousPoint(_ProductivityTrendPoint point) {
    final index = points.indexOf(point);
    if (index <= 0) return null;
    return points[index - 1];
  }
}

class _TrendDetailTile extends StatelessWidget {
  final _ProductivityTrendPoint point;
  final _ProductivityTrendPoint? previous;
  final bool isLatest;
  final bool isBest;

  const _TrendDetailTile({
    required this.point,
    required this.previous,
    required this.isLatest,
    required this.isBest,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final delta = previous == null ? null : point.score - previous!.score;
    final deltaColor = delta == null
        ? cs.onSurface.withValues(alpha: 0.56)
        : delta > 0
        ? const Color(0xFF2E7D32)
        : delta < 0
        ? const Color(0xFFC62828)
        : cs.onSurface.withValues(alpha: 0.62);
    final deltaText = delta == null
        ? '基准'
        : delta == 0
        ? '持平'
        : '${delta > 0 ? '+' : ''}$delta';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isLatest
            ? cs.primary.withValues(alpha: 0.08)
            : cs.surfaceContainerHighest.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isBest
              ? Colors.amber.withValues(alpha: 0.46)
              : cs.outlineVariant.withValues(alpha: 0.38),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${point.label} · ${point.dateRangeLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
              ),
              if (isBest)
                const AppStatusBadge(label: '最佳', color: Colors.amber)
              else if (isLatest)
                AppStatusBadge(label: '当前', color: cs.primary),
              const SizedBox(width: 8),
              Text(
                '${point.score} 分',
                style: TextStyle(
                  fontSize: 12,
                  color: isLatest ? cs.primary : cs.onSurface,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                deltaText,
                style: TextStyle(fontSize: 11, color: deltaColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TrendDetailMetric(
                label: '待办',
                value: '${point.completedTodos} 项',
              ),
              _TrendDetailMetric(label: '专注', value: '${point.focusMinutes} 分'),
              _TrendDetailMetric(
                label: '习惯',
                value: '${point.habitCheckIns} 次',
              ),
              _TrendDetailMetric(
                label: '足迹',
                value: '${point.timeEntryMinutes} 分',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendDetailMetric extends StatelessWidget {
  final String label;
  final String value;

  const _TrendDetailMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurface.withValues(alpha: 0.56),
            ),
          ),
          const SizedBox(width: 4),
          Text(value, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class _TrendSummaryBadge extends StatelessWidget {
  final int score;
  final int delta;

  const _TrendSummaryBadge({required this.score, required this.delta});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = delta > 0
        ? const Color(0xFF2E7D32)
        : delta < 0
        ? const Color(0xFFC62828)
        : cs.onSurface.withValues(alpha: 0.62);
    final label = delta == 0 ? '持平' : '${delta > 0 ? '+' : ''}$delta';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$score 分',
            style: TextStyle(
              fontSize: 12,
              fontWeight: DesignTokens.fontWeightStrong,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

class _TrendHistoryMetric extends StatelessWidget {
  final String label;
  final String value;

  const _TrendHistoryMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurface.withValues(alpha: 0.56),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: DesignTokens.fontWeightStrong,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductivityComparisonCard extends StatelessWidget {
  final ReportComparison comparison;
  final _Range range;
  final ColorScheme cs;

  const _ProductivityComparisonCard({
    required this.comparison,
    required this.range,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final score = comparison.productivityScore;
    final trendColor = _trendColor(score.direction);
    final trendIcon = _trendIcon(score.direction);
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '效率对比',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: DesignTokens.fontWeightStrong,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _rangeCompareLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.58),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: trendColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(trendIcon, size: 16, color: trendColor),
                    const SizedBox(width: 4),
                    Text(
                      _signedNumber(score.difference, suffix: ' 分'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: DesignTokens.fontWeightStrong,
                        color: trendColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary.withValues(alpha: 0.1),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.28)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      comparison.current.productivityScore.toString(),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: DesignTokens.fontWeightStrong,
                        color: cs.primary,
                      ),
                    ),
                    Text(
                      '效率分',
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ComparisonMetric(
                      label: '完成率',
                      value: _percent(comparison.current.todoCompletionRate),
                      delta: _percentagePointDelta(
                        comparison.todoCompletionRate,
                      ),
                      direction: comparison.todoCompletionRate.direction,
                    ),
                    _ComparisonMetric(
                      label: '专注',
                      value: '${comparison.current.focusMinutes} 分',
                      delta: _signedNumber(
                        comparison.focusMinutes.difference,
                        suffix: ' 分',
                      ),
                      direction: comparison.focusMinutes.direction,
                    ),
                    _ComparisonMetric(
                      label: '习惯',
                      value: '${comparison.current.habitCheckIns} 次',
                      delta: _signedNumber(
                        comparison.habitCheckIns.difference,
                        suffix: ' 次',
                      ),
                      direction: comparison.habitCheckIns.direction,
                    ),
                    _ComparisonMetric(
                      label: '足迹',
                      value: '${comparison.current.timeEntryMinutes} 分',
                      delta: _signedNumber(
                        comparison.timeEntryMinutes.difference,
                        suffix: ' 分',
                      ),
                      direction: comparison.timeEntryMinutes.direction,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (score.hasBaseline) ...[
            const SizedBox(height: 10),
            Text(
              '较上期 ${_signedPercent(score.percentChangeRounded ?? 0)}',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String get _rangeCompareLabel => switch (range) {
    _Range.week => '与上周同段对比',
    _Range.month => '与上一同长度周期对比',
    _Range.year => '与上一同长度周期对比',
  };

  Color _trendColor(ReportTrendDirection direction) => switch (direction) {
    ReportTrendDirection.up => const Color(0xFF2E7D32),
    ReportTrendDirection.down => const Color(0xFFC62828),
    ReportTrendDirection.flat => cs.onSurface.withValues(alpha: 0.62),
  };

  IconData _trendIcon(ReportTrendDirection direction) => switch (direction) {
    ReportTrendDirection.up => Icons.trending_up,
    ReportTrendDirection.down => Icons.trending_down,
    ReportTrendDirection.flat => Icons.trending_flat,
  };

  String _percent(double value) => '${(value * 100).round()}%';

  String _percentagePointDelta(ReportMetricDelta delta) {
    final points = (delta.difference * 100).round();
    return _signedInt(points, suffix: ' 个点');
  }

  String _signedNumber(double value, {required String suffix}) {
    if (value == 0) return '持平';
    return _signedInt(value.round(), suffix: suffix);
  }

  String _signedPercent(int value) => _signedInt(value, suffix: '%');

  String _signedInt(int value, {required String suffix}) {
    if (value == 0) return '持平';
    return '${value > 0 ? '+' : ''}$value$suffix';
  }
}

class _ComparisonMetric extends StatelessWidget {
  final String label;
  final String value;
  final String delta;
  final ReportTrendDirection direction;

  const _ComparisonMetric({
    required this.label,
    required this.value,
    required this.delta,
    required this.direction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (direction) {
      ReportTrendDirection.up => const Color(0xFF2E7D32),
      ReportTrendDirection.down => const Color(0xFFC62828),
      ReportTrendDirection.flat => cs.onSurface.withValues(alpha: 0.58),
    };
    return SizedBox(
      width: 96,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.46),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: DesignTokens.fontWeightStrong,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.56),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              delta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Selected-period Time Overview card
// ---------------------------------------------------------------------------

class _PeriodTimeOverview extends StatelessWidget {
  final int totalSeconds;
  final Map<String, int> sourceSeconds;
  final Map<String, int> daySeconds;
  final StatisticsWindow window;
  final ColorScheme cs;

  const _PeriodTimeOverview({
    super.key,
    required this.totalSeconds,
    required this.sourceSeconds,
    required this.daySeconds,
    required this.window,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            I18n.tr('statistics.time.${window.period.name}'),
            style: const TextStyle(
              fontWeight: DesignTokens.fontWeightStrong,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          // Headline total
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.access_time_filled_outlined,
                  color: cs.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDuration(totalSeconds),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: DesignTokens.fontWeightStrong,
                      ),
                    ),
                    Text(
                      I18n.tr('statistics.total.${window.period.name}'),
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (totalSeconds > 0) ...[
            SizedBox(height: 160, child: _buildSourcePie(context)),
            const SizedBox(height: 10),
            SizedBox(height: 140, child: _buildPeriodBars(context)),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: EmptyHint(
                icon: Icons.date_range,
                message: I18n.tr('statistics.time.empty'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSourcePie(BuildContext context) {
    final nonZero = sourceSeconds.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (nonZero.isEmpty) {
      return const EmptyHint(icon: Icons.inbox_outlined, message: '暂无数据');
    }
    final total = nonZero.fold<int>(0, (s, e) => s + e.value);

    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 28,
              sectionsSpace: 2,
              sections: [
                for (final entry in nonZero)
                  PieChartSectionData(
                    value: entry.value.toDouble(),
                    color: _sourceColor(entry.key),
                    radius: 40,
                    title: total == 0
                        ? ''
                        : '${((entry.value / total) * 100).toStringAsFixed(0)}%',
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: DesignTokens.fontWeightStrong,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 100,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in nonZero.take(5))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _sourceColor(entry.key),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          entry.key,
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodBars(BuildContext context) {
    final spans = window.buckets;
    final buckets = <String, int>{};
    for (var index = 0; index < spans.length; index++) {
      final span = spans[index];
      var seconds = 0;
      for (
        var date = span.start;
        !date.isAfter(span.end);
        date = date.add(const Duration(days: 1))
      ) {
        final key =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        seconds += daySeconds[key] ?? 0;
      }
      buckets[_statisticsBucketLabel(window.period, span, index)] = seconds;
    }

    final maxV = buckets.values.fold<int>(0, (a, b) => a > b ? a : b);
    if (maxV == 0) {
      return EmptyHint(
        icon: Icons.date_range,
        message: I18n.tr('statistics.time.empty'),
      );
    }

    final entries = buckets.entries.toList();
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        alignment: BarChartAlignment.spaceAround,
        maxY: (maxV / 60 * 1.2).clamp(1, double.infinity),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: const TextStyle(fontSize: 9),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= entries.length) return const SizedBox();
                if (entries.length > 8 && i.isOdd && i != entries.length - 1) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    entries[i].key,
                    style: const TextStyle(fontSize: 9),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (int i = 0; i < entries.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: entries[i].value / 60,
                  color: cs.primary,
                  width: 12,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _formatDuration(int seconds) {
    if (seconds >= 3600) {
      final h = seconds / 3600;
      return '${h.toStringAsFixed(seconds % 3600 == 0 ? 0 : 1)} 小时';
    }
    final m = seconds / 60;
    return '${m.toStringAsFixed(seconds % 60 == 0 ? 0 : 1)} 分钟';
  }

  static Color _sourceColor(String label) => switch (label) {
    '番茄钟' => Colors.redAccent,
    '待办' => const Color(0xFF42A5F5),
    '习惯' => const Color(0xFF66BB6A),
    '目标' => const Color(0xFFAB47BC),
    '手动' => const Color(0xFF78909C),
    _ => const Color(0xFF78909C),
  };
}
