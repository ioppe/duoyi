import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/web_target.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder get _filters => find.byKey(const ValueKey('todo_filter_bar'));
Finder get _views => find.byKey(const ValueKey('todo_view_switcher'));
Finder get _clear => find.byKey(const ValueKey('todo_clear_filters'));
Finder get _summary => find.byKey(const ValueKey('todo_today_summary_card'));

Finder _quickFilter(String label) => find
    .ancestor(
      of: find.descendant(of: _filters, matching: find.text(label)),
      matching: find.byType(InkWell),
    )
    .first;

Future<void> _openTodo(
  WidgetTester tester, {
  required Size size,
  required ThemeData theme,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final provider = TodoProvider();
  addTearDown(provider.dispose);
  final now = AppClock.now();
  await provider.addTodo(
    TodoItem(
      title: '今日任务',
      dueDate: now,
      quadrant: EisenhowerQuadrant.urgentImportant,
    ),
  );
  await provider.addTodo(
    TodoItem(
      title: '稍后任务',
      dueDate: now.add(const Duration(days: 3)),
      quadrant: EisenhowerQuadrant.notUrgentImportant,
    ),
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TodoProvider>.value(value: provider),
        ChangeNotifierProvider(create: (_) => HabitProvider()),
        ChangeNotifierProvider(create: (_) => GoalProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => ShareProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AiService()),
      ],
      child: MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const TodoScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectStacked(WidgetTester tester) {
  final summary = tester.getRect(_summary);
  final filters = tester.getRect(_filters);
  final views = tester.getRect(_views);
  expect(summary.bottom, lessThanOrEqualTo(filters.top));
  expect(filters.bottom, lessThanOrEqualTo(views.top));
  expect(summary.left, closeTo(filters.left, 0.01));
  expect(summary.right, closeTo(filters.right, 0.01));
  expect(find.byType(VerticalDivider), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await (FontLoader(
      DesignTokens.fontFamily,
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'))).load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WebTarget.debugWebBuild = true;
  });

  tearDown(() => WebTarget.debugWebBuild = null);

  for (final brand in [AppBrands.defaultBrand, AppBrands.liquidGlass]) {
    for (final (size, scale) in [
      (const Size(1280, 800), 1.0),
      (const Size(1600, 900), 1.0),
      (const Size(390, 844), 1.0),
      (const Size(320, 720), 1.5),
    ]) {
      testWidgets('${brand.id} $size ×$scale Web 筛选置顶且切换不改变高度', (tester) async {
        await _openTodo(
          tester,
          size: size,
          theme: brand.theme,
          textScale: scale,
        );
        _expectStacked(tester);
        expect(find.text('自定义视图 · 2/2'), findsOneWidget);
        expect(tester.widget<TextButton>(_clear).onPressed, isNull);
        final initialFilterRect = tester.getRect(_filters);
        final initialViewsRect = tester.getRect(_views);
        final initialButtonSize = tester.getSize(_quickFilter('今日'));
        expect(
          initialButtonSize.height,
          greaterThanOrEqualTo(DesignTokens.controlMinHeight),
        );

        await tester.tap(_quickFilter('今日'));
        await tester.pumpAndSettle();
        expect(find.text('自定义视图 · 1/2'), findsOneWidget);
        expect(tester.widget<TextButton>(_clear).onPressed, isNotNull);
        expect(tester.getRect(_filters), initialFilterRect);
        expect(tester.getRect(_views), initialViewsRect);
        expect(tester.getSize(_quickFilter('今日')), initialButtonSize);
        _expectStacked(tester);

        await tester.tap(_quickFilter('今日'));
        await tester.pumpAndSettle();
        expect(find.text('自定义视图 · 2/2'), findsOneWidget);
        expect(tester.getRect(_filters), initialFilterRect);
        expect(tester.getRect(_views), initialViewsRect);
        await tester.tap(_quickFilter('今日'));
        await tester.pumpAndSettle();
        await tester.tap(_clear);
        await tester.pumpAndSettle();
        expect(find.text('自定义视图 · 2/2'), findsOneWidget);
        expect(tester.getRect(_filters), initialFilterRect);
        expect(tester.getRect(_views), initialViewsRect);

        for (final label in ['列表', '看板', '四象限']) {
          await tester.tap(
            find.descendant(of: _views, matching: find.text(label)),
          );
          await tester.pumpAndSettle();
          _expectStacked(tester);
          expect(find.text('今日任务'), findsOneWidget);
          expect(find.text('稍后任务'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('快捷筛选与菜单高度一致，选择象限后筛选区和页签保持位置', (tester) async {
    await _openTodo(
      tester,
      size: const Size(1280, 800),
      theme: AppBrands.defaultBrand.theme,
    );
    final initialFilters = tester.getRect(_filters);
    final initialViews = tester.getRect(_views);
    final controlHeight = tester.getSize(_quickFilter('今日')).height;
    expect(tester.getSize(find.byTooltip('象限')).height, controlHeight);
    expect(tester.getSize(find.byTooltip('优先级')).height, controlHeight);
    await tester.tap(find.byTooltip('象限'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重要且紧急').last);
    await tester.pumpAndSettle();
    expect(find.text('自定义视图 · 1/2'), findsOneWidget);
    expect(tester.getRect(_filters), initialFilters);
    expect(tester.getRect(_views), initialViews);
    expect(tester.getSize(find.byTooltip('重要且紧急')).height, controlHeight);
    await tester.tap(_clear);
    await tester.pumpAndSettle();
    expect(find.text('自定义视图 · 2/2'), findsOneWidget);
    expect(tester.getRect(_filters), initialFilters);
    expect(tester.getRect(_views), initialViews);
    expect(tester.takeException(), isNull);
  });
}
