import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_clock.dart';
import '../models/pomodoro.dart';
import '../core/completion_visibility_policy.dart';
import '../core/design_tokens.dart';
import '../core/desktop_tokens.dart';
import '../core/goal_icons.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/lunar_calendar.dart';
import '../core/quotes.dart';
import '../core/report_engine.dart';
import '../core/smart_schedule_advisor.dart';
import '../core/todo_templates.dart';
import '../models/course_schedule.dart' show CourseItem, ScheduleSettings;
import '../models/todo.dart';
import '../providers/anniversary_provider.dart';
import '../providers/course_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/share_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/time_audit_provider.dart';
import '../providers/todo_provider.dart';
import '../providers/user_provider.dart';
import '../widgets/brand_background.dart';
import '../widgets/surface_components.dart';
import '../widgets/todo_completion_flow.dart';
import 'diary_screen.dart';
import 'habit_screen.dart';
import 'almanac_screen.dart';
import 'goal_edit_screen.dart';
import 'pomodoro_screen.dart';
import 'statistics_screen.dart';
import 'today_detail_router.dart';
import 'todo_screen.dart';

List<TodoItem> _visibleTodayOverviewTodos(
  Iterable<TodoItem> todos,
  DateTime now,
) {
  final today = CompletionVisibilityPolicy.dateOnly(now);
  return todos.where((todo) {
    if (todo.isArchivedAfterRollover || todo.isCompleted) return false;
    final due = todo.localDueDate;
    if (due == null) return true;
    final dueDay = CompletionVisibilityPolicy.dateOnly(due);
    if (dueDay.isBefore(today)) return false;
    if (CompletionVisibilityPolicy.isDateOnly(due)) return true;
    return !todo.dueAt!.isBefore(now);
  }).toList();
}

