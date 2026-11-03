import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/screens/calendar_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('CalendarScreen exposes year view', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => TodoProvider()),
          ChangeNotifierProvider(create: (_) => HabitProvider()),
          ChangeNotifierProvider(create: (_) => PomodoroProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => CloudSyncProvider()),
          ChangeNotifierProvider(create: (_) => CalendarProvider()),
          ChangeNotifierProvider(create: (_) => UserProvider()),
          ChangeNotifierProvider(create: (_) => CountdownProvider()),
          ChangeNotifierProvider(create: (_) => NoteProvider()),
          ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
          ChangeNotifierProvider(create: (_) => DiaryProvider()),
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => CourseProvider()),
          ChangeNotifierProvider(create: (_) => AppLockProvider()),
          ChangeNotifierProvider(create: (_) => PreferencesProvider()),
          ChangeNotifierProvider(create: (_) => AchievementProvider()),
          ChangeNotifierProvider(create: (_) => ShareProvider()),
          ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
          ChangeNotifierProvider(create: (_) => NotificationService()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => AiService()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ChangeNotifierProvider(create: (_) => LocationReminderProvider()),
          ChangeNotifierProvider(create: (_) => CalendarSyncProvider()),
          ChangeNotifierProvider(
            create: (_) => AppUpdateService(
              repo: 'dq52099/duoyi',
              currentVersion: AppVersion.name,
            ),
          ),
        ],
        child: const MaterialApp(home: CalendarScreen()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('年'));
    await tester.pumpAndSettle();
    expect(find.byType(Tab), findsNWidgets(5));
    expect(
      find.byKey(const ValueKey('calendar_year_overview')),
      findsOneWidget,
    );
  });

  testWidgets('CalendarScreen year navigation shows year controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => TodoProvider()),
          ChangeNotifierProvider(create: (_) => HabitProvider()),
          ChangeNotifierProvider(create: (_) => PomodoroProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => CloudSyncProvider()),
          ChangeNotifierProvider(create: (_) => CalendarProvider()),
          ChangeNotifierProvider(create: (_) => UserProvider()),
          ChangeNotifierProvider(create: (_) => CountdownProvider()),
          ChangeNotifierProvider(create: (_) => NoteProvider()),
          ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
          ChangeNotifierProvider(create: (_) => DiaryProvider()),
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => CourseProvider()),
          ChangeNotifierProvider(create: (_) => AppLockProvider()),
          ChangeNotifierProvider(create: (_) => PreferencesProvider()),
          ChangeNotifierProvider(create: (_) => AchievementProvider()),
          ChangeNotifierProvider(create: (_) => ShareProvider()),
          ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
          ChangeNotifierProvider(create: (_) => NotificationService()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => AiService()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ChangeNotifierProvider(create: (_) => LocationReminderProvider()),
          ChangeNotifierProvider(create: (_) => CalendarSyncProvider()),
          ChangeNotifierProvider(
            create: (_) => AppUpdateService(
              repo: 'dq52099/duoyi',
              currentVersion: AppVersion.name,
            ),
          ),
        ],
        child: const MaterialApp(home: CalendarScreen()),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('年'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('calendar_year_overview')),
      findsOneWidget,
    );
    expect(find.byTooltip('上一年'), findsOneWidget);
    expect(find.byTooltip('下一年'), findsOneWidget);
  });

  testWidgets('CalendarScreen day navigation moves by one day', (tester) async {
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    final todayLabel = '${today.year}年${today.month}月${today.day}日';
    final tomorrowLabel = '${tomorrow.year}年${tomorrow.month}月${tomorrow.day}日';

    await tester.pumpWidget(_wrapCalendar());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(Tab, '日'));
    await tester.pumpAndSettle();
    expect(find.text(todayLabel), findsOneWidget);

    await tester.tap(find.byTooltip('下一天'));
    await tester.pumpAndSettle();
    expect(find.text(tomorrowLabel), findsOneWidget);

    await tester.tap(find.byTooltip('上一天'));
    await tester.pumpAndSettle();
    expect(find.text(todayLabel), findsOneWidget);
  });

  testWidgets('CalendarScreen exposes three-day view and navigation', (
    tester,
  ) async {
    // Crossing the New York DST fallback must still advance three calendar days.
    final today = DateTime(2026, 10, 30);
    final rangeEnd = DateTime(today.year, today.month, today.day + 2);
    final nextRangeStart = DateTime(today.year, today.month, today.day + 3);
    final nextRangeEnd = DateTime(today.year, today.month, today.day + 5);
    final todayRange =
        '${today.year}年${today.month}/${today.day} - ${rangeEnd.month}/${rangeEnd.day}';
    final nextRange =
        '${nextRangeStart.year}年${nextRangeStart.month}/${nextRangeStart.day} - ${nextRangeEnd.month}/${nextRangeEnd.day}';

    await tester.pumpWidget(_wrapCalendar(initialDate: today));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(Tab, '三日'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('calendar_three_day_view')),
      findsOneWidget,
    );
    expect(find.text(todayRange), findsOneWidget);
    expect(find.byTooltip('前三天'), findsOneWidget);
    expect(find.byTooltip('后三天'), findsOneWidget);

    await tester.tap(find.byTooltip('后三天'));
    await tester.pumpAndSettle();
    expect(find.text(nextRange), findsOneWidget);
    await tester.tap(find.byTooltip('前三天'));
    await tester.pumpAndSettle();
    expect(find.text(todayRange), findsOneWidget);
  });
}

Widget _wrapCalendar({
  CountdownProvider? countdownProvider,
  DateTime? initialDate,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => TodoProvider()),
      ChangeNotifierProvider(create: (_) => HabitProvider()),
      ChangeNotifierProvider(create: (_) => PomodoroProvider()),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => CloudSyncProvider()),
      ChangeNotifierProvider(create: (_) => CalendarProvider()),
      ChangeNotifierProvider(create: (_) => UserProvider()),
      ChangeNotifierProvider(
        create: (_) => countdownProvider ?? CountdownProvider(),
      ),
      ChangeNotifierProvider(create: (_) => NoteProvider()),
      ChangeNotifierProvider(create: (_) => AnniversaryProvider()),
      ChangeNotifierProvider(create: (_) => DiaryProvider()),
      ChangeNotifierProvider(create: (_) => GoalProvider()),
      ChangeNotifierProvider(create: (_) => CourseProvider()),
      ChangeNotifierProvider(create: (_) => AppLockProvider()),
      ChangeNotifierProvider(create: (_) => PreferencesProvider()),
      ChangeNotifierProvider(create: (_) => AchievementProvider()),
      ChangeNotifierProvider(create: (_) => ShareProvider()),
      ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
      ChangeNotifierProvider(create: (_) => NotificationService()),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => AiService()),
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ChangeNotifierProvider(create: (_) => LocationReminderProvider()),
      ChangeNotifierProvider(create: (_) => CalendarSyncProvider()),
      ChangeNotifierProvider(
        create: (_) => AppUpdateService(
          repo: 'dq52099/duoyi',
          currentVersion: AppVersion.name,
        ),
      ),
    ],
    child: MaterialApp(home: CalendarScreen(initialDate: initialDate)),
  );
}
