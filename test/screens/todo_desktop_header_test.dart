import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/design_tokens.dart';
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
import 'package:duoyi/widgets/apple_page_frame.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Key _backKey = ValueKey('todo_back_button');
const Key _headerKey = ValueKey('todo_desktop_header');

/// 宿主页：模拟「今日 / 我的」→ 待办 的 push 入口。
class _HostPage extends StatelessWidget {
  const _HostPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('宿主页'),
            TextButton(
              key: const ValueKey('open_todo'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const TodoScreen()),
              ),
              child: const Text('打开待办'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<TodoProvider> _pump(
  WidgetTester tester, {
  required Size size,
  bool home = false,
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
        debugShowCheckedModeBanner: false,
        theme: AppBrands.defaultBrand.theme,
        home: home ? const TodoScreen() : const _HostPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return provider;
}

Future<void> _pushTodo(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open_todo')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      DesignTokens.fontFamily,
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets(
    '从宿主页 push 待办后有返回键，点击返回宿主页',
    (tester) async {
      await _pump(tester, size: const Size(1280, 800));
      expect(find.byKey(_backKey), findsNothing);
      await _pushTodo(tester);

      final back = find.byKey(_backKey);
      expect(back, findsOneWidget);
      expect(back.hitTestable(), findsOneWidget);
      expect(find.text('宿主页'), findsNothing);

      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text('宿主页'), findsOneWidget);
      expect(find.byType(TodoScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'Escape 作为系统返回：回到宿主页',
    (tester) async {
      await _pump(tester, size: const Size(1280, 800));
      await _pushTodo(tester);
      expect(find.byKey(_backKey), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('宿主页'), findsOneWidget);
      expect(find.byType(TodoScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    '筛选菜单打开时 Esc 只关闭菜单，不返回；再次 Esc 才返回',
    (tester) async {
      await _pump(tester, size: const Size(1440, 800));
      await _pushTodo(tester);
      // 桌面筛选默认收起：展开后打开「象限」菜单。
      await tester.tap(find.byKey(const ValueKey('todo_filter_toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('象限'));
      await tester.pumpAndSettle();
      expect(find.text('全部象限'), findsOneWidget);

      // 菜单打开时 Esc 不返回页面（本页不是当前路由，不安装返回意图）。
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TodoScreen), findsOneWidget);
      expect(find.text('宿主页'), findsNothing);
      expect(find.byKey(_backKey), findsOneWidget);

      // 关掉菜单（点击浮层外）后，Esc 恢复为系统返回。
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.text('全部象限'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('宿主页'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    '首页直接嵌入待办不出现返回键，Escape 不弹页',
    (tester) async {
      await _pump(tester, size: const Size(1280, 800), home: true);

      expect(find.byKey(_backKey), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TodoScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final width in const [1280.0, 2000.0]) {
    testWidgets(
      'macOS ${width.toInt()} 宽：返回键贴左 gutter，动作贴右 gutter，标题同排',
      (tester) async {
        await _pump(tester, size: Size(width, 900));
        await _pushTodo(tester);

        final header = tester.getRect(find.byKey(_headerKey));
        expect(header.width, closeTo(width, 0.5));
        final back = tester.getRect(find.byKey(_backKey));
        expect(back.left, greaterThanOrEqualTo(ApplePageFrame.gutter));
        expect(back.left, lessThan(120));

        final actions = tester
            .widgetList<IconButton>(
              find.descendant(
                of: find.byKey(_headerKey),
                matching: find.byType(IconButton),
              ),
            )
            .toList();
        expect(actions, isNotEmpty);
        final lastAction = tester.getRect(
          find
              .descendant(
                of: find.byKey(_headerKey),
                matching: find.byType(IconButton),
              )
              .last,
        );
        expect(lastAction.right, lessThanOrEqualTo(width));
        expect(lastAction.right, greaterThan(width - 80));

        // 返回键与动作在同一行（纵向重叠）。
        expect(back.top, lessThan(lastAction.bottom));
        expect(lastAction.top, lessThan(back.bottom));
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'macOS 390 窄窗：页头返回键与动作不溢出',
    (tester) async {
      await _pump(tester, size: const Size(390, 844));
      await _pushTodo(tester);

      expect(find.byKey(_backKey), findsOneWidget);
      expect(tester.takeException(), isNull);
      final header = tester.getRect(find.byKey(_headerKey));
      expect(header.width, closeTo(390, 0.5));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

/// 页头左右 gutter：与 ApplePageFrame.gutter 保持一致。
