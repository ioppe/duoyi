import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_clock.dart';
import '../core/domain_event_bus.dart';
import '../models/diary_entry.dart';
import 'cloud_sync_provider.dart';

class DiaryProvider extends ChangeNotifier {
  static const _key = 'duoyi_diary';
  List<DiaryEntry> _entries = [];

  /// entries 倒序视图缓存；为 null 表示脏，下次读取时重排一次。
  List<DiaryEntry>? _sortedEntriesCache;
  int _storageGeneration = 0;

  /// 按 date 倒序的只读条目列表。
  ///
  /// 首次访问排序一次并缓存，后续访问直接返回同一不可变视图；
  /// 增/删/改/加载等变异入口通过 [_invalidateSortedCache] 置脏。
  /// 读取本 getter 不会变异 [_entries] 的内部顺序。
  List<DiaryEntry> get entries {
    final cached = _sortedEntriesCache;
    if (cached != null) return cached;
    final sorted = [..._entries]..sort((a, b) => b.date.compareTo(a.date));
    return _sortedEntriesCache = List.unmodifiable(sorted);
  }

  void _invalidateSortedCache() => _sortedEntriesCache = null;

  int get totalCount => _entries.length;

  int get thisMonthCount {
    final now = AppClock.now();
    return _entries
        .where((e) => e.date.year == now.year && e.date.month == now.month)
        .length;
  }

  /// 连续写日记天数
  int get currentStreak {
    if (_entries.isEmpty) return 0;
    final sorted = entries;
    final dates = sorted.map((e) => _normalize(e.date)).toSet().toList()
      ..sort((a, b) => b.compareTo(a));

    final today = AppClock.today();
    int streak = 0;
    DateTime cursor = today;
    if (!dates.contains(today)) {
      cursor = DateTime(today.year, today.month, today.day - 1);
      if (!dates.contains(cursor)) return 0;
    }
    while (dates.contains(cursor)) {
      streak++;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    return streak;
  }

  DateTime _normalize(DateTime d) => DateTime(d.year, d.month, d.day);

  DiaryEntry? entryForDate(DateTime date) {
    final key =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    for (final e in _entries) {
      if (e.dateKey == key) return e;
    }
    return null;
  }

  Map<String, DiaryEntry> get entriesByDate {
    final map = <String, DiaryEntry>{};
    for (final e in _entries) {
      map[e.dateKey] = e;
    }
    return map;
  }

  /// 心情统计(过去 N 天)
  Map<Mood, int> moodDistribution({int days = 30}) {
    final today = AppClock.today();
    final cutoff = DateTime(today.year, today.month, today.day - days + 1);
    final map = <Mood, int>{};
    for (final e in _entries) {
      if (e.mood == null) continue;
      if (_normalize(e.date).isBefore(cutoff)) continue;
      map[e.mood!] = (map[e.mood!] ?? 0) + 1;
    }
    return map;
  }

  Future<void> loadFromStorage() async {
    final generation = _storageGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration) return;
    final data = prefs.getStringList(_key) ?? [];
    _entries = data.map((e) => DiaryEntry.fromJson(jsonDecode(e))).toList();
    _invalidateSortedCache();
    notifyListeners();
  }

  void resetLocalState() {
    _storageGeneration++;
    _entries = [];
    _invalidateSortedCache();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      _entries.map((e) => jsonEncode(e.toJson())).toList(),
    );
    notifyListeners();
  }

  Future<void> addOrUpdate(DiaryEntry entry) async {
    final idx = _entries.indexWhere((e) => e.id == entry.id);
    // 同一天只保留一条，更新的情况下比对日期
    final sameDayIdx = _entries.indexWhere(
      (e) => e.dateKey == entry.dateKey && e.id != entry.id,
    );
    if (idx != -1) {
      entry.updatedAt = DateTime.now();
      _entries[idx] = entry;
    } else if (sameDayIdx != -1) {
      // 存在同一天的日记，合并
      final existing = _entries[sameDayIdx];
      existing.content = entry.content;
      existing.mood = entry.mood;
      existing.weather = entry.weather;
      existing.tags = entry.tags;
      existing.imagePaths = entry.imagePaths;
      existing.location = entry.location;
      existing.updatedAt = DateTime.now();
    } else {
      _entries.add(entry);
      DomainEventBus.instance.publish(
        DomainEvent(type: DomainEventType.diaryWritten, objectId: entry.id),
      );
    }
    // 增/改（含同日合并、同 id 替换）都可能影响排序键或内容，置脏。
    _invalidateSortedCache();
    await _save();
  }

  Future<void> delete(String id) async {
    await CloudSyncProvider.recordDeletedItem('diaries', id);
    _entries.removeWhere((e) => e.id == id);
    _invalidateSortedCache();
    await _save();
  }
}
