import 'dart:convert';

import 'package:duoyi/core/home_widget_todos.dart';
import 'package:duoyi/models/todo.dart';
import 'package:flutter_test/flutter_test.dart';

/// 今日视图里的一条待办：日期落在 [today]，字段可逐个覆盖。
TodoItem _todo(
  String id, {
  EisenhowerQuadrant quadrant = EisenhowerQuadrant.urgentImportant,
  TodoPriority priority = TodoPriority.none,
  int sortOrder = 0,
  DateTime? createdAt,
  bool completed = false,
  bool archived = false,
  DateTime? date,
  DateTime? dueDate,
}) => TodoItem(
  id: id,
  title: '任务 $id',
  quadrant: quadrant,
  priority: priority,
  sortOrder: sortOrder,
  createdAt: createdAt ?? DateTime(2026, 5, 1, 9),
  isCompleted: completed,
  isArchivedAfterRollover: archived,
  date: date ?? DateTime(2026, 5, 6),
  dueDate: dueDate,
);

void main() {
  final now = DateTime(2026, 5, 6, 10);

  test('四象限展示顺序是 Q1→Q3→Q2→Q4（枚举编号 0→2→1→3）', () {
    // 枚举定义顺序是 Q1/Q2/Q3/Q4，但展示顺序必须是 Q1→Q3→Q2→Q4；
    // 序列化仍写原枚举编号，因此 rank 与 index 不是同一个映射。
    expect(
      <int>[
        homeWidgetTodoQuadrantRank(EisenhowerQuadrant.urgentImportant),
        homeWidgetTodoQuadrantRank(EisenhowerQuadrant.urgentNotImportant),
        homeWidgetTodoQuadrantRank(EisenhowerQuadrant.notUrgentImportant),
        homeWidgetTodoQuadrantRank(EisenhowerQuadrant.notUrgentNotImportant),
      ],
      <int>[0, 1, 2, 3],
    );

    final items = buildHomeWidgetTodoItems(<TodoItem>[
      _todo('q4', quadrant: EisenhowerQuadrant.notUrgentNotImportant),
      _todo('q2', quadrant: EisenhowerQuadrant.notUrgentImportant),
      _todo('q3', quadrant: EisenhowerQuadrant.urgentNotImportant),
      _todo('q1', quadrant: EisenhowerQuadrant.urgentImportant),
    ], now: now);

    expect(items.map((todo) => todo.id).toList(), <String>[
      'q1',
      'q3',
      'q2',
      'q4',
    ]);
  });

  test('象限优先于 priority：Q3 的普通项仍排在 Q2 的 urgent 之前', () {
    final items = buildHomeWidgetTodoItems(<TodoItem>[
      _todo(
        'q2-urgent',
        quadrant: EisenhowerQuadrant.notUrgentImportant,
        priority: TodoPriority.urgent,
      ),
      _todo('q3-none', quadrant: EisenhowerQuadrant.urgentNotImportant),
    ], now: now);

    expect(items.map((todo) => todo.id).toList(), <String>[
      'q3-none',
      'q2-urgent',
    ]);
  });

  test('同象限：priority 倒序 → sortOrder 升序 → createdAt → id 稳定', () {
    final items = buildHomeWidgetTodoItems(<TodoItem>[
      _todo('low', priority: TodoPriority.low, sortOrder: 9),
      _todo('urgent', priority: TodoPriority.urgent, sortOrder: 9),
      _todo('order-2', sortOrder: 2),
      _todo('order-1', sortOrder: 1),
      _todo('created-late', sortOrder: 3, createdAt: DateTime(2026, 5, 1, 10)),
      _todo(
        'created-early-a',
        sortOrder: 3,
        createdAt: DateTime(2026, 5, 1, 8),
      ),
      _todo(
        'created-early-b',
        sortOrder: 3,
        createdAt: DateTime(2026, 5, 1, 8),
      ),
    ], now: now);

    expect(items.map((todo) => todo.id).toList(), <String>[
      'urgent',
      'low',
      'order-1',
      'order-2',
      'created-early-a',
      'created-early-b',
      'created-late',
    ]);

    // 稳定排序：同样输入再排一次结果完全一致。
    final again = buildHomeWidgetTodoItems(items.reversed, now: now);
    expect(
      again.map((todo) => todo.id).toList(),
      items.map((todo) => todo.id).toList(),
    );
  });

  test('今日过滤：已完成 / 跨日归档 / 未来进入 / 过期截止都不展示', () {
    final items = buildHomeWidgetTodoItems(<TodoItem>[
      _todo('today'),
      _todo('done', completed: true),
      _todo('archived', archived: true),
      _todo('future', date: DateTime(2026, 5, 7)),
      _todo('due-past', dueDate: DateTime(2026, 5, 5)),
      _todo('due-today', dueDate: DateTime(2026, 5, 6)),
    ], now: now);

    expect(items.map((todo) => todo.id).toList()..sort(), <String>[
      'due-today',
      'today',
    ]);
  });

  test('不截 Top3：全部今日未完成都进入原生数组', () {
    final items = buildHomeWidgetTodoItems(<TodoItem>[
      for (var index = 0; index < 7; index++)
        _todo('t$index', sortOrder: index),
    ], now: now);

    expect(items, hasLength(7));
    final decoded = jsonDecode(encodeHomeWidgetTodoItems(items)) as List;
    expect(decoded, hasLength(7));
  });

  test('encodeHomeWidgetTodoItems 只带渲染字段并保留原枚举编号', () {
    final items = buildHomeWidgetTodoItems(<TodoItem>[
      _todo('q3', quadrant: EisenhowerQuadrant.urgentNotImportant),
      _todo('q1', quadrant: EisenhowerQuadrant.urgentImportant),
      _todo('q4', quadrant: EisenhowerQuadrant.notUrgentNotImportant),
    ], now: now);

    final decoded = (jsonDecode(encodeHomeWidgetTodoItems(items)) as List)
        .cast<Map<String, dynamic>>();

    expect(decoded.map((todo) => todo['id']).toList(), <String>[
      'q1',
      'q3',
      'q4',
    ]);
    // 象限字段是原枚举编号：Q1=0、Q3=2、Q4=3。
    expect(decoded.map((todo) => todo['quadrant']).toList(), <int>[0, 2, 3]);
    expect(decoded.first['title'], '任务 q1');
    expect(decoded.first.keys.toSet(), <String>{'id', 'title', 'quadrant'});
  });
}
