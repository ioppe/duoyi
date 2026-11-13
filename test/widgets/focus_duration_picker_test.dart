import 'package:duoyi/widgets/focus_duration_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required int focusMinutes,
  bool isCountUp = false,
  bool enabled = true,
  ValueChanged<int>? onMinutes,
  ValueChanged<bool>? onCountUp,
  Size size = const Size(800, 600),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: FocusDurationPicker(
            focusMinutes: focusMinutes,
            isCountUp: isCountUp,
            enabled: enabled,
            onMinutesSelected: onMinutes ?? (_) {},
            onCountUpChanged: onCountUp ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _dropdown => find.byKey(FocusDurationPicker.dropdownKey);
Finder get _countUp => find.byKey(FocusDurationPicker.countUpKey);

void main() {
  testWidgets('下拉一次展示完整预设，鼠标可直接选 90 分钟', (tester) async {
    int? picked;
    await _pump(tester, focusMinutes: 25, onMinutes: (value) => picked = value);

    // 收起态只有当前值，没有横向滚动容器（选项不需要拖动才能看到）。
    expect(_dropdown, findsOneWidget);
    expect(find.text('25 分钟'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);

    await tester.tap(_dropdown);
    await tester.pumpAndSettle();

    for (final minutes in kFocusDurationPresets) {
      expect(
        find.text(focusDurationOptionLabel(minutes)),
        findsWidgets,
        reason: '$minutes 分钟应完整出现在下拉里',
      );
    }
    final menu90 = find.text('90 分钟').last;
    expect(tester.getRect(menu90).right, lessThanOrEqualTo(800));
    await tester.tap(menu90);
    await tester.pumpAndSettle();

    expect(picked, 90);
    expect(tester.takeException(), isNull);
  });

  testWidgets('键盘 Tab 聚焦 + Enter 展开，方向键与 Enter 选中 90 分钟', (tester) async {
    int? picked;
    await _pump(tester, focusMinutes: 25, onMinutes: (value) => picked = value);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('90 分钟'), findsOneWidget, reason: 'Enter 应展开完整选项菜单');

    // 25 → 30 → 45 → 60 → 90
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(picked, 90);
    expect(find.text('90 分钟'), findsNothing);
  });

  testWidgets('Esc 只关闭下拉，不改变选择', (tester) async {
    int? picked;
    await _pump(tester, focusMinutes: 25, onMinutes: (value) => picked = value);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('90 分钟'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('90 分钟'), findsNothing);
    expect(picked, isNull);
  });

  testWidgets('运行中 / 暂停中禁用：下拉与正向计时都不可操作', (tester) async {
    await _pump(tester, focusMinutes: 25, enabled: false);

    expect(tester.widget<DropdownButton<int>>(_dropdown).onChanged, isNull);
    expect(tester.widget<ChoiceChip>(_countUp).onSelected, isNull);

    await tester.tap(_dropdown);
    await tester.pumpAndSettle();
    expect(find.text('90 分钟'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自定义时长作为唯一值保留，重建后不被重置', (tester) async {
    await _pump(tester, focusMinutes: 37);
    expect(find.text('37 分钟'), findsOneWidget);

    // Provider 重建（同一配置）后仍是 37 分钟。
    await _pump(tester, focusMinutes: 37);
    expect(find.text('37 分钟'), findsOneWidget);

    await tester.tap(_dropdown);
    await tester.pumpAndSettle();
    expect(find.text('37 分钟'), findsWidgets);
    expect(find.text('90 分钟'), findsOneWidget);
    expect(find.text('15 分钟'), findsOneWidget);
  });

  testWidgets('正向计时是独立选项，选中态由外部状态驱动', (tester) async {
    bool? countUp;
    await _pump(
      tester,
      focusMinutes: 25,
      onCountUp: (value) => countUp = value,
    );

    expect(find.text('正向计时'), findsOneWidget);
    expect(tester.widget<ChoiceChip>(_countUp).selected, isFalse);

    await tester.tap(_countUp);
    await tester.pumpAndSettle();
    expect(countUp, isTrue);

    await _pump(tester, focusMinutes: 25, isCountUp: true);
    expect(tester.widget<ChoiceChip>(_countUp).selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final (size, scale) in [
    (const Size(320, 640), 1.5),
    (const Size(240, 420), 1.0),
  ]) {
    testWidgets('$size ×$scale 窄窗不溢出，下拉仍可展开', (tester) async {
      await _pump(tester, focusMinutes: 25, size: size, textScale: scale);
      expect(tester.takeException(), isNull);

      await tester.tap(_dropdown);
      await tester.pumpAndSettle();
      expect(find.text('90 分钟'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    });
  }
}
