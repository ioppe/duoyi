import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/todo_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('历史清单字面名称 null 与未分类可区分、保存并清空', (tester) async {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
    final todos = TodoProvider();
    await todos.addTodo(TodoItem(id: 'target', title: '分类空值兼容'));
    await todos.addTodo(
      TodoItem(id: 'history', title: '历史任务', listGroupName: 'null'),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<TodoProvider>.value(
        value: todos,
        child: MaterialApp(
          theme: AppBrands.defaultBrand.theme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TodoDetailScreen(todoId: 'target'),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> openAndExpand() async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final selector = find.byKey(const ValueKey('todo_list_group_selector'));
      final scrollable = find
          .descendant(
            of: find.byKey(const ValueKey('todo-detail-form')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(selector, 180, scrollable: scrollable);
      await tester.tap(selector);
      await tester.pumpAndSettle();
    }

    TodoItem stored() => todos.todos.singleWhere((item) => item.id == 'target');
    final summary = find.byKey(const ValueKey('todo_list_group_selected_name'));
    Future<void> revealSummary() async {
      final scrollable = find
          .descendant(
            of: find.byKey(const ValueKey('todo-detail-form')),
            matching: find.byType(Scrollable),
          )
          .first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pump();
      await tester.scrollUntilVisible(summary, 180, scrollable: scrollable);
    }

    await openAndExpand();
    final search = find.byKey(const ValueKey('todo_list_group_search'));
    await tester.ensureVisible(search);
    await tester.enterText(search, 'null');
    await tester.pumpAndSettle();
    final literal = find.byKey(const ValueKey('todo_list_group_null'));
    await tester.ensureVisible(literal);
    await tester.tap(literal);
    await tester.pumpAndSettle();
    await revealSummary();
    expect(tester.widget<Text>(summary).data, 'null');
    expect(stored().listGroupName, isNull, reason: '选择只修改详情草稿');
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();
    expect(stored().listGroupName, 'null');
    expect(stored().listGroupId, isNull);

    await openAndExpand();
    final ungrouped = find.byKey(const ValueKey('todo_list_group_'));
    await tester.ensureVisible(ungrouped);
    await tester.tap(ungrouped);
    await tester.pumpAndSettle();
    await revealSummary();
    expect(tester.widget<Text>(summary).data, I18n.tr('list_group.ungrouped'));
    expect(stored().listGroupName, 'null');
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();
    expect(stored().listGroupName, isNull);
    expect(stored().listGroupId, isNull);
    expect(tester.takeException(), isNull);
  });
}
