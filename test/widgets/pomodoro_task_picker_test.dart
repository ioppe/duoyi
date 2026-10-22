import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/widgets/pomodoro_task_picker.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> open(
  WidgetTester tester, {
  required List<TodoItem> todos,
  required void Function(TodoItem, Subtask?) onSelected,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppBrands.defaultBrand.theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppModalSheet<void>(
              context: context,
              builder: (_) => PomodoroTaskPicker(
                title: '专注任务',
                todos: todos,
                hasSelection: false,
                onSelected: (todo, child) {
                  onSelected(todo, child);
                  Navigator.of(context).pop();
                },
                onPreset: (_) {},
                onManual: () {},
                onClear: () {},
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  testWidgets(
    'existing tasks precede presets; parent and child selections keep their IDs',
    (tester) async {
      TodoItem? selected;
      Subtask? child;
      final todo = TodoItem(
        id: 'a',
        title: '项目计划',
        subtasks: [Subtask(id: 'c', title: '调研需求')],
      );
      await open(
        tester,
        todos: [
          todo,
          TodoItem(title: '已完成', isCompleted: true),
        ],
        onSelected: (t, c) {
          selected = t;
          child = c;
        },
      );
      expect(find.text('已完成'), findsNothing);
      expect(
        tester.getTopLeft(find.text('项目计划')).dy,
        lessThan(tester.getTopLeft(find.text('其他专注内容')).dy),
      );
      await tester.tap(find.byKey(const ValueKey('focus_task_expand_a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('focus_subtask_a_c')));
      await tester.pumpAndSettle();
      expect(selected?.id, 'a');
      expect(child?.id, 'c');
      expect(todo.isCompleted, isFalse);
      expect(todo.subtasks.single.isCompleted, isFalse);
      await open(
        tester,
        todos: [todo],
        onSelected: (t, c) {
          selected = t;
          child = c;
        },
      );
      await tester.tap(find.byKey(const ValueKey('focus_task_a')));
      await tester.pumpAndSettle();
      expect(selected?.id, 'a');
      expect(child, isNull);
    },
  );

  testWidgets('search finds child names and hides completed children', (
    tester,
  ) async {
    await open(
      tester,
      todos: [
        TodoItem(
          id: 'a',
          title: '项目',
          subtasks: [
            Subtask(id: 'c', title: '调研需求'),
            Subtask(title: '完成的子任务', isCompleted: true),
          ],
        ),
      ],
      onSelected: (_, _) {},
    );
    await tester.enterText(
      find.byKey(const ValueKey('focus_task_search')),
      '调研',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('focus_subtask_a_c')), findsOneWidget);
    expect(find.text('完成的子任务'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('focus_task_search')),
      '不存在',
    );
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的任务或子任务'), findsOneWidget);
  });

  testWidgets(
    '320px enlarged text scrolls to a task and outside tap dismisses',
    (tester) async {
      final todos = List.generate(
        15,
        (i) => TodoItem(id: '$i', title: '任务 $i 需要完成的较长内容'),
      );
      await open(
        tester,
        todos: todos,
        size: const Size(320, 720),
        textScale: 1.5,
        onSelected: (_, _) {},
      );
      await tester.enterText(
        find.byKey(const ValueKey('focus_task_search')),
        '任务 14',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('focus_task_14')));
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(10, 20));
      await tester.pumpAndSettle();
      expect(find.byType(PomodoroTaskPicker), findsNothing);
    },
  );
}
