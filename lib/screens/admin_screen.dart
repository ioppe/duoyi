import '../core/app_clock.dart';
import '../core/app_motion.dart';
import '../widgets/app_page_tabs.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/app_version.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../providers/auth_provider.dart';
import '../services/admin_api.dart';
import '../services/ai_service.dart';
import '../services/api_client.dart';
import '../widgets/empty_state.dart';
import '../widgets/result_states.dart' show ErrorState, LoadingState;
import '../widgets/surface_components.dart';

/// 管理员后台 — 仅当 AuthProvider.state.isAdmin == true 时可进入。
class AdminScreen extends StatefulWidget {
  final int initialTabIndex;

  const AdminScreen({super.key, this.initialTabIndex = 0});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  static const int _adminTabCount = 10;
  late TabController _tabs;
  late final List<int> _tabRefreshSerials;
  late int _activeTabIndex;

  @override
  void initState() {
    super.initState();
    _activeTabIndex = widget.initialTabIndex.clamp(0, _adminTabCount - 1);
    _tabs = TabController(
      length: _adminTabCount,
      vsync: this,
      initialIndex: _activeTabIndex,
    );
    _tabs.addListener(_handleTabChanged);
    _tabRefreshSerials = List<int>.filled(_adminTabCount, 0);
  }

  @override
  void dispose() {
    _tabs.removeListener(_handleTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    final nextIndex = _tabs.index.clamp(0, _adminTabCount - 1);
    if (nextIndex == _activeTabIndex) return;
    setState(() => _activeTabIndex = nextIndex);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    if (!auth.state.isLoggedIn || !auth.state.isAdmin) {
      return Scaffold(
        backgroundColor: routeBackground,
        appBar: AppBar(
          title: const Text('管理员后台'),
          titleTextStyle: appSecondaryRouteTitleTextStyle(context),
          backgroundColor: routeBackground.withValues(alpha: 0.96),
          surfaceTintColor: Colors.transparent,
        ),
        body: const EmptyState(icon: Icons.lock, message: '仅管理员可访问'),
      );
    }
    final api = AdminApi(auth.client);

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: const Text('管理员后台'),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '刷新当前页',
            onPressed: () {
              final index = _tabs.index.clamp(0, _tabRefreshSerials.length - 1);
              setState(() => _tabRefreshSerials[index]++);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: AppPageTabs(
          controller: _tabs,
          height: AppPageTabs.heightFor(context),
          tabs: const [
            Tab(
              height: 34,
              child: _AdminTabLabel(icon: Icons.dashboard_outlined, text: '概览'),
            ),
            Tab(
              height: 34,
              child: _AdminTabLabel(icon: Icons.tune, text: '全站设置'),
            ),
            Tab(
              height: 34,
              child: _AdminTabLabel(icon: Icons.auto_awesome, text: 'AI 配置'),
            ),
            Tab(
              height: 34,
              child: _AdminTabLabel(icon: Icons.cloud_outlined, text: '云端备份'),
            ),
            Tab(
              height: 34,
              child: _AdminTabLabel(icon: Icons.people_outline, text: '用户'),
            ),
            Tab(
              height: 34,
              child: _AdminTabLabel(icon: Icons.groups_2_outlined, text: '用户组'),
            ),
            Tab(
              height: 34,
              child: _AdminTabLabel(icon: Icons.campaign_outlined, text: '公告'),
            ),
            Tab(
              height: 34,
              child: _AdminTabLabel(
                icon: Icons.feedback_outlined,
                text: '许愿与反馈',
              ),
            ),
            Tab(
              height: 34,
              child: _AdminTabLabel(icon: Icons.vpn_key_outlined, text: '邀请码'),
            ),
            Tab(
              height: 34,
              child: _AdminTabLabel(
                icon: Icons.receipt_long_outlined,
                text: '日志',
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _AdminTabContent(
            child: _DashboardTab(
              key: ValueKey('admin-dashboard-${_tabRefreshSerials[0]}'),
              api: api,
            ),
          ),
          _AdminTabContent(
            child: _SettingsTab(
              key: ValueKey('admin-settings-${_tabRefreshSerials[1]}'),
              api: api,
              selfAdminPermissions: auth.state.adminPermissions,
            ),
          ),
          _AdminTabContent(
            child: _AiSettingsTab(
              key: ValueKey('admin-ai-${_tabRefreshSerials[2]}'),
              api: api,
            ),
          ),
          _AdminTabContent(
            child: _BackupSettingsTab(
              key: ValueKey('admin-backup-${_tabRefreshSerials[3]}'),
              api: api,
            ),
          ),
          _AdminTabContent(
            child: _UsersTab(
              key: ValueKey('admin-users-${_tabRefreshSerials[4]}'),
              api: api,
              selfId: auth.state.userId,
              selfAdminPermissions: auth.state.adminPermissions,
              isActive: _activeTabIndex == 4,
            ),
          ),
          _AdminTabContent(
            child: _GroupsTab(
              key: ValueKey('admin-groups-${_tabRefreshSerials[5]}'),
              api: api,
              selfAdminPermissions: auth.state.adminPermissions,
            ),
          ),
          _AdminTabContent(
            child: _AnnouncementsTab(
              key: ValueKey('admin-announcements-${_tabRefreshSerials[6]}'),
              api: api,
            ),
          ),
          _AdminTabContent(
            child: _FeedbackTab(
              key: ValueKey('admin-feedback-${_tabRefreshSerials[7]}'),
              api: api,
            ),
          ),
          _AdminTabContent(
            child: _InvitesTab(
              key: ValueKey('admin-invites-${_tabRefreshSerials[8]}'),
              api: api,
            ),
          ),
          _AdminTabContent(
            child: _AuditLogTab(
              key: ValueKey('admin-audit-${_tabRefreshSerials[9]}'),
              api: api,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminTabContent extends StatelessWidget {
  final Widget child;

  const _AdminTabContent({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: SizedBox(
              width: double.infinity,
              height: constraints.maxHeight,
              child: AppSecondaryControlTheme(
                child: _AdminGlassControlTheme(child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AdminGlassControlTheme extends StatelessWidget {
  final Widget child;

  const _AdminGlassControlTheme({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final controlText = appSecondaryControlTextStyle(
      context,
    ).copyWith(color: cs.onSurface, fontWeight: DesignTokens.fontWeightStrong);
    final labelText = appSecondaryControlLabelStyle(
      context,
    ).copyWith(color: cs.onSurface, fontWeight: DesignTokens.fontWeightStrong);
    final selectedFill = isDark
        ? cs.primary.withValues(alpha: 0.16)
        : cs.primary.withValues(alpha: 0.075);
    final selectedBorder = cs.primary.withValues(alpha: isDark ? 0.24 : 0.18);
    final selectedForeground = cs.onSurface;
    final defaultBorder = cs.outlineVariant.withValues(
      alpha: isDark ? 0.09 : 0.11,
    );
    final glassFill = isDark
        ? cs.surfaceContainerHighest.withValues(alpha: 0.28)
        : cs.surfaceContainerHighest.withValues(alpha: 0.36);

    ButtonStyle adminTextButtonStyle() {
      return TextButton.styleFrom(
        foregroundColor: cs.primary,
        textStyle: controlText,
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    ButtonStyle adminOutlinedButtonStyle() {
      return OutlinedButton.styleFrom(
        foregroundColor: cs.onSurface,
        disabledForegroundColor: cs.onSurface.withValues(alpha: 0.36),
        side: BorderSide(color: defaultBorder, width: 0.45),
        textStyle: controlText,
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    ButtonStyle adminFilledButtonStyle() {
      return FilledButton.styleFrom(
        backgroundColor: glassFill,
        foregroundColor: cs.onSurface,
        disabledBackgroundColor: glassFill.withValues(alpha: 0.42),
        disabledForegroundColor: cs.onSurface.withValues(alpha: 0.34),
        side: BorderSide(color: defaultBorder, width: 0.45),
        textStyle: controlText,
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    return Theme(
      data: theme.copyWith(
        textButtonTheme: TextButtonThemeData(style: adminTextButtonStyle()),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: adminOutlinedButtonStyle(),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: adminFilledButtonStyle(),
        ),
        chipTheme: theme.chipTheme.copyWith(
          labelStyle: labelText.copyWith(color: cs.onSurface),
          secondaryLabelStyle: labelText.copyWith(color: selectedForeground),
          selectedColor: selectedFill,
          backgroundColor: glassFill.withValues(alpha: 0.72),
          disabledColor: glassFill.withValues(alpha: 0.36),
          checkmarkColor: selectedForeground,
          iconTheme: IconThemeData(size: 15, color: selectedForeground),
          side: BorderSide(color: defaultBorder, width: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(color: selectedBorder, width: 0.45),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      ),
      child: child,
    );
  }
}

class _AdminTabLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _AdminTabLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 16), const SizedBox(width: 5), Text(text)],
    );
  }
}

class _AdminChipWrap extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final List<Widget> children;

  const _AdminChipWrap({
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(12, 0, 12, 8),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(spacing: 8, runSpacing: 6, children: children),
      ),
    );
  }
}

class _AdminCompactChipStrip extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final List<Widget> children;

  const _AdminCompactChipStrip({
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(12, 0, 12, 6),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: SingleChildScrollView(
        key: const ValueKey('admin_compact_chip_strip_horizontal'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final child in children) ...[child, const SizedBox(width: 6)],
          ],
        ),
      ),
    );
  }
}

Border _adminSubtleSectionBorder(BuildContext context) {
  final theme = Theme.of(context);
  final alpha = theme.brightness == Brightness.dark ? 0.07 : 0.026;
  return Border.all(
    color: theme.colorScheme.outline.withValues(alpha: alpha),
    width: 0.45,
  );
}

Border _adminSubtleListBorder(BuildContext context) {
  final theme = Theme.of(context);
  final alpha = theme.brightness == Brightness.dark ? 0.06 : 0.020;
  return Border.all(
    color: theme.colorScheme.outline.withValues(alpha: alpha),
    width: 0.45,
  );
}

class _AdminListTileCard extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry margin;
  final bool dense;
  final bool isThreeLine;

  const _AdminListTileCard({
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.margin = EdgeInsets.zero,
    this.dense = false,
    this.isThreeLine = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppListTileCard(
      title: title,
      leading: leading,
      subtitle: subtitle,
      trailing: trailing,
      margin: margin,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      dense: dense,
      isThreeLine: isThreeLine,
      border: _adminSubtleListBorder(context),
      elevation: 0,
    );
  }
}

class _AdminSettingsSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const _AdminSettingsSection({
    required this.title,
    required this.children,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return AppSettingsSection(
      title: title,
      subtitle: subtitle,
      border: _adminSubtleSectionBorder(context),
      elevation: 0,
      children: children,
    );
  }
}

class _AdminPermissionGroupPanel extends StatelessWidget {
  final _AdminPermissionGroup group;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  const _AdminPermissionGroupPanel({
    required this.group,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final visiblePermissions = group.permissions
        .where(_adminPermissionLabels.containsKey)
        .toList(growable: false);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: cs.outlineVariant.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.12 : 0.14,
          ),
          width: 0.55,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(group.icon, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  group.title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final permission in visiblePermissions)
              CheckboxListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: EdgeInsets.zero,
                value: selected.contains(permission),
                title: Text(_adminPermissionLabels[permission] ?? permission),
                onChanged: (value) {
                  final next = selected.toSet();
                  if (value == true) {
                    next.add(permission);
                  } else {
                    next.remove(permission);
                  }
                  onChanged(next);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _AdminGroupSummaryCard extends StatelessWidget {
  final Map<String, dynamic> group;
  final bool canManage;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool showDelete;

  const _AdminGroupSummaryCard({
    required this.group,
    required this.canManage,
    this.onEdit,
    this.onDelete,
    this.showDelete = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final active = group['is_active'] != false;
    final id = (group['id'] ?? '').toString();
    final name = (group['name'] ?? id).toString();
    final description = adminVisibleDescription(group['description']);
    final userCount = _adminIntValue(group['user_count']);
    final statusColor = active ? Colors.green : cs.onSurfaceVariant;
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      borderRadius: BorderRadius.circular(9),
      border: _adminSubtleListBorder(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (active ? cs.primary : cs.onSurfaceVariant).withValues(
                alpha: 0.10,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.groups_2_outlined,
              color: active ? cs.primary : cs.onSurfaceVariant,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? '未命名用户组' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    AppStatusBadge(
                      label: '$userCount 人',
                      color: cs.primary,
                      icon: Icons.people_outline,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                    ),
                    AppStatusBadge(
                      label: active ? '启用' : '停用',
                      color: statusColor,
                      icon: active
                          ? Icons.check_circle_outline
                          : Icons.pause_circle_outline,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (canManage)
            SizedBox(
              width: showDelete && id != 'group_default' ? 82 : 40,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 2,
                children: [
                  IconButton(
                    tooltip: '编辑用户组',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  if (showDelete && id != 'group_default')
                    IconButton(
                      key: ValueKey('admin_group_delete_$id'),
                      tooltip: '删除用户组',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AdminMobileMetaItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _AdminMobileMetaItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.68),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// 概览
// ====================================================================

class _DashboardTab extends StatefulWidget {
  final AdminApi api;
  const _DashboardTab({super.key, required this.api});
  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  Map<String, dynamic>? _stats;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _stats = await widget.api.stats();
    } on ApiException catch (e) {
      _error = userVisibleApiError(e);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LoadingState();
    }
    if (_stats == null) {
      return ErrorState(
        title: I18n.tr('state.load_failed'),
        error: _error ?? I18n.tr('state.error'),
        onRetry: _load,
      );
    }
    final users = _stats!['users'] as Map? ?? {};
    final fb = _stats!['feedback'] as Map? ?? {};
    final ann = _stats!['announcements'] as Map? ?? {};
    final inv = _stats!['invites'] as Map? ?? {};
    final series = (_stats!['registration_series'] as List?)?.cast<Map>() ?? [];
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          AppInfoBanner(
            icon: Icons.verified_outlined,
            color: Colors.indigo,
            title: '客户端连接',
            message: context.watch<AuthProvider>().baseUrl.isEmpty
                ? '相对路径 (同域反代)'
                : context.watch<AuthProvider>().baseUrl,
            margin: const EdgeInsets.only(bottom: 12),
          ),
          _GridCards([
            _Kpi('总用户', '${users['total'] ?? 0}', Icons.people, Colors.blue),
            _Kpi(
              '管理员',
              '${users['admin'] ?? 0}',
              Icons.shield,
              Colors.deepOrange,
            ),
            _Kpi('已禁用', '${users['disabled'] ?? 0}', Icons.block, cs.error),
            _Kpi(
              '今日新增',
              '${users['new_today'] ?? 0}',
              Icons.person_add_alt,
              Colors.green,
            ),
            _Kpi(
              '7 日活跃',
              '${users['active_7d'] ?? 0}',
              Icons.trending_up,
              Colors.teal,
            ),
            _Kpi(
              '在线',
              '${users['online'] ?? _stats!['tokens_online'] ?? 0}',
              Icons.wifi_tethering,
              Colors.cyan,
            ),
            _Kpi(
              '邮箱未验证',
              '${users['unverified_email'] ?? 0}',
              Icons.mark_email_unread_outlined,
              Colors.amber,
            ),
            _Kpi(
              '待处理反馈',
              '${fb['open'] ?? 0}',
              Icons.chat_bubble_outline,
              Colors.orange,
            ),
            _Kpi(
              '处理中反馈',
              '${fb['in_progress'] ?? 0}',
              Icons.pending_actions_outlined,
              Colors.deepPurple,
            ),
            _Kpi(
              '反馈总数',
              '${fb['total'] ?? 0}',
              Icons.forum_outlined,
              Colors.grey,
            ),
            _Kpi(
              '公告(已发)',
              '${ann['published'] ?? 0}',
              Icons.campaign,
              Colors.indigo,
            ),
            _Kpi(
              '邀请码已用',
              '${inv['used'] ?? 0} / ${inv['total'] ?? 0}',
              Icons.vpn_key,
              Colors.purple,
            ),
          ]),
          const SizedBox(height: 14),
          AppSurfaceCard(
            padding: const EdgeInsets.all(14),
            child: Padding(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '近 7 天注册',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: DesignTokens.fontWeightStrong,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (series.isEmpty)
                    Text(
                      '暂无注册',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.58),
                      ),
                    ),
                  ...series.map((row) {
                    final count = ((row['count'] as num?) ?? 0).toDouble();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 90,
                            child: Text(
                              row['date'].toString(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.68),
                                fontWeight: DesignTokens.fontWeightStrong,
                              ),
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: (count / 10).clamp(0.0, 1.0),
                                minHeight: 8,
                                backgroundColor: cs.surfaceContainerHighest,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${row['count']}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface,
                              fontWeight: DesignTokens.fontWeightStrong,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Kpi {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const _Kpi(this.title, this.value, this.icon, this.color);
}

class _GridCards extends StatelessWidget {
  final List<_Kpi> items;
  const _GridCards(this.items);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = Theme.of(context).colorScheme;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.4,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: items
          .map(
            (k) => AppSurfaceCard(
              padding: const EdgeInsets.all(12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: k.color.withValues(alpha: 0.16),
                width: 0.45,
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: k.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(k.icon, color: k.color, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          k.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.62),
                            fontWeight: DesignTokens.fontWeightStrong,
                          ),
                        ),
                        Text(
                          k.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: DesignTokens.fontWeightStrong,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

const int _adminPageSize = 20;
const List<int> _adminPageSizeOptions = [20, 50, 100, 200];
const String _adminUpdatePresetCurrent = 'current';
const String _adminUpdatePresetNextPatch = 'next_patch';
const String _adminUpdatePresetNextMinor = 'next_minor';
const String _adminUpdatePresetMinimumNextPatch = 'minimum_next_patch';
const String _adminAllPermission = '*';
const String _adminNoPermission = '__none__';
const Map<String, String> _adminPermissionLabels = {
  'settings': '全站设置',
  'users': '用户',
  'backup': '备份',
  'ai': 'AI',
  'announcements': '公告',
  'feedback': '反馈',
  'invites': '邀请码',
  'audit': '日志',
  'groups': '用户组',
  'roles': '角色',
  'permissions': '权限字典',
};

class _AdminPermissionGroup {
  final String title;
  final IconData icon;
  final List<String> permissions;

  const _AdminPermissionGroup({
    required this.title,
    required this.icon,
    required this.permissions,
  });
}

const List<_AdminPermissionGroup> _adminPermissionGroups = [
  _AdminPermissionGroup(
    title: '基础功能',
    icon: Icons.tune,
    permissions: ['settings', 'announcements', 'invites'],
  ),
  _AdminPermissionGroup(
    title: '个人数据',
    icon: Icons.person_search_outlined,
    permissions: ['users', 'backup', 'feedback'],
  ),
  _AdminPermissionGroup(
    title: '管理功能',
    icon: Icons.admin_panel_settings_outlined,
    permissions: ['groups', 'roles', 'permissions'],
  ),
  _AdminPermissionGroup(
    title: '系统功能',
    icon: Icons.memory_outlined,
    permissions: ['ai', 'audit'],
  ),
];

Set<String> _adminAllPermissionKeys() => _adminPermissionLabels.keys.toSet();

bool _adminHasAllPermissions(Set<String> selected) {
  return _adminPermissionLabels.keys.every(selected.contains);
}

String _adminStatusLabel(String value) {
  switch (value) {
    case 'open':
      return '待处理';
    case 'in_progress':
      return '处理中';
    case 'resolved':
      return '已解决';
    case 'closed':
      return '已关闭';
    case 'published':
      return '已发布';
    case 'draft':
      return '草稿';
    case 'used':
      return '已使用';
    case 'unused':
      return '未使用';
    case 'admin':
      return '管理员';
    case 'disabled':
      return '已禁用';
    case 'active':
      return '可登录';
    case 'normal':
      return '普通用户';
    case 'online':
      return '在线';
    case 'offline':
      return '离线';
    case 'unverified_email':
      return '邮箱未验证';
    case 'verified_email':
      return '邮箱已验证';
    case 'no_email':
      return '未绑定邮箱';
    case 'has_feedback':
      return '有反馈';
    case 'info':
      return '普通';
    case 'warning':
      return '重要';
    case 'critical':
      return '紧急';
    default:
      return value.isEmpty ? '全部' : value;
  }
}

class _AdminUpdateVersionOption {
  final String key;
  final String label;
  final String latestVersion;
  final String minimumSupportedVersion;

  const _AdminUpdateVersionOption({
    required this.key,
    required this.label,
    required this.latestVersion,
    required this.minimumSupportedVersion,
  });
}

String _adminUserSortLabel(String value) {
  switch (value) {
    case 'last_active_desc':
      return '最近活跃优先';
    case 'last_login_desc':
      return '最近登录优先';
    case 'feedback_desc':
      return '反馈较多优先';
    case 'username_asc':
      return '用户名 A-Z';
    case 'email_asc':
      return '邮箱 A-Z';
    default:
      return '最新注册优先';
  }
}

List<String> _adminUserPermissions(dynamic raw, {required bool isAdmin}) =>
    parseAdminPermissions(raw, isAdmin: isAdmin);

@visibleForTesting
List<String> parseAdminPermissions(dynamic raw, {required bool isAdmin}) {
  if (raw is List) {
    final normalized = <String>[];
    for (final value in raw.map((e) => e.toString().trim())) {
      if (value == _adminNoPermission) return const [];
      if (value == _adminAllPermission) return const [_adminAllPermission];
      // Legacy permissions must survive parsing independently of UI options.
      if ((_adminPermissionLabels.containsKey(value) || value == 'coins') &&
          !normalized.contains(value)) {
        normalized.add(value);
      }
    }
    return normalized;
  }
  return isAdmin ? const [_adminAllPermission] : const [];
}

final _legacyCurrencyPattern = RegExp(
  r'coin|时光币|金币|charged|welfare|virtual.?rewards|^balance$|^lifetime$|^ledger(_entry)?$|^credit.?balance$',
  caseSensitive: false,
);

@visibleForTesting
String adminVisibleDescription(dynamic raw) => (raw ?? '')
    .toString()
    .split(RegExp(r'[。；;\n]'))
    .where((part) => !_legacyCurrencyPattern.hasMatch(part))
    .map((part) => part.trim())
    .where((part) => part.isNotEmpty)
    .join('。');

@visibleForTesting
bool adminAuditActionVisible(String action) =>
    !_legacyCurrencyPattern.hasMatch(action);

@visibleForTesting
String adminVisibleAuditDetail(dynamic raw) {
  Object? sanitize(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (!_legacyCurrencyPattern.hasMatch(entry.key.toString()))
            entry.key.toString(): sanitize(entry.value),
      };
    }
    if (value is List) {
      return value
          .where(
            (item) => item is! String || !_legacyCurrencyPattern.hasMatch(item),
          )
          .map(sanitize)
          .toList();
    }
    if (value is String && _legacyCurrencyPattern.hasMatch(value)) return '';
    return value;
  }

  if (raw == null || raw == '') return '';
  try {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    return jsonEncode(sanitize(decoded));
  } on FormatException {
    return adminVisibleDescription(raw);
  }
}

String _adminPermissionsLabel(
  List<String> permissions, {
  required bool isAdmin,
}) {
  if (!isAdmin) return '无管理权限';
  if (permissions.contains(_adminAllPermission)) return '全部权限';
  final visible = permissions
      .where(_adminPermissionLabels.containsKey)
      .toList();
  if (visible.isEmpty) return '无管理权限';
  return visible.map((key) => _adminPermissionLabels[key]!).join('、');
}

int _adminIntValue(dynamic raw) {
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? 0;
}

String _adminAnnouncementSortLabel(String value) {
  switch (value) {
    case 'updated_desc':
      return '最近更新优先';
    case 'title_asc':
      return '标题 A-Z';
    case 'level_desc':
      return '紧急程度优先';
    default:
      return '最新创建优先';
  }
}

String _adminFeedbackSortLabel(String value) {
  switch (value) {
    case 'updated_desc':
      return '最近处理优先';
    case 'status_asc':
      return '待处理优先';
    case 'user_asc':
      return '用户 A-Z';
    default:
      return '最新反馈优先';
  }
}

String _adminInviteSortLabel(String value) {
  switch (value) {
    case 'used_desc':
      return '最近使用优先';
    case 'code_asc':
      return '邀请码 A-Z';
    case 'note_asc':
      return '备注 A-Z';
    default:
      return '最新生成优先';
  }
}

String _adminAuditSortLabel(String value) {
  switch (value) {
    case 'actor_asc':
      return '管理员 A-Z';
    case 'action_asc':
      return '操作类型 A-Z';
    case 'target_asc':
      return '对象 A-Z';
    default:
      return '最新操作优先';
  }
}

String _adminBackupSortLabel(String value) {
  switch (value) {
    case 'username_asc':
      return '用户名 A-Z';
    case 'size_desc':
      return '备份体积从大到小';
    case 'size_asc':
      return '备份体积从小到大';
    case 'version_desc':
      return '同步版本较高优先';
    default:
      return '最近同步优先';
  }
}

String _adminServerBackupSortLabel(String value) {
  switch (value) {
    case 'size_desc':
      return '文件从大到小';
    case 'size_asc':
      return '文件从小到大';
    case 'status_asc':
      return '状态 A-Z';
    case 'filename_asc':
      return '文件名 A-Z';
    default:
      return '最新生成优先';
  }
}

String _auditActionLabel(String value) {
  switch (value) {
    case 'user.update':
      return '更新用户';
    case 'user.delete':
      return '删除用户';
    case 'announcement.create':
      return '创建公告';
    case 'announcement.update':
      return '更新公告';
    case 'announcement.delete':
      return '删除公告';
    case 'feedback.reply':
      return '回复反馈';
    case 'feedback.delete':
      return '删除反馈';
    case 'invite.create':
      return '生成邀请码';
    case 'invite.delete':
      return '删除邀请码';
    default:
      return value.isEmpty ? '全部操作' : value;
  }
}

String _feedbackCategoryLabel(String value) {
  switch (value) {
    case 'feature':
      return '功能建议';
    case 'bug':
      return '问题反馈';
    case 'wish':
      return '愿望清单';
    case 'other':
      return '其他';
    default:
      return value.isEmpty ? '全部分类' : value;
  }
}

String _adminPageSummary(AdminPage? page) {
  if (page == null) return '正在加载本页数据';
  if (page.total <= 0) return '0 条';
  final safeLimit = page.limit <= 0 ? _adminPageSize : page.limit;
  final maxOffset = ((page.total - 1) ~/ safeLimit) * safeLimit;
  final safeOffset = page.offset.clamp(0, maxOffset).toInt();
  final start = safeOffset + 1;
  final end = (safeOffset + page.items.length).clamp(start, page.total).toInt();
  return '第 $start-$end 条 / 共 ${page.total} 条';
}

String _adminPageNumber(AdminPage? page) {
  if (page == null) return '第 -/- 页';
  if (page.total <= 0) return '第 0/0 页';
  final safeLimit = page.limit <= 0 ? _adminPageSize : page.limit;
  final totalPages = ((page.total + safeLimit - 1) ~/ safeLimit).clamp(
    1,
    999999,
  );
  final current = ((page.offset ~/ safeLimit) + 1).clamp(1, totalPages).toInt();
  return '第 $current/$totalPages 页';
}

int _adminTotalPages(AdminPage? page, int pageSize) {
  if (page == null || page.total <= 0) return 0;
  final safeLimit = pageSize <= 0 ? _adminPageSize : pageSize;
  return ((page.total + safeLimit - 1) ~/ safeLimit).clamp(1, 999999);
}

int _previousAdminOffset(int offset, [int pageSize = _adminPageSize]) {
  return offset <= pageSize ? 0 : offset - pageSize;
}

int _offsetAfterAdminDelete({
  required int offset,
  required int itemCount,
  int pageSize = _adminPageSize,
}) {
  if (itemCount == 1 && offset > 0) {
    return _previousAdminOffset(offset, pageSize);
  }
  return offset;
}

int _lastAdminOffset({required int total, required int pageSize}) {
  if (total <= 0) return 0;
  final safeLimit = pageSize <= 0 ? _adminPageSize : pageSize;
  return ((total - 1) ~/ safeLimit) * safeLimit;
}

String _adminErrorMessage(Object error, String target) {
  final text = userVisibleApiError(error);
  return '无法加载$target：$text';
}

String _adminActionErrorMessage(Object error, String action) {
  final text = userVisibleApiError(error);
  return '$action失败：$text';
}

List<Widget> _adminDialogChildren(List<Widget> children, {double gap = 10}) {
  final separated = <Widget>[];
  for (final child in children) {
    if (separated.isNotEmpty) separated.add(SizedBox(height: gap));
    separated.add(child);
  }
  return separated;
}

Widget _adminDialogForm({
  double maxWidth = 460,
  required List<Widget> children,
}) {
  final constraints = maxWidth == 430
      ? const BoxConstraints(maxWidth: 430)
      : maxWidth == 420
      ? const BoxConstraints(maxWidth: 420)
      : maxWidth == 400
      ? const BoxConstraints(maxWidth: 400)
      : BoxConstraints(maxWidth: maxWidth);
  return ConstrainedBox(
    constraints: constraints,
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _adminDialogChildren(children),
      ),
    ),
  );
}

List<Widget> _adminDialogActions(
  BuildContext context, {
  String saveLabel = '保存',
}) {
  return [
    TextButton(
      onPressed: () => Navigator.pop(context, false),
      child: const Text('取消'),
    ),
    FilledButton(
      onPressed: () => Navigator.pop(context, true),
      child: Text(saveLabel),
    ),
  ];
}

/// Create/edit sheet body. [AppModalSheet] owns the only scroll view, so the
/// form must not add its own scroller or the sheet's keyboard avoidance and
/// drag-to-expand would fight a nested viewport.
Widget _adminSheetForm({required List<Widget> children, double gap = 10}) {
  return AppFormFieldTheme(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _adminDialogChildren(children, gap: gap),
    ),
  );
}

List<Widget> _adminSheetActions(
  BuildContext context, {
  String saveLabel = '保存',
}) {
  return [
    TextButton(
      onPressed: () => Navigator.pop(context, false),
      child: const Text('取消'),
    ),
    FilledButton(
      onPressed: () => Navigator.pop(context, true),
      child: Text(saveLabel),
    ),
  ];
}

Widget _adminPermissionChecklist({
  required Set<String> selected,
  required ValueChanged<Set<String>> onChanged,
}) {
  final allSelected = _adminHasAllPermissions(selected);
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: allSelected,
        title: const Text('全部权限'),
        onChanged: (value) =>
            onChanged(value == true ? _adminAllPermissionKeys() : <String>{}),
      ),
      const SizedBox(height: 4),
      for (final group in _adminPermissionGroups) ...[
        _AdminPermissionGroupPanel(
          group: group,
          selected: selected,
          onChanged: onChanged,
        ),
        const SizedBox(height: 8),
      ],
    ],
  );
}

Future<bool> _confirmAdminDangerAction({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = '删除',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AppDialog(
      title: Text(title),
      icon: const Icon(Icons.warning_amber_outlined),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}

class _AdminErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _AdminErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 40,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重新加载'),
              ),
            ],
          ),
        );
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : 0,
            ),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}

class _AdminInlineLoadingIndicator extends StatelessWidget {
  final bool visible;
  final String label;

  const _AdminInlineLoadingIndicator({
    required this.visible,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedSwitcher(
      duration: AppMotion.feedback(context),
      switchInCurve: AppMotion.enterCurve,
      switchOutCurve: AppMotion.exitCurve,
      child: visible
          ? Padding(
              key: ValueKey(label),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.58),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox(key: ValueKey('idle'), height: 0),
    );
  }
}

class _AdminPaginationBar extends StatelessWidget {
  final Key? barKey;
  final AdminPage? page;
  final bool loading;
  final int pageSize;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<int>? onJumpToPage;
  final ValueChanged<int>? onPageSizeChanged;

  const _AdminPaginationBar({
    this.barKey,
    required this.page,
    required this.loading,
    this.pageSize = _adminPageSize,
    required this.onPrevious,
    required this.onNext,
    this.onJumpToPage,
    this.onPageSizeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final canPrevious = !loading && (page?.offset ?? 0) > 0;
    final canNext = !loading && (page?.hasMore ?? false);
    final totalPages = _adminTotalPages(page, pageSize);
    final canPickPage =
        onJumpToPage != null && totalPages > 1 && totalPages <= 200;
    final currentPage = totalPages <= 0 || page == null
        ? 0
        : (page!.offset ~/ (page!.limit <= 0 ? pageSize : page!.limit)) + 1;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final topBorderColor = cs.outlineVariant.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.14 : 0.16,
    );
    final summaryTextStyle = appSecondaryControlLabelStyle(
      context,
    ).copyWith(color: cs.onSurface.withValues(alpha: 0.64));
    final glassControlFill = theme.brightness == Brightness.dark
        ? cs.surfaceContainerHighest.withValues(alpha: 0.30)
        : cs.surfaceContainerHighest.withValues(alpha: 0.38);
    final glassControlBorder = cs.outlineVariant.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.09 : 0.11,
    );
    return Container(
      key: barKey,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.92),
        border: Border(top: BorderSide(color: topBorderColor, width: 0.55)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final summary = Text(
            '${_adminPageSummary(page)} · ${_adminPageNumber(page)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: summaryTextStyle,
          );
          final pageSizePicker = onPageSizeChanged == null
              ? null
              : _AdminPaginationLabeledControl(
                  label: '每页',
                  child: AppCompactDropdown<int>(
                    width: 54,
                    value: pageSize,
                    items: _adminPageSizeOptions
                        .map(
                          (v) => DropdownMenuItem(value: v, child: Text('$v')),
                        )
                        .toList(),
                    onChanged: loading || onPageSizeChanged == null
                        ? null
                        : (v) {
                            if (v != null) onPageSizeChanged!(v);
                          },
                  ),
                );
          final pageJump = !canPickPage
              ? null
              : _AdminPaginationLabeledControl(
                  label: '页码',
                  child: AppCompactDropdown<int>(
                    width: 76,
                    value: currentPage.clamp(1, totalPages).toInt(),
                    items: List.generate(totalPages > 200 ? 200 : totalPages, (
                      index,
                    ) {
                      final pageNo = index + 1;
                      return DropdownMenuItem(
                        value: pageNo,
                        child: Text('$pageNo/$totalPages'),
                      );
                    }),
                    onChanged: loading
                        ? null
                        : (value) {
                            if (value != null) onJumpToPage!(value);
                          },
                  ),
                );
          Widget navigation() {
            Widget navButton({
              required String message,
              required IconData icon,
              required VoidCallback? onPressed,
            }) {
              return Tooltip(
                message: message,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: SizedBox.square(
                    dimension: 32,
                    child: IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      style: IconButton.styleFrom(
                        backgroundColor: onPressed == null
                            ? Colors.transparent
                            : glassControlFill,
                        disabledBackgroundColor: Colors.transparent,
                        side: BorderSide(
                          color: onPressed == null
                              ? glassControlBorder.withValues(alpha: 0.50)
                              : glassControlBorder,
                          width: 0.45,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            DesignTokens.radiusControl,
                          ),
                        ),
                      ),
                      onPressed: onPressed,
                      icon: Icon(icon),
                    ),
                  ),
                ),
              );
            }

            final hasPageShortcuts = onJumpToPage != null && totalPages > 1;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasPageShortcuts)
                  navButton(
                    message: '跳到第一页',
                    icon: Icons.first_page,
                    onPressed: canPrevious ? () => onJumpToPage!(1) : null,
                  ),
                navButton(
                  message: '上一页',
                  icon: Icons.chevron_left,
                  onPressed: canPrevious ? onPrevious : null,
                ),
                navButton(
                  message: '下一页',
                  icon: Icons.chevron_right,
                  onPressed: canNext ? onNext : null,
                ),
                if (hasPageShortcuts)
                  navButton(
                    message: '跳到最后一页',
                    icon: Icons.last_page,
                    onPressed: canNext ? () => onJumpToPage!(totalPages) : null,
                  ),
              ],
            );
          }

          final isCompact = constraints.maxWidth < 720;
          final fullControls = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (pageJump != null) ...[pageJump, const SizedBox(width: 6)],
              if (pageSizePicker != null) ...[
                pageSizePicker,
                const SizedBox(width: 6),
              ],
              Tooltip(message: '分页导航', child: navigation()),
            ],
          );
          final compactControls = Wrap(
            key: const ValueKey('admin_compact_pagination_controls'),
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              ?pageJump,
              ?pageSizePicker,
              Tooltip(message: '分页导航', child: navigation()),
            ],
          );
          final isVeryCompact = constraints.maxWidth < 420;
          if (isCompact) {
            if (isVeryCompact) {
              return SizedBox(
                width: double.infinity,
                key: const ValueKey('admin_compact_pagination_full_width'),
                child: Row(
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: 6),
                    Tooltip(message: '分页导航', child: navigation()),
                  ],
                ),
              );
            }
            return SizedBox(
              width: double.infinity,
              key: const ValueKey('admin_compact_pagination_full_width'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 4,
                    spacing: 8,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: summary,
                      ),
                      compactControls,
                    ],
                  ),
                ],
              ),
            );
          }
          return SizedBox(
            width: double.infinity,
            child: Row(
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: summary,
                  ),
                ),
                const SizedBox(width: 10),
                fullControls,
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AdminPaginationLabeledControl extends StatelessWidget {
  final String label;
  final Widget child;

  const _AdminPaginationLabeledControl({
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? cs.surfaceContainerHighest.withValues(alpha: 0.34)
        : cs.surfaceContainerHighest.withValues(alpha: 0.48);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.14 : 0.16),
          width: 0.55,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 68, minHeight: 32),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: appSecondaryControlLabelStyle(
                  context,
                ).copyWith(color: cs.onSurface.withValues(alpha: 0.68)),
              ),
              const SizedBox(width: 4),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupsTab extends StatefulWidget {
  final AdminApi api;
  final List<String>? selfAdminPermissions;

  const _GroupsTab({
    super.key,
    required this.api,
    required this.selfAdminPermissions,
  });

  @override
  State<_GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<_GroupsTab> {
  final List<Map<String, dynamic>> _groups = [];
  AdminPage? _page;
  bool _loading = true;
  String? _error;
  int _offset = 0;
  int _pageSize = _adminPageSize;
  int _loadSerial = 0;

  bool _canUseAdminPermission(String permission) {
    final permissions = widget.selfAdminPermissions;
    if (permissions == null) return true;
    return permissions.contains(_adminAllPermission) ||
        permissions.contains(permission);
  }

  bool get _canManageGroups => _canUseAdminPermission('groups');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int? pageSize, int? offset}) async {
    final serial = ++_loadSerial;
    final nextPageSize = pageSize ?? _pageSize;
    final nextOffset = offset ?? _offset;
    setState(() {
      _loading = true;
      _error = null;
      _pageSize = nextPageSize;
      _offset = nextOffset;
    });
    try {
      final page = await widget.api.listGroupsPage(
        limit: nextPageSize,
        offset: nextOffset,
      );
      if (!mounted || serial != _loadSerial) return;
      _page = page;
      _groups
        ..clear()
        ..addAll(page.items);
    } on ApiException catch (e) {
      if (!mounted || serial != _loadSerial) return;
      _error = userVisibleApiError(e);
    } catch (e) {
      if (!mounted || serial != _loadSerial) return;
      _error = e.toString();
    } finally {
      if (mounted && serial == _loadSerial) setState(() => _loading = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editGroup([Map<String, dynamic>? group]) async {
    if (!_canManageGroups) {
      _showSnack('缺少用户组管理权限');
      return;
    }
    final nameCtrl = TextEditingController(
      text: (group?['name'] ?? '').toString(),
    );
    final descCtrl = TextEditingController(
      text: adminVisibleDescription(group?['description']),
    );
    var isActive = group?['is_active'] != false;
    final saved = await showAppModalSheet<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AppModalSheet(
          title: group == null ? '新增用户组' : '编辑用户组',
          actions: _adminSheetActions(ctx),
          child: _adminSheetForm(
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '用户组名称'),
                textInputAction: TextInputAction.next,
              ),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: '说明',
                  helperText: '用于管理员识别该组适用的人群或规则',
                ),
                maxLines: 2,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: isActive,
                title: const Text('启用用户组'),
                subtitle: const Text('停用后不再作为可分配用户组'),
                onChanged: (value) => setSt(() => isActive = value),
              ),
            ],
          ),
        ),
      ),
    );
    final name = nameCtrl.text.trim();
    final description = descCtrl.text.trim();
    if (saved != true) return;
    if (name.isEmpty) {
      _showSnack('请填写用户组名称');
      return;
    }
    try {
      await widget.api.saveGroup(
        id: group?['id']?.toString(),
        name: name,
        description:
            description == adminVisibleDescription(group?['description'])
            ? (group?['description'] ?? '').toString()
            : description,
        isActive: isActive,
      );
      await _load(offset: _offset);
      _showSnack('用户组已保存');
    } on ApiException catch (e) {
      _showSnack(userVisibleApiError(e));
    }
  }

  Future<void> _deleteGroup(Map<String, dynamic> group) async {
    if (!_canManageGroups) {
      _showSnack('缺少用户组管理权限');
      return;
    }
    final id = (group['id'] ?? '').toString();
    if (id.isEmpty) return;
    if (id == 'group_default') {
      _showSnack('默认用户组不能删除');
      return;
    }
    final name = (group['name'] ?? id).toString();
    final userCount = _adminIntValue(group['user_count']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text('删除用户组 $name'),
        icon: const Icon(Icons.delete_outline),
        content: Text(
          userCount > 0 ? '该组内 $userCount 个用户会回退到默认用户组。' : '删除后不会影响已有用户数据。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final result = await widget.api.deleteGroup(id);
      await _load(
        offset: _offsetAfterAdminDelete(
          offset: _offset,
          itemCount: _groups.length,
          pageSize: _pageSize,
        ),
      );
      final reassigned = _adminIntValue(result['reassigned_users']);
      _showSnack(reassigned > 0 ? '用户组已删除，$reassigned 个用户已回退到默认组' : '用户组已删除');
    } on ApiException catch (e) {
      _showSnack(userVisibleApiError(e));
    } catch (e) {
      _showSnack(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _groups.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _groups.isEmpty) {
      return Center(child: Text(_error!));
    }
    final cs = Theme.of(context).colorScheme;
    final canManageGroups = _canManageGroups;
    final page =
        _page ??
        AdminPage.fromItems(_groups, limit: _pageSize, offset: _offset);
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(offset: _offset),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _AdminSettingsSection(
                  title: '用户组管理',
                  subtitle: '管理成员分组和用户组启用状态',
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final banner = AppInfoBanner(
                          icon: Icons.groups_2_outlined,
                          title: '成员分组',
                          message: '新用户加入默认组，可按使用需求调整分组。',
                          color: cs.primary,
                          margin: EdgeInsets.zero,
                        );
                        final addButton = FilledButton.icon(
                          onPressed: () => _editGroup(),
                          icon: const Icon(Icons.add),
                          label: const Text('新增用户组'),
                        );
                        if (constraints.maxWidth < 420) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              banner,
                              if (canManageGroups) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: addButton,
                                ),
                              ],
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: banner),
                            if (canManageGroups) ...[
                              const SizedBox(width: 10),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 150,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: addButton,
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (page.items.isEmpty)
                  const EmptyState(
                    icon: Icons.groups_2_outlined,
                    message: '暂无用户组',
                  )
                else
                  for (final group in page.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _AdminGroupSummaryCard(
                        group: group,
                        canManage: canManageGroups,
                        showDelete: true,
                        onEdit: () => _editGroup(group),
                        onDelete: () => _deleteGroup(group),
                      ),
                    ),
              ],
            ),
          ),
        ),
        _AdminPaginationBar(
          barKey: const ValueKey('admin_groups_pagination_bar'),
          page: page,
          loading: _loading,
          pageSize: _pageSize,
          onPrevious: () =>
              _load(offset: _previousAdminOffset(_offset, _pageSize)),
          onNext: () => _load(offset: _offset + _pageSize),
          onJumpToPage: (pageNo) =>
              _load(offset: ((pageNo - 1) * _pageSize).clamp(0, page.total)),
          onPageSizeChanged: (value) => _load(pageSize: value, offset: 0),
        ),
      ],
    );
  }
}

