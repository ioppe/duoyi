import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/achievement_engine.dart';
import '../core/achievements.dart';
import '../core/domain_event_bus.dart';
import '../core/growth_levels.dart';
import '../core/productivity_challenges.dart';
import '../services/account_local_data_cleaner.dart';
import 'notification_service.dart';

class RewardLedgerEntry {
  final String id;
  final String title;
  final int coins;
  final String reason;
  final DateTime awardedAt;

  const RewardLedgerEntry({
    required this.id,
    required this.title,
    required this.coins,
    required this.reason,
    required this.awardedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'coins': coins,
    'reason': reason,
    'awardedAt': awardedAt.toIso8601String(),
  };

  factory RewardLedgerEntry.fromJson(Map<String, dynamic> json) {
    return RewardLedgerEntry(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      coins: (json['coins'] as num?)?.toInt() ?? 0,
      reason: json['reason']?.toString() ?? '',
      awardedAt:
          DateTime.tryParse(json['awardedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class AchievementProvider extends ChangeNotifier {
  static const _storageKey = 'duoyi_achievements_unlocked';
  static const _rewardStorageKey = 'duoyi_virtual_rewards';
  static const _notifiedStorageKey = 'duoyi_achievements_notified';

  final AchievementEngine _engine;
  final DomainEventBus _bus;
  StreamSubscription<DomainEvent>? _eventSub;
  NotificationService? _notificationService;
  AchievementContext? _context;

  final Map<String, DateTime> _unlockedAt = {};
  final List<Achievement> _pendingUnlockedFeedback = <Achievement>[];
  final Set<String> _notifiedAchievementIds = <String>{};
  final Set<String> _rewardGrantIds = <String>{};
  final List<RewardLedgerEntry> _rewardLedger = <RewardLedgerEntry>[];
  List<AchievementSnapshot> _snapshots = const <AchievementSnapshot>[];
  DateTime? _lastEventAt;
  int _coinBalance = 0;
  int _lifetimeCoins = 0;
  int _persistedRevision = 0;
  String _rewardsUpdatedAt = '';
  bool _serverConfirmedRewardsChangePending = false;
  bool _storageLoaded = false;
  // 账号切换 / 登录后会先清空本地成就状态，再由云端 `achievement_states`
  // 回填 `_unlockedAt`。在回填完成前，任何对刚同步数据的成就重算都会把早已
  // 解锁（且用户已读）的成就误判为“新解锁”，从而重复弹出解锁提示。
  // 该开关在切号期间抑制解锁反馈（Toast + 系统通知），待基线恢复后再放开。
  bool _unlockFeedbackSuppressed = false;
  // 每次切号 / 登录抑制都会自增，用于让上一轮的安全兜底定时器失效：
  // 30s 兜底定时器捕获抑制时的代次，仅当代次未变时才放开，避免二次切号
  // 仍在抑制窗口内时被旧定时器提前恢复。
  int _unlockSuppressionGeneration = 0;
  Future<void>? _storageLoadFuture;
  int _storageGeneration = 0;

  AchievementProvider({AchievementEngine? engine, DomainEventBus? bus})
    : _engine = engine ?? AchievementEngine(),
      _bus = bus ?? DomainEventBus.instance;

  List<AchievementSnapshot> get snapshots =>
      List<AchievementSnapshot>.unmodifiable(_snapshots);
  List<ProductivityChallenge> get challenges => _context == null
      ? const <ProductivityChallenge>[]
      : ProductivityChallenges.build(_context!);
  Map<String, DateTime> get unlockedAt =>
      Map<String, DateTime>.unmodifiable(_unlockedAt);
  DateTime? get lastEventAt => _lastEventAt;
  int get coinBalance => _coinBalance;
  int get lifetimeCoins => _lifetimeCoins;
  int get persistedRevision => _persistedRevision;
  GrowthLevel get growthLevel => GrowthLevels.fromLifetimeCoins(_lifetimeCoins);
  List<RewardLedgerEntry> get rewardLedger =>
      List<RewardLedgerEntry>.unmodifiable(_rewardLedger);

  bool consumeServerConfirmedRewardsChange() {
    final value = _serverConfirmedRewardsChangePending;
    _serverConfirmedRewardsChangePending = false;
    return value;
  }

  int get unlockedCount => _snapshots.where((s) => s.unlocked).length;
  int get totalCount => Achievements.all.length;

  List<Achievement> takeUnlockedFeedback() {
    if (_pendingUnlockedFeedback.isEmpty) return const <Achievement>[];
    final next = List<Achievement>.unmodifiable(_pendingUnlockedFeedback);
    _pendingUnlockedFeedback.clear();
    return next;
  }

  /// 切号 / 登录开始时调用：在云端成就基线回填前抑制解锁反馈，
  /// 避免把早已解锁的成就当成“新解锁”重复弹窗。
  ///
  /// 返回本轮抑制的代次，调用方可把它传给 [resumeUnlockFeedback] 作为兜底，
  /// 确保只有“同一轮抑制”的延迟恢复才会生效。
  int suppressUnlockFeedback() {
    _unlockFeedbackSuppressed = true;
    _unlockSuppressionGeneration++;
    // 抑制窗口内已经误入队列的反馈先清掉，确保不会在恢复后补弹。
    _pendingUnlockedFeedback.clear();
    return _unlockSuppressionGeneration;
  }

  /// 云端基线回填完成（或切号流程结束）后调用，恢复正常解锁反馈。
  ///
  /// [generation] 非空时仅当它仍是最新一轮抑制才放开——这样上一轮切号的
  /// 安全兜底定时器不会误恢复正处于抑制窗口的新一轮切号。云端基线回填的
  /// 即时恢复不传 [generation]，无条件放开。
  ///
  /// 恢复前会把当前所有已解锁成就（`_unlockedAt.keys`）标记为"已通知"：
  /// 这些成就是在抑制窗口内 / 云端基线回填期间记录下来的，属于"早已解锁"，
  /// 不应在恢复后被当成"新解锁"重复弹窗。真正的新解锁只可能发生在恢复之后。
  void resumeUnlockFeedback({int? generation}) {
    if (generation != null && generation != _unlockSuppressionGeneration) {
      return;
    }
    if (_unlockFeedbackSuppressed) {
      final beforeCount = _notifiedAchievementIds.length;
      _notifiedAchievementIds.addAll(_unlockedAt.keys);
      if (_notifiedAchievementIds.length != beforeCount) {
        // 持久化新增的"已通知"标记，避免下次 loadFromStorage 再次丢失。
        unawaited(_saveNotifiedAchievements());
      }
    }
    _unlockFeedbackSuppressed = false;
  }

  @visibleForTesting
  bool get unlockFeedbackSuppressed => _unlockFeedbackSuppressed;

  /// 当前抑制代次，供切号兜底定时器捕获后回传 [resumeUnlockFeedback]。
  int get unlockSuppressionGeneration => _unlockSuppressionGeneration;

  void attachNotificationService(NotificationService service) {
    _notificationService = service;
  }

  Future<bool> spendCoins({
    required int coins,
    required String title,
    required String reason,
  }) async {
    if (coins <= 0 || _coinBalance < coins) return false;
    _coinBalance -= coins;
    _rewardLedger.insert(
      0,
      RewardLedgerEntry(
        id: 'spend:${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        coins: -coins,
        reason: reason,
        awardedAt: DateTime.now(),
      ),
    );
    if (_rewardLedger.length > 50) {
      _rewardLedger.removeRange(50, _rewardLedger.length);
    }
    await _saveRewards();
    _persistedRevision++;
    notifyListeners();
    return true;
  }

  Future<void> applyRewardsSnapshot(Map<dynamic, dynamic> rewards) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration) return;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return;
    }
    final incoming = Map<String, dynamic>.from(rewards);
    if (_isIncomingRewardsOlder(incoming)) {
      debugPrint(
        '[reward-sync] skipped older snapshot incoming='
        '${_rewardsUpdatedAtOf(incoming)} current=$_rewardsUpdatedAt',
      );
      return;
    }
    await prefs.setString(_rewardStorageKey, jsonEncode(incoming));
    final changed = _loadRewardsFromPrefs(prefs);
    if (!changed) return;
    _persistedRevision++;
    _serverConfirmedRewardsChangePending = true;
    debugPrint(
      '[reward-sync] applied server snapshot balance=$_coinBalance '
      'lifetime=$_lifetimeCoins revision=$_persistedRevision',
    );
    notifyListeners();
  }

  Future<void> loadFromStorage() async {
    final existing = _storageLoadFuture;
    if (existing != null) return existing;
    final generation = _storageGeneration;
    final future = _loadFromStorageNow(generation);
    _storageLoadFuture = future;
    await future.whenComplete(() {
      if (_storageLoadFuture == future) {
        _storageLoadFuture = null;
      }
    });
  }

  void resetLocalState() {
    _storageGeneration++;
    _storageLoadFuture = null;
    _storageLoaded = false;
    _unlockedAt.clear();
    _pendingUnlockedFeedback.clear();
    _notifiedAchievementIds.clear();
    _rewardGrantIds.clear();
    _rewardLedger.clear();
    _snapshots = const <AchievementSnapshot>[];
    _lastEventAt = null;
    _coinBalance = 0;
    _lifetimeCoins = 0;
    _persistedRevision++;
    _rewardsUpdatedAt = '';
    _serverConfirmedRewardsChangePending = false;
    _context = null;
    notifyListeners();
  }

  Future<void> _loadFromStorageNow(int generation) async {
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration) return;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return;
    }
    final beforeUnlocked = jsonEncode(
      _unlockedAt.map(
        (id, unlockedAt) => MapEntry(id, unlockedAt.toIso8601String()),
      ),
    );
    final raw = prefs.getString(_storageKey);
    _unlockedAt.clear();
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final parsed = DateTime.tryParse(entry.value.toString());
          if (parsed != null) _unlockedAt[entry.key.toString()] = parsed;
        }
      }
    }
    final previousNotifiedIds = Set<String>.from(_notifiedAchievementIds);
    final storedNotifiedIds = _normalizedAchievementIds(
      prefs.getStringList(_notifiedStorageKey) ?? const <String>[],
    );
    _notifiedAchievementIds
      ..clear()
      ..addAll(storedNotifiedIds)
      ..addAll(_unlockedAt.keys);
    if (_unlockFeedbackSuppressed) {
      _notifiedAchievementIds.addAll(previousNotifiedIds);
    }
    final shouldPersistNotified = !setEquals(
      storedNotifiedIds,
      _notifiedAchievementIds,
    );
    final unlockedChanged =
        beforeUnlocked !=
        jsonEncode(
          _unlockedAt.map(
            (id, unlockedAt) => MapEntry(id, unlockedAt.toIso8601String()),
          ),
        );
    final rewardsChanged = _loadRewardsFromPrefs(prefs);
    _storageLoaded = true;
    _subscribe();
    _rebuildSnapshots(notify: false);
    if (shouldPersistNotified &&
        generation == _storageGeneration &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      await prefs.setStringList(
        _notifiedStorageKey,
        _sortedNotifiedAchievementIds(),
      );
    }
    if (unlockedChanged || rewardsChanged) notifyListeners();
  }

  Future<void> updateContext(
    AchievementContext context, {
    bool silentUnlockFeedback = false,
  }) async {
    if (!_storageLoaded) {
      await loadFromStorage();
    }
    _context = context;
    _rebuildSnapshots(silentUnlockFeedback: silentUnlockFeedback);
  }

  AchievementSnapshot snapshotFor(String achievementId) {
    return _snapshots.firstWhere(
      (s) => s.id == achievementId,
      orElse: () =>
          AchievementSnapshot(id: achievementId, unlocked: false, current: 0),
    );
  }

  void _subscribe() {
    _eventSub ??= _bus.events.listen((event) {
      _lastEventAt = event.occurredAt;
      _rebuildSnapshots();
    });
  }

  void _rebuildSnapshots({
    bool notify = true,
    bool silentUnlockFeedback = false,
  }) {
    final context = _context;
    if (context == null) {
      _snapshots = [
        for (final achievement in Achievements.all)
          AchievementSnapshot(
            id: achievement.id,
            unlocked: _unlockedAt.containsKey(achievement.id),
            current: 0,
            target: achievement.target,
            unlockedAt: _unlockedAt[achievement.id],
          ),
      ];
      if (notify) notifyListeners();
      return;
    }

    final previousIds = _unlockedAt.keys.toSet();
    final evaluated = _engine.evaluate(
      context: context,
      previouslyUnlocked: _unlockedAt,
    );
    final newlyUnlocked = <Achievement>[];
    for (final snapshot in evaluated) {
      if (!snapshot.unlocked || snapshot.unlockedAt == null) continue;
      if (!_unlockedAt.containsKey(snapshot.id)) {
        _unlockedAt[snapshot.id] = snapshot.unlockedAt!;
      }
      if (!previousIds.contains(snapshot.id)) {
        final rule = Achievements.all.firstWhere((a) => a.id == snapshot.id);
        newlyUnlocked.add(rule);
      }
    }
    _snapshots = evaluated
        .map(
          (snapshot) => AchievementSnapshot(
            id: snapshot.id,
            unlocked: snapshot.unlocked,
            current: snapshot.current,
            target: snapshot.target,
            unlockedAt: _unlockedAt[snapshot.id],
          ),
        )
        .toList(growable: false);

    // 切号 / 登录基线回填期间仍记录成就解锁，抑制重复的解锁反馈。
    final silent = silentUnlockFeedback || _unlockFeedbackSuppressed;

    if (newlyUnlocked.isNotEmpty) {
      if (!silent) {
        // 与系统通知出口保持一致：已通知过的成就不再补弹应用内 Toast。
        _pendingUnlockedFeedback.addAll(
          newlyUnlocked.where(
            (achievement) => !_notifiedAchievementIds.contains(achievement.id),
          ),
        );
      }
    }

    final achievementIdsToMarkNotified = silent
        ? newlyUnlocked.map((achievement) => achievement.id).toList()
        : newlyUnlocked
              .map((achievement) => achievement.id)
              .where((id) => !_notifiedAchievementIds.contains(id))
              .toList(growable: false);
    final achievementsToNotify = silent
        ? const <Achievement>[]
        : newlyUnlocked
              .where(
                (achievement) =>
                    !_notifiedAchievementIds.contains(achievement.id),
              )
              .toList(growable: false);

    if (achievementIdsToMarkNotified.isNotEmpty) {
      _notifiedAchievementIds.addAll(achievementIdsToMarkNotified);
    }

    if (newlyUnlocked.isNotEmpty) {
      unawaited(
        _persistChangesThenNotify(
          saveAchievements: newlyUnlocked.isNotEmpty,
          saveRewards: false,
          notify: notify,
          achievementIdsToMarkNotified: achievementIdsToMarkNotified,
          achievementsToNotify: achievementsToNotify,
        ),
      );
      return;
    }

    if (notify) notifyListeners();
  }

  Future<void> _persistChangesThenNotify({
    required bool saveAchievements,
    required bool saveRewards,
    required bool notify,
    required List<String> achievementIdsToMarkNotified,
    required List<Achievement> achievementsToNotify,
  }) async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    if (saveAchievements) {
      await _save();
    }
    if (generation != _storageGeneration) {
      return;
    }
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return;
    }
    if (saveRewards) {
      await _saveRewards();
    }
    if (generation != _storageGeneration) {
      return;
    }
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return;
    }
    if (saveAchievements || saveRewards) {
      _persistedRevision++;
    }
    if (achievementIdsToMarkNotified.isNotEmpty) {
      _notifiedAchievementIds.addAll(achievementIdsToMarkNotified);
      await _saveNotifiedAchievements();
    }
    if (achievementsToNotify.isNotEmpty) {
      for (final achievement in achievementsToNotify) {
        _notificationService?.notifyAchievementUnlocked(achievement);
      }
    }
    if (notify) {
      notifyListeners();
    }
  }

  bool _loadRewardsFromPrefs(SharedPreferences prefs) {
    final before = _rewardsSnapshotHash();
    final raw = prefs.getString(_rewardStorageKey);
    _coinBalance = 0;
    _lifetimeCoins = 0;
    _rewardsUpdatedAt = '';
    _rewardGrantIds.clear();
    _rewardLedger.clear();
    if (raw == null || raw.isEmpty) {
      return before != _rewardsSnapshotHash();
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return before != _rewardsSnapshotHash();
    _coinBalance = (decoded['balance'] as num?)?.toInt() ?? 0;
    _lifetimeCoins = (decoded['lifetime'] as num?)?.toInt() ?? _coinBalance;
    _rewardsUpdatedAt = _rewardsUpdatedAtOf(decoded);
    final grantIds = decoded['grantIds'];
    if (grantIds is List) {
      _rewardGrantIds.addAll(grantIds.map((id) => id.toString()));
    }
    final ledger = decoded['ledger'];
    if (ledger is List) {
      for (final item in ledger) {
        if (item is Map) {
          _rewardLedger.add(
            RewardLedgerEntry.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return before != _rewardsSnapshotHash();
  }

  Future<void> _save() async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final data = jsonEncode(
      _unlockedAt.map(
        (id, unlockedAt) => MapEntry(id, unlockedAt.toIso8601String()),
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration) {
      return;
    }
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return;
    }
    await prefs.setString(_storageKey, data);
  }

  Future<void> _saveRewards() async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final data = jsonEncode({
      'balance': _coinBalance,
      'lifetime': _lifetimeCoins,
      'grantIds': _rewardGrantIds.toList(growable: false),
      'ledger': _rewardLedger.map((entry) => entry.toJson()).toList(),
      'updatedAt': updatedAt,
    });
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return;
    }
    _rewardsUpdatedAt = updatedAt;
    await prefs.setString(_rewardStorageKey, data);
  }

  Future<void> _saveNotifiedAchievements() async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final ids = _sortedNotifiedAchievementIds();
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return;
    }
    await prefs.setStringList(_notifiedStorageKey, ids);
  }

  Set<String> _normalizedAchievementIds(Iterable<String> ids) {
    return ids.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
  }

  List<String> _sortedNotifiedAchievementIds() {
    return _notifiedAchievementIds.toList(growable: false)..sort();
  }

  bool _isIncomingRewardsOlder(Map<dynamic, dynamic> incoming) {
    final incomingUpdatedAt = _rewardsUpdatedAtOf(incoming);
    if (_rewardsUpdatedAt.isEmpty) return false;
    if (incomingUpdatedAt.isEmpty) return true;
    final incomingTime = DateTime.tryParse(incomingUpdatedAt);
    final currentTime = DateTime.tryParse(_rewardsUpdatedAt);
    if (incomingTime != null && currentTime != null) {
      return incomingTime.toUtc().isBefore(currentTime.toUtc());
    }
    return incomingUpdatedAt.compareTo(_rewardsUpdatedAt) < 0;
  }

  String _rewardsUpdatedAtOf(Map<dynamic, dynamic> data) {
    return data['updatedAt']?.toString() ??
        data['updated_at']?.toString() ??
        '';
  }

  String _rewardsSnapshotHash() {
    return jsonEncode({
      'balance': _coinBalance,
      'lifetime': _lifetimeCoins,
      'grantIds': _rewardGrantIds.toList(growable: false)..sort(),
      'ledger': _rewardLedger.map((entry) => entry.toJson()).toList(),
      'updatedAt': _rewardsUpdatedAt,
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}
