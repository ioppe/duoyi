import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_clock.dart';
import '../core/domain_event_bus.dart';
import '../models/habit.dart';
import '../models/time_entry.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/reminder_scheduler.dart';
import 'cloud_sync_provider.dart';
import 'time_audit_provider.dart';

class HabitProvider extends ChangeNotifier {
  static const Duration _reminderSyncTimeout = Duration(seconds: 5);

  List<Habit> _habits = [];
  TimeAuditProvider? _timeAudit;
  ReminderScheduler? _scheduler;
  int _storageGeneration = 0;

  List<Habit> get habits => _habits;

  double get todayOverallProgress {
    final active = _habits.where((h) => h.isActiveToday()).toList();
    if (active.isEmpty) return 0;
    return active.fold(0.0, (sum, h) => sum + h.todayProgress()) /
        active.length;
  }

  int get todayTotalCompletions => _habits
      .where((h) => h.isActiveToday())
      .fold(0, (sum, h) => sum + h.todayCount());

  double get todayCompletionRate {
    final active = _habits.where((h) => h.isActiveToday()).toList();
    if (active.isEmpty) return 0;
    return active.where((h) => h.isCompletedToday()).length / active.length;
  }

  int get longestCurrentStreak => _habits.fold(
    0,
    (max, h) => h.currentStreak > max ? h.currentStreak : max,
  );

  int get longestBestStreak =>
      _habits.fold(0, (max, h) => h.bestStreak > max ? h.bestStreak : max);

  // --- Persistence ---

