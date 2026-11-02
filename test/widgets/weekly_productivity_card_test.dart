import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/widgets/weekly_productivity_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
    AppClock.debugNow = () => DateTime.utc(2026, 6, 2, 12);
  });

  tearDown(() {
    AppClock.debugNow = null;
  });

  for (final zone in ['America/New_York', 'Asia/Tokyo']) {
    testWidgets('本周效率在 $zone 按相同日历天数比较上周同段', (tester) async {
      await tester.runAsync(
        () => LocalTimezoneResolver.setApplicationTimeZone(zone),
      );
      expect(AppClock.now().weekday, DateTime.tuesday);
      final sessions = [
        PomodoroSession(
          id: 'current-week',
          startTime: DateTime.utc(2026, 6, 1, 11),
          endTime: DateTime.utc(2026, 6, 1, 12),
          durationSeconds: 3600,
          type: PomodoroType.focus,
        ),
        PomodoroSession(
          id: 'previous-week',
          startTime: DateTime.utc(2026, 5, 25, 11),
          endTime: DateTime.utc(2026, 5, 25, 12),
          durationSeconds: 3600,
          type: PomodoroType.focus,
        ),
      ];
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => TodoProvider()),
            ChangeNotifierProvider(create: (_) => HabitProvider()),
            ChangeNotifierProvider(
              create: (_) => PomodoroProvider()..sessions.addAll(sessions),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(body: WeeklyProductivityCard(onTap: () {})),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Each period spans Monday and Tuesday: 60 / (2 * 60) * 25 = 13.
      // A mixed application-zone instant and system-zone date incorrectly gave
      // the current period one day and a spurious upward trend.
      expect(find.text('13'), findsOneWidget);
      expect(find.text(I18n.tr('today.productivity.flat')), findsOneWidget);
      expect(find.textContaining('+12'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('320px 窄屏 + 2x 文字：单列统计、趋势落在分数下方且不溢出', (tester) async {
    _useViewSize(tester, 320);
    await tester.pumpWidget(_pumpCard(textScale: 2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(I18n.tr('today.productivity.title')), findsOneWidget);
    expect(find.text(I18n.tr('today.productivity.weekly')), findsOneWidget);
    expect(find.text(I18n.tr('today.productivity.score')), findsOneWidget);
    expect(find.text(I18n.tr('today.productivity.comparison')), findsOneWidget);

    final cardRect = tester.getRect(find.byType(WeeklyProductivityCard));
    final labels = [
      I18n.tr('today.productivity.completion_rate'),
      I18n.tr('nav.focus'),
      I18n.tr('nav.habit'),
    ];
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
      // 文字完整落在卡面内，没有被裁切到卡片之外。
      final rect = tester.getRect(find.text(label));
      expect(rect.left, greaterThanOrEqualTo(cardRect.left));
      expect(rect.right, lessThanOrEqualTo(cardRect.right));
      final widget = tester.widget<Text>(find.text(label));
      expect(widget.overflow, isNull);
      expect(widget.maxLines, isNull);
    }

    // 文字放大 2 倍且宽度只有 320px 时，三栏降为单列（逐行往下排）。
    final labelTops = labels
        .map((label) => tester.getTopLeft(find.text(label)).dy)
        .toList();
    expect(labelTops[0], lessThan(labelTops[1]));
    expect(labelTops[1], lessThan(labelTops[2]));

    // 趋势块位于分数下方（而不是右侧）。
    final trendRect = tester.getRect(
      find.text(I18n.tr('today.productivity.comparison')),
    );
    expect(trendRect.left, lessThan(cardRect.center.dx));
  });

  testWidgets('390 手机：三栏统计同行、趋势在分数右侧并整卡可点击', (tester) async {
    _useViewSize(tester, 390);
    var taps = 0;
    await tester.pumpWidget(_pumpCard(onTap: () => taps++));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final labels = [
      I18n.tr('today.productivity.completion_rate'),
      I18n.tr('nav.focus'),
      I18n.tr('nav.habit'),
    ];
    final labelTops = labels
        .map((label) => tester.getTopLeft(find.text(label)).dy)
        .toSet();
    expect(labelTops.length, 1);

    final cardRect = tester.getRect(find.byType(WeeklyProductivityCard));
    final trendRect = tester.getRect(
      find.text(I18n.tr('today.productivity.comparison')),
    );
    expect(trendRect.left, greaterThan(cardRect.center.dx));

    await tester.tap(find.byType(WeeklyProductivityCard));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('English 文案与长统计值在窄屏 2x 下完整渲染', (tester) async {
    _useViewSize(tester, 320);
    // 40 个一小时番茄 → 本周专注 2400 分钟，验证长数值不被省略号截断。
    final sessions = List<PomodoroSession>.generate(
      40,
      (index) => PomodoroSession(
        id: 'focus-$index',
        startTime: DateTime.utc(2026, 6, 1, 1),
        endTime: DateTime.utc(2026, 6, 1, 2),
        durationSeconds: 3600,
        type: PomodoroType.focus,
      ),
    );
    await tester.pumpWidget(
      _pumpCard(
        onTap: () {},
        locale: AppLocale.en,
        textScale: 2,
        sessions: sessions,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Time footprints'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('Score'), findsOneWidget);
    expect(find.text('Same days last week'), findsOneWidget);

    final focusValue = find.text('2400${I18n.tr('unit.min')}');
    expect(focusValue, findsOneWidget);
    expect(tester.widget<Text>(focusValue).overflow, isNull);
    expect(tester.widget<Text>(focusValue).maxLines, isNull);
  });

  testWidgets('空数据时本周效率为 0 且不溢出', (tester) async {
    _useViewSize(tester, 320);
    await tester.pumpWidget(_pumpCard(textScale: 2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('0'), findsOneWidget);
    expect(find.text(I18n.tr('today.productivity.flat')), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('0${I18n.tr('unit.min')}'), findsOneWidget);
    expect(find.text('0${I18n.tr('today.unit.times')}'), findsOneWidget);
  });

  testWidgets('深色主题沿用主题调色并正常渲染', (tester) async {
    _useViewSize(tester, 390);
    await tester.pumpWidget(
      _pumpCard(onTap: () {}, theme: ThemeData.dark(useMaterial3: true)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(I18n.tr('today.productivity.title')), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text(I18n.tr('today.productivity.flat')), findsOneWidget);
  });

  testWidgets('键盘 Tab 聚焦后 Enter 和 Space 可激活整卡', (tester) async {
    _useViewSize(tester, 390);
    var taps = 0;
    await tester.pumpWidget(_pumpCard(onTap: () => taps++));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    expect(focusedContext, isNotNull);
    // 焦点确实落在整卡内部（InkWell 的焦点节点），而不是页面其它位置。
    expect(
      focusedContext!.findAncestorWidgetOfExactType<WeeklyProductivityCard>(),
      isNotNull,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(taps, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(taps, 2);
  });

  testWidgets('整卡只暴露一个 button 语义节点并带操作提示', (tester) async {
    _useViewSize(tester, 390);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_pumpCard(onTap: () {}));
    await tester.pumpAndSettle();

    final data = tester
        .getSemantics(find.byType(WeeklyProductivityCard))
        .getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.hint, I18n.tr('today.productivity.subtitle'));
    expect(data.label, contains(I18n.tr('today.productivity.title')));
    expect(data.label, contains(I18n.tr('today.productivity.weekly')));
    expect(data.label, contains('0'));
    expect(data.label, contains(I18n.tr('today.productivity.comparison')));
    expect(data.label, contains(I18n.tr('today.productivity.flat')));
    for (final key in [
      'today.productivity.completion_rate',
      'nav.focus',
      'nav.habit',
    ]) {
      expect(data.label, contains(I18n.tr(key)));
    }
    semantics.dispose();
  });

  testWidgets('768 平板宽度保持三栏与右侧趋势且不溢出', (tester) async {
    _useViewSize(tester, 768);
    await tester.pumpWidget(_pumpCard(onTap: () {}));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final labels = [
      I18n.tr('today.productivity.completion_rate'),
      I18n.tr('nav.focus'),
      I18n.tr('nav.habit'),
    ];
    expect(
      labels
          .map((label) => tester.getTopLeft(find.text(label)).dy)
          .toSet()
          .length,
      1,
    );
    final cardRect = tester.getRect(find.byType(WeeklyProductivityCard));
    expect(
      tester.getRect(find.text(I18n.tr('today.productivity.comparison'))).left,
      greaterThan(cardRect.center.dx),
    );
  });

  for (final platform in const [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.windows,
  ]) {
    testWidgets('$platform 平台的典型宽度下渲染无异常', (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = platform;
      try {
        _useViewSize(tester, platform == TargetPlatform.iOS ? 390 : 1280);
        await tester.pumpWidget(_pumpCard());
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(I18n.tr('today.productivity.title')), findsOneWidget);
        expect(find.text('0'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    });
  }
}

/// 用固定视口宽度渲染，模拟 320/390 手机、768 平板、1280 桌面。
void _useViewSize(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// 构造成与“我的”页一致的 Provider / 主题环境。
Widget _pumpCard({
  VoidCallback? onTap,
  AppLocale locale = AppLocale.zh,
  ThemeData? theme,
  double textScale = 1,
  List<PomodoroSession> sessions = const <PomodoroSession>[],
}) {
  I18n.setLocale(locale);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => TodoProvider()),
      ChangeNotifierProvider(create: (_) => HabitProvider()),
      ChangeNotifierProvider(
        create: (_) => PomodoroProvider()..sessions.addAll(sessions),
      ),
    ],
    child: MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: WeeklyProductivityCard(onTap: onTap ?? () {})),
    ),
  );
}
