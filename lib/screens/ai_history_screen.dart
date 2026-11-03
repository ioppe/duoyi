import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_clock.dart';
import '../core/app_motion.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/iterable_extensions.dart';
import '../models/ai_report_context.dart';
import '../services/ai_service.dart';
import '../widgets/ai_review_markdown.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

/// AI 解读历史：本机账号私有存储。
///
/// 统计报告按自然周期分组，每组各自保留最近 50 条；旧版本没有周期元数据的
/// 记录仍共用原来的最近 50 条池，不会被新周期的记录挤掉。这里只读取本机
/// 存档，不涉及云端或备份。
class AiHistoryScreen extends StatefulWidget {
  const AiHistoryScreen({super.key, this.initialReportContext});

  /// 从统计页进入时带上当前周期；默认无参数时保持「全部历史」入口不变。
  final AiReportContext? initialReportContext;

  @override
  State<AiHistoryScreen> createState() => _AiHistoryScreenState();
}

class _AiHistoryScreenState extends State<AiHistoryScreen> {
  /// 旧版本统计报告条目只有正文和摘要前缀，没有周期元数据；
  /// 这里只用来提示「周期未知」，绝不据此推断日期或时区。
  static const _legacyReportSummaryPrefix = '统计报告 AI 解读';

  final Set<String> _expandedReviewIds = <String>{};

  /// null 表示「全部历史」。
  String? _selectedKey;

  @override
  void initState() {
    super.initState();
    _selectedKey = widget.initialReportContext?.key;
  }

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiService>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final contexts = _contexts(ai);
    final selected = contexts
        .where((context) => context.key == _selectedKey)
        .firstOrNull;
    final items = _items(ai, selected);
    final runningJob = selected == null ? null : ai.reportJobFor(selected);

