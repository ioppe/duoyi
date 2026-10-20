/// 推荐目标选择器（Recommended Goals Picker）。
///
/// - 顶部：水平可滚动的类别分段（5 个主类别：推荐/健康/学习/运动/情感）。
///   不使用 `SegmentedButton`，因为分段 ≤5 且 UI 上希望允许未来扩类；
///   改用水平 `ListView` 渲染 `ChoiceChip`，既能滑动又能高亮选中。
/// - 中部：按当前选中类别筛选 [RecommendedGoalsLibrary.byCategory] 的条目，
///   以卡片列表形式展示（标题 / 描述 / 元信息徽章 / 添加按钮）。
/// - 点击卡片或加号按钮 → 把模板实例化后写入 [GoalProvider]，并弹
///   SnackBar 提示"已添加到目标列表"。
///
/// 关于 `recommend` 类别的约定：当用户选中 `GoalCategory.recommend` 时，
/// 本页面只展示 `byCategory(recommend)` 对应的 5 条通用推荐条目，**不**
/// 合并展示其它 4 类的内容。这和 `RecommendedGoalsLibrary` 的分类语义保持
/// 一致，避免重复呈现。
///
/// 关于写入 Provider 的策略：本页调用 `GoalProvider.applyRecommended(r)` 把
/// 模板实例化后写入本地；Provider 返回新创建的 [GoalItem]，SnackBar 的
/// "查看"动作用它作为 `Navigator.pop` 的返回值，供上游（GoalScreen）串联跳转。
///
/// 对应 Requirements: 1.3, 1.4。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/goal_icons.dart';
import '../core/i18n_date_format.dart';
import '../core/recommended_goals.dart';
import '../models/goal.dart';
import '../models/recurrence.dart';
import '../providers/goal_provider.dart';
import '../widgets/surface_components.dart';

/// 顶部 5 个主类别（和 [RecommendedGoalsLibrary] 对齐，排除 `custom`）。
const List<GoalCategory> _pickerCategories = <GoalCategory>[
  GoalCategory.recommend,
  GoalCategory.health,
  GoalCategory.study,
  GoalCategory.sport,
  GoalCategory.emotion,
];

/// 推荐目标选择器页面。
class RecommendedGoalsPicker extends StatefulWidget {
  /// 进入页面时默认选中的类别，默认为 [GoalCategory.recommend]。
  final GoalCategory initialCategory;

  const RecommendedGoalsPicker({
    super.key,
    this.initialCategory = GoalCategory.recommend,
  });

  @override
  State<RecommendedGoalsPicker> createState() => _RecommendedGoalsPickerState();
}

class _RecommendedGoalsPickerState extends State<RecommendedGoalsPicker> {
  late GoalCategory _selected;

  @override
  void initState() {
    super.initState();
    // 如果传入了 `custom`（理论上不会），回退到 recommend。
    _selected = _pickerCategories.contains(widget.initialCategory)
        ? widget.initialCategory
        : GoalCategory.recommend;
  }

  void _select(GoalCategory c) {
    if (_selected == c) return;
    setState(() => _selected = c);
  }

