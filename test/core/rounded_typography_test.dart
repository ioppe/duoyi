import 'dart:convert';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/home_page_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Iterable<TextStyle?> _roles(TextTheme theme) => [
  theme.displayLarge,
  theme.displayMedium,
  theme.displaySmall,
  theme.headlineLarge,
  theme.headlineMedium,
  theme.headlineSmall,
  theme.titleLarge,
  theme.titleMedium,
  theme.titleSmall,
  theme.bodyLarge,
  theme.bodyMedium,
  theme.bodySmall,
  theme.labelLarge,
  theme.labelMedium,
  theme.labelSmall,
];

Iterable<TextStyle?> _sharedStyles(ThemeData theme) => [
  ..._roles(theme.textTheme),
  ..._roles(theme.primaryTextTheme),
  theme.appBarTheme.titleTextStyle,
  theme.appBarTheme.toolbarTextStyle,
  theme.dialogTheme.titleTextStyle,
  theme.dialogTheme.contentTextStyle,
  theme.snackBarTheme.contentTextStyle,
  theme.inputDecorationTheme.hintStyle,
  theme.inputDecorationTheme.labelStyle,
  theme.inputDecorationTheme.floatingLabelStyle,
  theme.popupMenuTheme.textStyle,
  theme.dropdownMenuTheme.textStyle,
  theme.tabBarTheme.labelStyle,
  theme.tabBarTheme.unselectedLabelStyle,
  theme.floatingActionButtonTheme.extendedTextStyle,
  theme.navigationRailTheme.selectedLabelTextStyle,
  theme.navigationRailTheme.unselectedLabelTextStyle,
  theme.filledButtonTheme.style?.textStyle?.resolve({}),
  theme.elevatedButtonTheme.style?.textStyle?.resolve({}),
  theme.outlinedButtonTheme.style?.textStyle?.resolve({}),
  theme.textButtonTheme.style?.textStyle?.resolve({}),
  theme.datePickerTheme.weekdayStyle,
  theme.datePickerTheme.dayStyle,
  HomePageStyle.fromTheme(theme).typography(theme, size: 16),
  for (final states in [
    <WidgetState>{},
    {WidgetState.selected},
  ])
    theme.navigationBarTheme.labelTextStyle?.resolve(states),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('九套主题共用同一中文无衬线字体，并区分正文 / 标签 / 标题字重', () {
    for (final brand in AppBrands.all) {
      final theme = brand.theme;
      for (final style in _sharedStyles(theme)) {
        expect(style, isNotNull, reason: brand.id);
        expect(style!.fontFamily, DesignTokens.fontFamily, reason: brand.id);
      }

      // 正文、说明文字、菜单与输入提示使用 Regular。
      for (final style in [
        theme.textTheme.bodyLarge,
        theme.textTheme.bodyMedium,
        theme.textTheme.bodySmall,
        theme.appBarTheme.toolbarTextStyle,
        theme.dialogTheme.contentTextStyle,
        theme.snackBarTheme.contentTextStyle,
        theme.popupMenuTheme.textStyle,
        theme.dropdownMenuTheme.textStyle,
        theme.inputDecorationTheme.hintStyle,
        theme.inputDecorationTheme.labelStyle,
      ]) {
        expect(
          style!.fontWeight,
          DesignTokens.fontWeightRegular,
          reason: '${brand.id} body/toolbar/menu',
        );
      }

      // 标签：按钮文字、导航标签、页签、chip 与浮动标签使用 Medium。
      for (final style in [
        theme.textTheme.labelLarge,
        theme.textTheme.labelMedium,
        theme.textTheme.labelSmall,
        theme.filledButtonTheme.style!.textStyle!.resolve({}),
        theme.elevatedButtonTheme.style!.textStyle!.resolve({}),
        theme.outlinedButtonTheme.style!.textStyle!.resolve({}),
        theme.textButtonTheme.style!.textStyle!.resolve({}),
        theme.tabBarTheme.labelStyle,
        theme.tabBarTheme.unselectedLabelStyle,
        theme.floatingActionButtonTheme.extendedTextStyle,
        theme.navigationRailTheme.selectedLabelTextStyle,
        theme.navigationRailTheme.unselectedLabelTextStyle,
        theme.inputDecorationTheme.floatingLabelStyle,
        theme.navigationBarTheme.labelTextStyle!.resolve({
          WidgetState.selected,
        }),
      ]) {
        expect(
          style!.fontWeight,
          DesignTokens.fontWeightMedium,
          reason: '${brand.id} label/button/navigation',
        );
      }

      // 标题与强调使用 Semibold。
      for (final style in [
        theme.textTheme.displayLarge,
        theme.textTheme.headlineSmall,
        theme.textTheme.titleLarge,
        theme.textTheme.titleMedium,
        theme.textTheme.titleSmall,
        theme.appBarTheme.titleTextStyle,
        theme.dialogTheme.titleTextStyle,
        theme.datePickerTheme.headerHeadlineStyle,
      ]) {
        expect(
          style!.fontWeight,
          DesignTokens.fontWeightStrong,
          reason: '${brand.id} title/emphasis',
        );
      }

      expect(
        theme.appBarTheme.titleTextStyle!.fontSize,
        DesignTokens.fontSizePageTitle,
        reason: brand.id,
      );
      expect(
        theme.navigationBarTheme.labelTextStyle!.resolve({})!.fontSize,
        DesignTokens.fontSizeBottomNavLabel,
        reason: brand.id,
      );
    }
  });

  test('字号层级符合常见手机 App 档位', () {
    expect(DesignTokens.fontSizeXs, 12);
    expect(DesignTokens.fontSizeSm, 14);
    expect(DesignTokens.fontSizeBase, 16);
    expect(DesignTokens.fontSizeSection, 16);
    expect(DesignTokens.fontSizeMd, 16);
    expect(DesignTokens.fontSizeLg, 18);
    expect(DesignTokens.fontSizeXl, 22);
    expect(DesignTokens.fontSizeXxl, 28);
    expect(DesignTokens.fontSizePageTitle, 20);
    expect(DesignTokens.fontSizeNavigationTitle, 20);
    expect(DesignTokens.fontSizeButton, 14);
    expect(DesignTokens.fontSizeBottomNavLabel, 12);
    expect(DesignTokens.homeHeadingSize, 20);
    expect(DesignTokens.homeTaskTitleSize, 16);
    expect(DesignTokens.homeCaptionSize, 12);
    expect(DesignTokens.homeCounterSize, 12);

    expect(DesignTokens.fontSizeXs, lessThanOrEqualTo(DesignTokens.fontSizeSm));
    expect(DesignTokens.fontSizeSm, lessThan(DesignTokens.fontSizeBase));
    expect(DesignTokens.fontSizeBase, lessThan(DesignTokens.fontSizeLg));
    expect(DesignTokens.fontSizeLg, lessThan(DesignTokens.fontSizeXl));
    expect(DesignTokens.fontSizeXl, lessThan(DesignTokens.fontSizeXxl));

    for (final brand in AppBrands.all) {
      final theme = brand.theme;
      expect(
        theme.textTheme.bodyMedium!.fontSize,
        DesignTokens.fontSizeBase,
        reason: brand.id,
      );
      expect(
        theme.textTheme.titleLarge!.fontSize,
        DesignTokens.fontSizePageTitle,
        reason: brand.id,
      );
      expect(
        theme.inputDecorationTheme.hintStyle!.fontSize,
        DesignTokens.fontSizeBody,
        reason: brand.id,
      );
      expect(
        theme.inputDecorationTheme.labelStyle!.fontSize,
        DesignTokens.fontSizeSm,
        reason: brand.id,
      );
      expect(
        theme.inputDecorationTheme.floatingLabelStyle!.fontSize,
        DesignTokens.fontSizeXs,
        reason: brand.id,
      );
    }
  });

  test('四类共享按钮、图标按钮与选择器动作按钮共用最小高度', () {
    const minimumHeight = Size(0, DesignTokens.controlMinHeight);
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 10);
    for (final brand in AppBrands.all) {
      final theme = brand.theme;
      for (final style in [
        theme.filledButtonTheme.style!,
        theme.elevatedButtonTheme.style!,
        theme.outlinedButtonTheme.style!,
        theme.textButtonTheme.style!,
      ]) {
        expect(style.minimumSize!.resolve({}), minimumHeight, reason: brand.id);
        expect(style.padding!.resolve({}), padding, reason: brand.id);
        expect(style.visualDensity, VisualDensity.standard, reason: brand.id);
        expect(
          style.textStyle!.resolve({})!.fontSize,
          DesignTokens.fontSizeButton,
          reason: brand.id,
        );
        expect(
          style.textStyle!.resolve({})!.fontWeight,
          DesignTokens.fontWeightMedium,
          reason: brand.id,
        );
      }

      expect(
        theme.iconButtonTheme.style!.minimumSize!.resolve({}),
        const Size(
          DesignTokens.controlMinHeight,
          DesignTokens.controlMinHeight,
        ),
        reason: brand.id,
      );

      for (final style in [
        theme.datePickerTheme.confirmButtonStyle!,
        theme.datePickerTheme.cancelButtonStyle!,
        theme.timePickerTheme.confirmButtonStyle!,
        theme.timePickerTheme.cancelButtonStyle!,
      ]) {
        expect(style.minimumSize!.resolve({}), minimumHeight, reason: brand.id);
        expect(style.visualDensity, VisualDensity.standard, reason: brand.id);
      }
    }
  });

  test('打包字体在 400/500/600/700 注册，变量字重覆盖 400–700 且可离线加载', () async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    final entry = manifest.cast<Map<String, dynamic>>().singleWhere(
      (item) => item['family'] == DesignTokens.fontFamily,
    );
    final fonts = (entry['fonts'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(fonts.map((font) => font['weight']).toSet(), {400, 500, 600, 700});

    final assets = fonts.map((font) => font['asset']).toSet();
    expect(assets, hasLength(1));
    final asset = assets.single as String;

    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final tables = data.getUint16(4);
    int? fvar;
    for (var i = 0; i < tables; i++) {
      final record = 12 + 16 * i;
      final tag = ascii.decode(bytes.sublist(record, record + 4));
      if (tag == 'fvar') fvar = data.getUint32(record + 8);
    }
    expect(fvar, isNotNull, reason: '打包字体必须是变量字体');

    final axisCount = data.getUint16(fvar! + 8);
    final axisSize = data.getUint16(fvar + 10);
    final axisOffset = fvar + data.getUint16(fvar + 4);
    double? minWeight;
    double? maxWeight;
    for (var i = 0; i < axisCount; i++) {
      final axis = axisOffset + i * axisSize;
      if (ascii.decode(bytes.sublist(axis, axis + 4)) == 'wght') {
        minWeight = data.getInt32(axis + 4) / 65536;
        maxWeight = data.getInt32(axis + 12) / 65536;
      }
    }
    expect(minWeight, isNotNull, reason: '变量字体需要 wght 轴');
    expect(minWeight!, lessThanOrEqualTo(400));
    expect(maxWeight!, greaterThanOrEqualTo(700));

    await (FontLoader(
      DesignTokens.fontFamily,
    )..addFont(Future.value(data))).load();
  });
}
