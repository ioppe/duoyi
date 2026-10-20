import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/i18n_date_format.dart';
import '../services/permission_health_service.dart';
import 'surface_components.dart';

class NotificationHealthCard extends StatelessWidget {
  final NotificationHealthReport? report;
  final bool loading;
  final String? errorText;
  final int? pendingCount;
  final DateTime? lastTestAt;
  final VoidCallback onRefresh;
  final VoidCallback onOpenSystemSettings;
  final ValueChanged<String> onOpenNotificationChannelSettings;
  final VoidCallback onSendTest;
  final VoidCallback onSendStrongTest;
  final VoidCallback onClearPending;
  final VoidCallback onRequestNotificationPermission;
  final VoidCallback onRequestExactAlarmPermission;
  final VoidCallback onRequestFullScreenIntentPermission;

  const NotificationHealthCard({
    super.key,
    required this.onRefresh,
    required this.onOpenSystemSettings,
    required this.onOpenNotificationChannelSettings,
    required this.onSendTest,
    required this.onSendStrongTest,
    required this.onClearPending,
    required this.onRequestNotificationPermission,
    required this.onRequestExactAlarmPermission,
    required this.onRequestFullScreenIntentPermission,
    this.report,
    this.loading = false,
    this.errorText,
    this.pendingCount,
    this.lastTestAt,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final report = this.report;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: '通知健康检查',
            subtitle:
                report?.summarySubtitle ??
                (loading ? '正在检查系统权限与通知渠道' : '用于排查系统通知和闹钟异常'),
            actionLabel: '刷新',
            actionIcon: Icons.refresh_rounded,
            onAction: onRefresh,
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          _SummaryBanner(report: report, loading: loading),
          if (errorText != null) ...[
            const SizedBox(height: 12),
            AppActionTile(
              icon: Icons.error_outline,
              label: '检测失败',
              color: Colors.red,
              subtitle: errorText,
              onTap: onRefresh,
            ),
          ],
          if (report != null) ...[
            const SizedBox(height: 8),
            for (final check in report.checks) ...[
              _HealthCheckTile(
                check: check,
                onRequestNotificationPermission:
                    onRequestNotificationPermission,
                onRequestExactAlarmPermission: onRequestExactAlarmPermission,
                onRequestFullScreenIntentPermission:
                    onRequestFullScreenIntentPermission,
                onOpenSystemSettings: onOpenSystemSettings,
                onOpenNotificationChannelSettings:
                    onOpenNotificationChannelSettings,
              ),
              const SizedBox(height: 2),
            ],
          ],
          const SizedBox(height: 8),
          AppSettingsTile(
            icon: Icons.notifications_active_outlined,
            color: cs.primary,
            title: '立即发送测试通知',
            subtitle: lastTestAt == null
                ? '验证普通通知渠道是否可见、可响铃'
                : '上次测试 ${_formatDateTime(lastTestAt!)}',
            onTap: onSendTest,
          ),
          AppSettingsTile(
            icon: Icons.alarm_on_outlined,
            color: Colors.deepOrange,
            title: '测试强提醒铃声',
            subtitle: '验证闹钟提醒、内置铃声和通知停止按钮，同时检查系统闹钟音量和勿扰影响，可能会响铃',
            onTap: onSendStrongTest,
          ),
          if (report == null ||
              report.summaryStatus != PermissionHealthStatus.ok)
            AppSettingsTile(
              icon: Icons.settings_outlined,
              color: Colors.deepOrange,
              title: '疑难设置入口',
              subtitle: '系统无法直达厂商开关时再打开应用页；先按上方检查项逐项确认',
              onTap: onOpenSystemSettings,
            ),
          AppSettingsTile(
            icon: Icons.schedule,
            color: Colors.teal,
            title: '已调度提醒',
            subtitle: pendingCount == null
                ? '正在读取待触发队列'
                : '${pendingCount!} 条待触发',
            trailing: pendingCount == null
                ? null
                : (pendingCount! > 0
                      ? TextButton(
                          onPressed: onClearPending,
                          child: const Text('全部取消'),
                        )
                      : const Icon(Icons.check_circle, color: Colors.green)),
          ),
        ],
      ),
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  final NotificationHealthReport? report;
  final bool loading;