// ====================================================================
// 全站设置
// ====================================================================

class _SettingsTab extends StatefulWidget {
  final AdminApi api;
  final List<String>? selfAdminPermissions;

  const _SettingsTab({
    super.key,
    required this.api,
    required this.selfAdminPermissions,
  });
  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _roles = [];
  bool _loading = true;
  final Set<String> _savingKeys = <String>{};
  String? _error;
  String? _groupsRolesError;
  final _msgCtrl = TextEditingController();
  final _latestVersionCtrl = TextEditingController();
  final _minimumVersionCtrl = TextEditingController();
  String _updateVersionPreset = _adminUpdatePresetCurrent;

  bool _canUseAdminPermission(String permission) {
    final permissions = widget.selfAdminPermissions;
    if (permissions == null) return true;
    return permissions.contains(_adminAllPermission) ||
        permissions.contains(permission);
  }

  bool get _canManageGroups => _canUseAdminPermission('groups');
  bool get _canManageRoles => _canUseAdminPermission('roles');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _latestVersionCtrl.dispose();
    _minimumVersionCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _groupsRolesError = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        widget.api.getSettings(),
        _loadGroupsForSettings(),
        _loadRolesForSettings(),
      ]);
      final data = results[0] as Map<String, dynamic>;
      if (!mounted) return;
      _data = data;
      _groups = List<Map<String, dynamic>>.from(results[1] as List);
      _roles = List<Map<String, dynamic>>.from(results[2] as List);
      _msgCtrl.text = (_data['maintenance_message'] ?? '').toString();
      final latestVersion = (_data['latest_version'] ?? '').toString().trim();
      final minimumVersion = (_data['minimum_supported_version'] ?? '')
          .toString()
          .trim();
      _latestVersionCtrl.text = latestVersion.isEmpty
          ? _serverCurrentVersion
          : latestVersion;
      _minimumVersionCtrl.text = minimumVersion.isEmpty
          ? _serverCurrentVersion
          : minimumVersion;
      _updateVersionPreset = _presetForVersions(
        latestVersion: _latestVersionCtrl.text,
        minimumSupportedVersion: _minimumVersionCtrl.text,
      );
    } catch (e) {
      if (!mounted) return;
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _set(String key, dynamic value) async {
    if (key == 'force_update_required') {
      await _saveForceUpdateRequired(value == true);
      return;
    }
    setState(() => _savingKeys.add(key));
    try {
      await widget.api.updateSettings(
        inviteCodeRequired: key == 'invite_code_required' ? value : null,
        registrationEnabled: key == 'registration_enabled' ? value : null,
        registrationEmailRequired: key == 'registration_email_required'
            ? value
            : null,
        emailCodeLoginEnabled: key == 'email_code_login_enabled' ? value : null,
        maintenanceMode: key == 'maintenance_mode' ? value : null,
        maintenanceMessage: key == 'maintenance_message' ? value : null,
        forceUpdateRequired: key == 'force_update_required' ? value : null,
        latestVersion: key == 'latest_version' ? value : null,
        minimumSupportedVersion: key == 'minimum_supported_version'
            ? value
            : null,
        updateNotes: key == 'update_notes' ? value : null,
        updateDownloadUrl: key == 'update_download_url' ? value : null,
      );
      _data[key] = value;
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userVisibleApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _savingKeys.remove(key));
    }
  }

  bool _saving(String key) => _savingKeys.contains(key);

  Future<void> _reloadGroupsRoles() async {
    _groupsRolesError = null;
    final results = await Future.wait<dynamic>([
      _loadGroupsForSettings(),
      _loadRolesForSettings(),
    ]);
    if (!mounted) return;
    setState(() {
      _groups = List<Map<String, dynamic>>.from(results[0] as List);
      _roles = List<Map<String, dynamic>>.from(results[1] as List);
    });
  }

  Future<List<Map<String, dynamic>>> _loadGroupsForSettings() async {
    try {
      return await widget.api.listGroups();
    } catch (error) {
      _groupsRolesError = _adminErrorMessage(error, '用户组');
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _loadRolesForSettings() async {
    try {
      return await widget.api.listRoles();
    } catch (error) {
      final message = _adminErrorMessage(error, '角色');
      _groupsRolesError = _groupsRolesError == null
          ? message
          : '$_groupsRolesError\n$message';
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> _editGroup([Map<String, dynamic>? group]) async {
    if (!_canManageGroups) {
      _showSettingsSnack('缺少用户组管理权限');
      return;
    }
    final nameCtrl = TextEditingController(
      text: (group?['name'] ?? '').toString(),
    );
    final descCtrl = TextEditingController(
      text: adminVisibleDescription(group?['description']),
    );
    var isActive = group?['is_active'] != false;
    final saved = await showAppModalSheet<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AppModalSheet(
          title: group == null ? '新增用户组' : '编辑用户组',
          actions: _adminSheetActions(ctx),
          child: _adminSheetForm(
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '用户组名称'),
                textInputAction: TextInputAction.next,
              ),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: '说明',
                  helperText: '用于管理员识别该组适用的人群或规则',
                ),
                maxLines: 2,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: isActive,
                title: const Text('启用用户组'),
                subtitle: const Text('停用后不再作为可分配用户组'),
                onChanged: (value) => setSt(() => isActive = value),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      _showSettingsSnack('请填写用户组名称');
      return;
    }
    try {
      await widget.api.saveGroup(
        id: group?['id']?.toString(),
        name: name,
        description:
            descCtrl.text.trim() ==
                adminVisibleDescription(group?['description'])
            ? (group?['description'] ?? '').toString()
            : descCtrl.text.trim(),
        isActive: isActive,
      );
      await _reloadGroupsRoles();
      _showSettingsSnack('用户组已保存');
    } on ApiException catch (e) {
      _showSettingsSnack(userVisibleApiError(e));
    }
  }

  Future<void> _editRole([Map<String, dynamic>? role]) async {
    if (!_canManageRoles) {
      _showSettingsSnack('缺少角色管理权限');
      return;
    }
    final nameCtrl = TextEditingController(
      text: (role?['name'] ?? '').toString(),
    );
    final descCtrl = TextEditingController(
      text: (role?['description'] ?? '').toString(),
    );
    final rawPermissions = role?['permission_codes'] ?? role?['permissions'];
    var selected = _adminUserPermissions(rawPermissions, isAdmin: true).toSet();
    if (selected.contains(_adminAllPermission)) {
      selected = _adminAllPermissionKeys();
    }
    var isActive = role?['is_active'] != false;
    final saved = await showAppModalSheet<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AppModalSheet(
          title: role == null ? '新增角色' : '编辑角色',
          actions: _adminSheetActions(ctx),
          child: _adminSheetForm(
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '角色名称'),
                textInputAction: TextInputAction.next,
              ),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: '说明',
                  helperText: '说明该角色的适用对象或权限边界',
                ),
                maxLines: 2,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: isActive,
                title: const Text('启用角色'),
                subtitle: const Text('停用后不再作为可分配角色'),
                onChanged: (value) => setSt(() => isActive = value),
              ),
              _adminPermissionChecklist(
                selected: selected,
                onChanged: (next) => setSt(() => selected = next),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      _showSettingsSnack('请填写角色名称');
      return;
    }
    try {
      await widget.api.saveRole(
        id: role?['id']?.toString(),
        name: name,
        description: descCtrl.text.trim(),
        permissions: selected.toList(),
        isActive: isActive,
      );
      await _reloadGroupsRoles();
      _showSettingsSnack('角色已保存');
    } on ApiException catch (e) {
      _showSettingsSnack(userVisibleApiError(e));
    }
  }

  bool get _savingUpdateConfig => _savingKeys.any(
    const {
      'latest_version',
      'minimum_supported_version',
      'update_notes',
      'force_update_required',
    }.contains,
  );

  void _showSettingsSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String get _serverCurrentVersion {
    final value =
        (_data['current_version'] ?? _data['current_version_name'] ?? '')
            .toString()
            .trim();
    return value.isEmpty ? AppVersion.name : value;
  }

  String get _nextPatchVersion {
    final parts = _normalizedVersionParts(_serverCurrentVersion);
    return '${parts[0]}.${parts[1]}.${parts[2] + 1}';
  }

  String get _nextMinorVersion {
    final parts = _normalizedVersionParts(_serverCurrentVersion);
    return '${parts[0]}.${parts[1] + 1}.0';
  }

  String get _nextPatchMinimumVersion => _nextPatchVersion;

  List<_AdminUpdateVersionOption> get _updateVersionOptions {
    final raw = _data['version_options'];
    final options = <_AdminUpdateVersionOption>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final key = (item['key'] ?? '').toString().trim();
        final label = (item['label'] ?? '').toString().trim();
        final latest = (item['latest_version'] ?? '').toString().trim();
        final minimum = (item['minimum_supported_version'] ?? '')
            .toString()
            .trim();
        if (key.isEmpty || latest.isEmpty || minimum.isEmpty) continue;
        if (options.any((option) => option.key == key)) continue;
        options.add(
          _AdminUpdateVersionOption(
            key: key,
            label: label.isEmpty ? key : label,
            latestVersion: latest,
            minimumSupportedVersion: minimum,
          ),
        );
      }
    }
    final fallbackOptions = [
      _AdminUpdateVersionOption(
        key: _adminUpdatePresetCurrent,
        label: '当前版本',
        latestVersion: _serverCurrentVersion,
        minimumSupportedVersion: _serverCurrentVersion,
      ),
      _AdminUpdateVersionOption(
        key: _adminUpdatePresetNextPatch,
        label: '下一补丁',
        latestVersion: _nextPatchVersion,
        minimumSupportedVersion: _serverCurrentVersion,
      ),
      _AdminUpdateVersionOption(
        key: _adminUpdatePresetNextMinor,
        label: '下一小版本',
        latestVersion: _nextMinorVersion,
        minimumSupportedVersion: _serverCurrentVersion,
      ),
      _AdminUpdateVersionOption(
        key: _adminUpdatePresetMinimumNextPatch,
        label: '强制低于下一补丁',
        latestVersion: _nextPatchVersion,
        minimumSupportedVersion: _nextPatchMinimumVersion,
      ),
    ];
    if (options.isNotEmpty) {
      for (final fallback in fallbackOptions) {
        if (!options.any((option) => option.key == fallback.key)) {
          options.add(fallback);
        }
      }
      return options;
    }
    return fallbackOptions;
  }

  String _latestVersionForSave() {
    return _latestVersionCtrl.text.trim();
  }

  String _minimumSupportedVersionForSave() {
    return _minimumVersionCtrl.text.trim();
  }

  ({String latestVersion, String minimumSupportedVersion, String updateNotes})
  _normalizedUpdateVersionsForSave({
    required bool forceUpdateRequired,
    required String latestVersion,
    required String minimumSupportedVersion,
  }) {
    final latest = latestVersion.trim();
    final minimum = minimumSupportedVersion.trim();
    final current = _serverCurrentVersion;
    final isDefaultCurrentVersions = latest == current && minimum == current;
    final hasExplicitPolicy =
        forceUpdateRequired ||
        _compareAppVersions(latest, current) > 0 ||
        _compareAppVersions(minimum, current) > 0;
    if (isDefaultCurrentVersions && !hasExplicitPolicy) {
      return (latestVersion: '', minimumSupportedVersion: '', updateNotes: '');
    }
    return (
      latestVersion: latest,
      minimumSupportedVersion: minimum,
      updateNotes: _defaultUpdateNotesFor(latestVersion: latest),
    );
  }

  void _syncUpdateVersionPreset() {
    final preset = _presetForVersions(
      latestVersion: _latestVersionCtrl.text,
      minimumSupportedVersion: _minimumVersionCtrl.text,
    );
    if (_updateVersionPreset != preset) {
      setState(() => _updateVersionPreset = preset);
    }
  }

  List<int> _normalizedVersionParts(String value) {
    final parts = _versionParts(value);
    return [
      parts.isNotEmpty ? parts[0] : 0,
      parts.length > 1 ? parts[1] : 0,
      parts.length > 2 ? parts[2] : 0,
    ];
  }

  String _presetForVersions({
    required String latestVersion,
    required String minimumSupportedVersion,
  }) {
    final latest = latestVersion.trim();
    final minimum = minimumSupportedVersion.trim();
    for (final option in _updateVersionOptions) {
      if (option.latestVersion == latest &&
          option.minimumSupportedVersion == minimum) {
        return option.key;
      }
    }
    return _adminUpdatePresetCurrent;
  }

  void _applyUpdateVersionPreset(String value) {
    setState(() {
      _updateVersionPreset = value;
      _AdminUpdateVersionOption? option;
      for (final item in _updateVersionOptions) {
        if (item.key == value) {
          option = item;
          break;
        }
      }
      if (option != null) {
        _latestVersionCtrl.text = option.latestVersion;
        _minimumVersionCtrl.text = option.minimumSupportedVersion;
        return;
      }
      switch (value) {
        case _adminUpdatePresetCurrent:
          _latestVersionCtrl.text = _serverCurrentVersion;
          _minimumVersionCtrl.text = _serverCurrentVersion;
          break;
        case _adminUpdatePresetNextPatch:
          _latestVersionCtrl.text = _nextPatchVersion;
          _minimumVersionCtrl.text = _serverCurrentVersion;
          break;
        case _adminUpdatePresetNextMinor:
          _latestVersionCtrl.text = _nextMinorVersion;
          _minimumVersionCtrl.text = _serverCurrentVersion;
          break;
        case _adminUpdatePresetMinimumNextPatch:
          _latestVersionCtrl.text = _nextPatchVersion;
          _minimumVersionCtrl.text = _nextPatchMinimumVersion;
          break;
      }
    });
  }

  String _updateVersionOptionLabel(_AdminUpdateVersionOption option) {
    final label = option.label.trim();
    final latest = option.latestVersion.trim();
    final minimum = option.minimumSupportedVersion.trim();
    if (latest.isEmpty || minimum.isEmpty) {
      return label.isEmpty ? option.key : label;
    }
    if (latest == minimum) return '$label $latest';
    return '$label $latest / 最低 $minimum';
  }

  Future<void> _saveUpdateConfig() async {
    final latestVersion = _latestVersionForSave();
    final minimumSupportedVersion = _minimumSupportedVersionForSave();
    final forceUpdateRequired = _data['force_update_required'] == true;
    final versions = _normalizedUpdateVersionsForSave(
      forceUpdateRequired: forceUpdateRequired,
      latestVersion: latestVersion,
      minimumSupportedVersion: minimumSupportedVersion,
    );
    final message = _validateUpdatePolicy(
      forceUpdateRequired: forceUpdateRequired,
      latestVersion: latestVersion,
      minimumSupportedVersion: minimumSupportedVersion,
    );
    if (message != null) {
      _showSettingsSnack(message);
      return;
    }

    const keys = {
      'latest_version',
      'minimum_supported_version',
      'update_notes',
      'update_download_url',
    };
    setState(() => _savingKeys.addAll(keys));
    try {
      await widget.api.updateSettings(
        latestVersion: versions.latestVersion,
        minimumSupportedVersion: versions.minimumSupportedVersion,
        updateNotes: versions.updateNotes,
        updateDownloadUrl: '',
      );
      _data['latest_version'] = versions.latestVersion;
      _data['minimum_supported_version'] = versions.minimumSupportedVersion;
      _data['update_notes'] = versions.updateNotes;
      _data['update_download_url'] = '';
      _syncUpdateVersionPreset();
      _showSettingsSnack('更新配置已保存');
    } on ApiException catch (e) {
      _showSettingsSnack(userVisibleApiError(e));
    } finally {
      if (mounted) setState(() => _savingKeys.removeAll(keys));
    }
  }

  Future<void> _saveForceUpdateRequired(bool value) async {
    final latestVersion = _latestVersionForSave();
    final minimumSupportedVersion = _minimumSupportedVersionForSave();
    final versions = _normalizedUpdateVersionsForSave(
      forceUpdateRequired: value,
      latestVersion: latestVersion,
      minimumSupportedVersion: minimumSupportedVersion,
    );
    final message = _validateUpdatePolicy(
      forceUpdateRequired: value,
      latestVersion: latestVersion,
      minimumSupportedVersion: minimumSupportedVersion,
    );
    if (message != null) {
      _showSettingsSnack(message);
      return;
    }

    const keys = {
      'force_update_required',
      'latest_version',
      'minimum_supported_version',
      'update_notes',
      'update_download_url',
    };
    setState(() => _savingKeys.addAll(keys));
    try {
      await widget.api.updateSettings(
        forceUpdateRequired: value,
        latestVersion: versions.latestVersion,
        minimumSupportedVersion: versions.minimumSupportedVersion,
        updateNotes: versions.updateNotes,
        updateDownloadUrl: '',
      );
      _data['force_update_required'] = value;
      _data['latest_version'] = versions.latestVersion;
      _data['minimum_supported_version'] = versions.minimumSupportedVersion;
      _data['update_notes'] = versions.updateNotes;
      _data['update_download_url'] = '';
      _syncUpdateVersionPreset();
    } on ApiException catch (e) {
      _showSettingsSnack(userVisibleApiError(e));
    } finally {
      if (mounted) setState(() => _savingKeys.removeAll(keys));
    }
  }

  String? _validateUpdatePolicy({
    required bool forceUpdateRequired,
    required String latestVersion,
    required String minimumSupportedVersion,
  }) {
    final hasAnyUpdatePolicy =
        forceUpdateRequired ||
        _compareAppVersions(latestVersion, _serverCurrentVersion) > 0 ||
        _compareAppVersions(minimumSupportedVersion, _serverCurrentVersion) > 0;
    if (!hasAnyUpdatePolicy) return null;
    // 当前版本也允许保存强制更新开关。真正是否遮挡客户端由后端发布通道
    // 结合可安装包、版本号和下载地址判定，避免管理员必须手填 URL 或内容。
    return null;
  }

  String _defaultUpdateNotesFor({required String latestVersion}) {
    final target = latestVersion.trim().isEmpty
        ? _serverCurrentVersion
        : latestVersion;
    return [
      '本次更新摘要：',
      '- 版本 $target 包含近期问题修复与稳定性优化。',
      '- 安装包与完整发布说明由后端发布通道自动读取。',
      '- 若管理员开启强制更新，客户端会遮挡当前页面直到完成更新。',
    ].join('\n');
  }

  String _updateNotesPreview() {
    final existing = (_data['update_notes'] ?? '').toString().trim();
    if (_updateVersionPreset == _adminUpdatePresetCurrent &&
        existing.isNotEmpty) {
      return existing;
    }
    return _defaultUpdateNotesFor(latestVersion: _latestVersionForSave());
  }

  Widget _groupRoleManagementSection(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final canManageGroups = _canManageGroups;
    final canManageRoles = _canManageRoles;
    final groupCards = _groups.take(6).map((group) {
      return _AdminGroupSummaryCard(
        group: group,
        canManage: canManageGroups,
        onEdit: () => _editGroup(group),
      );
    }).toList();
    final roleCards = _roles.take(6).map((role) {
      final active = role['is_active'] != false;
      final name = (role['name'] ?? role['id'] ?? '').toString();
      final userCount = _adminIntValue(role['user_count']);
      final permissions = _adminUserPermissions(
        role['permission_codes'] ?? role['permissions'],
        isAdmin: true,
      );
      return _AdminListTileCard(
        dense: true,
        leading: Icon(
          Icons.admin_panel_settings_outlined,
          color: active ? Colors.indigo : cs.onSurfaceVariant,
        ),
        title: Text(name.isEmpty ? '未命名角色' : name),
        subtitle: Text(
          '${_adminPermissionsLabel(permissions, isAdmin: true)} · $userCount 人 · ${active ? '启用' : '停用'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: canManageRoles
            ? IconButton(
                tooltip: '编辑角色',
                onPressed: () => _editRole(role),
                icon: const Icon(Icons.edit_outlined),
              )
            : null,
      );
    }).toList();

    return _AdminSettingsSection(
      title: '用户组与角色',
      subtitle: '管理成员分组和管理员权限模板',
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final summary = Text(
              '用户组 ${_groups.length} 个 · 角色 ${_roles.length} 个',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.62),
              ),
            );
            final actions = <Widget>[
              if (canManageGroups)
                TextButton.icon(
                  onPressed: () => _editGroup(),
                  icon: const Icon(Icons.add),
                  label: const Text('用户组'),
                ),
              if (canManageRoles)
                TextButton.icon(
                  onPressed: () => _editRole(),
                  icon: const Icon(Icons.add),
                  label: const Text('角色'),
                ),
            ];
            final actionWrap = Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            );
            if (constraints.maxWidth < 420) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  summary,
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    actionWrap,
                  ],
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: summary),
                if (actions.isNotEmpty) actionWrap,
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        if (_groupsRolesError != null) ...[
          AppInfoBanner(
            icon: Icons.lock_outline,
            title: '用户组或角色加载失败',
            message: _groupsRolesError!,
            color: cs.error,
            margin: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
        ],
        if (_groups.isEmpty)
          AppInfoBanner(
            icon: Icons.groups_2_outlined,
            title: '暂无可管理用户组',
            message: _groupsRolesError == null
                ? '后端返回为空。'
                : '上方错误说明了用户组未能加载的原因。',
            color: Colors.blueGrey,
            margin: EdgeInsets.zero,
          )
        else
          ...groupCards,
        const SizedBox(height: 8),
        if (_roles.isEmpty)
          AppInfoBanner(
            icon: Icons.admin_panel_settings_outlined,
            title: '暂无可管理角色',
            message: _groupsRolesError == null
                ? '后端返回为空。'
                : '上方错误说明了角色未能加载的原因。',
            color: Colors.blueGrey,
            margin: EdgeInsets.zero,
          )
        else
          ...roleCards,
      ],
    );
  }

  int _compareAppVersions(String a, String b) {
    final pa = _versionParts(a);
    final pb = _versionParts(b);
    for (var i = 0; i < 3; i++) {
      final ai = i < pa.length ? pa[i] : 0;
      final bi = i < pb.length ? pb[i] : 0;
      if (ai != bi) return ai.compareTo(bi);
    }
    return 0;
  }

  List<int> _versionParts(String value) {
    return value
        .trim()
        .replaceFirst(RegExp(r'^v'), '')
        .split('-')
        .first
        .split('+')
        .first
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    final cs = Theme.of(context).colorScheme;

    return AppSecondaryControlTheme(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AdminSettingsSection(
            title: '账户、注册与用户组',
            subtitle: '控制新用户入口、邀请码和邮箱验证',
            children: [
              AppSwitchTile(
                icon: Icons.person_add_alt_1_outlined,
                color: Colors.green,
                value: _data['registration_enabled'] == true,
                title: '允许注册',
                subtitle: '关闭后新用户无法注册，现有用户仍可登录',
                onChanged: _saving('registration_enabled')
                    ? null
                    : (v) => _set('registration_enabled', v),
              ),
              AppSwitchTile(
                icon: Icons.vpn_key_outlined,
                color: Colors.purple,
                value: _data['invite_code_required'] == true,
                title: '注册需要邀请码',
                subtitle: '只有带邀请码才能注册',
                onChanged: _saving('invite_code_required')
                    ? null
                    : (v) => _set('invite_code_required', v),
              ),
              AppSwitchTile(
                icon: Icons.mark_email_read_outlined,
                color: Colors.teal,
                value: _data['registration_email_required'] == true,
                title: '注册需要邮箱验证',
                subtitle: '新账号必须填写邮箱并通过验证码后才能创建',
                onChanged: _saving('registration_email_required')
                    ? null
                    : (v) => _set('registration_email_required', v),
              ),
              AppSwitchTile(
                icon: Icons.mark_email_unread_outlined,
                color: Colors.teal,
                value: _data['email_code_login_enabled'] == true,
                title: I18n.tr('admin.email_code_login.title'),
                subtitle: I18n.tr('admin.email_code_login.subtitle'),
                onChanged: _saving('email_code_login_enabled')
                    ? null
                    : (value) => _set('email_code_login_enabled', value),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _groupRoleManagementSection(context),
          const SizedBox(height: 12),
          _AdminSettingsSection(
            title: '维护模式',
            subtitle: '控制同步服务与客户端提示',
            children: [
              AppSwitchTile(
                icon: Icons.construction_outlined,
                color: Colors.orange,
                value: _data['maintenance_mode'] == true,
                title: '启用维护模式',
                subtitle: '开启后 /api/sync 拒绝服务；客户端登录页会提示',
                onChanged: _saving('maintenance_mode')
                    ? null
                    : (v) => _set('maintenance_mode', v),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _msgCtrl,
                decoration: const InputDecoration(
                  labelText: '维护公告文字',
                  hintText: '将在客户端登录/同步报错时展示',
                  prefixIcon: Icon(Icons.campaign_outlined),
                ),
                onEditingComplete: () =>
                    _set('maintenance_message', _msgCtrl.text.trim()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _AdminSettingsSection(
            title: '应用更新',
            subtitle: '通过 /api/config 下发版本、更新内容与强制更新策略',
            children: [
              AppSwitchTile(
                icon: Icons.system_update_alt_outlined,
                color: cs.error,
                value: _data['force_update_required'] == true,
                title: '强制更新',
                subtitle: '开启后由发布通道判定可安装新版本，并在客户端全屏阻断',
                onChanged: _saving('force_update_required')
                    ? null
                    : (v) => _set('force_update_required', v),
              ),
              const SizedBox(height: 10),
              AppInfoBanner(
                icon: Icons.info_outline,
                title: '当前客户端版本 ${AppVersion.name}',
                message:
                    '普通更新会在“检查更新”和底部“我的”入口显示红点；强制更新会锁定客户端，直到用户安装新版本。安装包与发布说明由后端发布通道自动读取。',
                color: Theme.of(context).colorScheme.primary,
                margin: EdgeInsets.zero,
              ),
              const SizedBox(height: 10),
              AppDropdownField<String>(
                key: ValueKey(_updateVersionPreset),
                initialValue: _updateVersionPreset,
                labelText: '版本策略',
                prefixIcon: const Icon(Icons.rule_folder_outlined),
                items: [
                  for (final option in _updateVersionOptions)
                    DropdownMenuItem(
                      value: option.key,
                      child: Text(_updateVersionOptionLabel(option)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) _applyUpdateVersionPreset(value);
                },
              ),
              const SizedBox(height: 10),
              AppInfoBanner(
                icon: Icons.new_releases_outlined,
                title: '版本选择',
                message:
                    '最新版本：${_latestVersionForSave()}；最低支持版本：${_minimumSupportedVersionForSave()}。管理员只需选择上方策略，无需手动输入版本、安装包地址或更新内容。',
                color: Colors.teal,
                margin: EdgeInsets.zero,
              ),
              const SizedBox(height: 10),
              AppInfoBanner(
                icon: Icons.notes_outlined,
                title: '更新内容预览',
                message: _updateNotesPreview(),
                color: Colors.blueGrey,
                margin: EdgeInsets.zero,
              ),
              const SizedBox(height: 6),
              Text(
                '保存时会自动写入以上摘要；安装包地址和完整发布说明由后端发布通道自动读取。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.62),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _savingUpdateConfig ? null : _saveUpdateConfig,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存更新配置'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppInfoBanner(
            icon: Icons.info_outline,
            color: cs.primary,
            title: '服务器地址',
            message: '服务器地址在 APK / Web 构建时就已锁定，运行期不可修改。如需切换后端，请重新构建并分发新版本。',
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// AI 配置
// ====================================================================

class _AiSettingsTab extends StatefulWidget {
  final AdminApi api;
  const _AiSettingsTab({super.key, required this.api});
  @override
  State<_AiSettingsTab> createState() => _AiSettingsTabState();
}

class _AiSettingsTabState extends State<_AiSettingsTab> {
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;
  Color _testColor = Colors.grey;
  String? _error;
  bool _enabled = false;
  final _baseCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _quotaCtrl = TextEditingController(text: '0');
  bool _keyMasked = true;

  @override
  void initState() {
    super.initState();
    for (final ctrl in _aiFieldControllers) {
      ctrl.addListener(_invalidateTestResult);
    }
    _load();
  }

  @override
  void dispose() {
    for (final ctrl in _aiFieldControllers) {
      ctrl.removeListener(_invalidateTestResult);
    }
    _baseCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    _quotaCtrl.dispose();
    super.dispose();
  }

  List<TextEditingController> get _aiFieldControllers => [
    _baseCtrl,
    _keyCtrl,
    _modelCtrl,
    _quotaCtrl,
  ];

  /// 测试结论只对点击那一刻的表单值成立；任一字段变化后旧绿勾必须失效。
  void _invalidateTestResult() {
    if (_testResult == null && _testColor == Colors.grey) return;
    if (!mounted) return;
    setState(() {
      _testResult = null;
      _testColor = Colors.grey;
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.getSettings(scope: 'ai');
      if (!mounted) return;
      _enabled = data['ai_enabled'] == true;
      _baseCtrl.text = (data['ai_base_url'] ?? '').toString();
      _keyCtrl.text = (data['ai_api_key'] ?? '').toString();
      _keyMasked = (data['ai_api_key_set'] == true);
      _modelCtrl.text = (data['ai_model'] ?? '').toString();
      _quotaCtrl.text = (((data['ai_daily_quota'] as num?) ?? 0).toInt())
          .toString();
      context.read<AiService>().updateFromServerConfig(data);
    } catch (e) {
      if (!mounted) return;
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final newKey = _keyCtrl.text.trim();
      final submitKey = (_keyMasked && newKey.contains('***')) ? null : newKey;
      final payload = <String, Object?>{
        'ai_enabled': _enabled,
        'ai_base_url': _baseCtrl.text.trim(),
        'ai_model': _modelCtrl.text.trim(),
        'ai_daily_quota': int.tryParse(_quotaCtrl.text.trim()) ?? 0,
      };
      if (submitKey != null) {
        payload['ai_api_key'] = submitKey;
      }
      await widget.api.client.patch('/api/admin/settings', payload);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('AI 配置已保存')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_adminActionErrorMessage(e, '保存 AI 配置'))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final newKey = _keyCtrl.text.trim();
      final submitKey = (_keyMasked && newKey.contains('***')) ? null : newKey;
      final res = await widget.api.testAi(
        aiEnabled: _enabled,
        baseUrl: _baseCtrl.text.trim(),
        apiKey: submitKey,
        model: _modelCtrl.text.trim(),
      );
      if (!mounted) return;
      final model = (res['model'] ?? _modelCtrl.text.trim()).toString().trim();
      final sample = (res['sample'] ?? '').toString().trim();
      final enabled = res['enabled'] != false;
      final skipped = res['skipped'] == true;
      final ok = res['ok'] != false;
      final message = (res['message'] ?? '').toString().trim();
      final finishReason = (res['finish_reason'] ?? '').toString().trim();
      final reasoningTokens = (res['reasoning_tokens'] as num?)?.toInt() ?? 0;
      setState(() {
        final modelLabel = model.isEmpty ? '未命名模型' : model;
        if (skipped) {
          _testResult = message.isEmpty
              ? 'AI 功能开关未启用，未测试上游连接。模型：$modelLabel'
              : message;
          _testColor = Colors.orange;
        } else if (!enabled) {
          _testResult = '当前表单配置完整，AI 功能开关未启用，未发起上游请求。模型：$modelLabel';
          _testColor = Colors.orange;
        } else if (!ok) {
          _testResult = message.isNotEmpty
              ? message
              : '模型未返回正文（finish_reason=${finishReason.isEmpty ? '未知' : finishReason}，'
                    '思考 $reasoningTokens tokens）';
          _testColor = Theme.of(context).colorScheme.error;
        } else {
          _testResult =
              '当前表单配置可达，模型 $modelLabel 回复: ${sample.isEmpty ? '空回复' : sample}';
          _testColor = Colors.green;
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _testResult = _adminAiFailureReason(userVisibleApiError(e));
        _testColor = Theme.of(context).colorScheme.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testResult = _adminAiFailureReason(e.toString());
        _testColor = Theme.of(context).colorScheme.error;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AdminSettingsSection(
          title: 'AI 功能',
          subtitle: '所有请求经后端代理，前端不暴露密钥',
          children: [
            AppSwitchTile(
              icon: Icons.auto_awesome,
              color: cs.primary,
              value: _enabled,
              title: '启用 AI 功能',
              subtitle: '关闭后所有用户都无法使用 AI 拆解/回顾',
              onChanged: (v) {
                _invalidateTestResult();
                setState(() => _enabled = v);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _baseCtrl,
              decoration: const InputDecoration(
                labelText: 'Base URL (OpenAI 兼容网关)',
                hintText: 'https://api.openai.com',
                helperText: '路径后自动加 /v1/chat/completions',
                prefixIcon: Icon(Icons.link_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _keyCtrl,
              decoration: InputDecoration(
                labelText: 'API Key',
                helperText: _keyMasked ? '已配置（显示为掩码，保持不动即不修改）' : '尚未配置',
                prefixIcon: const Icon(Icons.key_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _modelCtrl,
              decoration: const InputDecoration(
                labelText: '模型名称',
                hintText: 'gpt-4o-mini / claude-3-haiku-20240307',
                prefixIcon: Icon(Icons.memory_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _quotaCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '每用户每日调用上限',
                helperText: '0 = 不限',
                prefixIcon: Icon(Icons.speed_outlined),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? '保存中…' : '保存'),
                ),
                OutlinedButton.icon(
                  icon: _testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check),
                  label: const Text('测试当前表单'),
                  onPressed: _testing ? null : _test,
                ),
              ],
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _testColor.withValues(alpha: 0.18),
                    width: 0.45,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _testColor == Colors.green
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      color: _testColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _testResult!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.74),
                          fontWeight: DesignTokens.fontWeightStrong,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        AppInfoBanner(
          icon: Icons.security_outlined,
          color: Colors.teal,
          title: '安全代理',
          message: '所有用户的 AI 请求都通过后端 /api/ai/chat 代理，前端永远拿不到 API Key。',
        ),
      ],
    );
  }
}

String _adminAiFailureReason(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '测试失败：AI 服务没有返回错误详情';
  if (text.contains('AI 功能未启用')) return '测试失败：AI 功能未启用，请先保存并开启 AI 功能';
  if (text.contains('API Key')) return '测试失败：管理员尚未配置 AI API Key';
  if (text.contains('401') || text.contains('403')) {
    return '测试失败：AI 密钥无效或没有模型权限';
  }
  if (text.contains('429') || text.contains('额度')) return '测试失败：今日 AI 额度已用尽';
  if (text.contains('404') || text.toLowerCase().contains('not found')) {
    return '测试失败：AI 代理或上游模型不可用，请检查 Base URL、模型名称和后端 /api/admin/ai/test 路由';
  }
  if (text.contains('超时')) return '测试失败：AI 服务响应超时，请稍后重试';
  if (text.contains('上游不可达') || text.contains('不可达')) {
    return '测试失败：AI 上游服务不可达：$text';
  }
  if (text.contains('502')) return '测试失败：AI 代理处理失败：$text';
  return '测试失败：$text';
}

// ====================================================================
// 云端备份
// ====================================================================

class _BackupSettingsTab extends StatefulWidget {
  final AdminApi api;
  const _BackupSettingsTab({super.key, required this.api});
  @override
  State<_BackupSettingsTab> createState() => _BackupSettingsTabState();
}

class _BackupSettingsTabState extends State<_BackupSettingsTab> {
  bool _loading = true;
  bool _saving = false;
  bool _runningServerBackup = false;
  bool _testingReminderEmail = false;
  bool _testingAccountEmail = false;
  bool _exportingBackups = false;
  bool _exportingServerBackups = false;
  String? _error;

  bool _backupEnabled = true;
  bool _serverBackupEnabled = true;
  bool _openlistEnabled = false;
  bool _backupEmailEnabled = false;
  bool _reminderEmailEnabled = false;
  bool _accountEmailEnabled = true;
  bool _emailAutoSwitchEnabled = false;
  bool _accountSmtpUseSsl = true;
  String _emailPrimaryProvider = 'claw163';
  String _emailBackupProvider = 'resend';
  String _emailActiveSlot = 'primary';
  final _maxSizeCtrl = TextEditingController(text: '2048');
  final _intervalCtrl = TextEditingController(text: '30');
  final _retainCtrl = TextEditingController(text: '0');
  final _serverIntervalCtrl = TextEditingController(text: '720');
  final _serverRetainCtrl = TextEditingController(text: '14');
  final _openlistUrlCtrl = TextEditingController();
  final _openlistPublicUrlCtrl = TextEditingController();
  final _openlistUserCtrl = TextEditingController();
  final _openlistPasswordCtrl = TextEditingController();
  final _openlistPathCtrl = TextEditingController(text: '/duoyi-backups');
  final _emailToCtrl = TextEditingController();
  final _emailFromCtrl = TextEditingController();
  final _smtpHostCtrl = TextEditingController();
  final _smtpPortCtrl = TextEditingController(text: '465');
  final _smtpUserCtrl = TextEditingController();
  final _smtpPasswordCtrl = TextEditingController();
  final _reminderEmailToCtrl = TextEditingController();
  final _reminderEmailFromCtrl = TextEditingController();
  final _reminderSmtpHostCtrl = TextEditingController();
  final _reminderSmtpPortCtrl = TextEditingController(text: '465');
  final _reminderSmtpUserCtrl = TextEditingController();
  final _reminderSmtpPasswordCtrl = TextEditingController();
  final _emailTitleCtrl = TextEditingController(text: '多仪');
  final _emailSenderNameCtrl = TextEditingController(text: '多仪');
  final _openclawMailUserCtrl = TextEditingController();
  final _openclawMailKeyCtrl = TextEditingController();
  final _resendBaseUrlCtrl = TextEditingController();
  final _resendApiKeyCtrl = TextEditingController();
  final _resendFromCtrl = TextEditingController();
  final _systemNoticeEmailCtrl = TextEditingController();
  final _accountSmtpHostCtrl = TextEditingController();
  final _accountSmtpPortCtrl = TextEditingController(text: '465');
  final _accountSmtpUserCtrl = TextEditingController();
  final _accountSmtpFromCtrl = TextEditingController();
  final _accountSmtpPasswordCtrl = TextEditingController();
  bool _openlistPasswordMasked = false;
  bool _smtpPasswordMasked = false;
  bool _reminderSmtpPasswordMasked = false;
  bool _openclawMailKeyMasked = false;
  bool _resendApiKeyMasked = false;
  bool _accountSmtpPasswordMasked = false;

  List<Map<String, dynamic>> _backups = [];
  List<Map<String, dynamic>> _serverBackups = [];
  AdminPage? _backupPage;
  AdminPage? _serverBackupPage;
  int _backupOffset = 0;
  int _serverBackupOffset = 0;
  int _backupPageSize = _adminPageSize;
  int _serverBackupPageSize = _adminPageSize;
  String _backupQuery = '';
  String _serverBackupQuery = '';
  String _backupStatus = '';
  String _serverBackupStatus = '';
  String _backupSort = 'updated_desc';
  String _serverBackupSort = 'created_desc';
  final _backupSearchCtrl = TextEditingController();
  final _serverBackupSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _maxSizeCtrl.dispose();
    _intervalCtrl.dispose();
    _retainCtrl.dispose();
    _serverIntervalCtrl.dispose();
    _serverRetainCtrl.dispose();
    _openlistUrlCtrl.dispose();
    _openlistPublicUrlCtrl.dispose();
    _openlistUserCtrl.dispose();
    _openlistPasswordCtrl.dispose();
    _openlistPathCtrl.dispose();
    _emailToCtrl.dispose();
    _emailFromCtrl.dispose();
    _smtpHostCtrl.dispose();
    _smtpPortCtrl.dispose();
    _smtpUserCtrl.dispose();
    _smtpPasswordCtrl.dispose();
    _reminderEmailToCtrl.dispose();
    _reminderEmailFromCtrl.dispose();
    _reminderSmtpHostCtrl.dispose();
    _reminderSmtpPortCtrl.dispose();
    _reminderSmtpUserCtrl.dispose();
    _reminderSmtpPasswordCtrl.dispose();
    _emailTitleCtrl.dispose();
    _emailSenderNameCtrl.dispose();
    _openclawMailUserCtrl.dispose();
    _openclawMailKeyCtrl.dispose();
    _resendBaseUrlCtrl.dispose();
    _resendApiKeyCtrl.dispose();
    _resendFromCtrl.dispose();
    _systemNoticeEmailCtrl.dispose();
    _accountSmtpHostCtrl.dispose();
    _accountSmtpPortCtrl.dispose();
    _accountSmtpUserCtrl.dispose();
    _accountSmtpFromCtrl.dispose();
    _accountSmtpPasswordCtrl.dispose();
    _backupSearchCtrl.dispose();
    _serverBackupSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({
    int? backupOffset,
    int? serverBackupOffset,
    int? backupPageSize,
    int? serverBackupPageSize,
    String? backupQuery,
    String? serverBackupQuery,
    String? backupStatus,
    String? serverBackupStatus,
    String? backupSort,
    String? serverBackupSort,
  }) async {
    final nextBackupOffset = backupOffset ?? _backupOffset;
    final nextServerBackupOffset = serverBackupOffset ?? _serverBackupOffset;
    final nextBackupPageSize = backupPageSize ?? _backupPageSize;
    final nextServerBackupPageSize =
        serverBackupPageSize ?? _serverBackupPageSize;
    final nextBackupQuery = backupQuery ?? _backupQuery;
    final nextServerBackupQuery = serverBackupQuery ?? _serverBackupQuery;
    final nextBackupStatus = backupStatus ?? _backupStatus;
    final nextServerBackupStatus = serverBackupStatus ?? _serverBackupStatus;
    final nextBackupSort = backupSort ?? _backupSort;
    final nextServerBackupSort = serverBackupSort ?? _serverBackupSort;
    _backupOffset = nextBackupOffset;
    _serverBackupOffset = nextServerBackupOffset;
    _backupPageSize = nextBackupPageSize;
    _serverBackupPageSize = nextServerBackupPageSize;
    _backupQuery = nextBackupQuery;
    _serverBackupQuery = nextServerBackupQuery;
    _backupStatus = nextBackupStatus;
    _serverBackupStatus = nextServerBackupStatus;
    _backupSort = nextBackupSort;
    _serverBackupSort = nextServerBackupSort;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.getSettings(scope: 'backup');
      if (!mounted) return;
      _backupEnabled = data['backup_enabled'] != false;
      _maxSizeCtrl.text =
          (((data['backup_max_size_kb'] as num?) ?? 2048).toInt()).toString();
      _intervalCtrl.text =
          (((data['backup_interval_minutes'] as num?) ?? 30).toInt())
              .toString();
      _retainCtrl.text = (((data['backup_retain_days'] as num?) ?? 0).toInt())
          .toString();
      _serverBackupEnabled = data['server_backup_enabled'] != false;
      _serverIntervalCtrl.text =
          (((data['server_backup_interval_minutes'] as num?) ?? 720).toInt())
              .toString();
      _serverRetainCtrl.text =
          (((data['server_backup_retain_days'] as num?) ?? 14).toInt())
              .toString();
      _openlistEnabled = data['openlist_backup_enabled'] == true;
      _openlistUrlCtrl.text = (data['openlist_webdav_url'] ?? '').toString();
      _openlistPublicUrlCtrl.text = (data['openlist_public_url'] ?? '')
          .toString();
      _openlistUserCtrl.text = (data['openlist_username'] ?? '').toString();
      _openlistPasswordCtrl.text = (data['openlist_password'] ?? '').toString();
      _openlistPasswordMasked = data['openlist_password_set'] == true;
      _openlistPathCtrl.text =
          (data['openlist_backup_path'] ?? '/duoyi-backups').toString();
      _backupEmailEnabled = data['backup_email_enabled'] == true;
      _emailToCtrl.text = (data['backup_email_to'] ?? '').toString();
      _emailFromCtrl.text = (data['backup_email_from'] ?? '').toString();
      _smtpHostCtrl.text = (data['backup_email_smtp_host'] ?? '').toString();
      _smtpPortCtrl.text =
          (((data['backup_email_smtp_port'] as num?) ?? 465).toInt())
              .toString();
      _smtpUserCtrl.text = (data['backup_email_smtp_username'] ?? '')
          .toString();
      _smtpPasswordCtrl.text = (data['backup_email_smtp_password'] ?? '')
          .toString();
      _smtpPasswordMasked = data['backup_email_smtp_password_set'] == true;
      _reminderEmailEnabled = data['reminder_email_enabled'] == true;
      _reminderEmailToCtrl.text = (data['reminder_email_to'] ?? '').toString();
      _reminderEmailFromCtrl.text = (data['reminder_email_from'] ?? '')
          .toString();
      _reminderSmtpHostCtrl.text = (data['reminder_email_smtp_host'] ?? '')
          .toString();
      _reminderSmtpPortCtrl.text =
          (((data['reminder_email_smtp_port'] as num?) ?? 465).toInt())
              .toString();
      _reminderSmtpUserCtrl.text = (data['reminder_email_smtp_username'] ?? '')
          .toString();
      _reminderSmtpPasswordCtrl.text =
          (data['reminder_email_smtp_password'] ?? '').toString();
      _reminderSmtpPasswordMasked =
          data['reminder_email_smtp_password_set'] == true;
      _accountEmailEnabled = data['email_service_enabled'] != false;
      _emailAutoSwitchEnabled = data['email_auto_switch_enabled'] == true;
      _emailPrimaryProvider = _mailProviderValue(
        data['email_code_primary_provider'],
        fallback: 'claw163',
      );
      _emailBackupProvider = _mailProviderValue(
        data['email_code_backup_provider'],
        fallback: 'resend',
      );
      _emailActiveSlot = data['email_code_active_slot'] == 'backup'
          ? 'backup'
          : 'primary';
      _emailTitleCtrl.text = (data['email_title'] ?? '多仪').toString();
      _emailSenderNameCtrl.text = (data['email_sender_name'] ?? '多仪')
          .toString();
      _openclawMailUserCtrl.text = (data['openclaw_mail_user'] ?? '')
          .toString();
      _openclawMailKeyCtrl.text = (data['openclaw_mail_api_key'] ?? '')
          .toString();
      _openclawMailKeyMasked = data['openclaw_mail_api_key_set'] == true;
      _resendBaseUrlCtrl.text =
          (data['resend_base_url'] ?? 'https://api.resend.com').toString();
      _resendApiKeyCtrl.text = (data['resend_api_key'] ?? '').toString();
      _resendApiKeyMasked = data['resend_api_key_set'] == true;
      _resendFromCtrl.text = (data['resend_from'] ?? '').toString();
      _systemNoticeEmailCtrl.text = (data['system_notice_email_to'] ?? '')
          .toString();
      _accountSmtpHostCtrl.text = (data['email_smtp_host'] ?? '').toString();
      _accountSmtpPortCtrl.text =
          (((data['email_smtp_port'] as num?) ?? 465).toInt()).toString();
      _accountSmtpUserCtrl.text = (data['email_smtp_username'] ?? '')
          .toString();
      _accountSmtpFromCtrl.text = (data['email_smtp_from'] ?? '').toString();
      _accountSmtpPasswordCtrl.text = (data['email_smtp_password'] ?? '')
          .toString();
      _accountSmtpPasswordMasked = data['email_smtp_password_set'] == true;
      _accountSmtpUseSsl = data['email_smtp_use_ssl'] != false;
      final backupPage = await widget.api.listBackupsPage(
        query: nextBackupQuery.isEmpty ? null : nextBackupQuery,
        status: nextBackupStatus.isEmpty ? null : nextBackupStatus,
        sort: nextBackupSort,
        limit: nextBackupPageSize,
        offset: nextBackupOffset,
      );
      if (!mounted) return;
      final serverBackupPage = await widget.api.listServerBackupsPage(
        query: nextServerBackupQuery.isEmpty ? null : nextServerBackupQuery,
        status: nextServerBackupStatus.isEmpty ? null : nextServerBackupStatus,
        sort: nextServerBackupSort,
        limit: nextServerBackupPageSize,
        offset: nextServerBackupOffset,
      );
      if (!mounted) return;
      _backupPage = backupPage;
      _serverBackupPage = serverBackupPage;
      _backups = backupPage.items;
      _serverBackups = serverBackupPage.items;
    } catch (e) {
      if (!mounted) return;
      _error = _adminErrorMessage(e, '备份配置与备份记录');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final openlistPassword = _openlistPasswordCtrl.text.trim();
      final smtpPassword = _smtpPasswordCtrl.text.trim();
      final reminderSmtpPassword = _reminderSmtpPasswordCtrl.text.trim();
      final openclawMailKey = _openclawMailKeyCtrl.text.trim();
      final resendApiKey = _resendApiKeyCtrl.text.trim();
      final accountSmtpPassword = _accountSmtpPasswordCtrl.text.trim();
      final payload = <String, Object?>{
        'backup_enabled': _backupEnabled,
        'backup_max_size_kb': int.tryParse(_maxSizeCtrl.text.trim()) ?? 2048,
        'backup_interval_minutes':
            int.tryParse(_intervalCtrl.text.trim()) ?? 30,
        'backup_retain_days': int.tryParse(_retainCtrl.text.trim()) ?? 0,
        'server_backup_enabled': _serverBackupEnabled,
        'server_backup_interval_minutes':
            int.tryParse(_serverIntervalCtrl.text.trim()) ?? 720,
        'server_backup_retain_days':
            int.tryParse(_serverRetainCtrl.text.trim()) ?? 14,
        'openlist_backup_enabled': _openlistEnabled,
        'openlist_webdav_url': _openlistUrlCtrl.text.trim(),
        'openlist_public_url': _openlistPublicUrlCtrl.text.trim(),
        'openlist_username': _openlistUserCtrl.text.trim(),
        'openlist_backup_path': _openlistPathCtrl.text.trim(),
        'backup_email_enabled': _backupEmailEnabled,
        'backup_email_to': _emailToCtrl.text.trim(),
        'backup_email_from': _emailFromCtrl.text.trim(),
        'backup_email_smtp_host': _smtpHostCtrl.text.trim(),
        'backup_email_smtp_port':
            int.tryParse(_smtpPortCtrl.text.trim()) ?? 465,
        'backup_email_smtp_username': _smtpUserCtrl.text.trim(),
        'reminder_email_enabled': _reminderEmailEnabled,
        'reminder_email_to': _reminderEmailToCtrl.text.trim(),
        'reminder_email_from': _reminderEmailFromCtrl.text.trim(),
        'reminder_email_smtp_host': _reminderSmtpHostCtrl.text.trim(),
        'reminder_email_smtp_port':
            int.tryParse(_reminderSmtpPortCtrl.text.trim()) ?? 465,
        'reminder_email_smtp_username': _reminderSmtpUserCtrl.text.trim(),
        'email_service_enabled': _accountEmailEnabled,
        'email_title': _emailTitleCtrl.text.trim(),
        'email_sender_name': _emailSenderNameCtrl.text.trim(),
        'email_code_primary_provider': _emailPrimaryProvider,
        'email_code_backup_provider': _emailBackupProvider,
        'email_code_active_slot': _emailActiveSlot,
        'email_auto_switch_enabled': _emailAutoSwitchEnabled,
        'openclaw_mail_enabled':
            _emailPrimaryProvider == 'claw163' ||
            _emailBackupProvider == 'claw163',
        'openclaw_mail_user': _openclawMailUserCtrl.text.trim(),
        'resend_base_url': _resendBaseUrlCtrl.text.trim(),
        'resend_from': _resendFromCtrl.text.trim(),
        'system_notice_email_to': _systemNoticeEmailCtrl.text.trim(),
        'email_smtp_host': _accountSmtpHostCtrl.text.trim(),
        'email_smtp_port':
            int.tryParse(_accountSmtpPortCtrl.text.trim()) ?? 465,
        'email_smtp_username': _accountSmtpUserCtrl.text.trim(),
        'email_smtp_from': _accountSmtpFromCtrl.text.trim(),
        'email_smtp_use_ssl': _accountSmtpUseSsl,
      };
      if (!(_openlistPasswordMasked && openlistPassword.contains('***'))) {
        payload['openlist_password'] = openlistPassword;
      }
      if (!(_smtpPasswordMasked && smtpPassword.contains('***'))) {
        payload['backup_email_smtp_password'] = smtpPassword;
      }
      if (!(_reminderSmtpPasswordMasked &&
          reminderSmtpPassword.contains('***'))) {
        payload['reminder_email_smtp_password'] = reminderSmtpPassword;
      }
      if (!(_openclawMailKeyMasked && openclawMailKey.contains('***'))) {
        payload['openclaw_mail_api_key'] = openclawMailKey;
      }
      if (!(_resendApiKeyMasked && resendApiKey.contains('***'))) {
        payload['resend_api_key'] = resendApiKey;
      }
      if (!(_accountSmtpPasswordMasked &&
          accountSmtpPassword.contains('***'))) {
        payload['email_smtp_password'] = accountSmtpPassword;
      }
      await widget.api.client.patch('/api/admin/settings', payload);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('云端备份配置已保存')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_adminActionErrorMessage(e, '保存备份配置'))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _runServerBackup() async {
    setState(() => _runningServerBackup = true);
    try {
      await widget.api.runServerBackup();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('服务器备份已执行')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_adminActionErrorMessage(e, '执行服务器备份'))),
        );
      }
    } finally {
      if (mounted) setState(() => _runningServerBackup = false);
    }
  }

  Future<void> _testReminderEmail() async {
    setState(() => _testingReminderEmail = true);
    try {
      final res = await widget.api.testReminderEmail();
      if (mounted) {
        final recipient = (res['recipient'] ?? '').toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              recipient.isEmpty ? '测试邮件已发送' : '测试邮件已发送到 $recipient',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_adminActionErrorMessage(e, '发送提醒测试邮件'))),
        );
      }
    } finally {
      if (mounted) setState(() => _testingReminderEmail = false);
    }
  }

  Future<void> _testAccountEmail() async {
    setState(() => _testingAccountEmail = true);
    try {
      final res = await widget.api.testAccountEmail();
      if (mounted) {
        final recipient = (res['recipient'] ?? '').toString();
        final provider = (res['provider'] ?? '').toString();
        final channel = provider.isEmpty ? '' : ' · $provider';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              recipient.isEmpty
                  ? '账号测试邮件已发送$channel'
                  : '账号测试邮件已发送到 $recipient$channel',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_adminActionErrorMessage(e, '发送账号测试邮件'))),
        );
      }
    } finally {
      if (mounted) setState(() => _testingAccountEmail = false);
    }
  }

  String _mailProviderValue(Object? value, {required String fallback}) {
    final raw = (value ?? fallback).toString().trim().toLowerCase();
    final normalized = switch (raw) {
      'openclaw' || 'openclaw_mail' => 'claw163',
      _ => raw,
    };
    return {'claw163', 'resend', 'smtp', 'none'}.contains(normalized)
        ? normalized
        : fallback;
  }

  List<DropdownMenuItem<String>> _mailProviderItems() => const [
    DropdownMenuItem(value: 'claw163', child: Text('Claw163')),
    DropdownMenuItem(value: 'resend', child: Text('Resend')),
    DropdownMenuItem(value: 'smtp', child: Text('SMTP')),
    DropdownMenuItem(value: 'none', child: Text('关闭')),
  ];

  Future<void> _wipe(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text('清空 ${row['username']} 的云端备份?'),
        icon: const Icon(Icons.cloud_off_outlined),
        content: const Text('账号保留，但服务器上的同步数据会清零，用户下次同步后本地数据将被覆盖。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.wipeBackup(row['user_id'].toString());
      final nextOffset = _backups.length == 1 && _backupOffset > 0
          ? (_backupOffset - _backupPageSize).clamp(0, _backupOffset)
          : _backupOffset;
      await _load(backupOffset: nextOffset);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_adminActionErrorMessage(e, '清空云端备份'))),
        );
      }
    }
  }

  Future<void> _exportBackupsCsv() async {
    setState(() => _exportingBackups = true);
    try {
      final csv = await widget.api.exportBackupsCsv(
        query: _backupQuery.isEmpty ? null : _backupQuery,
        status: _backupStatus.isEmpty ? null : _backupStatus,
        sort: _backupSort,
      );
      await _shareAdminCsv(
        csv,
        prefix: 'duoyi_backups',
        text: '多仪用户备份导出',
        subject: '多仪用户备份 CSV',
        successLabel: '用户备份 CSV 已导出',
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userVisibleApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _exportingBackups = false);
    }
  }

  Future<void> _exportServerBackupsCsv() async {
    setState(() => _exportingServerBackups = true);
    try {
      final csv = await widget.api.exportServerBackupsCsv(
        query: _serverBackupQuery.isEmpty ? null : _serverBackupQuery,
        status: _serverBackupStatus.isEmpty ? null : _serverBackupStatus,
        sort: _serverBackupSort,
      );
      await _shareAdminCsv(
        csv,
        prefix: 'duoyi_server_backups',
        text: '多仪服务器备份导出',
        subject: '多仪服务器备份 CSV',
        successLabel: '服务器备份 CSV 已导出',
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userVisibleApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _exportingServerBackups = false);
    }
  }

  Future<void> _shareAdminCsv(
    String csv, {
    required String prefix,
    required String text,
    required String subject,
    required String successLabel,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    await file.writeAsString(csv, flush: true);
    await Clipboard.setData(ClipboardData(text: file.path));
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: text, subject: subject),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$successLabel，路径已复制：${file.path}')));
  }

  Widget _backupStatusChip(String label, String value) {
    final selected = _backupStatus == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _load(backupStatus: value, backupOffset: 0),
      ),
    );
  }

  Widget _serverBackupStatusChip(String label, String value) {
    final selected = _serverBackupStatus == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) =>
            _load(serverBackupStatus: value, serverBackupOffset: 0),
      ),
    );
  }

  Widget _buildBackupRecordTabs(
    BuildContext context, {
    required ThemeData theme,
    required ColorScheme cs,
    required int totalKb,
  }) {
    return DecoratedBox(
      key: const ValueKey('admin_backup_record_tabs'),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cs.outlineVariant.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.10 : 0.12,
          ),
          width: 0.45,
        ),
      ),
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            AppPageTabs(
              height: AppPageTabs.heightFor(context),
              tabs: const [
                Tab(text: '服务器备份记录'),
                Tab(text: '所有用户备份'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildServerBackupRecords(theme: theme, cs: cs),
                  _buildUserBackupRecords(
                    theme: theme,
                    cs: cs,
                    totalKb: totalKb,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerBackupRecords({
    required ThemeData theme,
    required ColorScheme cs,
  }) {
    return Column(
      key: const ValueKey('admin_backup_server_panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: AppSectionHeader(
            title: '服务器备份记录',
            subtitle: _adminPageSummary(_serverBackupPage),
            actionLabel: _exportingServerBackups ? '导出中…' : '导出筛选结果',
            actionIcon: Icons.ios_share_outlined,
            onAction: _exportingServerBackups ? null : _exportServerBackupsCsv,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: TextField(
            controller: _serverBackupSearchCtrl,
            decoration: InputDecoration(
              hintText: '搜索文件名、状态、路径或详情',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _serverBackupQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空服务器备份搜索',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _serverBackupSearchCtrl.clear();
                        _load(serverBackupQuery: '', serverBackupOffset: 0);
                      },
                    ),
              isDense: true,
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(
              serverBackupQuery: _serverBackupSearchCtrl.text.trim(),
              serverBackupOffset: 0,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: _AdminChipWrap(
            padding: EdgeInsets.zero,
            children: [
              _serverBackupStatusChip('全部备份', ''),
              _serverBackupStatusChip('已上传', 'uploaded'),
              _serverBackupStatusChip('仅本地', 'local_only'),
              _serverBackupStatusChip('远端失败', 'local_created_remote_failed'),
              _serverBackupStatusChip('已创建', 'created'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: AppDropdownField<String>(
                  initialValue: _serverBackupSort,
                  labelText: '服务器备份排序',
                  items: const [
                    DropdownMenuItem(
                      value: 'created_desc',
                      child: Text('最新生成优先'),
                    ),
                    DropdownMenuItem(value: 'size_desc', child: Text('文件从大到小')),
                    DropdownMenuItem(value: 'size_asc', child: Text('文件从小到大')),
                    DropdownMenuItem(
                      value: 'status_asc',
                      child: Text('状态 A-Z'),
                    ),
                    DropdownMenuItem(
                      value: 'filename_asc',
                      child: Text('文件名 A-Z'),
                    ),
                  ],
                  onChanged: (value) => _load(
                    serverBackupSort: value ?? 'created_desc',
                    serverBackupOffset: 0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _loading
                    ? null
                    : () => _load(serverBackupOffset: _serverBackupOffset),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('刷新'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _serverBackups.isEmpty
              ? Center(
                  child: Text(
                    '当前筛选下没有服务器备份记录。可搜索文件名、状态、路径或详情，也可以切换状态后再看。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.58),
                    ),
                  ),
                )
              : ListView.builder(
                  key: const ValueKey('admin_backup_server_records'),
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  itemCount: _serverBackups.length,
                  itemBuilder: (context, index) {
                    final b = _serverBackups[index];
                    final status = (b['status'] ?? '-').toString();
                    return _AdminListTileCard(
                      margin: const EdgeInsets.only(bottom: 8),
                      dense: true,
                      leading: Icon(Icons.backup_outlined, color: cs.primary),
                      title: Text((b['filename'] ?? '-').toString()),
                      subtitle: Text(
                        '${b['created_at'] ?? '-'} · ${_adminStatusLabel(status)} · ${b['size_bytes'] ?? 0} bytes · 排序: ${_adminServerBackupSortLabel(_serverBackupSort)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                    );
                  },
                ),
        ),
        _AdminPaginationBar(
          barKey: const ValueKey('admin_backup_server_pagination'),
          page: _serverBackupPage,
          loading: _loading,
          pageSize: _serverBackupPageSize,
          onPageSizeChanged: (value) =>
              _load(serverBackupPageSize: value, serverBackupOffset: 0),
          onPrevious: () => _load(
            serverBackupOffset: (_serverBackupOffset - _serverBackupPageSize)
                .clamp(0, _serverBackupOffset),
          ),
          onNext: () => _load(
            serverBackupOffset: _serverBackupOffset + _serverBackupPageSize,
          ),
          onJumpToPage: (page) =>
              _load(serverBackupOffset: (page - 1) * _serverBackupPageSize),
        ),
      ],
    );
  }

  Widget _buildUserBackupRecords({
    required ThemeData theme,
    required ColorScheme cs,
    required int totalKb,
  }) {
    return Column(
      key: const ValueKey('admin_backup_user_panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: AppSectionHeader(
            title: '所有用户备份',
            subtitle:
                '${_adminPageSummary(_backupPage)} · 本页 ${(totalKb / 1024).toStringAsFixed(1)} MB',
            actionLabel: _exportingBackups ? '导出中…' : '导出筛选结果',
            actionIcon: Icons.ios_share_outlined,
            onAction: _exportingBackups ? null : _exportBackupsCsv,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: TextField(
            controller: _backupSearchCtrl,
            decoration: InputDecoration(
              hintText: '搜索用户名、邮箱、昵称或用户 ID',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _backupQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空用户备份搜索',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _backupSearchCtrl.clear();
                        _load(backupQuery: '', backupOffset: 0);
                      },
                    ),
              isDense: true,
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(
              backupQuery: _backupSearchCtrl.text.trim(),
              backupOffset: 0,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: _AdminChipWrap(
            padding: EdgeInsets.zero,
            children: [
              _backupStatusChip('全部用户', ''),
              _backupStatusChip('已有快照', 'synced'),
              _backupStatusChip('无快照', 'empty'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: AppDropdownField<String>(
                  initialValue: _backupSort,
                  labelText: '用户备份排序',
                  items: const [
                    DropdownMenuItem(
                      value: 'updated_desc',
                      child: Text('最近同步优先'),
                    ),
                    DropdownMenuItem(
                      value: 'username_asc',
                      child: Text('用户名 A-Z'),
                    ),
                    DropdownMenuItem(
                      value: 'size_desc',
                      child: Text('备份体积从大到小'),
                    ),
                    DropdownMenuItem(
                      value: 'size_asc',
                      child: Text('备份体积从小到大'),
                    ),
                    DropdownMenuItem(
                      value: 'version_desc',
                      child: Text('同步版本较高优先'),
                    ),
                  ],
                  onChanged: (value) => _load(
                    backupSort: value ?? 'updated_desc',
                    backupOffset: 0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _loading
                    ? null
                    : () => _load(backupOffset: _backupOffset),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('刷新'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _backups.isEmpty
              ? Center(
                  child: Text(
                    '当前筛选下没有用户备份。可搜索用户名、邮箱、昵称或用户 ID，也可以切换“已有快照/无快照”。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.58),
                    ),
                  ),
                )
              : ListView.builder(
                  key: const ValueKey('admin_backup_user_records'),
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  itemCount: _backups.length,
                  itemBuilder: (context, index) {
                    final b = _backups[index];
                    final email = (b['email'] ?? '').toString();
                    final displayName = (b['display_name'] ?? '').toString();
                    final hasSnapshot = b['has_snapshot'] == true;
                    final updated = hasSnapshot
                        ? (b['updated_at'] ?? '尚无同步时间').toString()
                        : '尚无同步快照';
                    return _AdminListTileCard(
                      margin: const EdgeInsets.only(bottom: 8),
                      dense: true,
                      leading: Icon(
                        Icons.cloud_done_outlined,
                        color: cs.primary,
                      ),
                      title: Text(b['username'].toString()),
                      subtitle: Text(
                        [
                          if (displayName.isNotEmpty) '昵称: $displayName',
                          if (email.isNotEmpty) '邮箱: $email',
                          updated,
                          '版本 ${b['sync_version'] ?? 0}',
                          '${b['size_kb']} KB',
                          '排序: ${_adminBackupSortLabel(_backupSort)}',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: '清空备份',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _wipe(b),
                      ),
                    );
                  },
                ),
        ),
        _AdminPaginationBar(
          barKey: const ValueKey('admin_backup_user_pagination'),
          page: _backupPage,
          loading: _loading,
          pageSize: _backupPageSize,
          onPageSizeChanged: (value) =>
              _load(backupPageSize: value, backupOffset: 0),
          onPrevious: () => _load(
            backupOffset: (_backupOffset - _backupPageSize).clamp(
              0,
              _backupOffset,
            ),
          ),
          onNext: () => _load(backupOffset: _backupOffset + _backupPageSize),
          onJumpToPage: (page) =>
              _load(backupOffset: (page - 1) * _backupPageSize),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _AdminErrorState(message: _error!, onRetry: () => _load());
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final totalKb = _backups.fold<int>(
      0,
      (s, e) => s + ((e['size_kb'] as int?) ?? 0),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AdminSettingsSection(
          title: '云端备份',
          subtitle: '限制同步体积、频率与服务开关',
          children: [
            AppSwitchTile(
              icon: Icons.cloud_sync_outlined,
              color: cs.primary,
              value: _backupEnabled,
              title: '启用云端备份',
              subtitle: '关闭后所有 /api/sync 请求会被拒绝',
              onChanged: (v) => setState(() => _backupEnabled = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _maxSizeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '单用户同步大小上限 (KB)',
                helperText: '0 = 不限，默认 2048',
                prefixIcon: Icon(Icons.storage_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _intervalCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '客户端最小自动同步间隔 (分钟)',
                helperText: '用于客户端回退策略参考',
                prefixIcon: Icon(Icons.update_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _retainCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '备份历史保留天数',
                helperText: '0 = 永久保留 (当前后端仅保留最新快照)',
                prefixIcon: Icon(Icons.history_outlined),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? '保存中…' : '保存'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _AdminSettingsSection(
          title: '服务器备份',
          subtitle: '定期打包后台数据库，上传到 OpenList，并可邮件通知',
          children: [
            AppSwitchTile(
              icon: Icons.dns_outlined,
              color: Colors.indigo,
              value: _serverBackupEnabled,
              title: '启用服务器定期备份',
              subtitle: '后台进程按间隔生成数据库 ZIP 快照',
              onChanged: (v) => setState(() => _serverBackupEnabled = v),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _serverIntervalCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '服务器备份间隔 (分钟)',
                      prefixIcon: Icon(Icons.schedule_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _serverRetainCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '本地保留天数',
                      prefixIcon: Icon(Icons.history_toggle_off_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppSwitchTile(
              icon: Icons.cloud_upload_outlined,
              color: Colors.blue,
              value: _openlistEnabled,
              title: '上传到 OpenList',
              subtitle: '使用 OpenList WebDAV 保存服务器备份包',
              onChanged: (v) => setState(() => _openlistEnabled = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _openlistUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'OpenList WebDAV URL',
                hintText: 'http://127.0.0.1:5244/dav',
                prefixIcon: Icon(Icons.link_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _openlistPublicUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'OpenList 公开 URL (可选)',
                prefixIcon: Icon(Icons.public_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _openlistUserCtrl,
                    decoration: const InputDecoration(
                      labelText: 'OpenList 用户名',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _openlistPasswordCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'OpenList 密码',
                      helperText: _openlistPasswordMasked
                          ? '已配置，保持不动即不修改'
                          : null,
                      prefixIcon: const Icon(Icons.password_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _openlistPathCtrl,
              decoration: const InputDecoration(
                labelText: 'OpenList 备份目录',
                hintText: '/duoyi-backups',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
            ),
            const SizedBox(height: 12),
            AppSwitchTile(
              icon: Icons.mark_email_read_outlined,
              color: Colors.teal,
              value: _backupEmailEnabled,
              title: '备份完成后发送邮件',
              subtitle: '支持 SMTP，失败会写入备份记录',
              onChanged: (v) => setState(() => _backupEmailEnabled = v),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailToCtrl,
                    decoration: const InputDecoration(
                      labelText: '通知收件人',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _emailFromCtrl,
                    decoration: const InputDecoration(
                      labelText: '发件人',
                      prefixIcon: Icon(Icons.outgoing_mail),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _smtpHostCtrl,
              decoration: const InputDecoration(
                labelText: 'SMTP Host',
                prefixIcon: Icon(Icons.dns_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _smtpPortCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'SMTP 端口',
                      prefixIcon: Icon(Icons.numbers_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _smtpUserCtrl,
                    decoration: const InputDecoration(
                      labelText: 'SMTP 用户名',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _smtpPasswordCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'SMTP 密码',
                helperText: _smtpPasswordMasked ? '已配置，保持不动即不修改' : null,
                prefixIcon: const Icon(Icons.key_outlined),
              ),
            ),
            const SizedBox(height: 16),
            AppSwitchTile(
              icon: Icons.mark_email_read_outlined,
              color: Colors.indigo,
              value: _accountEmailEnabled,
              title: '账号验证码邮件',
              subtitle: '注册验证、邮箱登录和找回密码共用主备通道',
              onChanged: (v) => setState(() => _accountEmailEnabled = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emailTitleCtrl,
              decoration: const InputDecoration(
                labelText: '账号邮件标题',
                helperText: '兼容 RE0 的 TITLE，默认使用多仪',
                prefixIcon: Icon(Icons.title_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _emailSenderNameCtrl,
              decoration: const InputDecoration(
                labelText: '账号邮件发件人显示名',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: AppDropdownField<String>(
                    initialValue: _emailPrimaryProvider,
                    decoration: const InputDecoration(
                      labelText: '主通道',
                      prefixIcon: Icon(Icons.route_outlined),
                    ),
                    items: _mailProviderItems(),
                    onChanged: (v) =>
                        setState(() => _emailPrimaryProvider = v ?? 'claw163'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppDropdownField<String>(
                    initialValue: _emailBackupProvider,
                    decoration: const InputDecoration(
                      labelText: '备用通道',
                      prefixIcon: Icon(Icons.alt_route_outlined),
                    ),
                    items: _mailProviderItems(),
                    onChanged: (v) =>
                        setState(() => _emailBackupProvider = v ?? 'resend'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: AppDropdownField<String>(
                    initialValue: _emailActiveSlot,
                    decoration: const InputDecoration(
                      labelText: '当前优先线路',
                      prefixIcon: Icon(Icons.swap_horiz_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'primary', child: Text('主通道')),
                      DropdownMenuItem(value: 'backup', child: Text('备用通道')),
                    ],
                    onChanged: (v) =>
                        setState(() => _emailActiveSlot = v ?? 'primary'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('备用成功后自动切换'),
                    value: _emailAutoSwitchEnabled,
                    onChanged: (v) =>
                        setState(() => _emailAutoSwitchEnabled = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _openclawMailUserCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Claw163 发件邮箱',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _openclawMailKeyCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Claw163 API Key',
                      helperText: _openclawMailKeyMasked
                          ? '已配置，保持不动即不修改'
                          : null,
                      prefixIcon: const Icon(Icons.key_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _resendBaseUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'Resend Base URL',
                hintText: 'https://api.resend.com',
                prefixIcon: Icon(Icons.link_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _resendApiKeyCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Resend API Key',
                      helperText: _resendApiKeyMasked ? '已配置，保持不动即不修改' : null,
                      prefixIcon: const Icon(Icons.key_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _resendFromCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Resend 发件人',
                      prefixIcon: Icon(Icons.outgoing_mail),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _systemNoticeEmailCtrl,
              decoration: const InputDecoration(
                labelText: '系统通知收件人',
                helperText: '多个邮箱用逗号分隔',
                prefixIcon: Icon(Icons.notifications_active_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _accountSmtpHostCtrl,
              decoration: const InputDecoration(
                labelText: '账号 SMTP Host',
                prefixIcon: Icon(Icons.dns_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _accountSmtpPortCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '账号 SMTP 端口',
                      prefixIcon: Icon(Icons.numbers_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _accountSmtpUserCtrl,
                    decoration: const InputDecoration(
                      labelText: '账号 SMTP 用户名',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _accountSmtpFromCtrl,
              decoration: const InputDecoration(
                labelText: '账号 SMTP 发件地址',
                helperText: '留空时使用账号 SMTP 用户名',
                prefixIcon: Icon(Icons.outgoing_mail),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _accountSmtpPasswordCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: '账号 SMTP 密码',
                helperText: _accountSmtpPasswordMasked ? '已配置，保持不动即不修改' : null,
                prefixIcon: const Icon(Icons.key_outlined),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('账号 SMTP 使用 SSL'),
              value: _accountSmtpUseSsl,
              onChanged: (v) => setState(() => _accountSmtpUseSsl = v),
            ),
            const SizedBox(height: 16),
            AppSwitchTile(
              icon: Icons.alternate_email_outlined,
              color: Colors.deepPurple,
              value: _reminderEmailEnabled,
              title: '邮件提醒投递',
              subtitle: '待办/目标的“邮件”提醒会按计划写入后端 SMTP 队列',
              onChanged: (v) => setState(() => _reminderEmailEnabled = v),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _reminderEmailToCtrl,
                    decoration: const InputDecoration(
                      labelText: '默认提醒收件人',
                      helperText: '用户登录名是邮箱时优先投递给该用户',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _reminderEmailFromCtrl,
                    decoration: const InputDecoration(
                      labelText: '提醒发件人',
                      prefixIcon: Icon(Icons.outgoing_mail),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reminderSmtpHostCtrl,
              decoration: const InputDecoration(
                labelText: '提醒 SMTP Host',
                prefixIcon: Icon(Icons.dns_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _reminderSmtpPortCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '提醒 SMTP 端口',
                      prefixIcon: Icon(Icons.numbers_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _reminderSmtpUserCtrl,
                    decoration: const InputDecoration(
                      labelText: '提醒 SMTP 用户名',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reminderSmtpPasswordCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: '提醒 SMTP 密码',
                helperText: _reminderSmtpPasswordMasked ? '已配置，保持不动即不修改' : null,
                prefixIcon: const Icon(Icons.key_outlined),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? '保存中…' : '保存配置'),
                ),
                OutlinedButton.icon(
                  onPressed: _runningServerBackup ? null : _runServerBackup,
                  icon: _runningServerBackup
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.backup_outlined),
                  label: Text(_runningServerBackup ? '备份中…' : '立即备份'),
                ),
                OutlinedButton.icon(
                  onPressed: _testingReminderEmail ? null : _testReminderEmail,
                  icon: _testingReminderEmail
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.mark_email_read_outlined),
                  label: Text(_testingReminderEmail ? '发送中…' : '测试提醒邮件'),
                ),
                OutlinedButton.icon(
                  onPressed: _testingAccountEmail ? null : _testAccountEmail,
                  icon: _testingAccountEmail
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.alternate_email_outlined),
                  label: Text(_testingAccountEmail ? '发送中…' : '测试账号邮件'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 640,
          child: _buildBackupRecordTabs(
            context,
            theme: theme,
            cs: cs,
            totalKb: totalKb,
          ),
        ),
      ],
    );
  }
}

// ====================================================================
// 用户
// ====================================================================

class _UsersTab extends StatefulWidget {
  final AdminApi api;
  final String? selfId;
  final List<String>? selfAdminPermissions;
  final bool isActive;
  const _UsersTab({
    super.key,
    required this.api,
    required this.selfId,
    required this.selfAdminPermissions,
    required this.isActive,
  });
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  static const _onlineRefreshInterval = Duration(seconds: 60);

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _roles = [];
  AdminPage? _page;
  bool _loading = true;
  String? _error;
  String? _groupsRolesError;
  String _query = '';
  String _status = '';
  String _sort = 'created_desc';
  int _pageSize = _adminPageSize;
  int _offset = 0;
  int _loadSerial = 0;
  final Set<String> _selectedUserIds = <String>{};
  Timer? _onlineRefreshTimer;
  bool _backgroundRefreshInFlight = false;
  final _searchCtrl = TextEditingController();

  bool _canUseAdminPermission(String permission) {
    final permissions = widget.selfAdminPermissions;
    if (permissions == null) return true;
    return permissions.contains(_adminAllPermission) ||
        permissions.contains(permission);
  }

  bool get _canManageUsers => _canUseAdminPermission('users');
  bool get _canManageGroups => _canUseAdminPermission('groups');
  bool get _canManageRoles => _canUseAdminPermission('roles');
  bool get _canManagePermissions => _canUseAdminPermission('permissions');
  bool get _canAssignGroups => _canManageGroups;
  bool get _canManageAdminAccess => _canManageRoles || _canManagePermissions;
  bool get _canManageUserAdminAccess =>
      _canManageUsers && _canManageAdminAccess;
  bool get _hasAllAdminPermission {
    final permissions = widget.selfAdminPermissions;
    return permissions == null || permissions.contains(_adminAllPermission);
  }

  bool _canToggleAdminFor(bool currentAdmin) {
    if (!_canManageUsers) return false;
    return currentAdmin ? _canManageAdminAccess : _hasAllAdminPermission;
  }

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.isActive) {
      _startOnlineRefreshTimer();
    }
  }

  @override
  void didUpdateWidget(covariant _UsersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) return;
    if (widget.isActive) {
      _startOnlineRefreshTimer();
    } else {
      _stopOnlineRefreshTimer();
    }
  }

  void _startOnlineRefreshTimer() {
    if (_onlineRefreshTimer != null) return;
    _onlineRefreshTimer = Timer.periodic(_onlineRefreshInterval, (_) {
      if (!mounted ||
          !widget.isActive ||
          _loading ||
          _backgroundRefreshInFlight) {
        return;
      }
      _load(quiet: true, background: true);
    });
  }

  void _stopOnlineRefreshTimer() {
    _onlineRefreshTimer?.cancel();
    _onlineRefreshTimer = null;
  }

  @override
  void dispose() {
    _stopOnlineRefreshTimer();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({
    String? query,
    String? status,
    String? sort,
    int? pageSize,
    int? offset,
    bool quiet = false,
    bool background = false,
  }) async {
    if (background && (_backgroundRefreshInFlight || _loading)) return;
    if (background) _backgroundRefreshInFlight = true;
    final loadSerial = ++_loadSerial;
    final nextQuery = query ?? _query;
    final nextStatus = status ?? _status;
    final nextSort = sort ?? _sort;
    final nextPageSize = pageSize ?? _pageSize;
    final nextOffset = offset ?? _offset;
    _query = nextQuery;
    _status = nextStatus;
    _sort = nextSort;
    _pageSize = nextPageSize;
    _offset = nextOffset;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
        _groupsRolesError = null;
      });
    }
    try {
      final groupsRolesErrors = <String>[];
      final pageFuture = widget.api.listUsersPage(
        query: nextQuery.isEmpty ? null : nextQuery,
        status: _backendStatusFilter(nextStatus),
        online: _onlineFilter(nextStatus),
        sort: nextSort,
        limit: nextPageSize,
        offset: nextOffset,
      );
      final groupsFuture = _groups.isEmpty && _canAssignGroups
          ? _loadUserGroupsForUsers(groupsRolesErrors)
          : Future<List<Map<String, dynamic>>>.value(_groups);
      final rolesFuture = _roles.isEmpty && _canManageRoles
          ? _loadUserRolesForUsers(groupsRolesErrors)
          : Future<List<Map<String, dynamic>>>.value(_roles);
      final results = await Future.wait<dynamic>([
        pageFuture,
        groupsFuture,
        rolesFuture,
      ]);
      final page = results[0] as AdminPage;
      if (!mounted || loadSerial != _loadSerial) return;
      setState(() {
        _page = page;
        _users = page.items;
        _groups = List<Map<String, dynamic>>.from(results[1] as List);
        _roles = List<Map<String, dynamic>>.from(results[2] as List);
        _selectedUserIds.removeWhere(
          (id) => !_users.any((u) => u['user_id'].toString() == id),
        );
        _error = null;
        _groupsRolesError = groupsRolesErrors.isEmpty
            ? null
            : groupsRolesErrors.join('\n');
      });
    } catch (e) {
      if (!mounted || loadSerial != _loadSerial) return;
      if (!quiet) {
        setState(() => _error = _adminErrorMessage(e, '用户列表'));
      }
    } finally {
      if (background) _backgroundRefreshInFlight = false;
      if (mounted && !quiet && loadSerial == _loadSerial) {
        setState(() => _loading = false);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadUserGroupsForUsers(
    List<String> errors,
  ) async {
    try {
      return await widget.api.listGroups();
    } catch (error) {
      errors.add(_adminErrorMessage(error, '用户组'));
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _loadUserRolesForUsers(
    List<String> errors,
  ) async {
    try {
      return await widget.api.listRoles();
    } catch (error) {
      errors.add(_adminErrorMessage(error, '角色'));
      return const <Map<String, dynamic>>[];
    }
  }

  String _adminEntityName(
    List<Map<String, dynamic>> items,
    String id,
    String fallback,
  ) {
    if (id.isEmpty) return fallback;
    for (final item in items) {
      if (item['id'].toString() == id) {
        final name = (item['name'] ?? '').toString();
        return name.isEmpty ? id : name;
      }
    }
    return id;
  }

  List<DropdownMenuItem<String>> _adminEntityItems(
    List<Map<String, dynamic>> items,
    String currentId,
    String currentFallback, {
    bool activeOnly = false,
  }) {
    final seen = <String>{};
    final result = <DropdownMenuItem<String>>[];
    if (currentId.isNotEmpty) {
      seen.add(currentId);
      final current = items.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['id'].toString() == currentId,
        orElse: () => null,
      );
      final isInactive = current?['is_active'] == false;
      result.add(
        DropdownMenuItem(
          value: currentId,
          child: Text(
            '${_adminEntityName(items, currentId, currentFallback)}${isInactive ? ' · 停用' : ''}',
          ),
        ),
      );
    }
    for (final item in items) {
      final id = (item['id'] ?? '').toString();
      if (id.isEmpty || seen.contains(id)) continue;
      if (activeOnly && item['is_active'] == false) continue;
      seen.add(id);
      final name = (item['name'] ?? '').toString();
      final count = _adminIntValue(item['user_count']);
      result.add(
        DropdownMenuItem(
          value: id,
          child: Text('${name.isEmpty ? id : name} · $count 人'),
        ),
      );
    }
    return result;
  }

  List<DropdownMenuItem<String>> _roleEntityItems(
    String currentId,
    String currentFallback, {
    bool activeOnly = false,
  }) {
    final roles = _hasAllAdminPermission
        ? _roles
        : _roles
              .where((role) => (role['id'] ?? '').toString() != 'role_admin')
              .toList(growable: false);
    return _adminEntityItems(
      roles,
      currentId,
      currentFallback,
      activeOnly: activeOnly,
    );
  }

  void _applySearch() {
    _load(query: _searchCtrl.text.trim(), offset: 0);
  }

  void _applyStatus(String status) {
    setState(() => _status = status);
    _load(status: status, offset: 0);
  }

  void _applySort(String sort) {
    _load(sort: sort, offset: 0);
  }

  void _jumpToPage(int pageNumber) {
    final page = pageNumber < 1 ? 1 : pageNumber;
    _load(offset: (page - 1) * _pageSize);
  }

  bool? _onlineFilter(String status) {
    if (status == 'online') return true;
    if (status == 'offline') return false;
    return null;
  }

  String? _backendStatusFilter(String status) {
    if (status.isEmpty || status == 'online' || status == 'offline') {
      return null;
    }
    return status;
  }

  Future<void> _createUser() async {
    if (!_canManageUsers) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缺少用户管理权限')));
      return;
    }
    if (_canAssignGroups && _groups.isEmpty ||
        _canManageRoles && _roles.isEmpty) {
      await _load(quiet: true);
    }
    if (!mounted) return;

    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final displayNameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final assignableRoles = _hasAllAdminPermission
        ? _roles
        : _roles
              .where((role) => (role['id'] ?? '').toString() != 'role_admin')
              .toList(growable: false);
    var selectedGroupId = _groups.any((g) => g['id'] == 'group_default')
        ? 'group_default'
        : (_groups.isNotEmpty ? _groups.first['id'].toString() : '');
    var selectedRoleId = assignableRoles.any((r) => r['id'] == 'role_user')
        ? 'role_user'
        : (assignableRoles.isNotEmpty
              ? assignableRoles.first['id'].toString()
              : '');
    var isAdmin = false;
    var isDisabled = false;

    final saved = await showAppModalSheet<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AppModalSheet(
          title: '新增用户',
          actions: _adminSheetActions(ctx, saveLabel: '创建'),
          child: _adminSheetForm(
            children: [
              TextField(
                controller: usernameCtrl,
                decoration: const InputDecoration(labelText: '用户名'),
                textInputAction: TextInputAction.next,
              ),
              TextField(
                controller: passwordCtrl,
                decoration: const InputDecoration(
                  labelText: '初始密码',
                  helperText: '留空时由服务器生成随机密码',
                ),
                obscureText: true,
                textInputAction: TextInputAction.next,
              ),
              TextField(
                controller: displayNameCtrl,
                decoration: const InputDecoration(labelText: '昵称 (可选)'),
                textInputAction: TextInputAction.next,
              ),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: '邮箱 (可选)'),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              if (_canAssignGroups && _groups.isNotEmpty)
                AppDropdownField<String>(
                  initialValue: selectedGroupId,
                  labelText: '用户组',
                  prefixIcon: const Icon(Icons.groups_2_outlined),
                  items: _adminEntityItems(
                    _groups,
                    selectedGroupId,
                    '默认组',
                    activeOnly: true,
                  ),
                  onChanged: (value) {
                    if (value != null) {
                      setSt(() => selectedGroupId = value);
                    }
                  },
                ),
              if (_canManageRoles && assignableRoles.isNotEmpty)
                AppDropdownField<String>(
                  initialValue: selectedRoleId,
                  labelText: '角色',
                  prefixIcon: const Icon(Icons.admin_panel_settings_outlined),
                  items: _adminEntityItems(
                    assignableRoles,
                    selectedRoleId,
                    '普通角色',
                    activeOnly: true,
                  ),
                  onChanged: (value) {
                    if (value != null) {
                      setSt(() => selectedRoleId = value);
                    }
                  },
                ),
              if (_hasAllAdminPermission)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: isAdmin,
                  title: const Text('管理员账号'),
                  onChanged: (value) => setSt(() {
                    isAdmin = value;
                    if (value && selectedRoleId == 'role_user') {
                      selectedRoleId =
                          _roles.any((r) => r['id'] == 'role_admin')
                          ? 'role_admin'
                          : selectedRoleId;
                    } else if (!value && selectedRoleId == 'role_admin') {
                      selectedRoleId = _roles.any((r) => r['id'] == 'role_user')
                          ? 'role_user'
                          : selectedRoleId;
                    }
                  }),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: isDisabled,
                title: const Text('创建后先禁用'),
                onChanged: (value) => setSt(() => isDisabled = value),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;
    final username = usernameCtrl.text.trim();
    if (username.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写用户名')));
      return;
    }
    try {
      await widget.api.createUser(
        username: username,
        password: passwordCtrl.text,
        displayName: displayNameCtrl.text,
        email: emailCtrl.text,
        groupId: _canAssignGroups ? selectedGroupId : null,
        roleId: _canManageRoles ? selectedRoleId : null,
        isAdmin: _hasAllAdminPermission ? isAdmin : false,
        isDisabled: isDisabled,
      );
      await _load(offset: 0);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('用户已创建')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userVisibleApiError(e))));
    }
  }

  Future<void> _toggleAdmin(Map<String, dynamic> u) async {
    final becomeAdmin = !(u['is_admin'] == true);
    if (becomeAdmin && !_hasAllAdminPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缺少超级管理员权限')));
      return;
    }
    try {
      await widget.api.updateUser(u['user_id'], isAdmin: becomeAdmin);
      u['is_admin'] = becomeAdmin;
      await _load(quiet: true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userVisibleApiError(e))));
      }
    }
  }

  Future<void> _toggleDisable(Map<String, dynamic> u) async {
    if (u['user_id'].toString() == widget.selfId) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('不能禁用当前登录账号')));
      return;
    }
    final disable = !(u['is_disabled'] == true);
    try {
      await widget.api.updateUser(u['user_id'], isDisabled: disable);
      u['is_disabled'] = disable;
      await _load(quiet: true);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userVisibleApiError(e))));
      }
    }
  }

  Future<void> _exportUsersCsv() async {
    try {
      final csv = await widget.api.exportUsersCsv(
        query: _query.isEmpty ? null : _query,
        status: _backendStatusFilter(_status),
        online: _onlineFilter(_status),
        sort: _sort,
      );
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/duoyi_users_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
      await file.writeAsString(csv, flush: true);
      await Clipboard.setData(ClipboardData(text: file.path));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: '多仪管理员用户导出',
          subject: '多仪用户 CSV',
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('用户 CSV 已导出，路径已复制：${file.path}')));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userVisibleApiError(e))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_adminActionErrorMessage(e, '导出用户 CSV'))),
        );
      }
    }
  }

  List<String> get _selectableCurrentPageUserIds {
    if (!_canManageUsers) return const [];
    return _users
        .map((u) => u['user_id'].toString())
        .where((id) => id.isNotEmpty && id != widget.selfId)
        .toList();
  }

  List<String> get _selectedCurrentPageUserIds =>
      _selectableCurrentPageUserIds.where(_selectedUserIds.contains).toList();

  void _toggleUserSelection(String userId, bool selected) {
    setState(() {
      if (selected) {
        _selectedUserIds.add(userId);
      } else {
        _selectedUserIds.remove(userId);
      }
    });
  }

  void _toggleCurrentPageSelection(bool selected) {
    setState(() {
      final ids = _selectableCurrentPageUserIds;
      if (selected) {
        _selectedUserIds.addAll(ids);
      } else {
        _selectedUserIds.removeAll(ids);
      }
    });
  }

  Future<void> _bulkSetDisabled(bool disabled) async {
    final ids = _selectedCurrentPageUserIds;
    if (ids.isEmpty) return;
    final ok = await _confirmAdminDangerAction(
      context: context,
      title: disabled ? '批量禁用账号？' : '批量恢复账号？',
      message: disabled
          ? '将禁用当前页已选的 ${ids.length} 个账号，并使这些账号需要重新登录。'
          : '将恢复当前页已选的 ${ids.length} 个账号登录权限。',
      confirmLabel: disabled ? '禁用' : '恢复',
    );
    if (!ok) return;
    try {
      await widget.api.bulkUpdateUserStatus(userIds: ids, isDisabled: disabled);
      _selectedUserIds.removeAll(ids);
      await _load(offset: _offset);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            disabled ? '已批量禁用 ${ids.length} 个账号' : '已批量恢复 ${ids.length} 个账号',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userVisibleApiError(e))));
      }
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> u) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text('重置 ${u['username']} 的密码'),
        icon: const Icon(Icons.lock_reset_outlined),
        content: _adminDialogForm(
          maxWidth: 420,
          children: [
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: '新密码',
                helperText: '提交后该用户需要使用新密码重新登录',
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: _adminDialogActions(ctx, saveLabel: '提交'),
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      await widget.api.updateUser(u['user_id'], newPassword: ctrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('密码已重置，该用户需重新登录')));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userVisibleApiError(e))));
      }
    }
  }

  Future<void> _editAdminPermissions(Map<String, dynamic> u) async {
    if (!_canManageUserAdminAccess) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缺少权限管理权限')));
      return;
    }
    final userId = u['user_id'].toString();
    final username = u['username'].toString();
    final isAdmin = u['is_admin'] == true;
    if (!isAdmin) {
      final ok = await _confirmAdminDangerAction(
        context: context,
        title: '授予管理员身份？',
        message: '设置管理权限前需要先将“$username”设为管理员。',
        confirmLabel: '授予',
      );
      if (!ok) return;
      if (!mounted) return;
    }
    var selected = _adminUserPermissions(
      u['admin_permissions'],
      isAdmin: isAdmin,
    ).toSet();
    if (selected.contains(_adminAllPermission)) {
      selected = _adminAllPermissionKeys();
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AppDialog(
          title: Text('设置 $username 的管理权限'),
          icon: const Icon(Icons.admin_panel_settings_outlined),
          content: _adminDialogForm(
            maxWidth: 520,
            children: [
              _adminPermissionChecklist(
                selected: selected,
                onChanged: (next) => setSt(() => selected = next),
              ),
            ],
          ),
          actions: _adminDialogActions(ctx, saveLabel: '保存权限'),
        ),
      ),
    );
    if (saved != true) return;
    final selectedAllPermissions = _adminHasAllPermissions(selected);
    final permissions = selected.isEmpty
        ? const [_adminNoPermission]
        : (selectedAllPermissions && _hasAllAdminPermission
              ? const [_adminAllPermission]
              : selected.toList());
    try {
      final existingRoleId = (u['role_id'] ?? '').toString();
      final roleIdForPromotion =
          existingRoleId.isNotEmpty &&
              (existingRoleId != 'role_admin' || _hasAllAdminPermission)
          ? existingRoleId
          : 'role_user';
      await widget.api.updateUser(
        userId,
        isAdmin: isAdmin ? null : true,
        roleId: isAdmin ? null : roleIdForPromotion,
        adminPermissions: permissions,
      );
      await _load(quiet: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('管理权限已更新')));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userVisibleApiError(e))));
      }
    }
  }

  Future<void> _editUserGroupRole(Map<String, dynamic> u) async {
    if (!_canManageUsers) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缺少用户管理权限')));
      return;
    }
    if (!_canAssignGroups && !_canManageRoles) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缺少用户组或角色管理权限')));
      return;
    }
    if ((_canAssignGroups && _groups.isEmpty) ||
        (_canManageRoles && _roles.isEmpty)) {
      await _load(quiet: true);
    }
    if (!mounted) return;
    final username = u['username'].toString();
    var selectedGroupId = (u['group_id'] ?? 'group_default').toString();
    var selectedRoleId =
        (u['role_id'] ?? (u['is_admin'] == true ? 'role_admin' : 'role_user'))
            .toString();
    final canEditRoleForTarget =
        _canManageRoles &&
        (_hasAllAdminPermission || selectedRoleId != 'role_admin');
    if (!_canAssignGroups && !canEditRoleForTarget) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缺少可用的角色管理权限')));
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AppDialog(
          title: Text('调整 $username 的用户组与角色'),
          icon: const Icon(Icons.manage_accounts_outlined),
          content: _adminDialogForm(
            maxWidth: 430,
            children: [
              if (_canAssignGroups)
                AppDropdownField<String>(
                  initialValue: selectedGroupId,
                  labelText: '用户组',
                  prefixIcon: const Icon(Icons.groups_2_outlined),
                  items: _adminEntityItems(
                    _groups,
                    selectedGroupId,
                    '当前用户组',
                    activeOnly: true,
                  ),
                  onChanged: (value) {
                    if (value != null) {
                      setSt(() => selectedGroupId = value);
                    }
                  },
                ),
              if (canEditRoleForTarget)
                AppDropdownField<String>(
                  initialValue: selectedRoleId,
                  labelText: '管理员角色',
                  prefixIcon: const Icon(Icons.admin_panel_settings_outlined),
                  items: _roleEntityItems(
                    selectedRoleId,
                    '当前角色',
                    activeOnly: true,
                  ),
                  onChanged: (value) {
                    if (value != null) {
                      setSt(() => selectedRoleId = value);
                    }
                  },
                ),
            ],
          ),
          actions: _adminDialogActions(ctx),
        ),
      ),
    );
    if (saved != true) return;
    try {
      await widget.api.updateUser(
        u['user_id'].toString(),
        groupId: _canAssignGroups ? selectedGroupId : null,
        roleId: canEditRoleForTarget ? selectedRoleId : null,
      );
      await _load(quiet: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('用户组与角色已更新')));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userVisibleApiError(e))));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text('删除 ${u['username']} ?'),
        icon: const Icon(Icons.delete_outline),
        content: const Text('会同时删除其所有同步数据与反馈，不可恢复'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteUser(u['user_id']);
      await _load(
        offset: _offsetAfterAdminDelete(
          offset: _offset,
          itemCount: _users.length,
          pageSize: _pageSize,
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userVisibleApiError(e))));
      }
    }
  }

  String _formatServerTime(dynamic raw) {
    final text = raw?.toString() ?? '';
    if (text.isEmpty || text == 'null') return '-';
    var normalized = text.contains('T') ? text : text.replaceFirst(' ', 'T');
    final hasTimezone = RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(normalized);
    if (!hasTimezone) normalized = '${normalized}Z';
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) return text;
    final local = AppClock.toLocal(parsed);
    return I18nDateFormat.fullDateTime(local);
  }

  String _formatLastLogin(dynamic raw) {
    final formatted = _formatServerTime(raw);
    return formatted == '-' ? '从未登录' : formatted;
  }

  String _formatLastActive(dynamic raw) {
    final formatted = _formatServerTime(raw);
    return formatted == '-' ? '从未活跃' : formatted;
  }

  Future<void> _showUserDetails(Map<String, dynamic> u) async {
    final userId = u['user_id'].toString();
    final admin = u['is_admin'] == true;
    final disabled = u['is_disabled'] == true;
    final online = u['online'] == true;
    final email = (u['email'] ?? '').toString();
    final emailVerified = u['email_verified'] == true;
    final displayName = (u['display_name'] ?? '').toString();
    final username = (u['username'] ?? '').toString();
    final groupId = (u['group_id'] ?? 'group_default').toString();
    final roleId = (u['role_id'] ?? (admin ? 'role_admin' : 'role_user'))
        .toString();
    final permissions = _adminUserPermissions(
      u['admin_permissions'],
      isAdmin: admin,
    );
    final detailLines = [
      '用户名: ${username.isEmpty ? '-' : username}',
      '用户 ID: $userId',
      '昵称: ${displayName.isEmpty ? '-' : displayName}',
      '邮箱: ${email.isEmpty ? '未绑定邮箱' : '$email${emailVerified ? ' (已验证)' : ' (未验证)'}'}',
      '账号状态: ${disabled ? '已禁用' : '可登录'} · ${online ? '在线' : '离线'}',
      '管理员: ${admin ? '是' : '否'}',
      '管理权限: ${_adminPermissionsLabel(permissions, isAdmin: admin)}',
      '用户组: ${_adminEntityName(_groups, groupId, '默认组')}',
      '角色: ${_adminEntityName(_roles, roleId, '普通角色')}',
      '注册时间: ${_formatServerTime(u['created_at'])}',
      '最近登录: ${_formatLastLogin(u['last_login_at'])}',
      '最近活跃: ${_formatLastActive(u['last_active_at'])}',
      '反馈数: ${u['feedback_count'] ?? 0}',
      '当前排序: ${_adminUserSortLabel(_sort)}',
    ];
    await showDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('用户详情'),
        icon: const Icon(Icons.person_search_outlined),
        content: SingleChildScrollView(
          child: SelectableText(detailLines.join('\n')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  PopupMenuButton<String> _userActionMenu(
    BuildContext context,
    Map<String, dynamic> u, {
    required bool admin,
    required bool disabled,
    required bool isSelf,
  }) {
    return PopupMenuButton<String>(
      tooltip: '账号操作',
      onSelected: (action) async {
        switch (action) {
          case 'details':
            await _showUserDetails(u);
            break;
          case 'admin':
            if (_canToggleAdminFor(admin)) {
              await _toggleAdmin(u);
            } else if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('缺少超级管理员权限')));
            }
            break;
          case 'permissions':
            if (_canManageUserAdminAccess) {
              await _editAdminPermissions(u);
            } else if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('缺少权限管理权限')));
            }
            break;
          case 'group_role':
            if (_canManageUsers) {
              await _editUserGroupRole(u);
            } else if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('缺少用户管理权限')));
            }
            break;
          case 'disable':
            if (_canManageUsers) {
              await _toggleDisable(u);
            }
            break;
          case 'reset':
            if (_canManageUsers) {
              await _resetPassword(u);
            }
            break;
          case 'delete':
            if (_canManageUsers) {
              await _delete(u);
            }
            break;
          case 'copy_id':
            await Clipboard.setData(
              ClipboardData(text: u['user_id'].toString()),
            );
            if (!context.mounted) return;
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('用户 ID 已复制')));
            }
            break;
        }
      },
      itemBuilder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return [
          const PopupMenuItem(
            value: 'details',
            child: AppSecondaryMenuText('查看详情'),
          ),
          if (_canToggleAdminFor(admin))
            PopupMenuItem(
              value: 'admin',
              child: AppSecondaryMenuText(admin ? '撤销管理员权限' : '授予管理员权限'),
            ),
          PopupMenuItem(
            value: 'permissions',
            enabled: _canManageUserAdminAccess,
            child: AppSecondaryMenuText(
              _canManageUserAdminAccess ? '设置管理权限' : '设置管理权限（无权限）',
            ),
          ),
          PopupMenuItem(
            value: 'group_role',
            enabled: _canManageUsers && (_canAssignGroups || _canManageRoles),
            child: AppSecondaryMenuText(
              _canManageUsers && (_canAssignGroups || _canManageRoles)
                  ? '设置用户组/角色'
                  : '设置用户组/角色（无权限）',
            ),
          ),
          if (_canManageUsers && !isSelf)
            PopupMenuItem(
              value: 'disable',
              child: AppSecondaryMenuText(disabled ? '恢复账号登录' : '禁用账号登录'),
            ),
          if (_canManageUsers)
            const PopupMenuItem(
              value: 'reset',
              child: AppSecondaryMenuText('重置登录密码'),
            ),
          const PopupMenuItem(
            value: 'copy_id',
            child: AppSecondaryMenuText('复制用户 ID'),
          ),
          if (_canManageUsers && !isSelf)
            PopupMenuItem(
              value: 'delete',
              child: AppSecondaryMenuText('删除账号与数据', color: cs.error),
            ),
        ];
      },
    );
  }

  Widget _buildUserListItem(Map<String, dynamic> u) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final userId = u['user_id'].toString();
    final isSelf = userId == widget.selfId;
    final disabled = u['is_disabled'] == true;
    final admin = u['is_admin'] == true;
    final online = u['online'] == true;
    final permissions = _adminUserPermissions(
      u['admin_permissions'],
      isAdmin: admin,
    );
    final canSelectForBulk = _canManageUsers;
    final selected = canSelectForBulk && _selectedUserIds.contains(userId);
    final registeredAt = _formatServerTime(u['created_at']);
    final lastLoginAt = _formatLastLogin(u['last_login_at']);
    final lastActiveAt = _formatLastActive(u['last_active_at']);
    final email = (u['email'] ?? '').toString();
    final emailVerified = u['email_verified'] == true;
    final displayName = (u['display_name'] ?? '').toString();
    final username = u['username'].toString();
    final groupId = (u['group_id'] ?? 'group_default').toString();
    final roleId = (u['role_id'] ?? (admin ? 'role_admin' : 'role_user'))
        .toString();
    final groupName = _adminEntityName(_groups, groupId, '默认组');
    final roleName = _adminEntityName(_roles, roleId, '普通角色');
    final actionMenu = _userActionMenu(
      context,
      u,
      admin: admin,
      disabled: disabled,
      isSelf: isSelf,
    );
    final statusBadges = <Widget>[
      AppStatusBadge(
        label: online ? '在线' : '离线',
        color: online ? Colors.green : Colors.grey,
        icon: online ? Icons.circle : Icons.radio_button_unchecked,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      ),
      if (admin) const AppStatusBadge(label: '管理员', color: Colors.deepOrange),
      if (admin && !permissions.contains(_adminAllPermission))
        const AppStatusBadge(label: '细分权限', color: Colors.indigo),
      if (disabled)
        AppStatusBadge(
          label: '已禁用',
          color: Theme.of(context).colorScheme.error,
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 980) {
          final subtleText = appSecondaryControlLabelStyle(
            context,
          ).copyWith(color: cs.onSurface.withValues(alpha: 0.62));
          final mainText = appSecondaryMenuItemTextStyle(context).copyWith(
            color: cs.onSurface,
            decoration: disabled ? TextDecoration.lineThrough : null,
          );
          return AppSurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            borderRadius: BorderRadius.circular(9),
            border: _adminSubtleListBorder(context),
            onTap: () => _showUserDetails(u),
            child: Row(
              children: [
                if (canSelectForBulk)
                  SizedBox(
                    width: 34,
                    child: Checkbox(
                      value: selected,
                      onChanged: isSelf
                          ? null
                          : (value) =>
                                _toggleUserSelection(userId, value == true),
                    ),
                  ),
                SizedBox(
                  width: 220,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: admin
                            ? Colors.deepOrange.withValues(alpha: 0.16)
                            : cs.primary.withValues(alpha: 0.10),
                        foregroundColor: admin ? Colors.deepOrange : cs.primary,
                        child: Text(
                          username.isEmpty ? '?' : username.substring(0, 1),
                          style: appSecondaryControlLabelStyle(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: mainText,
                            ),
                            Text(
                              displayName.isEmpty ? userId : displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: subtleText,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    email.isEmpty
                        ? '未绑定邮箱'
                        : '$email${emailVerified ? ' · 已验证' : ' · 未验证'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: subtleText,
                  ),
                ),
                SizedBox(
                  width: 178,
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: statusBadges,
                  ),
                ),
                SizedBox(
                  width: 138,
                  child: Text(
                    '$groupName\n$roleName',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: subtleText,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '最近登录: $lastLoginAt\n最近活跃: $lastActiveAt',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: subtleText,
                  ),
                ),
                actionMenu,
              ],
            ),
          );
        }
        final roleBadgeColor = admin ? Colors.deepOrange : Colors.indigo;
        final emailText = email.isEmpty
            ? '未绑定邮箱'
            : '$email${emailVerified ? ' · 已验证' : ' · 未验证'}';
        final mobileStatusBadges = <Widget>[
          AppStatusBadge(
            label: online ? '在线' : '离线',
            color: online ? Colors.green : Colors.grey,
            icon: online ? Icons.circle : Icons.radio_button_unchecked,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          ),
          if (disabled)
            AppStatusBadge(
              label: '已禁用',
              color: cs.error,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            ),
        ];
        final identityBadges = <Widget>[
          AppStatusBadge(
            label: roleName,
            color: roleBadgeColor,
            icon: Icons.badge_outlined,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          ),
          AppStatusBadge(
            label: groupName,
            color: cs.primary,
            icon: Icons.groups_2_outlined,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          ),
          if (admin)
            const AppStatusBadge(label: '管理员', color: Colors.deepOrange),
          if (admin && !permissions.contains(_adminAllPermission))
            const AppStatusBadge(label: '细分权限', color: Colors.indigo),
        ];
        return AppSurfaceCard(
          key: ValueKey('admin_user_mobile_card_$userId'),
          padding: const EdgeInsets.fromLTRB(10, 9, 4, 10),
          borderRadius: BorderRadius.circular(9),
          border: _adminSubtleListBorder(context),
          onTap: () => _showUserDetails(u),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (canSelectForBulk)
                SizedBox(
                  width: 32,
                  child: Checkbox(
                    value: selected,
                    onChanged: isSelf
                        ? null
                        : (value) =>
                              _toggleUserSelection(userId, value == true),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: admin
                              ? Colors.deepOrange.withValues(alpha: 0.18)
                              : cs.primary.withValues(alpha: 0.12),
                          foregroundColor: admin
                              ? Colors.deepOrange
                              : cs.primary,
                          child: Text(
                            username.isEmpty ? '?' : username.substring(0, 1),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface,
                              fontWeight: DesignTokens.fontWeightStrong,
                              decoration: disabled
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 92),
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 4,
                            runSpacing: 4,
                            children: mobileStatusBadges,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      key: ValueKey('admin_user_identity_badges_$userId'),
                      spacing: 6,
                      runSpacing: 6,
                      children: identityBadges,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        _AdminMobileMetaItem(
                          icon: Icons.alternate_email_outlined,
                          text: emailText,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        _AdminMobileMetaItem(
                          icon: Icons.how_to_reg_outlined,
                          text: '注册 $registeredAt',
                        ),
                        _AdminMobileMetaItem(
                          icon: Icons.login_outlined,
                          text: '最近登录: $lastLoginAt',
                        ),
                        _AdminMobileMetaItem(
                          icon: Icons.schedule_outlined,
                          text: '最近活跃: $lastActiveAt',
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _showUserDetails(u),
                        icon: const Icon(Icons.more_horiz),
                        label: const Text('更多详情'),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 40,
                child: Align(alignment: Alignment.topRight, child: actionMenu),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loadingFirstPage = _loading && _page == null;
    final selectableIds = _selectableCurrentPageUserIds;
    final selectedIds = _selectedCurrentPageUserIds;
    final allCurrentPageSelected =
        selectableIds.isNotEmpty && selectedIds.length == selectableIds.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactAdminFilters = constraints.maxWidth < 720;
        final userFilterChips = [
          _userFilterChip('全部账号', ''),
          _userFilterChip('可登录', 'active'),
          _userFilterChip('在线', 'online'),
          _userFilterChip('离线', 'offline'),
          _userFilterChip('管理员', 'admin'),
          _userFilterChip('已禁用', 'disabled'),
          _userFilterChip('普通用户', 'normal'),
          _userFilterChip('有反馈', 'has_feedback'),
          _userFilterChip('邮箱未验证', 'unverified_email'),
          _userFilterChip('邮箱已验证', 'verified_email'),
          _userFilterChip('未绑定邮箱', 'no_email'),
        ];
        const sortItems = [
          DropdownMenuItem(value: 'created_desc', child: Text('最新注册优先')),
          DropdownMenuItem(value: 'last_active_desc', child: Text('最近活跃优先')),
          DropdownMenuItem(value: 'last_login_desc', child: Text('最近登录优先')),
          DropdownMenuItem(value: 'feedback_desc', child: Text('反馈较多优先')),
          DropdownMenuItem(value: 'username_asc', child: Text('用户名 A-Z')),
          DropdownMenuItem(value: 'email_asc', child: Text('邮箱 A-Z')),
        ];
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                compactAdminFilters ? 8 : 12,
                12,
                6,
              ),
              child: Column(
                children: [
                  LayoutBuilder(
                    builder: (context, toolbarConstraints) {
                      Widget searchField() => TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: '搜索用户名、邮箱、昵称或用户 ID',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清空搜索',
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    _load(query: '', offset: 0);
                                  },
                                ),
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _applySearch(),
                      );

                      List<Widget> toolbarButtons() => [
                        IconButton(
                          tooltip: '搜索用户',
                          onPressed: _applySearch,
                          icon: const Icon(Icons.manage_search),
                        ),
                        if (_canManageUsers)
                          IconButton(
                            key: const ValueKey('admin_create_user_button'),
                            tooltip: '新增用户',
                            onPressed: _loading ? null : _createUser,
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                          ),
                        if (_canManageUsers)
                          IconButton(
                            tooltip: '导出用户筛选结果',
                            onPressed: _loading ? null : _exportUsersCsv,
                            icon: const Icon(Icons.download_outlined),
                          ),
                        IconButton(
                          tooltip: '刷新用户列表',
                          onPressed: _loading
                              ? null
                              : () => _load(offset: _offset),
                          icon: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh),
                        ),
                      ];

                      final buttons = toolbarButtons();
                      final actionWrap = Wrap(
                        key: const ValueKey('admin_users_toolbar_actions'),
                        spacing: 2,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: buttons,
                      );
                      if (compactAdminFilters ||
                          toolbarConstraints.maxWidth < 380) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            searchField(),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: actionWrap,
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: searchField()),
                          const SizedBox(width: 4),
                          actionWrap,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  compactAdminFilters
                      ? _AdminCompactChipStrip(
                          padding: EdgeInsets.zero,
                          children: userFilterChips,
                        )
                      : _AdminChipWrap(
                          padding: EdgeInsets.zero,
                          children: userFilterChips,
                        ),
                  SizedBox(height: compactAdminFilters ? 4 : 8),
                  if (compactAdminFilters)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _AdminPaginationLabeledControl(
                        label: '排序',
                        child: AppCompactDropdown<String>(
                          width: 142,
                          value: _sort,
                          items: sortItems,
                          onChanged: (value) =>
                              _applySort(value ?? 'created_desc'),
                        ),
                      ),
                    )
                  else
                    AppDropdownField<String>(
                      initialValue: _sort,
                      labelText: '排序',
                      items: sortItems,
                      onChanged: (value) => _applySort(value ?? 'created_desc'),
                    ),
                  if (!loadingFirstPage &&
                      _error == null &&
                      _users.isNotEmpty) ...[
                    SizedBox(height: compactAdminFilters ? 6 : 8),
                    AppSurfaceCard(
                      padding: EdgeInsets.fromLTRB(
                        compactAdminFilters ? 8 : 10,
                        compactAdminFilters ? 5 : 8,
                        compactAdminFilters ? 8 : 10,
                        compactAdminFilters ? 5 : 8,
                      ),
                      color: cs.secondaryContainer.withValues(alpha: 0.22),
                      border: Border.all(
                        color: cs.secondary.withValues(alpha: 0.14),
                        width: 0.45,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final summaryText = !_canManageUsers
                              ? '本页 ${_users.length} 个'
                              : (selectedIds.isEmpty
                                    ? '本页 ${_users.length} 个'
                                    : '已选 ${selectedIds.length} 个 · 当前页批量操作');
                          final summary = Text(
                            summaryText,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.68),
                            ),
                          );
                          final actions = Wrap(
                            spacing: 8,
                            runSpacing: compactAdminFilters ? 2 : 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: _canManageUsers
                                ? [
                                    FilterChip(
                                      label: Text(
                                        allCurrentPageSelected
                                            ? '取消全选本页'
                                            : '全选本页',
                                      ),
                                      selected: allCurrentPageSelected,
                                      onSelected: selectableIds.isEmpty
                                          ? null
                                          : (_) => _toggleCurrentPageSelection(
                                              !allCurrentPageSelected,
                                            ),
                                    ),
                                    TextButton.icon(
                                      onPressed: selectedIds.isEmpty || _loading
                                          ? null
                                          : () => _bulkSetDisabled(true),
                                      icon: const Icon(Icons.block_outlined),
                                      label: const Text('批量禁用'),
                                    ),
                                    TextButton.icon(
                                      onPressed: selectedIds.isEmpty || _loading
                                          ? null
                                          : () => _bulkSetDisabled(false),
                                      icon: const Icon(
                                        Icons.lock_open_outlined,
                                      ),
                                      label: const Text('批量恢复'),
                                    ),
                                  ]
                                : const [],
                          );
                          if (compactAdminFilters ||
                              constraints.maxWidth < 560) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                summary,
                                const SizedBox(height: 6),
                                actions,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: summary),
                              actions,
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                  _AdminInlineLoadingIndicator(
                    visible: _loading && _page != null,
                    label: '正在更新当前页',
                  ),
                  if (_groupsRolesError != null) ...[
                    const SizedBox(height: 8),
                    AppInfoBanner(
                      icon: Icons.lock_outline,
                      title: '用户组或角色加载失败',
                      message: _groupsRolesError!,
                      color: cs.error,
                      margin: EdgeInsets.zero,
                    ),
                  ],
                ],
              ),
            ),
            if (loadingFirstPage)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('正在加载用户列表…'),
                    ],
                  ),
                ),
              )
            else if (_error != null)
              Expanded(
                child: _AdminErrorState(
                  message: _error!,
                  onRetry: () => _load(offset: _offset),
                ),
              )
            else if (_users.isEmpty)
              Expanded(
                child: EmptyState(
                  icon: Icons.people_outline,
                  message: _query.isEmpty && _status.isEmpty
                      ? '暂无用户记录'
                      : '没有匹配的用户。请调整搜索关键词或账号状态筛选。',
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _load(offset: _offset),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    itemCount: _users.length,
                    separatorBuilder: (context, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _buildUserListItem(_users[i]),
                  ),
                ),
              ),
            _AdminPaginationBar(
              page: _page,
              loading: _loading,
              pageSize: _pageSize,
              onPageSizeChanged: (value) => _load(pageSize: value, offset: 0),
              onPrevious: () =>
                  _load(offset: _previousAdminOffset(_offset, _pageSize)),
              onNext: () => _load(offset: _offset + _pageSize),
              onJumpToPage: _jumpToPage,
            ),
          ],
        );
      },
    );
  }

  Widget _userFilterChip(String label, String value) {
    final selected = _status == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _applyStatus(value),
      ),
    );
  }
}

