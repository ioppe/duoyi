import 'dart:convert';

import '../models/todo.dart';
import 'completion_visibility_policy.dart';

/// 桌面待办按用户指定的四象限显示顺序排列。
///
/// 序列化仍使用原有枚举编号；只改变小组件的展示顺序。
///
/// 枚举编号：Q1 `urgentImportant`=0、Q2 `notUrgentImportant`=1、
/// Q3 `urgentNotImportant`=2、Q4 `notUrgentNotImportant`=3；
/// 用户要求的展示顺序是 Q1 → Q3 → Q2 → Q4，即 0 → 2 → 1 → 3。
int homeWidgetTodoQuadrantRank(EisenhowerQuadrant quadrant) =>
    switch (quadrant) {
      EisenhowerQuadrant.urgentImportant => 0,
      EisenhowerQuadrant.urgentNotImportant => 1,
      EisenhowerQuadrant.notUrgentImportant => 2,
      EisenhowerQuadrant.notUrgentNotImportant => 3,
    };

/// 同一象限保留优先级与手动次序，并以创建时刻/ID 保证稳定排序。
int compareHomeWidgetTodos(TodoItem a, TodoItem b) {
  final quadrant = homeWidgetTodoQuadrantRank(
    a.quadrant,
  ).compareTo(homeWidgetTodoQuadrantRank(b.quadrant));
  if (quadrant != 0) return quadrant;
  final priority = b.priority.rank.compareTo(a.priority.rank);
  if (priority != 0) return priority;
  final order = a.sortOrder.compareTo(b.sortOrder);
  if (order != 0) return order;
  final created = a.createdAt.compareTo(b.createdAt);
  if (created != 0) return created;
  return a.id.compareTo(b.id);
}

/// 全部今日可见未完成事项；不在数据层按小组件密度截取 Top3。
List<TodoItem> buildHomeWidgetTodoItems(
  Iterable<TodoItem> todos, {
  required DateTime now,
}) =>
    todos
        .where(
          (todo) => CompletionVisibilityPolicy.shouldShowInToday(todo, now),
        )
        .toList()
      ..sort(compareHomeWidgetTodos);

/// 原生集合只接收渲染和详情入口必需的字段，不复制整个业务对象。
String encodeHomeWidgetTodoItems(Iterable<TodoItem> items) => jsonEncode([
  for (final todo in items)
    <String, Object>{
      'id': todo.id,
      'title': todo.title,
      'quadrant': todo.quadrant.index,
    },
]);