  const _SummaryBanner({required this.report, required this.loading});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = report?.summaryStatus ?? PermissionHealthStatus.unknown;
    final color = _statusColor(status, cs);
    final icon = _statusIcon(status);
    final title = report?.summaryTitle ?? (loading ? '正在检查' : '尚未读取通知健康状态');
    final subtitle = report == null
        ? (loading ? '请稍候，正在读取权限和渠道状态' : '刷新后可查看系统通知健康结果')
        : '${report!.checks.length} 项检查 · ${_formatDateTime(report!.checkedAt)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 0.45),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: DesignTokens.fontWeightStrong,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.66),
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

class _HealthCheckTile extends StatelessWidget {
  final PermissionHealthCheck check;
  final VoidCallback onRequestNotificationPermission;
  final VoidCallback onRequestExactAlarmPermission;
  final VoidCallback onRequestFullScreenIntentPermission;
  final VoidCallback onOpenSystemSettings;
  final ValueChanged<String> onOpenNotificationChannelSettings;

  const _HealthCheckTile({
    required this.check,
    required this.onRequestNotificationPermission,
    required this.onRequestExactAlarmPermission,
    required this.onRequestFullScreenIntentPermission,
    required this.onOpenSystemSettings,
    required this.onOpenNotificationChannelSettings,
  });

  @override
  Widget build(BuildContext context) {
    final VoidCallback? action = switch (check.action) {
      PermissionHealthAction.requestNotificationPermission =>
        onRequestNotificationPermission,
      PermissionHealthAction.requestExactAlarmPermission =>
        onRequestExactAlarmPermission,
      PermissionHealthAction.requestFullScreenIntentPermission =>
        onRequestFullScreenIntentPermission,
      PermissionHealthAction.openAppSettings =>
        check.actionChannelIds.isNotEmpty
            ? () => onOpenNotificationChannelSettings(
                check.actionChannelIds.first,
              )
            : onOpenSystemSettings,
      PermissionHealthAction.none => null,
      null => null,
    };
    final trailing = _actionTrailing(context, action);

    final color = _statusColor(check.status, Theme.of(context).colorScheme);
    final icon = check.manual
        ? Icons.tips_and_updates_outlined
        : _statusIcon(check.status);

    return AppSettingsTile(
      icon: icon,
      color: color,
      title: check.title,
      subtitle: check.manual ? '${check.subtitle} · 需要人工确认' : check.subtitle,
      trailing: trailing,
    );
  }

  Widget _actionTrailing(BuildContext context, VoidCallback? action) {
    final color = _statusColor(check.status, Theme.of(context).colorScheme);
    if (check.action == PermissionHealthAction.openAppSettings &&
        check.actionChannelIds.length > 1) {
      return PopupMenuButton<String>(
        tooltip: check.actionLabel ?? '渠道设置',
        icon: Icon(Icons.tune_outlined, color: color),
        onSelected: onOpenNotificationChannelSettings,
        itemBuilder: (context) => [
          for (final id in check.actionChannelIds)
            PopupMenuItem(
              value: id,
              child: AppSecondaryMenuText(_notificationChannelLabel(id)),
            ),
        ],
      );
    }
    if (action == null) {
      return Icon(_statusTrailingIcon(check.status), color: color);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 112),
      child: TextButton(
        key: const ValueKey('notification_health_action_button'),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: action,
        child: Text(
          check.actionLabel ?? '处理',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

String _notificationChannelLabel(String id) {
  if (id.contains('alarm') || id.contains('fullscreen')) return '强提醒渠道';
  if (id.contains('fallback')) return '闹钟兜底通知';
  if (id.contains('native') || id.contains('status')) return '内置铃声状态';
  if (id.contains('reminder') ||
      id.contains('notification') ||
      id.contains('general') ||
      id.contains('alerts')) {
    return '通知提醒渠道';
  }
  return id;
}

Color _statusColor(PermissionHealthStatus status, ColorScheme cs) {
  switch (status) {
    case PermissionHealthStatus.ok:
      return Colors.green;
    case PermissionHealthStatus.warning:
      return Colors.orange;
    case PermissionHealthStatus.blocked:
      return Colors.red;
    case PermissionHealthStatus.unknown:
      return cs.primary;
  }
}

IconData _statusIcon(PermissionHealthStatus status) {
  switch (status) {
    case PermissionHealthStatus.ok:
      return Icons.check_circle_outline;
    case PermissionHealthStatus.warning:
      return Icons.warning_amber_outlined;
    case PermissionHealthStatus.blocked:
      return Icons.error_outline;
    case PermissionHealthStatus.unknown:
      return Icons.help_outline;
  }
}

IconData _statusTrailingIcon(PermissionHealthStatus status) {
  switch (status) {
    case PermissionHealthStatus.ok:
      return Icons.check_circle;
    case PermissionHealthStatus.warning:
      return Icons.info_outline;
    case PermissionHealthStatus.blocked:
      return Icons.priority_high;
    case PermissionHealthStatus.unknown:
      return Icons.help_outline;
  }
}

String _formatDateTime(DateTime value) {
  return I18nDateFormat.fullDateTime(value);
}