/// 今日概览：登录后展示的聚合首屏。
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final themeProvider = context.watch<ThemeProvider>();
    final s = themeProvider.brand.strings;

    final todoP = context.watch<TodoProvider>();
    final habitP = context.watch<HabitProvider>();
    context.select<PomodoroProvider, int>(
      (provider) => provider.persistedRevision,
    );
    final todayFocusCount = context
        .read<PomodoroProvider>()
        .sessions
        .where(
          (session) =>
              session.type == PomodoroType.focus &&
              AppClock.dateOnly(AppClock.toLocal(session.endTime)) ==
                  AppClock.today(),
        )
        .length;
    final diaryP = context.watch<DiaryProvider>();
    final anniP = context.watch<AnniversaryProvider>();
    final courseP = context.watch<CourseProvider>();
    final goalP = context.watch<GoalProvider>();
    final user = context.watch<UserProvider>();

    final now = AppClock.now();
    final todayKey = DateTime(now.year, now.month, now.day);
    final lunar = LunarCalendar.fromSolar(now);
    final term = LunarCalendar.solarTerm(now);
    final festival =
        LunarCalendar.solarFestival(now) ?? LunarCalendar.lunarFestival(lunar);
    final suitable = LunarCalendar.suitable(now);
    final avoid = LunarCalendar.avoid(now);

    final todayTodos = _visibleTodayOverviewTodos(todoP.todos, now);
    final todayTodosCount = todayTodos.length;
    final completedTodayCount = todoP.todos.where((todo) {
      final completedAt = todo.completedAt == null
          ? null
          : AppClock.toLocal(todo.completedAt!);
      if (!todo.isCompleted || completedAt == null) return false;
      return completedAt.year == todayKey.year &&
          completedAt.month == todayKey.month &&
          completedAt.day == todayKey.day;
    }).length;
    final noDueTodayTodos = todayTodos.where((todo) => todo.dueDate == null);
    todayTodos.sort((a, b) {
      final dueA = a.dueAt;
      final dueB = b.dueAt;
      if (dueA != null && dueB != null) return dueA.compareTo(dueB);
      if (dueA != null) return -1;
      if (dueB != null) return 1;
      return a.quadrant.index.compareTo(b.quadrant.index);
    });

    final todayCourses = courseP.coursesOfDate(now)
      ..sort((a, b) => a.startSection.compareTo(b.startSection));
    final reminderGroups = _TodayReminderGroups.build(
      todos: todoP.todos,
      courses: todayCourses,
      courseSettings: courseP.settings,
      now: now,
      todayKey: todayKey,
    );
    final todayHabitProgress = habitP.todayCompletionRate;

    // 最近的 3 个纪念日
    final upcomingAnni = [...anniP.items]
      ..sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));
    final soon = upcomingAnni
        .where((a) => a.daysRemaining >= 0)
        .take(3)
        .toList();

    final activeGoals = goalP.activeGoals.take(2).toList();
    final suggestions = SmartScheduleAdvisor.suggestToday(
      todoP.todos.where(
        (todo) => !CompletionVisibilityPolicy.shouldShowInToday(todo, now),
      ),
      now: now,
      limit: 5,
    );
    final showReminderSection =
        !reminderGroups.isEmpty || suggestions.isNotEmpty;

    // 问候语随主题品牌文案变化（BrandStrings.greetingFor 按时段取词）。
    // 分隔符与用户名兜底跟随 locale：en 下为 "Good afternoon, User"。
    final rawUsername = user.profile.username.trim();
    final displayUsername = rawUsername.isEmpty || rawUsername == '用户'
        ? I18n.tr('profile.default_user')
        : rawUsername;
    final greeting =
        '${s.greetingFor(now)}${I18n.tr('greeting.separator')}$displayUsername';
    final almanacCard = _TodayAlmanacCard(
      now: now,
      lunarText: lunar.chineseText,
      suitable: suitable,
      avoid: avoid,
      term: term,
      festival: festival,
      onTap: () => _go(context, AlmanacScreen(initialDate: now)),
    );
    final productivityCard = _TodayProductivitySection(
      onTap: () => _go(context, const StatisticsScreen()),
    );

    Widget metricsGrid({required bool desktop}) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final theme = Theme.of(context);
          final cs = theme.colorScheme;
          final useTwoColumns = constraints.maxWidth < (desktop ? 640 : 520);
          final crossAxisCount = useTwoColumns ? 2 : 4;
          final aspectRatio = desktop
              ? (useTwoColumns ? 2.75 : 2.85)
              : (useTwoColumns ? 2.55 : 3.65);
          // 数值行默认字号已提升到 DesignTokens.fontSizeMd，移动端 4 列在
          // 中段宽度下按 3.65 宽高比算出的瓦片高度不足以容纳“标题+数值”
          // 两行（还要扣掉卡片 0.5 描边内缩）。这里按当前系统字号缩放换算
          // 内容所需高度给瓦片兜底：AppMetricCard 默认竖向内容为标题
          // 11×1.1 + 间距 2 + 数值 fontSizeMd×1.1，外加卡内边距 20、描边
          // 1、余量 2；宽裕时仍按宽高比走，任意字号下都不溢出。
          final textScaler = MediaQuery.textScalerOf(context);
          final minTileExtent =
              textScaler.scale(11 * 1.1) +
              2 +
              textScaler.scale(DesignTokens.fontSizeMd * 1.1) +
              23;
          final tileExtent = desktop || useTwoColumns
              ? null
              : math.max(
                  ((constraints.maxWidth - 3 * 8) / crossAxisCount) /
                      aspectRatio,
                  minTileExtent,
                );

          // 桌面端使用更大的字体和图标
          final titleStyle = desktop
              ? theme.textTheme.bodySmall?.copyWith(
                  fontSize: DesktopTokens.fontSizeCaption,
                  color: cs.onSurface.withValues(
                    alpha: DesktopTokens.opacityTextTertiary,
                  ),
                  fontWeight: FontWeight.normal,
                  height: 1.1,
                )
              : null;

          final valueStyle = desktop
              ? theme.textTheme.titleMedium?.copyWith(
                  fontSize: DesktopTokens.fontSizeBody,
                  color: cs.onSurface.withValues(
                    alpha: DesktopTokens.opacityTextPrimary,
                  ),
                  height: 1.08,
                )
              : null;

          final unitStyle = desktop
              ? theme.textTheme.bodySmall?.copyWith(
                  fontSize: DesktopTokens.fontSizeCaption,
                  fontWeight: FontWeight.normal,
                  color: cs.onSurface.withValues(
                    alpha: DesktopTokens.opacityTextTertiary,
                  ),
                  height: 1.08,
                )
              : null;

          final padding = desktop
              ? const EdgeInsets.fromLTRB(14, 12, 14, 12)
              : const EdgeInsets.fromLTRB(12, 10, 12, 10);

          final iconBoxSize = desktop ? 32.0 : 28.0;
          final iconSize = desktop ? 17.0 : 15.0;

          return GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: crossAxisCount,
            childAspectRatio: aspectRatio,
            mainAxisExtent: tileExtent,
            mainAxisSpacing: desktop ? DesktopTokens.cardSpacingMedium : 8,
            crossAxisSpacing: desktop ? DesktopTokens.cardSpacingMedium : 8,
            children: [
              AppMetricCard(
                title: s.navTodo,
                value: '${todayTodos.length}',
                unit: I18n.tr('today.unit.item'),
                icon: Icons.check_circle_outline,
                color: cs.primary,
                onTap: () => _go(context, const TodoScreen()),
                titleStyle: titleStyle,
                valueStyle: valueStyle,
                unitStyle: unitStyle,
                padding: padding,
                iconBoxSize: iconBoxSize,
                iconSize: iconSize,
              ),
              AppMetricCard(
                title: s.navHabit,
                value: '${(todayHabitProgress * 100).round()}',
                unit: '%',
                icon: Icons.repeat,
                color: cs.tertiary,
                onTap: () => _go(context, const HabitScreen()),
                titleStyle: titleStyle,
                valueStyle: valueStyle,
                unitStyle: unitStyle,
                padding: padding,
                iconBoxSize: iconBoxSize,
                iconSize: iconSize,
              ),
              AppMetricCard(
                title: s.navFocus,
                value: '$todayFocusCount',
                unit: I18n.tr('today.unit.times'),
                icon: Icons.timer,
                color: Colors.redAccent,
                onTap: () => _go(
                  context,
                  const PomodoroScreen(useShellBackground: true),
                ),
                titleStyle: titleStyle,
                valueStyle: valueStyle,
                unitStyle: unitStyle,
                padding: padding,
                iconBoxSize: iconBoxSize,
                iconSize: iconSize,
              ),
              AppMetricCard(
                title: I18n.tr('today.diary'),
                value: diaryP.entryForDate(now) == null
                    ? I18n.tr('today.diary.unwritten')
                    : I18n.tr('today.diary.written'),
                icon: Icons.book_outlined,
                color: const Color(0xFF26A69A),
                onTap: () => _go(context, const DiaryScreen()),
                titleStyle: titleStyle,
                valueStyle: valueStyle,
                unitStyle: unitStyle,
                padding: padding,
                iconBoxSize: iconBoxSize,
                iconSize: iconSize,
              ),
            ],
          );
        },
      );
    }

    Widget todosSection({int maxItems = 6}) {
      return _section(
        I18n.tr('today.todos'),
        subtitle:
            "$todayTodosCount ${I18n.tr('today.unit.item')} · ${I18n.tr('today.completed')} $completedTodayCount · ${I18n.tr('today.no_due')} ${noDueTodayTodos.length}",
        onMore: () => TodayDetailRouter.open(context, TodaySectionKind.todos),
        child: todayTodos.isEmpty
            ? _TodayTodoEmptyState(
                onTap: () =>
                    TodayDetailRouter.open(context, TodaySectionKind.todos),
              )
            : Column(
                children: todayTodos.take(maxItems).map((t) {
                  return _TodayTodoSwipeTile(
                    todo: t,
                    onToggle: () =>
                        completeTodoWithOptionalTimeRecord(context, t),
                    onOpen: () => TodayDetailRouter.open(
                      context,
                      TodaySectionKind.todos,
                      id: t.id,
                    ),
                  );
                }).toList(),
              ),
      );
    }

    Widget? reminderSection() {
      if (!showReminderSection) return null;
      return _TodayReminderSection(
        groups: reminderGroups,
        suggestions: suggestions,
        todayKey: todayKey,
        now: now,
        onOpenTodo: (id) =>
            TodayDetailRouter.open(context, TodaySectionKind.todos, id: id),
        onToggleTodo: (todo) =>
            completeTodoWithOptionalTimeRecord(context, todo),
        onOpenCourses: () =>
            TodayDetailRouter.open(context, TodaySectionKind.courses),
        onAddToday: (todo) async {
          final actionNow = AppClock.now();
          final changed = await context
              .read<TodoProvider>()
              .scheduleTodoForToday(todo.id, now: actionNow);
          if (!context.mounted || !changed) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${I18n.tr('today.added_prefix')}${todo.title}'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      );
    }

    Widget? coursesSection() {
      if (todayCourses.isEmpty) return null;
      return _section(
        I18n.tr('today.courses'),
        subtitle:
            '${todayCourses.length} ${I18n.tr('today.unit.course_section')}',
        onMore: () => TodayDetailRouter.open(context, TodaySectionKind.courses),
        child: Column(
          children: todayCourses.map((c) {
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: Color(c.colorValue).withValues(alpha: 0.2),
                child: Text(
                  '${c.startSection}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(c.colorValue),
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              title: Text(c.name),
              subtitle: Text(
                '${I18n.tr('today.course.period_prefix')}${c.startSection}-${c.endSection}${I18n.tr('today.course.period_suffix')}${c.location.isEmpty ? '' : ' · ${c.location}'}${c.teacher.isEmpty ? '' : ' · ${c.teacher}'}',
                style: const TextStyle(fontSize: 11),
              ),
              onTap: () =>
                  TodayDetailRouter.open(context, TodaySectionKind.courses),
            );
          }).toList(),
        ),
      );
    }

    Widget? anniversariesSection() {
      if (soon.isEmpty) return null;
      return _section(
        I18n.tr('today.upcoming_anniversaries'),
        onMore: () =>
            TodayDetailRouter.open(context, TodaySectionKind.anniversaries),
        child: Column(
          children: soon.map((a) {
            final d = a.daysRemaining;
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: Color(a.colorValue).withValues(alpha: 0.15),
                child: Text(
                  '$d',
                  style: TextStyle(
                    color: Color(a.colorValue),
                    fontWeight: FontWeight.normal,
                    fontSize: 11,
                  ),
                ),
              ),
              title: Text(a.title),
              subtitle: Text(
                d == 0
                    ? I18n.tr('today.anniversary.today')
                    : '${I18n.tr('today.anniversary.days_prefix')}$d ${I18n.tr('unit.day')}',
                style: const TextStyle(fontSize: 11),
              ),
              onTap: () => TodayDetailRouter.open(
                context,
                TodaySectionKind.anniversaries,
                id: a.id,
              ),
            );
          }).toList(),
        ),
      );
    }

    Widget goalsSection() {
      return _section(
        activeGoals.isEmpty
            ? I18n.tr('goal.title')
            : I18n.tr('today.active_goals'),
        actionLabel: activeGoals.isEmpty
            ? I18n.tr('goal.new')
            : I18n.tr('today.view'),
        onMore: () => activeGoals.isEmpty
            ? Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GoalEditScreen()),
              )
            : TodayDetailRouter.open(context, TodaySectionKind.goals),
        child: activeGoals.isEmpty
            ? ListTile(
                leading: const Icon(Icons.flag_circle_outlined),
                title: Text(I18n.tr('goal.new')),
                subtitle: Text(I18n.tr('today.goal.create.subtitle')),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GoalEditScreen()),
                ),
              )
            : Column(
                children: activeGoals.map((g) {
                  final p = g.computedProgress;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      goalIconFromName(g.icon),
                      color: Color(g.colorValue),
                      size: 18,
                    ),
                    title: Text(g.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: p,
                            minHeight: 5,
                            color: Color(g.colorValue),
                            backgroundColor: Color(
                              g.colorValue,
                            ).withValues(alpha: 0.15),
                          ),
                        ),
                        Text(
                          '${(p * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                    onTap: () => TodayDetailRouter.open(
                      context,
                      TodaySectionKind.goals,
                      id: g.id,
                    ),
                  );
                }).toList(),
              ),
      );
    }

    final isDesktopLayout = MediaQuery.sizeOf(context).width >= 1100;
    final reminder = reminderSection();
    final courses = coursesSection();
    final anniversaries = anniversariesSection();
    final goals = goalsSection();
    if (isDesktopLayout) {
      return _TodayDesktopDashboard(
        greeting: greeting,
        dateText:
            '${I18nDateFormat.monthDayWithWeekday(now)} · ${lunar.chineseText}',
        almanacCard: almanacCard,
        productivityCard: productivityCard,
        metricsGrid: metricsGrid(desktop: true),
        todosSection: todosSection(maxItems: 8),
        reminderSection: reminder,
        quoteCard: _QuoteCard(),
        goalsSection: goals,
        coursesSection: courses,
        anniversariesSection: anniversaries,
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(greeting),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        key: const ValueKey('today_screen_list'),
        restorationId: 'today_screen_list',
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          almanacCard,
          const SizedBox(height: 12),

          productivityCard,

          const SizedBox(height: 12),

          _QuoteCard(),

          const SizedBox(height: 10),
          metricsGrid(desktop: false),

          const SizedBox(height: 14),

          todosSection(),
          ?reminder,
          ?courses,
          ?anniversaries,
          goals,
        ],
      ),
    );
  }

  Widget _section(
    String title, {
    String? subtitle,
    required Widget child,
    VoidCallback? onMore,
    String? actionLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: AppSurfaceCard(
        margin: const EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(
              builder: (context) {
                final theme = Theme.of(context);
                final cs = theme.colorScheme;
                return AppSectionHeader(
                  title: title,
                  subtitle: subtitle,
                  actionLabel: onMore == null
                      ? null
                      : actionLabel ?? I18n.tr('today.view'),
                  onAction: onMore,
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
                  titleStyle: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    height: 1.25,
                    fontWeight: FontWeight.normal,
                    color: cs.onSurface,
                  ),
                  actionTextStyle: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.normal,
                  ),
                );
              },
            ),
            child,
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  void _go(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BrandRouteSurface(child: screen)),
    );
  }
}

