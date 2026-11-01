import 'dart:async';
import 'dart:convert';

import 'package:duoyi/models/server_config_status.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object data) => http.Response(jsonEncode(data), 200);

ApiClient _client(
  String baseUrl,
  Future<http.Response> Function(http.Request request) handler,
) => ApiClient(baseUrl: baseUrl, httpClient: MockClient(handler));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('配置成功：loading → 新 map → ready，顺序与回调都正确', () async {
    final events = <String>[];
    var requests = 0;
    final auth = AuthProvider(
      baseUrl: 'https://cfg.test',
      client: _client('https://cfg.test', (request) async {
        requests++;
        expect(request.url.path, '/api/config');
        return _json({'ai_enabled': true, 'ai_model': 'cfg-model'});
      }),
    );
    auth.onServerConfigChanged = (cfg) => events.add('cfg:${cfg['ai_model']}');
    auth.onServerConfigStatusChanged = (status) =>
        events.add('status:${status.name}');

    expect(auth.serverConfigStatus, ServerConfigStatus.unknown);
    await auth.refreshServerConfigFromServer();

    expect(requests, 1);
    expect(auth.serverConfigStatus, ServerConfigStatus.ready);
    expect(auth.serverConfig['ai_enabled'], isTrue);
    // 状态先行登记 loading，map 先落地，ready 最后广播：AI 看到 ready 时开关已就绪。
    expect(events, ['status:loading', 'cfg:cfg-model', 'status:ready']);
  });

  test('配置失败：状态 failed，保留同连接最后一次成功配置', () async {
    var fail = false;
    final auth = AuthProvider(
      baseUrl: 'https://cfg.test',
      client: _client('https://cfg.test', (request) async {
        if (fail) return http.Response('server down', 503);
        return _json({'ai_enabled': true, 'backup_enabled': true});
      }),
    );

    await auth.refreshServerConfigFromServer();
    expect(auth.serverConfigStatus, ServerConfigStatus.ready);

    fail = true;
    await auth.refreshServerConfigFromServer(force: true);
    expect(auth.serverConfigStatus, ServerConfigStatus.failed);
    // 失败不清空配置，也不能被当成「管理员关闭」。
    expect(auth.serverConfig['ai_enabled'], isTrue);
  });

  test('TTL 只对 ready 生效：force 绕过 TTL，失败后可立即重试', () async {
    var requests = 0;
    var fail = false;
    final auth = AuthProvider(
      baseUrl: 'https://cfg.test',
      client: _client('https://cfg.test', (request) async {
        requests++;
        if (fail) return http.Response('offline', 500);
        return _json({'ai_enabled': true});
      }),
    );

    await auth.refreshServerConfigFromServer();
    expect(requests, 1);
    // ready 后 30s 内复用结果，不再发请求。
    await auth.refreshServerConfigFromServer();
    expect(requests, 1);
    // force 绕过 TTL 但在途请求仍复用。
    await auth.refreshServerConfigFromServer(force: true);
    expect(requests, 2);

    fail = true;
    await auth.refreshServerConfigFromServer(force: true);
    expect(auth.serverConfigStatus, ServerConfigStatus.failed);
    // 失败不受 TTL 限制：下一次非 force 调用也要重试。
    fail = false;
    await auth.refreshServerConfigFromServer();
    expect(requests, 4);
    expect(auth.serverConfigStatus, ServerConfigStatus.ready);
  });

  test('在途 singleflight：并发与状态回调重入都只发一次 GET', () async {
    var requests = 0;
    final gate = Completer<http.Response>();
    late AuthProvider auth;
    final reentrant = <Future<void>>[];
    auth = AuthProvider(
      baseUrl: 'https://cfg.test',
      client: _client('https://cfg.test', (request) async {
        requests++;
        return gate.future;
      }),
    );
    auth.onServerConfigStatusChanged = (status) {
      if (status == ServerConfigStatus.loading) {
        // 同步回调里重入：in-flight 必须已经登记，不能发第二个请求。
        reentrant.add(auth.refreshServerConfigFromServer(force: true));
      }
    };

    final first = auth.refreshServerConfigFromServer();
    final second = auth.refreshServerConfigFromServer(force: true);
    gate.complete(_json({'ai_enabled': true}));
    await Future.wait([first, second]);
    for (final future in reentrant) {
      await future;
    }

    expect(requests, 1);
    expect(auth.serverConfigStatus, ServerConfigStatus.ready);
  });

  test('切服务器后旧请求的迟到成功不改变新连接', () async {
    final oldGate = Completer<http.Response>();
    final auth = AuthProvider(
      client: _client('https://old.test', (request) => oldGate.future),
      clientFactory: (url, token) => _client(
        url,
        (request) async => _json({'server': 'new', 'ai_enabled': false}),
      ),
    );

    final oldRefresh = auth.refreshServerConfigFromServer();
    await auth.configureServer('https://new.test');
    await auth.refreshServerConfigFromServer(force: true);
    expect(auth.serverConfigStatus, ServerConfigStatus.ready);
    expect(auth.serverConfig['server'], 'new');

    oldGate.complete(_json({'server': 'old', 'ai_enabled': true}));
    await oldRefresh;

    expect(auth.baseUrl, 'https://new.test');
    expect(auth.serverConfig['server'], 'new');
    expect(auth.serverConfigStatus, ServerConfigStatus.ready);
    expect(auth.serverConfig['ai_enabled'], isFalse);
  });

  test('切服务器后旧请求的迟到失败不改变新连接状态', () async {
    final oldGate = Completer<http.Response>();
    final auth = AuthProvider(
      client: _client('https://old.test', (request) async {
        await oldGate.future;
        return http.Response('old server down', 500);
      }),
      clientFactory: (url, token) => _client(
        url,
        (request) async => _json({'server': 'new', 'ai_enabled': true}),
      ),
    );

    final statuses = <ServerConfigStatus>[];
    final oldRefresh = auth.refreshServerConfigFromServer();
    await auth.configureServer('https://new.test');
    auth.onServerConfigStatusChanged = statuses.add;
    await auth.refreshServerConfigFromServer(force: true);
    expect(auth.serverConfigStatus, ServerConfigStatus.ready);

    oldGate.complete(http.Response('old server down', 500));
    await oldRefresh;

    // 旧连接的失败既不能把新连接标成 failed，也不能清掉新连接的配置。
    expect(auth.serverConfigStatus, ServerConfigStatus.ready);
    expect(auth.serverConfig['server'], 'new');
    expect(statuses, isNot(contains(ServerConfigStatus.failed)));
  });

  test('冷启动带保存会话：保留登录态并在首屏外拿到 ready 配置', () async {
    final paths = <String>[];
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_server_url': 'https://saved.test',
      'auth_state_server_url': 'https://saved.test',
      'auth_state': jsonEncode({
        'user_id': 'user-1',
        'username': 'saved',
        'token': 'saved-token',
        'coin_balance': 0,
      }),
    });
    final auth = AuthProvider(
      clientFactory: (url, token) => _client(url, (request) async {
        paths.add(request.url.path);
        return _json({'ai_enabled': true});
      }),
    );

    await auth.loadFromStorage();
    expect(auth.state.isLoggedIn, isTrue);
    expect(auth.state.userId, 'user-1');
    expect(auth.baseUrl, 'https://saved.test');
    expect(auth.serverConfigStatus, ServerConfigStatus.ready);
    expect(paths, ['/api/config']);
  });

  test('guest 冷启动也只 GET 公开配置', () async {
    final paths = <String>[];
    SharedPreferences.setMockInitialValues(<String, Object>{
      'auth_server_url': 'https://cfg.test',
    });
    final auth = AuthProvider(
      clientFactory: (url, token) => _client(url, (request) async {
        paths.add(request.url.path);
        return _json({'registration_enabled': true});
      }),
    );

    await auth.loadFromStorage();

    expect(auth.state.isLoggedIn, isFalse);
    expect(paths, ['/api/config']);
    expect(auth.serverConfigStatus, ServerConfigStatus.ready);
  });
}
