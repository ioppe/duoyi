import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  test('literal client /api calls match backend FastAPI routes and methods', () {
    final backendRoutes = _extractBackendRoutes(
      File('backend/main.py').readAsStringSync(),
    );
    final clientCalls = _extractClientCalls(Directory('lib'));

    expect(
      backendRoutes,
      isNotEmpty,
      reason: 'backend/main.py should expose FastAPI HTTP routes.',
    );
    expect(
      clientCalls,
      isNotEmpty,
      reason: 'lib should contain literal client /api calls to check.',
    );

    final failures = <String>[];
    for (final call in clientCalls) {
      final exactMatch = backendRoutes.any(
        (route) => route.method == call.method && _samePathShape(route, call),
      );
      if (exactMatch) continue;

      final samePathMethods =
          backendRoutes
              .where((route) => _samePathShape(route, call))
              .map((route) => route.method)
              .toSet()
              .toList()
            ..sort();
      final suffix = samePathMethods.isEmpty
          ? 'no matching backend path'
          : 'backend path exists with ${samePathMethods.join(', ')}';
      failures.add('${call.location}: ${call.method} ${call.path} ($suffix)');
    }

    expect(
      failures,
      isEmpty,
      reason:
          'Every literal /api call in lib must match an @app route in '
          'backend/main.py with the same HTTP method.\n${failures.join('\n')}',
    );
  });

  test(
    'every backend api literal in lib is covered by contract extraction',
    () {
      final clientCalls = _extractClientCalls(Directory('lib'));
      final apiLiterals = _extractApiLiterals(Directory('lib'));

      expect(
        apiLiterals,
        isNotEmpty,
        reason: 'lib should contain backend /api literals to audit.',
      );

      final missing = <String>[];
      for (final literal in apiLiterals) {
        final covered = clientCalls.any(
          (call) => _samePathShape(
            call,
            _RouteContract(
              method: call.method,
              path: literal.path,
              location: literal.location,
            ),
          ),
        );
        if (!covered) missing.add('${literal.location}: ${literal.path}');
      }

      expect(
        missing,
        isEmpty,
        reason:
            'Every backend-bound /api literal in lib must be visible to the '
            'static route-contract extractor, otherwise new call shapes can '
            'bypass the 404 guard.\n${missing.join('\n')}',
      );
    },
  );

  test('web shell does not carry stale backend api paths', () {
    final webApiLiterals = _extractTextApiLiterals(Directory('web'));

    expect(
      webApiLiterals,
      isEmpty,
      reason:
          'web/ is the Flutter shell/static manifest area. It must not keep '
          'stale hard-coded /api paths that bypass the Flutter ApiClient '
          'route-contract guard.\n${webApiLiterals.join('\n')}',
    );
  });

  test('client runtime contract hash matches backend required routes', () {
    final backend = File('backend/main.py').readAsStringSync();
    final client = File('lib/services/api_client.dart').readAsStringSync();
    final routesStart = backend.indexOf('API_CONTRACT_REQUIRED_ROUTES = [');
    final routesEnd = backend.indexOf(']', routesStart);
    expect(routesStart, greaterThanOrEqualTo(0));
    expect(routesEnd, greaterThan(routesStart));
    final routesBlock = backend.substring(routesStart, routesEnd);
    final routes = RegExp(
      r'"([^"]+)"',
    ).allMatches(routesBlock).map((match) => match.group(1)!).toList();
    expect(routes, isNotEmpty);

    final routesHash = sha256
        .convert(utf8.encode(routes.join('\n')))
        .toString()
        .substring(0, 16);
    expect(
      backend,
      contains('"required_routes_hash": API_CONTRACT_ROUTES_HASH'),
    );
    expect(client, contains("requiredApiContractRoutesHash = '$routesHash'"));
    expect(client, contains("decoded['required_routes_hash']"));
    expect(client, contains('requiredApiContractRoutesHash'));
  });

  test('account profile email avatar and coin routes stay compatible', () {
    final backend = File('backend/main.py').readAsStringSync();
    final authProvider = File(
      'lib/providers/auth_provider.dart',
    ).readAsStringSync();
    final aiService = File('lib/services/ai_service.dart').readAsStringSync();
    final feedbackScreen = File(
      'lib/screens/feedback_screen.dart',
    ).readAsStringSync();
    final loginScreen = File(
      'lib/screens/login_screen.dart',
    ).readAsStringSync();
    final profileScreen = File(
      'lib/screens/profile_screen.dart',
    ).readAsStringSync();
    final mineScreen = File('lib/screens/mine_screen.dart').readAsStringSync();
    final surfaceComponents = File(
      'lib/widgets/surface_components.dart',
    ).readAsStringSync();
    final adminApi = File('lib/services/admin_api.dart').readAsStringSync();

    for (final route in [
      '@app.post("/api/me/profile")',
      '@app.patch("/api/me/profile")',
      '@app.put("/api/me/profile")',
      '@app.post("/api/auth/login")',
      '@app.get("/api/auth/me")',
      '@app.get("/api/me")',
      '@app.post("/api/auth/logout")',
      '@app.post("/api/me/email")',
      '@app.patch("/api/me/email")',
      '@app.put("/api/me/email")',
      '@app.post("/api/me/email/bind")',
      '@app.patch("/api/me/email/bind")',
      '@app.put("/api/me/email/bind")',
      '@app.post("/api/me/bind-email")',
      '@app.patch("/api/me/bind-email")',
      '@app.put("/api/me/bind-email")',
      '@app.post("/api/auth/email")',
      '@app.patch("/api/auth/email")',
      '@app.put("/api/auth/email")',
      '@app.post("/api/auth/email/bind")',
      '@app.patch("/api/auth/email/bind")',
      '@app.put("/api/auth/email/bind")',
      '@app.post("/api/auth/bind-email")',
      '@app.patch("/api/auth/bind-email")',
      '@app.put("/api/auth/bind-email")',
      '@app.post("/api/me/email-code")',
      '@app.post("/api/me/email-code/send")',
      '@app.post("/api/me/email_code")',
      '@app.post("/api/me/email_code/send")',
      '@app.post("/api/me/email/send")',
      '@app.post("/api/me/email/send-code")',
      '@app.post("/api/auth/email-code")',
      '@app.post("/api/auth/email-code/send")',
      '@app.post("/api/auth/email_code")',
      '@app.post("/api/auth/email_code/send")',
      '@app.post("/api/auth/email/send")',
      '@app.post("/api/auth/email/send-code")',
      '@app.post("/api/auth/send-email-code")',
      '@app.post("/api/auth/send-email_code")',
      '@app.post("/api/auth/email-login")',
      '@app.post("/api/auth/email/login")',
      '@app.post("/api/auth/login/email")',
      '@app.post("/api/auth/email-code-login")',
      '@app.post("/api/auth/login/email-code")',
      '@app.post("/api/auth/email_code_login")',
      '@app.post("/api/auth/login/email_code")',
      '@app.post("/api/me/avatar")',
      '@app.patch("/api/me/avatar")',
      '@app.put("/api/me/avatar")',
      '@app.post("/api/me/profile/avatar")',
      '@app.patch("/api/me/profile/avatar")',
      '@app.put("/api/me/profile/avatar")',
      '@app.post("/api/auth/avatar")',
      '@app.patch("/api/auth/avatar")',
      '@app.put("/api/auth/avatar")',
      '@app.post("/api/auth/profile/avatar")',
      '@app.patch("/api/auth/profile/avatar")',
      '@app.put("/api/auth/profile/avatar")',
      '@app.post("/api/me/password")',
      '@app.post("/api/auth/change-password")',
      '@app.get("/api/uploads/avatars/{filename}")',
      '@app.post("/api/ai/chat")',
      '@app.get("/api/ai/usage")',
      '@app.post("/api/feedback")',
      '@app.get("/api/feedback/me")',
      '@app.get("/api/me/feedback")',
      '@app.get("/api/admin/feedback")',
      '@app.get("/api/admin/feedback/{fb_id}")',
      '@app.post("/api/admin/feedback/reply")',
      '@app.post("/api/admin/feedback/bulk-status")',
      '@app.delete("/api/admin/feedback/{fb_id}")',
      '@app.get("/api/admin/settings")',
      '@app.patch("/api/admin/settings")',
      '@app.get("/api/admin/system-settings")',
      '@app.post("/api/admin/system-settings")',
      '@app.patch("/api/admin/system-settings")',
      '@app.put("/api/admin/system-settings")',
      '@app.post("/api/admin/ai/test")',
      '@app.post("/api/admin/account-email/test")',
      '@app.get("/api/admin/groups")',
      '@app.get("/api/admin/user-groups")',
      '@app.get("/api/admin/user_groups")',
      '@app.post("/api/admin/groups")',
      '@app.post("/api/admin/user-groups")',
      '@app.post("/api/admin/user_groups")',
      '@app.delete("/api/admin/groups/{group_id}")',
      '@app.delete("/api/admin/user-groups/{group_id}")',
      '@app.delete("/api/admin/user_groups/{group_id}")',
      '@app.patch("/api/admin/groups/{group_id}")',
      '@app.put("/api/admin/groups/{group_id}")',
      '@app.patch("/api/admin/user-groups/{group_id}")',
      '@app.put("/api/admin/user-groups/{group_id}")',
      '@app.patch("/api/admin/user_groups/{group_id}")',
      '@app.put("/api/admin/user_groups/{group_id}")',
      '@app.post("/api/admin/users/{user_id}/coins")',
      '@app.patch("/api/admin/users/{user_id}/coins")',
      '@app.put("/api/admin/users/{user_id}/coins")',
      '@app.post("/api/admin/users/{user_id}/coin")',
      '@app.patch("/api/admin/users/{user_id}/coin")',
      '@app.put("/api/admin/users/{user_id}/coin")',
      '@app.post("/api/admin/users/{user_id}/coin-balance")',
      '@app.patch("/api/admin/users/{user_id}/coin-balance")',
      '@app.put("/api/admin/users/{user_id}/coin-balance")',
      '@app.post("/api/admin/users/{user_id}/coin_balance")',
      '@app.patch("/api/admin/users/{user_id}/coin_balance")',
      '@app.put("/api/admin/users/{user_id}/coin_balance")',
      '@app.post("/api/admin/users/{user_id}/quota")',
      '@app.patch("/api/admin/users/{user_id}/quota")',
      '@app.put("/api/admin/users/{user_id}/quota")',
      '@app.post("/api/admin/users/{user_id}/time-coins")',
      '@app.patch("/api/admin/users/{user_id}/time-coins")',
      '@app.put("/api/admin/users/{user_id}/time-coins")',
      '@app.post("/api/admin/users/{user_id}/time-coin-balance")',
      '@app.patch("/api/admin/users/{user_id}/time-coin-balance")',
      '@app.put("/api/admin/users/{user_id}/time-coin-balance")',
      '@app.post("/api/admin/users/{user_id}/time_coins")',
      '@app.patch("/api/admin/users/{user_id}/time_coins")',
      '@app.put("/api/admin/users/{user_id}/time_coins")',
      '@app.post("/api/admin/users/{user_id}/time_coin_balance")',
      '@app.patch("/api/admin/users/{user_id}/time_coin_balance")',
      '@app.put("/api/admin/users/{user_id}/time_coin_balance")',
      '@app.post("/api/admin/users/{user_id}/credits")',
      '@app.patch("/api/admin/users/{user_id}/credits")',
      '@app.put("/api/admin/users/{user_id}/credits")',
      '@app.post("/api/admin/users/{user_id}/credit-balance")',
      '@app.patch("/api/admin/users/{user_id}/credit-balance")',
      '@app.put("/api/admin/users/{user_id}/credit-balance")',
      '@app.post("/api/admin/users/{user_id}/credit_balance")',
      '@app.patch("/api/admin/users/{user_id}/credit_balance")',
      '@app.put("/api/admin/users/{user_id}/credit_balance")',
      '@app.post("/api/admin/users/{user_id}/coins/adjust")',
      '@app.patch("/api/admin/users/{user_id}/coins/adjust")',
      '@app.put("/api/admin/users/{user_id}/coins/adjust")',
      '@app.post("/api/admin/users/{user_id}/time-coins/adjust")',
      '@app.patch("/api/admin/users/{user_id}/time-coins/adjust")',
      '@app.put("/api/admin/users/{user_id}/time-coins/adjust")',
      '@app.post("/api/admin/users/{user_id}/time_coins/adjust")',
      '@app.patch("/api/admin/users/{user_id}/time_coins/adjust")',
      '@app.put("/api/admin/users/{user_id}/time_coins/adjust")',
      '@app.post("/api/admin/users/{user_id}/time-coin-balance/adjust")',
      '@app.patch("/api/admin/users/{user_id}/time-coin-balance/adjust")',
      '@app.put("/api/admin/users/{user_id}/time-coin-balance/adjust")',
      '@app.post("/api/admin/users/{user_id}/time_coin_balance/adjust")',
      '@app.patch("/api/admin/users/{user_id}/time_coin_balance/adjust")',
      '@app.put("/api/admin/users/{user_id}/time_coin_balance/adjust")',
      '@app.post("/api/admin/users/{user_id}/quota/adjust")',
      '@app.patch("/api/admin/users/{user_id}/quota/adjust")',
      '@app.put("/api/admin/users/{user_id}/quota/adjust")',
      '@app.post("/api/admin/users/{user_id}/coin-adjustment")',
      '@app.patch("/api/admin/users/{user_id}/coin-adjustment")',
      '@app.put("/api/admin/users/{user_id}/coin-adjustment")',
      '@app.post("/api/admin/users/{user_id}/coin_adjustment")',
      '@app.patch("/api/admin/users/{user_id}/coin_adjustment")',
      '@app.put("/api/admin/users/{user_id}/coin_adjustment")',
      '@app.get("/api/mobile/apps/{app_id}/update")',
      '@app.get("/api/config")',
    ]) {
      expect(backend, contains(route), reason: route);
    }

    expect(
      authProvider,
      contains("'/api/me/profile',"),
      reason: '资料保存应把当前后端主路由放在兼容路径第一位。',
    );
    expect(
      authProvider,
      contains("'/api/me/email',"),
      reason: '邮箱绑定应把当前后端主路由放在兼容路径第一位。',
    );
    expect(
      authProvider,
      contains("_uploadFirstAvailable("),
      reason: '头像上传应走可被契约扫描识别的兼容路由兜底。',
    );

    for (final call in [
      "'/api/me/profile'",
      "'/api/me/email'",
      "'/api/me/email-code'",
      "'/api/me/avatar'",
      "'/api/me/password'",
      "'/api/auth/change-password'",
      "'/api/auth/email-code'",
      "'/api/auth/email-login'",
      "'/api/auth/login'",
      "'/api/auth/me'",
      "'/api/auth/logout'",
    ]) {
      expect(authProvider, contains(call), reason: call);
    }
    for (final compatibilityFallback in [
      "'/api/auth/login/email-code'",
      "'/api/me/email-code/send'",
      "'/api/auth/email-code/send'",
      "'/api/me/profile/avatar'",
      "'/api/account/avatar'",
    ]) {
      expect(
        authProvider,
        contains(compatibilityFallback),
        reason:
            '$compatibilityFallback should remain as a stale-backend fallback after the main route.',
      );
    }

    expect(aiService, contains("post('/api/ai/chat'"));
    expect(feedbackScreen, contains("'/api/feedback'"));
    expect(feedbackScreen, contains("'/api/feedback/me?page="));
    expect(adminApi, contains("'/api/admin/users/\$userId/coins'"));
    expect(
      adminApi,
      contains("client.post('/api/admin/users/\$userId/coins', body)"),
    );
    for (final noisyFallback in [
      "'/api/admin/users/\$userId/quota/adjust'",
      "'/api/admin/users/\$userId/time-coins/adjust'",
      "'/api/admin/users/\$userId/time_coin_balance/adjust'",
      "'/api/admin/users/\$userId/coin-adjustment'",
    ]) {
      expect(
        adminApi,
        isNot(contains(noisyFallback)),
        reason:
            '$noisyFallback should remain a backend alias, not a frontend probe.',
      );
    }
    expect(adminApi, contains("'/api/admin/settings'"));
    expect(adminApi, contains("'/api/admin/system-settings'"));
    expect(adminApi, contains("'/api/admin/groups'"));
    expect(adminApi, contains("'/api/admin/user-groups'"));
    expect(adminApi, contains("'/api/admin/user_groups'"));
    expect(adminApi, contains("'/api/admin/feedback'"));
    expect(
      adminApi,
      contains('Future<Map<String, dynamic>> getFeedbackDetail'),
    );
    expect(adminApi, contains("client.get('/api/admin/feedback/\$id')"));
    expect(adminApi, contains("'/api/admin/feedback/export.csv'"));
    expect(adminApi, contains("'/api/admin/feedback/reply'"));
    expect(adminApi, contains("'/api/admin/feedback/bulk-status'"));
    expect(adminApi, contains("'/api/admin/ai/test'"));
    expect(adminApi, contains("'/api/admin/account-email/test'"));
    expect(loginScreen, contains('class _LoginActionField'));
    expect(loginScreen, contains('Widget _emailCodeSendField({'));
    expect(
      loginScreen,
      contains('final actionWidth = constraints.maxWidth < 360 ? 64.0 : 72.0'),
    );
    expect(
      surfaceComponents,
      contains('disabledBackgroundColor: disabledBackground'),
    );
    expect(loginScreen, contains(r"'${_emailCooldownSeconds}s 后'"));

    expect(profileScreen, contains('readOnly: true'));
    expect(profileScreen, contains("I18n.tr('profile.username.locked')"));
    expect(profileScreen, contains('sendBindEmailCode('));
    expect(profileScreen, contains('bindEmail(email: email, code: code)'));
    expect(profileScreen, contains('uploadAvatarBytes('));
    expect(profileScreen, contains('onPreview: _showAvatarPreview'));
    expect(profileScreen, contains('onEdit: _uploadAvatar'));
    expect(profileScreen, contains('onEdit: _pickLocalAvatar'));
    expect(profileScreen, isNot(contains('Icons.photo_camera_outlined')));
    expect(mineScreen, contains('onTap: () => _showAvatarPreview(context)'));
    expect(mineScreen, contains('onTap: () => _openProfileEditor(context)'));
    expect(
      mineScreen,
      contains('void _openProfileEditor(BuildContext context'),
    );
    expect(mineScreen, isNot(contains("title: '账号资料'")));
  });

  test('high-risk account admin ai and feedback calls are route-backed', () {
    final backendRoutes = _extractBackendRoutes(
      File('backend/main.py').readAsStringSync(),
    );
    final clientCalls = _extractClientCalls(Directory('lib'));

    final expectations = <_RouteContract>[
      const _RouteContract(
        method: 'GET',
        path: '/api/feedback/me',
        location: '',
      ),
      const _RouteContract(method: 'POST', path: '/api/feedback', location: ''),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/feedback',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/feedback/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/feedback/export.csv',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/feedback/reply',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/feedback/bulk-status',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/admin/feedback/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/ai/test',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/provider-healthcheck',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/groups',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/user-groups',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/user_groups',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/groups',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/user-groups',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/user_groups',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/admin/groups/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/admin/user-groups/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/admin/user_groups/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/admin/groups/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'PUT',
        path: '/api/admin/groups/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/admin/user-groups/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'PUT',
        path: '/api/admin/user-groups/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/admin/user_groups/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'PUT',
        path: '/api/admin/user_groups/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/admin/settings',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/system-settings',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/system-settings',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/mobile/apps/duoyi/update',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/users/{param}/coins',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/roles',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/roles',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/admin/roles/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/announcements',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/announcements',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/admin/announcements/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/admin/announcements/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/invite-codes',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/invite-codes',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/admin/invite-codes/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/audit-log',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/me/profile',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/me/email',
        location: '',
      ),
      const _RouteContract(method: 'POST', path: '/api/me/email', location: ''),
      const _RouteContract(
        method: 'POST',
        path: '/api/me/avatar',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/auth/email-code',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/me/email-code',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/auth/email-login',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/auth/login',
        location: '',
      ),
      const _RouteContract(method: 'GET', path: '/api/auth/me', location: ''),
      const _RouteContract(method: 'GET', path: '/api/me', location: ''),
      const _RouteContract(
        method: 'POST',
        path: '/api/auth/logout',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/me/password',
        location: '',
      ),
    ];

    final failures = <String>[];
    for (final expected in expectations) {
      final inClient = _hasContract(clientCalls, expected);
      final inBackend = backendRoutes.any(
        (route) =>
            route.method == expected.method && _samePathShape(route, expected),
      );
      if (!inClient || !inBackend) {
        failures.add(
          '${expected.method} ${expected.path} '
          '(client=${inClient ? 'yes' : 'no'}, backend=${inBackend ? 'yes' : 'no'})',
        );
      }
    }

    expect(
      failures,
      isEmpty,
      reason:
          'High-risk API calls must be present in the Flutter contract scan '
          'and backed by backend/main.py routes.\n${failures.join('\n')}',
    );
    expect(
      backendRoutes.any(
        (route) =>
            route.method == 'POST' &&
            _samePathShape(
              route,
              const _RouteContract(
                method: 'POST',
                path: '/api/admin/welfare-grants',
                location: '',
              ),
            ),
      ),
      isTrue,
      reason:
          '/api/admin/welfare-grants is a backend compatibility route; the '
          'current app adjusts per-user time coins through AdminApi.',
    );
  });

  test('legacy api service entrypoint delegates to api client', () {
    final source = File('lib/services/api_service.dart').readAsStringSync();

    expect(source, contains("import 'api_client.dart';"));
    expect(source, contains('class ApiService extends ApiClient'));
    expect(source, contains('super.httpClient'));
    expect(
      source,
      contains(
        "ApiService({super.baseUrl = '', super.token, super.httpClient})",
      ),
    );
  });

  test('RE0 style non-AI route aliases stay live', () {
    final backend = File('backend/main.py').readAsStringSync();

    for (final route in [
      '@app.post("/api/me/feedback")',
      '@app.get("/api/me/feedback")',
      '@app.get("/api/me/feedback/{fb_id}")',
      '@app.get("/api/feedback/me/{fb_id}")',
      '@app.get("/api/admin/feedback/{fb_id}")',
      '@app.post("/api/admin/feedback/{fb_id}/status")',
      '@app.post("/api/admin/feedback/{fb_id}/reply")',
      '@app.post("/api/admin/feedback/{fb_id}/ai-summary")',
      '@app.get("/api/admin/feedback/automation")',
      '@app.post("/api/admin/feedback/automation")',
      '@app.post("/api/admin/feedback/auto-run")',
      '@app.post("/api/admin/feedback/auto-reply")',
      '@app.get("/api/admin/feedback/insights")',
      '@app.post("/api/admin/feedback/export")',
      '@app.post("/api/me/password")',
      '@app.post("/api/auth/password-reset")',
      '@app.post("/api/auth/password-reset/request")',
      '@app.post("/api/auth/password-reset/confirm")',
      '@app.post("/api/auth/reset-password")',
      '@app.post("/api/auth/reset-password/request")',
      '@app.post("/api/auth/reset-password/confirm")',
      '@app.post("/api/auth/forgot-password")',
      '@app.post("/api/auth/forgot-password/request")',
      '@app.post("/api/auth/forgot-password/confirm")',
      '@app.post("/api/password-reset")',
      '@app.post("/api/password-reset/request")',
      '@app.post("/api/password-reset/confirm")',
      '@app.get("/api/admin/overview")',
      '@app.get("/api/admin/local-backups")',
      '@app.post("/api/admin/local-backups/run")',
    ]) {
      expect(backend, contains(route), reason: route);
    }

    expect(
      backend,
      contains('def admin_feedback_status_alias'),
      reason:
          'RE0 admin feedback status route should delegate to current handler.',
    );
    expect(
      backend,
      contains('def admin_feedback_reply_alias'),
      reason:
          'RE0 admin feedback reply route should delegate to current handler.',
    );
  });

  test('focus room share admin and sync route families stay backed', () {
    final backend = File('backend/main.py').readAsStringSync();
    final focusRoomApi = File(
      'lib/services/focus_room_api.dart',
    ).readAsStringSync();
    final shareProvider = File(
      'lib/providers/share_provider.dart',
    ).readAsStringSync();
    final adminApi = File('lib/services/admin_api.dart').readAsStringSync();
    final syncProvider = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final emailSink = File(
      'lib/services/backend_reminder_email_sink.dart',
    ).readAsStringSync();

    for (final route in [
      '@app.post("/api/focus-rooms/{room_id}/heartbeat")',
      '@app.get("/api/focus-rooms/{room_id}/ranking")',
      '@app.get("/api/focus-rooms/{room_id}/events")',
      '@app.post("/api/focus-rooms/{room_id}/leave")',
      '@app.get("/api/focus-friends")',
      '@app.get("/api/focus-friends/requests")',
      '@app.post("/api/focus-friends")',
      '@app.delete("/api/focus-friends/{friend_user_id}")',
      '@app.post("/api/focus-friend-requests/{requester_user_id}/accept")',
      '@app.post("/api/focus-friend-requests/{requester_user_id}/reject")',
      '@app.delete("/api/focus-friend-requests/{friend_user_id}")',
      '@app.get("/api/focus-leaderboard/friends")',
      '@app.get("/api/focus-leaderboard/global")',
      '@app.get("/api/focus-leaderboard/global/events")',
      '@app.post("/api/focus-rooms/{room_id}/invites")',
      '@app.get("/api/focus-rooms/{room_id}/invites")',
      '@app.delete("/api/focus-room-invites/{invite_id}")',
      '@app.post("/api/focus-room-invites/{code}/accept")',
      '@app.get("/api/workspaces")',
      '@app.post("/api/workspaces")',
      '@app.post("/api/workspaces/{workspace_id}/invites")',
      '@app.post("/api/invites/{code}/accept")',
      '@app.patch("/api/workspaces/{workspace_id}/members/{member_user_id}")',
      '@app.delete("/api/workspaces/{workspace_id}/members/{member_user_id}")',
      '@app.get("/api/workspaces/{workspace_id}/comments")',
      '@app.post("/api/workspaces/{workspace_id}/comments")',
      '@app.get("/api/workspaces/mentions")',
      '@app.post("/api/workspaces/mentions/{mention_id}/read")',
      '@app.get("/api/workspaces/{workspace_id}/activities")',
      '@app.get("/api/workspaces/{workspace_id}/leaderboard")',
      '@app.get("/api/admin/stats")',
      '@app.post("/api/admin/provider-healthcheck")',
      '@app.post("/api/admin/welfare-grants")',
      '@app.post("/api/admin/reminders/email/test")',
      '@app.post("/api/reminders/email/once")',
      '@app.post("/api/reminders/email/repeating")',
      '@app.delete("/api/reminders/email/{reminder_id}")',
      '@app.get("/api/admin/backups")',
      '@app.get("/api/admin/backups/export.csv")',
      '@app.delete("/api/admin/backups/{user_id}")',
      '@app.get("/api/admin/server-backups")',
      '@app.get("/api/admin/server-backups/export.csv")',
      '@app.post("/api/admin/server-backups/run")',
      '@app.post("/api/sync")',
      '@app.post("/api/sync/delta")',
      '@app.post("/api/sync/item-delta")',
      '@app.post("/api/sync/pull")',
      '@app.get("/api/sync/status")',
      '@app.get("/api/sync/events")',
    ]) {
      expect(backend, contains(route), reason: route);
    }

    for (final call in [
      "'/api/focus-rooms/\${Uri.encodeComponent(roomId)}/heartbeat'",
      "'/api/focus-friends'",
      "'/api/focus-leaderboard/global/events?\$query'",
      "'/api/focus-room-invites/\${Uri.encodeComponent(code)}/accept'",
    ]) {
      expect(focusRoomApi, contains(call), reason: call);
    }

    for (final call in [
      "'/api/workspaces'",
      "'/api/workspaces/mentions'",
      "'/api/workspaces/\$workspaceId/comments'",
      "'/api/invites/\${Uri.encodeComponent(code)}/accept'",
    ]) {
      expect(shareProvider, contains(call), reason: call);
    }

    for (final call in [
      "'/api/admin/stats'",
      "'/api/admin/provider-healthcheck'",
      "'/api/admin/reminders/email/test'",
      "'/api/admin/backups'",
      "'/api/admin/server-backups'",
      "'/api/admin/server-backups/run'",
    ]) {
      expect(adminApi, contains(call), reason: call);
    }

    for (final call in [
      "'/api/sync/events'",
      "'/api/sync'",
      "'/api/sync/item-delta'",
      "'/api/sync/delta'",
      "'/api/sync/pull'",
    ]) {
      expect(syncProvider, contains(call), reason: call);
    }
    expect(
      syncProvider,
      isNot(contains("'/api/sync/status'")),
      reason: '个人数据变化由 SSE 通知触发，客户端不得恢复版本探针轮询。',
    );

    for (final call in [
      "'/api/reminders/email/once'",
      "'/api/reminders/email/repeating'",
      "'/api/reminders/email/\$id'",
    ]) {
      expect(emailSink, contains(call), reason: call);
    }
  });

  test(
    'admin coin adjustment uses one primary route while backend keeps aliases',
    () {
      final backendRoutes = _extractBackendRoutes(
        File('backend/main.py').readAsStringSync(),
      );
      final adminApiSource = File(
        'lib/services/admin_api.dart',
      ).readAsStringSync();
      final adminApiCalls = [
        ..._literalApiMethodCalls(
          adminApiSource,
          'lib/services/admin_api.dart',
        ),
        ..._nestedPathApiMethodCalls(
          adminApiSource,
          'lib/services/admin_api.dart',
        ),
        ..._getPageApiCalls(adminApiSource, 'lib/services/admin_api.dart'),
        ..._firstAvailableApiCalls(
          adminApiSource,
          'lib/services/admin_api.dart',
        ),
      ];

      const primary = _RouteContract(
        method: 'POST',
        path: '/api/admin/users/{param}/coins',
        location: '',
      );
      expect(
        _hasContract(adminApiCalls, primary),
        isTrue,
        reason: 'AdminApi.adjustUserCoins must call the current primary route.',
      );
      expect(
        backendRoutes.any(
          (route) =>
              route.method == primary.method && _samePathShape(route, primary),
        ),
        isTrue,
        reason: 'The primary admin coin route must exist in backend/main.py.',
      );

      final backendAliasPaths = [
        '/api/admin/users/{param}/coins',
        '/api/admin/users/{param}/coin',
        '/api/admin/users/{param}/coin-balance',
        '/api/admin/users/{param}/coin_balance',
        '/api/admin/users/{param}/time-coins',
        '/api/admin/users/{param}/time_coins',
        '/api/admin/users/{param}/time-coin-balance',
        '/api/admin/users/{param}/time_coin_balance',
        '/api/admin/users/{param}/credits',
        '/api/admin/users/{param}/credit-balance',
        '/api/admin/users/{param}/credit_balance',
        '/api/admin/users/{param}/coins/adjust',
        '/api/admin/users/{param}/time-coins/adjust',
        '/api/admin/users/{param}/time_coins/adjust',
        '/api/admin/users/{param}/time-coin-balance/adjust',
        '/api/admin/users/{param}/time_coin_balance/adjust',
        '/api/admin/users/{param}/coin-adjustment',
        '/api/admin/users/{param}/coin_adjustment',
        '/api/admin/users/{param}/quota',
        '/api/admin/users/{param}/quota/adjust',
        '/api/admin/users/{param}',
      ];

      for (final method in ['POST', 'PATCH', 'PUT']) {
        for (final path in backendAliasPaths) {
          final expected = _RouteContract(
            method: method,
            path: path,
            location: '',
          );
          expect(
            backendRoutes.any(
              (route) =>
                  route.method == method && _samePathShape(route, expected),
            ),
            isTrue,
            reason:
                'Backend admin coin compatibility alias must exist: '
                '$method $path',
          );
        }
      }

      for (final path
          in backendAliasPaths
              .skip(1)
              .where((path) => path != '/api/admin/users/{param}')) {
        final clientProbe = _RouteContract(
          method: 'POST',
          path: path,
          location: '',
        );
        expect(
          _hasContract(adminApiCalls, clientProbe),
          isFalse,
          reason:
              'Compatibility alias $path should not be actively probed by '
              'AdminApi.adjustUserCoins.',
        );
      }

      for (final expected in [
        const _RouteContract(
          method: 'POST',
          path: '/api/admin/ai/test',
          location: '',
        ),
        const _RouteContract(
          method: 'POST',
          path: '/api/admin/provider-healthcheck',
          location: '',
        ),
      ]) {
        expect(
          _hasContract(adminApiCalls, expected),
          isTrue,
          reason:
              'AdminApi.testAi primary and fallback routes must both be '
              'contract-covered: ${expected.method} ${expected.path}',
        );
        expect(
          backendRoutes.any(
            (route) =>
                route.method == expected.method &&
                _samePathShape(route, expected),
          ),
          isTrue,
          reason:
              'AdminApi.testAi primary and fallback routes must both exist in '
              'backend/main.py: ${expected.method} ${expected.path}',
        );
      }
    },
  );

  test('dynamic and external api paths are classified correctly', () {
    final backendRoutes = _extractBackendRoutes(
      File('backend/main.py').readAsStringSync(),
    );
    final clientCalls = _extractClientCalls(Directory('lib'));

    for (final call in [
      const _RouteContract(
        method: 'POST',
        path: '/api/focus-rooms/{param}/heartbeat',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/focus-rooms/{param}/ranking',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/focus-rooms/{param}/events',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/focus-leaderboard/global/events',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/focus-rooms/{param}/leave',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/focus-friend-requests/{param}/accept',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/focus-friends/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/focus-friends/requests',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/focus-rooms/{param}/invites',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/focus-room-invites/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/focus-room-invites/{param}/accept',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/mobile/apps/duoyi/update',
        location: '',
      ),
      const _RouteContract(method: 'GET', path: '/api/config', location: ''),
      const _RouteContract(method: 'GET', path: '/api/auth/me', location: ''),
      const _RouteContract(
        method: 'GET',
        path: '/api/announcements',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/reminders/email/once',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/reminders/email/repeating',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/reminders/email/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/sync/events',
        location: '',
      ),
      const _RouteContract(method: 'POST', path: '/api/sync', location: ''),
      const _RouteContract(
        method: 'POST',
        path: '/api/sync/item-delta',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/sync/delta',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/sync/pull',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/backups',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/backups/export.csv',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/admin/backups/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/server-backups',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/server-backups/export.csv',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/server-backups/run',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/users/export.csv',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/feedback/export.csv',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/me/profile',
        location: '',
      ),
      const _RouteContract(method: 'POST', path: '/api/me/email', location: ''),
      const _RouteContract(
        method: 'POST',
        path: '/api/me/password',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/me/avatar',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/users/{param}/coins',
        location: '',
      ),
    ]) {
      expect(
        _hasContract(clientCalls, call),
        isTrue,
        reason: '${call.method} ${call.path} should be extracted from lib/.',
      );
      expect(
        backendRoutes.any(
          (route) => route.method == call.method && _samePathShape(route, call),
        ),
        isTrue,
        reason: '${call.method} ${call.path} should exist in backend/main.py.',
      );
    }

    expect(
      clientCalls.any((call) => call.path.contains('api.github.com')),
      isFalse,
      reason: 'External GitHub release checks are not backend /api routes.',
    );
  });

  test('contract extractor covers compatibility and uri edge cases', () {
    const source = '''
Future<void> sample(ApiClient client) async {
  await _sendFirstAvailable(
    const ['PATCH', 'POST', 'PUT'],
    const ['/api/me/profile', '/api/auth/profile'],
    {},
  );
  await _postFirstAvailable(const [
    '/api/auth/email-code',
    '/api/auth/email-code/send',
  ], {});
  await _getFirstAvailable(const ['/api/auth/me', '/api/me']);
  await _uploadFirstAvailable(const [
    '/api/me/avatar',
    '/api/auth/avatar',
  ], fieldName: 'avatar', filename: 'a.png', bytes: bytes);
  final request = http.MultipartRequest(
    'POST',
    Uri.parse('/api/me/avatar'),
  );
  final multipartPathUri = http.MultipartRequest(
    'POST',
    Uri(path: '/api/auth/avatar'),
  );
  final response = await http.get(Uri(path: '/api/config'));
  final httpsResponse = await http.get(
    Uri.https('example.test', '/api/mobile/apps/duoyi/update', {
      'current_version_code': '1',
    }),
  );
  final httpResponse = await http.post(
    Uri.http('example.test', '/api/feedback', {'page': '1'}),
  );
  final aliasedUri = Uri.https('example.test', '/api/admin/overview', {
    'scope': 'summary',
  });
  await http.get(aliasedUri);
  final backendUri = _backendUri(base, '/api/mobile/apps/duoyi/update');
  await http.get(backendUri);
  final Uri typedUri = Uri(path: '/api/announcements', queryParameters: {
    'limit': '5',
  });
  await http.get(typedUri);
  static const String typedPath = '/api/admin/audit-log';
  await client.get(typedPath);
  const apiBase = '/api/admin';
  final joinedPath = apiBase + '/users';
  await client.get(joinedPath);
  await client.delete('/api/admin/users/' + userId);
  await client.getList('/api/announcements');
  await client.post('/api/reminders/email/once', {});
  await client.delete('/api/reminders/email/\$reminderId');
  await client.streamLines('/api/sync/events');
  await client.getRaw(_path('/api/admin/backups', {'limit': 20}));
  await client.getText(_path('/api/admin/backups/export.csv', {'limit': 20}));
  await client.post('/api/focus-rooms/\${Uri.encodeComponent(roomId)}/leave');
  const methods = ['PATCH', 'POST'];
  const profileFallbacks = ['/api/me/profile', '/api/auth/profile'];
  await _sendFirstAvailable(methods, profileFallbacks, {});
	  const avatarFallbacks = ['/api/account/avatar'];
	  await _uploadFirstAvailable(avatarFallbacks, fieldName: 'avatar', filename: 'a.png', bytes: bytes);
	  await client.request('PATCH', '/api/admin/settings', {});
	  await client.requestWithoutRouteDiagnosis('PATCH', '/api/admin/system-settings', {});
	  await client.request(method: 'DELETE', path: '/api/admin/feedback/123');
	}
	''';
    final calls = [
      ..._literalApiMethodCalls(source, 'synthetic.dart'),
      ..._nestedPathApiMethodCalls(source, 'synthetic.dart'),
      ..._firstAvailableApiCalls(source, 'synthetic.dart'),
      ..._multipartApiCalls(source, 'synthetic.dart'),
      ..._uriPathApiCalls(source, 'synthetic.dart'),
      ..._httpUriConstructorApiCalls(source, 'synthetic.dart'),
      ..._httpUriAliasApiCalls(source, 'synthetic.dart'),
      ..._localLiteralAliasApiCalls(source, 'synthetic.dart'),
      ..._genericRequestApiCalls(source, 'synthetic.dart'),
      ..._concatenatedApiMethodCalls(source, 'synthetic.dart'),
    ];

    for (final call in [
      const _RouteContract(
        method: 'PATCH',
        path: '/api/me/profile',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/auth/profile',
        location: '',
      ),
      const _RouteContract(
        method: 'PUT',
        path: '/api/me/profile',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/auth/email-code',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/auth/email-code/send',
        location: '',
      ),
      const _RouteContract(method: 'GET', path: '/api/auth/me', location: ''),
      const _RouteContract(method: 'GET', path: '/api/me', location: ''),
      const _RouteContract(
        method: 'POST',
        path: '/api/me/avatar',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/auth/avatar',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/account/avatar',
        location: '',
      ),
      const _RouteContract(
        method: 'PUT',
        path: '/api/account/avatar',
        location: '',
      ),
      const _RouteContract(method: 'GET', path: '/api/config', location: ''),
      const _RouteContract(
        method: 'GET',
        path: '/api/mobile/apps/duoyi/update',
        location: '',
      ),
      const _RouteContract(method: 'POST', path: '/api/feedback', location: ''),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/overview',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/announcements',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/audit-log',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/users',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/admin/users/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/announcements',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/sync/events',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/backups',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/backups/export.csv',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/focus-rooms/{param}/leave',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/admin/settings',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/admin/system-settings',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/admin/feedback/{param}',
        location: '',
      ),
    ]) {
      expect(
        _hasContract(calls, call),
        isTrue,
        reason: '${call.method} ${call.path}',
      );
    }
  });
}