/// 桌面端左侧边栏 - 日历、一言、快捷入口
class _TodayDesktopLeftSidebar extends StatelessWidget {
  final DateTime now;
  final Widget quoteCard;

  const _TodayDesktopLeftSidebar({required this.now, required this.quoteCard});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 精简月历
        _CompactMonthCalendar(currentDate: now),
        const SizedBox(height: DesktopTokens.cardSpacing),

        // 今日一言
        quoteCard,
        const SizedBox(height: DesktopTokens.cardSpacing),

        // 快捷入口
        _QuickAccessPanel(),
      ],
    );
  }
}

/// 精简月历 - 当月日历，高亮今日
class _CompactMonthCalendar extends StatelessWidget {
  final DateTime currentDate;

  const _CompactMonthCalendar({required this.currentDate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final now = currentDate;

    // 当月第一天和最后一天
    final firstDay = DateTime(now.year, now.month, 1);
    final lastDay = DateTime(now.year, now.month + 1, 0);

    // 第一天是星期几（0=周日）
    final firstWeekday = firstDay.weekday % 7;

    // 构建日历网格
    final days = <Widget>[];

    // 星期标题
    const weekdays = ['日', '一', '二', '三', '四', '五', '六'];
    for (final weekday in weekdays) {
      days.add(
        Center(
          child: Text(
            weekday,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          ),
        ),
      );
    }

    // 填充前面的空格
    for (int i = 0; i < firstWeekday; i++) {
      days.add(const SizedBox.shrink());
    }

    // 填充日期
    for (int day = 1; day <= lastDay.day; day++) {
      final isToday = day == now.day;
      final date = DateTime(now.year, now.month, day);
      final isWeekend =
          date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

      days.add(
        Container(
          alignment: Alignment.center,
          decoration: isToday
              ? BoxDecoration(color: cs.primary, shape: BoxShape.circle)
              : null,
          child: Text(
            '$day',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 13,
              color: isToday
                  ? cs.onPrimary
                  : isWeekend
                  ? cs.onSurfaceVariant.withValues(alpha: 0.5)
                  : cs.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(DesktopTokens.cardPadding),
      decoration: BoxDecoration(
        color: cs.surface.withValues(
          alpha: DesktopTokens.opacityCardBackground,
        ),
        borderRadius: BorderRadius.circular(DesktopTokens.cardRadius),
        border: Border.all(
          color: cs.outlineVariant.withValues(
            alpha: DesktopTokens.opacityBorder,
          ),
          width: DesktopTokens.cardBorderWidth,
        ),
      ),
      child: Column(
        children: [
          // 月份标题
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${now.year}年${now.month}月',
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: DesktopTokens.fontSizeCardSubtitle,
                color: cs.onSurface.withValues(
                  alpha: DesktopTokens.opacityTextPrimary,
                ),
              ),
            ),
          ),

          // 日历网格
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 7,
            childAspectRatio: 1,
            mainAxisSpacing: 6,
            crossAxisSpacing: 4,
            children: days,
          ),
        ],
      ),
    );
  }
}

