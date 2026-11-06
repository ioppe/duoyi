import 'dart:async';
import 'dart:convert';

import 'package:duoyi/models/focus_runtime.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/focus_runtime_api.dart';
import 'package:duoyi/services/focus_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _t0 = 1700000000000;
const _server = 'https://sync.example.test/duoyi/api';
const _tokenA = 'token-a';

/// 只暴露协调器真正读取的四个 getter；换号通过 [switchIdentity] + notify 驱动。
class _FakeAuth extends AuthProvider {
  _FakeAuth({
    required ApiClient client,
    required String baseUrl,
    required AuthState state,
    Map<String, dynamic> serverConfig = const <String, dynamic>{},
  }) : _fakeClient = client,
       _fakeBaseUrl = baseUrl,
       _fakeState = state,
       _fakeServerConfig = serverConfig,
       super(client: client, initialState: state, baseUrl: baseUrl);

  ApiClient _fakeClient;
  final String _fakeBaseUrl;
  AuthState _fakeState;
  final Map<String, dynamic> _fakeServerConfig;

  @override
  AuthState get state => _fakeState;

  @override
  String get baseUrl => _fakeBaseUrl;

  @override
  ApiClient get client => _fakeClient;

  @override
  Map<String, dynamic> get serverConfig => _fakeServerConfig;

  void switchIdentity(AuthState state, ApiClient client) {
    _fakeState = state;
    _fakeClient = client;
    notifyListeners();
  }
}

/// 受控 WS：测试自己决定何时推帧、何时断开，绝不连真网络。
class _FakeSocket implements FocusRuntimeSocket {
  _FakeSocket(this.uri);

  final Uri uri;
  final StreamController<Object?> _controller =
      StreamController<Object?>.broadcast();
  final List<Object?> sent = <Object?>[];
  bool closed = false;

  @override
  Stream<Object?> get messages => _controller.stream;

  @override
  void send(Object? data) => sent.add(data);

  @override
  Future<void> close([int? code, String? reason]) async {
    closed = true;
  }

  /// 服务端推一条帧。
  void emit(Object? raw) => _controller.add(raw);

  /// 连接被动断开（onDone 路径）。
  Future<void> drop() => _controller.close();

  void dispose() {
    if (!_controller.isClosed) _controller.close();
  }
}

FocusRuntimeSnapshot _snapshot({
  String session = 'stage-a',
  int revision = 3,
  FocusRuntimeStatus status = FocusRuntimeStatus.running,
  int elapsedMs = 0,
  int durationMs = 60000,
  String? task = 'Server task',
  PomodoroSession? record,
  int syncVersion = 0,
}) => FocusRuntimeSnapshot(
  serverNowMs: _t0,
  runtime: FocusRuntimeState(
    sessionId: session,
    revision: revision,
    status: status,
    mode: FocusRuntimeMode.countdown,
    phase: FocusRuntimePhase.focus,
    durationMs: durationMs,
    elapsedMs: elapsedMs,
    anchorAtMs: status.isRunning ? _t0 : null,
    startedAtMs: _t0,
    sourceDeviceId: 'desktop',
    taskName: task,
  ),
  lastSession: record?.toJson(),
  syncVersion: syncVersion,
);

String _frame({
  String session = 'stage-a',
  int revision = 3,
  FocusRuntimeStatus status = FocusRuntimeStatus.running,
  String? task = 'Server task',
  PomodoroSession? record,
}) => jsonEncode(
  _snapshot(
    session: session,
    revision: revision,
    status: status,
    task: task,
    record: record,
  ).toJson(),
);

/// WS 帧必须带事件信封；裸快照会被解析器丢弃。
String _event({
  String session = 'stage-a',
  int revision = 3,
  FocusRuntimeStatus status = FocusRuntimeStatus.running,
  String? task = 'Server task',
  PomodoroSession? record,
}) => jsonEncode(<String, dynamic>{
  'event': 'focus.runtime',
  'data': _snapshot(
    session: session,
    revision: revision,
    status: status,
    task: task,
    record: record,
  ).toJson(),
});

PomodoroSession _history(String id) => PomodoroSession(
  id: id,
  startTime: DateTime.utc(2026, 1, 1),
  endTime: DateTime.utc(2026, 1, 1, 0, 1),
  durationSeconds: 60,
  type: PomodoroType.focus,
);

