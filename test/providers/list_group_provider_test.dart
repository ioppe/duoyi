import 'dart:convert';

import 'package:duoyi/models/list_group.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/list_group_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

ListGroup _group(String id, String name, int day, {bool deleted = false}) =>
    ListGroup(
      id: id,
      name: name,
      sortOrder: 3,
      workspaceId: 'private',
      isDeleted: deleted,
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, day),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'only persisted local CRUD marks sync dirty; hydration and remote merges stay clean',
    () async {
      final provider = ListGroupProvider();
      addTearDown(provider.dispose);
      final prefs = await SharedPreferences.getInstance();
      var localChanges = 0;
      provider.onLocalChanged = () {
        localChanges++;
        expect(prefs.getString(ListGroupProvider.storageKey), isNotNull);
      };
      await provider.loadFromStorage();
      expect(localChanges, 0);
      final group = await provider.create('旅行', 0);
      await provider.rename(group.id, '假期');
      await provider.delete(group.id);
      expect(localChanges, 3);
      await provider.loadFromStorage();
      await provider.mergeRemote([_group('remote', '远端', 21).toJson()]);
      expect(localChanges, 3);
    },
  );

  test(
    'model uses the exact contract and preserves timestamps in copyWith',
    () {
      final source = {
        'id': '4c439def-e52a-48ae-9c6b-c238e33f7db8',
        'name': '旅行',
        'sortOrder': 3,
        'workspaceId': 'private',
        'isDeleted': false,
        'createdAt': '2026-10-21T12:00:00.000',
        'updatedAt': '2026-10-21T12:00:00.000',
      };
      final group = ListGroup.fromJson(source);
      expect(group.toJson(), source);
      final copied = group.copyWith(name: '出游', isDeleted: true);
      expect(copied.id, group.id);
      expect(copied.name, '出游');
      expect(copied.isDeleted, isTrue);
      expect(copied.createdAt, group.createdAt);
      expect(copied.updatedAt, group.updatedAt);
    },
  );

  test('CRUD persists, sorts and retains hidden deletion tombstones', () async {
    final provider = ListGroupProvider();
    addTearDown(provider.dispose);
    final travel = await provider.create('  旅行  ', 3);
    final moving = await provider.create('搬家', 1);
    expect(
      travel.id,
      matches(
        RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ),
      ),
    );
    expect(provider.groups.map((g) => g.name), ['搬家', '旅行']);
    expect(provider.nextSortOrder, 4);
    final renamed = await provider.rename(travel.id, '  假期  ');
    expect(renamed.updatedAt.isAfter(travel.updatedAt), isTrue);
    await provider.delete(moving.id);
    expect(provider.groups.map((g) => g.name), ['假期']);
    final deleted = provider.allGroups.firstWhere((g) => g.id == moving.id);
    expect(deleted.isDeleted, isTrue);
    expect(deleted.updatedAt.isAfter(moving.updatedAt), isTrue);
    final reloaded = ListGroupProvider();
    addTearDown(reloaded.dispose);
    await reloaded.loadFromStorage();
    expect(reloaded.groups.single.toJson(), renamed.toJson());
    expect(reloaded.allGroups, hasLength(2));
    expect(reloaded.allGroups.first.isDeleted, isTrue);
    expect(() => reloaded.groups.add(travel), throwsUnsupportedError);
  });

  test(
    'names trim, reject empty/long/normalized duplicates and permit reuse after delete',
    () async {
      final provider = ListGroupProvider();
      addTearDown(provider.dispose);
      for (final (name, key) in [
        (' \t ', 'list_group.name_required'),
        (List.filled(25, '旅').join(), 'list_group.name_length'),
      ]) {
        await expectLater(
          provider.create(name, 0),
          throwsA(
            isA<ListGroupNameException>().having(
              (e) => e.messageKey,
              'key',
              key,
            ),
          ),
        );
      }
      final travel = await provider.create(' Travel ', 0);
      final other = await provider.create('出行', 1);
      await expectLater(
        provider.create(' travel ', 2),
        throwsA(isA<ListGroupNameException>()),
      );
      await expectLater(
        provider.rename(other.id, 'TRAVEL'),
        throwsA(isA<ListGroupNameException>()),
      );
      await provider.rename(travel.id, 'Travel');
      await provider.delete(travel.id);
      final replacement = await provider.create('travel', 2);
      expect(replacement.id, isNot(travel.id));
      expect(provider.groups, hasLength(2));
      expect(provider.allGroups, hasLength(3));
      expect(
        provider.validateName('工作', otherNames: ['工作']),
        'list_group.name_duplicate',
      );
      expect(provider.validateName(List.filled(24, '😀').join()), isNull);
    },
  );

  test('concurrent normalized duplicate creates are serialized', () async {
    final provider = ListGroupProvider();
    addTearDown(provider.dispose);
    final first = provider.create('旅行', 0);
    final second = provider.create(' 旅行 ', 1);
    await expectLater(second, throwsA(isA<ListGroupNameException>()));
    await first;
    expect(provider.groups, hasLength(1));
  });

  test(
    'mergeRemote is LWW by id, keeps local-only rows and tombstones across reload',
    () async {
      final provider = ListGroupProvider();
      addTearDown(provider.dispose);
      final local = _group('travel', '旅行', 21);
      final localOnly = _group('local-only', '本地清单', 20);
      await provider.mergeRemote([local.toJson(), localOnly.toJson()]);
      await provider.mergeRemote([_group('travel', '旧名称', 20).toJson()]);
      expect(provider.groups.firstWhere((g) => g.id == 'travel').name, '旅行');
      final tombstone = _group('travel', '旅行', 22, deleted: true);
      await provider.mergeRemote([
        tombstone.toJson(),
        _group('remote', '远端新增', 22).toJson(),
      ]);
      await provider.mergeRemote([local.toJson()]);
      expect(
        provider.groups.map((g) => g.id),
        containsAll(['remote', 'local-only']),
      );
      expect(provider.groups.any((g) => g.id == 'travel'), isFalse);
      expect(
        provider.allGroups.firstWhere((g) => g.id == 'travel').toJson(),
        tombstone.toJson(),
      );
      await provider.loadFromStorage();
      expect(
        provider.allGroups.firstWhere((g) => g.id == 'travel').isDeleted,
        isTrue,
      );
      await provider.mergeRemote([_group('travel', '恢复后', 23).toJson()]);
      expect(provider.groups.firstWhere((g) => g.id == 'travel').name, '恢复后');
    },
  );

  test(
    'a mutation re-reads sync writeback instead of replacing it with stale memory',
    () async {
      final provider = ListGroupProvider();
      addTearDown(provider.dispose);
      final local = await provider.create('旅行', 0);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        ListGroupProvider.storageKey,
        jsonEncode([local.toJson(), _group('remote', '远端清单', 21).toJson()]),
      );
      await provider.rename(local.id, '假期');
      expect(provider.groups.map((g) => g.name), containsAll(['假期', '远端清单']));
    },
  );

  for (final serverChange in [false, true]) {
    test(
      'AuthProvider isolates list groups when switching ${serverChange ? 'server' : 'account'}',
      () async {
        final mock = MockClient(
          (request) async => http.Response(
            jsonEncode(
              request.url.path == '/api/auth/me'
                  ? {
                      'user_id': serverChange ? 'user-a' : 'user-b',
                      'username': 'next',
                    }
                  : {},
            ),
            200,
          ),
        );
        addTearDown(mock.close);
        final auth = AuthProvider(
          baseUrl: 'https://one.test',
          initialState: const AuthState(userId: 'user-a', token: 'a-token'),
          clientFactory: (url, token) =>
              ApiClient(baseUrl: url, token: token, httpClient: mock),
        );
        final provider = ListGroupProvider();
        addTearDown(auth.dispose);
        addTearDown(provider.dispose);
        await provider.create('账号 A 清单', 0);
        await auth.loginWithToken(
          serverUrl: serverChange ? 'https://two.test' : 'https://one.test',
          token: 'b-token',
        );
        expect(
          provider.groups,
          isEmpty,
          reason: 'old memory is hidden at the account boundary',
        );
        await provider.loadFromStorage();
        expect(provider.groups, isEmpty);
        await provider.create('当前账号清单', 0);
        expect(provider.groups.single.name, '当前账号清单');
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString(ListGroupProvider.storageKey),
          isNot(contains('账号 A')),
        );
      },
    );
  }

  test(
    'account cleanup cancels queued writes and clears list group storage',
    () async {
      final provider = ListGroupProvider();
      addTearDown(provider.dispose);
      await provider.create('旧账号', 0);
      final pending = provider.create('迟到写入', 1);
      final checked = expectLater(pending, throwsStateError);
      await AccountLocalDataCleaner.clearSharedPreferences();
      provider.resetLocalState();
      await checked;
      await provider.loadFromStorage();
      expect(provider.groups, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(ListGroupProvider.storageKey), isFalse);
    },
  );
}
