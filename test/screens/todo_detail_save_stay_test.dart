import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/todo_detail_screen.dart';

import '../test_support/recording_reminder_scheduler.dart';

/// TodoDetailScreen 保存返回路由测试。
///
/// Feature: app-alignment-overhaul
/// Property 18 (P18): 保存成功或无改动点击保存时，详情页返回上一页。
///
/// Validates: Requirements 2.3, 2.4, 2.5
///
/// 用例形态：
/// - 在一个 `Navigator` 下从 `/home` push 一个 detail route；
/// - 在详情页中编辑标题并点 AppBar 的保存按钮；
/// - 断言：保存后回到 home，provider 已持久化修改。
/// - 再覆盖几个关键状态转移：脏 → 返回 → 确认弹窗 → 取消/放弃。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// 构造一个带一条 TodoItem 的 TodoProvider。
  Future<(TodoProvider, TodoItem)> buildProviderWithOne() async {
    final provider = TodoProvider();
    final item = TodoItem(title: '原始标题', notes: '原始备注');
    await provider.addTodo(item);
    return (provider, item);
  }

  /// 构造一个包含 Home 入口 + TodoDetail 的 MaterialApp。
  /// Home 上的 Text("home-root") 与 Button 用来断言路由层级。
  Widget buildApp({required TodoProvider provider, required String todoId}) {
    return ChangeNotifierProvider<TodoProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Builder(
          builder: (rootCtx) => Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('home-root'),
                  ElevatedButton(
                    onPressed: () => Navigator.of(rootCtx).push(
                      MaterialPageRoute(
                        settings: const RouteSettings(name: '/todo-detail'),
                        builder: (_) => TodoDetailScreen(todoId: todoId),
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
    );
  }

  group('P18 - save returns to previous route', () {
    testWidgets('编辑标题 → 点 AppBar check：保存并返回 home', (tester) async {
      final (provider, item) = await buildProviderWithOne();

      await tester.pumpWidget(buildApp(provider: provider, todoId: item.id));
      await tester.pumpAndSettle();

      // Home 页应当可见，detail 尚未打开。
      expect(find.text('home-root'), findsOneWidget);
      expect(find.byType(TodoDetailScreen), findsNothing);

      // 打开详情页。
      await tester.tap(find.text('open-detail'));
      await tester.pumpAndSettle();
      expect(find.byType(TodoDetailScreen), findsOneWidget);

      // 编辑标题，让页面进入 editing 状态。
      final titleField = find.widgetWithText(TextField, '任务名称');
      expect(titleField, findsOneWidget);
      await tester.enterText(titleField, '修改后的标题');
      await tester.pump();

      // 点 AppBar 的 check 按钮触发保存。
      final checkBtn = find.widgetWithIcon(IconButton, Icons.check);
      expect(checkBtn, findsOneWidget);
      await tester.tap(checkBtn);
      await tester.pumpAndSettle();

      expect(find.byType(TodoDetailScreen), findsNothing);
      expect(find.text('home-root'), findsOneWidget);

      // Provider 真的被写入了新标题。
      final stored = provider.todos.firstWhere((t) => t.id == item.id);
      expect(stored.title, '修改后的标题');
    });

    testWidgets('编辑保存会等待提醒同步完成后再返回', (tester) async {
      final (provider, item) = await buildProviderWithOne();
      final scheduler = _GatedTodoScheduler();
      provider.scheduler = scheduler;

      await tester.pumpWidget(buildApp(provider: provider, todoId: item.id));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open-detail'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '任务名称'), '等待提醒同步');
      await tester.pump();

      await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(scheduler.started, isTrue);
      expect(find.byType(TodoDetailScreen), findsOneWidget);
      expect(find.text('home-root'), findsNothing);

      scheduler.complete();
      await tester.pumpAndSettle();

      expect(find.byType(TodoDetailScreen), findsNothing);
      expect(find.text('home-root'), findsOneWidget);
      expect(provider.todos.single.title, '等待提醒同步');
    });

    testWidgets('子任务保存等待父完成聚合后的提醒同步再返回', (tester) async {
      final provider = TodoProvider();
      final item = TodoItem(
        title: '等待子任务聚合',
        subtasks: [Subtask(id: 'child', title: '最后一个步骤')],
      );
      await provider.addTodo(item);
      final scheduler = _GatedAggregationScheduler();
      provider.scheduler = scheduler;
      await tester.pumpWidget(buildApp(provider: provider, todoId: item.id));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open-detail'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('todo_subtask_complete_child')),
      );
      await tester.pump();
      expect(provider.todos.single.subtasks.single.isCompleted, isFalse);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(scheduler.todoSyncs, hasLength(1));
      expect(provider.todos.single.isCompleted, isTrue);
      expect(find.byType(TodoDetailScreen), findsOneWidget);
      expect(find.text('home-root'), findsNothing);

      scheduler.complete();
      await tester.pumpAndSettle();
      expect(find.byType(TodoDetailScreen), findsNothing);
      expect(find.text('home-root'), findsOneWidget);
      expect(provider.todos.single.completedAt, isNotNull);
    });

    testWidgets('clean 状态点保存：直接返回 home', (tester) async {
      final (provider, item) = await buildProviderWithOne();

      await tester.pumpWidget(buildApp(provider: provider, todoId: item.id));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open-detail'));
      await tester.pumpAndSettle();

      // 不做任何编辑，直接点 check。
      final checkBtn = find.widgetWithIcon(IconButton, Icons.check);
      expect(checkBtn, findsOneWidget);
      await tester.tap(checkBtn);
      await tester.pumpAndSettle();

      expect(find.byType(TodoDetailScreen), findsNothing);
      expect(find.text('home-root'), findsOneWidget);
    });

    testWidgets('设置重复与到期提醒后保存：provider 持久化新值', (tester) async {
      final (provider, item) = await buildProviderWithOne();

      await tester.pumpWidget(buildApp(provider: provider, todoId: item.id));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open-detail'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('提醒'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('提醒'), findsOneWidget);
      await tester.tap(find.text('提醒'));
      await tester.pumpAndSettle();

      expect(find.textContaining('提醒 ·'), findsOneWidget);
      await tester.tap(find.textContaining('提醒 ·'));
      await tester.pumpAndSettle();

      expect(find.text('提醒类型'), findsOneWidget);
      final sheetSave = find.widgetWithText(FilledButton, '保存').last;
      await tester.ensureVisible(sheetSave);
      await tester.tap(sheetSave);
      await tester.pumpAndSettle();

      final checkBtn = find.widgetWithIcon(IconButton, Icons.check);
      expect(checkBtn, findsOneWidget);
      await tester.tap(checkBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      final stored = provider.todos.firstWhere((t) => t.id == item.id);
      expect(stored.reminder.enabled, isTrue);
      expect(stored.reminder.hour, isNotNull);
      expect(stored.reminder.minute, isNotNull);
      // ignore: deprecated_member_use_from_same_package
      expect(stored.hasReminder, isTrue);
      // ignore: deprecated_member_use_from_same_package
      expect(stored.reminderAt, isNotNull);
    });

    testWidgets('逾期提醒未改动时编辑标题仍可保存返回', (tester) async {
      final provider = TodoProvider();
      final overdue = DateTime.now().subtract(const Duration(days: 1));
      final item = TodoItem(
        title: '逾期提醒标题',
        notes: '原始备注',
        dueDate: overdue,
        reminderPlan: ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'past-reminder',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: overdue.hour,
              minute: overdue.minute,
            ),
          ],
        ),
      );
      await provider.addTodo(item);

      await tester.pumpWidget(buildApp(provider: provider, todoId: item.id));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open-detail'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '任务名称'), '只修改标题');
      await tester.pump();

      await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(TodoDetailScreen), findsNothing);
      expect(find.text('home-root'), findsOneWidget);
      expect(provider.todos.single.title, '只修改标题');
    });
  });

  group('Editing 下返回键弹出确认框', () {
    testWidgets('取消 → 保持 editing，路由不 pop', (tester) async {
      final (provider, item) = await buildProviderWithOne();
      await tester.pumpWidget(buildApp(provider: provider, todoId: item.id));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open-detail'));
      await tester.pumpAndSettle();

      // 制造脏状态。
      await tester.enterText(find.widgetWithText(TextField, '任务名称'), '改名中');
      await tester.pump();

      // 点 AppBar 的返回按钮。
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('放弃未保存的修改？'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      // 仍然停留在详情页。
      expect(find.byType(TodoDetailScreen), findsOneWidget);
      expect(find.text('home-root'), findsNothing);
    });

    testWidgets('放弃 → 路由 pop 回 home，改动未写入', (tester) async {
      final (provider, item) = await buildProviderWithOne();
      await tester.pumpWidget(buildApp(provider: provider, todoId: item.id));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open-detail'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '任务名称'), '即将被放弃');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      await tester.tap(find.text('放弃'));
      await tester.pumpAndSettle();

      // 已经回到 home。
      expect(find.text('home-root'), findsOneWidget);
      expect(find.byType(TodoDetailScreen), findsNothing);

      // Provider 中仍是原始标题。
      final stored = provider.todos.firstWhere((t) => t.id == item.id);
      expect(stored.title, '原始标题');
    });
  });
}

class _GatedTodoScheduler extends RecordingReminderScheduler {
  final Completer<void> _gate = Completer<void>();

  bool get started => todoSyncs.isNotEmpty;

  void complete() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<void> syncTodos(
    Iterable<TodoItem> todos, {
    bool allowJustMissedOneShotReminders = true,
  }) async {
    todoSyncs.add(todos.map((todo) => todo.id).toList(growable: false));
    await _gate.future;
  }
}

class _GatedAggregationScheduler extends RecordingReminderScheduler {
  final Completer<void> _aggregationGate = Completer<void>();

  void complete() => _aggregationGate.complete();

  @override
  Future<void> syncTodos(
    Iterable<TodoItem> todos, {
    bool allowJustMissedOneShotReminders = true,
  }) async {
    todoSyncs.add(todos.map((todo) => todo.id).toList(growable: false));
    await _aggregationGate.future;
  }
}
