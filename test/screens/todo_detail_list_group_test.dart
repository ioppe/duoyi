import 'dart:convert';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/todo_templates.dart';
import 'package:duoyi/models/list_group.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/list_group_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/todo_detail_screen.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:duoyi/widgets/todo_list_group_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 任务详情页的“清单类型 + 四象限优先级”编辑流程。
///
/// 验收点：
/// - 旧的无/低/中/高/紧急 ChoiceChip 优先级行已移除，只保留一个以
///   `I18n.tr('todo.create.quadrant')`（优先级）为标签的四象限下拉；
/// - 清单选择器与新建表单共用 [TodoListGroupPicker]，保存前不改任务，
///   只写自定义清单注册表；
/// - 选择内置/自定义/历史清单只改 `listGroupName`/`listGroupId`，
///   不动 `workspaceId`/`assigneeId`，也不迁移旧的 `TodoPriority` 数据；
/// - 账号/服务器切换后禁止选择与保存。

class _ReadOnlyShare extends ShareProvider {
  @override
  bool canEdit(String? workspaceId) => false;
}

class _SwitchableAuth extends AuthProvider {
  AuthState _current = const AuthState(userId: 'account-a', token: 'fixture');
  String _server = 'https://server-a.invalid';

  @override
  AuthState get state => _current;

  @override
  String get baseUrl => _server;

  void switchIdentity({required bool changeServer}) {
    if (changeServer) {
      _server = 'https://server-b.invalid';
    } else {
      _current = const AuthState(userId: 'account-b', token: 'fixture-b');
    }
    notifyListeners();
  }
}

class _DetailHome extends StatelessWidget {
  final String todoId;

