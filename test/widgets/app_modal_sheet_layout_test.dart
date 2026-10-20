import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder sheetCard() => find
    .descendant(of: find.byType(AppModalSheet), matching: find.byType(Material))
    .first;

void expectSheetHeight(WidgetTester tester, double availableHeight) {
  final rect = tester.getRect(sheetCard());
  expect(rect.height, greaterThanOrEqualTo(availableHeight / 2 - 0.5));
  expect(rect.height, lessThanOrEqualTo(availableHeight * 2 / 3 + 0.5));
}

Future<void> openSheet(
  WidgetTester tester, {
  required Size size,
  required Widget child,
  bool scrollable = true,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppBrands.defaultBrand.theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showAppModalSheet<void>(
                context: context,
                builder: (context) => AppModalSheet(
                  title: '测试弹窗',
                  scrollable: scrollable,
                  child: child,
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  for (final size in const [
    Size(320, 720),
    Size(390, 844),
    Size(1280, 800),
    Size(844, 390),
  ]) {
    testWidgets('短内容至少半屏 ${size.width}×${size.height}', (tester) async {
      await openSheet(tester, size: size, child: const Text('简短内容'));
      expectSheetHeight(tester, size.height);
      expect(tester.getRect(sheetCard()).bottom, closeTo(size.height, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('长内容初始至多三分之二屏且可滚到底 ${size.width}×${size.height}', (
      tester,
    ) async {
      await openSheet(
        tester,
        size: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 24; i++)
              SizedBox(height: 64, child: Text('第 $i 项')),
            Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('完成'),
              ),
            ),
          ],
        ),
      );
      expectSheetHeight(tester, size.height);
      await tester.ensureVisible(find.text('完成'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.byType(AppModalSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('点击卡片上方空白区域关闭弹窗', (tester) async {
    await openSheet(
      tester,
      size: const Size(390, 844),
      child: const Text('简短内容'),
    );
    final card = tester.getRect(sheetCard());
    await tester.tapAt(Offset(card.center.dx, card.top - 20));
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsNothing);
  });

  testWidgets('点击卡片内空白不关闭弹窗', (tester) async {
    await openSheet(
      tester,
      size: const Size(390, 844),
      child: const Text('简短内容'),
    );
    final card = tester.getRect(sheetCard());
    await tester.tapAt(Offset(card.center.dx, card.bottom - 24));
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsOneWidget);
  });

  testWidgets('键盘弹出后按剩余空间约束高度并可点击遮罩关闭', (tester) async {
    await openSheet(
      tester,
      size: const Size(390, 844),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [TextField(), SizedBox(height: 900)],
      ),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expectSheetHeight(tester, 544);
    final card = tester.getRect(sheetCard());
    expect(card.bottom, closeTo(544, 0.5));
    await tester.tapAt(Offset(card.center.dx, card.top - 20));
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自带滚动区域的内容接收剩余高度，底部条目仍可访问', (tester) async {
    await openSheet(
      tester,
      size: const Size(390, 560),
      scrollable: false,
      child: SizedBox(
        height: 420,
        child: ListView(
          children: [
            for (var i = 0; i < 20; i++)
              SizedBox(height: 64, child: Text('选项 $i')),
          ],
        ),
      ),
    );
    expectSheetHeight(tester, 560);
    await tester.scrollUntilVisible(find.text('选项 19'), 300);
    await tester.pumpAndSettle();
    expect(find.text('选项 19').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏放大字体时仍满足高度范围且无溢出', (tester) async {
    await openSheet(
      tester,
      size: const Size(320, 720),
      textScale: 1.5,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 12; i++) const Text('长内容在弹窗内部滚动，保留页面上方遮罩。'),
        ],
      ),
    );
    expectSheetHeight(tester, 720);
    expect(tester.takeException(), isNull);
  });
}
