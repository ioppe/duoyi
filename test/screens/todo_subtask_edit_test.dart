import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/todo_detail_screen.dart';
import 'package:duoyi/widgets/todo_subtask_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingTodoProvider extends TodoProvider {
  int updates = 0;
  int recomputes = 0;
  bool failSave = false;
  Completer<void>? saveGate;

  @override
  Future<void> updateTodo(
    String id,
    TodoItem updated, {
    bool waitForReminderSync = true,
  }) async {
    updates++;
    if (failSave) throw StateError('测试保存失败');
    if (saveGate != null) await saveGate!.future;
    await super.updateTodo(
      id,
      updated,
      waitForReminderSync: waitForReminderSync,
    );
  }

  @override
  Future<void> recomputeParent(String todoId) async {
    recomputes++;
    throw StateError('父完成态应与子任务同一次写入，不能进行第二次聚合写入');
  }
}

class _ReadOnlyShareProvider extends ShareProvider {
  @override
  bool canEdit(String? workspaceId) => false;
}

List<Subtask> _children({bool completed = false}) => [
  for (final (index, id) in ['a', 'b', 'c'].indexed)
    Subtask(id: id, title: '子任务 $id', isCompleted: completed, sortOrder: index),
];

TodoSubtaskEditor _editor(WidgetTester tester) =>
    tester.widget<TodoSubtaskEditor>(find.byType(TodoSubtaskEditor));

Finder _child(String id) => find.byKey(ValueKey('todo_subtask_text_$id'));
Finder _saveButton() => find.widgetWithIcon(IconButton, Icons.check);
List<String> _draftIds(WidgetTester tester) =>
    _editor(tester).subtasks.map((child) => child.id).toList();
String _snapshot(TodoProvider provider) =>
    jsonEncode(provider.todos.single.toJson());

Future<_RecordingTodoProvider> _openDetail(
  WidgetTester tester, {
  bool autoToggle = true,
  bool completed = false,
  bool readOnly = false,
}) async {
  tester.view.physicalSize = const Size(720, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final provider = _RecordingTodoProvider();
  await provider.addTodo(
    TodoItem(
      id: 'task',
      title: '父任务',
      notes: '原始描述',
      workspaceId: readOnly ? 'shared-workspace' : 'private',
      isCompleted: completed,
      completedAt: completed ? DateTime(2026, 1, 1) : null,
      autoToggleByChildren: autoToggle,
      subtasks: _children(completed: completed),
    ),
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TodoProvider>.value(value: provider),
        if (readOnly)
          ChangeNotifierProvider<ShareProvider>(
            create: (_) => _ReadOnlyShareProvider(),
          ),
      ],
      child: MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TodoDetailScreen(todoId: 'task'),
                  ),
                ),
                child: const Text('open-detail'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open-detail'));
  await tester.pumpAndSettle();
  return provider;
}

