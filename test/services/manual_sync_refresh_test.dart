import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/sync_status_presenter.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/backend_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: const {'content-type': 'application/json'},
);
Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

String _hash(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(_canonical(value)))).toString();

Object? _serverValue(String key, Object? value) {
  if (key == 'quick_capture_templates' && value is Map) {
    final normalized = Map<String, dynamic>.from(value);
    if ((normalized['updatedAt']?.toString() ?? '').isEmpty) {
      normalized.remove('updatedAt');
    }
    normalized['items'] ??= <dynamic>[];
    return normalized;
  }
  return value;
}

class _Fixture {
  final paths = <String>[];
  final firstSyncStarted = Completer<void>();
  Completer<http.Response>? firstSyncGate;
  List<Map<String, Object>> remoteTodos = [];
  Map<String, dynamic> serverPayload = {};
  final cloud = CloudSyncProvider();
  late final AuthProvider auth;
  late final BackendSyncCoordinator coordinator;
  late final SyncStatusController controller;
  bool _cloudDisposed = false;

  List<String> get syncPaths =>
      paths.where((path) => path.startsWith('POST /api/sync')).toList();

  http.Response response() => _json({
    'server_version': syncPaths.length,
    'server_updated_at': '2026-11-05T12:00:00.000Z',
    'todos': remoteTodos,
    'quick_capture_templates': _serverValue(
      'quick_capture_templates',
      serverPayload['quick_capture_templates'],
    ),
    'collection_hashes': {
      for (final entry in serverPayload.entries)
        entry.key: _hash(
          entry.key == 'todos'
              ? remoteTodos
              : _serverValue(entry.key, entry.value),
        ),
    },
  });

  static Future<_Fixture> create({bool autoSync = false}) async {
    SharedPreferences.setMockInitialValues({'sync_auto': autoSync});
    final fixture = _Fixture();
    final client = ApiClient(
      baseUrl: 'https://fixture.test',
      token: 'fixture-token',
      httpClient: MockClient((request) async {
        fixture.paths.add('${request.method} ${request.url.path}');
        if (request.url.path == '/api/config') {
          return _json({'backup_enabled': true, 'ai_enabled': true});
        }
        if (request.method == 'POST' &&
            request.url.path.startsWith('/api/sync')) {
          if (request.url.path == '/api/sync') {
            fixture.serverPayload =
                jsonDecode(request.body) as Map<String, dynamic>;
          }
          if (!fixture.firstSyncStarted.isCompleted) {
            fixture.firstSyncStarted.complete();
          }
          if (fixture.syncPaths.length == 1 && fixture.firstSyncGate != null) {
            return fixture.firstSyncGate!.future;
          }
          return fixture.response();
        }
        return _json({});
      }),
    );
    fixture.auth = AuthProvider(
      initialState: const AuthState(
        userId: 'fixture-user',
        username: 'fixture',
        token: 'fixture-token',
      ),
      client: client,
    );
    fixture.cloud.apiClientGetter = () => fixture.auth.client;
    fixture.cloud.serverConfigGetter = () => fixture.auth.serverConfig;
    await fixture.cloud.loadFromStorage();
    fixture.coordinator = BackendSyncCoordinator(
      auth: fixture.auth,
      cloud: fixture.cloud,
    );
    fixture.controller = SyncStatusController(
      source: fixture.cloud,
      onSyncRequested: () => fixture.coordinator.refresh(force: true),
    );
    addTearDown(() {
      fixture.controller.dispose();
      fixture.coordinator.dispose();
      if (!fixture._cloudDisposed) fixture.cloud.dispose();
      fixture.auth.dispose();
    });
    return fixture;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('未创建快捷模板时不反复上传空时间戳，手动请求仍主动拉取', () async {
    final fixture = await _Fixture.create();
    await fixture.cloud.syncNow();
    await fixture.cloud.syncNow();
    expect(fixture.syncPaths, ['POST /api/sync']);
    await fixture.controller.requestSync();
    expect(fixture.syncPaths, ['POST /api/sync', 'POST /api/sync/pull']);
    expect(fixture.cloud.lastError, isNull);
  });

  for (final hasItems in [false, true]) {
    test('快捷模板${hasItems ? "内容" : "显式清空"}的真实更新时间保持不变', () async {
      final fixture = await _Fixture.create();
      final prefs = await SharedPreferences.getInstance();
      const stamp = '2026-11-06T08:00:00.000Z';
      final items = hasItems
          ? [
              {'id': 'saved-template', 'title': '保留模板'},
            ]
          : [];
      await prefs.setString(
        'duoyi_quick_capture_templates_v1',
        jsonEncode(items),
      );
      await prefs.setString('sync_quick_capture_templates_updated_at', stamp);
      await fixture.cloud.syncNow();
      expect(fixture.serverPayload['quick_capture_templates'], {
        'updatedAt': stamp,
        'items': items,
      });
      await fixture.cloud.syncNow();
      expect(fixture.syncPaths, ['POST /api/sync']);
      expect(prefs.getString('sync_quick_capture_templates_updated_at'), stamp);
      expect(
        jsonDecode(prefs.getString('duoyi_quick_capture_templates_v1')!),
        items,
      );
    });
  }

  test('无本地变动时手动拉取远端，等待页面回载并支持再次刷新', () async {
    final fixture = await _Fixture.create();
    await fixture.controller.requestSync();
    expect(fixture.syncPaths, ['POST /api/sync']);
    fixture.remoteTodos = [
      {
        'id': 'remote-todo',
        'title': '另一设备新增',
        'updatedAt': '2026-11-05T12:00:00.000Z',
      },
    ];
    final reloadStarted = Completer<void>();
    final releaseReload = Completer<void>();
    fixture.cloud.onSynced = (collections) async {
      expect(collections, contains('todos'));
      if (!reloadStarted.isCompleted) reloadStarted.complete();
      await releaseReload.future;
    };
    var finished = false;
    final refresh = fixture.controller.requestSync();
    unawaited(refresh.then((_) => finished = true));
    await reloadStarted.future.timeout(const Duration(seconds: 5));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('todos'), contains('remote-todo'));
    expect(finished, isFalse);
    expect(fixture.controller.isSyncing, isTrue);
    releaseReload.complete();
    await refresh;
    expect(fixture.syncPaths, ['POST /api/sync', 'POST /api/sync/pull']);
    expect(fixture.cloud.config.autoSync, isFalse);
    expect(fixture.paths, isNot(contains('GET /api/sync/events')));
    await fixture.controller.requestSync();
    expect(fixture.syncPaths.last, 'POST /api/sync/pull');
    expect(fixture.syncPaths, hasLength(3));
  });

