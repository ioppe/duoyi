import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart'
    as account_cleaner;
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'UserProvider loadFromStorage clears profile when account key is removed',
    () async {
      final provider = UserProvider();
      await provider.updateProfile(
        username: 'admin',
        displayName: 'Admin',
        email: 'admin@example.com',
      );
      expect(provider.profile.username, 'admin');

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_profile');
      await provider.loadFromStorage();

      expect(provider.profile.username, '用户');
      expect(provider.profile.displayName, isEmpty);
      expect(provider.profile.email, isEmpty);
    },
  );

  test('UserProvider skips unchanged account profile notifications', () async {
    final provider = UserProvider();
    var notifications = 0;
    provider.addListener(() {
      notifications++;
    });

    await provider.applyAccountSnapshot(
      username: 'stable-user',
      displayName: '当前用户',
      email: 'me@example.com',
      emailVerified: true,
      avatarUrl: 'https://example.com/avatar.png',
      bio: '简介',
    );
    final updatedAt = provider.profile.updatedAt;

    await provider.applyAccountSnapshot(
      username: 'stable-user',
      displayName: '当前用户',
      email: 'me@example.com',
      emailVerified: true,
      avatarUrl: 'https://example.com/avatar.png',
      bio: '简介',
    );

    expect(notifications, 1);
    expect(provider.profile.updatedAt, updatedAt);
  });

  test(
    'bindEmail keeps immutable username/avatar out of profile payload',
    () async {
      Map<String, dynamic>? requestBody;
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'u-1',
          username: 'stable-user',
          avatar: 'https://example.com/stable.png',
          token: 'token-1',
        ),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token-1',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/me/email');
            requestBody = json.decode(request.body) as Map<String, dynamic>;
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'stable-user',
                'email': requestBody!['email'],
                'email_verified': true,
                'display_name': '旧昵称',
                'avatar': 'https://example.com/stable.png',
                'bio': '旧简介',
                'coin_balance': '42',
                'lifetime_coins': 108,
                'token': 'token-ignored',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      await auth.bindEmail(email: 'new@example.com', code: '123456');

      expect(requestBody, {
        'email': 'new@example.com',
        'code': '123456',
        'email_code': '123456',
        'emailCode': '123456',
      });
      expect(auth.state.username, 'stable-user');
      expect(auth.state.avatar, 'https://example.com/stable.png');
      expect(auth.state.coinBalance, 42);
      expect(auth.state.lifetimeCoins, 108);
      expect(auth.state.token, 'token-1');
    },
  );

  test('email code send and login use stable auth routes', () async {
    final paths = <String>[];
    final auth = AuthProvider(
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          final body = json.decode(request.body) as Map<String, dynamic>;
          if (request.url.path == '/api/auth/email-code') {
            expect(body, {'email': 'login@example.com', 'purpose': 'login'});
            return http.Response(
              json.encode({'ok': true}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/api/auth/email-login') {
            expect(body, {
              'email': 'login@example.com',
              'code': '654321',
              'email_code': '654321',
            });
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'stable-user',
                'email': 'login@example.com',
                'email_verified': true,
                'token': 'token-1',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
      ),
    );

    await auth.sendEmailCode(email: 'login@example.com');
    await auth.emailLogin(email: 'login@example.com', code: '654321');

    expect(paths, ['/api/auth/email-code', '/api/auth/email-login']);
    expect(auth.state.token, 'token-1');
  });

  test('email login retries compatible routes after 404', () async {
    final paths = <String>[];
    final auth = AuthProvider(
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          final body = json.decode(request.body) as Map<String, dynamic>;
          if (request.url.path == '/api/auth/login/email-code') {
            expect(body, {
              'email': 'login@example.com',
              'code': '654321',
              'email_code': '654321',
            });
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'stable-user',
                'email': 'login@example.com',
                'email_verified': true,
                'token': 'token-1',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('not found', 404);
        }),
      ),
    );

    await auth.emailLogin(email: 'login@example.com', code: '654321');

    expect(paths, [
      '/api/auth/email-login',
      '/api/auth/email/login',
      '/api/auth/login/email',
      '/api/auth/email-code-login',
      '/api/auth/login/email-code',
    ]);
    expect(auth.state.token, 'token-1');
  });

  test(
    'login notifies account identity changing before applying new account',
    () async {
      const adminState = AuthState(
        userId: 'admin-id',
        username: 'admin',
        token: 'admin-token',
        coinBalance: 999,
        lifetimeCoins: 1999,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_state', json.encode(adminState.toJson()));
      final cleanupCalls = <String>[];
      String? stateUserIdDuringCleanup;
      int? coinBalanceDuringCleanup;
      int? lifetimeCoinsDuringCleanup;
      String? persistedUserIdDuringCleanup;
      late final AuthProvider auth;
      auth = AuthProvider(
        initialState: adminState,
        client: ApiClient(
          baseUrl: 'http://127.0.0.1:1',
          token: 'admin-token',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/auth/login');
            return http.Response(
              json.encode({
                'user_id': 'test-id',
                'username': 'test',
                'token': 'test-token',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      auth.onAccountIdentityChanging = (previous, next) async {
        cleanupCalls.add('${previous.userId}->${next.userId}');
        stateUserIdDuringCleanup = auth.state.userId;
        coinBalanceDuringCleanup = auth.state.coinBalance;
        lifetimeCoinsDuringCleanup = auth.state.lifetimeCoins;
        final persisted =
            json.decode(prefs.getString('auth_state')!) as Map<String, dynamic>;
        persistedUserIdDuringCleanup = persisted['user_id'] as String?;
      };

      await auth.login(username: 'test', password: 'pw');

      final persisted =
          json.decode(prefs.getString('auth_state')!) as Map<String, dynamic>;
      expect(cleanupCalls, ['admin-id->test-id']);
      expect(stateUserIdDuringCleanup, 'admin-id');
      expect(coinBalanceDuringCleanup, 999);
      expect(lifetimeCoinsDuringCleanup, 1999);
      expect(persistedUserIdDuringCleanup, 'admin-id');
      expect(auth.state.userId, 'test-id');
      expect(auth.state.coinBalance, 0);
      expect(auth.state.lifetimeCoins, 0);
      expect(persisted['user_id'], 'test-id');
      expect(persisted['coin_balance'], 0);
      expect(persisted['lifetime_coins'], 0);
    },
  );

  test(
    'login parses root token with nested user and clears previous account first',
    () async {
      const adminState = AuthState(
        userId: 'admin-id',
        username: 'admin',
        token: 'admin-token',
        coinBalance: 999,
        lifetimeCoins: 1999,
      );
      final cleanupCalls = <String>[];
      final auth = AuthProvider(
        initialState: adminState,
        client: ApiClient(
          baseUrl: 'http://127.0.0.1:1',
          token: 'admin-token',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/auth/login');
            return http.Response(
              json.encode({
                'token': 'test-token',
                'user': {
                  'user_id': 'test-id',
                  'username': 'test',
                  'coin_balance': 12,
                  'lifetime_coins': 15,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      auth.onAccountIdentityChanging = (previous, next) async {
        cleanupCalls.add('${previous.userId}->${next.userId}');
        expect(next.isLoggedIn, isTrue);
        expect(next.token, 'test-token');
      };

      await auth.login(username: 'test', password: 'pw');

      expect(cleanupCalls, ['admin-id->test-id']);
      expect(auth.state.userId, 'test-id');
      expect(auth.state.token, 'test-token');
      expect(auth.state.coinBalance, 12);
      expect(auth.state.lifetimeCoins, 15);
    },
  );

  test(
    'login from signed-out state clears residual local account data first',
    () async {
      AuthState? previousDuringCleanup;
      AuthState? nextDuringCleanup;
      String? stateUserIdDuringCleanup;
      final auth = AuthProvider(
        client: ApiClient(
          baseUrl: 'http://127.0.0.1:1',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/auth/login');
            return http.Response(
              json.encode({
                'user_id': 'test-id',
                'username': 'test',
                'token': 'test-token',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      auth.onAccountIdentityChanging = (previous, next) async {
        previousDuringCleanup = previous;
        nextDuringCleanup = next;
        stateUserIdDuringCleanup = auth.state.userId;
      };

      await auth.login(username: 'test', password: 'pw');

      expect(previousDuringCleanup?.isLoggedIn, isFalse);
      expect(nextDuringCleanup?.userId, 'test-id');
      expect(stateUserIdDuringCleanup, isNull);
      expect(auth.state.userId, 'test-id');
    },
  );

  test(
    'login clears residual account data even without app cleanup callback',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'habits': json.encode(<Map<String, Object>>[
          {'id': 'admin-habit', 'name': 'admin habit'},
        ]),
        'active_brand': 'admin-theme',
        'theme_shop_state': json.encode(<String, Object>{
          'activeBrand': 'admin-theme',
          'updatedAt': '2026-06-08T00:00:00.000Z',
        }),
        'duoyi_virtual_rewards': json.encode(<String, Object>{
          'balance': 999,
          'lifetime': 1999,
        }),
        account_cleaner.AccountLocalDataCleaner.accountDataOwnerKey:
            'id:admin-id',
      });
      final auth = AuthProvider(
        client: ApiClient(
          baseUrl: 'http://127.0.0.1:1',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/auth/login');
            return http.Response(
              json.encode({
                'user_id': 'test-id',
                'username': 'test',
                'token': 'test-token',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      await auth.login(username: 'test', password: 'pw');

      final prefs = await SharedPreferences.getInstance();
      final persisted =
          json.decode(prefs.getString('auth_state')!) as Map<String, dynamic>;
      expect(auth.state.userId, 'test-id');
      expect(auth.state.coinBalance, 0);
      expect(persisted['user_id'], 'test-id');
      expect(prefs.getString('habits'), isNull);
      expect(prefs.getString('active_brand'), isNull);
      expect(prefs.getString('theme_shop_state'), isNull);
      expect(prefs.getString('duoyi_virtual_rewards'), isNull);
      expect(
        prefs.getString(
          account_cleaner.AccountLocalDataCleaner.accountDataOwnerKey,
        ),
        jsonEncode([auth.baseUrl, 'id:test-id']),
      );
    },
  );

  test(
    'new login token clears account-scoped data before applying session',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'auth_state': json.encode(
          const AuthState(
            userId: 'same-id',
            username: 'same-user',
            token: 'old-token',
            coinBalance: 999,
            lifetimeCoins: 1999,
          ).toJson(),
        ),
        'habits': json.encode(<Map<String, Object>>[
          {'id': 'old-habit', 'name': 'old habit'},
        ]),
        'active_brand': 'old-theme',
        'duoyi_virtual_rewards': json.encode(<String, Object>{
          'balance': 999,
          'lifetime': 1999,
        }),
      });
      final cleanupCalls = <String>[];
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'same-id',
          username: 'same-user',
          token: 'old-token',
          coinBalance: 999,
          lifetimeCoins: 1999,
        ),
        client: ApiClient(
          baseUrl: 'http://127.0.0.1:1',
          token: 'old-token',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/auth/login');
            return http.Response(
              json.encode({
                'user_id': 'same-id',
                'username': 'same-user',
                'token': 'new-token',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      auth.onAccountIdentityChanging = (previous, next) async {
        cleanupCalls.add('${previous.token}->${next.token}');
        await account_cleaner.AccountLocalDataCleaner.clearSharedPreferences();
      };

      await auth.login(username: 'same-user', password: 'pw');

      final prefs = await SharedPreferences.getInstance();
      expect(cleanupCalls, ['old-token->new-token']);
      expect(auth.state.userId, 'same-id');
      expect(auth.state.token, 'new-token');
      expect(auth.state.coinBalance, 0);
      expect(prefs.getString('habits'), isNull);
      expect(prefs.getString('active_brand'), isNull);
      expect(prefs.getString('duoyi_virtual_rewards'), isNull);
    },
  );

  test(
    'logout clears account data even without app cleanup callback',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'auth_state': json.encode(
          const AuthState(
            userId: 'admin-id',
            username: 'admin',
            token: 'admin-token',
            coinBalance: 999,
            lifetimeCoins: 1999,
          ).toJson(),
        ),
        'habits': json.encode(<Map<String, Object>>[
          {'id': 'admin-habit', 'name': 'admin habit'},
        ]),
        'active_brand': 'admin-theme',
        'duoyi_virtual_rewards': json.encode(<String, Object>{
          'balance': 999,
          'lifetime': 1999,
        }),
        account_cleaner.AccountLocalDataCleaner.accountDataOwnerKey:
            'id:admin-id',
      });
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'admin-id',
          username: 'admin',
          token: 'admin-token',
          coinBalance: 999,
          lifetimeCoins: 1999,
        ),
        client: ApiClient(
          baseUrl: 'http://127.0.0.1:1',
          token: 'admin-token',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/auth/logout');
            return http.Response(
              json.encode({'ok': true}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      await auth.logout();

      final prefs = await SharedPreferences.getInstance();
      expect(auth.state.isLoggedIn, isFalse);
      expect(prefs.getString('auth_state'), isNull);
      expect(prefs.getString('habits'), isNull);
      expect(prefs.getString('active_brand'), isNull);
      expect(prefs.getString('duoyi_virtual_rewards'), isNull);
      expect(
        prefs.getString(
          account_cleaner.AccountLocalDataCleaner.accountDataOwnerKey,
        ),
        isNull,
      );
    },
  );

  test(
    'loadFromStorage clears unowned residual account data before signed-in user',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'auth_state': json.encode(
          const AuthState(
            userId: 'test-id',
            username: 'test',
            token: 'test-token',
            coinBalance: 0,
            lifetimeCoins: 0,
          ).toJson(),
        ),
        'user_profile': json.encode(<String, Object>{
          'username': 'admin',
          'email': 'admin@example.com',
        }),
        'habits': json.encode(<Map<String, Object>>[
          {'id': 'admin-habit', 'name': 'admin habit'},
        ]),
        'active_brand': 'admin-theme',
        'duoyi_virtual_rewards': json.encode(<String, Object>{
          'balance': 999,
          'lifetime': 1999,
        }),
      });
      var cleanupCalled = false;
      final auth = AuthProvider(
        client: ApiClient(
          baseUrl: 'http://127.0.0.1:1',
          token: 'test-token',
          httpClient: MockClient((_) async {
            return http.Response('{}', 200);
          }),
        ),
      );
      auth.onAccountIdentityChanging = (_, _) async {
        cleanupCalled = true;
        await account_cleaner.AccountLocalDataCleaner.clearSharedPreferences();
      };

      await auth.loadFromStorage(refreshServerConfig: false);

      final prefs = await SharedPreferences.getInstance();
      expect(cleanupCalled, isTrue);
      expect(auth.state.userId, 'test-id');
      expect(auth.state.token, 'test-token');
      expect(prefs.getString('habits'), isNull);
      expect(prefs.getString('active_brand'), isNull);
      expect(prefs.getString('duoyi_virtual_rewards'), isNull);
      expect(
        prefs.getString(
          account_cleaner.AccountLocalDataCleaner.accountDataOwnerKey,
        ),
        jsonEncode([auth.baseUrl, 'id:test-id']),
      );
    },
  );

  test('loadFromStorage clears account data when signed out', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'habits': json.encode(<Map<String, Object>>[
        {'id': 'admin-habit', 'name': 'admin habit'},
      ]),
      'active_brand': 'admin-theme',
      'duoyi_virtual_rewards': json.encode(<String, Object>{
        'balance': 999,
        'lifetime': 1999,
      }),
      account_cleaner.AccountLocalDataCleaner.accountDataOwnerKey:
          'id:admin-id',
    });
    final auth = AuthProvider();

    await auth.loadFromStorage(refreshServerConfig: false);

    final prefs = await SharedPreferences.getInstance();
    expect(auth.state.isLoggedIn, isFalse);
    expect(prefs.getString('habits'), isNull);
    expect(prefs.getString('active_brand'), isNull);
    expect(prefs.getString('duoyi_virtual_rewards'), isNull);
    expect(
      prefs.getString(
        account_cleaner.AccountLocalDataCleaner.accountDataOwnerKey,
      ),
      isNull,
    );
  });

  test('login is blocked when account cleanup fails', () async {
    final auth = AuthProvider(
      client: ApiClient(
        baseUrl: 'http://127.0.0.1:1',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/auth/login');
          return http.Response(
            json.encode({
              'user_id': 'test-id',
              'username': 'test',
              'token': 'test-token',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    auth.onAccountIdentityChanging = (_, _) async {
      throw StateError('cleanup failed');
    };

    await expectLater(
      auth.login(username: 'test', password: 'pw'),
      throwsA(isA<StateError>()),
    );

    expect(auth.state.isLoggedIn, isFalse);
  });

  test(
    'email login notifies account identity changing before applying new account',
    () async {
      final cleanupCalls = <String>[];
      String? stateUserIdDuringCleanup;
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'admin-id',
          username: 'admin',
          token: 'admin-token',
          coinBalance: 999,
        ),
        client: ApiClient(
          baseUrl: 'http://127.0.0.1:1',
          token: 'admin-token',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/auth/email-login');
            return http.Response(
              json.encode({
                'user_id': 'test-id',
                'email': 'test@example.com',
                'token': 'test-token',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      auth.onAccountIdentityChanging = (previous, next) async {
        cleanupCalls.add('${previous.userId}->${next.userId}');
        stateUserIdDuringCleanup = auth.state.userId;
      };

      await auth.emailLogin(email: 'test@example.com', code: '654321');

      expect(cleanupCalls, ['admin-id->test-id']);
      expect(stateUserIdDuringCleanup, 'admin-id');
      expect(auth.state.userId, 'test-id');
      expect(auth.state.coinBalance, 0);
    },
  );

  test(
    'register notifies account identity changing before applying new account',
    () async {
      final cleanupCalls = <String>[];
      String? stateUserIdDuringCleanup;
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'admin-id',
          username: 'admin',
          token: 'admin-token',
          coinBalance: 999,
        ),
        client: ApiClient(
          baseUrl: 'http://127.0.0.1:1',
          token: 'admin-token',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/auth/register');
            return http.Response(
              json.encode({
                'user_id': 'test-id',
                'username': 'test',
                'token': 'test-token',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      auth.onAccountIdentityChanging = (previous, next) async {
        cleanupCalls.add('${previous.userId}->${next.userId}');
        stateUserIdDuringCleanup = auth.state.userId;
      };

      await auth.register(username: 'test', password: 'pw');

      expect(cleanupCalls, ['admin-id->test-id']);
      expect(stateUserIdDuringCleanup, 'admin-id');
      expect(auth.state.userId, 'test-id');
      expect(auth.state.coinBalance, 0);
    },
  );

  test('binding email code uses authenticated me route', () async {
    Map<String, dynamic>? requestBody;
    final auth = AuthProvider(
      initialState: const AuthState(token: 'token-1'),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/me/email-code');
          requestBody = json.decode(request.body) as Map<String, dynamic>;
          return http.Response(
            json.encode({'message': '验证码已发送，请查收邮箱'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await auth.sendBindEmailCode(email: 'new@example.com');

    expect(requestBody, {'email': 'new@example.com', 'purpose': 'bind'});
  });

  test(
    'profile email and avatar APIs retry compatible routes after 404',
    () async {
      final paths = <String>[];
      final auth = AuthProvider(
        initialState: const AuthState(token: 'token-1'),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token-1',
          httpClient: MockClient((request) async {
            paths.add('${request.method} ${request.url.path}');
            if (request.url.path == '/api/me/email-code/send') {
              return http.Response(
                json.encode({'message': 'ok'}),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.url.path == '/api/auth/profile/avatar') {
              return http.Response(
                json.encode({
                  'user_id': 'u-1',
                  'username': 'stable-user',
                  'avatar': '/api/uploads/avatars/u-1.png',
                  'token': 'ignored',
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response('not found', 404);
          }),
        ),
      );

      await auth.sendBindEmailCode(email: 'new@example.com');
      await auth.uploadAvatarBytes(
        filename: 'avatar.png',
        bytes: Uint8List.fromList([137, 80, 78, 71]),
      );

      expect(paths, contains('POST /api/me/email-code'));
      expect(paths, contains('POST /api/me/email-code/send'));
      expect(paths, contains('POST /api/me/avatar'));
      expect(paths, contains('POST /api/me/profile/avatar'));
      expect(paths, contains('POST /api/auth/profile/avatar'));
      expect(
        auth.state.avatar,
        'https://duoyi.test/api/uploads/avatars/u-1.png',
      );
    },
  );

  test('avatar upload uses RE0-compatible me avatar route first', () async {
    final auth = AuthProvider(
      initialState: const AuthState(token: 'token-1'),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/me/avatar');
          return http.Response(
            json.encode({
              'user_id': 'u-1',
              'username': 'stable-user',
              'avatar': 'https://duoyi.test/api/uploads/avatars/u-1.png',
              'token': 'ignored',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await auth.uploadAvatarBytes(
      filename: 'avatar.png',
      bytes: Uint8List.fromList([137, 80, 78, 71]),
    );

    expect(auth.state.avatar, 'https://duoyi.test/api/uploads/avatars/u-1.png');
    expect(auth.state.token, 'token-1');
  });

  test(
    'avatar upload success syncs state, prefs and profile callback',
    () async {
      final syncedStates = <AuthState>[];
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'u-1',
          username: 'stable-user',
          avatar: 'https://duoyi.test/api/uploads/avatars/old.png',
          token: 'token-1',
        ),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token-1',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/me/avatar');
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'stable-user',
                'avatar': '/api/uploads/avatars/new.png',
                'token': 'ignored',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      auth.onAccountProfileChanged = (state) async {
        syncedStates.add(state);
      };

      await auth.uploadAvatarBytes(
        filename: 'avatar.png',
        bytes: Uint8List.fromList([137, 80, 78, 71]),
      );
      final prefs = await SharedPreferences.getInstance();
      final persisted =
          json.decode(prefs.getString('auth_state')!) as Map<String, dynamic>;

      expect(
        auth.state.avatar,
        'https://duoyi.test/api/uploads/avatars/new.png',
      );
      expect(auth.state.token, 'token-1');
      expect(persisted['avatar'], auth.state.avatar);
      expect(persisted['token'], 'token-1');
      expect(syncedStates.single.avatar, auth.state.avatar);
    },
  );

  test(
    'avatar upload failure keeps previous state and prefs visible',
    () async {
      const previous = AuthState(
        userId: 'u-1',
        username: 'stable-user',
        avatar: 'https://duoyi.test/api/uploads/avatars/old.png',
        token: 'token-1',
      );
      SharedPreferences.setMockInitialValues({
        'auth_state': json.encode(previous.toJson()),
      });
      var profileCallbackCalled = false;
      final auth = AuthProvider(
        initialState: previous,
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token-1',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/me/avatar');
            return http.Response(
              json.encode({'detail': 'avatar image is too large'}),
              413,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      auth.onAccountProfileChanged = (_) async {
        profileCallbackCalled = true;
      };

      await expectLater(
        auth.uploadAvatarBytes(
          filename: 'avatar.png',
          bytes: Uint8List.fromList([137, 80, 78, 71]),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('avatar image is too large'),
          ),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      final persisted =
          json.decode(prefs.getString('auth_state')!) as Map<String, dynamic>;

      expect(auth.state.avatar, previous.avatar);
      expect(auth.state.token, previous.token);
      expect(persisted['avatar'], previous.avatar);
      expect(persisted['token'], previous.token);
      expect(profileCallbackCalled, isFalse);
    },
  );

  test(
    'avatar upload does not duplicate api prefix when base URL includes /api',
    () async {
      final paths = <String>[];
      final auth = AuthProvider(
        initialState: const AuthState(token: 'token-1'),
        client: ApiClient(
          baseUrl: 'https://duoyi.test/api/',
          token: 'token-1',
          httpClient: MockClient((request) async {
            paths.add(request.url.toString());
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'stable-user',
                'avatar': '/api/uploads/avatars/u-1.png',
                'token': 'ignored',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      await auth.uploadAvatarBytes(
        filename: 'avatar.png',
        bytes: Uint8List.fromList([137, 80, 78, 71]),
      );

      expect(paths.single, 'https://duoyi.test/api/me/avatar');
      expect(
        auth.state.avatar,
        'https://duoyi.test/api/uploads/avatars/u-1.png',
      );
      expect(auth.state.avatar, isNot(contains('/api/api/')));
    },
  );

  test('avatar upload retries compatible multipart field names', () async {
    final uploadFields = <String>[];
    final auth = AuthProvider(
      initialState: const AuthState(username: 'stable-user', token: 'token-1'),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/me/avatar');
          final body = utf8.decode(request.bodyBytes, allowMalformed: true);
          final field = body.contains('name="file"') ? 'file' : 'avatar';
          uploadFields.add(field);
          if (field == 'avatar') {
            return http.Response(
              json.encode({'detail': '头像文件不能为空'}),
              400,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            json.encode({
              'user_id': 'u-1',
              'identifier': 'stable-user',
              'emailVerified': true,
              'displayName': '兼容昵称',
              'avatarUrl': '/api/uploads/avatars/u-1.png',
              'permissions': ['feedback.manage'],
              'token': 'ignored',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await auth.uploadAvatarBytes(
      filename: 'avatar.png',
      bytes: Uint8List.fromList([137, 80, 78, 71]),
    );

    expect(uploadFields, ['avatar', 'file']);
    expect(auth.state.username, 'stable-user');
    expect(auth.state.emailVerified, isTrue);
    expect(auth.state.displayName, '兼容昵称');
    expect(auth.state.avatar, 'https://duoyi.test/api/uploads/avatars/u-1.png');
    expect(auth.state.adminPermissions, ['feedback.manage']);
    expect(auth.state.token, 'token-1');
  });

  test('updateProfile omits untouched profile fields', () async {
    Map<String, dynamic>? requestBody;
    final auth = AuthProvider(
      initialState: const AuthState(
        userId: 'u-1',
        username: 'stable-user',
        email: 'old@example.com',
        displayName: '旧昵称',
        bio: '旧简介',
        token: 'token-1',
      ),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          requestBody = json.decode(request.body) as Map<String, dynamic>;
          return http.Response(
            json.encode({
              'user_id': 'u-1',
              'username': 'stable-user',
              'email': 'old@example.com',
              'display_name': requestBody!['display_name'],
              'bio': requestBody!['bio'],
              'token': 'ignored',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await auth.updateProfile(displayName: '新昵称', bio: '');

    expect(requestBody, {
      'display_name': '新昵称',
      'displayName': '新昵称',
      'bio': '',
    });
    expect(auth.state.email, 'old@example.com');
  });

  test('updateProfile syncs saved profile into state and prefs', () async {
    final syncedStates = <AuthState>[];
    Map<String, dynamic>? requestBody;
    final auth = AuthProvider(
      initialState: const AuthState(
        userId: 'u-1',
        username: 'stable-user',
        email: 'old@example.com',
        emailVerified: false,
        displayName: 'Old name',
        avatar: 'https://duoyi.test/api/uploads/avatars/old.png',
        bio: 'Old bio',
        token: 'token-1',
      ),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(request.url.path, '/api/me/profile');
          requestBody = json.decode(request.body) as Map<String, dynamic>;
          return http.Response(
            json.encode({
              'profile': {
                'user_id': 'u-1',
                'username': 'stable-user',
                'email': 'new@example.com',
                'email_verified': true,
                'display_name': 'New name',
                'avatar': '/api/uploads/avatars/new.png',
                'bio': 'New bio',
                'coin_balance': 77,
                'lifetime_coins': 101,
                'token': 'ignored',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    auth.onAccountProfileChanged = (state) async {
      syncedStates.add(state);
    };

    await auth.updateProfile(displayName: 'New name', bio: 'New bio');
    final prefs = await SharedPreferences.getInstance();
    final persisted =
        json.decode(prefs.getString('auth_state')!) as Map<String, dynamic>;

    expect(requestBody, {
      'display_name': 'New name',
      'displayName': 'New name',
      'bio': 'New bio',
    });
    expect(auth.state.displayName, 'New name');
    expect(auth.state.bio, 'New bio');
    expect(auth.state.email, 'new@example.com');
    expect(auth.state.emailVerified, isTrue);
    expect(auth.state.avatar, 'https://duoyi.test/api/uploads/avatars/new.png');
    expect(auth.state.coinBalance, 77);
    expect(auth.state.lifetimeCoins, 101);
    expect(auth.state.token, 'token-1');
    expect(persisted['display_name'], auth.state.displayName);
    expect(persisted['bio'], auth.state.bio);
    expect(persisted['email'], auth.state.email);
    expect(persisted['email_verified'], isTrue);
    expect(persisted['avatar'], auth.state.avatar);
    expect(persisted['coin_balance'], 77);
    expect(persisted['lifetime_coins'], 101);
    expect(persisted['token'], 'token-1');
    expect(syncedStates.single.displayName, auth.state.displayName);
    expect(syncedStates.single.avatar, auth.state.avatar);
  });

  test('refreshMe retries compatible me route after 404', () async {
    final paths = <String>[];
    final auth = AuthProvider(
      initialState: const AuthState(token: 'token-1'),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/api/me') {
            return http.Response(
              json.encode({
                'user_id': 'u-1',
                'username': 'stable-user',
                'email': 'me@example.com',
                'display_name': '当前用户',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            json.encode({'detail': 'Not Found'}),
            404,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await auth.refreshMe();

    expect(paths, ['/api/auth/me', '/api/me']);
    expect(auth.state.displayName, '当前用户');
    expect(auth.state.token, 'token-1');
  });

  test(
    'refreshMe coalesces concurrent requests and throttles repeats',
    () async {
      var requests = 0;
      final response = Completer<http.Response>();
      final auth = AuthProvider(
        initialState: const AuthState(token: 'token-1'),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token-1',
          httpClient: MockClient((request) async {
            expect(request.url.path, '/api/auth/me');
            requests++;
            return response.future;
          }),
        ),
      );

      final first = auth.refreshMe(reason: 'startup');
      final second = auth.refreshMe(reason: 'cloud_sync_account_snapshot');
      await Future<void>.delayed(Duration.zero);

      expect(requests, 1);
      response.complete(
        http.Response(
          json.encode({
            'user_id': 'u-1',
            'username': 'stable-user',
            'display_name': '当前用户',
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await Future.wait([first, second]);

      await auth.refreshMe(reason: 'foreground_resume');

      expect(requests, 1);
      expect(auth.state.displayName, '当前用户');
    },
  );

  test(
    'theme shop apply updates global auth state, prefs and profile callback',
    () async {
      Map<String, dynamic>? requestBody;
      final syncedStates = <AuthState>[];
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'u-1',
          username: 'stable-user',
          coinBalance: 200,
          lifetimeCoins: 200,
          token: 'token-1',
        ),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token-1',
          httpClient: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/api/theme-shop/apply');
            requestBody = json.decode(request.body) as Map<String, dynamic>;
            return http.Response(
              json.encode({
                'status': 'ok',
                'coin_balance': 60,
                'lifetime_coins': 200,
                'virtual_rewards': {
                  'balance': 60,
                  'lifetime': 200,
                  'ledger': [
                    {
                      'id': 'theme-shop:1',
                      'title': '兑换主题：从零开始',
                      'coins': -140,
                      'awardedAt': '2026-06-01T00:00:00Z',
                    },
                  ],
                  'updatedAt': '2026-06-01T00:00:00Z',
                },
                'theme_shop_state': {
                  'activeBrand': 're0',
                  'unlockedBrandIds': ['defaultBrand', 're0'],
                  'updatedAt': '2026-06-01T00:00:00Z',
                },
                'user': {
                  'user_id': 'u-1',
                  'username': 'stable-user',
                  'coin_balance': 60,
                  'lifetime_coins': 200,
                },
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      auth.onAccountProfileChanged = (state) async {
        syncedStates.add(state);
      };

      final res = await auth.applyThemeShopItem(
        itemType: 'brand',
        itemId: 're0',
        title: '兑换主题：从零开始',
      );
      final prefs = await SharedPreferences.getInstance();
      final persisted =
          json.decode(prefs.getString('auth_state')!) as Map<String, dynamic>;

      expect(requestBody, {
        'item_type': 'brand',
        'item_id': 're0',
        'title': '兑换主题：从零开始',
        'activate': true,
      });
      expect(res['theme_shop_state']['activeBrand'], 're0');
      expect(auth.state.coinBalance, 60);
      expect(auth.state.lifetimeCoins, 200);
      expect(auth.state.token, 'token-1');
      expect(persisted['coin_balance'], 60);
      expect(persisted['lifetime_coins'], 200);
      expect(syncedStates.single.coinBalance, 60);
    },
  );

  test(
    'theme shop apply falls back to virtual rewards balance for auth coins',
    () async {
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'u-1',
          username: 'stable-user',
          coinBalance: 200,
          lifetimeCoins: 200,
          token: 'token-1',
        ),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token-1',
          httpClient: MockClient((request) async {
            expect(request.url.path, '/api/theme-shop/apply');
            return http.Response(
              json.encode({
                'status': 'ok',
                'virtual_rewards': {
                  'balance': 60,
                  'lifetime': 200,
                  'updatedAt': '2026-06-01T00:00:00Z',
                },
                'theme_shop_state': {
                  'activeBrand': 're0',
                  'unlockedBrandIds': ['defaultBrand', 're0'],
                  'updatedAt': '2026-06-01T00:00:00Z',
                },
                'user': {'user_id': 'u-1', 'username': 'stable-user'},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      await auth.applyThemeShopItem(
        itemType: 'brand',
        itemId: 're0',
        title: '兑换主题：从零开始',
      );
      final prefs = await SharedPreferences.getInstance();
      final persisted =
          json.decode(prefs.getString('auth_state')!) as Map<String, dynamic>;

      expect(auth.state.coinBalance, 60);
      expect(auth.state.lifetimeCoins, 200);
      expect(persisted['coin_balance'], 60);
      expect(persisted['lifetime_coins'], 200);
    },
  );

  test(
    'stale refreshMe response cannot override a newer account mutation',
    () async {
      final meResponse = Completer<http.Response>();
      var meRequested = false;
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'u-1',
          username: 'stable-user',
          coinBalance: 200,
          lifetimeCoins: 200,
          token: 'token-1',
        ),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token-1',
          httpClient: MockClient((request) async {
            if (request.url.path == '/api/auth/me') {
              meRequested = true;
              return meResponse.future;
            }
            if (request.url.path == '/api/theme-shop/apply') {
              return http.Response(
                json.encode({
                  'status': 'ok',
                  'user': {
                    'user_id': 'u-1',
                    'username': 'stable-user',
                    'coin_balance': 60,
                    'lifetime_coins': 200,
                  },
                  'virtual_rewards': {
                    'balance': 60,
                    'lifetime': 200,
                    'updatedAt': '2026-06-01T00:00:01Z',
                  },
                  'theme_shop_state': {
                    'activeBrand': 're0',
                    'unlockedBrandIds': ['defaultBrand', 're0'],
                    'updatedAt': '2026-06-01T00:00:01Z',
                  },
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              json.encode({'detail': 'Not Found'}),
              404,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      final refreshFuture = auth.refreshMe(reason: 'test_stale_refresh');
      await Future<void>.delayed(Duration.zero);
      expect(meRequested, isTrue);

      await auth.applyThemeShopItem(
        itemType: 'brand',
        itemId: 're0',
        title: '兑换主题：从零开始',
      );
      meResponse.complete(
        http.Response(
          json.encode({
            'user_id': 'u-1',
            'username': 'stable-user',
            'coin_balance': 200,
            'lifetime_coins': 200,
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await refreshFuture;

      expect(auth.state.coinBalance, 60);
      expect(auth.state.lifetimeCoins, 200);
    },
  );

  for (final rejection in [
    (status: 401, detail: 'token expired'),
    (status: 403, detail: 'Account disabled'),
  ]) {
    test(
      'refreshMe clears local session on ${rejection.status} ${rejection.detail}',
      () async {
        const previous = AuthState(
          userId: 'u-1',
          username: 'stable-user',
          token: 'token-1',
        );
        SharedPreferences.setMockInitialValues({
          'auth_state': json.encode(previous.toJson()),
        });
        var loggedOut = false;
        final auth = AuthProvider(
          initialState: previous,
          client: ApiClient(
            baseUrl: 'https://duoyi.test',
            token: 'token-1',
            httpClient: MockClient((request) async {
              expect(request.url.path, '/api/auth/me');
              return http.Response(
                json.encode({'detail': rejection.detail}),
                rejection.status,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        );
        auth.onAccountLoggedOut = () async {
          loggedOut = true;
        };

        await auth.refreshMe();
        final prefs = await SharedPreferences.getInstance();

        expect(auth.state.isLoggedIn, isFalse);
        expect(auth.client.token, isNull);
        expect(prefs.getString('auth_state'), isNull);
        expect(loggedOut, isTrue);
      },
    );
  }

  test(
    'logout retries compatible routes and always clears local state',
    () async {
      final paths = <String>[];
      var loggedOut = false;
      String? stateUserIdDuringLogout;
      String? persistedUserIdDuringLogout;
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'u-1',
          username: 'stable-user',
          token: 'token-1',
        ),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token-1',
          httpClient: MockClient((request) async {
            paths.add('${request.method} ${request.url.path}');
            if (request.url.path == '/api/me/logout') {
              return http.Response(
                json.encode({'ok': true}),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              json.encode({'detail': 'Not Found'}),
              404,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_state', json.encode(auth.state.toJson()));
      auth.onAccountLoggedOut = () async {
        loggedOut = true;
        stateUserIdDuringLogout = auth.state.userId;
        final persisted =
            json.decode(prefs.getString('auth_state')!) as Map<String, dynamic>;
        persistedUserIdDuringLogout = persisted['user_id'] as String?;
      };

      await auth.logout();

      expect(paths, [
        'POST /api/auth/logout',
        'POST /api/logout',
        'POST /api/me/logout',
      ]);
      expect(auth.state.isLoggedIn, isFalse);
      expect(auth.state.username, isNull);
      expect(auth.client.token, isNull);
      expect(prefs.getString('auth_state'), isNull);
      expect(loggedOut, isTrue);
      expect(stateUserIdDuringLogout, 'u-1');
      expect(persistedUserIdDuringLogout, 'u-1');
    },
  );

  test(
    'logout falls back after primary route misses and clears cache',
    () async {
      final paths = <String>[];
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'u-1',
          username: 'stable-user',
          token: 'token-1',
        ),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token-1',
          httpClient: MockClient((request) async {
            paths.add('${request.method} ${request.url.path}');
            if (request.url.path == '/api/logout') {
              return http.Response(
                json.encode({'ok': true}),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              json.encode({'detail': 'Not Found'}),
              404,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_state', json.encode(auth.state.toJson()));

      await auth.logout();

      expect(paths, ['POST /api/auth/logout', 'POST /api/logout']);
      expect(auth.state.isLoggedIn, isFalse);
      expect(auth.client.token, isNull);
      expect(prefs.getString('auth_state'), isNull);
    },
  );

  test(
    'changePassword retries RE0-compatible me password route first',
    () async {
      final paths = <String>[];
      Map<String, dynamic>? requestBody;
      final auth = AuthProvider(
        initialState: const AuthState(token: 'token-1'),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token-1',
          httpClient: MockClient((request) async {
            paths.add(request.url.path);
            requestBody = json.decode(request.body) as Map<String, dynamic>;
            if (request.url.path == '/api/me/password') {
              return http.Response(
                json.encode({'ok': true}),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              json.encode({'detail': 'Not Found'}),
              404,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_state', json.encode(auth.state.toJson()));

      await auth.changePassword(
        currentPassword: 'oldpass123',
        newPassword: 'newpass456',
      );

      expect(paths, ['/api/me/password']);
      expect(requestBody, {
        'current_password': 'oldpass123',
        'currentPassword': 'oldpass123',
        'old_password': 'oldpass123',
        'new_password': 'newpass456',
        'newPassword': 'newpass456',
        'password': 'newpass456',
      });
      expect(auth.state.isLoggedIn, isFalse);
      expect(auth.client.token, isNull);
      expect(prefs.getString('auth_state'), isNull);
    },
  );

  test(
    'changePassword failure exposes backend message and keeps payload',
    () async {
      final paths = <String>[];
      Map<String, dynamic>? requestBody;
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'u-1',
          username: 'stable-user',
          token: 'token-1',
        ),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token-1',
          httpClient: MockClient((request) async {
            paths.add(request.url.path);
            requestBody = json.decode(request.body) as Map<String, dynamic>;
            return http.Response(
              json.encode({'detail': 'current password is invalid'}),
              400,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      Object? error;
      try {
        await auth.changePassword(
          currentPassword: 'oldpass123',
          newPassword: 'newpass456',
        );
      } catch (e) {
        error = e;
      }

      expect(paths, ['/api/me/password']);
      expect(requestBody, {
        'current_password': 'oldpass123',
        'currentPassword': 'oldpass123',
        'old_password': 'oldpass123',
        'new_password': 'newpass456',
        'newPassword': 'newpass456',
        'password': 'newpass456',
      });
      expect(
        error,
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('current password is invalid'),
        ),
      );
      expect(
        userVisibleApiError(error!, fallbackMessage: 'password change failed'),
        contains('current password is invalid'),
      );
      expect(auth.state.token, 'token-1');
      expect(auth.client.token, 'token-1');
    },
  );

  test('password reset request retries compatible routes after 404', () async {
    final paths = <String>[];
    final auth = AuthProvider(
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          final body = json.decode(request.body) as Map<String, dynamic>;
          if (request.url.path == '/api/auth/password-reset/request') {
            expect(body, {
              'username': 'reset@example.com',
              'account': 'reset@example.com',
              'identifier': 'reset@example.com',
              'email': 'reset@example.com',
            });
            return http.Response(
              json.encode({'ok': true}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            json.encode({'detail': 'Not Found'}),
            404,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final result = await auth.requestPasswordReset(
      account: 'reset@example.com',
    );

    expect(paths, [
      '/api/auth/password-reset',
      '/api/auth/password-reset/request',
    ]);
    expect(result['ok'], isTrue);
  });

  test('password reset confirm retries compatible routes after 404', () async {
    final paths = <String>[];
    Map<String, dynamic>? requestBody;
    final auth = AuthProvider(
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          requestBody = json.decode(request.body) as Map<String, dynamic>;
          if (request.url.path == '/api/auth/reset-password/confirm') {
            return http.Response(
              json.encode({'ok': true}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            json.encode({'detail': 'Not Found'}),
            404,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await auth.confirmPasswordReset(
      email: 'reset@example.com',
      code: '123456',
      newPassword: 'newpass456',
    );

    expect(paths, [
      '/api/auth/password-reset/confirm',
      '/api/auth/reset-password/confirm',
    ]);
    expect(requestBody, {
      'password': 'newpass456',
      'new_password': 'newpass456',
      'account': 'reset@example.com',
      'identifier': 'reset@example.com',
      'email': 'reset@example.com',
      'code': '123456',
    });
  });

  test(
    'register requires username and sends optional email verification',
    () async {
      final requests = <Map<String, dynamic>>[];
      final auth = AuthProvider(
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          httpClient: MockClient((request) async {
            if (request.method == 'POST' &&
                request.url.path == '/api/auth/register') {
              final body = json.decode(request.body) as Map<String, dynamic>;
              requests.add(body);
              return http.Response(
                json.encode({
                  'user_id': 'u-2',
                  'username': body['username'],
                  'email': body['email'],
                  'email_verified': true,
                  'display_name': body['display_name'],
                  'avatar': '',
                  'bio': '',
                  'token': 'token-2',
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response('not found', 404);
          }),
        ),
      );

      await auth.register(
        username: 'new-user',
        password: 'pass123456',
        email: 'new@example.com',
        emailCode: '654321',
        displayName: '新用户',
      );

      expect(requests.single, {
        'username': 'new-user',
        'password': 'pass123456',
        'email': 'new@example.com',
        'email_code': '654321',
        'display_name': '新用户',
      });
      expect(auth.state.username, 'new-user');
      expect(auth.state.emailVerified, isTrue);
    },
  );

  test('registration email verification defaults to required', () {
    final auth = AuthProvider();

    expect(auth.registrationEmailRequired, isTrue);
  });

  test(
    'email code sent false without dev code throws and does not succeed',
    () async {
      final auth = AuthProvider(
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          httpClient: MockClient((request) async {
            expect(request.url.path, '/api/auth/email-code');
            return http.Response(
              json.encode({'ok': true, 'sent': false, 'detail': 'SMTP 未完整配置'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      await expectLater(
        auth.sendEmailCode(email: 'login@example.com'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('SMTP 未完整配置'),
          ),
        ),
      );
    },
  );

  test('business 404 is not swallowed as a route fallback', () async {
    final paths = <String>[];
    final auth = AuthProvider(
      initialState: const AuthState(token: 'token-1'),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token-1',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/api/me/email-code') {
            return http.Response(
              json.encode({'detail': '邮箱未绑定'}),
              404,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            json.encode({'detail': 'unexpected fallback'}),
            500,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await expectLater(
      auth.sendBindEmailCode(email: 'new@example.com'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('邮箱未绑定'),
        ),
      ),
    );
    expect(paths, ['/api/me/email-code']);
  });
}