List<_RouteContract> _extractBackendRoutes(String source) {
  final routePattern = RegExp(
    r'''@app\.(get|post|patch|delete|put)\(\s*(["'])(/api/[^"']*)\2''',
    multiLine: true,
  );
  return [
    for (final match in routePattern.allMatches(source))
      _RouteContract(
        method: match.group(1)!.toUpperCase(),
        path: _normalizePath(match.group(3)!),
        location: 'backend/main.py:${_lineOf(source, match.start)}',
      ),
  ];
}

List<_RouteContract> _extractClientCalls(Directory root) {
  final calls = <_RouteContract>{};
  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final source = file.readAsStringSync();
    final relativePath = file.path.replaceFirst('${root.path}/', 'lib/');
    calls.addAll(_literalApiMethodCalls(source, relativePath));
    calls.addAll(_nestedPathApiMethodCalls(source, relativePath));
    calls.addAll(_getPageApiCalls(source, relativePath));
    calls.addAll(_httpUriParseApiCalls(source, relativePath));
    calls.addAll(_httpUriConstructorApiCalls(source, relativePath));
    calls.addAll(_httpUriAliasApiCalls(source, relativePath));
    calls.addAll(_localLiteralAliasApiCalls(source, relativePath));
    calls.addAll(_concatenatedApiMethodCalls(source, relativePath));
    calls.addAll(_firstAvailableApiCalls(source, relativePath));
    calls.addAll(_multipartApiCalls(source, relativePath));
    calls.addAll(_uriPathApiCalls(source, relativePath));
    calls.addAll(_genericRequestApiCalls(source, relativePath));
  }
  return calls.toList()..sort((a, b) => a.location.compareTo(b.location));
}

