import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/habit_detail_screen.dart';
import 'package:duoyi/screens/habit_screen.dart';
import 'package:duoyi/widgets/habit_heatmap.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder get _add => find.byKey(const ValueKey('habit_add_action'));
Finder _card(String id) => find.byKey(ValueKey('habit_checkin_card_$id'));
Finder _filter(String status) => find.byKey(ValueKey('habit_filter_$status'));

Future<void> _open(
  WidgetTester tester,
  HabitProvider provider, {
  Size size = const Size(1280, 900),
  ThemeData? theme,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(provider.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<HabitProvider>.value(value: provider),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        theme: theme ?? AppBrands.defaultBrand.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const HabitScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<HabitProvider> _twoHabits() async {
  final provider = HabitProvider();
  await provider.addHabit(Habit(id: 'read', name: '阅读', category: '学习'));
  await provider.addHabit(
    Habit(
      id: 'walk',
      name: '散步',
      category: '健康',
      completions: {Habit(id: 'key', name: 'key').todayKey(): 1},
    ),
  );
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(DesignTokens.fontFamilyRounded)..addFont(
          rootBundle.load('assets/fonts/ResourceHanRoundedCN-Bold.ttf'),
        ))
        .load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final theme in [
    AppBrands.defaultBrand.theme,
    AppBrands.starRail.theme,
  ]) {
    for (final (size, scale) in [
      (const Size(1600, 1000), 1.0),
      (const Size(390, 844), 1.0),
      (const Size(320, 720), 1.5),
    ]) {
      testWidgets('${theme.brightness} $size ×$scale 两个页签各只有一处创建入口和各自空态', (
        tester,
      ) async {
        await _open(
          tester,
          HabitProvider(),
          size: size,
          theme: theme,
          textScale: scale,
        );
        expect(find.byType(TabBar), findsOneWidget);
        expect(find.byType(VerticalDivider), findsNothing);
        expect(_add, findsOneWidget);
        expect(find.text('添加习惯'), findsOneWidget);
        expect(find.text('今天没有习惯任务'), findsOneWidget);
        expect(find.byType(HabitHeatmap), findsNothing);
        await tester.tap(find.text('热度图'));
        await tester.pumpAndSettle();
        expect(find.byType(HabitHeatmap), findsOneWidget);
        expect(find.text('今天没有习惯任务'), findsNothing);
        expect(find.text('让坚持留下痕迹'), findsOneWidget);
        expect(_add, findsOneWidget);
        expect(find.text('添加习惯'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('待完成筛选随打卡更新，已达标筛选可撤回并返回全部', (tester) async {
    final provider = await _twoHabits();
    await _open(tester, provider);
    expect(find.text('全部 2'), findsOneWidget);
    expect(find.text('待完成 1'), findsOneWidget);
    expect(find.text('已达标 1'), findsOneWidget);
    await tester.tap(_filter('pending'));
    await tester.pumpAndSettle();
    expect(_card('read'), findsOneWidget);
    expect(_card('walk'), findsNothing);
    await tester.tap(
      find.descendant(of: _card('read'), matching: find.text('打卡')),
    );
    await tester.pumpAndSettle();
    expect(provider.habits.first.todayCount(), 1);
    expect(find.text('今天的目标都完成了'), findsOneWidget);
    expect(find.text('待完成 0'), findsOneWidget);
    expect(find.text('已达标 2'), findsOneWidget);
    await tester.tap(_filter('completed'));
    await tester.pumpAndSettle();
    expect(_card('read'), findsOneWidget);
    expect(_card('walk'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: _card('read'),
        matching: find.byKey(const ValueKey('habit-undo-inline-button')),
      ),
    );
    await tester.pumpAndSettle();
    expect(provider.habits.first.todayCount(), 0);
    expect(_card('read'), findsNothing);
    expect(find.text('待完成 1'), findsOneWidget);
    await tester.tap(_filter('all'));
    await tester.pumpAndSettle();
    expect(_card('read'), findsOneWidget);
    expect(_card('walk'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('今天无安排时给出休息日说明，已有习惯仍可查看详情', (tester) async {
    final provider = HabitProvider();
    await provider.addHabit(
      Habit(
        id: 'rest',
        name: '明日阅读',
        category: '学习',
        activeWeekdays: [AppClock.now().weekday % 7],
      ),
    );
    await _open(tester, provider);
    expect(find.text('今天没有安排打卡'), findsOneWidget);
    expect(find.text('今天没有习惯任务'), findsNothing);
    await tester.tap(find.text('查看全部习惯'));
    await tester.pumpAndSettle();
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
    await tester.scrollUntilVisible(
      find.text('明日阅读'),
      140,
      scrollable: find
          .descendant(
            of: find.byKey(const PageStorageKey('habit_history_scroll_view')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('明日阅读'));
    await tester.pumpAndSettle();
    expect(find.byType(HabitDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(1280, 900), const Size(390, 844)]) {
    testWidgets('$size 唯一创建入口可打开原有习惯表单', (tester) async {
      await _open(tester, HabitProvider(), size: size);
      await tester.tap(_add);
      await tester.pumpAndSettle();
      expect(find.byType(AppModalSheet), findsOneWidget);
      expect(find.text('新建习惯'), findsOneWidget);
      expect(find.widgetWithText(TextField, '习惯名称'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
