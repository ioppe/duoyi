import 'package:flutter/material.dart';

import 'achievements.dart';
import 'i18n.dart';
import 'virtual_rewards.dart';

enum ProductivityChallengePeriod { daily, weekly }

class ProductivityChallenge {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final ProductivityChallengePeriod period;
  final int current;
  final int target;
  final int rewardCoins;

  const ProductivityChallenge({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.period,
    required this.current,
    required this.target,
    required this.rewardCoins,
  });

  bool get completed => current >= target;

  double get progress => target <= 0 ? 0 : (current / target).clamp(0.0, 1.0);

  String get periodLabel => switch (period) {
    ProductivityChallengePeriod.daily => '今日挑战',
    ProductivityChallengePeriod.weekly => '本周挑战',
  };
}

class ProductivityChallenges {
  const ProductivityChallenges._();

  static List<ProductivityChallenge> build(AchievementContext context) => [
    ProductivityChallenge(
      id: 'daily_todo_clear',
      title: '今日清单推进',
      description: '完成 3 个待办，保持计划向前滚动',
      icon: Icons.task_alt,
      color: const Color(0xFF2E7D32),
      period: ProductivityChallengePeriod.daily,
      current: context.todayCompletedTodos,
      target: 3,
      rewardCoins: 0,
    ),
    ProductivityChallenge(
      id: 'daily_focus_start',
      title: '专注启动',
      description: '累计专注 25 分钟，进入一次完整心流',
      icon: Icons.timer_outlined,
      color: const Color(0xFF1565C0),
      period: ProductivityChallengePeriod.daily,
      current: context.todayFocusMinutes,
      target: 25,
      rewardCoins: 0,
    ),
    ProductivityChallenge(
      id: 'daily_habit_anchor',
      title: '习惯锚点',
      description: '完成 2 次习惯打卡，让一天有稳定节奏',
      icon: Icons.repeat,
      color: const Color(0xFF00897B),
      period: ProductivityChallengePeriod.daily,
      current: context.todayHabitCheckIns,
      target: 2,
      rewardCoins: 0,
    ),
    ProductivityChallenge(
      id: 'weekly_todo_sprint',
      title: '周清单冲刺',
      description: '本周完成 15 个待办，清掉关键事项',
      icon: Icons.done_all,
      color: const Color(0xFF6A1B9A),
      period: ProductivityChallengePeriod.weekly,
      current: context.weeklyCompletedTodos,
      target: 15,
      rewardCoins: 0,
    ),
    ProductivityChallenge(
      id: 'weekly_focus_deep_work',
      title: '深度工作周',
      description: '本周累计专注 180 分钟，沉淀长期成果',
      icon: Icons.psychology_alt_outlined,
      color: const Color(0xFF283593),
      period: ProductivityChallengePeriod.weekly,
      current: context.weeklyFocusMinutes,
      target: 180,
      rewardCoins: 0,
    ),
    ProductivityChallenge(
      id: 'weekly_habit_chain',
      title: '习惯链条',
      description: '本周累计完成 10 次习惯打卡',
      icon: Icons.link,
      color: const Color(0xFF00796B),
      period: ProductivityChallengePeriod.weekly,
      current: context.weeklyHabitCheckIns,
      target: 10,
      rewardCoins: 0,
    ),
    ProductivityChallenge(
      id: 'weekly_active_days',
      title: '五日在线',
      description: I18n.tr('challenge.weekly_active_days.description'),
      icon: Icons.calendar_month_outlined,
      color: const Color(0xFFEF6C00),
      period: ProductivityChallengePeriod.weekly,
      current: context.weeklyActiveDays,
      target: 5,
      rewardCoins: 0,
    ),
  ];

  static String rewardPeriodKey(
    ProductivityChallenge challenge, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final date = challenge.period == ProductivityChallengePeriod.daily
        ? DateTime(at.year, at.month, at.day)
        : DateTime(
            at.year,
            at.month,
            at.day,
          ).subtract(Duration(days: at.weekday - 1));
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static RewardGrant rewardGrant(
    ProductivityChallenge challenge, {
    DateTime? now,
  }) {
    final periodKey = rewardPeriodKey(challenge, now: now);
    return RewardGrant(
      id: 'challenge:${challenge.id}:$periodKey',
      title: '完成挑战：${challenge.title}',
      coins: 0,
      reason: '${challenge.periodLabel} · $periodKey',
    );
  }
}
