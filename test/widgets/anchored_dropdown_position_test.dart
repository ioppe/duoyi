import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _fieldKey = ValueKey('dropdown_anchor');

Future<void> _pumpField(
  WidgetTester tester, {
  required double top,
  int count = 4,
  double scale = 1,
  bool compact = false,
  ValueChanged<String?>? onChanged,
}) async {
  tester.view.physicalSize = const Size(390, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final items = [
    for (var i = 1; i <= count; i++)
      DropdownMenuItem(value: 'Q$i', child: Text('Option $i')),
  ];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppBrands.defaultBrand.theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Positioned(
              left: 24,
              right: 24,
              top: top,
              child: compact
                  ? AppCompactDropdown<String>(
                      key: _fieldKey,
                      value: 'Q2',
                      items: items,
                      onChanged: onChanged ?? (_) {},
                    )
                  : AppDropdownField<String>(
                      key: _fieldKey,
                      initialValue: count == 1 ? 'Q1' : 'Q2',
                      items: items,
                      onChanged: onChanged ?? (_) {},
                    ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<Rect> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(_fieldKey));
  for (
    var i = 0;
    i < 24 && find.byType(PopupMenuItem<String>).evaluate().isEmpty;
    i++
  ) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
  final item = find.byType(PopupMenuItem<String>).first;
  expect(item, findsOneWidget);
  return tester.getRect(
    find.ancestor(of: item, matching: find.byType(Material)).first,
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(DesignTokens.fontFamily)..addFont(
          rootBundle.load('assets/fonts/ResourceHanRoundedCN-Bold.ttf'),
        ))
        .load();
  });

  for (final compact in [false, true]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('${compact ? '紧凑' : '表单'}四选项菜单 ×$scale 向上展开紧贴锚点', (
        tester,
      ) async {
        await _pumpField(tester, top: 590, compact: compact, scale: scale);
        final anchor = tester.getRect(find.byKey(_fieldKey));
        final menu = await _openMenu(tester);
        expect(
          anchor.top - menu.bottom,
          closeTo(6, 1),
          reason: '菜单使用实际四项内容高度，不能按320px预留而悬空。',
        );
        expect(menu.left, closeTo(anchor.left, 1));
        expect(menu.width, closeTo(anchor.width, 1));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('只有一项且下方能容纳时向下展开，不为最大高度翻到上方', (tester) async {
    await _pumpField(tester, top: 570, count: 1);
    final anchor = tester.getRect(find.byKey(_fieldKey));
    final menu = await _openMenu(tester);
    expect(menu.top - anchor.bottom, closeTo(6, 1));
    expect(menu.bottom, lessThanOrEqualTo(712));
    expect(tester.takeException(), isNull);
  });

  testWidgets('顶部菜单向下展开，点选后返回正确值', (tester) async {
    String? picked;
    await _pumpField(tester, top: 80, onChanged: (value) => picked = value);
    final anchor = tester.getRect(find.byKey(_fieldKey));
    final menu = await _openMenu(tester);
    expect(menu.top - anchor.bottom, closeTo(6, 1));
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Option 3'));
    await tester.pumpAndSettle();
    expect(picked, 'Q3');
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('长菜单紧贴锚点并保留高度上限和滚动', (tester) async {
    String? picked;
    await _pumpField(
      tester,
      top: 590,
      count: 20,
      onChanged: (value) => picked = value,
    );
    final anchor = tester.getRect(find.byKey(_fieldKey));
    final menu = await _openMenu(tester);
    expect(anchor.top - menu.bottom, closeTo(6, 1));
    expect(menu.height, lessThanOrEqualTo(320));
    final last = find.widgetWithText(PopupMenuItem<String>, 'Option 20');
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(picked, 'Q20');
    expect(tester.takeException(), isNull);
  });

  testWidgets('等待键盘收起和锚点回位后，菜单仍紧贴新位置', (tester) async {
    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Builder(
            builder: (context) => Stack(
              children: [
                const Positioned(
                  top: 50,
                  left: 20,
                  right: 20,
                  child: TextField(autofocus: true),
                ),
                Positioned(
                  top: MediaQuery.viewInsetsOf(context).bottom > 0 ? 320 : 590,
                  left: 24,
                  right: 24,
                  child: AppDropdownField<String>(
                    key: _fieldKey,
                    initialValue: 'Q2',
                    items: [
                      for (var i = 1; i <= 4; i++)
                        DropdownMenuItem(
                          value: 'Q$i',
                          child: Text('Option $i'),
                        ),
                    ],
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final before = tester.getRect(find.byKey(_fieldKey));
    await tester.tap(find.byKey(_fieldKey));
    await tester.pump(const Duration(milliseconds: 50));
    tester.view.viewInsets = const FakeViewPadding(bottom: 150);
    await tester.pump(const Duration(milliseconds: 50));
    tester.view.viewInsets = const FakeViewPadding();
    for (
      var i = 0;
      i < 24 && find.byType(PopupMenuItem<String>).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    final anchor = tester.getRect(find.byKey(_fieldKey));
    final menu = tester.getRect(
      find
          .ancestor(
            of: find.byType(PopupMenuItem<String>).first,
            matching: find.byType(Material),
          )
          .first,
    );
    expect(anchor.top, greaterThan(before.top));
    expect(anchor.top - menu.bottom, closeTo(6, 1));
    expect(tester.takeException(), isNull);
  });
}
