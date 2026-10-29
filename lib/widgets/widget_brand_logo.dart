import 'package:flutter/material.dart';

import '../core/i18n.dart';

/// 统一红底白标的矢量绘制，与 duoyi_unified_logo.svg 的 1/4 坐标一致。
/// 红色圆角方块是 logo 的组成部分，外部画布透明。
class WidgetBrandLogo extends StatelessWidget {
  static const Color brandRed = Color(0xFFC95455);
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
    canvas.save();
    canvas.scale(size.shortestSide / 24);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.75, 1.25, 22.5, 22),
        const Radius.circular(8),
      ),
      Paint()
        ..isAntiAlias = true
        ..color = WidgetBrandLogo.brandRed,
    );
    final white = Paint()
      ..isAntiAlias = true
      ..color = WidgetBrandLogo.markWhite;
    for (final rect in const [
      Rect.fromLTWH(7.5, 7.75, 4, 9),
      Rect.fromLTWH(12.5, 7.75, 4, 3.5),
      Rect.fromLTWH(12.5, 12.25, 4, 4.5),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1)),
        white,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WidgetBrandLogoPainter oldDelegate) => false;
}
