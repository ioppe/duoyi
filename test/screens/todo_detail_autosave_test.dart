import 'dart:async';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/screens/todo_detail_screen.dart';
import 'package:duoyi/widgets/todo_subtask_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 任务详情自动保存回归。
///
/// 覆盖：600ms 防抖、写入在途继续编辑（光标保持）、快速返回先落盘、
/// 空标题 / 空子任务暂缓与显式校验、失败保留草稿 + 重试、账号切换隔离、
/// 生命周期最佳努力落盘，以及 Android / macOS 共用同一条保存路径。
class _AutosaveTodoProvider extends TodoProvider {
  int updates = 0;
  bool failSave = false;
  bool skipSave = false;
  Completer<void>? gate;
  final List<String> writtenTitles = [];

  @override
  Future<void> updateTodo(
    String id,
    TodoItem updated, {
    bool waitForReminderSync = true,
  }) async {
    updates++;
    writtenTitles.add(updated.title);
    if (skipSave) return;
    if (failSave) throw StateError('测试写入失败');
    final pending = gate;
    if (pending != null) await pending.future;
    await super.updateTodo(
      id,
      updated,
      waitForReminderSync: waitForReminderSync,
    );
  }
}

class _SwitchableAuth extends AuthProvider {
  AuthState _current = const AuthState(userId: 'account-a', token: 'fixture');
  final String _server = 'https://server-a.invalid';

  @override
  AuthState get state => _current;

  @override
  String get baseUrl => _server;

  void switchAccount() {
    _current = const AuthState(userId: 'account-b', token: 'fixture-b');
    notifyListeners();
  }
}

class _SwitchableShare extends ShareProvider {
  bool writable = true;

  @override
  bool canEdit(String? workspaceId) => writable;

  void setWritable(bool value) {
    writable = value;
    notifyListeners();
  }
}

Finder _titleField() => find.widgetWithText(TextField, '任务名称');

Finder _notesField() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.hintText == '支持 Markdown 描述',
);

Finder _subtaskText(String id) => find.byKey(ValueKey('todo_subtask_text_$id'));

Finder _subtaskToggle(String id) =>
    find.byKey(ValueKey('todo_subtask_complete_$id'));

TodoSubtaskEditor _editor(WidgetTester tester) =>
    tester.widget<TodoSubtaskEditor>(find.byType(TodoSubtaskEditor));

String _editorSubtasks(WidgetTester tester) =>
    _editor(tester).subtasks.map((child) => child.title).join('|');

