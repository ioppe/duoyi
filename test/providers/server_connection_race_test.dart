import 'dart:async';
import 'dart:convert';

import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response jsonResponse(Object data) => http.Response(jsonEncode(data), 200);
ApiClient candidateClient(String url, String? token) => ApiClient(
  baseUrl: url,
  token: token,
  httpClient: MockClient(
    (request) async => jsonResponse(
      request.url.path == '/api/auth/me'
          ? {'user_id': 'new-user', 'avatar': '/api/uploads/avatars/new.png'}
          : {},
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final flow in ['password', 'email', 'register']) {
    test(
      'late $flow response cannot bind old credentials to a new server',
      () async {
        final pending = Completer<http.Response>();
        final auth = AuthProvider(
          client: ApiClient(
            baseUrl: 'https://old.test',
            httpClient: MockClient((_) => pending.future),
          ),
          clientFactory: candidateClient,
        );
        final operation = switch (flow) {
          'password' => auth.login(username: 'old', password: 'old-password'),
          'email' => auth.emailLogin(email: 'old@example.test', code: '123456'),
          _ => auth.register(username: 'old', password: 'old-password'),
        };
        final rejected = expectLater(operation, throwsA(isA<ApiException>()));
        await auth.loginWithToken(
          serverUrl: 'https://new.test',
          token: 'new-token',
        );
        expect(
          auth.state.avatar,
          'https://new.test/api/uploads/avatars/new.png',
        );
        pending.complete(
          jsonResponse({'user_id': 'old-user', 'token': 'old-secret'}),
        );
        await rejected;
        expect(auth.baseUrl, 'https://new.test');
        expect(auth.state.userId, 'new-user');
        expect(auth.client.token, 'new-token');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('auth_state'), isNot(contains('old-secret')));
      },
    );
  }

  test('account cleanup completes before the next login can commit', () async {
    final auth = AuthProvider(
      baseUrl: 'https://old.test',
      clientFactory: candidateClient,
    );
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    auth.onAccountIdentityChanging = (_, _) async {
      if (++calls == 1) {
        entered.complete();
        await release.future;
      }
    };
    final first = auth.loginWithToken(
      serverUrl: 'https://first.test',
      token: 'first-token',
    );
    final rejected = expectLater(first, throwsA(isA<ApiException>()));
    await entered.future;
    final second = auth.loginWithToken(
      serverUrl: 'https://second.test',
      token: 'second-token',
    );
    release.complete();
    await Future.wait([rejected, second]);
    expect(auth.baseUrl, 'https://second.test');
    expect(auth.state.token, 'second-token');
    expect(calls, 2);
  });

  test(
    'delayed current-token revocation never clears a newer session',
    () async {
      final deleted = Completer<http.Response>();
      final auth = AuthProvider(
        initialState: const AuthState(userId: 'old', token: 'old-token'),
        client: ApiClient(
          baseUrl: 'https://old.test',
          token: 'old-token',
          httpClient: MockClient((_) => deleted.future),
        ),
        clientFactory: candidateClient,
      );
      final revocation = auth.revokeAccessToken('old-device', current: true);
      await auth.loginWithToken(
        serverUrl: 'https://new.test',
        token: 'new-token',
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('todos', 'new-account-data');
      deleted.complete(jsonResponse({}));
      await revocation;
      expect(auth.state.token, 'new-token');
      expect(prefs.getString('todos'), 'new-account-data');
    },
  );

  test(
    'revoking the current token clears this session and its cached data',
    () async {
      final auth = AuthProvider(
        initialState: const AuthState(userId: 'user', token: 'pat'),
        client: ApiClient(
          baseUrl: 'https://server.test',
          token: 'pat',
          httpClient: MockClient((_) async => jsonResponse({})),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('todos', 'account-data');
      await auth.revokeAccessToken('this-device', current: true);
      expect(auth.state.isLoggedIn, isFalse);
      expect(prefs.getString('todos'), isNull);
    },
  );
}
