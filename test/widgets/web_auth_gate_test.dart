import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/login_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/web_auth_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _cached = AuthState(
  userId: 'one',
  username: 'admin',
  token: 'test-session',
  isAdmin: true,
);
Map<String, Object?> _me({String id = 'one', bool admin = false}) => {
  'user_id': id,
  'username': admin ? 'admin' : 'ordinary',
  'is_admin': admin,
  'admin_permissions': admin ? ['*'] : [],
};
http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

AuthProvider _auth(
  Future<http.Response> Function(http.Request) handle, {
  AuthState initial = _cached,
}) {
  final transport = MockClient((request) {
    if (request.url.path == '/api/config') return Future.value(_json({}));
    return handle(request);
  });
  ApiClient client(String base, String? token) =>
      ApiClient(baseUrl: base, token: token, httpClient: transport);
  return AuthProvider(
    baseUrl: 'https://server.test',
    initialState: initial,
    client: client('https://server.test', initial.token),
    clientFactory: client,
  );
}

Widget _app(AuthProvider auth, {bool enabled = true, WidgetBuilder? shell}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        builder: (context, child) =>
            WebAuthGate(enabled: enabled, child: child!),
        home: Builder(
          builder: shell ?? (_) => const Scaffold(body: Text('private-shell')),
        ),
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });

  testWidgets('anonymous web never mounts account routes', (tester) async {
    var builds = 0;
    final auth = _auth((_) async => _json({}), initial: const AuthState());
    await tester.pumpWidget(
      _app(
        auth,
        shell: (_) {
          builds++;
          return const Text('private-data');
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(builds, 0);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('private-data'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(builds, 0);
  });

  testWidgets(
    'restored session waits for server and replaces cached admin role',
    (tester) async {
      final response = Completer<http.Response>();
      var builds = 0;
      final auth = _auth((request) {
        expect(request.url.path, '/api/auth/me');
        expect(request.headers['Authorization'], 'Bearer test-session');
        return response.future;
      });
      await tester.pumpWidget(
        _app(
          auth,
          shell: (_) {
            builds++;
            return const Scaffold(body: Text('private-shell'));
          },
        ),
      );
      await tester.pump();
      expect(builds, 0);
      expect(find.text(I18n.tr('auth.session.checking')), findsOneWidget);
      response.complete(_json(_me()));
      await tester.pumpAndSettle();
      expect(builds, greaterThan(0));
      expect(auth.state.username, 'ordinary');
      expect(auth.state.isAdmin, isFalse);
      expect(auth.state.adminPermissions, isEmpty);
      expect(find.text('private-shell'), findsOneWidget);
    },
  );

  testWidgets(
    'expired restored token returns to login without exposing a frame',
    (tester) async {
      var builds = 0;
      final auth = _auth((_) async => _json({'detail': 'Invalid token'}, 401));
      await tester.pumpWidget(
        _app(
          auth,
          shell: (_) {
            builds++;
            return const Text('private-data');
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(auth.state.isLoggedIn, isFalse);
      expect(builds, 0);
      expect(find.byType(LoginScreen), findsOneWidget);
    },
  );

  testWidgets(
    'connection failure blocks entry and retry revalidates the session',
    (tester) async {
      var attempts = 0;
      final auth = _auth((_) async {
        attempts++;
        return attempts == 1
            ? _json({'detail': 'Unavailable'}, 503)
            : _json(_me());
      });
      await tester.pumpWidget(_app(auth));
      await tester.pumpAndSettle();
      expect(find.text('private-shell'), findsNothing);
      expect(find.text(I18n.tr('auth.session.unavailable')), findsOneWidget);
      expect(auth.state.isLoggedIn, isTrue);
      await tester.tap(find.text(I18n.tr('action.retry')));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text('private-shell'), findsOneWidget);
    },
  );

  for (final invalid in <Map<String, Object?>>[
    {},
    _me(id: 'different-account'),
  ]) {
    testWidgets(
      'malformed or mismatched server identity cannot unlock routes: $invalid',
      (tester) async {
        final auth = _auth((_) async => _json(invalid));
        await tester.pumpWidget(_app(auth));
        await tester.pumpAndSettle();
        expect(find.text('private-shell'), findsNothing);
        expect(find.text(I18n.tr('auth.session.unavailable')), findsOneWidget);
        expect(auth.state.userId, 'one');
      },
    );
  }

  testWidgets(
    'logout removes pushed private routes and a new login starts at home',
    (tester) async {
      final auth = _auth((request) async {
        if (request.url.path == '/api/auth/login') {
          return _json({..._me(id: 'two'), 'token': 'second-session'});
        }
        if (request.url.path == '/api/auth/me') {
          return _json(
            _me(
              id: request.headers['Authorization'] == 'Bearer second-session'
                  ? 'two'
                  : 'one',
            ),
          );
        }
        return _json({});
      });
      await tester.pumpWidget(
        _app(
          auth,
          shell: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const Scaffold(body: Text('old-private-detail')),
                ),
              ),
              child: const Text('open-detail'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open-detail'));
      await tester.pumpAndSettle();
      expect(find.text('old-private-detail'), findsOneWidget);
      await auth.logout();
      await tester.pumpAndSettle();
      expect(find.text('old-private-detail'), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      // A subsequent authenticated account receives a fresh application Navigator.
      await auth.login(username: 'ordinary', password: 'test-password');
      await tester.pumpAndSettle();
      expect(auth.state.userId, 'two');
      expect(find.text('open-detail'), findsOneWidget);
      expect(find.text('old-private-detail'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late verification response after logout cannot reopen the app', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final auth = _auth(
      (request) async =>
          request.url.path == '/api/auth/me' ? response.future : _json({}),
    );
    await tester.pumpWidget(_app(auth));
    await tester.pump();
    await auth.logout();
    await tester.pumpAndSettle();
    response.complete(_json(_me(admin: true)));
    await tester.pumpAndSettle();
    expect(auth.state.isLoggedIn, isFalse);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('private-shell'), findsNothing);
  });

  testWidgets(
    'password login at web entry unlocks shell without popping the entry route',
    (tester) async {
      var logins = 0;
      final response = Completer<http.Response>();
      final auth = _auth((request) async {
        if (request.url.path == '/api/auth/login') {
          logins++;
          return response.future;
        }
        return _json(_me());
      }, initial: const AuthState());
      await tester.pumpWidget(_app(auth));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('auth-account')),
        'ordinary',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        'test-password',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pump();
      expect(logins, 1);
      response.complete(_json({..._me(), 'token': 'test-session'}));
      await tester.pumpAndSettle();
      expect(find.text('private-shell'), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final entryPayload in <Map<String, Object?>>[{}, _me()]) {
    testWidgets(
      'superseded entry never unlocks cached privileges: $entryPayload',
      (tester) async {
        final entry = Completer<http.Response>();
        final background = Completer<http.Response>();
        final replacement = Completer<http.Response>();
        var requests = 0;
        final auth = _auth((_) {
          requests++;
          return switch (requests) {
            1 => entry.future,
            2 => background.future,
            _ => replacement.future,
          };
        });
        await tester.pumpWidget(_app(auth));
        await tester.pump();
        final refresh = auth.refreshMe(
          reason: 'foreground_resume',
          force: true,
        );
        await tester.pump();
        entry.complete(_json(entryPayload));
        await tester.pump();
        await tester.pump();
        final exposedCachedAccount = find
            .text('private-shell')
            .evaluate()
            .isNotEmpty;
        background.complete(_json({'detail': 'Unavailable'}, 503));
        await refresh;
        await tester.pump();
        replacement.complete(_json(_me()));
        await tester.pumpAndSettle();
        expect(exposedCachedAccount, isFalse, reason: '入口不能把跳过的旧响应视为已验证');
        expect(requests, 3, reason: '被后台刷新替代的验证必须重新请求');
        expect(auth.state.isAdmin, isFalse);
        expect(find.text('private-shell'), findsOneWidget);
      },
    );
  }

  testWidgets('native offline shell remains available without network checks', (
    tester,
  ) async {
    var requests = 0;
    final auth = _auth((_) async {
      requests++;
      return _json({});
    }, initial: const AuthState());
    await tester.pumpWidget(_app(auth, enabled: false));
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(find.text('private-shell'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });
}
