import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('今日提醒按优先级展示且今日建议默认收起放在末尾', () {
    final today = File('lib/screens/today_screen.dart').readAsStringSync();

    expect(
      today,
      contains('final reminderGroups = _TodayReminderGroups.build'),
    );
    expect(today, contains('class _TodayReminderGroups'));
    expect(today, contains("Text(\n                            '今日提醒'"));
    expect(today, contains('今日待提醒 > 即将开始 > 逾期优先处理'));
    expect(
      today,
      contains("ValueKey('today_reminder_section_collapsed_by_default')"),
    );
    expect(today, contains('bool _expanded = false'));
    expect(
      today,
      contains('if (_expanded && widget.groups.dueToday.isNotEmpty)'),
    );
    expect(today, contains("title: '今日待提醒事项'"));
    expect(today, contains("title: '即将开始事项'"));
    expect(today, contains("title: '已逾期事项'"));
    expect(today, contains('overdue: true'));
    expect(today, contains('class _OverdueReminderBadge'));
    expect(today, contains("I18n.tr('todo.status.overdue')"));
    expect(today, contains('Icons.priority_high_rounded'));
    expect(today, contains('cs.error.withValues(alpha: 0.10)'));
    expect(today, contains('cs.error.withValues(alpha: 0.38)'));
    expect(today, contains('cs.error.withValues(alpha: 0.08)'));
    expect(today, contains('cs.error.withValues(alpha: 0.26)'));
    expect(today, contains('overdueTitleColor = cs.error'));
    expect(today, contains('overdueSubtitleColor = cs.error'));
    expect(today, contains('final completedColor = const Color(0xFF4CAF50)'));
    expect(today, contains('final completedBackground = Color.alphaBlend'));
    expect(today, contains('completedToday.add(item)'));
    expect(today, contains('completed: todo.isCompleted'));
    expect(today, contains('completed ? TextDecoration.lineThrough : null'));
    expect(today, contains('completedTextColor: overdue'));
    expect(today, contains('tileBackground: overdue'));
    expect(today, contains('tileBorderColor: overdue'));
    expect(today, contains('showOverdueBadge: overdue'));
    expect(today, contains('showStatusDecoration: true'));
    expect(today, contains('ExpansionTile('));
    expect(today, contains('initiallyExpanded: false'));
    expect(today, contains('maintainState: true'));
    expect(today, contains('class _SuggestionSectionState'));
    expect(today, contains("final Set<String> _addingTodoIds = <String>{};"));
    expect(today, contains("ValueKey('today_suggestion_add_"));
    expect(today, contains('默认收起'));
    expect(today, contains('class _TodoTemplateAvatar'));
    expect(today, contains('today_suggestion_template_icon'));
    expect(today, contains('class _TodayTodoLeading'));
    expect(today, contains('today_todo_template_icon'));
    expect(today, contains('today_reminder_template_icon'));
    expect(today, contains("iconKeyPrefix = 'today_todo_template_icon'"));
    // 无子任务时左侧是可点的完成控件；有子任务时改为进度，完成交给子任务。
    expect(today, contains('? _TodayTodoLeading('));
    expect(today, contains(': _TodaySubtaskProgress(todo: todo)'));
    expect(today, contains('class _TodayTodoStatusToggle'));
    expect(today, contains('class _TodayTodoTitleLine'));
    expect(today, contains('static const double width = 44'));
    expect(today, contains('static const double touchTargetSize = 44'));
    expect(today, contains('static const double statusButtonSize = 24'));

    expect(
      today,
      contains(
        'final showReminderSection =\n        !reminderGroups.isEmpty || suggestions.isNotEmpty;',
      ),
    );
    final reminderFactoryIndex = today.indexOf('Widget? reminderSection()');
    final reminderValueIndex = today.indexOf(
      'final reminder = reminderSection();',
    );
    final pageStart = today.indexOf("id: 'today_screen_list'");
    final pageEnd = today.indexOf("id: 'today_goals_list'", pageStart);
    final todoIndex = today.indexOf('Widget todosSection({int maxItems = 6})');
    final goalIndex = today.indexOf('Widget goalsSection()');
    expect(reminderFactoryIndex, greaterThanOrEqualTo(0));
    expect(reminderValueIndex, greaterThan(reminderFactoryIndex));
    expect(todoIndex, greaterThanOrEqualTo(0));
    expect(reminderFactoryIndex, greaterThan(todoIndex));
    expect(goalIndex, greaterThan(reminderFactoryIndex));
    expect(pageStart, greaterThanOrEqualTo(0));
    expect(pageEnd, greaterThan(pageStart));
    final page = today.substring(pageStart, pageEnd);
    final taskPosition = page.indexOf('todosSection(maxItems:');
    final reminderPosition = page.indexOf('?reminder,');
    expect(taskPosition, greaterThanOrEqualTo(0));
    expect(reminderPosition, greaterThan(taskPosition));
    expect(today, contains('TabBarView('));
    expect(today, contains('initialIndex: 0'));

    final sectionStart = today.indexOf('class _TodayReminderSection');
    final sectionEnd = today.indexOf('class _ReminderGroupBlock');
    expect(sectionStart, greaterThanOrEqualTo(0));
    expect(sectionEnd, greaterThan(sectionStart));
    final section = today.substring(sectionStart, sectionEnd);

    final dueIndex = section.indexOf("title: '今日待提醒事项'");
    final upcomingIndex = section.indexOf("title: '即将开始事项'");
    final overdueIndex = section.indexOf("title: '已逾期事项'");
    final suggestionIndex = section.indexOf(
      'if (_expanded && widget.suggestions.isNotEmpty)',
    );
    expect(dueIndex, greaterThanOrEqualTo(0));
    expect(upcomingIndex, greaterThan(dueIndex));
    expect(overdueIndex, greaterThan(upcomingIndex));
    expect(suggestionIndex, greaterThan(overdueIndex));
  });
}
