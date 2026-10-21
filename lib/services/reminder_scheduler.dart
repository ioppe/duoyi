import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/app_clock.dart';
import '../core/brand_strings.dart';
import '../core/i18n.dart';
import '../models/anniversary.dart';
import '../models/countdown.dart';
import '../models/goal.dart';
import '../models/habit.dart';
import '../models/todo.dart';
import 'alarm_service.dart';
import 'notification_permission_exception.dart';
import 'reminder_sinks.dart';
import 'reminder_notification_id.dart';

const Duration _sameMinuteReminderGrace = Duration(seconds: 70);

class TodoReminderPreflightIssue {
  final String title;
  final String message;
  final bool blocking;
  final DateTime? scheduledTime;

  const TodoReminderPreflightIssue({
    required this.title,
    required this.message,
    this.blocking = true,
    this.scheduledTime,
  });
}

class TodoReminderPreflightResult {
  final bool hasEnabledPlan;
  final Set<ReminderKind> kinds;
  final DateTime? firstScheduledTime;
  final List<TodoReminderPreflightIssue> issues;

  const TodoReminderPreflightResult({
    required this.hasEnabledPlan,
    required this.kinds,
    required this.firstScheduledTime,
    required this.issues,
  });

  bool get ok => issues.every((issue) => !issue.blocking);
  TodoReminderPreflightIssue? get blockingIssue {
    for (final issue in issues) {
      if (issue.blocking) return issue;
    }
    return null;
  }
}

@immutable
class ReminderScheduleSnapshotEntry {
  final String objectType;
  final String objectId;
  final List<int> ids;
  final String title;
  final String subtitle;

  const ReminderScheduleSnapshotEntry({
    required this.objectType,
    required this.objectId,
    required this.ids,
    required this.title,
    required this.subtitle,
  });

  int get idCount => ids.length;
  String get objectKey => '$objectType:$objectId';
}

@immutable
class ReminderScheduleDisplayInfo {
  final String title;
  final String subtitle;

  const ReminderScheduleDisplayInfo({
    required this.title,
    required this.subtitle,
  });
}

TodoReminderPreflightResult preflightTodoReminderPlan(
  TodoItem todo, {
  DateTime? now,
}) {
  final effectiveNow = now == null ? AppClock.now() : AppClock.toLocal(now);
  final plan = _effectiveTodoPlanForPreflight(todo);
  final enabledRules = plan.enabled
      ? plan.rules
            .where((rule) => rule.enabled && rule.kind != ReminderKind.off)
            .toList(growable: false)
      : const <ReminderRule>[];
  if (enabledRules.isEmpty) {
    return const TodoReminderPreflightResult(
      hasEnabledPlan: false,
      kinds: <ReminderKind>{},
      firstScheduledTime: null,
      issues: <TodoReminderPreflightIssue>[],
    );
  }

  final kinds = <ReminderKind>{};
  final issues = <TodoReminderPreflightIssue>[];
  DateTime? firstScheduledTime;
  var deliverableRules = 0;

  for (final rule in enabledRules) {
    kinds.add(rule.kind);
    switch (rule.type) {
      case ReminderRuleType.absolute:
        final anchor = _absoluteTodoReminderAnchor(todo);
        if (anchor == null) {
          issues.add(
            const TodoReminderPreflightIssue(
              title: '待办提醒注册失败',
              message: '一次性提醒需要截止日期或提醒日期。请先设置未来的日期。',
            ),
          );
          continue;
        }
        final base = _todoReminderAtTime(
          anchor,
          rule.hour ?? anchor.hour,
          rule.minute ?? anchor.minute,
        );
        final scheduledWhen = _coerceJustMissedOneShotReminder(
          base,
          effectiveNow,
        );
        if (scheduledWhen == null) {
          issues.add(
            TodoReminderPreflightIssue(
              title: '待办提醒注册失败',
              message: '提醒时间已过去，未注册到系统通知。请把提醒时间改到未来时间。',
              scheduledTime: base,
            ),
          );
          continue;
        }
        deliverableRules++;
        if (firstScheduledTime == null ||
            scheduledWhen.isBefore(firstScheduledTime)) {
          firstScheduledTime = scheduledWhen;
        }
        break;
      case ReminderRuleType.relativeToDue:
        final anchor = _relativeTodoReminderAnchor(todo);
        if (anchor == null) {
          issues.add(
            const TodoReminderPreflightIssue(
              title: '待办提醒注册失败',
              message: '一次性提醒需要截止日期或提醒日期。请先设置未来的日期。',
            ),
          );
          continue;
        }
        final base = _todoReminderAtTime(
          anchor,
          rule.hour ?? anchor.hour,
          rule.minute ?? anchor.minute,
        );
        final when = base.add(Duration(minutes: rule.offsetMinutes ?? 0));
        final scheduledWhen = _coerceJustMissedOneShotReminder(
          when,
          effectiveNow,
        );
        if (scheduledWhen == null) {
          issues.add(
            TodoReminderPreflightIssue(
              title: '待办提醒注册失败',
              message: '提醒时间已过去，未注册到系统通知。请把提醒时间改到未来时间。',
              scheduledTime: when,
            ),
          );
          continue;
        }
        deliverableRules++;
        if (firstScheduledTime == null ||
            scheduledWhen.isBefore(firstScheduledTime)) {
          firstScheduledTime = scheduledWhen;
        }
        break;
      case ReminderRuleType.dailyTime:
        if (!_validTimeForPreflight(rule.hour, rule.minute)) {
          issues.add(
            const TodoReminderPreflightIssue(
              title: '重复提醒注册失败',
              message: '重复提醒缺少有效时间，请重新选择提醒时间。',
            ),
          );
          continue;
        }
        deliverableRules++;
        break;
      case ReminderRuleType.weeklyTime:
        if (!_validTimeForPreflight(rule.hour, rule.minute) ||
            rule.weekdays.isEmpty) {
          issues.add(
            const TodoReminderPreflightIssue(
              title: '每周提醒注册失败',
              message: '每周提醒需要有效时间和至少一个星期。请重新选择提醒规则。',
            ),
          );
          continue;
        }
        deliverableRules++;
        break;
    }
  }

  if (deliverableRules == 0 && issues.isEmpty) {
    issues.add(
      const TodoReminderPreflightIssue(
        title: '待办提醒注册失败',
        message: '提醒计划没有可注册的规则，请重新设置提醒。',
      ),
    );
  }

  return TodoReminderPreflightResult(
    hasEnabledPlan: true,
    kinds: kinds,
    firstScheduledTime: firstScheduledTime,
    issues: issues,
  );
}

ReminderPlan _effectiveTodoPlanForPreflight(TodoItem t) {
  if (t.reminderPlan.enabled && t.reminderPlan.rules.isNotEmpty) {
    return t.reminderPlan;
  }
  if (t.reminder.enabled) {
    return ReminderPlan.fromLegacy(t.reminder);
  }
  // ignore: deprecated_member_use_from_same_package
  if (t.hasReminder) {
    final anchor = _absoluteTodoReminderAnchor(t);
    if (anchor == null) return const ReminderPlan.disabled();
    return ReminderPlan(
      enabled: true,
      rules: [
        ReminderRule(
          id: 'legacy-${t.id}',
          enabled: true,
          type: ReminderRuleType.absolute,
          kind: ReminderKind.push,
          hour: anchor.hour,
          minute: anchor.minute,
        ),
      ],
    );
  }
  return const ReminderPlan.disabled();
}

DateTime? _absoluteTodoReminderAnchor(TodoItem todo) => todo.reminderAt == null
    ? todo.localDueDate
    : AppClock.toLocal(todo.reminderAt!);

DateTime? _relativeTodoReminderAnchor(TodoItem todo) =>
    todo.localDueDate ?? _absoluteTodoReminderAnchor(todo);

DateTime _todoReminderAtTime(DateTime anchor, int hour, int minute) {
  // Preserve the selected occurrence of a repeated DST wall-clock hour.
  if (anchor is tz.TZDateTime &&
      anchor.hour == hour &&
      anchor.minute == minute) {
    return anchor;
  }
  return AppClock.date(anchor.year, anchor.month, anchor.day, hour, minute);
}

bool _validTimeForPreflight(int? hour, int? minute) {
  return hour != null &&
      minute != null &&
      hour >= 0 &&
      hour <= 23 &&
      minute >= 0 &&
      minute <= 59;
}

DateTime? _coerceJustMissedOneShotReminder(DateTime when, DateTime now) {
  if (when.isAfter(now)) return when;
  when = AppClock.toLocal(when);
  now = AppClock.toLocal(now);
  final missedBy = now.difference(when);
  final sameLocalMinute =
      when.year == now.year &&
      when.month == now.month &&
      when.day == now.day &&
      when.hour == now.hour &&
      when.minute == now.minute;
  if (sameLocalMinute &&
      !missedBy.isNegative &&
      missedBy <= _sameMinuteReminderGrace) {
    return now.add(
      Duration(
        seconds: 60 - now.second,
        milliseconds: -now.millisecond,
        microseconds: -now.microsecond,
      ),
    );
  }
  return null;
}

DateTime? _resolveOneShotReminderTime(
  DateTime when,
  DateTime now, {
  required bool allowJustMissed,
}) {
  if (allowJustMissed) {
    return _coerceJustMissedOneShotReminder(when, now);
  }
  return when.isAfter(now) ? when : null;
}

/// 推送 / 闹钟路由分发用的统一载荷。
class _DispatchPayload {
  final int id;
  final String title;
  final String body;
  final DateTime when;
  final String? payload;
  final bool fullScreen;
  final bool vibrate;
  final int snoozeMinutes;
  final int repeatCount;

  const _DispatchPayload({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
    this.payload,
    this.fullScreen = true,
    this.vibrate = true,
    this.snoozeMinutes = 0,
    this.repeatCount = 0,
  });
}

class _ScheduledRule {
  final ReminderKind kind;
  final _DispatchMode mode;
  final String scope;
  final String fingerprint;
  final String title;
  final String body;

  const _ScheduledRule({
    required this.kind,
    required this.mode,
    required this.scope,
    required this.fingerprint,
    required this.title,
    required this.body,
  });
}

enum _DispatchMode { once, repeating }

abstract class ReminderScheduleRegistry {
  const ReminderScheduleRegistry();

  Future<Map<String, Set<int>>> idsByObject(String objectType);

  Future<Map<String, ReminderScheduleDisplayInfo>> displayByObject(
    String objectType,
  );

  Future<void> replaceObject(
    String objectType,
    String objectId,
    Set<int> ids, {
    ReminderScheduleDisplayInfo? display,
  });

  Future<void> removeObject(String objectType, String objectId);
}

class SharedPreferencesReminderScheduleRegistry
    implements ReminderScheduleRegistry {
  static const _storageKey = 'reminder_scheduler_registry_v1';
  static const _displayStorageKey = 'reminder_scheduler_display_registry_v1';

  const SharedPreferencesReminderScheduleRegistry();

  @override
  Future<Map<String, Set<int>>> idsByObject(String objectType) async {
    final all = await _readAll();
    return {
      for (final entry
          in (all[objectType] ?? const <String, Set<int>>{}).entries)
        entry.key: Set<int>.from(entry.value),
    };
  }

  @override
  Future<Map<String, ReminderScheduleDisplayInfo>> displayByObject(
    String objectType,
  ) async {
    final all = await _readDisplayAll();
    return {
      for (final entry
          in (all[objectType] ?? const <String, ReminderScheduleDisplayInfo>{})
              .entries)
        entry.key: entry.value,
    };
  }

  @override
  Future<void> replaceObject(
    String objectType,
    String objectId,
    Set<int> ids, {
    ReminderScheduleDisplayInfo? display,
  }) async {
    final normalized = ids.where((id) => id != 0).toSet();
    if (normalized.isEmpty) {
      await removeObject(objectType, objectId);
      return;
    }
    final all = await _readAll();
    final typeMap = all.putIfAbsent(objectType, () => <String, Set<int>>{});
    typeMap[objectId] = normalized;
    await _writeAll(all);
    if (display != null) {
      await _replaceDisplayObject(objectType, objectId, display);
    }
  }

  @override
  Future<void> removeObject(String objectType, String objectId) async {
    final all = await _readAll();
    final typeMap = all[objectType];
    if (typeMap == null) return;
    typeMap.remove(objectId);
    if (typeMap.isEmpty) all.remove(objectType);
    await _writeAll(all);
    await _removeDisplayObject(objectType, objectId);
  }

  Future<SharedPreferences?> _prefsOrNull() async {
    var bindingInitialized = true;
    assert(() {
      bindingInitialized = BindingBase.debugBindingType() != null;
      return true;
    }());
    if (!bindingInitialized) return null;
    try {
      return await SharedPreferences.getInstance();
    } catch (e, st) {
      debugPrint(
        '[ReminderScheduler] reminder registry prefs unavailable: $e\n$st',
      );
      return null;
    }
  }

  Future<Map<String, Map<String, Set<int>>>> _readAll() async {
    final prefs = await _prefsOrNull();
    if (prefs == null) return <String, Map<String, Set<int>>>{};
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return <String, Map<String, Set<int>>>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, Map<String, Set<int>>>{};
      final result = <String, Map<String, Set<int>>>{};
      decoded.forEach((type, rawObjects) {
        if (type is! String || rawObjects is! Map) return;
        final objects = <String, Set<int>>{};
        rawObjects.forEach((objectId, rawIds) {
          if (objectId is! String || rawIds is! List) return;
          final ids = <int>{};
          for (final rawId in rawIds) {
            final id = rawId is int
                ? normalizePlatformNotificationId(rawId)
                : rawId is num
                ? normalizePlatformNotificationId(rawId.toInt())
                : null;
            if (id != null && id != 0) ids.add(id);
          }
          if (ids.isNotEmpty) objects[objectId] = ids;
        });
        if (objects.isNotEmpty) result[type] = objects;
      });
      return result;
    } catch (e, st) {
      debugPrint(
        '[ReminderScheduler] reminder registry decode failed: $e\n$st',
      );
      return <String, Map<String, Set<int>>>{};
    }
  }

  Future<Map<String, Map<String, ReminderScheduleDisplayInfo>>>
  _readDisplayAll() async {
    final prefs = await _prefsOrNull();
    if (prefs == null) {
      return <String, Map<String, ReminderScheduleDisplayInfo>>{};
    }
    final raw = prefs.getString(_displayStorageKey);
    if (raw == null || raw.isEmpty) {
      return <String, Map<String, ReminderScheduleDisplayInfo>>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, Map<String, ReminderScheduleDisplayInfo>>{};
      }
      final result = <String, Map<String, ReminderScheduleDisplayInfo>>{};
      decoded.forEach((type, rawObjects) {
        if (type is! String || rawObjects is! Map) return;
        final objects = <String, ReminderScheduleDisplayInfo>{};
        rawObjects.forEach((objectId, rawDisplay) {
          if (objectId is! String || rawDisplay is! Map) return;
          final title = rawDisplay['title'];
          final subtitle = rawDisplay['subtitle'];
          if (title is! String || subtitle is! String) return;
          final cleanTitle = title.trim();
          final cleanSubtitle = subtitle.trim();
          if (cleanTitle.isEmpty && cleanSubtitle.isEmpty) return;
          objects[objectId] = ReminderScheduleDisplayInfo(
            title: cleanTitle,
            subtitle: cleanSubtitle,
          );
        });
        if (objects.isNotEmpty) result[type] = objects;
      });
      return result;
    } catch (e, st) {
      debugPrint(
        '[ReminderScheduler] reminder display registry decode failed: $e\n$st',
      );
      return <String, Map<String, ReminderScheduleDisplayInfo>>{};
    }
  }

  Future<void> _writeAll(Map<String, Map<String, Set<int>>> all) async {
    final prefs = await _prefsOrNull();
    if (prefs == null) return;
    final encoded = <String, Map<String, List<int>>>{};
    for (final typeEntry in all.entries) {
      final objects = <String, List<int>>{};
      for (final objectEntry in typeEntry.value.entries) {
        final ids = objectEntry.value.where((id) => id != 0).toList()..sort();
        if (ids.isNotEmpty) objects[objectEntry.key] = ids;
      }
      if (objects.isNotEmpty) encoded[typeEntry.key] = objects;
    }
    if (encoded.isEmpty) {
      await prefs.remove(_storageKey);
    } else {
      await prefs.setString(_storageKey, jsonEncode(encoded));
    }
  }

  Future<void> _replaceDisplayObject(
    String objectType,
    String objectId,
    ReminderScheduleDisplayInfo display,
  ) async {
    final all = await _readDisplayAll();
    final typeMap = all.putIfAbsent(
      objectType,
      () => <String, ReminderScheduleDisplayInfo>{},
    );
    typeMap[objectId] = display;
    await _writeDisplayAll(all);
  }

  Future<void> _removeDisplayObject(String objectType, String objectId) async {
    final all = await _readDisplayAll();
    final typeMap = all[objectType];
    if (typeMap == null) return;
    typeMap.remove(objectId);
    if (typeMap.isEmpty) all.remove(objectType);
    await _writeDisplayAll(all);
  }

  Future<void> _writeDisplayAll(
    Map<String, Map<String, ReminderScheduleDisplayInfo>> all,
  ) async {
    final prefs = await _prefsOrNull();
    if (prefs == null) return;
    final encoded = <String, Map<String, Map<String, String>>>{};
    for (final typeEntry in all.entries) {
      final objects = <String, Map<String, String>>{};
      for (final objectEntry in typeEntry.value.entries) {
        objects[objectEntry.key] = {
          'title': objectEntry.value.title,
          'subtitle': objectEntry.value.subtitle,
        };
      }
      if (objects.isNotEmpty) encoded[typeEntry.key] = objects;
    }
    if (encoded.isEmpty) {
      await prefs.remove(_displayStorageKey);
    } else {
      await prefs.setString(_displayStorageKey, jsonEncode(encoded));
    }
  }
}

