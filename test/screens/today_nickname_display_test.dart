import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/i18n.dart';
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
import 'package:duoyi/screens/today_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/models/user_profile.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首页问候语的昵称来源：账号显示名 → 本地显示名 → 用户名 → 本地化默认名。
///
/// 资料页保存昵称后「我的」页显示正确、首页却仍是登录账号名（admin）是本次
/// 修复的回归点；这里同时覆盖没有 AuthProvider 的降级、空白/占位兜底，以及
/// 登出/切号不能串前一个账号昵称。
Widget _wrapToday({
  required UserProvider userProvider,
  AuthProvider? authProvider,
  bool registerAuth = true,
  ThemeData? theme,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => TodoProvider()),
      ChangeNotifierProvider(create: (_) => HabitProvider()),
      ChangeNotifierProvider(create: (_) => PomodoroProvider()),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => CloudSyncProvider()),
      ChangeNotifierProvider(create: (_) => CalendarProvider()),
      ChangeNotifierProvider<UserProvider>.value(value: userProvider),
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
      if (registerAuth)
        if (authProvider == null)
          ChangeNotifierProvider(create: (_) => AuthProvider())
        else
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      // 夹具显式标记 AI 配置已就绪，避免首页等待未发起的配置加载后
      // pumpAndSettle 停在未知动画上。
      ChangeNotifierProvider(
        create: (_) =>
            AiService()..updateFromServerConfig({'ai_enabled': false}),
      ),
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
    child: MaterialApp(
      theme: theme ?? AppBrands.defaultBrand.theme,
      home: const TodayScreen(),
    ),
  );
}

String _greetingText(WidgetTester tester) {
  final greeting = tester.widget<Text>(
    find.byKey(const ValueKey('home_greeting')),
  );
  return greeting.data ?? greeting.textSpan?.toPlainText() ?? '';
}

