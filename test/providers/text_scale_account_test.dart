import 'dart:convert';

import 'package:duoyi/core/app_text_scale.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async => 'UTC';
  });
  tearDown(() => LocalTimezoneResolver.debugSystemTimeZoneReader = null);

  Future<void> bind(
    PreferencesProvider p,
    String user, {
    String server = 'https://duoyi.test',
  }) => p.bindTextScaleToAccount(serverUrl: server, userId: user);

  Future<(AuthProvider, PreferencesProvider)> start() async {
    final p = PreferencesProvider();
    ApiClient client(String url, String? token) => ApiClient(
      baseUrl: url,
      token: token,
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          final name = (jsonDecode(request.body) as Map)['username'];
          if (name == 'fail') return http.Response('{"detail":"invalid"}', 401);
          return http.Response(
            jsonEncode({
              'user_id': name,
              'username': name,
              'token': 'token-$name',
            }),
            200,
          );
        }
        return http.Response('{"ok":true}', 200);
      }),
    );
    final auth = AuthProvider(
      baseUrl: 'https://duoyi.test',
      clientFactory: client,
    );
    Future<void> clear() async {
      await AccountLocalDataCleaner.clearSharedPreferences();
      p.resetLocalState();
      await p.loadFromStorage();
      await AccountLocalDataCleaner.clearSharedPreferences();
    }

    auth.onAccountLoggedOut = clear;
    auth.onAccountIdentityChanging = (_, _) => clear();
    auth.onAccountProfileChanged = (state) async {
      if (state.isLoggedIn) {
        await p.bindTextScaleToAccount(
          serverUrl: auth.baseUrl,
          userId: state.userId,
        );
      }
    };
    await auth.loadFromStorage(refreshServerConfig: false);
    await p.loadFromStorage();
    if (auth.state.isLoggedIn) {
      await bind(p, auth.state.userId!, server: auth.baseUrl);
    }
    return (auth, p);
  }

  test('旧版本首次绑定保留原字号，八档都能保存并重新载入', () async {
    SharedPreferences.setMockInitialValues({'pref_text_scale': 1.15});
    final p = PreferencesProvider();
    await p.loadFromStorage();
    await bind(p, 'a');
    expect(p.textScale, 1.15);
    for (final value in AppTextScale.options) {
      await p.setTextScale(value);
      final restarted = PreferencesProvider();
      await restarted.loadFromStorage();
      await bind(restarted, 'a');
      expect(restarted.textScale, value);
      restarted.dispose();
    }
    p.dispose();
  });

  test('真实登录链连续两次冷启动、退出后重登同账号都保留字号', () async {
    var (auth, p) = await start();
    await auth.configureServer('https://duoyi.test');
    await auth.login(username: 'a', password: 'pw');
    await p.setTextScale(1.75);
    auth.dispose();
    p.dispose();
    for (var index = 0; index < 2; index++) {
      (auth, p) = await start();
      expect(auth.state.userId, 'a');
      expect(p.textScale, 1.75);
      if (index == 0) {
        auth.dispose();
        p.dispose();
      }
    }
    await auth.logout();
    expect(p.textScale, 1.75);
    auth.dispose();
    p.dispose();
    (auth, p) = await start();
    expect(p.textScale, 1.75);
    await auth.login(username: 'a', password: 'pw');
    expect(p.textScale, 1.75);
    auth.dispose();
    p.dispose();
  });

  test('A 换 B 只重置字号，其他设备偏好保留，登录失败不重置', () async {
    final (auth, p) = await start();
    await auth.configureServer('https://duoyi.test');
    await auth.login(username: 'a', password: 'pw');
    await p.setTextScale(.85);
    await p.setDateFormat('dd/MM/yyyy');
    await p.setHaptic(false);
    await expectLater(
      auth.login(username: 'fail', password: 'pw'),
      throwsA(isA<ApiException>()),
    );
    expect(p.textScale, .85);
    await auth.logout();
    await auth.login(username: 'b', password: 'pw');
    expect(p.textScale, AppTextScale.standard);
    expect(p.dateFormat, 'dd/MM/yyyy');
    expect(p.haptic, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getDouble('pref_text_scale'),
      1,
    );
    await p.setTextScale(1.6);
    await auth.logout();
    await auth.configureServer('https://other.test');
    await auth.login(username: 'b', password: 'pw');
    expect(p.textScale, 1);
    auth.dispose();
    p.dispose();
  });

  test('空账号和普通残留清理不删除字号归属', () async {
    final p = PreferencesProvider();
    await bind(p, 'a');
    await p.setTextScale(1.45);
    final owner = p.textScaleOwner;
    await AccountLocalDataCleaner.clearSharedPreferences();
    p.resetLocalState();
    expect(p.textScale, 1.45);
    await p.loadFromStorage();
    await p.bindTextScaleToAccount(
      serverUrl: 'https://duoyi.test',
      userId: null,
    );
    expect(p.textScaleOwner, owner);
    expect(p.textScale, 1.45);
    p.dispose();
  });

  test('保存排队后换号以重置为准，换号前排队的旧草稿不能写入新账号', () async {
    final p = PreferencesProvider();
    await bind(p, 'a');
    final oldWrite = p.setTextScale(1.75);
    final switchToB = bind(p, 'b');
    await Future.wait([oldWrite, switchToB]);
    expect(p.textScale, 1);
    final switchToC = bind(p, 'c');
    final stale = p.setTextScale(1.9);
    final rejected = expectLater(stale, throwsStateError);
    await switchToC;
    await rejected;
    expect(p.textScale, 1);
    expect(
      (await SharedPreferences.getInstance()).getDouble('pref_text_scale'),
      1,
    );
    await p.setTextScale(1.3);
    await p.loadFromStorage();
    expect(p.textScale, 1.3);
    p.dispose();
  });
}
