import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/app_text_scale.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/screens/preferences_screen.dart';
import 'package:duoyi/screens/text_size_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingPreferences extends PreferencesProvider {
  bool fail = true;
  @override
  Future<void> setTextScale(double value) => fail
      ? Future<void>.error(StateError('simulated storage failure'))
      : super.setTextScale(value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      DesignTokens.fontFamily,
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'))).load();
    await (FontLoader(
      Icons.check.fontFamily!,
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async => 'UTC';
  });
  tearDown(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    I18n.setLocale(AppLocale.zh);
  });

  Future<void> mount(
    WidgetTester tester,
    PreferencesProvider p, {
    Size size = const Size(390, 844),
    double systemScale = 1,
    bool settings = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final locale = LocaleProvider();
    addTearDown(locale.dispose);
    await tester.runAsync(() => locale.setLocale(AppLocale.zh));
    await tester.runAsync(p.loadFromStorage);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PreferencesProvider>.value(value: p),
          ChangeNotifierProvider<LocaleProvider>.value(value: locale),
        ],
        child: MaterialApp(
          theme: AppBrands.defaultBrand.theme,
          builder: (context, child) {
            final factor = context.select<PreferencesProvider, double>(
              (p) => p.textScale,
            );
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: AppTextScale.resolve(
                  system: TextScaler.linear(systemScale),
                  appScale: factor,
                ),
              ),
              child: AppClockScope(child: child!),
            );
          },
          home: settings
              ? const PersonalizationSettingsScreen()
              : Builder(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: FilledButton(
                        key: const ValueKey('open_text_size'),
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const TextSizeSettingsScreen(),
                          ),
                        ),
                        child: const Text('open'),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final entry = find.byKey(
      ValueKey(settings ? 'preferences_text_scale_tile' : 'open_text_size'),
    );
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, int index) async {
    final slider = find.byKey(const ValueKey('text_size_slider'));
    final rect = tester.getRect(slider);
    await tester.tapAt(
      Offset(rect.left + 24 + (rect.width - 48) * index / 7, rect.center.dy),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).value, index.toDouble());
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final directory = Platform.environment['DUOYI_TEXT_SCALE_SCREENSHOTS'];
    if (directory == null || directory.isEmpty) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('text_size_page')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('八个刻度实际点击只改变预览，完成保存，重新进入恢复已选档', (tester) async {
    final p = PreferencesProvider();
    addTearDown(p.dispose);
    await mount(tester, p);
    final storage = await SharedPreferences.getInstance();
    final initialStored = storage.getDouble('pref_text_scale');
    expect(initialStored, AppTextScale.defaultScale);
    expect(tester.widget<Slider>(find.byType(Slider)).divisions, 7);
    for (var index = 0; index < 8; index++) {
      await choose(tester, index);
      final preview = tester.element(
        find.text(I18n.tr('preferences.text_scale.preview_title')),
      );
      expect(
        MediaQuery.textScalerOf(preview).scale(16),
        closeTo(16 * AppTextScale.options[index], .001),
      );
      expect(p.textScale, AppTextScale.defaultScale);
      expect(storage.getDouble('pref_text_scale'), initialStored);
      if ([0, 1, 7].contains(index)) {
        await capture(
          tester,
          'text-size-${AppTextScale.percentOf(AppTextScale.options[index])}',
        );
      }
    }
    await tester.tap(find.byKey(const ValueKey('text_size_done_button')));
    await tester.pumpAndSettle();
    expect(find.byType(TextSizeSettingsScreen), findsNothing);
    expect(p.textScale, 1.9);
    expect(storage.getDouble('pref_text_scale'), 1.9);
    await tester.tap(find.byKey(const ValueKey('open_text_size')));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 7);
    await tester.drag(find.byType(Slider), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0);
    expect(p.textScale, 1.9);
    expect(tester.takeException(), isNull);
  });

  testWidgets('返回取消草稿，原字号不变且预览没有重复叠加', (tester) async {
    final p = PreferencesProvider();
    addTearDown(p.dispose);
    await p.setTextScale(1.45);
    await mount(tester, p);
    final preview = tester.element(
      find.text(I18n.tr('preferences.text_scale.preview_title')),
    );
    expect(
      MediaQuery.textScalerOf(preview).scale(16),
      closeTo(16 * 1.45, .001),
    );
    await choose(tester, 7);
    await tester.tap(find.byKey(const ValueKey('text_size_back_button')));
    await tester.pumpAndSettle();
    expect(p.textScale, 1.45);
    expect(
      (await SharedPreferences.getInstance()).getDouble('pref_text_scale'),
      1.45,
    );
    expect(find.byType(TextSizeSettingsScreen), findsNothing);
  });

  testWidgets('设置入口打开独立字号页', (tester) async {
    final p = PreferencesProvider();
    addTearDown(p.dispose);
    await mount(tester, p, size: const Size(1100, 1000), settings: true);
    expect(find.byType(TextSizeSettingsScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('text_size_standard_marker')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('换账号时丢弃旧账号预览草稿', (tester) async {
    final p = PreferencesProvider();
    addTearDown(p.dispose);
    await p.bindTextScaleToAccount(
      serverUrl: 'https://duoyi.test',
      userId: 'a',
    );
    await mount(tester, p);
    await choose(tester, 7);
    await tester.runAsync(
      () => p.bindTextScaleToAccount(
        serverUrl: 'https://duoyi.test',
        userId: 'b',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Slider>(find.byType(Slider)).value,
      AppTextScale.indexOf(AppTextScale.defaultScale).toDouble(),
    );
    await tester.tap(find.byKey(const ValueKey('text_size_done_button')));
    await tester.pumpAndSettle();
    expect(p.textScale, AppTextScale.defaultScale);
    expect(
      (await SharedPreferences.getInstance()).getDouble('pref_text_scale'),
      AppTextScale.defaultScale,
    );
  });

  testWidgets('保存失败留在页面并支持重试', (tester) async {
    final p = _FailingPreferences();
    addTearDown(p.dispose);
    await mount(tester, p);
    await choose(tester, 7);
    await tester.tap(find.byKey(const ValueKey('text_size_done_button')));
    await tester.pumpAndSettle();
    expect(find.byType(TextSizeSettingsScreen), findsOneWidget);
    expect(
      find.text(I18n.tr('preferences.text_scale.save_failed')),
      findsOneWidget,
    );
    expect(p.textScale, AppTextScale.defaultScale);
    p.fail = false;
    await tester.tap(find.byKey(const ValueKey('text_size_done_button')));
    await tester.pumpAndSettle();
    expect(find.byType(TextSizeSettingsScreen), findsNothing);
    expect(p.textScale, 1.9);
  });

  testWidgets('320窄屏系统2倍与应用最大字号下控制区可用且预览可滚动', (tester) async {
    final p = PreferencesProvider();
    addTearDown(p.dispose);
    await p.setTextScale(1.9);
    await mount(tester, p, size: const Size(320, 568), systemScale: 2);
    expect(
      find.byKey(const ValueKey('text_size_done_button')).hitTestable(),
      findsOneWidget,
    );
    expect(find.byType(Slider).hitTestable(), findsOneWidget);
    final preview = tester.element(
      find.text(I18n.tr('preferences.text_scale.preview_title')),
    );
    expect(
      MediaQuery.textScalerOf(preview).scale(16),
      closeTo(16 * 1.9 * 2, .001),
    );
    await tester.drag(
      find.byKey(const ValueKey('text_size_preview_scroll')),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'text-size-narrow-system-200');
    expect(tester.takeException(), isNull);
    await choose(tester, 0);
    expect(tester.takeException(), isNull);
  });
}
