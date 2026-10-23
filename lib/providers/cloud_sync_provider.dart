import 'dart:convert';
import 'dart:async';
import 'dart:collection';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/feature_flags.dart';
import '../services/api_client.dart';
import 'list_group_provider.dart';

class SyncConfig {
  final DateTime lastSync;
  final bool autoSync;

  const SyncConfig({required this.lastSync, this.autoSync = true});
}

class SyncMergeDecision {
  final String workspaceId;
  final String itemType;
  final String itemId;
  final String winner;
  final String reason;
  final List<String> changedFields;
  final String localUpdatedAt;
  final String remoteUpdatedAt;
  final DateTime decidedAt;

  const SyncMergeDecision({
    required this.workspaceId,
    required this.itemType,
    required this.itemId,
    required this.winner,
    required this.reason,
    this.changedFields = const [],
    required this.localUpdatedAt,
    required this.remoteUpdatedAt,
    required this.decidedAt,
  });

  Map<String, dynamic> toJson() => {
    'workspaceId': workspaceId,
    'itemType': itemType,
    'itemId': itemId,
    'winner': winner,
    'reason': reason,
    'changedFields': changedFields,
    'localUpdatedAt': localUpdatedAt,
    'remoteUpdatedAt': remoteUpdatedAt,
    'decidedAt': decidedAt.toIso8601String(),
  };

