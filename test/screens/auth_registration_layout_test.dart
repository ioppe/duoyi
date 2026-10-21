import 'dart:convert';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/web_target.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/login_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

AuthProvider _auth(
  Map<String, Object?> config, {
  Future<http.Response> Function(http.Request)? send,
}) {
  final transport = MockClient((request) async {
    if (request.url.path == '/api/config') {
      return http.Response(jsonEncode(config), 200);
    }
    return send == null ? http.Response('{}', 200) : send(request);
  });
  ApiClient client(String url, String? token) =>
      ApiClient(baseUrl: url, token: token, httpClient: transport);
  return AuthProvider(
    client: client('https://server.test', null),
    clientFactory: client,
  );
}

Widget _app(AuthProvider auth, {double scale = 1, double keyboard = 0}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: child!,
        ),
        home: const LoginScreen(asEntry: true),
      ),
    );

void _expectStaticCard(WidgetTester tester) {
  final surface = find.byKey(const ValueKey('auth_form_surface'));
  final innerScrolls = find.descendant(
    of: surface,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          (widget.axisDirection == AxisDirection.down ||
              widget.axisDirection == AxisDirection.up),
    ),
  );
  expect(innerScrolls, findsNothing, reason: '认证卡片内部不应存在纵向滚动区');
  final content = tester.getRect(
    find.byKey(const ValueKey('auth_form_content')),
  );
  final footer = tester.getRect(find.byKey(const ValueKey('auth-submit')));
  for (final field in find.byType(TextField).evaluate()) {
    final rect = tester.getRect(find.byWidget(field.widget));
    expect(rect.top, greaterThanOrEqualTo(content.top - 0.1));
    expect(rect.bottom, lessThanOrEqualTo(content.bottom + 0.1));
    expect(rect.bottom, lessThanOrEqualTo(footer.top));
  }
  expect(footer.bottom, lessThanOrEqualTo(tester.getRect(surface).bottom));
  expect(tester.takeException(), isNull);
}

Future<void> _register(WidgetTester tester) async {
  final toggle = find.byKey(const ValueKey('auth-switch-mode'));
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
    WebTarget.debugWebBuild = true;
  });
  tearDown(() => WebTarget.debugWebBuild = null);

  testWidgets(
    'required email signup is fully laid out without inner scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(_auth({'registration_email_required': true})),
      );
      await tester.pumpAndSettle();
      final original = tester.getRect(
        find.byKey(const ValueKey('auth_form_surface')),
      );
      await _register(tester);
      _expectStaticCard(tester);
      expect(
        tester.getRect(find.byKey(const ValueKey('auth_form_surface'))),
        original,
      );
      expect(
        find.byKey(const ValueKey('auth_registration_passwords')),
        findsOneWidget,
      );
      final password = tester.getRect(
        find.byKey(const ValueKey('auth-password')),
      );
      final confirm = tester.getRect(
        find.byKey(const ValueKey('auth-confirm-password')),
      );
      expect(password.top, confirm.top);
      expect(password.right, lessThan(confirm.left));
      expect(find.byKey(const ValueKey('auth-email')), findsOneWidget);
      expect(find.text(I18n.tr('auth.email_code')), findsOneWidget);
    },
  );

  for (final native in [false, true]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'complete email and invite layout at 320px, native=$native, scale=$scale',
        (tester) async {
          WebTarget.debugWebBuild = !native;
          tester.view.physicalSize = const Size(320, 720);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            _app(
              _auth({
                'registration_email_required': true,
                'invite_code_required': true,
              }),
              scale: scale,
            ),
          );
          await tester.pumpAndSettle();
          final height = tester
              .getSize(find.byKey(const ValueKey('auth_form_surface')))
              .height;
          await _register(tester);
          _expectStaticCard(tester);
          expect(
            tester
                .getSize(find.byKey(const ValueKey('auth_form_surface')))
                .height,
            height,
          );
          expect(
            find.byKey(const ValueKey('auth-invite-code')),
            findsOneWidget,
          );
          await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.byKey(const ValueKey('auth-submit'))).bottom,
            lessThanOrEqualTo(720),
          );
        },
      );
    }
  }

  testWidgets('optional email layout stays equal when flipping back to login', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_auth({'registration_email_available': true})),
    );
    await tester.pumpAndSettle();
    await _register(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final height = tester
        .getSize(find.byKey(const ValueKey('auth_form_surface')))
        .height;
    _expectStaticCard(tester);
    await _register(tester);
    expect(
      tester.getSize(find.byKey(const ValueKey('auth_form_surface'))).height,
      height,
    );
    await _register(tester);
    expect(
      tester.getSize(find.byKey(const ValueKey('auth_form_surface'))).height,
      height,
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    _expectStaticCard(tester);
  });

  testWidgets(
    'required email register validates, sends code, and submits all fields',
    (tester) async {
      final requests = <String>[];
      final auth = _auth(
        {'registration_email_required': true, 'invite_code_required': true},
        send: (request) async {
          requests.add(request.url.path);
          final payload = jsonDecode(request.body) as Map;
          if (request.url.path == '/api/auth/email-code') {
            expect(payload, {
              'email': 'signup@example.test',
              'purpose': 'bind',
            });
            return http.Response(
              jsonEncode({'sent': true, 'message': 'code-sent-for-test'}),
              200,
            );
          }
          expect(request.url.path, '/api/auth/register');
          expect(payload['username'], 'new-user');
          expect(payload['display_name'], 'new-user');
          expect(payload['email'], 'signup@example.test');
          expect(payload['email_code'], '123456');
          expect(payload['invite_code'], 'invite-test');
          return http.Response(
            jsonEncode({
              'user_id': 'new-id',
              'username': 'new-user',
              'token': 'test-session',
              'is_admin': false,
            }),
            200,
          );
        },
      );
      await tester.pumpWidget(_app(auth));
      await tester.pumpAndSettle();
      await _register(tester);
      await tester.enterText(
        find.byKey(const ValueKey('auth-account')),
        'new-user',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        'test-password',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-confirm-password')),
        'test-password',
      );
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      expect(find.text(I18n.tr('auth.error.email_required')), findsOneWidget);
      _expectStaticCard(tester);
      await tester.enterText(
        find.byKey(const ValueKey('auth-email')),
        'signup@example.test',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(I18n.tr('auth.send')));
      await tester.tap(find.text(I18n.tr('auth.send')));
      await tester.pumpAndSettle();
      _expectStaticCard(tester);
      await tester.enterText(
        find.widgetWithText(TextField, I18n.tr('auth.email_code')),
        '123456',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-invite-code')),
        'invite-test',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      expect(requests, ['/api/auth/email-code', '/api/auth/register']);
      expect(auth.state.isLoggedIn, isTrue);
      expect(auth.state.isAdmin, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('native token form remains complete at large text', (
    tester,
  ) async {
    WebTarget.debugWebBuild = false;
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(_auth({}), scale: 2));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('auth-method-token')));
    await tester.tap(find.byKey(const ValueKey('auth-method-token')));
    await tester.pumpAndSettle();
    _expectStaticCard(tester);
    expect(find.byKey(const ValueKey('access-token')), findsOneWidget);
  });

  testWidgets('English email registration stays complete with enlarged text', (
    tester,
  ) async {
    I18n.setLocale(AppLocale.en);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        _app(_auth({'registration_email_required': true}), scale: scale),
      );
      await tester.pumpAndSettle();
      await _register(tester);
      _expectStaticCard(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
