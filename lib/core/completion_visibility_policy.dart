import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../models/todo.dart';
import '../providers/goal_provider.dart';
import '../providers/todo_provider.dart';
import '../services/recurrence_engine.dart';
import 'app_clock.dart';
import 'design_tokens.dart';

/// 一条 Todo 在 UI 上呈现的"语义可视状态"。
///
/// 对应 `requirements.md` Requirement 3 与 `design.md §4 P4/P5` 的不变式：
/// - `normal`    ：普通任务（未完成，未过期，未临期）。
/// - `dueSoon`   ：临期（距离 `dueDate` < 3 小时 且仍在未来）。
/// - `overdue`   ：已过期（未完成，`dueDate` < now）。
/// - `completed` ：已完成（按 P4，"当日完成不销毁"）。
/// - `archived`  ：已在次日 00:00 归档，不再出现在"今日"视图。
enum TodoVisualState { normal, dueSoon, overdue, completed, archived }

/// 完成态 / 过期 / 归档的可视与可见性策略。
///
/// 设计目标：把"一条 Todo 今天是否露出"与"它的视觉语义"收敛到一个地方，
/// 让 Today 列表、日历、Widget 等调用方遵循同一套规则。
///
/// 详见 `design.md §3.5` 与 `requirements.md §3`。
class CompletionVisibilityPolicy {
  CompletionVisibilityPolicy._();

  /// 判断一条 Todo 是否应该出现在"今日待办"视图。
  ///
  /// 规则：
  /// 1. 已归档、已完成任务不展示。
  /// 2. 今天早于任务进入日期时不展示。
  /// 3. 无截止日期的未完成任务，从进入日期起持续展示，避免遗漏。
  /// 4. 有截止日期时，从进入日期起展示到截止日期当天结束。
  ///    兼容只保存日期、不保存具体时刻的旧数据：当天 00:00 视为全天截止。
  static bool shouldShowInToday(TodoItem t, DateTime now) {
    if (t.isArchivedAfterRollover) return false;
    if (t.isCompleted) return false;
    final today = dateOnly(now);
    final start = dateOnly(t.date);
    if (today.isBefore(start)) return false;
    final due = t.localDueDate;
    if (due == null) return true;
    final dueDay = dateOnly(due);
    if (today.isAfter(dueDay)) return false;
    return true;
  }

  /// 把一条 Todo 映射到它当前的可视语义状态。
  ///
  /// 优先级：`archived` > `completed` > `overdue` > `dueSoon` > `normal`。
  /// `now` 用于计算"过期 / 临期"，缺省使用应用时区的当前时刻。
  static TodoVisualState visualState(TodoItem t, {DateTime? now}) {
    if (t.isArchivedAfterRollover) return TodoVisualState.archived;
    if (t.isCompleted) return TodoVisualState.completed;

    final due = t.dueAt;
    if (due == null) return TodoVisualState.normal;

    final reference = now ?? AppClock.now();
    if (due.isBefore(reference)) return TodoVisualState.overdue;

    final delta = due.difference(reference);
    if (delta.inHours < 3 && due.isAfter(reference)) {
      return TodoVisualState.dueSoon;
    }
    return TodoVisualState.normal;
  }

  /// 把 [TodoVisualState] 映射到 `DesignTokens` 颜色。
  ///
  /// 调用方可以在列表项上直接使用这里返回的颜色作为主色 / 徽章色。
  static Color colorFor(TodoVisualState s) {
    switch (s) {
      case TodoVisualState.normal:
        return DesignTokens.todoNormal;
      case TodoVisualState.dueSoon:
        return DesignTokens.todoDueSoon;
      case TodoVisualState.overdue:
        return DesignTokens.todoOverdue;
      case TodoVisualState.completed:
        return DesignTokens.todoCompleted;
      case TodoVisualState.archived:
        return DesignTokens.todoArchived;
    }
  }

  /// 截断到"本地日"：把 [d] 的 `hour/minute/second/ms/µs` 全部置 0。
  ///
  /// 公开此工具是为了让 `DailyRollover`、`TodoProvider` 等调用方
  /// 与本策略保持相同的"当日"判定口径。
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 是否是仅表示本地日期的时间戳。
  static bool isDateOnly(DateTime d) =>
      d.hour == 0 &&
      d.minute == 0 &&
      d.second == 0 &&
      d.millisecond == 0 &&
      d.microsecond == 0;

  /// 每日跨天的"滚动归档"批处理入口（P5 / Requirement 3.3-3.6）。
  ///
  /// 在本地 00:00 或 `AppLifecycleState.resumed` 且日期跨天时由外层
  /// （Task 11.2 的 `main.dart` hookpoint）调用一次：
  ///
  /// 1. **归档昨日及更早的已完成任务**：调用
  ///    [TodoProvider.archivePastCompletions]，把
  ///    `isCompleted ∧ dateOnly(completedAt) < today` 的条目置为
  ///    `isArchivedAfterRollover = true`。
  /// 2. **基于 recurrence 派发今日实例**：`materializeTodayFromRecurring`
  ///    已由冷启动和 `AppLifecycleState.resumed` 跨天路径传入 [GoalProvider]
  ///    接线；命中后触发目标提醒重同步。
  ///
  /// [now] 作为参数注入便于测试；内部只使用其"日"部分做对齐。
  /// [goalProvider] 可选，传入时会触发 `materializeTodayFromRecurring` 并
  /// 对命中的 goal 刷新 `updatedAt` 以触发 ReminderScheduler 重同步。
  static Future<void> runDailyRollover(
    TodoProvider provider,
    DateTime now, {
    GoalProvider? goalProvider,
  }) async {
    final todayDay = dateOnly(now);

    // Step 1: 归档昨日及更早的已完成任务。
    await provider.archivePastCompletions(todayDay);

    // Step 2: 基于 recurrence 派发今日实例。
    if (goalProvider != null) {
      final matched = <String>[];
      RecurrenceEngine.materializeTodayFromRecurring(
        goals: goalProvider.goals,
        today: todayDay,
        onHit: (g, _) => matched.add(g.id),
      );
      if (matched.isNotEmpty) {
        debugPrint(
          '[CompletionVisibilityPolicy] runDailyRollover: '
          'materialized ${matched.length} recurring goal(s) for today.',
        );
        // 触发一次 onTimezoneChanged（它会通过 scheduler 重同步 goals），
        // 让命中的 goal 进入当日调度。这条路径是幂等的。
        await goalProvider.onTimezoneChanged();
      }
    } else {
      debugPrint(
        '[CompletionVisibilityPolicy] runDailyRollover: '
        'goalProvider omitted; skipping materializeTodayFromRecurring.',
      );
    }
  }
}
