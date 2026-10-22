import 'dart:convert';

import 'package:duoyi/models/pomodoro.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 关联字段（todoId / subtaskId / todoTitle）上线前的历史会话 JSON。
  Map<String, dynamic> legacySessionJson() => <String, dynamic>{
    'id': 'session-legacy',
    'startTime': DateTime.utc(2026, 1, 1, 8).toIso8601String(),
    'endTime': DateTime.utc(2026, 1, 1, 8, 25).toIso8601String(),
    'durationSeconds': 1500,
    'type': PomodoroType.focus.index,
    'taskName': '写周报',
    'whiteNoiseSound': 'rain',
    'tag': '工作',
    'updatedAt': DateTime.utc(2026, 1, 1, 8, 25).toIso8601String(),
  };

  PomodoroSession linkedSession() => PomodoroSession(
    id: 'session-linked',
    startTime: DateTime.utc(2026, 1, 2, 9),
    endTime: DateTime.utc(2026, 1, 2, 9, 25),
    durationSeconds: 1500,
    type: PomodoroType.focus,
    taskName: '写总结',
    todoId: 'todo-1',
    subtaskId: 'sub-1',
    todoTitle: '周报整理',
  );

  test('PomodoroSession 旧 JSON 缺关联字段时读取为 null，taskLabel 退化为 taskName', () {
    final legacy = PomodoroSession.fromJson(legacySessionJson());

    expect(legacy.todoId, isNull);
    expect(legacy.subtaskId, isNull);
    expect(legacy.todoTitle, isNull);
    expect(legacy.taskName, '写周报');
    expect(legacy.taskLabel, '写周报', reason: '旧数据没有父任务快照，只能显示 taskName');

    // 重新序列化仍是合法 JSON，且关联键存在但为 null（客户端可安全回写）。
    final encoded = legacy.toJson();
    expect(encoded['todoId'], isNull);
    expect(encoded['subtaskId'], isNull);
    expect(encoded['todoTitle'], isNull);

    final roundtrip = PomodoroSession.fromJson(
      jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>,
    );
    expect(roundtrip.taskName, '写周报');
    expect(roundtrip.todoId, isNull);
    expect(roundtrip.subtaskId, isNull);
    expect(roundtrip.todoTitle, isNull);
  });

  test('PomodoroSession 关联字段 JSON roundtrip 保留，taskLabel 为父任务 / 子任务', () {
    final session = linkedSession();

    final decoded = PomodoroSession.fromJson(
      jsonDecode(jsonEncode(session.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.todoId, 'todo-1');
    expect(decoded.subtaskId, 'sub-1');
    expect(decoded.todoTitle, '周报整理');
    expect(decoded.taskName, '写总结', reason: 'taskName 仍是被选择的对象（子任务）名称');
    expect(decoded.taskLabel, '周报整理 / 写总结');
  });

  test('PomodoroSession copyWith 默认保留关联，clearTaskLink 一次清三字段', () {
    final session = linkedSession();

    final renamed = session.copyWith(taskName: '写结论');
    expect(renamed.todoId, 'todo-1');
    expect(renamed.subtaskId, 'sub-1');
    expect(renamed.todoTitle, '周报整理');
    expect(renamed.taskLabel, '周报整理 / 写结论');

    final cleared = session.copyWith(clearTaskLink: true);
    expect(cleared.todoId, isNull);
    expect(cleared.subtaskId, isNull);
    expect(cleared.todoTitle, isNull);
    expect(cleared.taskName, '写总结', reason: 'clearTaskLink 只清关联，不动 taskName');
    expect(cleared.taskLabel, '写总结');

    // 清关联的同时仍可改名（两个开关互不影响）。
    final clearedAndNamed = session.copyWith(
      taskName: '手动任务',
      clearTaskLink: true,
    );
    expect(clearedAndNamed.taskName, '手动任务');
    expect(clearedAndNamed.todoId, isNull);
    expect(clearedAndNamed.subtaskId, isNull);
    expect(clearedAndNamed.todoTitle, isNull);
  });

  test('PomodoroState copyWith 维护关联字段与 taskLabel', () {
    const linked = PomodoroState(
      remainingSeconds: 100,
      totalSeconds: 1500,
      isRunning: true,
      type: PomodoroType.focus,
      completedSessions: 2,
      taskName: '写总结',
      todoId: 'todo-1',
      subtaskId: 'sub-1',
      todoTitle: '周报整理',
    );
    expect(linked.taskLabel, '周报整理 / 写总结');

    final ticked = linked.copyWith(remainingSeconds: 99);
    expect(ticked.todoId, 'todo-1');
    expect(ticked.subtaskId, 'sub-1');
    expect(ticked.todoTitle, '周报整理');
    expect(ticked.taskLabel, '周报整理 / 写总结');

    // 只选父任务（有 todoTitle 但无 subtaskId）：展示仍用 taskName。
    const parentOnly = PomodoroState(
      remainingSeconds: 100,
      totalSeconds: 1500,
      isRunning: false,
      type: PomodoroType.focus,
      completedSessions: 0,
      taskName: '周报整理',
      todoId: 'todo-1',
      todoTitle: '周报整理',
    );
    expect(
      parentOnly.taskLabel,
      '周报整理',
      reason: '无 subtaskId 时即使有 todoTitle 也只用 taskName',
    );

    final cleared = linked.copyWith(clearTaskLink: true);
    expect(cleared.todoId, isNull);
    expect(cleared.subtaskId, isNull);
    expect(cleared.todoTitle, isNull);
    expect(cleared.taskName, '写总结');
    expect(cleared.taskLabel, '写总结');
  });
}