// ====================================================================
// 公告
// ====================================================================

class _AnnouncementsTab extends StatefulWidget {
  final AdminApi api;
  const _AnnouncementsTab({super.key, required this.api});
  @override
  State<_AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends State<_AnnouncementsTab> {
  List<Map<String, dynamic>> _items = [];
  AdminPage? _page;
  bool _loading = true;
  String? _error;
  String _query = '';
  String _status = '';
  String _level = '';
  String _sort = 'created_desc';
  int _pageSize = _adminPageSize;
  int _offset = 0;
  int _loadSerial = 0;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({
    int? offset,
    String? query,
    String? status,
    String? level,
    String? sort,
    int? pageSize,
  }) async {
    final loadSerial = ++_loadSerial;
    final nextOffset = offset ?? _offset;
    final nextQuery = query ?? _query;
    final nextStatus = status ?? _status;
    final nextLevel = level ?? _level;
    final nextSort = sort ?? _sort;
    final nextPageSize = pageSize ?? _pageSize;
    _offset = nextOffset;
    _query = nextQuery;
    _status = nextStatus;
    _level = nextLevel;
    _sort = nextSort;
    _pageSize = nextPageSize;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.listAnnouncementsPage(
        query: nextQuery.isEmpty ? null : nextQuery,
        status: nextStatus.isEmpty ? null : nextStatus,
        level: nextLevel.isEmpty ? null : nextLevel,
        sort: nextSort,
        limit: nextPageSize,
        offset: nextOffset,
      );
      if (!mounted || loadSerial != _loadSerial) return;
      setState(() {
        _page = page;
        _items = page.items;
      });
    } catch (e) {
      if (!mounted || loadSerial != _loadSerial) return;
      if (mounted) {
        setState(() => _error = _adminErrorMessage(e, '公告列表'));
      }
    }
    if (mounted && loadSerial == _loadSerial) setState(() => _loading = false);
  }

