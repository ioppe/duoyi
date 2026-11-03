import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_clock.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../providers/sync_status_presenter.dart';
import 'surface_components.dart';

/// 我的页"云同步状态卡"。
///
/// 只读消费 [SyncStatusController]（底层云同步 Provider 状态的展示层
/// 包装）：四态渲染——失败（lastError 红字 + 自动重试提示）、同步中
/// （转圈）、从未同步（引导文案）、已同步（上次同步时间，
/// hasPendingChanges 时附"待同步"角标）。
///
/// 已同步时间按**应用墙钟**呈现：读取 [AppClock]（IANA 应用时区）换算后交给
/// I18nDateFormat；存储的 lastSync 仍是真实 instant，不换算、不回写、不触发同步。
///
/// 手动同步入口：整卡可点击，点击调用 `SyncStatusController.requestSync()`，
/// 由应用层注入的回调先刷新公共后端配置 / 账号 AI 配置，再同步业务数据。
/// 本卡片不直接引用底层云同步 Provider（架构守卫见
/// test/services/cloud_sync_provider_test.dart「UI 层只经
/// SyncStatusController 请求同步」）；未注入回调时整卡不可点击、也不显示
/// 刷新图标。同步中禁用点击并保留既有转圈，空闲时右侧显示小型刷新图标
/// （tooltip + button 语义）。失败后可再次点击重试。
class SyncStatusCard extends StatelessWidget {
  const SyncStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SyncStatusController?>();
    if (controller == null) return const SizedBox.shrink();
    // 上次同步时间按应用墙钟展示：跟随 IANA 应用时区重建（main 根部已有 scope）。
    AppClock.watch(context);
    final cs = Theme.of(context).colorScheme;
    final canSync = controller.canSync;

    final String stateLabel;
    final Color stateColor;
    final IconData stateIcon;
    var detail = '';
    Color? detailColor;
    String? autoRetryHint;
    Widget? trailing;

    final lastError = controller.lastError;
    if (lastError != null || controller.syncRequestFailed) {
      stateLabel = I18n.tr('sync.state.failed');
      stateColor = cs.error;
      stateIcon = Icons.sync_problem_outlined;
      // 手动请求失败只呈现失败态，不展示异常文本（可能含地址 / token）。
      detail = lastError ?? '';
      detailColor = lastError != null ? cs.error : null;
      if (lastError != null) {
        autoRetryHint = I18n.tr('sync.state.auto_retry_hint');
      }
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
      // 存储的 lastSync 是真实 instant：只按应用时区换算显示，不回写、不触发同步。
      final syncedAt = AppClock.toLocal(controller.lastSync);
      detail =
          '${I18n.tr('sync.last_sync_prefix')}'
          '${I18nDateFormat.shortDateTime(syncedAt)}';
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
        onTap: canSync ? () => unawaited(controller.requestSync()) : null,
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
            if (canSync) ...[
              const SizedBox(width: DesignTokens.spaceSm),
              Tooltip(
                key: const ValueKey('sync_status_card_sync_action'),
                message: I18n.tr('sync.action.sync_now'),
                child: Semantics(
                  button: true,
                  label: I18n.tr('sync.action.sync_now'),
                  child: Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
