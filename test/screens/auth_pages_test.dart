import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
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

class _SelectedTheme extends ThemeProvider {
  final AppBrand selected;
  _SelectedTheme(this.selected);
  @override
  AppBrand get brand => selected;
}

AuthProvider _provider({
  Map<String, Object?> config = const {},
  Future<http.Response> Function(http.Request)? handle,
}) {
  final transport = MockClient((request) async {
    if (request.url.path == '/api/config') {
      return http.Response(jsonEncode(config), 200);
    }
    return handle == null ? http.Response('{}', 200) : handle(request);
  });
  ApiClient client(String url, String? token) =>
      ApiClient(baseUrl: url, token: token, httpClient: transport);
  return AuthProvider(
    baseUrl: 'https://server.test',
    client: client('https://server.test', null),
    clientFactory: client,
  );
}

Widget _page(
  AuthProvider auth, {
  AppBrand? brand,
  double scale = 1,
  double keyboard = 0,
}) {
  final selected = brand ?? AppBrands.defaultBrand;
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => _SelectedTheme(selected),
      ),
    ],
    child: MaterialApp(
      theme: selected.theme,
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
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });

  testWidgets(
    'shared forms fit every brand at narrow and desktop sizes with large text',
    (tester) async {
      addTearDown(tester.view.reset);
      for (final brand in AppBrands.all) {
        for (final size in [const Size(320, 720), const Size(1440, 900)]) {
          for (final scale in [1.0, 2.0]) {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            final auth = _provider(
              config: {
                'registration_email_required': true,
                'invite_code_required': true,
              },
            );
            await tester.pumpWidget(_page(auth, brand: brand, scale: scale));
            await tester.pumpAndSettle();
            final account = find.byKey(const ValueKey('auth-account'));
            expect(
              tester.getSize(account).height,
              greaterThanOrEqualTo(DesignTokens.formFieldMinHeight),
            );
            expect(
              tester
                  .getSize(find.byKey(const ValueKey('auth_form_surface')))
                  .width,
              lessThanOrEqualTo(DesignTokens.authFormMaxWidth),
            );
            expect(
              find.byKey(const ValueKey('auth_desktop_introduction')),
              size.width >= DesignTokens.authWideBreakpoint
                  ? findsOneWidget
                  : findsNothing,
            );
            await _tap(tester, find.byKey(const ValueKey('auth-switch-mode')));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('auth-confirm-password')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('auth-invite-code')),
              findsOneWidget,
            );
            await tester.ensureVisible(
              find.byKey(const ValueKey('auth-submit')),
            );
            await tester.pumpAndSettle();
            expect(
              tester.getRect(find.byKey(const ValueKey('auth-submit'))).bottom,
              lessThanOrEqualTo(size.height),
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '${brand.id} $size $scale',
            );
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
      }
    },
  );

  testWidgets('password visibility preserves input and account autofill', (
    tester,
  ) async {
    await tester.pumpWidget(_page(_provider()));
    await tester.pumpAndSettle();
    final password = find.byKey(const ValueKey('auth-password'));
    await tester.enterText(password, 'private-test-password');
    expect(tester.widget<TextField>(password).obscureText, isTrue);
    await tester.tap(find.byTooltip(I18n.tr('auth.password.show')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(password).obscureText, isFalse);
    expect(
      tester.widget<TextField>(password).controller!.text,
      'private-test-password',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('auth-account')))
          .autofillHints,
      contains(AutofillHints.username),
    );
    await tester.tap(find.byTooltip(I18n.tr('auth.password.hide')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(password).obscureText, isTrue);
  });

  testWidgets(
    'registration validates matching passwords and submits once as ordinary user',
    (tester) async {
      final response = Completer<http.Response>();
      var requests = 0;
      final auth = _provider(
        config: {'registration_email_required': false},
        handle: (request) {
          expect(request.url.path, '/api/auth/register');
          final body = jsonDecode(request.body) as Map;
          expect(body['username'], 'new-user');
          expect(body['email'], anyOf(isNull, isEmpty));
          expect(body['display_name'], 'new-user');
          expect(body.containsKey('is_admin'), isFalse);
          requests++;
          return response.future;
        },
      );
      await tester.pumpWidget(_page(auth));
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('auth-switch-mode')));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsNothing);
      expect(find.byKey(const ValueKey('auth-display-name')), findsNothing);
      expect(find.byKey(const ValueKey('auth-email')), findsNothing);
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
        'different-password',
      );
      await _tap(tester, find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      expect(
        find.text(I18n.tr('auth.error.password_mismatch')),
        findsOneWidget,
      );
      expect(requests, 0);
      await tester.enterText(
        find.byKey(const ValueKey('auth-confirm-password')),
        'test-password',
      );
      await _tap(tester, find.byKey(const ValueKey('auth-submit')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('auth-submit')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('auth-switch-mode')))
            .onPressed,
        isNull,
      );
      expect(requests, 1);
      response.complete(
        http.Response(
          jsonEncode({
            'user_id': 'new-id',
            'username': 'new-user',
            'token': 'new-session',
            'is_admin': false,
          }),
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(auth.state.isLoggedIn, isTrue);
      expect(auth.state.isAdmin, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'registration respects required email, invite and closed registration policy',
    (tester) async {
      final auth = _provider(
        config: {
          'registration_enabled': false,
          'registration_email_required': true,
          'invite_code_required': true,
        },
      );
      await tester.pumpWidget(_page(auth));
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('auth-switch-mode')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('auth-email')), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-invite-code')), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(find.text(I18n.tr('auth.registration_closed')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('auth-submit')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('small keyboard viewport can scroll to registration action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = _provider();
    await tester.pumpWidget(_page(auth, scale: 1.5, keyboard: 300));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const ValueKey('auth-switch-mode')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('auth-submit'))).bottom,
      lessThanOrEqualTo(420),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('password recovery remains usable at the entry route', (
    tester,
  ) async {
    final paths = <String>[];
    final auth = _provider(
      handle: (request) async {
        paths.add(request.url.path);
        return http.Response(jsonEncode({'message': 'test-code-sent'}), 200);
      },
    );
    await tester.pumpWidget(_page(auth));
    await tester.pumpAndSettle();
    await _tap(tester, find.text(I18n.tr('auth.forgot_password')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, I18n.tr('auth.reset_account')),
      'user@example.test',
    );
    await tester.tap(find.text(I18n.tr('auth.password_reset.send_email')));
    await tester.pumpAndSettle();
    expect(paths.single, '/api/auth/password-reset');
    await tester.enterText(
      find.widgetWithText(TextField, I18n.tr('auth.email_code')),
      '123456',
    );
    await tester.enterText(
      find.widgetWithText(TextField, I18n.tr('auth.new_password')),
      'new-test-password',
    );
    await tester.tap(find.text(I18n.tr('auth.password_reset.confirm')));
    await tester.pumpAndSettle();
    expect(paths.last, '/api/auth/password-reset/confirm');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
