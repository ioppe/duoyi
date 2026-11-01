import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/feature_flags.dart';
import 'package:duoyi/models/server_config_status.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/backend_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: const {'content-type': 'application/json'},
);

class _Harness {
  final requests = <String>[];
  final configStarted = Completer<void>();
  Completer<http.Response>? configGate;
  bool configFails = false;
  bool syncFails = false;
  bool backupEnabled = true;
  late final AuthProvider auth;
  late final CloudSyncProvider cloud;
  late final BackendSyncCoordinator coordinator;

  int get configCount =>
      requests.where((request) => request == 'GET /api/config').length;
  int get syncCount =>
      requests.where((request) => request.startsWith('POST /api/sync')).length;

  ApiClient client(String url, String? token) => ApiClient(
    baseUrl: url,
    token: token,
    httpClient: MockClient((request) async {
      final route = request.url.path;
      requests.add('${request.method} $route');
      if (route == '/api/config') {
        if (!configStarted.isCompleted) configStarted.complete();
        if (configGate != null && request.url.host == 'fixture.test') {
          return configGate!.future;
        }
        if (configFails) return _json({'detail': 'fixture offline'}, 503);
        return _json({
          'ai_enabled': true,
          'backup_enabled': backupEnabled,
          'server_host': request.url.host,
        });
      }
      if (request.method == 'POST' && route.startsWith('/api/sync')) {
        if (syncFails) return _json({'detail': 'fixture sync failed'}, 503);
        return _json({
          'server_updated_at': '2026-11-01T12:00:00.000Z',
          'server_version': 1,
        });
      }
      return _json({});
    }),
  );