  test('后台同步中下拉等待后主动拉取，重复手动请求只执行一次', () async {
    final fixture = await _Fixture.create();
    fixture.firstSyncGate = Completer<http.Response>();
    final background = fixture.cloud.syncNow();
    await fixture.firstSyncStarted.future;
    var finished = false;
    final manual = fixture.controller.requestSync();
    expect(identical(manual, fixture.controller.requestSync()), isTrue);
    unawaited(manual.then((_) => finished = true));
    await Future<void>.delayed(Duration.zero);
    expect(fixture.syncPaths, hasLength(1));
    expect(finished, isFalse);
    fixture.firstSyncGate!.complete(fixture.response());
    await Future.wait([background, manual]);
    expect(fixture.syncPaths, ['POST /api/sync', 'POST /api/sync/pull']);
    expect(finished, isTrue);
  });

  test('等待同步期间切号，旧手动请求不会在新账号执行或回写', () async {
    final fixture = await _Fixture.create();
    fixture.firstSyncGate = Completer<http.Response>();
    final background = fixture.cloud.syncNow();
    await fixture.firstSyncStarted.future;
    final manual = fixture.cloud.syncNowAndPull();
    await fixture.cloud.resetForAccountChange();
    fixture.cloud.resumeForActiveAccount();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'todos',
      jsonEncode([
        {'id': 'new-account'},
      ]),
    );
    await manual.timeout(const Duration(seconds: 5));
    fixture.remoteTodos = [
      {'id': 'old-account'},
    ];
    fixture.firstSyncGate!.complete(fixture.response());
    await background;
    expect(fixture.syncPaths, hasLength(1));
    expect(prefs.getString('todos'), contains('new-account'));
    expect(prefs.getString('todos'), isNot(contains('old-account')));
  });

  test('销毁提供器解除等待且迟到响应不能发起新的拉取', () async {
    final fixture = await _Fixture.create();
    fixture.firstSyncGate = Completer<http.Response>();
    final background = fixture.cloud.syncNow();
    await fixture.firstSyncStarted.future;
    final manual = fixture.cloud.syncNowAndPull();
    fixture.cloud.dispose();
    fixture._cloudDisposed = true;
    await manual.timeout(const Duration(seconds: 5));
    fixture.firstSyncGate!.complete(fixture.response());
    await background;
    expect(fixture.syncPaths, hasLength(1));
  });

  test('手动请求在后台业务同步期间到来，也能升级为主动拉取', () async {
    final fixture = await _Fixture.create(autoSync: true);
    fixture.firstSyncGate = Completer<http.Response>();
    final background = fixture.coordinator.refresh();
    await fixture.firstSyncStarted.future;
    final manual = fixture.coordinator.refresh(force: true);
    expect(identical(background, manual), isTrue);
    fixture.firstSyncGate!.complete(fixture.response());
    await Future.wait([background, manual]);
    expect(fixture.syncPaths, ['POST /api/sync', 'POST /api/sync/pull']);
    expect(
      fixture.paths.where((path) => path == 'GET /api/config'),
      hasLength(1),
    );
  });
}
