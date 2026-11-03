import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../models/goal.dart' show ReminderKind;
import '../services/permission_health_service.dart';
import '../services/web_notifications/web_notification_core.dart';
import '../services/web_notifications/web_notification_service.dart';
import 'surface_components.dart';

class ReminderHealthHint extends StatefulWidget {
  final ReminderKind reminderKind;
  final VoidCallback onOpenSystemSettings;
  final Future<void> Function() onRequestNotificationPermission;
  final Future<void> Function() onRequestExactAlarmPermission;
  final Future<void> Function() onRequestFullScreenIntentPermission;

  /// Web 分支读取的浏览器通知状态；默认 [WebNotificationService.instance]。
  final WebNotificationService? webNotifications;

  /// 测试钩子：强制使用 Web 分支（VM 上 `kIsWeb` 恒为 false）。
  final bool? forceWebBranch;

  const ReminderHealthHint({
    super.key,
    required this.reminderKind,
    required this.onOpenSystemSettings,
    required this.onRequestNotificationPermission,
    required this.onRequestExactAlarmPermission,
    required this.onRequestFullScreenIntentPermission,
    this.webNotifications,
    this.forceWebBranch,
  });

  @override
  State<ReminderHealthHint> createState() => _ReminderHealthHintState();
}

class _ReminderHealthHintState extends State<ReminderHealthHint>
    with WidgetsBindingObserver {
  late Future<NotificationHealthReport> _future;
  bool _webBusy = false;
  String? _webFeedback;

  WebNotificationService get _web =>
      widget.webNotifications ?? WebNotificationService.instance;

  bool get _useWebBranch => widget.forceWebBranch ?? _web.isWeb;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = PermissionHealthService.instance.check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    if (_useWebBranch) {
      // 用户在地址栏站点设置里外部改动后，重新读取真实浏览器状态。
      await _web.refreshPermission();
      if (!mounted) return;
    }
    setState(() {
      _future = PermissionHealthService.instance.check();
    });
  }

  Future<void> _handleNotificationPermission() async {
    await widget.onRequestNotificationPermission();
    await _refresh();
  }

  Future<void> _handleExactAlarmPermission() async {
    await widget.onRequestExactAlarmPermission();
    await _refresh();
  }

  Future<void> _handleFullScreenIntentPermission() async {
    await widget.onRequestFullScreenIntentPermission();
    await _refresh();
  }

  /// Web 分支的授权入口：点击链路里同步发起浏览器原生请求，然后展示结果。
  Future<void> _handleWebNotificationPermission() async {
    if (_webBusy) return;
    setState(() {
      _webBusy = true;
      _webFeedback = null;
    });
    WebNotificationRequestResult? result;
    Object? error;
    try {
      // 不要在这个 await 之前做任何其它异步操作：否则浏览器会判定本次
      // requestPermission 不在用户手势里，直接静默拒绝弹框。
      await widget.onRequestNotificationPermission();
      result = _web.lastRequest;
      if (result == null) {
        // 回调没有经过浏览器核心（例如注入的其它实现）时回读真实状态。
        await _web.refreshPermission();
      }
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    final feedback = _webFeedbackText(result: result, error: error);
    setState(() {
      _webBusy = false;
      // 已授权时状态行本身已经说明情况，不重复堆一段反馈。
      _webFeedback = result?.isGranted == true ? null : feedback;
    });
  }

  String _webFeedbackText({
    WebNotificationRequestResult? result,
    Object? error,
  }) {
    if (error != null) return I18n.tr('reminder.web.status.failed');
    switch (result?.outcome) {
      case WebNotificationRequestOutcome.granted:
        return I18n.tr('reminder.web.status.granted');
      case WebNotificationRequestOutcome.denied:
        return I18n.tr('reminder.web.status.denied');
      case WebNotificationRequestOutcome.dismissed:
        return I18n.tr('reminder.web.status.dismissed');
      case WebNotificationRequestOutcome.unsupported:
        return I18n.tr('reminder.web.status.unsupported');
      case WebNotificationRequestOutcome.insecureContext:
        return I18n.tr('reminder.web.status.insecure');
      case WebNotificationRequestOutcome.failed:
        return I18n.tr('reminder.web.status.failed');
      case null:
        if (_web.permissionGranted) {
          return I18n.tr('reminder.web.status.granted');
        }
        if (_web.permission == WebNotificationPermission.denied) {
          return I18n.tr('reminder.web.status.denied');
        }
        return I18n.tr('reminder.web.status.dismissed');
    }
  }

  Widget _buildWebBranch(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final support = _web.support;
    final permission = _web.permission;

    PermissionHealthStatus status = PermissionHealthStatus.blocked;
    String subtitle = I18n.tr('reminder.web.status.prompt');
    IconData icon = Icons.notifications_outlined;
    var canRequest = false;

    if (support == WebNotificationSupport.insecureContext) {
      status = PermissionHealthStatus.warning;
      subtitle = I18n.tr('reminder.web.status.insecure');
      icon = Icons.lock_outline;
    } else if (support == WebNotificationSupport.unsupported) {
      status = PermissionHealthStatus.warning;
      subtitle = I18n.tr('reminder.web.status.unsupported');
      icon = Icons.notifications_off_outlined;
    } else if (permission == WebNotificationPermission.granted) {
      status = PermissionHealthStatus.ok;
      subtitle = I18n.tr('reminder.web.status.granted');
      icon = Icons.notifications_active_outlined;
    } else if (permission == WebNotificationPermission.denied) {
      // 浏览器已拒绝时不会再弹框，重复请求无效，只提示去站点设置。
      status = PermissionHealthStatus.blocked;
      subtitle = I18n.tr('reminder.web.status.denied');
      icon = Icons.notifications_off_outlined;
    } else {
      status = PermissionHealthStatus.blocked;
      subtitle = I18n.tr('reminder.web.status.prompt');
      icon = Icons.notifications_off_outlined;
      canRequest = true;
    }

    if (_webBusy) {
      subtitle = I18n.tr('reminder.web.status.requesting');
    }

    final color = switch (status) {
      PermissionHealthStatus.ok => Colors.green,
      PermissionHealthStatus.warning => Colors.orange,
      PermissionHealthStatus.blocked => Colors.red,
      PermissionHealthStatus.unknown => Colors.blueGrey,
    };

    final Widget trailing;
    if (_webBusy) {
      trailing = const SizedBox(
        width: DesignTokens.controlIconSize,
        height: DesignTokens.controlIconSize,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (canRequest) {
      trailing = TextButton(
        onPressed: _handleWebNotificationPermission,
        child: Text(I18n.tr('reminder.web.action.request')),
      );
    } else {
      trailing = Icon(
        status == PermissionHealthStatus.ok
            ? Icons.check_circle
            : Icons.info_outline,
        color: color,
      );
    }

    // 用户在站点设置里重新允许后，旧的拒绝反馈不应继续显示。
    final feedback = _web.permissionGranted ? null : _webFeedback;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppActionTile(
          icon: icon,
          label: I18n.tr('reminder.health'),
          color: color,
          // Web 没有「应用通知设置」入口，避免跳到无意义的系统页面。
          onTap: null,
          trailing: trailing,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.spaceLg,
            0,
            DesignTokens.spaceLg,
            DesignTokens.spaceSm,
          ),
          child: Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: DesignTokens.fontWeightRegular,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        if (feedback != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spaceLg,
              0,
              DesignTokens.spaceLg,
              DesignTokens.spaceSm,
            ),
            child: Text(
              feedback,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: DesignTokens.fontSizeCaption,
                fontWeight: DesignTokens.fontWeightRegular,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_useWebBranch) return _buildWebBranch(context);
    return FutureBuilder<NotificationHealthReport>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return AppActionTile(
            icon: Icons.error_outline,
            label: '提醒健康',
            color: Colors.red,
            subtitle: '无法读取系统提醒状态',
            onTap: widget.onOpenSystemSettings,
          );
        }

        final report = snap.data;
        final notificationGranted = report?.notificationGranted ?? false;
        final exactGranted = report?.exactAlarmGranted ?? false;
        final fullScreenIntentGranted =
            report?.fullScreenIntentGranted ?? false;
        final isXiaomi = report?.isXiaomiLike ?? false;
        final alarmKind = widget.reminderKind == ReminderKind.alarm;

        PermissionHealthStatus status = PermissionHealthStatus.unknown;
        String subtitle = '正在读取提醒健康状态';
        VoidCallback? action;
        String? actionLabel;
        IconData icon = Icons.notifications_outlined;

        if (report != null) {
          if (!notificationGranted) {
            status = PermissionHealthStatus.blocked;
            subtitle = '系统通知未授权，提醒不会正常显示';
            action = _handleNotificationPermission;
            actionLabel = '通知授权';
            icon = Icons.notifications_off_outlined;
          } else if (alarmKind && !exactGranted) {
            status = PermissionHealthStatus.blocked;
            subtitle = '系统通知已授权，但精准闹钟未开启，强提醒可能延后';
            action = _handleExactAlarmPermission;
            actionLabel = '精准闹钟';
            icon = Icons.alarm_off_outlined;
          } else if (alarmKind && !fullScreenIntentGranted) {
            status = PermissionHealthStatus.blocked;
            subtitle = '弹出屏幕权限未允许，强提醒可能只显示在通知栏';
            action = _handleFullScreenIntentPermission;
            actionLabel = '弹屏权限';
            icon = Icons.phonelink_lock_outlined;
          } else if (report.hasWarnings) {
            status = PermissionHealthStatus.warning;
            subtitle = isXiaomi
                ? 'HyperOS/MIUI 需确认自启动、后台、电池、锁屏、横幅和渠道声音'
                : 'Android 设备还要检查后台和电池限制';
            icon = Icons.tips_and_updates_outlined;
          } else if (report.hasUnknown) {
            status = PermissionHealthStatus.unknown;
            subtitle = '部分系统状态无法自动读取';
            icon = Icons.help_outline;
          } else {
            status = PermissionHealthStatus.ok;
            subtitle = alarmKind ? '系统通知、精准闹钟和弹屏权限均已就绪' : '系统通知已授权，提醒可正常进入通知中心';
            icon = Icons.notifications_active_outlined;
          }
        }

        final color = switch (status) {
          PermissionHealthStatus.ok => Colors.green,
          PermissionHealthStatus.warning => Colors.orange,
          PermissionHealthStatus.blocked => Colors.red,
          PermissionHealthStatus.unknown => Colors.blueGrey,
        };

        return AppActionTile(
          icon: icon,
          label: '提醒健康',
          color: color,
          subtitle: subtitle,
          onTap: widget.onOpenSystemSettings,
          trailing: action == null
              ? Icon(Icons.check_circle, color: color)
              : TextButton(onPressed: action, child: Text(actionLabel ?? '处理')),
        );
      },
    );
  }
}
