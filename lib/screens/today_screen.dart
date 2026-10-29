import 'dart:math' as math;
import '../widgets/app_page_tabs.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_clock.dart';
import '../core/app_motion.dart';
import '../models/pomodoro.dart';
import '../core/completion_visibility_policy.dart';
import '../core/design_tokens.dart';
import '../core/home_page_style.dart';
import '../core/goal_icons.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/lunar_calendar.dart';
import '../core/quotes.dart';
import '../core/smart_schedule_advisor.dart';
import '../core/todo_templates.dart';
import '../core/todo_quadrant_style.dart';
import '../models/course_schedule.dart' show CourseItem, ScheduleSettings;
import '../models/todo.dart';
import '../providers/anniversary_provider.dart';
import '../providers/course_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/share_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/todo_provider.dart';
import '../providers/user_provider.dart';
import '../widgets/apple_page_frame.dart';
import '../widgets/brand_background.dart';
import '../widgets/surface_components.dart';
import '../widgets/todo_completion_flow.dart';
import 'habit_screen.dart';
import '../widgets/quick_capture_fab.dart';
import 'almanac_screen.dart';
import 'goal_edit_screen.dart';
import 'pomodoro_screen.dart';
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

/// 首页：默认先看今日待办，通过顶部标签切换到目标。
class TodayScreen extends StatelessWidget {
  final bool showCaptureFab;

  const TodayScreen({super.key, this.showCaptureFab = false});

  @override
  Widget build(BuildContext context) =>
      ScaffoldMessenger(child: Builder(builder: _buildHome));

