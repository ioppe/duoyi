import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart' show LocaleProvider;
import 'package:duoyi/core/desktop_tokens.dart';
import 'package:duoyi/core/web_target.dart';
import 'package:duoyi/l10n/generated/app_localizations.dart';
import 'package:duoyi/main.dart';
import 'package:duoyi/models/habit.dart';
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
import 'package:duoyi/screens/habit_screen.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/screens/today_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 宽屏外壳（NavigationRail）冒烟：
///
/// 外壳分派自运行时宽度判定（WebTarget.isWidescreenLayout，≥900 rail 壳）
/// 后不再依赖编译期档位；[WebTarget.debugDesktopWebBuild] 注入仅用于
/// 对齐桌面包的 tab 集过滤（隐藏小组件 tab）。视口写法沿用
/// today_mine_smoke_test 的 tester.view.physicalSize + devicePixelRatio。
Finder get _maxWidthBox =>
    find.byKey(const ValueKey('desktop_web_body_max_width'));

Widget _wrapShell(ThemeData theme, {HabitProvider? habitProvider}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => TodoProvider()),
      ChangeNotifierProvider(create: (_) => habitProvider ?? HabitProvider()),
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
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      theme: theme,
      home: MainShell(),
    ),
  );
}

Future<void> _pumpShellAt(
  WidgetTester tester,
  ThemeData theme,
  Size size, {
  HabitProvider? habitProvider,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrapShell(theme, habitProvider: habitProvider));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WebTarget.debugDesktopWebBuild = true;
  });
  tearDown(() {
    WebTarget.debugDesktopWebBuild = null;
  });

  testWidgets('1280x800 默认主题：桌面壳渲染今日主 tab，无溢出且内容限宽', (tester) async {
    await _pumpShellAt(
      tester,
      AppBrands.defaultBrand.theme,
      const Size(1280, 800),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(
      tester
          .widget<NavigationRail>(find.byType(NavigationRail))
          .destinations
          .map((item) => (item.label as Text).data),
      ['今日', '待办', '习惯', '我的'],
    );
    expect(tester.takeException(), isNull);

    final width = tester.getSize(_maxWidthBox).width;
    expect(width, greaterThan(0));
    expect(width, lessThanOrEqualTo(DesktopTokens.maxContentWidth));
  });

  testWidgets('1280x800 液态玻璃主题：切到待办主 tab，无溢出且卡片限宽', (tester) async {
    await _pumpShellAt(
      tester,
      AppBrands.liquidGlass.theme,
      const Size(1280, 800),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    tester.state<MainShellState>(find.byType(MainShell)).navigateTo(1);
    await tester.pumpAndSettle();

    expect(find.byType(TodoScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    final width = tester.getSize(_maxWidthBox).width;
    expect(width, greaterThan(0));
    expect(width, lessThanOrEqualTo(DesktopTokens.maxContentWidth));
  });

  testWidgets('1600x900 默认主题：内容宽度钉在 maxContentWidth', (tester) async {
    await _pumpShellAt(
      tester,
      AppBrands.defaultBrand.theme,
      const Size(1600, 900),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.getSize(_maxWidthBox).width, DesktopTokens.maxContentWidth);
    expect(tester.takeException(), isNull);
  });

  testWidgets('1280x800 未注入编译期档位（responsive 包）：宽度达阈值仍走 rail 壳', (tester) async {
    WebTarget.debugDesktopWebBuild = null;
    await _pumpShellAt(
      tester,
      AppBrands.defaultBrand.theme,
      const Size(1280, 800),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(
      tester.getSize(_maxWidthBox).width,
      lessThanOrEqualTo(DesktopTokens.maxContentWidth),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('1280x800 宽屏习惯今日打卡走双列懒构建网格', (tester) async {
    final habitProvider = HabitProvider();
    for (final id in ['a', 'b', 'c']) {
      await habitProvider.addHabit(
        Habit(id: id, name: '习惯$id', icon: Icons.book.codePoint.toString()),
      );
    }
    await _pumpShellAt(
      tester,
      AppBrands.defaultBrand.theme,
      const Size(1280, 800),
      habitProvider: habitProvider,
    );

    tester.state<MainShellState>(find.byType(MainShell)).navigateTo(2);
    await tester.pumpAndSettle();

    expect(find.byType(HabitScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('habit_today_checkin_sliver')),
      findsOneWidget,
    );
    expect(find.byType(SliverGrid), findsOneWidget);
    expect(find.byKey(const ValueKey('habit_checkin_card_a')), findsOneWidget);
    expect(find.byKey(const ValueKey('habit_checkin_card_c')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('800x600 宽度不足阈值：注入 desktop 档也回落移动底导航壳', (tester) async {
    await _pumpShellAt(
      tester,
      AppBrands.defaultBrand.theme,
      const Size(800, 600),
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .destinations
          .map((item) => (item as NavigationDestination).label),
      ['今日', '待办', '习惯', '我的'],
    );
    expect(find.byType(NavigationRail), findsNothing);
    expect(_maxWidthBox, findsNothing);
    expect(find.byType(TodayScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('web 底导航模糊降级档低于原生档（VM 上 kIsWeb=false 不降级）', () {
    expect(
      DesignTokens.navBarWebBlurSigma,
      lessThan(DesignTokens.navBarIosBlurSigma),
    );
    expect(WebTarget.shouldReduceNavBarBlur, isFalse);
  });
}
