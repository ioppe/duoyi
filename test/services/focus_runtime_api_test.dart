import 'dart:convert';

import 'package:duoyi/models/focus_runtime.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/focus_runtime_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 传输层契约：只验证 URL / 方法 / 凭证与解析，不触网。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 反向代理把后端挂在 /duoyi/api 下：HTTP 请求必须保留此前缀。
  const deploymentBase = 'https://focus.example.test/duoyi/api';
  const token = 'api-token';

  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) responder;
  late FocusRuntimeApi api;

  Map<String, dynamic> snapshotJson({
    int revision = 3,
    String session = 's1',
  }) => FocusRuntimeSnapshot(
    serverNowMs: 1700000000000,
    runtime: FocusRuntimeState.empty.copyWith(
      sessionId: session,
      revision: revision,
      status: FocusRuntimeStatus.running,
      anchorAtMs: 1700000000000,
    ),
  ).toJson();

  setUp(() {
    requests = <http.Request>[];
    responder = (_) async => http.Response(jsonEncode(snapshotJson()), 200);
    final transport = MockClient((request) async {
      requests.add(request);
      return responder(request);
    });
    addTearDown(transport.close);
    api = FocusRuntimeApi(
      ApiClient(baseUrl: deploymentBase, token: token, httpClient: transport),
    );
  });

  test(
    'fetchRuntime issues one exact GET with the captured bearer token',
    () async {
      final snapshot = await api.fetchRuntime();

      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(
        requests.single.url.toString(),
        'https://focus.example.test/duoyi/api/focus/runtime',
      );
      expect(requests.single.headers['Authorization'], 'Bearer $token');
      expect(requests.single.body, isEmpty);
      expect(snapshot.runtime.revision, 3);
      expect(snapshot.runtime.sessionId, 's1');
    },
  );

  test('sendCommand posts explicit action with expected revision', () async {
    responder = (_) async =>
        http.Response(jsonEncode({'snapshot': snapshotJson(revision: 8)}), 200);
    final command = FocusRuntimeCommand.create(
      deviceId: 'dev-a',
      sessionId: 's1',
      expectedRevision: 7,
      action: FocusRuntimeAction.pause,
      payload: FocusRuntimeCommand.updatePayload(taskName: 'Deep work'),
    );

    final snapshot = await api.sendCommand(command);

    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(
      requests.single.url.toString(),
      'https://focus.example.test/duoyi/api/focus/runtime/commands',
    );
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['action'], 'pause');
    expect(body['expectedRevision'], 7);
    expect(body['sessionId'], 's1');
    expect(body['deviceId'], 'dev-a');
    expect(body['commandId'], command.commandId);
    final payload = body['payload'] as Map<String, dynamic>;
    expect(payload['taskName'], 'Deep work');
    expect(
      payload.keys,
      everyElement(isIn(FocusRuntimeCommand.updatePayload().keys)),
      reason: 'update 载荷必须是白名单字段',
    );
    // 命令只带显式动作：不得偷偷携带运行态字段。
    expect(body.containsKey('status'), isFalse);
    expect(snapshot.runtime.revision, 8);
  });

  test(
    'mutated token or base URL rejects the request before it is sent',
    () async {
      final client = ApiClient(
        baseUrl: deploymentBase,
        token: 'other-token',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode(snapshotJson()), 200);
        }),
      );
      final pinned = FocusRuntimeApi(client, tokenOverride: token);

      await expectLater(
        pinned.fetchRuntime(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('身份已变化'),
          ),
        ),
      );
      expect(requests, isEmpty);

      client.token = token;
      await pinned.fetchRuntime();
      expect(requests, hasLength(1));

      client.baseUrl = 'https://attacker.example.test/duoyi/api';
      await expectLater(pinned.fetchRuntime(), throwsA(isA<ApiException>()));
      expect(requests, hasLength(1), reason: '换服务器后不得复用旧凭证发请求');

      final anonymous = FocusRuntimeApi(ApiClient(baseUrl: deploymentBase));
      await expectLater(
        anonymous.fetchRuntime(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('请先登录'),
          ),
        ),
      );
      expect(requests, hasLength(1));
    },
  );

  test('websocket URI keeps deployment prefix and encodes the token', () {
    final uri = FocusRuntimeApi.buildRuntimeWebSocketUri(
      baseUrl: 'https://host/prefix/api/',
      token: 'a b/c&d',
    );

    expect(uri, isNotNull);
    expect(uri!.scheme, 'wss');
    expect(uri.host, 'host');
    expect(uri.path, '/prefix/ws/focus/runtime/events');
    // 空格与 & 必须编码，否则会被解析成额外的查询参数。
    expect(uri.queryParameters['token'], 'a b/c&d');
    expect(uri.toString(), isNot(contains('a b/c&d')));
    expect(uri.toString(), contains('token='));

    final plain = FocusRuntimeApi.buildRuntimeWebSocketUri(
      baseUrl: 'http://localhost:8080',
      token: 't',
    );
    expect(plain!.scheme, 'ws');
    expect(plain.port, 8080);
    expect(plain.path, '/ws/focus/runtime/events');

    expect(
      FocusRuntimeApi.buildRuntimeWebSocketUri(
        baseUrl: 'https://host/prefix',
        token: '   ',
      ),
      isNull,
    );
    expect(
      api.eventsUri().toString(),
      contains('/duoyi/ws/focus/runtime/events'),
    );
  });

  test(
    'diagnostics redact the token from uris, query strings and bearer headers',
    () {
      const secret = 'sk-secret-123';
      final text = FocusRuntimeApi.sanitizeDiagnostic(
        'ws error wss://h/ws?token=$secret&mode=1 '
        'Authorization: Bearer $secret raw=$secret',
        token: secret,
      );

      expect(text, isNot(contains(secret)));
      expect(text, contains('<redacted-token>'));
      expect(text, contains('mode=1'));
      expect(
        FocusRuntimeApi.sanitizeDiagnostic('GET /x?access_token=abc123&y=2'),
        isNot(contains('abc123')),
      );
    },
  );

  test(
    'only focus.runtime envelopes with a parseable snapshot are accepted',
    () {
      final accepted = FocusRuntimeApi.parseEventMessage(
        jsonEncode({
          'event': 'focus.runtime',
          'data': snapshotJson(revision: 5),
        }),
      );
      expect(accepted?.runtime.revision, 5);

      // 事件名/结构不符一律丢弃，不制造假状态。
      expect(
        FocusRuntimeApi.parseEventMessage(jsonEncode({'event': 'ping'})),
        isNull,
      );
      expect(
        FocusRuntimeApi.parseEventMessage(
          jsonEncode({'event': 'focus.runtime', 'data': <String, dynamic>{}}),
        ),
        isNull,
      );
      expect(
        FocusRuntimeApi.parseEventMessage(
          jsonEncode({
            'event': 'focus.runtime',
            'data': {
              'serverNowMs': 1,
              'runtime': {'revision': 2},
            },
          }),
        ),
        isNull,
        reason: '缺少 sessionId 的快照不可投影',
      );
      expect(FocusRuntimeApi.parseEventMessage('not-json'), isNull);
      expect(FocusRuntimeApi.parseEventMessage(42), isNull);
    },
  );

  test(
    'capability flag stays unknown unless explicitly enabled or disabled',
    () {
      FocusRuntimeFeatureState stateOf(Map<String, dynamic> config) =>
          focusRuntimeFeatureState(config);

      expect(
        stateOf({
          'features': {'focus_runtime_sync': true},
        }),
        FocusRuntimeFeatureState.enabled,
      );
      expect(
        stateOf({
          'features': {'focus_runtime_sync': false},
        }),
        FocusRuntimeFeatureState.disabled,
      );
      // 配置未加载 / 缺字段 / 类型错误：未知，不等于关闭。
      expect(stateOf(const {}), FocusRuntimeFeatureState.unknown);
      expect(
        stateOf({
          'features': {'other': true},
        }),
        FocusRuntimeFeatureState.unknown,
      );
      expect(
        stateOf({
          'features': {'focus_runtime_sync': 'yes'},
        }),
        FocusRuntimeFeatureState.unknown,
      );
      expect(
        stateOf(const {'features': 'nope'}),
        FocusRuntimeFeatureState.unknown,
      );

      expect(
        isFocusRuntimeRouteMissing(const ApiException('404: Not Found')),
        isTrue,
      );
      expect(
        isFocusRuntimeRouteMissing(
          const ApiException('405: Method Not Allowed'),
        ),
        isTrue,
      );
      expect(
        isFocusRuntimeRouteMissing(
          const ApiException('无法连接服务器 https://h/api：网络不可用'),
        ),
        isFalse,
      );
    },
  );
}
