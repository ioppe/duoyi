import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/screens/widget_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('小组件预览覆盖待办 o、月历和目标三档尺寸', (tester) async {
    final screenshotKey = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(390, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: screenshotKey,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: const [
                    WidgetPreviewCard.todo(
                      displayMode: WidgetDisplayMode.compact,
                    ),
                    SizedBox(height: 12),
                    WidgetPreviewCard.todo(
                      displayMode: WidgetDisplayMode.standard,
                    ),
                    SizedBox(height: 12),
                    WidgetPreviewCard.todo(
                      displayMode: WidgetDisplayMode.detailed,
                    ),
                    SizedBox(height: 16),
                    WidgetPreviewCard.calendar(
                      displayMode: WidgetDisplayMode.compact,
                    ),
                    SizedBox(height: 12),
                    WidgetPreviewCard.calendar(
                      displayMode: WidgetDisplayMode.standard,
                    ),
                    SizedBox(height: 12),
                    WidgetPreviewCard.calendar(
                      displayMode: WidgetDisplayMode.detailed,
                    ),
                    SizedBox(height: 16),
                    WidgetPreviewCard.goal(
                      displayMode: WidgetDisplayMode.compact,
                    ),
                    SizedBox(height: 12),
                    WidgetPreviewCard.goal(
                      displayMode: WidgetDisplayMode.standard,
                    ),
                    SizedBox(height: 12),
                    WidgetPreviewCard.goal(
                      displayMode: WidgetDisplayMode.detailed,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    // 旧“o”假完成圈已移除：改为真实行/计数 key 的正向断言。
    expect(find.text('o'), findsNothing);
    expect(
      find.byKey(const ValueKey('widget-preview-todo-count')),
      findsWidgets,
    );
    expect(find.text('整理今日计划'), findsWidgets);
    expect(find.text('今天'), findsWidgets);
    expect(find.textContaining('发版准备'), findsWidgets);
    expect(find.textContaining('4x3'), findsWidgets);

    if (Platform.environment['DUOYI_CAPTURE_WIDGET_SCREENSHOT'] == '1') {
      final boundary =
          screenshotKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data!.buffer.asUint8List();
      image.dispose();
      final file = File(
        '.playwright-mcp/ui-regression/widget_preview_todo_calendar.png',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
    }
  });

  testWidgets('小组件预览窄屏 2x2、3x2、4x3 不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                children: [
                  WidgetPreviewCard.todo(
                    displayMode: WidgetDisplayMode.compact,
                  ),
                  SizedBox(height: 10),
                  WidgetPreviewCard.todo(
                    displayMode: WidgetDisplayMode.standard,
                  ),
                  SizedBox(height: 10),
                  WidgetPreviewCard.todo(
                    displayMode: WidgetDisplayMode.detailed,
                  ),
                  SizedBox(height: 14),
                  WidgetPreviewCard.calendar(
                    displayMode: WidgetDisplayMode.compact,
                  ),
                  SizedBox(height: 10),
                  WidgetPreviewCard.calendar(
                    displayMode: WidgetDisplayMode.standard,
                  ),
                  SizedBox(height: 10),
                  WidgetPreviewCard.calendar(
                    displayMode: WidgetDisplayMode.detailed,
                  ),
                  SizedBox(height: 14),
                  WidgetPreviewCard.goal(
                    displayMode: WidgetDisplayMode.compact,
                  ),
                  SizedBox(height: 10),
                  WidgetPreviewCard.goal(
                    displayMode: WidgetDisplayMode.standard,
                  ),
                  SizedBox(height: 10),
                  WidgetPreviewCard.goal(
                    displayMode: WidgetDisplayMode.detailed,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('o'), findsNothing);
    expect(
      find.byKey(const ValueKey('widget-preview-todo-count')),
      findsWidgets,
    );
    expect(find.text('整理今日计划'), findsWidgets);
    expect(find.text('今天'), findsWidgets);
    expect(find.textContaining('发版准备'), findsWidgets);
  });
}