List<_ApiLiteral> _extractApiLiterals(Directory root) {
  final literals = <_ApiLiteral>{};
  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final quotedStringPattern = RegExp(r'''r?(["'])(.*?)\1''', dotAll: true);

  for (final file in files) {
    final source = file.readAsStringSync();
    final relativePath = file.path.replaceFirst('${root.path}/', 'lib/');
    for (final match in quotedStringPattern.allMatches(source)) {
      final path = _pathFromBackendApiLiteral(match.group(2)!);
      if (path == null) continue;
      literals.add(
        _ApiLiteral(path, '$relativePath:${_lineOf(source, match.start)}'),
      );
    }
  }

  return literals.toList()..sort((a, b) {
    final byPath = a.path.compareTo(b.path);
    if (byPath != 0) return byPath;
    return a.location.compareTo(b.location);
  });
}

List<String> _extractTextApiLiterals(Directory root) {
  if (!root.existsSync()) return const [];
  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => _isAuditableTextFile(file.path))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final matches = <String>[];
  final apiPattern = RegExp(r'/api(?:/[A-Za-z0-9_{}.$%:+-]+)*');

  for (final file in files) {
    final source = file.readAsStringSync();
    for (final match in apiPattern.allMatches(source)) {
      matches.add('${file.path}:${_lineOf(source, match.start)} ${match[0]}');
    }
  }
  return matches;
}

