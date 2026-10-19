/// 推荐目标库（Recommended Goals Library）。
///
/// - 在 UI 上提供"分类浏览 → 一键添加"的入口数据源（见 `RecommendedGoalsPicker`）。
/// - 每一条 [RecommendedGoal] 均为 `const` 值，使得 [RecommendedGoalsLibrary.all]
///   能够以**零分配**的方式返回内置常量列表。
/// - [RecommendedGoalsLibrary.instantiate] 会把推荐条目"铸模"成用户自己的
///   [GoalItem]（生成新的 UUID、填入当前时间作为 `startDate/createdAt/updatedAt`）。
///
/// 本文件**禁止**引入任何 `package:flutter/*` 依赖：
/// - `icon` 以 `MaterialIcons` 的**字符串名**承载，UI 侧再通过 icon registry
///   还原成 `IconData`；这样可以让推荐库在纯 Dart 单元测试里直接构造与断言。
///
/// 五大类（`GoalCategory`）各预置 5 条，合计 25 条，满足
/// `requirements.md` Requirement 1.3 的"每类 ≥ 5、合计 ≥ 25"约束。
library;

import 'package:uuid/uuid.dart';

import 'i18n.dart';
import '../models/goal.dart';
import '../models/recurrence.dart';

const _uuid = Uuid();

/// 推荐目标条目（库内模板，不等于用户的 [GoalItem]）。
///
/// 所有字段均为 `final`，构造器为 `const`，以便在 [RecommendedGoalsLibrary._all]
/// 中作为编译期常量集合返回。
class RecommendedGoal {
  /// 模板稳定 ID（例如 `rec.health.water_8_glasses`），用于未来可能的"基于
  /// 哪个模板创建"追踪。注意：这**不是** [GoalItem.id]，后者由
  /// [RecommendedGoalsLibrary.instantiate] 现场生成新 UUID。
  final String id;
  final GoalCategory category;
  final String title;
  final String description;

  /// MaterialIcons 的 iconName（例如 `'self_improvement'`），UI 侧负责映射到
  /// `IconData`。选用常见、国区 Flutter SDK 必定存在的名称。
  final String icon;

  /// ARGB 颜色值，例如 `0xFF4CAF50`。
  final int colorValue;

  final RecurrenceRule recurrence;
  final GoalScheduling scheduling;
  final bool skipHolidays;
  final FocusLink focusLink;
  final ReminderConfig reminder;

  /// 目标时长（秒）；对于"阅读 30 分钟"这类条目填 `1800`，不相关的条目传 `null`。
  final int? timeTargetSeconds;

  /// 每日目标次数；对于"八杯水"填 `8`、"俯卧撑 20 个"填 `20`，不相关传 `null`。
  final int? dailyTargetCount;

  const RecommendedGoal({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.icon,
    required this.colorValue,
    required this.recurrence,
    required this.scheduling,
    this.skipHolidays = false,
    this.focusLink = const FocusLink.disabled(),
    this.reminder = const ReminderConfig.disabled(),
    this.timeTargetSeconds,
    this.dailyTargetCount,
  });

  String get localizedTitle {
    return I18n.current == AppLocale.en ? (_enText[id]?.title ?? title) : title;
  }

  String get localizedDescription {
    return I18n.current == AppLocale.en
        ? (_enText[id]?.description ?? description)
        : description;
  }
}

class _RecommendedGoalText {
  final String title;
  final String description;

  const _RecommendedGoalText(this.title, this.description);
}

