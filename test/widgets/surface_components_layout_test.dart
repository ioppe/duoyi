import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/widgets/stats_overview_cards.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppSectionHeader handles long action on narrow width', (
    tester,
  ) async {
    await _pumpNarrow(
      tester,
      width: 280,
      child: AppSectionHeader(
        title: '非常长的标题用于验证窄屏标题不会被右侧操作按钮挤压到不可读',
        subtitle: '较长的说明文字也需要在窄屏下安全省略或换行',
        actionLabel: '导出全部长期统计数据',
        actionIcon: Icons.file_download_outlined,
        onAction: () {},
      ),
    );

    expect(find.textContaining('非常长的标题'), findsOneWidget);
    expect(find.textContaining('导出全部'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppStatusBadge constrains long labels in narrow containers', (
    tester,
  ) async {
    await _pumpNarrow(
      tester,
      width: 120,
      child: const AppStatusBadge(
        label: '超长角色名称和权限标签会被安全截断而不是撑破父容器',
        color: Colors.indigo,
        icon: Icons.verified_user_outlined,
      ),
    );

    expect(find.byType(AppStatusBadge), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'AppSettingsTile stacks complex actions without shrinking touch targets',
    (tester) async {
      await _pumpNarrow(
        tester,
        width: 320,
        child: AppSettingsTile(
          icon: Icons.tune_outlined,
          title: '底部导航和通知设置里的超长设置项标题',
          subtitle: '副标题也可能来自动态状态，需要保留可读空间',
          color: Colors.teal,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '上移',
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: () {},
              ),
              IconButton(
                tooltip: '下移',
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: () {},
              ),
              Switch(value: true, onChanged: (_) {}),
            ],
          ),
        ),
      );

      expect(find.textContaining('底部导航'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
      final iconRect = tester.getRect(find.byIcon(Icons.tune_outlined));
      final titleRect = tester.getRect(find.text('底部导航和通知设置里的超长设置项标题'));
      final subtitleRect = tester.getRect(find.text('副标题也可能来自动态状态，需要保留可读空间'));
      final actionRect = tester.getRect(find.byType(Switch));
      final textCenterDy = _textBlockCenterDy(titleRect, subtitleRect);
      expect((iconRect.center.dy - textCenterDy).abs(), lessThan(5));
      expect(actionRect.top, greaterThan(subtitleRect.bottom));
      expect(
        tester.getSize(find.byType(IconButton).first).width,
        greaterThanOrEqualTo(kMinInteractiveDimension),
      );
      expect(actionRect.left, greaterThan(titleRect.left));
      expect(subtitleRect.top, greaterThan(titleRect.bottom));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('AppSettingsTile centers leading icon in the whole row', (
    tester,
  ) async {
    await _pumpNarrow(
      tester,
      width: 320,
      child: const AppSettingsTile(
        icon: Icons.notifications_none_outlined,
        title: '没有右侧按钮的设置项',
        subtitle: '默认箭头也不能让标题贴着图标上沿',
        color: Colors.orange,
      ),
    );

    final iconRect = tester.getRect(
      find.byIcon(Icons.notifications_none_outlined),
    );
    final titleRect = tester.getRect(find.text('没有右侧按钮的设置项'));
    final subtitleRect = tester.getRect(find.text('默认箭头也不能让标题贴着图标上沿'));
    final textCenterDy = _textBlockCenterDy(titleRect, subtitleRect);
    expect((iconRect.center.dy - textCenterDy).abs(), lessThan(5));
    expect(subtitleRect.top, greaterThan(titleRect.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'AppSettingsTile keeps the reminder time below text on narrow screens',
    (tester) async {
      await _pumpNarrow(
        tester,
        width: 320,
        child: AppSettingsTile(
          icon: Icons.schedule,
          title: '提醒时间',
          subtitle: '到点发送带声音和震动的提醒',
          color: Colors.deepOrange,
          trailing: TextButton(onPressed: () {}, child: const Text('08:30')),
        ),
      );

      final iconRect = tester.getRect(find.byIcon(Icons.schedule));
      final titleRect = tester.getRect(find.text('提醒时间'));
      final subtitleRect = tester.getRect(find.text('到点发送带声音和震动的提醒'));
      final actionRect = tester.getRect(find.text('08:30'));
      final textCenterDy = _textBlockCenterDy(titleRect, subtitleRect);
      expect((iconRect.center.dy - textCenterDy).abs(), lessThan(4));
      expect(actionRect.top, greaterThan(subtitleRect.bottom));
      expect(subtitleRect.top, greaterThan(titleRect.bottom));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('AppMetricCard 默认数值字号为主角，标题/单位保持 11', (tester) async {
    await _pumpNarrow(
      tester,
      width: 320,
      child: const AppMetricCard(
        title: '本周专注',
        value: '325',
        unit: '分钟',
        icon: Icons.timer,
        color: Colors.redAccent,
      ),
    );

    final spans = _metricValueSpans(tester, valueText: '325');
    final valueSpan = spans.value;
    final unitSpan = spans.unit!;
    final titleStyle = tester.widget<Text>(find.text('本周专注')).style;

    expect(valueSpan.style?.fontSize, DesignTokens.fontSizeMd);
    expect(valueSpan.style?.height, 1.1);
    expect(unitSpan.style?.fontSize, 11);
    expect(titleStyle?.fontSize, 11);
    expect(valueSpan.style!.fontSize!, greaterThan(titleStyle!.fontSize!));
    expect(valueSpan.style!.fontSize!, greaterThan(unitSpan.style!.fontSize!));
    expect(tester.takeException(), isNull);
  });

  testWidgets('StatsOverviewCard 不传样式时数值吃到 16 默认（我的页路径）', (tester) async {
    await _pumpNarrow(
      tester,
      width: 320,
      child: const StatsOverviewCard(
        title: '效率评分',
        value: '85',
        unit: '%',
        icon: Icons.insights,
        color: Colors.indigo,
      ),
    );

    final valueSpan = _metricValueSpans(tester, valueText: '85').value;
    expect(valueSpan.style?.fontSize, DesignTokens.fontSizeMd);
    expect(valueSpan.style?.height, 1.1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppMetricCard 显式 valueStyle 仍然优先生效', (tester) async {
    await _pumpNarrow(
      tester,
      width: 320,
      child: AppMetricCard(
        title: '连续打卡',
        value: '7',
        unit: '天',
        icon: Icons.repeat,
        color: Colors.teal,
        valueStyle: const TextStyle(fontSize: 14, height: 1.05),
      ),
    );

    final spans = _metricValueSpans(tester, valueText: '7');
    expect(spans.value.style?.fontSize, 14);
    expect(spans.value.style?.height, 1.05);
    expect(spans.unit?.style?.fontSize, 11);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppMetricCard 亮色下填充/描边/阴影走主题玻璃档（两套主题同源）', (tester) async {
    Future<BoxDecoration> pumpDecoration(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Center(
              child: AppMetricCard(
                title: '本周专注',
                value: '325',
                icon: Icons.timer,
                color: Colors.redAccent,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ink = tester.widget<Ink>(find.byType(Ink).first);
      return ink.decoration! as BoxDecoration;
    }

    final defaultDecoration = await pumpDecoration(
      AppBrands.defaultBrand.theme,
    );
    final glassDecoration = await pumpDecoration(AppBrands.liquidGlass.theme);
    final defaultStyle = AppBrands.defaultBrand.theme
        .extension<AppSurfaceStyle>()!;
    final glassStyle = AppBrands.liquidGlass.theme
        .extension<AppSurfaceStyle>()!;

    // 填充走 cardFillColor（默认主题此前回退 surface@0.85）。
    expect(defaultDecoration.color, defaultStyle.cardFillColor);
    expect(glassDecoration.color, glassStyle.cardFillColor);
    // 描边走 cardBorder（此前固定灰 outlineVariant@0.18）。
    expect(defaultDecoration.border, defaultStyle.cardBorder);
    expect(glassDecoration.border, glassStyle.cardBorder);
    // 阴影走 cardShadow（此前固定无阴影）。
    expect(defaultDecoration.boxShadow, defaultStyle.cardShadow);
    expect(glassDecoration.boxShadow, glassStyle.cardShadow);
  });
}

/// 在指标卡的富文本里找到数值/单位 span。
/// Text.build 会把传入的 textSpan 再包一层（children: [textSpan]），
/// 因此按文本内容在两层里递归查找，避免依赖固定层级。
({TextSpan value, TextSpan? unit}) _metricValueSpans(
  WidgetTester tester, {
  required String valueText,
}) {
  final roots = tester
      .widgetList<RichText>(find.byType(RichText))
      .map((rich) => rich.text as TextSpan);
  for (final root in roots) {
    final children = root.children;
    if (children == null) {
      continue;
    }
    for (final child in children) {
      final childSpan = child as TextSpan;
      if (childSpan.text == valueText) {
        return (value: childSpan, unit: null);
      }
      final nested = childSpan.children;
      if (nested == null) {
        continue;
      }
      for (var i = 0; i < nested.length; i++) {
        final nestedSpan = nested[i] as TextSpan;
        if (nestedSpan.text == valueText) {
          return (
            value: nestedSpan,
            unit: i + 1 < nested.length ? nested[i + 1] as TextSpan : null,
          );
        }
      }
    }
  }
  throw StateError('找不到文本为 "$valueText" 的指标数值富文本');
}

double _textBlockCenterDy(Rect titleRect, Rect subtitleRect) {
  final top = titleRect.top < subtitleRect.top
      ? titleRect.top
      : subtitleRect.top;
  final bottom = titleRect.bottom > subtitleRect.bottom
      ? titleRect.bottom
      : subtitleRect.bottom;
  return (top + bottom) / 2;
}

Future<void> _pumpNarrow(
  WidgetTester tester, {
  required double width,
  required Widget child,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
