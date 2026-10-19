import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 路由层（showModalBottomSheet 的 Material）曾沿用 bottomSheetTheme 的
/// showDragHandle: true 与 modalElevation: 4，于是卡片上方多出一条拖动示意
/// 按钮、投影也比实际卡片更大。现在这两项由 AppModalSheet 自己负责，
/// 路由层必须保持关闭。
void main() {
  /// 统计实际绘制出来的“手柄”：又扁又短的小色块（40x4 或 Flutter 自带的 32x4）。
  int countDragHandles(WidgetTester tester) {
    var count = 0;
    for (final element in find.byType(Container).evaluate()) {
      final box = element.renderObject;
      if (box is! RenderBox || !box.hasSize) continue;
      final size = box.size;
      final isHandleShaped =
          size.height <= 6 && size.width >= 24 && size.width <= 48;
      if (isHandleShaped) count++;
    }
    return count;
  }

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showAppModalSheet<void>(
                  context: context,
                  builder: (_) => const AppModalSheet(
                    title: '新建任务',
                    child: SizedBox(height: 120, child: Text('内容')),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('底部弹窗只渲染一个拖动手柄', (tester) async {
    await pumpSheet(tester);

    // 手柄由 AppModalSheet 画成 40x4；路由层若也画（32x4）就是两条。
    expect(countDragHandles(tester), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('路由层不再叠加自身的投影与手柄占位', (tester) async {
    await pumpSheet(tester);

    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    final theme = AppBrands.defaultBrand.theme.bottomSheetTheme;
    // 旧实现把这两项留空，于是回落到主题里的 showDragHandle:true /
    // modalElevation:4；解析后的有效值必须显式关闭。
    final effectiveShowDragHandle =
        sheet.showDragHandle ?? theme.showDragHandle ?? false;
    final effectiveElevation =
        sheet.elevation ?? theme.modalElevation ?? 0;
    expect(effectiveShowDragHandle, isFalse);
    expect(effectiveElevation, 0);
    expect(sheet.backgroundColor, Colors.transparent);
  });

  testWidgets('弹窗卡片贴住屏幕底边', (tester) async {
    await pumpSheet(tester);

    final sheetRect = tester.getRect(find.byType(AppModalSheet));
    final cardRect = tester.getRect(find.byType(Material).last);
    expect(sheetRect.bottom, moreOrLessEquals(800, epsilon: 0.5));
    expect(cardRect.bottom, moreOrLessEquals(800, epsilon: 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('贴底后仍保留底部安全区留白', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // 全面屏底部手势条：模态路由读的是 view 的 padding，不是外层 MediaQuery；
    // 测试环境的 devicePixelRatio 默认是 3.0，会把 34 缩成 11.3。
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showAppModalSheet<void>(
                  context: context,
                  builder: (_) => const AppModalSheet(
                    title: '新建任务',
                    child: Text('内容'),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 卡片仍贴住屏幕底边，但内容底边要留出 34 的安全区。
    final sheetRect = tester.getRect(find.byType(AppModalSheet));
    final contentRect = tester.getRect(find.text('内容'));
    expect(sheetRect.bottom, moreOrLessEquals(800, epsilon: 0.5));
    expect(contentRect.bottom, lessThanOrEqualTo(800 - 34));
    expect(tester.takeException(), isNull);
  });
}
