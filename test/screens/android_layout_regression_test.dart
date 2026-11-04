import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/web_target.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/mine_screen.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/app_create_fab.dart';
import 'package:duoyi/widgets/quick_capture_fab.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 原生安卓窄屏布局打磨的回归保护：
/// 1. 待办页顶部在安卓手机上压缩为「页签 + 折叠筛选栏」，桌面/Web 不变；
/// 2. 待办页不再有右下角悬浮创建按钮，创建入口收进 AppBar；
/// 3. 首页快速捕获与 HabitScreen 复用同一个 [AppCreateFab] 视觉与尺寸；
/// 4. 「我的」功能分组的卡片内左右留白 ≥16，分隔线两侧留白。

Finder get _filterBar => find.byKey(const ValueKey('todo_filter_bar'));
Finder get _filterToggle => find.byKey(const ValueKey('todo_filter_toggle'));
Finder get _clearFilters => find.byKey(const ValueKey('todo_clear_filters'));
Finder get _summaryCard =>
    find.byKey(const ValueKey('todo_today_summary_card'));
Finder get _viewSwitcher => find.byKey(const ValueKey('todo_view_switcher'));
Finder get _createAction => find.byKey(const ValueKey('todo_create_action'));

Finder _quickFilter(String label) => find
    .ancestor(
      of: find.descendant(of: _filterBar, matching: find.text(label)),
      matching: find.byType(InkWell),
    )
    .first;

