import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:duoyi/main.dart';
import 'package:duoyi/core/app_text_scale.dart';
import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';

void main() {
  testWidgets('App renders default bottom tabs: 今日/待办/习惯/专注/我的', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => TodoProvider()),
          ChangeNotifierProvider(create: (_) => HabitProvider()),
          ChangeNotifierProvider(create: (_) => PomodoroProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => FocusRoomProvider()),
          ChangeNotifierProvider(create: (_) => CustomFocusSoundProvider()),
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
        child: const DuoyiApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('待办'), findsWidgets);
    expect(find.text('习惯'), findsWidgets);
    expect(find.text('今日'), findsWidgets);
    expect(find.text('专注'), findsWidgets);
    expect(find.text('我的'), findsWidgets);
    expect(find.text('小组件'), findsNothing);
    expect(find.text('日历'), findsNothing);

    // MaterialApp.builder 把应用字号乘进 MediaQuery.textScaler，主页面随之缩放。
    expect(
      MediaQuery.textScalerOf(tester.element(find.byType(MainShell))).scale(20),
      closeTo(20 * AppTextScale.defaultScale, 1e-9),
    );

    final preferences = Provider.of<PreferencesProvider>(
      tester.element(find.byType(MainShell)),
      listen: false,
    );
    await tester.runAsync(() => preferences.setTextScale(AppTextScale.large));
    await tester.pump();
    expect(
      MediaQuery.textScalerOf(tester.element(find.byType(MainShell))).scale(20),
      closeTo(20 * AppTextScale.large, 1e-9),
    );
  });
}
