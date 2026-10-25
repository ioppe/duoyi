import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/app_text_scale.dart';
import 'package:duoyi/core/app_typography.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/screens/preferences_screen.dart';
import 'package:duoyi/screens/text_size_settings_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _androidProfile = <double>[.55, .70, .85, 1.0, 1.15, 1.30, 1.45];
const _sharedProfile = <double>[.85, 1.0, 1.15, 1.30, 1.45, 1.60, 1.75, 1.90];

class _FailingPreferences extends PreferencesProvider {
  bool fail = true;
  @override
  Future<void> setTextScale(double value) => fail
      ? Future<void>.error(StateError('simulated storage failure'))
      : super.setTextScale(value);
}

/// 在指定目标平台下跑用例：档位表与页面布局都按该平台计算。
///
/// 覆盖层只在用例内部生效，退出时恢复，避免影响其它用例。
Future<void> _onPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  final previous = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = previous;
  }
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
    bool androidBaseline = false,
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
                  system: androidBaseline
                      ? AppTypography.platformScaler(
                          system: TextScaler.linear(systemScale),
                          platform: TargetPlatform.android,
                          isWeb: false,
                        )
                      : TextScaler.linear(systemScale),
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

  final sliderFinder = find.byKey(const ValueKey('text_size_slider'));
  final markerFinder = find.byKey(const ValueKey('text_size_standard_marker'));

  /// 按实际刻度数点击目标档位，坐标由 slider 的 divisions / max 推导。
  Future<void> choose(WidgetTester tester, int index) async {
    final slider = tester.widget<Slider>(sliderFinder);
    final divisions = slider.divisions!.round();
    final rect = tester.getRect(sliderFinder);
    expect(slider.max, divisions.toDouble());
    // Slider 轨道左右各留一个滑块的命中偏移，并非占满整个描边宽度。
    final trackLeft = rect.left + 24;
    final trackWidth = rect.width - 48;
    await tester.tapAt(
      Offset(trackLeft + trackWidth * index / divisions, rect.center.dy),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(sliderFinder).value, index.toDouble());
  }

  /// 预览气泡在当前草稿档位下正文的实际字号。
  double previewBodySize(WidgetTester tester) => MediaQuery.textScalerOf(
    tester.element(find.text(I18n.tr('preferences.text_scale.preview_title'))),
  ).scale(DesignTokens.fontSizeBody);

  String percentLabel(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('text_size_percent_label')))
      .data!;

  Alignment markerAlign(WidgetTester tester) {
    final align = tester.widget<Align>(
      find.ancestor(of: markerFinder, matching: find.byType(Align)).first,
    );
    return align.alignment as Alignment;
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

  // ---------------------------------------------------------------------
  // Android 七档：55 / 70 / 85 / 100 / 115 / 130 / 145，标准第四档居中。
  // ---------------------------------------------------------------------

  testWidgets('Android 七档：默认标准第四档、刻度 6、标准标识实际居中', (tester) async {
    await _onPlatform(TargetPlatform.android, () async {
      final p = PreferencesProvider();
      addTearDown(p.dispose);
      await mount(tester, p, androidBaseline: true);

      final slider = tester.widget<Slider>(sliderFinder);
      expect(slider.value, 3);
      expect(slider.max, 6);
      expect(slider.divisions, 6);
      expect(percentLabel(tester), '100%');
      // 默认档位叠加 Android 正文基准后仍是 10。
      expect(previewBodySize(tester), closeTo(10, .001));
      expect(p.textScale, AppTextScale.defaultScale);

      // 标准标识按 index / (len - 1) * 2 - 1 计算，七档时正好居中。
      expect(markerAlign(tester), Alignment.center);
      final markerRect = tester.getRect(markerFinder);
      final sliderRect = tester.getRect(sliderFinder);
      expect(markerRect.center.dx, closeTo(sliderRect.center.dx, .5));

      // 载入不写盘。
      expect(
        (await SharedPreferences.getInstance()).getDouble('pref_text_scale'),
        isNull,
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Android 七档实际点击：55% 正文 5.5、100% 正文 10、145% 正文 14.5，遍历不写盘', (
    tester,
  ) async {
    await _onPlatform(TargetPlatform.android, () async {
      final p = PreferencesProvider();
      addTearDown(p.dispose);
      await mount(tester, p, androidBaseline: true);
      final storage = await SharedPreferences.getInstance();

      for (var index = 0; index < _androidProfile.length; index++) {
        await choose(tester, index);
        final ratio = _androidProfile[index];
        // 正文 14 先按 10 / 14 缩到 10，再乘用户档位：5.5 / 10 / 14.5。
        expect(
          previewBodySize(tester),
          closeTo(10 * ratio, .001),
          reason: '第 $index 档 ${(ratio * 100).round()}%',
        );
        expect(percentLabel(tester), '${(ratio * 100).round()}%');
        // 点击只改草稿，不写盘也不改已保存档位。
        expect(p.textScale, AppTextScale.defaultScale);
        expect(storage.getDouble('pref_text_scale'), isNull);
        if (index == 0 || index == 3 || index == 6) {
          await capture(tester, 'text-size-android-${(ratio * 100).round()}');
        }
      }

      // 最小 / 标准 / 最大档的正文实际字号。
      await choose(tester, 0);
      expect(previewBodySize(tester), closeTo(5.5, .001));
      await choose(tester, 3);
      expect(previewBodySize(tester), closeTo(10, .001));
      await choose(tester, 6);
      expect(previewBodySize(tester), closeTo(14.5, .001));
      // 七档上限就是 145%，不会出现八档的 160 / 175 / 190。
      expect(percentLabel(tester), '145%');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Android 完成保存 145%，重启后从磁盘恢复第六档', (tester) async {
    await _onPlatform(TargetPlatform.android, () async {
      final p = PreferencesProvider();
      addTearDown(p.dispose);
      await mount(tester, p, androidBaseline: true);
      await choose(tester, 6);
      await tester.tap(find.byKey(const ValueKey('text_size_done_button')));
      await tester.pumpAndSettle();
      expect(find.byType(TextSizeSettingsScreen), findsNothing);
      expect(p.textScale, 1.45);
      final storage = await SharedPreferences.getInstance();
      expect(storage.getDouble('pref_text_scale'), 1.45);

      // 模拟重启：丢弃 SharedPreferences 缓存后从磁盘快照重新载入。
      SharedPreferences.resetStatic();
      final restarted = PreferencesProvider();
      addTearDown(restarted.dispose);
      await tester.runAsync(restarted.loadFromStorage);
      expect(restarted.textScale, 1.45);

      await mount(tester, restarted, androidBaseline: true);
      expect(tester.widget<Slider>(sliderFinder).value, 6);
      expect(percentLabel(tester), '145%');
      expect(previewBodySize(tester), closeTo(14.5, .001));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Android 旧版 175% 载入为 145%：滑块、百分比、预览一致且不改写磁盘', (tester) async {
    await _onPlatform(TargetPlatform.android, () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'pref_text_scale': 1.75,
      });
      final p = PreferencesProvider();
      addTearDown(p.dispose);
      await mount(tester, p, androidBaseline: true);

      expect(p.textScale, 1.45);
      expect(tester.widget<Slider>(sliderFinder).value, 6);
      expect(percentLabel(tester), '145%');
      expect(previewBodySize(tester), closeTo(14.5, .001));
      // 载入不写盘：磁盘保留升级前的历史值，下次读取再按范围吸附。
      expect(
        (await SharedPreferences.getInstance()).getDouble('pref_text_scale'),
        1.75,
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Android 已保存 145% 预览 14.5，草稿 130% 显示 13，取消保持 145%', (
    tester,
  ) async {
    await _onPlatform(TargetPlatform.android, () async {
      final p = PreferencesProvider();
      addTearDown(p.dispose);
      await p.setTextScale(1.45);
      await mount(tester, p, androidBaseline: true);
      expect(previewBodySize(tester), closeTo(14.5, .001));

      // 草稿 130%：正文 14 * 130% * 10 / 14 = 13，不会把已存 145% 再乘进来。
      await choose(tester, 5);
      expect(previewBodySize(tester), closeTo(13, .001));
      expect(p.textScale, 1.45);

      await tester.tap(find.byKey(const ValueKey('text_size_back_button')));
      await tester.pumpAndSettle();
      expect(find.byType(TextSizeSettingsScreen), findsNothing);
      expect(p.textScale, 1.45);
      expect(
        (await SharedPreferences.getInstance()).getDouble('pref_text_scale'),
        1.45,
      );
    });
  });

  testWidgets('Android 保存失败留在页面并支持重试', (tester) async {
    await _onPlatform(TargetPlatform.android, () async {
      final p = _FailingPreferences();
      addTearDown(p.dispose);
      await mount(tester, p, androidBaseline: true);
      await choose(tester, 6);
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
      expect(p.textScale, 1.45);
    });
  });

  // ---------------------------------------------------------------------
  // 其它平台八档：85 / 100 / 115 / … / 190，标准第二档（保留原位置）。
  // ---------------------------------------------------------------------

  testWidgets('八档：八个刻度实际点击只改变预览，完成保存，重新进入恢复已选档', (tester) async {
    await _onPlatform(TargetPlatform.linux, () async {
      final p = PreferencesProvider();
      addTearDown(p.dispose);
      await mount(tester, p);
      final storage = await SharedPreferences.getInstance();
      final initialStored = storage.getDouble('pref_text_scale');
      // 载入不再写盘：首次进入页面时磁盘上还没有字号记录。
      expect(initialStored, isNull);
      expect(tester.widget<Slider>(sliderFinder).divisions, 7);
      // 八档时标准标识保持原位置。
      expect(markerAlign(tester).x, closeTo(-5 / 7, 1e-9));
      for (var index = 0; index < _sharedProfile.length; index++) {
        await choose(tester, index);
        final ratio = _sharedProfile[index];
        expect(previewBodySize(tester), closeTo(14 * ratio, .001));
        expect(p.textScale, AppTextScale.defaultScale);
        expect(storage.getDouble('pref_text_scale'), initialStored);
        if (index == 0 || index == 1 || index == 7) {
          await capture(
            tester,
            'text-size-${AppTextScale.percentOf(ratio, platform: TargetPlatform.linux)}',
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
      expect(tester.widget<Slider>(sliderFinder).value, 7);
      await tester.drag(sliderFinder, const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(sliderFinder).value, 0);
      expect(p.textScale, 1.9);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('八档：返回取消草稿，原字号不变且预览没有重复叠加', (tester) async {
    await _onPlatform(TargetPlatform.linux, () async {
      final p = PreferencesProvider();
      addTearDown(p.dispose);
      await p.setTextScale(1.45);
      await mount(tester, p);
      expect(previewBodySize(tester), closeTo(14 * 1.45, .001));
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
  });

  testWidgets('换账号时丢弃旧账号预览草稿', (tester) async {
    await _onPlatform(TargetPlatform.linux, () async {
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
        tester.widget<Slider>(sliderFinder).value,
        AppTextScale.indexOf(
          AppTextScale.defaultScale,
          platform: TargetPlatform.linux,
        ).toDouble(),
      );
      await tester.tap(find.byKey(const ValueKey('text_size_done_button')));
      await tester.pumpAndSettle();
      expect(p.textScale, AppTextScale.defaultScale);
      expect(
        (await SharedPreferences.getInstance()).getDouble('pref_text_scale'),
        AppTextScale.defaultScale,
      );
    });
  });

  testWidgets('八档：保存失败留在页面并支持重试', (tester) async {
    await _onPlatform(TargetPlatform.linux, () async {
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
  });

  testWidgets('320窄屏系统2倍与应用最大字号下控制区可用且预览可滚动', (tester) async {
    await _onPlatform(TargetPlatform.linux, () async {
      final p = PreferencesProvider();
      addTearDown(p.dispose);
      await p.setTextScale(1.9);
      await mount(tester, p, size: const Size(320, 568), systemScale: 2);
      expect(
        find.byKey(const ValueKey('text_size_done_button')).hitTestable(),
        findsOneWidget,
      );
      expect(find.byType(Slider).hitTestable(), findsOneWidget);
      expect(previewBodySize(tester), closeTo(14 * 1.9 * 2, .001));
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
  });

  testWidgets('设置入口打开独立字号页', (tester) async {
    final p = PreferencesProvider();
    addTearDown(p.dispose);
    await mount(tester, p, size: const Size(1100, 1000), settings: true);
    expect(find.byType(TextSizeSettingsScreen), findsOneWidget);
    expect(markerFinder, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
