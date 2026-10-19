import 'dart:convert';

import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/screens/anniversary_screen.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('纪念日编辑器与键盘共用半屏至三分之二屏限制', (tester) async {
    _setSurfaceSize(tester, const Size(390, 844));
    addTearDown(tester.view.reset);
    final provider = AnniversaryProvider();
    await provider.loadFromStorage();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAnniversaryEditor(
                  context,
                  fixedType: AnniversaryType.birthday,
                ),
                child: const Text('打开编辑器'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开编辑器'));
    await tester.pumpAndSettle();
    final card = find.descendant(
      of: find.byType(AppModalSheet),
      matching: find.byType(Material),
    ).first;
    expect(
      tester.getSize(card).height,
      inInclusiveRange(844 / 2 - 0.5, 844 * 2 / 3 + 0.5),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final rect = tester.getRect(card);
    expect(rect.height, closeTo(544 * 2 / 3, 0.5));
    expect(rect.bottom, closeTo(544, 0.5));
    await tester.tapAt(Offset(rect.center.dx, rect.top - 20));
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('birthday and anniversary list fits mobile and desktop widths', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final today = DateTime.now();
    final items = [
      Anniversary.create(
        id: 'long-birthday',
        title: '这是一个非常长的生日名称用于验证顶部统计和列表卡片不会溢出',
        description: '生日备注内容很长，窄屏下应该被限制在卡片内部而不是撑开布局',
        solarDate: DateTime(today.year - 18, 6, 28),
        type: AnniversaryType.birthday,
        calendarType: AnniversaryCalendarType.solar,
      ),
      Anniversary.create(
        id: 'long-lunar-memorial',
        title: '农历纪念日标题非常长用于验证公历农历展示不会超出边框',
        description: '农历日期说明很长，卡片底部文案需要省略或者换行处理',
        solarDate: DateTime(today.year - 3, 7, 22),
        type: AnniversaryType.memorial,
        calendarType: AnniversaryCalendarType.lunar,
      ),
    ];
    SharedPreferences.setMockInitialValues({
      'duoyi_anniversaries_v2': items
          .map((item) => jsonEncode(item.toJson()))
          .toList(),
    });
    final provider = AnniversaryProvider();
    await provider.loadFromStorage();

    for (final size in const [
      Size(320, 720),
      Size(390, 720),
      Size(430, 720),
      Size(1024, 768),
    ]) {
      _setSurfaceSize(tester, size);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: const AnniversaryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('anniversary_summary_total')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('anniversary_summary_within_30_days')),
        findsOneWidget,
      );
      expect(
        tester
            .getRect(find.byKey(const ValueKey('anniversary_summary_total')))
            .right,
        lessThanOrEqualTo(size.width),
      );
      _expectNoLayoutException(tester);
    }
  });

  testWidgets('anniversary editor date and reminder controls fit 320px width', (
    tester,
  ) async {
    _setSurfaceSize(tester, const Size(320, 720));
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final provider = AnniversaryProvider();
    await provider.loadFromStorage();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const BirthdayScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('anniversary_calendar_type_segments')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('anniversary_editor_date_tile')),
      findsOneWidget,
    );
    _expectNoLayoutException(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('anniversary_calendar_type_segments')),
        matching: find.text('农历'),
      ),
    );
    await tester.pumpAndSettle();
    _expectNoLayoutException(tester);

    await tester.ensureVisible(find.text('到期提醒'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('到期提醒'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(
        const ValueKey('anniversary_reminder_kind_segments'),
        skipOffstage: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('anniversary_reminder_kind_segments')),
      findsOneWidget,
    );
    _expectNoLayoutException(tester);
  });
}

void _setSurfaceSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
}

void _expectNoLayoutException(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}
