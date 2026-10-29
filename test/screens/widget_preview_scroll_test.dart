import 'dart:convert';

import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const ValueKey<String> _todoListKey = ValueKey('widget-preview-todo-list');
const ValueKey<String> _monthGridKey = ValueKey(
  'widget-preview-calendar-month-grid',
);
const ValueKey<String> _todayButtonKey = ValueKey(
  'widget-preview-calendar-today',
);

Finder _monthKey(String yearMonth) =>
    find.byKey(ValueKey('widget-calendar-month-$yearMonth'));

Finder _dateKey(String date) =>
    find.byKey(ValueKey('widget-calendar-date-$date'));

Future<void> _pumpCard(
  WidgetTester tester,
  Widget card, {
  TodoProvider? todos,
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  Size surface = const Size(360, 720),
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  Widget body = card;
  if (todos != null) {
    body = ChangeNotifierProvider<TodoProvider>.value(
      value: todos,
      child: body,
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: body,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<TodoProvider> _providerWithTodos(List<TodoItem> items) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'todos': jsonEncode(<Map<String, dynamic>>[
      for (final todo in items) todo.toJson(),
    ]),
  });
  final provider = TodoProvider();
  await provider.loadFromStorage();
  addTearDown(provider.dispose);
  return provider;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalTimezoneResolver.setApplicationTimeZone('UTC');
  });

  tearDown(() {
    AppClock.debugNow = null;
  });

  testWidgets('今日待办可滚动到最后一项，数据刷新不回到顶部', (tester) async {
    AppClock.debugNow = () => DateTime.utc(2026, 10, 26, 8);
    final todos = await _providerWithTodos(<TodoItem>[
      for (var index = 0; index < 20; index++)
        TodoItem(
          id: 'todo-$index',
          title: '待办条目 $index',
          sortOrder: index,
          date: DateTime(2026, 10, 26),
        ),
    ]);

    await _pumpCard(
      tester,
      const WidgetPreviewCard.todo(displayMode: WidgetDisplayMode.standard),
      todos: todos,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('待办条目 0'), findsOneWidget);
    // 不再按密度截断数据：末项只是初始不在视口内，可以滚动到。
    expect(find.text('待办条目 19'), findsNothing);

    await tester.drag(find.byKey(_todoListKey), const Offset(0, -600));
    await tester.pump();
    expect(find.text('待办条目 19'), findsOneWidget);
    expect(find.text('待办条目 0'), findsNothing);

    // 数据变化只重建可见行，不重置滚动位置（首项仍在视口外）。
    await todos.addTodo(
      TodoItem(id: 'new', title: '新增条目', date: DateTime(2026, 10, 26)),
      waitForReminderSync: false,
    );
    await tester.pump();
    expect(find.text('待办条目 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('月历恢复原单月尺寸和顶部月份标题，不显示纵向月份列表', (tester) async {
    AppClock.debugNow = () => DateTime.utc(2026, 10, 26, 8);
    await _pumpCard(
      tester,
      const WidgetPreviewCard.calendar(displayMode: WidgetDisplayMode.standard),
    );
    expect(tester.takeException(), isNull);
    expect(_monthKey('2026-10'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('widget-preview-calendar-months')),
      findsNothing,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('widget-preview-header-label')),
          )
          .data,
      I18n.tr(
        'widget.calendar_month_title',
      ).replaceAll('{year}', '2026').replaceAll('{month}', '10'),
    );
    final gridRect = tester.getRect(find.byKey(_monthGridKey));
    for (var day = 1; day <= 31; day++) {
      final cell = _dateKey('2026-10-${day.toString().padLeft(2, '0')}');
      expect(cell, findsOneWidget);
      final cellRect = tester.getRect(cell);
      expect(cellRect.top, greaterThanOrEqualTo(gridRect.top));
      expect(cellRect.bottom, lessThanOrEqualTo(gridRect.bottom));
    }
    final todayCell = tester.widget<Container>(_dateKey('2026-10-26'));
    expect(
      (todayCell.decoration! as BoxDecoration).color,
      isNot(Colors.transparent),
    );

    expect(
      find.descendant(
        of: _monthKey('2026-10'),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
      reason: '单月正文不能被纵向月份列表挤占',
    );
    await tester.tap(find.byKey(_todayButtonKey));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(_monthGridKey)), gridRect);
    expect(tester.takeException(), isNull);
  });

  testWidgets('专注预览有 3 个控制按钮，暂停后首按钮显示继续', (tester) async {
    await _pumpCard(
      tester,
      const WidgetPreviewCard.focus(displayMode: WidgetDisplayMode.standard),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('widget-preview-focus-start')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('widget-preview-focus-pause')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('widget-preview-focus-stop')),
      findsOneWidget,
    );
    // 旧的“前往专注”入口已被 3 个控制按钮替换。
    expect(find.text(I18n.tr('widget.focus_open_label')), findsNothing);
    expect(find.text(I18n.tr('widget.focus_start_label')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('widget-preview-focus-start')));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('widget-preview-focus-pause')));
    await tester.pump();
    expect(find.text(I18n.tr('widget.focus_resume_label')), findsOneWidget);
    expect(find.text(I18n.tr('widget.focus_paused_label')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('widget-preview-focus-stop')));
    await tester.pump();
    expect(find.text(I18n.tr('widget.focus_start_label')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320 宽 + 1.3 倍字号下 3 个控制按钮与月历都不溢出', (tester) async {
    AppClock.debugNow = () => DateTime.utc(2026, 10, 26, 8);
    for (final card in const <Widget>[
      WidgetPreviewCard.focus(displayMode: WidgetDisplayMode.standard),
      WidgetPreviewCard.calendar(displayMode: WidgetDisplayMode.standard),
      WidgetPreviewCard.todo(displayMode: WidgetDisplayMode.standard),
    ]) {
      await _pumpCard(
        tester,
        card,
        textScale: 1.3,
        surface: const Size(320, 640),
      );
      expect(tester.takeException(), isNull, reason: '$card 不应溢出');
    }
  });

  testWidgets('浅色与深色下控制按钮文字都有对比', (tester) async {
    for (final brightness in Brightness.values) {
      await _pumpCard(
        tester,
        const WidgetPreviewCard.focus(displayMode: WidgetDisplayMode.standard),
        brightness: brightness,
      );
      expect(tester.takeException(), isNull);
      final startLabel = find.descendant(
        of: find.byKey(const ValueKey('widget-preview-focus-start')),
        matching: find.byType(Text),
      );
      final color = tester.widget<Text>(startLabel).style?.color;
      expect(color, isNotNull, reason: '$brightness 首按钮文字必须有颜色');
      expect(color, isNot(Colors.transparent));
    }
  });
}
