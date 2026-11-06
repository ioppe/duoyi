import 'dart:convert';

import 'package:duoyi/models/focus_runtime.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/focus_runtime_background_control.dart';
import 'package:duoyi/services/home_widget_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const server = 'https://focus.example.test';
  late SharedPreferences prefs;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) responder;

  Map<String, dynamic> snapshot({
    FocusRuntimeStatus status = FocusRuntimeStatus.running,
    int revision = 4,
  }) => FocusRuntimeSnapshot(
    serverNowMs: 1700000000000,
    runtime: FocusRuntimeState.empty.copyWith(
      sessionId: 'shared',
      revision: revision,
      status: status,
      anchorAtMs: 1700000000000,
    ),
  ).toJson();

  HomeWidgetActionRequest request(
    String action,
    String state, {
    int revision = 4,
  }) {
    final scope = HomeWidgetAccountScope.fromPreferences(
      prefs,
    ).focusControlScope!;
    return HomeWidgetActionRequest.parse(
      Uri(
        scheme: 'duoyi',
        host: 'action',
        path: '/${action}_pomodoro',
        queryParameters: {
          'session': 'shared',
          'revision': '$revision',
          'state': state,
          'scope': scope,
        },
      ),
    )!;
  }

  Future<FocusRuntimeBackgroundResult> run(HomeWidgetActionRequest action) {
    final transport = MockClient((request) async {
      requests.add(request);
      return responder(request);
    });
    addTearDown(transport.close);
    return FocusRuntimeBackgroundControl.run(
      action,
      prefs,
      client: ApiClient(
        baseUrl: server,
        token: 'phone-token',
        httpClient: transport,
      ),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'auth_state': jsonEncode({'user_id': 'u1', 'token': 'phone-token'}),
      AuthProvider.serverUrlStorageKey: server,
      AuthProvider.sessionServerStorageKey: server,
      AccountLocalDataCleaner.accountDataOwnerKey: jsonEncode([
        server,
        'id:u1',
      ]),
      PomodoroProvider.focusRemoteMarkerKey: true,
      'duoyi_focus_sync_device_id': 'phone',
    });
    prefs = await SharedPreferences.getInstance();
    requests = [];
    responder = (request) async => http.Response(jsonEncode(snapshot()), 200);
  });

  test(
    'cold pause sends one explicit command bound to the confirmed revision',
    () async {
      responder = (request) async => http.Response(
        jsonEncode(
          snapshot(
            status: request.method == 'POST'
                ? FocusRuntimeStatus.paused
                : FocusRuntimeStatus.running,
            revision: request.method == 'POST' ? 5 : 4,
          ),
        ),
        200,
      );
      final result = await run(request('pause', 'running'));
      expect(result.changed, isTrue);
      expect(result.snapshot?.runtime.status, FocusRuntimeStatus.paused);
      expect(requests, hasLength(2));
      expect(requests.last.headers['authorization'], 'Bearer phone-token');
      final body = jsonDecode(requests.last.body) as Map;
      expect(body['action'], 'pause');
      expect(body['deviceId'], 'phone');
      expect(body['sessionId'], 'shared');
      expect(body['expectedRevision'], 4);
    },
  );

  test('paused start is an explicit resume', () async {
    responder = (_) async => http.Response(
      jsonEncode(snapshot(status: FocusRuntimeStatus.paused)),
      200,
    );
    expect((await run(request('start', 'paused'))).changed, isTrue);
    expect((jsonDecode(requests.last.body) as Map)['action'], 'resume');
  });

  test('stale widget refreshes projection without sending a command', () async {
    final result = await run(request('pause', 'running', revision: 3));
    expect(result.handled, isTrue);
    expect(result.changed, isFalse);
    expect(result.snapshot?.runtime.revision, 4);
    expect(requests, hasLength(1));
  });

  test(
    'credential change while fetching cancels command and projection',
    () async {
      responder = (_) async {
        await prefs.setString(
          'auth_state',
          jsonEncode({'user_id': 'u1', 'token': 'new-token'}),
        );
        return http.Response(jsonEncode(snapshot()), 200);
      };
      final result = await run(request('pause', 'running'));
      expect(result.handled, isTrue);
      expect(result.changed, isFalse);
      expect(result.snapshot, isNull);
      expect(requests, hasLength(1));
    },
  );

  test('server change while fetching cancels command and projection', () async {
    responder = (_) async {
      await prefs.setString(
        AuthProvider.serverUrlStorageKey,
        'https://other.example.test',
      );
      return http.Response(jsonEncode(snapshot()), 200);
    };
    final result = await run(request('pause', 'running'));
    expect(result.handled, isTrue);
    expect(result.changed, isFalse);
    expect(result.snapshot, isNull);
    expect(requests, hasLength(1));
  });

  test(
    'network failure keeps remote ownership and never falls back locally',
    () async {
      responder = (_) async => throw http.ClientException('offline');
      final result = await run(request('pause', 'running'));
      expect(result.handled, isTrue);
      expect(result.changed, isFalse);
      expect(prefs.getBool(PomodoroProvider.focusRemoteMarkerKey), isTrue);
    },
  );

  test(
    'confirmed missing runtime route releases old-backend local mode',
    () async {
      responder = (_) async => http.Response('{"detail":"Not Found"}', 404);
      final result = await run(request('pause', 'running'));
      expect(result.handled, isFalse);
      expect(prefs.containsKey(PomodoroProvider.focusRemoteMarkerKey), isFalse);
    },
  );

  test('local widget action does not contact a focus endpoint', () async {
    await prefs.remove(PomodoroProvider.focusRemoteMarkerKey);
    expect((await run(request('pause', 'running'))).handled, isFalse);
    expect(requests, isEmpty);
  });
}
