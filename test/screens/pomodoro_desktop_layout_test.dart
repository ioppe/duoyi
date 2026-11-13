import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/pomodoro_screen.dart';
import 'package:duoyi/widgets/apple_page_frame.dart';
import 'package:duoyi/widgets/focus_duration_picker.dart';
import 'package:duoyi/widgets/surface_components.dart';
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

Future<PomodoroProvider> _pumpScreen(
  WidgetTester tester,
  Size size, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(textScale: textScale));
  await tester.pumpAndSettle();
  return Provider.of<PomodoroProvider>(
    tester.element(find.byType(PomodoroScreen)),
    listen: false,
  );
}

Finder get _dropdown => find.byKey(FocusDurationPicker.dropdownKey);
Finder get _countUp => find.byKey(FocusDurationPicker.countUpKey);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader(DesignTokens.fontFamily)
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'));
    await font.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // 用户问题 2：宽窗里页头右侧入口被 720 内容列拉到窗口中间。
  for (final width in const [1280.0, 2000.0]) {
    testWidgets(
      'macOS ${width.toInt()} 宽：页头入口贴右侧 gutter，计时卡仍按原宽度居中',
      (tester) async {
        await _pumpScreen(tester, Size(width, 900));

        expect(tester.takeException(), isNull);
        final header = tester.getRect(
          find.byKey(const ValueKey('focus_page_header')),
        );
        final trailing = tester.getRect(
          find.byKey(const ValueKey('focus_header_trailing')),
        );
        expect(header.left, closeTo(ApplePageFrame.gutter, 0.5));
        expect(header.right, closeTo(width - ApplePageFrame.gutter, 0.5));
        expect(trailing.right, closeTo(width - ApplePageFrame.gutter, 0.5));
        // 不再落在内容列中间：始终在窗口右侧 1/4 内。
        expect(trailing.left, greaterThan(width * 0.75));

        final card = tester.getRect(find.byType(AppSurfaceCard).first);
        expect(
          card.width,
          lessThanOrEqualTo(DesignTokens.focusRestCardMaxWidth),
        );
        expect(card.center.dx, closeTo(width / 2, 1));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'macOS 桌面：下拉里鼠标选 90 分钟即写入时长，切回倒计时',
    (tester) async {
      final provider = await _pumpScreen(tester, const Size(1280, 900));

      expect(_dropdown, findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '25 分钟'), findsNothing);

      await tester.tap(_dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('90 分钟').last);
      await tester.pumpAndSettle();

      expect(provider.config.focusDuration, 90 * 60);
      expect(provider.state.totalSeconds, 90 * 60);
      expect(provider.state.isCountUp, isFalse);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'macOS 桌面：正向计时是独立选项，切换后进入 countup',
    (tester) async {
      final provider = await _pumpScreen(tester, const Size(1280, 900));

      await tester.tap(_countUp);
      await tester.pumpAndSettle();
      expect(provider.state.isCountUp, isTrue);
      expect(provider.state.totalSeconds, 0);
      expect(tester.widget<ChoiceChip>(_countUp).selected, isTrue);

      // 再选分钟数回到倒计时。
      await tester.tap(_dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('45 分钟').last);
      await tester.pumpAndSettle();
      expect(provider.state.isCountUp, isFalse);
      expect(provider.config.focusDuration, 45 * 60);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'macOS 桌面：运行中与暂停中下拉和正向计时都被禁用',
    (tester) async {
      final provider = await _pumpScreen(tester, const Size(1280, 900));

      DropdownButton<int> dropdown() =>
          tester.widget<DropdownButton<int>>(_dropdown);
      ChoiceChip chip() => tester.widget<ChoiceChip>(_countUp);

      expect(dropdown().onChanged, isNotNull);
      expect(chip().onSelected, isNotNull);

      provider.toggleTimer();
      await tester.pumpAndSettle();
      expect(dropdown().onChanged, isNull);
      expect(chip().onSelected, isNull);

      provider.toggleTimer();
      await tester.pumpAndSettle();
      expect(provider.isPaused, isTrue);
      expect(dropdown().onChanged, isNull);
      expect(chip().onSelected, isNull);

      provider.resetTimer();
      await tester.pumpAndSettle();
      expect(dropdown().onChanged, isNotNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final (size, scale) in [
    (const Size(390, 844), 1.0),
    (const Size(320, 720), 1.5),
  ]) {
    testWidgets(
      'macOS 窄窗 $size ×$scale 无溢出且下拉完整可用',
      (tester) async {
        await _pumpScreen(tester, size, textScale: scale);

        expect(tester.takeException(), isNull);
        expect(_dropdown, findsOneWidget);
        await tester.tap(_dropdown);
        await tester.pumpAndSettle();
        expect(find.text('90 分钟'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'Android 手机保留原有横向 chips，不出现桌面下拉',
    (tester) async {
      await _pumpScreen(tester, const Size(390, 844));

      expect(_dropdown, findsNothing);
      expect(find.widgetWithText(ChoiceChip, '25 分钟'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '自由计时'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
