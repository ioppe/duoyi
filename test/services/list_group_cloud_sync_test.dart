import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:duoyi/models/list_group.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/providers/list_group_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PollingClient extends ApiClient {
  _PollingClient(http.Client httpClient)
    : super(
        baseUrl: 'https://duoyi.test',
        token: 'token',
        httpClient: httpClient,
      );

  final events = StreamController<String>.broadcast();

  @override
  Stream<String> streamLines(String path) => events.stream;
}

Map<String, dynamic> _row(
  String id,
  String name,
  int day, {
  bool deleted = false,
}) => ListGroup(
  id: id,
  name: name,
  sortOrder: 3,
  isDeleted: deleted,
  createdAt: DateTime.utc(2026, 10, 1),
  updatedAt: DateTime.utc(2026, 10, day),
).toJson();

Object? _canonical(Object? value) {
  if (value is Map) {
    return SplayTreeMap<String, Object?>.from({
      for (final entry in value.entries)
        entry.key.toString(): _canonical(entry.value),
    });
  }
  return value is Iterable ? value.map(_canonical).toList() : value;
}

http.Response _response(Map<String, dynamic> payload) => http.Response.bytes(
  utf8.encode(jsonEncode(payload)),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'full push and item deltas include list_groups with per-record stamps and tombstones',
    () async {
      final groups = ListGroupProvider();
      final live = await groups.create('旅行', 0);
      final removed = await groups.create('搬家', 1);
      await groups.delete(removed.id);
      final requests = <({String path, Map<String, dynamic> body})>[];
      var server = <String, dynamic>{};
      final mock = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add((path: request.url.path, body: body));
        if (request.url.path == '/api/sync') {
          server = Map.of(body);
        } else {
          expect(request.url.path, '/api/sync/item-delta');
          final items = body['items'] as Map;
          final changed = items['list_groups'] as List;
          final current = ListGroupProvider.decodeGroups(
            server['list_groups'] as List,
          );
          server['list_groups'] = ListGroupProvider.mergeGroups(
            current,
            ListGroupProvider.decodeGroups(changed),
          ).map((g) => g.toJson()).toList();
        }
        return _response({
          ...server,
          'collection_hashes': {
            for (final entry in server.entries)
              entry.key: sha256
                  .convert(utf8.encode(jsonEncode(_canonical(entry.value))))
                  .toString(),
          },
        });
      });
      final sync = CloudSyncProvider()
        ..apiClientGetter = () => ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token',
          httpClient: mock,
        );
      addTearDown(groups.dispose);
      addTearDown(sync.dispose);
      addTearDown(mock.close);
      await sync.syncNow();
      expect(sync.lastError, isNull);
      expect(sync.hasPendingChanges, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sync_collection_hashes'), isNotNull);
      expect(prefs.getString('sync_item_hashes'), isNotNull);
      final pushed = requests.single.body['list_groups'] as List;
      expect(pushed, hasLength(2));
      expect(
        pushed.singleWhere((item) => item['id'] == removed.id)['isDeleted'],
        isTrue,
      );
      expect(
        pushed.singleWhere((item) => item['id'] == live.id),
        live.toJson(),
      );
      final renamed = await groups.rename(live.id, '假期');
      await sync.syncNow();
      expect(sync.lastError, isNull);
      expect(requests, hasLength(2));
      expect(requests.last.path, '/api/sync/item-delta');
      final delta = (requests.last.body['items'] as Map)['list_groups'] as List;
      expect(delta, [renamed.toJson()]);
      expect(
        (requests.last.body['collection_hashes'] as Map)['list_groups'],
        matches(r'^[0-9a-f]{64}$'),
      );
      await groups.delete(live.id);
      await sync.syncNow();
      final deletedDelta =
          (requests.last.body['items'] as Map)['list_groups'] as List;
      expect(deletedDelta.single['id'], live.id);
      expect(deletedDelta.single['isDeleted'], isTrue);
      expect(
        DateTime.parse(
          deletedDelta.single['updatedAt'],
        ).isAfter(renamed.updatedAt),
        isTrue,
      );
      expect(sync.lastError, isNull);
    },
  );

  test(
    'remote polling pulls additions/deletions and reloads the visible provider',
    () async {
      final groups = ListGroupProvider();
      await groups.mergeRemote([_row('existing', '旧清单', 20)]);
      var version = 1;
      var applied = Completer<void>();
      final pulls = <Map<String, dynamic>>[];
      final mock = MockClient((request) async {
        if (request.url.path == '/api/sync/status') {
          return _response({'server_version': version});
        }
        expect(request.url.path, '/api/sync/pull');
        pulls.add(jsonDecode(request.body) as Map<String, dynamic>);
        return _response({
          'server_version': version,
          'list_groups': [
            _row(
              'existing',
              '旧清单',
              version == 1 ? 20 : 22,
              deleted: version == 2,
            ),
            _row('travel', '远端旅行', 21),
          ],
        });
      });
      final client = _PollingClient(mock);
      final sync = CloudSyncProvider()..apiClientGetter = () => client;
      sync.onSynced = (collections) async {
        expect(collections, contains('list_groups'));
        await groups.loadFromStorage();
        applied.complete();
      };
      addTearDown(() async {
        sync.dispose();
        groups.dispose();
        await client.events.close();
        mock.close();
      });
      sync.startRemotePolling();
      await applied.future.timeout(const Duration(seconds: 3));
      sync.stopRemotePolling();
      expect(groups.groups.map((g) => g.name), containsAll(['旧清单', '远端旅行']));
      expect(
        (pulls.single['collection_hashes'] as Map).keys,
        contains('list_groups'),
      );
      version = 2;
      applied = Completer<void>();
      sync.startRemotePolling();
      await applied.future.timeout(const Duration(seconds: 3));
      sync.stopRemotePolling();
      expect(pulls, hasLength(2));
      expect(groups.groups.single.name, '远端旅行');
      expect(
        groups.allGroups.firstWhere((g) => g.id == 'existing').isDeleted,
        isTrue,
      );
      expect(sync.lastError, isNull);
    },
  );

  test(
    'an old response merges remote additions while retaining a concurrent local rename',
    () async {
      final groups = ListGroupProvider();
      await groups.mergeRemote([_row('travel', '旅行', 20)]);
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final mock = MockClient((request) async {
        started.complete();
        return response.future;
      });
      final sync = CloudSyncProvider()
        ..apiClientGetter = () => ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token',
          httpClient: mock,
        );
      addTearDown(sync.dispose);
      addTearDown(groups.dispose);
      addTearDown(mock.close);
      final pending = sync.syncNow();
      await started.future;
      final renamed = await groups.rename('travel', '本地新名称');
      response.complete(
        _response({
          'list_groups': [_row('travel', '旧远端名称', 19), _row('new', '远端新增', 21)],
        }),
      );
      await pending;
      await groups.loadFromStorage();
      expect(
        groups.groups.firstWhere((g) => g.id == 'travel').toJson(),
        renamed.toJson(),
      );
      expect(groups.groups.any((g) => g.id == 'new'), isTrue);
      expect(
        sync.hasPendingChanges,
        isTrue,
        reason: 'the newer local row must still be uploaded',
      );
      expect(sync.lastError, isNull);
    },
  );

  test('account reset rejects a late list_groups sync response', () async {
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final mock = MockClient((request) async {
      started.complete();
      return response.future;
    });
    final sync = CloudSyncProvider()
      ..apiClientGetter = () => ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token',
        httpClient: mock,
      );
    addTearDown(sync.dispose);
    addTearDown(mock.close);
    final pending = sync.syncNow();
    await started.future;
    await sync.resetForAccountChange();
    response.complete(
      _response({
        'list_groups': [_row('old-account', '旧账号清单', 21)],
      }),
    );
    await pending;
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(ListGroupProvider.storageKey), isFalse);
  });
}
