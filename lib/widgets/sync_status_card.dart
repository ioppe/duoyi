import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../providers/sync_status_presenter.dart';
import 'surface_components.dart';

/// 我的页"云同步状态卡"（纯展示）。
///
/// 只读消费 [SyncStatusController]（底层云同步 Provider 状态的展示层
/// 包装）：四态渲染——失败（lastError 红字 + 自动重试提示）、同步中
/// （转圈）、从未同步（引导文案）、已同步（上次同步时间，
/// hasPendingChanges 时附"待同步"角标）。
///
/// 依据架构守卫（test/services/cloud_sync_provider_test.dart
/// 「屏幕和组件层不暴露手动云同步入口」），本卡片**不提供任何手动
/// 触发同步的按钮**：同步仅由后台排队触发，失败后自动重试。
class SyncStatusCard extends StatelessWidget {
  const SyncStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SyncStatusController?>();
    if (controller == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    final String stateLabel;
    final Color stateColor;
    final IconData stateIcon;
    var detail = '';
    Color? detailColor;
    String? autoRetryHint;
    Widget? trailing;

    if (controller.lastError != null) {
      stateLabel = I18n.tr('sync.state.failed');
      stateColor = cs.error;
      stateIcon = Icons.sync_problem_outlined;
      detail = controller.lastError ?? '';
      detailColor = cs.error;
      autoRetryHint = I18n.tr('sync.state.auto_retry_hint');
    } else if (controller.isSyncing) {
      stateLabel = I18n.tr('sync.state.syncing');
      stateColor = cs.primary;
      stateIcon = Icons.sync;
      trailing = const SizedBox(
        key: ValueKey('sync_status_card_spinner'),
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (!controller.hasEverSynced) {
      stateLabel = I18n.tr('sync.state.never');
      stateColor = cs.onSurfaceVariant;
      stateIcon = Icons.cloud_off_outlined;
      detail = I18n.tr('sync.state.never_hint');
    } else {
      stateLabel = I18n.tr('sync.state.synced');
      stateColor = cs.primary;
      stateIcon = Icons.cloud_done_outlined;
      detail =
          '${I18n.tr('sync.last_sync_prefix')}'
          '${I18nDateFormat.shortDateTime(controller.lastSync)}';
      if (controller.hasPendingChanges) {
        trailing = Container(
          key: const ValueKey('sync_status_card_pending_badge'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: cs.tertiary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: cs.tertiary.withValues(alpha: 0.18),
              width: 0.5,
            ),
          ),
          child: Text(
            I18n.tr('sync.pending_badge'),
            style: TextStyle(
              fontSize: DesignTokens.fontSizeCaption,
              color: cs.tertiary,
              fontWeight: DesignTokens.fontWeightStrong,
            ),
          ),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: AppSurfaceCard(
        key: const ValueKey('sync_status_card'),
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(stateIcon, size: 18, color: stateColor),
            const SizedBox(width: DesignTokens.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    I18n.tr('sync.status.title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      color: cs.onSurface,
                      fontWeight: DesignTokens.fontWeightStrong,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stateLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeSm,
                      height: 1.2,
                      color: stateColor,
                      fontWeight: DesignTokens.fontWeightStrong,
                    ),
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeXs,
                        height: 1.3,
                        color: detailColor ?? cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (autoRetryHint != null && autoRetryHint.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      autoRetryHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeXs,
                        height: 1.3,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: DesignTokens.spaceSm),
              trailing,
            ],
          ],
        ),
      ),
    );
  }
}
