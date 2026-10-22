import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/widgets/result_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets('加载动画随减少动画与页面可见性停止和恢复', (tester) async {
    const loading = LoadingState(key: ValueKey('loading'), message: '正在加载');
    await _pump(tester, loading);
    expect(find.byType(ShaderMask), findsNWidgets(3));
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await _pump(tester, loading, reduced: true);
    await tester.pumpAndSettle();
    expect(find.byType(ShaderMask), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);

    await _pump(tester, loading);
    expect(find.byType(ShaderMask), findsNWidgets(3));
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await _pump(tester, loading, visible: false);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);

    await _pump(tester, loading);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('九套主题下静态骨架使用当前表面色', (tester) async {
    for (final brand in AppBrands.all) {
      await _pump(
        tester,
        LoadingState(key: ValueKey(brand.id)),
        reduced: true,
        theme: brand.theme,
      );
      await tester.pumpAndSettle();
      final bars = tester.widgetList<Container>(
        find.descendant(
          of: find.byType(LoadingState),
          matching: find.byType(Container),
        ),
      );
      final colors = bars
          .where((bar) => bar.decoration is BoxDecoration)
          .map((bar) => (bar.decoration! as BoxDecoration).color);
      expect(
        colors,
        everyElement(brand.theme.colorScheme.surfaceContainerHighest),
      );
      expect(colors.length, 3);
      expect(tester.takeException(), isNull, reason: brand.id);
    }
  });

  testWidgets('短屏大字空态的操作可滚动到达', (tester) async {
    tester.view.physicalSize = const Size(260, 180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var actions = 0;
    await _pump(
      tester,
      EmptyState(
        icon: Icons.inbox_outlined,
        message: '暂无记录，从一件小事开始',
        description: '添加内容后会在这里展示，也可以稍后回来继续。',
        actionLabel: '创建记录',
        onAction: () => actions++,
      ),
      reduced: true,
      scale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('创建记录'));
    await tester.tap(find.text('创建记录'));
    expect(actions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('短屏大字加载说明可滚动且不溢出', (tester) async {
    tester.view.physicalSize = const Size(260, 140);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      const LoadingState(message: '正在加载记录，请稍候，完成后将在这里展示', lines: 4),
      reduced: true,
      scale: 2,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('正在加载记录，请稍候，完成后将在这里展示'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('错误状态本地化默认标题、重试并保留主题错误色', (tester) async {
    I18n.setLocale(AppLocale.en);
    var retries = 0;
    final theme = AppBrands.starRail.theme;
    await _pump(
      tester,
      ErrorState(error: 'Connection lost', onRetry: () => retries++),
      reduced: true,
      theme: theme,
    );
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Connection lost'), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.error_outline)).color,
      theme.colorScheme.error,
    );
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduced = false,
  bool visible = true,
  double scale = 1,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      themeAnimationStyle: AnimationStyle.noAnimation,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduced,
          textScaler: TextScaler.linear(scale),
        ),
        child: TickerMode(enabled: visible, child: child!),
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}