bool _isAuditableTextFile(String path) {
  return path.endsWith('.html') ||
      path.endsWith('.json') ||
      path.endsWith('.js') ||
      path.endsWith('.css') ||
      path.endsWith('.txt') ||
      path.endsWith('.xml');
}

List<_RouteContract> _literalApiMethodCalls(String source, String filePath) {
  final callPattern = RegExp(
    r'\.\s*(get|post|patch|put|delete|getList|getRaw|getText|streamLines|uploadBytes)\s*'
    r'''\(\s*r?(["'])(.*?/api.*?)\2''',
    dotAll: true,
  );
  return [
    for (final match in callPattern.allMatches(source))
      if (_pathFromLiteral(match.group(3)!) case final path?)
        _RouteContract(
          method: _methodForClientCall(match.group(1)!),
          path: path,
          location: '$filePath:${_lineOf(source, match.start)}',
        ),
  ];
}

List<_RouteContract> _nestedPathApiMethodCalls(String source, String filePath) {
  final callPattern = RegExp(
    r'\.\s*(get|post|patch|put|delete|getList|getRaw|getText|streamLines)\s*'
    r'''\(\s*_path\(\s*r?(["'])(.*?/api.*?)\2''',
    dotAll: true,
  );
  return [
    for (final match in callPattern.allMatches(source))
      if (_pathFromLiteral(match.group(3)!) case final path?)
        _RouteContract(
          method: _methodForClientCall(match.group(1)!),
          path: path,
          location: '$filePath:${_lineOf(source, match.start)}',
        ),
  ];
}

