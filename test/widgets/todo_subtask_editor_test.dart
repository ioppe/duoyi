import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:duoyi/widgets/todo_subtask_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host extends StatefulWidget {
  final List<Subtask> initial;
  final bool enabled;
  final double scale;
  final ThemeData? theme;
  const _Host({
    super.key,
    required this.initial,
    this.enabled = true,
    this.scale = 1,
    this.theme,
  });
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late List<Subtask> items = widget.initial;
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: widget.theme ?? AppBrands.defaultBrand.theme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(widget.scale)),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: AppFormFieldTheme(
          child: TodoSubtaskEditor(
            subtasks: items,
            enabled: widget.enabled,
            onChanged: (next) => setState(() => items = next),
          ),
        ),
      ),
    ),
  );
}

List<Subtask> _items() => [
  Subtask(id: 'a', title: '收集资料', sortOrder: 0),
  Subtask(id: 'b', title: '核实证据', sortOrder: 1),
  Subtask(id: 'c', title: '整理问题', sortOrder: 2),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      DesignTokens.fontFamily,
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'))).load();
  });
  setUp(() => I18n.setLocale(AppLocale.zh));

  testWidgets('子任务可编辑、增删、勾选且保持原对象和稳定ID', (tester) async {
    final source = _items();
    final host = GlobalKey<_HostState>();
    await tester.pumpWidget(_Host(key: host, initial: source));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('todo_subtask_text_a')),
      '收集方案和测试报告',
    );
    await tester.pump();
    expect(host.currentState!.items.first.id, 'a');
    expect(host.currentState!.items.first.title, '收集方案和测试报告');
    expect(source.first.title, '收集资料', reason: '草稿操作不能修改传入模型对象');
    await tester.tap(find.byKey(const ValueKey('todo_subtask_delete_b')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('todo_subtask_add_input')),
      '准备追问',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(I18n.tr('todo.subtask.add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo_subtask_complete_a')));
    await tester.pumpAndSettle();
    final items = host.currentState!.items;
    expect(items.map((task) => task.title), ['收集方案和测试报告', '整理问题', '准备追问']);
    expect(items.map((task) => task.sortOrder), [0, 1, 2]);
    expect(items.map((task) => task.id).toSet().length, 3);
    expect(items.first.isCompleted, isTrue);
    expect(source.first.isCompleted, isFalse);
    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('todo_subtask_add_input')),
    );
    expect(input.controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('显式把手拖动立即落位，后续帧不回旧序且编辑控制器不重建', (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final host = GlobalKey<_HostState>();
    await tester.pumpWidget(_Host(key: host, initial: _items()));
    await tester.pumpAndSettle();
    final first = find.byKey(const ValueKey('todo_subtask_text_a'));
    final controller = tester.widget<TextField>(first).controller;
    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    expect(list.buildDefaultDragHandles, isFalse);
    final start = tester.getCenter(
      find.byKey(const ValueKey('todo_subtask_drag_a')),
    );
    final target = Offset(
      start.dx,
      tester.getRect(find.byType(ReorderableListView)).bottom +
          tester.getSize(find.byKey(const ValueKey('a'))).height / 2,
    );
    final gesture = await tester.startGesture(start);
    await tester.pump();
    for (var step = 1; step <= 8; step++) {
      await gesture.moveTo(Offset.lerp(start, target, step / 8)!);
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 350));
    await gesture.up();
    var sawNewOrder = false;
    for (var frame = 0; frame < 45; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final ids = host.currentState!.items.map((task) => task.id).toList();
      if (ids.first == 'b') sawNewOrder = true;
      if (sawNewOrder) {
        expect(ids, ['b', 'c', 'a'], reason: '落位后第 $frame 帧不能回跳旧序');
        expect(
          tester.getTopLeft(first).dy,
          greaterThan(
            tester
                .getTopLeft(find.byKey(const ValueKey('todo_subtask_text_b')))
                .dy,
          ),
        );
      }
    }
    expect(sawNewOrder, isTrue);
    await tester.pumpAndSettle();
    expect(
      identical(tester.widget<TextField>(first).controller, controller),
      isTrue,
    );
    expect(host.currentState!.items.map((task) => task.sortOrder), [0, 1, 2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏与2倍字体长子任务换行增高，删除和拖动各有独立触点', (tester) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final theme in [
      AppBrands.defaultBrand.theme,
      AppBrands.starRail.theme,
    ]) {
      await tester.pumpWidget(
        _Host(
          initial: [Subtask(id: 'a', title: '核实云计算项目的证据与风险')],
          scale: 2,
          theme: theme,
        ),
      );
      await tester.pumpAndSettle();
      final text = find.byKey(const ValueKey('todo_subtask_text_a'));
      expect(tester.widget<TextField>(text).maxLines, isNull);
      expect(tester.getSize(text).height, greaterThan(56));
      final delete = tester.getRect(
        find.byKey(const ValueKey('todo_subtask_delete_a')),
      );
      final drag = tester.getRect(
        find.byKey(const ValueKey('todo_subtask_drag_a')),
      );
      expect(delete.width, greaterThanOrEqualTo(44));
      expect(drag.width, greaterThanOrEqualTo(44));
      expect(delete.right, lessThanOrEqualTo(drag.left));
      expect(drag.right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('只读编辑器禁用内容、增删和排序', (tester) async {
    final host = GlobalKey<_HostState>();
    await tester.pumpWidget(
      _Host(key: host, initial: _items(), enabled: false),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('todo_subtask_text_a')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<ReorderableDragStartListener>(
            find.byKey(const ValueKey('todo_subtask_drag_a')),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(const ValueKey('todo_subtask_delete_a')),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    // ignore: deprecated_member_use
    list.onReorder!(0, 3);
    expect(host.currentState!.items.map((task) => task.id), ['a', 'b', 'c']);
    expect(tester.takeException(), isNull);
  });
}
