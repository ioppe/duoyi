import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/habit_trend.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/screens/habit_detail_screen.dart';

/// 固定应用墙钟：2026-03-10（周二），让日期格与补卡日历可预测。
///
/// 2026-03-01 是周日，因此本月有 6 个 leading 空位、31 天、6 行；
/// 2026-02-01 也是周日，共 28 天。
final DateTime _fixedNow = DateTime(2026, 3, 10, 9, 15);
final DateTime _fixedToday = DateTime(2026, 3, 10);

String _dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime _daysAgo(int days) =>
    DateTime(_fixedToday.year, _fixedToday.month, _fixedToday.day - days);

Finder _cellsWithPrefix(String prefix) => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith(prefix);
});

ValueKey<String> _trendDayKey(DateTime date) =>
    ValueKey<String>('$habitTrendDayKeyPrefix${_dateKey(date)}');

ValueKey<String> _calendarDayKey(DateTime date) =>
    ValueKey<String>('$habitCalendarDayKeyPrefix${_dateKey(date)}');

List<Rect> _cellRects(WidgetTester tester, String prefix) {
  final rects = <Rect>[];
  for (final element in _cellsWithPrefix(prefix).evaluate()) {
    rects.add(tester.getRect(find.byKey(element.widget.key!)));
  }
  return rects;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppClock.debugNow = () => _fixedNow;
  });

  tearDown(() {
    AppClock.debugNow = null;
    I18n.setLocale(AppLocale.zh);
  });

  Future<void> pumpDetail(
    WidgetTester tester, {
    required HabitProvider provider,
    required String habitId,
    ThemeData? theme,
    Size size = const Size(390, 844),
    double textScale = 1,
    bool disableAnimations = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      ChangeNotifierProvider<HabitProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: theme ?? AppBrands.defaultBrand.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: disableAnimations,
            ),
            child: child!,
          ),
          home: HabitDetailScreen(habitId: habitId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder detailScrollable() {
    return find
        .descendant(
          of: find.byKey(habitDetailListKey),
          matching: find.byType(Scrollable),
        )
        .first;
  }

  /// 主列表按需构建子项：深部内容先滚动到可见再断言。
  Future<void> scrollDetailTo(WidgetTester tester, Finder target) async {
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        240,
        scrollable: detailScrollable(),
        maxScrolls: 80,
      );
    } else {
      await tester.ensureVisible(target);
    }
    await tester.pumpAndSettle();
  }

  Set<HabitTrendWindow> selectedWindow(WidgetTester tester) {
    final selector = tester.widget<SegmentedButton<HabitTrendWindow>>(
      find.byKey(habitTrendWindowSelectorKey),
    );
    return selector.selected;
  }

  Future<void> selectWindow(
    WidgetTester tester,
    HabitTrendWindow window,
  ) async {
    await scrollDetailTo(tester, find.byKey(habitTrendWindowSelectorKey));
    final label = find.descendant(
      of: find.byKey(habitTrendWindowSelectorKey),
      matching: find.text(localizedHabitTrendWindowLabel(window)),
    );
    expect(label, findsOneWidget);
    await tester.ensureVisible(label);
    await tester.pumpAndSettle();
    await tester.tap(label);
    await tester.pumpAndSettle();
  }

  Future<void> expandCalendar(WidgetTester tester) async {
    await scrollDetailTo(tester, find.byKey(habitCalendarToggleKey));
    await tester.tap(find.byKey(habitCalendarToggleKey));
    await tester.pumpAndSettle();
  }

  Future<void> turnMonth(WidgetTester tester, Key key) async {
    final button = find.byKey(key);
    await scrollDetailTo(tester, button);
    await tester.tap(button.hitTestable());
    await tester.pumpAndSettle();
  }

  Finder cellSemantics(Finder cell) =>
      find.descendant(of: cell, matching: find.byType(Semantics)).first;

  String monthLabel(WidgetTester tester, DateTime month) {
    return MaterialLocalizations.of(
      tester.element(find.byType(HabitDetailScreen)),
    ).formatMonthYear(month);
  }

  String fullDateLabel(WidgetTester tester, DateTime date) {
    return MaterialLocalizations.of(
      tester.element(find.byType(HabitDetailScreen)),
    ).formatFullDate(date);
  }

  List<String> trendTexts(WidgetTester tester) {
    return tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(habitTrendCardKey),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data ?? '')
        .toList();
  }

  testWidgets('习惯详情趋势默认 14 天，且最近日期排在最前', (tester) async {
    addTearDown(tester.view.reset);
    final provider = HabitProvider();
    await provider.addHabit(Habit(id: 'h14', name: '喝水', targetCount: 2));

    await pumpDetail(tester, provider: provider, habitId: 'h14');

    expect(find.byKey(habitTrendCardKey), findsOneWidget);
    expect(selectedWindow(tester), {HabitTrendWindow.days14});

    final badges = trendTexts(tester)
        .where((text) => RegExp(r'^(?:[1-9]|1[0-2])/\d{1,2}$').hasMatch(text))
        .toList();
    expect(badges, hasLength(14));
    expect(badges.first, '${_fixedToday.month}/${_fixedToday.day}');
    final oldest = _daysAgo(13);
    expect(badges.last, '${oldest.month}/${oldest.day}');
    expect(tester.takeException(), isNull);
  });

  testWidgets('30 天视图是 30 个等高日期格，语义与方法可达的详情浮层', (tester) async {
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    try {
      final provider = HabitProvider();
      // 目标 2、今天 3：今天是「达标」，昨天是「有记录但未达标」，
      // 生效期之前的日子是「未在周期内」，三种状态同时出现。
      final habit = Habit(
        id: 'h30',
        name: '喝水',
        targetCount: 2,
        startDate: _daysAgo(5),
        completions: {_dateKey(_fixedToday): 3},
      );
      await provider.addHabit(habit);

      await pumpDetail(tester, provider: provider, habitId: 'h30');
      await selectWindow(tester, HabitTrendWindow.days30);

      // 30 个稳定 key 的日期格，最近日期在最前。
      final cells = _cellsWithPrefix(habitTrendDayKeyPrefix);
      expect(cells, findsNWidgets(30));
      final keys = _cellsWithPrefix(habitTrendDayKeyPrefix)
          .evaluate()
          .map((element) => (element.widget.key! as ValueKey<String>).value)
          .toList();
      expect(keys.first, '$habitTrendDayKeyPrefix${_dateKey(_fixedToday)}');
      expect(keys.last, '$habitTrendDayKeyPrefix${_dateKey(_daysAgo(29))}');
      expect(keys.toSet().length, 30, reason: '30 个日期格的 key 必须唯一，不能被同一日期重复命中');

      // 全部等高、等宽、行对齐，且不小于 44 触控尺寸。
      final rects = _cellRects(tester, habitTrendDayKeyPrefix);
      expect(rects, hasLength(30));
      for (final rect in rects) {
        expect(rect.height, closeTo(rects.first.height, 0.1));
        expect(rect.width, closeTo(rects.first.width, 0.1));
      }
      expect(rects.first.height, greaterThanOrEqualTo(43.9));
      expect(rects.first.width, greaterThanOrEqualTo(43.9));
      expect(rects.first.width, lessThan(120), reason: '日期格是网格而不是满宽行');
      final tops = rects.map((rect) => rect.top).toSet().toList()..sort();
      final firstRowCount = rects
          .where((rect) => (rect.top - tops.first).abs() < 0.1)
          .length;
      expect(firstRowCount, greaterThan(1));
      for (final top in tops.take(tops.length - 1)) {
        expect(
          rects.where((rect) => (rect.top - top).abs() < 0.1).length,
          firstRowCount,
          reason: '同一列宽度一致，只有最后一行可以不满',
        );
      }

      // 旧灰色 Tooltip 已移除，格内两行都是 Text（图标与数字不再混排）。
      expect(
        find.descendant(
          of: find.byKey(habitTrendCardKey),
          matching: find.byType(Tooltip),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: _cellsWithPrefix(habitTrendDayKeyPrefix),
          matching: find.byType(Icon),
        ),
        findsNothing,
      );

      // 内容：完成日显示数量并带「达标」语义，未完成显示 0，未在周期内显示 –。
      final todayCell = find.byKey(_trendDayKey(_fixedToday));
      expect(
        find.descendant(of: todayCell, matching: find.byType(Text)),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: todayCell, matching: find.text('3')),
        findsOneWidget,
      );
      final yesterdayCell = find.byKey(_trendDayKey(_daysAgo(1)));
      expect(
        find.descendant(of: yesterdayCell, matching: find.text('0')),
        findsOneWidget,
      );
      final inactiveCell = find.byKey(_trendDayKey(_daysAgo(6)));
      expect(
        find.descendant(of: inactiveCell, matching: find.text('–')),
        findsOneWidget,
      );

      // 读屏保留完整日期、数量与状态。
      final todayNode = tester.widget<Semantics>(cellSemantics(todayCell));
      final todayDescription = todayNode.properties.label!;
      expect(todayNode.properties.onTap, isNotNull);
      expect(todayDescription, contains('2026/3/10'));
      expect(todayDescription, contains(I18n.tr('habit.trend.completed')));
      expect(todayDescription, contains('3'));
      final inactiveDescription = tester
          .widget<Semantics>(cellSemantics(inactiveCell))
          .properties
          .label!;
      expect(inactiveDescription, contains('2026/3/4'));
      expect(inactiveDescription, contains(I18n.tr('habit.records.inactive')));
      expect(find.bySemanticsLabel(todayDescription), findsOneWidget);
      expect(find.bySemanticsLabel(inactiveDescription), findsOneWidget);

      // 点击日期格 → 主题详情浮层（趋势区只读，不提供写入按钮）。
      await tester.ensureVisible(todayCell);
      await tester.pumpAndSettle();
      await tester.tap(todayCell);
      await tester.pumpAndSettle();
      expect(find.byKey(habitDayDetailsCardKey), findsOneWidget);
      expect(find.text(fullDateLabel(tester, _fixedToday)), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(habitDayDetailsCardKey),
          matching: find.text(I18n.tr('habit.day.details')),
        ),
        findsNothing,
        reason: '浮层标题是完整日期，不重复页面级名称',
      );
      expect(
        find.descendant(
          of: find.byKey(habitDayDetailsCardKey),
          matching: find.text(I18n.tr('habit.trend.completed')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(habitDayDetailsCardKey),
          matching: find.text(I18n.tr('habit.day.count')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(habitDayDetailsCardKey),
          matching: find.text(I18n.tr('habit.day.target')),
        ),
        findsOneWidget,
      );
      expect(find.byKey(habitDayDetailsPrimaryKey), findsNothing);
      expect(find.byKey(habitDayDetailsUndoKey), findsNothing);
      expect(
        tester
            .widget<IconButton>(find.byKey(habitDayDetailsCloseKey))
            .autofocus,
        isTrue,
        reason: '浮层必须能用键盘聚焦到关闭按钮',
      );

      // 点卡内不关闭。
      await tester.tap(find.text(fullDateLabel(tester, _fixedToday)));
      await tester.pumpAndSettle();
      expect(find.byKey(habitDayDetailsCardKey), findsOneWidget);

      // 关闭按钮。
      await tester.tap(find.byKey(habitDayDetailsCloseKey));
      await tester.pumpAndSettle();
      expect(find.byKey(habitDayDetailsCardKey), findsNothing);

      // 点浮层外部关闭。
      await tester.tap(todayCell);
      await tester.pumpAndSettle();
      expect(find.byKey(habitDayDetailsCardKey), findsOneWidget);
      await tester.tapAt(const Offset(6, 60));
      await tester.pumpAndSettle();
      expect(find.byKey(habitDayDetailsCardKey), findsNothing);

      // 系统返回关闭。
      await tester.tap(todayCell);
      await tester.pumpAndSettle();
      expect(find.byKey(habitDayDetailsCardKey), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(habitDayDetailsCardKey), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('30 天日期格在 2x 字体下仍然等高、行对齐且不裁字', (tester) async {
    addTearDown(tester.view.reset);
    final provider = HabitProvider();
    await provider.addHabit(
      Habit(
        id: 'h30big',
        name: '喝水',
        targetCount: 3,
        unit: '杯',
        startDate: _daysAgo(9),
        completions: {_dateKey(_fixedToday): 3, _dateKey(_daysAgo(1)): 1},
      ),
    );

    await pumpDetail(
      tester,
      provider: provider,
      habitId: 'h30big',
      textScale: 2,
    );
    await selectWindow(tester, HabitTrendWindow.days30);

    final rects = _cellRects(tester, habitTrendDayKeyPrefix);
    expect(rects, hasLength(30));
    for (final rect in rects) {
      expect(rect.height, closeTo(rects.first.height, 0.1));
      expect(rect.width, closeTo(rects.first.width, 0.1));
    }
    expect(rects.first.height, greaterThan(43.9));
    expect(rects.first.width, greaterThan(43.9));
    expect(tester.takeException(), isNull);
  });

  testWidgets('30 天详情浮层在减少动效下立即可用', (tester) async {
    addTearDown(tester.view.reset);
    final provider = HabitProvider();
    await provider.addHabit(
      Habit(
        id: 'h30motion',
        name: '喝水',
        targetCount: 2,
        startDate: _daysAgo(3),
        completions: {_dateKey(_fixedToday): 2},
      ),
    );

    await pumpDetail(
      tester,
      provider: provider,
      habitId: 'h30motion',
      disableAnimations: true,
    );
    await selectWindow(tester, HabitTrendWindow.days30);

    final todayCell = find.byKey(_trendDayKey(_fixedToday));
    await tester.ensureVisible(todayCell);
    await tester.pumpAndSettle();
    await tester.tap(todayCell);
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(habitDayDetailsCardKey),
      findsOneWidget,
      reason: '减少动效时浮层不能依赖过渡动画完成',
    );

    await tester.tap(find.byKey(habitDayDetailsCloseKey));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(habitDayDetailsCardKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('90 天与一年聚合视图保持最近区间在最前', (tester) async {
    addTearDown(tester.view.reset);
    final provider = HabitProvider();
    await provider.addHabit(Habit(id: 'h90', name: '喝水', targetCount: 2));

    await pumpDetail(tester, provider: provider, habitId: 'h90');

    await selectWindow(tester, HabitTrendWindow.days90);
    final weekLabels = trendTexts(tester)
        .where(
          (text) => RegExp(r'^\d{1,2}/\d{1,2}-\d{1,2}/\d{1,2}$').hasMatch(text),
        )
        .toList();
    expect(weekLabels, isNotEmpty);
    expect(
      weekLabels.first,
      endsWith('${_fixedToday.month}/${_fixedToday.day}'),
      reason: '最近一周（含今天）必须排在最前',
    );

    await selectWindow(tester, HabitTrendWindow.days365);
    final monthLabels = trendTexts(
      tester,
    ).where((text) => RegExp(r'^\d{4}/\d{1,2}$').hasMatch(text)).toList();
    expect(monthLabels, isNotEmpty);
    expect(monthLabels.first, '${_fixedToday.year}/${_fixedToday.month}');
    final oldest = _daysAgo(364);
    expect(monthLabels.last, '${oldest.year}/${oldest.month}');
    expect(tester.takeException(), isNull);
  });

  testWidgets('趋势卡片滚出缓存再回滚，范围与补卡日历展开月份都不丢', (tester) async {
    addTearDown(tester.view.reset);
    final provider = HabitProvider();
    await provider.addHabit(Habit(id: 'h365', name: '喝水', targetCount: 3));

    // 短视口确保收纳后的日历仍足以让趋势子树离开缓存。
    await pumpDetail(
      tester,
      provider: provider,
      habitId: 'h365',
      size: const Size(390, 200),
    );
    await selectWindow(tester, HabitTrendWindow.days365);
    expect(selectedWindow(tester), {HabitTrendWindow.days365});

    // 展开日历并翻到上个月：这两个状态都属于详情页。
    await expandCalendar(tester);
    await turnMonth(tester, habitCalendarPrevMonthKey);
    final february = monthLabel(tester, DateTime(2026, 2));
    expect(find.text(february), findsOneWidget);
    expect(_cellsWithPrefix(habitCalendarDayKeyPrefix), findsNWidgets(28));

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final position = tester.state<ScrollableState>(detailScrollable()).position;
    for (var i = 0; i < 3; i++) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    expect(
      find.byKey(habitTrendCardKey),
      findsNothing,
      reason: '滚到深处后趋势子树应已被回收，状态不能留在卡片内部',
    );

    position.jumpTo(0);
    await tester.pumpAndSettle();
    await scrollDetailTo(tester, find.byKey(habitTrendWindowSelectorKey));
    expect(find.byKey(habitTrendCardKey), findsOneWidget);
    expect(selectedWindow(tester), {HabitTrendWindow.days365});

    await scrollDetailTo(tester, find.byKey(habitRecentRecordsCardKey));
    expect(
      find.text(february),
      findsOneWidget,
      reason: '展开的月份由详情页持有，滚出缓存重建后不能回到当月',
    );
    expect(_cellsWithPrefix(habitCalendarDayKeyPrefix), findsNWidgets(28));
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider 打卡与编辑保存后趋势范围与日历月份仍保持', (tester) async {
    addTearDown(tester.view.reset);
    final provider = HabitProvider();
    await provider.addHabit(
      Habit(id: 'hkeep', name: '喝水', targetCount: 3, startDate: _daysAgo(40)),
    );

    await pumpDetail(tester, provider: provider, habitId: 'hkeep');
    await selectWindow(tester, HabitTrendWindow.days365);
    await expandCalendar(tester);
    await turnMonth(tester, habitCalendarPrevMonthKey);
    final february = monthLabel(tester, DateTime(2026, 2));

    await provider.incrementHabitForDate('hkeep', _fixedToday);
    await tester.pumpAndSettle();
    expect(selectedWindow(tester), {HabitTrendWindow.days365});

    await provider.updateHabit(
      'hkeep',
      provider.habits.single.copyWith(name: '多喝水'),
    );
    await tester.pumpAndSettle();
    expect(find.text('多喝水'), findsWidgets);
    expect(selectedWindow(tester), {HabitTrendWindow.days365});

    await scrollDetailTo(tester, find.byKey(habitRecentRecordsCardKey));
    expect(find.text(february), findsOneWidget);
    expect(
      _cellsWithPrefix(habitCalendarDayKeyPrefix),
      findsNWidgets(28),
      reason: 'provider 更新不会把用户折叠回当月日历',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('补卡日历默认收起，展开后是本月日期与正确的星期偏移', (tester) async {
    addTearDown(tester.view.reset);
    final provider = HabitProvider();
    await provider.addHabit(
      Habit(id: 'hcal', name: '喝水', targetCount: 2, startDate: _daysAgo(9)),
    );

    await pumpDetail(tester, provider: provider, habitId: 'hcal');
    await scrollDetailTo(tester, find.byKey(habitRecentRecordsCardKey));

    // 默认收起：只有标题与提示，没有 30 行记录，也没有月历日格。
    expect(find.byKey(habitCalendarToggleKey), findsOneWidget);
    expect(find.text(I18n.tr('habit.calendar.title')), findsOneWidget);
    expect(find.text(I18n.tr('habit.calendar.hint')), findsOneWidget);
    expect(_cellsWithPrefix(habitCalendarDayKeyPrefix), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'habit_recent_record_',
            ),
      ),
      findsNothing,
      reason: '最近记录 30 行长列表已替换为补卡日历',
    );
    expect(
      find.descendant(
        of: find.byKey(habitRecentRecordsCardKey),
        matching: find.byType(ListView),
      ),
      findsNothing,
      reason: '收起状态不构建嵌套长列表',
    );

    await tester.tap(find.byKey(habitCalendarToggleKey));
    await tester.pumpAndSettle();
    expect(find.text(I18n.tr('habit.calendar.expanded_hint')), findsOneWidget);
    expect(find.text(monthLabel(tester, DateTime(2026, 3))), findsOneWidget);

    // 完整本月 31 天，不重复显示相邻月份的日号。
    expect(_cellsWithPrefix(habitCalendarDayKeyPrefix), findsNWidgets(31));
    expect(find.byKey(_calendarDayKey(DateTime(2026, 3, 1))), findsOneWidget);
    expect(find.byKey(_calendarDayKey(DateTime(2026, 3, 31))), findsOneWidget);
    expect(find.byKey(_calendarDayKey(DateTime(2026, 2, 28))), findsNothing);
    expect(find.byKey(_calendarDayKey(DateTime(2026, 4, 1))), findsNothing);

    // 2026-03-01 是周日：首日必须落在最后一列（周一为首列，6 个空位）。
    final firstDay = find.byKey(_calendarDayKey(DateTime(2026, 3, 1)));
    final sundayHeader = find.descendant(
      of: find.byKey(habitRecentRecordsCardKey),
      matching: find.text(I18n.tr('habit.weekday.7')),
    );
    expect(sundayHeader, findsOneWidget);
    expect(
      tester.getCenter(firstDay).dx,
      closeTo(tester.getCenter(sundayHeader).dx, 1),
    );
    final mondayHeader = find.descendant(
      of: find.byKey(habitRecentRecordsCardKey),
      matching: find.text(I18n.tr('habit.weekday.1')),
    );
    expect(
      tester.getCenter(firstDay).dx,
      greaterThan(tester.getCenter(mondayHeader).dx),
    );

    // 所有日格同宽同高，且不小于 44。
    final rects = _cellRects(tester, habitCalendarDayKeyPrefix);
    for (final rect in rects) {
      expect(rect.width, closeTo(rects.first.width, 0.1));
      expect(rect.height, closeTo(rects.first.height, 0.1));
      expect(rect.width, greaterThan(43.9));
      expect(rect.height, greaterThan(43.9));
    }
    // 390dp 宽屏下 7 列直接铺满，不需要横向滚动。
    expect(
      find.descendant(
        of: find.byKey(habitRecentRecordsCardKey),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('补卡日历可翻历史月份，但不能翻到未来月份', (tester) async {
    addTearDown(tester.view.reset);
    final provider = HabitProvider();
    await provider.addHabit(
      Habit(
        id: 'hmonth',
        name: '喝水',
        targetCount: 2,
        startDate: DateTime(2025, 12, 20),
      ),
    );

    await pumpDetail(tester, provider: provider, habitId: 'hmonth');
    await expandCalendar(tester);

    // 当前月：下个月按钮禁用（未来没有可补卡的日期）。
    expect(
      tester
          .widget<IconButton>(find.byKey(habitCalendarNextMonthKey))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(habitCalendarPrevMonthKey))
          .onPressed,
      isNotNull,
    );

    await turnMonth(tester, habitCalendarPrevMonthKey);
    expect(find.text(monthLabel(tester, DateTime(2026, 2))), findsOneWidget);
    expect(_cellsWithPrefix(habitCalendarDayKeyPrefix), findsNWidgets(28));
    expect(find.byKey(_calendarDayKey(DateTime(2026, 2, 28))), findsOneWidget);
    expect(find.byKey(_calendarDayKey(DateTime(2026, 3, 1))), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.byKey(habitCalendarNextMonthKey))
          .onPressed,
      isNotNull,
    );

    // 继续往前翻不受 30 天历史限制。
    await turnMonth(tester, habitCalendarPrevMonthKey);
    expect(find.text(monthLabel(tester, DateTime(2026, 1))), findsOneWidget);
    expect(_cellsWithPrefix(habitCalendarDayKeyPrefix), findsNWidgets(31));
    expect(find.byKey(_calendarDayKey(DateTime(2026, 1, 31))), findsOneWidget);

    await turnMonth(tester, habitCalendarNextMonthKey);
    await turnMonth(tester, habitCalendarNextMonthKey);
    expect(find.text(monthLabel(tester, DateTime(2026, 3))), findsOneWidget);
    expect(_cellsWithPrefix(habitCalendarDayKeyPrefix), findsNWidgets(31));
    expect(
      tester
          .widget<IconButton>(find.byKey(habitCalendarNextMonthKey))
          .onPressed,
      isNull,
      reason: '回到当前月后仍然不能前进到未来',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('日历选中过去的未达标日补卡，浮层实时刷新且不影响今天', (tester) async {
    addTearDown(tester.view.reset);
    final provider = HabitProvider();
    final yesterday = _daysAgo(1);
    await provider.addHabit(
      Habit(
        id: 'hfill',
        name: '喝水',
        targetCount: 2,
        startDate: _daysAgo(9),
        completions: {_dateKey(_fixedToday): 1},
      ),
    );

    await pumpDetail(tester, provider: provider, habitId: 'hfill');
    await expandCalendar(tester);

    final yesterdayCell = find.byKey(_calendarDayKey(yesterday));
    await tester.ensureVisible(yesterdayCell);
    await tester.pumpAndSettle();
    await tester.tap(yesterdayCell);
    await tester.pumpAndSettle();

    expect(find.byKey(habitDayDetailsCardKey), findsOneWidget);
    expect(find.text(fullDateLabel(tester, yesterday)), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(habitDayDetailsCardKey),
        matching: find.text(I18n.tr('habit.day.pending')),
      ),
      findsOneWidget,
    );
    final countUnit = I18n.tr('habit.unit.times');
    expect(
      find.descendant(
        of: find.byKey(habitDayDetailsCardKey),
        matching: find.text('0$countUnit'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(habitDayDetailsUndoKey), findsNothing);
    final primary = find.byKey(habitDayDetailsPrimaryKey);
    expect(
      find.descendant(
        of: primary,
        matching: find.text(I18n.tr('habit.records.make_up_once')),
      ),
      findsOneWidget,
    );

    await tester.tap(primary);
    await tester.pumpAndSettle();
    expect(provider.habits.single.countForDate(yesterday), 1);
    expect(
      provider.habits.single.countForDate(_fixedToday),
      1,
      reason: '补卡只作用于选中日期',
    );

    // 浮层原地刷新：数量、状态与撤销按钮都跟着变，浮层不关闭。
    expect(find.byKey(habitDayDetailsCardKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(habitDayDetailsCardKey),
        matching: find.text('1$countUnit'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(habitDayDetailsUndoKey), findsOneWidget);

    await tester.tap(find.byKey(habitDayDetailsUndoKey));
    await tester.pumpAndSettle();
    expect(provider.habits.single.countForDate(yesterday), 0);
    expect(provider.habits.single.countForDate(_fixedToday), 1);
    expect(
      find.descendant(
        of: find.byKey(habitDayDetailsCardKey),
        matching: find.text('0$countUnit'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(habitDayDetailsCloseKey));
    await tester.pumpAndSettle();
    expect(find.byKey(habitDayDetailsCardKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('日历里未来日期不可写，生效期外日期只读', (tester) async {
    addTearDown(tester.view.reset);
    final provider = HabitProvider();
    await provider.addHabit(
      Habit(id: 'hfuture', name: '喝水', targetCount: 2, startDate: _daysAgo(2)),
    );

    await pumpDetail(tester, provider: provider, habitId: 'hfuture');
    await expandCalendar(tester);

    final futureCell = find.byKey(_calendarDayKey(DateTime(2026, 3, 20)));
    await tester.ensureVisible(futureCell);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(cellSemantics(futureCell)),
      matchesSemantics(
        label: '2026/3/20 · ${I18n.tr('habit.day.future')}',
        hasEnabledState: true,
        isEnabled: false,
      ),
      reason: '未来日期没有可用的写入入口',
    );
    await tester.tap(futureCell, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byKey(habitDayDetailsCardKey), findsNothing);
    expect(provider.habits.single.countForDate(DateTime(2026, 3, 20)), 0);

    // 生效期之前的日期可以打开详情，但没有写入按钮。
    final inactiveCell = find.byKey(_calendarDayKey(DateTime(2026, 3, 1)));
    await tester.ensureVisible(inactiveCell);
    await tester.pumpAndSettle();
    await tester.tap(inactiveCell);
    await tester.pumpAndSettle();
    expect(find.byKey(habitDayDetailsCardKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(habitDayDetailsCardKey),
        matching: find.text(I18n.tr('habit.records.inactive')),
      ),
      findsOneWidget,
    );
    expect(find.byKey(habitDayDetailsPrimaryKey), findsNothing);
    expect(find.byKey(habitDayDetailsUndoKey), findsNothing);
    await tester.tap(find.byKey(habitDayDetailsCloseKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('320/390 与 1.0/1.5/2x 字体在普通与暗色主题下不溢出', (tester) async {
    addTearDown(tester.view.reset);
    final themes = [AppBrands.defaultBrand.theme, AppBrands.starRail.theme];

    for (final theme in themes) {
      for (final width in const [320.0, 390.0]) {
        for (final scale in const [1.0, 1.5, 2.0]) {
          final provider = HabitProvider();
          await provider.addHabit(
            Habit(
              id: 'hlayout',
              name: '超长习惯名称用于验证详情布局不会挤压遮挡',
              kind: HabitKind.negative,
              unit: '杯超长单位名称',
              targetCount: 3,
              startDate: _daysAgo(3),
              completions: {_dateKey(_fixedToday): 2},
            ),
          );

          await pumpDetail(
            tester,
            provider: provider,
            habitId: 'hlayout',
            theme: theme,
            size: Size(width, 800),
            textScale: scale,
          );

          for (final window in HabitTrendWindow.values) {
            await selectWindow(tester, window);
            expect(
              tester.takeException(),
              isNull,
              reason: 'width=$width scale=$scale window=$window',
            );
          }

          // 补卡日历：收起与展开都不能溢出。
          await scrollDetailTo(tester, find.byKey(habitRecentRecordsCardKey));
          expect(
            find.byKey(habitRecentRecordsCardKey),
            findsOneWidget,
            reason: 'width=$width scale=$scale',
          );
          await tester.tap(find.byKey(habitCalendarToggleKey));
          await tester.pumpAndSettle();
          expect(
            _cellsWithPrefix(habitCalendarDayKeyPrefix),
            findsNWidgets(31),
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'width=$width scale=$scale calendar',
          );

          // 卸载，避免下一轮复用旧 provider 的组件。
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    }
  });

  testWidgets('369.23dp/1.25 倍与长单位中英文在窄屏不裁切', (tester) async {
    addTearDown(tester.view.reset);
    for (final locale in const [AppLocale.zh, AppLocale.en]) {
      I18n.setLocale(locale);
      final provider = HabitProvider();
      await provider.addHabit(
        Habit(
          id: 'hdpi',
          name: 'Streaming practice with a very long name',
          targetCount: 5,
          unit: '杯超长单位名称',
          startDate: _daysAgo(12),
          completions: {_dateKey(_fixedToday): 5, _dateKey(_daysAgo(2)): 2},
        ),
      );

      await pumpDetail(
        tester,
        provider: provider,
        habitId: 'hdpi',
        size: const Size(369.23, 821.5),
        textScale: 1.25,
      );

      await selectWindow(tester, HabitTrendWindow.days30);
      final trendRects = _cellRects(tester, habitTrendDayKeyPrefix);
      expect(trendRects, hasLength(30));
      for (final rect in trendRects) {
        expect(rect.height, closeTo(trendRects.first.height, 0.1));
      }
      expect(tester.takeException(), isNull, reason: 'locale=$locale trend');

      await scrollDetailTo(tester, find.byKey(habitRecentRecordsCardKey));
      await tester.tap(find.byKey(habitCalendarToggleKey));
      await tester.pumpAndSettle();
      expect(_cellsWithPrefix(habitCalendarDayKeyPrefix), findsNWidgets(31));
      final calendarRects = _cellRects(tester, habitCalendarDayKeyPrefix);
      for (final rect in calendarRects) {
        expect(rect.width, closeTo(calendarRects.first.width, 0.1));
        expect(rect.height, closeTo(calendarRects.first.height, 0.1));
        expect(rect.width, greaterThan(43.9));
      }
      // 7 列都能在 369.23dp 内直接看到，不需要横向滚动。
      expect(
        find.descendant(
          of: find.byKey(habitRecentRecordsCardKey),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
        reason: 'locale=$locale calendar',
      );
      expect(tester.takeException(), isNull, reason: 'locale=$locale calendar');

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
