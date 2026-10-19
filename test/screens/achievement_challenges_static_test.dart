import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('成就页展示每日和每周挑战进度且不自动发币', () {
    final challengeCore = File(
      'lib/core/productivity_challenges.dart',
    ).readAsStringSync();
    final achievementContext = File(
      'lib/core/achievements.dart',
    ).readAsStringSync();
    final provider = File(
      'lib/providers/achievement_provider.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/screens/achievements_screen.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(challengeCore, contains('class ProductivityChallenge'));
    expect(challengeCore, contains('ProductivityChallengePeriod.daily'));
    expect(challengeCore, contains('ProductivityChallengePeriod.weekly'));
    expect(challengeCore, contains('daily_todo_clear'));
    expect(challengeCore, contains('daily_focus_start'));
    expect(challengeCore, contains('daily_habit_anchor'));
    expect(challengeCore, contains('daily_reflection'));
    expect(challengeCore, contains('weekly_todo_sprint'));
    expect(challengeCore, contains('weekly_focus_deep_work'));
    expect(challengeCore, contains('weekly_habit_chain'));
    expect(challengeCore, contains('weekly_reflection'));
    expect(challengeCore, contains('weekly_active_days'));
    expect(challengeCore, contains('RewardGrant rewardGrant('));
    expect(
      challengeCore,
      contains(r"id: 'challenge:${challenge.id}:$periodKey'"),
    );

    expect(achievementContext, contains('todayCompletedTodos'));
    expect(achievementContext, contains('todayHabitCheckIns'));
    expect(achievementContext, contains('todayFocusMinutes'));
    expect(achievementContext, contains('weeklyCompletedTodos'));
    expect(achievementContext, contains('weeklyHabitCheckIns'));
    expect(achievementContext, contains('weeklyFocusMinutes'));
    expect(achievementContext, contains('weeklyActiveDays'));

    expect(
      provider,
      contains("import '../core/productivity_challenges.dart';"),
    );
    expect(provider, contains('List<ProductivityChallenge> get challenges'));
    expect(provider, isNot(contains('_awardCompletedChallenges')));
    expect(provider, isNot(contains('ProductivityChallenges.rewardGrant')));
    expect(challengeCore, isNot(matches(RegExp(r'rewardCoins: [1-9]'))));

    expect(screen, contains("import '../core/productivity_challenges.dart';"));
    expect(screen, contains('每日/每周挑战'));
    expect(screen, contains('_ChallengeCard'));
    expect(screen, contains('challenge.periodLabel'));
    expect(screen, isNot(contains('challenge.rewardCoins')));
    expect(screen, contains('challenge.progress'));
    expect(screen, contains('challenge.completed'));

    expect(main, contains('todayCompletedTodos: todayCompletedTodos'));
    expect(main, contains('weeklyCompletedTodos: weeklyCompletedTodos'));
    expect(main, contains('todayFocusMinutes: todayFocusMinutes'));
    expect(main, contains('weeklyFocusMinutes: weeklyFocusMinutes'));
    expect(main, contains('weeklyActiveDays: activeDays.length'));
  });
}
