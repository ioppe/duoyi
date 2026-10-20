import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/access_tokens_screen.dart';
import 'package:duoyi/screens/login_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget app(AuthProvider auth, Widget screen) => MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: auth),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
  ],
  child: MaterialApp(home: screen),
);

void main() {
  setUp(() {
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'installed login shows editable server and hidden token at phone width',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = AuthProvider(baseUrl: 'https://my-server.test');
      await tester.pumpWidget(app(auth, const LoginScreen()));
      await tester.tap(find.text(I18n.tr('auth.token.login')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('token-server-url')), findsOneWidget);
      final token = tester.widget<TextField>(
        find.byKey(const ValueKey('access-token')),
      );
      expect(token.obscureText, isTrue);
      await tester.tap(find.byTooltip(I18n.tr('auth.token.show')));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('access-token')))
            .obscureText,
        isFalse,
      );
      await tester.tap(
        find.widgetWithText(FilledButton, I18n.tr('auth.login')),
      );
      await tester.pumpAndSettle();
      expect(find.text(I18n.tr('auth.token.required')), findsOneWidget);
      expect(auth.state.isLoggedIn, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'token management creates once, shows metadata, and revokes a device token',
    (tester) async {
      var created = false;
      var revoked = false;
      final auth = AuthProvider(
        initialState: const AuthState(userId: 'user', token: 'web-session'),
        client: ApiClient(
          baseUrl: 'https://server.test',
          token: 'web-session',
          httpClient: MockClient((request) async {
            expect(request.headers['Authorization'], 'Bearer web-session');
            if (request.method == 'POST') {
              final body = jsonDecode(request.body) as Map;
              expect(body['name'], 'phone');
              expect(body['expires_in_days'], isNull);
              created = true;
              return http.Response(
                jsonEncode({'token': 'test-token-shown-once'}),
                200,
              );
            }
            if (request.method == 'DELETE') {
              expect(request.url.path, '/api/auth/tokens/device-1');
              revoked = true;
              return http.Response('{}', 200);
            }
            return http.Response(
              jsonEncode({
                'tokens': created
                    ? [
                        {
                          'id': 'device-1',
                          'name': 'phone',
                          'prefix': 'duoyi_test',
                          'last_used_at': null,
                          'expires_at': null,
                          'revoked_at': revoked ? '2026-06-01T10:00:00Z' : null,
                          'current': false,
                        },
                      ]
                    : [],
              }),
              200,
            );
          }),
        ),
      );
      await tester.pumpWidget(app(auth, const AccessTokensScreen()));
      await tester.pumpAndSettle();
      expect(find.text(I18n.tr('tokens.empty')), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, I18n.tr('action.create')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, I18n.tr('tokens.name')),
        'phone',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, I18n.tr('action.create')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey('created-access-token')),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(FilledButton, I18n.tr('action.complete')),
      );
      await tester.pumpAndSettle();
      expect(find.text('phone'), findsOneWidget);
      expect(find.text(I18n.tr('tokens.never_expires')), findsOneWidget);
      expect(find.text('test-token-shown-once'), findsNothing);
      await tester.tap(
        find.widgetWithText(TextButton, I18n.tr('tokens.revoke')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, I18n.tr('tokens.revoke')),
      );
      await tester.pumpAndSettle();
      expect(revoked, isTrue);
      expect(find.text(I18n.tr('tokens.revoked')), findsOneWidget);
      expect(auth.state.isLoggedIn, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
