import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 新建任务弹窗此前直接继承外层 AppSecondaryControlTheme 的紧凑档
/// （isDense + 10/8 内边距），主输入框在桌面上只有约 30px 高。
/// 现在改为套 AppFormFieldTheme，最小高度对齐账号表单。
void main() {
  Future<void> pumpTitleField(
    WidgetTester tester, {
    required double width,
    double textScale = 1.0,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: AppSecondaryControlTheme(
                  child: AppFormFieldTheme(
                    child: TextField(
                      autofocus: false,
                      decoration: const InputDecoration(
                        hintText: '准备做什么？例如：明天下午3点开会',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('新建任务主输入框至少达到账号表单的标准高度', (tester) async {
    await pumpTitleField(tester, width: 420);

    final fieldRect = tester.getRect(find.byType(TextField));
    expect(fieldRect.height, greaterThanOrEqualTo(DesignTokens.formFieldMinHeight));
    // 旧的紧凑档只有约 30px，这里明确守住「明显高于紧凑控件」。
    expect(fieldRect.height, greaterThan(40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('新建任务主输入框在窄屏下不溢出且保持高度', (tester) async {
    await pumpTitleField(tester, width: 320);

    final fieldRect = tester.getRect(find.byType(TextField));
    expect(fieldRect.height, greaterThanOrEqualTo(DesignTokens.formFieldMinHeight));
    expect(fieldRect.right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('新建任务主输入框在 1.3 倍字体下仍不溢出', (tester) async {
    await pumpTitleField(tester, width: 360, textScale: 1.3);

    final fieldRect = tester.getRect(find.byType(TextField));
    expect(fieldRect.height, greaterThanOrEqualTo(DesignTokens.formFieldMinHeight));
    expect(tester.takeException(), isNull);
  });
}
