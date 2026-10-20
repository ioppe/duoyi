import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/login_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('password login maps 401 invalid credentials to friendly text', (
    tester,
  ) async {
    final loginResponse = Completer<http.Response>();
    final auth = AuthProvider(
      baseUrl: 'https://api.example.test',
      client: ApiClient(
        baseUrl: 'https://api.example.test',
        httpClient: MockClient((request) {
          if (request.url.path == '/api/config') {
            return Future.value(http.Response('{}', 200));
          }
          expect(request.url.path, '/api/auth/login');
          return loginResponse.future;
        }),
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, I18n.tr('auth.account')),
      'demo',
    );
    await tester.enterText(
      find.widgetWithText(TextField, I18n.tr('auth.password')),
      'wrong-password',
    );
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, I18n.tr('auth.login')),
    );
    await tester.tap(find.widgetWithText(FilledButton, I18n.tr('auth.login')));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    loginResponse.complete(
      http.Response(
        json.encode({'detail': 'Invalid credentials'}),
        401,
        headers: {'content-type': 'application/json'},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('账号或密码错误，请重新输入'), findsOneWidget);
    expect(find.textContaining('401'), findsNothing);
    expect(find.textContaining('Invalid credentials'), findsNothing);

    final accountField = tester.widget<TextField>(
      find.widgetWithText(TextField, I18n.tr('auth.account')),
    );
    final passwordField = tester.widget<TextField>(
      find.widgetWithText(TextField, I18n.tr('auth.password')),
    );
    expect(accountField.controller?.text, 'demo');
    expect(passwordField.controller?.text, isEmpty);
  });
  testWidgets('login offers a token mode and returns to password mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = AuthProvider(
      client: ApiClient(
        baseUrl: 'https://api.example.test',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({'email_code_login_enabled': true}),
            200,
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(I18n.tr('auth.email_code_login')));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextField, I18n.tr('auth.verified_email')),
      findsOneWidget,
    );
    await tester.tap(find.text(I18n.tr('auth.token.login')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('access-token')), findsOneWidget);
    final server = tester.widget<TextField>(
      find.byKey(const ValueKey('token-server-url')),
    );
    expect(server.readOnly, kIsWeb);
    expect(server.controller?.text, kIsWeb ? Uri.base.origin : auth.baseUrl);
    await tester.tap(find.text(I18n.tr('auth.password_login')));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextField, I18n.tr('auth.password')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
