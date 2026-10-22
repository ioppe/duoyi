import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('管理员用户列表显示真实最近活跃和在线离线状态', () {
    final backend = File('backend/main.py').readAsStringSync();
    final adminScreen = File(
      'lib/screens/admin_screen.dart',
    ).readAsStringSync();

    expect(backend, contains('SESSION_ONLINE_SECONDS'));
    expect(backend, contains('last_active_at TEXT'));
    expect(backend, contains('def _utc_now_text()'));
    expect(backend, contains('UPDATE users SET last_active_at=?'));
    expect(backend, contains('VALUES(?,?,?,?)'));
    expect(
      backend,
      contains('UPDATE users SET last_login_at=?, last_active_at=? WHERE id=?'),
    );
    expect(backend, contains('def _has_recent_user_activity'));
    expect(
      backend,
      isNot(contains("last_login_at >= datetime('now','-7 days')")),
    );
    expect(backend, contains('u.last_login_at, u.last_active_at'));
    expect(backend, contains('"last_active_at": r["last_active_at"]'));
    expect(backend, contains('"online": r["id"] in online_user_ids'));

    expect(adminScreen, contains("u['last_login_at']"));
    expect(adminScreen, contains("u['last_active_at']"));
    expect(adminScreen, contains('text.replaceFirst'));
    expect(adminScreen, contains('hasTimezone'));
    expect(adminScreen, contains('_formatLastLogin'));
    expect(adminScreen, contains("online ? '在线' : '离线'"));
    expect(adminScreen, contains(r'最近登录: $lastLoginAt'));
    expect(adminScreen, contains(r'最近活跃: $lastActiveAt'));
    expect(adminScreen, contains('从未登录'));
    expect(adminScreen, contains('从未活跃'));
    expect(adminScreen, contains('Timer.periodic(_onlineRefreshInterval'));
    expect(adminScreen, contains('Duration(seconds: 60)'));
    expect(adminScreen, contains('isActive: _activeTabIndex == 4'));
    expect(adminScreen, contains('void _handleTabChanged()'));
    expect(adminScreen, contains('void _startOnlineRefreshTimer()'));
    expect(adminScreen, contains('void _stopOnlineRefreshTimer()'));
    expect(adminScreen, contains('!widget.isActive ||'));
    expect(adminScreen, contains('_backgroundRefreshInFlight'));
    expect(adminScreen, contains('_load(quiet: true, background: true)'));
    expect(
      adminScreen,
      contains('if (background && (_backgroundRefreshInFlight || _loading))'),
    );
    expect(
      adminScreen,
      contains('if (background) _backgroundRefreshInFlight = true;'),
    );
    expect(
      adminScreen,
      contains('if (background) _backgroundRefreshInFlight = false;'),
    );
  });

  test('管理员后台大数据列表使用分页 API 和分页文案', () {
    final adminScreen = File(
      'lib/screens/admin_screen.dart',
    ).readAsStringSync();
    final adminApi = File('lib/services/admin_api.dart').readAsStringSync();

    expect(adminApi, contains('class AdminPage'));
    expect(adminApi, contains('Future<AdminPage> listUsersPage'));
    expect(adminApi, contains('Future<AdminPage> listBackupsPage'));
    expect(adminApi, contains('Future<AdminPage> listServerBackupsPage'));
    expect(adminApi, contains('Future<String> exportBackupsCsv'));
    expect(adminApi, contains('Future<String> exportServerBackupsCsv'));
    expect(adminApi, contains("'/api/admin/backups/export.csv'"));
    expect(adminApi, contains("'/api/admin/server-backups/export.csv'"));
    expect(adminApi, contains('Future<AdminPage> listAnnouncementsPage'));
    expect(adminApi, contains('Future<AdminPage> listFeedbackPage'));
    expect(adminApi, contains('Future<AdminPage> listInviteCodesPage'));
    expect(adminApi, contains('Future<String> exportFeedbackCsv'));
    expect(adminApi, contains("'/api/admin/feedback/export.csv'"));
    expect(adminApi, contains('client.getText('));
    expect(adminApi, contains("'limit': limit"));
    expect(adminApi, contains("'offset': offset"));
    expect(
      adminApi,
      contains("params: {'q': query, 'status': status, 'sort': sort}"),
    );

    expect(adminScreen, contains('const int _adminPageSize = 20'));
    expect(adminScreen, contains('_AdminPaginationBar'));
    expect(adminScreen, contains(r'第 $start-$end 条 / 共 ${page.total} 条'));
    expect(adminScreen, contains('String _adminPageNumber(AdminPage? page)'));
    expect(adminScreen, contains(r'第 $current/$totalPages 页'));
    expect(adminScreen, contains('正在加载公告列表…'));
    expect(adminScreen, contains('正在加载反馈列表…'));
    expect(adminScreen, contains('正在加载邀请码列表…'));
    expect(adminScreen, contains('正在加载审计日志…'));
    expect(adminScreen, contains("hintText: '搜索文件名、状态、路径或详情'"));
    expect(adminScreen, contains("hintText: '搜索用户名、邮箱、昵称或用户 ID'"));
    expect(adminScreen, contains("hintText: '搜索用户名、邮箱、昵称或用户 ID'"));
    expect(adminScreen, contains("tooltip: '清空服务器备份搜索'"));
    expect(adminScreen, contains("tooltip: '清空用户备份搜索'"));
    expect(adminScreen, contains('Future<void> _exportBackupsCsv()'));
    expect(adminScreen, contains('Future<void> _exportServerBackupsCsv()'));
    expect(adminScreen, contains('widget.api.exportBackupsCsv('));
    expect(adminScreen, contains('widget.api.exportServerBackupsCsv('));
    expect(adminScreen, contains("prefix: 'duoyi_backups'"));
    expect(adminScreen, contains("prefix: 'duoyi_server_backups'"));
    expect(
      adminScreen,
      contains("actionLabel: _exportingBackups ? '导出中…' : '导出筛选结果'"),
    );
    expect(
      adminScreen,
      contains("actionLabel: _exportingServerBackups ? '导出中…' : '导出筛选结果'"),
    );
    expect(adminScreen, contains("labelText: '服务器备份排序'"));
    expect(adminScreen, contains("labelText: '用户备份排序'"));
    expect(adminScreen, contains("_serverBackupStatusChip('已上传', 'uploaded')"));
    expect(adminScreen, contains("_backupStatusChip('已有快照', 'synced')"));
    expect(adminScreen, contains("_userFilterChip('在线', 'online')"));
    expect(
      adminScreen,
      contains("_userFilterChip('邮箱未验证', 'unverified_email')"),
    );
    expect(adminScreen, contains("_userFilterChip('有反馈', 'has_feedback')"));
    expect(adminScreen, contains("online: _onlineFilter(nextStatus)"));
    expect(adminScreen, contains("status: _backendStatusFilter(nextStatus)"));
    expect(adminScreen, contains("value: 'email_asc'"));
    expect(adminScreen, contains("value: 'version_desc'"));
    expect(adminScreen, contains('serverBackupPageSize: value'));
    expect(adminScreen, contains('backupPageSize: value'));
    expect(adminScreen, contains('_adminServerBackupSortLabel'));
    expect(adminScreen, contains('_adminBackupSortLabel'));
    expect(adminScreen, contains('公告较多时使用底部分页查看'));
    expect(adminScreen, contains('当前筛选下没有反馈'));
    expect(adminScreen, contains('反馈较多时请用底部分页查看其他页面'));
    expect(adminScreen, contains('切换处理状态和分类'));
    expect(adminScreen, contains('Future<void> _exportFilteredCsv()'));
    expect(adminScreen, contains('widget.api.exportFeedbackCsv('));
    expect(adminScreen, contains("tooltip: '导出筛选结果'"));
    expect(adminScreen, contains('SharePlus.instance.share'));
    expect(adminScreen, contains('duoyi_feedback_'));
    expect(adminScreen, contains('也可导出当前筛选结果'));
    expect(adminScreen, contains('邀请码较多时请用底部分页查看其他页面'));
    expect(adminScreen, contains('搜索邀请码、备注或使用者'));
    expect(adminScreen, contains('搜索管理员、操作、对象或详情'));
    expect(adminScreen, contains("tooltip: '清空邀请码搜索'"));
    expect(adminScreen, contains("tooltip: '清空日志搜索'"));
    expect(
      adminScreen,
      contains('query: nextQuery.isEmpty ? null : nextQuery'),
    );
    expect(adminScreen, contains('删除公告？'));
    expect(adminScreen, contains('删除反馈？'));
    expect(adminScreen, contains('删除邀请码？'));
    expect(adminScreen, contains("label: const Text('发布公告')"));
    expect(adminScreen, contains("label: const Text('生成邀请码')"));
    expect(adminScreen, isNot(contains('floatingActionButton:')));
    expect(adminScreen, isNot(contains('FloatingActionButton.extended')));
    expect(adminScreen, contains("'每页'"));
    expect(adminScreen, contains("label: '每页'"));
    expect(adminScreen, contains("label: '页码'"));
    expect(adminScreen, contains('class _AdminPaginationLabeledControl'));
    expect(adminScreen, contains('constraints.maxWidth < 720'));
    expect(adminScreen, isNot(contains('constraints.maxWidth < 520')));
    expect(
      adminScreen,
      contains("key: const ValueKey('admin_compact_pagination_full_width')"),
    );
    expect(
      adminScreen,
      contains('crossAxisAlignment: CrossAxisAlignment.stretch'),
    );
    expect(adminScreen, contains('Wrap('));
    expect(adminScreen, contains('WrapAlignment.spaceBetween'));
    expect(adminScreen, contains('width: 76'));
    expect(adminScreen, contains('width: 54'));
    expect(adminScreen, contains('maxWidth: 300'));
    expect(adminScreen, contains('maxWidth: 300'));
    expect(adminScreen, contains('fromLTRB(10, 4, 10, 4)'));
    expect(
      adminScreen,
      contains("'\${_adminPageSummary(page)} · \${_adminPageNumber(page)}'"),
    );
    expect(adminScreen, contains('class _AdminChipWrap'));
    final chipWrapStart = adminScreen.indexOf('class _AdminChipWrap');
    final chipWrapEnd = adminScreen.indexOf('class _AdminCompactChipStrip');
    expect(chipWrapStart, greaterThanOrEqualTo(0));
    expect(chipWrapEnd, greaterThan(chipWrapStart));
    final chipWrap = adminScreen.substring(chipWrapStart, chipWrapEnd);
    expect(
      chipWrap,
      contains('Wrap('),
      reason: '标签条用 Wrap 随内容宽度自然换行，标签宽度由共享样式决定，不写死局部宽度。',
    );
    expect(chipWrap, contains('spacing: 8'));
    expect(chipWrap, contains('runSpacing: 6'));
    expect(chipWrap, contains('children: children'));
    expect(
      chipWrap,
      isNot(contains('textWidth.clamp')),
      reason: '标签宽度由共享样式决定，组件内不再局部测量文本宽度。',
    );
    expect(adminScreen, isNot(contains('width: 92')));
    expect(
      RegExp(r'_AdminChipWrap\(').allMatches(adminScreen).length,
      greaterThanOrEqualTo(8),
    );
    final scrollableDialogs = RegExp(
      r'content:\s+SingleChildScrollView\(',
    ).allMatches(adminScreen).length;
    final sharedScrollableSheets = RegExp(
      r'\bAppModalSheet\(',
    ).allMatches(adminScreen).length;
    expect(
      scrollableDialogs + sharedScrollableSheets,
      greaterThanOrEqualTo(4),
      reason: '管理员表单通过共享弹层或自带滚动的对话框保持内容可达，共享弹层不再嵌套第二层滚动。',
    );
    expect(adminScreen, contains('Widget navButton({'));
    expect(adminScreen, contains('iconSize: 16'));
    expect(adminScreen, isNot(contains('admin_compact_pagination_inline')));
    expect(adminScreen, isNot(contains('compactHasPageShortcuts')));
    expect(adminScreen, isNot(contains('Expanded(child: previousButton)')));
    expect(adminScreen, isNot(contains('Expanded(child: nextButton)')));
    expect(
      adminScreen,
      isNot(contains('minimumSize: const WidgetStatePropertyAll')),
    );
    expect(adminScreen, contains('dimension: 32'));
    expect(adminScreen, isNot(contains('dimension: 26')));
    expect(adminScreen, isNot(contains('height: 22')));
    expect(adminScreen, isNot(contains('dimension: 22')));
    expect(adminScreen, isNot(contains('width: 124')));
    expect(adminScreen, contains('minHeight: 32'));
    expect(adminScreen, isNot(contains('minHeight: 26')));
    expect(adminScreen, contains('class _AdminGlassControlTheme'));
    expect(adminScreen, contains('selectedFill'));
    expect(adminScreen, contains('glassControlFill'));
    expect(adminScreen, contains("message: '分页导航'"));
    expect(adminScreen, contains("message: '跳到第一页'"));
    expect(adminScreen, contains("message: '上一页'"));
    expect(adminScreen, contains("message: '下一页'"));
    expect(adminScreen, contains("message: '跳到最后一页'"));
    expect(adminScreen, contains('onJumpToPage'));
    expect(adminScreen, isNot(contains("label: const Text('上一页')")));
    expect(adminScreen, isNot(contains("label: const Text('下一页')")));
    expect(adminScreen, contains("tooltip: '回复'"));
    expect(adminScreen, contains("tooltip: '删除'"));
    expect(adminScreen, contains("tooltip: '查看反馈详情'"));
    expect(adminScreen, contains('if (_open)'));
    expect(adminScreen, isNot(contains('Matrix4.translationValues')));
    expect(adminScreen, contains('static const double _actionRailWidth'));
    expect(
      adminScreen,
      contains('const List<int> _adminPageSizeOptions = [20, 50, 100, 200]'),
    );
    expect(adminScreen, contains('items: _adminPageSizeOptions'));
    expect(adminScreen, contains('DropdownMenuItem(value: v'));
    expect(adminScreen, contains('widget.api.listAnnouncementsPage'));
    expect(adminScreen, contains('widget.api.listFeedbackPage'));
    expect(adminScreen, contains('widget.api.listInviteCodesPage'));
    expect(adminScreen, contains('widget.api.auditLogPage'));
    expect(adminScreen, contains('公告排序'));
    expect(adminScreen, contains('反馈排序'));
    expect(adminScreen, contains('邀请码排序'));
    expect(adminScreen, contains('日志排序'));
    expect(adminScreen, contains('最近更新优先'));
    expect(adminScreen, contains('最近处理优先'));
    expect(adminScreen, contains('最近使用优先'));
    expect(adminScreen, contains('操作类型 A-Z'));
    expect(adminScreen, contains('本页处理中转已解决'));
    expect(adminScreen, contains('本页已解决转关闭'));
    expect(adminScreen, contains('_adminAnnouncementSortLabel'));
    expect(adminScreen, contains('_adminFeedbackSortLabel'));
    expect(adminScreen, contains('_adminInviteSortLabel'));
    expect(adminScreen, contains('_adminAuditSortLabel'));
    expect(adminScreen, contains('_feedbackCategoryLabel(category)'));
    expect(adminScreen, contains('_categoryChip(_feedbackCategoryLabel'));
    expect(adminScreen, contains('_inviteStatusChip'));
    expect(adminScreen, contains('_offsetAfterAdminDelete'));
  });

  test('管理员反馈 CSV 导出使用当前筛选并做表格公式防护', () {
    final backend = File('backend/main.py').readAsStringSync();

    expect(backend, contains('@app.get("/api/admin/feedback/export.csv")'));
    expect(backend, contains('def export_feedback_csv'));
    expect(backend, contains('_feedback_admin_filters('));
    expect(backend, contains('_feedback_admin_order_by(sort)'));
    expect(backend, contains('email_verified'));
    expect(backend, contains('sync_version'));
    expect(backend, contains('has_snapshot'));
    expect(backend, contains('status == "has_feedback"'));
    expect(backend, contains('status == "unverified_email"'));
    expect(backend, contains('"email_asc"'));
    expect(backend, contains('"version_desc"'));
    expect(backend, contains('limit: int = Query(5000, ge=1, le=20000)'));
    expect(backend, contains('"Content-Disposition"'));
    expect(backend, contains('"X-Total-Count"'));
    expect(backend, contains('"X-Exported-Count"'));
    expect(backend, contains('"feedback.export"'));
    expect(backend, contains('def _csv_safe(value)'));
    expect(
      backend,
      contains('text[0] in ("=", "+", "-", "@", "\\t", "\\r", "\\n")'),
    );
    expect(backend, contains('writer.writerow('));
    expect(backend, contains('text/csv; charset=utf-8'));
  });
}