    return Scaffold(
      appBar: AppBar(
        title: Text(I18n.tr('ai_history.title')),
        actions: [
          if (ai.reviewHistory.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: I18n.tr('ai_history.clear.tooltip'),
              onPressed: () => _confirmClear(context),
            ),
        ],
      ),
      body: Column(
        children: [
          if (contexts.isNotEmpty)
            _PeriodPicker(
              contexts: contexts,
              selectedKey: selected?.key,
              onChanged: (value) => setState(() => _selectedKey = value),
            ),
          if (runningJob != null && runningJob.isRunning)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  I18n.tr('statistics.ai.generating'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: DesignTokens.fontWeightRegular,
                  ),
                ),
              ),
            ),
          Expanded(
            child: items.isEmpty
                ? EmptyState(
                    icon: Icons.auto_awesome,
                    message: I18n.tr(
                      selected == null
                          ? 'ai_history.empty'
                          : 'ai_history.period.empty',
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    separatorBuilder: (context, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _buildEntry(context, ai, items[i]),
                  ),
          ),
        ],
      ),
    );
  }

  /// 初始周期始终在选项里（即使还没有任何记录），其余来自服务端的已存档/进行中分组。
  List<AiReportContext> _contexts(AiService ai) {
    final merged = <String, AiReportContext>{};
    final initial = widget.initialReportContext;
    if (initial != null) merged[initial.key] = initial;
    for (final context in ai.reportContexts) {
      merged.putIfAbsent(context.key, () => context);
    }
    return merged.values.toList();
  }

  /// 按 metadata key 过滤，不按标题猜；「全部历史」保留所有条目（含旧版）。
  List<AiReviewEntry> _items(AiService ai, AiReportContext? selected) {
    if (selected == null) {
      return [...ai.reviewHistory]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return ai.reportHistoryFor(selected);
  }

  Widget _buildEntry(BuildContext context, AiService ai, AiReviewEntry e) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final createdAt = I18nDateFormat.fullDateTime(
      AppClock.toLocal(e.createdAt),
    );
    final expanded = _expandedReviewIds.contains(e.id);
    final reportContext = e.reportContext;
    final dataThrough = e.dataThrough;
    final messenger = ScaffoldMessenger.maybeOf(context);
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    createdAt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.62),
                      fontWeight: DesignTokens.fontWeightStrong,
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('ai_history_toggle_${e.id}'),
                  tooltip: expanded
                      ? I18n.tr('ai_history.collapse')
                      : I18n.tr('ai_history.expand'),
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: () {
                    setState(() {
                      if (expanded) {
                        _expandedReviewIds.remove(e.id);
                      } else {
                        _expandedReviewIds.add(e.id);
                      }
                    });
                  },
                  icon: Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                ),
                PopupMenuButton<String>(
                  iconSize: 18,
                  onSelected: (v) async {
                    if (v == 'copy') {
                      await Clipboard.setData(ClipboardData(text: e.content));
                      messenger?.showSnackBar(
                        SnackBar(
                          content: Text(I18n.tr('ai_history.copy.done')),
                        ),
                      );
                    } else if (v == 'delete') {
                      try {
                        await ai.deleteReview(e.id);
                      } catch (_) {
                        messenger?.showSnackBar(
                          SnackBar(
                            content: Text(
                              I18n.tr('statistics.ai.error.storage_failed'),
                            ),
                          ),
                        );
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'copy',
                      child: Text(I18n.tr('ai_history.copy')),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        I18n.tr('ai_history.delete'),
                        style: TextStyle(color: cs.error),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (e.model.isNotEmpty) ...[
              const SizedBox(height: 6),
              AppStatusBadge(
                label: e.model,
                color: cs.primary,
                icon: Icons.memory_outlined,
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              ),
            ],
            if (reportContext != null) ...[
              const SizedBox(height: 6),
              _MetaLine(text: _periodLine(reportContext)),
            ] else if (_looksLikeLegacyReport(e)) ...[
              const SizedBox(height: 6),
              _MetaLine(text: I18n.tr('ai_history.period.unknown')),
            ],
            if (dataThrough != null) ...[
              const SizedBox(height: 2),
              _MetaLine(
                text: I18n.tr(
                  'statistics.ai.data_through',
                ).replaceAll('{date}', I18nDateFormat.date(dataThrough)),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              e.summary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.68),
                fontWeight: DesignTokens.fontWeightStrong,
              ),
            ),
            ClipRect(
              key: ValueKey('ai_history_content_${e.id}'),
              child: AnimatedSize(
                duration: AppMotion.transition(context),
                curve: AppMotion.enterCurve,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: AiReviewMarkdown(data: e.content),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _looksLikeLegacyReport(AiReviewEntry entry) =>
      entry.reportContext == null &&
      entry.summary.startsWith(_legacyReportSummaryPrefix);

  /// 周期类型 + 完整自然周期边界 + 生成时区；日期是浮动日历日，不做时区换算。
  String _periodLine(AiReportContext reportContext) {
    final period = I18n.tr('statistics.period.${reportContext.period.name}');
    final range =
        '${I18nDateFormat.date(reportContext.start)} – '
        '${I18nDateFormat.date(reportContext.end)}';
    if (reportContext.timeZone.isEmpty) {
      return I18n.tr(
        'ai_history.period.range',
      ).replaceAll('{period}', period).replaceAll('{range}', range);
    }
    return I18n.tr('ai_history.period.line')
        .replaceAll('{period}', period)
        .replaceAll('{range}', range)
        .replaceAll('{zone}', reportContext.timeZone);
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ai = context.read<AiService>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text(I18n.tr('ai_history.clear.title')),
        icon: const Icon(Icons.delete_sweep_outlined),
        content: Text(I18n.tr('ai_history.clear.content')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(I18n.tr('ai_history.clear.action')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _expandedReviewIds.clear();
    });
    try {
      await ai.clearReviewHistory();
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(I18n.tr('statistics.ai.error.storage_failed'))),
      );
    }
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
        fontWeight: DesignTokens.fontWeightRegular,
      ),
    );
  }
}

/// 顶部紧凑的周期选择器：全部历史 + 各个已存档/进行中的自然周期。
class _PeriodPicker extends StatelessWidget {
  /// DropdownButton 把 null 当作“未选择”，所以“全部历史”用显式哨兵值。
  static const String allValue = '__all_history__';

  const _PeriodPicker({
    required this.contexts,
    required this.selectedKey,
    required this.onChanged,
  });

  final List<AiReportContext> contexts;
  final String? selectedKey;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final value = contexts.any((context) => context.key == selectedKey)
        ? selectedKey!
        : allValue;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: AppSurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        borderRadius: BorderRadius.circular(DesignTokens.radiusControlIos),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const ValueKey('ai_history_period_filter'),
            value: value,
            isExpanded: true,
            icon: Icon(
              Icons.expand_more,
              size: DesignTokens.controlIconSize,
              color: cs.onSurfaceVariant,
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: DesignTokens.fontWeightMedium,
            ),
            items: [
              DropdownMenuItem<String>(
                value: allValue,
                child: Text(
                  I18n.tr('ai_history.filter.all'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              for (final context in contexts)
                DropdownMenuItem<String>(
                  value: context.key,
                  child: Text(
                    _label(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (selected) =>
                onChanged(selected == allValue ? null : selected),
          ),
        ),
      ),
    );
  }

  String _label(AiReportContext reportContext) {
    final period = I18n.tr('statistics.period.${reportContext.period.name}');
    final range =
        '${I18nDateFormat.date(reportContext.start)} – '
        '${I18nDateFormat.date(reportContext.end)}';
    return I18n.tr(
      'ai_history.period.range',
    ).replaceAll('{period}', period).replaceAll('{range}', range);
  }
}
