import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

void main() {
  test('账号切换会冻结云同步并阻断旧账号异步回写', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();

    for (final field in const [
      'int _accountGeneration = 0;',
      'bool _syncSuspendedForAccountChange = false;',
      'Future<void>? _activeLocalWriteback;',
      'Future<T> _runAccountBoundWriteback<T>',
      'Future<void> resetForAccountChange() async',
      '_syncSuspendedForAccountChange = true;',
      'final activeWriteback = _activeLocalWriteback;',
      'await activeWriteback;',
      'void resumeForActiveAccount()',
      'expectedAccountGeneration',
      '_pullRemoteChanges(expectedAccountGeneration: accountGenerationAtStart)',
      'accountGenerationAtStart: accountGenerationAtStart',
    ]) {
      expect(providerSource, contains(field), reason: field);
    }

    expect(
      providerSource,
      contains('if (_syncSuspendedForAccountChange) {\n      return;\n    }'),
    );
    expect(
      mainSource,
      contains('await cloudSyncProvider.resetForAccountChange();'),
    );
    expect(mainSource, contains('cloudSyncProvider.resumeForActiveAccount();'));
  });

  test('resetForAccountChange 后旧账号 sync 响应不会写回本地', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'todos': json.encode([
        {'id': 'local-before-switch', 'title': '切号前本地数据'},
      ]),
    });
    final requestStarted = Completer<void>();
    final responseCompleter = Completer<http.Response>();
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/sync') {
          if (!requestStarted.isCompleted) requestStarted.complete();
          return responseCompleter.future;
        }
        return http.Response('{}', 200);
      }),
    );
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () => client;
    provider.serverConfigGetter = () => {'backup_enabled': true};

    final syncFuture = provider.syncNow();
    await requestStarted.future.timeout(const Duration(seconds: 1));
    await provider.resetForAccountChange();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'todos',
      json.encode([
        {'id': 'test-local', 'title': '新账号清理后的本地数据'},
      ]),
    );
    responseCompleter.complete(
      http.Response(
        json.encode({
          'server_updated_at': '2026-06-07T00:00:00.000Z',
          'server_version': 1,
          'todos': [
            {'id': 'admin-remote', 'title': '旧账号远端数据'},
          ],
        }),
        200,
        headers: const {'content-type': 'application/json'},
      ),
    );

    await syncFuture.timeout(const Duration(seconds: 2));
    final todos = prefs.getString('todos') ?? '';
    expect(todos, contains('test-local'));
    expect(todos, isNot(contains('admin-remote')));

    provider.dispose();
  });

  test('resetForAccountChange 后旧账号本地同步元数据不会重新载入内存', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'sync_last_time': '2026-06-07T12:00:00.000Z',
      'sync_auto': false,
      'sync_pending_local_changes': true,
      'sync_server_updated_at': '2026-06-07T12:00:00.000Z',
      'sync_server_version': 9,
    });
    final provider = CloudSyncProvider();

    final loadFuture = provider.loadFromStorage();
    await provider.resetForAccountChange();
    await loadFuture.timeout(const Duration(seconds: 1));

    expect(provider.config.autoSync, isTrue);
    expect(provider.config.lastSync.millisecondsSinceEpoch, 0);
    expect(provider.hasPendingChanges, isFalse);
    expect(provider.lastServerUpdatedAt, isEmpty);
    expect(provider.lastServerVersion, isNull);

    provider.dispose();
  });

  test('resetForAccountChange 会等待进行中的同步回调退出', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final onSyncedStarted = Completer<void>();
    final releaseOnSynced = Completer<void>();
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'admin-token',
      httpClient: MockClient((request) async {
        return http.Response(
          json.encode({
            'server_updated_at': '2026-06-07T00:00:00.000Z',
            'server_version': 1,
            'todos': [
              {'id': 'remote-during-switch', 'title': '写回中'},
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () => client;
    provider.serverConfigGetter = () => {'backup_enabled': true};
    provider.onSynced = (changedCollections) async {
      expect(changedCollections, contains('todos'));
      if (!onSyncedStarted.isCompleted) onSyncedStarted.complete();
      await releaseOnSynced.future;
    };

    final syncFuture = provider.syncNow();
    await onSyncedStarted.future.timeout(const Duration(seconds: 1));

    var resetCompleted = false;
    final resetFuture = provider.resetForAccountChange().then((_) {
      resetCompleted = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(resetCompleted, isFalse);

    releaseOnSynced.complete();
    await resetFuture.timeout(const Duration(seconds: 1));
    await syncFuture.timeout(const Duration(seconds: 1));
    expect(resetCompleted, isTrue);

    provider.dispose();
  });

  test('本地改动会后台自动同步，不需要手动入口', () {
    final source = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(source, contains('static const _autoSyncDelay'));
    expect(source, contains('Timer? _autoSyncTimer'));
    expect(source, contains('void markPendingLocalChange()'));
    expect(source, contains('_hasPendingChanges = true'));
    expect(source, contains('_scheduleAutoSync();'));
    expect(source, contains('if (_hasPendingChanges && _config.autoSync'));
    expect(source, contains('syncNow();'));
    expect(source, contains('_autoSyncTimer?.cancel();'));
    expect(source, contains("'user_profile': 'user_profile'"));
    expect(
      mainSource,
      contains(
        'userProvider.addListener(markUserProfileDirtyOnEditableChange);',
      ),
    );
    expect(
      mainSource,
      contains('locationReminderProvider.addListener(markDirty);'),
    );
    expect(mainSource, contains('ReminderRingtoneSettings.onChanged = (keys)'));
    expect(
      mainSource,
      contains(
        'final persisted = cloudSyncProvider.markPreferencesChanged(keys);',
      ),
    );
    expect(mainSource, contains('return persisted;'));
    expect(
      mainSource,
      isNot(
        contains(
          'preferencesProvider.addListener(cloudSyncProvider.markPreferencesChanged);',
        ),
      ),
    );
    expect(
      mainSource,
      contains(
        'preferencesProvider.onChangedKeys = cloudSyncProvider.markPreferencesChanged;',
      ),
    );
  });

  test('离线本地改动的待同步状态会持久化并在失败后保留重试', () {
    final source = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(source, contains("static const _pendingLocalChangesStorageKey"));
    expect(source, contains("'sync_pending_local_changes'"));
    expect(source, contains('prefs.getBool(_pendingLocalChangesStorageKey)'));
    expect(source, contains('unawaited(_persistPendingChanges(true))'));
    expect(source, contains('Future<void> _setPendingChanges('));
    expect(source, contains('() => _setPendingChanges('));
    expect(
      source,
      contains('var shouldRetryLocalChanges = _hasPendingChanges'),
    );
    expect(source, contains('changedCollections == null'));
    expect(source, contains('changedCollections.isNotEmpty'));
    expect(source, contains('await _writePendingChanges(localPrefs, true);'));
    expect(source, contains('_scheduleAutoSync(_autoRetryDelay);'));
  });

  test('登录后启用远端轮询拉取，登出或关闭自动同步会停止轮询', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(providerSource, contains('static const _remotePollDelay'));
    expect(providerSource, contains('Timer? _remotePollTimer'));
    expect(
      providerSource,
      contains('StreamSubscription<String>? _remoteEventSubscription'),
    );
    expect(providerSource, contains('void startRemotePolling()'));
    expect(providerSource, contains('void stopRemotePolling()'));
    expect(providerSource, contains('void _startRemoteEvents()'));
    expect(providerSource, contains('void _scheduleRemoteEventReconnect('));
    expect(providerSource, contains('void _scheduleRemotePoll'));
    expect(providerSource, contains('Future<void> _pollRemoteChanges()'));
    expect(providerSource, contains("client.get('/api/sync/status')"));
    expect(providerSource, contains(".streamLines('/api/sync/events')"));
    expect(providerSource, contains("'server_version'"));
    expect(providerSource, contains('_lastServerVersion'));
    expect(providerSource, contains('serverVersion <= _lastServerVersion!'));
    expect(
      providerSource,
      contains('await _pullRemoteChanges(\n        expectedAccountGeneration:'),
    );
    expect(providerSource, contains('_hasPendingChanges || _isSyncing'));
    expect(providerSource, contains('_scheduleRemotePoll();'));
    expect(mainSource, contains('Future<void> startCloudSyncAfterAuth'));
    expect(mainSource, contains("'server config before cloud sync'"));
    expect(mainSource, contains(r"'cloud sync $reason'"));
    expect(mainSource, contains('cloudSyncProvider.startRemotePolling();'));
    expect(mainSource, contains('cloudSyncProvider.stopRemotePolling();'));
  });

  test('同步回写不会用旧主题或旧时光币对象覆盖本地新状态', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(providerSource, contains('bool _remoteObjectIsOlderThanLocal'));
    expect(providerSource, contains("localKey != 'theme_shop_state'"));
    expect(providerSource, contains("localKey != 'duoyi_virtual_rewards'"));
    expect(
      providerSource,
      contains('_timestampGt(localUpdatedAt, remoteUpdatedAt)'),
    );
    expect(
      providerSource,
      contains('if (localUpdatedAt.isNotEmpty && remoteUpdatedAt.isEmpty)'),
    );
    expect(providerSource, contains(r'skipped stale object $remoteKey'));
  });

  test('同步事件流收到新版本后即时拉取，轮询仍作为兜底', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final backendSource = File('backend/main.py').readAsStringSync();

    for (final field in [
      'StreamSubscription<String>? _remoteEventSubscription',
      "Timer? _remoteEventRetryTimer",
      ".streamLines('/api/sync/events')",
      'void _handleRemoteEventLine(String line)',
      'void _dispatchRemoteEvent()',
      'void _scheduleRemoteEventReconnect(',
      "line.startsWith('event:')",
      "line.startsWith('data:')",
      "final eventName = _remoteEventName.isEmpty ? 'message' : _remoteEventName",
      "if (eventName != 'sync' || rawData.isEmpty) return;",
      "json.decode(rawData)",
      "decoded['server_version']",
      "decoded['server_updated_at']",
      'if (versionUnchanged || timestampUnchanged) return;',
      'if (_hasPendingChanges || _isSyncing || !_config.autoSync) return;',
      'cancelOnError: true',
      '_scheduleRemoteEventReconnect(_autoRetryDelay)',
      '_scheduleRemotePoll(_autoRetryDelay)',
      '_remoteEventRetryTimer?.cancel();',
      '_remoteEventSubscription?.cancel();',
    ]) {
      expect(providerSource, contains(field));
    }

    for (final field in [
      '@app.get("/api/sync/events")',
      'async def sync_events',
      'interval_seconds: int = Query(15, ge=2, le=60)',
      '"event: sync\\n"',
      'json.dumps(payload, ensure_ascii=False)',
      'media_type="text/event-stream"',
      '"Cache-Control": "no-cache"',
      '"X-Accel-Buffering": "no"',
    ]) {
      expect(backendSource, contains(field));
    }
  });

  test('远端轮询使用轻量版本探针，未变化时跳过全量同步', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final backendSource = File('backend/main.py').readAsStringSync();

    expect(providerSource, contains("static const _serverVersionStorageKey"));
    expect(providerSource, contains("'sync_server_version'"));
    expect(providerSource, contains("static const _serverUpdatedAtStorageKey"));
    expect(providerSource, contains("'sync_server_updated_at'"));
    expect(providerSource, contains('int? get lastServerVersion'));
    expect(providerSource, contains('String get lastServerUpdatedAt'));
    expect(providerSource, contains('_persistServerRevision(prefs, response)'));
    expect(providerSource, contains("response['server_updated_at']"));
    expect(providerSource, contains("response['server_version']"));
    expect(providerSource, contains('prefs.setInt(_serverVersionStorageKey'));
    expect(
      providerSource,
      contains('prefs.setString(_serverUpdatedAtStorageKey'),
    );
    expect(providerSource, contains('versionUnchanged || timestampUnchanged'));

    expect(backendSource, contains('sync_version INTEGER DEFAULT 0'));
    expect(backendSource, contains('("sync_data", "sync_version", "0")'));
    expect(backendSource, contains('@app.get("/api/sync/status")'));
    expect(backendSource, contains('def sync_status'));
    expect(backendSource, contains('"server_version"'));
    expect(backendSource, contains('next_sync_version'));
  });

  test('远端变化拉取使用集合 hash 增量接口，避免无本地改动时整包同步', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final backendSource = File('backend/main.py').readAsStringSync();

    expect(
      providerSource,
      contains(
        'Future<void> _pullRemoteChanges({int? expectedAccountGeneration})',
      ),
    );
    expect(providerSource, contains("client.post('/api/sync/pull'"));
    expect(providerSource, contains("'collection_hashes'"));
    expect(providerSource, contains('_collectionHashForKey('));
    expect(providerSource, contains('_itemHashBucketForKey('));
    expect(providerSource, contains('static const _syncPullCollections'));
    expect(providerSource, contains('sha256'));
    expect(providerSource, contains('.convert(utf8.encode'));
    expect(providerSource, contains('SplayTreeMap<String, Object?>'));
    expect(providerSource, contains('await _applySyncResponse('));
    expect(
      providerSource,
      contains('await _pullRemoteChanges(\n        expectedAccountGeneration:'),
    );

    final pollBody = providerSource.substring(
      providerSource.indexOf('Future<void> _pollRemoteChanges()'),
      providerSource.indexOf('static const _stringEncodedListKeys'),
    );
    expect(pollBody, isNot(contains('await syncNow();')));

    expect(backendSource, contains('class SyncPullRequest'));
    expect(backendSource, contains('@app.post("/api/sync/pull")'));
    expect(backendSource, contains('def sync_pull'));
    expect(backendSource, contains('SYNC_PULL_COLLECTIONS'));
    expect(backendSource, contains('def _sync_collection_hashes'));
    expect(backendSource, contains('def _payload_hash'));
    expect(
      backendSource,
      contains('collection_hashes = _sync_collection_hashes'),
    );
    expect(backendSource, contains('changed_payload = {'));
    expect(
      backendSource,
      contains(
        'if str(client_hashes.get(key) or "") != collection_hashes[key]',
      ),
    );
  });

  test('本地改动上传使用集合 hash delta，避免每次整包上传', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final backendSource = File('backend/main.py').readAsStringSync();

    expect(
      providerSource,
      contains("static const _collectionHashesStorageKey"),
    );
    expect(providerSource, contains("'sync_collection_hashes'"));
    expect(providerSource, contains('_lastCollectionHashes'));
    expect(providerSource, contains('_decodeCollectionHashes('));
    expect(providerSource, contains('_changedSyncCollections('));
    expect(providerSource, contains("client.post('/api/sync/delta'"));
    expect(providerSource, contains("'collections': changedCollections"));
    expect(providerSource, contains("response['collection_hashes']"));
    expect(providerSource, contains('_collectionHashesStorageKey'));

    final syncBody = providerSource.substring(
      providerSource.indexOf('Future<void> syncNow()'),
      providerSource.indexOf(
        'Future<void> _pullRemoteChanges({int? expectedAccountGeneration})',
      ),
    );
    expect(syncBody, contains("client.post('/api/sync', payload)"));
    expect(syncBody, contains("client.post('/api/sync/delta'"));
    expect(syncBody, contains('changedCollections == null'));
    expect(syncBody, contains('changedCollections.isEmpty'));

    expect(backendSource, contains('class SyncDeltaRequest'));
    expect(backendSource, contains('@app.post("/api/sync/delta")'));
    expect(backendSource, contains('def sync_delta'));
    expect(backendSource, contains('SyncRequest(**payload)'));
    expect(backendSource, contains('model_dump_payload=req.model_dump()'));
  });

  test('有条目 hash 基线时优先按条目 delta 上传', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final backendSource = File('backend/main.py').readAsStringSync();

    expect(providerSource, contains("static const _itemHashesStorageKey"));
    expect(providerSource, contains("'sync_item_hashes'"));
    expect(providerSource, contains('_lastItemHashes'));
    expect(
      providerSource,
      contains('_itemHashBucketForKey('),
      reason: '条目哈希按集合计算并缓存，原始存储不变的集合复用结果，避免重复全量哈希。',
    );
    expect(providerSource, contains('_buildSyncItemDelta('));
    expect(providerSource, contains("client.post('/api/sync/item-delta'"));
    expect(providerSource, contains("'items': items"));
    expect(providerSource, contains("'objects': objects"));
    expect(providerSource, contains("'deleted_items': deletedItems"));
    expect(providerSource, contains('_decodeItemHashes('));
    expect(providerSource, contains('_itemDeltaCollections'));
    expect(providerSource, contains('_objectDeltaCollections'));
    expect(providerSource, contains("'location_reminders'"));
    expect(providerSource, contains("_itemHashesStorageKey"));

    final syncBody = providerSource.substring(
      providerSource.indexOf('Future<void> syncNow()'),
      providerSource.indexOf(
        'Future<void> _pullRemoteChanges({int? expectedAccountGeneration})',
      ),
    );
    expect(syncBody, contains("client.post('/api/sync/item-delta'"));
    expect(syncBody, contains("client.post('/api/sync/delta'"));
    expect(
      syncBody.indexOf("client.post('/api/sync/item-delta'"),
      lessThan(syncBody.indexOf("client.post('/api/sync/delta'")),
    );

    expect(backendSource, contains('class SyncItemDeltaRequest'));
    expect(backendSource, contains('@app.post("/api/sync/item-delta")'));
    expect(backendSource, contains('def sync_item_delta'));
    expect(backendSource, contains('def _apply_item_delta_to_payload'));
    expect(backendSource, contains('SYNC_OBJECT_COLLECTIONS'));
    expect(backendSource, contains('SYNC_STATE_OBJECT_COLLECTIONS'));
    expect(backendSource, contains('_merge_by_timestamp('));
    expect(backendSource, contains('_merge_deleted_items('));
    expect(backendSource, contains('_prune_deleted_items('));
  });

  test('倒数日集合参与云同步 pull、delta 和删除墓碑', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final countdownSource = File(
      'lib/providers/countdown_provider.dart',
    ).readAsStringSync();

    final listPayloadsBody = providerSource.substring(
      providerSource.indexOf('static const _listPayloads'),
      providerSource.indexOf('static const _objectPayloads'),
    );
    expect(listPayloadsBody, contains("'duoyi_countdowns': 'countdowns'"));

    final pullCollectionsBody = providerSource.substring(
      providerSource.indexOf('static const _syncPullCollections'),
      providerSource.indexOf('static const _itemDeltaCollections'),
    );
    expect(pullCollectionsBody, contains("'countdowns'"));

    final itemDeltaCollectionsBody = providerSource.substring(
      providerSource.indexOf('static const _itemDeltaCollections'),
      providerSource.indexOf('static const _objectDeltaCollections'),
    );
    expect(itemDeltaCollectionsBody, contains("'countdowns'"));
    expect(
      countdownSource,
      contains("CloudSyncProvider.recordDeletedItem('countdowns'"),
    );
  });

  test('旧周年表 type=0 记录不会被 Flutter 同步过滤删除', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(providerSource, isNot(contains('_filterLocalSyncList')));
    expect(providerSource, isNot(contains("type.trim() != '0'")));
    expect(providerSource, isNot(contains('type.toInt() != 0')));
  });

  test('云端回写后会刷新本地个人资料且不触发二次脏标记', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(providerSource, contains("'user_profile': 'user_profile'"));
    expect(
      mainSource,
      contains('cloudSyncProvider.onSynced = (changedCollections)'),
    );
    expect(
      mainSource,
      contains('cloudSyncProvider.suppressDirtyMarkWhile(() async {'),
    );
    expect(
      mainSource,
      contains('reloadTasks.add(userProvider.loadFromStorage)'),
    );
    expect(mainSource, contains('_runSyncReloadTasksInBatches(reloadTasks)'));
    expect(
      mainSource,
      contains(
        'userProvider.addListener(markUserProfileDirtyOnEditableChange);',
      ),
    );
  });

  test('同步回调携带实际变更集合，main 只刷新命中的 provider', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(providerSource, contains('typedef SyncChangedCollectionsCallback'));
    expect(
      providerSource,
      contains('Future<void> Function(Set<String> changedCollections)'),
    );
    expect(providerSource, contains('class _SyncApplyResult'));
    expect(
      providerSource,
      contains('Future<_SyncApplyResult> _applySyncResponse'),
    );
    expect(providerSource, contains('final skippedCollections = <String>{};'));
    expect(
      providerSource,
      contains(
        'final localChangedBeforeApply =\n'
        '        _localChangeGeneration != localChangeGenerationAtStart;',
      ),
      reason: '应用前的本地改动判定改用变更生成数，避免每轮同步在主线程全量重建负载比对哈希。',
    );
    expect(providerSource, contains('skippedCollections.add(remoteKey);'));
    expect(
      providerSource,
      contains('if (!localChangedBeforeApply && skippedCollections.isEmpty)'),
    );
    expect(providerSource, contains('final nextHashes ='));
    expect(
      providerSource,
      contains('if (applyResult.changedCollections.isNotEmpty)'),
    );
    expect(
      providerSource,
      contains('await onSynced?.call(applyResult.changedCollections);'),
    );

    expect(
      mainSource,
      contains('cloudSyncProvider.onSynced = (changedCollections)'),
    );
    expect(mainSource, contains("changedCollections.contains('todos')"));
    expect(
      mainSource,
      contains('todoProvider.loadFromStorage(force: true)'),
      reason: '云同步回写后 TodoProvider 必须强制重读，避免内存旧快照覆盖同步结果。',
    );
    expect(mainSource, contains("changedCollections.contains('habits')"));
    expect(
      mainSource,
      contains('reloadTasks.add(habitProvider.loadFromStorage)'),
    );
    expect(
      mainSource,
      contains("changedCollections.contains('pomodoro_sessions')"),
    );
    expect(
      mainSource,
      contains('reloadTasks.add(pomodoroProvider.loadFromStorage)'),
    );
    expect(mainSource, contains("changedCollections.contains('user_profile')"));
    expect(
      mainSource,
      contains(
        "await authProvider.refreshMe(reason: 'cloud_sync_account_snapshot');",
      ),
    );
    expect(
      mainSource,
      contains("changedCollections.contains('virtual_rewards')"),
    );
    expect(mainSource, isNot(contains("reason: 'cloud_sync_virtual_rewards'")));
    expect(
      mainSource,
      contains("changedCollections.contains('location_reminders')"),
    );
    expect(
      mainSource,
      contains('reloadTasks.add(locationReminderProvider.loadFromStorage)'),
    );
    expect(
      mainSource,
      contains('locationReminderProvider.addListener(syncLocationGeofences);'),
    );
    expect(
      mainSource,
      contains(
        'await ReminderRingtoneSettings.applyPersistedSettingsToNative();',
      ),
    );
    expect(
      mainSource,
      contains("changedCollections.contains('workspace_payloads')"),
    );
    expect(mainSource, contains('await shareProvider.load();'));

    final onSyncedBody = mainSource.substring(
      mainSource.indexOf('cloudSyncProvider.onSynced = (changedCollections)'),
      mainSource.indexOf(
        'authProvider.addListener(() {',
        mainSource.indexOf('cloudSyncProvider.onSynced = (changedCollections)'),
      ),
    );
    expect(
      onSyncedBody,
      isNot(contains('await todoProvider.loadFromStorage();')),
    );
    expect(
      onSyncedBody,
      contains('await _runSyncReloadTasksInBatches(reloadTasks);'),
    );
  });

  test('同步回写内容相同时跳过 SharedPreferences 写入，降低无效 IO', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(providerSource, contains('Future<void> _writeLocalList('));
    expect(providerSource, contains('Map<String, dynamic> _readLocalObject('));
    expect(providerSource, contains('Future<void> _writeLocalObject('));
    expect(
      providerSource,
      contains('_syncPayloadHash(_readLocalList(prefs, localKey))'),
    );
    expect(
      providerSource,
      contains('_syncPayloadHash(_readLocalObject(prefs, localKey))'),
    );
    expect(
      providerSource,
      contains('await _writeLocalList(prefs, localKey, filteredValue);'),
    );
    expect(
      providerSource,
      contains('await _writeLocalObject(prefs, localKey, value);'),
    );

    final applyBody = providerSource.substring(
      providerSource.indexOf('Future<_SyncApplyResult> _applySyncResponse'),
      providerSource.indexOf('Future<void> _persistServerRevision'),
    );
    expect(applyBody, isNot(contains('await prefs.setString(localKey')));
    expect(
      applyBody,
      isNot(contains('await prefs.setStringList(\n          localKey')),
    );
  });

  test('个人资料仍可同步但统计重算不会刷新资料更新时间', () {
    final modelSource = File('lib/models/user_profile.dart').readAsStringSync();
    final providerSource = File(
      'lib/providers/user_provider.dart',
    ).readAsStringSync();
    final backendSource = File('backend/main.py').readAsStringSync();
    final recalcBody = providerSource.substring(
      providerSource.indexOf('void recalc({'),
      providerSource.indexOf('void _notifyListenersSafely()'),
    );

    expect(modelSource, contains('DateTime? updatedAt;'));
    expect(modelSource, contains("'updatedAt': updatedAt?.toIso8601String()"));
    expect(recalcBody, isNot(contains('updatedAt')));
    expect(
      providerSource,
      contains('if (touchUpdatedAt || _profile.updatedAt == null)'),
    );
    expect(
      backendSource,
      contains('def _merge_dict(server: dict, client: dict)'),
    );
    expect(backendSource, contains('def _item_updated_at(item: dict)'));
    expect(
      backendSource,
      contains(
        'for key in ("updatedAt", "updated_at", "modifiedAt", "endTime", "createdAt")',
      ),
    );
    expect(backendSource, contains('client_ts = _item_updated_at(client)'));
    expect(backendSource, contains('def _timestamp_gt(left: str, right: str)'));
    expect(backendSource, contains('_timestamp_gt(client_ts, server_ts)'));
  });

  test('屏幕和组件层不暴露手动云同步入口', () {
    final uiFiles = <File>[
      ...Directory('lib/screens')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      ...Directory('lib/widgets')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    ];

    final offenders = <String>[];
    for (final file in uiFiles) {
      final text = file.readAsStringSync();
      if (text.contains('CloudSyncProvider') ||
          text.contains('syncNow()') ||
          text.contains('.syncNow(')) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '云同步应由 main.dart/provider 后台排队触发，UI 层不能重新出现立即同步按钮。',
    );
  });

  test('共享空间合并保留可解释的冲突决策记录', () {
    final source = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(source, contains('class SyncMergeDecision'));
    expect(source, contains('lastWorkspaceMergeDecisions'));
    expect(source, contains('sync_merge_decisions'));
    expect(source, contains('final List<String> changedFields'));
    expect(source, contains("'changedFields': changedFields"));
    expect(source, contains('_changedWorkspaceFields(prior, item)'));
    expect(source, contains("'id', 'workspaceId', 'createdAt', 'updatedAt'"));
    expect(source, contains("winner: remoteWins ? 'remote' : 'local'"));
    expect(source, contains('final oldTs = _remoteItemUpdatedAt(prior);'));
    expect(source, contains('final newTs = _remoteItemUpdatedAt(item);'));
    expect(
      source,
      contains(
        'final remoteWins = oldTs.isEmpty || !_timestampGt(oldTs, newTs);',
      ),
    );
    expect(source, isNot(contains('newTs.compareTo(oldTs)')));
    expect(source, contains('云端更新时间不早于本地'));
    expect(source, contains('本地更新时间更新'));
  });

  test('冲突决策序列化保留字段级差异说明', () {
    final source = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(source, contains('SyncMergeDecision.fromJson'));
    expect(source, contains("json['changedFields'] as List?"));
    expect(source, contains("'changedFields': changedFields"));
    expect(source, contains("json['decidedAt']"));
    expect(source, contains('decision.toJson()'));
  });

  test('同步删除墓碑会上传并保存，避免云端旧列表复活本地删除', () {
    final source = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(
      source,
      contains("static const deletedItemsStorageKey = 'sync_deleted_items'"),
    );
    expect(source, contains('static Future<void> recordDeletedItem'));
    expect(source, contains('static Future<void> recordDeletedItems'));
    expect(source, contains("payload['deleted_items']"));
    expect(
      source,
      contains("final responseDeletedItems = response['deleted_items'];"),
    );
    expect(source, contains('var mergedDeletedItems ='));
    expect(source, contains('_filterDeletedRemoteList('));
    expect(source, contains('collection: remoteKey'));
    expect(source, contains('deletedItems: mergedDeletedItems'));
    expect(
      source,
      contains(
        'return updatedAt.isNotEmpty && _timestampGt(updatedAt, deletedAt);',
      ),
    );
    expect(source, contains('prefs.setString('));
  });

  test('本地模块删除都会记录同步删除墓碑', () {
    final pomodoro = File(
      'lib/providers/pomodoro_provider.dart',
    ).readAsStringSync();
    final timeAudit = File(
      'lib/providers/time_audit_provider.dart',
    ).readAsStringSync();
    final habit = File('lib/providers/habit_provider.dart').readAsStringSync();
    final todo = File('lib/providers/todo_provider.dart').readAsStringSync();
    final note = File('lib/providers/note_provider.dart').readAsStringSync();
    final countdown = File(
      'lib/providers/countdown_provider.dart',
    ).readAsStringSync();
    final calendar = File(
      'lib/providers/calendar_provider.dart',
    ).readAsStringSync();
    final locationReminders = File(
      'lib/providers/location_reminder_provider.dart',
    ).readAsStringSync();
    final quickCaptureTemplates = File(
      'lib/providers/quick_capture_template_provider.dart',
    ).readAsStringSync();
    final course = File(
      'lib/providers/course_provider.dart',
    ).readAsStringSync();
    final diary = File('lib/providers/diary_provider.dart').readAsStringSync();
    final anniversary = File(
      'lib/providers/anniversary_provider.dart',
    ).readAsStringSync();
    final goal = File('lib/providers/goal_provider.dart').readAsStringSync();

    expect(
      pomodoro,
      contains("CloudSyncProvider.recordDeletedItem('pomodoro_sessions'"),
    );
    expect(
      timeAudit,
      contains("CloudSyncProvider.recordDeletedItems('time_entries'"),
    );
    expect(habit, contains("CloudSyncProvider.recordDeletedItem('habits'"));
    // TodoProvider 统一使用批量删除 recordDeletedItems
    expect(todo, contains('CloudSyncProvider.recordDeletedItems('));
    expect(todo, contains("'todos',"));
    expect(note, contains("CloudSyncProvider.recordDeletedItem('notes'"));
    expect(
      countdown,
      contains("CloudSyncProvider.recordDeletedItem('countdowns'"),
    );
    expect(
      calendar,
      contains("CloudSyncProvider.recordDeletedItem('calendar_events'"),
    );
    expect(
      locationReminders,
      contains("CloudSyncProvider.recordDeletedItem('location_reminders'"),
    );
    expect(
      quickCaptureTemplates,
      contains("CloudSyncProvider.recordDeletedItem('quick_capture_templates'"),
    );
    expect(course, contains("CloudSyncProvider.recordDeletedItem('courses'"));
    expect(diary, contains("CloudSyncProvider.recordDeletedItem('diaries'"));
    expect(
      anniversary,
      contains("CloudSyncProvider.recordDeletedItem('anniversaries'"),
    );
    expect(goal, contains("CloudSyncProvider.recordDeletedItem('goals'"));
  });

  test('偏好、位置提醒和共享空间漏项纳入同步链路', () {
    final providerSource = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();
    final backendSource = File('backend/main.py').readAsStringSync();

    for (final field in const [
      "'duoyi_location_reminders_v1': 'location_reminders'",
      "'location_reminders'",
      "'pref_reminder_ringtone_volume_percent'",
      "'pref_reminder_ringtone_sound'",
      "'pref_daily_reminder_kind'",
      "'pref_daily_reminder_slot2_kind'",
      "'pref_daily_reminder_slot3_kind'",
      "'courses': _WorkspacePayloadSpec(",
      "'time_entries': _WorkspacePayloadSpec(",
      "localKey: 'duoyi_courses'",
      "localKey: 'duoyi_time_entries'",
    ]) {
      expect(providerSource, contains(field), reason: field);
    }

    for (final field in const [
      'locationReminderProvider.addListener(markDirty);',
      "changedCollections.contains('location_reminders')",
      'reloadTasks.add(locationReminderProvider.loadFromStorage)',
      'locationReminderProvider.addListener(syncLocationGeofences);',
      'preferencesProvider.onChangedKeys = cloudSyncProvider.markPreferencesChanged;',
      'ReminderRingtoneSettings.onChanged = (keys)',
      'final persisted = cloudSyncProvider.markPreferencesChanged(keys);',
      'return persisted;',
      'await ReminderRingtoneSettings.applyPersistedSettingsToNative();',
    ]) {
      expect(mainSource, contains(field), reason: field);
    }

    expect(
      mainSource,
      isNot(
        contains(
          'preferencesProvider.addListener(cloudSyncProvider.markPreferencesChanged);',
        ),
      ),
    );

    for (final field in const [
      'static const _preferencesChangedKeysStorageKey',
      'Future<void> markPreferencesChanged([Iterable<String>? keys])',
      'if (keys != null && normalizedKeys.isEmpty) return;',
      'final changedKeys = _readPendingPreferenceChangedKeys(prefs);',
      "if (changedKeys.isNotEmpty) 'changedKeys': changedKeys",
      'await prefs.remove(_preferencesChangedKeysStorageKey);',
      'normalized.remove(\'changedKeys\');',
      'normalized.remove(\'changed_keys\');',
    ]) {
      expect(providerSource, contains(field), reason: field);
    }

    final preferencesProvider = File(
      'lib/providers/preferences_provider.dart',
    ).readAsStringSync();
    final ringtoneSettings = File(
      'lib/services/reminder_ringtone_settings.dart',
    ).readAsStringSync();
    for (final field in const [
      'FutureOr<void> Function(Iterable<String> keys)? onChangedKeys;',
      'await callback(cleanKeys);',
      '_notifyPreferenceKeys(const [_kFirstDayOfWeek]);',
      '_notifyPreferenceKeys(_dailyReminderSlotKeys(index));',
      '_notifyPreferenceKeys(const [_kBottomNavVisible]);',
      '_notifyPreferenceKeys(const [_kBottomNavOrder]);',
    ]) {
      expect(preferencesProvider, contains(field), reason: field);
    }
    for (final field in const [
      'static FutureOr<void> Function(Iterable<String> keys)? onChanged;',
      'await onChanged?.call(const [volumePreferenceKey]);',
      'await onChanged?.call(const [soundPreferenceKey]);',
    ]) {
      expect(ringtoneSettings, contains(field), reason: field);
    }

    for (final field in const [
      'location_reminders TEXT DEFAULT',
      '("sync_data", "location_reminders", "\'[]\'")',
      'location_reminders: list = []',
      '"location_reminders"',
      'server_location_reminders = _list("location_reminders")',
      'merged_location_reminders = _merge_by_timestamp(',
      'req.location_reminders',
      'json.dumps(merged_location_reminders, ensure_ascii=False)',
      'merged_diaries = _merge_diaries_by_date(',
      'def _apply_tombstones_to_list(',
      'next_payload[collection_key] = _apply_tombstones_to_list(',
      'raw_changed_keys = client.get("changedKeys") or client.get("changed_keys")',
      'if changed_keys:',
      'result.pop("changedKeys", None)',
    ]) {
      expect(backendSource, contains(field), reason: field);
    }
  });

  test('课表、纪念日和位置提醒携带 updatedAt 防止旧同步覆盖', () {
    final courseModel = File(
      'lib/models/course_schedule.dart',
    ).readAsStringSync();
    final courseProvider = File(
      'lib/providers/course_provider.dart',
    ).readAsStringSync();
    final anniversaryModel = File(
      'lib/models/anniversary.dart',
    ).readAsStringSync();
    final anniversaryProvider = File(
      'lib/providers/anniversary_provider.dart',
    ).readAsStringSync();
    final locationModel = File(
      'lib/models/location_reminder.dart',
    ).readAsStringSync();
    final locationProvider = File(
      'lib/providers/location_reminder_provider.dart',
    ).readAsStringSync();

    for (final field in const [
      'DateTime updatedAt;',
      "'updatedAt': updatedAt.toIso8601String()",
      "DateTime.tryParse(json['updatedAt']?.toString() ?? '')",
      "DateTime.tryParse(json['updated_at']?.toString() ?? '')",
    ]) {
      expect(courseModel, contains(field), reason: 'course $field');
      expect(anniversaryModel, contains(field), reason: 'anniversary $field');
    }

    for (final field in const [
      'final DateTime updatedAt;',
      "'updatedAt': updatedAt.toIso8601String()",
      "DateTime.tryParse(json['updatedAt']?.toString() ?? '')",
      "DateTime.tryParse(json['updated_at']?.toString() ?? '')",
    ]) {
      expect(locationModel, contains(field), reason: 'location $field');
    }

    expect(courseProvider, contains('course.updatedAt = DateTime.now();'));
    expect(anniversaryProvider, contains('item.updatedAt = DateTime.now();'));
    expect(
      anniversaryProvider,
      contains('_items[idx].updatedAt = DateTime.now();'),
    );
    expect(
      locationProvider,
      contains('reminder.copyWith(updatedAt: DateTime.now())'),
    );

    final backendSource = File('backend/main.py').readAsStringSync();
    for (final field in const [
      'merged_annis = _merge_by_timestamp(',
      'server_annis,',
      'req_annis,',
      'merged_courses = _merge_by_timestamp(',
      'server_courses,',
      'req.courses,',
      'merged_location_reminders = _merge_by_timestamp(',
      'server_location_reminders,',
      'req.location_reminders,',
    ]) {
      expect(backendSource, contains(field), reason: field);
    }
  });

  test('会触发云同步的本地修改必须先落盘再通知监听', () {
    final habit = File('lib/providers/habit_provider.dart').readAsStringSync();
    final locationReminders = File(
      'lib/providers/location_reminder_provider.dart',
    ).readAsStringSync();
    final quickCaptureTemplates = File(
      'lib/providers/quick_capture_template_provider.dart',
    ).readAsStringSync();

    final addHabitBody = _methodBody(habit, 'Future<void> addHabit(');
    expect(addHabitBody, contains('await _save();'));
    expect(addHabitBody, contains('notifyListeners();'));
    _expectBefore(addHabitBody, 'await _save();', 'notifyListeners();');

    final importHabitsBody = _methodBody(
      habit,
      'Future<HabitImportSummary> importHabits(',
    );
    _expectBefore(importHabitsBody, 'await _save();', 'notifyListeners();');

    final incrementBody = _methodBody(
      habit,
      'Future<void> incrementHabitForDate(',
    );
    _expectBefore(incrementBody, 'await _save();', 'notifyListeners();');

    final decrementBody = _methodBody(
      habit,
      'Future<void> decrementHabitForDate(',
    );
    _expectBefore(decrementBody, 'await _save();', 'notifyListeners();');

    final locationRemoveBody = _methodBody(
      locationReminders,
      'Future<void> remove(String id)',
    );
    _expectBefore(
      locationRemoveBody,
      "await CloudSyncProvider.recordDeletedItem('location_reminders', id);",
      'notifyListeners();',
    );
    _expectBefore(locationRemoveBody, 'await _save();', 'notifyListeners();');

    final saveTriggeredHitsBody = _methodBody(
      locationReminders,
      'Future<void> _saveTriggeredHits(',
    );
    final normalizedSaveTriggeredHitsBody = saveTriggeredHitsBody.replaceAll(
      '\r\n',
      '\n',
    );
    expect(
      normalizedSaveTriggeredHitsBody,
      contains(
        "CloudSyncProvider.recordDeletedItems(\n        'location_reminders',",
      ),
    );
    _expectBefore(
      saveTriggeredHitsBody,
      "await CloudSyncProvider.recordDeletedItems(",
      'await _save();',
    );
    _expectBefore(
      saveTriggeredHitsBody,
      'await _save();',
      'notifyListeners();',
    );

    final ingestFixBody = _methodBody(
      locationReminders,
      'List<LocationReminderHit> ingestFix(',
    );
    expect(ingestFixBody, contains('_saveTriggeredHits(removedIds);'));
    expect(
      ingestFixBody,
      isNot(contains('_save();\n      notifyListeners();')),
    );

    final saveTemplateBody = _methodBody(
      quickCaptureTemplates,
      'Future<void> saveTemplate(',
    );
    _expectBefore(saveTemplateBody, 'await _persist();', 'notifyListeners();');

    final deleteTemplateBody = _methodBody(
      quickCaptureTemplates,
      'Future<void> deleteTemplate(String id)',
    );
    _expectBefore(
      deleteTemplateBody,
      "await CloudSyncProvider.recordDeletedItem('quick_capture_templates', id);",
      'notifyListeners();',
    );
    _expectBefore(
      deleteTemplateBody,
      'await _persist();',
      'notifyListeners();',
    );
  });

  test('无待同步标记时较旧的云端偏好不会回滚本地设备设置', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_show_lunar': false,
      'pref_date_format': 'dd/MM/yyyy',
      'sync_preferences_updated_at': '2026-06-10T00:00:00.000Z',
      'todos': '[]',
    });
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'test-token',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/sync') {
          return http.Response(
            json.encode({
              'server_updated_at': '2026-06-11T00:00:00.000Z',
              'server_version': 2,
              'todos': [
                {
                  'id': 'remote-todo',
                  'title': '远端待办',
                  'updatedAt': '2026-06-11T00:00:00.000Z',
                },
              ],
              'preferences': {
                'updatedAt': '2026-06-05T00:00:00.000Z',
                'values': {'pref_show_lunar': true},
              },
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200);
      }),
    );
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () => client;
    provider.serverConfigGetter = () => {'backup_enabled': true};

    await provider.syncNow();

    final prefs = await SharedPreferences.getInstance();
    // 旧云端偏好被拒绝，业务条目仍应用。
    expect(prefs.getBool('pref_show_lunar'), isFalse);
    expect(prefs.getString('pref_date_format'), 'dd/MM/yyyy');
    // 业务条目仍照常消费远端新值。
    expect(prefs.getString('todos'), contains('remote-todo'));

    provider.dispose();
  });

  test('较新的云端偏好仍会应用到本地', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_show_lunar': false,
      'sync_preferences_updated_at': '2026-06-01T00:00:00.000Z',
      'todos': '[]',
    });
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'test-token',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/sync') {
          return http.Response(
            json.encode({
              'server_updated_at': '2026-06-21T00:00:00.000Z',
              'server_version': 3,
              'preferences': {
                'updatedAt': '2026-06-20T00:00:00.000Z',
                'values': {'pref_show_lunar': true},
              },
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200);
      }),
    );
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () => client;
    provider.serverConfigGetter = () => {'backup_enabled': true};

    await provider.syncNow();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('pref_show_lunar'), isTrue);
    expect(prefs.getString('sync_preferences_updated_at'), isNotNull);

    provider.dispose();
  });
}

String _methodBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNonNegative, reason: signature);
  var parenDepth = 0;
  var open = -1;
  for (var i = start; i < source.length; i++) {
    final char = source.codeUnitAt(i);
    if (char == 40) parenDepth++;
    if (char == 41 && parenDepth > 0) parenDepth--;
    if (char == 123 && parenDepth == 0) {
      open = i;
      break;
    }
  }
  expect(open, isNonNegative, reason: signature);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final char = source.codeUnitAt(i);
    if (char == 123) depth++;
    if (char == 125) depth--;
    if (depth == 0) return source.substring(open, i + 1);
  }
  fail('未找到方法结束：$signature');
}

void _expectBefore(String source, String first, String second) {
  final firstIndex = source.indexOf(first);
  final secondIndex = source.indexOf(second);
  expect(firstIndex, isNonNegative, reason: first);
  expect(secondIndex, isNonNegative, reason: second);
  expect(
    firstIndex,
    lessThan(secondIndex),
    reason: '$first should precede $second',
  );
}