@visibleForTesting
class InMemoryReminderScheduleRegistry implements ReminderScheduleRegistry {
  final Map<String, Map<String, Set<int>>> _store = {};
  final Map<String, Map<String, ReminderScheduleDisplayInfo>> _displayStore =
      {};

  @override
  Future<Map<String, Set<int>>> idsByObject(String objectType) async {
    return {
      for (final entry
          in (_store[objectType] ?? const <String, Set<int>>{}).entries)
        entry.key: Set<int>.from(entry.value),
    };
  }

  @override
  Future<Map<String, ReminderScheduleDisplayInfo>> displayByObject(
    String objectType,
  ) async {
    return {
      for (final entry
          in (_displayStore[objectType] ??
                  const <String, ReminderScheduleDisplayInfo>{})
              .entries)
        entry.key: entry.value,
    };
  }

  @override
  Future<void> replaceObject(
    String objectType,
    String objectId,
    Set<int> ids, {
    ReminderScheduleDisplayInfo? display,
  }) async {
    final normalized = ids.where((id) => id != 0).toSet();
    if (normalized.isEmpty) {
      await removeObject(objectType, objectId);
      return;
    }
    _store.putIfAbsent(objectType, () => <String, Set<int>>{})[objectId] =
        normalized;
    if (display != null) {
      _displayStore.putIfAbsent(
        objectType,
        () => <String, ReminderScheduleDisplayInfo>{},
      )[objectId] = display;
    }
  }

  @override
  Future<void> removeObject(String objectType, String objectId) async {
    final typeMap = _store[objectType];
    if (typeMap == null) return;
    typeMap.remove(objectId);
    if (typeMap.isEmpty) _store.remove(objectType);
    final displayTypeMap = _displayStore[objectType];
    if (displayTypeMap == null) return;
    displayTypeMap.remove(objectId);
    if (displayTypeMap.isEmpty) _displayStore.remove(objectType);
  }
}

class _ResolvedRule {
  final String objectType;
  final String objectId;
  final String ruleId;
  final ReminderKind kind;
  final _DispatchMode mode;
  final ReminderRuleType ruleType;
  final String title;
  final String body;
  final String payload;
  final bool fullScreen;
  final bool vibrate;
  final int snoozeMinutes;
  final int repeatCount;
  final DateTime? when;
  final int? hour;
  final int? minute;
  final List<int> weekdays;
  final String scope;

  const _ResolvedRule({
    required this.objectType,
    required this.objectId,
    required this.ruleId,
    required this.kind,
    required this.mode,
    required this.ruleType,
    required this.title,
    required this.body,
    required this.payload,
    required this.fullScreen,
    required this.vibrate,
    required this.snoozeMinutes,
    required this.repeatCount,
    required this.scope,
    this.when,
    this.hour,
    this.minute,
    this.weekdays = const <int>[],
  });

  String get key => '$objectType:$objectId:$ruleId';

  String get fingerprint {
    final weekdayPart = weekdays.isEmpty ? '-' : weekdays.join(',');
    final whenPart = when?.toIso8601String() ?? '-';
    final hourPart = hour?.toString() ?? '-';
    final minutePart = minute?.toString() ?? '-';
    return [
      kind.index,
      mode.name,
      ruleType.index,
      scope,
      title,
      body,
      payload,
      fullScreen ? 'fs1' : 'fs0',
      vibrate ? 'v1' : 'v0',
      snoozeMinutes,
      repeatCount,
      whenPart,
      hourPart,
      minutePart,
      weekdayPart,
    ].join('|');
  }

  String get deliveryFingerprint {
    final weekdayPart = weekdays.isEmpty ? '-' : weekdays.join(',');
    final whenPart = when?.toIso8601String() ?? '-';
    final hourPart = hour?.toString() ?? '-';
    final minutePart = minute?.toString() ?? '-';
    return [
      kind.index,
      mode.name,
      scope,
      body,
      payload,
      fullScreen ? 'fs1' : 'fs0',
      vibrate ? 'v1' : 'v0',
      snoozeMinutes,
      repeatCount,
      whenPart,
      hourPart,
      minutePart,
      weekdayPart,
    ].join('|');
  }

  String get logicalDeliveryFingerprint {
    final weekdayPart = weekdays.isEmpty ? '-' : weekdays.join(',');
    final whenPart = when?.toIso8601String() ?? '-';
    final hourPart = hour?.toString() ?? '-';
    final minutePart = minute?.toString() ?? '-';
    return [
      objectType,
      objectId,
      mode.name,
      scope,
      body,
      whenPart,
      hourPart,
      minutePart,
      weekdayPart,
    ].join('|');
  }
}

/// 根据 todo / habit / anniversary / goal 数据幂等地同步本地通知 / 闹钟队列。
///
/// 每次数据变化时由 `main.dart` 调用对应的 `syncXxx` 或 [resyncAll]。服务
/// 内部保证：
/// 1. 先取消自己管理过的 id（同时清理 push 与 alarm 两条通道，防止 `kind`
///    由 `push` 翻转到 `alarm` 时出现遗留调度）；
/// 2. 再按最新数据通过 [_dispatch] 路由到 `NotificationService`（push）或
///    `AlarmService`（alarm）重新下发。
///
/// R4.1 / R4.4 / R4.5 / R4.7 / R4.8：本类是协调器，职责严格与
/// `NotificationService` 和 `AlarmService` 分离；两者互不直接通话。
class ReminderScheduler {
  static const List<String> _registryObjectTypes = <String>[
    'todo',
    'goal',
    'habit',
    'anniversary',
    'countdown',
  ];

  final ReminderNotificationSink notif;
  final ReminderAlarmSink alarm;
  final ReminderEmailSink email;
  final ReminderPopupSink popup;
  final ReminderScheduleRegistry registry;

  /// 上一轮已下发的 todo / goal rule → 通道与调度形态。
  final Map<String, Map<String, _ScheduledRule>> _scheduledTodoRules = {};
  final Map<String, Map<String, _ScheduledRule>> _scheduledGoalRules = {};
  final Map<String, String> _scheduledHabitScopes = {};
  final Map<String, String> _scheduledAnniversaryScopes = {};
  final Map<String, String> _scheduledCountdownScopes = {};
  final Map<String, ReminderScheduleDisplayInfo> _registeredReminderDisplay =
      {};
  final Map<String, String> _todoScheduleFailures = <String, String>{};
  Future<void> _syncQueue = Future<void>.value();

  /// [notif] 必传；[alarm] 默认取 `AlarmService.instance` 单例，便于测试时
  /// 注入 fake。[popup] 未注入时默认落到 [notif] 作为系统通知兜底，避免
  /// popup 规则被空实现缓存为“已调度”。[email] 默认 no-op，未配置邮件
  /// 服务时不会误发本地通知。各通道均以 sink 接口表达，便于属性测试注入。
  ReminderScheduler(
    this.notif, {
    ReminderAlarmSink? alarm,
    ReminderEmailSink? email,
    ReminderPopupSink? popup,
    ReminderScheduleRegistry? registry,
  }) : alarm = alarm ?? AlarmService.instance,
       email = email ?? const NoopReminderEmailSink(),
       popup = popup ?? NotificationFallbackReminderPopupSink(notif),
       registry = registry ?? const SharedPreferencesReminderScheduleRegistry();

  @visibleForTesting
  int debugScheduledTodoRuleCount(String todoId) {
    return _scheduledTodoRules[todoId]?.length ?? 0;
  }

  Future<List<ReminderScheduleSnapshotEntry>> registeredRemindersSnapshot() {
    return _runSerialized(_registeredRemindersSnapshotLocked);
  }

  Future<List<ReminderScheduleSnapshotEntry>>
  _registeredRemindersSnapshotLocked() async {
    final result = <ReminderScheduleSnapshotEntry>[];
    for (final objectType in _registryObjectTypes) {
      final byObject = await registry.idsByObject(objectType);
      final persistedDisplays = await registry.displayByObject(objectType);
      for (final entry in byObject.entries) {
        final ids = entry.value.where((id) => id != 0).toList()..sort();
        if (ids.isEmpty) continue;
        final display = _snapshotDisplayFor(
          objectType,
          entry.key,
          persisted: persistedDisplays[entry.key],
        );
        result.add(
          ReminderScheduleSnapshotEntry(
            objectType: objectType,
            objectId: entry.key,
            ids: List<int>.unmodifiable(ids),
            title: display.title,
            subtitle: display.subtitle,
          ),
        );
      }
    }
    result.sort((a, b) {
      final typeCompare = _registryObjectTypes
          .indexOf(a.objectType)
          .compareTo(_registryObjectTypes.indexOf(b.objectType));
      if (typeCompare != 0) return typeCompare;
      return a.objectId.compareTo(b.objectId);
    });
    return List<ReminderScheduleSnapshotEntry>.unmodifiable(result);
  }

  ReminderScheduleDisplayInfo _snapshotDisplayFor(
    String objectType,
    String objectId, {
    ReminderScheduleDisplayInfo? persisted,
  }) {
    final stored = _registeredReminderDisplay['$objectType:$objectId'];
    if (stored != null) return stored;
    if (persisted != null) return persisted;
    final scheduledRules = switch (objectType) {
      'todo' => _scheduledTodoRules[objectId],
      'goal' => _scheduledGoalRules[objectId],
      _ => null,
    };
    if (scheduledRules != null && scheduledRules.isNotEmpty) {
      return _displayFromScheduledRules(objectType, scheduledRules.values);
    }
    final typeLabel = _objectTypeLabel(objectType);
    return ReminderScheduleDisplayInfo(
      title: '$typeLabel提醒',
      subtitle: '$typeLabel · 已登记到系统提醒队列',
    );
  }

  ReminderScheduleDisplayInfo _displayFromScheduledRules(
    String objectType,
    Iterable<_ScheduledRule> rules,
  ) {
    final list = rules.toList(growable: false);
    final typeLabel = _objectTypeLabel(objectType);
    final title = list
        .map((rule) => rule.body.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '$typeLabel提醒');
    final kinds = list.map((rule) => _kindLabel(rule.kind)).toSet().join('、');
    final repeating = list.any((rule) => rule.mode == _DispatchMode.repeating);
    final cadence = repeating ? '重复提醒' : '一次提醒';
    return ReminderScheduleDisplayInfo(
      title: title,
      subtitle:
          '$typeLabel · $cadence · ${kinds.isEmpty ? '系统提醒' : kinds} · ${list.length} 条规则',
    );
  }

  void _rememberReminderDisplay(
    String objectType,
    String objectId, {
    required String title,
    required String subtitle,
  }) {
    final trimmedTitle = title.trim();
    _registeredReminderDisplay['$objectType:$objectId'] =
        ReminderScheduleDisplayInfo(
          title: trimmedTitle.isEmpty
              ? '${_objectTypeLabel(objectType)}提醒'
              : trimmedTitle,
          subtitle: subtitle.trim().isEmpty
              ? '${_objectTypeLabel(objectType)} · 已登记到系统提醒队列'
              : subtitle.trim(),
        );
  }

  void _forgetReminderDisplay(String objectType, String objectId) {
    _registeredReminderDisplay.remove('$objectType:$objectId');
  }

  ReminderScheduleDisplayInfo? _registryDisplayFor(
    String objectType,
    String objectId, {
    Iterable<_ScheduledRule>? scheduledRules,
    Iterable<_ResolvedRule>? resolvedRules,
  }) {
    final stored = _registeredReminderDisplay['$objectType:$objectId'];
    if (stored != null) return stored;
    final scheduledList = scheduledRules?.toList(growable: false);
    if (scheduledList != null && scheduledList.isNotEmpty) {
      return _displayFromScheduledRules(objectType, scheduledList);
    }
    final resolvedList = resolvedRules?.toList(growable: false);
    if (resolvedList != null && resolvedList.isNotEmpty) {
      return _displayFromResolvedRules(objectType, resolvedList);
    }
    return null;
  }

  ReminderScheduleDisplayInfo _displayFromResolvedRules(
    String objectType,
    Iterable<_ResolvedRule> rules,
  ) {
    final list = rules.toList(growable: false);
    final typeLabel = _objectTypeLabel(objectType);
    final title = list
        .map((rule) => rule.body.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '$typeLabel提醒');
    final kinds = list.map((rule) => _kindLabel(rule.kind)).toSet().join('、');
    final repeating = list.any((rule) => rule.mode == _DispatchMode.repeating);
    final cadence = repeating ? '重复提醒' : '一次提醒';
    return ReminderScheduleDisplayInfo(
      title: title,
      subtitle:
          '$typeLabel · $cadence · ${kinds.isEmpty ? '系统提醒' : kinds} · ${list.length} 条规则',
    );
  }

  Future<void> _replaceRegistryObject(
    String objectType,
    String objectId,
    Set<int> ids, {
    Iterable<_ScheduledRule>? scheduledRules,
    Iterable<_ResolvedRule>? resolvedRules,
  }) {
    return registry.replaceObject(
      objectType,
      objectId,
      ids,
      display: _registryDisplayFor(
        objectType,
        objectId,
        scheduledRules: scheduledRules,
        resolvedRules: resolvedRules,
      ),
    );
  }

  String _objectTypeLabel(String objectType) {
    return switch (objectType) {
      'todo' => '待办',
      'goal' => '目标',
      'habit' => '日常',
      'anniversary' => '纪念日',
      'countdown' => '倒数日',
      _ => '事项',
    };
  }

  String _kindLabel(ReminderKind kind) {
    return switch (kind) {
      ReminderKind.push => '普通通知',
      ReminderKind.popup => '弹出提醒',
      ReminderKind.alarm => '闹钟提醒',
      ReminderKind.email => '邮件提醒',
      ReminderKind.off => '关闭',
    };
  }

  String _timeLabel(int? hour, int? minute) {
    if (!_validTime(hour, minute)) return '时间未设置';
    return '${hour!.toString().padLeft(2, '0')}:${minute!.toString().padLeft(2, '0')}';
  }

  String _weekdaysLabel(List<int> weekdays) {
    if (weekdays.isEmpty || weekdays.length == 7) return '每天';
    const labels = <int, String>{
      1: '周一',
      2: '周二',
      3: '周三',
      4: '周四',
      5: '周五',
      6: '周六',
      7: '周日',
    };
    return weekdays
        .map((day) => labels[day] ?? '')
        .where((v) => v.isNotEmpty)
        .join('、');
  }

