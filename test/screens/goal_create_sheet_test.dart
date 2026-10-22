import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/goal_screen.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder get _sheet => find.byType(AppModalSheet);
Finder get _card =>
    find.descendant(of: _sheet, matching: find.byType(Material)).first;
Finder get _scroll =>
    find.descendant(of: _sheet, matching: find.byType(Scrollable)).first;
Finder _key(String value) => find.byKey(ValueKey(value));

Future<GoalProvider> _openGoalCreate(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final goals = GoalProvider();
  addTearDown(goals.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<GoalProvider>.value(value: goals),
        ChangeNotifierProvider(create: (_) => CustomFocusSoundProvider()),
        ChangeNotifierProvider(create: (_) => ShareProvider()),
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
        home: const GoalScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  return goals;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(DesignTokens.fontFamilyRounded)..addFont(
          rootBundle.load('assets/fonts/ResourceHanRoundedCN-Bold.ttf'),
        ))
        .load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('目标管理新建使用共享底部弹窗且没有嵌套独立页面', (tester) async {
    await _openGoalCreate(tester);
    expect(_sheet, findsOneWidget);
    expect(
      find.descendant(of: _sheet, matching: find.byType(Scaffold)),
      findsNothing,
    );
    expect(find.byType(GoalScreen), findsOneWidget);
    expect(_key('goal_form_title'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (size, scale) in [
    (const Size(320, 720), 1.5),
    (const Size(390, 844), 1.0),
    (const Size(1280, 800), 1.0),
    (const Size(844, 390), 1.0),
  ]) {
    testWidgets('$size ×$scale 目标弹窗尺寸、展开、保留输入与遮罩关闭', (tester) async {
      await _openGoalCreate(
        tester,
        size: size,
        textScale: scale,
        theme: AppBrands.starRail.theme,
      );
      final initial = tester.getRect(_card);
      expect(
        initial.height,
        inInclusiveRange(size.height / 2, size.height * 2 / 3 + 1),
      );
      expect(
        initial.width,
        lessThanOrEqualTo(DesignTokens.creationFormMaxWidth),
      );
      expect(initial.bottom, closeTo(size.height, 1));
      await tester.enterText(_key('goal_form_title'), '弹窗内保留的目标');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final scrollRect = tester.getRect(_scroll);
      await tester.timedDragFrom(
        Offset(scrollRect.left + 6, scrollRect.center.dy),
        const Offset(0, -150),
        const Duration(milliseconds: 500),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(_card).height, closeTo(size.height, 1));
      expect(
        tester.widget<TextField>(_key('goal_form_title')).controller!.text,
        '弹窗内保留的目标',
      );
      await tester.timedDragFrom(
        Offset(scrollRect.left + 6, size.height / 2),
        const Offset(0, 3500),
        const Duration(milliseconds: 500),
      );
      await tester.pumpAndSettle();
      final topRect = tester.getRect(_scroll);
      await tester.timedDragFrom(
        Offset(topRect.left + 6, topRect.center.dy),
        const Offset(0, 120),
        const Duration(milliseconds: 500),
      );
      await tester.pumpAndSettle();
      final collapsed = tester.getRect(_card);
      expect(collapsed.height, closeTo(initial.height, 1));
      await tester.tapAt(Offset(collapsed.center.dx, collapsed.top - 20));
      await tester.pumpAndSettle();
      expect(_sheet, findsNothing);
      expect(find.byType(GoalScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('目标弹窗键盘避让且底部保存写入后关闭', (tester) async {
    final provider = await _openGoalCreate(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.getRect(_card).bottom, closeTo(844 - 300, 1));
    expect(
      tester.getRect(_card).height,
      lessThanOrEqualTo((844 - 300) * 2 / 3 + 1),
    );
    await tester.enterText(_key('goal_form_title'), '弹窗目标');
    await tester.enterText(_key('goal_form_description'), '保留完整描述');
    tester.view.viewInsets = const FakeViewPadding();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      _key('goal_form_submit'),
      280,
      scrollable: _scroll,
    );
    await tester.tap(_key('goal_form_submit'));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(provider.goals.single.title, '弹窗目标');
    expect(provider.goals.single.description, '保留完整描述');
    expect(tester.takeException(), isNull);
  });
}
