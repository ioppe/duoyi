import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/pomodoro_screen.dart';
import 'package:duoyi/widgets/focus_rest_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app({double textScale = 1}) {
  final theme = ThemeProvider();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => PomodoroProvider()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => theme),
      ChangeNotifierProvider(create: (_) => FocusRoomProvider()),
      ChangeNotifierProvider(create: (_) => CustomFocusSoundProvider()),
    ],
    child: MaterialApp(
      theme: theme.brand.theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const PomodoroScreen(),
    ),
  );
}

Future<void> _pumpScreen(
  WidgetTester tester,
  Size size, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(textScale: textScale));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader(DesignTokens.fontFamily)
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'));
    await font.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  testWidgets('320×720 手机 125% 文字：休息摘要与主操作在首屏且无溢出', (tester) async {
    await _pumpScreen(tester, const Size(320, 720), textScale: 1.25);

    expect(tester.takeException(), isNull);
    expect(find.text('准备开始'), findsOneWidget);
    expect(find.text('100%'), findsNothing);
    expect(find.byKey(FocusRestKeys.summary).hitTestable(), findsOneWidget);
    expect(find.text('开始专注').hitTestable(), findsOneWidget);
    expect(find.byTooltip('重置计时').hitTestable(), findsOneWidget);
    expect(find.byTooltip('跳过当前阶段').hitTestable(), findsOneWidget);
  });

  testWidgets('390×844 手机：摘要紧跟在时长选项之后、主操作之前', (tester) async {
    await _pumpScreen(tester, const Size(390, 844));

    expect(tester.takeException(), isNull);
    final chips = tester.getRect(find.widgetWithText(ChoiceChip, '25 分钟'));
    final summary = tester.getRect(find.byKey(FocusRestKeys.summary));
    final primary = tester.getRect(find.text('开始专注'));

    expect(summary.top, greaterThanOrEqualTo(chips.bottom));
    expect(primary.top, greaterThanOrEqualTo(summary.bottom));
    expect(summary.height, greaterThanOrEqualTo(64));
  });

  testWidgets('短屏 390×560 允许滚动，正文不被缩小', (tester) async {
    await _pumpScreen(tester, const Size(390, 560));

    expect(tester.takeException(), isNull);
    final timerText = tester.widget<Text>(find.text('25:00'));
    expect(timerText.style?.fontSize ?? 0, greaterThan(0));
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('严格专注'), findsOneWidget);
  });

  testWidgets('桌面 1280×800：双栏把时长与休息安排放到计时右侧', (tester) async {
    await _pumpScreen(tester, const Size(1280, 800));

    expect(tester.takeException(), isNull);
    final summary = tester.getRect(find.byKey(FocusRestKeys.summary));
    final primary = tester.getRect(find.text('开始专注'));
    expect(summary.left, greaterThan(primary.right));
    expect(summary.width, lessThan(500));
  });

  testWidgets('运行中与暂停中时长选项禁用，休息摘要仍可打开面板', (tester) async {
    await _pumpScreen(tester, const Size(390, 844));
    final provider = Provider.of<PomodoroProvider>(
      tester.element(find.byKey(FocusRestKeys.summary)),
      listen: false,
    );

    ChoiceChip chip() =>
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '25 分钟'));

    expect(chip().onSelected, isNotNull);
    provider.toggleTimer();
    await tester.pumpAndSettle();
    expect(chip().onSelected, isNull);

    provider.toggleTimer();
    await tester.pumpAndSettle();
    expect(provider.isPaused, isTrue);
    expect(chip().onSelected, isNull);

    await tester.tap(find.byKey(FocusRestKeys.summary));
    await tester.pumpAndSettle();
    expect(find.byKey(FocusRestKeys.sheet), findsOneWidget);
    expect(find.text('当前计时不受影响；之后开始的专注使用新设置。'), findsOneWidget);
    await tester.tap(find.byKey(FocusRestKeys.cancel));
    await tester.pumpAndSettle();
    expect(find.byKey(FocusRestKeys.sheet), findsNothing);
    provider.resetTimer();
  });

  testWidgets('短休息状态用休息色显示剩余时间与下一轮专注时长', (tester) async {
    await _pumpScreen(tester, const Size(390, 844));
    final provider = Provider.of<PomodoroProvider>(
      tester.element(find.byKey(FocusRestKeys.summary)),
      listen: false,
    );

    provider.skipSession();
    await tester.pumpAndSettle();

    expect(find.text('开始休息'), findsOneWidget);
    expect(find.textContaining('休息后专注 25 分钟'), findsOneWidget);
    expect(find.text('短休息'), findsOneWidget);
    provider.resetTimer();
  });
}
