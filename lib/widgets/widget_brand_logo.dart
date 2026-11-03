// GENERATED FILE — 由 scripts/sync_app_icons.py 从唯一母版
// assets/logo/duoyi_app_logo.svg 生成，请勿手改；重新生成请运行
// `python3 scripts/sync_app_icons.py`。
//
// 母版：88×88 画布，#C85656 红色圆角方块（radius 32）承载白色三块几何图形，
// 图形变换为 translate(20 68) scale(.09375 -.09375)。Android 原生小组件矢量
// drawable/duoyi_widget_logo.xml 由同一母版生成并套用同一组变换，因此应用内
// 预览、认证页与系统小组件不会各自维护第二种图形。

import 'package:flutter/material.dart';

import '../core/i18n.dart';

/// 红底白标品牌标记：与 Android 小组件、各平台图标共用同一母版的矢量绘制。
/// 红色圆角方块是标记本身，方块外部画布保持透明。
class WidgetBrandLogo extends StatelessWidget {
  /// 母版品牌红 `#C85656`，不随主题主色改色。
  static const Color brandRed = Color(0xFFC85656);

  /// 母版图形白 `#FFFFFF`。
  static const Color markWhite = Color(0xFFFFFFFF);

  final double size;
  final String? semanticLabel;

  const WidgetBrandLogo({super.key, this.size = 24, this.semanticLabel});

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: semanticLabel ?? I18n.tr('mine.about.title'),
    child: SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: const _WidgetBrandLogoPainter(),
        size: Size.square(size),
      ),
    ),
  );
}

class _WidgetBrandLogoPainter extends CustomPainter {
  const _WidgetBrandLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final red = Paint()
      ..isAntiAlias = true
      ..color = WidgetBrandLogo.brandRed;
    final white = Paint()
      ..isAntiAlias = true
      ..color = WidgetBrandLogo.markWhite;
    canvas.save();
    canvas.scale(size.shortestSide / _artboard);
    canvas.drawPath(_tilePath, red);
    canvas.save();
    canvas.translate(_glyphTranslateX, _glyphTranslateY);
    canvas.scale(_glyphScaleX, _glyphScaleY);
    canvas.drawPath(_glyphPath, white);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WidgetBrandLogoPainter oldDelegate) => false;
}

/// 母版画布边长（母版 `viewBox="0 0 88 88"`）。
const double _artboard = 88;

/// 母版图形变换 `translate(20 68) scale(.09375 -.09375)`，与原生 vector 一致。
const double _glyphTranslateX = 20;
const double _glyphTranslateY = 68;
const double _glyphScaleX = 0.09375;
const double _glyphScaleY = -0.09375;

/// 母版红色圆角方块：母版 `<rect 0 0 88 88 rx 32>`。
final RRect _tileRect = RRect.fromRectAndRadius(
  Rect.fromLTWH(0, 0, 88, 88),
  Radius.circular(32),
);
final Path _tilePath = Path()..addRRect(_tileRect);

/// 母版白色三块图形：母版 `<path>` 的 M/L/C/Z 指令逐条落到 88 单位画布，
/// 绘制时套用上面的母版变换，与 `duoyi_widget_logo.xml` 同源同形。
final Path _glyphPath = Path()
  ..moveTo(192, 64)
  ..lineTo(107, 64)
  ..cubicTo(83, 64, 64, 83, 64, 107)
  ..lineTo(64, 405)
  ..cubicTo(64, 429, 83, 448, 107, 448)
  ..lineTo(192, 448)
  ..cubicTo(215, 448, 235, 429, 235, 405)
  ..lineTo(235, 107)
  ..cubicTo(235, 83, 215, 64, 192, 64)
  ..close()
  ..moveTo(320, 64)
  ..lineTo(405, 64)
  ..cubicTo(429, 64, 448, 83, 448, 107)
  ..lineTo(448, 213)
  ..cubicTo(448, 237, 429, 256, 405, 256)
  ..lineTo(320, 256)
  ..cubicTo(297, 256, 277, 237, 277, 213)
  ..lineTo(277, 107)
  ..cubicTo(277, 83, 297, 64, 320, 64)
  ..close()
  ..moveTo(448, 341)
  ..lineTo(448, 405)
  ..cubicTo(448, 429, 429, 448, 405, 448)
  ..lineTo(320, 448)
  ..cubicTo(297, 448, 277, 429, 277, 405)
  ..lineTo(277, 341)
  ..cubicTo(277, 318, 297, 299, 320, 299)
  ..lineTo(405, 299)
  ..cubicTo(429, 299, 448, 318, 448, 341)
  ..close();