  Widget _buildHome(BuildContext context) {
    AppClock.watch(context);
    final themeProvider = context.watch<ThemeProvider>();
    final s = themeProvider.brand.strings;
    final theme = Theme.of(context);
    final home = HomePageStyle.of(context);

    final todoP = context.watch<TodoProvider>();
    final habitP = context.watch<HabitProvider>();
    context.select<PomodoroProvider, int>(
      (provider) => provider.persistedRevision,
    );
    final todayFocusMinutes =
        context
            .read<PomodoroProvider>()
            .sessions
            .where(
              (session) =>
                  session.type == PomodoroType.focus &&
                  AppClock.dateOnly(AppClock.toLocal(session.endTime)) ==
                      AppClock.today(),
            )
            .fold<int>(0, (sum, session) => sum + session.durationSeconds) ~/
        60;
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

    final activeGoals = goalP.activeGoals;
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

    final metricsContent = Wrap(
      key: const ValueKey('today_metrics_summary'),
      spacing: DesignTokens.spaceXxl,
      runSpacing: DesignTokens.spaceXs,
      alignment: WrapAlignment.spaceBetween,
      children: [
        _TodayMetricLink(
          label: s.navTodo,
          value: '$todayTodosCount',
          unit: I18n.tr('today.unit.item'),
          icon: Icons.check_circle_outline,
          onTap: () => _go(context, const TodoScreen()),
        ),
        _TodayMetricLink(
          label: s.navHabit,
          value: '${(todayHabitProgress * 100).round()}',
          unit: '%',
          icon: Icons.repeat,
          onTap: () => _go(context, const HabitScreen()),
        ),
        _TodayMetricLink(
          label: s.navFocus,
          value: '$todayFocusMinutes',
          unit: I18n.tr('unit.min'),
          icon: Icons.timer_outlined,
          onTap: () =>
              _go(context, const PomodoroScreen(useShellBackground: true)),
        ),
      ],
    );
    // 默认主题：指标并入同一内容列的一张轻量组面；其他主题保留旧的内外边距。
    final metrics = usesApplePageLayout(context)
        ? AppleGroup(
            margin: const EdgeInsets.only(bottom: ApplePageFrame.sectionGap),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: metricsContent,
          )
        : Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceMd,
              vertical: DesignTokens.spaceSm,
            ),
            child: metricsContent,
          );

    Widget todosSection({int maxItems = 6}) {
      return _section(
        context,
        I18n.tr(
          'today.todos.summary',
        ).replaceAll('{count}', '$todayTodosCount'),
        headerKey: const ValueKey('today_todos_header'),
        actionLabel: I18n.tr('today.all_todos'),
        subtitle: completedTodayCount == 0
            ? null
            : '${I18n.tr('today.completed')} $completedTodayCount',
        onMore: () => TodayDetailRouter.open(context, TodaySectionKind.todos),
        // 默认主题：今日待办拆成组面内的扁平行（细分隔线分列）。
        flatChildren: todayTodos.isEmpty
            ? null
            : <Widget>[
                for (final t in todayTodos.take(maxItems))
                  _TodayTodoSwipeTile(
                    key: ValueKey('today_todo_row_${t.id}'),
                    todo: t,
                    flat: true,
                    onToggle: () =>
                        completeTodoWithOptionalTimeRecord(context, t),
                    onOpen: () => TodayDetailRouter.open(
                      context,
                      TodaySectionKind.todos,
                      id: t.id,
                    ),
                  ),
              ],
        child: todayTodos.isEmpty
            ? _TodayTodoEmptyState(
                onTap: () =>
                    TodayDetailRouter.open(context, TodaySectionKind.todos),
              )
            : Column(
                children: [
                  for (final t in todayTodos.take(maxItems)) ...[
                    _TodayTodoSwipeTile(
                      key: ValueKey('today_todo_row_${t.id}'),
                      todo: t,
                      flat: true,
                      onToggle: () =>
                          completeTodoWithOptionalTimeRecord(context, t),
                      onOpen: () => TodayDetailRouter.open(
                        context,
                        TodaySectionKind.todos,
                        id: t.id,
                      ),
                    ),
                    const _TodayListDivider(),
                  ],
                ],
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
        context,
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
                    fontWeight: DesignTokens.fontWeightStrong,
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
        context,
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
                    fontWeight: DesignTokens.fontWeightStrong,
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
      final theme = Theme.of(context);
      return _section(
        context,
        I18n.tr(
          'today.goals.summary',
        ).replaceAll('{count}', '${activeGoals.length}'),
        headerKey: const ValueKey('today_goals_header'),
        actionLabel: activeGoals.isEmpty
            ? I18n.tr('goal.new')
            : I18n.tr('today.all_goals'),
        onMore: () => activeGoals.isEmpty
            ? showGoalCreateSheet(context)
            : TodayDetailRouter.open(context, TodaySectionKind.goals),
        child: activeGoals.isEmpty
            ? _TodaySectionEmptyState(
                icon: Icons.flag_circle_outlined,
                title: I18n.tr('goal.new'),
                subtitle: I18n.tr('today.goal.create.subtitle'),
                onTap: () => showGoalCreateSheet(context),
              )
            : Column(
                children: activeGoals.map((g) {
                  final p = g.computedProgress;
                  return Column(
                    children: [
                      ListTile(
                        key: ValueKey('today_goal_${g.id}'),
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: DesignTokens.spaceMd,
                        ),
                        minLeadingWidth: DesignTokens.controlMinHeight,
                        horizontalTitleGap:
                            DesignTokens.homeItemLeadingGap +
                            DesignTokens.spaceXs,
                        leading: SizedBox.square(
                          dimension: DesignTokens.controlMinHeight,
                          child: Icon(
                            goalIconFromName(g.icon),
                            color: Color(g.colorValue),
                            size: DesignTokens.controlIconSize,
                          ),
                        ),
                        title: Text(
                          g.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: home.typography(
                            theme,
                            size: DesignTokens.homeTaskTitleSize,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(
                            top: DesignTokens.spaceSm,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    DesignTokens.radiusXs,
                                  ),
                                  child: LinearProgressIndicator(
                                    value: p,
                                    minHeight: DesignTokens.spaceXs,
                                    color: Color(g.colorValue),
                                    backgroundColor: Color(
                                      g.colorValue,
                                    ).withValues(alpha: 0.15),
                                  ),
                                ),
                              ),
                              const SizedBox(width: DesignTokens.spaceMd),
                              Text(
                                '${(p * 100).toStringAsFixed(0)}%',
                                style: home.typography(
                                  theme,
                                  size: DesignTokens.homeCaptionSize,
                                  color: home.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        onTap: () => TodayDetailRouter.open(
                          context,
                          TodaySectionKind.goals,
                          id: g.id,
                        ),
                      ),
                      const _TodayListDivider(),
                    ],
                  );
                }).toList(),
              ),
      );
    }

    final showHomeCalendar = context.select<PreferencesProvider, bool>(
      (preferences) => preferences.showHomeCalendar,
    );
    final reminder = reminderSection();
    final courses = coursesSection();
    final anniversaries = anniversariesSection();
    final isDesktopLayout = MediaQuery.sizeOf(context).width >= 1100;

    final appleLayout = usesApplePageLayout(context);

    Widget homePage({required String id, required List<Widget> children}) {
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: DesignTokens.homeContentMaxWidth,
          ),
          // 默认主题：统一 16 内容列 + 页头/页尾留白；其他主题维持既有边距。
          child: ApplePageFrame(
            horizontalInset: appleLayout ? ApplePageFrame.gutter : 0,
            maxWidth: double.infinity,
            child: ListView(
              key: ValueKey(id),
              restorationId: id,
              padding: EdgeInsets.fromLTRB(
                appleLayout ? 0 : DesignTokens.spaceMd,
                appleLayout ? ApplePageFrame.pageTop : DesignTokens.spaceXs,
                appleLayout ? 0 : DesignTokens.spaceMd,
                (appleLayout
                        ? ApplePageFrame.pageBottom
                        : DesignTokens.space5xl) +
                    DesignTokens.spaceXxl,
              ),
              children: children,
            ),
          ),
        ),
      );
    }

    final scaler = MediaQuery.textScalerOf(context);
    final tabHeight = AppPageTabs.heightFor(context);
    // Apple 页头与现有页面标题共用 18 号基线，额外留白由页头组件负责。
    final toolbarTitleSize = DesignTokens.homeHeadingSize;
    final toolbarHeight =
        DesignTokens.homeTopInset +
        scaler.scale(toolbarTitleSize) * 1.5 +
        DesignTokens.spaceXs +
        scaler.scale(DesignTokens.homeCaptionSize) * 1.5;
    Widget homeTab({
      required Key key,
      required String text,
      required int count,
    }) => Tab(
      key: key,
      height: tabHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(text),
          const SizedBox(width: DesignTokens.spaceSm - DesignTokens.spaceXxs),
          Opacity(
            opacity: 0.7,
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: DesignTokens.homeCounterSize,
                fontWeight: DesignTokens.fontWeightStrong,
              ),
            ),
          ),
        ],
      ),
    );
    final todayTabs = AppPageTabs(
      barKey: const ValueKey('today_home_tabs'),
      height: tabHeight,
      padding: EdgeInsets.zero,
      tabs: [
        homeTab(
          key: const ValueKey('today_todos_tab'),
          text: I18n.tr('today.todos'),
          count: todayTodosCount,
        ),
        homeTab(
          key: const ValueKey('today_goals_tab'),
          text: I18n.tr('today.tab.goals'),
          count: activeGoals.length,
        ),
      ],
    );
    final todayPages = <Widget>[
      homePage(
        id: 'today_screen_list',
        children: [
          todosSection(maxItems: isDesktopLayout ? 8 : 6),
          metrics,
          ?reminder,
          ?courses,
          ?anniversaries,
          if (showHomeCalendar) ...[
            AppleGroup(
              margin: EdgeInsets.only(
                bottom: appleLayout ? ApplePageFrame.sectionGap : 0,
              ),
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
              child: almanacCard,
            ),
            if (!appleLayout) const SizedBox(height: DesignTokens.spaceMd),
          ],
          _QuoteCard(),
        ],
      ),
      homePage(id: 'today_goals_list', children: [goalsSection()]),
    ];
    final todayFab = showCaptureFab
        ? Builder(
            builder: (context) {
              final controller = DefaultTabController.of(context);
              return AnimatedBuilder(
                animation: controller,
                builder: (context, _) => QuickCaptureFab(
                  key: ValueKey(controller.index),
                  label: controller.index == 0
                      ? (home.usesReferencePalette
                            ? I18n.tr('today.new_todo')
                            : s.todoCreateTitle)
                      : I18n.tr('today.new_goal'),
                  onCreate: controller.index == 0
                      ? null
                      : () => showGoalCreateSheet(context),
                ),
              );
            },
          )
        : null;

    // 默认主题：没有 AppBar，页头 / 页签 / 内容都在同一条页面内容流里。
    if (appleLayout) {
      return DefaultTabController(
        length: 2,
        initialIndex: 0,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesignTokens.homeContentMaxWidth,
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        ApplePageFrame.gutter,
                        DesignTokens.homeTopInset,
                        ApplePageFrame.gutter,
                        0,
                      ),
                      child: ApplePageHeader(
                        title: greeting,
                        subtitle: I18nDateFormat.homeHeader(now),
                        titleKey: const ValueKey('home_greeting'),
                        subtitleKey: const ValueKey('home_date'),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        ApplePageFrame.gutter,
                        DesignTokens.spaceSm,
                        ApplePageFrame.gutter,
                        DesignTokens.spaceXs,
                      ),
                      child: todayTabs,
                    ),
                    Expanded(child: TabBarView(children: todayPages)),
                  ],
                ),
              ),
            ),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          floatingActionButton: todayFab,
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      initialIndex: 0,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          centerTitle: false,
          titleSpacing: 0,
          toolbarHeight: toolbarHeight,
          title: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DesignTokens.homeContentMaxWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.spaceXxl,
                  DesignTokens.homeTopInset,
                  DesignTokens.spaceXxl,
                  0,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        greeting,
                        key: const ValueKey('home_greeting'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: home.typography(
                          theme,
                          size: DesignTokens.homeHeadingSize,
                        ),
                      ),
                      const SizedBox(height: DesignTokens.spaceXs),
                      Text(
                        I18nDateFormat.homeHeader(now),
                        key: const ValueKey('home_date'),
                        style: home.typography(
                          theme,
                          size: DesignTokens.homeCaptionSize,
                          color: home.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(
              tabHeight + DesignTokens.spaceMd + 1,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesignTokens.homeContentMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spaceMd,
                    DesignTokens.spaceMd + 1,
                    DesignTokens.spaceMd,
                    0,
                  ),
                  child: AppPageTabs(
                    barKey: const ValueKey('today_home_tabs'),
                    height: tabHeight,
                    padding: EdgeInsets.zero,
                    tabs: [
                      homeTab(
                        key: const ValueKey('today_todos_tab'),
                        text: I18n.tr('today.todos'),
                        count: todayTodosCount,
                      ),
                      homeTab(
                        key: const ValueKey('today_goals_tab'),
                        text: I18n.tr('today.tab.goals'),
                        count: activeGoals.length,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        body: TabBarView(children: todayPages),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: todayFab,
      ),
    );
  }

  Widget _section(
    BuildContext context,
    String title, {
    String? subtitle,
    required Widget child,
    List<Widget>? flatChildren,
    VoidCallback? onMore,
    String? actionLabel,
    Key? headerKey,
  }) {
    final theme = Theme.of(context);
    final home = HomePageStyle.of(context);
    final headerStyle = home.typography(
      theme,
      size: DesignTokens.homeCaptionSize,
      color: home.muted,
    );
    final apple = usesApplePageLayout(context);
    return Padding(
      // 默认主题：组与组之间固定 16 间距（页头 + 组面），其他主题维持零外距。
      padding: EdgeInsets.only(bottom: apple ? ApplePageFrame.sectionGap : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppleSectionHeader(
            headerKey: headerKey,
            title: title,
            subtitle: subtitle,
            titleStyle: headerStyle,
            subtitleStyle: headerStyle,
            actionTextStyle: headerStyle,
            actionColor: home.muted,
            actionLabel: onMore == null
                ? null
                : (actionLabel ?? I18n.tr('today.view')),
            onAction: onMore,
            padding: apple
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: DesignTokens.spaceMd),
          ),
          // 默认主题：内容进一张白组面；可拆成扁平行时用细分隔线分列，
          // 其他主题原样返回旧内容。
          apple
              ? AppleGroupedList(children: flatChildren ?? <Widget>[child])
              : child,
        ],
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

class _TodayListDivider extends StatelessWidget {
  const _TodayListDivider();

  @override
  Widget build(BuildContext context) {
    // 默认主题：分隔线在组面内部不再叠加页边距；其他主题维持既有 12 缩进。
    final horizontalInset = usesApplePageLayout(context)
        ? 0.0
        : DesignTokens.spaceMd;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalInset),
      child: Divider(
        height: 1,
        thickness: 0.5,
        color: HomePageStyle.of(context).divider,
      ),
    );
  }
}

class _TodayMetricLink extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final VoidCallback onTap;

  const _TodayMetricLink({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final home = HomePageStyle.of(context);
    final style = home.typography(
      theme,
      size: DesignTokens.homeCaptionSize,
      color: home.muted,
    );
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: DesignTokens.borderRadiusSm,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: DesignTokens.controlMinHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceSm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: DesignTokens.fontSizeBody, color: home.muted),
                const SizedBox(width: DesignTokens.spaceXs),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(label, style: style),
                    const SizedBox(width: DesignTokens.spaceXs),
                    Text(
                      unit == '%' ? '$value$unit' : '$value $unit',
                      style: style.copyWith(color: home.text),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
                                    fontWeight: DesignTokens.fontWeightStrong,
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
    final textScaler = MediaQuery.textScalerOf(context);
    final extraTextHeight =
        math.max(0.0, textScaler.scale(11) - 11) +
        math.max(0.0, textScaler.scale(10) - 10);
    return Container(
      width: 68,
      height: 76 + extraTextHeight,
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
                fontWeight: DesignTokens.fontWeightStrong,
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
                        fontWeight: DesignTokens.fontWeightStrong,
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
            fontWeight: DesignTokens.fontWeightStrong,
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
                fontWeight: DesignTokens.fontWeightStrong,
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

class _QuoteCard extends StatefulWidget {
  @override
  State<_QuoteCard> createState() => _QuoteCardState();
}

class _TodayTodoEmptyState extends StatelessWidget {
  final VoidCallback onTap;

  const _TodayTodoEmptyState({required this.onTap});

  @override
  Widget build(BuildContext context) => _TodaySectionEmptyState(
    icon: Icons.checklist_rtl_outlined,
    title: I18n.tr('today.todos.empty'),
    onTap: onTap,
  );
}

/// 今日分区共用轻量空状态，保持与条目相同的图标和文本起点。
class _TodaySectionEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _TodaySectionEmptyState({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: DesignTokens.borderRadiusSm,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceXxl),
          child: Row(
            children: [
              SizedBox.square(
                dimension: DesignTokens.controlMinHeight,
                child: Icon(
                  icon,
                  size: DesignTokens.controlIconSize,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: DesignTokens.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: HomePageStyle.of(
                        context,
                      ).typography(theme, size: DesignTokens.fontSizeBody),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: DesignTokens.spaceXs),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: HomePageStyle.of(context).typography(
                          theme,
                          size: DesignTokens.homeCaptionSize,
                          color: HomePageStyle.of(context).muted,
                        ),
                      ),
                    ],
                  ],
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
  final bool textOnly;

  const _TodoTodaySubtitle({required this.todo, this.textOnly = false});

  @override
  Widget build(BuildContext context) {
    final visual = CompletionVisibilityPolicy.visualState(todo);
    final subtasks = todo.subtasks;
    final hasNoDueDate = todo.dueDate == null;
    if (todo.listGroupName == null &&
        subtasks.isEmpty &&
        visual == TodoVisualState.normal &&
        !hasNoDueDate) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(
        top: textOnly ? DesignTokens.spaceXs + 1 : DesignTokens.spaceXxs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: DesignTokens.spaceSm,
            runSpacing: DesignTokens.spaceXs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (todo.listGroupName != null)
                _TodoListTemplateLabel(todo: todo, textOnly: textOnly),
              if (textOnly && todo.listGroupName != null && hasNoDueDate)
                Text(
                  '·',
                  style: HomePageStyle.of(context).typography(
                    Theme.of(context),
                    size: DesignTokens.homeCaptionSize,
                    color: HomePageStyle.of(context).muted,
                  ),
                ),
              if (hasNoDueDate) const _TodayNoDueDateLabel(),
              if (visual != TodoVisualState.normal)
                _TodayTodoStatusPill(visual: visual),
            ],
          ),
          if (subtasks.isNotEmpty) const SizedBox(height: DesignTokens.spaceXs),
          for (final subtask in subtasks)
            _TodaySubtaskRow(todo: todo, subtask: subtask),
        ],
      ),
    );
  }
}