const Map<String, _RecommendedGoalText> _enText = {
  'rec.recommend.drink_water': _RecommendedGoalText(
    'Drink water daily',
    'Build a steady hydration rhythm for clearer focus.',
  ),
  'rec.recommend.early_sleep': _RecommendedGoalText(
    'Sleep early',
    'Put the phone down before 11 PM and reduce screen light before bed.',
  ),
  'rec.recommend.morning_meditation': _RecommendedGoalText(
    'Morning meditation',
    'Start the day with 10 minutes of breathing and awareness.',
  ),
  'rec.recommend.daily_review': _RecommendedGoalText(
    'Daily review',
    'Spend 5 minutes before bed reviewing today and planning tomorrow.',
  ),
  'rec.health.walk_8000': _RecommendedGoalText(
    'Walk 8,000 steps',
    'Commutes, walks, and stairs all count toward the daily goal.',
  ),
  'rec.health.water_8_glasses': _RecommendedGoalText(
    'Eight glasses of water',
    'Drink one glass every two hours to stay hydrated.',
  ),
  'rec.health.annual_checkup': _RecommendedGoalText(
    'Annual health checkup',
    'Schedule a full checkup once a year and track body changes.',
  ),
  'rec.health.eye_massage': _RecommendedGoalText(
    'Eye massage before bed',
    'Press around the eyes for 2 minutes to ease screen fatigue.',
  ),
  'rec.health.daily_breakfast': _RecommendedGoalText(
    'Eat breakfast',
    'Give your body a stable start and avoid low blood sugar.',
  ),
  'rec.study.read_30min': _RecommendedGoalText(
    'Read 30 minutes',
    'Paper or ebook, the goal is to start reading first.',
  ),
  'rec.study.english_words': _RecommendedGoalText(
    'Review English words',
    'Learn 50 new words and review yesterday’s list every day.',
  ),
  'rec.study.weekly_summary': _RecommendedGoalText(
    'Weekly summary',
    'Spend 20 minutes on Sunday reviewing the week and planning ahead.',
  ),
  'rec.study.new_skill_1h': _RecommendedGoalText(
    'Learn a new skill',
    'Pick 3 random days each week and practice with focus for 1 hour.',
  ),
  'rec.study.mooc_homework': _RecommendedGoalText(
    'Finish MOOC homework',
    'Reserve Tuesday and Thursday evenings for course assignments.',
  ),
  'rec.sport.running_3x_week': _RecommendedGoalText(
    'Run 3 times a week',
    'Run 5 km on Monday, Wednesday, and Friday for at least 15 km weekly.',
  ),
  'rec.sport.pushups': _RecommendedGoalText(
    'Push-up check-in',
    'Do 20 standard push-ups each day to build upper-body strength.',
  ),
  'rec.sport.core_15min': _RecommendedGoalText(
    'Core training 15 min',
    'Rotate planks, crunches, and glute bridges for core stability.',
  ),
  'rec.sport.stairs_over_elevator': _RecommendedGoalText(
    'Take stairs',
    'Use the stairs within 6 floors and turn commuting into training.',
  ),
  'rec.sport.weekend_cycling': _RecommendedGoalText(
    'Weekend cycling',
    'Ride outdoors for at least 1 hour on Saturday or Sunday.',
  ),
  'rec.emotion.gratitude_3': _RecommendedGoalText(
    'Three gratitudes',
    'Write down three small things that made today feel warmer.',
  ),
  'rec.emotion.family_call': _RecommendedGoalText(
    'Call family',
    'Call at least once a week, even briefly, just to stay connected.',
  ),
  'rec.emotion.breathing_10min': _RecommendedGoalText(
    'Breathing relax 10 min',
    'Use 4-7-8 breathing and white noise to release tension.',
  ),
  'rec.emotion.friend_greeting': _RecommendedGoalText(
    'Greet a friend',
    'Pick two days a week to message a friend you have not contacted lately.',
  ),
};

/// 推荐目标库的只读入口。
///
/// - [all] 返回完整内置列表（顺序稳定，便于 UI 做稳定索引）。
/// - [byCategory] 过滤出某一类的推荐条目。
/// - [instantiate] 把一条 [RecommendedGoal] 实例化为属于当前用户的 [GoalItem]。
class RecommendedGoalsLibrary {
  // 纯工具类，不允许实例化。
  RecommendedGoalsLibrary._();

