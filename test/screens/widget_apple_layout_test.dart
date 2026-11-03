import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const ValueKey<String> _headerKey = ValueKey('widget-preview-header-label');
const ValueKey<String> _navTrackKey = ValueKey('widget-preview-nav-track');
const ValueKey<String> _navSelectedKey = ValueKey(
  'widget-preview-nav-selected',
);

Finder _navTab(int index) => find.byKey(ValueKey('widget-preview-nav-$index'));

Future<TodoProvider> _emptyTodoProvider() async {
  final provider = TodoProvider();
  await provider.loadFromStorage();
  addTearDown(provider.dispose);
  return provider;
}

Future<void> _pumpCard(
  WidgetTester tester,
  Widget card, {
  TodoProvider? todos,
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  Size surface = const Size(360, 680),
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

Color _containerColor(WidgetTester tester, Key key) {
  final container = tester.widget<Container>(find.byKey(key));
  return (container.decoration! as BoxDecoration).color!;
}

Color? _labelColorIn(WidgetTester tester, Finder parent) => tester
    .widget<Text>(find.descendant(of: parent, matching: find.byType(Text)))
    .style
    ?.color;

String _todoEmptyHint() =>
    I18n.tr('widget.todo_empty_hint').replaceAll('{tab}', I18n.tr('nav.todo'));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('空 TodoProvider 渲染居中空态与新增提示文案', (tester) async {
    final todos = await _emptyTodoProvider();
    expect(todos.todos, isEmpty);

    await _pumpCard(
      tester,
      const WidgetPreviewCard.todo(displayMode: WidgetDisplayMode.standard),
      todos: todos,
    );

    expect(tester.takeException(), isNull);
    final emptyTitle = find.text(I18n.tr('widget.todo_top3_empty'));
    final emptyHint = find.text(_todoEmptyHint());
    expect(emptyTitle, findsOneWidget, reason: '可用 Provider 且无待办必须是真空态');
    expect(emptyHint, findsOneWidget);
    // 示例列表不能混进真空态。
    expect(find.text('整理今日计划'), findsNothing);
    expect(find.text('项目复盘 · 3 个子任务'), findsNothing);

    final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle_outline));
    expect(icon.size, 26);
    expect(tester.widget<Text>(emptyTitle).style!.fontSize, 14);
    expect(tester.widget<Text>(emptyHint).style!.fontSize, 11);

    // 空态水平居中（与卡内底栏同轴）。
    final navTrack = tester.getRect(find.byKey(_navTrackKey));
    final titleRect = tester.getRect(emptyTitle);
    expect((titleRect.center.dx - navTrack.center.dx).abs(), lessThan(2));
    // 旧“o”假完成圈已移除。
    expect(find.text('o'), findsNothing);
  });

  testWidgets('没有 TodoProvider 时保留示例列表和 4 个底部 tab', (tester) async {
    await _pumpCard(
      tester,
      const WidgetPreviewCard.todo(displayMode: WidgetDisplayMode.standard),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('整理今日计划'), findsOneWidget);
    expect(find.text('项目复盘 · 3 个子任务'), findsOneWidget);
    // 新的滚动契约：示例数据同样不按密度截断，全部条目都可滚动浏览。
    expect(find.text('晚间运动 30 分钟'), findsOneWidget);
    expect(find.text(I18n.tr('widget.todo_top3_empty')), findsNothing);

    expect(
      tester.widget<Text>(find.byKey(_headerKey)).data,
      I18n.tr('nav.todo'),
    );
    for (var index = 0; index < 4; index++) {
      expect(_navTab(index), findsOneWidget);
    }
    expect(find.byKey(_navSelectedKey), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(_navSelectedKey)).data,
      I18n.tr('nav.todo'),
    );
  });

  testWidgets('core 4 的 compact 预览仍显示 4 个 tab', (tester) async {
    const cards = <Widget>[
      WidgetPreviewCard.todo(displayMode: WidgetDisplayMode.compact),
      WidgetPreviewCard.focus(displayMode: WidgetDisplayMode.compact),
      WidgetPreviewCard.habit(displayMode: WidgetDisplayMode.compact),
      WidgetPreviewCard.calendar(displayMode: WidgetDisplayMode.compact),
    ];
    for (final card in cards) {
      await _pumpCard(tester, card);
      expect(tester.takeException(), isNull);
      for (var index = 0; index < 4; index++) {
        expect(
          _navTab(index),
          findsOneWidget,
          reason: 'compact 密度也必须保留第 $index 个 tab',
        );
      }
      expect(find.byKey(_navSelectedKey), findsOneWidget);
    }
  });

  testWidgets('320 宽 + 1.3 倍字号不溢出，空态与头部/底栏不重叠', (tester) async {
    final todos = await _emptyTodoProvider();
    await _pumpCard(
      tester,
      const WidgetPreviewCard.todo(displayMode: WidgetDisplayMode.standard),
      todos: todos,
      textScale: 1.3,
      surface: const Size(320, 640),
    );

    expect(tester.takeException(), isNull);
    final header = tester.getRect(find.byKey(_headerKey));
    final navTrack = tester.getRect(find.byKey(_navTrackKey));
    final emptyTitle = tester.getRect(
      find.text(I18n.tr('widget.todo_top3_empty')),
    );
    final emptyHint = tester.getRect(find.text(_todoEmptyHint()));

    expect(header.bottom, lessThanOrEqualTo(navTrack.top));
    expect(emptyTitle.top, greaterThanOrEqualTo(header.bottom - 0.5));
    expect(emptyTitle.bottom, lessThanOrEqualTo(emptyHint.top + 0.5));
    expect(emptyHint.bottom, lessThanOrEqualTo(navTrack.top + 0.5));
    expect(navTrack.right, lessThanOrEqualTo(320));
  });

  testWidgets('浅色/深色下选中段与正文都有对比，选择 key 可定位', (tester) async {
    for (final brightness in Brightness.values) {
      await _pumpCard(
        tester,
        const WidgetPreviewCard.todo(displayMode: WidgetDisplayMode.standard),
        brightness: brightness,
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(_navSelectedKey), findsOneWidget);

      final track = _containerColor(tester, _navTrackKey);
      final selectedBg = _containerColor(
        tester,
        const ValueKey('widget-preview-nav-0'),
      );
      final unselectedBg = _containerColor(
        tester,
        const ValueKey('widget-preview-nav-1'),
      );
      expect(selectedBg, isNot(track), reason: '$brightness 选中段必须与轨道区分');
      expect(unselectedBg, isNot(selectedBg));

      final selectedLabel = tester
          .widget<Text>(find.byKey(_navSelectedKey))
          .style!
          .color;
      final unselectedLabel = _labelColorIn(tester, _navTab(1));
      expect(selectedLabel, isNotNull);
      expect(unselectedLabel, isNotNull);
      expect(
        selectedLabel,
        isNot(unselectedLabel),
        reason: '$brightness 选中文字与未选中文字必须区分',
      );

      final headerColor = tester
          .widget<Text>(find.byKey(_headerKey))
          .style!
          .color;
      expect(headerColor, isNotNull);
      expect(headerColor, isNot(track), reason: '$brightness 正文不能与底栏轨道同色');
    }
  });
}
