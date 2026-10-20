import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/widgets/habit_heatmap.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder get _cells => find.byWidgetPredicate(
  (widget) => widget is Container && widget.margin == const EdgeInsets.all(1.5),
);

String _key(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  double scale = 1,
  bool fit = true,
  int weeks = 12,
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final today = AppClock.today();
  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey('$width-$scale-$fit-$weeks-$dark'),
      theme: dark ? AppBrands.starRail.theme : AppBrands.defaultBrand.theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: HabitHeatmap(
              heatmapData: {
                _key(today): 3,
                _key(today.subtract(const Duration(days: 1))): 5,
              },
              weeks: weeks,
              fitToWidth: fit,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(DesignTokens.fontFamilyRounded)..addFont(
          rootBundle.load('assets/fonts/ResourceHanRoundedCN-Bold.ttf'),
        ))
        .load();
  });

  testWidgets('自适应图表填满绘图区，宽屏格子可超过原18px且不拉伸文字', (tester) async {
    for (final width in [224.0, 360.0, 600.0, 840.0]) {
      for (final dark in [false, true]) {
        await _pump(tester, width: width, dark: dark);
        final chart = tester.getRect(find.byType(HabitHeatmap));
        final first = tester.getRect(_cells.first);
        final lastColumn = tester.getRect(_cells.at(77));
        expect(lastColumn.right, closeTo(chart.right - 10, 1));
        expect(first.left, closeTo(chart.left + 10 + 28, 1));
        expect(first.width, closeTo(first.height, 0.01));
        if (width >= 360) expect(first.width, greaterThan(21));
        expect(find.byType(FittedBox), findsNothing);
        expect(_cells, findsNWidgets(84));
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('大字窄图不溢出，最右日期可滚动到达且打卡值及提示正确', (tester) async {
    await _pump(tester, width: 224, scale: 2, dark: true);
    final today = AppClock.today();
    final tip = '${I18nDateFormat.date(today)} · 3 次';
    final target = find.byTooltip(tip);
    expect(target, findsOneWidget);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    final monthLabels = find.byWidgetPredicate(
      (widget) =>
          widget is Text && RegExp(r'^\d+月$').hasMatch(widget.data ?? ''),
    );
    expect(monthLabels, findsNWidgets(3));
    for (final label in monthLabels.evaluate()) {
      expect(
        tester.getSize(find.byWidget(label.widget)).height,
        lessThanOrEqualTo(20),
      );
    }
    expect(position.maxScrollExtent, greaterThan(0));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    final rect = tester.getRect(target);
    final chart = tester.getRect(find.byType(HabitHeatmap));
    expect(rect.left, greaterThanOrEqualTo(chart.left));
    expect(rect.right, lessThanOrEqualTo(chart.right));
    await tester.longPress(target);
    await tester.pumpAndSettle();
    expect(find.text(tip), findsOneWidget);
    final maxDay = find.byTooltip(
      '${I18nDateFormat.date(today.subtract(const Duration(days: 1)))} · 5 次',
    );
    final maxCell = tester.widget<Container>(
      find.descendant(
        of: maxDay,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container && widget.margin == const EdgeInsets.all(1.5),
        ),
      ),
    );
    expect(
      (maxCell.decoration! as BoxDecoration).color,
      const Color(0xFF2E7D32),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('默认年度图保持原有密度与52周数据，末端日期仍可访问', (tester) async {
    await _pump(tester, width: 320, fit: false, weeks: 52);
    expect(_cells, findsNWidgets(52 * 7));
    final size = tester.getSize(_cells.first);
    expect(size.width, inInclusiveRange(13.0, 21.0));
    expect(size.width, closeTo(size.height, 0.01));
    final tip = '${I18nDateFormat.date(AppClock.today())} · 3 次';
    await tester.ensureVisible(find.byTooltip(tip));
    await tester.pumpAndSettle();
    expect(find.byTooltip(tip).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