  const _DetailHome({required this.todoId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('home-root'),
            ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TodoDetailScreen(todoId: todoId),
                ),
              ),
              child: const Text('open-detail'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 只挂载传入的 provider：不传清单/共享/账号 provider 时，详情页必须
/// 仍能工作（旧测试形态只有 [TodoProvider]）。
Future<void> _pumpDetail(
  WidgetTester tester, {
  required TodoProvider todos,
  required String todoId,
  ListGroupProvider? listGroups,
  ShareProvider? shares,
  AuthProvider? auth,
  Size size = const Size(420, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TodoProvider>.value(value: todos),
        if (listGroups != null)
          ChangeNotifierProvider<ListGroupProvider>.value(value: listGroups),
        if (shares != null)
          ChangeNotifierProvider<ShareProvider>.value(value: shares),
        if (auth != null)
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        home: _DetailHome(todoId: todoId),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _openDetail(tester);
}

Future<void> _openDetail(WidgetTester tester) async {
  await tester.tap(find.text('open-detail'));
  await tester.pumpAndSettle();
  expect(find.byType(TodoDetailScreen), findsOneWidget);
}

Finder _form() => find.byKey(const ValueKey('todo-detail-form'));

/// 先滚动外层表单（key=todo-detail-form），避免懒加载的行尚未构建。
Future<void> _revealInForm(WidgetTester tester, Finder target) async {
  final form = _form();
  expect(form, findsOneWidget);
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

TodoListGroupPicker _picker(WidgetTester tester) =>
    tester.widget<TodoListGroupPicker>(
      find.byKey(const ValueKey('todo_detail_list_group_picker')),
    );

String _selectedListGroup(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('todo_list_group_selected_name')))
    .data!;

IconButton _saveButton(WidgetTester tester) =>
    tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.check));

Future<void> _tapSave(WidgetTester tester) async {
  await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
  await tester.pumpAndSettle();
  expect(find.byType(TodoDetailScreen), findsNothing);
}

/// 展开选择器：折叠时只有 selector，展开后才有搜索框与选项列表。
Future<void> _expandListGroup(WidgetTester tester) async {
  final selector = find.byKey(const ValueKey('todo_list_group_selector'));
  await _revealInForm(tester, selector);
  if (find.byKey(const ValueKey('todo_list_group_search')).evaluate().isEmpty) {
    await tester.tap(selector);
    await tester.pumpAndSettle();
  }
  final search = find.byKey(const ValueKey('todo_list_group_search'));
  expect(search, findsOneWidget);
  await tester.ensureVisible(search);
  await tester.pumpAndSettle();
}

/// 选项在展开面板内部的滚动区（key=todo_list_group_options）里。
Future<void> _revealOption(WidgetTester tester, Finder target) async {
  final options = find.byKey(const ValueKey('todo_list_group_options'));
  for (var i = 0; i < 16; i++) {
    if (target.hitTestable().evaluate().isNotEmpty) return;
    if (options.evaluate().isEmpty) break;
    await tester.drag(options, const Offset(0, -100));
    await tester.pump();
  }
  expect(target.hitTestable(), findsOneWidget);
}

Future<void> _selectListGroup(WidgetTester tester, String name) async {
  await _expandListGroup(tester);
  final option = find.byKey(ValueKey('todo_list_group_$name'));
  await _revealOption(tester, option);
  await tester.tap(option);
  await tester.pumpAndSettle();
  expect(
    _selectedListGroup(tester),
    name.isEmpty ? I18n.tr('list_group.ungrouped') : name,
  );
}

Future<void> _selectQuadrant(
  WidgetTester tester,
  EisenhowerQuadrant quadrant,
) async {
  final anchor = find.byKey(const ValueKey('todo_detail_quadrant'));
  await _revealInForm(tester, anchor);
  await tester.tap(anchor);
  for (
    var i = 0;
    i < 24 && find.byType(PopupMenuItem<EisenhowerQuadrant>).evaluate().isEmpty;
    i++
  ) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
  final items = find.byType(PopupMenuItem<EisenhowerQuadrant>);
  expect(items, findsNWidgets(4));
  await tester.tap(items.at(quadrant.index));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  testWidgets('移除旧优先级 ChoiceChip 行，改象限与清单后保存仍保留 legacy priority', (
    tester,
  ) async {
    final todos = TodoProvider();
    final groups = ListGroupProvider();
    final group = await groups.create('项目冲刺', groups.nextSortOrder);
    final item = TodoItem(
      id: 'task-priority',
      title: '季度复盘',
      notes: '保留备注',
      priority: TodoPriority.high,
      quadrant: EisenhowerQuadrant.urgentImportant,
      tags: ['复盘'],
      dueDate: DateTime(2026, 5, 20),
    );
    await todos.addTodo(item);

    await _pumpDetail(
      tester,
      todos: todos,
      listGroups: groups,
      todoId: item.id,
    );

    for (final priority in TodoPriority.values) {
      expect(
        find.widgetWithText(ChoiceChip, priority.label),
        findsNothing,
        reason: '旧优先级行应移除：${priority.name}',
      );
    }
    final quadrantFields = find.byWidgetPredicate(
      (widget) => widget is AppDropdownField<EisenhowerQuadrant>,
    );
    expect(quadrantFields, findsOneWidget);
    final quadrantField = tester.widget<AppDropdownField<EisenhowerQuadrant>>(
      quadrantFields,
    );
    expect(quadrantField.enabled, isTrue);
    expect(quadrantField.labelText, I18n.tr('todo.create.quadrant'));
    expect(find.text(I18n.tr('todo.create.quadrant')), findsOneWidget);

    await _selectQuadrant(tester, EisenhowerQuadrant.urgentNotImportant);
    await _selectListGroup(tester, '项目冲刺');
    await _tapSave(tester);

    final stored = todos.todos.firstWhere((todo) => todo.id == item.id);
    expect(stored.priority, TodoPriority.high);
    expect(stored.quadrant, EisenhowerQuadrant.urgentNotImportant);
    expect(stored.listGroupName, '项目冲刺');
    expect(stored.listGroupId, group.id);
    expect(stored.notes, '保留备注');
    expect(stored.tags, ['复盘']);
    expect(stored.dueDate, DateTime(2026, 5, 20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('只有 TodoProvider 的旧用法仍可选内置清单：脏状态拦截返回，保存只写名称', (tester) async {
    final todos = TodoProvider();
    final item = TodoItem(
      id: 'task-builtin',
      title: '内置清单',
      priority: TodoPriority.low,
    );
    await todos.addTodo(item);

    // 不注入 ListGroupProvider / ShareProvider / AuthProvider。
    await _pumpDetail(tester, todos: todos, todoId: item.id);

    expect(
      find.byKey(const ValueKey('todo_detail_list_group_picker')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('todo_detail_quadrant')), findsOneWidget);
    expect(_picker(tester).provider, isNull);
    expect(_picker(tester).canCreate, isFalse);
    for (final priority in TodoPriority.values) {
      expect(find.widgetWithText(ChoiceChip, priority.label), findsNothing);
    }

    await _selectListGroup(tester, '学习');
    expect(todos.todos.single.listGroupName, isNull, reason: '保存前不得写 provider');

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(TodoDetailScreen), findsOneWidget);

    await _tapSave(tester);
    final stored = todos.todos.single;
    expect(stored.listGroupName, '学习');
    expect(stored.listGroupId, isNull, reason: '内置清单没有自定义 ID');
    expect(stored.priority, TodoPriority.low);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选择已持久化的空自定义清单：保存、重开与存储重载后名称和 ID 一致', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ListGroupProvider.storageKey: jsonEncode([
        ListGroup(id: 'g-exam', name: '备考', sortOrder: 0).toJson(),
      ]),
    });
    final todos = TodoProvider();
    final item = TodoItem(id: 'task-empty-group', title: '刷题计划');
    await todos.addTodo(item);
    // 不在 pump 前 load：由详情页 init 水合自定义清单。
    final groups = ListGroupProvider();

    await _pumpDetail(
      tester,
      todos: todos,
      listGroups: groups,
      todoId: item.id,
    );
    expect(groups.groups.map((group) => group.id), contains('g-exam'));

    await _selectListGroup(tester, '备考');
    expect(_picker(tester).value, '备考');
    await _tapSave(tester);

    final stored = todos.todos.firstWhere((todo) => todo.id == item.id);
    expect(stored.listGroupName, '备考');
    expect(stored.listGroupId, 'g-exam');

    await _openDetail(tester);
    expect(_selectedListGroup(tester), '备考');
    expect(_picker(tester).value, '备考');

    final reloadedTodos = TodoProvider();
    await reloadedTodos.loadFromStorage();
    final reloadedTodo = reloadedTodos.todos.firstWhere(
      (todo) => todo.id == item.id,
    );
    expect(reloadedTodo.listGroupName, '备考');
    expect(reloadedTodo.listGroupId, 'g-exam');

    final reloadedGroups = ListGroupProvider();
    await reloadedGroups.loadFromStorage();
    expect(reloadedGroups.groups.single.id, 'g-exam');
    expect(reloadedGroups.groups.single.name, '备考');
    expect(tester.takeException(), isNull);
  });

  testWidgets('清空自定义清单选择后保存：名称与 ID 都回到 null', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ListGroupProvider.storageKey: jsonEncode([
        ListGroup(id: 'g-exam', name: '备考', sortOrder: 0).toJson(),
      ]),
    });
    final todos = TodoProvider();
    final item = TodoItem(
      id: 'task-clear-group',
      title: '清空清单',
      listGroupName: '备考',
      listGroupId: 'g-exam',
    );
    await todos.addTodo(item);
    final groups = ListGroupProvider();

