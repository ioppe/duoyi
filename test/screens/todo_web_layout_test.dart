import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/desktop_tokens.dart';
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
import 'package:duoyi/widgets/eisenhower_matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

/// 完整 app 的绘制边界。用生产 TodoScreen 的真实 RenderRepaintBoundary 导出
/// PNG，避免另建一套伪 UI 截图；未设置环境变量时此 key 不产生任何副作用。
final GlobalKey _appBoundaryKey = GlobalKey();

/// 仅当 `DUOYI_TODO_LAYOUT_EXPORT=<目录>` 时把当前 app 绘制结果写成 PNG。
/// CI 与常规测试不设置该变量，因此不写文件、不改变断言。
Future<void> _exportPng(WidgetTester tester, String fileName) async {
  final dir = Platform.environment['DUOYI_TODO_LAYOUT_EXPORT'];
  if (dir == null || dir.isEmpty) return;
  final boundaryContext = _appBoundaryKey.currentContext;
  if (boundaryContext == null) return;
  final boundary = boundaryContext.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$dir/$fileName');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

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
    RepaintBoundary(
      key: _appBoundaryKey,
      child: MultiProvider(
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
          debugShowCheckedModeBanner: false,
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
    ),
  );
  await tester.pumpAndSettle();
}

/// 顶部筛选布局（Web 与 macOS 共用）：概要 → 筛选 → 页签 → 内容，
/// 任何宽度都不出现右侧筛选栏或 VerticalDivider。
void _expectTopFilterLayout(WidgetTester tester) {
  final summary = tester.getRect(_summary);
  final filters = tester.getRect(_filters);
  final views = tester.getRect(_views);
  expect(summary.bottom, lessThanOrEqualTo(filters.top));
  expect(filters.bottom, lessThanOrEqualTo(views.top));
  expect(summary.left, closeTo(filters.left, 0.01));
  expect(summary.right, closeTo(filters.right, 0.01));
  expect(find.byType(VerticalDivider), findsNothing);
}

