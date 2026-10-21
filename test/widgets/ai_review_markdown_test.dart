import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/widgets/ai_review_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

const _sample = '''### 本周解读

**保留真实记录。 ** 从**一件小事**开始。

- 只记下一步。
- 保留 `10 分钟` 专注。

### 未来 7 天

1. 写下行动。
2. 检查进展。

> 记录要真实。

| 方向 | 行动 |
| --- | --- |
| 专注 | 保持短时开始 |
''';

Widget _app({String data = _sample, AppBrand? brand, double scale = 1}) =>
    MaterialApp(
      theme: (brand ?? AppBrands.defaultBrand).theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [AiReviewMarkdown(data: data)],
        ),
      ),
    );

String _text() => find
    .byWidgetPredicate(
      (widget) => widget is RichText || widget is SelectableText,
    )
    .evaluate()
    .map((element) {
      final widget = element.widget;
      return widget is SelectableText
          ? widget.data ?? widget.textSpan!.toPlainText()
          : (widget as RichText).text.toPlainText();
    })
    .join('\n');

void main() {
  testWidgets(
    'Markdown renders blocks, inline styles and model-spaced strong',
    (tester) async {
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      final text = _text();
      expect(text, contains('本周解读'));
      expect(text, contains('保留真实记录。'));
      expect(text, contains('一件小事'));
      expect(text, contains('写下行动。'));
      expect(text, contains('记录要真实。'));
      expect(text, isNot(contains('###')));
      expect(text, isNot(contains('**')));
      expect(text, isNot(contains('`10 分钟`')));
      expect(find.byType(Table), findsOneWidget);
      final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      expect(markdown.data, _sample, reason: '渲染兼容不应改写原始内容');
      expect(markdown.selectable, isTrue);
      expect(find.byType(SelectableText), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(AiReviewMarkdown),
          matching: find.byType(ListView),
        ),
        findsNothing,
        reason: '解读跟随原页面滚动，不嵌套独立列表',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('code blocks and escaped literal markers are not rewritten', (
    tester,
  ) async {
    const data = r'''**这句是重点。 **

```markdown
**literal **
### literal
```

`**inline literal **`

\*\*escaped literal\*\*
''';
    await tester.pumpWidget(_app(data: data));
    await tester.pumpAndSettle();
    final text = _text();
    expect(text, contains('这句是重点。'));
    expect(text, isNot(contains('**这句是重点。 **')));
    expect(text, contains('**literal **'));
    expect(text, contains('### literal'));
    expect(text, contains('**inline literal **'));
    expect(text, contains('**escaped literal**'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy plain text remains readable', (tester) async {
    const data = '本周回顾：保留轻量记录。\n下周建议：每天完成一件小事。';
    await tester.pumpWidget(_app(data: data));
    await tester.pumpAndSettle();
    expect(_text(), contains('本周回顾：保留轻量记录。'));
    expect(_text(), contains('下周建议：每天完成一件小事。'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('nine themes keep rounded text and fit narrow/enlarged reports', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final brand in AppBrands.all) {
      for (final width in [320.0, 1440.0]) {
        for (final scale in [1.0, 2.0]) {
          tester.view.physicalSize = Size(width, 1200);
          await tester.pumpWidget(_app(brand: brand, scale: scale));
          await tester.pumpAndSettle();
          final style = tester
              .widget<MarkdownBody>(find.byType(MarkdownBody))
              .styleSheet!;
          for (final textStyle in [
            style.p,
            style.h1,
            style.h2,
            style.h3,
            style.strong,
            style.code,
            style.tableHead,
            style.tableBody,
          ]) {
            expect(textStyle!.fontFamily, DesignTokens.fontFamilyRounded);
            expect(textStyle.fontWeight, DesignTokens.fontWeightStrong);
            expect(textStyle.color, brand.theme.colorScheme.onSurface);
          }
          expect(style.h3!.fontSize, greaterThan(style.p!.fontSize!));
          expect(
            tester.takeException(),
            isNull,
            reason: '${brand.id}, $width, $scale',
          );
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    }
  });
}