Future<void> _addChild(WidgetTester tester, [String title = '新增子任务']) async {
  final input = find.byKey(const ValueKey('todo_subtask_add_input'));
  await tester.ensureVisible(input);
  await tester.enterText(input, title);
  await tester.pumpAndSettle();
  final addButton = find.descendant(
    of: find.byKey(const ValueKey('todo_subtask_add')),
    matching: find.byType(IconButton),
  );
  await Scrollable.ensureVisible(tester.element(addButton), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(addButton);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(_saveButton());
  await tester.pumpAndSettle();
}

Future<TodoItem> _reloadStoredTodo() async {
  final provider = TodoProvider();
  await provider.loadFromStorage();
  final todo = provider.todos.single;
  provider.dispose();
  return todo;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('编辑增删与其它字段共用草稿，保存后重开及存储重载均保留', (tester) async {
    final provider = await _openDetail(tester);
    final before = _snapshot(provider);
    final initialDraft = _editor(tester).subtasks;
    expect(identical(initialDraft, provider.todos.single.subtasks), isFalse);
    for (var i = 0; i < initialDraft.length; i++) {
      expect(
        identical(initialDraft[i], provider.todos.single.subtasks[i]),
        isFalse,
      );
    }

    await tester.enterText(_child('a'), '  第一行\n第二行  ');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('todo_subtask_delete_b')));
    await tester.pump();
    await _addChild(tester);
    final addedId = _editor(tester).subtasks.last.id;
    expect(_draftIds(tester), ['a', 'c', addedId]);
    expect(_snapshot(provider), before);
    expect(provider.updates, 0);
    expect(provider.recomputes, 0);

    final title = find.widgetWithText(TextField, '任务名称');
    await tester.ensureVisible(title);
    await tester.enterText(title, '修改父任务\n保留第二行');
    await tester.pump();
    final description = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == '支持 Markdown 描述',
    );
    await tester.ensureVisible(description);
    await tester.enterText(description, '修改描述');
    await tester.pump();
    expect(_snapshot(provider), before);
    await _save(tester);

    expect(find.byType(TodoDetailScreen), findsNothing);
    expect(provider.updates, 1);
    expect(provider.recomputes, 0);
    final stored = provider.todos.single;
    expect(stored.title, '修改父任务\n保留第二行');
    expect(stored.notes, '修改描述');
    expect(stored.subtasks.map((child) => child.id), ['a', 'c', addedId]);
    expect(stored.subtasks.map((child) => child.title), [
      '第一行\n第二行',
      '子任务 c',
      '新增子任务',
    ]);
    expect(stored.subtasks.map((child) => child.sortOrder), [0, 1, 2]);
    final reloaded = await _reloadStoredTodo();
    expect(
      reloaded.subtasks.map((child) => child.toJson()),
      stored.subtasks.map((child) => child.toJson()),
    );

    await tester.tap(find.text('open-detail'));
    await tester.pumpAndSettle();
    expect(_draftIds(tester), ['a', 'c', addedId]);
    expect(tester.widget<TextField>(_child('a')).controller!.text, '第一行\n第二行');
    expect(find.byKey(const ValueKey('todo_subtask_text_b')), findsNothing);
  });

  for (final operation in ['edit', 'add', 'delete', 'toggle', 'reorder']) {
    testWidgets('仅子任务 $operation 也提示未保存，取消保留草稿，放弃不污染 provider', (tester) async {
      final provider = await _openDetail(tester);
      final before = _snapshot(provider);
      switch (operation) {
        case 'edit':
          await tester.enterText(_child('a'), '未保存的内容');
        case 'add':
          await _addChild(tester);
        case 'delete':
          await tester.tap(find.byKey(const ValueKey('todo_subtask_delete_a')));
        case 'toggle':
          await tester.tap(
            find.byKey(const ValueKey('todo_subtask_complete_a')),
          );
        case 'reorder':
          final list = tester.widget<ReorderableListView>(
            find.byKey(const ValueKey('todo_subtask_list')),
          );
          // ignore: deprecated_member_use
          list.onReorder!(0, 3);
      }
      await tester.pumpAndSettle();
      final draft = jsonEncode(
        _editor(tester).subtasks.map((child) => child.toJson()).toList(),
      );
      expect(_snapshot(provider), before);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('放弃未保存的修改？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        jsonEncode(
          _editor(tester).subtasks.map((child) => child.toJson()).toList(),
        ),
        draft,
      );
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃'));
      await tester.pumpAndSettle();
      expect(find.byType(TodoDetailScreen), findsNothing);
      expect(_snapshot(provider), before);
      expect(provider.updates, 0);
      expect(provider.recomputes, 0);
      final reloaded = await _reloadStoredTodo();
      expect(jsonEncode(reloaded.toJson()), before);
      await tester.tap(find.text('open-detail'));
      await tester.pumpAndSettle();
      expect(_draftIds(tester), ['a', 'b', 'c']);
      expect(tester.widget<TextField>(_child('a')).controller!.text, '子任务 a');
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey('todo_subtask_complete_a')),
            )
            .value,
        isFalse,
      );
    });
  }

  testWidgets('空白子任务阻止整个草稿保存，修正后可继续保存', (tester) async {
    final provider = await _openDetail(tester);
    final before = _snapshot(provider);
    await tester.enterText(
      find.widgetWithText(TextField, '任务名称'),
      '也不能提前写入的父任务',
    );
    await tester.enterText(_child('a'), ' \n  ');
    await tester.pump();
    await _save(tester);
    expect(find.text(I18n.tr('todo.subtask.empty')), findsOneWidget);
    expect(find.byType(TodoDetailScreen), findsOneWidget);
    expect(_snapshot(provider), before);
    expect(provider.updates, 0);
    await tester.enterText(_child('a'), '有效内容');
    await tester.pump();
    await _save(tester);
    expect(find.byType(TodoDetailScreen), findsNothing);
    expect(provider.todos.single.subtasks.first.title, '有效内容');
    expect(provider.todos.single.title, '也不能提前写入的父任务');
  });

  for (final autoToggle in [true, false]) {
    testWidgets('所有子任务勾选后保存一律聚合父任务 autoToggle=$autoToggle', (tester) async {
      final provider = await _openDetail(tester, autoToggle: autoToggle);
      for (final id in ['a', 'b', 'c']) {
        await tester.tap(find.byKey(ValueKey('todo_subtask_complete_$id')));
        await tester.pump();
      }
      expect(
        _editor(tester).subtasks.every((child) => child.isCompleted),
        isTrue,
      );
      expect(
        provider.todos.single.subtasks.every((child) => !child.isCompleted),
        isTrue,
      );
      expect(provider.todos.single.isCompleted, isFalse);
      await _save(tester);
      expect(provider.recomputes, 0);
      // 有子任务时父完成态只由子任务推导，autoToggleByChildren 不再能绕过。
      expect(provider.todos.single.isCompleted, isTrue);
      expect(provider.todos.single.completedAt, isNotNull);
      final stored = await _reloadStoredTodo();
      expect(stored.isCompleted, isTrue);
      expect(stored.subtasks.every((child) => child.isCompleted), isTrue);
    });
  }

  testWidgets('撤销子任务勾选后保存会重新打开父任务并清空完成时间', (tester) async {
    final provider = await _openDetail(tester, completed: true);
    await tester.tap(find.byKey(const ValueKey('todo_subtask_complete_b')));
    await tester.pump();
    expect(provider.todos.single.isCompleted, isTrue);
    await _save(tester);
    expect(provider.todos.single.isCompleted, isFalse);
    expect(provider.todos.single.completedAt, isNull);
    expect((await _reloadStoredTodo()).isCompleted, isFalse);
  });

  testWidgets('仅修改父任务标题不会额外触发子任务聚合', (tester) async {
    final provider = await _openDetail(tester);
    await tester.enterText(find.widgetWithText(TextField, '任务名称'), '只改标题');
    await tester.pump();
    await _save(tester);
    expect(provider.updates, 1);
    expect(provider.recomputes, 0);
    expect(provider.todos.single.title, '只改标题');
  });

  testWidgets('排序回调立即更新本地草稿，多帧保持新序，保存后顺序持久化', (tester) async {
    final provider = await _openDetail(tester);
    final before = _snapshot(provider);
    final list = tester.widget<ReorderableListView>(
      find.byKey(const ValueKey('todo_subtask_list')),
    );
    expect(list.buildDefaultDragHandles, isFalse);
    final listContext = tester.element(
      find.byKey(const ValueKey('todo_subtask_list')),
    );
    expect(
      List.generate(
        list.itemCount,
        (index) => list.itemBuilder(listContext, index).key,
      ),
      [const ValueKey('a'), const ValueKey('b'), const ValueKey('c')],
    );
    // ignore: deprecated_member_use
    list.onReorder!(0, 3);
    await tester.pump();
    for (var frame = 0; frame < 30; frame++) {
      expect(_draftIds(tester), ['b', 'c', 'a'], reason: '排序回调后第 $frame 帧');
      expect(_editor(tester).subtasks.map((child) => child.sortOrder), [
        0,
        1,
        2,
      ]);
      expect(
        tester.getTopLeft(_child('b')).dy,
        lessThan(tester.getTopLeft(_child('c')).dy),
      );
      expect(
        tester.getTopLeft(_child('c')).dy,
        lessThan(tester.getTopLeft(_child('a')).dy),
      );
      expect(_snapshot(provider), before);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await _save(tester);
    expect(provider.todos.single.subtasks.map((child) => child.id), [
      'b',
      'c',
      'a',
    ]);
    expect((await _reloadStoredTodo()).subtasks.map((child) => child.id), [
      'b',
      'c',
      'a',
    ]);
    await tester.tap(find.text('open-detail'));
    await tester.pumpAndSettle();
    expect(_draftIds(tester), ['b', 'c', 'a']);
  });

  testWidgets('真实把手拖动完成后不会出现新序回跳旧序的一帧', (tester) async {
    final provider = await _openDetail(tester);
    final before = _snapshot(provider);
    final handle = find.byKey(const ValueKey('todo_subtask_drag_a'));
    final start = tester.getCenter(handle);
    final target = Offset(
      start.dx,
      tester.getRect(find.byKey(const ValueKey('todo_subtask_list'))).bottom +
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
      final ids = _draftIds(tester);
      if (ids.first == 'b') sawNewOrder = true;
      if (sawNewOrder) {
        expect(ids, ['b', 'c', 'a'], reason: '把手放下后第 $frame 帧');
      }
      expect(_snapshot(provider), before);
    }
    expect(sawNewOrder, isTrue);
    expect(
      tester.getTopLeft(_child('c')).dy,
      lessThan(tester.getTopLeft(_child('a')).dy),
    );
    expect(provider.updates, 0);
    expect(tester.takeException(), isNull);
    await _save(tester);
    expect((await _reloadStoredTodo()).subtasks.map((child) => child.id), [
      'b',
      'c',
      'a',
    ]);
  });

  testWidgets('共享只读权限禁用标题和所有子任务操作', (tester) async {
    final provider = await _openDetail(tester, readOnly: true);
    final before = _snapshot(provider);
    expect(
      tester.widget<TextField>(find.widgetWithText(TextField, '任务名称')).enabled,
      isFalse,
    );
    expect(_editor(tester).enabled, isFalse);
    expect(tester.widget<TextField>(_child('a')).enabled, isFalse);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('todo_subtask_add_input')),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<Checkbox>(
            find.byKey(const ValueKey('todo_subtask_complete_a')),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<ReorderableDragStartListener>(
            find.byKey(const ValueKey('todo_subtask_drag_a')),
          )
          .enabled,
      isFalse,
    );
    expect(tester.widget<IconButton>(_saveButton()).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('todo_subtask_delete_a')));
    await tester.tap(find.byKey(const ValueKey('todo_subtask_add')));
    _editor(tester).onChanged([Subtask(id: 'forbidden', title: '不允许修改')]);
    await tester.pump();
    expect(_draftIds(tester), ['a', 'b', 'c']);
    expect(_snapshot(provider), before);
    expect(provider.updates, 0);
    expect(provider.recomputes, 0);
  });

  testWidgets('保存失败保留子任务草稿，重试成功后返回', (tester) async {
    final provider = await _openDetail(tester);
    final before = _snapshot(provider);
    provider.failSave = true;
    await tester.enterText(_child('a'), '失败后仍然保留');
    await tester.pump();
    await _save(tester);
    expect(find.byType(TodoDetailScreen), findsOneWidget);
    expect(find.textContaining('保存失败：'), findsOneWidget);
    expect(tester.widget<TextField>(_child('a')).controller!.text, '失败后仍然保留');
    expect(_snapshot(provider), before);
    expect(provider.recomputes, 0);
    provider.failSave = false;
    await _save(tester);
    expect(find.byType(TodoDetailScreen), findsNothing);
    expect(provider.todos.single.subtasks.first.title, '失败后仍然保留');
    expect(provider.recomputes, 0);
  });

  testWidgets('保存进行中禁用标题和子任务编辑，等待完成再返回', (tester) async {
    final provider = await _openDetail(tester);
    provider.saveGate = Completer<void>();
    await tester.enterText(_child('a'), '提交中的草稿');
    await tester.pump();
    await tester.tap(_saveButton());
    await tester.pump();
    expect(find.byType(TodoDetailScreen), findsOneWidget);
    expect(
      tester.widget<TextField>(find.widgetWithText(TextField, '任务名称')).enabled,
      isFalse,
    );
    expect(_editor(tester).enabled, isFalse);
    _editor(tester).onChanged([]);
    await tester.pump();
    expect(_draftIds(tester), ['a', 'b', 'c']);
    provider.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(TodoDetailScreen), findsNothing);
    expect(provider.todos.single.subtasks.first.title, '提交中的草稿');
    expect(provider.recomputes, 0);
  });
}
