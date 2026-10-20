import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/ai_schedule_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/widgets/quick_capture_fab.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAiService extends AiService {
  @override
  bool get enabled => true;

  @override
  Future<List<String>> breakDownTask(String goal) async {
    return List<String>.generate(14, (i) => '子任务 ${i + 1}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('quick capture keeps notes without any retired creation action', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AiService>(
        create: (_) => _FakeAiService(),
        child: const MaterialApp(
          home: Scaffold(floatingActionButton: QuickCaptureFab()),
        ),
      ),
    );
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithIcon(FloatingActionButton, Icons.book_outlined),
      findsNothing,
    );
    expect(find.text('写日记'), findsNothing);
    expect(
      find.widgetWithIcon(FloatingActionButton, Icons.edit_note),
      findsOneWidget,
    );
    await tester.tap(
      find.widgetWithIcon(FloatingActionButton, Icons.edit_note),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('快捷模板占半屏至三分之二屏，点击上方遮罩关闭', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AiService>(
        create: (_) => _FakeAiService(),
        child: const MaterialApp(
          home: Scaffold(floatingActionButton: QuickCaptureFab()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    final card = tester.getRect(
      find
          .descendant(
            of: find.byType(AppModalSheet),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(card.height, inInclusiveRange(844 / 2, 844 * 2 / 3));
    await tester.tapAt(Offset(card.center.dx, card.top - 20));
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI schedule shortcut opens dedicated route', (tester) async {
    tester.view.physicalSize = const Size(390, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TodoProvider>(create: (_) => TodoProvider()),
          ChangeNotifierProvider<CalendarProvider>(
            create: (_) => CalendarProvider(),
          ),
          ChangeNotifierProvider<NotificationService>(
            create: (_) => NotificationService(),
          ),
          ChangeNotifierProvider<NoteProvider>(create: (_) => NoteProvider()),
          ChangeNotifierProvider<AiService>(create: (_) => _FakeAiService()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(),
            floatingActionButton: QuickCaptureFab(),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(FloatingActionButton).last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithIcon(FloatingActionButton, Icons.auto_awesome),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AiScheduleScreen), findsOneWidget);
    expect(find.text('AI 创建日程'), findsOneWidget);
  });

  test('待办快捷入口复用完整添加表单并保留智能日期解析', () {
    final source = File(
      'lib/widgets/quick_capture_fab.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> _quickTodo');
    final end = source.indexOf('Future<void> _quickAiTodo', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final method = source.substring(start, end);
    expect(method, contains('showTodoCreateSheet(context)'));
    expect(method, isNot(contains('showDialog')));
    final form = File('lib/widgets/todo_create_sheet.dart').readAsStringSync();
    expect(form, contains('SmartTodoDraftBuilder.fromText'));
    expect(form, contains('draft.toTodo'));
    expect(
      File('lib/screens/todo_screen.dart').readAsStringSync(),
      contains(
        'showTodoCreateSheet(context, initialQuadrant: initialQuadrant)',
      ),
    );
  });

  test('AI schedule shortcut routes into the dedicated AI schedule screen', () {
    final source = File(
      'lib/widgets/quick_capture_fab.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> _quickAiTodo');
    final end = source.indexOf('Future<void> _quickAiCommand', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final method = source.substring(start, end);

    expect(method, contains('AiScheduleScreen'));
    expect(
      method,
      contains('MaterialPageRoute(builder: (_) => const AiScheduleScreen())'),
    );
  });
}
