import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/models/note.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/todo_detail_screen.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpDetail(
  WidgetTester tester, {
  required Size size,
  ThemeData? theme,
  double textScale = 1,
  String notes = '',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final provider = TodoProvider();
  await provider.addTodo(
    TodoItem(
      id: 'layout-task',
      title: '工作',
      notes: notes,
      tags: ['一条很长的标签用于验证窄屏不会撑破页面边界'],
      attachments: const [
        NoteAttachment(
          name: '一份名称很长的工作资料与项目交付文档.pdf',
          uri: 'https://example.com/document.pdf',
        ),
      ],
      subtasks: [Subtask(title: '一条足够长的子任务标题用于验证文字换行与删除按钮位置')],
    ),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        theme: theme ?? AppBrands.defaultBrand.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const TodoDetailScreen(todoId: 'layout-task'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder descriptionField() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.hintText == '支持 Markdown 描述',
);

Finder descriptionCard() => find
    .ancestor(of: descriptionField(), matching: find.byType(AppSurfaceCard))
    .first;

void main() {
  testWidgets('描述工具栏与卡片等宽，输入区域不叠加边框', (tester) async {
    await pumpDetail(tester, size: const Size(720, 960));
    final toolbar = find
        .ancestor(
          of: find.byTooltip('标题'),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    final card = tester.getRect(descriptionCard());
    final toolbarRect = tester.getRect(toolbar);
    expect(toolbarRect.left, closeTo(card.left, 0.5));
    expect(toolbarRect.right, closeTo(card.right, 0.5));
    final field = tester.widget<TextField>(descriptionField());
    final decoration = field.decoration!.applyDefaults(
      Theme.of(tester.element(descriptionField())).inputDecorationTheme,
    );
    expect(decoration.enabledBorder, InputBorder.none);
    expect(decoration.focusedBorder, InputBorder.none);
    expect(decoration.filled, isFalse);
    expect(field.style?.fontSize, DesignTokens.fontSizeBody);
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽屏表单保持居中限宽，标题与正文采用统一字阶', (tester) async {
    await pumpDetail(tester, size: const Size(1280, 960));
    final title = find.widgetWithText(TextField, '任务名称');
    final titleRect = tester.getRect(title);
    expect(titleRect.width, lessThanOrEqualTo(840));
    expect(titleRect.center.dx, closeTo(640, 0.5));
    expect(tester.getSize(title).height, greaterThanOrEqualTo(56));
    expect(
      tester.widget<TextField>(title).style?.fontSize,
      DesignTokens.fontSizeMd,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('描述、附件、优先级与日期行采用相同正文字号', (tester) async {
    await pumpDetail(tester, size: const Size(720, 1200));
    for (final label in ['任务描述', '附件', '优先级', '截止日期', '重复']) {
      final finder = find.text(label);
      final text = tester.widget<Text>(finder);
      final style = DefaultTextStyle.of(
        tester.element(finder),
      ).style.merge(text.style);
      expect(style.fontSize, DesignTokens.fontSizeBody, reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  for (final brand in AppBrands.all) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('窄屏与${brand.name}主题 $scale倍字体滚动无溢出', (tester) async {
        await pumpDetail(
          tester,
          size: const Size(320, 844),
          theme: brand.theme,
          textScale: scale,
        );
        final list = find.byType(ListView).first;
        expect(tester.takeException(), isNull);
        await tester.drag(list, const Offset(0, -480));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.drag(list, const Offset(0, -480));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.drag(list, const Offset(0, -480));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Markdown 预览使用当前主题的文字和链接颜色', (tester) async {
    final theme = AppBrands.starRail.theme;
    await pumpDetail(
      tester,
      size: const Size(720, 960),
      theme: theme,
      notes: '正文 [链接](https://example.com) 与 `代码`',
    );
    await tester.tap(find.byTooltip('预览描述'));
    await tester.pumpAndSettle();
    final richText = tester.widget<RichText>(
      find
          .descendant(
            of: find.byKey(const ValueKey('todo-description-preview')),
            matching: find.byType(RichText),
          )
          .first,
    );
    final root = richText.text as TextSpan;
    expect(root.style?.fontSize, DesignTokens.fontSizeBody);
    expect(root.style?.color, theme.colorScheme.onSurface);
    final spans = <TextSpan>[];
    void collect(InlineSpan span) {
      if (span is TextSpan) {
        spans.add(span);
        for (final child in span.children ?? const <InlineSpan>[]) {
          collect(child);
        }
      }
    }

    collect(root);
    expect(
      spans.singleWhere((span) => span.text == '链接').style?.color,
      theme.colorScheme.primary,
    );
    expect(
      spans.singleWhere((span) => span.text == '代码').style?.backgroundColor,
      theme.colorScheme.surfaceContainerHighest,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('工具栏插入格式后可预览并切回编辑，正文不丢失', (tester) async {
    await pumpDetail(tester, size: const Size(390, 844), notes: '工作说明');
    await tester.tap(find.byTooltip('加粗'));
    await tester.pump();
    final field = tester.widget<TextField>(descriptionField());
    expect(field.controller!.text, contains('**'));
    final draft = field.controller!.text;
    await tester.tap(find.byTooltip('预览描述'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('todo-description-preview')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('编辑描述'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(descriptionField()).controller!.text,
      draft,
    );
    expect(tester.takeException(), isNull);
  });
}
