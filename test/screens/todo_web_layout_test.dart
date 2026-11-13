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
  bool pushed = false,
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
          home: pushed
              ? Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      key: const ValueKey('open_todo_route'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const TodoScreen(),
                        ),
                      ),
                      child: const Text('Open tasks'),
                    ),
                  ),
                )
              : const TodoScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (pushed) {
    await tester.tap(find.byKey(const ValueKey('open_todo_route')));
    await tester.pumpAndSettle();
  }
}

/// 顶部筛选布局（Web 与 macOS 共用）：概要 → 筛选 → 页签 → 内容，
/// 任何宽度都不出现右侧筛选栏或 VerticalDivider。
void _expectTopFilterLayout(WidgetTester tester, {String? reason}) {
  final summary = tester.getRect(_summary);
  final filters = tester.getRect(_filters);
  final views = tester.getRect(_views);
  expect(summary.bottom, lessThanOrEqualTo(filters.top), reason: reason);
  expect(filters.bottom, lessThanOrEqualTo(views.top), reason: reason);
  expect(summary.left, closeTo(filters.left, 0.01), reason: reason);
  expect(summary.right, closeTo(filters.right, 0.01), reason: reason);
  expect(find.byType(VerticalDivider), findsNothing, reason: reason);
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
  bool expandFilters = false,
  bool collapseBeforeViewSwitch = false,
}) async {
  await _openTodo(tester, size: size, theme: theme, textScale: textScale);
  expect(
    tester.widget<EisenhowerMatrix>(find.byType(EisenhowerMatrix)).fourColumn,
    size.width >= DesktopTokens.breakpointThreeColumn,
    reason: '最宽 Web/macOS 档保留单行四列，窄屏使用 2×2',
  );
  if (expandFilters) {
    await tester.tap(find.byKey(const ValueKey('todo_filter_toggle')));
    await tester.pumpAndSettle();
  }
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

  // 桌面收起是默认态：视图切换在收起态验证，避免展开面板压缩内容区
  // （看板泳道按可视区懒加载，压缩后末位卡片可能不在构建范围）。
  if (collapseBeforeViewSwitch) {
    await tester.tap(find.byKey(const ValueKey('todo_filter_toggle')));
    await tester.pumpAndSettle();
  }

  for (final label in ['列表', '看板', '四象限']) {
    await tester.tap(find.descendant(of: _views, matching: find.text(label)));
    await tester.pumpAndSettle();
    _expectTopFilterLayout(tester, reason: label);
    expect(find.text('今日任务'), findsOneWidget, reason: '$label 视图应保留今日任务');
    expect(find.text('稍后任务'), findsOneWidget, reason: '$label 视图应保留稍后任务');
    expect(tester.takeException(), isNull, reason: label);
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
            expandFilters: true,
            collapseBeforeViewSwitch: true,
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
      // 桌面筛选默认收起：先展开再验证控件几何与位置稳定。
      await tester.tap(find.byKey(const ValueKey('todo_filter_toggle')));
      await tester.pumpAndSettle();
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

  testWidgets(
    'macOS 桌面筛选默认收起一行，鼠标/键盘展开后全部条件可达且值保留',
    (tester) async {
      WebTarget.debugWebBuild = false;
      expect(defaultTargetPlatform, TargetPlatform.macOS);
      await _openTodo(
        tester,
        size: const Size(1440, 732),
        theme: AppBrands.defaultBrand.theme,
      );

      // 默认收起：一行数量 / 筛选开关 + 清空 + 箭头，摘要卡仍在。
      // 「象限」菜单只在展开后存在，用它判断收起 / 展开，避免「今日」
      // 同时出现在快捷 chip 与日期菜单标签上造成歧义。
      final quadrantMenu = find.descendant(
        of: _filters,
        matching: find.byTooltip('象限'),
      );
      final toggle = find.byKey(const ValueKey('todo_filter_toggle'));
      expect(toggle, findsOneWidget);
      expect(_summary, findsOneWidget);
      expect(find.text('自定义视图 · 2/2'), findsOneWidget);
      expect(quadrantMenu, findsNothing);
      final collapsedRect = tester.getRect(_filters);
      expect(collapsedRect.height, lessThan(80));

      // 鼠标展开：全部快捷条件与下拉菜单同屏可达。
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(_filters).height,
        greaterThan(collapsedRect.height),
      );
      for (final label in ['今日', '逾期', '7天内', '已完成']) {
        expect(
          find.descendant(of: _filters, matching: find.text(label)),
          findsWidgets,
          reason: '展开后 $label 应可见',
        );
      }
      for (final tooltip in ['象限', '优先级', '日期', '完成状态']) {
        expect(
          find.descendant(of: _filters, matching: find.byTooltip(tooltip)),
          findsOneWidget,
          reason: '展开后 $tooltip 菜单应可见',
        );
      }
      // 桌面用 Wrap 自动换行，不靠横向拖动：控件右缘不越出筛选栏。
      final expandedRect = tester.getRect(_filters);
      expect(
        tester.getRect(quadrantMenu).right,
        lessThanOrEqualTo(expandedRect.right + 0.01),
      );
      expect(
        tester.getRect(find.byTooltip('完成状态')).right,
        lessThanOrEqualTo(expandedRect.right + 0.01),
      );
      // 桌面展开不靠横向拖动：筛选区里没有横向滚动容器。
      expect(
        find.descendant(
          of: _filters,
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );

      // 选择条件后收起 / 再展开，筛选值不丢。
      await tester.tap(_quickFilter('今日'));
      await tester.pumpAndSettle();
      expect(find.text('自定义视图 · 1/2'), findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('自定义视图 · 1/2'), findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('自定义视图 · 1/2'), findsOneWidget);
      expect(tester.widget<TextButton>(_clear).onPressed, isNotNull);

      // 键盘：聚焦折叠行后 Enter 与鼠标同一激活路径。
      tester.widget<InkWell>(toggle).focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(quadrantMenu, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(quadrantMenu, findsOneWidget);

      // 清空恢复 2/2。
      await tester.tap(_clear);
      await tester.pumpAndSettle();
      expect(find.text('自定义视图 · 2/2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  // Android 窄屏保留自己的紧凑布局，不套用 Web/macOS 的顶部概要。
  testWidgets(
    'Android 390 非 Web 保持页签在折叠筛选之前',
    (tester) async {
      WebTarget.debugWebBuild = false;
      await _openTodo(
        tester,
        size: const Size(390, 844),
        theme: AppBrands.defaultBrand.theme,
      );
      expect(_summary, findsNothing);
      final filters = tester.getRect(_filters);
      final views = tester.getRect(_views);
      expect(views.bottom, lessThanOrEqualTo(filters.top));
      expect(find.byKey(const ValueKey('todo_filter_toggle')), findsOneWidget);
      expect(
        find.descendant(of: _filters, matching: find.text('今日')),
        findsNothing,
      );
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
  testWidgets(
    'macOS 路由待办页提供返回按钮和稳定的添加任务文案',
    (tester) async {
      WebTarget.debugWebBuild = false;
      await _openTodo(
        tester,
        size: const Size(2000, 900),
        theme: AppBrands.defaultBrand.theme,
        pushed: true,
      );
      expect(find.byKey(const ValueKey('todo_back_button')), findsOneWidget);
      expect(find.text('添加任务'), findsOneWidget);
      expect(find.text('添加第一个任务'), findsNothing);
      expect(find.byKey(const ValueKey('todo_filter_toggle')), findsOneWidget);
      expect(
        find.descendant(of: _filters, matching: find.text('今日')),
        findsNothing,
      );
      await _exportPng(tester, 'macos-todo-collapsed-with-back.png');
      await tester.tap(find.byKey(const ValueKey('todo_back_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('open_todo_route')), findsOneWidget);
      expect(find.byType(TodoScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'macOS 路由 Escape 先关闭筛选菜单，再返回上一页',
    (tester) async {
      WebTarget.debugWebBuild = false;
      await _openTodo(
        tester,
        size: const Size(1280, 900),
        theme: AppBrands.defaultBrand.theme,
        pushed: true,
      );
      await tester.tap(find.byKey(const ValueKey('todo_filter_toggle')));
      await tester.pumpAndSettle();
      await _exportPng(tester, 'macos-todo-expanded-with-back.png');
      await tester.tap(
        find.descendant(of: _filters, matching: find.text('象限')),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TodoScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('todo_back_button')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TodoScreen), findsNothing);
      expect(find.byKey(const ValueKey('open_todo_route')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