  factory SyncMergeDecision.fromJson(Map<String, dynamic> json) {
    return SyncMergeDecision(
      workspaceId: json['workspaceId']?.toString() ?? '',
      itemType: json['itemType']?.toString() ?? '',
      itemId: json['itemId']?.toString() ?? '',
      winner: json['winner']?.toString() ?? '',
      reason: json['reason']?.toString() ?? '',
      changedFields:
          (json['changedFields'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          const [],
      localUpdatedAt: json['localUpdatedAt']?.toString() ?? '',
      remoteUpdatedAt: json['remoteUpdatedAt']?.toString() ?? '',
      decidedAt:
          DateTime.tryParse(json['decidedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class _WorkspacePayloadSpec {
  final String localKey;
  final String itemType;

  const _WorkspacePayloadSpec({required this.localKey, required this.itemType});
}

class _WorkspaceMergeResult {
  final List<dynamic> items;
  final List<SyncMergeDecision> decisions;

  const _WorkspaceMergeResult(this.items, this.decisions);
}

class _SyncApplyResult {
  final Set<String> changedCollections;
  final Set<String> skippedCollections;
  final bool localChangedBeforeApply;

  const _SyncApplyResult({
    required this.changedCollections,
    required this.skippedCollections,
    required this.localChangedBeforeApply,
  });

  bool get hasSkippedLocalChanges =>
      skippedCollections.isNotEmpty || localChangedBeforeApply;
}

class _SyncCancelled implements Exception {
  const _SyncCancelled();
}

typedef SyncChangedCollectionsCallback =
    Future<void> Function(Set<String> changedCollections);

/// 云同步：服务器地址与 token 直接复用 AuthProvider(普通用户无需感知)。
/// 登录后和本地数据变更后自动同步。
class CloudSyncProvider extends ChangeNotifier {
  static const _autoSyncDelay = Duration(seconds: 20);
  static const _autoRetryDelay = Duration(minutes: 3);
  static const _remotePollDelay = Duration(minutes: 2);
  static const _serviceUnavailableMessage = '云同步暂不可用，请稍后重试或联系管理员';
  static const deletedItemsStorageKey = 'sync_deleted_items';
  static const _serverUpdatedAtStorageKey = 'sync_server_updated_at';
  static const _serverVersionStorageKey = 'sync_server_version';
  static const _collectionHashesStorageKey = 'sync_collection_hashes';
  static const _itemHashesStorageKey = 'sync_item_hashes';
  static const _pendingLocalChangesStorageKey = 'sync_pending_local_changes';
  static const _preferencesUpdatedAtStorageKey = 'sync_preferences_updated_at';
  static const _preferencesValuesSnapshotStorageKey =
      'sync_preferences_values_snapshot';
  static const _preferencesChangedKeysStorageKey =
      'sync_preferences_changed_keys';
  static const _preferencesFullSyncSentinel = '*';
  static const _quickCaptureTemplatesStorageKey =
      'duoyi_quick_capture_templates_v1';
  static const _quickCaptureTemplatesUpdatedAtStorageKey =
      'sync_quick_capture_templates_updated_at';

  SyncConfig _config = SyncConfig(
    lastSync: DateTime.fromMillisecondsSinceEpoch(0),
    autoSync: true,
  );
  bool _isSyncing = false;
  bool _syncQueued = false;
  bool _notifyQueued = false;
  String? _lastError;
  Timer? _autoSyncTimer;
  Timer? _remotePollTimer;
  Timer? _remoteEventRetryTimer;
  StreamSubscription<String>? _remoteEventSubscription;
  String _remoteEventName = '';
  final List<String> _remoteEventDataLines = <String>[];
  List<SyncMergeDecision> _lastWorkspaceMergeDecisions = const [];
  String _lastServerUpdatedAt = '';
  int? _lastServerVersion;
  Map<String, String> _lastCollectionHashes = const {};
  Map<String, Map<String, String>> _lastItemHashes = const {};
  String? _pendingPreferencesUpdatedAt;
  final Set<String> _pendingPreferenceKeys = <String>{};
  bool _pendingPreferencesFullSync = false;
  String? _pendingQuickCaptureTemplatesUpdatedAt;

  /// 按集合的解码缓存：原始存储内容不变时复用解码结果与哈希，
  /// 使每轮同步的重复负载构建（apply 末尾 rebuild）几乎零成本。
  final Map<String, _DecodedCollection> _decodedCollectionCache =
      <String, _DecodedCollection>{};
  Map<String, dynamic>? _workspacePayloadsCache;
  String? _workspaceCollectionHashCache;

  SyncChangedCollectionsCallback? onSynced;

  // 由 main.dart 注入(通过 AuthProvider 取活跃的 ApiClient)
  ApiClient? Function()? apiClientGetter;

  /// 可选：返回当前服务端 /api/config，用来判断 backup_enabled
  Map<String, dynamic>? Function()? serverConfigGetter;

  SyncConfig get config => _config;
  bool get isSyncing => _isSyncing;
  String? get lastError => _lastError;
  bool get hasEverSynced => _config.lastSync.millisecondsSinceEpoch > 0;
  String get lastServerUpdatedAt => _lastServerUpdatedAt;
  int? get lastServerVersion => _lastServerVersion;
  List<SyncMergeDecision> get lastWorkspaceMergeDecisions =>
      List.unmodifiable(_lastWorkspaceMergeDecisions);

  /// 是否有未同步到后端的本地改动（由 Provider 写入时打上时间戳；本次同步成功后清零）。
  bool _hasPendingChanges = false;
  int _localChangeGeneration = 0;
  int _accountGeneration = 0;
  bool _syncSuspendedForAccountChange = false;
  Future<void>? _activeLocalWriteback;
  bool get hasPendingChanges => _hasPendingChanges;

  bool _isCurrentAccountGeneration(int generation) =>
      generation == _accountGeneration && !_syncSuspendedForAccountChange;

  void _throwIfAccountGenerationChanged(int generation) {
    if (!_isCurrentAccountGeneration(generation)) {
      throw const _SyncCancelled();
    }
  }

  Future<T> _guardAccountGeneration<T>(
    int generation,
    Future<T> Function() body,
  ) async {
    _throwIfAccountGenerationChanged(generation);
    final result = await body();
    _throwIfAccountGenerationChanged(generation);
    return result;
  }

  Future<T> _runAccountBoundWriteback<T>(
    int generation,
    Future<T> Function() body,
  ) async {
    _throwIfAccountGenerationChanged(generation);
    final completer = Completer<void>();
    final activeFuture = completer.future;
    _activeLocalWriteback = activeFuture;
    try {
      _throwIfAccountGenerationChanged(generation);
      final result = await body();
      _throwIfAccountGenerationChanged(generation);
      return result;
    } finally {
      completer.complete();
      if (identical(_activeLocalWriteback, activeFuture)) {
        _activeLocalWriteback = null;
      }
    }
  }

  void _notifySyncStateChanged() {
    if (_notifyQueued) return;
    _notifyQueued = true;
    scheduleMicrotask(() {
      _notifyQueued = false;
      if (hasListeners) notifyListeners();
    });
  }

  void _scheduleQueuedSyncIfNeeded() {
    if (_syncQueued && _config.autoSync) {
      _syncQueued = false;
      _scheduleAutoSync(const Duration(milliseconds: 1200));
    } else {
      _syncQueued = false;
    }
  }

  String _userVisibleSyncError(Object error) {
    debugPrint('[CloudSync] $error');
    return userVisibleApiError(
      error,
      fallbackMessage: _serviceUnavailableMessage,
    );
  }

  Future<void> _persistPendingChanges(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await _writePendingChanges(prefs, value);
  }

  Future<void> _writePendingChanges(SharedPreferences prefs, bool value) async {
    await prefs.setBool(_pendingLocalChangesStorageKey, value);
  }

  Future<void> _setPendingChanges(SharedPreferences prefs, bool value) async {
    _hasPendingChanges = value;
    await _writePendingChanges(prefs, value);
  }

  /// 由外部（Provider 的 addListener）在本地数据发生变动后调用，
  /// 标记待同步并排队后台自动同步。
  ///
  /// 为避免冷启动 `loadFromStorage` 触发的 notifyListeners 与同步回写
  /// `onSynced → loadFromStorage` 触发的 notifyListeners 被当作"脏改动"
  /// 误报 badge，本方法仅在 [_suppressDirtyMark] = false 时生效。
  void markPendingLocalChange() {
    if (_suppressDirtyMark) return;
    _localChangeGeneration++;
    if (!_hasPendingChanges) {
      _hasPendingChanges = true;
      _notifySyncStateChanged();
    }
    unawaited(_persistPendingChanges(true));
    _remotePollTimer?.cancel();
    _scheduleAutoSync();
  }

  /// 由 PreferencesProvider 在本地偏好写入后调用。
  ///
  /// 内存标记（stamp / changedKeys / pending）与自动同步排队保持同步执行，
  /// 调用方 await 之前即可见；返回的 Future 在同步元数据落盘后完成，避免
  /// 进程退出或连续设置时丢失冲突元数据、或被旧 stamp 覆盖新 stamp。
  Future<void> markPreferencesChanged([Iterable<String>? keys]) {
    if (_suppressDirtyMark) return Future<void>.value();
    final normalizedKeys = _normalizePreferenceChangedKeys(keys);
    if (keys != null && normalizedKeys.isEmpty) return Future<void>.value();
    final stamp = DateTime.now().toUtc().toIso8601String();
    _pendingPreferencesUpdatedAt = stamp;
    if (keys == null) {
      _pendingPreferencesFullSync = true;
      _pendingPreferenceKeys.clear();
    } else if (!_pendingPreferencesFullSync) {
      _pendingPreferenceKeys.addAll(normalizedKeys);
    }
    markPendingLocalChange();
    return _persistPreferenceSyncMetadata();
  }

  Future<void> _preferenceMetadataWriteQueue = Future<void>.value();

  /// 串行落盘偏好同步元数据。每个任务执行时才读取最新内存状态，因此快速
  /// 连续设置不会被较早的调用用旧 stamp 覆盖；切号（[_accountGeneration]）
  /// 之后到达的旧任务直接丢弃，不把上一账号的同步元数据写给新账号。
  Future<void> _persistPreferenceSyncMetadata() {
    final generation = _accountGeneration;
    final next = _preferenceMetadataWriteQueue.then((_) async {
      if (generation != _accountGeneration) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        if (generation != _accountGeneration) return;
        final stamp = _pendingPreferencesUpdatedAt;
        if (stamp != null) {
          await prefs.setString(_preferencesUpdatedAtStorageKey, stamp);
        }
        await _persistPreferenceChangedKeys(prefs);
        if (_hasPendingChanges) {
          await _writePendingChanges(prefs, true);
        }
      } catch (error, stack) {
        debugPrint(
          '[CloudSync] failed to persist preference sync metadata: $error\n'
          '$stack',
        );
      }
    });
    _preferenceMetadataWriteQueue = next;
    return next;
  }

  void markQuickCaptureTemplatesChanged() {
    if (_suppressDirtyMark) return;
    final stamp = DateTime.now().toUtc().toIso8601String();
    _pendingQuickCaptureTemplatesUpdatedAt = stamp;
    unawaited(
      _persistSyncStamp(_quickCaptureTemplatesUpdatedAtStorageKey, stamp),
    );
    markPendingLocalChange();
  }

  Future<void> _persistSyncStamp(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _persistPreferenceChangedKeys([SharedPreferences? prefs]) async {
    final target = prefs ?? await SharedPreferences.getInstance();
    if (_pendingPreferencesFullSync) {
      await target.setStringList(_preferencesChangedKeysStorageKey, const [
        _preferencesFullSyncSentinel,
      ]);
      return;
    }
    final keys = _pendingPreferenceKeys.toList()..sort();
    await target.setStringList(_preferencesChangedKeysStorageKey, keys);
  }

  void _scheduleAutoSync([Duration delay = _autoSyncDelay]) {
    _autoSyncTimer?.cancel();
    if (_syncSuspendedForAccountChange ||
        !_config.autoSync ||
        !FeatureFlags.cloudSyncV2) {
      return;
    }
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      return;
    }
    final accountGenerationAtStart = _accountGeneration;
    _autoSyncTimer = Timer(delay, () {
      if (!_isCurrentAccountGeneration(accountGenerationAtStart)) return;
      if (_hasPendingChanges && _config.autoSync && !_isSyncing) {
        // ignore: discarded_futures
        syncNow();
      }
    });
  }

  void startRemotePolling() {
    if (_syncSuspendedForAccountChange) return;
    final alreadyPolling =
        _remoteEventSubscription != null || _remotePollTimer != null;
    _startRemoteEvents();
    if (!alreadyPolling) {
      _scheduleRemotePoll(Duration.zero);
    }
  }

  void stopRemotePolling() {
    _remotePollTimer?.cancel();
    _remotePollTimer = null;
    _remoteEventRetryTimer?.cancel();
    _remoteEventRetryTimer = null;
    _remoteEventSubscription?.cancel();
    _remoteEventSubscription = null;
    _remoteEventName = '';
    _remoteEventDataLines.clear();
  }

  void _startRemoteEvents() {
    if (_remoteEventSubscription != null) return;
    if (_syncSuspendedForAccountChange ||
        !_config.autoSync ||
        !FeatureFlags.cloudSyncV2) {
      return;
    }
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      return;
    }
    final accountGenerationAtStart = _accountGeneration;
    _remoteEventRetryTimer?.cancel();
    _remoteEventRetryTimer = null;
    _remoteEventSubscription = client
        .streamLines('/api/sync/events')
        .listen(
          (line) {
            if (!_isCurrentAccountGeneration(accountGenerationAtStart)) return;
            _handleRemoteEventLine(line);
          },
          onError: (Object error) {
            if (!_isCurrentAccountGeneration(accountGenerationAtStart)) return;
            _lastError = _userVisibleSyncError(error);
            _remoteEventSubscription = null;
            _remoteEventName = '';
            _remoteEventDataLines.clear();
            _scheduleRemoteEventReconnect(_autoRetryDelay);
            _scheduleRemotePoll(_autoRetryDelay);
            _notifySyncStateChanged();
          },
          onDone: () {
            if (!_isCurrentAccountGeneration(accountGenerationAtStart)) return;
            _remoteEventSubscription = null;
            _remoteEventName = '';
            _remoteEventDataLines.clear();
            _scheduleRemoteEventReconnect(_autoRetryDelay);
            _scheduleRemotePoll(_autoRetryDelay);
          },
          cancelOnError: true,
        );
  }

  void _scheduleRemoteEventReconnect([Duration delay = _autoRetryDelay]) {
    _remoteEventRetryTimer?.cancel();
    if (_syncSuspendedForAccountChange ||
        !_config.autoSync ||
        !FeatureFlags.cloudSyncV2) {
      return;
    }
    if (_remoteEventSubscription != null) return;
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      return;
    }
    final accountGenerationAtStart = _accountGeneration;
    _remoteEventRetryTimer = Timer(delay, () {
      _remoteEventRetryTimer = null;
      if (!_isCurrentAccountGeneration(accountGenerationAtStart)) return;
      _startRemoteEvents();
    });
  }

  void _handleRemoteEventLine(String line) {
    if (line.isEmpty) {
      _dispatchRemoteEvent();
      return;
    }
    if (line.startsWith(':')) return;
    if (line.startsWith('event:')) {
      _remoteEventName = line.substring('event:'.length).trim();
      return;
    }
    if (line.startsWith('data:')) {
      _remoteEventDataLines.add(line.substring('data:'.length).trimLeft());
    }
  }

  void _dispatchRemoteEvent() {
    if (_syncSuspendedForAccountChange) return;
    final accountGenerationAtStart = _accountGeneration;
    final eventName = _remoteEventName.isEmpty ? 'message' : _remoteEventName;
    final rawData = _remoteEventDataLines.join('\n');
    _remoteEventName = '';
    _remoteEventDataLines.clear();
    if (eventName != 'sync' || rawData.isEmpty) return;
    if (_hasPendingChanges || _isSyncing || !_config.autoSync) return;
    try {
      final decoded = json.decode(rawData);
      if (decoded is! Map) return;
      final serverVersion = (decoded['server_version'] as num?)?.toInt();
      final serverUpdatedAt = decoded['server_updated_at']?.toString() ?? '';
      final versionUnchanged =
          serverVersion != null &&
          _lastServerVersion != null &&
          serverVersion <= _lastServerVersion!;
      final timestampUnchanged =
          serverVersion == null &&
          serverUpdatedAt.isNotEmpty &&
          serverUpdatedAt == _lastServerUpdatedAt;
      if (versionUnchanged || timestampUnchanged) return;
      // ignore: discarded_futures
      _pullRemoteChanges(expectedAccountGeneration: accountGenerationAtStart);
    } catch (e) {
      _lastError = _userVisibleSyncError(e);
      _notifySyncStateChanged();
    }
  }

  void _scheduleRemotePoll([Duration delay = _remotePollDelay]) {
    _remotePollTimer?.cancel();
    if (_syncSuspendedForAccountChange ||
        !_config.autoSync ||
        !FeatureFlags.cloudSyncV2) {
      return;
    }
    if (_hasPendingChanges || _isSyncing) return;
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      return;
    }
    final accountGenerationAtStart = _accountGeneration;
    _remotePollTimer = Timer(delay, () {
      _remotePollTimer = null;
      if (!_isCurrentAccountGeneration(accountGenerationAtStart)) return;
      if (_hasPendingChanges || !_config.autoSync || _isSyncing) {
        _scheduleRemotePoll();
        return;
      }
      // ignore: discarded_futures
      _pollRemoteChanges();
    });
  }

  /// 让一段代码块内的 `markPendingLocalChange` 静默（调用链返回后自动恢复）。
  ///
  /// 用法：
  /// ```dart
  /// await cloudSync.suppressDirtyMarkWhile(() async {
  ///   await todoProvider.loadFromStorage();
  /// });
  /// ```
  Future<void> suppressDirtyMarkWhile(Future<void> Function() body) async {
    _dirtyMarkSuppressDepth++;
    try {
      await body();
    } finally {
      _dirtyMarkSuppressDepth--;
    }
  }

  bool _dirtyMarkEnabled = false; // 初始 false，等 main.dart 显式放开
  int _dirtyMarkSuppressDepth = 0;
  bool get _suppressDirtyMark =>
      !_dirtyMarkEnabled || _dirtyMarkSuppressDepth > 0;

  /// 让外部显式放开 dirty 抑制。`main.dart` 在所有冷启动 `loadFromStorage`
  /// 完成、即将 `runApp` 之前调一次 `setDirtyMarkEnabled(true)`。
  set dirtyMarkEnabled(bool value) {
    _dirtyMarkEnabled = value;
  }

  Future<void> resetForAccountChange() async {
    _accountGeneration++;
    _syncSuspendedForAccountChange = true;
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    stopRemotePolling();
    final activeWriteback = _activeLocalWriteback;
    if (activeWriteback != null) {
      await activeWriteback;
    }
    _isSyncing = false;
    _syncQueued = false;
    _notifyQueued = false;
    _lastError = null;
    _lastWorkspaceMergeDecisions = const <SyncMergeDecision>[];
    _lastServerUpdatedAt = '';
    _lastServerVersion = null;
    _lastCollectionHashes = const <String, String>{};
    _lastItemHashes = const <String, Map<String, String>>{};
    _pendingPreferencesUpdatedAt = null;
    _pendingPreferenceKeys.clear();
    _pendingPreferencesFullSync = false;
    _pendingQuickCaptureTemplatesUpdatedAt = null;
    _decodedCollectionCache.clear();
    _workspacePayloadsCache = null;
    _workspaceCollectionHashCache = null;
    _hasPendingChanges = false;
    _localChangeGeneration++;
    _config = SyncConfig(
      lastSync: DateTime.fromMillisecondsSinceEpoch(0),
      autoSync: true,
    );
    _notifySyncStateChanged();
  }

  void resumeForActiveAccount() {
    _syncSuspendedForAccountChange = false;
  }

  /// cloud_sync_v2 特性开关：关闭时 [syncNow] 直接返回，不发出网络请求。
  /// 对应 Requirements 12.6。
  bool get isCloudSyncV2Enabled => FeatureFlags.cloudSyncV2;

  Future<void> _pollRemoteChanges() async {
    if (_syncSuspendedForAccountChange ||
        !_config.autoSync ||
        !FeatureFlags.cloudSyncV2) {
      return;
    }
    if (_hasPendingChanges || _isSyncing) {
      _scheduleRemotePoll();
      return;
    }
    final accountGenerationAtStart = _accountGeneration;
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      return;
    }

    try {
      final status = await client.get('/api/sync/status');
      if (!_isCurrentAccountGeneration(accountGenerationAtStart)) return;
      final serverVersion = (status['server_version'] as num?)?.toInt();
      final serverUpdatedAt = status['server_updated_at']?.toString() ?? '';
      final versionUnchanged =
          serverVersion != null &&
          _lastServerVersion != null &&
          serverVersion <= _lastServerVersion!;
      final timestampUnchanged =
          serverVersion == null &&
          serverUpdatedAt.isNotEmpty &&
          serverUpdatedAt == _lastServerUpdatedAt;

      if (versionUnchanged || timestampUnchanged) {
        final hadError = _lastError != null;
        _lastError = null;
        _scheduleRemotePoll();
        if (hadError) _notifySyncStateChanged();
        return;
      }

      await _pullRemoteChanges(
        expectedAccountGeneration: accountGenerationAtStart,
      );
    } catch (e) {
      if (!_isCurrentAccountGeneration(accountGenerationAtStart)) return;
      _lastError = _userVisibleSyncError(e);
      _scheduleRemotePoll(_autoRetryDelay);
      _notifySyncStateChanged();
    }
  }

  static const _stringEncodedListKeys = <String>{
    'todos',
    'habits',
    'pomodoro_sessions',
    'pomodoro_focus_penalties',
    'duoyi_location_reminders_v1',
  };

  static const _listPayloads = <String, String>{
    'todos': 'todos',
    'habits': 'habits',
    'pomodoro_sessions': 'pomodoro_sessions',
    'pomodoro_focus_penalties': 'focus_penalties',
    'duoyi_notes': 'notes',
    'duoyi_countdowns': 'countdowns',
    'duoyi_anniversaries_v2': 'anniversaries',
    'duoyi_diary': 'diaries',
    'duoyi_goals': 'goals',
    'duoyi_local_calendar_events_v1': 'calendar_events',
    'duoyi_time_entries': 'time_entries',
    'duoyi_courses': 'courses',
    'duoyi_location_reminders_v1': 'location_reminders',
  };

  static const _objectPayloads = <String, String>{
    'pomodoro_config': 'pomodoro_config',
    'user_profile': 'user_profile',
    'duoyi_course_settings': 'course_settings',
    'duoyi_achievements_unlocked': 'achievement_states',
    'duoyi_virtual_rewards': 'virtual_rewards',
    'duoyi_focus_rooms': 'focus_rooms',
    'theme_shop_state': 'theme_shop_state',
  };

  static const _preferenceBoolKeys = <String>{
    'pref_haptic_feedback',
    'pref_show_lunar',
    'pref_show_completed_todos',
    'pref_quick_capture_fab',
    'pref_notification_quick_add',
    'pref_notification_today_progress',
    'pref_daily_reminder_enabled',
    'pref_daily_reminder_today_tasks',
    'pref_daily_reminder_tomorrow_plan',
    'pref_daily_reminder_overdue',
    'pref_daily_reminder_pause_holidays',
    'pref_daily_reminder_slot2_enabled',
    'pref_daily_reminder_slot2_today',
    'pref_daily_reminder_slot2_tomorrow',
    'pref_daily_reminder_slot2_overdue',
    'pref_daily_reminder_slot2_pause_holidays',
    'pref_daily_reminder_slot3_enabled',
    'pref_daily_reminder_slot3_today',
    'pref_daily_reminder_slot3_tomorrow',
    'pref_daily_reminder_slot3_overdue',
    'pref_daily_reminder_slot3_pause_holidays',
    'pref_daily_report_reminder',
    'pref_weekly_report_reminder',
    'pref_monthly_report_reminder',
    'pref_yearly_report_reminder',
  };

  static const _preferenceIntKeys = <String>{
    'pref_first_day_of_week',
    'pref_default_tab',
    'pref_default_pomodoro_minutes',
    'pref_notification_history_limit',
    'pref_auto_archive_completed_days',
    'pref_daily_reminder_hour',
    'pref_daily_reminder_minute',
    'pref_daily_reminder_slot2_hour',
    'pref_daily_reminder_slot2_minute',
    'pref_daily_reminder_slot3_hour',
    'pref_daily_reminder_slot3_minute',
    'pref_daily_report_reminder_hour',
    'pref_daily_report_reminder_minute',
    'pref_weekly_report_reminder_weekday',
    'pref_weekly_report_reminder_hour',
    'pref_weekly_report_reminder_minute',
    'pref_monthly_report_reminder_day',
    'pref_monthly_report_reminder_hour',
    'pref_monthly_report_reminder_minute',
    'pref_yearly_report_reminder_month',
    'pref_yearly_report_reminder_day',
    'pref_yearly_report_reminder_hour',
    'pref_yearly_report_reminder_minute',
    'pref_reminder_ringtone_volume_percent',
  };

  static const _preferenceStringKeys = <String>{
    'pref_date_format',
    'pref_app_timezone_iana',
    'pref_app_timezone_mode',
    'pref_daily_reminder_kind',
    'pref_daily_reminder_slot2_kind',
    'pref_daily_reminder_slot3_kind',
    'pref_reminder_ringtone_sound',
  };

  static const _preferenceStringListKeys = <String>{
    'pref_daily_reminder_repeat_days',
    'pref_daily_reminder_slot2_repeat_days',
    'pref_daily_reminder_slot3_repeat_days',
    'pref_bottom_nav_order',
    'pref_bottom_nav_visible',
  };

  static final Set<String> _preferenceKeys = {
    ..._preferenceBoolKeys,
    ..._preferenceIntKeys,
    ..._preferenceStringKeys,
    ..._preferenceStringListKeys,
  };

  static const _syncPullCollections = <String>{
    'todos',
    'habits',
    'pomodoro_sessions',
    'focus_penalties',
    'notes',
    'countdowns',
    'anniversaries',
    'diaries',
    'goals',
    'calendar_events',
    'time_entries',
    'courses',
    'location_reminders',
    'pomodoro_config',
    'user_profile',
    'course_settings',
    'achievement_states',
    'virtual_rewards',
    'focus_rooms',
    'theme_shop_state',
    'preferences',
    'quick_capture_templates',
    'list_groups',
    'deleted_items',
    'workspace_payloads',
  };

  static const _itemDeltaCollections = <String>{
    'todos',
    'habits',
    'pomodoro_sessions',
    'focus_penalties',
    'notes',
    'countdowns',
    'anniversaries',
    'diaries',
    'goals',
    'calendar_events',
    'time_entries',
    'courses',
    'location_reminders',
    'list_groups',
  };

  static const _objectDeltaCollections = <String>{
    'pomodoro_config',
    'user_profile',
    'course_settings',
    'achievement_states',
    'virtual_rewards',
    'focus_rooms',
    'theme_shop_state',
    'preferences',
    'quick_capture_templates',
  };

  static Future<void> recordDeletedItem(
    String collection,
    String id, {
    DateTime? deletedAt,
  }) async {
    await recordDeletedItems(collection, [id], deletedAt: deletedAt);
  }

  static Future<void> recordDeletedItems(
    String collection,
    Iterable<String> ids, {
    DateTime? deletedAt,
  }) async {
    final cleanIds = ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (cleanIds.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final deleted = _decodeDeletedItems(
      prefs.getString(deletedItemsStorageKey),
    );
    final bucket = deleted.putIfAbsent(collection, () => <String, String>{});
    final stamp = (deletedAt ?? DateTime.now()).toIso8601String();
    for (final id in cleanIds) {
      final current = bucket[id];
      if (current == null || stamp.compareTo(current) > 0) {
        bucket[id] = stamp;
      }
    }
    await prefs.setString(deletedItemsStorageKey, json.encode(deleted));
  }

  static Map<String, Map<String, String>> _decodeDeletedItems(String? raw) {
    if (raw == null || raw.isEmpty) return <String, Map<String, String>>{};
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return <String, Map<String, String>>{};
      final result = <String, Map<String, String>>{};
      for (final entry in decoded.entries) {
        final bucket = <String, String>{};
        final value = entry.value;
        if (value is Map) {
          for (final entry in value.entries) {
            final id = entry.key.toString().trim();
            final deletedAt = entry.value?.toString() ?? '';
            if (id.isNotEmpty && deletedAt.isNotEmpty) {
              bucket[id] = deletedAt;
            }
          }
        }
        if (bucket.isNotEmpty) {
          result[entry.key.toString()] = bucket;
        }
      }
      return result;
    } catch (_) {
      return <String, Map<String, String>>{};
    }
  }

  static List<dynamic> _filterDeletedRemoteList({
    required String collection,
    required List<dynamic> items,
    required Map<String, Map<String, String>> deletedItems,
  }) {
    final tombstones = deletedItems[collection];
    if (tombstones == null || tombstones.isEmpty) return items;
    return items.where((item) {
      if (item is! Map || item['id'] == null) return true;
      final deletedAt = tombstones[item['id'].toString()];
      if (deletedAt == null || deletedAt.isEmpty) return true;
      final updatedAt = _remoteItemUpdatedAt(item);
      return updatedAt.isNotEmpty && _timestampGt(updatedAt, deletedAt);
    }).toList();
  }

  static bool _timestampGt(String left, String right) {
    final leftDt = DateTime.tryParse(left);
    final rightDt = DateTime.tryParse(right);
    if (leftDt != null && rightDt != null) {
      return leftDt.toUtc().isAfter(rightDt.toUtc());
    }
    return left.compareTo(right) > 0;
  }

  static Map<String, Map<String, String>> _mergeDeletedItemMaps(
    Map<String, Map<String, String>> a,
    Map<String, Map<String, String>> b,
  ) {
    final merged = <String, Map<String, String>>{
      for (final entry in a.entries)
        entry.key: Map<String, String>.from(entry.value),
    };
    for (final entry in b.entries) {
      final bucket = merged.putIfAbsent(entry.key, () => <String, String>{});
      for (final item in entry.value.entries) {
        final current = bucket[item.key];
        if (current == null || _timestampGt(item.value, current)) {
          bucket[item.key] = item.value;
        }
      }
    }
    return merged;
  }

  static String _remoteItemUpdatedAt(Map<dynamic, dynamic> item) {
    for (final key in const [
      'updatedAt',
      'updated_at',
      'modifiedAt',
      'endTime',
      'createdAt',
    ]) {
      final value = item[key]?.toString() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Future<void> loadFromStorage() async {
    final accountGenerationAtStart = _accountGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (!_isCurrentAccountGeneration(accountGenerationAtStart)) return;
    final lastSyncStr = prefs.getString('sync_last_time');
    final lastSync = lastSyncStr != null
        ? DateTime.parse(lastSyncStr)
        : DateTime.fromMillisecondsSinceEpoch(0);
    final autoSync = prefs.getBool('sync_auto') ?? true;
    _lastServerUpdatedAt = prefs.getString(_serverUpdatedAtStorageKey) ?? '';
    _lastServerVersion = prefs.getInt(_serverVersionStorageKey);
    _lastCollectionHashes = _decodeCollectionHashes(
      prefs.getString(_collectionHashesStorageKey),
    );
    _lastItemHashes = _decodeItemHashes(prefs.getString(_itemHashesStorageKey));
    _hasPendingChanges = prefs.getBool(_pendingLocalChangesStorageKey) ?? false;
    final preferenceChangedKeys = prefs.getStringList(
      _preferencesChangedKeysStorageKey,
    );
    _pendingPreferencesFullSync =
        preferenceChangedKeys?.contains(_preferencesFullSyncSentinel) ?? false;
    _pendingPreferenceKeys
      ..clear()
      ..addAll(_normalizePreferenceChangedKeys(preferenceChangedKeys));
    _config = SyncConfig(lastSync: lastSync, autoSync: autoSync);
    _lastWorkspaceMergeDecisions =
        (prefs.getStringList('sync_merge_decisions') ?? const [])
            .map((raw) {
              try {
                return SyncMergeDecision.fromJson(
                  Map<String, dynamic>.from(json.decode(raw) as Map),
                );
              } catch (_) {
                return null;
              }
            })
            .whereType<SyncMergeDecision>()
            .toList();
    if (!_isCurrentAccountGeneration(accountGenerationAtStart)) return;
    _notifySyncStateChanged();
  }

  Future<void> setAutoSync(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_auto', value);
    _config = SyncConfig(lastSync: _config.lastSync, autoSync: value);
    if (value) {
      resumeForActiveAccount();
    }
    if (value && _hasPendingChanges) {
      _scheduleAutoSync();
    } else if (value) {
      _scheduleRemotePoll(Duration.zero);
    } else {
      _autoSyncTimer?.cancel();
      stopRemotePolling();
    }
    _notifySyncStateChanged();
  }

  Future<void> syncNow() async {
    _autoSyncTimer?.cancel();
    // Req 12.6：关闭 cloud_sync_v2 时完全离线可用，不发出任何网络请求。
    if (!FeatureFlags.cloudSyncV2) {
      return;
    }
    if (_syncSuspendedForAccountChange) {
      return;
    }
    if (_isSyncing) {
      _syncQueued = true;
      return;
    }
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      _lastError = '请先登录';
      _notifySyncStateChanged();
      return;
    }
    // 如果服务端关掉了 backup_enabled，就不要浪费网络
    if (serverConfigGetter != null) {
      final cfg = serverConfigGetter!.call();
      if (cfg != null && cfg['backup_enabled'] == false) {
        _lastError = '管理员已关闭云端备份';
        _notifySyncStateChanged();
        _scheduleQueuedSyncIfNeeded();
        return;
      }
    }
    _isSyncing = true;
    _lastError = null;
    _notifySyncStateChanged();
    final accountGenerationAtStart = _accountGeneration;

    SharedPreferences? prefs;
    var shouldRetryLocalChanges = _hasPendingChanges;
    try {
      prefs = await SharedPreferences.getInstance();
      if (!_isCurrentAccountGeneration(accountGenerationAtStart)) {
        _isSyncing = false;
        _notifySyncStateChanged();
        return;
      }

      final syncGeneration = _localChangeGeneration;
      // 负载构建 + 哈希是 CPU 密集型操作（JSON 解码 + 递归排序 + SHA-256，
      // 2000 条待办时约 120ms），合并为单次后台 isolate 往返执行，主线程
      // 只保留 prefs 字符串读取与小负载组装，UI 不再被同步阻塞。
      final prepared = await _buildLocalSyncPayload(prefs);
      final payload = prepared.payload;
      final localHashes = prepared.collections;
      final localItemHashes = prepared.items;
      final itemDelta = _buildSyncItemDelta(payload, localItemHashes);
      final changedCollections = _changedSyncCollections(payload, localHashes);
      if (!_isCurrentAccountGeneration(accountGenerationAtStart)) {
        _isSyncing = false;
        _notifySyncStateChanged();
        return;
      }
      shouldRetryLocalChanges =
          shouldRetryLocalChanges ||
          changedCollections == null ||
          changedCollections.isNotEmpty;
      Map<String, dynamic> response;
      if (changedCollections == null) {
        response = await client.post('/api/sync', payload);
      } else if (changedCollections.isEmpty) {
        await _runAccountBoundWriteback(accountGenerationAtStart, () async {
          _lastCollectionHashes = localHashes;
          _lastItemHashes = localItemHashes;
          await _guardAccountGeneration(
            accountGenerationAtStart,
            () => prefs!.setString(
              _collectionHashesStorageKey,
              json.encode(localHashes),
            ),
          );
          await _guardAccountGeneration(
            accountGenerationAtStart,
            () => prefs!.setString(
              _itemHashesStorageKey,
              json.encode(localItemHashes),
            ),
          );
          await _guardAccountGeneration(
            accountGenerationAtStart,
            () => _persistPreferencesSnapshot(prefs!, payload['preferences']),
          );
          await _guardAccountGeneration(
            accountGenerationAtStart,
            () => _setPendingChanges(
              prefs!,
              _localChangeGeneration != syncGeneration,
            ),
          );
        });
        _lastError = null;
        _isSyncing = false;
        if (_hasPendingChanges) {
          _scheduleAutoSync();
        } else {
          _scheduleRemotePoll();
        }
        _notifySyncStateChanged();
        _scheduleQueuedSyncIfNeeded();
        return;
      } else if (itemDelta != null && itemDelta.isNotEmpty) {
        response = await client.post('/api/sync/item-delta', {
          ...itemDelta,
          'collection_hashes': localHashes,
        });
      } else {
        response = await client.post('/api/sync/delta', {
          'collections': changedCollections,
          'collection_hashes': localHashes,
        });
      }
      if (!_isCurrentAccountGeneration(accountGenerationAtStart)) {
        _isSyncing = false;
        _notifySyncStateChanged();
        return;
      }
      await _runAccountBoundWriteback(accountGenerationAtStart, () async {
        final applyResult = await _applySyncResponse(
          prefs!,
          response,
          accountGenerationAtStart: accountGenerationAtStart,
          localChangeGenerationAtStart: syncGeneration,
          requestCollectionHashes: localHashes,
          requestLocalSnapshots: prepared.snapshots,
          fallbackDeletedItems:
              payload['deleted_items'] as Map<String, Map<String, String>>,
        );

        final now = DateTime.now();
        _config = SyncConfig(lastSync: now, autoSync: _config.autoSync);
        await _guardAccountGeneration(
          accountGenerationAtStart,
          () => prefs!.setString('sync_last_time', now.toIso8601String()),
        );
        await _guardAccountGeneration(
          accountGenerationAtStart,
          () => _setPendingChanges(
            prefs!,
            _localChangeGeneration != syncGeneration ||
                applyResult.hasSkippedLocalChanges,
          ),
        );

        if (applyResult.changedCollections.isNotEmpty) {
          _throwIfAccountGenerationChanged(accountGenerationAtStart);
          await onSynced?.call(applyResult.changedCollections);
          _throwIfAccountGenerationChanged(accountGenerationAtStart);
        }
      });
    } on _SyncCancelled {
      _isSyncing = false;
      _notifySyncStateChanged();
      return;
    } catch (e) {
      if (!_isCurrentAccountGeneration(accountGenerationAtStart)) {
        _isSyncing = false;
        _notifySyncStateChanged();
        return;
      }
      _lastError = _userVisibleSyncError(e);
      if (shouldRetryLocalChanges) {
        _hasPendingChanges = true;
        final localPrefs = prefs;
        if (localPrefs == null) {
          unawaited(_persistPendingChanges(true));
        } else {
          await _writePendingChanges(localPrefs, true);
        }
      }
    }

    _isSyncing = false;
    if (!_isCurrentAccountGeneration(accountGenerationAtStart)) {
      _notifySyncStateChanged();
      return;
    }
    if (_lastError != null && _hasPendingChanges) {
      _scheduleAutoSync(_autoRetryDelay);
    } else if (_lastError == null && _hasPendingChanges) {
      _scheduleAutoSync();
    } else if (_lastError == null && !_hasPendingChanges) {
      _scheduleRemotePoll();
    }
    _notifySyncStateChanged();
    _scheduleQueuedSyncIfNeeded();
  }

  Future<void> _pullRemoteChanges({int? expectedAccountGeneration}) async {
    if (_syncSuspendedForAccountChange) return;
    final accountGenerationAtStart =
        expectedAccountGeneration ?? _accountGeneration;
    if (!_isCurrentAccountGeneration(accountGenerationAtStart)) return;
    if (_isSyncing) {
      _syncQueued = true;
      return;
    }
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      return;
    }
    if (serverConfigGetter != null) {
      final cfg = serverConfigGetter!.call();
      if (cfg != null && cfg['backup_enabled'] == false) {
        _lastError = '管理员已关闭云端备份';
        _notifySyncStateChanged();
        return;
      }
    }

    _isSyncing = true;
    _lastError = null;
    _notifySyncStateChanged();

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_isCurrentAccountGeneration(accountGenerationAtStart)) {
        _isSyncing = false;
        _notifySyncStateChanged();
        return;
      }
      final syncGeneration = _localChangeGeneration;
      final prepared = await _buildLocalSyncPayload(prefs);
      final localHashes = prepared.collections;
      final response = await client.post('/api/sync/pull', {
        'collection_hashes': localHashes,
      });
      if (!_isCurrentAccountGeneration(accountGenerationAtStart)) {
        _isSyncing = false;
        _notifySyncStateChanged();
        return;
      }
      await _runAccountBoundWriteback(accountGenerationAtStart, () async {
        final applyResult = await _applySyncResponse(
          prefs,
          response,
          accountGenerationAtStart: accountGenerationAtStart,
          localChangeGenerationAtStart: syncGeneration,
          requestCollectionHashes: localHashes,
          requestLocalSnapshots: prepared.snapshots,
          fallbackDeletedItems:
              prepared.payload['deleted_items']
                  as Map<String, Map<String, String>>,
        );
        final now = DateTime.now();
        _config = SyncConfig(lastSync: now, autoSync: _config.autoSync);
        await _guardAccountGeneration(
          accountGenerationAtStart,
          () => prefs.setString('sync_last_time', now.toIso8601String()),
        );
        await _guardAccountGeneration(
          accountGenerationAtStart,
          () => _setPendingChanges(
            prefs,
            _localChangeGeneration != syncGeneration ||
                applyResult.hasSkippedLocalChanges,
          ),
        );
        if (applyResult.changedCollections.isNotEmpty) {
          _throwIfAccountGenerationChanged(accountGenerationAtStart);
          await onSynced?.call(applyResult.changedCollections);
          _throwIfAccountGenerationChanged(accountGenerationAtStart);
        }
      });
    } on _SyncCancelled {
      _isSyncing = false;
      _notifySyncStateChanged();
      return;
    } catch (e) {
      if (!_isCurrentAccountGeneration(accountGenerationAtStart)) {
        _isSyncing = false;
        _notifySyncStateChanged();
        return;
      }
      _lastError = _userVisibleSyncError(e);
    }