  String _dateTimeLabel(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  void _rememberHabitReminderDisplay(Habit habit) {
    final rule = _effectiveHabitPlan(habit).primaryRule;
    if (rule == null) return;
    final weekdays = _habitWeekdays(habit, rule);
    _rememberReminderDisplay(
      'habit',
      habit.id,
      title: habit.name,
      subtitle:
          '日常 · ${_kindLabel(rule.kind)} · ${_weekdaysLabel(weekdays)} ${_timeLabel(rule.hour, rule.minute)}',
    );
  }

  void _rememberAnniversaryReminderDisplay(
    Anniversary item,
    DateTime remindAt,
  ) {
    _rememberReminderDisplay(
      'anniversary',
      item.id,
      title: item.title,
      subtitle:
          '纪念日 · ${_kindLabel(item.reminderKind)} · ${_dateTimeLabel(remindAt)}',
    );
  }

  void _rememberCountdownReminderDisplay(
    CountdownItem item,
    DateTime remindAt,
  ) {
    _rememberReminderDisplay(
      'countdown',
      item.id,
      title: item.title,
      subtitle:
          '倒数日 · ${_kindLabel(item.reminderKind)} · ${_dateTimeLabel(remindAt)}',
    );
  }

  /// Clears scheduler-owned in-memory state during account cleanup.
  ///
  /// Platform notifications and alarms may already have been removed by their
  /// services, but popup timers and this scheduler's rule cache live in memory.
  /// If they survive an account switch, a same-id/same-rule reminder from the
  /// next account can be treated as already scheduled, especially for popup
  /// reminders which do not expose a system pending queue.
  Future<void> resetInMemoryState() {
    return _runSerialized(_resetInMemoryStateLocked);
  }

  Future<void> _resetInMemoryStateLocked() async {
    for (final entry in _scheduledTodoRules.entries.toList()) {
      await _cancelRuleObjects('todo', entry.key, entry.value.keys);
      await _cancelTodoLegacy(entry.key);
      await registry.removeObject('todo', entry.key);
    }
    _scheduledTodoRules.clear();

    for (final entry in _scheduledGoalRules.entries.toList()) {
      await _cancelRuleObjects('goal', entry.key, entry.value.keys);
      await _cancelGoalLegacy(entry.key);
      await registry.removeObject('goal', entry.key);
    }
    _scheduledGoalRules.clear();

    for (final id in _scheduledHabitScopes.keys.toList()) {
      await _cancelHabit(id);
      await registry.removeObject('habit', id);
    }
    _scheduledHabitScopes.clear();

    for (final id in _scheduledAnniversaryScopes.keys.toList()) {
      await _cancelAnniversary(id);
      await registry.removeObject('anniversary', id);
    }
    _scheduledAnniversaryScopes.clear();

    for (final id in _scheduledCountdownScopes.keys.toList()) {
      await _cancelCountdown(id);
      await registry.removeObject('countdown', id);
    }
    _scheduledCountdownScopes.clear();
    _registeredReminderDisplay.clear();
  }

  // -------------------------------------------------------------------------
  // 公共 API
  // -------------------------------------------------------------------------

  /// 按最新的 [todos] 幂等地重新同步待办提醒。
  Future<void> syncTodos(
    Iterable<TodoItem> todos, {
    bool allowJustMissedOneShotReminders = true,
  }) async {
    final snapshot = todos.toList(growable: false);
    await _runSerialized(() async {
      _todoScheduleFailures.clear();
      await _syncTodosLocked(
        snapshot,
        allowJustMissedOneShotReminders: allowJustMissedOneShotReminders,
      );
    });
  }

  Future<String?> syncTodosAndGetTodoFailure(
    Iterable<TodoItem> todos,
    String todoId, {
    bool allowJustMissedOneShotReminders = true,
  }) async {
    final snapshot = todos.toList(growable: false);
    return _runSerialized(() async {
      _todoScheduleFailures.remove(todoId);
      await _syncTodosLocked(
        snapshot,
        allowJustMissedOneShotReminders: allowJustMissedOneShotReminders,
      );
      return _todoScheduleFailures[todoId];
    });
  }

  Future<void> _syncTodosLocked(
    Iterable<TodoItem> todos, {
    required bool allowJustMissedOneShotReminders,
  }) async {
    final todoSnapshot = todos.toList(growable: false);
    final wanted = <String, Map<String, _ResolvedRule>>{};
    for (final t in todoSnapshot) {
      if (t.isCompleted) {
        await _cancelCurrentTodoPlan(t);
        continue;
      }
      final resolved = _resolveTodoRules(
        t,
        allowJustMissedOneShotReminders: allowJustMissedOneShotReminders,
      );
      if (resolved.isEmpty) {
        _recordUnresolvedTodoReminderIssue(t);
        await _cancelCurrentTodoPlan(t);
        continue;
      }
      wanted[t.id] = {for (final rule in resolved) rule.ruleId: rule};
    }
    final blockedRegistryIds = await _sweepRuleRegistry(
      objectType: 'todo',
      wanted: wanted,
    );
    await _syncRuleObjects(
      objectType: 'todo',
      wanted: wanted,
      scheduled: _scheduledTodoRules,
      cancelLegacy: _cancelTodoLegacy,
      blockedRegistryIdsByObject: blockedRegistryIds,
    );
  }

  void _recordUnresolvedTodoReminderIssue(TodoItem todo) {
    final preflight = preflightTodoReminderPlan(todo);
    if (!preflight.hasEnabledPlan || preflight.ok) return;
    final blocking = preflight.blockingIssue;
    final issue =
        blocking ?? (preflight.issues.isEmpty ? null : preflight.issues.first);
    if (issue == null) return;
    _todoScheduleFailures[todo.id] = issue.message;
    final issueSink = notif is ReminderScheduleIssueSink
        ? notif as ReminderScheduleIssueSink
        : null;
    if (issueSink == null) return;
    issueSink.recordReminderScheduleIssue(
      title: issue.title,
      message: issue.message,
      scheduledTime: issue.scheduledTime,
      relatedId: todo.id,
      blocking: issue.blocking,
    );
  }

  void _recordAlarmScheduleIssue({
    required String relatedId,
    DateTime? scheduledTime,
    bool blocking = false,
  }) {
    final issueSink = notif is ReminderScheduleIssueSink
        ? notif as ReminderScheduleIssueSink
        : null;
    if (issueSink == null || alarm is! AlarmService) return;
    final issue = (alarm as AlarmService).lastScheduleIssue;
    if (issue == null) {
      final clearSink = notif is ReminderScheduleIssueClearSink
          ? notif as ReminderScheduleIssueClearSink
          : null;
      clearSink?.clearReminderScheduleIssue();
      return;
    }
    issueSink.recordReminderScheduleIssue(
      title: issue.title,
      message: issue.message,
      scheduledTime: issue.scheduledTime ?? scheduledTime,
      relatedId: relatedId,
      blocking: blocking,
    );
  }

  /// 按最新的 [habits] 幂等地重新同步习惯提醒。
  ///
  /// 习惯提醒按用户选择走通知、应用内弹窗或柔和强提醒闹钟。闹钟权限不足时
  /// 降级为普通 push，确保不会静默丢提醒。
  Future<void> syncHabits(Iterable<Habit> habits) async {
    final snapshot = habits.toList(growable: false);
    await _runSerialized(() => _syncHabitsLocked(snapshot));
  }

  Future<void> _syncHabitsLocked(Iterable<Habit> habits) async {
    final wanted = <String, Habit>{};
    final handledInactiveHabitIds = <String>{};
    for (final h in habits) {
      final plan = _effectiveHabitPlan(h);
      final rule = plan.primaryRule;
      if (!plan.enabled ||
          rule == null ||
          !rule.enabled ||
          rule.kind == ReminderKind.off) {
        handledInactiveHabitIds.add(h.id);
        // 多提醒时间习惯被关闭时，主 id 之外的派生 id 不在 wanted 内、也不会
        // 进入 sweep，需要在此显式清理，避免遗漏的提醒成为孤儿继续触发。
        final baseId = _idFor('habit_${h.id}');
        final storedIds =
            (await registry.idsByObject('habit'))[h.id] ?? const <int>{};
        final extraIds = storedIds.where((id) => id != baseId).toSet();
        final cancelled = await _cancelHabit(h.id);
        final extraCancelled = extraIds.isEmpty
            ? true
            : await _cancelIds('habit', h.id, extraIds, blocking: false);
        if (cancelled && extraCancelled) {
          _scheduledHabitScopes.remove(h.id);
          _forgetReminderDisplay('habit', h.id);
          await registry.removeObject('habit', h.id);
        }
        continue;
      }
      wanted[h.id] = h;
    }
    final scopes = <String, String>{};
    for (final h in wanted.values) {
      scopes[h.id] = _habitScope(h);
      _rememberHabitReminderDisplay(h);
    }
    final blockedHabitIdsFromRegistry = await _sweepSingleRegistry(
      objectType: 'habit',
      wantedIdsByObject: {
        for (final h in wanted.values) h.id: _habitRegistryIds(h),
      },
    );

    final blockedHabitIds = <String>{};
    for (final id in _scheduledHabitScopes.keys.toList()) {
      if (handledInactiveHabitIds.contains(id)) continue;
      final nextScope = scopes[id];
      if (nextScope == null || _scheduledHabitScopes[id] != nextScope) {
        final cancelled = await _cancelHabit(id);
        if (cancelled) {
          _scheduledHabitScopes.remove(id);
          _forgetReminderDisplay('habit', id);
          await registry.removeObject('habit', id);
        } else {
          blockedHabitIds.add(id);
        }
      }
    }
    for (final h in wanted.values) {
      if (blockedHabitIds.contains(h.id)) continue;
      if (!_scheduledHabitScopes.containsKey(h.id)) {
        final swept = await _cancelHabit(h.id);
        if (!swept) continue;
      }
      final scope = scopes[h.id]!;
      final blockedRegistryIds =
          blockedHabitIdsFromRegistry[h.id] ?? const <int>{};
      if (_scheduledHabitScopes[h.id] == scope) {
        if (await _habitStillPending(h)) {
          _rememberHabitReminderDisplay(h);
          await _replaceRegistryObject('habit', h.id, {
            ...blockedRegistryIds,
            ..._habitRegistryIds(h),
          });
          continue;
        }
        final cancelled = await _cancelHabit(h.id);
        if (!cancelled) continue;
        _scheduledHabitScopes.remove(h.id);
        _forgetReminderDisplay('habit', h.id);
        await registry.removeObject('habit', h.id);
      }
      final scheduled = await _scheduleHabit(h);
      if (scheduled) {
        _rememberHabitReminderDisplay(h);
        _scheduledHabitScopes[h.id] = scope;
      }
      // 即便部分规则调度失败（scheduled == false，scope 不落库以便下次重排），
      // 也要把这条习惯当前“应注册”的全部派生 id 写入 registry：否则已成功的
      // 那几条派生通知会成为不在册的孤儿，禁用习惯时只按 registry 清理就漏掉它们。
      if (scheduled || _habitRegistryIds(h).isNotEmpty) {
        await _replaceRegistryObject('habit', h.id, {
          ...blockedRegistryIds,
          ..._habitRegistryIds(h),
        });
      }
    }
  }

  /// 习惯当前生效（已启用、非 off）的全部提醒规则，支持多提醒时间。
  List<ReminderRule> _enabledHabitRules(Habit habit) {
    final plan = _effectiveHabitPlan(habit);
    if (!plan.enabled) return const <ReminderRule>[];
    return [
      for (final rule in plan.rules)
        if (rule.enabled && rule.kind != ReminderKind.off) rule,
    ];
  }

  /// 习惯某条提醒规则对应的系统通知基础 id。
  ///
  /// 第一条规则沿用历史 `habit_<id>`，保证既有单条提醒幂等；其余规则按规则
  /// 自身 id 派生独立基础 id，从而支持“每天 8 杯水”这类多提醒时间习惯。
  int _habitRuleId(String habitId, ReminderRule rule, int index) {
    if (index == 0) return _idFor('habit_$habitId');
    return _avoidReservedNotificationId(_idFor('habit_$habitId#${rule.id}'));
  }

  Future<bool> _scheduleHabit(Habit habit) async {
    final rules = _enabledHabitRules(habit);
    if (rules.isEmpty) return false;
    // 单条提醒沿用历史路径，避免触动既有幂等 / 取消语义与测试基线。
    if (rules.length == 1) {
      return _scheduleHabitRule(
        habit,
        rules.single,
        _idFor('habit_${habit.id}'),
        isPrimary: true,
      );
    }
    // 多条提醒逐条注册到独立 id；任一失败都视为整体未完成，交由上层重排兜底。
    var allOk = true;
    for (var i = 0; i < rules.length; i++) {
      final ok = await _scheduleHabitRule(
        habit,
        rules[i],
        _habitRuleId(habit.id, rules[i], i),
        isPrimary: i == 0,
      );
      allOk = allOk && ok;
    }
    return allOk;
  }

  Future<bool> _scheduleHabitRule(
    Habit habit,
    ReminderRule rule,
    int id, {
    required bool isPrimary,
  }) async {
    final hour = rule.hour;
    final minute = rule.minute;
    if (hour == null || minute == null) return false;
    final weekdays = _habitWeekdays(habit, rule);
    final payload = 'duoyi://habit/${habit.id}?confirm=1';
    final title = _habitTitle();
    final body = '${habit.name} 到时间了，点开确认打卡';

    switch (rule.kind) {
      case ReminderKind.push:
        return _scheduleHabitPush(
          habit,
          hour,
          minute,
          weekdays,
          explicitId: isPrimary ? null : id,
        );
      case ReminderKind.popup:
        try {
          await popup.scheduleRepeating(
            id: id,
            title: title,
            body: body,
            hour: hour,
            minute: minute,
            weekdays: weekdays.isEmpty ? null : weekdays,
            payload: payload,
          );
          return true;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] habit popup dispatch failed for ${habit.id}: $e\n$st',
          );
          return false;
        }
      case ReminderKind.alarm:
        try {
          await alarm.scheduleDailyFullScreen(
            id: id,
            title: title,
            body: body,
            hour: hour,
            minute: minute,
            weekdays: weekdays.isEmpty ? null : weekdays,
            payload: payload,
            fullScreen: rule.fullScreen,
            vibrate: rule.vibrate,
            snoozeMinutes: rule.snoozeMinutes,
            repeatCount: rule.repeatCount,
          );
          _recordAlarmScheduleIssue(relatedId: habit.id);
          return true;
        } on AlarmPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] habit alarm permission denied for ${habit.id}: $e',
          );
          if (await _alarmQueueAlreadyOwns(
            label: 'habit:${habit.id}',
            expected: _expectedRepeatingPendingIds(id, weekdays),
            acceptedExpectedSets: _acceptedRepeatingPendingIdSets(
              kind: ReminderKind.alarm,
              base: id,
              weekdays: weekdays,
            ),
          )) {
            _recordAlarmScheduleIssue(relatedId: habit.id);
            return true;
          }
          final fallbackScheduled = await _scheduleHabitPush(
            habit,
            hour,
            minute,
            weekdays,
            explicitId: isPrimary ? null : id,
          );
          _recordAlarmScheduleIssue(
            relatedId: habit.id,
            blocking: !fallbackScheduled,
          );
          return fallbackScheduled;
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] habit alarm notification permission denied for ${habit.id}: $e',
          );
          if (await _alarmQueueAlreadyOwns(
            label: 'habit:${habit.id}',
            expected: _expectedRepeatingPendingIds(id, weekdays),
            acceptedExpectedSets: _acceptedRepeatingPendingIdSets(
              kind: ReminderKind.alarm,
              base: id,
              weekdays: weekdays,
            ),
          )) {
            _recordAlarmScheduleIssue(relatedId: habit.id);
            return true;
          }
          final fallbackScheduled = await _scheduleHabitPush(
            habit,
            hour,
            minute,
            weekdays,
            explicitId: isPrimary ? null : id,
          );
          _recordAlarmScheduleIssue(
            relatedId: habit.id,
            blocking: !fallbackScheduled,
          );
          return fallbackScheduled;
        } on AlarmQueueHandoffException catch (e) {
          debugPrint(
            '[ReminderScheduler] habit alarm queue handoff failed for ${habit.id}: $e',
          );
          _recordAlarmScheduleIssue(relatedId: habit.id, blocking: true);
          return false;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] habit alarm dispatch failed for ${habit.id}: $e\n$st',
          );
          if (await _alarmQueueAlreadyOwns(
            label: 'habit:${habit.id}',
            expected: _expectedRepeatingPendingIds(id, weekdays),
            acceptedExpectedSets: _acceptedRepeatingPendingIdSets(
              kind: ReminderKind.alarm,
              base: id,
              weekdays: weekdays,
            ),
          )) {
            _recordAlarmScheduleIssue(relatedId: habit.id);
            return true;
          }
          final fallbackScheduled = await _scheduleHabitPush(
            habit,
            hour,
            minute,
            weekdays,
            explicitId: isPrimary ? null : id,
          );
          _recordAlarmScheduleIssue(
            relatedId: habit.id,
            blocking: !fallbackScheduled,
          );
          return fallbackScheduled;
        }
      case ReminderKind.email:
      case ReminderKind.off:
        return false;
    }
  }

  Future<bool> _scheduleHabitPush(
    Habit habit,
    int hour,
    int minute,
    List<int> weekdays, {
    int? explicitId,
  }) async {
    try {
      if (explicitId == null) {
        await notif.scheduleHabitReminder(
          habitId: habit.id,
          habitName: habit.name,
          hour: hour,
          minute: minute,
          weekdays: weekdays.isEmpty ? null : weekdays,
        );
      } else {
        // 多提醒时间的非首条规则走通用 push 出口，使用独立 id 以免互相覆盖。
        await notif.scheduleDaily(
          id: explicitId,
          title: _habitTitle(),
          body: '${habit.name} 到时间了，点开确认打卡',
          hour: hour,
          minute: minute,
          weekdays: weekdays.isEmpty ? null : weekdays,
          payload: 'duoyi://habit/${habit.id}?confirm=1',
        );
      }
      return true;
    } on NotificationPermissionDeniedException catch (fallbackError) {
      debugPrint(
        '[ReminderScheduler] habit notification permission denied for ${habit.id}: $fallbackError',
      );
      return false;
    } catch (fallbackError, st) {
      debugPrint(
        '[ReminderScheduler] habit notification dispatch failed for ${habit.id}: $fallbackError\n$st',
      );
      return false;
    }
  }

  Future<bool> _cancelHabit(String habitId) async {
    final id = _idFor('habit_$habitId');
    var ok = true;
    ok =
        await _cancelSafely(
          'habit notification:$habitId',
          () => notif.cancelHabitReminder(habitId),
        ) &&
        ok;
    ok =
        await _cancelSafely('habit alarm:$habitId', () => alarm.cancel(id)) &&
        ok;
    ok =
        await _cancelSafely('habit popup:$habitId', () => popup.cancel(id)) &&
        ok;
    ok = await _cancelEmail(id, 'habit:$habitId') && ok;
    return ok;
  }

  Future<bool> _scheduleAnniversaryPushFallback(Anniversary item) async {
    try {
      await notif.scheduleAnniversary(
        annId: item.id,
        title: item.title,
        whenDate: item.nextOccurrence,
        daysBefore: item.remindDaysBefore,
        hour: item.remindHour,
        minute: item.remindMinute,
      );
      return true;
    } on NotificationPermissionDeniedException catch (fallbackError) {
      debugPrint(
        '[ReminderScheduler] anniversary fallback notification permission denied for ${item.id}: $fallbackError',
      );
      return false;
    } catch (fallbackError, st) {
      debugPrint(
        '[ReminderScheduler] anniversary fallback notification dispatch failed for ${item.id}: $fallbackError\n$st',
      );
      return false;
    }
  }

  /// 按最新的纪念日 [items] 幂等地重新同步提醒。
  ///
  /// 纪念日提醒按 `reminderKind` 路由到通知、弹出框、闹钟或关闭；闹钟权限
  /// 不足时自动降级为 push。
  Future<void> syncAnniversaries(Iterable<Anniversary> items) async {
    final snapshot = items.toList(growable: false);
    await _runSerialized(() => _syncAnniversariesLocked(snapshot));
  }

  Future<void> _syncAnniversariesLocked(Iterable<Anniversary> items) async {
    final wanted = <String, Anniversary>{};
    for (final a in items) {
      if (!a.remind) {
        await _cancelAnniversary(a.id);
        _forgetReminderDisplay('anniversary', a.id);
        await registry.removeObject('anniversary', a.id);
        continue;
      }
      final nextDate = a.nextOccurrence;
      final today = AppClock.today();
      if (nextDate.isBefore(DateTime(today.year, today.month, today.day - 1))) {
        await _cancelAnniversary(a.id);
        _forgetReminderDisplay('anniversary', a.id);
        await registry.removeObject('anniversary', a.id);
        continue;
      }
      if (a.reminderKind == ReminderKind.off) {
        await _cancelAnniversary(a.id);
        _forgetReminderDisplay('anniversary', a.id);
        await registry.removeObject('anniversary', a.id);
        continue;
      }
      wanted[a.id] = a;
    }
    final scopes = <String, String>{};
    for (final a in wanted.values) {
      final remindAt = rollAnniversaryRemindAtForward(
        _anniversaryReminderAt(a),
        AppClock.now(),
      );
      if (!remindAt.isAfter(AppClock.now())) continue;
      scopes[a.id] = _anniversaryScope(a, remindAt);
      _rememberAnniversaryReminderDisplay(a, remindAt);
    }
    final blockedAnniversaryIdsFromRegistry = await _sweepSingleRegistry(
      objectType: 'anniversary',
      wantedIdsByObject: {
        for (final a in wanted.values) a.id: _anniversaryRegistryIds(a),
      },
    );

    final blockedAnniversaryIds = <String>{};
    for (final id in _scheduledAnniversaryScopes.keys.toList()) {
      final nextScope = scopes[id];
      if (nextScope == null || _scheduledAnniversaryScopes[id] != nextScope) {
        final cancelled = await _cancelAnniversary(id);
        if (cancelled) {
          _scheduledAnniversaryScopes.remove(id);
          _forgetReminderDisplay('anniversary', id);
          await registry.removeObject('anniversary', id);
        } else {
          blockedAnniversaryIds.add(id);
        }
      }
    }

    for (final a in wanted.values) {
      if (blockedAnniversaryIds.contains(a.id)) continue;
      if (!_scheduledAnniversaryScopes.containsKey(a.id)) {
        final swept = await _cancelAnniversary(a.id);
        if (!swept) continue;
      }
      // 周年提醒时刻已过（打开 app 时当年的提醒时刻已经过去）时，
      // 推进到下一年同一时刻再注册，避免该周年被跳过后整年漏提醒。
      final remindAt = rollAnniversaryRemindAtForward(
        _anniversaryReminderAt(a),
        AppClock.now(),
      );
      if (!remindAt.isAfter(AppClock.now())) {
        continue;
      }
      final scope = scopes[a.id]!;
      final blockedRegistryIds =
          blockedAnniversaryIdsFromRegistry[a.id] ?? const <int>{};
      if (_scheduledAnniversaryScopes[a.id] == scope) {
        if (await _anniversaryStillPending(a)) {
          _rememberAnniversaryReminderDisplay(a, remindAt);
          await _replaceRegistryObject('anniversary', a.id, {
            ...blockedRegistryIds,
            ..._anniversaryRegistryIds(a),
          });
          continue;
        }
        final cancelled = await _cancelAnniversary(a.id);
        if (!cancelled) continue;
        _scheduledAnniversaryScopes.remove(a.id);
        _forgetReminderDisplay('anniversary', a.id);
        await registry.removeObject('anniversary', a.id);
      }

      final scheduled = await _dispatchAnniversary(a, remindAt);
      if (scheduled) {
        _rememberAnniversaryReminderDisplay(a, remindAt);
        _scheduledAnniversaryScopes[a.id] = scope;
        await _replaceRegistryObject('anniversary', a.id, {
          ...blockedRegistryIds,
          ..._anniversaryRegistryIds(a),
        });
      }
    }
  }

  /// 按最新的倒数日 [items] 幂等地同步到期提醒。
  Future<void> syncCountdowns(Iterable<CountdownItem> items) async {
    final snapshot = items.toList(growable: false);
    await _runSerialized(() => _syncCountdownsLocked(snapshot));
  }

  Future<void> _syncCountdownsLocked(Iterable<CountdownItem> items) async {
    final now = AppClock.now();
    final wanted = <String, CountdownItem>{};
    final scopes = <String, String>{};
    for (final item in items) {
      if (!item.remind || item.reminderKind == ReminderKind.off) {
        await _cancelCountdown(item.id);
        _forgetReminderDisplay('countdown', item.id);
        await registry.removeObject('countdown', item.id);
        continue;
      }
      final when = _countdownReminderAt(item);
      if (!when.isAfter(now)) {
        await _cancelCountdown(item.id);
        _forgetReminderDisplay('countdown', item.id);
        await registry.removeObject('countdown', item.id);
        continue;
      }
      wanted[item.id] = item;
      scopes[item.id] = _countdownScope(item, when);
      _rememberCountdownReminderDisplay(item, when);
    }
    final blockedCountdownIdsFromRegistry = await _sweepSingleRegistry(
      objectType: 'countdown',
      wantedIdsByObject: {
        for (final item in wanted.values) item.id: _countdownRegistryIds(item),
      },
    );

    final blockedCountdownIds = <String>{};
    for (final id in _scheduledCountdownScopes.keys.toList()) {
      final nextScope = scopes[id];
      if (nextScope == null || _scheduledCountdownScopes[id] != nextScope) {
        final cancelled = await _cancelCountdown(id);
        if (cancelled) {
          _scheduledCountdownScopes.remove(id);
          _forgetReminderDisplay('countdown', id);
          await registry.removeObject('countdown', id);
        } else {
          blockedCountdownIds.add(id);
        }
      }
    }

    for (final item in wanted.values) {
      if (blockedCountdownIds.contains(item.id)) continue;
      if (!_scheduledCountdownScopes.containsKey(item.id)) {
        final swept = await _cancelCountdown(item.id);
        if (!swept) continue;
      }
      final scope = scopes[item.id]!;
      final blockedRegistryIds =
          blockedCountdownIdsFromRegistry[item.id] ?? const <int>{};
      if (_scheduledCountdownScopes[item.id] == scope) {
        if (await _countdownStillPending(item)) {
          _rememberCountdownReminderDisplay(item, _countdownReminderAt(item));
          await _replaceRegistryObject('countdown', item.id, {
            ...blockedRegistryIds,
            ..._countdownRegistryIds(item),
          });
          continue;
        }
        final cancelled = await _cancelCountdown(item.id);
        if (!cancelled) continue;
        _scheduledCountdownScopes.remove(item.id);
        _forgetReminderDisplay('countdown', item.id);
        await registry.removeObject('countdown', item.id);
      }
      final when = _countdownReminderAt(item);
      final scheduled = await _dispatch(
        kind: item.reminderKind,
        payload: _DispatchPayload(
          id: _idFor('countdown:${item.id}:due'),
          title: '🔔 倒数日提醒',
          body:
              '${item.title} · ${item.daysRemaining >= 0 ? '还有 ${item.daysRemaining} 天' : '已过 ${-item.daysRemaining} 天'}',
          when: when,
          payload: 'duoyi://countdown/${item.id}',
          fullScreen: item.reminderKind == ReminderKind.alarm,
        ),
      );
      if (scheduled) {
        _rememberCountdownReminderDisplay(item, when);
        _scheduledCountdownScopes[item.id] = scope;
        await _replaceRegistryObject('countdown', item.id, {
          ...blockedRegistryIds,
          ..._countdownRegistryIds(item),
        });
      }
    }
  }

  /// 按最新的 [goals] 幂等地重新同步目标提醒（支持多 rule）。
  Future<void> syncGoals(Iterable<GoalItem> goals) async {
    final snapshot = goals.toList(growable: false);
    await _runSerialized(() => _syncGoalsLocked(snapshot));
  }

  Future<void> _syncGoalsLocked(Iterable<GoalItem> goals) async {
    final wanted = <String, Map<String, _ResolvedRule>>{};
    for (final g in goals) {
      if (g.status != GoalStatus.active) {
        await _cancelCurrentGoalPlan(g);
        continue;
      }
      final resolved = _resolveGoalRules(g);
      if (resolved.isEmpty) {
        await _cancelCurrentGoalPlan(g);
        continue;
      }
      wanted[g.id] = {for (final rule in resolved) rule.ruleId: rule};
    }
    final blockedRegistryIds = await _sweepRuleRegistry(
      objectType: 'goal',
      wanted: wanted,
    );
    await _syncRuleObjects(
      objectType: 'goal',
      wanted: wanted,
      scheduled: _scheduledGoalRules,
      cancelLegacy: _cancelGoalLegacy,
      blockedRegistryIdsByObject: blockedRegistryIds,
    );
  }

  /// 时区变化、权限变化、应用冷启动时整轮重放（R4.7）。
  Future<void> resyncAll({
    required Iterable<TodoItem> todos,
    required Iterable<Habit> habits,
    required Iterable<Anniversary> annis,
    required Iterable<GoalItem> goals,
    Iterable<CountdownItem> countdowns = const <CountdownItem>[],
  }) async {
    final todoSnapshot = todos.toList(growable: false);
    final habitSnapshot = habits.toList(growable: false);
    final anniversarySnapshot = annis.toList(growable: false);
    final goalSnapshot = goals.toList(growable: false);
    final countdownSnapshot = countdowns.toList(growable: false);
    await _runSerialized(
      () => _resyncAllLocked(
        todos: todoSnapshot,
        habits: habitSnapshot,
        annis: anniversarySnapshot,
        goals: goalSnapshot,
        countdowns: countdownSnapshot,
      ),
    );
  }

  Future<void> _resyncAllLocked({
    required Iterable<TodoItem> todos,
    required Iterable<Habit> habits,
    required Iterable<Anniversary> annis,
    required Iterable<GoalItem> goals,
    required Iterable<CountdownItem> countdowns,
  }) async {
    for (final id in _scheduledTodoRules.keys.toList()) {
      final rulesCancelled = await _cancelRuleObjects(
        'todo',
        id,
        _scheduledTodoRules[id]!.keys,
      );
      final legacyCancelled = await _cancelTodoLegacy(id);
      if (rulesCancelled && legacyCancelled) {
        _scheduledTodoRules.remove(id);
        await registry.removeObject('todo', id);
      }
    }
    for (final id in _scheduledGoalRules.keys.toList()) {
      final rulesCancelled = await _cancelRuleObjects(
        'goal',
        id,
        _scheduledGoalRules[id]!.keys,
      );
      final legacyCancelled = await _cancelGoalLegacy(id);
      if (rulesCancelled && legacyCancelled) {
        _scheduledGoalRules.remove(id);
        await registry.removeObject('goal', id);
      }
    }
    for (final id in _scheduledHabitScopes.keys.toList()) {
      if (await _cancelHabit(id)) {
        _scheduledHabitScopes.remove(id);
        await registry.removeObject('habit', id);
      }
    }
    for (final id in _scheduledAnniversaryScopes.keys.toList()) {
      if (await _cancelAnniversary(id)) {
        _scheduledAnniversaryScopes.remove(id);
        await registry.removeObject('anniversary', id);
      }
    }
    for (final id in _scheduledCountdownScopes.keys.toList()) {
      if (await _cancelCountdown(id)) {
        _scheduledCountdownScopes.remove(id);
        await registry.removeObject('countdown', id);
      }
    }

    await _syncTodosLocked(todos, allowJustMissedOneShotReminders: false);
    await _syncHabitsLocked(habits);
    await _syncAnniversariesLocked(annis);
    await _syncGoalsLocked(goals);
    await _syncCountdownsLocked(countdowns);
  }

  Future<T> _runSerialized<T>(Future<T> Function() action) {
    final run = _syncQueue.then((_) => action());
    _syncQueue = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  // -------------------------------------------------------------------------
  // 内部：通道路由
  // -------------------------------------------------------------------------

  /// 按 [kind] 路由到 push、alarm 或 email。权限不足时记录并返回 false，
  /// 避免 ChangeNotifier 监听回调里出现未处理异步异常。
  void _recordDispatchIssue(
    _DispatchPayload payload,
    Object error, {
    required bool blocking,
  }) {
    final relatedId =
        _relatedIdFromPayload(payload.payload) ?? payload.id.toString();
    if (payload.payload?.startsWith('duoyi://todo/') == true) {
      _todoScheduleFailures[relatedId] = error.toString();
    }
    final issueSink = notif is ReminderScheduleIssueSink
        ? notif as ReminderScheduleIssueSink
        : null;
    issueSink?.recordReminderScheduleIssue(
      title: '提醒注册失败',
      message: '提醒已保存，但未能注册到系统：$error',
      scheduledTime: payload.when,
      relatedId: relatedId,
      blocking: blocking,
    );
  }

  void _recordTodoRuleDispatchFailure(_ResolvedRule rule) {
    if (rule.objectType != 'todo' ||
        _todoScheduleFailures.containsKey(rule.objectId)) {
      return;
    }
    const message = '提醒调度器未能确认规则已注册到系统';
    _todoScheduleFailures[rule.objectId] = message;
    final issueSink = notif is ReminderScheduleIssueSink
        ? notif as ReminderScheduleIssueSink
        : null;
    issueSink?.recordReminderScheduleIssue(
      title: '提醒注册失败',
      message: message,
      scheduledTime: rule.when,
      relatedId: rule.objectId,
    );
  }

  String? _relatedIdFromPayload(String? payload) {
    final uri = payload == null ? null : Uri.tryParse(payload);
    if (uri == null || uri.pathSegments.isEmpty) return null;
    return uri.pathSegments.first == 'todo' && uri.pathSegments.length > 1
        ? uri.pathSegments[1]
        : uri.pathSegments.first;
  }

  Future<bool> _schedulePushOnceWithResult({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async {
    final notification = notif;
    final resultSink = notification is ReminderNotificationScheduleResultSink
        ? notification as ReminderNotificationScheduleResultSink
        : null;
    if (resultSink != null) {
      final scheduled = await resultSink.scheduleOnceWithResult(
        id: id,
        title: title,
        body: body,
        when: when,
        payload: payload,
      );
      if (!scheduled) {
        _recordDispatchIssue(
          _DispatchPayload(
            id: id,
            title: title,
            body: body,
            when: when,
            payload: payload,
          ),
          StateError('系统通知服务返回未注册'),
          blocking: true,
        );
      }
      return scheduled;
    }
    try {
      await notification.scheduleOnce(
        id: id,
        title: title,
        body: body,
        when: when,
        payload: payload,
      );
      return true;
    } on NotificationPermissionDeniedException catch (error) {
      _recordDispatchIssue(
        _DispatchPayload(
          id: id,
          title: title,
          body: body,
          when: when,
          payload: payload,
        ),
        error,
        blocking: true,
      );
      return false;
    } catch (error, stackTrace) {
      debugPrint(
        '[ReminderScheduler] notification scheduling failed: $error\n$stackTrace',
      );
      _recordDispatchIssue(
        _DispatchPayload(
          id: id,
          title: title,
          body: body,
          when: when,
          payload: payload,
        ),
        error,
        blocking: true,
      );
      return false;
    }
  }

  Future<bool> _schedulePushDailyWithResult({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async {
    final notification = notif;
    final resultSink = notification is ReminderNotificationScheduleResultSink
        ? notification as ReminderNotificationScheduleResultSink
        : null;
    if (resultSink != null) {
      final scheduled = await resultSink.scheduleDailyWithResult(
        id: id,
        title: title,
        body: body,
        hour: hour,
        minute: minute,
        weekdays: weekdays,
        payload: payload,
      );
      if (!scheduled) {
        _recordDispatchIssue(
          _DispatchPayload(
            id: id,
            title: title,
            body: body,
            when: DateTime.now(),
            payload: payload,
          ),
          StateError('系统重复通知服务返回未注册'),
          blocking: true,
        );
      }
      return scheduled;
    }
    try {
      await notification.scheduleDaily(
        id: id,
        title: title,
        body: body,
        hour: hour,
        minute: minute,
        weekdays: weekdays,
        payload: payload,
      );
      return true;
    } on NotificationPermissionDeniedException catch (error) {
      _recordDispatchIssue(
        _DispatchPayload(
          id: id,
          title: title,
          body: body,
          when: DateTime.now(),
          payload: payload,
        ),
        error,
        blocking: true,
      );
      return false;
    } catch (error, stackTrace) {
      debugPrint(
        '[ReminderScheduler] daily notification scheduling failed: $error\n$stackTrace',
      );
      _recordDispatchIssue(
        _DispatchPayload(
          id: id,
          title: title,
          body: body,
          when: DateTime.now(),
          payload: payload,
        ),
        error,
        blocking: true,
      );
      return false;
    }
  }

  Future<bool> _dispatch({
    required ReminderKind kind,
    required _DispatchPayload payload,
  }) async {
    switch (kind) {
      case ReminderKind.popup:
        try {
          await popup.scheduleOnce(
            id: payload.id,
            title: payload.title,
            body: payload.body,
            when: payload.when,
            payload: payload.payload,
          );
          return true;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] popup dispatch failed for ${payload.id}: $e\n$st',
          );
          _recordDispatchIssue(payload, e, blocking: true);
          return false;
        }
      case ReminderKind.push:
        try {
          return await _schedulePushOnceWithResult(
            id: payload.id,
            title: payload.title,
            body: payload.body,
            when: payload.when,
            payload: payload.payload,
          );
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] push notification permission denied for ${payload.id}: $e',
          );
          _recordDispatchIssue(payload, e, blocking: true);
          return false;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] push notification dispatch failed for ${payload.id}: $e\n$st',
          );
          _recordDispatchIssue(payload, e, blocking: true);
          return false;
        }
      case ReminderKind.alarm:
        try {
          await alarm.scheduleFullScreen(
            id: payload.id,
            title: payload.title,
            body: payload.body,
            when: payload.when,
            payload: payload.payload,
            fullScreen: payload.fullScreen,
            vibrate: payload.vibrate,
            snoozeMinutes: payload.snoozeMinutes,
            repeatCount: payload.repeatCount,
          );
          _recordAlarmScheduleIssue(
            relatedId: payload.payload ?? payload.id.toString(),
            scheduledTime: payload.when,
          );
          return true;
        } on AlarmPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] alarm permission denied for ${payload.id}: $e',
          );
          if (await _alarmQueueAlreadyOwns(
            label: 'once:${payload.id}',
            expected: <int>{payload.id},
          )) {
            _recordAlarmScheduleIssue(
              relatedId: payload.payload ?? payload.id.toString(),
              scheduledTime: payload.when,
            );
            return true;
          }
          try {
            await notif.scheduleOnce(
              id: payload.id,
              title: payload.title,
              body: payload.body,
              when: payload.when,
              payload: _fallbackPayload(payload.payload),
            );
            _recordAlarmScheduleIssue(
              relatedId: payload.payload ?? payload.id.toString(),
              scheduledTime: payload.when,
            );
            return true;
          } on NotificationPermissionDeniedException catch (fallbackError) {
            debugPrint(
              '[ReminderScheduler] alarm fallback notification permission denied for ${payload.id}: $fallbackError',
            );
            _recordAlarmScheduleIssue(
              relatedId: payload.payload ?? payload.id.toString(),
              scheduledTime: payload.when,
              blocking: true,
            );
            return false;
          } catch (fallbackError, fallbackStack) {
            debugPrint(
              '[ReminderScheduler] alarm fallback notification dispatch failed for ${payload.id}: $fallbackError\n$fallbackStack',
            );
            _recordAlarmScheduleIssue(
              relatedId: payload.payload ?? payload.id.toString(),
              scheduledTime: payload.when,
              blocking: true,
            );
            return false;
          }
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] alarm notification permission denied for ${payload.id}: $e',
          );
          if (await _alarmQueueAlreadyOwns(
            label: 'once:${payload.id}',
            expected: <int>{payload.id},
          )) {
            _recordAlarmScheduleIssue(
              relatedId: payload.payload ?? payload.id.toString(),
              scheduledTime: payload.when,
            );
            return true;
          }
          _recordAlarmScheduleIssue(
            relatedId: payload.payload ?? payload.id.toString(),
            scheduledTime: payload.when,
            blocking: true,
          );
          return false;
        } on AlarmQueueHandoffException catch (e) {
          debugPrint(
            '[ReminderScheduler] alarm queue handoff failed for ${payload.id}: $e',
          );
          _recordAlarmScheduleIssue(
            relatedId: payload.payload ?? payload.id.toString(),
            scheduledTime: payload.when,
            blocking: true,
          );
          return false;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] alarm dispatch failed for ${payload.id}: $e\n$st',
          );
          if (await _alarmQueueAlreadyOwns(
            label: 'once:${payload.id}',
            expected: <int>{payload.id},
          )) {
            _recordAlarmScheduleIssue(
              relatedId: payload.payload ?? payload.id.toString(),
              scheduledTime: payload.when,
            );
            return true;
          }
          try {
            await notif.scheduleOnce(
              id: payload.id,
              title: payload.title,
              body: payload.body,
              when: payload.when,
              payload: _fallbackPayload(payload.payload),
            );
            _recordAlarmScheduleIssue(
              relatedId: payload.payload ?? payload.id.toString(),
              scheduledTime: payload.when,
            );
            return true;
          } on NotificationPermissionDeniedException catch (fallbackError) {
            debugPrint(
              '[ReminderScheduler] alarm fallback notification permission denied for ${payload.id}: $fallbackError',
            );
            _recordAlarmScheduleIssue(
              relatedId: payload.payload ?? payload.id.toString(),
              scheduledTime: payload.when,
              blocking: true,
            );
            return false;
          } catch (fallbackError, fallbackStack) {
            debugPrint(
              '[ReminderScheduler] alarm fallback notification dispatch failed for ${payload.id}: $fallbackError\n$fallbackStack',
            );
            _recordAlarmScheduleIssue(
              relatedId: payload.payload ?? payload.id.toString(),
              scheduledTime: payload.when,
              blocking: true,
            );
            return false;
          }
        }
      case ReminderKind.email:
        try {
          await email.scheduleOnce(
            id: payload.id,
            title: payload.title,
            body: payload.body,
            when: payload.when,
            payload: payload.payload,
          );
          return true;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] email dispatch failed for ${payload.id}: $e\n$st',
          );
          return false;
        }
      case ReminderKind.off:
        return false;
    }
  }

  Future<bool> _dispatchRepeating(_ResolvedRule rule) async {
    switch (rule.kind) {
      case ReminderKind.popup:
        try {
          await popup.scheduleRepeating(
            id: _idFor(rule.key),
            title: rule.title,
            body: rule.body,
            hour: rule.hour!,
            minute: rule.minute!,
            weekdays: rule.weekdays.isEmpty ? null : rule.weekdays,
            payload: rule.payload,
          );
          return true;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] repeating popup dispatch failed for ${rule.key}: $e\n$st',
          );
          return false;
        }
      case ReminderKind.push:
        try {
          return await _schedulePushDailyWithResult(
            id: _idFor(rule.key),
            title: rule.title,
            body: rule.body,
            hour: rule.hour!,
            minute: rule.minute!,
            weekdays: rule.weekdays.isEmpty ? null : rule.weekdays,
            payload: rule.payload,
          );
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] repeating push permission denied for ${rule.key}: $e',
          );
          return false;
        }
      case ReminderKind.alarm:
        try {
          await alarm.scheduleDailyFullScreen(
            id: _idFor(rule.key),
            title: rule.title,
            body: rule.body,
            hour: rule.hour!,
            minute: rule.minute!,
            weekdays: rule.weekdays.isEmpty ? null : rule.weekdays,
            payload: rule.payload,
            fullScreen: rule.fullScreen,
            vibrate: rule.vibrate,
            snoozeMinutes: rule.snoozeMinutes,
            repeatCount: rule.repeatCount,
          );
          _recordAlarmScheduleIssue(relatedId: rule.key);
          return true;
        } on AlarmPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] alarm permission denied for ${rule.key}: $e',
          );
          if (await _alarmQueueAlreadyOwns(
            label: rule.key,
            expected: _expectedPendingIdsForRule(rule),
            acceptedExpectedSets: _acceptedPendingIdSetsForRule(rule),
          )) {
            _recordAlarmScheduleIssue(relatedId: rule.key);
            return true;
          }
          try {
            await notif.scheduleDaily(
              id: _idFor(rule.key),
              title: rule.title,
              body: rule.body,
              hour: rule.hour!,
              minute: rule.minute!,
              weekdays: rule.weekdays.isEmpty ? null : rule.weekdays,
              payload: _fallbackPayload(rule.payload),
            );
            _recordAlarmScheduleIssue(relatedId: rule.key);
            return true;
          } on NotificationPermissionDeniedException catch (fallbackError) {
            debugPrint(
              '[ReminderScheduler] repeating alarm fallback permission denied for ${rule.key}: $fallbackError',
            );
            _recordAlarmScheduleIssue(relatedId: rule.key, blocking: true);
            return false;
          } catch (fallbackError, fallbackStack) {
            debugPrint(
              '[ReminderScheduler] repeating alarm fallback dispatch failed for ${rule.key}: $fallbackError\n$fallbackStack',
            );
            _recordAlarmScheduleIssue(relatedId: rule.key, blocking: true);
            return false;
          }
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] alarm notification permission denied for ${rule.key}: $e',
          );
          if (await _alarmQueueAlreadyOwns(
            label: rule.key,
            expected: _expectedPendingIdsForRule(rule),
            acceptedExpectedSets: _acceptedPendingIdSetsForRule(rule),
          )) {
            _recordAlarmScheduleIssue(relatedId: rule.key);
            return true;
          }
          _recordAlarmScheduleIssue(relatedId: rule.key, blocking: true);
          return false;
        } on AlarmQueueHandoffException catch (e) {
          debugPrint(
            '[ReminderScheduler] repeating alarm queue handoff failed for ${rule.key}: $e',
          );
          _recordAlarmScheduleIssue(relatedId: rule.key, blocking: true);
          return false;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] repeating alarm dispatch failed for ${rule.key}: $e\n$st',
          );
          final id = _idFor(rule.key);
          if (await _alarmQueueAlreadyOwns(
            label: rule.key,
            expected: _expectedPendingIdsForRule(rule),
            acceptedExpectedSets: _acceptedPendingIdSetsForRule(rule),
          )) {
            _recordAlarmScheduleIssue(relatedId: rule.key);
            return true;
          }
          try {
            await notif.scheduleDaily(
              id: id,
              title: rule.title,
              body: rule.body,
              hour: rule.hour!,
              minute: rule.minute!,
              weekdays: rule.weekdays.isEmpty ? null : rule.weekdays,
              payload: _fallbackPayload(rule.payload),
            );
            _recordAlarmScheduleIssue(relatedId: rule.key);
            return true;
          } on NotificationPermissionDeniedException catch (fallbackError) {
            debugPrint(
              '[ReminderScheduler] repeating alarm fallback permission denied for ${rule.key}: $fallbackError',
            );
            _recordAlarmScheduleIssue(relatedId: rule.key, blocking: true);
            return false;
          } catch (fallbackError, fallbackStack) {
            debugPrint(
              '[ReminderScheduler] repeating alarm fallback dispatch failed for ${rule.key}: $fallbackError\n$fallbackStack',
            );
            _recordAlarmScheduleIssue(relatedId: rule.key, blocking: true);
            return false;
          }
        }
      case ReminderKind.email:
        try {
          await email.scheduleRepeating(
            id: _idFor(rule.key),
            title: rule.title,
            body: rule.body,
            hour: rule.hour!,
            minute: rule.minute!,
            weekdays: rule.weekdays.isEmpty ? null : rule.weekdays,
            payload: rule.payload,
          );
          return true;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] repeating email dispatch failed for ${rule.key}: $e\n$st',
          );
          return false;
        }
      case ReminderKind.off:
        return false;
    }
  }

  // -------------------------------------------------------------------------
  // 内部：取消
  // -------------------------------------------------------------------------

  Future<bool> _cancelTodo(String todoId, {bool blocking = true}) async {
    // 双通道清理：即便本地记录的是 push，用户从 alarm 切过来时也能扫到尾巴。
    var ok = true;
    ok =
        await _cancelSafely(
          'todo notification legacy:$todoId',
          () => notif.cancelTodoReminder(todoId),
          blocking: blocking,
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'todo alarm legacy:$todoId',
          () => alarm.cancel(_idFor('todo_$todoId')),
          blocking: blocking,
        ) &&
        ok;
    return ok;
  }

  Future<bool> _cancelGoal(String goalId, {bool blocking = true}) async {
    final id = _idFor('goal_$goalId');
    var ok = true;
    ok =
        await _cancelSafely(
          'goal notification:$goalId',
          () => notif.cancel(id),
          blocking: blocking,
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'goal alarm:$goalId',
          () => alarm.cancel(id),
          blocking: blocking,
        ) &&
        ok;
    return ok;
  }

  Future<bool> _cancelTodoLegacy(String todoId, {bool blocking = true}) =>
      _cancelTodo(todoId, blocking: blocking);

  Future<bool> _cancelGoalLegacy(String goalId, {bool blocking = true}) =>
      _cancelGoal(goalId, blocking: blocking);

  Future<bool> _cancelAnniversary(String annId) async {
    var ok = true;
    ok =
        await _cancelSafely(
          'anniversary notification:$annId',
          () => notif.cancelAnniversary(annId),
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'anniversary alarm:$annId',
          () => alarm.cancel(_idFor('anni_alarm_$annId')),
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'anniversary popup:$annId',
          () => popup.cancel(_idFor('anni_$annId')),
        ) &&
        ok;
    ok = await _cancelEmail(_idFor('anni_$annId'), 'anniversary:$annId') && ok;
    return ok;
  }

  Future<bool> _cancelCountdown(String countdownId) async {
    final id = _idFor('countdown:$countdownId:due');
    var ok = true;
    ok =
        await _cancelSafely(
          'countdown notification:$countdownId',
          () => notif.cancel(id),
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'countdown alarm:$countdownId',
          () => alarm.cancel(id),
        ) &&
        ok;
    ok =
        await _cancelSafely(
          'countdown popup:$countdownId',
          () => popup.cancel(id),
        ) &&
        ok;
    ok = await _cancelEmail(id, 'countdown:$countdownId') && ok;
    return ok;
  }

  Future<bool> _cancelRuleObjects(
    String objectType,
    String objectId,
    Iterable<String> ruleIds, {
    bool blocking = true,
  }) async {
    var ok = true;
    for (final ruleId in ruleIds) {
      ok =
          await _cancelRule(objectType, objectId, ruleId, blocking: blocking) &&
          ok;
    }
    return ok;
  }

  Future<Map<String, Set<int>>> _sweepRuleRegistry({
    required String objectType,
    required Map<String, Map<String, _ResolvedRule>> wanted,
  }) async {
    final persisted = await registry.idsByObject(objectType);
    final blocked = <String, Set<int>>{};
    for (final entry in persisted.entries) {
      final objectId = entry.key;
      final wantedRules = wanted[objectId] ?? const <String, _ResolvedRule>{};
      final wantedIds = {
        for (final rule in wantedRules.values) ..._registryIdsForRule(rule),
      };
      final staleIds = entry.value.difference(wantedIds);
      if (staleIds.isEmpty) continue;
      final cancelled = await _cancelIds(
        objectType,
        objectId,
        staleIds,
        blocking: false,
      );
      if (cancelled) {
        if (wantedIds.isEmpty) {
          await registry.removeObject(objectType, objectId);
        } else {
          await _replaceRegistryObject(
            objectType,
            objectId,
            wantedIds,
            resolvedRules: wantedRules.values,
          );
        }
      } else {
        blocked[objectId] = staleIds;
      }
    }
    return blocked;
  }

  Future<Map<String, Set<int>>> _sweepSingleRegistry({
    required String objectType,
    required Map<String, Set<int>> wantedIdsByObject,
  }) async {
    final persisted = await registry.idsByObject(objectType);
    final blocked = <String, Set<int>>{};
    for (final entry in persisted.entries) {
      final objectId = entry.key;
      final wantedIds = wantedIdsByObject[objectId] ?? const <int>{};
      final staleIds = entry.value.difference(wantedIds);
      if (staleIds.isEmpty) continue;
      final cancelled = await _cancelIds(
        objectType,
        objectId,
        staleIds,
        blocking: false,
      );
      if (cancelled) {
        if (wantedIds.isEmpty) {
          await registry.removeObject(objectType, objectId);
        } else {
          await _replaceRegistryObject(objectType, objectId, wantedIds);
        }
      } else {
        blocked[objectId] = staleIds;
      }
    }
    return blocked;
  }

  Future<bool> _cancelCurrentTodoPlan(TodoItem todo) async {
    final plan = _effectiveTodoPlan(todo);
    var ok = await _cancelTodoLegacy(todo.id);
    if (plan.rules.isNotEmpty) {
      ok =
          await _cancelRuleObjects(
            'todo',
            todo.id,
            plan.rules.map((rule) => rule.id),
          ) &&
          ok;
    }
    if (ok) await registry.removeObject('todo', todo.id);
    return ok;
  }

  Future<bool> _cancelCurrentGoalPlan(GoalItem goal) async {
    final plan = goal.reminderPlan.enabled && goal.reminderPlan.rules.isNotEmpty
        ? goal.reminderPlan
        : goal.reminder.enabled
        ? ReminderPlan.fromLegacy(goal.reminder)
        : const ReminderPlan.disabled();
    var ok = await _cancelGoalLegacy(goal.id);
    if (plan.rules.isNotEmpty) {
      ok =
          await _cancelRuleObjects(
            'goal',
            goal.id,
            plan.rules.map((rule) => rule.id),
          ) &&
          ok;
    }
    if (ok) await registry.removeObject('goal', goal.id);
    return ok;
  }

  Future<bool> _cancelIds(
    String objectType,
    String objectId,
    Iterable<int> ids, {
    bool blocking = true,
  }) async {
    var ok = true;
    for (final id in ids.where((id) => id != 0).toSet()) {
      ok =
          await _cancelSafely(
            '$objectType notification registry:$objectId ($id)',
            () => notif.cancel(id),
            blocking: blocking,
          ) &&
          ok;
      ok =
          await _cancelSafely(
            '$objectType alarm registry:$objectId ($id)',
            () => alarm.cancel(id),
            blocking: blocking,
          ) &&
          ok;
      ok =
          await _cancelSafely(
            '$objectType popup registry:$objectId ($id)',
            () => popup.cancel(id),
            blocking: blocking,
          ) &&
          ok;
      ok =
          await _cancelEmail(
            id,
            '$objectType:$objectId registry',
            blocking: blocking,
          ) &&
          ok;
    }
    return ok;
  }

  Future<bool> _cancelRule(
    String objectType,
    String objectId,
    String ruleId, {
    bool blocking = true,
  }) async {
    final intId = _idFor('$objectType:$objectId:$ruleId');
    var ok = true;
    ok =
        await _cancelSafely(
          '$objectType notification:$objectId:$ruleId',
          () => notif.cancel(intId),
          blocking: blocking,
        ) &&
        ok;
    ok =
        await _cancelSafely(
          '$objectType alarm:$objectId:$ruleId',
          () => alarm.cancel(intId),
          blocking: blocking,
        ) &&
        ok;
    ok =
        await _cancelEmail(
          intId,
          '$objectType:$objectId:$ruleId',
          blocking: blocking,
        ) &&
        ok;
    ok =
        await _cancelSafely(
          '$objectType popup:$objectId:$ruleId',
          () => popup.cancel(intId),
          blocking: blocking,
        ) &&
        ok;
    return ok;
  }

  Future<bool> _cancelEmail(
    int id,
    String label, {
    bool blocking = true,
  }) async {
    return _cancelSafely(
      'email:$label ($id)',
      () => email.cancel(id),
      blocking: blocking,
    );
  }

  Future<bool> _cancelSafely(
    String label,
    Future<void> Function() cancel, {
    bool blocking = true,
  }) async {
    try {
      await cancel();
      return true;
    } catch (e, st) {
      debugPrint('[ReminderScheduler] cancel failed for $label: $e\n$st');
      _recordCancellationIssue(label: label, error: e, blocking: blocking);
      return false;
    }
  }

  void _recordCancellationIssue({
    required String label,
    required Object error,
    bool blocking = true,
  }) {
    debugPrint(
      '[ReminderScheduler] Old reminder cleanup failed for $label: $error',
    );
    // 旧提醒清理失败时不阻塞新提醒注册，允许覆盖旧规则
    // 系统通知队列通常允许相同 ID 覆盖，重复注册会自动替换
    final issueSink = notif is ReminderScheduleIssueSink
        ? notif as ReminderScheduleIssueSink
        : null;
    if (issueSink == null) return;
    issueSink.recordReminderScheduleIssue(
      title: '提醒已更新',
      message: '提醒已保存。若旧提醒仍弹出，可前往"我的 → 通知设置 → 已注册提醒"手动检查。',
      relatedId: label,
      blocking: false,
    );
  }

  Future<void> _syncRuleObjects({
    required String objectType,
    required Map<String, Map<String, _ResolvedRule>> wanted,
    required Map<String, Map<String, _ScheduledRule>> scheduled,
    required Future<bool> Function(String objectId, {bool blocking})
    cancelLegacy,
    required Map<String, Set<int>> blockedRegistryIdsByObject,
  }) async {
    final nextScheduled = <String, Map<String, _ScheduledRule>>{};
    final persistedRegistryIdsByObject = await registry.idsByObject(objectType);

    for (final objectId in scheduled.keys.toList()) {
      final priorRules = scheduled[objectId] ?? const {};
      final nextRules = wanted[objectId];
      if (objectType == 'todo' && nextRules != null) {
        _todoScheduleFailures.remove(objectId);
      }
      final blockedRegistryIds = <int>{
        ...?blockedRegistryIdsByObject[objectId],
      };
      if (nextRules == null) {
        final rulesCancelled = await _cancelRuleObjects(
          objectType,
          objectId,
          priorRules.keys,
        );
        final legacyCancelled = await cancelLegacy(objectId);
        if (!rulesCancelled || !legacyCancelled) {
          nextScheduled[objectId] = Map<String, _ScheduledRule>.from(
            priorRules,
          );
          await _replaceRegistryObject(objectType, objectId, {
            ...blockedRegistryIds,
            ..._registryIdsForScheduledRules(objectType, objectId, priorRules),
          }, scheduledRules: priorRules.values);
        } else {
          await registry.removeObject(objectType, objectId);
        }
        continue;
      }

      final kept = <String, _ScheduledRule>{};
      for (final priorEntry in priorRules.entries) {
        if (!nextRules.containsKey(priorEntry.key)) {
          final cancelled = await _cancelRule(
            objectType,
            objectId,
            priorEntry.key,
          );
          if (!cancelled) {
            kept[priorEntry.key] = priorEntry.value;
          }
        }
      }

      for (final nextEntry in nextRules.entries) {
        final nextRule = nextEntry.value;
        final prior = priorRules[nextEntry.key];
        final needsCancel =
            prior != null && !_sameScheduledRule(prior, nextRule);
        if (needsCancel) {
          await _cancelRule(
            objectType,
            objectId,
            nextEntry.key,
            blocking: false,
          );
        }
      }

      await cancelLegacy(objectId, blocking: false);
      for (final nextRule in nextRules.values) {
        final prior = priorRules[nextRule.ruleId];
        if (prior != null && _sameScheduledRule(prior, nextRule)) {
          if (await _scheduledRuleStillPending(nextRule)) {
            kept[nextRule.ruleId] = prior;
            continue;
          }
          final cancelled = await _cancelRule(
            objectType,
            objectId,
            nextRule.ruleId,
          );
          if (!cancelled) {
            kept[nextRule.ruleId] = prior;
            continue;
          }
        }
        // 强制注册新规则，即使旧规则清理失败
        // 系统通知 ID 相同时会自动覆盖
        final ok = await _dispatchRule(nextRule);
        if (ok) {
          kept[nextRule.ruleId] = _scheduledFromResolved(nextRule);
        } else {
          _recordTodoRuleDispatchFailure(nextRule);
          final prior = priorRules[nextRule.ruleId];
          if (prior != null &&
              _sameScheduledRule(prior, nextRule) &&
              await _scheduledRuleStillPending(nextRule)) {
            kept[nextRule.ruleId] = prior;
          }
        }
      }

      if (kept.isNotEmpty) {
        nextScheduled[objectId] = kept;
        await _replaceRegistryObject(objectType, objectId, {
          ...blockedRegistryIds,
          ..._registryIdsForScheduledRules(objectType, objectId, kept),
        }, scheduledRules: kept.values);
      } else if (blockedRegistryIds.isNotEmpty) {
        await _replaceRegistryObject(
          objectType,
          objectId,
          blockedRegistryIds,
          resolvedRules: nextRules.values,
        );
      } else {
        await registry.removeObject(objectType, objectId);
      }
    }

    for (final entry in wanted.entries) {
      final objectId = entry.key;
      if (scheduled.containsKey(objectId)) continue;

      final nextRules = entry.value;
      final kept = <String, _ScheduledRule>{};
      final blockedRegistryIds = <int>{
        ...?blockedRegistryIdsByObject[objectId],
      };
      final persistedRegistryIds =
          persistedRegistryIdsByObject[objectId] ?? const <int>{};
      await cancelLegacy(objectId, blocking: false);
      for (final nextRule in nextRules.values) {
        final nextRuleRegistryIds = _registryIdsForRule(nextRule);
        final cancelled = await _cancelRule(
          objectType,
          objectId,
          nextRule.ruleId,
          blocking: false,
        );
        final hadPersistedRuleIds = persistedRegistryIds.any(
          nextRuleRegistryIds.contains,
        );
        if (!cancelled && hadPersistedRuleIds) {
          blockedRegistryIds.addAll(nextRuleRegistryIds);
        }
        final ok = await _dispatchRule(nextRule);
        if (ok) {
          kept[nextRule.ruleId] = _scheduledFromResolved(nextRule);
        } else {
          _recordTodoRuleDispatchFailure(nextRule);
        }
      }
      if (kept.isNotEmpty) {
        nextScheduled[objectId] = kept;
        await _replaceRegistryObject(objectType, objectId, {
          ...blockedRegistryIds,
          ..._registryIdsForScheduledRules(objectType, objectId, kept),
        }, scheduledRules: kept.values);
      } else if (blockedRegistryIds.isNotEmpty) {
        await _replaceRegistryObject(
          objectType,
          objectId,
          blockedRegistryIds,
          resolvedRules: nextRules.values,
        );
      } else {
        await registry.removeObject(objectType, objectId);
      }
    }

    scheduled
      ..clear()
      ..addAll(nextScheduled);
  }

  bool _sameScheduledRule(_ScheduledRule prior, _ResolvedRule next) {
    return prior.kind == next.kind &&
        prior.mode == next.mode &&
        prior.scope == next.scope &&
        prior.fingerprint == next.fingerprint;
  }

  Future<bool> _scheduledRuleStillPending(_ResolvedRule rule) async {
    return _sinkStillPending(
      label: rule.key,
      kind: rule.kind,
      expected: _expectedPendingIdsForRule(rule),
      acceptedExpectedSets: _acceptedPendingIdSetsForRule(rule),
      stalePeerIds: _registryIdsForRule(rule),
    );
  }

  Future<bool> _habitStillPending(Habit habit) async {
    final rules = _enabledHabitRules(habit);
    if (rules.isEmpty) return true;
    // 单条提醒沿用历史校验路径。
    if (rules.length == 1) {
      final rule = rules.single;
      final baseId = _idFor('habit_${habit.id}');
      return _sinkStillPending(
        label: 'habit:${habit.id}',
        kind: rule.kind,
        expected: _expectedRepeatingPendingIds(
          baseId,
          _habitWeekdays(habit, rule),
        ),
        acceptedExpectedSets: _acceptedRepeatingPendingIdSets(
          kind: rule.kind,
          base: baseId,
          weekdays: _habitWeekdays(habit, rule),
        ),
        stalePeerIds: _habitRegistryIds(habit),
      );
    }
    // 多提醒时间：任一条不在系统队列即视为整体需要重排。
    final peers = _habitRegistryIds(habit);
    for (var i = 0; i < rules.length; i++) {
      final rule = rules[i];
      final baseId = _habitRuleId(habit.id, rule, i);
      final weekdays = _habitWeekdays(habit, rule);
      final stillPending = await _sinkStillPending(
        label: 'habit:${habit.id}#${rule.id}',
        kind: rule.kind,
        expected: _expectedRepeatingPendingIds(baseId, weekdays),
        acceptedExpectedSets: _acceptedRepeatingPendingIdSets(
          kind: rule.kind,
          base: baseId,
          weekdays: weekdays,
        ),
        stalePeerIds: peers,
      );
      if (!stillPending) return false;
    }
    return true;
  }

  Future<bool> _anniversaryStillPending(Anniversary item) {
    final baseId = switch (item.reminderKind) {
      ReminderKind.alarm => _idFor('anni_alarm_${item.id}'),
      _ => _idFor('anni_${item.id}'),
    };
    return _sinkStillPending(
      label: 'anniversary:${item.id}',
      kind: item.reminderKind,
      expected: <int>{baseId},
      notificationFallbackExpectedSets: item.reminderKind == ReminderKind.alarm
          ? <Set<int>>[
              <int>{_idFor('anni_${item.id}')},
            ]
          : null,
      stalePeerIds: _anniversaryRegistryIds(item),
    );
  }

  Future<bool> _countdownStillPending(CountdownItem item) {
    final baseId = _idFor('countdown:${item.id}:due');
    return _sinkStillPending(
      label: 'countdown:${item.id}',
      kind: item.reminderKind,
      expected: <int>{baseId},
      stalePeerIds: _countdownRegistryIds(item),
    );
  }

  Future<bool> _sinkStillPending({
    required String label,
    required ReminderKind kind,
    required Set<int> expected,
    List<Set<int>>? acceptedExpectedSets,
    List<Set<int>>? notificationFallbackExpectedSets,
    Set<int>? stalePeerIds,
  }) async {
    final sink = switch (kind) {
      ReminderKind.push => notif,
      ReminderKind.alarm => alarm,
      _ => null,
    };
    if (sink is! ReminderPendingSink || expected.isEmpty) {
      return _cancelStalePeerPending(
        label: label,
        ownerKind: kind,
        ids: stalePeerIds ?? expected,
      );
    }
    try {
      final actual = (await sink.pendingIds()).toSet();
      final acceptedSets = acceptedExpectedSets ?? <Set<int>>[expected];
      final pendingSatisfied = acceptedSets.any(
        (ids) => ids.isNotEmpty && actual.containsAll(ids),
      );
      if (pendingSatisfied) {
        final staleCleaned = await _cancelStalePeerPending(
          label: label,
          ownerKind: kind,
          ids: stalePeerIds ?? expected,
        );
        return staleCleaned;
      }
      if (kind == ReminderKind.alarm &&
          await _notificationFallbackStillPendingForAlarm(
            label: label,
            acceptedExpectedSets:
                notificationFallbackExpectedSets ?? acceptedSets,
            stalePeerIds: stalePeerIds ?? expected,
          )) {
        return true;
      }
      final missing = expected.difference(actual);
      debugPrint(
        '[ReminderScheduler] pending queue missing for $label: '
        '${missing.join(',')}',
      );
      return false;
    } catch (e, st) {
      debugPrint(
        '[ReminderScheduler] pending probe failed for $label: $e\n$st',
      );
      _recordPendingProbeIssue(
        title: switch (kind) {
          ReminderKind.push => '普通通知状态无法确认',
          ReminderKind.alarm => '闹钟提醒状态无法确认',
          _ => '提醒状态无法确认',
        },
        message: '系统待触发队列查询失败，将重新注册提醒以修复可能丢失的系统队列；请检查系统提醒权限。',
        label: label,
        error: e,
      );
      return false;
    }
  }

  Future<bool> _notificationFallbackStillPendingForAlarm({
    required String label,
    required List<Set<int>> acceptedExpectedSets,
    required Set<int> stalePeerIds,
  }) async {
    if (notif is! ReminderPendingSink) return false;
    try {
      final actual = (await (notif as ReminderPendingSink).pendingIds())
          .toSet();
      final pendingSatisfied = acceptedExpectedSets.any(
        (ids) => ids.isNotEmpty && actual.containsAll(ids),
      );
      if (!pendingSatisfied) return false;
      debugPrint(
        '[ReminderScheduler] notification fallback queue owns alarm reminder '
        'for $label; keep fallback to avoid duplicate delivery.',
      );
      return await _cancelStalePeerPending(
        label: label,
        ownerKind: ReminderKind.push,
        ids: stalePeerIds,
      );
    } catch (e, st) {
      debugPrint(
        '[ReminderScheduler] notification fallback pending probe failed for '
        '$label; keep prior state to avoid duplicate delivery: $e\n$st',
      );
      _recordPendingProbeIssue(
        title: '普通通知兜底状态无法确认',
        message: '普通通知兜底队列查询失败，已保留现有状态以避免重复弹出；请重新保存提醒或检查系统通知权限。',
        label: label,
        error: e,
      );
      return true;
    }
  }

  Future<bool> _alarmQueueAlreadyOwns({
    required String label,
    required Set<int> expected,
    List<Set<int>>? acceptedExpectedSets,
  }) async {
    if (alarm is! ReminderPendingSink || expected.isEmpty) return false;
    try {
      final actual = (await (alarm as ReminderPendingSink).pendingIds())
          .toSet();
      final acceptedSets = acceptedExpectedSets ?? <Set<int>>[expected];
      final owns = acceptedSets.any(
        (ids) => ids.isNotEmpty && actual.containsAll(ids),
      );
      if (owns) {
        debugPrint(
          '[ReminderScheduler] alarm dispatch for $label failed after the '
          'alarm queue was registered; skip notification fallback to avoid duplicate delivery.',
        );
      }
      return owns;
    } catch (e, st) {
      debugPrint(
        '[ReminderScheduler] alarm fallback pending probe failed for $label; '
        'attempt notification fallback because alarm ownership was not confirmed: '
        '$e\n$st',
      );
      _recordPendingProbeIssue(
        title: '闹钟提醒状态无法确认',
        message: '系统待触发队列查询失败，已尝试使用普通通知兜底保住提醒；请重新保存提醒或检查系统提醒权限。',
        label: label,
        error: e,
      );
      return false;
    }
  }

  void _recordPendingProbeIssue({
    required String title,
    required String message,
    required String label,
    required Object error,
  }) {
    final issueSink = notif is ReminderScheduleIssueSink
        ? notif as ReminderScheduleIssueSink
        : null;
    if (issueSink == null) return;
    issueSink.recordReminderScheduleIssue(
      title: title,
      message: message,
      relatedId: label,
      blocking: false,
    );
  }

  Future<bool> _cancelStalePeerPending({
    required String label,
    required ReminderKind ownerKind,
    required Set<int> ids,
  }) async {
    if (ids.isEmpty) return true;
    var ok = true;

    Future<void> cleanupPeer({
      required ReminderPendingSink pending,
      required Future<void> Function(int id) cancel,
      required String staleLabel,
    }) async {
      Set<int> staleIds;
      try {
        staleIds = (await pending.pendingIds()).toSet().intersection(ids);
      } catch (e, st) {
        debugPrint(
          '[ReminderScheduler] stale $staleLabel pending probe failed for '
          '$label: $e\n$st',
        );
        _recordPendingProbeIssue(
          title: '残留提醒状态无法确认',
          message: '旧提醒队列查询失败，已保留当前注册状态以避免重复弹出；请重新保存提醒或检查系统提醒权限。',
          label: '$label stale $staleLabel',
          error: e,
        );
        ok = false;
        return;
      }
      for (final id in staleIds) {
        ok =
            await _cancelSafely(
              '$label stale $staleLabel owner:$id',
              () => cancel(id),
            ) &&
            ok;
      }
      if (staleIds.isNotEmpty && !ok) {
        debugPrint(
          '[ReminderScheduler] stale $staleLabel owner cleanup incomplete for '
          '$label; keep current owner without re-registering to avoid duplicates.',
        );
      }
    }

    switch (ownerKind) {
      case ReminderKind.push:
        if (alarm is ReminderPendingSink) {
          await cleanupPeer(
            pending: alarm as ReminderPendingSink,
            cancel: alarm.cancel,
            staleLabel: 'alarm',
          );
        }
        break;
      case ReminderKind.alarm:
        if (notif is ReminderPendingSink) {
          await cleanupPeer(
            pending: notif as ReminderPendingSink,
            cancel: notif.cancel,
            staleLabel: 'notification',
          );
        }
        break;
      case ReminderKind.popup:
        if (notif is ReminderPendingSink) {
          await cleanupPeer(
            pending: notif as ReminderPendingSink,
            cancel: notif.cancel,
            staleLabel: 'notification',
          );
        }
        if (alarm is ReminderPendingSink) {
          await cleanupPeer(
            pending: alarm as ReminderPendingSink,
            cancel: alarm.cancel,
            staleLabel: 'alarm',
          );
        }
        break;
      case ReminderKind.email:
      case ReminderKind.off:
        return true;
    }
    return ok;
  }

  Set<int> _expectedRepeatingPendingIds(int base, List<int> weekdays) {
    if (weekdays.isEmpty) return <int>{base};
    return {for (final weekday in weekdays) _subId(base, weekday)};
  }

  Set<int> _expectedPendingIdsForRule(_ResolvedRule rule) {
    final base = _idFor(rule.key);
    if (rule.mode == _DispatchMode.once || rule.weekdays.isEmpty) {
      return <int>{base};
    }
    return {for (final weekday in rule.weekdays) _subId(base, weekday)};
  }

  List<Set<int>> _acceptedPendingIdSetsForRule(_ResolvedRule rule) {
    final base = _idFor(rule.key);
    if (rule.mode == _DispatchMode.once || rule.weekdays.isEmpty) {
      return <Set<int>>[
        <int>{base},
      ];
    }
    return _acceptedRepeatingPendingIdSets(
      kind: rule.kind,
      base: base,
      weekdays: rule.weekdays,
    );
  }

  List<Set<int>> _acceptedRepeatingPendingIdSets({
    required ReminderKind kind,
    required int base,
    required List<int> weekdays,
  }) {
    final expected = _expectedRepeatingPendingIds(base, weekdays);
    if (kind != ReminderKind.alarm || weekdays.isEmpty) {
      return <Set<int>>[expected];
    }
    return <Set<int>>[
      <int>{base},
      expected,
    ];
  }

  Set<int> _registryIdsForRule(_ResolvedRule rule) {
    final base = _idFor(rule.key);
    if (rule.mode == _DispatchMode.once || rule.weekdays.isEmpty) {
      return <int>{base};
    }
    return <int>{
      base,
      for (final weekday in rule.weekdays) _subId(base, weekday),
      for (final weekday in rule.weekdays) _legacySubId(base, weekday),
    };
  }

  Set<int> _registryIdsForScheduledRules(
    String objectType,
    String objectId,
    Map<String, _ScheduledRule> rules,
  ) {
    return {
      for (final entry in rules.entries)
        ..._registryIdsForScheduledRule(
          objectType,
          objectId,
          entry.key,
          entry.value,
        ),
    };
  }

  Set<int> _registryIdsForScheduledRule(
    String objectType,
    String objectId,
    String ruleId,
    _ScheduledRule rule,
  ) {
    final base = _idFor('$objectType:$objectId:$ruleId');
    if (rule.mode == _DispatchMode.once) return <int>{base};
    final weekdays = _weekdaysFromScope(rule.scope);
    if (weekdays.isEmpty) return <int>{base};
    return <int>{
      base,
      for (final weekday in weekdays) _subId(base, weekday),
      for (final weekday in weekdays) _legacySubId(base, weekday),
    };
  }

  List<int> _weekdaysFromScope(String scope) {
    if (!scope.startsWith('weekly:')) return const <int>[];
    final rawDays = scope.substring('weekly:'.length).split(',');
    final result = <int>{};
    for (final raw in rawDays) {
      final day = int.tryParse(raw);
      if (day != null && day >= 1 && day <= 7) result.add(day);
    }
    return result.toList()..sort();
  }

  Set<int> _habitRegistryIds(Habit habit) {
    final rules = _enabledHabitRules(habit);
    if (rules.isEmpty) return const <int>{};
    final ids = <int>{};
    for (var i = 0; i < rules.length; i++) {
      final base = _habitRuleId(habit.id, rules[i], i);
      ids.add(base);
      final weekdays = _habitWeekdays(habit, rules[i]);
      for (final weekday in weekdays) {
        ids.add(_subId(base, weekday));
        ids.add(_legacySubId(base, weekday));
      }
    }
    return ids;
  }

  Set<int> _anniversaryRegistryIds(Anniversary item) {
    return <int>{_idFor('anni_${item.id}'), _idFor('anni_alarm_${item.id}')};
  }

  Set<int> _countdownRegistryIds(CountdownItem item) {
    return <int>{_idFor('countdown:${item.id}:due')};
  }

  _ScheduledRule _scheduledFromResolved(_ResolvedRule rule) {
    return _ScheduledRule(
      kind: rule.kind,
      mode: rule.mode,
      scope: rule.scope,
      fingerprint: rule.fingerprint,
      title: rule.title,
      body: rule.body,
    );
  }

  int _subId(int base, int weekday) {
    var h = 0x811c9dc5;
    final key = '$base:$weekday';
    for (final unit in key.codeUnits) {
      h ^= unit;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h == 0 ? weekday : h;
  }

  int _legacySubId(int base, int weekday) =>
      legacyWeekdayNotificationId(base, weekday);

  // -------------------------------------------------------------------------
  // 内部：决定什么时候、以什么通道派发
  // -------------------------------------------------------------------------

  List<_ResolvedRule> _resolveTodoRules(
    TodoItem t, {
    required bool allowJustMissedOneShotReminders,
  }) {
    final plan = _effectiveTodoPlan(t);
    if (!plan.enabled || plan.rules.isEmpty) return const <_ResolvedRule>[];
    final now = AppClock.now();
    final resolved = <_ResolvedRule>[];
    for (final rule in plan.rules) {
      if (!rule.enabled || rule.kind == ReminderKind.off) continue;
      final next = _resolveTodoRule(
        t,
        rule,
        now,
        allowJustMissedOneShotReminders: allowJustMissedOneShotReminders,
      );
      if (next != null) resolved.add(next);
    }
    return _dedupeResolvedRules(resolved);
  }

  ReminderPlan _effectiveTodoPlan(TodoItem t) {
    if (t.reminderPlan.enabled && t.reminderPlan.rules.isNotEmpty) {
      return t.reminderPlan;
    }
    if (t.reminder.enabled) {
      return ReminderPlan.fromLegacy(t.reminder);
    }
    // ignore: deprecated_member_use_from_same_package
    if (t.hasReminder) {
      final anchor = _absoluteTodoReminderAnchor(t);
      if (anchor == null) return const ReminderPlan.disabled();
      return ReminderPlan(
        enabled: true,
        rules: [
          ReminderRule(
            id: 'legacy-${t.id}',
            enabled: true,
            type: ReminderRuleType.absolute,
            kind: ReminderKind.push,
            hour: anchor.hour,
            minute: anchor.minute,
          ),
        ],
      );
    }
    return const ReminderPlan.disabled();
  }

  _ResolvedRule? _resolveTodoRule(
    TodoItem t,
    ReminderRule rule,
    DateTime now, {
    required bool allowJustMissedOneShotReminders,
  }) {
    switch (rule.type) {
      case ReminderRuleType.absolute:
        final payload = _todoPayload(t.id, rule.kind);
        final anchor = _absoluteTodoReminderAnchor(t);
        if (anchor == null) return null;
        final hour = rule.hour ?? anchor.hour;
        final minute = rule.minute ?? anchor.minute;
        if (!_validTime(hour, minute)) return null;
        final when = _todoReminderAtTime(anchor, hour, minute);
        final scheduledWhen = _resolveOneShotReminderTime(
          when,
          now,
          allowJustMissed: allowJustMissedOneShotReminders,
        );
        if (scheduledWhen == null) return null;
        return _buildOnceRule(
          objectType: 'todo',
          objectId: t.id,
          rule: rule,
          title: _todoTitle(t, rule.type),
          body: t.title,
          payload: payload,
          when: scheduledWhen,
        );
      case ReminderRuleType.relativeToDue:
        final payload = _todoPayload(t.id, rule.kind);
        final anchor = _relativeTodoReminderAnchor(t);
        if (anchor == null) return null;
        final hour = rule.hour ?? anchor.hour;
        final minute = rule.minute ?? anchor.minute;
        if (!_validTime(hour, minute)) return null;
        final base = _todoReminderAtTime(anchor, hour, minute);
        final when = base.add(Duration(minutes: rule.offsetMinutes ?? 0));
        final scheduledWhen = _resolveOneShotReminderTime(
          when,
          now,
          allowJustMissed: allowJustMissedOneShotReminders,
        );
        if (scheduledWhen == null) return null;
        return _buildOnceRule(
          objectType: 'todo',
          objectId: t.id,
          rule: rule,
          title: _todoTitle(t, rule.type),
          body: t.title,
          payload: payload,
          when: scheduledWhen,
        );
      case ReminderRuleType.dailyTime:
        final payload = _todoPayload(t.id, rule.kind);
        if (!_validTime(rule.hour, rule.minute)) return null;
        return _buildRepeatingRule(
          objectType: 'todo',
          objectId: t.id,
          rule: rule,
          title: _todoTitle(t, rule.type),
          body: t.title,
          payload: payload,
          hour: rule.hour!,
          minute: rule.minute!,
          weekdays: const <int>[],
        );
      case ReminderRuleType.weeklyTime:
        final payload = _todoPayload(t.id, rule.kind);
        if (!_validTime(rule.hour, rule.minute) || rule.weekdays.isEmpty) {
          return null;
        }
        return _buildRepeatingRule(
          objectType: 'todo',
          objectId: t.id,
          rule: rule,
          title: _todoTitle(t, rule.type),
          body: t.title,
          payload: payload,
          hour: rule.hour!,
          minute: rule.minute!,
          weekdays: _normalizedWeekdays(rule.weekdays),
        );
    }
  }

  List<_ResolvedRule> _resolveGoalRules(GoalItem g) {
    final plan = g.reminderPlan.enabled && g.reminderPlan.rules.isNotEmpty
        ? g.reminderPlan
        : g.reminder.enabled
        ? ReminderPlan.fromLegacy(g.reminder)
        : const ReminderPlan.disabled();
    if (!plan.enabled || plan.rules.isEmpty) return const <_ResolvedRule>[];
    final now = AppClock.now();
    final resolved = <_ResolvedRule>[];
    for (final rule in plan.rules) {
      if (!rule.enabled || rule.kind == ReminderKind.off) continue;
      final next = _resolveGoalRule(g, rule, now);
      if (next != null) resolved.add(next);
    }
    return _dedupeResolvedRules(resolved);
  }

  List<_ResolvedRule> _dedupeResolvedRules(List<_ResolvedRule> rules) {
    if (rules.length < 2) return rules;
    final selectedOnceRuleKeys = <String>{};
    final selectedWeekdaysByRuleKey = <String, Set<int>>{};
    final selectedByOccurrence = <String, _ResolvedRule>{};
    for (final rule in rules) {
      if (rule.mode == _DispatchMode.repeating) {
        for (final weekday in _logicalDeliveryWeekdays(rule)) {
          final fingerprint = _logicalRepeatingDeliveryFingerprint(
            rule,
            weekday,
          );
          final prior = selectedByOccurrence[fingerprint];
          if (prior == null ||
              _deliveryPriority(rule.kind) > _deliveryPriority(prior.kind)) {
            if (prior != null) {
              selectedWeekdaysByRuleKey[prior.key]?.remove(weekday);
            }
            selectedByOccurrence[fingerprint] = rule;
            selectedWeekdaysByRuleKey
                .putIfAbsent(rule.key, () => <int>{})
                .add(weekday);
          }
        }
        continue;
      }

      final fingerprint = rule.logicalDeliveryFingerprint;
      final prior = selectedByOccurrence[fingerprint];
      if (prior == null ||
          _deliveryPriority(rule.kind) > _deliveryPriority(prior.kind)) {
        if (prior != null) {
          selectedOnceRuleKeys.remove(prior.key);
        }
        selectedByOccurrence[fingerprint] = rule;
        selectedOnceRuleKeys.add(rule.key);
      }
    }

    final result = <_ResolvedRule>[];
    for (final rule in rules) {
      if (rule.mode == _DispatchMode.repeating) {
        final weekdays = selectedWeekdaysByRuleKey[rule.key];
        if (weekdays == null || weekdays.isEmpty) continue;
        final original = _logicalDeliveryWeekdays(rule).toSet();
        if (weekdays.length == original.length &&
            weekdays.containsAll(original)) {
          result.add(rule);
        } else {
          result.add(_copyRepeatingRuleWithWeekdays(rule, weekdays));
        }
      } else if (selectedOnceRuleKeys.contains(rule.key)) {
        result.add(rule);
      }
    }
    return result;
  }

  int _deliveryPriority(ReminderKind kind) {
    return switch (kind) {
      ReminderKind.alarm => 4,
      ReminderKind.push => 3,
      ReminderKind.popup => 2,
      ReminderKind.email => 1,
      ReminderKind.off => 0,
    };
  }

  List<int> _logicalDeliveryWeekdays(_ResolvedRule rule) {
    final weekdays = _normalizedWeekdays(rule.weekdays);
    if (weekdays.isEmpty) return const <int>[1, 2, 3, 4, 5, 6, 7];
    return weekdays;
  }

  String _logicalRepeatingDeliveryFingerprint(_ResolvedRule rule, int weekday) {
    return [
      rule.objectType,
      rule.objectId,
      rule.mode.name,
      rule.body,
      rule.hour?.toString() ?? '-',
      rule.minute?.toString() ?? '-',
      weekday,
    ].join('|');
  }

  _ResolvedRule _copyRepeatingRuleWithWeekdays(
    _ResolvedRule rule,
    Iterable<int> weekdays,
  ) {
    final normalized = _normalizedWeekdays(weekdays.toList());
    final scope = normalized.length == 7
        ? 'daily'
        : 'weekly:${normalized.join(',')}';
    return _ResolvedRule(
      objectType: rule.objectType,
      objectId: rule.objectId,
      ruleId: rule.ruleId,
      kind: rule.kind,
      mode: rule.mode,
      ruleType: normalized.length == 7
          ? ReminderRuleType.dailyTime
          : ReminderRuleType.weeklyTime,
      title: rule.title,
      body: rule.body,
      payload: rule.payload,
      fullScreen: rule.fullScreen,
      vibrate: rule.vibrate,
      snoozeMinutes: rule.snoozeMinutes,
      repeatCount: rule.repeatCount,
      hour: rule.hour,
      minute: rule.minute,
      weekdays: normalized.length == 7 ? const <int>[] : normalized,
      scope: scope,
    );
  }

  _ResolvedRule? _resolveGoalRule(GoalItem g, ReminderRule rule, DateTime now) {
    final payload = 'duoyi://goal/${g.id}';
    switch (rule.type) {
      case ReminderRuleType.absolute:
        final anchorDate = _goalAnchorDate(g, now);
        final hour = rule.hour ?? anchorDate.hour;
        final minute = rule.minute ?? anchorDate.minute;
        if (!_validTime(hour, minute)) return null;
        final when = _dateAtTime(anchorDate, hour, minute);
        if (!when.isAfter(now)) {
          final tomorrow = AppClock.date(now.year, now.month, now.day + 1);
          final fallback = _dateAtTime(tomorrow, hour, minute);
          if (!fallback.isAfter(now)) return null;
          return _buildOnceRule(
            objectType: 'goal',
            objectId: g.id,
            rule: rule,
            title: _titleFor('goal', rule.type, rule.kind),
            body: g.title,
            payload: payload,
            when: fallback,
          );
        }
        return _buildOnceRule(
          objectType: 'goal',
          objectId: g.id,
          rule: rule,
          title: _titleFor('goal', rule.type, rule.kind),
          body: g.title,
          payload: payload,
          when: when,
        );
      case ReminderRuleType.relativeToDue:
        final anchor = g.targetDate;
        if (anchor == null) return null;
        final hour = rule.hour ?? anchor.hour;
        final minute = rule.minute ?? anchor.minute;
        if (!_validTime(hour, minute)) return null;
        final base = _dateAtTime(anchor, hour, minute);
        final when = base.add(Duration(minutes: rule.offsetMinutes ?? 0));
        if (!when.isAfter(now)) return null;
        return _buildOnceRule(
          objectType: 'goal',
          objectId: g.id,
          rule: rule,
          title: _titleFor('goal', rule.type, rule.kind),
          body: g.title,
          payload: payload,
          when: when,
        );
      case ReminderRuleType.dailyTime:
        if (!_validTime(rule.hour, rule.minute)) return null;
        return _buildRepeatingRule(
          objectType: 'goal',
          objectId: g.id,
          rule: rule,
          title: _titleFor('goal', rule.type, rule.kind),
          body: g.title,
          payload: payload,
          hour: rule.hour!,
          minute: rule.minute!,
          weekdays: const <int>[],
        );
      case ReminderRuleType.weeklyTime:
        if (!_validTime(rule.hour, rule.minute) || rule.weekdays.isEmpty) {
          return null;
        }
        return _buildRepeatingRule(
          objectType: 'goal',
          objectId: g.id,
          rule: rule,
          title: _titleFor('goal', rule.type, rule.kind),
          body: g.title,
          payload: payload,
          hour: rule.hour!,
          minute: rule.minute!,
          weekdays: _normalizedWeekdays(rule.weekdays),
        );
    }
  }

  _ResolvedRule _buildOnceRule({
    required String objectType,
    required String objectId,
    required ReminderRule rule,
    required String title,
    required String body,
    required String payload,
    required DateTime when,
  }) {
    return _ResolvedRule(
      objectType: objectType,
      objectId: objectId,
      ruleId: rule.id,
      kind: rule.kind,
      mode: _DispatchMode.once,
      ruleType: rule.type,
      title: title,
      body: body,
      payload: payload,
      fullScreen: rule.fullScreen,
      vibrate: rule.vibrate,
      snoozeMinutes: rule.snoozeMinutes,
      repeatCount: rule.repeatCount,
      when: when,
      scope: 'once',
    );
  }

  _ResolvedRule _buildRepeatingRule({
    required String objectType,
    required String objectId,
    required ReminderRule rule,
    required String title,
    required String body,
    required String payload,
    required int hour,
    required int minute,
    required List<int> weekdays,
  }) {
    final normalized = weekdays.isEmpty ? const <int>[] : weekdays;
    final scope = normalized.isEmpty
        ? 'daily'
        : 'weekly:${normalized.join(',')}';
    return _ResolvedRule(
      objectType: objectType,
      objectId: objectId,
      ruleId: rule.id,
      kind: rule.kind,
      mode: _DispatchMode.repeating,
      ruleType: rule.type,
      title: title,
      body: body,
      payload: payload,
      fullScreen: rule.fullScreen,
      vibrate: rule.vibrate,
      snoozeMinutes: rule.snoozeMinutes,
      repeatCount: rule.repeatCount,
      hour: hour,
      minute: minute,
      weekdays: normalized,
      scope: scope,
    );
  }

  Future<bool> _dispatchRule(_ResolvedRule rule) async {
    try {
      switch (rule.mode) {
        case _DispatchMode.once:
          if (rule.when == null) return false;
          return await _dispatch(
            kind: rule.kind,
            payload: _DispatchPayload(
              id: _idFor(rule.key),
              title: rule.title,
              body: rule.body,
              when: rule.when!,
              payload: rule.payload,
              fullScreen: rule.fullScreen,
              vibrate: rule.vibrate,
              snoozeMinutes: rule.snoozeMinutes,
              repeatCount: rule.repeatCount,
            ),
          );
        case _DispatchMode.repeating:
          return await _dispatchRepeating(rule);
      }
    } catch (e, st) {
      debugPrint(
        '[ReminderScheduler] dispatch failed for ${rule.key}: $e\n$st',
      );
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // 内部：时间与文案
  // -------------------------------------------------------------------------

  DateTime _dateAtTime(DateTime date, int hour, int minute) {
    return AppClock.date(date.year, date.month, date.day, hour, minute);
  }

  DateTime _countdownReminderAt(CountdownItem item) {
    return AppClock.date(
      item.targetDate.year,
      item.targetDate.month,
      item.targetDate.day - item.remindDaysBefore,
      item.remindHour,
      item.remindMinute,
    );
  }

  String _countdownScope(CountdownItem item, DateTime when) {
    return '${when.millisecondsSinceEpoch}:${item.title}:${item.remindDaysBefore}:${item.remindHour}:${item.remindMinute}:${item.reminderKind.name}';
  }

  String _habitScope(Habit habit) {
    final rules = _enabledHabitRules(habit);
    if (rules.isEmpty) return 'off';
    String fingerprint(ReminderRule rule) {
      final weekdays = _habitWeekdays(habit, rule);
      return [
        rule.kind.name,
        rule.type.name,
        rule.hour,
        rule.minute,
        rule.fullScreen,
        rule.vibrate,
        rule.snoozeMinutes,
        rule.repeatCount,
        weekdays.join(','),
      ].join('|');
    }

    // 单条提醒保持与历史完全一致的 scope，避免无谓重排与既有测试漂移。
    if (rules.length == 1) {
      return [habit.name, fingerprint(rules.single)].join('|');
    }
    // 多提醒时间：把每条规则的指纹（含 ruleId）一起编码，任一条变更都重排。
    return [
      habit.name,
      for (final rule in rules) '${rule.id}~${fingerprint(rule)}',
    ].join('||');
  }

  ReminderPlan _effectiveHabitPlan(Habit habit) {
    if (habit.reminderPlan.enabled && habit.reminderPlan.rules.isNotEmpty) {
      return habit.reminderPlan;
    }
    if (habit.remind &&
        habit.remindHour != null &&
        habit.remindMinute != null) {
      final weekdays = habit.activeWeekdays.map((w) => w + 1).toSet().toList()
        ..sort();
      return ReminderPlan(
        enabled: true,
        rules: [
          ReminderRule(
            id: 'habit-reminder',
            enabled: true,
            type: weekdays.length == 7
                ? ReminderRuleType.dailyTime
                : ReminderRuleType.weeklyTime,
            kind: ReminderKind.popup,
            hour: habit.remindHour,
            minute: habit.remindMinute,
            weekdays: weekdays.length == 7 ? const <int>[] : weekdays,
          ),
        ],
      );
    }
    return const ReminderPlan.disabled();
  }

  List<int> _habitWeekdays(Habit habit, ReminderRule rule) {
    if (rule.type == ReminderRuleType.weeklyTime && rule.weekdays.isNotEmpty) {
      return _normalizedWeekdays(rule.weekdays);
    }
    if (rule.type == ReminderRuleType.dailyTime) return const <int>[];
    final weekdays =
        habit.activeWeekdays
            .where((w) => w >= 0 && w <= 6)
            .map((w) => w + 1)
            .toSet()
            .toList()
          ..sort();
    return weekdays.length == 7 ? const <int>[] : weekdays;
  }

  /// 通知标题的品牌文案；默认 defaultBrand 与历史硬编码文案一致，
  /// 切换主题后由外部通过 [setStrings] 注入对应主题词条。
  BrandStrings _strings = BrandStrings.defaultBrand;

  /// 注入当前主题的通知文案（对齐 NotificationService.setStrings）。
  // ignore: use_setters_to_change_properties
  void setStrings(BrandStrings strings) {
    _strings = strings;
  }

  String _habitTitle() {
    return _strings.notifHabitRemindTitle;
  }

  String _todoTitle(TodoItem item, ReminderRuleType type) {
    return switch (type) {
      ReminderRuleType.dailyTime ||
      ReminderRuleType.weeklyTime => _strings.notifTodoDueTitle,
      // 一次性/相对截止提醒标题走 I18n（语言跟随）：daily/weekly 分支读品牌
      // 词条，本分支历史上为硬编码中文，会让 en 用户收到中文系统通知标题。
      ReminderRuleType.absolute || ReminderRuleType.relativeToDue =>
        '${I18n.tr('reminder.todo_title_prefix')}${item.title}',
    };
  }

  List<int> _normalizedWeekdays(List<int> weekdays) {
    final normalized = <int>{};
    for (final day in weekdays) {
      if (day >= 1 && day <= 7) normalized.add(day);
    }
    final result = normalized.toList()..sort();
    return result;
  }

  bool _validTime(int? hour, int? minute) {
    return hour != null &&
        minute != null &&
        hour >= 0 &&
        hour <= 23 &&
        minute >= 0 &&
        minute <= 59;
  }

  String _titleFor(
    String objectType,
    ReminderRuleType type,
    ReminderKind kind,
  ) {
    final subject = objectType == 'goal' ? '目标' : '待办';
    final prefix = switch (kind) {
      ReminderKind.alarm => '⏰',
      ReminderKind.popup => '🔔',
      ReminderKind.email => '✉️',
      ReminderKind.off => '🔕',
      ReminderKind.push => '🔔',
    };
    return switch (type) {
      ReminderRuleType.absolute => '$prefix $subject提醒',
      ReminderRuleType.relativeToDue => '$prefix $subject提前提醒',
      ReminderRuleType.dailyTime => '$prefix 每日$subject提醒',
      ReminderRuleType.weeklyTime => '$prefix 每周$subject提醒',
    };
  }

  String _todoPayload(String id, ReminderKind kind) {
    if (kind == ReminderKind.alarm) return 'duoyi://todo/$id?confirm=1';
    return 'duoyi://todo/$id';
  }

  Future<bool> _dispatchAnniversary(Anniversary item, DateTime remindAt) async {
    switch (item.reminderKind) {
      case ReminderKind.push:
        try {
          await notif.scheduleAnniversary(
            annId: item.id,
            title: item.title,
            whenDate: item.nextOccurrence,
            daysBefore: item.remindDaysBefore,
            hour: item.remindHour,
            minute: item.remindMinute,
          );
          return true;
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] anniversary push permission denied for ${item.id}: $e',
          );
          return false;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] anniversary push dispatch failed for ${item.id}: $e\n$st',
          );
          return false;
        }
      case ReminderKind.popup:
        try {
          await popup.scheduleOnce(
            id: _idFor('anni_${item.id}'),
            title: '🔔 纪念日提醒',
            body: item.remindDaysBefore == 0
                ? '今天是 ${item.title}'
                : '${item.remindDaysBefore} 天后是 ${item.title}',
            when: remindAt,
            payload: 'duoyi://anniversary/${item.id}',
          );
          return true;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] anniversary popup dispatch failed for ${item.id}: $e\n$st',
          );
          return false;
        }
      case ReminderKind.alarm:
        try {
          await alarm.scheduleFullScreen(
            id: _idFor('anni_alarm_${item.id}'),
            title: '⏰ 纪念日提醒',
            body: item.remindDaysBefore == 0
                ? '今天是 ${item.title}'
                : '${item.remindDaysBefore} 天后是 ${item.title}',
            when: remindAt,
            payload: 'duoyi://anniversary/${item.id}',
          );
          _recordAlarmScheduleIssue(
            relatedId: item.id,
            scheduledTime: remindAt,
          );
          return true;
        } on AlarmPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] anniversary alarm permission denied for ${item.id}: $e',
          );
          final id = _idFor('anni_alarm_${item.id}');
          if (await _alarmQueueAlreadyOwns(
            label: 'anniversary:${item.id}',
            expected: <int>{id},
          )) {
            _recordAlarmScheduleIssue(
              relatedId: item.id,
              scheduledTime: remindAt,
            );
            return true;
          }
          final fallbackScheduled = await _scheduleAnniversaryPushFallback(
            item,
          );
          _recordAlarmScheduleIssue(
            relatedId: item.id,
            scheduledTime: remindAt,
            blocking: !fallbackScheduled,
          );
          return fallbackScheduled;
        } on NotificationPermissionDeniedException catch (e) {
          debugPrint(
            '[ReminderScheduler] anniversary notification permission denied for ${item.id}: $e',
          );
          final id = _idFor('anni_alarm_${item.id}');
          if (await _alarmQueueAlreadyOwns(
            label: 'anniversary:${item.id}',
            expected: <int>{id},
          )) {
            _recordAlarmScheduleIssue(
              relatedId: item.id,
              scheduledTime: remindAt,
            );
            return true;
          }
          _recordAlarmScheduleIssue(
            relatedId: item.id,
            scheduledTime: remindAt,
            blocking: true,
          );
          return false;
        } on AlarmQueueHandoffException catch (e) {
          debugPrint(
            '[ReminderScheduler] anniversary alarm queue handoff failed for ${item.id}: $e',
          );
          _recordAlarmScheduleIssue(
            relatedId: item.id,
            scheduledTime: remindAt,
            blocking: true,
          );
          return false;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] anniversary alarm dispatch failed for ${item.id}: $e\n$st',
          );
          final id = _idFor('anni_alarm_${item.id}');
          if (await _alarmQueueAlreadyOwns(
            label: 'anniversary:${item.id}',
            expected: <int>{id},
          )) {
            _recordAlarmScheduleIssue(
              relatedId: item.id,
              scheduledTime: remindAt,
            );
            return true;
          }
          final fallbackScheduled = await _scheduleAnniversaryPushFallback(
            item,
          );
          _recordAlarmScheduleIssue(
            relatedId: item.id,
            scheduledTime: remindAt,
            blocking: !fallbackScheduled,
          );
          return fallbackScheduled;
        }
      case ReminderKind.email:
        try {
          await email.scheduleOnce(
            id: _idFor('anni_${item.id}'),
            title: '✉️ 纪念日提醒',
            body: item.remindDaysBefore == 0
                ? '今天是 ${item.title}'
                : '${item.remindDaysBefore} 天后是 ${item.title}',
            when: remindAt,
            payload: 'duoyi://anniversary/${item.id}',
          );
          return true;
        } catch (e, st) {
          debugPrint(
            '[ReminderScheduler] anniversary email dispatch failed for ${item.id}: $e\n$st',
          );
          return false;
        }
      case ReminderKind.off:
        return false;
    }
  }

  String? _fallbackPayload(String? payload) {
    if (payload == null) return null;
    final uri = Uri.tryParse(payload);
    if (uri == null) return payload;
    final query = Map<String, String>.from(uri.queryParameters)
      ..remove('confirm')
      ..['fallback'] = 'push';
    return uri.replace(queryParameters: query).toString();
  }

  /// 目标锚定日：未设置开始日期时按创建日开启；提醒只从今天或未来开始注册。
  DateTime _goalAnchorDate(GoalItem g, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final start = g.startDate ?? AppClock.toLocal(g.createdAt);
    final startDay = DateTime(start.year, start.month, start.day);
    return startDay.isAfter(today) ? startDay : today;
  }

  // -------------------------------------------------------------------------
  // 内部：字符串 id → 稳定 int（与 `NotificationService._idFor` 等价）
  // -------------------------------------------------------------------------

  int _idFor(String key) {
    int h = 0;
    for (final c in key.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _avoidReservedNotificationId(h);
  }

  int _avoidReservedNotificationId(int id) {
    var next = id;
    while (_reservedNotificationIds.contains(next)) {
      next = (next + 1) & 0x7fffffff;
    }
    return next;
  }

  static const Set<int> _reservedNotificationIds = <int>{
    880016,
    880017,
    880018,
    880019,
    880020,
    880021,
    880022,
    880023,
    919001,
    919002,
    919003,
    919004,
    919005,
    919006,
    919007,
  };

  DateTime _anniversaryReminderAt(Anniversary item) {
    final next = item.nextOccurrence;
    return AppClock.date(
      next.year,
      next.month,
      next.day - item.remindDaysBefore,
      item.remindHour,
      item.remindMinute,
    );
  }

  String _anniversaryScope(Anniversary item, DateTime when) {
    return [
      item.reminderKind.index,
      item.title,
      item.remindDaysBefore,
      item.remindHour,
      item.remindMinute,
      when.toIso8601String(),
    ].join('|');
  }
}

/// 周年提醒时刻已过（如打开 app 时当天的提醒时刻已经过去）时，
/// 推进到下一年同一时刻，避免该周年被跳过后整年漏提醒；
/// 闰日（2/29）推进后由 DateTime 自动滚动到 3/1。未来时刻原样返回。
DateTime rollAnniversaryRemindAtForward(DateTime remindAt, DateTime now) {
  if (remindAt.isAfter(now)) return remindAt;
  return AppClock.date(
    remindAt.year + 1,
    remindAt.month,
    remindAt.day,
    remindAt.hour,
    remindAt.minute,
  );
}
