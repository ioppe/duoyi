import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/recommended_goals.dart';
import 'package:duoyi/models/goal.dart';

/// 推荐目标库单测（Task 3.2）。
///
/// 覆盖 requirements.md §1 的 1.3 / 1.4：
/// - 退役两条记录模板后保留 23 条；推荐与情感类各 4 条，其余各 5 条；
/// - `byCategory(custom)` 为空（推荐库不使用 custom 类别）；
/// - 条目 `id` 全局唯一；
/// - `instantiate(r)` 生成的 `GoalItem.id` 是新 UUID，不等于 `r.id`、
///   与任何模板 id 不冲突，且连续两次调用产生不同 id；
/// - 实例化过程会把模板字段原样搬到 `GoalItem` 上；
/// - 实例化后的 goal 处于"新建即运行"状态：`status = active`、
///   `progress = 0`、`autoProgress = true`、`milestones = []`、
///   `sortOrder = 0`、`startDate` 为今日本地 00:00。
void main() {
  setUp(() {
    I18n.setLocale(AppLocale.zh);
  });

  group('RecommendedGoalsLibrary.all / byCategory 数量与分类', () {
    test('all() 保留 23 条有效推荐并移除退役模板', () {
      final items = RecommendedGoalsLibrary.all();
      expect(items, hasLength(23));
      expect(
        items.map((item) => item.id),
        isNot(contains('rec.recommend.daily_journal')),
      );
      expect(
        items.map((item) => item.id),
        isNot(contains('rec.emotion.mood_diary')),
      );
    });

    test('五个主类别保留所有未退役模板', () {
      const mainCategories = <GoalCategory>[
        GoalCategory.recommend,
        GoalCategory.health,
        GoalCategory.study,
        GoalCategory.sport,
        GoalCategory.emotion,
      ];

      for (final c in mainCategories) {
        final list = RecommendedGoalsLibrary.byCategory(c);
        final expectedCount =
            c == GoalCategory.recommend || c == GoalCategory.emotion ? 4 : 5;
        expect(list, hasLength(expectedCount), reason: '类别 $c 的有效推荐数量');
        // 同时验证 byCategory 过滤结果都属于该类别。
        for (final r in list) {
          expect(r.category, c);
        }
      }
    });

    test('byCategory(GoalCategory.custom) 应返回空列表（推荐库不用 custom）', () {
      final list = RecommendedGoalsLibrary.byCategory(GoalCategory.custom);
      expect(list, isEmpty);
    });

    test('全部条目的 id 必须全局唯一', () {
      final items = RecommendedGoalsLibrary.all();
      final ids = items.map((r) => r.id).toList(growable: false);
      final uniq = ids.toSet();
      expect(
        uniq.length,
        ids.length,
        reason: '存在重复的 RecommendedGoal.id，请检查库定义',
      );
    });
  });

  group('RecommendedGoalsLibrary.instantiate', () {
    /// 挑一条稳定存在的模板做代表性断言；找不到时兜底用第一个。
    RecommendedGoal pickTemplate() {
      final all = RecommendedGoalsLibrary.all();
      return all.firstWhere(
        (r) => r.id == 'rec.recommend.drink_water',
        orElse: () => all.first,
      );
    }

    test('生成的 GoalItem.id 不等于模板 id，也不与任何模板 id 冲突', () {
      final templates = RecommendedGoalsLibrary.all();
      final templateIds = templates.map((r) => r.id).toSet();

      final r = pickTemplate();
      final goal = RecommendedGoalsLibrary.instantiate(r);

      expect(goal.id, isNotEmpty);
      expect(
        goal.id,
        isNot(equals(r.id)),
        reason: 'GoalItem.id 应为新 UUID，不得复用模板 id',
      );
      expect(
        templateIds.contains(goal.id),
        isFalse,
        reason: '新 GoalItem.id 不得与任何模板 id 冲突',
      );
    });

    test('连续两次 instantiate 同一模板，生成的 id 不同', () {
      final r = pickTemplate();
      final a = RecommendedGoalsLibrary.instantiate(r);
      final b = RecommendedGoalsLibrary.instantiate(r);

      expect(a.id, isNot(equals(b.id)), reason: '每次 instantiate 都应生成新的 UUID');
    });

    test('对库中每条模板 instantiate，产出的 GoalItem.id 彼此不重复，且与模板 id 不重叠', () {
      final templates = RecommendedGoalsLibrary.all();
      final templateIds = templates.map((r) => r.id).toSet();

      final newIds = <String>{};
      for (final r in templates) {
        final g = RecommendedGoalsLibrary.instantiate(r);
        expect(templateIds.contains(g.id), isFalse);
        expect(
          newIds.add(g.id),
          isTrue,
          reason: '第二次出现同一个 GoalItem.id: ${g.id}',
        );
      }
      expect(newIds.length, templates.length);
    });

    test('instantiate 复制模板的核心字段（title/category/icon/color/recurrence/...）', () {
      final r = pickTemplate();
      final goal = RecommendedGoalsLibrary.instantiate(r);

      expect(goal.title, r.title);
      expect(goal.category, r.category);
      expect(goal.icon, r.icon);
      expect(goal.colorValue, r.colorValue);
      // 这些都是不可变值类型，直接引用相等即可。
      expect(identical(goal.recurrence, r.recurrence), isTrue);
      expect(identical(goal.scheduling, r.scheduling), isTrue);
      expect(goal.skipHolidays, r.skipHolidays);
      expect(identical(goal.focusLink, r.focusLink), isTrue);
      expect(identical(goal.reminder, r.reminder), isTrue);
      expect(goal.timeTargetSeconds, r.timeTargetSeconds);
      expect(goal.dailyTargetCount, r.dailyTargetCount);
    });

    test('instantiate 后 GoalItem 处于"新建即运行"状态', () {
      final r = pickTemplate();
      final goal = RecommendedGoalsLibrary.instantiate(r);

      expect(goal.status, GoalStatus.active);
      expect(goal.progress, 0);
      expect(goal.autoProgress, isTrue);
      expect(goal.milestones, isEmpty);
      expect(goal.sortOrder, 0);
      expect(goal.startDate, isNotNull);
    });

    test('instantiate().startDate 对齐到今日本地 00:00', () {
      final r = pickTemplate();
      final before = DateTime.now();
      final goal = RecommendedGoalsLibrary.instantiate(r);
      final after = DateTime.now();

      final start = goal.startDate!;
      // hour/minute/second 均为 0（对齐到 00:00）。
      expect(start.hour, 0);
      expect(start.minute, 0);
      expect(start.second, 0);
      expect(start.millisecond, 0);

      // 日期应等于 before ~ after 之间某一天的 00:00（处理调用期间恰好跨天
      // 的极端情况：至少匹配到其中一天）。
      final beforeDay = DateTime(before.year, before.month, before.day);
      final afterDay = DateTime(after.year, after.month, after.day);
      expect(
        start == beforeDay || start == afterDay,
        isTrue,
        reason:
            'startDate=$start 应等于 today 00:00（'
            'beforeDay=$beforeDay, afterDay=$afterDay）',
      );
    });

    test('英文环境下推荐目标展示和实例化使用英文文案', () {
      I18n.setLocale(AppLocale.en);
      final r = RecommendedGoalsLibrary.all().firstWhere(
        (item) => item.id == 'rec.recommend.drink_water',
      );

      expect(r.localizedTitle, 'Drink water daily');
      expect(r.localizedDescription, isNot(contains('规律饮水')));

      final goal = RecommendedGoalsLibrary.instantiate(r);
      expect(goal.title, 'Drink water daily');
      expect(goal.description, isNot(contains('规律饮水')));
    });
  });
}
