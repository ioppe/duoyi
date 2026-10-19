import 'dart:convert';

import 'package:duoyi/core/achievements.dart';
import 'package:duoyi/core/domain_event_bus.dart';
import 'package:duoyi/core/productivity_challenges.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'loaded unlocked achievements do not re-enter feedback after restart',
    () async {
      final unlockedAt = DateTime(2026, 6, 1).toIso8601String();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'duoyi_achievements_unlocked': json.encode({'first_todo': unlockedAt}),
        'duoyi_achievements_notified': <String>['first_todo'],
      });
      final provider = AchievementProvider();

      await provider.loadFromStorage();
      await provider.updateContext(
        const AchievementContext(
          totalTodos: 1,
          completedTodos: 1,
          longestHabitStreak: 0,
          habitCount: 0,
          focusMinutes: 0,
          focusSessions: 0,
          diaryStreak: 0,
          diaryCount: 0,
          goalsTotal: 0,
          goalsAchieved: 0,
          anniversaries: 0,
          courses: 0,
          notes: 0,
        ),
      );

      expect(provider.snapshotFor('first_todo').unlocked, isTrue);
      expect(provider.takeUnlockedFeedback(), isEmpty);
    },
  );

  test(
    'cloud-restored wardrobe achievement is treated as an already notified baseline',
    () async {
      final unlockedAt = DateTime(2026, 6, 1).toIso8601String();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'duoyi_achievements_unlocked': json.encode({
          'theme_explorer': unlockedAt,
        }),
      });
      final provider = AchievementProvider();

      await provider.loadFromStorage();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList('duoyi_achievements_notified'),
        contains('theme_explorer'),
      );

      await provider.updateContext(
        const AchievementContext(
          totalTodos: 0,
          completedTodos: 0,
          longestHabitStreak: 0,
          habitCount: 0,
          focusMinutes: 0,
          focusSessions: 0,
          diaryStreak: 0,
          diaryCount: 0,
          goalsTotal: 0,
          goalsAchieved: 0,
          anniversaries: 0,
          courses: 0,
          notes: 0,
          themeSwitches: 3,
        ),
      );

      expect(provider.snapshotFor('theme_explorer').unlocked, isTrue);
      expect(provider.takeUnlockedFeedback(), isEmpty);
      provider.dispose();
    },
  );

  test(
    'login-restored wardrobe achievement does not pop after feedback resumes',
    () async {
      final unlockedAt = DateTime(2026, 6, 1).toIso8601String();
      final provider = AchievementProvider();
      await provider.loadFromStorage();

      provider.resetLocalState();
      final suppressionGeneration = provider.suppressUnlockFeedback();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'duoyi_achievements_unlocked',
        json.encode({'theme_explorer': unlockedAt}),
      );

      await provider.loadFromStorage();
      expect(provider.unlockFeedbackSuppressed, isTrue);
      expect(
        prefs.getStringList('duoyi_achievements_notified'),
        contains('theme_explorer'),
      );

      provider.resumeUnlockFeedback(generation: suppressionGeneration);
      await provider.updateContext(
        const AchievementContext(
          totalTodos: 0,
          completedTodos: 0,
          longestHabitStreak: 0,
          habitCount: 0,
          focusMinutes: 0,
          focusSessions: 0,
          diaryStreak: 0,
          diaryCount: 0,
          goalsTotal: 0,
          goalsAchieved: 0,
          anniversaries: 0,
          courses: 0,
          notes: 0,
          themeSwitches: 3,
        ),
      );

      expect(provider.snapshotFor('theme_explorer').unlocked, isTrue);
      expect(provider.takeUnlockedFeedback(), isEmpty);
      provider.dispose();
    },
  );

  test(
    'suppressed unlock feedback hides re-derived achievements but resumes for genuine new unlocks',
    () async {
      final provider = AchievementProvider();
      await provider.loadFromStorage();

      // 模拟切号：云端基线尚未回填前抑制反馈。
      provider.suppressUnlockFeedback();
      expect(provider.unlockFeedbackSuppressed, isTrue);

      await provider.updateContext(
        const AchievementContext(
          totalTodos: 1,
          completedTodos: 1,
          longestHabitStreak: 0,
          habitCount: 0,
          focusMinutes: 0,
          focusSessions: 0,
          diaryStreak: 0,
          diaryCount: 0,
          goalsTotal: 0,
          goalsAchieved: 0,
          anniversaries: 0,
          courses: 0,
          notes: 0,
        ),
      );

      // 抑制期内：成就被静默记录为已解锁，但不产生任何弹窗反馈。
      expect(provider.snapshotFor('first_todo').unlocked, isTrue);
      expect(provider.takeUnlockedFeedback(), isEmpty);

      // 基线恢复后，真正的新解锁应当正常弹出反馈。
      provider.resumeUnlockFeedback();
      expect(provider.unlockFeedbackSuppressed, isFalse);

      await provider.updateContext(
        const AchievementContext(
          totalTodos: 10,
          completedTodos: 10,
          longestHabitStreak: 0,
          habitCount: 0,
          focusMinutes: 0,
          focusSessions: 0,
          diaryStreak: 0,
          diaryCount: 0,
          goalsTotal: 0,
          goalsAchieved: 0,
          anniversaries: 0,
          courses: 0,
          notes: 0,
        ),
      );

      final feedback = provider.takeUnlockedFeedback().map((a) => a.id).toSet();
      // 抑制期内解锁的 first_todo 不应补弹；新解锁的 todo_10 应当弹出。
      expect(feedback, contains('todo_10'));
      expect(feedback, isNot(contains('first_todo')));
    },
  );

  test(
    'resume keeps suppressed-window unlocks silent and notified across restart',
    () async {
      final provider = AchievementProvider();
      await provider.loadFromStorage();

      // 模拟切号/云端基线回填窗口：first_todo 在抑制期内被静默解锁。
      provider.suppressUnlockFeedback();
      await provider.updateContext(
        const AchievementContext(
          totalTodos: 1,
          completedTodos: 1,
          longestHabitStreak: 0,
          habitCount: 0,
          focusMinutes: 0,
          focusSessions: 0,
          diaryStreak: 0,
          diaryCount: 0,
          goalsTotal: 0,
          goalsAchieved: 0,
          anniversaries: 0,
          courses: 0,
          notes: 0,
        ),
      );
      expect(provider.snapshotFor('first_todo').unlocked, isTrue);
      expect(provider.takeUnlockedFeedback(), isEmpty);

      // 恢复反馈窗口：恢复点不得把抑制期内解锁的成就当成"新解锁"补弹，
      // 且"已通知"标记必须已落盘（resume 的补记 + 静默路径双保险）。
      provider.resumeUnlockFeedback();
      expect(provider.unlockFeedbackSuppressed, isFalse);

      // 等待 rebuild 触发的 unawaited 持久化链路完成。
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList('duoyi_achievements_notified'),
        contains('first_todo'),
        reason: '抑制窗口内解锁的成就必须保持"已通知"并持久化',
      );

      // 模拟重启：全新 provider 载入同一存储，抑制期成就不得补弹。
      final reloaded = AchievementProvider();
      await reloaded.loadFromStorage();
      await reloaded.updateContext(
        const AchievementContext(
          totalTodos: 1,
          completedTodos: 1,
          longestHabitStreak: 0,
          habitCount: 0,
          focusMinutes: 0,
          focusSessions: 0,
          diaryStreak: 0,
          diaryCount: 0,
          goalsTotal: 0,
          goalsAchieved: 0,
          anniversaries: 0,
          courses: 0,
          notes: 0,
        ),
      );
      expect(reloaded.takeUnlockedFeedback(), isEmpty);
      reloaded.dispose();
      provider.dispose();
    },
  );

  test(
    'stale resume generation does not lift a newer suppression window',
    () async {
      final provider = AchievementProvider();
      await provider.loadFromStorage();

      // 第一轮切号抑制，记下其代次（模拟旧的兜底定时器捕获值）。
      final firstGeneration = provider.suppressUnlockFeedback();
      expect(provider.unlockFeedbackSuppressed, isTrue);

      // 第二轮切号在旧兜底定时器触发前再次抑制，代次自增。
      final secondGeneration = provider.suppressUnlockFeedback();
      expect(secondGeneration, greaterThan(firstGeneration));
      expect(provider.unlockFeedbackSuppressed, isTrue);

      // 旧兜底定时器以第一轮代次触发：不应放开仍处于抑制窗口的新一轮。
      provider.resumeUnlockFeedback(generation: firstGeneration);
      expect(provider.unlockFeedbackSuppressed, isTrue);

      // 当前代次的恢复（或云端基线即时恢复）才会真正放开。
      provider.resumeUnlockFeedback(generation: secondGeneration);
      expect(provider.unlockFeedbackSuppressed, isFalse);
    },
  );

  test(
    'loadFromStorage clears stale rewards when account keys are removed',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'duoyi_achievements_unlocked': json.encode({
          'first_todo': '2026-06-01T00:00:00.000Z',
        }),
        'duoyi_achievements_notified': <String>['first_todo'],
        'duoyi_virtual_rewards': json.encode({
          'balance': 88,
          'lifetime': 120,
          'grantIds': <String>['admin-grant'],
          'ledger': <Map<String, Object>>[
            {
              'id': 'admin-grant',
              'title': 'Admin reward',
              'coins': 88,
              'reason': 'old account data',
              'awardedAt': '2026-06-01T00:00:00.000Z',
            },
          ],
          'updatedAt': '2026-06-01T00:00:00.000Z',
        }),
      });
      final provider = AchievementProvider();
      await provider.loadFromStorage();
      expect(provider.coinBalance, 88);
      expect(provider.unlockedAt, isNotEmpty);

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('duoyi_achievements_unlocked');
      await prefs.remove('duoyi_achievements_notified');
      await prefs.remove('duoyi_virtual_rewards');
      await provider.loadFromStorage();

      expect(provider.coinBalance, 0);
      expect(provider.lifetimeCoins, 0);
      expect(provider.rewardLedger, isEmpty);
      expect(provider.unlockedAt, isEmpty);
      provider.dispose();
    },
  );
  test(
    'work, challenges and badges preserve historical rewards without issuing new coins',
    () async {
      final history = {
        'balance': 88,
        'lifetime': 120,
        'grantIds': ['legacy'],
        'ledger': [
          {
            'id': 'legacy',
            'title': '历史记录',
            'coins': 120,
            'reason': 'history',
            'awardedAt': '2026-01-01T00:00:00Z',
          },
        ],
        'updatedAt': '2026-01-01T00:00:00Z',
      };
      SharedPreferences.setMockInitialValues({
        'duoyi_virtual_rewards': jsonEncode(history),
      });
      final bus = DomainEventBus.instance;
      final provider = AchievementProvider(bus: bus);
      await provider.loadFromStorage();
      await provider.updateContext(
        const AchievementContext(
          totalTodos: 3,
          completedTodos: 3,
          longestHabitStreak: 0,
          habitCount: 0,
          focusMinutes: 25,
          focusSessions: 1,
          diaryStreak: 0,
          diaryCount: 0,
          goalsTotal: 0,
          goalsAchieved: 0,
          anniversaries: 0,
          courses: 0,
          notes: 0,
          todayCompletedTodos: 3,
          todayFocusMinutes: 25,
        ),
      );
      for (final type in DomainEventType.values) {
        bus.publish(
          DomainEvent(
            type: type,
            objectId: 'work',
            metadata: {'durationSeconds': 1500},
          ),
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(provider.snapshotFor('first_todo').unlocked, isTrue);
      expect(provider.takeUnlockedFeedback(), isNotEmpty);
      expect(provider.challenges.where((item) => item.completed), isNotEmpty);
      for (final challenge in provider.challenges) {
        expect(ProductivityChallenges.rewardGrant(challenge).coins, 0);
      }
      expect(provider.lastEventAt, isNotNull);
      expect(provider.coinBalance, 88);
      expect(provider.lifetimeCoins, 120);
      expect(provider.rewardLedger, hasLength(1));
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('duoyi_virtual_rewards')!), history);
      provider.dispose();
    },
  );
}
