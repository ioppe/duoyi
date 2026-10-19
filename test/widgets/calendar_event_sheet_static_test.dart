import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('日历详情拥有独立滚动区域，避免长内容撑高底部弹层', () {
    final source = File(
      'lib/widgets/calendar_event_sheet.dart',
    ).readAsStringSync();

    final sheetStart = source.indexOf('class CalendarEventSheet');
    final actionsStart = source.indexOf(
      'List<Widget> _buildActions',
      sheetStart,
    );
    expect(sheetStart, greaterThanOrEqualTo(0));
    expect(actionsStart, greaterThan(sheetStart));
    final sheet = source.substring(sheetStart, actionsStart);

    expect(sheet, contains('maxWidth: 860'));
    expect(sheet, contains('scrollable: false'));
    expect(
      sheet,
      contains("key: const ValueKey('calendar_event_detail_scroll_region')"),
    );
    expect(sheet, contains('mainAxisSize: MainAxisSize.min'));
    expect(sheet, isNot(contains('detailMaxHeight')));
    expect(sheet, contains('SingleChildScrollView('));
    expect(sheet, isNot(contains('Scrollbar(')));
    expect(sheet, isNot(contains('ListView(')));
    expect(sheet, isNot(contains('shrinkWrap: true')));
    expect(
      source,
      contains('minimumSize: const WidgetStatePropertyAll(Size(0, 34))'),
    );
    expect(source, contains('tapTargetSize: MaterialTapTargetSize.shrinkWrap'));
    expect(source, contains('visualDensity: VisualDensity.compact'));
    expect(source, contains('appSecondaryControlTextStyle(context)'));
    expect(source, contains('BrandRouteSurface('));
    expect(
      source,
      contains('const BrandRouteSurface(child: TimeAuditScreen())'),
    );
  });

  test('日历详情对可回写类型暴露改期和删除动作', () {
    final source = File(
      'lib/widgets/calendar_event_sheet.dart',
    ).readAsStringSync();

    for (final type in [
      'CalendarEventType.goal',
      'CalendarEventType.anniversary',
      'CalendarEventType.countdown',
    ]) {
      final block = _caseBlock(source, type);
      expect(block, contains("label: '改期'"));
      expect(block, contains('onPressed: () => _reschedule(context)'));
      expect(block, contains("label: '删除'"));
      expect(block, contains('onPressed: () => _delete(context)'));
    }

    for (final type in [
      'CalendarEventType.anniversary',
      'CalendarEventType.countdown',
      'CalendarEventType.course',
      'CalendarEventType.habit',
      'CalendarEventType.pomodoro',
    ]) {
      final block = _caseBlock(source, type);
      expect(block, contains("label: '编辑'"));
      expect(block, contains('onPressed: () => _editSourceEvent(context)'));
    }

    for (final type in [
      'CalendarEventType.countdown',
      'CalendarEventType.course',
      'CalendarEventType.habit',
      'CalendarEventType.timeEntry',
    ]) {
      final block = _caseBlock(source, type);
      expect(block, contains("label: '删除'"));
      expect(block, contains('onPressed: () => _delete(context)'));
    }
  });

  test('日历详情复用原模块编辑器并拒绝已退役类型', () {
    final sheet = File(
      'lib/widgets/calendar_event_sheet.dart',
    ).readAsStringSync();
    final anniversary = File(
      'lib/screens/anniversary_screen.dart',
    ).readAsStringSync();
    final course = File(
      'lib/screens/course_schedule_screen.dart',
    ).readAsStringSync();
    final diary = File('lib/screens/diary_screen.dart').readAsStringSync();
    final habit = File(
      'lib/screens/habit_detail_screen.dart',
    ).readAsStringSync();

    expect(sheet, contains("import '../screens/anniversary_screen.dart';"));
    expect(sheet, contains("import '../screens/countdown_screen.dart';"));
    expect(sheet, contains("import '../providers/countdown_provider.dart';"));
    expect(sheet, contains("import '../screens/course_schedule_screen.dart';"));
    expect(sheet, isNot(contains("import '../screens/diary_screen.dart';")));
    expect(sheet, contains("import '../screens/habit_detail_screen.dart';"));
    expect(sheet, isNot(contains('DiaryProvider')));
    expect(sheet, contains('Future<void> _editSourceEvent'));
    expect(
      sheet,
      contains('showAnniversaryEditor(navigationContext, item: item)'),
    );
    expect(
      sheet,
      contains('showCountdownEditor(navigationContext, item: item)'),
    );
    expect(sheet, contains('CountdownScreen(initialCountdownId: sourceId)'));
    expect(
      sheet,
      contains('context.read<CountdownProvider>().deleteItem(sourceId)'),
    );
    expect(
      sheet,
      contains('await provider.updateItem(item.copyWith(targetDate: picked))'),
    );
    expect(
      sheet,
      contains('showCourseEditor(navigationContext, course: item)'),
    );
    expect(sheet, isNot(contains('showDiaryEditor(')));
    expect(sheet, contains('showHabitEditor(navigationContext, item)'));
    expect(
      sheet,
      contains('showPomodoroSessionEditor(navigationContext, item)'),
    );
    expect(
      _caseBlock(sheet, 'CalendarEventType.diary'),
      contains('return const <Widget>[]'),
    );
    expect(
      sheet,
      contains('context.read<HabitProvider>().deleteHabit(sourceId)'),
    );
    expect(
      sheet,
      contains('context.read<PomodoroProvider>().deleteSession(sourceId)'),
    );

    expect(anniversary, contains('Future<void> showAnniversaryEditor'));
    expect(
      anniversary,
      contains('_AnniversaryEditSheet(editing: item, fixedType: editorType)'),
    );
    expect(course, contains('Future<void> showCourseEditor'));
    expect(
      course,
      contains('_CourseEditSheet(provider: provider, course: course)'),
    );
    expect(diary, contains('Future<void> showDiaryEditor'));
    expect(diary, contains("I18n.tr('feature.unavailable')"));
    expect(habit, contains('Future<void> showHabitEditor'));
    expect(habit, contains('habitProvider.updateHabit(habit.id, updated)'));
    expect(habit, contains('onPressed: () => showHabitEditor(context, habit)'));
    final pomodoro = File(
      'lib/screens/pomodoro_screen.dart',
    ).readAsStringSync();
    final card = File(
      'lib/widgets/pomodoro_session_card.dart',
    ).readAsStringSync();
    expect(pomodoro, contains('Future<void> showPomodoroSessionEditor'));
    expect(pomodoro, contains('provider.updateSession(next)'));
    expect(
      pomodoro,
      contains('onEdit: () => showPomodoroSessionEditor(context, s)'),
    );
    expect(card, contains('final VoidCallback? onEdit;'));
    expect(card, contains("message: '编辑记录'"));
    expect(card, contains('icon: const Icon(Icons.edit_outlined)'));
  });
}

String _caseBlock(String source, String caseLabel) {
  final start = source.indexOf('case $caseLabel:');
  expect(start, isNonNegative, reason: '$caseLabel should exist');
  final rest = source.substring(start + 'case $caseLabel:'.length);
  final nextCase = rest.indexOf('case CalendarEventType.');
  final end = nextCase == -1 ? rest.indexOf('    }\n  }') : nextCase;
  expect(end, isNonNegative, reason: '$caseLabel case should have an end');
  return rest.substring(0, end);
}
