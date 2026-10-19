import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/today_detail_router.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpRouterHarness(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => TodoProvider()),
          ChangeNotifierProvider(create: (_) => CourseProvider()),
          ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => HabitProvider()),
          ChangeNotifierProvider(create: (_) => NoteProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ListView(
                children: [
                  for (final entry in _missingDetailCases.entries)
                    TextButton(
                      key: ValueKey('open_${entry.key.name}'),
                      onPressed: () => TodayDetailRouter.open(
                        context,
                        entry.key,
                        id: 'missing-${entry.key.name}',
                      ),
                      child: Text(entry.key.name),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  for (final entry in _missingDetailCases.entries) {
    testWidgets('${entry.key.name} missing id opens branded fallback', (
      tester,
    ) async {
      await pumpRouterHarness(tester);

      await tester.tap(find.byKey(ValueKey('open_${entry.key.name}')));
      await tester.pumpAndSettle();

      expect(find.byType(BrandRouteSurface), findsOneWidget);
      expect(
        find.text(entry.value),
        entry.key == TodaySectionKind.diary ? findsNWidgets(2) : findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, '返回'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

final _missingDetailCases = <TodaySectionKind, String>{
  TodaySectionKind.todos: '这个待办不存在或已被删除',
  TodaySectionKind.courses: '这节课程不存在或已被删除',
  TodaySectionKind.anniversaries: '这个纪念日不存在或已被删除',
  TodaySectionKind.goals: '这个目标不存在或已被删除',
  TodaySectionKind.habits: '这个习惯不存在或已被删除',
  TodaySectionKind.notes: '这条随手记不存在或已被删除',
  TodaySectionKind.diary: I18n.tr('feature.unavailable'),
};
