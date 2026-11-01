import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_clock.dart';
import '../core/app_motion.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../models/ai_report_context.dart';
import '../models/server_config_status.dart';
import '../services/ai_service.dart';
import 'ai_review_markdown.dart';

/// 统计页「AI 解读」的状态与结果区。
///
/// 状态本身由 [AiService] 按自然周期持有（[AiReportReviewJob] 与已存档条目都
/// 以 [AiReportContext.key] 分组），因此离开本页再回来不会丢结果、也不会把上个
/// 周期的回复写进当前周期。已用时长用本组件内部的 leaf 计时器刷新，避免每秒重建
/// 整页图表；没有任务或任务结束时计时器立即取消。
class ReportAiReviewPanel extends StatefulWidget {
  const ReportAiReviewPanel({
    super.key,
    required this.aiEnabled,
    this.configStatus = ServerConfigStatus.ready,
    this.onRetryConfig,
    required this.job,
    required this.latestEntry,
    required this.onGenerate,
    required this.onRetrySave,
  });

  /// AI 是否真的可用（`AiService.enabled` 已经内建 configStatus==ready 判断）。
  /// 未启用时历史仍可查看，只是不能再生成。
  final bool aiEnabled;

  /// `/api/config` 的拉取状态。
  ///
  /// 默认 [ServerConfigStatus.ready]：旧的独立调用方不传时行为不变（显示原有的
  /// 「管理员已关闭」提示）；统计页会显式传入，避免把「还没加载」误报成管理员关闭。
  final ServerConfigStatus configStatus;

  /// 配置获取失败时的重试回调；为 null 时不显示重试按钮。
  final VoidCallback? onRetryConfig;

  /// 当前周期的任务：生成中 / 存档中 / 失败（含未存档正文）。
  final AiReportReviewJob? job;

  /// 当前周期最近一次成功存档的解读，用于重新生成或失败时继续展示旧结果。
  final AiReviewEntry? latestEntry;

  final VoidCallback onGenerate;
  final VoidCallback onRetrySave;

  @override
  State<ReportAiReviewPanel> createState() => _ReportAiReviewPanelState();
}

