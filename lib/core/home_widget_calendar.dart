import 'dart:convert';

import '../models/todo.dart';
import 'i18n.dart';
import 'todo_filters.dart';

/// 桌面小组件月历的数据口径。
///
/// 与 App 内月历一致：完成的事项仍占它那一天，跨日归档
/// （[TodoItem.isArchivedAfterRollover]）的事项不再显示。
/// 每个 [TodoItem] 只计 1 次，不沿 `date..dueDate` 展开；内嵌 [Subtask] 不是
/// 独立待办，因此不会额外计数。
///
/// 日期归属：有截止日期用 `dueDate`，否则用“创建/设定当天”（`createdAt`）。
/// 两者都先经 [todoDateInAppZone] 归入应用时区：纯日期浮动不偏移，UTC 时刻按
/// 应用时区换算，无偏移墙钟（`createdAt` 的序列化形态）保持原分量，避免二次
/// 跨日。

/// `YYYY-MM-DD` 键。入参必须已是应用墙钟/浮动日期，这里不再做时区换算。
String homeWidgetCalendarDayKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

/// 每个日期的事项数，键按 `YYYY-MM-DD` 升序，JSON 输出稳定可去重。
Map<String, int> buildHomeWidgetCalendarDayCounts(Iterable<TodoItem> todos) {
  final counts = <String, int>{};
  for (final todo in todos) {
    if (todo.isArchivedAfterRollover) continue;
    final dueDate = todo.dueDate;
    final anchor = todoDateInAppZone(dueDate ?? todo.createdAt);
    final key = homeWidgetCalendarDayKey(anchor);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final keys = counts.keys.toList()..sort();
  return <String, int>{for (final key in keys) key: counts[key]!};
}

/// 协议字段 `calendar_day_counts_json` 的规范形态（键已排序）。
String homeWidgetCalendarDayCountsJson(Map<String, int> counts) {
  final keys = counts.keys.toList()..sort();
  return jsonEncode(<String, int>{for (final key in keys) key: counts[key]!});
}

/// 完整当月周网格：周一为首列，周一..周日 7 列固定，行数 4-6。
///
/// 前导/尾部补 null；1 号到月末每天恰好出现一次，不产生多余的全空周。
/// 返回的是浮动日期，不含时区信息。
List<List<DateTime?>> buildHomeWidgetCalendarWeeks(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  final leading = first.weekday - DateTime.monday;
  final cells = <DateTime?>[
    for (var i = 0; i < leading; i++) null,
    for (var day = 1; day <= daysInMonth; day++)
      DateTime(month.year, month.month, day),
  ];
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  return <List<DateTime?>>[
    for (var start = 0; start < cells.length; start += 7)
      cells.sublist(start, start + 7),
  ];
}

/// 周一..周日的本地化短标签（native 侧按列填充表头）。
List<String> homeWidgetCalendarWeekdayLabels() => <String>[
  I18n.tr('widget.calendar_weekday_mon'),
  I18n.tr('widget.calendar_weekday_tue'),
  I18n.tr('widget.calendar_weekday_wed'),
  I18n.tr('widget.calendar_weekday_thu'),
  I18n.tr('widget.calendar_weekday_fri'),
  I18n.tr('widget.calendar_weekday_sat'),
  I18n.tr('widget.calendar_weekday_sun'),
];

/// 协议字段 `calendar_weekdays_json` 的形态。
String homeWidgetCalendarWeekdayLabelsJson() =>
    jsonEncode(homeWidgetCalendarWeekdayLabels());