/// 今日页子任务行：整行可点，勾选后立即写回，父任务按 autoToggle 规则聚合。
class _TodaySubtaskRow extends StatefulWidget {
  final TodoItem todo;
  final Subtask subtask;

  const _TodaySubtaskRow({required this.todo, required this.subtask});

  @override
  State<_TodaySubtaskRow> createState() => _TodaySubtaskRowState();
}

class _TodaySubtaskRowState extends State<_TodaySubtaskRow> {
  /// 12px 文字 + 18px 勾选圈 + 纵向留白，整行宽度都可点。
  static const double _minRowHeight = 36;

  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    final shares = context.read<ShareProvider?>();
    if (!(shares?.canEdit(widget.todo.workspaceId) ?? true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(I18n.tr('today.subtask.read_only')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final provider = context.read<TodoProvider>();
      final current = provider.todos.firstWhere(
        (item) => item.id == widget.todo.id,
        orElse: () => widget.todo,
      );
      final next = current.copyWith(
        subtasks: [
          for (final item in current.subtasks)
            item.id == widget.subtask.id
                ? Subtask(
                    id: item.id,
                    title: item.title,
                    isCompleted: !item.isCompleted,
                    sortOrder: item.sortOrder,
                  )
                : item,
        ],
      );
      // 沿用默认的提醒同步：今日页不允许跳过同步（静态 guard 亦强制）。
      await provider.updateTodo(current.id, next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(I18n.tr('today.subtask.update_failed')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final completed = widget.subtask.isCompleted;
    return Semantics(
      button: true,
      checked: completed,
      label: widget.subtask.title,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('today_subtask_toggle_${widget.subtask.id}'),
        onTap: _busy ? null : _toggle,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minRowHeight),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: _busy
                    ? const Padding(
                        padding: EdgeInsets.all(2),
                        child: CircularProgressIndicator(strokeWidth: 1.6),
                      )
                    : AnimatedSwitcher(
                        duration: AppMotion.feedback(context),
                        switchInCurve: AppMotion.enterCurve,
                        switchOutCurve: AppMotion.exitCurve,
                        child: Icon(
                          completed
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          key: ValueKey('today_subtask_icon_$completed'),
                          size: 16,
                          color: completed ? cs.primary : cs.onSurfaceVariant,
                        ),
                      ),
              ),
              const SizedBox(width: DesignTokens.spaceSm),
              Expanded(
                child: Text(
                  widget.subtask.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: completed
                        ? cs.onSurfaceVariant.withValues(alpha: 0.55)
                        : cs.onSurfaceVariant,
                    decoration: completed ? TextDecoration.lineThrough : null,
                    decorationColor: cs.onSurfaceVariant,
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

class _TodayNoDueDateLabel extends StatelessWidget {
  const _TodayNoDueDateLabel();

  @override
  Widget build(BuildContext context) {
    final home = HomePageStyle.of(context);
    return Text(
      I18n.tr('today.no_due_date'),
      style: home.typography(
        Theme.of(context),
        size: DesignTokens.homeCaptionSize,
        color: home.muted,
      ),
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

Color _todoQuadrantColor(EisenhowerQuadrant quadrant) =>
    todoQuadrantColor(quadrant);

class _TodoListTemplateLabel extends StatelessWidget {
  final TodoItem todo;
  final bool textOnly;

  const _TodoListTemplateLabel({required this.todo, this.textOnly = false});

  @override
  Widget build(BuildContext context) {
    final label = todo.listGroupName?.trim();
    if (label == null || label.isEmpty) return const SizedBox.shrink();
    final template = _todoListTemplateFor(label);
    final cs = Theme.of(context).colorScheme;
    final color = template?.color ?? cs.onSurfaceVariant;
    if (textOnly) {
      final home = HomePageStyle.of(context);
      return Text(
        label,
        key: ValueKey('today_todo_list_icon_${template?.name ?? 'custom'}'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: home.typography(
          Theme.of(context),
          size: DesignTokens.homeCaptionSize,
          color: home.category,
        ),
      );
    }
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

/// 有子任务时替代整任务勾选：显示已完成/总数，完成只能通过子任务。
class _TodaySubtaskProgress extends StatelessWidget {
  final TodoItem todo;

  const _TodaySubtaskProgress({required this.todo});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final done = todo.subtasks.where((subtask) => subtask.isCompleted).length;
    final total = todo.subtasks.length;
    final completed = total > 0 && done == total;
    return SizedBox(
      width: _TodayTodoLeading.width,
      height: _TodayTodoLeading.height,
      child: Center(
        child: Text(
          '$done/$total',
          key: ValueKey('today_subtask_progress_${todo.id}'),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 11,
            color: completed ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
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
  final bool neutral;

  const _TodayTodoLeading({
    required this.statusColor,
    required this.isCompleted,
    required this.completedCheckColor,
    required this.onChanged,
    this.neutral = false,
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
          neutral: neutral,
        ),
      ),
    );
  }
}

class _TodayTodoQuadrantDot extends StatelessWidget {
  final TodoItem todo;

  const _TodayTodoQuadrantDot({required this.todo});

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<ThemeProvider>().brand.strings;
    final label = switch (todo.quadrant) {
      EisenhowerQuadrant.urgentImportant => strings.quadrantQ1Label,
      EisenhowerQuadrant.notUrgentImportant => strings.quadrantQ2Label,
      EisenhowerQuadrant.urgentNotImportant => strings.quadrantQ3Label,
      EisenhowerQuadrant.notUrgentNotImportant => strings.quadrantQ4Label,
    };
    return Tooltip(
      message: '$label (Q${todo.quadrant.index + 1})',
      child: Container(
        key: ValueKey('today_todo_quadrant_dot_${todo.id}'),
        width: DesignTokens.homeQuadrantDotSize,
        height: DesignTokens.homeQuadrantDotSize,
        decoration: BoxDecoration(
          color: _todoQuadrantColor(todo.quadrant),
          shape: BoxShape.circle,
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
  final bool showTemplateIcon;

  const _TodayTodoTitleLine({
    required this.todo,
    required this.title,
    required this.completed,
    required this.overdue,
    required this.iconKeyPrefix,
    this.titleColor,
    this.showTemplateIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = titleColor ?? (overdue ? cs.error : cs.onSurface);
    return Row(
      children: [
        if (showTemplateIcon) ...[
          _TodoTemplateAvatar(
            todo: todo,
            keyPrefix: iconKeyPrefix,
            radius: 10,
            iconSize: 12,
          ),
          const SizedBox(width: DesignTokens.spaceSm),
        ],
        _TodayTodoQuadrantDot(todo: todo),
        const SizedBox(width: DesignTokens.homeQuadrantTitleGap),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: effectiveColor,
              fontSize: showTemplateIcon
                  ? DesignTokens.fontSizeBody
                  : DesignTokens.homeTaskTitleSize,
              decoration: completed ? TextDecoration.lineThrough : null,
              fontWeight: DesignTokens.fontWeightStrong,
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
  final bool neutral;

  const _TodayTodoStatusToggle({
    required this.color,
    required this.isCompleted,
    required this.completedCheckColor,
    required this.onChanged,
    this.neutral = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = color ?? cs.primary;
    final background = isCompleted
        ? accent
        : neutral
        ? Colors.transparent
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
                width: neutral
                    ? DesignTokens.homeStatusSize
                    : _TodayTodoLeading.statusButtonSize,
                height: neutral
                    ? DesignTokens.homeStatusSize
                    : _TodayTodoLeading.statusButtonSize,
                decoration: ShapeDecoration(
                  color: background,
                  shape: CircleBorder(
                    side: BorderSide(
                      color: neutral && !isCompleted
                          ? HomePageStyle.of(
                              context,
                            ).muted.withValues(alpha: 0.38)
                          : accent.withValues(alpha: isCompleted ? 0.24 : 0.34),
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
  final bool flat;

  const _TodayTodoSwipeTile({
    super.key,
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
    this.flat = false,
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
      color: widget.flat && _swipeActive
          ? Theme.of(context).scaffoldBackgroundColor
          : Colors.transparent,
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        key: ValueKey('today_todo_${todo.id}'),
        contentPadding: widget.flat
            ? const EdgeInsets.symmetric(vertical: DesignTokens.spaceMd)
            : EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
        horizontalTitleGap:
            DesignTokens.homeItemLeadingGap + DesignTokens.spaceXs,
        minLeadingWidth: widget.leading == null ? _TodayTodoLeading.width : 30,
        leading:
            widget.leading ??
            // 有子任务时完成态由子任务决定：不再提供整任务勾选，改为显示进度。
            (todo.subtasks.isEmpty
                ? _TodayTodoLeading(
                    statusColor: widget.flat && visual == TodoVisualState.normal
                        ? cs.primary
                        : statusColor,
                    isCompleted: isCompleted,
                    completedCheckColor: cs.onTertiary,
                    onChanged: canEdit
                        ? (_) => widget.onToggle()
                        : (_) => _showReadOnlyMessage('完成任务'),
                  )
                : _TodaySubtaskProgress(todo: todo)),
        title: _TodayTodoTitleLine(
          todo: todo,
          title: widget.title ?? todo.title,
          titleColor: effectiveTitleColor,
          completed: todo.isCompleted,
          overdue: widget.showOverdueBadge || isOverdue,
          iconKeyPrefix: widget.iconKeyPrefix,
          showTemplateIcon: !widget.flat,
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
    if (widget.flat) {
      final home = HomePageStyle.of(context);
      tile = Material(
        color: _swipeActive
            ? Theme.of(context).scaffoldBackgroundColor
            : Colors.transparent,
        child: InkWell(
          key: ValueKey('today_todo_${todo.id}'),
          onTap: _swipeOpen ? _closeSwipe : widget.onOpen,
          child: Padding(
            padding: const EdgeInsets.only(
              top: DesignTokens.spaceLg,
              bottom: DesignTokens.spaceXl,
            ),
            child: Row(
              children: [
                // 平板/扁平布局同样遵守“有子任务则显示进度”。
                todo.subtasks.isEmpty
                    ? _TodayTodoLeading(
                        neutral: true,
                        statusColor: visual == TodoVisualState.normal
                            ? home.accent
                            : statusColor,
                        isCompleted: isCompleted,
                        completedCheckColor: cs.onPrimary,
                        onChanged: canEdit
                            ? (_) => widget.onToggle()
                            : (_) => _showReadOnlyMessage('完成任务'),
                      )
                    : _TodaySubtaskProgress(todo: todo),
                const SizedBox(width: DesignTokens.homeItemLeadingGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Text(
                            widget.title ?? todo.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: home.typography(
                              Theme.of(context),
                              size: DesignTokens.homeTaskTitleSize,
                              color: effectiveTitleColor ?? home.text,
                            ),
                          ),
                          Positioned(
                            left:
                                -(DesignTokens.homeQuadrantDotSize +
                                    DesignTokens.homeQuadrantTitleGap),
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: _TodayTodoQuadrantDot(todo: todo),
                            ),
                          ),
                        ],
                      ),
                      widget.subtitle ??
                          _TodoTodaySubtitle(todo: todo, textOnly: true),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  key: ValueKey('today_task_menu_${todo.id}'),
                  tooltip: I18n.tr('today.task.actions'),
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.more_horiz,
                    size: DesignTokens.fontSizeLg,
                    color: home.subtle,
                  ),
                  onSelected: (action) async {
                    if (action == 'open') {
                      widget.onOpen();
                    } else if (canEdit) {
                      await _confirmDelete(context);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'open',
                      child: Text(I18n.tr('today.view')),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      enabled: canEdit,
                      child: Text(I18n.tr('action.delete')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (!widget.flat &&
        (effectiveTileBackground != null || effectiveTileBorderColor != null)) {
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
            duration: _dragging ? Duration.zero : AppMotion.feedback(context),
            curve: AppMotion.enterCurve,
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
                              fontWeight: DesignTokens.fontWeightStrong,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _expanded ? subtitle : '$subtitle · 默认收起',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.56),
                              fontWeight: DesignTokens.fontWeightStrong,
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
                          fontWeight: DesignTokens.fontWeightStrong,
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
                      fontWeight: DesignTokens.fontWeightStrong,
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
        leading: todo.subtasks.isNotEmpty
            ? _TodaySubtaskProgress(todo: todo)
            : _TodayTodoLeading(
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
            fontWeight: DesignTokens.fontWeightStrong,
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
    final home = HomePageStyle.of(context);
    return Semantics(
      button: true,
      child: InkWell(
        key: const ValueKey('today_quiet_quote'),
        borderRadius: DesignTokens.borderRadiusSm,
        onTap: () => setState(() => _text = DailyQuotes.random()),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.spaceMd,
            DesignTokens.spaceLg,
            DesignTokens.spaceMd,
            DesignTokens.spaceMd,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: home.typography(
                    theme,
                    size: DesignTokens.homeCaptionSize,
                    color: home.subtle,
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
