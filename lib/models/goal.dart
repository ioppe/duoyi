import 'package:uuid/uuid.dart';

import '../core/app_clock.dart';
import 'recurrence.dart';

const _uuid = Uuid();
const Object _reminderCopyUnset = Object();

/// 目标分类（与推荐目标库一致）。
///
/// 旧版 JSON 中可能以 `String?` 保存分类名（例如 'health'），
/// 迁移时会按名称匹配；匹配不到则回退到 [GoalCategory.custom]。
enum GoalCategory { recommend, health, study, sport, emotion, custom }

/// 调度模式：固定日期 vs 在区间内随机派发。
enum SchedulingMode { fixed, random }

/// 提醒类型：
/// - [ReminderKind.push] 走通知通道（`duoyi_general`）。
/// - [ReminderKind.popup] 走轻量弹出提醒通道，适合不需要强提醒的场景。
/// - [ReminderKind.alarm] 走闹钟通道（`duoyi_alarm`，全屏 / 高优先级）。
/// - [ReminderKind.email] 走邮件提醒出口；保留为后台/历史兼容通道，不作为本地提醒方式展示。
/// - [ReminderKind.off] 保留规则内容但不派发提醒。
enum ReminderKind { push, alarm, email, popup, off }

const userSelectableReminderKinds = <ReminderKind>[
  ReminderKind.push,
  ReminderKind.popup,
  ReminderKind.alarm,
  ReminderKind.off,
];

ReminderKind normalizeUserSelectableReminderKind(ReminderKind kind) {
  return userSelectableReminderKinds.contains(kind) ? kind : ReminderKind.push;
}

/// 目标调度策略：结合 [RecurrenceRule] 决定具体派发日期。
///
/// - `fixed` 模式：配合 `fixedWeekdays`（周重复）或 `fixedMonthDays`（月重复）
///   指定具体星期或日期。
/// - `random` 模式：在 `[anchor + randomMinGapDays, upperBound]` 之间按稳定
///   种子随机采样；`randomMaxPerWeek` / `randomMaxPerMonth` 控制派发上限。
class GoalScheduling {
  final SchedulingMode mode;
  final List<int>? fixedWeekdays;
  final List<int>? fixedMonthDays;
  final int? randomMinGapDays;
  final int? randomMaxPerWeek;
  final int? randomMaxPerMonth;

  const GoalScheduling({
    required this.mode,
    this.fixedWeekdays,
    this.fixedMonthDays,
    this.randomMinGapDays,
    this.randomMaxPerWeek,
    this.randomMaxPerMonth,
  });

  /// 固定模式的便捷构造；可选传入固定的星期 / 月日。
  const GoalScheduling.fixed({
    List<int>? fixedWeekdays,
    List<int>? fixedMonthDays,
  }) : this(
         mode: SchedulingMode.fixed,
         fixedWeekdays: fixedWeekdays,
         fixedMonthDays: fixedMonthDays,
       );

  /// 随机模式的便捷构造。
  const GoalScheduling.random({
    int minGapDays = 1,
    int? maxPerWeek,
    int? maxPerMonth,
  }) : this(
         mode: SchedulingMode.random,
         randomMinGapDays: minGapDays,
         randomMaxPerWeek: maxPerWeek,
         randomMaxPerMonth: maxPerMonth,
       );

  GoalScheduling copyWith({
    SchedulingMode? mode,
    List<int>? fixedWeekdays,
    List<int>? fixedMonthDays,
    int? randomMinGapDays,
    int? randomMaxPerWeek,
    int? randomMaxPerMonth,
  }) => GoalScheduling(
    mode: mode ?? this.mode,
    fixedWeekdays: fixedWeekdays ?? this.fixedWeekdays,
    fixedMonthDays: fixedMonthDays ?? this.fixedMonthDays,
    randomMinGapDays: randomMinGapDays ?? this.randomMinGapDays,
    randomMaxPerWeek: randomMaxPerWeek ?? this.randomMaxPerWeek,
    randomMaxPerMonth: randomMaxPerMonth ?? this.randomMaxPerMonth,
  );

