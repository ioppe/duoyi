import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('习惯页提供可见分组列表并沿用习惯分类字段', () {
    final source = File('lib/screens/habit_screen.dart').readAsStringSync();

    expect(source, contains("import '../core/habit_grouping.dart';"));
    expect(source, contains('groupHabitsByCategory(provider.habits)'));
    expect(source, contains('_HabitGroupSection'));
    expect(source, contains('ExpansionTile('));
    expect(source, contains('const int _habitHeatmapGroupPreviewLimit = 8'));
    expect(
      source,
      matches(
        RegExp(
          r'initiallyExpanded:\s*group\.habits\.length\s*<=\s*_habitHeatmapGroupPreviewLimit',
        ),
      ),
    );
    expect(source, contains('for (final habit in previewHabits)'));
    expect(source, contains('习惯分组'));
    expect(source, contains('Icons.folder_outlined'));
    expect(
      source,
      contains('category: habitCategoryOrNull(categoryCtrl.text)'),
    );
  });

  test('习惯模板选择会带入分类，手动创建也暴露分组字段', () {
    final source = File('lib/screens/habit_screen.dart').readAsStringSync();

    expect(source, contains('final categoryCtrl = TextEditingController()'));
    expect(source, contains('selectedKind = HabitKind.positive'));
    expect(source, contains('selectedIcon = habitIconTokenForIcon('));
    expect(source, contains('t.icon'));
    expect(source, contains('unitCtrl.text = t.localizedUnit'));
    expect(source, contains('categoryCtrl.text = t.localizedCategory'));
    expect(source, contains('flexRuleEnabled = t.hasFlexRule'));
    expect(source, contains('selectedFlexPeriod = t.flexPeriod!'));
    expect(source, contains('flexTargetCtrl.text = t.flexTarget!'));
    expect(source, contains('t.localizedFrequencyLabel'));
    expect(source, contains("labelText: '分组'"));
    expect(source, contains("hintText: '例如 身体健康、学习提升'"));
  });

  test('习惯详情编辑支持修改或清空分组', () {
    final source = File(
      'lib/screens/habit_detail_screen.dart',
    ).readAsStringSync();

    expect(source, contains("import '../core/habit_grouping.dart';"));
    expect(
      source,
      contains(
        "final categoryCtrl = TextEditingController(text: habit.category ?? '')",
      ),
    );
    expect(
      source,
      contains('category: habitCategoryOrNull(categoryCtrl.text)'),
    );
    expect(source, contains('clearCategory:'));
    expect(source, contains('defaultHabitCategoryName'));
    expect(source, contains("I18n.tr('habit.field.group.empty_hint')"));
  });

  test('习惯详情页直接暴露结束和删除操作', () {
    final source = File(
      'lib/screens/habit_detail_screen.dart',
    ).readAsStringSync();
    final headerStart = source.indexOf('width: 64,');
    final headerEnd = source.indexOf(
      "I18n.tr('habit.heatmap.title')",
      headerStart,
    );
    expect(headerStart, greaterThanOrEqualTo(0));
    expect(headerEnd, greaterThan(headerStart));
    final header = source.substring(headerStart, headerEnd);

    expect(header, contains('OutlinedButton.icon('));
    expect(header, contains("label: const Text('结束习惯')"));
    expect(header, contains('Icons.event_busy_outlined'));
    expect(header, contains('provider.endHabit(habit.id)'));
    expect(header, contains('_habitDangerOutlinedButtonStyle(context)'));
    expect(header, contains("label: const Text('删除')"));
    expect(header, contains('Icons.delete_outline'));
    expect(source, contains("title: const Text('删除习惯？')"));
    expect(header, contains('deleteHabit('));
    expect(source, contains("tooltip: '更多操作'"));
    expect(source, contains("value: 'end'"));
    expect(source, contains("title: Text('结束习惯')"));
    expect(source, contains("value: 'delete'"));
    expect(source, contains("title: Text('删除习惯'"));
    expect(source, isNot(contains("value == 'detail'")));
    expect(header, contains('habitDisplayIconFor(habit)'));
    expect(
      File('lib/core/habit_icons.dart').readAsStringSync(),
      contains('IconData habitDisplayIconFor(Habit habit)'),
    );
    expect(source, isNot(contains('IconData(codePoint')));
    expect(source, isNot(contains('child: Icon(Icons.star')));
    expect(source, contains('builder: (ctx) => AppDialog('));
    expect(source, isNot(contains('builder: (ctx) => AlertDialog(')));
  });

  test('习惯打卡提供完成反馈和轻量动效', () {
    final source = File('lib/screens/habit_screen.dart').readAsStringSync();

    expect(source, contains("import 'package:flutter/services.dart';"));
    expect(source, isNot(contains('AnimatedScale(')));
    expect(source, contains('AnimatedSwitcher('));
    expect(source, contains('_HabitFeedbackBadge'));
    expect(source, contains('HapticFeedback.mediumImpact()'));
    expect(source, contains('SystemSound.play(SystemSoundType.click)'));
    expect(source, contains('HapticFeedback.selectionClick()'));
    expect(source, contains("'habit-undo-inline-button'"));
    expect(source, contains('IconButton('));
    expect(source, contains("message: '撤回一次'"));
    expect(source, isNot(contains("label: const Text('还原')")));
    expect(source, contains('width: _habitUndoButtonWidth'));
    expect(source, contains('height: 26'));
    expect(
      source,
      contains('fixedSize: const Size(_habitUndoButtonWidth, 26)'),
    );
    expect(
      source,
      contains('fixedSize: const Size(_habitUndoButtonWidth, 26)'),
    );
    expect(source, contains('tapTargetSize: MaterialTapTargetSize.shrinkWrap'));
    expect(source, isNot(contains('dimension: 48')));
    expect(source, contains('messenger.hideCurrentSnackBar()'));
    expect(source, contains('今日已达标'));
    expect(source, contains("label: habit.hasFlexRule"));
    expect(source, contains(": '已达标'"));
    expect(source, contains("label: '已记录'"));
  });

  test('习惯打卡卡片采用紧凑排版让一屏展示更多任务', () {
    final source = File('lib/screens/habit_screen.dart').readAsStringSync();
    final cardStart = source.indexOf('class _HabitCheckinCard');
    final cardEnd = source.indexOf('Future<void> _handleCheckIn', cardStart);
    expect(cardStart, greaterThanOrEqualTo(0));
    expect(cardEnd, greaterThan(cardStart));
    final cardSource = source.substring(cardStart, cardEnd);

    expect(
      cardSource,
      contains('margin: const EdgeInsets.fromLTRB(10, 0, 10, 1)'),
    );
    expect(
      cardSource,
      contains('padding: const EdgeInsets.fromLTRB(7, 2, 6, 2)'),
    );
    expect(source, contains('const double _habitCheckinCardBodyHeight = 38'));
    expect(source, contains('const double _habitTitleStatusHeight = 15'));
    expect(source, contains('const double _habitUndoButtonWidth = 28'));
    expect(source, isNot(contains('const double _habitMenuButtonWidth')));
    expect(source, contains('const double _habitActionButtonGap = 3'));
    expect(source, contains('const double _habitActionRailWidth'));
    expect(cardSource, contains('height: _habitCheckinCardBodyHeight'));
    expect(cardSource, contains('width: 20'));
    expect(cardSource, contains('height: 20'));
    expect(cardSource, contains('height: 2'));
    expect(cardSource, contains('width: _habitCheckinButtonWidth'));
    expect(cardSource, contains('height: 25'));
    expect(cardSource, contains('minimumSize: const Size('));
    expect(cardSource, contains('_habitCheckinButtonWidth'));
    expect(cardSource, contains('_habitDisplayIcon(habit)'));
    expect(source, contains('_HabitSummaryTile'));
    expect(source, contains('_habitDisplayIcon(habit)'));
    expect(source, contains("import '../core/habit_icons.dart';"));
    expect(source, isNot(contains('IconData(codePoint')));
    expect(source, isNot(contains('Icon(Icons.star')));
    expect(source, isNot(contains('child: Icon(Icons.star')));
    expect(cardSource, isNot(contains('Icons.shield_outlined')));
    expect(cardSource, isNot(contains('Icons.warning_amber_rounded')));
    expect(cardSource, isNot(contains('Icons.verified_rounded')));
    expect(cardSource, isNot(contains('_HabitEditButton(habit: habit)')));
    expect(
      source,
      isNot(contains('class _HabitEditButton extends StatelessWidget')),
    );
    expect(
      source,
      isNot(contains("key: const ValueKey('habit_inline_edit_button')")),
    );
    expect(source, contains('message: label'));
    expect(source, isNot(contains("tooltip: '习惯操作'")));
    expect(source, isNot(contains('PopupMenuButton<String>')));
    expect(source, contains('class _HabitInlineSwipeActions'));
    expect(source, contains("key: const ValueKey('habit_swipe_edit_button')"));
    expect(source, contains("key: const ValueKey('habit_swipe_end_button')"));
    expect(
      source,
      contains("key: const ValueKey('habit_swipe_delete_button')"),
    );
    expect(source, contains("label: '编辑'"));
    expect(source, contains("label: '结束'"));
    expect(source, contains("label: '删除'"));
    expect(source, isNot(contains("PopupMenuItem(value: 'end'")));
    expect(source, isNot(contains("value: 'delete'")));
    expect(
      source,
      isNot(contains("AppSecondaryMenuText('删除习惯', color: cs.error)")),
    );
    expect(cardSource, contains('Visibility('));
    expect(cardSource, contains('maintainSize: true'));
    expect(
      cardSource,
      contains('const SizedBox(width: _habitActionButtonGap)'),
    );
    expect(cardSource, contains("'\$targetText · \$countText'"));
    expect(cardSource, contains('if (habit.currentStreak > 0)'));
    expect(cardSource, contains('overflow: TextOverflow.ellipsis'));
  });

  test('习惯本周概览置顶且保持紧凑', () {
    final screen = File('lib/screens/habit_screen.dart').readAsStringSync();
    final weekly = File(
      'lib/widgets/habit_weekly_card.dart',
    ).readAsStringSync();

    final weeklyIndex = screen.indexOf(
      'const SliverToBoxAdapter(child: HabitWeeklyCard())',
    );
    final scrollViewIndex = screen.indexOf(
      "key: const ValueKey('habit_today_scroll_view')",
    );
    final sliversIndex = screen.indexOf('slivers: [', scrollViewIndex);
    final insightIndex = screen.indexOf(
      "key: const ValueKey('habit_insight_before_today_list')",
    );
    expect(scrollViewIndex, greaterThanOrEqualTo(0));
    expect(sliversIndex, greaterThan(scrollViewIndex));
    expect(weeklyIndex, greaterThanOrEqualTo(0));
    expect(weeklyIndex, greaterThan(sliversIndex));
    expect(weeklyIndex, lessThan(insightIndex));
    expect(weeklyIndex, lessThan(screen.indexOf('_HabitTodaySummaryCard(')));
    expect(
      weeklyIndex,
      lessThan(
        screen.indexOf("key: const ValueKey('habit_today_checkin_sliver')"),
      ),
    );
    expect(
      weeklyIndex,
      lessThan(
        screen.indexOf("key: const ValueKey('habit_today_empty_state_sliver')"),
      ),
    );
    expect(
      weekly,
      contains("key: const ValueKey('habit_weekly_overview_card')"),
    );
    expect(weekly, contains('context.watch<HabitProvider>()'));
    expect(weekly, contains('final data = provider.currentWeekProgress();'));
    expect(weekly, contains('margin: const EdgeInsets.fromLTRB(10, 4, 10, 4)'));
    expect(weekly, contains('padding: const EdgeInsets.fromLTRB(8, 6, 8, 7)'));
    expect(weekly, contains('currentWeekProgress()'));
    expect(
      weekly,
      contains('borderRadius: BorderRadius.circular(DesignTokens.radiusCard)'),
    );
    expect(weekly, contains('fontSize: 13'));
    expect(weekly, contains('fontSize: DesignTokens.fontSizeCaption'));
    expect(weekly, contains('minHeight: 3'));
    expect(weekly, contains('width: 30'));
    expect(weekly, contains('height: 30'));
    expect(weekly, contains('width: 25'));
    expect(weekly, contains('height: 25'));
    expect(weekly, contains('fontWeight: DesignTokens.fontWeightRegular'));
  });

  test('习惯达标状态与任务名同一行靠右展示', () {
    final source = File('lib/screens/habit_screen.dart').readAsStringSync();
    final cardStart = source.indexOf('class _HabitCheckinCard');
    final cardSource = source.substring(cardStart);
    final nameIndex = cardSource.indexOf('habit.name');
    final badgeIndex = cardSource.indexOf('_HabitFeedbackBadge');
    final streakIndex = cardSource.indexOf("\${habit.currentStreak}");

    expect(nameIndex, greaterThanOrEqualTo(0));
    expect(badgeIndex, greaterThan(nameIndex));
    expect(streakIndex, greaterThan(badgeIndex));
    expect(cardSource, contains("'habit-completed-feedback'"));
    expect(cardSource, contains('key: const ValueKey('));
    expect(cardSource, contains("'habit-warning-feedback'"));
  });

  test('习惯打卡先落盘再通知界面，且不被耗时记录拖住状态', () {
    final source = File('lib/providers/habit_provider.dart').readAsStringSync();

    final incrementStart = source.indexOf('Future<void> incrementHabitForDate');
    final decrementStart = source.indexOf('Future<void> decrementHabitForDate');
    final defaultStart = source.indexOf('int _defaultCheckInAmount');
    expect(incrementStart, greaterThanOrEqualTo(0));
    expect(decrementStart, greaterThan(incrementStart));
    expect(defaultStart, greaterThan(decrementStart));

    final incrementBody = source.substring(incrementStart, decrementStart);
    final decrementBody = source.substring(decrementStart, defaultStart);

    expect(
      incrementBody.indexOf('await _save();'),
      lessThan(incrementBody.indexOf('notifyListeners();')),
    );
    expect(
      incrementBody.indexOf('notifyListeners();'),
      lessThan(incrementBody.indexOf('await timeAudit.recordHabitCheckIn(')),
    );
    expect(
      decrementBody.indexOf('await _save();'),
      lessThan(decrementBody.indexOf('notifyListeners();')),
    );
    expect(
      decrementBody.indexOf('notifyListeners();'),
      lessThan(decrementBody.indexOf('await timeAudit.removeHabitCheckIn(')),
    );
  });

  test('习惯详情提供长期趋势范围切换和区间明细', () {
    final source = File(
      'lib/screens/habit_detail_screen.dart',
    ).readAsStringSync();

    expect(source, contains("import '../core/habit_trend.dart';"));
    expect(source, contains('buildHabitTrendSummary(widget.habit'));
    expect(source, contains('HabitTrendWindow.days30'));
    expect(source, contains('SegmentedButton<HabitTrendWindow>'));
    expect(source, contains('for (final window in HabitTrendWindow.values)'));
    expect(source, contains("I18n.tr('habit.trend.title')"));
    expect(source, contains("I18n.tr('habit.trend.vs_previous')"));
    expect(source, contains("I18n.tr('habit.trend.longest_streak')"));
    expect(source, contains("I18n.tr('habit.trend.bucket_details')"));
    expect(source, contains('_HabitTrendBucketRow'));
  });

  test('习惯首页展示智能习惯洞察', () {
    final source = File('lib/screens/habit_screen.dart').readAsStringSync();
    final weeklyIndex = source.indexOf(
      'const SliverToBoxAdapter(child: HabitWeeklyCard())',
    );
    final insightKeyIndex = source.indexOf(
      "key: const ValueKey('habit_insight_before_today_list')",
    );
    final insightIndex = source.indexOf(
      '_HabitInsightSection(habits: provider.habits)',
    );
    final emptyIndex = source.indexOf(
      "key: const ValueKey('habit_today_empty_state_sliver')",
    );
    final summaryIndex = source.indexOf('_HabitTodaySummaryCard(');
    final listIndex = source.indexOf(
      "key: const ValueKey('habit_today_checkin_sliver')",
    );

    expect(source, contains("import '../core/habit_insights.dart';"));
    expect(source, contains('HabitInsightEngine.buildInsights('));
    expect(source, contains('_HabitInsightCard'));
    expect(source, contains('_HabitInsightSection(habits: provider.habits)'));
    expect(
      source,
      contains("key: const ValueKey('habit_insight_before_today_list')"),
    );
    expect(source, contains('智能习惯洞察'));
    expect(weeklyIndex, greaterThanOrEqualTo(0));
    expect(insightKeyIndex, greaterThan(weeklyIndex));
    expect(insightIndex, greaterThan(insightKeyIndex));
    expect(insightIndex, lessThan(emptyIndex));
    expect(insightIndex, lessThan(summaryIndex));
    expect(insightIndex, lessThan(listIndex));
    expect(source, contains('HabitInsightKind.rising'));
    expect(source, contains('HabitInsightKind.slipping'));
  });

  test('习惯创建和详情编辑暴露弹性打卡规则', () {
    final screen = File('lib/screens/habit_screen.dart').readAsStringSync();
    final detail = File(
      'lib/screens/habit_detail_screen.dart',
    ).readAsStringSync();
    final provider = File(
      'lib/providers/habit_provider.dart',
    ).readAsStringSync();
    final zh = File('lib/l10n/app_zh.arb').readAsStringSync();
    final en = File('lib/l10n/app_en.arb').readAsStringSync();

    expect(screen, contains('flexRuleEnabled'));
    expect(screen, contains('SegmentedButton<HabitFlexPeriod>'));
    expect(screen, contains("I18n.tr('habit.unit.week')"));
    expect(screen, contains("I18n.tr('habit.unit.month')"));
    expect(screen, contains("'habit.flex.period_target'"));
    expect(screen, contains("'habit.flex.period_target_hint'"));
    expect(screen, contains('flexTarget: shouldUseFlex ? flexTarget : null'));
    expect(screen, contains('flexPeriod: shouldUseFlex'));
    expect(screen, contains('_habitFlexGoalText(habit)'));
    expect(screen, contains("HabitFlexPeriod.week => '每周目标:"));
    expect(screen, contains("HabitFlexPeriod.month => '每月目标:"));
    expect(screen, contains('habit.streakUnitLabel'));
    expect(screen, contains("I18n.tr('habit.flex.weekly')"));
    expect(screen, contains("I18n.tr('habit.flex.monthly')"));
    expect(screen, contains('周期目标至少为 1'));
    expect(screen, contains("HabitFlexPeriod.week => '每周目标'"));
    expect(screen, contains("HabitFlexPeriod.month => '每月目标'"));

    expect(detail, contains("I18n.tr('habit.flex.rule')"));
    expect(detail, contains('flexRuleEnabled = habit.hasFlexRule'));
    expect(detail, contains('clearFlexRule: !shouldUseFlex'));
    expect(detail, contains('localizedFlexPeriodGoalLabel(habit)'));
    expect(detail, contains('habit.flexProgressForDate(AppClock.now())'));
    expect(detail, contains('localizedHabitCountForDate(habit, d)'));
    expect(detail, contains('_localizedHabitStreakUnit(habit)'));
    expect(detail, contains("'habit.flex.period_target'"));
    expect(detail, contains("I18n.tr('habit.flex.weekly_goal_prefix')"));
    expect(detail, contains("I18n.tr('habit.flex.monthly_goal_prefix')"));

    expect(provider, contains('_recalcFlexStreak'));
    expect(provider, contains('h.periodBoundsForDate(AppClock.now())'));
    expect(provider, contains('h.previousPeriodBounds(bounds)'));

    expect(zh, contains('"habitFlexWeekly": "每周目标"'));
    expect(zh, contains('"habitFlexMonthly": "每月目标"'));
    expect(zh, contains('"habitFlexPeriodTarget": "目标次数"'));
    expect(zh, contains('"habitFlexPeriodTargetHint": "例如每周目标 5 次"'));
    expect(en, contains('"habitFlexWeekly": "Weekly target"'));
    expect(en, contains('"habitFlexMonthly": "Monthly target"'));
    expect(en, contains('"habitFlexPeriodTarget": "Target count"'));
  });

  test('习惯创建和详情编辑暴露起止日期并禁用周期外补卡', () {
    final screen = File('lib/screens/habit_screen.dart').readAsStringSync();
    final detail = File(
      'lib/screens/habit_detail_screen.dart',
    ).readAsStringSync();
    final dateFields = File(
      'lib/widgets/habit_date_range_fields.dart',
    ).readAsStringSync();

    expect(
      screen,
      contains("import '../widgets/habit_date_range_fields.dart';"),
    );
    expect(screen, contains('DateTime? startDate'));
    expect(screen, contains('DateTime? endDate'));
    expect(screen, contains('HabitDateRangeFields('));
    expect(screen, contains('habitDateRangeIsValid(startDate, endDate)'));
    expect(screen, contains('startDate: startDate'));
    expect(screen, contains('endDate: endDate'));

    expect(
      detail,
      contains("import '../widgets/habit_date_range_fields.dart';"),
    );
    expect(detail, contains('DateTime? startDate = habit.startDate'));
    expect(detail, contains('DateTime? endDate = habit.endDate'));
    expect(detail, contains('clearStartDate: startDate == null'));
    expect(detail, contains('clearEndDate: endDate == null'));
    expect(
      detail,
      contains('habitDateRangeLabel(habit.startDate, habit.endDate)'),
    );
    expect(detail, contains('final activeForDay = habit.activeForDate(d)'));
    expect(detail, contains("I18n.tr('habit.records.inactive')"));
    expect(detail, contains('onPressed: activeForDay'));

    expect(dateFields, contains("I18n.tr('habit.date_range.start')"));
    expect(dateFields, contains("I18n.tr('habit.date_range.end')"));
    expect(dateFields, contains("I18n.tr('habit.date_range.start_empty')"));
    expect(dateFields, contains("I18n.tr('habit.date_range.end_empty')"));
    expect(dateFields, contains('bool habitDateRangeIsValid'));
  });
}