List<_RouteContract> _getPageApiCalls(String source, String filePath) {
  final callPattern = RegExp(
    r'''\b_getPage\s*\(\s*r?(["'])(.*?/api.*?)\1''',
    dotAll: true,
  );
  return [
    for (final match in callPattern.allMatches(source))
      if (_pathFromLiteral(match.group(2)!) case final path?)
        _RouteContract(
          method: 'GET',
          path: path,
          location: '$filePath:${_lineOf(source, match.start)}',
        ),
  ];
}

List<_RouteContract> _httpUriParseApiCalls(String source, String filePath) {
  final callPattern = RegExp(
    r'''\bhttp\.(get|post|patch|delete|put)\s*\(\s*Uri\.parse\(\s*r?(["'])(.*?/api.*?)\2''',
    dotAll: true,
  );
  return [
    for (final match in callPattern.allMatches(source))
      if (_pathFromLiteral(match.group(3)!) case final path?)
        _RouteContract(
          method: match.group(1)!.toUpperCase(),
          path: path,
          location: '$filePath:${_lineOf(source, match.start)}',
        ),
  ];
}

List<_RouteContract> _httpUriConstructorApiCalls(
  String source,
  String filePath,
) {
  final callPattern = RegExp(
    r'''\bhttp\.(get|post|patch|delete|put)\s*\(\s*Uri\.(?:https|http)\s*\(\s*r?(["'])(.*?)\2\s*,\s*r?(["'])(.*?/api.*?)\4''',
    dotAll: true,
    caseSensitive: false,
  );
  return [
    for (final match in callPattern.allMatches(source))
      if (_pathFromLiteral(match.group(5)!) case final path?)
        _RouteContract(
          method: match.group(1)!.toUpperCase(),
          path: path,
          location: '$filePath:${_lineOf(source, match.start)}',
        ),
  ];
}

