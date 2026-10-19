import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/home_page_style.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('首页辅助色不再回退为正文色，并保留其他品牌配色', () {
    final defaultTheme = AppBrands.defaultBrand.theme;
    expect(
      defaultTheme.colorScheme.onSurfaceVariant,
      defaultTheme.colorScheme.onSurface,
    );
    final style = HomePageStyle.fromTheme(defaultTheme);
    expect(style.text, DesignTokens.homeText);
    expect(style.muted, DesignTokens.homeMuted);
    expect(style.subtle, DesignTokens.homeSubtle);
    expect(
      style.muted.computeLuminance(),
      greaterThan(style.text.computeLuminance()),
    );
    expect(
      style.subtle.computeLuminance(),
      greaterThan(style.muted.computeLuminance()),
    );
    for (final brand in AppBrands.all.where(
      (brand) => brand.style != BrandStyle.defaultBrand,
    )) {
      final branded = HomePageStyle.fromTheme(brand.theme);
      expect(branded.accent, brand.theme.colorScheme.primary, reason: brand.id);
      expect(branded.text, brand.theme.colorScheme.onSurface, reason: brand.id);
    }
  });

  for (final direction in TextDirection.values) {
    test('页签指示线在 $direction 下保持22像素且靠文字起点', () async {
      for (final labelWidth in [80.0, 150.0]) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final painter = const HomeTabIndicator(
          color: Colors.red,
        ).createBoxPainter();
        painter.paint(
          canvas,
          Offset.zero,
          ImageConfiguration(
            size: Size(labelWidth, 44),
            textDirection: direction,
          ),
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(labelWidth.toInt(), 44);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final columns = <int>{};
        for (var y = 0; y < image.height; y++) {
          for (var x = 0; x < image.width; x++) {
            if (bytes.getUint8((y * image.width + x) * 4 + 3) > 0) {
              columns.add(x);
            }
          }
        }
        expect(columns.length, 22);
        expect(
          columns.first,
          direction == TextDirection.ltr ? 0 : labelWidth.toInt() - 22,
        );
        painter.dispose();
        image.dispose();
        picture.dispose();
      }
    });
  }

  test('首页日期使用完整星期并跟随界面语言', () {
    addTearDown(() => I18n.setLocale(AppLocale.zh));
    final date = DateTime(2026, 10, 19);
    I18n.setLocale(AppLocale.zh);
    expect(I18nDateFormat.homeHeader(date), '10 月 19 日，星期一');
    I18n.setLocale(AppLocale.en);
    expect(I18nDateFormat.homeHeader(date), 'Oct 19, Monday');
  });
}