  static Future<_Harness> create({
    bool loggedIn = true,
    bool autoSync = true,
  }) async {
    SharedPreferences.setMockInitialValues({'sync_auto': autoSync});
    final harness = _Harness();
    final state = loggedIn
        ? const AuthState(
            userId: 'fixture-user',
            username: 'fixture',
            token: 'fixture-only-token',
          )
        : const AuthState();
    harness.auth = AuthProvider(
      initialState: state,
      client: harness.client('https://fixture.test', state.token),
      clientFactory: harness.client,
    );
    harness.cloud = CloudSyncProvider();
    harness.cloud.apiClientGetter = () => harness.auth.client;
    harness.cloud.serverConfigGetter = () => harness.auth.serverConfig;
    await harness.cloud.loadFromStorage();
    harness.coordinator = BackendSyncCoordinator(
      auth: harness.auth,
      cloud: harness.cloud,
    );
    addTearDown(() {
      harness.coordinator.dispose();
      harness.cloud.dispose();
      harness.auth.dispose();
    });
    return harness;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(FeatureFlags.resetAllOverrides);
  tearDown(FeatureFlags.resetAllOverrides);

  test('启动刷新先拿配置，再以当前登录身份同步', () async {
    final harness = await _Harness.create();
    await harness.coordinator.refresh();
    expect(harness.requests.take(2), ['GET /api/config', 'POST /api/sync']);
    expect(harness.configCount, 1);
    expect(harness.syncCount, 1);
    expect(harness.auth.serverConfigStatus, ServerConfigStatus.ready);
    expect(harness.cloud.hasEverSynced, isTrue);
    expect(harness.cloud.lastError, isNull);
  });

  test('访客只取公开配置，不请求任何个人同步接口', () async {
    final harness = await _Harness.create(loggedIn: false);
    await harness.coordinator.refresh(force: true);
    expect(harness.requests, ['GET /api/config']);
    expect(harness.cloud.hasEverSynced, isFalse);
    expect(harness.cloud.lastError, isNull);
  });

  test('关闭自动同步时后台只刷新配置，手动仍可执行一次', () async {
    final harness = await _Harness.create(autoSync: false);
    await harness.coordinator.refresh();
    expect(harness.syncCount, 0);
    await harness.coordinator.refresh(force: true);
    expect(harness.configCount, 2);
    expect(harness.syncCount, 1);
    expect(harness.cloud.config.autoSync, isFalse);
    expect(harness.requests, isNot(contains('GET /api/sync/events')));
  });

  test('手动点击升级在途后台刷新，配置与数据请求均不重复', () async {
    final harness = await _Harness.create(autoSync: false);
    harness.configGate = Completer<http.Response>();
    final background = harness.coordinator.refresh();
    await harness.configStarted.future;
    final manual = harness.coordinator.refresh(force: true);
    final repeated = harness.coordinator.refresh(force: true);
    expect(identical(background, manual), isTrue);
    expect(identical(manual, repeated), isTrue);
    harness.configGate!.complete(
      _json({'ai_enabled': true, 'backup_enabled': true}),
    );
    await Future.wait([background, manual, repeated]);
    expect(harness.configCount, 1);
    expect(harness.syncCount, 1);
    expect(harness.cloud.config.autoSync, isFalse);
  });

  test('配置失败不开始同步，也不冒充成功，恢复后可立即重试', () async {
    final harness = await _Harness.create();
    harness.configFails = true;
    await expectLater(
      harness.coordinator.refresh(),
      throwsA(isA<BackendSyncConfigException>()),
    );
    expect(harness.auth.serverConfigStatus, ServerConfigStatus.failed);
    expect(harness.syncCount, 0);
    expect(harness.cloud.hasEverSynced, isFalse);
    harness.configFails = false;
    await harness.coordinator.refresh(force: true);
    expect(harness.configCount, 2);
    expect(harness.syncCount, 1);
    expect(harness.cloud.hasEverSynced, isTrue);
  });

  test('管理员关闭备份时手动操作不上传，并显示真实关闭原因', () async {
    final harness = await _Harness.create();
    harness.backupEnabled = false;
    await harness.cloud.resetForAccountChange();
    await harness.coordinator.refresh(force: true);
    expect(harness.configCount, 1);
    expect(harness.syncCount, 0);
    expect(harness.cloud.hasEverSynced, isFalse);
    expect(harness.cloud.lastError, '管理员已关闭云端备份');
  });

  test('配置在途切换服务器，旧连接不能恢复同步或覆盖新配置', () async {
    final harness = await _Harness.create();
    harness.configGate = Completer<http.Response>();
    final oldRefresh = harness.coordinator.refresh();
    await harness.configStarted.future;
    await harness.auth.logout();
    await harness.auth.configureServer('https://new.test');
    await harness.coordinator.refresh();
    harness.configGate!.complete(
      _json({
        'ai_enabled': false,
        'backup_enabled': true,
        'server_host': 'fixture.test',
      }),
    );
    await oldRefresh;
    expect(harness.auth.baseUrl, 'https://new.test');
    expect(harness.auth.serverConfig['server_host'], 'new.test');
    expect(harness.auth.state.isLoggedIn, isFalse);
    expect(harness.syncCount, 0);
    expect(harness.cloud.hasEverSynced, isFalse);
  });

  test('销毁后配置迟返回不能开始同步', () async {
    final harness = await _Harness.create();
    harness.configGate = Completer<http.Response>();
    final refresh = harness.coordinator.refresh();
    await harness.configStarted.future;
    harness.coordinator.dispose();
    harness.configGate!.complete(_json({'ai_enabled': true}));
    await refresh;
    expect(harness.syncCount, 0);
    expect(harness.cloud.hasEverSynced, isFalse);
  });

  test('关闭同步特性时仍可刷新配置，但不发个人数据请求', () async {
    FeatureFlags.overrideCloudSyncV2(false);
    final harness = await _Harness.create();
    await harness.coordinator.refresh(force: true);
    expect(harness.configCount, 1);
    expect(harness.syncCount, 0);
    expect(harness.cloud.hasEverSynced, isFalse);
  });

  test('业务同步失败由状态呈现，手动重试后可恢复', () async {
    final harness = await _Harness.create();
    harness.syncFails = true;
    await harness.coordinator.refresh(force: true);
    expect(harness.cloud.hasEverSynced, isFalse);
    expect(harness.cloud.lastError, isNotNull);
    harness.syncFails = false;
    await harness.coordinator.refresh(force: true);
    expect(harness.syncCount, 2);
    expect(harness.cloud.lastError, isNull);
    expect(harness.cloud.hasEverSynced, isTrue);
  });
}