    await _pumpDetail(
      tester,
      todos: todos,
      listGroups: groups,
      todoId: item.id,
    );
    expect(_selectedListGroup(tester), '备考');

    await _selectListGroup(tester, '');
    expect(_selectedListGroup(tester), I18n.tr('list_group.ungrouped'));
    await _tapSave(tester);

    final stored = todos.todos.firstWhere((todo) => todo.id == item.id);
    expect(stored.listGroupName, isNull);
    expect(stored.listGroupId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('放弃清单修改：取消留在页面，放弃返回且 provider 不变', (tester) async {
    final todos = TodoProvider();
    final item = TodoItem(id: 'task-discard', title: '放弃清单修改');
    await todos.addTodo(item);

    await _pumpDetail(
      tester,
      todos: todos,
      listGroups: ListGroupProvider(),
      todoId: item.id,
    );
    await _selectListGroup(tester, '学习');
    expect(todos.todos.single.listGroupName, isNull);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(TodoDetailScreen), findsOneWidget);
    expect(todos.todos.single.listGroupName, isNull);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃'));
    await tester.pumpAndSettle();
    expect(find.byType(TodoDetailScreen), findsNothing);
    final stored = todos.todos.single;
    expect(stored.listGroupName, isNull);
    expect(stored.listGroupId, isNull);
    expect(find.text('open-detail'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选择器内联新建：注册表立即持久化，任务只在下一次保存时写入 ID', (tester) async {
    final todos = TodoProvider();
    final item = TodoItem(id: 'task-inline-create', title: '内联新建清单');
    await todos.addTodo(item);
    final groups = ListGroupProvider();

    await _pumpDetail(
      tester,
      todos: todos,
      listGroups: groups,
      todoId: item.id,
    );

    await _expandListGroup(tester);
    final search = find.byKey(const ValueKey('todo_list_group_search'));
    await tester.enterText(search, '专项复习');
    await tester.pumpAndSettle();
    expect(groups.groups, isEmpty, reason: '输入过程中不得自动创建');

    final action = find.byKey(const ValueKey('todo_list_group_create'));
    await _revealOption(tester, action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    final created = groups.groups.single;
    expect(created.name, '专项复习');
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(ListGroupProvider.storageKey),
      contains('专项复习'),
      reason: '清单注册表在创建时立即落盘',
    );
    expect(todos.todos.single.listGroupName, isNull, reason: '任务只在下一次保存时写入');
    expect(todos.todos.single.listGroupId, isNull);
    expect(_selectedListGroup(tester), '专项复习');
    expect(find.byType(TodoDetailScreen), findsOneWidget);

    await _tapSave(tester);
    final stored = todos.todos.single;
    expect(stored.listGroupName, '专项复习');
    expect(stored.listGroupId, created.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('只读共享任务：清单与象限控件禁用、无法展开、保存按钮不可用', (tester) async {
    final todos = TodoProvider();
    final item = TodoItem(
      id: 'task-readonly',
      title: '只读任务',
      workspaceId: 'ws-shared',
    );
    await todos.addTodo(item);

    await _pumpDetail(
      tester,
      todos: todos,
      listGroups: ListGroupProvider(),
      shares: _ReadOnlyShare(),
      todoId: item.id,
    );

    final picker = _picker(tester);
    expect(picker.enabled, isFalse);
    expect(picker.canCreate, isFalse);
    final quadrant = tester.widget<AppDropdownField<EisenhowerQuadrant>>(
      find.byKey(const ValueKey('todo_detail_quadrant')),
    );
    expect(quadrant.enabled, isFalse);
    expect(_saveButton(tester).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('todo_list_group_selector')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('todo_list_group_search')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('todo_detail_quadrant')));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<EisenhowerQuadrant>), findsNothing);

    await tester.tap(find.byTooltip('保存'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(TodoDetailScreen), findsOneWidget);
    final stored = todos.todos.single;
    expect(stored.listGroupName, isNull);
    expect(stored.listGroupId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('共享任务只列出同空间的清单与历史名称，选内置清单不改空间和负责人', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ListGroupProvider.storageKey: jsonEncode([
        ListGroup(id: 'g-private', name: '私密清单', sortOrder: 0).toJson(),
        ListGroup(
          id: 'g-shared',
          name: '共享清单',
          sortOrder: 1,
          workspaceId: 'ws-shared',
        ).toJson(),
        ListGroup(
          id: 'g-other',
          name: '外部清单',
          sortOrder: 2,
          workspaceId: 'ws-other',
        ).toJson(),
      ]),
    });
    final todos = TodoProvider();
    final item = TodoItem(
      id: 'task-shared',
      title: '共享任务',
      workspaceId: 'ws-shared',
      assigneeId: 'member-7',
    );
    await todos.addTodo(item);
    await todos.addTodo(
      TodoItem(
        id: 'task-shared-history',
        title: '同空间历史',
        workspaceId: 'ws-shared',
        listGroupName: '共享历史',
      ),
    );
    await todos.addTodo(
      TodoItem(
        id: 'task-private-history',
        title: '私有历史',
        listGroupName: '私密历史',
      ),
    );
    await todos.addTodo(
      TodoItem(
        id: 'task-other-history',
        title: '外部历史',
        workspaceId: 'ws-other',
        listGroupName: '外部历史',
      ),
    );
    final groups = ListGroupProvider();
    await groups.loadFromStorage();

    await _pumpDetail(
      tester,
      todos: todos,
      listGroups: groups,
      shares: ShareProvider(),
      todoId: item.id,
    );

    final picker = _picker(tester);
    expect(picker.enabled, isTrue);
    expect(picker.canCreate, isFalse, reason: '新建清单固定落在私有空间，共享任务不可用');
    expect(picker.names, containsAll(TodoListTemplates.all.map((t) => t.name)));
    expect(picker.names, contains('共享清单'));
    expect(picker.names, contains('共享历史'));
    expect(picker.names, isNot(contains('私密清单')));
    expect(picker.names, isNot(contains('外部清单')));
    expect(picker.names, isNot(contains('私密历史')));
    expect(picker.names, isNot(contains('外部历史')));

    await _expandListGroup(tester);
    expect(find.byKey(const ValueKey('todo_list_group_共享清单')), findsOneWidget);
    final search = find.byKey(const ValueKey('todo_list_group_search'));
    await tester.enterText(search, '新共享清单');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('todo_list_group_create')), findsNothing);
    await tester.enterText(search, '');
    await tester.pumpAndSettle();

    await _selectListGroup(tester, '工作');
    await _tapSave(tester);

    final stored = todos.todos.firstWhere((todo) => todo.id == item.id);
    expect(stored.listGroupName, '工作');
    expect(stored.listGroupId, isNull);
    expect(stored.workspaceId, 'ws-shared');
    expect(stored.assigneeId, 'member-7');
    expect(tester.takeException(), isNull);
  });

  testWidgets('账号切换后关闭清单查询并阻止保存', (tester) async {
    final todos = TodoProvider();
    final item = TodoItem(id: 'task-switch', title: '切换账号');
    await todos.addTodo(item);
    final auth = _SwitchableAuth();

    await _pumpDetail(
      tester,
      todos: todos,
      listGroups: ListGroupProvider(),
      auth: auth,
      todoId: item.id,
    );
    expect(_picker(tester).enabled, isTrue);

    await _expandListGroup(tester);
    final search = find.byKey(const ValueKey('todo_list_group_search'));
    await tester.enterText(search, '旧账号清单');
    await tester.pumpAndSettle();
    expect(search, findsOneWidget);

    auth.switchIdentity(changeServer: false);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo_list_group_search')), findsNothing);
    expect(_picker(tester).enabled, isFalse);
    expect(_saveButton(tester).onPressed, isNull);

    await tester.tap(find.byTooltip('保存'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(TodoDetailScreen), findsOneWidget);
    final stored = todos.todos.single;
    expect(stored.listGroupName, isNull);
    expect(stored.listGroupId, isNull);
    expect(tester.takeException(), isNull);
  });
}