    _isSyncing = false;
    if (!_isCurrentAccountGeneration(accountGenerationAtStart)) {
      _notifySyncStateChanged();
      return;
    }
    if (_lastError == null && !_hasPendingChanges) {
      _scheduleRemotePoll();
    } else if (_lastError == null && _hasPendingChanges) {
      _scheduleAutoSync();
    } else if (_lastError != null) {
      _scheduleRemotePoll(_autoRetryDelay);
    }
    _notifySyncStateChanged();
    _scheduleQueuedSyncIfNeeded();
  }

  /// 构建本地同步负载，并顺带产出集合/条目哈希。
  ///
  /// 大的字符串编码集合（todos 等可达数 MB）的 JSON 解码 + 全量哈希合并为
  /// **单次**后台 isolate 往返，并按集合做解码缓存：原始存储内容不变的集合
  /// 直接复用上一次的解码结果与哈希（apply 末尾的重建因此几乎零成本）。
  ///
  /// 共享实例约定：缓存与负载中的 decoded 列表/映射在整个同步流程中只读
  /// （下游仅做序列化、过滤拷贝与逐项哈希），任何使用方不得原地修改。
  Future<
    ({
      Map<String, dynamic> payload,
      Map<String, String> collections,
      Map<String, Map<String, String>> items,
      Map<String, Object?> snapshots,
    })
  >
  _buildLocalSyncPayload(SharedPreferences prefs) async {
    final payload = <String, dynamic>{};
    // 请求时刻各集合的原始存储快照：apply 阶段用它做“本地是否在请求后
    // 又被写入”的守卫（字符串等值比较即可判定）。
    final snapshots = <String, Object?>{};
    final collectionsHash = <String, String>{};
    final itemHashes = <String, Map<String, String>>{};
    final isolateMisses = <String, String>{};
    var allListCollectionsCached = true;
    for (final entry in _listPayloads.entries) {
      final localKey = entry.key;
      final remoteKey = entry.value;
      if (_stringEncodedListKeys.contains(localKey)) {
        final raw = prefs.getString(localKey) ?? '';
        snapshots[localKey] = raw;
        final cached = _decodedCollectionCache[localKey];
        if (cached != null && cached.raw == raw) {
          payload[remoteKey] = cached.decoded;
          collectionsHash[remoteKey] = cached.collectionHash;
          final bucket = cached.itemBucket;
          if (bucket != null) itemHashes[remoteKey] = bucket;
          continue;
        }
        allListCollectionsCached = false;
        if (raw.length >= _isolateDecodeMinChars) {
          isolateMisses[localKey] = raw;
          continue;
        }
        final decoded = _decodeStringEncodedList(raw);
        _storeCollectionCache(
          localKey: localKey,
          remoteKey: remoteKey,
          raw: raw,
          decoded: decoded,
          collectionsHash: collectionsHash,
          itemHashes: itemHashes,
        );
        payload[remoteKey] = decoded;
      } else {
        final raw = prefs.getStringList(localKey) ?? const <String>[];
        snapshots[localKey] = List<String>.unmodifiable(raw);
        final cached = _decodedCollectionCache[localKey];
        if (cached != null &&
            cached.raw is List<String> &&
            _stringListEquals(cached.raw as List<String>, raw)) {
          payload[remoteKey] = cached.decoded;
          collectionsHash[remoteKey] = cached.collectionHash;
          final bucket = cached.itemBucket;
          if (bucket != null) itemHashes[remoteKey] = bucket;
          continue;
        }
        allListCollectionsCached = false;
        final decoded = raw
            .map((e) {
              try {
                return json.decode(e);
              } catch (_) {
                return null;
              }
            })
            .where((e) => e != null)
            .toList();
        _storeCollectionCache(
          localKey: localKey,
          remoteKey: remoteKey,
          raw: raw,
          decoded: decoded,
          collectionsHash: collectionsHash,
          itemHashes: itemHashes,
        );
        payload[remoteKey] = decoded;
      }
    }

    for (final entry in _objectPayloads.entries) {
      final localKey = entry.key;
      final remoteKey = entry.value;
      final raw = prefs.getString(localKey) ?? '';
      snapshots[localKey] = raw;
      final cached = _decodedCollectionCache[localKey];
      if (cached != null && cached.raw == raw) {
        payload[remoteKey] = cached.decoded;
        collectionsHash[remoteKey] = cached.collectionHash;
        final bucket = cached.itemBucket;
        if (bucket != null) itemHashes[remoteKey] = bucket;
        continue;
      }
      final decoded = _decodeStringEncodedObject(raw);
      _storeCollectionCache(
        localKey: localKey,
        remoteKey: remoteKey,
        raw: raw,
        decoded: decoded,
        collectionsHash: collectionsHash,
        itemHashes: itemHashes,
      );
      payload[remoteKey] = decoded;
    }

    if (isolateMisses.isNotEmpty) {
      final result = await compute(
        _decodeCollectionsForIsolate,
        Map<String, String>.of(isolateMisses),
      );
      for (final entry in result.entries) {
        final localKey = entry.key;
        final remoteKey = _listPayloads[localKey]!;
        final decoded = (entry.value as Map)['decoded'] as List<dynamic>;
        final collectionHash = (entry.value as Map)['collectionHash'] as String;
        final bucketResult = (entry.value as Map)['itemBucket'];
        final itemBucket = bucketResult == null
            ? null
            : Map<String, String>.from(bucketResult as Map);
        _decodedCollectionCache[localKey] = _DecodedCollection(
          raw: isolateMisses[localKey]!,
          decoded: decoded,
          collectionHash: collectionHash,
          itemBucket: itemBucket,
        );
        payload[remoteKey] = decoded;
        collectionsHash[remoteKey] = collectionHash;
        if (itemBucket != null) itemHashes[remoteKey] = itemBucket;
      }
    }

    payload['preferences'] = _buildPreferencesPayload(prefs);
    collectionsHash['preferences'] = _collectionHashForKey(
      'preferences',
      payload['preferences'],
    );
    _fillItemHashBucket(itemHashes, 'preferences', payload['preferences']);
    payload['quick_capture_templates'] = _buildQuickCaptureTemplatesPayload(
      prefs,
    );
    collectionsHash['quick_capture_templates'] = _collectionHashForKey(
      'quick_capture_templates',
      payload['quick_capture_templates'],
    );
    _fillItemHashBucket(
      itemHashes,
      'quick_capture_templates',
      payload['quick_capture_templates'],
    );
    payload['list_groups'] = _buildListGroupsPayload(prefs);
    collectionsHash['list_groups'] = _collectionHashForKey(
      'list_groups',
      payload['list_groups'],
    );
    _fillItemHashBucket(itemHashes, 'list_groups', payload['list_groups']);
    payload['deleted_items'] = _decodeDeletedItems(
      prefs.getString(deletedItemsStorageKey),
    );
    collectionsHash['deleted_items'] = _collectionHashForKey(
      'deleted_items',
      payload['deleted_items'],
    );

    // workspace_payloads 仅由列表集合派生：全部列表命中缓存时内容与上次
    // 一致，可整体复用缓存，省掉对共享条目的再次全量哈希。
    final cachedWorkspaceHash = _workspaceCollectionHashCache;
    if (allListCollectionsCached && cachedWorkspaceHash != null) {
      payload['workspace_payloads'] = _workspacePayloadsCache;
      collectionsHash['workspace_payloads'] = cachedWorkspaceHash;
    } else {
      final workspacePayloads = _buildWorkspacePayloads(payload);
      payload['workspace_payloads'] = workspacePayloads;
      final workspaceHash = _collectionHashForKey(
        'workspace_payloads',
        workspacePayloads,
      );
      _workspacePayloadsCache = workspacePayloads;
      _workspaceCollectionHashCache = workspaceHash;
      collectionsHash['workspace_payloads'] = workspaceHash;
    }

    return (
      payload: payload,
      collections: collectionsHash,
      items: itemHashes,
      snapshots: snapshots,
    );
  }

  /// 后台 isolate 的批量解码入口（`compute` 需要静态函数）：
  /// localKey → 原始存储字符串，返回各集合的解码结果与哈希。
  static Map<String, dynamic> _decodeCollectionsForIsolate(
    Map<String, String> misses,
  ) {
    final out = <String, dynamic>{};
    misses.forEach((localKey, raw) {
      final remoteKey = _listPayloads[localKey]!;
      final decoded = _decodeStringEncodedList(raw);
      out[localKey] = {
        'decoded': decoded,
        'collectionHash': _collectionHashForKey(remoteKey, decoded),
        'itemBucket': _itemHashBucketForKey(remoteKey, decoded),
      };
    });
    return out;
  }

  static List<dynamic> _decodeStringEncodedList(String raw) {
    try {
      final decoded = json.decode(raw);
      return decoded is List ? decoded : const <dynamic>[];
    } catch (_) {
      return const <dynamic>[];
    }
  }

  static Map<String, dynamic> _decodeStringEncodedObject(String raw) {
    try {
      final decoded = json.decode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  void _storeCollectionCache({
    required String localKey,
    required String remoteKey,
    required Object? raw,
    required Object? decoded,
    required Map<String, String> collectionsHash,
    required Map<String, Map<String, String>> itemHashes,
  }) {
    final collectionHash = _collectionHashForKey(remoteKey, decoded);
    final itemBucket = _itemHashBucketForKey(remoteKey, decoded);
    _decodedCollectionCache[localKey] = _DecodedCollection(
      raw: raw,
      decoded: decoded,
      collectionHash: collectionHash,
      itemBucket: itemBucket,
    );
    collectionsHash[remoteKey] = collectionHash;
    if (itemBucket != null) itemHashes[remoteKey] = itemBucket;
  }

  /// 单集合的 canonicalize + SHA-256 哈希（等价于旧全量构建里的逐键计算）。
  static String _collectionHashForKey(String remoteKey, Object? value) {
    return _syncPayloadHash(_hashableCollectionValue(remoteKey, value));
  }

  /// 单集合的条目哈希桶；不属于条目增量集合时返回 null。
  static Map<String, String>? _itemHashBucketForKey(
    String remoteKey,
    Object? value,
  ) {
    if (_itemDeltaCollections.contains(remoteKey) && value is List) {
      final bucket = <String, String>{};
      for (final item in value) {
        if (item is! Map || item['id'] == null) continue;
        final id = item['id'].toString();
        if (id.isEmpty) continue;
        bucket[id] = _syncPayloadHash(item);
      }
      return bucket;
    }
    if (_objectDeltaCollections.contains(remoteKey)) {
      return {
        '_': _syncPayloadHash(_hashableCollectionValue(remoteKey, value)),
      };
    }
    return null;
  }

  void _fillItemHashBucket(
    Map<String, Map<String, String>> itemHashes,
    String remoteKey,
    Object? value,
  ) {
    final bucket = _itemHashBucketForKey(remoteKey, value);
    if (bucket != null) itemHashes[remoteKey] = bucket;
  }

  Map<String, dynamic> _buildPreferencesPayload(SharedPreferences prefs) {
    final values = _readPreferenceValues(prefs);
    final changedKeys = _readPendingPreferenceChangedKeys(prefs);
    return {
      'updatedAt':
          _pendingPreferencesUpdatedAt ??
          prefs.getString(_preferencesUpdatedAtStorageKey) ??
          '',
      'values': values,
      if (changedKeys.isNotEmpty) 'changedKeys': changedKeys,
    };
  }

  Map<String, dynamic> _readPreferenceValues(SharedPreferences prefs) {
    final values = <String, dynamic>{};
    for (final key in _preferenceBoolKeys) {
      if (prefs.containsKey(key)) values[key] = prefs.getBool(key);
    }
    for (final key in _preferenceIntKeys) {
      if (prefs.containsKey(key)) values[key] = prefs.getInt(key);
    }
    for (final key in _preferenceStringKeys) {
      if (prefs.containsKey(key)) values[key] = prefs.getString(key);
    }
    for (final key in _preferenceStringListKeys) {
      if (prefs.containsKey(key)) values[key] = prefs.getStringList(key);
    }
    return values;
  }

  List<String> _readPendingPreferenceChangedKeys(SharedPreferences prefs) {
    final stored = prefs.getStringList(_preferencesChangedKeysStorageKey);
    if (_pendingPreferencesFullSync ||
        (stored?.contains(_preferencesFullSyncSentinel) ?? false)) {
      return const <String>[];
    }
    final keys = <String>{
      ..._pendingPreferenceKeys,
      ..._normalizePreferenceChangedKeys(stored),
    }.toList()..sort();
    return keys;
  }

  Set<String> _normalizePreferenceChangedKeys(Iterable<String>? keys) {
    if (keys == null) return <String>{};
    return keys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty && key != _preferencesFullSyncSentinel)
        .where(_preferenceKeys.contains)
        .toSet();
  }

  Map<String, dynamic> _buildQuickCaptureTemplatesPayload(
    SharedPreferences prefs,
  ) {
    final raw = prefs.getString(_quickCaptureTemplatesStorageKey);
    var items = <dynamic>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw);
        if (decoded is List) items = decoded;
      } catch (_) {
        items = <dynamic>[];
      }
    }
    return {
      'updatedAt':
          _pendingQuickCaptureTemplatesUpdatedAt ??
          prefs.getString(_quickCaptureTemplatesUpdatedAtStorageKey) ??
          '',
      'items': items,
    };
  }

  List<Map<String, dynamic>> _buildListGroupsPayload(SharedPreferences prefs) =>
      ListGroupProvider.decodeStoredGroups(
        prefs.getString(ListGroupProvider.storageKey),
      ).map((group) => group.toJson()).toList();

  Future<bool> _writeListGroupsPayload(
    SharedPreferences prefs,
    List<dynamic> payload,
  ) async {
    // Each record carries its own updatedAt, including isDeleted tombstones.
    // Merge against current storage so edits made during the request survive.
    final remote = ListGroupProvider.decodeGroups(payload);
    final merged = ListGroupProvider.mergeGroups(
      ListGroupProvider.decodeStoredGroups(
        prefs.getString(ListGroupProvider.storageKey),
      ),
      remote,
    );
    final items = merged.map((group) => group.toJson()).toList();
    final encoded = json.encode(items);
    if (prefs.getString(ListGroupProvider.storageKey) != encoded) {
      await prefs.setString(ListGroupProvider.storageKey, encoded);
    }
    return _syncPayloadHash(items) !=
        _syncPayloadHash(remote.map((group) => group.toJson()).toList());
  }

  /// 存储字符串总量超过该长度时，负载构建与哈希移入后台 isolate
  /// （todos 等可达数 MB；小负载走主线程避免 isolate 往返开销）。
  static const int _isolateDecodeMinChars = 60000;

  static Object? _hashableCollectionValue(String key, Object? value) {
    if (key == 'preferences' && value is Map) {
      final normalized = Map<String, dynamic>.from(value);
      normalized.remove('changedKeys');
      normalized.remove('changed_keys');
      return normalized;
    }
    return value;
  }

  Map<String, dynamic>? _buildSyncItemDelta(
    Map<String, dynamic> payload,
    Map<String, Map<String, String>> localItemHashes,
  ) {
    final hasBaseline = _itemDeltaCollections.every(
      _lastItemHashes.containsKey,
    );
    if (!hasBaseline) return null;

    final items = <String, List<dynamic>>{};
    final objects = <String, dynamic>{};
    final deletedItems = _decodeDeletedItems(
      json.encode(payload['deleted_items']),
    );

    for (final key in _itemDeltaCollections) {
      final baseline = _lastItemHashes[key] ?? const <String, String>{};
      final current = localItemHashes[key] ?? const <String, String>{};
      final list = payload[key];
      if (list is List) {
        final changed = <dynamic>[];
        for (final item in list) {
          if (item is! Map || item['id'] == null) continue;
          final id = item['id'].toString();
          if (baseline[id] != current[id]) {
            changed.add(item);
          }
        }
        if (changed.isNotEmpty) items[key] = changed;
      }
    }

    for (final key in _objectDeltaCollections) {
      final baselineHash = _lastItemHashes[key]?['_'];
      final currentHash = localItemHashes[key]?['_'];
      if (baselineHash != currentHash) {
        objects[key] = payload[key];
      }
    }

    if (items.isEmpty && objects.isEmpty && deletedItems.isEmpty) {
      return const <String, dynamic>{};
    }
    return {'items': items, 'objects': objects, 'deleted_items': deletedItems};
  }

  Map<String, dynamic>? _changedSyncCollections(
    Map<String, dynamic> payload,
    Map<String, String> localHashes,
  ) {
    final hasBaseline = _syncPullCollections.every(
      _lastCollectionHashes.containsKey,
    );
    if (!hasBaseline) return null;
    final changed = <String, dynamic>{};
    for (final key in _syncPullCollections) {
      if (_lastCollectionHashes[key] != localHashes[key]) {
        changed[key] = payload[key];
      }
    }
    return changed;
  }

  static String _syncPayloadHash(Object? value) {
    return sha256
        .convert(utf8.encode(json.encode(_canonicalize(value))))
        .toString();
  }

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final sorted = SplayTreeMap<String, Object?>();
      for (final entry in value.entries) {
        sorted[entry.key.toString()] = _canonicalize(entry.value);
      }
      return sorted;
    }
    if (value is Iterable) {
      return value.map(_canonicalize).toList(growable: false);
    }
    return value;
  }

  Future<_SyncApplyResult> _applySyncResponse(
    SharedPreferences prefs,
    Map<String, dynamic> response, {
    required int accountGenerationAtStart,
    required int localChangeGenerationAtStart,
    required Map<String, String> requestCollectionHashes,
    required Map<String, Object?> requestLocalSnapshots,
    required Map<String, Map<String, String>> fallbackDeletedItems,
  }) async {
    void throwIfAccountChanged() {
      if (!_isCurrentAccountGeneration(accountGenerationAtStart)) {
        throw const _SyncCancelled();
      }
    }

    throwIfAccountChanged();
    // 请求发出后本地是否有新改动：用本地变更生成数判定。
    // 之前在这里全量重建负载并比对哈希，2000 条待办时一次就要在主线程
    // 解码数 MB 的存储；所有同步集合的写入都会经过 markPendingLocalChange
    // 递增生成数，判定结果只会更保守（误判为有改动最多多同步一轮）。
    final localChangedBeforeApply =
        _localChangeGeneration != localChangeGenerationAtStart;
    final skippedCollections = <String>{};

    final responseDeletedItems = response['deleted_items'];
    var mergedDeletedItems = fallbackDeletedItems;
    if (responseDeletedItems is Map) {
      final remoteDeletedItems = _decodeDeletedItems(
        json.encode(responseDeletedItems),
      );
      final currentDeletedItems = _decodeDeletedItems(
        prefs.getString(deletedItemsStorageKey),
      );
      final expectedDeletedHash = requestCollectionHashes['deleted_items'];
      mergedDeletedItems =
          expectedDeletedHash != null &&
              _syncPayloadHash(currentDeletedItems) != expectedDeletedHash
          ? _mergeDeletedItemMaps(remoteDeletedItems, currentDeletedItems)
          : remoteDeletedItems;
      if (_syncPayloadHash(currentDeletedItems) !=
          _syncPayloadHash(mergedDeletedItems)) {
        throwIfAccountChanged();
        await prefs.setString(
          deletedItemsStorageKey,
          json.encode(mergedDeletedItems),
        );
        throwIfAccountChanged();
      }
    }

    for (final entry in _listPayloads.entries) {
      throwIfAccountChanged();
      final remoteKey = entry.value;
      final localKey = entry.key;
      final value = response[remoteKey];
      if (value is! List) continue;
      final filteredValue = _filterDeletedRemoteList(
        collection: remoteKey,
        items: value,
        deletedItems: mergedDeletedItems,
      );
      if (!_collectionStillMatchesRequest(
        prefs,
        localKey,
        remoteKey,
        requestLocalSnapshots,
      )) {
        skippedCollections.add(remoteKey);
        continue;
      }
      await _writeLocalList(prefs, localKey, filteredValue);
      throwIfAccountChanged();
    }
    for (final entry in _objectPayloads.entries) {
      throwIfAccountChanged();
      final remoteKey = entry.value;
      final localKey = entry.key;
      final value = response[remoteKey];
      if (value is! Map) continue;
      if (!_collectionStillMatchesRequest(
        prefs,
        localKey,
        remoteKey,
        requestLocalSnapshots,
      )) {
        skippedCollections.add(remoteKey);
        continue;
      }
      if (_remoteObjectIsOlderThanLocal(prefs, localKey, value)) {
        skippedCollections.add(remoteKey);
        debugPrint(
          '[CloudSync] skipped stale object $remoteKey remote='
          '${_remoteItemUpdatedAt(value)} local='
          '${_remoteItemUpdatedAt(_readLocalObject(prefs, localKey))}',
        );
        continue;
      }
      await _writeLocalObject(prefs, localKey, value);
      throwIfAccountChanged();
    }
    final preferences = response['preferences'];
    if (preferences is Map) {
      throwIfAccountChanged();
      final current = _buildPreferencesPayload(prefs);
      if (!_customCollectionStillMatchesRequest(
        current,
        'preferences',
        requestCollectionHashes,
      )) {
        skippedCollections.add('preferences');
      } else if (_remotePreferencesAreOlderThanLocal(
        prefs,
        Map<String, dynamic>.from(preferences),
      )) {
        skippedCollections.add('preferences');
        debugPrint('[CloudSync] skipped stale preferences payload');
      } else {
        await _writePreferencesPayload(prefs, preferences);
        throwIfAccountChanged();
      }
    }
    final quickCaptureTemplates = response['quick_capture_templates'];
    if (quickCaptureTemplates is Map) {
      throwIfAccountChanged();
      final current = _buildQuickCaptureTemplatesPayload(prefs);
      if (!_customCollectionStillMatchesRequest(
        current,
        'quick_capture_templates',
        requestCollectionHashes,
      )) {
        skippedCollections.add('quick_capture_templates');
      } else if (_remoteQuickCaptureTemplatesAreOlderThanLocal(
        prefs,
        Map<String, dynamic>.from(quickCaptureTemplates),
      )) {
        skippedCollections.add('quick_capture_templates');
        debugPrint('[CloudSync] skipped stale quick capture templates payload');
      } else {
        await _writeQuickCaptureTemplatesPayload(prefs, quickCaptureTemplates);
        throwIfAccountChanged();
      }
    }
    final listGroups = response['list_groups'];
    if (listGroups is List) {
      throwIfAccountChanged();
      final hasNewerLocalGroups = await _writeListGroupsPayload(
        prefs,
        listGroups,
      );
      throwIfAccountChanged();
      if (hasNewerLocalGroups) skippedCollections.add('list_groups');
    }

    final workspacePayloads = response['workspace_payloads'];
    if (workspacePayloads is Map) {
      throwIfAccountChanged();
      _lastWorkspaceMergeDecisions = await _mergeWorkspacePayloads(
        prefs,
        workspacePayloads,
        requestLocalSnapshots,
        skippedCollections,
      );
      await prefs.setStringList(
        'sync_merge_decisions',
        _lastWorkspaceMergeDecisions
            .take(50)
            .map((decision) => json.encode(decision.toJson()))
            .toList(),
      );
      throwIfAccountChanged();
    }
    throwIfAccountChanged();
    final nextPrepared = await _buildLocalSyncPayload(prefs);
    final nextPayload = nextPrepared.payload;
    final nextHashes = nextPrepared.collections;
    // 与请求时刻的哈希基准对比：本轮应用（或并发的本地写入）造成
    // 内容变化的集合，需要通知 onSynced 重新加载对应 Provider。
    final changedCollections = {
      for (final key in _syncPullCollections)
        if (requestCollectionHashes[key] != nextHashes[key]) key,
    };
    if (!localChangedBeforeApply && skippedCollections.isEmpty) {
      throwIfAccountChanged();
      await _persistServerRevision(prefs, response);
      throwIfAccountChanged();
      await _persistPreferencesSnapshot(prefs, nextPayload['preferences']);
      throwIfAccountChanged();
      _lastItemHashes = nextPrepared.items;
      await prefs.setString(
        _itemHashesStorageKey,
        json.encode(_lastItemHashes),
      );
      throwIfAccountChanged();
    }
    return _SyncApplyResult(
      changedCollections: changedCollections,
      skippedCollections: skippedCollections,
      localChangedBeforeApply: localChangedBeforeApply,
    );
  }

  bool _customCollectionStillMatchesRequest(
    Object? currentValue,
    String remoteKey,
    Map<String, String> requestCollectionHashes,
  ) {
    final expectedHash = requestCollectionHashes[remoteKey];
    if (expectedHash == null || expectedHash.isEmpty) return true;
    return _syncPayloadHash(
          _hashableCollectionValue(remoteKey, currentValue),
        ) ==
        expectedHash;
  }

  /// 请求后的本地内容守卫：比较当前原始存储与请求时刻的快照。
  /// 字符串/列表等值比较远快于旧方案的全量解码 + canonicalize + SHA-256。
  bool _collectionStillMatchesRequest(
    SharedPreferences prefs,
    String localKey,
    String remoteKey,
    Map<String, Object?> requestLocalSnapshots,
  ) {
    final snapshot = requestLocalSnapshots[localKey];
    if (snapshot == null) return true;
    if (snapshot is String) {
      return (prefs.getString(localKey) ?? '') == snapshot;
    }
    if (snapshot is List<String>) {
      return _stringListEquals(
        prefs.getStringList(localKey) ?? const <String>[],
        snapshot,
      );
    }
    return true;
  }

  static bool _stringListEquals(List<String>? left, List<String> right) {
    if (left == null || left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  Future<void> _persistServerRevision(
    SharedPreferences prefs,
    Map<String, dynamic> response,
  ) async {
    final serverUpdatedAt = response['server_updated_at']?.toString() ?? '';
    final serverVersion = (response['server_version'] as num?)?.toInt();
    if (serverUpdatedAt.isNotEmpty) {
      _lastServerUpdatedAt = serverUpdatedAt;
      await prefs.setString(_serverUpdatedAtStorageKey, serverUpdatedAt);
    }
    if (serverVersion != null) {
      _lastServerVersion = serverVersion;
      await prefs.setInt(_serverVersionStorageKey, serverVersion);
    }
    final collectionHashes = response['collection_hashes'];
    if (collectionHashes is Map) {
      _lastCollectionHashes = _decodeCollectionHashes(
        json.encode(collectionHashes),
      );
      await prefs.setString(
        _collectionHashesStorageKey,
        json.encode(_lastCollectionHashes),
      );
    }
  }

  static Map<String, String> _decodeCollectionHashes(String? raw) {
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return <String, String>{};
      return {
        for (final entry in decoded.entries)
          if (entry.value != null) entry.key.toString(): entry.value.toString(),
      };
    } catch (_) {
      return <String, String>{};
    }
  }

  static Map<String, Map<String, String>> _decodeItemHashes(String? raw) {
    if (raw == null || raw.isEmpty) return <String, Map<String, String>>{};
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return <String, Map<String, String>>{};
      final result = <String, Map<String, String>>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        result[entry.key.toString()] = {
          for (final item in value.entries)
            if (item.value != null) item.key.toString(): item.value.toString(),
        };
      }
      return result;
    } catch (_) {
      return <String, Map<String, String>>{};
    }
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _remotePollTimer?.cancel();
    _remoteEventRetryTimer?.cancel();
    _remoteEventSubscription?.cancel();
    super.dispose();
  }

  static Map<String, dynamic> _buildWorkspacePayloads(
    Map<String, dynamic> payload,
  ) {
    final result = <String, dynamic>{};
    for (final collection in _workspacePayloadCollections.keys) {
      final list = payload[collection];
      if (list is! List) continue;
      for (final item in list) {
        if (item is! Map) continue;
        final workspaceId = _sharedWorkspaceId(item);
        if (workspaceId == null) continue;
        final bucket = _workspaceBucket(result, workspaceId);
        (bucket[collection] as List).add(item);
      }
    }
    return result;
  }

  Future<List<SyncMergeDecision>> _mergeWorkspacePayloads(
    SharedPreferences prefs,
    Map<dynamic, dynamic> payloads,
    Map<String, Object?> requestLocalSnapshots,
    Set<String> skippedCollections,
  ) async {
    final decisions = <SyncMergeDecision>[];
    final remoteByCollection = <String, List<Map<String, dynamic>>>{};
    final remoteWorkspaceIdsByCollection = <String, Map<String, String>>{};
    for (final collection in _workspacePayloadCollections.keys) {
      remoteByCollection[collection] = <Map<String, dynamic>>[];
      remoteWorkspaceIdsByCollection[collection] = <String, String>{};
    }

    for (final entry in payloads.entries) {
      final workspaceId = entry.key.toString();
      final payload = entry.value;
      if (payload is! Map) continue;
      for (final collection in _workspacePayloadCollections.keys) {
        final list = payload[collection];
        if (list is! List) continue;
        for (final item in list) {
          if (item is Map && item['id'] != null) {
            final normalized = Map<String, dynamic>.from(item);
            final itemWorkspaceId = normalized['workspaceId']?.toString();
            if (itemWorkspaceId == null ||
                itemWorkspaceId.isEmpty ||
                itemWorkspaceId == 'private') {
              normalized['workspaceId'] = workspaceId;
            }
            final id = normalized['id'].toString();
            remoteWorkspaceIdsByCollection[collection]![id] = workspaceId;
            remoteByCollection[collection]!.add(normalized);
          }
        }
      }
    }

    for (final entry in _workspacePayloadCollections.entries) {
      final collection = entry.key;
      final spec = entry.value;
      final remoteItems = remoteByCollection[collection]!;
      if (remoteItems.isEmpty) continue;
      if (!_collectionStillMatchesRequest(
        prefs,
        spec.localKey,
        collection,
        requestLocalSnapshots,
      )) {
        skippedCollections.add('workspace_payloads');
        continue;
      }
      final merge = _mergeRemoteWorkspaceItems(
        current: _currentDecodedList(prefs, spec.localKey),
        remote: remoteItems,
        remoteWorkspaceIds: remoteWorkspaceIdsByCollection[collection]!,
        itemType: spec.itemType,
      );
      await _writeLocalList(prefs, spec.localKey, merge.items);
      decisions.addAll(merge.decisions);
    }

    return decisions;
  }

  /// 缓存感知的当前列表读取：原始内容与解码缓存一致时直接复用解码结果，
  /// 避免 workspace 合并阶段对大集合的重复全量解码；未命中时一次性解码。
  List<dynamic> _currentDecodedList(SharedPreferences prefs, String localKey) {
    if (_stringEncodedListKeys.contains(localKey)) {
      final raw = prefs.getString(localKey) ?? '';
      final cached = _decodedCollectionCache[localKey];
      if (cached != null && cached.raw == raw && cached.decoded is List) {
        return cached.decoded as List<dynamic>;
      }
    }
    return _readLocalList(prefs, localKey);
  }

  List<dynamic> _readLocalList(SharedPreferences prefs, String localKey) {
    if (_stringEncodedListKeys.contains(localKey)) {
      final currentRaw = prefs.getString(localKey);
      if (currentRaw == null || currentRaw.isEmpty) return <dynamic>[];
      try {
        final decoded = json.decode(currentRaw);
        return decoded is List ? decoded : <dynamic>[];
      } catch (_) {
        return <dynamic>[];
      }
    }
    return (prefs.getStringList(localKey) ?? const <String>[])
        .map((raw) {
          try {
            return json.decode(raw);
          } catch (_) {
            return null;
          }
        })
        .where((item) => item != null)
        .toList();
  }

  Future<void> _writeLocalList(
    SharedPreferences prefs,
    String localKey,
    Iterable<dynamic> items,
  ) async {
    final list = items.toList(growable: false);
    if (_stringEncodedListKeys.contains(localKey)) {
      final currentRaw = prefs.getString(localKey);
      var encoded = '';
      var identicalContent = false;
      String? collectionHash;
      Map<String, String>? itemBucket;
      if (currentRaw != null && currentRaw.length >= _isolateDecodeMinChars) {
        // 大内容的 no-op 判定与编码（解码 + 双向哈希 + 编码 ≈ 150ms）
        // 一并移入后台 isolate，避免同步应用阶段阻塞主线程。
        final remoteKey = _listPayloads[localKey]!;
        final result = await compute(_encodeAndCompareForIsolate, {
          'raw': currentRaw,
          'items': list,
          'remoteKey': remoteKey,
        });
        identicalContent = result['identical'] == true;
        encoded = result['encoded'] as String;
        collectionHash = result['collectionHash'] as String;
        final bucketResult = result['itemBucket'];
        itemBucket = bucketResult == null
            ? null
            : Map<String, String>.from(bucketResult as Map);
      } else {
        encoded = json.encode(list);
        if (_syncPayloadHash(_readLocalList(prefs, localKey)) ==
            _syncPayloadHash(list)) {
          identicalContent = true;
        }
        final remoteKey = _listPayloads[localKey]!;
        collectionHash = _collectionHashForKey(remoteKey, list);
        itemBucket = _itemHashBucketForKey(remoteKey, list);
      }
      if (identicalContent &&
          _decodedCollectionCache[localKey]?.raw == currentRaw) {
        // 缓存已与存储一致，无需预热。
        return;
      }
      await prefs.setString(localKey, encoded);
      _decodedCollectionCache[localKey] = _DecodedCollection(
        raw: encoded,
        decoded: list,
        collectionHash: collectionHash,
        itemBucket: itemBucket,
      );
      return;
    }
    final encodedItems = list
        .map((item) => json.encode(item))
        .toList(growable: false);
    final currentRawList = prefs.getStringList(localKey);
    if (_stringListEquals(currentRawList, encodedItems)) {
      return;
    }
    await prefs.setStringList(localKey, encodedItems);
    final remoteKey = _listPayloads[localKey]!;
    _decodedCollectionCache[localKey] = _DecodedCollection(
      raw: List<String>.unmodifiable(encodedItems),
      decoded: list,
      collectionHash: _collectionHashForKey(remoteKey, list),
      itemBucket: _itemHashBucketForKey(remoteKey, list),
    );
  }

  /// 后台 isolate 的大内容写入辅助：同时完成 no-op 判定（原始存储解码后
  /// 与目标列表哈希比较）与目标列表编码，返回编码结果与哈希供主线程
  /// 预热解码缓存（`compute` 需要静态函数）。原始存储损坏时视为内容不同，
  /// 让调用方走写入路径修复。
  static Map<String, dynamic> _encodeAndCompareForIsolate(
    Map<Object?, Object?> args,
  ) {
    final raw = args['raw'] as String;
    final items = args['items'] as List;
    final remoteKey = args['remoteKey'] as String;
    Object? decodedCurrent;
    try {
      final decoded = json.decode(raw);
      decodedCurrent = decoded is List ? decoded : const <dynamic>[];
    } catch (_) {
      decodedCurrent = null;
    }
    final collectionHash = _collectionHashForKey(remoteKey, items);
    return {
      'identical':
          decodedCurrent != null &&
          _syncPayloadHash(decodedCurrent) == collectionHash,
      'encoded': json.encode(items),
      'collectionHash': collectionHash,
      'itemBucket': _itemHashBucketForKey(remoteKey, items),
    };
  }

  Map<String, dynamic> _readLocalObject(
    SharedPreferences prefs,
    String localKey,
  ) {
    final raw = prefs.getString(localKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = json.decode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Treat corrupt local object payloads as empty so a valid remote payload
      // can repair them.
    }
    return <String, dynamic>{};
  }

  Future<void> _writeLocalObject(
    SharedPreferences prefs,
    String localKey,
    Map<dynamic, dynamic> value,
  ) async {
    if (_syncPayloadHash(_readLocalObject(prefs, localKey)) ==
        _syncPayloadHash(value)) {
      return;
    }
    await prefs.setString(localKey, json.encode(value));
  }

  bool _remoteObjectIsOlderThanLocal(
    SharedPreferences prefs,
    String localKey,
    Map<dynamic, dynamic> remoteValue,
  ) {
    if (localKey != 'theme_shop_state' &&
        localKey != 'duoyi_virtual_rewards' &&
        localKey != 'user_profile') {
      return false;
    }
    final local = _readLocalObject(prefs, localKey);
    final localUpdatedAt = _remoteItemUpdatedAt(local);
    final remoteUpdatedAt = _remoteItemUpdatedAt(remoteValue);
    if (localUpdatedAt.isNotEmpty && remoteUpdatedAt.isEmpty) return true;
    if (localUpdatedAt.isEmpty || remoteUpdatedAt.isEmpty) return false;
    return _timestampGt(localUpdatedAt, remoteUpdatedAt);
  }

  Future<void> _writePreferencesPayload(
    SharedPreferences prefs,
    Map<dynamic, dynamic> payload,
  ) async {
    final normalized = Map<String, dynamic>.from(payload);
    final values = normalized['values'];
    if (values is Map) {
      final remoteKeys = values.keys
          .map((key) => key.toString())
          .where(_preferenceKeys.contains)
          .toSet();
      if (_syncPayloadHash(_readPreferenceValues(prefs)) ==
          _syncPayloadHash({for (final key in remoteKeys) key: values[key]})) {
        // Values already match. Still fall through to update the sync stamp.
      }
      for (final entry in values.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (_preferenceBoolKeys.contains(key) && value is bool) {
          await prefs.setBool(key, value);
        } else if (_preferenceIntKeys.contains(key) && value is num) {
          await prefs.setInt(key, value.toInt());
        } else if (_preferenceStringKeys.contains(key) && value is String) {
          await prefs.setString(key, value);
        } else if (_preferenceStringListKeys.contains(key) && value is List) {
          await prefs.setStringList(
            key,
            value.map((item) => item.toString()).toList(growable: false),
          );
        }
      }
    }
    final updatedAt = normalized['updatedAt']?.toString() ?? '';
    if (updatedAt.isNotEmpty) {
      _pendingPreferencesUpdatedAt = null;
      await prefs.setString(_preferencesUpdatedAtStorageKey, updatedAt);
    }
  }

  bool _remotePreferencesAreOlderThanLocal(
    SharedPreferences prefs,
    Map<String, dynamic> remotePayload,
  ) {
    // 只要本地存在有效的偏好 stamp 就按时间戳比较：pendingKeys 可能已经
    // 被一次失败的同步/进程重启丢掉，此时若直接返回 false，旧远端会覆盖
    // 带更新本地 stamp 的偏好。冲突合并仍由 changedKeys 语义处理。
    final localUpdatedAt =
        _pendingPreferencesUpdatedAt ??
        prefs.getString(_preferencesUpdatedAtStorageKey) ??
        '';
    final remoteUpdatedAt = remotePayload['updatedAt']?.toString() ?? '';
    if (localUpdatedAt.isEmpty) return false;
    if (remoteUpdatedAt.isEmpty) return true;
    return _timestampGt(localUpdatedAt, remoteUpdatedAt);
  }

  bool _remoteQuickCaptureTemplatesAreOlderThanLocal(
    SharedPreferences prefs,
    Map<String, dynamic> remotePayload,
  ) {
    final localUpdatedAt =
        _pendingQuickCaptureTemplatesUpdatedAt ??
        prefs.getString(_quickCaptureTemplatesUpdatedAtStorageKey) ??
        '';
    final remoteUpdatedAt = remotePayload['updatedAt']?.toString() ?? '';
    if (_pendingQuickCaptureTemplatesUpdatedAt == null &&
        localUpdatedAt.isEmpty) {
      return false;
    }
    if (localUpdatedAt.isNotEmpty && remoteUpdatedAt.isEmpty) return true;
    if (localUpdatedAt.isEmpty || remoteUpdatedAt.isEmpty) return false;
    return _timestampGt(localUpdatedAt, remoteUpdatedAt);
  }

  Future<void> _persistPreferencesSnapshot(
    SharedPreferences prefs,
    Object? preferencesPayload,
  ) async {
    final values = preferencesPayload is Map
        ? preferencesPayload['values']
        : null;
    if (values is! Map) return;
    await prefs.setString(
      _preferencesValuesSnapshotStorageKey,
      json.encode(Map<String, dynamic>.from(values)),
    );
    final updatedAt = preferencesPayload is Map
        ? preferencesPayload['updatedAt']?.toString() ?? ''
        : '';
    if (updatedAt.isNotEmpty) {
      _pendingPreferencesUpdatedAt = null;
      await prefs.setString(_preferencesUpdatedAtStorageKey, updatedAt);
    }
    _pendingPreferenceKeys.clear();
    _pendingPreferencesFullSync = false;
    await prefs.remove(_preferencesChangedKeysStorageKey);
  }

  Future<void> _writeQuickCaptureTemplatesPayload(
    SharedPreferences prefs,
    Map<dynamic, dynamic> payload,
  ) async {
    final normalized = Map<String, dynamic>.from(payload);
    if (_syncPayloadHash(_buildQuickCaptureTemplatesPayload(prefs)) ==
        _syncPayloadHash(normalized)) {
      return;
    }
    final items = normalized['items'];
    await prefs.setString(
      _quickCaptureTemplatesStorageKey,
      json.encode(items is List ? items : const <dynamic>[]),
    );
    final updatedAt = normalized['updatedAt']?.toString() ?? '';
    if (updatedAt.isNotEmpty) {
      _pendingQuickCaptureTemplatesUpdatedAt = null;
      await prefs.setString(
        _quickCaptureTemplatesUpdatedAtStorageKey,
        updatedAt,
      );
    }
  }

  _WorkspaceMergeResult _mergeRemoteWorkspaceItems({
    required List<dynamic> current,
    required List<Map<String, dynamic>> remote,
    required Map<String, String> remoteWorkspaceIds,
    required String itemType,
  }) {
    final merged = <String, dynamic>{};
    for (final item in current) {
      if (item is Map && item['id'] != null) {
        merged[item['id'].toString()] = item;
      }
    }
    final decisions = <SyncMergeDecision>[];
    for (final item in remote) {
      final id = item['id'].toString();
      final prior = merged[id];
      if (prior is Map) {
        final oldTs = _remoteItemUpdatedAt(prior);
        final newTs = _remoteItemUpdatedAt(item);
        if (json.encode(prior) != json.encode(item)) {
          final remoteWins = oldTs.isEmpty || !_timestampGt(oldTs, newTs);
          final changedFields = _changedWorkspaceFields(prior, item);
          decisions.add(
            SyncMergeDecision(
              workspaceId: remoteWorkspaceIds[id] ?? '',
              itemType: itemType,
              itemId: id,
              winner: remoteWins ? 'remote' : 'local',
              reason: remoteWins ? '云端更新时间不早于本地' : '本地更新时间更新',
              changedFields: changedFields,
              localUpdatedAt: oldTs,
              remoteUpdatedAt: newTs,
              decidedAt: DateTime.now(),
            ),
          );
          if (remoteWins) merged[id] = item;
        }
      } else {
        merged[id] = item;
        decisions.add(
          SyncMergeDecision(
            workspaceId: remoteWorkspaceIds[id] ?? '',
            itemType: itemType,
            itemId: id,
            winner: 'remote',
            reason: '本地不存在该共享${_itemTypeLabel(itemType)}',
            localUpdatedAt: '',
            remoteUpdatedAt: _remoteItemUpdatedAt(item),
            decidedAt: DateTime.now(),
          ),
        );
      }
    }
    return _WorkspaceMergeResult(merged.values.toList(), decisions);
  }

  List<String> _changedWorkspaceFields(
    Map<dynamic, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final keys = <String>{
      for (final key in local.keys) key.toString(),
      ...remote.keys,
    }..removeAll(const {'id', 'workspaceId', 'createdAt', 'updatedAt'});
    final changed = <String>[];
    for (final key in keys) {
      final localValue = local[key];
      final remoteValue = remote[key];
      if (json.encode(localValue) != json.encode(remoteValue)) {
        changed.add(key);
      }
    }
    changed.sort();
    return changed;
  }

  static const _workspacePayloadCollections = <String, _WorkspacePayloadSpec>{
    'todos': _WorkspacePayloadSpec(localKey: 'todos', itemType: 'todo'),
    'goals': _WorkspacePayloadSpec(localKey: 'duoyi_goals', itemType: 'goal'),
    'courses': _WorkspacePayloadSpec(
      localKey: 'duoyi_courses',
      itemType: 'course',
    ),
    'time_entries': _WorkspacePayloadSpec(
      localKey: 'duoyi_time_entries',
      itemType: 'time_entry',
    ),
    'calendar_events': _WorkspacePayloadSpec(
      localKey: 'duoyi_local_calendar_events_v1',
      itemType: 'calendar_event',
    ),
  };

  static Map<String, dynamic> _workspaceBucket(
    Map<String, dynamic> result,
    String workspaceId,
  ) {
    return result.putIfAbsent(
          workspaceId,
          () => <String, dynamic>{
            'todos': <dynamic>[],
            'goals': <dynamic>[],
            'courses': <dynamic>[],
            'time_entries': <dynamic>[],
            'calendar_events': <dynamic>[],
          },
        )
        as Map<String, dynamic>;
  }

  static String? _sharedWorkspaceId(Map<dynamic, dynamic> item) {
    final workspaceId = item['workspaceId']?.toString().trim();
    if (workspaceId == null ||
        workspaceId.isEmpty ||
        workspaceId == 'private') {
      return null;
    }
    return workspaceId;
  }

  static String _itemTypeLabel(String itemType) {
    return switch (itemType) {
      'goal' => '目标',
      'course' => '课程',
      'time_entry' => '时间记录',
      'calendar_event' => '日程',
      _ => '任务',
    };
  }

  // legacy helper kept for future, but not wired to UI
  Future<Map<String, dynamic>?> rawPost(
    String url,
    Map<String, dynamic> body, {
    required String token,
  }) async {
    final resp = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode(body),
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>?;
    }
    return null;
  }
}

/// 单个同步集合的解码缓存条目。
///
/// [raw] 是该集合在 SharedPreferences 中的原始内容（字符串编码集合为
/// String，字符串列表集合为 `List<String>`）；[decoded] 是对应的解码结果，
/// 在整个同步流程中只读。raw 相等即保证解码结果一致（解码是确定性的），
/// 因此可以整体复用 [decoded]、[collectionHash] 与 [itemBucket]。
class _DecodedCollection {
  final Object? raw;
  final Object? decoded;
  final String collectionHash;
  final Map<String, String>? itemBucket;

  const _DecodedCollection({
    required this.raw,
    required this.decoded,
    required this.collectionHash,
    required this.itemBucket,
  });
}