  Map<String, dynamic> toJson() => {
    'mode': mode.index,
    'fixedWeekdays': fixedWeekdays,
    'fixedMonthDays': fixedMonthDays,
    'randomMinGapDays': randomMinGapDays,
    'randomMaxPerWeek': randomMaxPerWeek,
    'randomMaxPerMonth': randomMaxPerMonth,
  };

  factory GoalScheduling.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const GoalScheduling.fixed();
    final rawMode = json['mode'];
    final mode =
        _enumFromIndex(
          SchedulingMode.values,
          rawMode is num ? rawMode.toInt() : null,
        ) ??
        SchedulingMode.fixed;
    return GoalScheduling(
      mode: mode,
      fixedWeekdays: (json['fixedWeekdays'] as List?)
          ?.whereType<num>()
          .map((e) => e.toInt())
          .toList(),
      fixedMonthDays: (json['fixedMonthDays'] as List?)
          ?.whereType<num>()
          .map((e) => e.toInt())
          .toList(),
      randomMinGapDays: (json['randomMinGapDays'] as num?)?.toInt(),
      randomMaxPerWeek: (json['randomMaxPerWeek'] as num?)?.toInt(),
      randomMaxPerMonth: (json['randomMaxPerMonth'] as num?)?.toInt(),
    );
  }
}

/// 提醒配置：目标 / 任务 / 习惯共用。
///
/// `enabled = false` 时所有其它字段仅作为"最后一次设置"的记忆，
/// 不会触发任何系统提醒。
class ReminderConfig {
  final bool enabled;
  final ReminderKind kind;
  final int? hour;
  final int? minute;
  final int daysBefore;
  final bool vibrate;
  final bool fullScreen;

  const ReminderConfig({
    this.enabled = false,
    this.kind = ReminderKind.push,
    this.hour,
    this.minute,
    this.daysBefore = 0,
    this.vibrate = true,
    this.fullScreen = false,
  });

  /// 未启用的默认值。
  const ReminderConfig.disabled() : this(enabled: false);

  ReminderConfig copyWith({
    bool? enabled,
    ReminderKind? kind,
    int? hour,
    int? minute,
    int? daysBefore,
    bool? vibrate,
    bool? fullScreen,
  }) {
    final nextKind = kind ?? this.kind;
    return ReminderConfig(
      enabled: nextKind == ReminderKind.off ? false : enabled ?? this.enabled,
      kind: nextKind,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      daysBefore: daysBefore ?? this.daysBefore,
      vibrate: vibrate ?? this.vibrate,
      fullScreen: nextKind == ReminderKind.alarm
          ? fullScreen ?? this.fullScreen
          : false,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'kind': kind.index,
    'hour': hour,
    'minute': minute,
    'daysBefore': daysBefore,
    'vibrate': vibrate,
    'fullScreen': fullScreen,
  };

  factory ReminderConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ReminderConfig.disabled();
    final rawKind = json['kind'];
    final kind =
        _enumFromIndex(
          ReminderKind.values,
          rawKind is num ? rawKind.toInt() : null,
        ) ??
        ReminderKind.push;
    return ReminderConfig(
      enabled: kind == ReminderKind.off ? false : json['enabled'] == true,
      kind: kind,
      hour: (json['hour'] as num?)?.toInt(),
      minute: (json['minute'] as num?)?.toInt(),
      daysBefore: (json['daysBefore'] as num?)?.toInt() ?? 0,
      vibrate: json['vibrate'] ?? true,
      fullScreen:
          kind == ReminderKind.alarm &&
          (json['fullScreen'] ?? kind == ReminderKind.alarm),
    );
  }
}

enum ReminderRuleType { absolute, relativeToDue, dailyTime, weeklyTime }

class ReminderRule {
  /// 常用提前提醒模板，单位为分钟，负数表示相对截止时间提前。
  ///
  /// 覆盖竞品中高频的"提前 5 分钟 / 15 分钟 / 1 小时 / 1 天"录入路径，
  /// UI 层可直接复用，避免不同提醒入口维护不一致的快捷选项。
  static const relativeOffsetPresetMinutes = <int>[
    -5,
    -15,
    -30,
    -60,
    -24 * 60,
    -2 * 24 * 60,
    -3 * 24 * 60,
  ];