  void _applySearch() {
    _load(query: _searchCtrl.text.trim(), offset: 0);
  }

  Future<void> _openEdit({Map<String, dynamic>? item}) async {
    final titleCtrl = TextEditingController(
      text: (item?['title'] ?? '').toString(),
    );
    final bodyCtrl = TextEditingController(
      text: (item?['body'] ?? '').toString(),
    );
    String level = (item?['level'] ?? 'info').toString();
    bool published =
        (item?['published'] ?? 1) == 1 || item?['published'] == true;

    final saved = await showAppModalSheet<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AppModalSheet(
          title: item == null ? '新增公告' : '编辑公告',
          actions: _adminSheetActions(ctx),
          child: _adminSheetForm(
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              TextField(
                controller: bodyCtrl,
                maxLines: 6,
                decoration: const InputDecoration(labelText: '内容'),
              ),
              AppDropdownField<String>(
                initialValue: level,
                labelText: '级别',
                items: const [
                  DropdownMenuItem(value: 'info', child: Text('普通')),
                  DropdownMenuItem(value: 'warning', child: Text('警告')),
                  DropdownMenuItem(value: 'critical', child: Text('紧急')),
                ],
                onChanged: (v) => setSt(() => level = v ?? 'info'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: published,
                title: const Text('立即发布'),
                onChanged: (v) => setSt(() => published = v),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;
    try {
      if (item == null) {
        await widget.api.createAnnouncement(
          title: titleCtrl.text.trim(),
          body: bodyCtrl.text.trim(),
          level: level,
          published: published,
        );
      } else {
        await widget.api.updateAnnouncement(
          (item['id'] as num).toInt(),
          title: titleCtrl.text.trim(),
          body: bodyCtrl.text.trim(),
          level: level,
          published: published,
        );
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userVisibleApiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loadingFirstPage = _loading && _page == null;
    return Column(
      children: [
        AppSectionHeader(
          title: '公告列表',
          subtitle: _adminPageSummary(_page),
          actionLabel: '刷新',
          actionIcon: Icons.refresh,
          onAction: _loading ? null : () => _load(offset: _offset),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _openEdit(),
              icon: const Icon(Icons.add),
              label: const Text('发布公告'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索公告标题或正文',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空公告搜索',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchCtrl.clear();
                        _load(query: '', offset: 0);
                      },
                    ),
              isDense: true,
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _applySearch(),
          ),
        ),
        _AdminChipWrap(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          children: [
            _announcementStatusChip('全部状态', ''),
            _announcementStatusChip('已发布', 'published'),
            _announcementStatusChip('草稿', 'draft'),
          ],
        ),
        _AdminChipWrap(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          children: [
            _announcementLevelChip('全部级别', ''),
            _announcementLevelChip('普通', 'info'),
            _announcementLevelChip('重要', 'warning'),
            _announcementLevelChip('紧急', 'critical'),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: AppDropdownField<String>(
            initialValue: _sort,
            labelText: '公告排序',
            items: const [
              DropdownMenuItem(value: 'created_desc', child: Text('最新创建优先')),
              DropdownMenuItem(value: 'updated_desc', child: Text('最近更新优先')),
              DropdownMenuItem(value: 'level_desc', child: Text('紧急程度优先')),
              DropdownMenuItem(value: 'title_asc', child: Text('标题 A-Z')),
            ],
            onChanged: (value) =>
                _load(sort: value ?? 'created_desc', offset: 0),
          ),
        ),
        _AdminInlineLoadingIndicator(
          visible: _loading && _page != null,
          label: '正在更新公告列表',
        ),
        if (loadingFirstPage)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在加载公告列表…'),
                ],
              ),
            ),
          )
        else if (_error != null)
          Expanded(
            child: _AdminErrorState(
              message: _error!,
              onRetry: () => _load(offset: _offset),
            ),
          )
        else if (_items.isEmpty)
          const Expanded(
            child: EmptyState(
              icon: Icons.campaign_outlined,
              message: '当前筛选下没有公告。可调整关键词、发布状态或级别筛选，公告较多时使用底部分页查看。',
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(offset: _offset),
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final a = _items[i];
                  final published =
                      a['published'] == 1 || a['published'] == true;
                  final level = (a['level'] ?? 'info').toString();
                  final levelColor = switch (level) {
                    'critical' => cs.error,
                    'warning' => Colors.orange,
                    _ => cs.primary,
                  };
                  return _AdminListTileCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    isThreeLine: true,
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            (a['title'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: DesignTokens.fontWeightStrong,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        AppStatusBadge(
                          label: _adminStatusLabel(level),
                          color: levelColor,
                        ),
                        if (!published) ...[
                          const SizedBox(width: 6),
                          AppStatusBadge(
                            label: '草稿',
                            color: cs.onSurface.withValues(alpha: 0.58),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      '创建: ${a['created_at']} · 更新: ${a['updated_at'] ?? '-'} · 排序: ${_adminAnnouncementSortLabel(_sort)}\n${(a['body'] ?? '').toString()}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.64),
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) async {
                        switch (action) {
                          case 'edit':
                            await _openEdit(item: a);
                            return;
                          case 'toggle':
                            await widget.api.updateAnnouncement(
                              (a['id'] as num).toInt(),
                              published: !published,
                            );
                            await _load(offset: _offset);
                            return;
                          case 'delete':
                            final confirmed = await _confirmAdminDangerAction(
                              context: context,
                              title: '删除公告？',
                              message:
                                  '将删除“${(a['title'] ?? '').toString()}”，已发布用户也将不再看到这条公告。',
                            );
                            if (!confirmed) return;
                            await widget.api.deleteAnnouncement(
                              (a['id'] as num).toInt(),
                            );
                            await _load(
                              offset: _offsetAfterAdminDelete(
                                offset: _offset,
                                itemCount: _items.length,
                                pageSize: _pageSize,
                              ),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('公告已删除')),
                            );
                            return;
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: AppSecondaryMenuText('编辑'),
                        ),
                        PopupMenuItem(
                          value: 'toggle',
                          child: AppSecondaryMenuText(published ? '下架' : '发布'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: AppSecondaryMenuText('删除'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        _AdminPaginationBar(
          page: _page,
          loading: _loading,
          pageSize: _pageSize,
          onPageSizeChanged: (value) => _load(pageSize: value, offset: 0),
          onPrevious: () =>
              _load(offset: _previousAdminOffset(_offset, _pageSize)),
          onNext: () => _load(offset: _offset + _pageSize),
          onJumpToPage: (page) => _load(offset: (page - 1) * _pageSize),
        ),
      ],
    );
  }

  Widget _announcementStatusChip(String label, String value) {
    final selected = _status == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _load(status: value, offset: 0),
      ),
    );
  }

  Widget _announcementLevelChip(String label, String value) {
    final selected = _level == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _load(level: value, offset: 0),
      ),
    );
  }
}

// ====================================================================
// 反馈
// ====================================================================

class _FeedbackTab extends StatefulWidget {
  final AdminApi api;
  const _FeedbackTab({super.key, required this.api});
  @override
  State<_FeedbackTab> createState() => _FeedbackTabState();
}

class _FeedbackTabState extends State<_FeedbackTab> {
  List<Map<String, dynamic>> _items = [];
  AdminPage? _page;
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  String _filter = '';
  String _categoryFilter = '';
  String _query = '';
  String _sort = 'created_desc';
  int _pageSize = _adminPageSize;
  int _offset = 0;
  int _loadSerial = 0;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({
    int? offset,
    String? query,
    String? sort,
    int? pageSize,
  }) async {
    if (!mounted) return;
    final loadSerial = ++_loadSerial;
    final nextOffset = offset ?? _offset;
    final nextQuery = query ?? _query;
    final nextSort = sort ?? _sort;
    final nextPageSize = pageSize ?? _pageSize;
    _offset = nextOffset;
    _query = nextQuery;
    _sort = nextSort;
    _pageSize = nextPageSize;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.listFeedbackPage(
        status: _filter.isEmpty ? null : _filter,
        query: nextQuery.isEmpty ? null : nextQuery,
        category: _categoryFilter.isEmpty ? null : _categoryFilter,
        sort: nextSort,
        limit: nextPageSize,
        offset: nextOffset,
      );
      if (!mounted || loadSerial != _loadSerial) return;
      if (page.items.isEmpty && page.total > 0 && nextOffset > 0) {
        final lastOffset = _lastAdminOffset(
          total: page.total,
          pageSize: nextPageSize,
        );
        if (lastOffset != nextOffset) {
          await _load(offset: lastOffset);
          return;
        }
      }
      setState(() {
        _page = page;
        _items = page.items;
      });
    } catch (e) {
      if (!mounted || loadSerial != _loadSerial) return;
      if (mounted) {
        setState(() => _error = _adminErrorMessage(e, '反馈列表'));
      }
    }
    if (mounted && loadSerial == _loadSerial) setState(() => _loading = false);
  }

  void _applySearch() {
    _load(query: _searchCtrl.text.trim(), offset: 0);
  }

  List<int> get _currentPageOpenIds => _items
      .where((f) => (f['status'] ?? 'open').toString() == 'open')
      .map((f) => (f['id'] as num).toInt())
      .toList();

  List<int> _currentPageIdsWithStatus(String status) => _items
      .where((f) => (f['status'] ?? 'open').toString() == status)
      .map((f) => (f['id'] as num).toInt())
      .toList();

  Map<String, int> get _currentPageStatusCounts {
    final counts = <String, int>{
      'open': 0,
      'in_progress': 0,
      'resolved': 0,
      'closed': 0,
    };
    for (final f in _items) {
      final status = (f['status'] ?? 'open').toString();
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> _markCurrentPageOpenInProgress() async {
    await _bulkUpdateCurrentPageStatus(
      fromStatus: 'open',
      toStatus: 'in_progress',
      reply: '已收到，进入处理中。',
      successMessage: '已将当前页 {count} 条待处理反馈标记为处理中',
    );
  }

  Future<void> _bulkUpdateCurrentPageStatus({
    required String fromStatus,
    required String toStatus,
    required String reply,
    required String successMessage,
  }) async {
    final ids = _currentPageIdsWithStatus(fromStatus);
    if (ids.isEmpty) return;
    try {
      await widget.api.bulkUpdateFeedbackStatus(
        feedbackIds: ids,
        reply: reply,
        status: toStatus,
      );
      if (!mounted) return;
      await _load(offset: _offset);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage.replaceAll('{count}', '${ids.length}')),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userVisibleApiError(e))));
      }
    }
  }

  Future<void> _exportFilteredCsv() async {
    setState(() => _exporting = true);
    try {
      final csv = await widget.api.exportFeedbackCsv(
        status: _filter.isEmpty ? null : _filter,
        query: _query.isEmpty ? null : _query,
        category: _categoryFilter.isEmpty ? null : _categoryFilter,
        sort: _sort,
      );
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/duoyi_feedback_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
      await file.writeAsString(csv, flush: true);
      await Clipboard.setData(ClipboardData(text: file.path));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: '多仪管理员反馈导出',
          subject: '多仪反馈 CSV',
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('反馈 CSV 已导出，路径已复制：${file.path}')));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userVisibleApiError(e))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_adminActionErrorMessage(e, '导出反馈 CSV'))),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _reply(Map<String, dynamic> f) async {
    var replyText = (f['admin_reply'] ?? '').toString();
    String status = (f['status'] ?? 'resolved').toString();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AppDialog(
          title: const Text('回复反馈'),
          icon: const Icon(Icons.reply_outlined),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    (f['content'] ?? '').toString(),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: replyText,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '回复内容'),
                  onChanged: (value) => replyText = value,
                ),
                const SizedBox(height: 8),
                AppDropdownField<String>(
                  initialValue: status,
                  labelText: '处理状态',
                  items: const [
                    DropdownMenuItem(value: 'open', child: Text('待处理')),
                    DropdownMenuItem(value: 'in_progress', child: Text('处理中')),
                    DropdownMenuItem(value: 'resolved', child: Text('已解决')),
                    DropdownMenuItem(value: 'closed', child: Text('已关闭')),
                  ],
                  onChanged: (v) => setSt(() => status = v ?? status),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('提交'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      await widget.api.replyFeedback(
        feedbackId: (f['id'] as num).toInt(),
        reply: replyText.trim(),
        status: status,
      );
      if (!mounted) return;
      await _load(offset: _offset);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('反馈已回复')));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userVisibleApiError(e))));
      }
    }
  }

  Future<void> _showFeedbackDetail(Map<String, dynamic> feedback) async {
    if (!mounted) return;
    final summary = Map<String, dynamic>.from(feedback);
    final id = (feedback['id'] as num?)?.toInt();
    final detailFuture = id == null
        ? Future<Map<String, dynamic>>.value(summary)
        : widget.api
              .getFeedbackDetail(id)
              .then((remote) => <String, dynamic>{...summary, ...remote});
    await showDialog<void>(
      context: context,
      builder: (ctx) => FutureBuilder<Map<String, dynamic>>(
        future: detailFuture,
        initialData: summary,
        builder: (ctx, snapshot) {
          final detail = snapshot.data ?? summary;
          final loading = snapshot.connectionState != ConnectionState.done;
          final loadError = snapshot.hasError
              ? _adminActionErrorMessage(snapshot.error!, '加载反馈详情')
              : null;
          final status = (detail['status'] ?? 'open').toString();
          final category = (detail['category'] ?? '').toString();
          final username = (detail['username'] ?? '').toString();
          final displayName = (detail['display_name'] ?? '').toString();
          final email = (detail['email'] ?? '').toString();
          final emailVerified = detail['email_verified'] == true;
          final userLabel = displayName.trim().isNotEmpty
              ? displayName.trim()
              : username;
          final identity = [
            if (username.trim().isNotEmpty && username.trim() != userLabel)
              '@${username.trim()}',
            if (email.trim().isNotEmpty)
              '${email.trim()}${emailVerified ? ' (已验证)' : ' (未验证)'}',
          ].join(' · ');
          final createdAt = (detail['created_at'] ?? '').toString();
          final updatedAt = (detail['updated_at'] ?? '').toString();
          final content = (detail['content'] ?? '').toString();
          final adminReply = (detail['admin_reply'] ?? '').toString();
          return AppDialog(
            maxWidth: 720,
            icon: const Icon(Icons.feedback_outlined),
            title: const Text('反馈详情'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (loading) ...[
                      const LinearProgressIndicator(minHeight: 2),
                      const SizedBox(height: 12),
                    ],
                    if (loadError != null) ...[
                      Text(
                        '详情加载失败，已展示列表摘要：$loadError',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _AdminFeedbackDetailField(label: '用户', value: userLabel),
                    if (identity.isNotEmpty)
                      _AdminFeedbackDetailField(label: '账号', value: identity),
                    _AdminFeedbackDetailField(
                      label: '分类',
                      value: _feedbackCategoryLabel(category),
                    ),
                    _AdminFeedbackDetailField(
                      label: '状态',
                      value: _adminStatusLabel(status),
                    ),
                    if (createdAt.isNotEmpty)
                      _AdminFeedbackDetailField(label: '提交', value: createdAt),
                    if (updatedAt.isNotEmpty)
                      _AdminFeedbackDetailField(label: '更新', value: updatedAt),
                    const SizedBox(height: 4),
                    _AdminFeedbackDetailField(
                      label: '内容',
                      value: content,
                      multiline: true,
                    ),
                    if (adminReply.trim().isNotEmpty)
                      _AdminFeedbackDetailField(
                        label: '管理员回复',
                        value: adminReply,
                        multiline: true,
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _reply(detail);
                },
                child: const Text('回复'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteFeedback(
    Map<String, dynamic> f,
    String feedbackUserLabel,
  ) async {
    final confirmed = await _confirmAdminDangerAction(
      context: context,
      title: '删除反馈？',
      message: '将删除 $feedbackUserLabel 的这条反馈，删除后无法恢复。',
    );
    if (!confirmed) return;
    try {
      await widget.api.deleteFeedback((f['id'] as num).toInt());
      await _load(
        offset: _offsetAfterAdminDelete(
          offset: _offset,
          itemCount: _items.length,
          pageSize: _pageSize,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('反馈已删除')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userVisibleApiError(e))));
    }
  }

  Future<void> _closeFeedback(
    Map<String, dynamic> f,
    String feedbackUserLabel,
  ) async {
    final confirmed = await _confirmAdminDangerAction(
      context: context,
      title: '关闭反馈？',
      message: '将把 $feedbackUserLabel 的这条反馈标记为已关闭。',
      confirmLabel: '关闭',
    );
    if (!confirmed) return;
    try {
      final existingReply = (f['admin_reply'] ?? '').toString().trim();
      await widget.api.closeFeedback(
        (f['id'] as num).toInt(),
        reply: existingReply.isEmpty ? '已关闭。' : existingReply,
      );
      await _load(offset: _offset);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('反馈已关闭')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userVisibleApiError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loadingFirstPage = _loading && _page == null;
    final statusCounts = _currentPageStatusCounts;
    final openIds = _currentPageOpenIds;
    final inProgressIds = _currentPageIdsWithStatus('in_progress');
    final resolvedIds = _currentPageIdsWithStatus('resolved');
    final feedbackSummaryCard =
        !loadingFirstPage && _error == null && _items.isNotEmpty
        ? Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
            child: AppSurfaceCard(
              padding: const EdgeInsets.all(10),
              color: cs.primary.withValues(alpha: 0.08),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.18),
                width: 0.45,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.dashboard_customize_outlined,
                        color: cs.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '本页 ${_items.length} 条 · 待处理 ${statusCounts['open'] ?? 0} · 处理中 ${statusCounts['in_progress'] ?? 0} · 已解决 ${statusCounts['resolved'] ?? 0}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: DesignTokens.fontWeightStrong,
                                color: cs.onSurface,
                              ),
                            ),
                            Text(
                              '共 ${_page?.total ?? _items.length} 条反馈，当前按${_adminFeedbackSortLabel(_sort)}排列。大量反馈按状态、分类、搜索和分页拆开处理，也可导出当前筛选结果。',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.64),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '导出筛选结果',
                        onPressed: _loading || _exporting
                            ? null
                            : _exportFilteredCsv,
                        icon: _exporting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      if (openIds.isNotEmpty)
                        TextButton.icon(
                          onPressed: _loading
                              ? null
                              : _markCurrentPageOpenInProgress,
                          icon: const Icon(Icons.playlist_add_check_outlined),
                          label: const Text('本页待处理转处理中'),
                        ),
                      if (inProgressIds.isNotEmpty)
                        TextButton.icon(
                          onPressed: _loading
                              ? null
                              : () => _bulkUpdateCurrentPageStatus(
                                  fromStatus: 'in_progress',
                                  toStatus: 'resolved',
                                  reply: '已处理完成。',
                                  successMessage: '已将当前页 {count} 条处理中反馈标记为已解决',
                                ),
                          icon: const Icon(Icons.task_alt_outlined),
                          label: const Text('本页处理中转已解决'),
                        ),
                      if (resolvedIds.isNotEmpty)
                        TextButton.icon(
                          onPressed: _loading
                              ? null
                              : () => _bulkUpdateCurrentPageStatus(
                                  fromStatus: 'resolved',
                                  toStatus: 'closed',
                                  reply: '已归档关闭。',
                                  successMessage: '已将当前页 {count} 条已解决反馈关闭归档',
                                ),
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: const Text('本页已解决转关闭'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          )
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactAdminFilters = constraints.maxWidth < 720;
        final effectiveFeedbackSummaryCard = compactAdminFilters
            ? null
            : feedbackSummaryCard;
        final statusChips = [
          _filterChip('全部', ''),
          _filterChip('待处理', 'open'),
          _filterChip('处理中', 'in_progress'),
          _filterChip('已解决', 'resolved'),
          _filterChip('已关闭', 'closed'),
        ];
        final categoryChips = [
          _categoryChip(_feedbackCategoryLabel(''), ''),
          _categoryChip(_feedbackCategoryLabel('feature'), 'feature'),
          _categoryChip(_feedbackCategoryLabel('bug'), 'bug'),
          _categoryChip(_feedbackCategoryLabel('wish'), 'wish'),
          _categoryChip(_feedbackCategoryLabel('other'), 'other'),
        ];
        final paginationBar = _AdminPaginationBar(
          barKey: const ValueKey('admin_feedback_pagination'),
          page: _page,
          loading: _loading,
          pageSize: _pageSize,
          onPageSizeChanged: (value) => _load(pageSize: value, offset: 0),
          onPrevious: () =>
              _load(offset: _previousAdminOffset(_offset, _pageSize)),
          onNext: () => _load(offset: _offset + _pageSize),
          onJumpToPage: (page) => _load(offset: (page - 1) * _pageSize),
        );
        Widget feedbackBody() {
          if (loadingFirstPage) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在加载反馈列表…'),
                ],
              ),
            );
          }
          if (_error != null) {
            return _AdminErrorState(
              message: _error!,
              onRetry: () => _load(offset: _offset),
            );
          }
          if (_items.isEmpty) {
            return const EmptyState(
              icon: Icons.inbox_outlined,
              message: '当前筛选下没有反馈。反馈较多时请用底部分页查看其他页面，或切换处理状态和分类。',
            );
          }
          return RefreshIndicator(
            onRefresh: () => _load(offset: _offset),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              itemCount:
                  _items.length +
                  (effectiveFeedbackSummaryCard == null ? 0 : 1),
              itemBuilder: (_, i) {
                if (effectiveFeedbackSummaryCard != null && i == 0) {
                  return effectiveFeedbackSummaryCard;
                }
                final itemIndex = effectiveFeedbackSummaryCard == null
                    ? i
                    : i - 1;
                final f = _items[itemIndex];
                final status = (f['status'] ?? 'open').toString();
                final category = (f['category'] ?? '').toString();
                final username = (f['username'] ?? '').toString();
                final displayName = (f['display_name'] ?? '').toString();
                final email = (f['email'] ?? '').toString();
                final emailVerified = f['email_verified'] == true;
                final feedbackUserLabel = displayName.trim().isNotEmpty
                    ? displayName.trim()
                    : username;
                final feedbackIdentity = [
                  if (username.trim().isNotEmpty &&
                      username.trim() != feedbackUserLabel)
                    '@${username.trim()}',
                  if (email.trim().isNotEmpty)
                    '${email.trim()}${emailVerified ? ' (已验证)' : ' (未验证)'}',
                ].join(' · ');
                final statusColor = switch (status) {
                  'resolved' => Colors.green,
                  'closed' => Colors.grey,
                  'in_progress' => Colors.orange,
                  _ => cs.primary,
                };
                final reply = (f['admin_reply'] ?? '').toString();
                final createdAt = (f['created_at'] ?? '').toString();
                final metaLine = [
                  if (createdAt.isNotEmpty) createdAt,
                  if (feedbackIdentity.isNotEmpty) feedbackIdentity,
                ].join(' · ');
                final feedbackCard = AppSurfaceCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  border: _adminSubtleListBorder(context),
                  elevation: 0,
                  onTap: () => unawaited(_showFeedbackDetail(f)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${feedbackUserLabel.isEmpty ? '匿名用户' : feedbackUserLabel} · ${_feedbackCategoryLabel(category)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurface,
                                fontWeight: DesignTokens.fontWeightStrong,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          AppStatusBadge(
                            label: _adminStatusLabel(status),
                            color: statusColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                          ),
                        ],
                      ),
                      if (metaLine.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 4),
                          child: Text(
                            metaLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.52),
                            ),
                          ),
                        ),
                      Text(
                        (f['content'] ?? '').toString(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      if (reply.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.teal.withValues(alpha: 0.16),
                                width: 0.45,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.subdirectory_arrow_right,
                                  size: 16,
                                  color: Colors.teal,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '回复: $reply',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.68,
                                      ),
                                      fontWeight: DesignTokens.fontWeightStrong,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
                return _AdminFeedbackSwipeActions(
                  key: ValueKey('admin_feedback_swipe_${f['id']}'),
                  onDetail: () => unawaited(_showFeedbackDetail(f)),
                  onClose: () => _closeFeedback(f, feedbackUserLabel),
                  onReply: () => _reply(f),
                  onDelete: () => _deleteFeedback(f, feedbackUserLabel),
                  child: feedbackCard,
                );
              },
            ),
          );
        }

        return Column(
          children: [
            AppSectionHeader(
              title: '反馈列表',
              subtitle: _adminPageSummary(_page),
              actionLabel: '刷新',
              actionIcon: Icons.refresh,
              onAction: _loading ? null : () => _load(offset: _offset),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: '搜索反馈内容、回复或用户名',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空反馈搜索',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchCtrl.clear();
                            _load(query: '', offset: 0);
                          },
                        ),
                  isDense: true,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _applySearch(),
              ),
            ),
            compactAdminFilters
                ? _AdminCompactChipStrip(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    children: [...statusChips, ...categoryChips],
                  )
                : Column(
                    children: [
                      _AdminChipWrap(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                        children: statusChips,
                      ),
                      _AdminChipWrap(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        children: categoryChips,
                      ),
                    ],
                  ),
            LayoutBuilder(
              builder: (context, constraints) {
                final sortField = AppDropdownField<String>(
                  initialValue: _sort,
                  labelText: '反馈排序',
                  items: const [
                    DropdownMenuItem(
                      value: 'created_desc',
                      child: Text('最新反馈优先'),
                    ),
                    DropdownMenuItem(
                      value: 'updated_desc',
                      child: Text('最近处理优先'),
                    ),
                    DropdownMenuItem(value: 'status_asc', child: Text('待处理优先')),
                    DropdownMenuItem(value: 'user_asc', child: Text('用户 A-Z')),
                  ],
                  onChanged: (value) =>
                      _load(sort: value ?? 'created_desc', offset: 0),
                );
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: sortField,
                );
              },
            ),
            _AdminInlineLoadingIndicator(
              visible: _loading && _page != null,
              label: '正在更新反馈列表',
            ),
            Expanded(child: feedbackBody()),
            paginationBar,
          ],
        );
      },
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _filter = value);
          _load(offset: 0);
        },
      ),
    );
  }

  Widget _categoryChip(String label, String value) {
    final selected = _categoryFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _categoryFilter = value);
          _load(offset: 0);
        },
      ),
    );
  }
}