List<_RouteContract> _httpUriAliasApiCalls(String source, String filePath) {
  final aliases = <String, List<_ApiLiteral>>{};
  final declarationPattern = RegExp(
    r'''\b(?:static\s+)?(?:final|const|var)\s+(?:(?:Uri)\s+)?(\w+)\s*=\s*([^;]*\b(?:Uri\.(?:parse|https|http)|Uri|_backendUri)\s*\([^;]*\)[^;]*)\s*;''',
    dotAll: true,
  );
  final uriParsePattern = RegExp(
    r'''\bUri\.parse\s*\(\s*r?(["'])(.*?)\1\s*\)''',
    dotAll: true,
  );
  final uriConstructorPattern = RegExp(
    r'''\bUri\.(?:https|http)\s*\(\s*r?(["'])(.*?)\1\s*,\s*r?(["'])(.*?)\3''',
    dotAll: true,
  );
  final uriPathPattern = RegExp(
    r'''\bUri\s*\(\s*path\s*:\s*r?(["'])(.*?)\1''',
    dotAll: true,
  );
  final backendUriPattern = RegExp(
    r'''\b_backendUri\s*\(\s*[^,]+,\s*r?(["'])(.*?)\1''',
    dotAll: true,
  );
  for (final declaration in declarationPattern.allMatches(source)) {
    final literals = <_ApiLiteral>[];
    final initializer = declaration.group(2)!;
    for (final uriMatch in uriParsePattern.allMatches(initializer)) {
      final path = _pathFromLiteral(uriMatch.group(2)!);
      if (path == null) continue;
      if (literals.any((literal) => literal.path == path)) continue;
      literals.add(
        _ApiLiteral(path, '$filePath:${_lineOf(source, declaration.start)}'),
      );
    }
    for (final uriMatch in uriConstructorPattern.allMatches(initializer)) {
      final path = _pathFromLiteral(uriMatch.group(4)!);
      if (path == null) continue;
      if (literals.any((literal) => literal.path == path)) continue;
      literals.add(
        _ApiLiteral(path, '$filePath:${_lineOf(source, declaration.start)}'),
      );
    }
    for (final uriMatch in uriPathPattern.allMatches(initializer)) {
      final path = _pathFromLiteral(uriMatch.group(2)!);
      if (path == null) continue;
      if (literals.any((literal) => literal.path == path)) continue;
      literals.add(
        _ApiLiteral(path, '$filePath:${_lineOf(source, declaration.start)}'),
      );
    }
    for (final uriMatch in backendUriPattern.allMatches(initializer)) {
      final path = _pathFromLiteral(uriMatch.group(2)!);
      if (path == null) continue;
      if (literals.any((literal) => literal.path == path)) continue;
      literals.add(
        _ApiLiteral(path, '$filePath:${_lineOf(source, declaration.start)}'),
      );
    }
    if (literals.isNotEmpty) {
      aliases[declaration.group(1)!] = literals;
    }
  }
  if (aliases.isEmpty) return const [];

  final calls = <_RouteContract>[];
  final aliasCallPattern = RegExp(
    r'\bhttp\.(get|post|patch|delete|put)\s*\(\s*(\w+)\b',
    dotAll: true,
  );
  for (final match in aliasCallPattern.allMatches(source)) {
    final literals = aliases[match.group(2)!];
    if (literals == null) continue;
    for (final literal in literals) {
      calls.add(
        _RouteContract(
          method: match.group(1)!.toUpperCase(),
          path: literal.path,
          location:
              '$filePath:${_lineOf(source, match.start)} via ${literal.location}',
        ),
      );
    }
  }
  return calls;
}

