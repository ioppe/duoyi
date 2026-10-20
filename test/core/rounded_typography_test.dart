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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('九套主题的文字和共享控件均使用圆体粗体', () {
    for (final brand in AppBrands.all) {
      final theme = brand.theme;
      final styles = [
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
        theme.outlinedButtonTheme.style?.textStyle?.resolve({}),
        theme.textButtonTheme.style?.textStyle?.resolve({}),
        HomePageStyle.fromTheme(theme).typography(theme, size: 14),
        for (final states in [
          <WidgetState>{},
          {WidgetState.selected},
        ])
          theme.navigationBarTheme.labelTextStyle?.resolve(states),
      ];
      for (final style in styles) {
        expect(style, isNotNull, reason: brand.id);
        expect(
          style!.fontFamily,
          DesignTokens.fontFamilyRounded,
          reason: brand.id,
        );
        expect(style.fontWeight, FontWeight.w700, reason: brand.id);
      }
    }
  });

  test('打包字体注册为真实 700 字重，且能直接从应用资源加载', () async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json'))
            as List<dynamic>;
    final entry = manifest.cast<Map<String, dynamic>>().singleWhere(
      (item) => item['family'] == DesignTokens.fontFamilyRounded,
    );
    final font =
        (entry['fonts'] as List<dynamic>).single as Map<String, dynamic>;
    expect(font['weight'], 700);
    final asset = font['asset'] as String;
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final tables = data.getUint16(4);
    int? os2;
    for (var i = 0; i < tables; i++) {
      final record = 12 + 16 * i;
      final tag = ascii.decode(bytes.sublist(record, record + 4));
      if (tag == 'OS/2') os2 = data.getUint32(record + 8);
    }
    expect(os2, isNotNull);
    expect(data.getUint16(os2! + 4), 700);
    await (FontLoader(
      DesignTokens.fontFamilyRounded,
    )..addFont(Future.value(data))).load();
  });
}
