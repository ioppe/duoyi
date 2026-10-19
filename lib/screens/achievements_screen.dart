import 'dart:io' show File;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/achievements.dart';
import '../core/i18n.dart';
import '../core/productivity_challenges.dart';
import '../providers/achievement_provider.dart';
import '../widgets/surface_components.dart';

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AchievementProvider>();
    final all = Achievements.all;
    final unlocked = provider.unlockedCount;

    final unlockedAchievements = _unlockedAchievements(provider);
    final challenges = provider.challenges;

    return Scaffold(
      appBar: AppBar(
        title: Text('成就 · $unlocked / ${all.length}'),
        actions: [
          IconButton(
            tooltip: '成就分享图',
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: () => _showAchievementShareCard(
              context,
              provider: provider,
              unlockedAchievements: unlockedAchievements,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: [
          _ProgressHeader(unlocked: unlocked, total: all.length),
          if (challenges.isNotEmpty) ...[
            const SizedBox(height: 12),
            AppSectionHeader(
              title: '每日/每周挑战',
              subtitle: I18n.tr('achievements.challenges.subtitle'),
              padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            ),
            for (final challenge in challenges) ...[
              _ChallengeCard(challenge: challenge),
              const SizedBox(height: 10),
            ],
          ],
          const SizedBox(height: 12),
          const AppSectionHeader(
            title: '徽章墙',
            subtitle: '按使用进度逐步解锁',
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
          ),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.42,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: all.map((a) {
              final snapshot = provider.snapshotFor(a.id);
              final target = snapshot.target;
              return _BadgeCard(
                ach: a,
                unlocked: snapshot.unlocked,
                current: a.current == null && target == null
                    ? null
                    : snapshot.current,
                target: target,
                progress: snapshot.progress,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  List<Achievement> _unlockedAchievements(AchievementProvider provider) {
    final items = Achievements.all
        .where((achievement) => provider.snapshotFor(achievement.id).unlocked)
        .toList();
    items.sort((a, b) {
      final aTime =
          provider.snapshotFor(a.id).unlockedAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          provider.snapshotFor(b.id).unlockedAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return items;
  }

  Future<void> _showAchievementShareCard(
    BuildContext context, {
    required AchievementProvider provider,
    required List<Achievement> unlockedAchievements,
  }) async {
    final markdown = _achievementShareMarkdown(
      provider: provider,
      unlockedAchievements: unlockedAchievements,
    );
    await showDialog<void>(
      context: context,
      builder: (_) => _AchievementShareDialog(
        markdown: markdown,
        child: _AchievementShareCard(
          unlockedCount: provider.unlockedCount,
          totalCount: provider.totalCount,
          achievements: unlockedAchievements.take(5).toList(),
        ),
      ),
    );
  }

  String _achievementShareMarkdown({
    required AchievementProvider provider,
    required List<Achievement> unlockedAchievements,
  }) {
    final sb = StringBuffer()
      ..writeln('# 多仪成就海报')
      ..writeln()
      ..writeln('- 已解锁：${provider.unlockedCount} / ${provider.totalCount}');
    if (unlockedAchievements.isNotEmpty) {
      sb
        ..writeln()
        ..writeln('## 最近解锁');
      for (final achievement in unlockedAchievements.take(8)) {
        sb.writeln('- ${achievement.title}：${achievement.description}');
      }
    }
    return sb.toString();
  }
}

class _ChallengeCard extends StatelessWidget {
  final ProductivityChallenge challenge;

  const _ChallengeCard({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final completed = challenge.completed;
    final color = challenge.color;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(13),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: color.withValues(alpha: completed ? 0.28 : 0.14),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(challenge.icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        challenge.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        challenge.periodLabel,
                        style: TextStyle(color: color, fontSize: 10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  challenge.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.58),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: challenge.progress,
                    minHeight: 5,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.12),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${challenge.current.clamp(0, challenge.target)} / ${challenge.target}',
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            completed ? Icons.check_circle : Icons.flag_outlined,
            color: completed ? color : cs.onSurfaceVariant,
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  final int unlocked;
  final int total;
  const _ProgressHeader({required this.unlocked, required this.total});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = total == 0 ? 0.0 : unlocked / total;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(20),
      gradient: LinearGradient(
        colors: [
          cs.primary.withValues(alpha: 0.92),
          cs.tertiary.withValues(alpha: 0.78),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: Border.all(color: cs.onPrimary.withValues(alpha: 0.14)),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: cs.onPrimary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.emoji_events, color: cs.onPrimary, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '你的成就',
                  style: TextStyle(
                    color: cs.onPrimary.withValues(alpha: 0.78),
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$unlocked / $total',
                  style: TextStyle(
                    color: cs.onPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  I18n.tr('achievements.summary.subtitle'),
                  style: TextStyle(
                    color: cs.onPrimary.withValues(alpha: 0.78),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: p,
                    minHeight: 7,
                    backgroundColor: cs.onPrimary.withValues(alpha: 0.25),
                    color: cs.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementShareDialog extends StatefulWidget {
  final String markdown;
  final Widget child;

  const _AchievementShareDialog({required this.markdown, required this.child});

  @override
  State<_AchievementShareDialog> createState() =>
      _AchievementShareDialogState();
}

class _AchievementShareDialogState extends State<_AchievementShareDialog> {
  final GlobalKey _cardKey = GlobalKey();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: const Text('成就分享图'),
      content: SingleChildScrollView(
        child: RepaintBoundary(key: _cardKey, child: widget.child),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        TextButton.icon(
          onPressed: _saving ? null : _copyMarkdown,
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('复制文案'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _savePng,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.image_outlined, size: 16),
          label: const Text('保存 PNG'),
        ),
      ],
    );
  }

  Future<void> _copyMarkdown() async {
    await Clipboard.setData(ClipboardData(text: widget.markdown));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('成就文案已复制'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _savePng() async {
    final boundary =
        _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    setState(() => _saving = true);
    try {
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/duoyi_achievement_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      await Clipboard.setData(ClipboardData(text: file.path));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: widget.markdown,
          subject: '多仪成就海报',
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('成就分享图已保存并打开系统分享面板，路径已复制：${file.path}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _AchievementShareCard extends StatelessWidget {
  final int unlockedCount;
  final int totalCount;
  final List<Achievement> achievements;

  const _AchievementShareCard({
    required this.unlockedCount,
    required this.totalCount,
    required this.achievements,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = totalCount == 0 ? 0.0 : unlockedCount / totalCount;
    return Container(
      width: 360,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.16),
          width: 0.45,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.emoji_events, color: cs.primary, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '多仪成就海报',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    Text(
                      '持续积累的可见进步',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '$unlockedCount / $totalCount',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.normal),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              color: cs.primary,
              backgroundColor: cs.primary.withValues(alpha: 0.14),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AchievementShareMetric(
                label: '完成度',
                value: '${(progress * 100).round()}%',
              ),
            ],
          ),
          if (achievements.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              '最近解锁',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.normal),
            ),
            const SizedBox(height: 8),
            for (final achievement in achievements)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: achievement.color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        achievement.icon,
                        size: 16,
                        color: achievement.color,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        achievement.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 12),
          Text(
            '由多仪生成',
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.44),
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementShareMetric extends StatelessWidget {
  final String label;
  final String value;

  const _AchievementShareMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.normal),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.58),
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeCard extends StatelessWidget {
  final Achievement ach;
  final bool unlocked;
  final int? current;
  final int? target;
  final double progress;

  const _BadgeCard({
    required this.ach,
    required this.unlocked,
    required this.current,
    required this.target,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = unlocked ? ach.color : Colors.grey.shade400;

    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: color.withValues(alpha: unlocked ? 0.24 : 0.14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(ach.icon, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ach.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: 13,
                    color: unlocked
                        ? cs.onSurface
                        : cs.onSurface.withValues(alpha: 0.48),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: unlocked ? 0.14 : 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  unlocked ? '已解锁' : '进行中',
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ach.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.62),
              height: 1.4,
            ),
          ),
          const Spacer(),
          if (current != null && target != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: color.withValues(alpha: 0.12),
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$current / $target',
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