/// 快捷入口面板
class _QuickAccessPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final quickActions = [
      _QuickAction(
        icon: Icons.repeat,
        label: '习惯打卡',
        color: cs.tertiary,
        onTap: () => Navigator.pushNamed(context, '/habit'),
      ),
      _QuickAction(
        icon: Icons.timer_outlined,
        label: '番茄专注',
        color: Colors.redAccent,
        onTap: () => Navigator.pushNamed(context, '/pomodoro'),
      ),
      _QuickAction(
        icon: Icons.edit_note_outlined,
        label: '快速笔记',
        color: cs.secondary,
        onTap: () => Navigator.pushNamed(context, '/notes'),
      ),
      _QuickAction(
        icon: Icons.calendar_today_outlined,
        label: '日程安排',
        color: cs.primary,
        onTap: () => Navigator.pushNamed(context, '/calendar'),
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(DesktopTokens.cardPadding),
      decoration: BoxDecoration(
        color: cs.surface.withValues(
          alpha: DesktopTokens.opacityCardBackground,
        ),
        borderRadius: BorderRadius.circular(DesktopTokens.cardRadius),
        border: Border.all(
          color: cs.outlineVariant.withValues(
            alpha: DesktopTokens.opacityBorder,
          ),
          width: DesktopTokens.cardBorderWidth,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '快捷入口',
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: DesktopTokens.fontSizeCardSubtitle,
              color: cs.onSurface.withValues(
                alpha: DesktopTokens.opacityTextPrimary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.4,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: quickActions,
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: DesktopTokens.iconSizeMedium, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: DesktopTokens.fontSizeCaptionSmall,
                color: cs.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayDesktopDashboard extends StatelessWidget {
  final String greeting;
  final String dateText;
  final Widget almanacCard;
  final Widget productivityCard;
  final Widget metricsGrid;
  final Widget todosSection;
  final Widget? reminderSection;
  final Widget quoteCard;
  final Widget goalsSection;
  final Widget? coursesSection;
  final Widget? anniversariesSection;

  const _TodayDesktopDashboard({
    required this.greeting,
    required this.dateText,
    required this.almanacCard,
    required this.productivityCard,
    required this.metricsGrid,
    required this.todosSection,
    required this.reminderSection,
    required this.quoteCard,
    required this.goalsSection,
    required this.coursesSection,
    required this.anniversariesSection,
  });

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final now = AppClock.now(); // 用于左侧边栏日历

    final rightSidebarChildren = <Widget>[
      goalsSection,
      ?coursesSection,
      ?anniversariesSection,
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Scrollbar(
          child: SingleChildScrollView(
            key: const ValueKey('today_screen_list'),
            primary: true,
            padding: EdgeInsets.fromLTRB(
              DesktopTokens.pageHorizontalPadding,
              DesktopTokens.pageTopPadding,
              DesktopTokens.pageHorizontalPadding,
              DesktopTokens.pageBottomPadding,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesktopTokens.maxContentWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TodayDesktopHeader(greeting: greeting, dateText: dateText),
                    const SizedBox(height: DesktopTokens.cardSpacing),

                    // 响应式三栏/两栏布局
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final showLeftSidebar =
                            DesktopTokens.isThreeColumnLayout(
                              constraints.maxWidth,
                            );

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 左侧边栏（仅在宽度 >= 1400px 时显示）
                            if (showLeftSidebar) ...[
                              SizedBox(
                                width: DesktopTokens.leftSidebarWidth,
                                child: _TodayDesktopLeftSidebar(
                                  now: now,
                                  quoteCard: quoteCard,
                                ),
                              ),
                              const SizedBox(
                                width: DesktopTokens.columnSpacing,
                              ),
                            ],

                            // 主内容区
                            Expanded(
                              child: Column(
                                children: [
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      if (constraints.maxWidth < 720) {
                                        return Column(
                                          children: [
                                            almanacCard,
                                            const SizedBox(
                                              height: DesktopTokens
                                                  .cardSpacingMedium,
                                            ),
                                            productivityCard,
                                          ],
                                        );
                                      }
                                      return Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(child: almanacCard),
                                          const SizedBox(
                                            width:
                                                DesktopTokens.cardSpacingMedium,
                                          ),
                                          SizedBox(
                                            width: 340,
                                            child: productivityCard,
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                  const SizedBox(
                                    height: DesktopTokens.cardSpacingMedium,
                                  ),
                                  metricsGrid,
                                  const SizedBox(
                                    height: DesktopTokens.cardSpacing,
                                  ),

                                  // 当左侧边栏隐藏时，今日一言显示在主内容区
                                  if (!showLeftSidebar) ...[
                                    quoteCard,
                                    const SizedBox(
                                      height: DesktopTokens.cardSpacing,
                                    ),
                                  ],

                                  todosSection,
                                  ?reminderSection,
                                ],
                              ),
                            ),

                            // 右侧边栏
                            const SizedBox(width: DesktopTokens.columnSpacing),
                            SizedBox(
                              width: DesktopTokens.rightSidebarWidth,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: rightSidebarChildren,
                              ),
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 4),
                    Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.20),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TodayDesktopHeader extends StatelessWidget {
  final String greeting;
  final String dateText;

  const _TodayDesktopHeader({required this.greeting, required this.dateText});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesktopTokens.cardPadding,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        color: cs.surface.withValues(
          alpha: DesktopTokens.opacityCardBackground,
        ),
        borderRadius: BorderRadius.circular(DesktopTokens.cardRadius),
        border: Border.all(
          color: cs.outlineVariant.withValues(
            alpha: DesktopTokens.opacityBorder,
          ),
          width: DesktopTokens.cardBorderWidth,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: DesktopTokens.fontSizePageTitle,
                    height: 1.15,
                    color: cs.onSurface.withValues(
                      alpha: DesktopTokens.opacityTextPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  dateText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: DesktopTokens.fontSizePageSubtitle,
                    color: cs.onSurfaceVariant.withValues(
                      alpha: DesktopTokens.opacityTextSecondary,
                    ),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Text(
              I18n.tr('nav.today'),
              style: theme.textTheme.labelMedium?.copyWith(
                fontSize: DesktopTokens.fontSizeBody,
                color: cs.onSurfaceVariant.withValues(
                  alpha: DesktopTokens.opacityTextSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayAlmanacCard extends StatelessWidget {
  final DateTime now;
  final String lunarText;
  final String suitable;
  final String avoid;
  final String? term;
  final String? festival;
  final VoidCallback onTap;

  const _TodayAlmanacCard({
    required this.now,
    required this.lunarText,
    required this.suitable,
    required this.avoid,
    required this.term,
    required this.festival,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final brand = context.watch<ThemeProvider>().brand;
    final radius = BorderRadius.circular(DesignTokens.radiusCard);
    final foreground = isDark ? Colors.white : cs.onSurface;
    final muted = foreground.withValues(alpha: isDark ? 0.74 : 0.68);
    final accent = cs.primary;
    final backgroundAsset = brand.backgroundAsset;
    final panelFill = foreground.withValues(alpha: isDark ? 0.09 : 0.055);
    final panelBorder = foreground.withValues(alpha: isDark ? 0.13 : 0.09);

    final fallbackGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.alphaBlend(
          accent.withValues(alpha: isDark ? 0.26 : 0.16),
          cs.surface,
        ),
        Color.alphaBlend(
          cs.secondary.withValues(alpha: isDark ? 0.20 : 0.12),
          cs.surface,
        ),
      ],
    );
    final imageOverlay = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              Colors.black.withValues(alpha: 0.42),
              cs.surface.withValues(alpha: 0.72),
            ]
          : [
              brand.backgroundOverlay.withValues(alpha: 0.62),
              cs.surface.withValues(alpha: 0.76),
            ],
    );

    return AppSurfaceCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      borderRadius: radius,
      color: Colors.transparent,
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.10)
            : cs.outlineVariant.withValues(alpha: 0.18),
        width: 0.55,
      ),
      elevation: 2,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned.fill(
              child: backgroundAsset == null
                  ? DecoratedBox(
                      decoration: BoxDecoration(gradient: fallbackGradient),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final dpr = MediaQuery.devicePixelRatioOf(
                          context,
                        ).clamp(1.0, 3.0);
                        final fallbackSize = MediaQuery.sizeOf(context);
                        final width = constraints.hasBoundedWidth
                            ? constraints.maxWidth
                            : fallbackSize.width;
                        final height = constraints.hasBoundedHeight
                            ? constraints.maxHeight
                            : 180.0;
                        final cacheWidth = (width * dpr).ceil().clamp(1, 2048);
                        final cacheHeight = (height * dpr).ceil().clamp(
                          1,
                          2048,
                        );
                        return Image.asset(
                          backgroundAsset,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          cacheWidth: cacheWidth,
                          cacheHeight: cacheHeight,
                          filterQuality: FilterQuality.low,
                          gaplessPlayback: true,
                        );
                      },
                    ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: imageOverlay),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(15),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: panelFill,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                  border: Border.all(color: panelBorder, width: 0.45),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _TodayDateBadge(
                            date: now,
                            accent: accent,
                            foreground: foreground,
                            muted: muted,
                            isDark: isDark,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: accent.withValues(
                                          alpha: isDark ? 0.20 : 0.13,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          DesignTokens.radiusSm,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.calendar_month_rounded,
                                        size: 14,
                                        color: accent,
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Text(
                                        '${I18n.tr('today.almanac.title')} · ${I18nDateFormat.monthDayWithWeekday(now)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: muted,
                                              fontSize: 12.5,
                                              height: 1.2,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      width: 26,
                                      height: 26,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: foreground.withValues(
                                          alpha: isDark ? 0.12 : 0.08,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.chevron_right_rounded,
                                        size: 17,
                                        color: foreground.withValues(
                                          alpha: 0.62,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${I18n.tr('calendar.chinese_lunar_calendar')} $lunarText',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: foreground,
                                    fontSize: 16,
                                    height: 1.25,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                                if (term != null || festival != null) ...[
                                  const SizedBox(height: 9),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      if (term != null)
                                        _TodayCalendarChip(
                                          text: term!,
                                          color: accent,
                                        ),
                                      if (festival != null)
                                        _TodayCalendarChip(
                                          text: festival!,
                                          color: cs.tertiary,
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _TodayYijiPreview(
                              label: '宜',
                              text: suitable,
                              color: const Color(0xFF2E7D32),
                              foreground: foreground,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _TodayYijiPreview(
                              label: '忌',
                              text: avoid,
                              color: const Color(0xFFC62828),
                              foreground: foreground,
                              isDark: isDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayDateBadge extends StatelessWidget {
  final DateTime date;
  final Color accent;
  final Color foreground;
  final Color muted;
  final bool isDark;

  const _TodayDateBadge({
    required this.date,
    required this.accent,
    required this.foreground,
    required this.muted,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 68,
      height: 76,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: isDark ? 0.08 : 0.05),
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        border: Border.all(
          color: foreground.withValues(alpha: isDark ? 0.12 : 0.10),
          width: 0.55,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.045),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 5),
            color: accent.withValues(alpha: isDark ? 0.20 : 0.13),
            child: Text(
              '${date.month}月',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontSize: 11,
                height: 1,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 44,
                  height: 31,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${date.day}',
                      maxLines: 1,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: foreground,
                        fontSize: 30,
                        height: 0.96,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${date.year}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: muted,
                    fontSize: 10,
                    height: 1,
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

class _TodayCalendarChip extends StatelessWidget {
  final String text;
  final Color color;

  const _TodayCalendarChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.16), width: 0.45),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 128),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 11,
            color: color,
            height: 1.1,
            fontWeight: FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _TodayYijiPreview extends StatelessWidget {
  final String label;
  final String text;
  final Color color;
  final Color foreground;
  final bool isDark;

  const _TodayYijiPreview({
    required this.label,
    required this.text,
    required this.color,
    required this.foreground,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.17 : 0.105),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.22), width: 0.45),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                height: 1,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: foreground.withValues(alpha: isDark ? 0.88 : 0.82),
                fontSize: 11.5,
                height: 1.16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayProductivitySection extends StatelessWidget {
  final VoidCallback onTap;

  const _TodayProductivitySection({required this.onTap});

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final todoP = context.watch<TodoProvider>();
    final habitP = context.watch<HabitProvider>();
    context.select<PomodoroProvider, int>(
      (provider) => provider.persistedRevision,
    );
    final pomoP = context.read<PomodoroProvider>();
    final timeEntries = context.watch<TimeAuditProvider>().entries;

    final now = AppClock.now();
    final todayKey = DateTime(now.year, now.month, now.day);
    final weekStart = todayKey.subtract(Duration(days: todayKey.weekday - 1));
    final weekEnd = todayKey;
    final previousWeekStart = weekStart.subtract(const Duration(days: 7));
    final previousWeekEnd = weekEnd.subtract(const Duration(days: 7));
    final weeklyReport = ReportEngine.buildReport(
      start: weekStart,
      end: weekEnd,
      todos: todoP.todos,
      habits: habitP.habits,
      sessions: pomoP.sessions,
      timeEntries: timeEntries,
    );
    final previousWeeklyReport = ReportEngine.buildReport(
      start: previousWeekStart,
      end: previousWeekEnd,
      todos: todoP.todos,
      habits: habitP.habits,
      sessions: pomoP.sessions,
      timeEntries: timeEntries,
    );
    return _TodayProductivityCard(
      comparison: ReportEngine.compare(
        current: weeklyReport,
        previous: previousWeeklyReport,
      ),
      onTap: onTap,
    );
  }
}

class _TodayProductivityCard extends StatelessWidget {
  final ReportComparison comparison;
  final VoidCallback onTap;

  const _TodayProductivityCard({required this.comparison, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final scoreDelta = comparison.productivityScore.difference.round();
    final trendColor = _trendColor(cs, comparison.productivityScore.direction);
    return AppSurfaceCard(
      onTap: onTap,
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(
            cs.primary.withValues(alpha: isDark ? 0.075 : 0.035),
            cs.surface,
          ),
          Color.alphaBlend(
            trendColor.withValues(alpha: isDark ? 0.070 : 0.030),
            cs.surface,
          ),
        ],
      ),
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: isDark ? 0.16 : 0.20),
        width: 0.55,
      ),
      elevation: 1.5,
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.alphaBlend(
                cs.primary.withValues(alpha: isDark ? 0.18 : 0.11),
                cs.surface,
              ),
              border: Border.all(color: cs.primary.withValues(alpha: 0.28)),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: isDark ? 0.16 : 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  comparison.current.productivityScore.toString(),
                  style: TextStyle(
                    fontSize: 22,
                    height: 1,
                    color: cs.primary,
                    fontWeight: FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  I18n.tr('today.productivity.score'),
                  style: TextStyle(
                    fontSize: 9,
                    color: cs.onSurface.withValues(alpha: 0.58),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        I18n.tr('today.productivity.weekly'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                    Icon(
                      _trendIcon(comparison.productivityScore.direction),
                      color: trendColor,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      scoreDelta == 0
                          ? I18n.tr('today.productivity.flat')
                          : '${scoreDelta > 0 ? '+' : ''}$scoreDelta ${I18n.tr('today.unit.point')}',
                      style: TextStyle(fontSize: 12, color: trendColor),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  I18n.tr('today.productivity.subtitle'),
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.58),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _TodayProductivityPill(
                      label: I18n.tr('today.productivity.completion_rate'),
                      value:
                          '${(comparison.current.todoCompletionRate * 100).round()}%',
                    ),
                    _TodayProductivityPill(
                      label: I18n.tr('nav.focus'),
                      value:
                          '${comparison.current.focusMinutes}${I18n.tr('unit.min')}',
                    ),
                    _TodayProductivityPill(
                      label: I18n.tr('nav.habit'),
                      value:
                          '${comparison.current.habitCheckIns}${I18n.tr('today.unit.times')}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.chevron_right,
            size: 18,
            color: cs.onSurface.withValues(alpha: 0.38),
          ),
        ],
      ),
    );
  }

  Color _trendColor(ColorScheme cs, ReportTrendDirection direction) =>
      switch (direction) {
        ReportTrendDirection.up => const Color(0xFF2E7D32),
        ReportTrendDirection.down => const Color(0xFFC62828),
        ReportTrendDirection.flat => cs.onSurface.withValues(alpha: 0.62),
      };

  IconData _trendIcon(ReportTrendDirection direction) => switch (direction) {
    ReportTrendDirection.up => Icons.trending_up,
    ReportTrendDirection.down => Icons.trending_down,
    ReportTrendDirection.flat => Icons.trending_flat,
  };
}

class _TodayProductivityPill extends StatelessWidget {
  final String label;
  final String value;

  const _TodayProductivityPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.18),
          width: 0.45,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 150),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurface.withValues(alpha: 0.56),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuoteCard extends StatefulWidget {
  @override
  State<_QuoteCard> createState() => _QuoteCardState();
}

class _TodayTodoEmptyState extends StatelessWidget {
  final VoidCallback onTap;

  const _TodayTodoEmptyState({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.56),
              width: 0.7,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.checklist_rtl_outlined, size: 17, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  I18n.tr('today.todos.empty'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodoTodaySubtitle extends StatelessWidget {
  final TodoItem todo;

  const _TodoTodaySubtitle({required this.todo});

  @override
  Widget build(BuildContext context) {
    final visual = CompletionVisibilityPolicy.visualState(todo);
    final subtasks = todo.subtasks.take(3).toList();
    final hasNoDueDate = todo.dueDate == null;
    if (todo.listGroupName == null &&
        subtasks.isEmpty &&
        visual == TodoVisualState.normal &&
        !hasNoDueDate) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (visual != TodoVisualState.normal)
            _TodayTodoStatusPill(visual: visual),
          if (hasNoDueDate) const _TodayNoDueDateLabel(),
          if ((visual != TodoVisualState.normal || hasNoDueDate) &&
              (todo.listGroupName != null || subtasks.isNotEmpty))
            const SizedBox(height: 3),
          if (todo.listGroupName != null) _TodoListTemplateLabel(todo: todo),
          for (final subtask in subtasks)
            Row(
              children: [
                Icon(
                  subtask.isCompleted
                      ? Icons.check_circle_outline
                      : Icons.subdirectory_arrow_right,
                  size: 12,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    subtask.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TodayNoDueDateLabel extends StatelessWidget {
  const _TodayNoDueDateLabel();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      I18n.tr('today.no_due_date'),
      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
    );
  }
}

class _TodayTodoStatusPill extends StatelessWidget {
  final TodoVisualState visual;

  const _TodayTodoStatusPill({required this.visual});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (label, icon, color) = switch (visual) {
      TodoVisualState.completed => (
        I18n.tr('today.completed'),
        Icons.check_circle_outline,
        cs.tertiary,
      ),
      TodoVisualState.overdue => (
        I18n.tr('todo.status.overdue'),
        Icons.priority_high_rounded,
        cs.error,
      ),
      TodoVisualState.dueSoon => (
        I18n.tr('todo.status.due_soon'),
        Icons.alarm_outlined,
        Colors.orange.shade700,
      ),
      _ => (
        I18n.tr('todo.status.normal'),
        Icons.radio_button_unchecked,
        cs.onSurfaceVariant,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24), width: 0.7),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }
}

class _TodoTemplateVisual {
  final IconData icon;
  final Color color;
  final String key;

  const _TodoTemplateVisual({
    required this.icon,
    required this.color,
    required this.key,
  });
}

TodoListTemplate? _todoListTemplateFor(String? name) {
  final target = name?.trim();
  if (target == null || target.isEmpty) return null;
  for (final template in TodoListTemplates.all) {
    if (template.name == target) return template;
  }
  return null;
}

_TodoTemplateVisual _todoTemplateVisual(BuildContext context, TodoItem todo) {
  final template = _todoListTemplateFor(todo.listGroupName);
  if (template != null) {
    return _TodoTemplateVisual(
      icon: template.icon,
      color: template.color,
      key: template.name,
    );
  }
  return _TodoTemplateVisual(
    icon: _todoQuadrantIcon(todo.quadrant),
    color: _todoQuadrantColor(todo.quadrant),
    key: 'quadrant_${todo.quadrant.index}',
  );
}

IconData _todoQuadrantIcon(EisenhowerQuadrant quadrant) {
  return switch (quadrant) {
    EisenhowerQuadrant.urgentImportant => Icons.priority_high_outlined,
    EisenhowerQuadrant.notUrgentImportant => Icons.flag_outlined,
    EisenhowerQuadrant.urgentNotImportant => Icons.bolt_outlined,
    EisenhowerQuadrant.notUrgentNotImportant => Icons.checklist_rounded,
  };
}

Color _todoQuadrantColor(EisenhowerQuadrant quadrant) {
  return switch (quadrant) {
    EisenhowerQuadrant.urgentImportant => const Color(0xFFE53935),
    EisenhowerQuadrant.notUrgentImportant => const Color(0xFFF6A339),
    EisenhowerQuadrant.urgentNotImportant => const Color(0xFF42A5F5),
    EisenhowerQuadrant.notUrgentNotImportant => const Color(0xFF8E8E8E),
  };
}

class _TodoListTemplateLabel extends StatelessWidget {
  final TodoItem todo;

  const _TodoListTemplateLabel({required this.todo});

  @override
  Widget build(BuildContext context) {
    final label = todo.listGroupName?.trim();
    if (label == null || label.isEmpty) return const SizedBox.shrink();
    final template = _todoListTemplateFor(label);
    final cs = Theme.of(context).colorScheme;
    final color = template?.color ?? cs.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          template?.icon ?? Icons.folder_outlined,
          key: ValueKey('today_todo_list_icon_${template?.name ?? 'custom'}'),
          size: 11,
          color: color,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: color),
          ),
        ),
      ],
    );
  }
}

class _TodoTemplateAvatar extends StatelessWidget {
  final TodoItem todo;
  final String keyPrefix;
  final double radius;
  final double iconSize;

  const _TodoTemplateAvatar({
    required this.todo,
    required this.keyPrefix,
    this.radius = 14,
    this.iconSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    final visual = _todoTemplateVisual(context, todo);
    return CircleAvatar(
      key: ValueKey('${keyPrefix}_${visual.key}'),
      radius: radius,
      backgroundColor: visual.color.withValues(alpha: 0.13),
      child: Icon(visual.icon, size: iconSize, color: visual.color),
    );
  }
}

class _TodayTodoLeading extends StatelessWidget {
  static const double width = 44;
  static const double height = 44;
  static const double touchTargetSize = 44;
  static const double statusButtonSize = 24;

  final Color? statusColor;
  final bool isCompleted;
  final Color? completedCheckColor;
  final ValueChanged<bool?>? onChanged;

  const _TodayTodoLeading({
    required this.statusColor,
    required this.isCompleted,
    required this.completedCheckColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Center(
        child: _TodayTodoStatusToggle(
          color: statusColor,
          isCompleted: isCompleted,
          completedCheckColor: completedCheckColor,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _TodayTodoTitleLine extends StatelessWidget {
  final TodoItem todo;
  final String title;
  final Color? titleColor;
  final bool completed;
  final bool overdue;
  final String iconKeyPrefix;

  const _TodayTodoTitleLine({
    required this.todo,
    required this.title,
    required this.completed,
    required this.overdue,
    required this.iconKeyPrefix,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = titleColor ?? (overdue ? cs.error : cs.onSurface);
    return Row(
      children: [
        _TodoTemplateAvatar(
          todo: todo,
          keyPrefix: iconKeyPrefix,
          radius: 10,
          iconSize: 12,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: effectiveColor,
              decoration: completed ? TextDecoration.lineThrough : null,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
        if (overdue) ...[
          const SizedBox(width: 6),
          _OverdueReminderBadge(color: cs.error),
        ],
      ],
    );
  }
}

class _TodayTodoStatusToggle extends StatelessWidget {
  final Color? color;
  final bool isCompleted;
  final Color? completedCheckColor;
  final ValueChanged<bool?>? onChanged;

  const _TodayTodoStatusToggle({
    required this.color,
    required this.isCompleted,
    required this.completedCheckColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = color ?? cs.primary;
    final background = isCompleted
        ? accent
        : Color.alphaBlend(accent.withValues(alpha: 0.08), cs.surface);
    final foreground = completedCheckColor ?? cs.onPrimary;
    final enabled = onChanged != null;
    return Semantics(
      button: true,
      checked: isCompleted,
      label: isCompleted ? '标记为未完成' : '标记为完成',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? () => onChanged?.call(!isCompleted) : null,
          child: SizedBox(
            width: _TodayTodoLeading.touchTargetSize,
            height: _TodayTodoLeading.touchTargetSize,
            child: Center(
              child: Container(
                width: _TodayTodoLeading.statusButtonSize,
                height: _TodayTodoLeading.statusButtonSize,
                decoration: ShapeDecoration(
                  color: background,
                  shape: CircleBorder(
                    side: BorderSide(
                      color: accent.withValues(
                        alpha: isCompleted ? 0.24 : 0.34,
                      ),
                      width: 0.9,
                    ),
                  ),
                ),
                child: isCompleted
                    ? Icon(Icons.check_rounded, size: 15, color: foreground)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TodayTodoSwipeTile extends StatefulWidget {
  final TodoItem todo;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final Widget? leading;
  final String? title;
  final Color? titleColor;
  final Color? completedTextColor;
  final Widget? subtitle;
  final Widget? trailing;
  final Color? tileBackground;
  final Color? tileBorderColor;
  final bool showStatusDecoration;
  final String iconKeyPrefix;
  final bool showOverdueBadge;

  const _TodayTodoSwipeTile({
    required this.todo,
    required this.onToggle,
    required this.onOpen,
    this.leading,
    this.title,
    this.titleColor,
    this.completedTextColor,
    this.subtitle,
    this.trailing,
    this.tileBackground,
    this.tileBorderColor,
    this.showStatusDecoration = true,
    this.iconKeyPrefix = 'today_todo_template_icon',
    this.showOverdueBadge = false,
  });

  @override
  State<_TodayTodoSwipeTile> createState() => _TodayTodoSwipeTileState();
}

class _TodayTodoSwipeTileState extends State<_TodayTodoSwipeTile> {
  static const double _swipeActionWidth = 56;
  static const double _swipeOpenThreshold = 30;

  double _swipeOffset = 0;
  bool _dragging = false;

  bool get _swipeOpen => _swipeOffset > 0;
  bool get _swipeActive => _swipeOffset > 0;

  @override
  void didUpdateWidget(covariant _TodayTodoSwipeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.todo.id != oldWidget.todo.id) {
      _swipeOffset = 0;
      _dragging = false;
    }
  }

  void _closeSwipe() {
    if (!_swipeOpen || !mounted) return;
    setState(() => _swipeOffset = 0);
  }

  void _showReadOnlyMessage(String action) {
    _closeSwipe();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('共享空间只读，不能$action'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    _closeSwipe();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AppDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('删除任务？'),
        content: Text('将删除“${widget.todo.title}”，相关时间足迹也会同步移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<TodoProvider>().deleteTodo(widget.todo.id);
    } else {
      _closeSwipe();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final todo = widget.todo;
    final visual = CompletionVisibilityPolicy.visualState(todo);
    final isCompleted = visual == TodoVisualState.completed;
    final isOverdue = visual == TodoVisualState.overdue;
    final templateVisual = _todoTemplateVisual(context, todo);
    final statusColor = widget.showStatusDecoration
        ? switch (visual) {
            TodoVisualState.completed => cs.tertiary,
            TodoVisualState.overdue => cs.error,
            TodoVisualState.dueSoon => Colors.orange.shade700,
            TodoVisualState.normal => templateVisual.color,
            TodoVisualState.archived => cs.outline,
          }
        : null;
    final backgroundAlpha = switch (visual) {
      TodoVisualState.completed => 0.06,
      TodoVisualState.overdue => 0.09,
      TodoVisualState.dueSoon => 0.07,
      TodoVisualState.normal => 0.035,
      TodoVisualState.archived => 0.04,
    };
    final borderAlpha = switch (visual) {
      TodoVisualState.completed => 0.24,
      TodoVisualState.overdue => 0.30,
      TodoVisualState.dueSoon => 0.24,
      TodoVisualState.normal => 0.16,
      TodoVisualState.archived => 0.18,
    };
    final effectiveTileBackground =
        widget.tileBackground ??
        (statusColor == null
            ? null
            : Color.alphaBlend(
                statusColor.withValues(alpha: backgroundAlpha),
                cs.surface,
              ));
    final effectiveTileBorderColor =
        widget.tileBorderColor ?? statusColor?.withValues(alpha: borderAlpha);
    final canEdit = context.select<ShareProvider?, bool>(
      (share) => share?.canEdit(todo.workspaceId) ?? true,
    );
    final effectiveTitleColor = todo.isCompleted
        ? widget.completedTextColor ?? cs.onSurface.withValues(alpha: 0.52)
        : widget.titleColor ?? (isOverdue ? cs.error : null);
    final compact = MediaQuery.sizeOf(context).width < 360;
    Widget tile = Material(
      color: Colors.transparent,
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
        horizontalTitleGap: 4,
        minLeadingWidth: widget.leading == null ? _TodayTodoLeading.width : 30,
        leading:
            widget.leading ??
            _TodayTodoLeading(
              statusColor: statusColor,
              isCompleted: isCompleted,
              completedCheckColor: cs.onTertiary,
              onChanged: canEdit
                  ? (_) => widget.onToggle()
                  : (_) => _showReadOnlyMessage('完成任务'),
            ),
        title: _TodayTodoTitleLine(
          todo: todo,
          title: widget.title ?? todo.title,
          titleColor: effectiveTitleColor,
          completed: todo.isCompleted,
          overdue: widget.showOverdueBadge || isOverdue,
          iconKeyPrefix: widget.iconKeyPrefix,
        ),
        subtitle: widget.subtitle ?? _TodoTodaySubtitle(todo: todo),
        trailing: widget.trailing == null
            ? null
            : ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? 72 : 96),
                child: widget.trailing!,
              ),
        onTap: _swipeOpen ? _closeSwipe : widget.onOpen,
      ),
    );
    if (effectiveTileBackground != null || effectiveTileBorderColor != null) {
      tile = Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: effectiveTileBackground ?? Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: effectiveTileBorderColor ?? Colors.transparent,
            width: 0.7,
          ),
        ),
        child: tile,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => setState(() => _dragging = true),
      onHorizontalDragUpdate: (details) {
        final next = (_swipeOffset - details.delta.dx).clamp(
          0.0,
          _swipeActionWidth,
        );
        if (next == _swipeOffset) return;
        setState(() => _swipeOffset = next);
      },
      onHorizontalDragEnd: (_) {
        final shouldOpen = _swipeOffset >= _swipeOpenThreshold;
        setState(() {
          _dragging = false;
          _swipeOffset = shouldOpen ? _swipeActionWidth : 0;
        });
      },
      onHorizontalDragCancel: () => setState(() {
        _dragging = false;
        _swipeOffset = _swipeOffset >= _swipeOpenThreshold
            ? _swipeActionWidth
            : 0;
      }),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          if (_swipeActive)
            Positioned.fill(
              child: RepaintBoundary(
                child: Container(
                  alignment: Alignment.centerRight,
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.62),
                  child: SizedBox(
                    width: _swipeActionWidth,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _TodayTodoSwipeButton(
                          key: const ValueKey('today_todo_swipe_delete_button'),
                          icon: Icons.delete_outline,
                          label: '删除',
                          background: canEdit
                              ? cs.errorContainer.withValues(alpha: 0.64)
                              : cs.surfaceContainerHighest.withValues(
                                  alpha: 0.78,
                                ),
                          foreground: canEdit ? cs.error : cs.onSurfaceVariant,
                          onTap: canEdit
                              ? () => _confirmDelete(context)
                              : () => _showReadOnlyMessage('删除任务'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          AnimatedContainer(
            duration: _dragging
                ? Duration.zero
                : const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(-_swipeOffset, 0, 0),
            child: RepaintBoundary(child: tile),
          ),
        ],
      ),
    );
  }
}

class _TodayTodoSwipeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _TodayTodoSwipeButton({
    super.key,
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 38,
              child: Icon(icon, size: 17, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}

enum _TodayReminderKind { todo, course }

class _TodayReminderItem {
  final _TodayReminderKind kind;
  final String id;
  final String title;
  final DateTime time;
  final String subtitle;
  final TodoItem? todo;
  final Color? accentColor;
  final bool completed;

  const _TodayReminderItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.time,
    required this.subtitle,
    this.todo,
    this.accentColor,
    this.completed = false,
  });
}

class _TodayReminderGroups {
  final List<_TodayReminderItem> dueToday;
  final List<_TodayReminderItem> upcoming;
  final List<_TodayReminderItem> overdue;

  const _TodayReminderGroups({
    required this.dueToday,
    required this.upcoming,
    required this.overdue,
  });

  bool get isEmpty => dueToday.isEmpty && upcoming.isEmpty && overdue.isEmpty;

  static _TodayReminderGroups build({
    required Iterable<TodoItem> todos,
    required Iterable<CourseItem> courses,
    required ScheduleSettings courseSettings,
    required DateTime now,
    required DateTime todayKey,
  }) {
    final dueToday = <_TodayReminderItem>[];
    final upcoming = <_TodayReminderItem>[];
    final overdue = <_TodayReminderItem>[];
    final completedToday = <_TodayReminderItem>[];
    final soonLimit = now.add(const Duration(hours: 6));

    for (final todo in todos) {
      if (todo.isArchivedAfterRollover) continue;
      final trigger = _todoTriggerTime(todo);
      if (trigger == null) continue;
      final item = _TodayReminderItem(
        kind: _TodayReminderKind.todo,
        id: todo.id,
        title: todo.title,
        time: trigger,
        subtitle: _todoReminderSubtitle(todo, trigger, now),
        todo: todo,
        completed: todo.isCompleted,
      );
      if (todo.isCompleted) {
        if (_sameDay(
          todo.completedAt == null
              ? trigger
              : AppClock.toLocal(todo.completedAt!),
          todayKey,
        )) {
          completedToday.add(item);
        }
      } else if (trigger.isBefore(now)) {
        overdue.add(item);
      } else if (_sameDay(trigger, todayKey)) {
        dueToday.add(item);
      } else if (trigger.isBefore(soonLimit)) {
        upcoming.add(item);
      }
    }

    for (final course in courses) {
      final wallStart = courseSettings.sectionStart(
        todayKey,
        course.startSection,
      );
      final wallEnd = courseSettings.sectionEnd(
        todayKey,
        course.startSection,
        course.sectionCount,
      );
      final start = AppClock.date(
        wallStart.year,
        wallStart.month,
        wallStart.day,
        wallStart.hour,
        wallStart.minute,
      );
      final end = AppClock.date(
        wallEnd.year,
        wallEnd.month,
        wallEnd.day,
        wallEnd.hour,
        wallEnd.minute,
      );
      final item = _TodayReminderItem(
        kind: _TodayReminderKind.course,
        id: course.id,
        title: course.name,
        time: start,
        subtitle:
            '${I18n.tr('today.course.period_prefix')}${course.startSection}-${course.endSection}${I18n.tr('today.course.period_suffix')}${course.location.isEmpty ? '' : ' · ${course.location}'}${course.teacher.isEmpty ? '' : ' · ${course.teacher}'}',
        accentColor: Color(course.colorValue),
      );
      if (end.isBefore(now)) {
        overdue.add(item);
      } else if (start.isBefore(now.add(const Duration(minutes: 30)))) {
        dueToday.add(item);
      } else {
        upcoming.add(item);
      }
    }

    int compare(_TodayReminderItem a, _TodayReminderItem b) =>
        a.time.compareTo(b.time);
    dueToday.sort(compare);
    upcoming.sort(compare);
    overdue.sort(compare);
    completedToday.sort(compare);

    return _TodayReminderGroups(
      dueToday: [...dueToday, ...completedToday],
      upcoming: upcoming,
      overdue: overdue,
    );
  }

  static bool _sameDay(DateTime value, DateTime day) =>
      value.year == day.year &&
      value.month == day.month &&
      value.day == day.day;

  static DateTime? _todoTriggerTime(TodoItem todo) {
    if (todo.hasReminder && todo.reminderAt != null) {
      return AppClock.toLocal(todo.reminderAt!);
    }
    return todo.dueAt;
  }

  static String _todoReminderSubtitle(
    TodoItem todo,
    DateTime trigger,
    DateTime now,
  ) {
    final prefix = trigger.isBefore(now)
        ? '提醒时间'
        : _sameDay(trigger, DateTime(now.year, now.month, now.day))
        ? '今日提醒'
        : '即将开始';
    final meta = <String>[
      I18nDateFormat.smartDate(trigger, includeTime: true),
      if (todo.listGroupName != null && todo.listGroupName!.isNotEmpty)
        todo.listGroupName!,
    ];
    return '$prefix · ${meta.join(' · ')}';
  }
}

class _TodayReminderSection extends StatefulWidget {
  final _TodayReminderGroups groups;
  final List<SmartScheduleSuggestion> suggestions;
  final DateTime todayKey;
  final DateTime now;
  final ValueChanged<String> onOpenTodo;
  final ValueChanged<TodoItem> onToggleTodo;
  final VoidCallback onOpenCourses;
  final Future<void> Function(TodoItem todo) onAddToday;

  const _TodayReminderSection({
    required this.groups,
    required this.suggestions,
    required this.todayKey,
    required this.now,
    required this.onOpenTodo,
    required this.onToggleTodo,
    required this.onOpenCourses,
    required this.onAddToday,
  });

  @override
  State<_TodayReminderSection> createState() => _TodayReminderSectionState();
}

class _TodayReminderSectionState extends State<_TodayReminderSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final total =
        widget.groups.dueToday.length +
        widget.groups.upcoming.length +
        widget.groups.overdue.length;
    final subtitle = widget.suggestions.isEmpty
        ? '$total 项 · 今日待提醒 > 即将开始 > 逾期优先处理'
        : '$total 项提醒 · 今日待提醒 > 即将开始 > 逾期优先处理 > 今日建议';
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: AppSurfaceCard(
        key: const ValueKey('today_reminder_section_collapsed_by_default'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: const ValueKey('today_reminder_header_toggle'),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(DesignTokens.radiusCard),
              ),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '今日提醒',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              height: 1.25,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _expanded ? subtitle : '$subtitle · 默认收起',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.56),
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => TodayDetailRouter.open(
                        context,
                        TodaySectionKind.todos,
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: cs.primary,
                        textStyle: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.normal,
                        ),
                        minimumSize: const Size(44, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.padded,
                      ),
                      child: Text(I18n.tr('today.view')),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded && widget.groups.dueToday.isNotEmpty)
              _ReminderGroupBlock(
                title: '今日待提醒事项',
                items: widget.groups.dueToday.take(4).toList(),
                now: widget.now,
                onOpenTodo: widget.onOpenTodo,
                onToggleTodo: widget.onToggleTodo,
                onOpenCourses: widget.onOpenCourses,
              ),
            if (_expanded && widget.groups.upcoming.isNotEmpty)
              _ReminderGroupBlock(
                title: '即将开始事项',
                items: widget.groups.upcoming.take(4).toList(),
                now: widget.now,
                onOpenTodo: widget.onOpenTodo,
                onToggleTodo: widget.onToggleTodo,
                onOpenCourses: widget.onOpenCourses,
              ),
            if (_expanded && widget.groups.overdue.isNotEmpty)
              _ReminderGroupBlock(
                title: '已逾期事项',
                items: widget.groups.overdue.take(4).toList(),
                now: widget.now,
                overdue: true,
                onOpenTodo: widget.onOpenTodo,
                onToggleTodo: widget.onToggleTodo,
                onOpenCourses: widget.onOpenCourses,
              ),
            if (_expanded && widget.suggestions.isNotEmpty)
              _SuggestionSection(
                suggestions: widget.suggestions,
                todayKey: widget.todayKey,
                onOpenTodo: widget.onOpenTodo,
                onAddToday: widget.onAddToday,
              ),
            SizedBox(height: _expanded ? 4 : 8),
          ],
        ),
      ),
    );
  }
}

class _ReminderGroupBlock extends StatelessWidget {
  final String title;
  final List<_TodayReminderItem> items;
  final DateTime now;
  final bool overdue;
  final ValueChanged<String> onOpenTodo;
  final ValueChanged<TodoItem> onToggleTodo;
  final VoidCallback onOpenCourses;

  const _ReminderGroupBlock({
    required this.title,
    required this.items,
    required this.now,
    required this.onOpenTodo,
    required this.onToggleTodo,
    required this.onOpenCourses,
    this.overdue = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = overdue ? cs.error : cs.primary;
    final backgroundColor = overdue
        ? Color.alphaBlend(
            cs.error.withValues(alpha: 0.10),
            cs.surfaceContainerHighest,
          )
        : cs.surfaceContainerHighest.withValues(alpha: 0.28);
    final borderColor = overdue
        ? cs.error.withValues(alpha: 0.38)
        : color.withValues(alpha: 0.1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: overdue ? 0.9 : 0.7),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 2),
              child: Row(
                children: [
                  Icon(
                    overdue
                        ? Icons.warning_amber_outlined
                        : Icons.notifications_none_outlined,
                    size: 16,
                    color: color,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: overdue ? cs.error : cs.onSurface,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  if (overdue) ...[
                    const SizedBox(width: 8),
                    _OverdueReminderBadge(color: cs.error),
                  ],
                  const Spacer(),
                  Text(
                    '${items.length} 项',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            ...items.map(
              (item) => _TodayReminderTile(
                item: item,
                now: now,
                overdue: overdue,
                onOpenTodo: onOpenTodo,
                onToggleTodo: onToggleTodo,
                onOpenCourses: onOpenCourses,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverdueReminderTitle extends StatelessWidget {
  final String title;
  final Color color;

  const _OverdueReminderTitle({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _OverdueReminderBadge(color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}

class _OverdueReminderBadge extends StatelessWidget {
  final Color color;

  const _OverdueReminderBadge({required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 0.7),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.priority_high_rounded, size: 10, color: color),
            const SizedBox(width: 2),
            Text(
              I18n.tr('todo.status.overdue'),
              style: TextStyle(fontSize: 10, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayReminderTile extends StatelessWidget {
  final _TodayReminderItem item;
  final DateTime now;
  final bool overdue;
  final ValueChanged<String> onOpenTodo;
  final ValueChanged<TodoItem> onToggleTodo;
  final VoidCallback onOpenCourses;

  const _TodayReminderTile({
    required this.item,
    required this.now,
    required this.overdue,
    required this.onOpenTodo,
    required this.onToggleTodo,
    required this.onOpenCourses,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final todo = item.todo;
    final isTodo = item.kind == _TodayReminderKind.todo;
    final completed = item.completed || (todo?.isCompleted ?? false);
    final overdueTitleColor = cs.error;
    final overdueSubtitleColor = cs.error.withValues(alpha: 0.86);
    final completedColor = const Color(0xFF4CAF50);
    final completedBackground = Color.alphaBlend(
      completedColor.withValues(alpha: 0.08),
      cs.surface,
    );
    final completedBorder = completedColor.withValues(alpha: 0.22);
    final overdueBackground = Color.alphaBlend(
      cs.error.withValues(alpha: 0.08),
      cs.surface,
    );
    final overdueBorder = cs.error.withValues(alpha: 0.26);
    final accent = item.accentColor ?? (overdue ? cs.error : cs.primary);
    final title = overdue
        ? _OverdueReminderTitle(title: item.title, color: overdueTitleColor)
        : Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: completed ? completedColor : cs.onSurface,
              decoration: completed ? TextDecoration.lineThrough : null,
            ),
          );
    if (isTodo && todo != null) {
      return _TodayTodoSwipeTile(
        todo: todo,
        onToggle: () => onToggleTodo(todo),
        onOpen: () => onOpenTodo(item.id),
        leading: _TodayTodoLeading(
          statusColor: overdue
              ? cs.error
              : completed
              ? completedColor
              : _todoTemplateVisual(context, todo).color,
          isCompleted: completed,
          completedCheckColor: overdue ? cs.onError : cs.onTertiary,
          onChanged: (_) => onToggleTodo(todo),
        ),
        title: item.title,
        titleColor: overdue
            ? overdueTitleColor
            : completed
            ? completedColor
            : null,
        iconKeyPrefix: 'today_reminder_template_icon',
        showOverdueBadge: overdue,
        subtitle: Text(
          overdue
              ? '${item.subtitle} · ${_pastStatusLabel(item, now)}'
              : item.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: overdue
                ? overdueSubtitleColor
                : completed
                ? completedColor.withValues(alpha: 0.82)
                : cs.onSurfaceVariant,
          ),
        ),
        trailing: Text(
          I18nDateFormat.time(item.time),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: overdue
                ? overdueTitleColor
                : completed
                ? completedColor
                : cs.onSurfaceVariant,
          ),
        ),
        completedTextColor: overdue
            ? overdueTitleColor
            : completed
            ? completedColor
            : null,
        tileBackground: overdue
            ? overdueBackground
            : completed
            ? completedBackground
            : null,
        tileBorderColor: overdue
            ? overdueBorder
            : completed
            ? completedBorder
            : null,
        showStatusDecoration: true,
      );
    }
    Widget tile = ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: const SizedBox(width: 4),
      minLeadingWidth: 4,
      horizontalTitleGap: 4,
      title: Row(
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: accent.withValues(alpha: overdue ? 0.18 : 0.14),
            child: Icon(Icons.menu_book_outlined, size: 12, color: accent),
          ),
          const SizedBox(width: 7),
          Expanded(child: title),
        ],
      ),
      subtitle: Text(
        overdue
            ? '${item.subtitle} · ${_pastStatusLabel(item, now)}'
            : item.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: overdue
              ? overdueSubtitleColor
              : completed
              ? completedColor.withValues(alpha: 0.82)
              : cs.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        I18nDateFormat.time(item.time),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: overdue
              ? overdueTitleColor
              : completed
              ? completedColor
              : cs.onSurfaceVariant,
        ),
      ),
      onTap: onOpenCourses,
    );
    if (overdue && !isTodo) {
      tile = Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: overdueBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: overdueBorder, width: 0.7),
        ),
        child: tile,
      );
    }
    return tile;
  }

  String _pastStatusLabel(_TodayReminderItem item, DateTime now) {
    final trigger = item.time;
    final triggerDay = DateTime(trigger.year, trigger.month, trigger.day);
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(triggerDay).inDays;
    if (days <= 0) {
      final minutes = now.difference(trigger).inMinutes.clamp(1, 999);
      return item.kind == _TodayReminderKind.course
          ? '已过期 $minutes 分钟'
          : '已过提醒 $minutes 分钟';
    }
    return '已逾期 $days 天';
  }
}

class _SuggestionSection extends StatefulWidget {
  final List<SmartScheduleSuggestion> suggestions;
  final DateTime todayKey;
  final ValueChanged<String> onOpenTodo;
  final Future<void> Function(TodoItem todo) onAddToday;

  const _SuggestionSection({
    required this.suggestions,
    required this.todayKey,
    required this.onOpenTodo,
    required this.onAddToday,
  });

  @override
  State<_SuggestionSection> createState() => _SuggestionSectionState();
}

class _SuggestionSectionState extends State<_SuggestionSection> {
  final Set<String> _addingTodoIds = <String>{};

  Future<void> _addToday(TodoItem todo) async {
    if (_addingTodoIds.contains(todo.id)) return;
    setState(() => _addingTodoIds.add(todo.id));
    try {
      await widget.onAddToday(todo);
    } finally {
      if (mounted) setState(() => _addingTodoIds.remove(todo.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        maintainState: true,
        tilePadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
        childrenPadding: const EdgeInsets.only(bottom: 4),
        leading: Icon(
          Icons.auto_awesome,
          size: 18,
          color: cs.primary.withValues(alpha: 0.72),
        ),
        title: Text(
          I18n.tr('today.suggestions'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.normal,
          ),
        ),
        subtitle: Text(
          '${I18n.tr('today.suggestions.subtitle')} · 默认收起',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.58),
          ),
        ),
        children: widget.suggestions.map((suggestion) {
          final t = suggestion.todo;
          final adding = _addingTodoIds.contains(t.id);
          return _TodayTodoSwipeTile(
            todo: t,
            onToggle: () {},
            onOpen: () => widget.onOpenTodo(t.id),
            title: t.title,
            titleColor: cs.onSurface.withValues(alpha: 0.76),
            iconKeyPrefix: 'today_suggestion_template_icon',
            subtitle: Text(
              suggestion.reason,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
            trailing:
                _sameDay(t.date, widget.todayKey) || t.isArchivedAfterRollover
                ? null
                : SizedBox(
                    width: MediaQuery.sizeOf(context).width < 360 ? 72 : 88,
                    height: 40,
                    child: TextButton(
                      key: ValueKey('today_suggestion_add_${t.id}'),
                      onPressed: adding ? null : () => _addToday(t),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(56, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.padded,
                      ),
                      child: adding
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                I18n.tr('today.add_to_today'),
                                maxLines: 1,
                              ),
                            ),
                    ),
                  ),
          );
        }).toList(),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _QuoteCardState extends State<_QuoteCard> {
  late String _text;

  @override
  void initState() {
    super.initState();
    _text = DailyQuotes.today();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = Theme.of(context).colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return AppSurfaceCard(
      onTap: () => setState(() => _text = DailyQuotes.random()),
      borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
      padding: const EdgeInsets.all(14),
      gradient: LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Color.alphaBlend(
            cs.secondary.withValues(alpha: isDark ? 0.08 : 0.04),
            cs.surface,
          ),
          cs.surface,
        ],
      ),
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: isDark ? 0.14 : 0.18),
        width: 0.55,
      ),
      elevation: 1,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.12),
                width: 0.45,
              ),
            ),
            child: Icon(
              Icons.format_quote,
              color: cs.primary.withValues(alpha: 0.7),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1.55),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.36),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.refresh,
              size: 15,
              color: cs.onSurface.withValues(alpha: 0.48),
            ),
          ),
        ],
      ),
    );
  }
}