class _AdminFeedbackDetailField extends StatelessWidget {
  final String label;
  final String value;
  final bool multiline;

  const _AdminFeedbackDetailField({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: appSecondaryControlLabelStyle(
              context,
            ).copyWith(color: cs.onSurface.withValues(alpha: 0.58)),
          ),
          const SizedBox(height: 4),
          SelectionArea(
            child: Text(
              value,
              softWrap: true,
              overflow: TextOverflow.visible,
              style:
                  (multiline
                          ? theme.textTheme.bodyMedium
                          : theme.textTheme.bodySmall)
                      ?.copyWith(
                        color: cs.onSurface.withValues(
                          alpha: multiline ? 0.82 : 0.7,
                        ),
                        height: multiline ? 1.35 : 1.28,
                        fontWeight: DesignTokens.fontWeightStrong,
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminFeedbackSwipeActions extends StatefulWidget {
  final Widget child;
  final VoidCallback onDetail;
  final Future<void> Function() onClose;
  final Future<void> Function() onReply;
  final Future<void> Function() onDelete;

  const _AdminFeedbackSwipeActions({
    super.key,
    required this.child,
    required this.onDetail,
    required this.onClose,
    required this.onReply,
    required this.onDelete,
  });

  @override
  State<_AdminFeedbackSwipeActions> createState() =>
      _AdminFeedbackSwipeActionsState();
}

class _AdminFeedbackSwipeActionsState
    extends State<_AdminFeedbackSwipeActions> {
  static const double _actionRailWidth = 160;
  static const double _dragOpenThreshold = 40;
  double _dragDistance = 0;
  bool _open = false;

  void _setOpen(bool value) {
    if (_open == value) return;
    setState(() => _open = value);
  }

  void _resetDragDistance() {
    _dragDistance = 0;
  }

  Future<void> _runAction(Future<void> Function() action) async {
    _setOpen(false);
    await action();
  }

  void _showDetail() {
    _setOpen(false);
    widget.onDetail();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRect(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => _resetDragDistance(),
        onHorizontalDragUpdate: (details) {
          _dragDistance += details.delta.dx;
          if (_dragDistance <= -_dragOpenThreshold) _setOpen(true);
          if (_dragDistance >= _dragOpenThreshold) _setOpen(false);
        },
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -120) _setOpen(true);
          if (velocity > 120) _setOpen(false);
          _resetDragDistance();
        },
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (_open)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4, bottom: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: _actionRailWidth,
                      height: 42,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.94,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.18),
                            width: 0.45,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: cs.shadow.withValues(alpha: 0.04),
                              blurRadius: 7,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _AdminFeedbackSwipeButton(
                              tooltip: '查看反馈详情',
                              icon: Icons.visibility_outlined,
                              color: cs.primary,
                              onPressed: _showDetail,
                            ),
                            const SizedBox(width: 4),
                            _AdminFeedbackSwipeButton(
                              tooltip: '回复',
                              icon: Icons.reply_outlined,
                              color: cs.tertiary,
                              onPressed: () =>
                                  unawaited(_runAction(widget.onReply)),
                            ),
                            const SizedBox(width: 4),
                            _AdminFeedbackSwipeButton(
                              tooltip: '关闭',
                              icon: Icons.inventory_2_outlined,
                              color: cs.secondary,
                              onPressed: () =>
                                  unawaited(_runAction(widget.onClose)),
                            ),
                            const SizedBox(width: 4),
                            _AdminFeedbackSwipeButton(
                              tooltip: '删除',
                              icon: Icons.delete_outline,
                              color: cs.error,
                              onPressed: () =>
                                  unawaited(_runAction(widget.onDelete)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: _open ? -_actionRailWidth : 0),
              duration: AppMotion.feedback(context),
              curve: AppMotion.enterCurve,
              builder: (context, dx, child) =>
                  Transform.translate(offset: Offset(dx, 0), child: child),
              child: widget.child,
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminFeedbackSwipeButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _AdminFeedbackSwipeButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 36,
            child: Icon(icon, size: 17, color: color),
          ),
        ),
      ),
    );
  }
}