Future<void> _settle([int rounds = 12]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _until(bool Function() predicate, String reason) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) fail('超时等待：$reason');
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) responder;
  late List<_FakeSocket> sockets;
  late _FakeAuth auth;
  late PomodoroProvider provider;
  late FocusSyncCoordinator coordinator;
  late int historyCallbacks;

  const enabledConfig = <String, dynamic>{
    'features': <String, dynamic>{'focus_runtime_sync': true},
  };

  ApiClient newClient(String token, {String baseUrl = _server}) {
    final transport = MockClient((request) async {
      requests.add(request);
      return responder(request);
    });
    addTearDown(transport.close);
    return ApiClient(baseUrl: baseUrl, token: token, httpClient: transport);
  }

  /// 构造真实 Provider + 真实协调器，仅替换认证与 WS 传输。
  Future<void> start({
    Map<String, dynamic> serverConfig = enabledConfig,
    String token = _tokenA,
    String baseUrl = _server,
    Map<String, Object> extraPrefs = const <String, Object>{},
    Future<http.Response> Function(http.Request)? respond,
    Duration probeRetryDelay = const Duration(milliseconds: 5),
    Duration pollInterval = const Duration(hours: 1),
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      FocusSyncCoordinator.deviceIdStorageKey: 'device-test',
      ...extraPrefs,
    });
    requests = <http.Request>[];
    sockets = <_FakeSocket>[];
    historyCallbacks = 0;
    responder = respond ?? (request) async => http.Response(_frame(), 200);

    final client = newClient(token, baseUrl: baseUrl);
    auth = _FakeAuth(
      client: client,
      baseUrl: baseUrl,
      state: AuthState(userId: 'u1', token: token),
      serverConfig: serverConfig,
    );
    provider = PomodoroProvider();
    await provider.loadFromStorage();
    coordinator = FocusSyncCoordinator(
      auth: auth,
      pomodoro: provider,
      onHistoryChanged: () async {
        historyCallbacks++;
      },
      socketFactory: (uri) {
        final socket = _FakeSocket(uri);
        sockets.add(socket);
        return socket;
      },
      pollInterval: pollInterval,
      probeRetryDelay: probeRetryDelay,
      minRefreshInterval: Duration.zero,
      reconnectBackoff: const <Duration>[Duration(milliseconds: 5)],
    );
    coordinator.start();
  }

  tearDown(() {
    coordinator.dispose();
    provider.dispose();
    for (final socket in sockets) {
      socket.dispose();
    }
  });

  test(
    'enabled capability subscribes to the prefixed WS path and fetches the exact endpoint',
    () async {
      await start();
      await _until(
        () => coordinator.ready || coordinator.error != null,
        'HTTP 快照就绪',
      );
      // 就绪与错误不可共存。
      expect(coordinator.error, isNull);

      expect(coordinator.mode, FocusSyncMode.remote);
      expect(provider.focusSyncMode, FocusSyncMode.remote);
      expect(provider.focusSyncReady, isTrue);

      // HTTP：部署前缀 + 精确路由，凭证来自捕获的身份。
      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(
        requests.single.url.toString(),
        'https://sync.example.test/duoyi/api/focus/runtime',
      );
      expect(requests.single.headers['Authorization'], 'Bearer $_tokenA');

      // WS：https -> wss，保留 /duoyi 前缀，token 只走查询参数。
      expect(sockets, hasLength(1));
      final uri = sockets.single.uri;
      expect(uri.scheme, 'wss');
      expect(uri.host, 'sync.example.test');
      expect(uri.path, '/duoyi/ws/focus/runtime/events');
      expect(uri.queryParameters['token'], _tokenA);

      // 建连本身不等于已同步：收到第一帧才算 connected。
      expect(coordinator.connected, isFalse);

      sockets.single.emit(_event(revision: 4));
      await _until(() => coordinator.connected, '收到 WS 帧后 connected');
      expect(provider.focusSyncConnected, isTrue);
      expect(provider.remoteFocusRevision, 4);
      expect(provider.canControlFocus, isTrue);
      expect(provider.state.taskName, 'Server task');
    },
  );

  test('existing history is hydrated before the first remote upsert', () async {
    await start(
      respond: (_) async => http.Response(
        _frame(revision: 4, record: _history('server-done')),
        200,
      ),
      extraPrefs: <String, Object>{
        'pomodoro_sessions': jsonEncode(<Map<String, dynamic>>[
          _history('local-old').toJson(),
        ]),
      },
    );
    await _until(() => coordinator.ready, '首帧快照就绪');
    await _until(() => provider.sessions.length == 2, '历史回填完成');

    expect(
      provider.sessions.map((s) => s.id),
      containsAll(<String>['local-old', 'server-done']),
    );
    expect(historyCallbacks, 1, reason: '回填历史只需触发一次补全回调');

    // 重复快照幂等：不复活记录、不重复回调。
    sockets.single.emit(_event(revision: 4, record: _history('server-done')));
    await _settle();
    expect(provider.sessions.length, 2);
    expect(historyCallbacks, 1);
  });

  test(
    'a lower revision from another stage is ignored everywhere and the next command uses the newest revision',
    () async {
      await start(
        respond: (_) async =>
            http.Response(_frame(revision: 8, session: 'stage-new'), 200),
      );
      await _until(() => coordinator.ready, '权威快照就绪');
      expect(coordinator.runtimeRevision, 8);

      sockets.single.emit(_event(revision: 8, session: 'stage-new'));
      await _until(() => coordinator.connected, 'WS 已连通');
      expect(provider.canControlFocus, isTrue);

      // 迟到的旧阶段（revision 6）不得覆盖 revision 8。
      sockets.single.emit(
        _event(
          revision: 6,
          session: 'stage-old',
          status: FocusRuntimeStatus.paused,
        ),
      );
      await _settle();
      expect(coordinator.runtimeRevision, 8);
      expect(coordinator.runtimeSessionId, 'stage-new');
      expect(provider.remoteFocusRevision, 8);
      expect(provider.remoteFocusSessionId, 'stage-new');
      expect(provider.state.isRunning, isTrue);
      expect(provider.isPaused, isFalse);

      responder = (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          _frame(
            revision: (body['expectedRevision'] as int) + 1,
            session: 'stage-new',
            status: FocusRuntimeStatus.paused,
          ),
          200,
        );
      };
      provider.toggleTimer();
      await _until(() => requests.any((r) => r.method == 'POST'), '发出显式命令');

      final command = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(command['action'], 'pause');
      expect(command['expectedRevision'], 8, reason: '必须绑定最新已确认 revision');
      expect(command['sessionId'], 'stage-new');
      expect(command['deviceId'], 'device-test');
      await _until(() => provider.remoteFocusRevision == 9, '命令回执被投影');
      expect(provider.isPaused, isTrue);
    },
  );

  test(
    'unknown capability with an unreachable backend stays unknown and never runs local focus',
    () async {
      await start(
        serverConfig: const <String, dynamic>{},
        respond: (_) async => throw http.ClientException('offline'),
      );
      await _until(() => requests.isNotEmpty, '发起能力探测');
      await _settle(20);

      expect(coordinator.mode, FocusSyncMode.unknown);
      expect(coordinator.ready, isFalse);
      expect(provider.focusSyncMode, FocusSyncMode.unknown);
      expect(provider.focusSyncEnabled, isTrue, reason: '未知不等于回退本地');
      expect(provider.canControlFocus, isFalse);
      expect(provider.state.isRunning, isFalse);

      // 未知态下按钮不得启动独立本地计时，也不得发命令。
      provider.toggleTimer();
      await _settle(20);
      expect(provider.state.isRunning, isFalse);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
    },
  );

  test(
    'explicit 404 or an explicitly disabled feature releases local mode',
    () async {
      await start();
      responder = (_) async => http.Response('{"detail":"Not Found"}', 404);
      await _until(() => coordinator.mode == FocusSyncMode.local, '404 回退本地');
      expect(requests.first.url.path, '/duoyi/api/focus/runtime');
      expect(provider.focusSyncMode, FocusSyncMode.local);
      expect(provider.focusSyncEnabled, isFalse);
      expect(provider.canControlFocus, isTrue, reason: '本地模式可继续计时');
      final prefs = await SharedPreferences.getInstance();
      // 回退本地时不得留下远端标记（键不存在 == 未开启）。
      expect(prefs.getBool(PomodoroProvider.focusRemoteMarkerKey), isNot(true));

      coordinator.dispose();
      provider.dispose();
      for (final socket in sockets) {
        socket.dispose();
      }
      sockets = <_FakeSocket>[];

      // 明确关闭：一次个人专注请求都不发。
      await start(
        serverConfig: const <String, dynamic>{
          'features': <String, dynamic>{'focus_runtime_sync': false},
        },
      );
      await _settle();
      expect(coordinator.mode, FocusSyncMode.local);
      expect(provider.focusSyncEnabled, isFalse);
      expect(requests, isEmpty);
      expect(sockets, isEmpty);
    },
  );

  test(
    'token change makes the in-flight response and the old socket inert',
    () async {
      final gate = Completer<void>();
      var calls = 0;
      await start(
        respond: (request) async {
          calls++;
          if (calls == 1) {
            await gate.future;
            return http.Response(_frame(revision: 5, session: 'late'), 200);
          }
          return Completer<http.Response>().future; // 新身份的请求保持挂起
        },
      );
      await _until(() => requests.length == 1, '旧身份请求在途');

      // 换号：新 token + 新 ApiClient，绝不继承旧凭证。
      final clientB = newClient('token-b');
      auth.switchIdentity(
        const AuthState(userId: 'u1', token: 'token-b'),
        clientB,
      );
      await _until(() => requests.length == 2, '新身份重新拉取');
      expect(requests[1].headers['Authorization'], 'Bearer token-b');
      expect(sockets.first.closed, isTrue, reason: '旧 WS 必须关闭');

      gate.complete();
      await _settle(20);
      expect(coordinator.snapshot, isNull, reason: '旧代际响应不得写入');
      expect(coordinator.ready, isFalse);
      expect(provider.remoteFocusRevision, isNull);
      expect(provider.state.isRunning, isFalse);
      expect(provider.sessions, isEmpty);
    },
  );

  test(
    'resetForAccountChange closes the socket and swallows late WS frames',
    () async {
      await start();
      await _until(() => coordinator.ready, '快照就绪');
      sockets.single.emit(_event(revision: 3));
      await _until(() => coordinator.connected, 'WS 已连通');
      final oldSocket = sockets.single;

      await coordinator.resetForAccountChange();
      expect(oldSocket.closed, isTrue);
      expect(coordinator.mode, FocusSyncMode.unknown);
      expect(coordinator.snapshot, isNull);
      expect(coordinator.runtimeRevision, isNull);
      expect(provider.focusSyncMode, FocusSyncMode.unknown);
      expect(provider.remoteFocusRevision, isNull);
      expect(provider.focusRuntimeController, same(coordinator));

      oldSocket.emit(_event(revision: 9, session: 'late-stage'));
      await _settle(20);
      expect(coordinator.snapshot, isNull, reason: '旧 socket 的迟到帧不得投影');
      expect(provider.remoteFocusRevision, isNull);

      // 清理期间旧身份再次 notify：不得提前重连。
      auth.notifyListeners();
      await _settle();
      expect(sockets, hasLength(1));
      expect(requests, hasLength(1));
      expect(coordinator.mode, FocusSyncMode.unknown);
    },
  );

  test(
    'disconnect blocks controls and reconnect converges on the new authority',
    () async {
      await start();
      await _until(() => coordinator.ready, '快照就绪');
      sockets.single.emit(_event(revision: 3));
      await _until(() => coordinator.connected, 'WS 已连通');
      expect(provider.canControlFocus, isTrue);

      responder = (_) async =>
          http.Response(_frame(revision: 4, session: 'stage-b'), 200);
      await sockets.single.drop();
      await _until(() => !coordinator.connected, '断线被识别');
      expect(provider.focusSyncConnected, isFalse);
      expect(provider.canControlFocus, isFalse);

      // 断线期间按钮只补拉快照，绝不盲发命令。
      provider.toggleTimer();
      await _settle(20);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);

      // 有界退避后必须只重连一条新连接，且 URI 与旧身份一致。
      await _until(() => sockets.length == 2, '退避后重连');
      expect(sockets.last.uri, sockets.first.uri);
      sockets.last.emit(_event(revision: 4, session: 'stage-b'));
      await _until(() => coordinator.connected, '重连后重新收敛');
      expect(provider.canControlFocus, isTrue);
      expect(provider.remoteFocusRevision, 4);
      expect(provider.remoteFocusSessionId, 'stage-b');
    },
  );
}
