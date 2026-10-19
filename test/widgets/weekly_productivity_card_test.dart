import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/widgets/weekly_productivity_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
    AppClock.debugNow = () => DateTime.utc(2026, 6, 2, 12);
  });

  tearDown(() {
    AppClock.debugNow = null;
  });

  for (final zone in ['America/New_York', 'Asia/Tokyo']) {
    testWidgets('本周效率在 $zone 按相同日历天数比较上周同段', (tester) async {
      await tester.runAsync(
        () => LocalTimezoneResolver.setApplicationTimeZone(zone),
      );
      expect(AppClock.now().weekday, DateTime.tuesday);
      final sessions = [
        PomodoroSession(
          id: 'current-week',
          startTime: DateTime.utc(2026, 6, 1, 11),
          endTime: DateTime.utc(2026, 6, 1, 12),
          durationSeconds: 3600,
          type: PomodoroType.focus,
        ),
        PomodoroSession(
          id: 'previous-week',
          startTime: DateTime.utc(2026, 5, 25, 11),
          endTime: DateTime.utc(2026, 5, 25, 12),
          durationSeconds: 3600,
          type: PomodoroType.focus,
        ),
      ];
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => TodoProvider()),
            ChangeNotifierProvider(create: (_) => HabitProvider()),
            ChangeNotifierProvider(
              create: (_) => PomodoroProvider()..sessions.addAll(sessions),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(body: WeeklyProductivityCard(onTap: () {})),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Each period spans Monday and Tuesday: 60 / (2 * 60) * 25 = 13.
      // A mixed application-zone instant and system-zone date incorrectly gave
      // the current period one day and a spurious upward trend.
      expect(find.text('13'), findsOneWidget);
      expect(find.text(I18n.tr('today.productivity.flat')), findsOneWidget);
      expect(find.textContaining('+12'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
