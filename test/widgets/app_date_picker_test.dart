import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/widgets/app_date_picker.dart';

void main() {
  test('日期和时间选择器避免二级页面大字号和厚边框回退', () {
    final timePicker = _readSource('lib/widgets/app_time_picker.dart');
    expect(timePicker, isNot(contains('fontSize: 34')));
    expect(timePicker, contains('fontSize: 24'));
    expect(timePicker, contains('fontWeight: DesignTokens.fontWeightStrong'));
    expect(
      timePicker,
      contains(
        'Border.all(\n'
        '                color: cs.primary.withValues(alpha: 0.12),\n'
        '                width: 0.45,',
      ),
    );

    final datePicker = _readSource('lib/widgets/app_date_picker.dart');
    expect(datePicker, isNot(contains('width: 1.2')));
    expect(
      datePicker,
      isNot(contains('Border.all(color: cs.primary.withValues(alpha: 0.18))')),
    );
    expect(
      datePicker,
      contains(
        'Border.all(color: cs.primary.withValues(alpha: 0.26), width: 0.45)',
      ),
    );
    expect(
      datePicker,
      contains(
        'Border.all(color: cs.primary.withValues(alpha: 0.14), width: 0.45)',
      ),
    );
    expect(
      datePicker,
      isNot(contains('Border.all(color: cs.primary.withValues(alpha: 0.16))')),
    );
    expect(datePicker, contains('color: cs.primary.withValues(alpha: 0.16),'));
    expect(datePicker, contains('width: 0.45,'));
  });

  testWidgets('公历日期选择器显示可点击日期网格', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                AppDatePicker.show(
                  context,
                  initialDate: DateTime(2026, 5, 17),
                  firstDate: DateTime(2026, 1, 1),
                  lastDate: DateTime(2026, 12, 31),
                );
              },
              child: const Text('打开日期'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开日期'));
    await tester.pumpAndSettle();

    expect(find.text('公历'), findsOneWidget);
    expect(find.text('2026年5月'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
    expect(find.text('一'), findsOneWidget);
    expect(find.text('日'), findsOneWidget);
  });

  testWidgets('公历当前月日期不是禁用灰色态', (tester) async {
    const scheme = ColorScheme.light(
      primary: Color(0xFF2563EB),
      primaryContainer: Color(0xFFDCE8FF),
      onPrimary: Colors.white,
      onSurface: Color(0xFF111827),
      onSurfaceVariant: Color(0xFF6B7280),
      surface: Colors.white,
      outlineVariant: Color(0xFFE5E7EB),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                AppDatePicker.show(
                  context,
                  initialDate: DateTime(2026, 5, 17),
                  firstDate: DateTime(2026, 1, 1),
                  lastDate: DateTime(2026, 12, 31),
                );
              },
              child: const Text('打开日期'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开日期'));
    await tester.pumpAndSettle();

    final dayFinder = find.byKey(const ValueKey('solar-day-2026-05-19'));
    final material = tester.widget<Material>(dayFinder);
    expect(material.color, isNot(Colors.transparent));

    final text = tester.widget<Text>(
      find.descendant(of: dayFinder, matching: find.text('19')),
    );
    expect(text.style?.color, scheme.onSurface);

    final outsideMonthFinder = find.byKey(
      const ValueKey('solar-day-2026-04-27'),
    );
    final outsideText = tester.widget<Text>(
      find.descendant(of: outsideMonthFinder, matching: find.text('27')),
    );
    expect(outsideText.style?.color, isNot(scheme.onSurface));
  });
}

String _readSource(String path) {
  return File(path).readAsStringSync().replaceAll('\r\n', '\n');
}
