import 'package:flutter/material.dart';

/// 用于驱动徽章判定的聚合数据快照。
class AchievementContext {
  final int totalTodos;
  final int completedTodos;
  final int longestHabitStreak;
  final int habitCount;
  final int focusMinutes;
  final int focusSessions;
  final int diaryStreak;
  final int diaryCount;
  final int goalsTotal;
  final int goalsAchieved;
  final int anniversaries;
  final int courses;
  final int notes;
  final int themeSwitches; // 切换主题次数，从 SharedPreferences 读
  final int todayCompletedTodos;
  final int todayHabitCheckIns;
  final int todayFocusMinutes;
  final int todayDiaryEntries;
  final int weeklyCompletedTodos;
  final int weeklyHabitCheckIns;
  final int weeklyFocusMinutes;
  final int weeklyDiaryEntries;
  final int weeklyActiveDays;

  const AchievementContext({
    required this.totalTodos,
    required this.completedTodos,
    required this.longestHabitStreak,
    required this.habitCount,
    required this.focusMinutes,
    required this.focusSessions,
    required this.diaryStreak,
    required this.diaryCount,
    required this.goalsTotal,
    required this.goalsAchieved,
    required this.anniversaries,
    required this.courses,
    required this.notes,
    this.themeSwitches = 0,
    this.todayCompletedTodos = 0,
    this.todayHabitCheckIns = 0,
    this.todayFocusMinutes = 0,
    this.todayDiaryEntries = 0,
    this.weeklyCompletedTodos = 0,
    this.weeklyHabitCheckIns = 0,
    this.weeklyFocusMinutes = 0,
    this.weeklyDiaryEntries = 0,
    this.weeklyActiveDays = 0,
  });
}

typedef AchievementCheck = bool Function(AchievementContext);
typedef AchievementProgress = int Function(AchievementContext);

class Achievement {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final AchievementCheck unlocked;

  /// 当前进度(用于显示进度条)，可选。
  final AchievementProgress? current;

  /// 目标值；与 [current] 一起显示 `current/target`。
  final int? target;

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.unlocked,
    this.current,
    this.target,
  });
}