  /// 内置的全部推荐条目。保持 `const` 以避免重复分配。
  ///
  /// 约束（见 Requirement 1.3）：
  /// - `recommend` / `health` / `study` / `sport` / `emotion` 各 ≥ 5 条；
  /// - 合计 ≥ 25 条；
  /// - 每条的 `id` 全局唯一。
  static const List<RecommendedGoal> _all = <RecommendedGoal>[
    // -------------------- recommend（通用推荐） --------------------
    RecommendedGoal(
      id: 'rec.recommend.drink_water',
      category: GoalCategory.recommend,
      title: '每日喝水',
      description: '规律饮水,保持一天的清爽与专注。',
      icon: 'local_drink',
      colorValue: 0xFF2196F3,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        interval: 1,
      ),
      scheduling: GoalScheduling.fixed(),
      skipHolidays: false,
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 10,
        minute: 0,
      ),
      dailyTargetCount: 8,
    ),
    RecommendedGoal(
      id: 'rec.recommend.early_sleep',
      category: GoalCategory.recommend,
      title: '早睡',
      description: '在 23:00 前放下手机,睡前远离屏幕光。',
      icon: 'bedtime',
      colorValue: 0xFF3F51B5,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        interval: 1,
      ),
      scheduling: GoalScheduling.fixed(),
      skipHolidays: false,
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 22,
        minute: 30,
      ),
    ),
    RecommendedGoal(
      id: 'rec.recommend.morning_meditation',
      category: GoalCategory.recommend,
      title: '晨间冥想',
      description: '用 10 分钟呼吸与觉察,平稳开启一天。',
      icon: 'self_improvement',
      colorValue: 0xFF607D8B,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        interval: 1,
      ),
      scheduling: GoalScheduling.fixed(),
      skipHolidays: false,
      focusLink: FocusLink(
        enabled: true,
        presetId: 'pomodoro10',
        focusSeconds: 600,
        whiteNoise: 'forest',
      ),
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 7,
        minute: 0,
      ),
      timeTargetSeconds: 600,
    ),
    RecommendedGoal(
      id: 'rec.recommend.daily_review',
      category: GoalCategory.recommend,
      title: '每日复盘',
      description: '睡前花 5 分钟回顾今天的得失与明日重点。',
      icon: 'rate_review',
      colorValue: 0xFF009688,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        interval: 1,
      ),
      scheduling: GoalScheduling.fixed(),
      skipHolidays: false,
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 22,
        minute: 0,
      ),
    ),

    // -------------------- health（身体健康） --------------------
    RecommendedGoal(
      id: 'rec.health.walk_8000',
      category: GoalCategory.health,
      title: '每日 8000 步',
      description: '通勤、散步、爬楼梯都算数,累计达标。',
      icon: 'directions_walk',
      colorValue: 0xFF4CAF50,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        interval: 1,
      ),
      scheduling: GoalScheduling.fixed(),
      skipHolidays: false,
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 19,
        minute: 0,
      ),
      dailyTargetCount: 8000,
    ),
    RecommendedGoal(
      id: 'rec.health.water_8_glasses',
      category: GoalCategory.health,
      title: '每天八杯水',
      description: '每两小时补一杯,保持全天水分。',
      icon: 'local_drink',
      colorValue: 0xFF03A9F4,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        interval: 1,
      ),
      scheduling: GoalScheduling.fixed(),
      skipHolidays: false,
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 9,
        minute: 0,
      ),
      dailyTargetCount: 8,
    ),
    RecommendedGoal(
      id: 'rec.health.annual_checkup',
      category: GoalCategory.health,
      title: '年度体检提醒',
      description: '每年固定一次全面体检,关注身体变化。',
      icon: 'medical_services',
      colorValue: 0xFFE53935,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.yearly,
        interval: 1,
      ),
      scheduling: GoalScheduling.fixed(),
      skipHolidays: false,
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 9,
        minute: 0,
        daysBefore: 3,
      ),
    ),
    RecommendedGoal(
      id: 'rec.health.eye_massage',
      category: GoalCategory.health,
      title: '睡前眼周按摩',
      description: '用指腹轻按眼周 2 分钟,缓解屏幕疲劳。',
      icon: 'remove_red_eye',
      colorValue: 0xFF00ACC1,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        interval: 1,
      ),
      scheduling: GoalScheduling.fixed(),
      skipHolidays: false,
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 22,
        minute: 15,
      ),
      timeTargetSeconds: 120,
    ),
    RecommendedGoal(
      id: 'rec.health.daily_breakfast',
      category: GoalCategory.health,
      title: '坚持吃早餐',
      description: '给身体一个稳定的起点,避免低血糖。',
      icon: 'restaurant',
      colorValue: 0xFFFF9800,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        interval: 1,
      ),
      scheduling: GoalScheduling.fixed(),
      skipHolidays: false,
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 7,
        minute: 30,
      ),
    ),

    // -------------------- study（学习提升） --------------------
    RecommendedGoal(
      id: 'rec.study.read_30min',
      category: GoalCategory.study,
      title: '每日阅读 30 分钟',
      description: '无论纸书还是电子书,先读起来再说。',
      icon: 'menu_book',
      colorValue: 0xFF4CAF50,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        interval: 1,
      ),
      scheduling: GoalScheduling.fixed(),
      skipHolidays: true,
      focusLink: FocusLink(
        enabled: true,
        presetId: 'pomodoro30',
        focusSeconds: 1800,
        whiteNoise: 'rain',
      ),
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 20,
        minute: 0,
      ),
      timeTargetSeconds: 1800,
    ),
    RecommendedGoal(
      id: 'rec.study.english_words',
      category: GoalCategory.study,
      title: '英语单词背诵',
      description: '每天 50 个新词 + 前一日回顾,记得住才有用。',
      icon: 'translate',
      colorValue: 0xFF9C27B0,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        interval: 1,
      ),
      scheduling: GoalScheduling.fixed(),
      skipHolidays: true,
      focusLink: FocusLink(
        enabled: true,
        presetId: 'pomodoro15',
        focusSeconds: 900,
        whiteNoise: 'cafe',
      ),
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 8,
        minute: 0,
      ),
      dailyTargetCount: 50,
      timeTargetSeconds: 900,
    ),
    RecommendedGoal(
      id: 'rec.study.weekly_summary',
      category: GoalCategory.study,
      title: '每周总结一次',
      description: '周日晚上花 20 分钟,梳理本周收获与下周计划。',
      icon: 'edit_note',
      colorValue: 0xFF00BCD4,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        interval: 1,
        byWeekdays: [6], // 周日
      ),
      scheduling: GoalScheduling.fixed(fixedWeekdays: [6]),
      skipHolidays: false,
      focusLink: FocusLink(
        enabled: true,
        presetId: 'pomodoro20',
        focusSeconds: 1200,
        whiteNoise: 'forest',
      ),
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 20,
        minute: 0,
      ),
      timeTargetSeconds: 1200,
    ),
    RecommendedGoal(
      id: 'rec.study.new_skill_1h',
      category: GoalCategory.study,
      title: '学习新技能 1 小时',
      description: '每周随机挑 3 天,专注 1 小时练新技能。',
      icon: 'school',
      colorValue: 0xFF673AB7,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        interval: 1,
      ),
      scheduling: GoalScheduling.random(minGapDays: 1, maxPerWeek: 3),
      skipHolidays: true,
      focusLink: FocusLink(
        enabled: true,
        presetId: 'pomodoro60',
        focusSeconds: 3600,
        whiteNoise: 'rain',
      ),
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 20,
        minute: 30,
      ),
      timeTargetSeconds: 3600,
    ),
    RecommendedGoal(
      id: 'rec.study.mooc_homework',
      category: GoalCategory.study,
      title: '完成慕课作业',
      description: '每周二、周四晚上,雷打不动先把作业交了。',
      icon: 'assignment',
      colorValue: 0xFF3F51B5,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        interval: 1,
        byWeekdays: [1, 3], // 周二、周四
      ),
      scheduling: GoalScheduling.fixed(fixedWeekdays: [1, 3]),
      skipHolidays: true,
      focusLink: FocusLink(
        enabled: true,
        presetId: 'pomodoro45',
        focusSeconds: 2700,
        whiteNoise: 'cafe',
      ),
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 19,
        minute: 30,
      ),
      timeTargetSeconds: 2700,
    ),

    // -------------------- sport（运动锻炼） --------------------
    RecommendedGoal(
      id: 'rec.sport.running_3x_week',
      category: GoalCategory.sport,
      title: '每周跑步 3 次',
      description: '周一、三、五晚 5 公里,累计周跑量 ≥ 15km。',
      icon: 'directions_run',
      colorValue: 0xFFE91E63,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        interval: 1,
        byWeekdays: [0, 2, 4], // 周一、三、五
      ),
      scheduling: GoalScheduling.fixed(fixedWeekdays: [0, 2, 4]),
      skipHolidays: false,
      focusLink: FocusLink(
        enabled: true,
        presetId: 'pomodoro30',
        focusSeconds: 1800,
        whiteNoise: 'none',
      ),
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 19,
        minute: 0,
      ),
      timeTargetSeconds: 1800,
    ),
    RecommendedGoal(
      id: 'rec.sport.pushups',
      category: GoalCategory.sport,
      title: '俯卧撑打卡',
      description: '每天 20 个标准俯卧撑,练胸练肩打底。',
      icon: 'fitness_center',
      colorValue: 0xFFF44336,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        interval: 1,
      ),
      scheduling: GoalScheduling.fixed(),
      skipHolidays: false,
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 18,
        minute: 30,
      ),
      dailyTargetCount: 20,
    ),
    RecommendedGoal(
      id: 'rec.sport.core_15min',
      category: GoalCategory.sport,
      title: '核心训练 15 分钟',
      description: '平板支撑、卷腹、臀桥轮换,保持核心稳定。',
      icon: 'accessibility_new',
      colorValue: 0xFFFF5722,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        interval: 1,
      ),
      scheduling: GoalScheduling.fixed(),
      skipHolidays: false,
      focusLink: FocusLink(
        enabled: true,
        presetId: 'pomodoro15',
        focusSeconds: 900,
        whiteNoise: 'none',
      ),
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 20,
        minute: 0,
      ),
      timeTargetSeconds: 900,
    ),
    RecommendedGoal(
      id: 'rec.sport.stairs_over_elevator',
      category: GoalCategory.sport,
      title: '爬楼梯代替电梯',
      description: '6 层内一律走楼梯,把通勤变成训练。',
      icon: 'stairs',
      colorValue: 0xFFFF7043,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        interval: 1,
      ),
      scheduling: GoalScheduling.fixed(),
      skipHolidays: false,
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 8,
        minute: 45,
      ),
    ),
    RecommendedGoal(
      id: 'rec.sport.weekend_cycling',
      category: GoalCategory.sport,
      title: '周末户外骑行',
      description: '周六或周日出门骑行至少 1 小时。',
      icon: 'pedal_bike',
      colorValue: 0xFFC2185B,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        interval: 1,
      ),
      scheduling: GoalScheduling.random(minGapDays: 1, maxPerWeek: 1),
      skipHolidays: false,
      focusLink: FocusLink(
        enabled: true,
        presetId: 'pomodoro60',
        focusSeconds: 3600,
        whiteNoise: 'none',
      ),
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 9,
        minute: 0,
      ),
      timeTargetSeconds: 3600,
    ),

    // -------------------- emotion（情绪心理） --------------------
    RecommendedGoal(
      id: 'rec.emotion.gratitude_3',
      category: GoalCategory.emotion,
      title: '每日感恩 3 件事',
      description: '哪怕微小也好,写下三件今天让你觉得温暖的事。',
      icon: 'volunteer_activism',
      colorValue: 0xFFFFB300,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        interval: 1,
      ),
      scheduling: GoalScheduling.fixed(),
      skipHolidays: false,
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 22,
        minute: 0,
      ),
      dailyTargetCount: 3,
    ),
    RecommendedGoal(
      id: 'rec.emotion.family_call',
      category: GoalCategory.emotion,
      title: '给家人打电话',
      description: '每周至少一次,不用长,只是想听到你的声音。',
      icon: 'call',
      colorValue: 0xFFFF7043,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        interval: 1,
      ),
      scheduling: GoalScheduling.random(minGapDays: 1, maxPerWeek: 1),
      skipHolidays: false,
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 20,
        minute: 0,
      ),
    ),
    RecommendedGoal(
      id: 'rec.emotion.breathing_10min',
      category: GoalCategory.emotion,
      title: '呼吸放松 10 分钟',
      description: '4-7-8 呼吸法 + 白噪音,把紧绷的神经松下来。',
      icon: 'air',
      colorValue: 0xFF26A69A,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.daily,
        interval: 1,
      ),
      scheduling: GoalScheduling.fixed(),
      skipHolidays: false,
      focusLink: FocusLink(
        enabled: true,
        presetId: 'pomodoro10',
        focusSeconds: 600,
        whiteNoise: 'waves',
      ),
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 18,
        minute: 0,
      ),
      timeTargetSeconds: 600,
    ),
    RecommendedGoal(
      id: 'rec.emotion.friend_greeting',
      category: GoalCategory.emotion,
      title: '给朋友发问候',
      description: '每周挑两天,给许久未联系的朋友发一句问候。',
      icon: 'message',
      colorValue: 0xFFEC407A,
      recurrence: RecurrenceRule(
        frequency: RecurrenceFrequency.weekly,
        interval: 1,
      ),
      scheduling: GoalScheduling.random(minGapDays: 2, maxPerWeek: 2),
      skipHolidays: false,
      reminder: ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: 12,
        minute: 30,
      ),
    ),
  ];

  /// 返回全部推荐目标(稳定顺序,UI 可用索引缓存)。
  ///
  /// 返回值是 `const` 列表,调用方不得尝试修改(Dart 运行时会抛异常)。
  static List<RecommendedGoal> all() => _all;

  /// 按分类筛选推荐目标。
  ///
  /// - 未命中时返回空列表 `const []`(不抛异常);
  /// - 每次调用返回新列表(不可变视图),避免上游修改污染全局缓存。
  static List<RecommendedGoal> byCategory(GoalCategory c) {
    final matched = _all.where((r) => r.category == c).toList(growable: false);
    if (matched.isEmpty) return const <RecommendedGoal>[];
    return matched;
  }

  /// 把推荐模板实例化为属于当前用户的 [GoalItem]。
  ///
  /// 关键行为:
  /// - `id` 为新 UUID v4,保证与既有 Goal 不冲突;
  /// - `status = active`、`progress = 0`、`autoProgress = true`、`milestones = []`、
  ///   `sortOrder = 0`;
  /// - `startDate = today 00:00 (local)`,不携带 `targetDate`(推荐目标通常无截止日);
  /// - `createdAt / updatedAt = DateTime.now()`;
  /// - 其余字段从 [RecommendedGoal] 原样复制(结构共享,因为它们都是不可变值)。
  static GoalItem instantiate(RecommendedGoal r) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return GoalItem(
      id: _uuid.v4(),
      title: r.localizedTitle,
      description: r.localizedDescription,
      icon: r.icon,
      colorValue: r.colorValue,
      startDate: today,
      status: GoalStatus.active,
      progress: 0,
      autoProgress: true,
      milestones: <GoalMilestone>[],
      category: r.category,
      recurrence: r.recurrence,
      scheduling: r.scheduling,
      skipHolidays: r.skipHolidays,
      focusLink: r.focusLink,
      reminder: r.reminder,
      timeTargetSeconds: r.timeTargetSeconds,
      dailyTargetCount: r.dailyTargetCount,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    );
  }
}
