import 'dart:convert';
import 'dart:io';

import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/screens/mine_screen.dart';
import 'package:duoyi/screens/profile_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/widgets/cached_avatar_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrapMineHeaderTest({
  required AuthProvider auth,
  required UserProvider userProvider,
  AppUpdateService? appUpdateService,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => TodoProvider()),
      ChangeNotifierProvider(create: (_) => HabitProvider()),
      ChangeNotifierProvider(create: (_) => PomodoroProvider()),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider<UserProvider>.value(value: userProvider),
      ChangeNotifierProvider(create: (_) => NotificationService()),
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider(create: (_) => AiService()),
      ChangeNotifierProvider(create: (_) => AchievementProvider()),
      appUpdateService == null
          ? ChangeNotifierProvider(
              create: (_) => AppUpdateService(
                repo: 'dq52099/duoyi',
                currentVersion: AppVersion.name,
              ),
            )
          : ChangeNotifierProvider<AppUpdateService>.value(
              value: appUpdateService,
            ),
    ],
    child: const MaterialApp(home: MineScreen()),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('mine header stays stable when admin avatar syncs in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final auth = AuthProvider(
      initialState: const AuthState(
        userId: 'admin-1',
        username: 'admin',
        displayName: '后台管理员',
        token: 'token-1',
        isAdmin: true,
        coinBalance: 20,
      ),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((_) async => http.Response('not found', 404)),
      ),
    );
    final userProvider = UserProvider();
    await userProvider.applyAccountSnapshot(
      username: 'admin',
      displayName: '后台管理员',
      avatarInitials: '管',
    );

    await tester.pumpWidget(
      _wrapMineHeaderTest(auth: auth, userProvider: userProvider),
    );
    await tester.pump();

    final header = find.byKey(const ValueKey('mine_header_stable_box'));
    final userInfoRow = find.byKey(const ValueKey('mine_user_info_row'));
    final avatarRow = find.byKey(const ValueKey('mine_avatar_row'));
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).last,
    );
    final beforeHeader = tester.getRect(header);
    final beforeUserInfo = tester.getRect(userInfoRow);
    final beforeAvatar = tester.getRect(avatarRow);
    final beforeScrollOffset = scrollable.position.pixels;

    await auth.applyServerAccountSnapshot({
      'user': {
        'user_id': 'admin-1',
        'username': 'admin',
        'display_name': '后台管理员',
        'avatar': 'https://duoyi.test/uploads/admin.png',
        'is_admin': true,
        'coin_balance': 1888,
        'lifetime_coins': 1888,
      },
    }, reason: 'admin_return_profile_sync');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final afterHeader = tester.getRect(header);
    final afterUserInfo = tester.getRect(userInfoRow);
    final afterAvatar = tester.getRect(avatarRow);

    expect(find.byType(CachedAvatarImage), findsOneWidget);
    expect(afterHeader.height, closeTo(beforeHeader.height, 0.1));
    expect(afterUserInfo.height, closeTo(beforeUserInfo.height, 0.1));
    expect(afterAvatar.top, closeTo(beforeAvatar.top, 0.1));
    expect(afterAvatar.height, closeTo(beforeAvatar.height, 0.1));
    expect(scrollable.position.pixels, closeTo(beforeScrollOffset, 0.1));
  });

  testWidgets(
    'mine keeps restored scroll offset when admin avatar syncs back',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'admin-1',
          username: 'admin',
          displayName: '后台管理员',
          token: 'token-1',
          isAdmin: true,
          coinBalance: 20,
        ),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token-1',
          httpClient: MockClient((_) async => http.Response('not found', 404)),
        ),
      );
      final userProvider = UserProvider();
      await userProvider.applyAccountSnapshot(
        username: 'admin',
        displayName: '后台管理员',
        avatarInitials: '管',
      );

      await tester.pumpWidget(
        _wrapMineHeaderTest(auth: auth, userProvider: userProvider),
      );
      await tester.pump();

      Finder mineScrollable() => find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.restorationId == 'mine_screen_list',
      );

      final scrollable = tester.state<ScrollableState>(mineScrollable());
      final targetOffset = scrollable.position.maxScrollExtent < 36
          ? scrollable.position.maxScrollExtent
          : 36.0;
      scrollable.position.jumpTo(targetOffset);
      await tester.pump();

      final header = find.byKey(const ValueKey('mine_header_stable_box'));
      final avatarRow = find.byKey(const ValueKey('mine_avatar_row'));
      final beforeHeader = tester.getRect(header);
      final beforeAvatar = tester.getRect(avatarRow);
      final beforeScrollOffset = scrollable.position.pixels;

      Navigator.of(tester.element(find.byType(MineScreen))).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('管理员后台')),
        ),
      );
      await tester.pumpAndSettle();

      await auth.applyServerAccountSnapshot({
        'user': {
          'user_id': 'admin-1',
          'username': 'admin',
          'display_name': '后台管理员',
          'avatar': 'https://duoyi.test/uploads/admin.png',
          'is_admin': true,
          'coin_balance': 1888,
          'lifetime_coins': 1888,
        },
      }, reason: 'admin_return_from_route_avatar_sync');
      await tester.pump();

      Navigator.of(tester.element(find.text('管理员后台'))).pop();
      await tester.pumpAndSettle();

      final afterScrollable = tester.state<ScrollableState>(mineScrollable());
      final afterHeader = tester.getRect(header);
      final afterAvatar = tester.getRect(avatarRow);

      expect(find.byType(CachedAvatarImage), findsOneWidget);
      expect(afterScrollable.position.pixels, closeTo(beforeScrollOffset, 0.1));
      expect(afterHeader.height, closeTo(beforeHeader.height, 0.1));
      expect(afterAvatar.top, closeTo(beforeAvatar.top, 0.1));
      expect(afterAvatar.height, closeTo(beforeAvatar.height, 0.1));
    },
  );

  testWidgets('cached avatar reserves requested size while fallback is shown', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(240, 240);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Widget buildAvatar(String url) {
      return MaterialApp(
        home: Center(
          child: CachedAvatarImage(
            key: const ValueKey('stable_cached_avatar'),
            url: url,
            width: 64,
            height: 64,
            fallbackBuilder: (_) => const Text('管'),
          ),
        ),
      );
    }

    final avatar = find.byKey(const ValueKey('stable_cached_avatar'));

    await tester.pumpWidget(buildAvatar(''));
    expect(tester.getSize(avatar), const Size(64, 64));

    await tester.pumpWidget(
      buildAvatar('https://duoyi.test/uploads/admin.png'),
    );
    await tester.pump();
    expect(tester.getSize(avatar), const Size(64, 64));
  });

  testWidgets('local profile removes avatar URL editor', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final userProvider = UserProvider();
    await userProvider.updateProfile(
      username: '旧昵称',
      displayName: '旧显示名',
      email: 'old@example.com',
      avatarUrl: 'https://example.com/old.png',
      bio: '旧简介',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录账号'), findsOneWidget);
    expect(find.text('头像 URL、本地文件或文字'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '选择'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, '显示名'), '新显示名');
    await tester.enterText(find.widgetWithText(TextField, '本地昵称'), '新昵称');
    await tester.enterText(
      find.widgetWithText(TextField, '邮箱（仅本地展示，不用于登录或找回）'),
      'new@example.com',
    );
    await tester.enterText(find.widgetWithText(TextField, '简介'), '新的个人简介');
    await tester.tap(find.widgetWithText(FilledButton, '保存').last);
    await tester.pumpAndSettle();

    expect(userProvider.profile.username, '旧昵称');
    expect(userProvider.profile.displayName, '新显示名');
    expect(userProvider.profile.avatarUrl, 'https://example.com/old.png');
    expect(userProvider.profile.email, 'new@example.com');
    expect(userProvider.profile.bio, '新的个人简介');
  });

  test('profile email binding uses dedicated compact dialog flow', () {
    final source = File('lib/screens/profile_screen.dart').readAsStringSync();

    final accountBody = source.substring(
      source.indexOf('class _AccountProfileEditor'),
      source.indexOf('class _LocalProfileEditor'),
    );
    expect(source, contains('class _EmailBindingDialog'));
    expect(accountBody, contains('_showEmailBindingDialog'));
    expect(accountBody, isNot(contains('controller: _emailCodeCtrl')));
    expect(accountBody, isNot(contains('action: _sendButton(context)')));
    expect(accountBody, isNot(contains("const Text('绑定')")));
    expect(accountBody, contains("Text(I18n.tr('profile.email.binding'))"));
  });

  test('profile metric chips render their icons', () {
    final source = File('lib/screens/profile_screen.dart').readAsStringSync();
    final metricChip = source.substring(
      source.indexOf('class _ProfileMetricChip'),
      source.indexOf('class _ProfileSectionHeader'),
    );

    expect(metricChip, contains('Icon(icon'));
    expect(metricChip, contains('Semantics('));
    expect(metricChip, contains('Flexible('));
    expect(metricChip, contains('Text('));
  });

  test('profile avatar preview entry opens a full-screen viewer', () {
    final source = File('lib/screens/profile_screen.dart').readAsStringSync();
    final fullScreenStart = source.indexOf('class _ProfileAvatarFullScreen');
    final fullImageStart = source.indexOf('class _ProfileAvatarFullImage');
    final fullImageEnd = source.indexOf(
      'class _ChangePasswordDialog',
      fullImageStart,
    );
    expect(fullScreenStart, greaterThanOrEqualTo(0));
    expect(fullImageStart, greaterThan(fullScreenStart));
    expect(fullImageEnd, greaterThan(fullImageStart));

    final fullScreen = source.substring(fullScreenStart, fullImageEnd);
    expect(
      source,
      contains("key: const ValueKey('profile_avatar_preview_button')"),
    );
    expect(
      source,
      contains("key: const ValueKey('profile_avatar_edit_button')"),
    );
    expect(source, contains("message: '查看头像'"));
    expect(source, contains("message: '修改头像'"));
    expect(source, contains('MaterialPageRoute<void>('));
    expect(fullScreen, contains('return Scaffold('));
    expect(fullScreen, contains('backgroundColor: Colors.black'));
    expect(fullScreen, contains("title: const Text('头像')"));
    expect(fullScreen, contains('actions: ['));
    expect(fullScreen, contains("tooltip: '修改头像'"));
    expect(
      fullScreen,
      contains('WidgetsBinding.instance.addPostFrameCallback'),
    );
    expect(fullScreen, contains("tag: 'profile-avatar-preview'"));
    expect(fullScreen, contains('InteractiveViewer'));
    expect(fullScreen, contains('fit: BoxFit.contain'));
    expect(fullScreen, isNot(contains('AppDialog(')));
    expect(fullScreen, isNot(contains('showDialog(')));
    expect(fullScreen, isNot(contains('ClipOval')));
    expect(fullScreen, isNot(contains('BoxFit.cover')));
    expect(source, contains('String? _networkAvatarUrl(String value)'));
    expect(source, contains("pathSegments.first == 'api'"));
    expect(source, contains("pathSegments.first == 'uploads'"));
    expect(
      source,
      contains('if (_networkAvatarUrl(trimmed) != null) return null'),
    );
    expect(source, contains('final networkUrl = _networkAvatarUrl(value)'));
    expect(source, contains('networkUrl != null'));
  });

  test('profile actions keep fixed compact sizes and save flows editable', () {
    final source = File('lib/screens/profile_screen.dart').readAsStringSync();
    final auth = File('lib/providers/auth_provider.dart').readAsStringSync();

    expect(source, contains('const double _profileActionButtonHeight = 36'));
    expect(source, contains('const double _profileActionButtonWidth = 68'));
    expect(source, contains('const double _profileLongActionButtonWidth = 96'));
    expect(source, contains('double _profileInlineActionWidth'));
    expect(
      source,
      contains("key: const ValueKey('profile_action_field_stacked')"),
    );
    expect(
      source,
      contains("key: const ValueKey('profile_action_field_inline')"),
    );
    expect(source, contains("key: const ValueKey('profile_local_header_row')"));
    expect(
      source,
      contains("key: const ValueKey('profile_local_login_button')"),
    );
    expect(source, contains('width: _profileActionButtonWidth'));
    expect(source, contains('width: _profileLongActionButtonWidth'));
    expect(source, contains('height: _profileActionButtonHeight'));
    expect(source, contains('FittedBox('));
    expect(
      source,
      contains("child: Text(I18n.tr('action.save'), maxLines: 1)"),
    );
    expect(
      source,
      contains('titleTextStyle: appSecondaryRouteTitleTextStyle('),
    );
    expect(source, contains(').copyWith(color: Colors.white)'));
    expect(source, contains("I18n.tr('auth.send')"));
    expect(source, contains("I18n.tr('action.save')"));
    expect(source, contains('_showChangePasswordDialog'));
    expect(source, contains('changePassword('));
    expect(source, contains('await auth.updateProfile('));

    expect(auth, contains("'/api/me/profile'"));
    expect(auth, contains("'/api/auth/profile'"));
    expect(auth, contains("'/api/me/password'"));
    expect(auth, contains("'/api/auth/change-password'"));
  });

  test('account profile scopes provider subscriptions to displayed fields', () {
    final source = File('lib/screens/profile_screen.dart').readAsStringSync();
    final accountBody = source.substring(
      source.indexOf('class _AccountProfileEditor'),
      source.indexOf('class _LocalProfileEditor'),
    );

    expect(source, contains('context.select<AuthProvider, bool>'));
    expect(accountBody, contains('context.select<'));
    expect(accountBody, contains('AuthProvider,'));
    expect(accountBody, isNot(contains('context.select<UserProvider')));
    expect(accountBody, isNot(contains('profile.updatedAt')));
    expect(
      source,
      contains('String _avatarCacheKey(String? avatarUrl, String? userId)'),
    );
    expect(
      accountBody,
      contains('context.select<ThemeProvider, AvatarFrameReward>'),
    );
    expect(accountBody, isNot(contains('context.watch<AuthProvider>().state')));
    expect(
      accountBody,
      isNot(contains('context.watch<UserProvider>().profile')),
    );
    expect(accountBody, isNot(contains('context.watch<ThemeProvider>()')));
    expect(accountBody, isNot(contains('context.watch<AchievementProvider?>')));
  });

  testWidgets(
    'mine narrow header keeps long admin metadata and update badge visible',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'admin-long',
          username: 'admin-account-with-a-very-long-login-name',
          displayName: '后台管理员名字非常非常长需要省略显示',
          token: 'token-1',
          isAdmin: true,
          coinBalance: 123456789,
        ),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token-1',
          httpClient: MockClient((_) async => http.Response('not found', 404)),
        ),
      );
      final userProvider = UserProvider();
      await userProvider.applyAccountSnapshot(
        username: 'admin-account-with-a-very-long-login-name',
        displayName: '后台管理员名字非常非常长需要省略显示',
        avatarInitials: '管',
      );
      final appUpdateService =
          AppUpdateService(
            repo: 'dq52099/duoyi',
            currentVersion: AppVersion.name,
          )..debugSetUpdatePolicyForTest(
            latestVersion: '123.456.789-beta-build-extra-long',
          );

      await tester.pumpWidget(
        _wrapMineHeaderTest(
          auth: auth,
          userProvider: userProvider,
          appUpdateService: appUpdateService,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('mine_header_metadata_compact')),
        findsOneWidget,
      );
      expect(find.textContaining('时光币'), findsNothing);
      expect(find.text('管理员'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text(I18n.tr('mine.menu.support')),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text(I18n.tr('mine.menu.support')));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('检查更新'),
        700,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();

      expect(find.text('检查更新'), findsOneWidget);
      expect(find.textContaining('新版'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('local profile narrow header keeps login button inside card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final userProvider = UserProvider();
    await userProvider.updateProfile(
      username: 'local-user-with-a-very-long-name',
      displayName: '本地用户显示名非常非常长需要省略',
      email: 'local-user-with-a-long-email@example.com',
      bio: '本地资料简介也比较长',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AchievementProvider()),
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final header = find.byKey(const ValueKey('profile_local_header_row'));
    final login = find.byKey(const ValueKey('profile_local_login_button'));
    expect(header, findsOneWidget);
    expect(login, findsOneWidget);
    expect(
      tester.getRect(login).right,
      lessThanOrEqualTo(tester.getRect(header).right),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('email binding dialog stacks code field action on narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final auth = AuthProvider(
      initialState: const AuthState(
        userId: 'u-1',
        username: 'old-user',
        email: 'old@example.com',
        emailVerified: false,
        displayName: '旧昵称',
        token: 'token-1',
      ),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/me/email-code') {
            return http.Response(
              json.encode({'message': '验证码已发送，请查收邮箱'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
      ),
    );
    final userProvider = UserProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AchievementProvider()),
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '邮箱绑定'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('profile_action_field_stacked')),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, '邮箱验证码'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '发送'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('account profile long email labels are single-line ellipsized', () {
    final source = File('lib/screens/profile_screen.dart').readAsStringSync();
    final accountBody = source.substring(
      source.indexOf('class _AccountProfileEditor'),
      source.indexOf('class _LocalProfileEditor'),
    );

    expect(accountBody, contains('account.email?.isNotEmpty == true'));
    expect(accountBody, contains('account.email?.trim().isEmpty != false'));
    expect(accountBody, contains('maxLines: 1'));
    expect(accountBody, contains('overflow: TextOverflow.ellipsis'));
  });

  testWidgets('local profile avatar opens full screen preview', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final userProvider = UserProvider();
    await userProvider.updateProfile(
      username: '本地用户',
      displayName: '本地显示名',
      avatarUrl: '本',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AchievementProvider()),
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final editRect = tester.getRect(
      find.byKey(const ValueKey('profile_avatar_edit_button')),
    );
    expect(editRect.width, greaterThan(43.5));
    expect(editRect.height, greaterThan(43.5));

    final avatarButton = find.byKey(
      const ValueKey('profile_avatar_preview_button'),
    );
    await tester.tapAt(tester.getTopLeft(avatarButton) + const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('头像'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets(
    'account profile server-relative avatar uses full-screen network preview',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'u-1',
          username: 'stable-user',
          displayName: '服务器头像用户',
          avatar: '/api/uploads/avatars/u-1.png',
          token: 'token-1',
        ),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token-1',
          httpClient: MockClient((_) async => http.Response('not found', 404)),
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ChangeNotifierProvider(create: (_) => AchievementProvider()),
            ChangeNotifierProvider(create: (_) => UserProvider()),
          ],
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );

      Finder serverAvatarImage() => find.byWidgetPredicate((widget) {
        if (widget is! CachedAvatarImage) return false;
        return widget.url.contains('/api/uploads/avatars/u-1.png');
      });

      expect(serverAvatarImage(), findsOneWidget);

      final avatarButton = find.byKey(
        const ValueKey('profile_avatar_preview_button'),
      );
      await tester.tapAt(
        tester.getTopLeft(avatarButton) + const Offset(20, 20),
      );
      await tester.pumpAndSettle();

      expect(find.text('头像'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    },
  );

  testWidgets('account profile keeps username/avatar stable and binds email', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final requestBodies = <Map<String, dynamic>>[];
    final emailCodeRequests = <Map<String, dynamic>>[];
    final passwordRequests = <Map<String, dynamic>>[];
    var serverEmail = 'old@example.com';
    var serverEmailVerified = true;
    final auth = AuthProvider(
      initialState: const AuthState(
        userId: 'u-1',
        username: 'old-user',
        email: 'old@example.com',
        emailVerified: true,
        displayName: '旧昵称',
        avatar: 'https://example.com/old.png',
        bio: '旧简介',
        coinBalance: 88,
        lifetimeCoins: 144,
        token: 'token-1',
      ),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          if (request.method == 'PATCH' &&
              request.url.path == '/api/me/profile') {
            final body = json.decode(request.body) as Map<String, dynamic>;
            requestBodies.add(body);
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'old-user',
                'email': serverEmail,
                'email_verified': serverEmailVerified,
                'display_name': body['display_name'] ?? '旧昵称',
                'avatar': 'https://example.com/old.png',
                'bio': body['bio'] ?? '旧简介',
                'coin_balance': 88,
                'lifetime_coins': 144,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/me/email-code') {
            final body = json.decode(request.body) as Map<String, dynamic>;
            emailCodeRequests.add(body);
            return http.Response(
              json.encode({'message': '验证码已发送，请查收邮箱'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'PATCH' &&
              request.url.path == '/api/me/email') {
            final body = json.decode(request.body) as Map<String, dynamic>;
            requestBodies.add(body);
            serverEmail = (body['email'] ?? '').toString();
            serverEmailVerified = body.containsKey('code');
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'old-user',
                'email': serverEmail,
                'email_verified': serverEmailVerified,
                'display_name': '新昵称',
                'avatar': 'https://example.com/old.png',
                'bio': '新的账号简介',
                'coin_balance': 88,
                'lifetime_coins': 144,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/auth/change-password') {
            final body = json.decode(request.body) as Map<String, dynamic>;
            passwordRequests.add(body);
            return http.Response(
              json.encode({'ok': true}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
      ),
    );
    final userProvider = UserProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AchievementProvider()),
          ChangeNotifierProvider<UserProvider>.value(value: userProvider),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('时光币'), findsNothing);
    expect(find.text('头像 URL 或文字'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '上传'), findsNothing);
    final usernameField = tester.widget<TextField>(
      find.widgetWithText(TextField, '用户名'),
    );
    expect(usernameField.readOnly, isTrue);

    await tester.enterText(find.widgetWithText(TextField, '昵称'), '新昵称');
    expect(find.text('邮箱绑定'), findsAtLeastNWidgets(1));
    expect(find.widgetWithText(TextField, '邮箱'), findsNothing);
    expect(find.widgetWithText(TextField, '邮箱验证码'), findsNothing);
    expect(find.text('账号安全'), findsOneWidget);
    expect(find.text('修改登录密码'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '简介'), '新的账号简介');
    await tester.tap(find.widgetWithText(FilledButton, '保存').last);
    await tester.pumpAndSettle();

    expect(requestBodies.removeAt(0), {
      'display_name': '新昵称',
      'displayName': '新昵称',
      'bio': '新的账号简介',
    });
    expect(auth.state.username, 'old-user');
    expect(auth.state.avatar, 'https://example.com/old.png');

    await tester.tap(find.widgetWithText(TextButton, '邮箱绑定'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '邮箱'), findsOneWidget);
    expect(find.widgetWithText(TextField, '邮箱验证码'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, '邮箱'),
      'new@example.com',
    );
    await tester.enterText(find.widgetWithText(TextField, '邮箱验证码'), '123456');
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pump();
    expect(emailCodeRequests.single, {
      'email': 'new@example.com',
      'purpose': 'bind',
    });
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '邮箱绑定'));
    await tester.pumpAndSettle();

    expect(requestBodies.single, {
      'email': 'new@example.com',
      'code': '123456',
      'email_code': '123456',
      'emailCode': '123456',
    });
    expect(auth.state.email, 'new@example.com');
    expect(auth.state.emailVerified, isTrue);

    await tester.tap(find.text('修改登录密码'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '当前密码'), 'old-pass');
    await tester.enterText(find.widgetWithText(TextField, '新密码'), '123456');
    await tester.enterText(find.widgetWithText(TextField, '确认新密码'), '123456');
    await tester.tap(find.widgetWithText(FilledButton, '保存').last);
    await tester.pumpAndSettle();

    expect(passwordRequests.single, {
      'current_password': 'old-pass',
      'currentPassword': 'old-pass',
      'old_password': 'old-pass',
      'new_password': '123456',
      'newPassword': '123456',
      'password': '123456',
    });
    expect(auth.state.isLoggedIn, isFalse);
    expect(auth.client.token, isNull);
  });
}