  Future<void> _apply(RecommendedGoal r) async {
    final provider = context.read<GoalProvider>();
    // Provider 负责"实例化 + 持久化"两步，返回带新 UUID 的 GoalItem。
    final goal = await provider.applyRecommended(r);

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('已添加到目标列表'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: const RoundedRectangleBorder(
            borderRadius: DesignTokens.borderRadiusSm,
          ),
          action: SnackBarAction(
            label: '查看',
            onPressed: () {
              // 返回上一页（通常是 GoalScreen），把新 Goal 带回去。
              Navigator.pop(context, goal);
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final items = RecommendedGoalsLibrary.byCategory(_selected);
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: const Text('推荐目标'),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppSecondaryControlTheme(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CategoryChipRow(
              categories: _pickerCategories,
              selected: _selected,
              onSelect: _select,
            ),
            const SizedBox(height: DesignTokens.spaceXs),
            Expanded(
              child: items.isEmpty
                  ? _EmptyCategoryPlaceholder(category: _selected)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        DesignTokens.spaceLg,
                        DesignTokens.spaceSm,
                        DesignTokens.spaceLg,
                        DesignTokens.spaceXxl,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (context, _) =>
                          const SizedBox(height: DesignTokens.spaceMd),
                      itemBuilder: (_, i) => _RecommendedGoalCard(
                        goal: items[i],
                        onApply: () => _apply(items[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部类别分段行。使用水平 `ListView` + `ChoiceChip` 以便未来扩类。
class _CategoryChipRow extends StatelessWidget {
  final List<GoalCategory> categories;
  final GoalCategory selected;
  final ValueChanged<GoalCategory> onSelect;

  const _CategoryChipRow({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceLg,
          vertical: DesignTokens.spaceSm,
        ),
        itemCount: categories.length,
        separatorBuilder: (context, _) =>
            const SizedBox(width: DesignTokens.spaceSm),
        itemBuilder: (_, i) {
          final c = categories[i];
          return ChoiceChip(
            label: Text(_categoryLabel(c)),
            selected: selected == c,
            onSelected: (_) => onSelect(c),
          );
        },
      ),
    );
  }
}

/// 推荐目标卡片：主图标 + 标题/描述 + 元信息徽章 + 加号按钮。
class _RecommendedGoalCard extends StatelessWidget {
  final RecommendedGoal goal;
  final VoidCallback onApply;

  const _RecommendedGoalCard({required this.goal, required this.onApply});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = Color(goal.colorValue);
    final icon = goalIconFromName(goal.icon);

    return Material(
      color: cs.surface,
      borderRadius: DesignTokens.borderRadiusLg,
      child: InkWell(
        onTap: onApply,
        borderRadius: DesignTokens.borderRadiusLg,
        child: Ink(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: DesignTokens.borderRadiusLg,
            boxShadow: DesignTokens.shadowXs,
            border: Border.all(color: color.withValues(alpha: 0.12)),
          ),
          padding: const EdgeInsets.all(DesignTokens.spaceLg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: DesignTokens.borderRadiusMd,
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: DesignTokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.localizedTitle,
                      style: const TextStyle(
                        fontSize: DesignTokens.fontSizeMd,
                        fontWeight: DesignTokens.fontWeightStrong,
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spaceXxs),
                    Text(
                      goal.localizedDescription,
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeSm,
                        color: cs.onSurface.withValues(alpha: 0.65),
                        height: 1.35,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: DesignTokens.spaceSm),
                    _MetaBadges(goal: goal, baseColor: color),
                  ],
                ),
              ),
              const SizedBox(width: DesignTokens.spaceSm),
              IconButton(
                tooltip: '添加到目标列表',
                icon: Icon(Icons.add_circle, color: color),
                onPressed: onApply,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 第二行元信息：重复规则、节假日跳过、专注/闹钟/次数/目标时长。
class _MetaBadges extends StatelessWidget {
  final RecommendedGoal goal;
  final Color baseColor;

  const _MetaBadges({required this.goal, required this.baseColor});

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[];

    // 重复规则 + 调度模式
    final recurrenceLabel = _recurrenceLabel(goal.recurrence, goal.scheduling);
    badges.add(
      _Badge(icon: Icons.repeat, label: recurrenceLabel, color: baseColor),
    );

    // 跳过节假日
    if (goal.skipHolidays) {
      badges.add(
        const _Badge(
          icon: Icons.beach_access,
          label: '跳节假日',
          color: Color(0xFF8D6E63),
        ),
      );
    }

    // 专注联动（番茄钟）
    if (goal.focusLink.enabled) {
      badges.add(
        _Badge(
          icon: Icons.timer,
          label: _focusLabel(goal.focusLink.focusSeconds),
          color: const Color(0xFF7E57C2),
        ),
      );
    }

    // 提醒（push / alarm）
    if (goal.reminder.enabled) {
      final hhmm = _formatHm(goal.reminder.hour, goal.reminder.minute);
      final prefix = goal.reminder.kind == ReminderKind.alarm
          ? '闹钟'
          : goal.reminder.kind == ReminderKind.popup
          ? '弹出框'
          : '通知';
      badges.add(
        _Badge(
          icon: goal.reminder.kind == ReminderKind.alarm
              ? Icons.alarm
              : goal.reminder.kind == ReminderKind.popup
              ? Icons.open_in_new
              : Icons.notifications_active,
          label: hhmm == null ? prefix : '$prefix $hhmm',
          color: goal.reminder.kind == ReminderKind.alarm
              ? const Color(0xFFEF5350)
              : const Color(0xFF42A5F5),
        ),
      );
    }

    // 每日次数
    if (goal.dailyTargetCount != null && goal.dailyTargetCount! > 0) {
      badges.add(
        _Badge(
          icon: Icons.format_list_numbered,
          label: '×${goal.dailyTargetCount}',
          color: const Color(0xFF26A69A),
        ),
      );
    }

    // 目标时长
    if (goal.timeTargetSeconds != null && goal.timeTargetSeconds! > 0) {
      badges.add(
        _Badge(
          icon: Icons.hourglass_bottom,
          label: _formatDuration(goal.timeTargetSeconds!),
          color: const Color(0xFFFFA726),
        ),
      );
    }

    return Wrap(
      spacing: DesignTokens.spaceXs,
      runSpacing: DesignTokens.spaceXs,
      children: badges,
    );
  }
}

/// 小号圆角标签。
class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Badge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceSm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: DesignTokens.borderRadiusSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: DesignTokens.fontSizeXs,
              fontWeight: DesignTokens.fontWeightStrong,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 空类别提示（理论上 5 个主类别每类 ≥ 5 条，不会触达；保底兜底）。
class _EmptyCategoryPlaceholder extends StatelessWidget {
  final GoalCategory category;
  const _EmptyCategoryPlaceholder({required this.category});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spaceXxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: DesignTokens.spaceSm),
            Text(
              '「${_categoryLabel(category)}」暂无推荐条目',
              style: TextStyle(
                fontSize: DesignTokens.fontSizeBase,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 工具函数（中文标签 / 时长格式化）
// ---------------------------------------------------------------------------

/// 把 [GoalCategory] 渲染成顶部分段显示的中文标签。
String _categoryLabel(GoalCategory c) {
  switch (c) {
    case GoalCategory.recommend:
      return '推荐';
    case GoalCategory.health:
      return '健康';
    case GoalCategory.study:
      return '学习';
    case GoalCategory.sport:
      return '运动';
    case GoalCategory.emotion:
      return '情感';
    case GoalCategory.custom:
      return '自定义';
  }
}

/// 把 [RecurrenceRule] + [GoalScheduling] 拼成一个人类可读的短标签。
///
/// - 频率用 `rule.label` 的基础部分（如 "每天"、"每周"）；
/// - 固定模式附加 `by` 信息（周 X / 月 N 日）；
/// - 随机模式附加 "随机·每周 N 次" / "随机·每月 N 次" / "随机·每 N 天"。
String _recurrenceLabel(RecurrenceRule rule, GoalScheduling scheduling) {
  // 把 rule.label 里的"·周X/Y"再叠一层可能重复，简单起见直接从 frequency 派标签。
  final base = switch (rule.frequency) {
    RecurrenceFrequency.none => '不重复',
    RecurrenceFrequency.daily =>
      rule.interval == 1 ? '每天' : '每 ${rule.interval} 天',
    RecurrenceFrequency.weekly =>
      rule.interval == 1 ? '每周' : '每 ${rule.interval} 周',
    RecurrenceFrequency.monthly =>
      rule.interval == 1 ? '每月' : '每 ${rule.interval} 月',
    RecurrenceFrequency.yearly =>
      rule.interval == 1 ? '每年' : '每 ${rule.interval} 年',
  };

  switch (scheduling.mode) {
    case SchedulingMode.fixed:
      if (rule.frequency == RecurrenceFrequency.weekly &&
          (scheduling.fixedWeekdays?.isNotEmpty ?? false)) {
        const names = ['一', '二', '三', '四', '五', '六', '日'];
        final days = ([...scheduling.fixedWeekdays!]..sort())
            .where((d) => d >= 0 && d < names.length)
            .map((d) => names[d])
            .join('/');
        return '$base · 周$days';
      }
      if (rule.frequency == RecurrenceFrequency.monthly &&
          (scheduling.fixedMonthDays?.isNotEmpty ?? false)) {
        final days = ([...scheduling.fixedMonthDays!]..sort()).join('/');
        return '$base · $days 日';
      }
      return base;
    case SchedulingMode.random:
      if (scheduling.randomMaxPerWeek != null) {
        return '$base · 随机每周 ${scheduling.randomMaxPerWeek} 次';
      }
      if (scheduling.randomMaxPerMonth != null) {
        return '$base · 随机每月 ${scheduling.randomMaxPerMonth} 次';
      }
      if (scheduling.randomMinGapDays != null) {
        return '$base · 随机·≥${scheduling.randomMinGapDays} 天间隔';
      }
      return '$base · 随机';
  }
}

/// 秒数渲染成 "Xh / Ym / Zs" 的紧凑字符串。
String _formatDuration(int seconds) {
  if (seconds <= 0) return '0s';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0 && m > 0) return '${h}h${m}m';
  if (h > 0) return '${h}h';
  if (m > 0) return '${m}min';
  return '${s}s';
}

/// 专注时长标签：`专注 X min` / `专注 X h`。
String _focusLabel(int? focusSeconds) {
  if (focusSeconds == null || focusSeconds <= 0) return '专注';
  return '专注 ${_formatDuration(focusSeconds)}';
}

/// 把 `hour:minute` 渲染成 `HH:MM`，任一为 null 时返回 null。
String? _formatHm(int? hour, int? minute) {
  if (hour == null || minute == null) return null;
  return I18nDateFormat.timeOfDay(hour: hour, minute: minute);
}