List<_RouteContract> _localLiteralAliasApiCalls(
  String source,
  String filePath,
) {
  final aliases = <String, _ApiLiteral>{};
  final declarationPattern = RegExp(
    r'''\b(?:static\s+)?(?:final|const|var)\s+(?:(?:String)\s+)?(\w+)\s*=\s*([^;]*);''',
    dotAll: true,
  );
  for (final match in declarationPattern.allMatches(source)) {
    final path = _pathFromStringExpression(match.group(2)!, aliases);
    if (path == null) continue;
    aliases[match.group(1)!] = _ApiLiteral(
      path,
      '$filePath:${_lineOf(source, match.start)}',
    );
  }
  if (aliases.isEmpty) return const [];

  final calls = <_RouteContract>[];
  final aliasCallPattern = RegExp(
    r'\.\s*(get|post|patch|put|delete|getList|getRaw|getText|streamLines|uploadBytes)\s*'
    r'\(\s*(\w+)\b',
    dotAll: true,
  );
  for (final match in aliasCallPattern.allMatches(source)) {
    final alias = aliases[match.group(2)!];
    if (alias == null) continue;
    calls.add(
      _RouteContract(
        method: _methodForClientCall(match.group(1)!),
        path: alias.path,
        location:
            '$filePath:${_lineOf(source, match.start)} via ${alias.location}',
      ),
    );
  }
  return calls;
}

List<_RouteContract> _concatenatedApiMethodCalls(
  String source,
  String filePath,
) {
  final callPattern = RegExp(
    r'''\.\s*(get|post|patch|put|delete|getList|getRaw|getText|streamLines|uploadBytes)\s*\(\s*r?(["'])(.*?/api.*?)\2\s*\+''',
    dotAll: true,
  );
  return [
    for (final match in callPattern.allMatches(source))
      if (_pathFromConcatenatedPrefix(match.group(3)!) case final path?)
        _RouteContract(
          method: _methodForClientCall(match.group(1)!),
          path: path,
          location: '$filePath:${_lineOf(source, match.start)}',
        ),
  ];
}

List<_RouteContract> _firstAvailableApiCalls(String source, String filePath) {
  final calls = <_RouteContract>[];
  final quotedStringPattern = RegExp(r'''r?(["'])(.*?)\1''', dotAll: true);
  final listAliases = _stringListAliases(source);
  final sendPattern = RegExp(
    r'''\b_sendFirstAvailable\s*\(\s*(?:const\s*)?\[([^\]]*)\]\s*,\s*(?:const\s*)?\[([^\]]*)\]''',
    dotAll: true,
  );
  for (final match in sendPattern.allMatches(source)) {
    final methods = [
      for (final method in quotedStringPattern.allMatches(match.group(1)!))
        method.group(2)!.toUpperCase(),
    ];
    final paths = [
      for (final path in quotedStringPattern.allMatches(match.group(2)!))
        ?_pathFromLiteral(path.group(2)!),
    ];
    for (final method in methods) {
      for (final path in paths) {
        calls.add(
          _RouteContract(
            method: method,
            path: path,
            location: '$filePath:${_lineOf(source, match.start)}',
          ),
        );
      }
    }
  }

  final getRawPattern = RegExp(
    r'''\b_getRawFirstAvailable\s*\(\s*(?:const\s*)?\[([^\]]*)\]''',
    dotAll: true,
  );
  for (final match in getRawPattern.allMatches(source)) {
    for (final path in quotedStringPattern.allMatches(match.group(1)!)) {
      final normalized = _pathFromLiteral(path.group(2)!);
      if (normalized == null) continue;
      calls.add(
        _RouteContract(
          method: 'GET',
          path: normalized,
          location: '$filePath:${_lineOf(source, match.start)}',
        ),
      );
    }
  }

  final sendAliasPattern = RegExp(
    r'''\b_sendFirstAvailable\s*\(\s*(\w+)\s*,\s*(\w+)''',
    dotAll: true,
  );
  for (final match in sendAliasPattern.allMatches(source)) {
    final methods = listAliases[match.group(1)!];
    final rawPaths = listAliases[match.group(2)!];
    if (methods == null || rawPaths == null) continue;
    final paths = [for (final rawPath in rawPaths) ?_pathFromLiteral(rawPath)];
    for (final method in methods.map((value) => value.toUpperCase())) {
      for (final path in paths) {
        calls.add(
          _RouteContract(
            method: method,
            path: path,
            location: '$filePath:${_lineOf(source, match.start)}',
          ),
        );
      }
    }
  }

  final postPattern = RegExp(
    r'''\b_post(?:EmailCode)?FirstAvailable\s*\(\s*(?:const\s*)?\[([^\]]*)\]''',
    dotAll: true,
  );
  for (final match in postPattern.allMatches(source)) {
    for (final path in quotedStringPattern.allMatches(match.group(1)!)) {
      final normalized = _pathFromLiteral(path.group(2)!);
      if (normalized == null) continue;
      calls.add(
        _RouteContract(
          method: 'POST',
          path: normalized,
          location: '$filePath:${_lineOf(source, match.start)}',
        ),
      );
    }
  }
  final postAliasPattern = RegExp(
    r'''\b_post(?:EmailCode)?FirstAvailable\s*\(\s*(\w+)''',
    dotAll: true,
  );
  for (final match in postAliasPattern.allMatches(source)) {
    final rawPaths = listAliases[match.group(1)!];
    if (rawPaths == null) continue;
    for (final rawPath in rawPaths) {
      final normalized = _pathFromLiteral(rawPath);
      if (normalized == null) continue;
      calls.add(
        _RouteContract(
          method: 'POST',
          path: normalized,
          location: '$filePath:${_lineOf(source, match.start)}',
        ),
      );
    }
  }

  final uploadPattern = RegExp(
    r'''\b_uploadFirstAvailable\s*\(\s*(?:const\s*)?\[([^\]]*)\]''',
    dotAll: true,
  );
  for (final match in uploadPattern.allMatches(source)) {
    for (final path in quotedStringPattern.allMatches(match.group(1)!)) {
      final normalized = _pathFromLiteral(path.group(2)!);
      if (normalized == null) continue;
      for (final method in ['POST', 'PATCH', 'PUT']) {
        calls.add(
          _RouteContract(
            method: method,
            path: normalized,
            location: '$filePath:${_lineOf(source, match.start)}',
          ),
        );
      }
    }
  }
  final uploadAliasPattern = RegExp(
    r'''\b_uploadFirstAvailable\s*\(\s*(\w+)''',
    dotAll: true,
  );
  for (final match in uploadAliasPattern.allMatches(source)) {
    final rawPaths = listAliases[match.group(1)!];
    if (rawPaths == null) continue;
    for (final rawPath in rawPaths) {
      final normalized = _pathFromLiteral(rawPath);
      if (normalized == null) continue;
      for (final method in ['POST', 'PATCH', 'PUT']) {
        calls.add(
          _RouteContract(
            method: method,
            path: normalized,
            location: '$filePath:${_lineOf(source, match.start)}',
          ),
        );
      }
    }
  }

  final getPattern = RegExp(
    r'''\b_getFirstAvailable\s*\(\s*(?:const\s*)?\[([^\]]*)\]''',
    dotAll: true,
  );
  for (final match in getPattern.allMatches(source)) {
    for (final path in quotedStringPattern.allMatches(match.group(1)!)) {
      final normalized = _pathFromLiteral(path.group(2)!);
      if (normalized == null) continue;
      calls.add(
        _RouteContract(
          method: 'GET',
          path: normalized,
          location: '$filePath:${_lineOf(source, match.start)}',
        ),
      );
    }
  }
  final getAliasPattern = RegExp(
    r'''\b_getFirstAvailable\s*\(\s*(\w+)''',
    dotAll: true,
  );
  for (final match in getAliasPattern.allMatches(source)) {
    final rawPaths = listAliases[match.group(1)!];
    if (rawPaths == null) continue;
    for (final rawPath in rawPaths) {
      final normalized = _pathFromLiteral(rawPath);
      if (normalized == null) continue;
      calls.add(
        _RouteContract(
          method: 'GET',
          path: normalized,
          location: '$filePath:${_lineOf(source, match.start)}',
        ),
      );
    }
  }

  return calls;
}