/// 顶部筛选布局的行为基线：筛选计数与清空态、筛选前后 rect 不位移、
/// 三种视图均保留数据且无布局异常。Web 与 macOS 复用同一断言序列。
Future<void> _expectTopFilterBehavior(
  WidgetTester tester, {
  required Size size,
  required ThemeData theme,
  double textScale = 1,
  String? exportInitial,
  String? exportTodaySelected,
}) async {
  await _openTodo(tester, size: size, theme: theme, textScale: textScale);
  expect(
    tester.widget<EisenhowerMatrix>(find.byType(EisenhowerMatrix)).fourColumn,
    size.width >= DesktopTokens.breakpointThreeColumn,
    reason: '最宽 Web/macOS 档保留单行四列，窄屏使用 2×2',
  );
  if (exportInitial != null) await _exportPng(tester, exportInitial);
  _expectTopFilterLayout(tester);
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
  _expectTopFilterLayout(tester);
  if (exportTodaySelected != null) {
    await _exportPng(tester, exportTodaySelected);
  }

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
    await tester.tap(find.descendant(of: _views, matching: find.text(label)));
    await tester.pumpAndSettle();
    _expectTopFilterLayout(tester);
    expect(find.text('今日任务'), findsOneWidget);
    expect(find.text('稍后任务'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await (FontLoader(
      DesignTokens.fontFamily,
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'))).load();
    if (Platform.environment['DUOYI_TODO_LAYOUT_EXPORT']?.isNotEmpty ?? false) {
      final flutterRoot = Platform.environment['FLUTTER_ROOT'];
      if (flutterRoot == null || flutterRoot.isEmpty) {
        throw StateError('FLUTTER_ROOT is required for Todo layout PNG export');
      }
      final iconFont = await File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(iconFont.buffer.asByteData()))).load();
    }
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WebTarget.debugWebBuild = true;
  });

  tearDown(() {
    WebTarget.debugWebBuild = null;
  });

  // Web 原基线：两套 brand × 四个视口 × 文本缩放，筛选置顶且切换不改变高度。
  for (final brand in [AppBrands.defaultBrand, AppBrands.liquidGlass]) {
    for (final (size, scale) in [
      (const Size(1280, 800), 1.0),
      (const Size(1600, 900), 1.0),
      (const Size(390, 844), 1.0),
      (const Size(320, 720), 1.5),
    ]) {
      testWidgets('Web ${brand.id} $size ×$scale 筛选置顶且切换不改变高度', (tester) async {
        WebTarget.debugWebBuild = true;
        await _expectTopFilterBehavior(
          tester,
          size: size,
          theme: brand.theme,
          textScale: scale,
        );
      });
    }
  }

  testWidgets('Web 快捷筛选与菜单高度一致，选择象限后筛选区和页签保持位置', (tester) async {
    WebTarget.debugWebBuild = true;
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

  // macOS 原生（非 Web）：与 Web 同序置顶，覆盖用户宽屏截图 1440×732。
  for (final brand in [AppBrands.defaultBrand, AppBrands.liquidGlass]) {
    for (final (size, scale) in [
      (const Size(1280, 800), 1.0),
      (const Size(1600, 900), 1.0),
      (const Size(1440, 732), 1.0),
      (const Size(390, 844), 1.0),
      (const Size(320, 720), 1.5),
    ]) {
      testWidgets(
        'macOS ${brand.id} $size ×$scale 筛选置顶且切换不改变高度',
        (tester) async {
          WebTarget.debugWebBuild = false;
          expect(defaultTargetPlatform, TargetPlatform.macOS);
          final exportBrand = identical(brand, AppBrands.defaultBrand);
          final exportWide = size == const Size(1440, 732);
          final exportNarrow = size == const Size(320, 720);
          await _expectTopFilterBehavior(
            tester,
            size: size,
            theme: brand.theme,
            textScale: scale,
            exportInitial: !exportBrand
                ? null
                : exportWide
                ? 'macos-1440-top.png'
                : exportNarrow
                ? 'macos-320-top.png'
                : null,
            exportTodaySelected: exportBrand && exportWide
                ? 'macos-1440-today-filter.png'
                : null,
          );
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );
    }
  }

  testWidgets(
    'macOS 快捷筛选与菜单高度一致，选择象限后筛选区和页签保持位置',
    (tester) async {
      WebTarget.debugWebBuild = false;
      expect(defaultTargetPlatform, TargetPlatform.macOS);
      await _openTodo(
        tester,
        size: const Size(1440, 732),
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
      _expectTopFilterLayout(tester);
      await tester.tap(_clear);
      await tester.pumpAndSettle();
      expect(find.text('自定义视图 · 2/2'), findsOneWidget);
      expect(tester.getRect(_filters), initialFilters);
      expect(tester.getRect(_views), initialViews);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  // 控制用例：其他原生平台布局必须保持原样。
  testWidgets(
    'Android 390 非 Web 保持页签在概要之前',
    (tester) async {
      WebTarget.debugWebBuild = false;
      await _openTodo(
        tester,
        size: const Size(390, 844),
        theme: AppBrands.defaultBrand.theme,
      );
      final summary = tester.getRect(_summary);
      final views = tester.getRect(_views);
      expect(views.bottom, lessThanOrEqualTo(summary.top));
      expect(find.byType(VerticalDivider), findsNothing);
      expect(find.text('今日任务'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'Linux 1600 宽屏保留右侧栏筛选布局',
    (tester) async {
      WebTarget.debugWebBuild = false;
      await _openTodo(
        tester,
        size: const Size(1600, 900),
        theme: AppBrands.defaultBrand.theme,
      );
      expect(
        tester
            .widget<EisenhowerMatrix>(find.byType(EisenhowerMatrix))
            .fourColumn,
        isTrue,
      );
      final dividers = find.byType(VerticalDivider);
      expect(dividers, findsWidgets);
      final divider = tester.getRect(dividers.first);
      final summary = tester.getRect(_summary);
      final filters = tester.getRect(_filters);
      final views = tester.getRect(_views);
      expect(summary.left, greaterThan(divider.left));
      expect(filters.left, closeTo(summary.left, 0.01));
      expect(filters.right, closeTo(summary.right, 0.01));
      expect(summary.bottom, lessThanOrEqualTo(filters.top));
      expect(views.right, lessThanOrEqualTo(divider.left));
      expect(find.text('今日任务'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