class Achievements {
  static const List<Achievement> all = [
    // —— 待办 ——
    Achievement(
      id: 'first_todo',
      title: '启程',
      description: '完成第一个待办',
      icon: Icons.flag,
      color: Color(0xFF42A5F5),
      unlocked: _unlockedFirstTodo,
    ),
    Achievement(
      id: 'todo_10',
      title: '十事九顺',
      description: '累计完成 10 个待办',
      icon: Icons.task_alt,
      color: Color(0xFF26A69A),
      unlocked: _todo10,
      current: _curTodo,
      target: 10,
    ),
    Achievement(
      id: 'todo_100',
      title: '百事达人',
      description: '累计完成 100 个待办',
      icon: Icons.emoji_events,
      color: Color(0xFFFFA726),
      unlocked: _todo100,
      current: _curTodo,
      target: 100,
    ),
    Achievement(
      id: 'todo_500',
      title: '时间的朋友',
      description: '累计完成 500 个待办',
      icon: Icons.workspace_premium,
      color: Color(0xFFEF5350),
      unlocked: _todo500,
      current: _curTodo,
      target: 500,
    ),

    // —— 习惯 ——
    Achievement(
      id: 'habit_start',
      title: '习惯养成',
      description: '记录第一个习惯',
      icon: Icons.repeat_one,
      color: Color(0xFF66BB6A),
      unlocked: _habitStart,
    ),
    Achievement(
      id: 'streak_7',
      title: '七日连打',
      description: '连续打卡 7 天',
      icon: Icons.local_fire_department,
      color: Color(0xFFFF7043),
      unlocked: _streak7,
      current: _curStreak,
      target: 7,
    ),
    Achievement(
      id: 'streak_30',
      title: '月之忠诚',
      description: '连续打卡 30 天',
      icon: Icons.bolt,
      color: Color(0xFFFFCA28),
      unlocked: _streak30,
      current: _curStreak,
      target: 30,
    ),
    Achievement(
      id: 'streak_100',
      title: '百日筑基',
      description: '连续打卡 100 天',
      icon: Icons.whatshot,
      color: Color(0xFFD81B60),
      unlocked: _streak100,
      current: _curStreak,
      target: 100,
    ),

    // —— 专注 ——
    Achievement(
      id: 'focus_1h',
      title: '初心者',
      description: '累计专注 60 分钟',
      icon: Icons.timer,
      color: Color(0xFFAB47BC),
      unlocked: _focus1h,
      current: _curFocus,
      target: 60,
    ),
    Achievement(
      id: 'focus_10h',
      title: '心流达人',
      description: '累计专注 10 小时',
      icon: Icons.auto_awesome,
      color: Color(0xFF7E57C2),
      unlocked: _focus10h,
      current: _curFocus,
      target: 600,
    ),
    Achievement(
      id: 'focus_100h',
      title: '时间大师',
      description: '累计专注 100 小时',
      icon: Icons.rocket_launch,
      color: Color(0xFF5C6BC0),
      unlocked: _focus100h,
      current: _curFocus,
      target: 6000,
    ),

    // —— 目标 ——
    Achievement(
      id: 'goal_first',
      title: '理想主义者',
      description: '创建第一个目标',
      icon: Icons.flag_circle,
      color: Color(0xFFFFA726),
      unlocked: _goalFirst,
    ),
    Achievement(
      id: 'goal_achieved',
      title: '言出必行',
      description: '达成一个目标',
      icon: Icons.emoji_events,
      color: Color(0xFFFFCA28),
      unlocked: _goalAchieved,
    ),
    Achievement(
      id: 'goal_5',
      title: '五事毕',
      description: '达成 5 个目标',
      icon: Icons.military_tech,
      color: Color(0xFFFF8F00),
      unlocked: _goal5,
      current: _curGoalAchieved,
      target: 5,
    ),

    // —— 综合 ——
    Achievement(
      id: 'polymath',
      title: '多才多艺',
      description: '同时使用 5 种以上模块',
      icon: Icons.hub,
      color: Color(0xFF42A5F5),
      unlocked: _polymath,
    ),
    Achievement(
      id: 'theme_explorer',
      title: '衣橱达人',
      description: '切换过 3 次以上主题',
      icon: Icons.palette,
      color: Color(0xFFEC407A),
      unlocked: _themeExplorer,
    ),
  ];

  static int unlockedCount(AchievementContext c) =>
      all.where((a) => a.unlocked(c)).length;
}

// —— 私有条件 ——

bool _unlockedFirstTodo(AchievementContext c) => c.completedTodos >= 1;
bool _todo10(AchievementContext c) => c.completedTodos >= 10;
bool _todo100(AchievementContext c) => c.completedTodos >= 100;
bool _todo500(AchievementContext c) => c.completedTodos >= 500;
int _curTodo(AchievementContext c) => c.completedTodos;

bool _habitStart(AchievementContext c) => c.habitCount >= 1;
bool _streak7(AchievementContext c) => c.longestHabitStreak >= 7;
bool _streak30(AchievementContext c) => c.longestHabitStreak >= 30;
bool _streak100(AchievementContext c) => c.longestHabitStreak >= 100;
int _curStreak(AchievementContext c) => c.longestHabitStreak;

bool _focus1h(AchievementContext c) => c.focusMinutes >= 60;
bool _focus10h(AchievementContext c) => c.focusMinutes >= 600;
bool _focus100h(AchievementContext c) => c.focusMinutes >= 6000;
int _curFocus(AchievementContext c) => c.focusMinutes;

bool _goalFirst(AchievementContext c) => c.goalsTotal >= 1;
bool _goalAchieved(AchievementContext c) => c.goalsAchieved >= 1;
bool _goal5(AchievementContext c) => c.goalsAchieved >= 5;
int _curGoalAchieved(AchievementContext c) => c.goalsAchieved;

bool _polymath(AchievementContext c) {
  int mods = 0;
  if (c.totalTodos > 0) mods++;
  if (c.habitCount > 0) mods++;
  if (c.focusSessions > 0) mods++;
  if (c.goalsTotal > 0) mods++;
  if (c.anniversaries > 0) mods++;
  if (c.courses > 0) mods++;
  if (c.notes > 0) mods++;
  return mods >= 5;
}

bool _themeExplorer(AchievementContext c) => c.themeSwitches >= 3;
