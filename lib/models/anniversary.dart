import 'package:uuid/uuid.dart';
import '../core/app_clock.dart';
import '../core/lunar_calendar.dart';
import 'goal.dart' show ReminderKind;

const _uuid = Uuid();

enum AnniversaryType {
  normal, // 普通倒数日(单次)
  birthday, // 生日(每年循环)
  memorial, // 周年纪念(每年循环)
  custom, // 自定义周期
}

enum AnniversaryCalendarType { solar, lunar }

/// 纪念日 / 生日 / 倒数日
/// 既能做单次倒数，也能做按公历/农历每年循环。
class Anniversary {
  final String id;
  String title;
  String? description;
  DateTime originDate; // 原始日期(公历；若 calendarType=lunar，则这是第一次对应公历日期)
  AnniversaryType type;
  AnniversaryCalendarType calendarType;
  int colorValue;
  bool isPinned;
  bool remind;
  int remindDaysBefore; // 提前几天提醒
  int remindHour;
  int remindMinute;
  ReminderKind reminderKind;
  bool ignoreYear;
  int? lunarYear; // 农历年(仅 lunar 用)
  int? lunarMonth;
  int? lunarDay;
  bool lunarIsLeap;
  DateTime createdAt;
  DateTime updatedAt;

  Anniversary({
    String? id,
    required this.title,
    this.description,
    required this.originDate,
    this.type = AnniversaryType.normal,
    this.calendarType = AnniversaryCalendarType.solar,
    this.colorValue = 0xFFE91E63,
    this.isPinned = false,
    this.remind = false,
    this.remindDaysBefore = 1,
    this.remindHour = 9,
    this.remindMinute = 0,
    this.reminderKind = ReminderKind.push,
    this.ignoreYear = false,
    this.lunarYear,
    this.lunarMonth,
    this.lunarDay,
    this.lunarIsLeap = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? _uuid.v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  /// 从一个公历日期 + 是否按农历循环 构造
  factory Anniversary.create({
    String? id,
    required String title,
    String? description,
    required DateTime solarDate,
    AnniversaryType type = AnniversaryType.normal,
    AnniversaryCalendarType calendarType = AnniversaryCalendarType.solar,
    int colorValue = 0xFFE91E63,
    bool isPinned = false,
    bool remind = false,
    int remindDaysBefore = 1,
    int remindHour = 9,
    int remindMinute = 0,
    ReminderKind reminderKind = ReminderKind.push,
    bool ignoreYear = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    int? ly, lm, ld;
    bool leap = false;
    if (calendarType == AnniversaryCalendarType.lunar) {
      final l = LunarCalendar.fromSolar(solarDate);
      ly = l.year;
      lm = l.month;
      ld = l.day;
      leap = l.isLeapMonth;
    }
    return Anniversary(
      id: id,
      title: title,
      description: description,
      originDate: solarDate,
      type: type,
      calendarType: calendarType,
      colorValue: colorValue,
      isPinned: isPinned,
      remind: remind,
      remindDaysBefore: remindDaysBefore,
      remindHour: remindHour,
      remindMinute: remindMinute,
      reminderKind: reminderKind,
      ignoreYear: ignoreYear,
      lunarYear: ly,
      lunarMonth: lm,
      lunarDay: ld,
      lunarIsLeap: leap,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// 下一次(含今天)的公历日期
  DateTime get nextOccurrence {
    final today = AppClock.today();

    // 单次倒数：原始日期即下一次(过去就停留)
    if (type == AnniversaryType.normal) return originDate;

    if (calendarType == AnniversaryCalendarType.solar) {
      DateTime candidate = DateTime(
        today.year,
        originDate.month,
        originDate.day,
      );
      if (candidate.isBefore(today)) {
        candidate = DateTime(today.year + 1, originDate.month, originDate.day);
      }
      return candidate;
    }

    // 农历循环：用当前年重算农历对应公历
    final ly = lunarYear ?? 0;
    final lm = lunarMonth ?? 1;
    final ld = lunarDay ?? 1;
    DateTime solar;
    try {
      solar = LunarCalendar.toSolar(today.year, lm, ld, isLeap: lunarIsLeap);
    } catch (_) {
      solar = DateTime(today.year, originDate.month, originDate.day);
    }
    if (solar.isBefore(today)) {
      try {
        solar = LunarCalendar.toSolar(
          today.year + 1,
          lm,
          ld,
          isLeap: lunarIsLeap,
        );
      } catch (_) {
        solar = DateTime(today.year + 1, originDate.month, originDate.day);
      }
    }
    // 抑制未使用警告
    assert(ly >= 0);
    return solar;
  }

  /// 距离下一次还剩多少天(过去返回负数)
  int get daysRemaining {
    final today = AppClock.today();
    final next = nextOccurrence;
    final n = DateTime(next.year, next.month, next.day);
    return n.difference(today).inDays;
  }

  /// 已经过去多少年(生日/纪念日用)
  int? get yearsPassed {
    if (type == AnniversaryType.normal) return null;
    if (ignoreYear) return null;
    final now = AppClock.now();
    int years = now.year - originDate.year;
    final thisYearOccur = DateTime(now.year, originDate.month, originDate.day);
    if (thisYearOccur.isAfter(DateTime(now.year, now.month, now.day))) {
      years -= 1;
    }
    return years < 0 ? 0 : years;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'originDate': originDate.toIso8601String(),
    'type': type.index,
    'calendarType': calendarType.index,
    'colorValue': colorValue,
    'isPinned': isPinned,
    'remind': remind,
    'remindDaysBefore': remindDaysBefore,
    'remindHour': remindHour,
    'remindMinute': remindMinute,
    'reminderKind': reminderKind.index,
    'ignoreYear': ignoreYear,
    'lunarYear': lunarYear,
    'lunarMonth': lunarMonth,
    'lunarDay': lunarDay,
    'lunarIsLeap': lunarIsLeap,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Anniversary.fromJson(Map<String, dynamic> json) => Anniversary(
    id: json['id'],
    title: json['title'] ?? '',
    description: json['description'],
    originDate: DateTime.parse(json['originDate']),
    type: AnniversaryType.values[json['type'] ?? 0],
    calendarType: AnniversaryCalendarType.values[json['calendarType'] ?? 0],
    colorValue: json['colorValue'] ?? 0xFFE91E63,
    isPinned: json['isPinned'] ?? false,
    remind: json['remind'] ?? false,
    remindDaysBefore: json['remindDaysBefore'] ?? 1,
    remindHour: (json['remindHour'] as num?)?.toInt() ?? 9,
    remindMinute: (json['remindMinute'] as num?)?.toInt() ?? 0,
    reminderKind: _reminderKindFromJson(json['reminderKind']),
    ignoreYear: json['ignoreYear'] == true,
    lunarYear: json['lunarYear'],
    lunarMonth: json['lunarMonth'],
    lunarDay: json['lunarDay'],
    lunarIsLeap: json['lunarIsLeap'] ?? false,
    createdAt: json['createdAt'] != null
        ? DateTime.parse(json['createdAt'])
        : DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
        DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
  );
}

ReminderKind _reminderKindFromJson(Object? raw) {
  if (raw is num) {
    final index = raw.toInt();
    if (index >= 0 && index < ReminderKind.values.length) {
      return ReminderKind.values[index];
    }
  }
  if (raw is String) {
    for (final kind in ReminderKind.values) {
      if (kind.name == raw) return kind;
    }
  }
  return ReminderKind.push;
}