AuthProvider _signedInAuth({
  required String username,
  String? displayName,
  bool loggedIn = true,
}) {
  return AuthProvider(
    initialState: AuthState(
      userId: 'user-$username',
      username: username,
      displayName: displayName,
      token: loggedIn ? 'test-session' : null,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('首页问候显示账号昵称，不再显示登录账号名', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final userProvider = UserProvider();
    await userProvider.updateProfile(username: 'admin', displayName: '本地昵称');
    final auth = _signedInAuth(username: 'admin', displayName: '小明');
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      _wrapToday(userProvider: userProvider, authProvider: auth),
    );
    await tester.pumpAndSettle();

    final greeting = _greetingText(tester);
    expect(greeting, contains('小明'));
    expect(greeting, isNot(contains('admin')));
    expect(greeting, isNot(contains('本地昵称')));
  });

  testWidgets('资料页保存昵称后首页立即更新（账号名保持不变）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final userProvider = UserProvider();
    await userProvider.updateProfile(username: 'admin', displayName: '');
    final auth = _signedInAuth(username: 'admin');
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      _wrapToday(userProvider: userProvider, authProvider: auth),
    );
    await tester.pumpAndSettle();
    expect(_greetingText(tester), contains('admin'));

    // 与 ProfileScreen 保存路径一致：先走 auth.updateProfile，再把账号
    // 显示名写回本地资料并 notify。
    await userProvider.updateProfile(username: 'admin', displayName: '小明');
    await tester.pumpAndSettle();

    expect(_greetingText(tester), contains('小明'));
    expect(userProvider.profile.username, 'admin');
    expect(userProvider.profile.displayName, '小明');
  });

  testWidgets('未注册 AuthProvider 时退回本地昵称（可空 watch 降级）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final userProvider = UserProvider();
    await userProvider.updateProfile(username: 'admin', displayName: '本地昵称');

    await tester.pumpWidget(
      _wrapToday(userProvider: userProvider, registerAuth: false),
    );
    await tester.pumpAndSettle();

    final greeting = _greetingText(tester);
    expect(greeting, contains('本地昵称'));
    expect(greeting, isNot(contains('admin')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('空白昵称回落到用户名，占位用户名回落到本地化默认名', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final blankNickname = UserProvider();
    await blankNickname.updateProfile(username: 'admin', displayName: '   ');
    await tester.pumpWidget(_wrapToday(userProvider: blankNickname));
    await tester.pumpAndSettle();
    expect(_greetingText(tester), contains('admin'));

    final defaultName = UserProvider();
    await defaultName.updateProfile(username: '用户', displayName: '');
    await tester.pumpWidget(_wrapToday(userProvider: defaultName));
    await tester.pumpAndSettle();
    expect(_greetingText(tester), endsWith(I18n.tr('profile.default_user')));
  });

  test('昵称解析：账号昵称 → 本地昵称 → 用户名 → 本地化默认名', () {
    final blank = UserProfile(username: 'admin', displayName: '   ');
    expect(blank.effectiveDisplayName('默认'), 'admin');
    expect(
      blank.effectiveDisplayName('默认', preferredDisplayName: ' 小明 '),
      '小明',
    );
    final local = UserProfile(username: 'admin', displayName: '本地昵称');
    expect(local.effectiveDisplayName('默认'), '本地昵称');
    expect(
      local.effectiveDisplayName('默认', preferredDisplayName: '账号昵称'),
      '账号昵称',
    );
    expect(
      UserProfile(
        username: UserProfile.defaultUsername,
      ).effectiveDisplayName('默认'),
      '默认',
    );
    expect(UserProfile(username: '  ').effectiveDisplayName('默认'), '默认');
    expect(
      UserProfile().effectiveDisplayName('默认', preferredUsername: '  admin  '),
      'admin',
    );
    expect(
      UserProfile(
        displayName: '本地昵称',
      ).effectiveDisplayName('默认', preferredUsername: 'admin'),
      '本地昵称',
    );
  });

  testWidgets('认证资料先到时使用账号名，不等待本地资料加载', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final userProvider = UserProvider();
    final auth = _signedInAuth(username: 'admin');
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      _wrapToday(userProvider: userProvider, authProvider: auth),
    );
    await tester.pumpAndSettle();
    expect(_greetingText(tester), contains('admin'));
  });

  testWidgets('登出或切号后首页不串前一个账号的昵称', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final userProvider = UserProvider();
    await userProvider.updateProfile(username: 'admin', displayName: '小明');
    final firstAuth = _signedInAuth(username: 'admin', displayName: '小明');
    addTearDown(firstAuth.dispose);

    await tester.pumpWidget(
      _wrapToday(userProvider: userProvider, authProvider: firstAuth),
    );
    await tester.pumpAndSettle();
    expect(_greetingText(tester), contains('小明'));

    // 登出：账号私有资料被清理，首页回到本地化默认名而不是旧昵称。
    await userProvider.clearAccountProfileCache();
    final loggedOut = _signedInAuth(username: 'admin', loggedIn: false);
    addTearDown(loggedOut.dispose);
    await tester.pumpWidget(
      _wrapToday(userProvider: userProvider, authProvider: loggedOut),
    );
    await tester.pumpAndSettle();
    final signedOutGreeting = _greetingText(tester);
    expect(signedOutGreeting, isNot(contains('小明')));
    expect(signedOutGreeting, contains(I18n.tr('profile.default_user')));

    // 切号：新账号的显示名覆盖本地残留，旧昵称不再出现。
    final secondAuth = _signedInAuth(username: 'bob', displayName: '小红');
    addTearDown(secondAuth.dispose);
    await userProvider.updateProfile(username: 'bob', displayName: '小红');
    await tester.pumpWidget(
      _wrapToday(userProvider: userProvider, authProvider: secondAuth),
    );
    await tester.pumpAndSettle();
    final switchedGreeting = _greetingText(tester);
    expect(switchedGreeting, contains('小红'));
    expect(switchedGreeting, isNot(contains('小明')));
    expect(switchedGreeting, isNot(contains('admin')));
  });
}
