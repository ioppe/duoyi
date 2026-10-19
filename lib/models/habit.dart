import '../core/app_clock.dart';
import '../core/i18n.dart';
import 'goal.dart'
    show ReminderKind, ReminderPlan, ReminderRule, ReminderRuleType;

/// 习惯类型：正向=养成；负向=戒除 (记录"今天没做到")。
enum HabitKind { positive, negative }

/// 弹性打卡周期：一周/一月至少完成 N 次。
enum HabitFlexPeriod { week, month }

const String defaultHabitIconToken = 'track_changes_outlined';

int _readInt(Object? value, int fallback) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int? _readPositiveInt(Object? value) {
  if (value == null) return null;
  final parsed = _readInt(value, 0);
  return parsed > 0 ? parsed : null;
}

HabitFlexPeriod? _readFlexPeriod(Object? value) {
  if (value == null) return null;
  if (value is num) {
    final index = value.toInt();
    if (index >= 0 && index < HabitFlexPeriod.values.length) {
      return HabitFlexPeriod.values[index];
    }
  }
  final raw = value.toString();
  for (final period in HabitFlexPeriod.values) {
    if (period.name == raw) return period;
  }
  return null;
}

ReminderPlan _legacyReminderPlan({
  required bool remind,
  required int? hour,
  required int? minute,
  required List<int>? activeWeekdays,
}) {
  if (!remind || hour == null || minute == null) {
    return const ReminderPlan.disabled();
  }
  final weekdays =
      (activeWeekdays ?? const [0, 1, 2, 3, 4, 5, 6])
          .where((d) => d >= 0 && d <= 6)
          .map((d) => d + 1)
          .toSet()
          .toList()
        ..sort();
  final fullWeek = weekdays.length == 7;
  return ReminderPlan(
    enabled: true,
    rules: [
      ReminderRule(
        id: 'habit-reminder',
        enabled: true,
        type: fullWeek
            ? ReminderRuleType.dailyTime
            : ReminderRuleType.weeklyTime,
        kind: ReminderKind.popup,
        hour: hour,
        minute: minute,
        weekdays: fullWeek ? const <int>[] : weekdays,
      ),
    ],
  );
}

ReminderPlan _normalizeHabitReminderPlan(ReminderPlan plan) {
  return ReminderPlan(
    enabled: plan.enabled,
    rules: plan.rules.map(_normalizeHabitReminderRule).toList(),
  );
}

ReminderRule _normalizeHabitReminderRule(ReminderRule rule) {
  var type = rule.type;
  var weekdays = rule.weekdays;
  if (type == ReminderRuleType.absolute ||
      type == ReminderRuleType.relativeToDue) {
    type = ReminderRuleType.dailyTime;
    weekdays = const <int>[];
  } else if (type == ReminderRuleType.weeklyTime) {
    weekdays =
        rule.weekdays.where((day) => day >= 1 && day <= 7).toSet().toList()
          ..sort();
    if (weekdays.isEmpty) type = ReminderRuleType.dailyTime;
  } else {
    weekdays = const <int>[];
  }

  return rule.copyWith(
    type: type,
    kind: ReminderKind.popup,
    weekdays: weekdays,
    fullScreen: false,
    snoozeMinutes: 0,
    repeatCount: 0,
  );
}

class HabitPeriodBounds {
  final DateTime start;
  final DateTime end;

  const HabitPeriodBounds({required this.start, required this.end});
}

class HabitFlexProgress {
  final HabitFlexPeriod period;
  final DateTime start;
  final DateTime end;
  final int completed;
  final int target;

  const HabitFlexProgress({
    required this.period,
    required this.start,
    required this.end,
    required this.completed,
    required this.target,
  });

  bool get isCompleted => completed >= target;

  double get ratio =>
      target <= 0 ? 0 : (completed / target).clamp(0.0, 1.0).toDouble();

  String get labelPrefix => switch (period) {
    HabitFlexPeriod.week => '本周',
    HabitFlexPeriod.month => '本月',
  };

  String get label => '$labelPrefix $completed/$target';
}

class Habit {
  final String id;
  String name;
  String icon;
  int colorValue;
  HabitKind kind;
  List<int> activeWeekdays;
  int targetCount;
  String? unit; // 计量单位，如 '次/杯/分钟'
  int currentStreak;
  int bestStreak;
  Map<String, int> completions;
  Map<String, DateTime> completionUpdatedAt;
  String? category;
  List<String> tags;
  int weeklyTarget;
  int? flexTarget;
  HabitFlexPeriod? flexPeriod;
  DateTime? startDate;
  DateTime? endDate;
  int sortOrder;
  bool remind;
  int? remindHour;
  int? remindMinute;
  ReminderPlan reminderPlan;
  DateTime createdAt;
  DateTime updatedAt;