class _ReportAiReviewPanelState extends State<ReportAiReviewPanel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant ReportAiReviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }

  /// 只在任务进行中挂一秒一次的计时器；进度本身不伪造百分比。
  void _syncTicker() {
    final running = widget.job?.isRunning ?? false;
    if (!running) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final job = widget.job;
    final latest = widget.latestEntry;

    final blocks = <Widget>[
      if (job != null && job.isRunning) _runningBlock(theme, cs, job),
      if (job != null && job.phase == AiReportReviewPhase.failed)
        _failedBlock(theme, cs, job),
      if (latest != null && latest.content.trim().isNotEmpty)
        _latestBlock(theme, cs, latest),
      if (!widget.aiEnabled) _configStateHint(theme, cs),
    ];
    if (blocks.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (final block in blocks) {
      if (children.isNotEmpty) children.add(_divider(cs));
      children.add(block);
    }
    return Padding(
      padding: const EdgeInsets.only(top: DesignTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _divider(ColorScheme cs) => Padding(
    padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceMd),
    child: Divider(
      height: 1,
      thickness: 1,
      color: cs.onSurface.withValues(alpha: 0.08),
    ),
  );

  Widget _runningBlock(ThemeData theme, ColorScheme cs, AiReportReviewJob job) {
    final stage = job.phase == AiReportReviewPhase.saving
        ? I18n.tr('statistics.ai.stage.saving')
        : I18n.tr('statistics.ai.stage.generating');
    final seconds = _elapsedSeconds(job);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _thinProgress(cs),
        const SizedBox(height: DesignTokens.spaceSm),
        Wrap(
          spacing: DesignTokens.spaceSm,
          runSpacing: DesignTokens.spaceXxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              stage,
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: DesignTokens.fontWeightMedium,
              ),
            ),
            Text(
              I18n.tr(
                'statistics.ai.elapsed',
              ).replaceAll('{seconds}', '$seconds'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.62),
                fontWeight: DesignTokens.fontWeightRegular,
              ),
            ),
          ],
        ),
        const SizedBox(height: DesignTokens.spaceXs),
        Text(
          I18n.tr('statistics.ai.leave_hint'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: DesignTokens.fontWeightRegular,
          ),
        ),
      ],
    );
  }

  /// 细的不确定进度：没有百分比/ETA。减少动效时改为静态细线，语义仍是「进行中」。
  Widget _thinProgress(ColorScheme cs) {
    final radius = BorderRadius.circular(DesignTokens.radiusPill);
    if (AppMotion.reduced(context)) {
      return Container(
        height: 2,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.32),
          borderRadius: radius,
        ),
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: LinearProgressIndicator(
        minHeight: 2,
        backgroundColor: cs.primary.withValues(alpha: 0.12),
        color: cs.primary.withValues(alpha: 0.72),
      ),
    );
  }

  Widget _failedBlock(ThemeData theme, ColorScheme cs, AiReportReviewJob job) {
    final error = job.error ?? I18n.tr('statistics.ai.error.request_failed');
    final unsaved = job.unsavedContent?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 16, color: cs.error),
            const SizedBox(width: DesignTokens.spaceXs),
            Expanded(
              child: Text(
                error,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.error,
                  fontWeight: DesignTokens.fontWeightRegular,
                ),
              ),
            ),
          ],
        ),
        if (unsaved.isNotEmpty) ...[
          const SizedBox(height: DesignTokens.spaceSm),
          Text(
            I18n.tr('statistics.ai.unsaved_title'),
            style: theme.textTheme.labelLarge?.copyWith(
              color: cs.primary,
              fontWeight: DesignTokens.fontWeightMedium,
            ),
          ),
          const SizedBox(height: DesignTokens.spaceXs),
          AiReviewMarkdown(data: unsaved),
          const SizedBox(height: DesignTokens.spaceXs),
          Wrap(
            spacing: DesignTokens.spaceSm,
            runSpacing: DesignTokens.spaceXxs,
            children: [
              TextButton.icon(
                onPressed: () => _copy(unsaved),
                icon: const Icon(Icons.copy, size: 16),
                label: Text(I18n.tr('statistics.ai.copy_insight')),
              ),
              TextButton.icon(
                onPressed: widget.onRetrySave,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: Text(I18n.tr('statistics.ai.retry_save')),
              ),
            ],
          ),
        ] else ...[
          const SizedBox(height: DesignTokens.spaceXs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.aiEnabled ? widget.onGenerate : null,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(I18n.tr('statistics.ai.retry_generate')),
            ),
          ),
        ],
      ],
    );
  }

  Widget _latestBlock(ThemeData theme, ColorScheme cs, AiReviewEntry entry) {
    final reportContext = entry.reportContext;
    final dataThrough = entry.dataThrough;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, size: 16, color: cs.primary),
            const SizedBox(width: DesignTokens.spaceXs),
            Expanded(
              child: Text(
                I18n.tr('statistics.ai.result_title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.primary,
                  fontWeight: DesignTokens.fontWeightMedium,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: DesignTokens.spaceXs),
        if (reportContext != null)
          _metaLine(theme, cs, _periodLine(reportContext)),
        if (dataThrough != null)
          _metaLine(
            theme,
            cs,
            I18n.tr(
              'statistics.ai.data_through',
            ).replaceAll('{date}', I18nDateFormat.date(dataThrough)),
          ),
        _metaLine(
          theme,
          cs,
          I18n.tr('statistics.ai.generated_at').replaceAll(
            '{time}',
            I18nDateFormat.fullDateTime(AppClock.toLocal(entry.createdAt)),
          ),
        ),
        const SizedBox(height: DesignTokens.spaceXs),
        AiReviewMarkdown(data: entry.content),
        const SizedBox(height: DesignTokens.spaceXs),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _copy(entry.content),
            icon: const Icon(Icons.copy, size: 16),
            label: Text(I18n.tr('statistics.ai.copy_insight')),
          ),
        ),
      ],
    );
  }

  /// 不可生成时的说明：只有 ready 才是「管理员关闭」，其余如实显示加载/失败。
  Widget _configStateHint(ThemeData theme, ColorScheme cs) {
    switch (widget.configStatus) {
      case ServerConfigStatus.ready:
        return Text(
          I18n.tr('statistics.ai.disabled_hint'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: DesignTokens.fontWeightRegular,
          ),
        );
      case ServerConfigStatus.unknown:
      case ServerConfigStatus.loading:
        return _configLoadingHint(theme, cs);
      case ServerConfigStatus.failed:
        return _configFailedHint(theme, cs);
    }
  }

  /// 细加载提示：沿用任务进行中的不确定细线，不伪造百分比、不新增加卡片。
  Widget _configLoadingHint(ThemeData theme, ColorScheme cs) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _thinProgress(cs),
      const SizedBox(height: DesignTokens.spaceSm),
      Text(
        I18n.tr('statistics.ai.config.loading'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: DesignTokens.fontWeightRegular,
        ),
      ),
    ],
  );

  /// 获取失败：说明 + 原地重试，不弹对话框、不阻塞已有历史。
  Widget _configFailedHint(ThemeData theme, ColorScheme cs) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off_outlined, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: DesignTokens.spaceXs),
          Expanded(
            child: Text(
              I18n.tr('statistics.ai.config.failed'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: DesignTokens.fontWeightRegular,
              ),
            ),
          ),
        ],
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: widget.onRetryConfig,
          icon: const Icon(Icons.refresh, size: 16),
          label: Text(I18n.tr('statistics.ai.config.retry')),
        ),
      ),
    ],
  );

  Widget _metaLine(ThemeData theme, ColorScheme cs, String text) => Padding(
    padding: const EdgeInsets.only(bottom: DesignTokens.spaceXxs),
    child: Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: cs.onSurface.withValues(alpha: 0.62),
        fontWeight: DesignTokens.fontWeightRegular,
      ),
    ),
  );

  /// 周期 + 完整自然周期边界 + 生成时的时区；日期是浮动日历日，不做时区换算。
  String _periodLine(AiReportContext reportContext) {
    final period = I18n.tr('statistics.period.${reportContext.period.name}');
    final range =
        '${I18nDateFormat.date(reportContext.start)} – '
        '${I18nDateFormat.date(reportContext.end)}';
    if (reportContext.timeZone.isEmpty) {
      return I18n.tr(
        'statistics.ai.period_range',
      ).replaceAll('{period}', period).replaceAll('{range}', range);
    }
    return I18n.tr('statistics.ai.period_line')
        .replaceAll('{period}', period)
        .replaceAll('{range}', range)
        .replaceAll('{zone}', reportContext.timeZone);
  }

  int _elapsedSeconds(AiReportReviewJob job) {
    final seconds = DateTime.now().difference(job.startedAt).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  Future<void> _copy(String text) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger?.showSnackBar(
      SnackBar(content: Text(I18n.tr('ai_history.copy.done'))),
    );
  }
}