// ====================================================================
// 邀请码
// ====================================================================

class _InvitesTab extends StatefulWidget {
  final AdminApi api;
  const _InvitesTab({super.key, required this.api});
  @override
  State<_InvitesTab> createState() => _InvitesTabState();
}

class _InvitesTabState extends State<_InvitesTab> {
  List<Map<String, dynamic>> _codes = [];
  AdminPage? _page;
  bool _loading = true;
  String? _error;
  String _status = '';
  String _query = '';
  String _sort = 'created_desc';
  int _pageSize = _adminPageSize;
  int _offset = 0;
  int _loadSerial = 0;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({
    int? offset,
    String? status,
    String? query,
    String? sort,
    int? pageSize,
  }) async {
    final loadSerial = ++_loadSerial;
    final nextOffset = offset ?? _offset;
    final nextStatus = status ?? _status;
    final nextQuery = query ?? _query;
    final nextSort = sort ?? _sort;
    final nextPageSize = pageSize ?? _pageSize;
    _offset = nextOffset;
    _status = nextStatus;
    _query = nextQuery;
    _sort = nextSort;
    _pageSize = nextPageSize;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.listInviteCodesPage(
        query: nextQuery.isEmpty ? null : nextQuery,
        status: nextStatus.isEmpty ? null : nextStatus,
        sort: nextSort,
        limit: nextPageSize,
        offset: nextOffset,
      );
      if (!mounted || loadSerial != _loadSerial) return;
      setState(() {
        _page = page;
        _codes = page.items;
      });
    } catch (e) {
      if (!mounted || loadSerial != _loadSerial) return;
      if (mounted) {
        setState(() => _error = _adminErrorMessage(e, '邀请码列表'));
      }
    }
    if (mounted && loadSerial == _loadSerial) setState(() => _loading = false);
  }

  void _applySearch() {
    _load(query: _searchCtrl.text.trim(), offset: 0);
  }

  Future<void> _generate() async {
    int count = 5;
    String note = '';
    final ok = await showAppModalSheet<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AppModalSheet(
          title: '生成邀请码',
          actions: _adminSheetActions(ctx, saveLabel: '生成'),
          child: _adminSheetForm(
            children: [
              Row(
                children: [
                  const Text('数量:'),
                  Expanded(
                    child: Slider(
                      value: count.toDouble(),
                      min: 1,
                      max: 50,
                      divisions: 49,
                      label: '$count',
                      onChanged: (v) => setSt(() => count = v.toInt()),
                    ),
                  ),
                  Text('$count'),
                ],
              ),
              TextField(
                decoration: const InputDecoration(labelText: '备注 (可选)'),
                onChanged: (v) => note = v,
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    try {
      final codes = await widget.api.createInviteCodes(
        count: count,
        note: note,
      );
      await _load(offset: 0);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AppDialog(
          title: Text('已生成 ${codes.length} 个邀请码'),
          icon: const Icon(Icons.check_circle_outline),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              child: SelectableText(codes.join('\n')),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: codes.join('\n')));
                Navigator.pop(ctx);
              },
              child: const Text('复制并关闭'),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userVisibleApiError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loadingFirstPage = _loading && _page == null;
    return Column(
      children: [
        AppSectionHeader(
          title: '邀请码列表',
          subtitle: _adminPageSummary(_page),
          actionLabel: '刷新',
          actionIcon: Icons.refresh,
          onAction: _loading ? null : () => _load(offset: _offset),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.add),
              label: const Text('生成邀请码'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索邀请码、备注或使用者',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空邀请码搜索',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchCtrl.clear();
                        _load(query: '', offset: 0);
                      },
                    ),
              isDense: true,
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _applySearch(),
          ),
        ),
        _AdminChipWrap(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          children: [
            _inviteStatusChip('全部邀请码', ''),
            _inviteStatusChip('未使用', 'unused'),
            _inviteStatusChip('已使用', 'used'),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: AppDropdownField<String>(
            initialValue: _sort,
            labelText: '邀请码排序',
            items: const [
              DropdownMenuItem(value: 'created_desc', child: Text('最新生成优先')),
              DropdownMenuItem(value: 'used_desc', child: Text('最近使用优先')),
              DropdownMenuItem(value: 'code_asc', child: Text('邀请码 A-Z')),
              DropdownMenuItem(value: 'note_asc', child: Text('备注 A-Z')),
            ],
            onChanged: (value) =>
                _load(sort: value ?? 'created_desc', offset: 0),
          ),
        ),
        _AdminInlineLoadingIndicator(
          visible: _loading && _page != null,
          label: '正在更新邀请码列表',
        ),
        if (loadingFirstPage)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在加载邀请码列表…'),
                ],
              ),
            ),
          )
        else if (_error != null)
          Expanded(
            child: _AdminErrorState(
              message: _error!,
              onRetry: () => _load(offset: _offset),
            ),
          )
        else if (_codes.isEmpty)
          const Expanded(
            child: EmptyState(
              icon: Icons.vpn_key_outlined,
              message: '当前筛选下没有邀请码。可搜索邀请码、备注或使用者；邀请码较多时请用底部分页查看其他页面。',
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(offset: _offset),
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _codes.length,
                itemBuilder: (_, i) {
                  final c = _codes[i];
                  final used = (c['used_by'] ?? '').toString().isNotEmpty;
                  return _AdminListTileCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    leading: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: (used ? Colors.grey : Colors.blue).withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        used ? Icons.check_circle : Icons.key,
                        color: used ? Colors.grey : Colors.blue,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            c['code'].toString(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: DesignTokens.fontFamily,
                              fontWeight: DesignTokens.fontWeightStrong,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        AppStatusBadge(
                          label: used ? '已使用' : '未使用',
                          color: used ? Colors.grey : Colors.blue,
                        ),
                      ],
                    ),
                    subtitle: Text(
                      used
                          ? '已被 ${c['used_by_name'] ?? '?'} 使用 · ${c['used_at']} · 排序: ${_adminInviteSortLabel(_sort)}'
                          : '创建 ${c['created_at']} · 排序: ${_adminInviteSortLabel(_sort)}${(c['note'] ?? '').toString().isNotEmpty ? ' · ${c['note']}' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                    trailing: used
                        ? null
                        : IconButton(
                            tooltip: '删除',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final code = c['code'].toString();
                              final confirmed = await _confirmAdminDangerAction(
                                context: context,
                                title: '删除邀请码？',
                                message: '将删除未使用的邀请码 $code，删除后无法恢复。',
                              );
                              if (!confirmed) return;
                              await widget.api.deleteInviteCode(code);
                              await _load(
                                offset: _offsetAfterAdminDelete(
                                  offset: _offset,
                                  itemCount: _codes.length,
                                  pageSize: _pageSize,
                                ),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('邀请码已删除')),
                              );
                            },
                          ),
                  );
                },
              ),
            ),
          ),
        _AdminPaginationBar(
          page: _page,
          loading: _loading,
          pageSize: _pageSize,
          onPageSizeChanged: (value) => _load(pageSize: value, offset: 0),
          onPrevious: () =>
              _load(offset: _previousAdminOffset(_offset, _pageSize)),
          onNext: () => _load(offset: _offset + _pageSize),
          onJumpToPage: (page) => _load(offset: (page - 1) * _pageSize),
        ),
      ],
    );
  }

  Widget _inviteStatusChip(String label, String value) {
    final selected = _status == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _load(status: value, offset: 0),
      ),
    );
  }
}

