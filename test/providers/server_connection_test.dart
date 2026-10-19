import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/server_connection.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response response(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Web defaults to current origin even when a build server is configured',
    () {
      expect(
        ServerConnection.defaultBaseUrl(
          isWeb: true,
          configuredUrl: 'https://other.test',
        ),
        '',
      );
      expect(
        ServerConnection.defaultBaseUrl(
          isWeb: false,
          configuredUrl: 'https://other.test',
        ),
        'https://other.test',
      );
    },
  );

  test('server URL is canonical and rejects credential-bearing URLs', () {
    expect(
      ServerConnection.normalize(' https://EXAMPLE.test:443/api/ '),
      'https://example.test',
    );
    expect(
      ServerConnection.normalize('http://127.0.0.1:8000/duoyi/'),
      'http://127.0.0.1:8000/duoyi',
    );
    for (final value in [
      '',
      'example.test',
      'ftp://example.test',
      'https://name:secret@example.test',
      'https://example.test?token=secret',
      'https://example.test/#secret',
      'https://exa mple.test',
      'https://example.test:0',
    ]) {
      expect(
        () => ServerConnection.normalize(value),
        throwsFormatException,
        reason: value,
      );
    }
  });

  test(
    'token login verifies the candidate, isolates same user ID across servers, and persists connection',
    () async {
      final requests = <http.Request>[];
      final auth = AuthProvider(
        baseUrl: 'https://old.test',
        initialState: const AuthState(userId: 'same-id', token: 'same-token'),
        clientFactory: (url, token) => ApiClient(
          baseUrl: url,
          token: token,
          httpClient: MockClient((request) async {
            requests.add(request);
            if (request.url.path == '/api/auth/me') {
              return response({'user_id': 'same-id', 'username': 'phone'});
            }
            return response({'backup_enabled': true});
          }),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('todos', '[{"id":"old-server-task"}]');
      var cleanup = false;
      auth.onAccountIdentityChanging = (_, _) async {
        expect(auth.baseUrl, 'https://old.test');
        cleanup = true;
      };
      await auth.loginWithToken(
        serverUrl: 'https://new.test/api/',
        token: ' same-token ',
      );
      expect(cleanup, isTrue);
      expect(auth.baseUrl, 'https://new.test');
      expect(auth.client.token, 'same-token');
      expect(prefs.getString('todos'), isNull);
      expect(
        prefs.getString(AuthProvider.serverUrlStorageKey),
        'https://new.test',
      );
      expect(
        prefs.getString(AuthProvider.sessionServerStorageKey),
        'https://new.test',
      );
      expect(
        prefs.getString(AccountLocalDataCleaner.accountDataOwnerKey),
        jsonEncode(['https://new.test', 'id:same-id']),
      );
      expect(requests.map((r) => r.url.host).toSet(), {'new.test'});
      expect(requests.first.headers['Authorization'], 'Bearer same-token');

      await prefs.setString('todos', '[{"id":"new-server-task"}]');
      final restored = AuthProvider();
      await restored.loadFromStorage(refreshServerConfig: false);
      expect(restored.baseUrl, 'https://new.test');
      expect(restored.state.token, 'same-token');
      expect(prefs.getString('todos'), contains('new-server-task'));
    },
  );

  test(
    'failed token validation preserves current credentials and local account data',
    () async {
      final original = ApiClient(
        baseUrl: 'https://old.test',
        token: 'old-token',
      );
      final auth = AuthProvider(
        client: original,
        initialState: const AuthState(userId: 'old-user', token: 'old-token'),
        clientFactory: (url, token) => ApiClient(
          baseUrl: url,
          token: token,
          httpClient: MockClient(
            (_) async => response({'detail': 'Invalid token'}, 401),
          ),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('todos', 'old-data');
      await expectLater(
        auth.loginWithToken(serverUrl: 'https://new.test', token: 'bad-token'),
        throwsA(isA<ApiException>()),
      );
      expect(auth.client, same(original));
      expect(auth.state.token, 'old-token');
      expect(prefs.getString('todos'), 'old-data');
      expect(prefs.getString(AuthProvider.serverUrlStorageKey), isNull);
    },
  );

  test(
    'stored credentials bound to another server are never restored',
    () async {
      SharedPreferences.setMockInitialValues({
        AuthProvider.serverUrlStorageKey: 'https://new.test',
        AuthProvider.sessionServerStorageKey: 'https://old.test',
        'auth_state': jsonEncode(
          const AuthState(userId: 'same', token: 'old-secret').toJson(),
        ),
        'todos': 'old-data',
        AccountLocalDataCleaner.accountDataOwnerKey: jsonEncode([
          'https://old.test',
          'id:same',
        ]),
      });
      final auth = AuthProvider();
      await auth.loadFromStorage(refreshServerConfig: false);
      expect(auth.baseUrl, 'https://new.test');
      expect(auth.state.isLoggedIn, isFalse);
      expect(auth.client.token, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('todos'), isNull);
    },
  );

  test(
    'late config and expired-session responses from old server cannot change new connection',
    () async {
      final config = Completer<http.Response>();
      final me = Completer<http.Response>();
      final auth = AuthProvider(
        initialState: const AuthState(userId: 'old', token: 'old-token'),
        client: ApiClient(
          baseUrl: 'https://old.test',
          token: 'old-token',
          httpClient: MockClient(
            (request) =>
                request.url.path == '/api/config' ? config.future : me.future,
          ),
        ),
        clientFactory: (url, token) => ApiClient(
          baseUrl: url,
          token: token,
          httpClient: MockClient(
            (request) async => response(
              request.url.path == '/api/config'
                  ? {'backup_enabled': false}
                  : {'user_id': 'new'},
            ),
          ),
        ),
      );
      final oldConfig = auth.refreshServerConfigFromServer();
      final oldMe = auth.refreshMe(force: true);
      await auth.loginWithToken(
        serverUrl: 'https://new.test',
        token: 'new-token',
      );
      config.complete(response({'backup_enabled': true}));
      me.complete(response({'detail': 'Invalid token'}, 401));
      await Future.wait([oldConfig, oldMe]);
      expect(auth.state.userId, 'new');
      expect(auth.state.token, 'new-token');
      expect(auth.serverConfig['backup_enabled'], isFalse);
    },
  );
}