List<_RouteContract> _multipartApiCalls(String source, String filePath) {
  final callPattern = RegExp(
    r'''\bMultipartRequest\s*\(\s*r?(["'])(GET|POST|PATCH|PUT|DELETE)\1\s*,\s*(?:Uri\.parse\s*\(\s*r?(["'])(.*?/api.*?)\3|Uri\s*\(\s*path\s*:\s*r?(["'])(.*?/api.*?)\5)''',
    dotAll: true,
    caseSensitive: false,
  );
  return [
    for (final match in callPattern.allMatches(source))
      if (_pathFromLiteral(match.group(4) ?? match.group(6)!) case final path?)
        _RouteContract(
          method: match.group(2)!.toUpperCase(),
          path: path,
          location: '$filePath:${_lineOf(source, match.start)}',
        ),
  ];
}

List<_RouteContract> _uriPathApiCalls(String source, String filePath) {
  final callPattern = RegExp(
    r'''\bhttp\.(get|post|patch|put|delete)\s*\(\s*Uri\s*\(\s*path\s*:\s*r?(["'])(.*?/api.*?)\2''',
    dotAll: true,
    caseSensitive: false,
  );
  return [
    for (final match in callPattern.allMatches(source))
      if (_pathFromLiteral(match.group(3)!) case final path?)
        _RouteContract(
          method: match.group(1)!.toUpperCase(),
          path: path,
          location: '$filePath:${_lineOf(source, match.start)}',
        ),
  ];
}

List<_RouteContract> _genericRequestApiCalls(String source, String filePath) {
  final positionalPattern = RegExp(
    r'''\.\s*request(?:WithoutRouteDiagnosis)?\s*\(\s*r?(["'])(GET|POST|PATCH|PUT|DELETE)\1\s*,\s*r?(["'])(.*?/api.*?)\3''',
    dotAll: true,
    caseSensitive: false,
  );
  final namedPattern = RegExp(
    r'''\.\s*request(?:WithoutRouteDiagnosis)?\s*\([^;]*?\bmethod\s*:\s*r?(["'])(GET|POST|PATCH|PUT|DELETE)\1[^;]*?\bpath\s*:\s*r?(["'])(.*?/api.*?)\3''',
    dotAll: true,
    caseSensitive: false,
  );
  return [
    for (final match in positionalPattern.allMatches(source))
      if (_pathFromLiteral(match.group(4)!) case final path?)
        _RouteContract(
          method: match.group(2)!.toUpperCase(),
          path: path,
          location: '$filePath:${_lineOf(source, match.start)}',
        ),
    for (final match in namedPattern.allMatches(source))
      if (_pathFromLiteral(match.group(4)!) case final path?)
        _RouteContract(
          method: match.group(2)!.toUpperCase(),
          path: path,
          location: '$filePath:${_lineOf(source, match.start)}',
        ),
  ];
}

Map<String, List<String>> _stringListAliases(String source) {
  final aliases = <String, List<String>>{};
  final declarationPattern = RegExp(
    r'''\b(?:static\s+)?(?:final|const|var)\s+(?:(?:List\s*<\s*String\s*>)\s+)?(\w+)\s*=\s*(?:const\s*)?\[([^\]]*)\]''',
    dotAll: true,
  );
  final quotedStringPattern = RegExp(r'''r?(["'])(.*?)\1''', dotAll: true);
  for (final match in declarationPattern.allMatches(source)) {
    aliases[match.group(1)!] = [
      for (final value in quotedStringPattern.allMatches(match.group(2)!))
        value.group(2)!,
    ];
  }
  return aliases;
}

String _methodForClientCall(String method) {
  return switch (method) {
    'post' || 'uploadBytes' => 'POST',
    'patch' => 'PATCH',
    'put' => 'PUT',
    'delete' => 'DELETE',
    _ => 'GET',
  };
}

String? _pathFromLiteral(String literal) {
  final apiMatch = RegExp(r'/api(?=/|\?|$)').firstMatch(literal);
  if (apiMatch == null) return null;
  return _normalizePath(literal.substring(apiMatch.start));
}

String? _pathFromStringExpression(
  String expression,
  Map<String, _ApiLiteral> aliases,
) {
  final parts = expression.split('+');
  final buffer = StringBuffer();
  for (final rawPart in parts) {
    final part = rawPart.trim();
    if (part.isEmpty) continue;
    final literal = RegExp(
      r'''^r?(["'])(.*)\1$''',
      dotAll: true,
    ).firstMatch(part);
    if (literal != null) {
      buffer.write(literal.group(2)!);
      continue;
    }
    final alias = aliases[part];
    if (alias != null) {
      buffer.write(alias.path);
      continue;
    }
    if (buffer.toString().contains('/api')) {
      if (!buffer.toString().endsWith('/')) buffer.write('/');
      buffer.write('{param}');
    }
  }
  if (!buffer.toString().contains('/api')) return null;
  return _pathFromLiteral(buffer.toString());
}

String? _pathFromConcatenatedPrefix(String prefix) {
  final expanded = prefix.endsWith('/') ? '$prefix{param}' : '$prefix/{param}';
  return _pathFromLiteral(expanded);
}

String? _pathFromBackendApiLiteral(String literal) {
  final path = _pathFromLiteral(literal);
  if (path == null) return null;
  if (path.contains(RegExp(r'\s'))) return null;
  if (!RegExp(r'^/api(?:/[A-Za-z0-9_{}.$%:+-]+)*$').hasMatch(path)) {
    return null;
  }
  return path;
}

String _normalizePath(String path) {
  var normalized = path.split('?').first.trim();
  normalized = normalized
      .replaceAll(RegExp(r'\$\{[^}]+\}'), '{param}')
      .replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'), '{param}');
  if (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

bool _samePathShape(_RouteContract route, _RouteContract call) {
  final routeSegments = route.path.split('/');
  final callSegments = call.path.split('/');
  if (routeSegments.length != callSegments.length) return false;
  for (var i = 0; i < routeSegments.length; i += 1) {
    final routeSegment = routeSegments[i];
    final callSegment = callSegments[i];
    if (routeSegment == callSegment) continue;
    if (_isPathParam(routeSegment) || _isPathParam(callSegment)) continue;
    return false;
  }
  return true;
}

bool _isPathParam(String segment) =>
    segment.startsWith('{') && segment.endsWith('}');

bool _hasContract(List<_RouteContract> contracts, _RouteContract expected) {
  return contracts.any(
    (contract) =>
        contract.method == expected.method &&
        _samePathShape(contract, expected),
  );
}

int _lineOf(String source, int offset) {
  return '\n'.allMatches(source.substring(0, offset)).length + 1;
}

class _RouteContract {
  final String method;
  final String path;
  final String location;

  const _RouteContract({
    required this.method,
    required this.path,
    required this.location,
  });

  @override
  bool operator ==(Object other) =>
      other is _RouteContract &&
      method == other.method &&
      path == other.path &&
      location == other.location;

  @override
  int get hashCode => Object.hash(method, path, location);
}

class _ApiLiteral {
  final String path;
  final String location;

  const _ApiLiteral(this.path, this.location);

  @override
  bool operator ==(Object other) =>
      other is _ApiLiteral && path == other.path && location == other.location;

  @override
  int get hashCode => Object.hash(path, location);
}