// ====================================================================
// 审计日志
// ====================================================================

class _AuditLogTab extends StatefulWidget {
  final AdminApi api;
  const _AuditLogTab({super.key, required this.api});
  @override
  State<_AuditLogTab> createState() => _AuditLogTabState();
}

class _AuditLogTabState extends State<_AuditLogTab> {
  List<Map<String, dynamic>> _items = [];
  AdminPage? _page;
  bool _loading = true;
  String? _error;
  String _action = '';
  String _query = '';
  String _sort = 'created_desc';
  int _pageSize = _adminPageSize;
  int _offset = 0;
  int _loadSerial = 0;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({
    int? offset,
    String? action,
    String? query,
    String? sort,
    int? pageSize,
  }) async {
    final loadSerial = ++_loadSerial;
    final nextOffset = offset ?? _offset;
    final nextAction = action ?? _action;
    final nextQuery = query ?? _query;
    final nextSort = sort ?? _sort;
    final nextPageSize = pageSize ?? _pageSize;
    _offset = nextOffset;
    _action = nextAction;
    _query = nextQuery;
    _sort = nextSort;
    _pageSize = nextPageSize;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.auditLogPage(
        action: nextAction.isEmpty ? null : nextAction,
        query: nextQuery.isEmpty ? null : nextQuery,
        sort: nextSort,
        limit: nextPageSize,
        offset: nextOffset,
      );
      if (!mounted || loadSerial != _loadSerial) return;
      setState(() {
        _page = page;
        _items = page.items
            .where(
              (item) =>
                  adminAuditActionVisible((item['action'] ?? '').toString()),
            )
            .toList();
      });
    } catch (e) {
      if (!mounted || loadSerial != _loadSerial) return;
      if (mounted) {
        setState(() => _error = _adminErrorMessage(e, '审计日志'));
      }
    }
    if (mounted && loadSerial == _loadSerial) setState(() => _loading = false);
  }

  void _applySearch() {
    _load(query: _searchCtrl.text.trim(), offset: 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loadingFirstPage = _loading && _page == null;
    return Column(
      children: [
        AppSectionHeader(
          title: '审计日志',
          subtitle: _adminPageSummary(_page),
          actionLabel: '刷新',
          actionIcon: Icons.refresh,
          onAction: _loading ? null : () => _load(offset: _offset),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索管理员、操作、对象或详情',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空日志搜索',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchCtrl.clear();
                        _load(query: '', offset: 0);
                      },
                    ),
              isDense: true,
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _applySearch(),
          ),
        ),
        _AdminChipWrap(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          children: [
            _actionChip('全部操作', ''),
            _actionChip('更新用户', 'user.update'),
            _actionChip('公告', 'announcement.update'),
            _actionChip('回复反馈', 'feedback.reply'),
            _actionChip('邀请码', 'invite.create'),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: AppDropdownField<String>(
            initialValue: _sort,
            labelText: '日志排序',
            items: const [
              DropdownMenuItem(value: 'created_desc', child: Text('最新操作优先')),
              DropdownMenuItem(value: 'actor_asc', child: Text('管理员 A-Z')),
              DropdownMenuItem(value: 'action_asc', child: Text('操作类型 A-Z')),
              DropdownMenuItem(value: 'target_asc', child: Text('对象 A-Z')),
            ],
            onChanged: (value) =>
                _load(sort: value ?? 'created_desc', offset: 0),
          ),
        ),
        _AdminInlineLoadingIndicator(
          visible: _loading && _page != null,
          label: '正在更新审计日志',
        ),
        if (loadingFirstPage)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('正在加载审计日志…'),
                ],
              ),
            ),
          )
        else if (_error != null)
          Expanded(
            child: _AdminErrorState(
              message: _error!,
              onRetry: () => _load(offset: _offset),
            ),
          )
        else if (_items.isEmpty)
          const Expanded(
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              message: '当前筛选下没有审计日志。管理员操作较多时可搜索管理员、操作或对象，并使用底部分页查看。',
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(offset: _offset),
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final item = _items[i];
                  final action = (item['action'] ?? '').toString();
                  final actor = (item['actor_name'] ?? item['actor'] ?? '-')
                      .toString();
                  final target = adminVisibleDescription(item['target']);
                  final detail = adminVisibleAuditDetail(item['detail']);
                  final createdAt = (item['created_at'] ?? '').toString();
                  return _AdminListTileCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    leading: Icon(
                      Icons.receipt_long_outlined,
                      color: cs.primary,
                    ),
                    title: Text(
                      '${_auditActionLabel(action)} · $actor',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: DesignTokens.fontWeightStrong,
                      ),
                    ),
                    subtitle: Text(
                      [
                        if (createdAt.isNotEmpty) createdAt,
                        '排序: ${_adminAuditSortLabel(_sort)}',
                        if (target.isNotEmpty) '对象: $target',
                        if (detail.isNotEmpty) '详情: $detail',
                      ].join('\n'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.64),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        _AdminPaginationBar(
          page: _page,
          loading: _loading,
          pageSize: _pageSize,
          onPageSizeChanged: (value) => _load(pageSize: value, offset: 0),
          onPrevious: () =>
              _load(offset: _previousAdminOffset(_offset, _pageSize)),
          onNext: () => _load(offset: _offset + _pageSize),
          onJumpToPage: (page) => _load(offset: (page - 1) * _pageSize),
        ),
      ],
    );
  }

  Widget _actionChip(String label, String value) {
    final selected = _action == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _load(action: value, offset: 0),
      ),
    );
  }
}