Future<_AutosaveTodoProvider> _openDetail(
  WidgetTester tester, {
  _SwitchableAuth? auth,
  _SwitchableShare? share,
  Size size = const Size(720, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final provider = _AutosaveTodoProvider();
  await provider.addTodo(
    TodoItem(
      id: 'task',
      title: '原始标题',
      notes: '原始备注',
      subtasks: [
        Subtask(id: 'sub0', title: '子任务一', sortOrder: 0),
        Subtask(id: 'sub1', title: '子任务二', sortOrder: 1),
      ],
    ),
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TodoProvider>.value(value: provider),
        if (auth != null)
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
        if (share != null)
          ChangeNotifierProvider<ShareProvider>.value(value: share),
      ],
      child: MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('home-root'),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const TodoDetailScreen(todoId: 'task'),
                      ),
                    ),
                    child: const Text('open-detail'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open-detail'));
  await tester.pumpAndSettle();
  return provider;
}

/// 滚动到可输入位置后输入；不额外推进时间，避免提前触发防抖。
Future<void> _typeInto(WidgetTester tester, Finder field, String text) async {
  await tester.ensureVisible(field);
  await tester.pump();
  await tester.enterText(field, text);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('勾选子任务：600ms 后写入并留在详情页，不弹提示', (tester) async {
    final provider = await _openDetail(tester);
    expect(provider.updates, 0);

    await tester.tap(_subtaskToggle('sub0'));
    await tester.pump();
    expect(_editor(tester).subtasks.first.isCompleted, isTrue);
    expect(
      provider.todos.single.subtasks.first.isCompleted,
      isFalse,
      reason: '防抖窗口内不得写入',
    );

    await tester.pump(const Duration(milliseconds: 300));
    expect(provider.updates, 0, reason: '600ms 窗口未到不写');

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(provider.updates, 1);
    expect(provider.todos.single.subtasks.first.isCompleted, isTrue);
    expect(provider.todos.single.isCompleted, isFalse);
    expect(
      provider.todos.single.subtasks.last.isCompleted,
      isFalse,
      reason: '只写入被勾选的那一条',
    );
    expect(find.byType(TodoDetailScreen), findsOneWidget, reason: '自动保存不退出详情');
    expect(find.byType(SnackBar), findsNothing, reason: '自动保存不弹成功提示');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('todos'), contains('"isCompleted":true'));
  });

  testWidgets('标题 / 备注 / 子任务同时修改：自动保存后控件与 provider 一致', (tester) async {
    final provider = await _openDetail(tester);

    await _typeInto(tester, _titleField(), '新标题');
    final titleController = tester.widget<TextField>(_titleField()).controller!;
    await _typeInto(tester, _notesField(), '新描述');
    await _typeInto(tester, _subtaskText('sub0'), '改过的子任务');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final stored = provider.todos.single;
    expect(stored.title, '新标题');
    expect(stored.notes, '新描述');
    expect(stored.subtasks.first.title, '改过的子任务');
    expect(provider.updates, 1, reason: '连续输入只写一次');

    expect(titleController.text, '新标题');
    expect(_editorSubtasks(tester), '改过的子任务|子任务二');
    expect(find.byType(TodoDetailScreen), findsOneWidget);
  });

  testWidgets('防抖窗口内立即返回：先保存再回列表，无放弃确认框', (tester) async {
    final provider = await _openDetail(tester);

    await _typeInto(tester, _titleField(), '返回前最后一改');
    expect(provider.todos.single.title, '原始标题', reason: '仍处于 600ms 防抖窗口内');

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('放弃未保存的修改？'), findsNothing);
    expect(find.text('放弃'), findsNothing);
    expect(find.byType(TodoDetailScreen), findsNothing);
    expect(find.text('home-root'), findsOneWidget);
    expect(provider.todos.single.title, '返回前最后一改');
  });

  testWidgets('写入在途继续编辑：最后值写入且光标不被回执重置', (tester) async {
    final provider = await _openDetail(tester);
    provider.gate = Completer<void>();

    await _typeInto(tester, _titleField(), '第一版');
    await tester.pump(const Duration(milliseconds: 700));
    expect(provider.updates, 1, reason: '第一次自动保存已发起并卡在 gate 上');
    expect(provider.todos.single.title, '原始标题');

    final titleController = tester.widget<TextField>(_titleField()).controller!;
    await _typeInto(tester, _titleField(), '第二版草稿');
    titleController.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();

    provider.gate!.complete();
    provider.gate = null;
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(provider.todos.single.title, '第二版草稿');
    expect(provider.updates, greaterThanOrEqualTo(2), reason: '在途后的新修改必须补写');
    expect(titleController.text, '第二版草稿');
    expect(titleController.selection.baseOffset, 2, reason: '保存回执不得回灌控制器打断输入');
    expect(find.byType(TodoDetailScreen), findsOneWidget);
  });

  testWidgets('旧写入在途时改回原值：返回立即补写当前草稿', (tester) async {
    final provider = await _openDetail(tester);
    provider.gate = Completer<void>();
    await _typeInto(tester, _titleField(), '写入中的标题');
    await tester.pump(const Duration(milliseconds: 700));
    expect(provider.updates, 1);

    await _typeInto(tester, _titleField(), '原始标题');
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    provider.gate!.complete();
    provider.gate = null;
    await tester.pumpAndSettle();

    expect(provider.todos.single.title, '原始标题');
    expect(provider.writtenTitles, ['写入中的标题', '原始标题']);
    expect(find.byType(TodoDetailScreen), findsNothing);
    expect(find.text('home-root'), findsOneWidget);
  });

  testWidgets('等待写入时重复返回只退出详情一次', (tester) async {
    final provider = await _openDetail(tester);
    provider.gate = Completer<void>();
    await _typeInto(tester, _titleField(), '返回前的标题');
    await tester.pump(const Duration(milliseconds: 700));

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    provider.gate!.complete();
    provider.gate = null;
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TodoDetailScreen), findsNothing);
    expect(find.text('home-root'), findsOneWidget);
    expect(provider.todos.single.title, '返回前的标题');
  });

  testWidgets('空标题 / 空子任务只暂缓保存，修正后自动恢复', (tester) async {
    final provider = await _openDetail(tester);

    await _typeInto(tester, _titleField(), '   ');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(provider.updates, 0, reason: '空标题不写入');
    expect(find.text('任务名称不能为空'), findsNothing, reason: '输入过程中静默');

    await _typeInto(tester, _titleField(), '有效标题');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(provider.todos.single.title, '有效标题');

    await _typeInto(tester, _subtaskText('sub0'), '   ');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(
      provider.todos.single.subtasks.first.title,
      '子任务一',
      reason: '空子任务只暂缓，不写整份草稿',
    );

    // 显式返回：提示填写或删除，并留在页面。
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text(I18n.tr('todo.subtask.empty')), findsOneWidget);
    expect(find.text('放弃未保存的修改？'), findsNothing);
    expect(find.byType(TodoDetailScreen), findsOneWidget);

    await _typeInto(tester, _subtaskText('sub0'), '有效子任务');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(provider.todos.single.subtasks.first.title, '有效子任务');

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(TodoDetailScreen), findsNothing);
    expect(find.text('home-root'), findsOneWidget);
  });

  testWidgets('写入失败保留草稿，重试后落盘', (tester) async {
    final provider = await _openDetail(tester);
    provider.failSave = true;

    await _typeInto(tester, _titleField(), '失败后保留');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text(I18n.tr('todo.autosave.failed')), findsOneWidget);
    expect(find.text(I18n.tr('todo.autosave.retry')), findsOneWidget);
    expect(tester.widget<TextField>(_titleField()).controller!.text, '失败后保留');
    expect(provider.todos.single.title, '原始标题');
    expect(find.text('放弃未保存的修改？'), findsNothing);
    expect(find.byType(TodoDetailScreen), findsOneWidget);

    provider.failSave = false;
    await tester.tap(find.text(I18n.tr('todo.autosave.retry')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(provider.todos.single.title, '失败后保留');
    expect(find.byType(TodoDetailScreen), findsOneWidget);
  });

  testWidgets('保存失败仍可返回，重开恢复草稿并继续自动保存', (tester) async {
    final provider = await _openDetail(tester);
    provider.failSave = true;
    await _typeInto(tester, _titleField(), '重开后恢复的修改');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(TodoDetailScreen), findsNothing);
    expect(find.text('home-root'), findsOneWidget);
    expect(provider.todos.single.title, '原始标题');

    provider.failSave = false;
    await tester.tap(find.text('open-detail'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_titleField()).controller!.text,
      '重开后恢复的修改',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(provider.todos.single.title, '重开后恢复的修改');
  });

  testWidgets('编辑权限被收回后可以返回，权限恢复后重开仍有草稿', (tester) async {
    final share = _SwitchableShare();
    final provider = await _openDetail(tester, share: share);
    await _typeInto(tester, _titleField(), '权限变化前的修改');
    share.setWritable(false);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('home-root'), findsOneWidget);
    expect(find.byType(TodoDetailScreen), findsNothing);
    expect(provider.updates, 0);

    share.setWritable(true);
    await tester.tap(find.text('open-detail'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_titleField()).controller!.text,
      '权限变化前的修改',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(provider.todos.single.title, '权限变化前的修改');
  });

  testWidgets('Provider 忽略更新时不能标记保存成功，重试后才离开', (tester) async {
    final provider = await _openDetail(tester);
    provider.skipSave = true;
    await _typeInto(tester, _titleField(), '被忽略的修改');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(provider.todos.single.title, '原始标题');
    expect(find.text(I18n.tr('todo.autosave.failed')), findsOneWidget);
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();
    expect(find.byType(TodoDetailScreen), findsOneWidget);

    provider.skipSave = false;
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();
    expect(provider.todos.single.title, '被忽略的修改');
    expect(find.byType(TodoDetailScreen), findsNothing);
  });

  testWidgets('账号切换后取消排队写入，旧页面不写给新账号', (tester) async {
    final auth = _SwitchableAuth();
    final provider = await _openDetail(tester, auth: auth);

    await _typeInto(tester, _titleField(), '旧账号的修改');
    expect(provider.updates, 0);

    auth.switchAccount();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(provider.updates, 0, reason: '账号切换后不得继续写入');

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsNothing);
    expect(find.byType(TodoDetailScreen), findsNothing);
    expect(provider.todos.single.title, '原始标题');
  });

  testWidgets('切到 inactive 时最佳努力落盘，回来后不丢修改', (tester) async {
    final provider = await _openDetail(tester);
    await _typeInto(tester, _titleField(), '后台前的修改');
    expect(provider.updates, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(provider.todos.single.title, '后台前的修改');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(TodoDetailScreen), findsOneWidget);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    testWidgets('$platform 平台共用同一条自动保存路径', (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = platform;
      try {
        final provider = await _openDetail(tester);
        await _typeInto(tester, _titleField(), '$platform 修改');
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pumpAndSettle();

        expect(provider.todos.single.title, '$platform 修改');
        expect(find.byType(TodoDetailScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    });
  }
}
