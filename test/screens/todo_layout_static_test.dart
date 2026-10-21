import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('待办列表元信息长标签和负责人有窄屏保护', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(source, contains('class _MetaPill'));
    expect(source, contains('BoxConstraints(maxWidth: 160)'));
    expect(source, contains("'#\$t'"));
    expect(source, contains('overflow: TextOverflow.ellipsis'));
    expect(source, contains("'@\$assigneeName'"));
    expect(source, contains('Flexible('));
  });

  test('待办今日摘要和分组标题在窄屏下不撑破布局', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();

    final summary = source.substring(
      source.indexOf('class _TodoTodaySummaryCard'),
      source.indexOf('class _TodoSummaryChipData'),
    );
    expect(summary, contains('constraints.maxWidth < 420'));
    expect(summary, contains("'今日还要完成 \$remaining 项'"));
    expect(
      summary,
      contains(
        'final remaining = dailyRemaining + todoCount + activeGoalCount;',
      ),
    );
    expect(
      summary,
      isNot(contains('final remaining = dailyRemaining + todoCount;')),
    );
    expect(summary, isNot(contains("'今日还要完成 \$actionableRemaining 项'")));
    expect(
      summary,
      contains("'日常 \$dailyRemaining / 待办 \$todoCount / 目标 \$activeGoalCount'"),
    );
    expect(summary, isNot(contains('代表')));

    final chip = source.substring(
      source.indexOf('class _TodoSummaryChip'),
      source.indexOf('class _TodoFilterBar'),
    );
    expect(chip, contains('BoxConstraints(minWidth: 86, maxWidth: 118)'));
    expect(chip, contains('Flexible('));
    expect(chip, contains('overflow: TextOverflow.ellipsis'));

    final groupTile = source.substring(
      source.indexOf('class _ListGroupTile'),
      source.indexOf('class _TodoTile'),
    );
    expect(groupTile, contains('maxLines: 1'));
    expect(groupTile, contains('overflow: TextOverflow.ellipsis'));
  });

  test('待办详情长子任务和长标签不会撑破窄屏', () {
    final source = File(
      'lib/screens/todo_detail_screen.dart',
    ).readAsStringSync();

    expect(source, contains('child: TodoSubtaskEditor('));
    final editor = File(
      'lib/widgets/todo_subtask_editor.dart',
    ).readAsStringSync();
    final row = editor.substring(editor.indexOf('class _SubtaskDraftRowState'));
    expect(row, contains('Expanded('));
    expect(row, contains('child: TextField('));
    expect(row, contains('minLines: 1'));
    expect(row, contains('maxLines: null'));
    expect(row, contains('keyboardType: TextInputType.multiline'));
    expect(row, isNot(contains('TextOverflow.ellipsis')));
    expect(source, contains('BoxConstraints(maxWidth: 180)'));
    expect(source, contains('overflow: TextOverflow.ellipsis'));
    expect(source, contains("'#\$t'"));
  });

  test('待办详情负责人、评论和位置提醒弹窗有窄屏保护', () {
    final source = File(
      'lib/screens/todo_detail_screen.dart',
    ).readAsStringSync();

    final assignment = source.substring(
      source.indexOf('class _AssignmentEditor'),
      source.indexOf('class _TaskCommentsPanel'),
    );
    expect(assignment, contains('helperMaxLines: 2'));
    expect(assignment, contains('maxLines: 2'));
    expect(assignment, contains('overflow: TextOverflow.ellipsis'));

    final locationDialog = source.substring(
      source.indexOf("title: const Text('添加位置提醒')"),
      source.indexOf('if (ok != true) return;'),
    );
    expect(locationDialog, contains('LayoutBuilder('));
    expect(locationDialog, contains('constraints.maxWidth < 260'));
    expect(locationDialog, contains('Wrap('));

    final comments = source.substring(
      source.indexOf('class _TaskCommentsPanel'),
      source.indexOf('/// 目标时长编辑器'),
    );
    expect(comments, contains('maxLines: 1'));
    expect(comments, contains('overflow: TextOverflow.ellipsis'));
  });

  test('通知栏今日任务进展文案使用待办而不是代表', () {
    final statusBar = File(
      'lib/services/notification_status_bar_service.dart',
    ).readAsStringSync();
    final i18n = File('lib/core/i18n.dart').readAsStringSync();

    expect(statusBar, contains("'notification.status_bar.todo_count'"));
    expect(i18n, contains("'notification.status_bar.todo_count': '待办 '"));
    expect(i18n, isNot(contains("'notification.status_bar.todo_count': '代表 ")));
  });
}
