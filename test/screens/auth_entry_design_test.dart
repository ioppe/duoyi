import 'dart:convert';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/web_target.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/login_screen.dart';
import 'package:duoyi/services/admin_api.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(AuthProvider auth, {double scale = 1, bool reduceMotion = false}) =>
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
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
        home: const LoginScreen(asEntry: true),
      ),
    );

AuthProvider _auth(Map<String, Object?> config, {List<String>? paths}) =>
    AuthProvider(
      client: ApiClient(
        baseUrl: 'https://server.test',
        httpClient: MockClient((request) async {
          paths?.add(request.url.path);
          return http.Response(jsonEncode(config), 200);
        }),
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => WebTarget.debugWebBuild = null);

  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('default account card is compact on both faces: $size', (
      tester,
    ) async {
      WebTarget.debugWebBuild = true;
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(_auth({})));
      await tester.pumpAndSettle();
      final surface = find.byKey(const ValueKey('auth_form_surface'));
      final rect = tester.getRect(surface);
      expect(rect.height, lessThanOrEqualTo(size.width < 960 ? 460 : 484));
      final submit = find.byKey(const ValueKey('auth-submit'));
      final password = find.byKey(const ValueKey('auth-password'));
      final loginGap =
          tester.getTopLeft(submit).dy - tester.getBottomLeft(password).dy;
      expect(loginGap, inInclusiveRange(12, 80));
      await tester.tap(find.byKey(const ValueKey('auth-switch-mode')));
      await tester.pumpAndSettle();
      expect(tester.getRect(surface), rect);
      expect(find.byKey(const ValueKey('auth-display-name')), findsNothing);
      expect(find.byKey(const ValueKey('auth-email')), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(TextField), findsNWidgets(3));
      final confirm = find.byKey(const ValueKey('auth-confirm-password'));
      final registerGap =
          tester.getTopLeft(submit).dy - tester.getBottomLeft(confirm).dy;
      expect(registerGap, inInclusiveRange(12, 80));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('optional email binding is off until the user selects it', (
    tester,
  ) async {
    WebTarget.debugWebBuild = true;
    await tester.pumpWidget(
      _app(_auth({'registration_email_available': true})),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('auth-switch-mode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('auth-email')), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('auth-email')), findsOneWidget);
    expect(find.byKey(const ValueKey('auth-display-name')), findsNothing);
  });

  testWidgets(
    'web offers password and configured email only, with no bootstrap hint',
    (tester) async {
      WebTarget.debugWebBuild = true;
      for (final config in <Map<String, Object?>>[
        {},
        {'email_code_login_enabled': false},
        {'email_code_login_enabled': true},
      ]) {
        await tester.pumpWidget(_app(_auth(config)));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('auth-method-token')), findsNothing);
        expect(find.byKey(const ValueKey('access-token')), findsNothing);
        expect(find.byKey(const ValueKey('password-server-url')), findsNothing);
        expect(find.textContaining('admin'), findsNothing);
        expect(
          find.byKey(const ValueKey('auth-method-password')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('auth-method-emailCode')),
          config['email_code_login_enabled'] == true
              ? findsOneWidget
              : findsNothing,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('login and registration flip at an identical size: $size', (
      tester,
    ) async {
      WebTarget.debugWebBuild = true;
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          _auth({
            'registration_email_required': true,
            'invite_code_required': true,
          }),
        ),
      );
      await tester.pumpAndSettle();
      final surface = find.byKey(const ValueKey('auth_form_surface'));
      final original = tester.getRect(surface);
      final forgot = find.text(I18n.tr('auth.forgot_password'));
      final toggle = find.byKey(const ValueKey('auth-switch-mode'));
      expect(
        (tester.getCenter(forgot).dy - tester.getCenter(toggle).dy).abs(),
        lessThan(1),
      );
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(surface), original);
      final flip = tester.widget<Transform>(
        find.byKey(const ValueKey('auth_card_flip')),
      );
      expect(flip.transform.storage[0].abs(), lessThan(0.99));
      expect(find.byKey(const ValueKey('auth-account')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.getRect(surface), original);
      final submitRect = tester.getRect(
        find.byKey(const ValueKey('auth-submit')),
      );
      expect(submitRect.bottom, lessThanOrEqualTo(original.bottom));
      expect(submitRect.top, greaterThan(original.top));
      expect(
        find.byKey(const ValueKey('auth-confirm-password')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('auth-submit'))).bottom,
        lessThanOrEqualTo(original.bottom),
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.getRect(surface), original);
      expect(find.byKey(const ValueKey('auth-confirm-password')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'native methods keep identical button typography and field geometry',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(_auth({'email_code_login_enabled': true})));
      await tester.pumpAndSettle();
      final original = tester.getRect(
        find.byKey(const ValueKey('auth_form_surface')),
      );
      final accountSize = tester.getSize(
        find.byKey(const ValueKey('auth-account')),
      );
      final selectorHeight = tester
          .getSize(find.byKey(const ValueKey('auth_method_selector')))
          .height;
      final style = tester
          .widget<TextButton>(
            find.byKey(const ValueKey('auth-method-password')),
          )
          .style!
          .textStyle!
          .resolve({});
      for (final method in ['emailCode', 'token', 'password']) {
        final button = find.byKey(ValueKey('auth-method-$method'));
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const ValueKey('auth_form_surface'))),
          original,
        );
        expect(
          tester
              .getSize(find.byKey(const ValueKey('auth_method_selector')))
              .height,
          selectorHeight,
        );
        expect(
          tester.widget<TextButton>(button).style!.textStyle!.resolve({}),
          style,
        );
        if (method == 'token') {
          expect(find.byKey(const ValueKey('access-token')), findsOneWidget);
          expect(find.byKey(const ValueKey('auth-account')), findsNothing);
        }
        final field = find.byKey(
          ValueKey(method == 'token' ? 'access-token' : 'auth-account'),
        );
        final server = find.byKey(
          ValueKey(
            method == 'token' ? 'token-server-url' : 'password-server-url',
          ),
        );
        expect(tester.getSize(field), accountSize);
        expect(
          tester.getTopLeft(field).dy - tester.getBottomLeft(server).dy,
          closeTo(16, 0.1),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'email removal while form is open falls back to password without sending a code',
    (tester) async {
      WebTarget.debugWebBuild = true;
      final config = <String, Object?>{'email_code_login_enabled': true};
      final paths = <String>[];
      final auth = _auth(config, paths: paths);
      await tester.pumpWidget(_app(auth));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('auth-method-emailCode')));
      await tester.pumpAndSettle();
      config['email_code_login_enabled'] = false;
      await auth.refreshServerConfigFromServer(force: true);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('auth-method-emailCode')), findsNothing);
      expect(find.byKey(const ValueKey('auth-password')), findsOneWidget);
      expect(paths.every((path) => path == '/api/config'), isTrue);
    },
  );

  testWidgets(
    'large-text flip respects reduced motion without duplicated fields',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(_auth({}), scale: 2, reduceMotion: true));
      await tester.pumpAndSettle();
      final surface = find.byKey(const ValueKey('auth_form_surface'));
      final size = tester.getSize(surface);
      await tester.ensureVisible(
        find.byKey(const ValueKey('auth-switch-mode')),
      );
      await tester.tap(find.byKey(const ValueKey('auth-switch-mode')));
      await tester.pump();
      expect(find.byKey(const ValueKey('auth-account')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('auth-confirm-password')),
        findsOneWidget,
      );
      expect(tester.getSize(surface), size);
      expect(
        tester
            .widget<Transform>(find.byKey(const ValueKey('auth_card_flip')))
            .transform
            .storage[0],
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('admin switch sends explicit email login setting', () async {
    final client = ApiClient(
      baseUrl: 'https://server.test',
      token: 'test-admin',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/admin/settings');
        expect(request.method, 'PATCH');
        expect(jsonDecode(request.body), {'email_code_login_enabled': true});
        return http.Response('{}', 200);
      }),
    );
    await AdminApi(client).updateSettings(emailCodeLoginEnabled: true);
  });
}