Future<TodoProvider> _pumpTodoScreen(
  WidgetTester tester, {
  required Size size,
  ThemeData? theme,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final todos = TodoProvider();
  addTearDown(todos.dispose);
  final now = AppClock.now();
  await todos.addTodo(
    TodoItem(
      title: '今日任务',
      dueDate: now,
      quadrant: EisenhowerQuadrant.urgentImportant,
    ),
  );
  await todos.addTodo(
    TodoItem(
      title: '稍后任务',
      dueDate: now.add(const Duration(days: 3)),
      quadrant: EisenhowerQuadrant.notUrgentImportant,
    ),
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TodoProvider>.value(value: todos),
        ChangeNotifierProvider(create: (_) => HabitProvider()),
        ChangeNotifierProvider(create: (_) => GoalProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => ShareProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AiService()),
      ],
      child: MaterialApp(
        theme: theme ?? AppBrands.defaultBrand.theme,
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
  return todos;
}

Future<void> _pumpMineScreen(
  WidgetTester tester, {
  required Size size,
  required ThemeData theme,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TodoProvider()),
        ChangeNotifierProvider(create: (_) => HabitProvider()),
        ChangeNotifierProvider(create: (_) => PomodoroProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => CloudSyncProvider()),
        ChangeNotifierProvider(create: (_) => CalendarProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => CountdownProvider()),
        ChangeNotifierProvider(create: (_) => NoteProvider()),
        ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
        ChangeNotifierProvider(create: (_) => DiaryProvider()),
        ChangeNotifierProvider(create: (_) => GoalProvider()),
        ChangeNotifierProvider(create: (_) => CourseProvider()),
        ChangeNotifierProvider(create: (_) => AppLockProvider()),
        ChangeNotifierProvider(create: (_) => PreferencesProvider()),
        ChangeNotifierProvider(create: (_) => AchievementProvider()),
        ChangeNotifierProvider(create: (_) => ShareProvider()),
        ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
        ChangeNotifierProvider(create: (_) => NotificationService()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AiService()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => LocationReminderProvider()),
        ChangeNotifierProvider(create: (_) => CalendarSyncProvider()),
        ChangeNotifierProvider(
          create: (_) => AppUpdateService(
            repo: 'dq52099/duoyi',
            currentVersion: AppVersion.name,
          ),
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
        home: const MineScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await (FontLoader(
      DesignTokens.fontFamily,
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'))).load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    WebTarget.debugWebBuild = null;
  });

  tearDown(() {
    WebTarget.debugWebBuild = null;
  });

  testWidgets(
    '原生安卓 390×844 待办页顶部压缩为页签 + 折叠筛选栏',
    (tester) async {
      await _pumpTodoScreen(tester, size: const Size(390, 844));

      // 大型今日概要卡在手机窄屏收起，主视图区留给四象限。
      expect(_summaryCard, findsNothing);
      // 右下角「添加第一个任务」悬浮按钮已移除。
      expect(find.byType(FloatingActionButton), findsNothing);
      // 视图页签保留，筛选折叠成一行。
      expect(_viewSwitcher, findsOneWidget);
      expect(_filterToggle, findsOneWidget);

      final toolbarHeight =
          tester.getBottomLeft(_filterBar).dy -
          tester.getTopLeft(_viewSwitcher).dy;
      expect(toolbarHeight, lessThanOrEqualTo(120));
      expect(
        tester.getSize(_filterToggle).height,
        closeTo(DesignTokens.controlMinHeight, 2),
      );

      // 折叠态：只显示匹配数量与清空，完整筛选控件隐藏。
      expect(find.text('自定义视图 · 2/2'), findsOneWidget);
      expect(
        find.descendant(of: _filterBar, matching: find.text('7天内')),
        findsNothing,
      );
      expect(find.byTooltip('象限'), findsNothing);
      expect(tester.widget<TextButton>(_clearFilters).onPressed, isNull);

      // 展开后 4 个快捷条件与全部菜单齐备。
      await tester.tap(_filterToggle);
      await tester.pumpAndSettle();
      for (final label in ['今日', '逾期', '7天内', '已完成']) {
        expect(
          find.descendant(of: _filterBar, matching: find.text(label)),
          findsOneWidget,
          reason: '展开后必须保留快捷条件 $label',
        );
      }
      for (final menu in ['象限', '优先级', '日期', '完成状态']) {
        expect(
          find.byTooltip(menu),
          findsOneWidget,
          reason: '展开后必须保留 $menu 菜单',
        );
      }

      // 过滤逻辑与清空仍然生效。
      await tester.tap(_quickFilter('今日'));
      await tester.pumpAndSettle();
      expect(find.text('自定义视图 · 1/2'), findsOneWidget);
      expect(tester.widget<TextButton>(_clearFilters).onPressed, isNotNull);
      await tester.tap(_clearFilters);
      await tester.pumpAndSettle();
      expect(find.text('自定义视图 · 2/2'), findsOneWidget);
      expect(tester.widget<TextButton>(_clearFilters).onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    '原生安卓 320×720 放大字体折叠筛选栏可点击且不溢出',
    (tester) async {
      await _pumpTodoScreen(tester, size: const Size(320, 720), textScale: 1.5);

      expect(_summaryCard, findsNothing);
      expect(_filterToggle, findsOneWidget);
      expect(
        tester.getSize(_filterToggle).height,
        greaterThanOrEqualTo(DesignTokens.controlMinHeight),
      );
      await tester.tap(_filterToggle);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: _filterBar, matching: find.text('今日')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('todo_create_action')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'Web 与桌面窄屏保持概要卡和常驻筛选布局',
    (tester) async {
      // Web 窄屏（原有行为）。
      WebTarget.debugWebBuild = true;
      await _pumpTodoScreen(tester, size: const Size(390, 844));
      expect(_summaryCard, findsOneWidget);
      expect(_filterToggle, findsNothing);
      expect(
        find.descendant(of: _filterBar, matching: find.text('7天内')),
        findsOneWidget,
      );
      // 清理本次 Web 模拟，避免影响后续桌面断言。
      await tester.pumpWidget(const SizedBox.shrink());
      WebTarget.debugWebBuild = null;

      // macOS 桌面窄窗口（非安卓原生）：保持概要卡 + 常驻筛选。
      await _pumpTodoScreen(tester, size: const Size(390, 844));
      expect(_summaryCard, findsOneWidget);
      expect(_filterToggle, findsNothing);
      expect(
        find.descendant(of: _filterBar, matching: find.text('7天内')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    '待办页创建入口在页头，批量模式下隐藏',
    (tester) async {
      await _pumpTodoScreen(tester, size: const Size(390, 844));

      final themeProvider = tester
          .element(find.byType(TodoScreen))
          .read<ThemeProvider>();
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(_createAction, findsOneWidget);
      expect(
        tester.widget<IconButton>(_createAction).tooltip,
        themeProvider.brand.strings.todoCreateTitle,
      );

      await tester.tap(_createAction);
      await tester.pumpAndSettle();
      expect(find.byType(AppModalSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('todo_create_sheet')), findsOneWidget);
      Navigator.of(tester.element(find.byType(AppModalSheet))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(AppModalSheet), findsNothing);

      // 批量模式保持原有行为：页头只保留选择操作，不出现创建入口。
      await tester.tap(find.byTooltip('批量操作'));
      await tester.pumpAndSettle();
      expect(_createAction, findsNothing);
      expect(find.textContaining('已选择'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('创建按钮与首页快速捕获共用同一视觉、尺寸与长按行为', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const label = '新建待办';

    await tester.pumpWidget(
      MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        home: Scaffold(
          floatingActionButton: AppCreateFab(label: label, onPressed: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final sharedSize = tester.getSize(find.byType(FloatingActionButton));
    expect(sharedSize.height, greaterThanOrEqualTo(AppCreateFab.minHeight));
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.byType(FloatingActionButton),
              matching: find.byType(Icon),
            ),
          )
          .size,
      DesignTokens.controlIconSize,
    );
    final labelStyle = DefaultTextStyle.of(
      tester.element(find.text(label)),
    ).style.merge(tester.widget<Text>(find.text(label)).style);
    expect(labelStyle.fontSize, DesignTokens.fontSizeButton);
    expect(labelStyle.fontWeight, DesignTokens.fontWeightMedium);

    // 首页快速捕获（带标签分支）复用同一实现：同文案下 bounds 完全一致。
    var created = 0;
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider(create: (_) => AiService())],
        child: MaterialApp(
          theme: AppBrands.defaultBrand.theme,
          home: Scaffold(
            floatingActionButton: QuickCaptureFab(
              label: label,
              onCreate: () => created++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final homeFab = find.byKey(const ValueKey('home_create_button'));
    expect(homeFab, findsOneWidget);
    expect(tester.getSize(find.byType(FloatingActionButton)), sharedSize);

    // 长按展开快捷菜单并切成关闭图标。
    await tester.longPress(homeFab);
    await tester.pumpAndSettle();
    expect(find.text(I18n.tr('quick.menu.note')), findsOneWidget);
    expect(
      find.descendant(of: homeFab, matching: find.byIcon(Icons.close)),
      findsOneWidget,
    );

    // 点击关闭，不触发创建。
    await tester.tap(homeFab);
    await tester.pumpAndSettle();
    expect(find.text(I18n.tr('quick.menu.note')), findsNothing);
    expect(
      find.descendant(of: homeFab, matching: find.byIcon(Icons.add)),
      findsOneWidget,
    );
    expect(created, 0);

    // 关闭状态下点击执行创建回调。
    await tester.tap(homeFab);
    await tester.pumpAndSettle();
    expect(created, 1);
    expect(tester.takeException(), isNull);
  });

  for (final (size, scale) in [
    (const Size(320, 720), 1.5),
    (const Size(390, 844), 1.0),
  ]) {
    for (final theme in [
      AppBrands.defaultBrand.theme,
      AppBrands.starRail.theme,
    ]) {
      testWidgets('我的功能分组内容左右留白 $size ×$scale ${theme.brightness.name}', (
        tester,
      ) async {
        await _pumpMineScreen(
          tester,
          size: size,
          theme: theme,
          textScale: scale,
        );

        final scrollable = find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.restorationId == 'mine_screen_list',
        );
        final tile = find.byKey(const ValueKey('mine_apps_entry'));
        await tester.scrollUntilVisible(tile, 200, scrollable: scrollable);
        await tester.pumpAndSettle();

        final card = tester.getRect(
          find.byKey(const ValueKey('mine_menu_card')),
        );
        final icon = tester.getRect(
          find.descendant(of: tile, matching: find.byIcon(Icons.apps_outlined)),
        );
        final trailing = tester.getRect(
          find.descendant(of: tile, matching: find.byIcon(Icons.chevron_right)),
        );
        expect(
          icon.left - card.left,
          greaterThanOrEqualTo(DesignTokens.spaceLg),
          reason: '卡片左边缘到图标至少 16',
        );
        expect(
          card.right - trailing.right,
          greaterThanOrEqualTo(DesignTokens.spaceLg - 0.5),
          reason: '卡片右边缘到尾部控件至少 16',
        );
        expect(card.right - card.left, lessThanOrEqualTo(size.width));
        expect(trailing.left, greaterThan(icon.right));

        final dividers = find.descendant(
          of: find.byKey(const ValueKey('mine_menu_card')),
          matching: find.byType(Divider),
        );
        expect(dividers, findsWidgets);
        for (final divider in tester.widgetList<Divider>(dividers)) {
          expect(divider.indent, greaterThanOrEqualTo(DesignTokens.spaceLg));
          expect(divider.endIndent, greaterThanOrEqualTo(DesignTokens.spaceLg));
        }
        expect(tester.takeException(), isNull);

        // 导航入口仍可点击（几何调整不影响命中区域）。
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(find.text(I18n.tr('mine.menu.apps')), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