  final String id;
  final bool enabled;
  final ReminderRuleType type;
  final ReminderKind kind;
  final int? hour;
  final int? minute;
  final int? offsetMinutes;
  final List<int> weekdays;
  final bool vibrate;
  final bool fullScreen;
  final int snoozeMinutes;
  final int repeatCount;

  ReminderRule({
    String? id,
    this.enabled = true,
    this.type = ReminderRuleType.absolute,
    this.kind = ReminderKind.push,
    this.hour,
    this.minute,
    this.offsetMinutes,
    List<int>? weekdays,
    this.vibrate = true,
    this.fullScreen = false,
    this.snoozeMinutes = 0,
    this.repeatCount = 0,
  }) : id = id ?? _uuid.v4(),
       weekdays = List<int>.unmodifiable(weekdays ?? const <int>[]);

  ReminderRule copyWith({
    Object? id = _reminderCopyUnset,
    bool? enabled,
    ReminderRuleType? type,
    ReminderKind? kind,
    Object? hour = _reminderCopyUnset,
    Object? minute = _reminderCopyUnset,
    Object? offsetMinutes = _reminderCopyUnset,
    Object? weekdays = _reminderCopyUnset,
    bool? vibrate,
    bool? fullScreen,
    int? snoozeMinutes,
    int? repeatCount,
  }) {
    final nextKind = kind ?? this.kind;
    return ReminderRule(
      id: identical(id, _reminderCopyUnset) ? this.id : id as String?,
      enabled: nextKind == ReminderKind.off ? false : enabled ?? this.enabled,
      type: type ?? this.type,
      kind: nextKind,
      hour: identical(hour, _reminderCopyUnset) ? this.hour : hour as int?,
      minute: identical(minute, _reminderCopyUnset)
          ? this.minute
          : minute as int?,
      offsetMinutes: identical(offsetMinutes, _reminderCopyUnset)
          ? this.offsetMinutes
          : offsetMinutes as int?,
      weekdays: identical(weekdays, _reminderCopyUnset)
          ? this.weekdays
          : List<int>.unmodifiable((weekdays as List).cast<int>()),
      vibrate: vibrate ?? this.vibrate,
      fullScreen: nextKind == ReminderKind.alarm
          ? fullScreen ?? this.fullScreen
          : false,
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      repeatCount: repeatCount ?? this.repeatCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'enabled': enabled,
    'type': type.index,
    'kind': kind.index,
    'hour': hour,
    'minute': minute,
    'offsetMinutes': offsetMinutes,
    'weekdays': weekdays,
    'vibrate': vibrate,
    'fullScreen': fullScreen,
    'snoozeMinutes': snoozeMinutes,
    'repeatCount': repeatCount,
  };

  factory ReminderRule.fromJson(Map<String, dynamic> json) {
    final type =
        _enumFromIndex(
          ReminderRuleType.values,
          (json['type'] as num?)?.toInt(),
        ) ??
        ReminderRuleType.absolute;
    final kind =
        _enumFromIndex(ReminderKind.values, (json['kind'] as num?)?.toInt()) ??
        ReminderKind.push;
    return ReminderRule(
      id: json['id']?.toString(),
      enabled: kind == ReminderKind.off ? false : json['enabled'] != false,
      type: type,
      kind: kind,
      hour: (json['hour'] as num?)?.toInt(),
      minute: (json['minute'] as num?)?.toInt(),
      offsetMinutes: (json['offsetMinutes'] as num?)?.toInt(),
      weekdays:
          (json['weekdays'] as List?)
              ?.whereType<num>()
              .map((e) => e.toInt())
              .toList() ??
          const <int>[],
      vibrate: json['vibrate'] ?? true,
      fullScreen:
          kind == ReminderKind.alarm &&
          (json['fullScreen'] ?? kind == ReminderKind.alarm),
      snoozeMinutes: (json['snoozeMinutes'] as num?)?.toInt() ?? 0,
      repeatCount: (json['repeatCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class ReminderPlan {
  final bool enabled;
  final List<ReminderRule> rules;

  ReminderPlan({this.enabled = false, List<ReminderRule>? rules})
    : rules = List<ReminderRule>.unmodifiable(rules ?? const <ReminderRule>[]);

  const ReminderPlan.disabled()
    : enabled = false,
      rules = const <ReminderRule>[];

  bool get isEmpty => rules.isEmpty;

  ReminderRule? get primaryRule {
    for (final rule in rules) {
      if (rule.enabled && rule.kind != ReminderKind.off) return rule;
    }
    return rules.isEmpty ? null : rules.first;
  }

  ReminderPlan copyWith({bool? enabled, List<ReminderRule>? rules}) {
    return ReminderPlan(
      enabled: enabled ?? this.enabled,
      rules: rules ?? this.rules,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'rules': rules.map((r) => r.toJson()).toList(),
  };

  factory ReminderPlan.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ReminderPlan.disabled();
    return ReminderPlan(
      enabled: json['enabled'] == true,
      rules:
          (json['rules'] as List?)
              ?.whereType<Map>()
              .map(
                (raw) => ReminderRule.fromJson(Map<String, dynamic>.from(raw)),
              )
              .toList() ??
          const <ReminderRule>[],
    );
  }

  factory ReminderPlan.fromLegacy(ReminderConfig old) {
    if (!old.enabled) return const ReminderPlan.disabled();
    final type = old.daysBefore > 0
        ? ReminderRuleType.relativeToDue
        : ReminderRuleType.absolute;
    return ReminderPlan(
      enabled: true,
      rules: [
        ReminderRule(
          id: _legacyRuleId(old),
          enabled: true,
          type: type,
          kind: old.kind,
          hour: old.hour,
          minute: old.minute,
          offsetMinutes: old.daysBefore > 0 ? -old.daysBefore * 24 * 60 : null,
          vibrate: old.vibrate,
          fullScreen: old.fullScreen,
        ),
      ],
    );
  }

  ReminderConfig toLegacyReminderConfig({ReminderConfig? fallback}) {
    final rule = primaryRule;
    if (rule == null) return fallback ?? const ReminderConfig.disabled();
    final daysBefore =
        rule.type == ReminderRuleType.relativeToDue &&
            rule.offsetMinutes != null &&
            rule.offsetMinutes! < 0
        ? (-rule.offsetMinutes!) ~/ (24 * 60)
        : 0;
    return ReminderConfig(
      enabled: enabled && rule.enabled && rule.kind != ReminderKind.off,
      kind: rule.kind,
      hour: rule.hour ?? fallback?.hour,
      minute: rule.minute ?? fallback?.minute,
      daysBefore: daysBefore,
      vibrate: rule.vibrate,
      fullScreen: rule.fullScreen,
    );
  }
}

String _legacyRuleId(ReminderConfig old) {
  final hour = old.hour?.toString() ?? 'x';
  final minute = old.minute?.toString() ?? 'x';
  return [
    'legacy',
    old.kind.index.toString(),
    hour,
    minute,
    old.daysBefore.toString(),
    old.vibrate ? 'v1' : 'v0',
    old.fullScreen ? 'f1' : 'f0',
  ].join('-');
}

/// 专注（番茄钟）联动配置。
class FocusLink {
  final bool enabled;
  final String? presetId;
  final int? focusSeconds;
  final String whiteNoise;

  const FocusLink({
    this.enabled = false,
    this.presetId,
    this.focusSeconds,
    this.whiteNoise = 'none',
  });

  /// 未启用的默认值。
  const FocusLink.disabled() : this(enabled: false);

  FocusLink copyWith({
    bool? enabled,
    String? presetId,
    int? focusSeconds,
    String? whiteNoise,
  }) => FocusLink(
    enabled: enabled ?? this.enabled,
    presetId: presetId ?? this.presetId,
    focusSeconds: focusSeconds ?? this.focusSeconds,
    whiteNoise: whiteNoise ?? this.whiteNoise,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'presetId': presetId,
    'focusSeconds': focusSeconds,
    'whiteNoise': whiteNoise,
  };

  factory FocusLink.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const FocusLink.disabled();
    return FocusLink(
      enabled: json['enabled'] == true,
      presetId: json['presetId'] as String?,
      focusSeconds: (json['focusSeconds'] as num?)?.toInt(),
      whiteNoise: (json['whiteNoise'] as String?) ?? 'none',
    );
  }
}

/// 目标里程碑
class GoalMilestone {
  String id;
  String title;
  bool isCompleted;
  DateTime? completedAt;

  GoalMilestone({
    String? id,
    required this.title,
    this.isCompleted = false,
    this.completedAt,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'isCompleted': isCompleted,
    'completedAt': completedAt?.toIso8601String(),
  };

  factory GoalMilestone.fromJson(Map<String, dynamic> json) => GoalMilestone(
    id: json['id'],
    title: json['title'] ?? '',
    isCompleted: json['isCompleted'] ?? false,
    completedAt: json['completedAt'] != null
        ? DateTime.parse(json['completedAt'])
        : null,
  );
}

enum GoalStatus { active, paused, achieved, abandoned }

/// 长期目标
class GoalItem {
  final String id;
  String title;
  String description;
  String icon;
  int colorValue;
  DateTime? startDate;
  DateTime? targetDate;
  GoalStatus status;
  double progress; // 0.0 - 1.0，自动算或手动
  bool autoProgress; // true=由里程碑计算，false=手动
  List<GoalMilestone> milestones;
  GoalCategory category;
  RecurrenceRule recurrence;
  GoalScheduling scheduling;
  bool skipHolidays;
  FocusLink focusLink;
  ReminderConfig reminder;
  ReminderPlan reminderPlan;
  int? timeTargetSeconds;
  int? dailyTargetCount;
  int sortOrder;
  String workspaceId;
  DateTime createdAt;
  DateTime updatedAt;

  GoalItem({
    String? id,
    required this.title,
    this.description = '',
    this.icon = 'flag',
    this.colorValue = 0xFFFFA726,
    this.startDate,
    this.targetDate,
    this.status = GoalStatus.active,
    this.progress = 0,
    this.autoProgress = true,
    List<GoalMilestone>? milestones,
    this.category = GoalCategory.custom,
    RecurrenceRule? recurrence,
    GoalScheduling? scheduling,
    this.skipHolidays = false,
    FocusLink? focusLink,
    ReminderConfig? reminder,
    ReminderPlan? reminderPlan,
    this.timeTargetSeconds,
    this.dailyTargetCount,
    this.sortOrder = 0,
    this.workspaceId = 'private',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? _uuid.v4(),
       milestones = milestones ?? [],
       recurrence = recurrence ?? const RecurrenceRule(),
       scheduling = scheduling ?? const GoalScheduling.fixed(),
       focusLink = focusLink ?? const FocusLink.disabled(),
       reminder =
           reminder ??
           reminderPlan?.toLegacyReminderConfig() ??
           const ReminderConfig.disabled(),
       reminderPlan =
           reminderPlan ??
           ReminderPlan.fromLegacy(reminder ?? const ReminderConfig.disabled()),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  double get computedProgress {
    if (!autoProgress) return progress;
    if (milestones.isEmpty) return status == GoalStatus.achieved ? 1.0 : 0.0;
    final done = milestones.where((m) => m.isCompleted).length;
    return (done / milestones.length).clamp(0.0, 1.0);
  }

  int get daysRemaining {
    if (targetDate == null) return -1;
    final now = AppClock.now();
    // Count calendar dates rather than 24-hour periods across DST.
    final today = DateTime.utc(now.year, now.month, now.day);
    final t = DateTime.utc(
      targetDate!.year,
      targetDate!.month,
      targetDate!.day,
    );
    return t.difference(today).inDays;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'icon': icon,
    'colorValue': colorValue,
    'startDate': startDate?.toIso8601String(),
    'targetDate': targetDate?.toIso8601String(),
    'status': status.index,
    'progress': progress,
    'autoProgress': autoProgress,
    'milestones': milestones.map((m) => m.toJson()).toList(),
    'category': category.name,
    'recurrence': recurrence.toJson(),
    'scheduling': scheduling.toJson(),
    'skipHolidays': skipHolidays,
    'focusLink': focusLink.toJson(),
    'reminder': reminderPlan
        .toLegacyReminderConfig(fallback: reminder)
        .toJson(),
    'reminderPlan': reminderPlan.toJson(),
    'timeTargetSeconds': timeTargetSeconds,
    'dailyTargetCount': dailyTargetCount,
    'sortOrder': sortOrder,
    'workspaceId': workspaceId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory GoalItem.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final legacyReminder = ReminderConfig.fromJson(
      json['reminder'] as Map<String, dynamic>?,
    );
    final reminderPlan = json['reminderPlan'] is Map
        ? ReminderPlan.fromJson(
            Map<String, dynamic>.from(json['reminderPlan'] as Map),
          )
        : ReminderPlan.fromLegacy(legacyReminder);
    return GoalItem(
      id: json['id'],
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      icon: json['icon'] ?? 'flag',
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFFFFA726,
      startDate: json['startDate'] != null
          ? DateTime.tryParse(json['startDate'].toString())
          : null,
      targetDate: json['targetDate'] != null
          ? DateTime.tryParse(json['targetDate'].toString())
          : null,
      status:
          _enumFromIndex(
            GoalStatus.values,
            (json['status'] as num?)?.toInt(),
          ) ??
          GoalStatus.active,
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      autoProgress: json['autoProgress'] ?? true,
      milestones:
          (json['milestones'] as List<dynamic>?)
              ?.map((m) => GoalMilestone.fromJson(m))
              .toList() ??
          [],
      category: _parseGoalCategory(json['category']),
      recurrence: RecurrenceRule.fromJson(
        json['recurrence'] as Map<String, dynamic>?,
      ),
      scheduling: GoalScheduling.fromJson(
        json['scheduling'] as Map<String, dynamic>?,
      ),
      skipHolidays: json['skipHolidays'] == true,
      focusLink: FocusLink.fromJson(json['focusLink'] as Map<String, dynamic>?),
      reminder: reminderPlan.toLegacyReminderConfig(fallback: legacyReminder),
      reminderPlan: reminderPlan,
      timeTargetSeconds: (json['timeTargetSeconds'] as num?)?.toInt(),
      dailyTargetCount: (json['dailyTargetCount'] as num?)?.toInt(),
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      workspaceId: json['workspaceId']?.toString().trim().isNotEmpty == true
          ? json['workspaceId'].toString()
          : 'private',
      createdAt: json['createdAt'] != null
          ? (DateTime.tryParse(json['createdAt'].toString()) ?? now)
          : now,
      updatedAt: json['updatedAt'] != null
          ? (DateTime.tryParse(json['updatedAt'].toString()) ?? now)
          : now,
    );
  }
}

/// 把旧版 `category: String?`（如 `'health'`、`'自定义'`）迁移到新的
/// [GoalCategory] 枚举：
/// - `null` / 空串 → [GoalCategory.custom]
/// - 整数 / 数值字符串 → 按 index 匹配
/// - 字符串 → 按枚举 `name` 大小写不敏感匹配，匹配不到回退 custom。
GoalCategory _parseGoalCategory(dynamic raw) {
  if (raw == null) return GoalCategory.custom;
  if (raw is num) {
    return _enumFromIndex(GoalCategory.values, raw.toInt()) ??
        GoalCategory.custom;
  }
  if (raw is String) {
    final s = raw.trim();
    if (s.isEmpty) return GoalCategory.custom;
    final asInt = int.tryParse(s);
    if (asInt != null) {
      return _enumFromIndex(GoalCategory.values, asInt) ?? GoalCategory.custom;
    }
    final lower = s.toLowerCase();
    for (final c in GoalCategory.values) {
      if (c.name.toLowerCase() == lower) return c;
    }
  }
  return GoalCategory.custom;
}

T? _enumFromIndex<T>(List<T> values, int? index) {
  if (index == null) return null;
  if (index < 0 || index >= values.length) return null;
  return values[index];
}
