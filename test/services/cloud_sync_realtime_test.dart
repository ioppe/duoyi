import 'dart:async';
import 'dart:convert';

import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一次 SSE 订阅：每次 subscribe 都拿到独立 controller，便于模拟断线/重建。
class _EventStream {
  final controller = StreamController<String>();
  bool cancelled = false;
}

class _RealtimeClient extends ApiClient {
  _RealtimeClient(http.Client httpClient, {String token = 'token'})
    : super(
        baseUrl: 'https://duoyi.test',
        token: token,
        httpClient: httpClient,
      );

  final List<_EventStream> streams = <_EventStream>[];

  @override
  Stream<String> streamLines(String path) {
    final stream = _EventStream();
    stream.controller.onCancel = () => stream.cancelled = true;
    streams.add(stream);
    return stream.controller.stream;
  }

  _EventStream get lastStream => streams.last;

  /// 服务端事务提交后的即时修订帧：event: sync + data + 空行。
  void emitSync({int? version, String updatedAt = ''}) {
    final data = <String, dynamic>{
      'server_version': ?version,
      if (updatedAt.isNotEmpty) 'server_updated_at': updatedAt,
    };
    lastStream.controller.add('event: sync');
    lastStream.controller.add('data: ${jsonEncode(data)}');
    lastStream.controller.add('');
  }

  /// 心跳是 SSE 注释行，不携带任何业务数据。
  void emitHeartbeat() => lastStream.controller.add(': heartbeat');
}

Map<String, dynamic> _todo(String id, String title, String stamp) => {
  'id': id,
  'title': title,
  'isCompleted': false,
  'isDeleted': false,
  'createdAt': stamp,
  'updatedAt': stamp,
};

http.Response _json(Map<String, dynamic> body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json'},
);