  Future<void> loadFromStorage() async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration) return;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return;
    }
    final data = prefs.getString('habits');
    if (data != null) {
      final list = json.decode(data) as List;
      _habits = list.map((e) => Habit.fromJson(e)).toList();
    } else {
      _habits = [];
    }
    notifyListeners();
  }

  void resetLocalState() {
    _storageGeneration++;
    _habits = [];
    notifyListeners();
  }

  // ignore: use_setters_to_change_properties
  set timeAudit(TimeAuditProvider? provider) {
    _timeAudit = provider;
  }

  // ignore: use_setters_to_change_properties
  set scheduler(ReminderScheduler? scheduler) {
    _scheduler = scheduler;
  }

  Future<void> _save() async {
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    // 大列表的 JSON 编码会阻塞主 isolate，挪到后台 isolate 执行（对齐
    // todo_provider 的做法）；小列表直接同步编码，省去 isolate 往返。
    final data = _habits.length >= _isolateEncodeMinItems
        ? await compute(_encodeHabitStoragePayload, List<Habit>.of(_habits))
        : json.encode(_habits.map((e) => e.toJson()).toList());
    final prefs = await SharedPreferences.getInstance();
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return;
    }
    await prefs.setString('habits', data);
  }

  Future<void> _syncRemindersNow() async {
    final scheduler = _scheduler;
    if (scheduler == null) return;
    try {
      await scheduler
          .syncHabits(List.of(_habits))
          .timeout(_reminderSyncTimeout);
    } catch (error, stackTrace) {
      debugPrint('[HabitProvider] reminder sync failed: $error\n$stackTrace');
    }
  }

  // --- CRUD ---

  Future<void> addHabit(Habit habit) async {
    habit.updatedAt = DateTime.now();
    _habits.add(habit);
    DomainEventBus.instance.publish(
      DomainEvent(type: DomainEventType.habitCreated, objectId: habit.id),
    );
    await _save();
    await _syncRemindersNow();
    notifyListeners();
  }

  Future<HabitImportSummary> importHabits(Iterable<Habit> habits) async {
    var inserted = 0;
    var skippedDuplicates = 0;
    final existing = _habits
        .map((habit) => habit.name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
    for (final habit in habits) {
      final key = habit.name.trim().toLowerCase();
      if (key.isEmpty || existing.contains(key)) {
        skippedDuplicates++;
        continue;
      }
      _habits.add(habit);
      existing.add(key);
      inserted++;
      DomainEventBus.instance.publish(
        DomainEvent(type: DomainEventType.habitCreated, objectId: habit.id),
      );
    }
    if (inserted > 0) {
      await _save();
      await _syncRemindersNow();
      notifyListeners();
    }
    return HabitImportSummary(
      inserted: inserted,
      skippedDuplicates: skippedDuplicates,
    );
  }

  Future<void> incrementHabit(String id) async {
    await incrementHabitForDate(id, AppClock.now());
  }

  Future<void> incrementHabitForDate(
    String id,
    DateTime date, {
    int? amount,
  }) async {
    final idx = _habits.indexWhere((h) => h.id == id);
    if (idx != -1) {
      final habit = _habits[idx];
      if (!habit.activeForDate(date)) return;
      final key = _habits[idx].dateKey(date);
      final previousCount = habit.completions[key] ?? 0;
      if (habit.kind == HabitKind.positive) {
        if (habit.hasFlexRule) {
          final progress = habit.flexProgressForDate(date);
          if (progress?.isCompleted ?? false) return;
        } else if (previousCount >= habit.targetCount) {
          return;
        }
      }
      final increment = amount ?? _defaultCheckInAmount(habit, previousCount);
      if (increment <= 0) return;
      final stamp = DateTime.now();
      habit.completions[key] = previousCount + increment;
      habit.completionUpdatedAt[key] = stamp;
      _recalcStreak(idx);
      habit.updatedAt = stamp;
      DomainEventBus.instance.publish(
        DomainEvent(
          type: DomainEventType.habitCheckedIn,
          objectId: habit.id,
          metadata: {
            'amount': increment,
            'count': habit.completions[key] ?? 0,
            'date': key,
          },
        ),
      );
      await _save();
      notifyListeners();
      final timeAudit = _timeAudit;
      if (timeAudit != null) {
        try {
          await timeAudit.recordHabitCheckIn(
            habit,
            cumulativeCount: habit.completions[key] ?? 0,
            amount: increment,
            at: _timeForHabitRecord(date),
          );
        } catch (error, stackTrace) {
          debugPrint(
            '[HabitProvider] recordHabitCheckIn failed: $error\n$stackTrace',
          );
        }
      }
    }
  }

  Future<void> decrementHabit(String id) async {
    await decrementHabitForDate(id, AppClock.now());
  }

  Future<void> decrementHabitForDate(String id, DateTime date) async {
    final idx = _habits.indexWhere((h) => h.id == id);
    if (idx != -1) {
      final key = _habits[idx].dateKey(date);
      final v = _habits[idx].completions[key] ?? 0;
      if (v > 0) {
        final recordTime = _timeForHabitRecord(date);
        final amount =
            _timeAudit?.habitCheckInRecordedAmount(
              _habits[idx],
              count: v,
              at: recordTime,
            ) ??
            _defaultUndoAmount(_habits[idx], v);
        final next = v - amount;
        if (next <= 0) {
          _habits[idx].completions.remove(key);
        } else {
          _habits[idx].completions[key] = next;
        }
        final stamp = DateTime.now();
        _habits[idx].completionUpdatedAt[key] = stamp;
        _recalcStreak(idx);
        _habits[idx].updatedAt = stamp;
        await _save();
        notifyListeners();
        final timeAudit = _timeAudit;
        if (timeAudit != null) {
          try {
            await timeAudit.removeHabitCheckIn(
              _habits[idx],
              count: v,
              at: recordTime,
            );
          } catch (error, stackTrace) {
            debugPrint(
              '[HabitProvider] removeHabitCheckIn failed: $error\n$stackTrace',
            );
          }
        }
      }
    }
  }

  int _defaultCheckInAmount(Habit habit, int currentCount) {
    if (habit.kind != HabitKind.positive) return 1;
    if (TimeAuditProvider.habitUnitSeconds(habit) == null) return 1;
    final remaining = habit.targetCount - currentCount;
    return remaining > 0 ? remaining : 1;
  }

  int _defaultUndoAmount(Habit habit, int currentCount) {
    if (habit.kind != HabitKind.positive) return 1;
    if (TimeAuditProvider.habitUnitSeconds(habit) == null) return 1;
    if (currentCount <= habit.targetCount) return currentCount;
    return 1;
  }

  DateTime _timeForHabitRecord(DateTime date) {
    final now = AppClock.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return now;
    }
    return AppClock.date(date.year, date.month, date.day, 23, 59);
  }

  void _recalcStreak(int idx) {
    final h = _habits[idx];
    if (h.hasFlexRule) {
      _recalcFlexStreak(h);
      return;
    }
    int streak = 0;
    final now = AppClock.today();
    for (int i = 0; i < 365; i++) {
      final d = now.subtract(Duration(days: i));
      if (h.isCompletedForDate(d)) {
        streak++;
      } else if (i > 0) {
        break;
      }
    }
    h.currentStreak = streak;
    if (streak > h.bestStreak) h.bestStreak = streak;
  }

  void _recalcFlexStreak(Habit h) {
    var streak = 0;
    var bounds = h.periodBoundsForDate(AppClock.now());
    for (int i = 0; i < 120; i++) {
      final completed =
          h.flexProgressForDate(bounds.start)?.isCompleted ?? false;
      if (completed) {
        streak++;
      } else if (i > 0) {
        break;
      }
      bounds = h.previousPeriodBounds(bounds);
    }
    h.currentStreak = streak;
    if (streak > h.bestStreak) h.bestStreak = streak;
  }

  Future<void> deleteHabit(String id) async {
    final idx = _habits.indexWhere((h) => h.id == id);
    if (idx == -1) return;
    await CloudSyncProvider.recordDeletedItem('habits', id);
    await _timeAudit?.deleteBySource(TimeEntrySource.habit, id);
    _habits.removeWhere((h) => h.id == id);
    await _save();
    await _syncRemindersNow();
    notifyListeners();
  }

  Future<void> endHabit(String id, {DateTime? at}) async {
    final idx = _habits.indexWhere((h) => h.id == id);
    if (idx == -1) return;
    final base = at ?? AppClock.now();
    final day = DateTime(base.year, base.month, base.day);
    final habit = _habits[idx];
    final endDate = day.subtract(const Duration(days: 1));
    _habits[idx] = habit.copyWith(endDate: endDate);
    await _save();
    await _syncRemindersNow();
    notifyListeners();
  }

  Future<void> updateHabit(String id, Habit updated) async {
    final idx = _habits.indexWhere((h) => h.id == id);
    if (idx != -1) {
      _habits[idx] = updated.copyWith(updatedAt: DateTime.now());
      await _save();
      await _syncRemindersNow();
      notifyListeners();
    }
  }

  // --- Heatmap ---

  Map<String, int> combinedHeatmap(int weeks) {
    final data = <String, int>{};
    final now = AppClock.today();
    for (int w = 0; w < weeks; w++) {
      for (int d = 0; d < 7; d++) {
        final date = now.subtract(Duration(days: w * 7 + (6 - d)));
        final key =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        final active = _habits.where((h) => h.activeForDate(date)).toList();
        if (active.isEmpty) {
          data[key] = 0;
          continue;
        }
        final progress =
            active.fold(0.0, (sum, h) => sum + h.progressForDate(date)) /
            active.length;
        data[key] = progress <= 0
            ? 0
            : ((progress * 5).ceil().clamp(1, 5)).toInt();
      }
    }
    return data;
  }

  // --- Weekly stats ---

  List<double> last7DaysCompletion() {
    final now = AppClock.today();
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      final active = _habits.where((h) => h.activeForDate(d)).toList();
      if (active.isEmpty) return 0;
      return active.where((h) => h.isCompletedForDate(d)).length /
          active.length;
    });
  }

  bool _habitExistsOnDate(Habit habit, DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final start = AppClock.dateOnly(
      habit.startDate ?? AppClock.toLocal(habit.createdAt),
    );
    return !day.isBefore(start);
  }

  List<double> currentWeekProgress() {
    final now = AppClock.now();
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    return List.generate(7, (i) {
      final d = weekStart.add(Duration(days: i));
      final active = _habits
          .where((h) => _habitExistsOnDate(h, d) && h.activeForDate(d))
          .toList();
      if (active.isEmpty) return 0;
      return active.fold(0.0, (sum, h) => sum + h.progressForDate(d)) /
          active.length;
    });
  }

  // --- Reorder ---

  Future<void> reorder(List<String> orderedIds) async {
    final map = {for (final h in _habits) h.id: h};
    final newList = <Habit>[];
    for (int i = 0; i < orderedIds.length; i++) {
      final h = map[orderedIds[i]];
      if (h != null) {
        if (h.sortOrder != i) {
          h.sortOrder = i;
          h.updatedAt = DateTime.now();
        }
        newList.add(h);
        map.remove(orderedIds[i]);
      }
    }
    newList.addAll(map.values);
    _habits = newList;
    await _save();
    notifyListeners();
  }
}

class HabitImportSummary {
  final int inserted;
  final int skippedDuplicates;

  const HabitImportSummary({
    required this.inserted,
    required this.skippedDuplicates,
  });
}

/// 单文件本地持久化的 JSON 编码条数阈值：超过后挪到后台 isolate 编码。
const int _isolateEncodeMinItems = 500;

String _encodeHabitStoragePayload(List<Habit> habits) =>
    json.encode(habits.map((e) => e.toJson()).toList());
