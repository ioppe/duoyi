import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/calendar_event.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/widgets/calendar_event_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('legacy event sheet hides private data and all source actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarEventSheet(
            event: CalendarEvent(
              id: 'legacy',
              title: 'private content',
              subtitle: 'private mood',
              date: DateTime(2026, 5, 18),
              type: CalendarEventType.diary,
              color: Colors.teal,
              sourceId: 'legacy',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(I18n.tr('feature.unavailable')), findsWidgets);
    expect(find.text('private content'), findsNothing);
    expect(find.text('private mood'), findsNothing);
    for (final action in ['编辑', '删除', '跳转详情', '改期']) {
      expect(find.text(action), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('time entry event exposes quick duration adjustment', (
    tester,
  ) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    final provider = TimeAuditProvider();
    final entry = TimeEntry(
      id: 'time-1',
      title: '深度工作',
      startAt: DateTime(2026, 5, 18, 9),
      endAt: DateTime(2026, 5, 18, 9, 30),
      category: TimeEntryCategory.work,
      source: TimeEntrySource.manual,
    );
    await provider.add(entry);

    await tester.pumpWidget(
      ChangeNotifierProvider<TimeAuditProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: CalendarEventSheet(
              event: CalendarEvent(
                id: 'time_time-1',
                title: '深度工作',
                date: entry.startAt,
                endDate: entry.endAt,
                type: CalendarEventType.timeEntry,
                color: Colors.orange,
                sourceId: entry.id,
                time: TimeOfDay.fromDateTime(entry.startAt),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('改期'), findsOneWidget);
    expect(find.text('调整开始'), findsOneWidget);
    expect(find.text('调整时长'), findsOneWidget);

    await tester.tap(find.text('调整时长'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('90 分钟'));
    await tester.pumpAndSettle();

    expect(provider.entries.single.durationSeconds, 90 * 60);
    expect(provider.entries.single.startAt, entry.startAt);
    expect(provider.entries.single.endAt, DateTime(2026, 5, 18, 10, 30));
  });

  testWidgets('time entry event can adjust start time and keep duration', (
    tester,
  ) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    final provider = TimeAuditProvider();
    final entry = TimeEntry(
      id: 'time-2',
      title: '阅读',
      startAt: DateTime(2026, 5, 18, 9),
      endAt: DateTime(2026, 5, 18, 10),
      category: TimeEntryCategory.study,
      source: TimeEntrySource.manual,
    );
    await provider.add(entry);

    await tester.pumpWidget(
      ChangeNotifierProvider<TimeAuditProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: CalendarEventSheet(
              event: CalendarEvent(
                id: 'time_time-2',
                title: '阅读',
                date: entry.startAt,
                endDate: entry.endAt,
                type: CalendarEventType.timeEntry,
                color: Colors.orange,
                sourceId: entry.id,
                time: TimeOfDay.fromDateTime(entry.startAt),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('调整开始'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('晚上 20:00'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(provider.entries.single.startAt, DateTime(2026, 5, 18, 20));
    expect(provider.entries.single.endAt, DateTime(2026, 5, 18, 21));
    expect(provider.entries.single.durationSeconds, 60 * 60);
  });

  testWidgets('todo event can adjust due time from calendar sheet', (
    tester,
  ) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    final provider = TodoProvider();
    final todo = TodoItem(
      id: 'todo-1',
      title: '提交周报',
      date: DateTime(2026, 5, 18),
      dueDate: DateTime(2026, 5, 18, 9),
    );
    await provider.addTodo(todo);

    await tester.pumpWidget(
      ChangeNotifierProvider<TodoProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: CalendarEventSheet(
              event: CalendarEvent(
                id: 'todo_todo-1',
                title: '提交周报',
                date: todo.date,
                endDate: todo.dueDate,
                type: CalendarEventType.todo,
                color: Colors.blue,
                sourceId: todo.id,
                time: TimeOfDay.fromDateTime(todo.dueDate!),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('调整时间'), findsOneWidget);

    await tester.tap(find.text('调整时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('晚上 20:00'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('确定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(provider.todos.single.dueDate, DateTime(2026, 5, 18, 20));
    expect(provider.todos.single.date, DateTime(2026, 5, 18));
  });

  testWidgets('countdown event exposes actions and can delete source item', (
    tester,
  ) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    final provider = CountdownProvider();
    await provider.addItem(
      CountdownItem(
        id: 'countdown-1',
        title: '版本发布',
        targetDate: DateTime(2026, 6, 1),
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<CountdownProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: CalendarEventSheet(
              event: CalendarEvent(
                id: 'countdown_countdown-1',
                title: '版本发布',
                date: DateTime(2026, 6, 1),
                type: CalendarEventType.countdown,
                color: Colors.deepOrange,
                sourceId: 'countdown-1',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('改期'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('跳转详情'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(provider.items, isEmpty);
  });
}