String _stamp(int version) =>
    '2026-01-${version.toString().padLeft(2, '0')}T00:00:00Z';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CloudSyncProvider sync;
  late _RealtimeClient activeClient;
  late List<String> requests;

  Future<void> boot({
    required FutureOr<Map<String, dynamic>> Function(String path) respond,
    Map<String, Object> prefs = const <String, Object>{},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    requests = <String>[];
    activeClient = _RealtimeClient(
      MockClient((request) async {
        requests.add(request.url.path);
        return _json(await respond(request.url.path));
      }),
    );
    sync = CloudSyncProvider()..apiClientGetter = () => activeClient;
    await sync.loadFromStorage();
    sync.dirtyMarkEnabled = true;
  }

  tearDown(() async {
    sync.stopRemotePolling();
    sync.dispose();
    for (final stream in activeClient.streams) {
      await stream.controller.close();
    }
  });

  test('本地改动在 300ms 合并窗口内上传一次，空闲时没有任何周期轮询', () async {
    await boot(
      respond: (path) => {'server_version': 3, 'server_updated_at': _stamp(3)},
      prefs: {
        'todos': jsonEncode([_todo('local-1', '本地任务', _stamp(3))]),
      },
    );
    sync.startRemotePolling();

    sync.markPendingLocalChange();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(requests, isEmpty, reason: '短合并窗口内不立即上传');

    await Future<void>.delayed(const Duration(milliseconds: 600));
    final syncRequests = requests
        .where((path) => path.startsWith('/api/sync'))
        .toList();
    expect(syncRequests, hasLength(1), reason: '只上传一次');
    expect(requests, isNot(contains('/api/sync/status')));

    // 空闲 1.2s：既没有轮询也没有兜底定时器。
    final sent = requests.length;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(requests.length, sent);
    expect(sync.hasPendingChanges, isFalse);
  });

  test('收到 sync 事件立即按 hash 增量拉取并回调 onSynced', () async {
    await boot(
      respond: (path) => path == '/api/sync/pull'
          ? {
              'server_version': 7,
              'server_updated_at': _stamp(7),
              'todos': [_todo('remote-1', '远端任务', _stamp(7))],
            }
          : {'server_version': 7, 'server_updated_at': _stamp(7)},
    );
    final synced = Completer<Set<String>>();
    sync.onSynced = (collections) async {
      if (!synced.isCompleted) synced.complete(collections);
    };
    sync.startRemotePolling();
    activeClient.emitSync(version: 7);

    final changed = await synced.future.timeout(const Duration(seconds: 5));
    expect(changed, contains('todos'));
    expect(requests, contains('/api/sync/pull'));
    expect(requests, isNot(contains('/api/sync/status')));
    expect(sync.lastServerVersion, 7);
  });

  test('本地 pending 改动期间的事件不丢：先上传合并，再补齐远端修订', () async {
    await boot(
      respond: (path) {
        if (path == '/api/sync/pull') {
          return {
            'server_version': 9,
            'server_updated_at': _stamp(9),
            'todos': [_todo('local-1', '本地任务', _stamp(3))],
          };
        }
        return {'server_version': 4, 'server_updated_at': _stamp(4)};
      },
      prefs: {
        'todos': jsonEncode([_todo('local-1', '本地任务', _stamp(3))]),
      },
    );
    sync.startRemotePolling();
    sync.markPendingLocalChange();
    // 上传还没发生就先收到远端修订：事件必须被记录，不能丢弃。
    activeClient.emitSync(version: 9);

    await Future<void>.delayed(const Duration(milliseconds: 1500));

    final pushIndex = requests.indexWhere(
      (path) => path != '/api/sync/pull' && path.startsWith('/api/sync'),
    );
    final pullIndex = requests.indexOf('/api/sync/pull');
    expect(pushIndex, isNonNegative, reason: '本地改动仍然上传');
    expect(pullIndex, greaterThan(pushIndex), reason: '上传之后补齐远端');
    expect(sync.hasPendingChanges, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('todos'), contains('local-1'));
  });

  test('拉取 v2 途中收到 v3 仍继续补齐，不清掉新修订', () async {
    final firstPullStarted = Completer<void>();
    final firstPullResponse = Completer<Map<String, dynamic>>();
    final latestApplied = Completer<void>();
    var pullCount = 0;
    await boot(
      respond: (path) async {
        if (path != '/api/sync/pull') return <String, dynamic>{};
        pullCount++;
        if (pullCount == 1) {
          firstPullStarted.complete();
          return firstPullResponse.future;
        }
        return {
          'server_version': 3,
          'server_updated_at': _stamp(3),
          'todos': [_todo('latest', '第三版远端任务', _stamp(3))],
        };
      },
    );
    sync.onSynced = (_) async {
      if (sync.lastServerVersion == 3 && !latestApplied.isCompleted) {
        latestApplied.complete();
      }
    };
    sync.startRemotePolling();
    activeClient.emitSync(version: 2, updatedAt: _stamp(2));
    await firstPullStarted.future.timeout(const Duration(seconds: 3));
    activeClient.emitSync(version: 3, updatedAt: _stamp(3));
    await Future<void>.delayed(Duration.zero);
    firstPullResponse.complete({
      'server_version': 2,
      'server_updated_at': _stamp(2),
      'todos': [_todo('previous', '第二版远端任务', _stamp(2))],
    });
    await latestApplied.future.timeout(const Duration(seconds: 3));
    expect(pullCount, 2);
    expect(sync.lastServerVersion, 3);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('todos'), contains('latest'));
    expect(requests, isNot(contains('/api/sync/status')));
  });

  test('突发与重复事件不会造成同步风暴', () async {
    await boot(
      respond: (path) => {
        'server_version': 12,
        'server_updated_at': _stamp(12),
      },
    );
    sync.startRemotePolling();
    for (var version = 10; version <= 14; version++) {
      activeClient.emitSync(version: version);
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final pulls = requests.where((path) => path == '/api/sync/pull').length;
    expect(pulls, greaterThanOrEqualTo(1));
    expect(pulls, lessThanOrEqualTo(2), reason: '突发事件被合并，不是每个事件一次');

    // 重复的同一修订（含自己上传后的回声）不再额外同步。
    final sent = requests.length;
    activeClient.emitSync(version: 12);
    activeClient.emitSync(version: 12);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(requests.length, sent);
  });

  test('心跳不触发拉取，静默断流会取消旧订阅并退避重建', () async {
    await boot(
      respond: (path) => {'server_version': 5, 'server_updated_at': _stamp(5)},
    );
    sync.realtimeIdleTimeoutForTest = const Duration(milliseconds: 300);
    sync.startRemotePolling();
    expect(activeClient.streams, hasLength(1));

    // 连接建立后的第一帧会做一次补同步（断连期补齐），先让它结算。
    activeClient.emitHeartbeat();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final baseline = requests.length;

    activeClient.emitHeartbeat();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    activeClient.emitHeartbeat();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(requests.length, baseline, reason: '心跳不携带数据，不拉取');
    expect(activeClient.streams, hasLength(1), reason: '心跳续期，不重建');

    // 心跳停止 → 静默超时 → 取消旧订阅，按 1s 快退避重建。
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(activeClient.streams, hasLength(1));
    expect(activeClient.streams.first.cancelled, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(activeClient.streams, hasLength(2), reason: '退避后重建订阅');
  });

  test('网络断线按快退避恢复，并在恢复后补一次同步', () async {
    await boot(
      respond: (path) => {'server_version': 6, 'server_updated_at': _stamp(6)},
    );
    sync.startRemotePolling();
    await activeClient.lastStream.controller.close();

    await Future<void>.delayed(const Duration(milliseconds: 1300));
    expect(activeClient.streams, hasLength(2), reason: '退避重连');

    activeClient.emitSync(version: 6);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(
      requests.where((path) => path == '/api/sync/pull'),
      hasLength(1),
      reason: '断连恢复补一次同步',
    );
  });

  test('回到前台强制重建订阅并补齐一次', () async {
    await boot(
      respond: (path) => {'server_version': 8, 'server_updated_at': _stamp(8)},
    );
    sync.ensureRealtimeSync();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(activeClient.streams, hasLength(1));

    // resume：订阅对象还在，但底层 socket 已死 → 强制重建。
    sync.startRemotePolling();
    expect(activeClient.streams, hasLength(2));
    expect(activeClient.streams.first.cancelled, isTrue);

    activeClient.emitSync(version: 8);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(
      requests.where((path) => path == '/api/sync/pull'),
      hasLength(1),
      reason: '重连首帧补齐一次',
    );
  });

  test('切账号/换 token 后旧事件流无效，新订阅使用新凭证', () async {
    await boot(
      respond: (path) => {'server_version': 4, 'server_updated_at': _stamp(4)},
    );
    sync.startRemotePolling();
    expect(activeClient.streams, hasLength(1));
    final oldClient = activeClient;

    await sync.resetForAccountChange();
    activeClient = _RealtimeClient(
      MockClient((request) async {
        requests.add(request.url.path);
        return _json({'server_version': 4, 'server_updated_at': _stamp(4)});
      }),
      token: 'token-b',
    );
    sync.resumeForActiveAccount();
    sync.startRemotePolling();
    expect(oldClient.streams.first.cancelled, isTrue);
    expect(activeClient.streams, hasLength(1));

    final sent = requests.length;
    oldClient.emitSync(version: 99, updatedAt: _stamp(20));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(requests.length, sent, reason: '旧账号/旧 token 的迟到事件不得触发同步');
  });

  test('关闭自动同步时不订阅事件流', () async {
    await boot(
      respond: (path) => {'server_version': 4, 'server_updated_at': _stamp(4)},
    );
    sync.startRemotePolling();
    expect(activeClient.streams, hasLength(1));

    await sync.setAutoSync(false);
    expect(sync.isRealtimeSyncConnected, isFalse);
    expect(activeClient.streams.first.cancelled, isTrue);

    sync.startRemotePolling();
    expect(activeClient.streams, hasLength(1), reason: '关闭后不再订阅');
    expect(sync.isRealtimeSyncConnected, isFalse);
  });
}