  Habit({
    required this.id,
    required this.name,
    this.icon = defaultHabitIconToken,
    this.colorValue = 0xFF4CAF50,
    this.kind = HabitKind.positive,
    List<int>? activeWeekdays,
    this.targetCount = 1,
    this.unit,
    this.currentStreak = 0,
    this.bestStreak = 0,
    Map<String, int>? completions,
    Map<String, DateTime>? completionUpdatedAt,
    this.category,
    List<String>? tags,
    this.weeklyTarget = 7,
    this.flexTarget,
    this.flexPeriod,
    this.startDate,
    this.endDate,
    this.sortOrder = 0,
    this.remind = false,
    this.remindHour,
    this.remindMinute,
    ReminderPlan? reminderPlan,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : activeWeekdays = activeWeekdays ?? [0, 1, 2, 3, 4, 5, 6],
       completions = completions ?? {},
       completionUpdatedAt = completionUpdatedAt ?? {},
       tags = tags ?? [],
       reminderPlan = _normalizeHabitReminderPlan(
         reminderPlan ??
             _legacyReminderPlan(
               remind: remind,
               hour: remindHour,
               minute: remindMinute,
               activeWeekdays: activeWeekdays,
             ),
       ),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  Habit copyWith({
    String? name,
    String? icon,
    int? colorValue,
    HabitKind? kind,
    List<int>? activeWeekdays,
    int? targetCount,
    String? unit,
    int? currentStreak,
    int? bestStreak,
    Map<String, int>? completions,
    Map<String, DateTime>? completionUpdatedAt,
    String? category,
    List<String>? tags,
    int? weeklyTarget,
    int? flexTarget,
    HabitFlexPeriod? flexPeriod,
    DateTime? startDate,
    DateTime? endDate,
    int? sortOrder,
    bool? remind,
    int? remindHour,
    int? remindMinute,
    ReminderPlan? reminderPlan,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearUnit = false,
    bool clearCategory = false,
    bool clearFlexRule = false,
    bool clearStartDate = false,
    bool clearEndDate = false,
  }) {
    final nextActiveWeekdays =
        activeWeekdays ?? List<int>.from(this.activeWeekdays);
    final nextRemind = remind ?? this.remind;
    final nextRemindHour = remindHour ?? this.remindHour;
    final nextRemindMinute = remindMinute ?? this.remindMinute;
    final legacyReminderChanged =
        reminderPlan == null &&
        (remind != null ||
            remindHour != null ||
            remindMinute != null ||
            activeWeekdays != null);
    final nextReminderPlan =
        reminderPlan ??
        (legacyReminderChanged
            ? _legacyReminderPlan(
                remind: nextRemind,
                hour: nextRemindHour,
                minute: nextRemindMinute,
                activeWeekdays: nextActiveWeekdays,
              )
            : this.reminderPlan);
    return Habit(
      id: id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      colorValue: colorValue ?? this.colorValue,
      kind: kind ?? this.kind,
      activeWeekdays: nextActiveWeekdays,
      targetCount: targetCount ?? this.targetCount,
      unit: clearUnit ? null : unit ?? this.unit,
      currentStreak: currentStreak ?? this.currentStreak,
      bestStreak: bestStreak ?? this.bestStreak,
      completions: completions != null
          ? Map<String, int>.from(completions)
          : Map<String, int>.from(this.completions),
      completionUpdatedAt: completionUpdatedAt != null
          ? Map<String, DateTime>.from(completionUpdatedAt)
          : Map<String, DateTime>.from(this.completionUpdatedAt),
      category: clearCategory ? null : category ?? this.category,
      tags: tags ?? List<String>.from(this.tags),
      weeklyTarget: weeklyTarget ?? this.weeklyTarget,
      flexTarget: clearFlexRule ? null : flexTarget ?? this.flexTarget,
      flexPeriod: clearFlexRule ? null : flexPeriod ?? this.flexPeriod,
      startDate: clearStartDate ? null : startDate ?? this.startDate,
      endDate: clearEndDate ? null : endDate ?? this.endDate,
      sortOrder: sortOrder ?? this.sortOrder,
      remind: nextRemind,
      remindHour: nextRemindHour,
      remindMinute: nextRemindMinute,
      reminderPlan: nextReminderPlan,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    final legacyRule = reminderPlan.primaryRule;
    final legacyEnabled =
        reminderPlan.enabled &&
        legacyRule != null &&
        legacyRule.enabled &&
        legacyRule.kind != ReminderKind.off &&
        legacyRule.hour != null &&
        legacyRule.minute != null;
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'colorValue': colorValue,
      'kind': kind.index,
      'activeWeekdays': activeWeekdays,
      'targetCount': targetCount,
      'unit': unit,
      'currentStreak': currentStreak,
      'bestStreak': bestStreak,
      'completions': completions,
      'completionUpdatedAt': completionUpdatedAt.map(
        (key, value) => MapEntry(key, value.toIso8601String()),
      ),
      'category': category,
      'tags': tags,
      'weeklyTarget': weeklyTarget,
      'flexTarget': flexTarget,
      'flexPeriod': flexPeriod?.name,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'sortOrder': sortOrder,
      'remind': legacyEnabled,
      'remindHour': legacyEnabled ? legacyRule.hour : remindHour,
      'remindMinute': legacyEnabled ? legacyRule.minute : remindMinute,
      'reminderPlan': reminderPlan.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Habit.fromJson(Map<String, dynamic> json) {
    final kindIndex = _readInt(json['kind'], 0);
    final weekdaysRaw = json['activeWeekdays'] as List<dynamic>?;
    final completionsRaw = json['completions'];
    final completionUpdatedAtRaw = json['completionUpdatedAt'];
    final createdAtRaw = json['createdAt']?.toString();
    final updatedAtRaw = json['updatedAt']?.toString();
    final target = _readInt(json['targetCount'], 1);
    final flexTarget = _readPositiveInt(json['flexTarget']);

    final activeWeekdays =
        weekdaysRaw
            ?.map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
            .whereType<int>()
            .where((e) => e >= 0 && e <= 6)
            .toList() ??
        [0, 1, 2, 3, 4, 5, 6];
    final remind = json['remind'] == true;
    final remindHour = json['remindHour'] == null
        ? null
        : _readInt(json['remindHour'], 0).clamp(0, 23).toInt();
    final remindMinute = json['remindMinute'] == null
        ? null
        : _readInt(json['remindMinute'], 0).clamp(0, 59).toInt();
    var reminderPlan = json['reminderPlan'] is Map
        ? ReminderPlan.fromJson(
            Map<String, dynamic>.from(json['reminderPlan'] as Map),
          )
        : _legacyReminderPlan(
            remind: remind,
            hour: remindHour,
            minute: remindMinute,
            activeWeekdays: activeWeekdays,
          );
    if (!reminderPlan.enabled && remind) {
      reminderPlan = _legacyReminderPlan(
        remind: remind,
        hour: remindHour,
        minute: remindMinute,
        activeWeekdays: activeWeekdays,
      );
    }
    reminderPlan = _normalizeHabitReminderPlan(reminderPlan);

    return Habit(
      id: (json['id'] ?? DateTime.now().microsecondsSinceEpoch).toString(),
      name: (json['name'] ?? '未命名习惯').toString(),
      icon: (json['icon'] ?? defaultHabitIconToken).toString(),
      colorValue: _readInt(json['colorValue'], 0xFF4CAF50),
      kind: HabitKind
          .values[kindIndex.clamp(0, HabitKind.values.length - 1).toInt()],
      activeWeekdays: activeWeekdays,
      targetCount: target < 1 ? 1 : target,
      unit: json['unit']?.toString(),
      currentStreak: _readInt(json['currentStreak'], 0),
      bestStreak: _readInt(json['bestStreak'], 0),
      completions: completionsRaw is Map
          ? completionsRaw.map((key, value) {
              final count = _readInt(value, 0);
              return MapEntry(key.toString(), count < 0 ? 0 : count);
            })
          : {},
      completionUpdatedAt: completionUpdatedAtRaw is Map
          ? {
              for (final entry in completionUpdatedAtRaw.entries)
                if (DateTime.tryParse(entry.value?.toString() ?? '') != null)
                  entry.key.toString(): DateTime.parse(entry.value.toString()),
            }
          : {},
      category: json['category']?.toString(),
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          [],
      weeklyTarget: _readInt(json['weeklyTarget'], 7),
      flexTarget: flexTarget,
      flexPeriod: flexTarget == null
          ? null
          : _readFlexPeriod(json['flexPeriod']) ?? HabitFlexPeriod.week,
      startDate: json['startDate'] != null
          ? DateTime.tryParse(json['startDate'].toString())
          : null,
      endDate: json['endDate'] != null
          ? DateTime.tryParse(json['endDate'].toString())
          : null,
      sortOrder: _readInt(json['sortOrder'], 0),
      remind: reminderPlan.enabled && reminderPlan.primaryRule != null,
      remindHour: remindHour,
      remindMinute: remindMinute,
      reminderPlan: reminderPlan,
      createdAt: createdAtRaw == null
          ? DateTime.now()
          : DateTime.tryParse(createdAtRaw) ?? DateTime.now(),
      updatedAt: updatedAtRaw == null
          ? (createdAtRaw == null
                ? DateTime.now()
                : DateTime.tryParse(createdAtRaw) ?? DateTime.now())
          : DateTime.tryParse(updatedAtRaw) ?? DateTime.now(),
    );
  }

  int todayCount() => completions[todayKey()] ?? 0;

  DateTime _dayOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  bool isWithinDateRange(DateTime date) {
    final day = _dayOnly(date);
    final start = startDate == null ? null : _dayOnly(startDate!);
    final end = endDate == null ? null : _dayOnly(endDate!);
    if (start != null && day.isBefore(start)) return false;
    if (end != null && day.isAfter(end)) return false;
    return true;
  }

  bool get hasFlexRule =>
      kind == HabitKind.positive &&
      flexTarget != null &&
      flexTarget! > 0 &&
      flexPeriod != null;

  int get effectiveFlexTarget =>
      (flexTarget ?? weeklyTarget).clamp(1, 9999).toInt();

  /// 连续打卡计数单位（天 / 弹性周期为周、月）。
  /// 经 I18n 取词：en 骨架 habitStreakLabel 已译为 'Streak'，单位若仍硬编码
  /// 中文会拼出「Streak 5 天」式混搭。zh 取值与原硬编码逐字节一致。
  String get streakUnitLabel {
    if (!hasFlexRule) return I18n.tr('unit.day');
    return switch (flexPeriod!) {
      HabitFlexPeriod.week => I18n.tr('habit.unit.week'),
      HabitFlexPeriod.month => I18n.tr('habit.unit.month'),
    };
  }

  String get flexPeriodGoalLabel {
    if (!hasFlexRule) return '';
    return switch (flexPeriod!) {
      HabitFlexPeriod.week => '每周目标: $effectiveFlexTarget 次/周',
      HabitFlexPeriod.month => '每月目标: $effectiveFlexTarget 次/月',
    };
  }

  double progressForCount(int count) {
    if (kind == HabitKind.negative) {
      return count == 0 ? 1.0 : 0.0;
    }
    return targetCount > 0 ? (count / targetCount).clamp(0.0, 1.0) : 0.0;
  }

  double todayProgress() => progressForDate(AppClock.now());

  String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String todayKey() => dateKey(AppClock.now());

  int countForDate(DateTime d) => completions[dateKey(d)] ?? 0;
  double progressForDate(DateTime d) {
    if (!activeForDate(d)) return 0;
    if (hasFlexRule) return flexProgressForDate(d)?.ratio ?? 0;
    return progressForCount(countForDate(d));
  }

  /// 正向习惯：今日完成 >= 目标即"达标"；
  /// 负向习惯：今日为零即"戒除成功"。
  bool isCompletedToday() => isCompletedForDate(AppClock.now());

  bool isCompletedForDate(DateTime d) {
    if (!activeForDate(d)) return false;
    if (hasFlexRule) return flexProgressForDate(d)?.isCompleted ?? false;
    return kind == HabitKind.positive
        ? countForDate(d) >= targetCount
        : countForDate(d) == 0;
  }

  bool activeForDate(DateTime d) =>
      isWithinDateRange(d) && activeWeekdays.contains(d.weekday - 1);

  bool isActiveToday() => activeForDate(AppClock.now());

  HabitPeriodBounds periodBoundsForDate(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return switch (flexPeriod ?? HabitFlexPeriod.week) {
      HabitFlexPeriod.week => HabitPeriodBounds(
        start: day.subtract(Duration(days: day.weekday - 1)),
        end: day.add(Duration(days: DateTime.daysPerWeek - day.weekday)),
      ),
      HabitFlexPeriod.month => HabitPeriodBounds(
        start: DateTime(day.year, day.month),
        end: DateTime(day.year, day.month + 1, 0),
      ),
    };
  }

  HabitPeriodBounds previousPeriodBounds(HabitPeriodBounds bounds) {
    return switch (flexPeriod ?? HabitFlexPeriod.week) {
      HabitFlexPeriod.week => HabitPeriodBounds(
        start: bounds.start.subtract(const Duration(days: 7)),
        end: bounds.end.subtract(const Duration(days: 7)),
      ),
      HabitFlexPeriod.month => HabitPeriodBounds(
        start: DateTime(bounds.start.year, bounds.start.month - 1),
        end: DateTime(bounds.start.year, bounds.start.month, 0),
      ),
    };
  }

  int completionDaysInPeriod(DateTime date) {
    final bounds = periodBoundsForDate(date);
    return completionCountInRange(bounds.start, bounds.end);
  }

  HabitFlexProgress? flexProgressForDate(DateTime date) {
    if (!hasFlexRule || !isWithinDateRange(date)) return null;
    final bounds = periodBoundsForDate(date);
    return HabitFlexProgress(
      period: flexPeriod!,
      start: bounds.start,
      end: bounds.end,
      completed: completionCountInRange(bounds.start, bounds.end),
      target: effectiveFlexTarget,
    );
  }

  List<DateTime> completionDatesInRange(DateTime start, DateTime end) {
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    if (endDay.isBefore(startDay)) return const [];
    if (!hasFlexRule) {
      final dates = <DateTime>[];
      for (
        var date = startDay;
        !date.isAfter(endDay);
        date = date.add(const Duration(days: 1))
      ) {
        if (!activeForDate(date)) continue;
        if (isCompletedForDate(date)) {
          dates.add(DateTime(date.year, date.month, date.day, 12));
        }
      }
      return dates;
    }

    final dates = <DateTime>[];
    var bounds = periodBoundsForDate(startDay);
    while (!bounds.start.isAfter(endDay)) {
      final overlapStart = bounds.start.isBefore(startDay)
          ? startDay
          : bounds.start;
      final overlapEnd = bounds.end.isAfter(endDay) ? endDay : bounds.end;
      final completedByRangeEnd =
          completionCountInRange(bounds.start, overlapEnd) >=
          effectiveFlexTarget;
      if (completedByRangeEnd) {
        DateTime? representative;
        for (
          var date = overlapStart;
          !date.isAfter(overlapEnd);
          date = date.add(const Duration(days: 1))
        ) {
          if (activeForDate(date) && countForDate(date) > 0) {
            representative = DateTime(date.year, date.month, date.day, 12);
          }
        }
        if (representative != null) dates.add(representative);
      }
      bounds = switch (flexPeriod!) {
        HabitFlexPeriod.week => HabitPeriodBounds(
          start: bounds.start.add(const Duration(days: 7)),
          end: bounds.end.add(const Duration(days: 7)),
        ),
        HabitFlexPeriod.month => HabitPeriodBounds(
          start: DateTime(bounds.start.year, bounds.start.month + 1),
          end: DateTime(bounds.start.year, bounds.start.month + 2, 0),
        ),
      };
    }
    return dates;
  }

  /// 本地格式显示：  "2 杯 / 8 杯"
  String formatCountForDate(DateTime d) {
    final c = countForDate(d);
    final u = unit ?? '次';
    if (hasFlexRule) {
      final progress = flexProgressForDate(d);
      return progress == null ? '$c $u' : '$c $u · ${progress.label}';
    }
    return kind == HabitKind.positive ? '$c $u / $targetCount $u' : '已记录 $c $u';
  }

  Map<String, int> heatmapData(int weeks) {
    final data = <String, int>{};
    final now = AppClock.today();
    final safeTarget = targetCount < 1 ? 1 : targetCount;
    for (int w = 0; w < weeks; w++) {
      for (int d = 0; d < 7; d++) {
        final date = now.subtract(Duration(days: w * 7 + (6 - d)));
        final key = dateKey(date);
        final count = completions[key] ?? 0;
        if (!activeForDate(date)) {
          data[key] = 0;
        } else if (hasFlexRule) {
          final progress = flexProgressForDate(date)?.ratio ?? 0;
          data[key] = progress <= 0
              ? 0
              : ((progress * 5).ceil().clamp(1, 5)).toInt();
        } else if (kind == HabitKind.positive) {
          if (count > 0) {
            data[key] = ((count / safeTarget) * 5).ceil().clamp(1, 5);
          } else {
            data[key] = 0;
          }
        } else {
          // 负向：0 = 成功(满格)；>0 = 破戒
          data[key] = count == 0 ? 5 : 0;
        }
      }
    }
    return data;
  }

  int completionCountInRange(DateTime start, DateTime end) {
    int count = 0;
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      if (!activeForDate(d)) continue;
      if (kind == HabitKind.positive
          ? countForDate(d) > 0
          : countForDate(d) == 0) {
        count++;
      }
    }
    return count;
  }

  double weeklyCompletionRate() {
    final now = AppClock.today();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final completed = completionCountInRange(monday, now);
    var expected = 0;
    for (var d = monday; !d.isAfter(now); d = d.add(const Duration(days: 1))) {
      if (activeForDate(d)) expected++;
    }
    return expected > 0 ? completed / expected : 0;
  }
}
