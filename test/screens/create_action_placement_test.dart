import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/habit_screen.dart';
import 'package:duoyi/widgets/app_create_fab.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      DesignTokens.fontFamily,
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final brand in [AppBrands.defaultBrand, AppBrands.starRail]) {
    for (final (size, scale) in [
      (const Size(1600, 1000), 1.0),
      (const Size(1280, 800), 1.0),
      (const Size(390, 844), 1.0),
      (const Size(320, 720), 1.5),
    ]) {
      testWidgets('${brand.id} $size ×$scale 习惯页创建入口始终在右下角且打开共享弹窗', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final habits = HabitProvider();
        addTearDown(habits.dispose);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<HabitProvider>.value(value: habits),
              ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ],
            child: MaterialApp(
              theme: brand.theme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const HabitScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final label = tester
            .element(find.byType(HabitScreen))
            .read<ThemeProvider>()
            .brand
            .strings
            .habitAddAction;
        final fab = find.widgetWithText(FloatingActionButton, label);
        expect(fab, findsOneWidget);
        expect(
          find.descendant(of: find.byType(AppBar), matching: find.text(label)),
          findsNothing,
        );
        final rect = tester.getRect(fab);
        expect(rect.right, closeTo(size.width - 16, 1));
        expect(rect.bottom, closeTo(size.height - 16, 1));
        expect(rect.top, greaterThan(size.height * 0.7));
        expect(find.byKey(const ValueKey('habit_add_action')), findsOneWidget);
        await tester.tap(fab);
        await tester.pumpAndSettle();
        expect(find.byType(AppModalSheet), findsOneWidget);
        Navigator.of(tester.element(find.byType(AppModalSheet))).pop();
        await tester.pumpAndSettle();
        expect(find.byType(AppModalSheet), findsNothing);
        expect(habits.habits, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('共享创建按钮在窄屏大字号下保持可点击且长标签不撑破窗口', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var taps = 0;
    const label = '记录一个需要持续完成的新习惯';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          floatingActionButton: AppCreateFab(
            label: label,
            onPressed: () => taps++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byType(FloatingActionButton);
    final rect = tester.getRect(button);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(320));
    expect(rect.height, greaterThanOrEqualTo(DesignTokens.controlMinHeight));
    expect(find.byTooltip(label), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
