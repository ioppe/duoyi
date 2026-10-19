import '../core/app_clock.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/design_tokens.dart';
import '../core/notification_history_policy.dart';
import '../core/platform_info.dart';
import '../core/report_reminder_config.dart';
import '../models/goal.dart' show ReminderKind;
import '../providers/notification_service.dart';
import '../providers/preferences_provider.dart';
import '../services/alarm_service.dart';
import '../services/local_notifications.dart';
import '../services/notification_permission_exception.dart';
import '../services/notification_settings.dart';
import '../services/notification_status_bar_sync_bridge.dart';
import '../services/native_reminder_ringtone.dart';
import '../services/reminder_ringtone_settings.dart';
import '../services/reminder_scheduler.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';
import 'today_detail_router.dart';

enum _NotificationReadFilter { all, unread, read }

const double _notificationSettingsContentMaxWidth = 760;

class NotificationHistoryScreen extends StatefulWidget {
  /// 兼容旧路由参数；通知记录现在只通过用户手动操作标记已读。
  final bool markReadOnOpen;

  const NotificationHistoryScreen({super.key, this.markReadOnOpen = false});

  @override
  State<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState extends State<NotificationHistoryScreen> {
  static const _pageSize = 50;

  final _searchCtrl = TextEditingController();
  NotificationType? _typeFilter;
  _NotificationReadFilter _readFilter = _NotificationReadFilter.all;
  int _page = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _resetPaging() {
    _page = 0;
  }

  /// 通知类型 → 可跳转详情页的 section 映射。
  ///
  /// 只有 todo / habit / anniversary 关联到可打开的详情页；
  /// pomodoro / general / location 没有对应详情页，点击保持"只切换已读"。
  static TodaySectionKind? _relatedSectionKind(NotificationType type) {
    switch (type) {
      case NotificationType.todo:
        return TodaySectionKind.todos;
      case NotificationType.habit:
        return TodaySectionKind.habits;
      case NotificationType.anniversary:
        return TodaySectionKind.anniversaries;
      case NotificationType.pomodoro:
      case NotificationType.general:
      case NotificationType.location:
        return null;
    }
  }

  /// 点击卡片打开关联对象详情：先把这条记录标为已读，再跳转。
  ///
  /// - 关联对象已被删除时由 [TodayDetailRouter] 的空态兜底页承接，不会黑屏；
  /// - 已读记录同样可以点击跳转（[NotificationService.markHistoryItemRead]
  ///   对已读记录是幂等空操作）。
  Future<void> _openRelatedItem(NotificationItem item) async {
    final kind = _relatedSectionKind(item.type);
    final relatedId = item.relatedId;
    if (kind == null || relatedId == null || relatedId.trim().isEmpty) return;
    await context.read<NotificationService>().markHistoryItemRead(
      item.id,
      read: true,
    );
    if (!mounted) return;
    await TodayDetailRouter.open(context, kind, id: relatedId);
  }

  List<NotificationItem> _filteredHistory(List<NotificationItem> history) {
    final query = _searchCtrl.text.trim().toLowerCase();
    return history
        .where((item) {
          if (_typeFilter != null && item.type != _typeFilter) return false;
          if (_readFilter == _NotificationReadFilter.unread && item.isRead) {
            return false;
          }
          if (_readFilter == _NotificationReadFilter.read && !item.isRead) {
            return false;
          }
          if (query.isEmpty) return true;
          return item.title.toLowerCase().contains(query) ||
              item.body.toLowerCase().contains(query) ||
              (item.relatedId ?? '').toLowerCase().contains(query) ||
              _notificationTypeLabel(item.type).toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _confirmClearHistory(int count) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('清空通知记录？'),
        icon: const Icon(Icons.delete_outline),
        content: Text('将清空当前保留的 $count 条通知记录，已调度的提醒不会被取消。'),
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
    if (confirmed != true || !mounted) return;
    await context.read<NotificationService>().clearHistory();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('通知记录已清空'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final service = context.watch<NotificationService>();
    final history = service.history;
    final filteredHistory = _filteredHistory(history);
    final totalPages = filteredHistory.isEmpty
        ? 1
        : ((filteredHistory.length - 1) ~/ _pageSize) + 1;
    final currentPage = _page.clamp(0, totalPages - 1).toInt();
    if (currentPage != _page) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _page = currentPage);
      });
    }
    final pageStart = currentPage * _pageSize;
    final pageEnd = (pageStart + _pageSize)
        .clamp(0, filteredHistory.length)
        .toInt();
    final visibleHistory = filteredHistory.sublist(pageStart, pageEnd);
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final hasPager = filteredHistory.length > _pageSize;

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: const Text('通知记录'),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        actions: [
          if (service.unreadCount > 0)
            IconButton(
              key: const ValueKey('notification_history_mark_all_read_button'),
              tooltip: '全部标为已读',
              onPressed: () => service.markAllHistoryRead(),
              icon: const Icon(Icons.mark_email_read_outlined),
            ),
          IconButton(
            tooltip: '清空通知记录',
            onPressed: history.isEmpty
                ? null
                : () => _confirmClearHistory(history.length),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: AppSecondaryControlTheme(
        child: history.isEmpty
            ? const Center(child: Text('暂无通知记录'))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    child: _NotificationHistoryFilters(
                      searchCtrl: _searchCtrl,
                      typeFilter: _typeFilter,
                      readFilter: _readFilter,
                      historyCount: history.length,
                      filteredCount: filteredHistory.length,
                      page: currentPage + 1,
                      totalPages: totalPages,
                      unreadCount: service.unreadCount,
                      onSearchChanged: (_) => setState(_resetPaging),
                      onClearSearch: () {
                        _searchCtrl.clear();
                        setState(_resetPaging);
                      },
                      onTypeChanged: (type) => setState(() {
                        _typeFilter = type;
                        _resetPaging();
                      }),
                      onReadFilterChanged: (filter) => setState(() {
                        _readFilter = filter;
                        _resetPaging();
                      }),
                    ),
                  ),
                  Expanded(
                    child: filteredHistory.isEmpty
                        ? const EmptyState(
                            icon: Icons.manage_search_outlined,
                            message: '没有匹配的通知记录',
                          )
                        : ListView.separated(
                            padding: EdgeInsets.fromLTRB(
                              12,
                              6,
                              12,
                              hasPager ? 12 : 24 + bottomInset,
                            ),
                            itemCount: visibleHistory.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = visibleHistory[index];
                              final relatedKind = _relatedSectionKind(
                                item.type,
                              );
                              final hasRelatedTarget =
                                  relatedKind != null &&
                                  (item.relatedId?.trim().isNotEmpty ?? false);
                              return _NotificationRecordCard(
                                key: ValueKey('notification_record_${item.id}'),
                                item: item,
                                onToggleRead: () => service.markHistoryItemRead(
                                  item.id,
                                  read: !item.isRead,
                                ),
                                onOpenRelated: hasRelatedTarget
                                    ? () => _openRelatedItem(item)
                                    : null,
                              );
                            },
                          ),
                  ),
                  if (hasPager)
                    Padding(
                      padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottomInset),
                      child: Row(
                        children: [
                          Text(
                            '${pageStart + 1}-$pageEnd / ${filteredHistory.length}',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const Spacer(),
                          IconButton.outlined(
                            tooltip: '上一页',
                            onPressed: currentPage == 0
                                ? null
                                : () => setState(() => _page = currentPage - 1),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            tooltip: '下一页',
                            onPressed: currentPage >= totalPages - 1
                                ? null
                                : () => setState(() => _page = currentPage + 1),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _NotificationHistoryFilters extends StatelessWidget {
  final TextEditingController searchCtrl;
  final NotificationType? typeFilter;
  final _NotificationReadFilter readFilter;
  final int historyCount;
  final int filteredCount;
  final int page;
  final int totalPages;
  final int unreadCount;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<NotificationType?> onTypeChanged;
  final ValueChanged<_NotificationReadFilter> onReadFilterChanged;

  const _NotificationHistoryFilters({
    required this.searchCtrl,
    required this.typeFilter,
    required this.readFilter,
    required this.historyCount,
    required this.filteredCount,
    required this.page,
    required this.totalPages,
    required this.unreadCount,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onTypeChanged,
    required this.onReadFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索标题、内容或关联 ID',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchCtrl.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      icon: const Icon(Icons.close),
                      onPressed: onClearSearch,
                    ),
              isDense: true,
            ),
            textInputAction: TextInputAction.search,
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _historyTypeChip('全部', null, typeFilter, onTypeChanged),
                for (final type in NotificationType.values)
                  _historyTypeChip(
                    _notificationTypeLabel(type),
                    type,
                    typeFilter,
                    onTypeChanged,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_NotificationReadFilter>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _NotificationReadFilter.all,
                  label: Text('全部'),
                ),
                ButtonSegment(
                  value: _NotificationReadFilter.unread,
                  label: Text('未读'),
                ),
                ButtonSegment(
                  value: _NotificationReadFilter.read,
                  label: Text('已读'),
                ),
              ],
              selected: {readFilter},
              onSelectionChanged: (values) =>
                  onReadFilterChanged(values.single),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            filteredCount == historyCount
                ? '共 $historyCount 条 · 未读 $unreadCount 条 · 支持搜索、筛选和分页浏览 · 第 $page / $totalPages 页 · 每页 ${_NotificationHistoryScreenState._pageSize} 条'
                : '已筛出 $filteredCount / $historyCount 条 · 未读 $unreadCount 条 · 第 $page / $totalPages 页',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.58),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyTypeChip(
    String label,
    NotificationType? type,
    NotificationType? selected,
    ValueChanged<NotificationType?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected == type,
        onSelected: (_) => onChanged(type),
      ),
    );
  }
}

class _NotificationRecordCard extends StatelessWidget {
  final NotificationItem item;
  final VoidCallback onToggleRead;

  /// 非空时点击卡片跳到关联对象详情（todo / habit / anniversary）；
  /// 为空时回退为原有的"点击只切换已读"。
  final VoidCallback? onOpenRelated;

  const _NotificationRecordCard({
    super.key,
    required this.item,
    required this.onToggleRead,
    this.onOpenRelated,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _notificationColor(item.type);
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      color: item.isRead ? null : cs.primary.withValues(alpha: 0.06),
      border: item.isRead
          ? null
          : Border.all(color: cs.primary.withValues(alpha: 0.22), width: 0.45),
      onTap: onOpenRelated ?? (item.isRead ? null : onToggleRead),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _notificationIcon(item.type),
                  size: 20,
                  color: color,
                ),
              ),
              if (!item.isRead)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: cs.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.normal,
                        color: cs.onSurface,
                      ),
                    ),
                    AppStatusBadge(
                      label: _notificationTypeLabel(item.type),
                      color: color,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                    ),
                    AppStatusBadge(
                      label: item.isRead ? '已读' : '未读',
                      color: item.isRead ? cs.onSurfaceVariant : cs.error,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                    ),
                  ],
                ),
                if (item.body.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.body,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.66),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  _formatNotificationTime(item.scheduledTime),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.48),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: item.isRead ? '标为未读' : '标为已读',
            onPressed: onToggleRead,
            icon: Icon(
              item.isRead
                  ? Icons.mark_email_unread_outlined
                  : Icons.mark_email_read_outlined,
            ),
          ),
        ],
      ),
    );
  }
}

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  int? _pendingPushCount;
  int? _pendingAlarmCount;
  bool? _exactAlarmGranted;
  Map<String, NotificationChannelStatus>? _channelStatuses;
  List<ReminderScheduleSnapshotEntry> _registeredReminders =
      const <ReminderScheduleSnapshotEntry>[];
  bool _busy = false;
  int _statusBarPreferenceGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_refreshStatus());
    });
  }

  Future<void> _refreshStatus() async {
    final service = context.read<NotificationService>();
    final scheduler = context.read<ReminderScheduler?>();
    setState(() => _busy = true);
    try {
      await service.refreshPermission();
      final pendingIds = await service.pendingIds();
      await AlarmService.instance.init();
      final pendingAlarmIds = await _safePendingAlarmIds();
      final exactAlarmGranted = await AlarmService.instance
          .hasExactAlarmPermission();
      final channelStatuses =
          await NotificationSettings.notificationChannelStatuses(const [
            NotificationService.channelId,
            AlarmService.channelId,
            NativeReminderRingtone.statusChannelId,
            NativeReminderRingtone.fallbackChannelId,
          ]);
      final registeredReminders =
          await scheduler?.registeredRemindersSnapshot() ??
          const <ReminderScheduleSnapshotEntry>[];
      if (!mounted) return;
      setState(() {
        _pendingPushCount = pendingIds.length;
        _pendingAlarmCount = pendingAlarmIds.length;
        _exactAlarmGranted = exactAlarmGranted;
        _channelStatuses = channelStatuses;
        _registeredReminders = registeredReminders;
      });
    } catch (e, st) {
      debugPrint('[NotificationSettings] refresh status failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('通知状态读取失败，请稍后重试或打开系统通知设置检查。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<int>> _safePendingAlarmIds() async {
    try {
      return await AlarmService.instance.pendingIds();
    } catch (e, st) {
      debugPrint('[NotificationSettings] pending alarm probe failed: $e\n$st');
      return const <int>[];
    }
  }

  Future<void> _requestPermission() async {
    try {
      final granted = await context
          .read<NotificationService>()
          .requestPermission();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(granted ? '通知权限已开启' : '通知权限未开启'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _refreshStatus();
    } catch (e, st) {
      debugPrint('[NotificationSettings] request permission failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('通知权限请求失败，请前往系统设置手动开启。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _requestExactAlarmPermission() async {
    try {
      final granted = await AlarmService.instance.requestExactAlarmPermission();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(granted ? '精准闹钟权限已开启' : '精准闹钟权限未开启，闹钟可能延后或降级'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _refreshStatus();
    } catch (e, st) {
      debugPrint('[NotificationSettings] exact alarm request failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('精准闹钟权限请求失败，请前往系统设置手动开启。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _setNotificationStatusBarPreference({
    required bool quickAdd,
    required bool value,
  }) async {
    final prefs = context.read<PreferencesProvider>();
    final generation = ++_statusBarPreferenceGeneration;
    final previousValue = quickAdd
        ? prefs.notificationQuickAdd
        : prefs.notificationTodayProgress;
    setState(() => _busy = true);
    try {
      if (quickAdd) {
        await prefs.setNotificationQuickAdd(value);
      } else {
        await prefs.setNotificationTodayProgress(value);
      }
      final synced = await _syncNotificationStatusBarNow(
        requestIfNeeded: value,
      );
      if (!mounted) return;
      if (generation != _statusBarPreferenceGeneration) return;
      if (synced) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? I18n.tr('preferences.notification_status_bar.enabled')
                  : I18n.tr('preferences.notification_status_bar.disabled'),
            ),
          ),
        );
        return;
      }
      final stillMatchesThisRequest = quickAdd
          ? prefs.notificationQuickAdd == value
          : prefs.notificationTodayProgress == value;
      if (stillMatchesThisRequest) {
        if (quickAdd) {
          await prefs.setNotificationQuickAdd(previousValue);
        } else {
          await prefs.setNotificationTodayProgress(previousValue);
        }
      } else {
        debugPrint(
          '[NotificationSettings] stale status bar sync failure ignored; '
          'latest local preference already changed.',
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            I18n.tr('preferences.notification_status_bar.sync_failed'),
          ),
        ),
      );
    } finally {
      if (mounted && generation == _statusBarPreferenceGeneration) {
        setState(() => _busy = false);
      }
    }
  }

  Future<bool> _syncNotificationStatusBarNow({
    bool requestIfNeeded = false,
  }) async {
    try {
      return await NotificationStatusBarSyncBridge.sync(
        force: true,
        requestIfNeeded: requestIfNeeded,
      );
    } on NotificationPermissionDeniedException catch (e) {
      debugPrint('[NotificationSettings] status bar permission denied: $e');
      return false;
    } catch (e, st) {
      debugPrint('[NotificationSettings] status bar sync failed: $e\n$st');
      return false;
    }
  }

  Future<void> _sendTest() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<NotificationService>().sendTest();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('测试通知已发送'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _refreshStatus();
    } on NotificationPermissionDeniedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('通知权限未开启，无法发送测试通知'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } catch (e, st) {
      debugPrint('[NotificationSettings] send test failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('测试通知发送失败，请检查通知权限和渠道设置。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendScheduledTest() async {
    final kind = _scheduledTestReminderKind(context);
    await _sendScheduledDiagnostic(kind: kind);
  }

  Future<void> _sendScheduledPushTest() {
    return _sendScheduledDiagnostic(kind: ReminderKind.push);
  }

  Future<void> _sendScheduledPopupTest() {
    return _sendScheduledDiagnostic(kind: ReminderKind.popup);
  }

  Future<void> _sendScheduledAlarmTest() {
    return _sendScheduledDiagnostic(
      kind: ReminderKind.alarm,
      fullScreenAlarm: false,
    );
  }

  Future<void> _sendScheduledFullScreenAlarmTest() {
    return _sendScheduledDiagnostic(kind: ReminderKind.alarm);
  }

  Future<void> _sendScheduledDiagnostic({
    required ReminderKind kind,
    bool fullScreenAlarm = true,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final service = context.read<NotificationService>();
      final scheduler = context.read<ReminderScheduler?>();
      final granted = await service.requestPermission();
      if (!granted) {
        throw const NotificationPermissionDeniedException();
      }
      if (kind == ReminderKind.alarm) {
        await AlarmService.instance.init();
        final exactAlarmGranted =
            await AlarmService.instance.hasExactAlarmPermission() ||
            await AlarmService.instance.requestExactAlarmPermission();
        debugPrint(
          '[NotificationSettings] scheduled alarm exact permission: '
          '$exactAlarmGranted',
        );
        if (fullScreenAlarm) {
          final fullScreenGranted =
              await AlarmService.instance.hasFullScreenIntentPermission() ||
              await AlarmService.instance.requestFullScreenIntentPermission();
          debugPrint(
            '[NotificationSettings] scheduled alarm fullscreen permission: '
            '$fullScreenGranted',
          );
        }
      }
      await service.sendScheduledTest(
        reminderKind: kind,
        fullScreenAlarm: fullScreenAlarm,
        popup: scheduler?.popup,
        alarm: scheduler?.alarm,
      );
      if (!mounted) return;
      final label = _diagnosticKindLabel(
        kind,
        fullScreenAlarm: fullScreenAlarm,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已注册 1 分钟后的$label测试'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _refreshStatus();
    } on NotificationPermissionDeniedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('通知权限未开启，无法注册定时测试'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } catch (e, st) {
      debugPrint('[NotificationSettings] scheduled test failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('定时测试注册失败，请检查通知和精确闹钟权限。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _diagnosticKindLabel(
    ReminderKind kind, {
    bool fullScreenAlarm = true,
  }) {
    return switch (DailyReminderSlot.normalizeKind(kind)) {
      ReminderKind.popup => '弹出/后台兜底提醒',
      ReminderKind.alarm => fullScreenAlarm ? '锁屏全屏闹钟提醒' : '闹钟提醒',
      ReminderKind.push || ReminderKind.email || ReminderKind.off => '普通定时通知',
    };
  }

  ReminderKind _scheduledTestReminderKind(BuildContext context) {
    final prefs = context.read<PreferencesProvider?>();
    final slots = prefs?.dailyReminderSlots ?? const <DailyReminderSlot>[];
    for (final slot in slots) {
      final kind = DailyReminderSlot.normalizeKind(slot.kind);
      if (slot.enabled && kind != ReminderKind.off) return kind;
    }
    return ReminderKind.push;
  }

  Future<void> _sendStrongTest() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final service = context.read<NotificationService>();
      final notificationGranted = await service.requestPermission();
      await AlarmService.instance.init();
      final exactAlarmGranted =
          await AlarmService.instance.hasExactAlarmPermission() ||
          await AlarmService.instance.requestExactAlarmPermission();
      final fullScreenGranted =
          await AlarmService.instance.hasFullScreenIntentPermission() ||
          await AlarmService.instance.requestFullScreenIntentPermission();
      await AlarmService.instance.showFullScreenTest();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _strongTestMessage(
              notificationGranted: notificationGranted,
              exactAlarmGranted: exactAlarmGranted,
              fullScreenGranted: fullScreenGranted,
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _refreshStatus();
    } on NotificationPermissionDeniedException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('通知权限未开启，强提醒可能没有停止按钮'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } catch (e, st) {
      debugPrint('[NotificationSettings] strong test failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('强提醒测试启动失败，请检查通知、闹钟和后台运行权限。'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSystemSettings([String? channelId]) async {
    final opened =
        (channelId != null &&
            await NotificationSettings.openNotificationChannelSettings(
              channelId,
            )) ||
        await NotificationSettings.openAppNotificationSettings() ||
        await openAppSettings();
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('无法打开系统通知设置'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _strongTestMessage({
    required bool notificationGranted,
    required bool exactAlarmGranted,
    required bool fullScreenGranted,
  }) {
    final missing = <String>[
      if (!notificationGranted) '通知权限',
      if (!exactAlarmGranted) '精准闹钟权限',
      if (!fullScreenGranted) '全屏提醒权限',
    ];
    if (missing.isEmpty) {
      return '强提醒测试已启动，可在通知上手动停止响铃';
    }
    return '强提醒测试已启动；仍需开启${missing.join('、')}，否则闹钟、全屏或停止按钮可能异常。';
  }

  NotificationChannelStatus? _channelStatus(String channelId) {
    return _channelStatuses?[channelId];
  }

  String _channelStatusLabel(String channelId) {
    final status = _channelStatus(channelId);
    if (_channelStatuses == null) return _busy ? '检测中' : '未检测';
    if (status == null || !status.exists) return '未创建';
    if (status.isBlocked) return '已关闭';
    if (_channelRequiresSound(channelId) && status.isSilent) return '已静音';
    if (status.isLowImportance) return '提醒弱';
    return '声音正常';
  }

  Color _channelStatusColor(String channelId, ColorScheme cs) {
    final status = _channelStatus(channelId);
    if (_channelStatuses == null || status == null || !status.exists) {
      return cs.onSurfaceVariant;
    }
    if (status.isBlocked) return cs.error;
    if (_channelRequiresSound(channelId) && status.isSilent) {
      return Colors.deepOrange;
    }
    if (status.isLowImportance) return Colors.amber.shade800;
    return Colors.green;
  }

  bool _channelRequiresSound(String channelId) =>
      channelId != NativeReminderRingtone.statusChannelId;

  String _channelSubtitle(String base, String channelId) {
    return '$base · ${_channelStatusLabel(channelId)}';
  }

  Widget _channelStatusTrailing(String channelId, ColorScheme cs) {
    return Row(
      key: ValueKey('notification_channel_status_$channelId'),
      mainAxisSize: MainAxisSize.min,
      children: [
        AppStatusBadge(
          label: _channelStatusLabel(channelId),
          color: _channelStatusColor(channelId, cs),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        ),
        const SizedBox(width: 6),
        Icon(
          Icons.chevron_right,
          size: 18,
          color: cs.onSurface.withValues(alpha: 0.38),
        ),
      ],
    );
  }

  ButtonStyle _settingsTextActionStyle(
    BuildContext context, {
    Color? color,
    bool plain = false,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tone = color ?? cs.primary;
    return TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const Size(0, 30),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      foregroundColor: tone,
      disabledForegroundColor: cs.onSurfaceVariant.withValues(alpha: 0.44),
      backgroundColor: plain
          ? Colors.transparent
          : tone.withValues(alpha: 0.08),
      disabledBackgroundColor: plain
          ? Colors.transparent
          : cs.surfaceContainerHighest.withValues(alpha: 0.18),
      shape: const StadiumBorder(),
      textStyle: appSecondaryMenuItemTextStyle(
        context,
      ).copyWith(color: tone, fontSize: DesignTokens.fontSizeSm),
    );
  }

  Widget _settingsIconAction(
    BuildContext context, {
    required Key key,
    required String tooltip,
    required VoidCallback? onPressed,
    IconData icon = Icons.refresh,
    bool busy = false,
    bool embedded = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final button = IconButton(
      key: key,
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 17),
    );
    if (embedded) return button;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.22),
          width: 0.45,
        ),
      ),
      child: button,
    );
  }

  Widget _settingsActionGroup(BuildContext context, List<Widget> children) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.24),
          width: 0.45,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _settingsActionDivider(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 0.6,
      height: 16,
      color: cs.outlineVariant.withValues(alpha: 0.45),
    );
  }

  String _registeredReminderSummary() {
    if (_registeredReminders.isEmpty) {
      return _busy ? '正在读取提醒注册表' : '暂无通过提醒调度器注册的提醒';
    }
    final objectCount = _registeredReminders.length;
    return '$objectCount 个提醒对象，点查看核对任务详情';
  }

  Future<void> _showRegisteredReminderDetails() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const RegisteredRemindersScreen(),
      ),
    );
    if (!mounted) return;
    // 返回后刷新通知设置页上的“已注册提醒”摘要计数。
    await _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();
    final service = context.watch<NotificationService>();
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: const Text('通知设置'),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 52,
      ),
      body: AppSecondaryControlTheme(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            key: const ValueKey('notification_settings_content'),
            constraints: const BoxConstraints(
              maxWidth: _notificationSettingsContentMaxWidth,
            ),
            child: RefreshIndicator(
              onRefresh: _refreshStatus,
              child: CustomScrollView(
                key: const ValueKey('notification_settings_scroll_view'),
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                slivers: [
                  SliverSafeArea(
                    top: false,
                    bottom: true,
                    sliver: SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                      sliver: SliverList.list(
                        children: [
                          AppSurfaceCard(
                            padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
                            border: Border.all(
                              color: cs.outlineVariant.withValues(alpha: 0.12),
                              width: 0.35,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: cs.primary.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.notifications_active_outlined,
                                    color: cs.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '通知设置',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontSize: DesignTokens
                                                  .fontSizeCardTitle,
                                              fontWeight: DesignTokens
                                                  .fontWeightRegular,
                                            ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '系统权限、提醒时间、铃声和通知记录保留',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: cs.onSurface.withValues(
                                                alpha: 0.64,
                                              ),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          AppSettingsSection(
                            title: '系统通知',
                            subtitle: service.permissionGranted
                                ? '通知权限已开启'
                                : '通知权限未开启',
                            children: [
                              AppSettingsTile(
                                key: const ValueKey(
                                  'notification_permission_tile',
                                ),
                                icon: service.permissionGranted
                                    ? Icons.check_circle_outline
                                    : Icons.notifications_off_outlined,
                                color: service.permissionGranted
                                    ? Colors.green
                                    : Colors.red,
                                title: '通知权限',
                                subtitle: service.permissionGranted
                                    ? '系统允许多仪发送提醒'
                                    : '开启后才能收到普通通知和提醒',
                                trailing: TextButton(
                                  style: _settingsTextActionStyle(
                                    context,
                                    color: service.permissionGranted
                                        ? cs.primary
                                        : cs.error,
                                  ),
                                  onPressed: _busy ? null : _requestPermission,
                                  child: Text(
                                    service.permissionGranted ? '重新检查' : '开启',
                                  ),
                                ),
                              ),
                              AppSettingsTile(
                                icon: Icons.settings_outlined,
                                color: Colors.deepOrange,
                                title: '普通提醒渠道',
                                subtitle: _channelSubtitle(
                                  '检查普通通知的声音、横幅和锁屏权限',
                                  NotificationService.channelId,
                                ),
                                trailing: _channelStatusTrailing(
                                  NotificationService.channelId,
                                  cs,
                                ),
                                onTap: () => _openSystemSettings(
                                  NotificationService.channelId,
                                ),
                              ),
                              AppSettingsTile(
                                icon: Icons.alarm_on_outlined,
                                color: Colors.deepPurple,
                                title: '强提醒渠道',
                                subtitle: _channelSubtitle(
                                  '检查闹钟提醒的声音、横幅和全屏展示权限',
                                  AlarmService.channelId,
                                ),
                                trailing: _channelStatusTrailing(
                                  AlarmService.channelId,
                                  cs,
                                ),
                                onTap: () =>
                                    _openSystemSettings(AlarmService.channelId),
                              ),
                              AppSettingsTile(
                                icon: Icons.alt_route_outlined,
                                color: Colors.indigo,
                                title: '闹钟降级兜底',
                                subtitle: _channelSubtitle(
                                  '强提醒或内置铃声注册失败时会改用普通提醒；普通提醒渠道静音，兜底也可能无声',
                                  NativeReminderRingtone.fallbackChannelId,
                                ),
                                trailing: _channelStatusTrailing(
                                  NativeReminderRingtone.fallbackChannelId,
                                  cs,
                                ),
                                onTap: () => _openSystemSettings(
                                  NativeReminderRingtone.fallbackChannelId,
                                ),
                              ),
                              AppSettingsTile(
                                icon: Icons.music_note_outlined,
                                color: Colors.pink,
                                title: '内置铃声状态渠道',
                                subtitle: _channelSubtitle(
                                  '检查内置铃声前台状态通知是否被静音或屏蔽',
                                  NativeReminderRingtone.statusChannelId,
                                ),
                                trailing: _channelStatusTrailing(
                                  NativeReminderRingtone.statusChannelId,
                                  cs,
                                ),
                                onTap: () => _openSystemSettings(
                                  NativeReminderRingtone.statusChannelId,
                                ),
                              ),
                              AppSettingsTile(
                                icon: Icons.notifications_active_outlined,
                                color: cs.primary,
                                title: '立即发送测试通知',
                                subtitle: '验证普通通知渠道是否可见、可响铃',
                                onTap: _busy ? null : _sendTest,
                              ),
                              AppSettingsTile(
                                icon: Icons.schedule_send_outlined,
                                color: Colors.cyan,
                                title: '1 分钟后普通定时',
                                subtitle: '验证系统定时调度链路，到点应收到普通通知',
                                onTap: _busy ? null : _sendScheduledPushTest,
                              ),
                              AppSettingsTile(
                                icon: Icons.open_in_new_outlined,
                                color: Colors.teal,
                                title: '1 分钟后弹出测试',
                                subtitle: '前台直接弹窗；后台或锁屏时使用系统通知兜底',
                                onTap: _busy ? null : _sendScheduledPopupTest,
                              ),
                              AppSettingsTile(
                                icon: Icons.alarm_outlined,
                                color: Colors.amber.shade800,
                                title: '1 分钟后闹钟测试',
                                subtitle: '验证闹钟响铃和通知停止链路，不强制全屏遮挡',
                                onTap: _busy ? null : _sendScheduledAlarmTest,
                              ),
                              AppSettingsTile(
                                icon: Icons.fullscreen_outlined,
                                color: Colors.deepOrange,
                                title: '1 分钟后全屏闹钟',
                                subtitle: '锁屏或后台应全屏唤起，并同时响铃震动',
                                onTap: _busy
                                    ? null
                                    : _sendScheduledFullScreenAlarmTest,
                              ),
                              AppSettingsTile(
                                icon: Icons.rule_folder_outlined,
                                color: Colors.blueGrey,
                                title: '1 分钟后默认方式',
                                subtitle: '按每日提醒里当前启用的提醒方式注册一次测试',
                                onTap: _busy ? null : _sendScheduledTest,
                              ),
                              AppSettingsTile(
                                icon: Icons.alarm_on_outlined,
                                color: Colors.deepOrange,
                                title: '测试强提醒铃声',
                                subtitle: '验证闹钟提醒、内置铃声和通知停止按钮',
                                onTap: _busy ? null : _sendStrongTest,
                              ),
                              AppSettingsTile(
                                key: const ValueKey(
                                  'notification_pending_push_tile',
                                ),
                                icon: Icons.schedule,
                                color: Colors.teal,
                                title: '已调度普通提醒',
                                subtitle: _pendingPushCount == null
                                    ? '正在读取待触发队列'
                                    : '$_pendingPushCount 条待触发',
                                trailing: _settingsIconAction(
                                  context,
                                  key: const ValueKey(
                                    'notification_pending_push_refresh_button',
                                  ),
                                  tooltip: '刷新',
                                  onPressed: _busy ? null : _refreshStatus,
                                  busy: _busy,
                                ),
                              ),
                              AppSettingsTile(
                                key: const ValueKey(
                                  'notification_pending_alarm_tile',
                                ),
                                icon: Icons.alarm_on_outlined,
                                color: Colors.deepPurple,
                                title: '已调度闹钟提醒',
                                subtitle: _pendingAlarmCount == null
                                    ? '正在读取强提醒队列'
                                    : '$_pendingAlarmCount 条待触发 · ${_exactAlarmGranted == true ? '精准闹钟已开启' : '精准闹钟未开启'}',
                                trailing: TextButton(
                                  key: const ValueKey(
                                    'notification_pending_alarm_exact_button',
                                  ),
                                  style: _settingsTextActionStyle(
                                    context,
                                    color: Colors.deepPurple,
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : _requestExactAlarmPermission,
                                  child: const Text('精准闹钟'),
                                ),
                              ),
                              AppSettingsTile(
                                key: const ValueKey(
                                  'notification_registered_reminders_tile',
                                ),
                                icon: Icons.fact_check_outlined,
                                color: Colors.indigo,
                                title: '已注册提醒明细',
                                subtitle: _registeredReminderSummary(),
                                trailing: KeyedSubtree(
                                  key: const ValueKey(
                                    'notification_registered_reminders_actions',
                                  ),
                                  child: _settingsActionGroup(context, [
                                    TextButton(
                                      key: const ValueKey(
                                        'notification_registered_reminders_view_button',
                                      ),
                                      style: _settingsTextActionStyle(
                                        context,
                                        plain: true,
                                      ),
                                      onPressed: _showRegisteredReminderDetails,
                                      child: const Text('查看'),
                                    ),
                                    _settingsActionDivider(context),
                                    _settingsIconAction(
                                      context,
                                      key: const ValueKey(
                                        'notification_registered_reminders_refresh_button',
                                      ),
                                      tooltip: '刷新',
                                      onPressed: _busy ? null : _refreshStatus,
                                      embedded: true,
                                    ),
                                  ]),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          AppSettingsSection(
                            title: '提醒入口',
                            subtitle: '控制由通知触发的快捷记录和历史保留',
                            children: [
                              if (PlatformInfo.isAndroid) ...[
                                AppSettingsTile(
                                  key: const ValueKey(
                                    'notification_quick_add_tile',
                                  ),
                                  icon: Icons.add_alert_outlined,
                                  color: Colors.orange,
                                  title: I18n.tr(
                                    'preferences.notification_quick_add.title',
                                  ),
                                  subtitle: I18n.tr(
                                    'preferences.notification_quick_add.subtitle',
                                  ),
                                  trailing: _CompactSettingsSwitch(
                                    key: const ValueKey(
                                      'notification_quick_add_switch',
                                    ),
                                    value: prefs.notificationQuickAdd,
                                    onChanged: _busy
                                        ? null
                                        : (value) =>
                                              _setNotificationStatusBarPreference(
                                                quickAdd: true,
                                                value: value,
                                              ),
                                  ),
                                  onTap: _busy
                                      ? null
                                      : () =>
                                            _setNotificationStatusBarPreference(
                                              quickAdd: true,
                                              value:
                                                  !prefs.notificationQuickAdd,
                                            ),
                                ),
                                AppSettingsTile(
                                  key: const ValueKey(
                                    'notification_today_progress_tile',
                                  ),
                                  icon: Icons.today_outlined,
                                  color: Colors.teal,
                                  title: I18n.tr(
                                    'preferences.notification_today_progress.title',
                                  ),
                                  subtitle: I18n.tr(
                                    'preferences.notification_today_progress.subtitle',
                                  ),
                                  trailing: _CompactSettingsSwitch(
                                    key: const ValueKey(
                                      'notification_today_progress_switch',
                                    ),
                                    value: prefs.notificationTodayProgress,
                                    onChanged: _busy
                                        ? null
                                        : (value) =>
                                              _setNotificationStatusBarPreference(
                                                quickAdd: false,
                                                value: value,
                                              ),
                                  ),
                                  onTap: _busy
                                      ? null
                                      : () =>
                                            _setNotificationStatusBarPreference(
                                              quickAdd: false,
                                              value: !prefs
                                                  .notificationTodayProgress,
                                            ),
                                ),
                              ] else
                                AppSettingsTile(
                                  icon: Icons.notifications_none_outlined,
                                  color: Colors.blueGrey,
                                  title: I18n.tr(
                                    'preferences.notification_status_bar.title',
                                  ),
                                  subtitle: I18n.tr(
                                    'preferences.notification_status_bar.unsupported',
                                  ),
                                ),
                              _NotificationHistoryEntryTile(
                                historyCount: service.historyCount,
                                unreadCount: service.unreadCount,
                                onOpen: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const NotificationHistoryScreen(
                                          markReadOnOpen: false,
                                        ),
                                  ),
                                ),
                              ),
                              AppSettingsTile(
                                key: const ValueKey(
                                  'notification_history_limit_tile',
                                ),
                                icon: Icons.inventory_2_outlined,
                                color: Colors.indigo,
                                title: '通知记录保留',
                                subtitle:
                                    '最多保留 ${prefs.notificationHistoryLimit} 条历史，调低后会裁剪旧记录',
                                trailing: AppCompactDropdown<int>(
                                  key: const ValueKey(
                                    'notification_history_limit_dropdown',
                                  ),
                                  value: prefs.notificationHistoryLimit,
                                  width: 116,
                                  items: [
                                    for (final value
                                        in NotificationHistoryPolicy.options)
                                      DropdownMenuItem(
                                        value: value,
                                        child: Text('$value 条'),
                                      ),
                                  ],
                                  onChanged: (value) async {
                                    if (value == null) return;
                                    final prefProvider = context
                                        .read<PreferencesProvider>();
                                    final notif = context
                                        .read<NotificationService>();
                                    await prefProvider
                                        .setNotificationHistoryLimit(value);
                                    await notif.setHistoryLimit(
                                      prefProvider.notificationHistoryLimit,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          AppSettingsSection(
                            title: I18n.tr(
                              'preferences.section.daily_reminder',
                            ),
                            subtitle: I18n.tr(
                              'preferences.section.daily_reminder.subtitle',
                            ),
                            children: [
                              for (
                                var i = 0;
                                i < prefs.dailyReminderSlots.length;
                                i++
                              )
                                _NotificationReminderSlotTile(
                                  index: i,
                                  slot: prefs.dailyReminderSlots[i],
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const _NotificationRingtoneSection(),
                          const SizedBox(height: 12),
                          const _ReportReminderSection(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RegisteredReminderDetailRow extends StatelessWidget {
  final ReminderScheduleSnapshotEntry entry;

  /// 是否已进入系统提醒队列；null 表示不展示生效状态徽标。
  final bool? active;

  const _RegisteredReminderDetailRow({required this.entry, this.active});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final typeLabel = _registeredReminderTypeLabel(entry.objectType);
    final systemCount = entry.idCount;
    final title = _registeredReminderDisplayTitle(entry, typeLabel);
    final subtitle = _registeredReminderDisplaySubtitle(entry, typeLabel);
    return Container(
      key: ValueKey('registered_reminder_detail_${entry.objectKey}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.22),
          width: 0.4,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppStatusBadge(
            label: typeLabel,
            color: _registeredReminderTypeColor(entry.objectType, cs),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '提醒事项：$title',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.normal,
                          height: 1.16,
                        ),
                      ),
                    ),
                    if (active != null) ...[
                      const SizedBox(width: 6),
                      AppStatusBadge(
                        label: active! ? '生效中' : '未生效',
                        color: active! ? Colors.green : cs.error,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '提醒规则：$subtitle',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.52),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '待触发提醒：$systemCount 条',
                  softWrap: true,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.66),
                    height: 1.22,
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

enum _RegisteredReminderStatus { active, inactive, all }

/// 已注册提醒明细独立页：支持按生效状态过滤与分页浏览。
///
/// “生效中”表示该提醒的系统通知 id 仍在系统队列里、到点会触发；“未生效”表示
/// 调度器登记了但系统队列里查不到（常见于权限被收回或被系统清理），可据此排查
/// “到点没提醒”的问题。
class RegisteredRemindersScreen extends StatefulWidget {
  final Future<Set<int>> Function()? pendingQueueLoader;

  const RegisteredRemindersScreen({super.key, this.pendingQueueLoader});

  @override
  State<RegisteredRemindersScreen> createState() =>
      _RegisteredRemindersScreenState();
}

class _RegisteredRemindersScreenState extends State<RegisteredRemindersScreen> {
  static const _pageSize = 20;

  bool _loading = true;
  List<ReminderScheduleSnapshotEntry> _entries =
      const <ReminderScheduleSnapshotEntry>[];
  Set<int> _systemQueueIds = <int>{};
  // 系统队列是否成功读取；读取失败/超时时无法判定生效状态，按“生效中”处理，
  // 避免把实际已注册的提醒误标成“未生效”。
  bool _queueResolved = false;
  _RegisteredReminderStatus _status = _RegisteredReminderStatus.active;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _queueResolved = false;
    });
    final scheduler = context.read<ReminderScheduler?>();
    final entries =
        await scheduler?.registeredRemindersSnapshot() ??
        const <ReminderScheduleSnapshotEntry>[];
    if (!mounted) return;
    // 注册表来自内存，立即渲染；系统队列可能涉及较慢的平台调用，放到后台解析，
    // 解析完成前所有已注册提醒先按“生效中”展示，避免页面长时间空转。
    setState(() {
      _entries = entries;
      _loading = false;
      _page = 0;
    });
    unawaited(_resolveSystemQueue());
  }

  Future<void> _resolveSystemQueue() async {
    final customLoader = widget.pendingQueueLoader;
    if (customLoader != null) {
      try {
        final queue = await customLoader();
        if (!mounted) return;
        setState(() {
          _systemQueueIds = queue;
          _queueResolved = true;
        });
      } catch (e, st) {
        debugPrint('[RegisteredReminders] custom pending ids failed: $e\n$st');
        if (!mounted) return;
        setState(() {
          _systemQueueIds = <int>{};
          _queueResolved = false;
        });
      }
      return;
    }

    final queue = <int>{};
    var queueResolved = true;
    Future<List<int>> guarded(Future<List<int>> Function() read) async {
      try {
        return await read();
      } catch (e, st) {
        debugPrint('[RegisteredReminders] pending ids read failed: $e\n$st');
        queueResolved = false;
        return const <int>[];
      }
    }

    queue.addAll(await guarded(() => LocalNotifications.instance.pendingIds()));
    queue.addAll(await guarded(() => AlarmService.instance.pendingIds()));
    if (!mounted) return;
    setState(() {
      _systemQueueIds = queue;
      _queueResolved = queueResolved;
    });
  }

  bool _isActive(ReminderScheduleSnapshotEntry entry) =>
      !_queueResolved || entry.ids.any(_systemQueueIds.contains);

  List<ReminderScheduleSnapshotEntry> get _filtered {
    switch (_status) {
      case _RegisteredReminderStatus.active:
        return _entries.where(_isActive).toList(growable: false);
      case _RegisteredReminderStatus.inactive:
        return _entries
            .where((entry) => !_isActive(entry))
            .toList(growable: false);
      case _RegisteredReminderStatus.all:
        return _entries;
    }
  }

  void _setStatus(_RegisteredReminderStatus status) {
    if (_status == status) return;
    setState(() {
      _status = status;
      _page = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final filtered = _filtered;
    final activeCount = _entries.where(_isActive).length;
    final inactiveCount = _entries.length - activeCount;

    final totalPages = filtered.isEmpty
        ? 1
        : ((filtered.length - 1) ~/ _pageSize) + 1;
    final currentPage = _page.clamp(0, totalPages - 1).toInt();
    final pageStart = currentPage * _pageSize;
    final pageEnd = (pageStart + _pageSize).clamp(0, filtered.length).toInt();
    final visible = filtered.isEmpty
        ? const <ReminderScheduleSnapshotEntry>[]
        : filtered.sublist(pageStart, pageEnd);

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: const Text('已注册提醒'),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 52,
        actions: [
          IconButton(
            key: const ValueKey('registered_reminders_refresh'),
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _statusChip(
                        '生效中',
                        _RegisteredReminderStatus.active,
                        activeCount,
                      ),
                      _statusChip(
                        '未生效',
                        _RegisteredReminderStatus.inactive,
                        inactiveCount,
                      ),
                      _statusChip(
                        '全部',
                        _RegisteredReminderStatus.all,
                        _entries.length,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _statusHint(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? EmptyState(
                          icon: Icons.fact_check_outlined,
                          message: _emptyMessage(),
                        )
                      : ListView.builder(
                          key: const ValueKey('registered_reminders_list'),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final entry = visible[index];
                            return _RegisteredReminderDetailRow(
                              entry: entry,
                              active: _queueResolved ? _isActive(entry) : null,
                            );
                          },
                        ),
                ),
                if (filtered.length > _pageSize)
                  _Pager(
                    currentPage: currentPage,
                    totalPages: totalPages,
                    rangeStart: pageStart + 1,
                    rangeEnd: pageEnd,
                    total: filtered.length,
                    onPrev: currentPage <= 0
                        ? null
                        : () => setState(() => _page = currentPage - 1),
                    onNext: currentPage >= totalPages - 1
                        ? null
                        : () => setState(() => _page = currentPage + 1),
                  ),
              ],
            ),
    );
  }

  Widget _statusChip(
    String label,
    _RegisteredReminderStatus status,
    int count,
  ) {
    return ChoiceChip(
      key: ValueKey('registered_reminders_filter_${status.name}'),
      label: Text('$label · $count'),
      selected: _status == status,
      onSelected: (_) => _setStatus(status),
    );
  }

  String _statusHint() {
    switch (_status) {
      case _RegisteredReminderStatus.active:
        return '已进入系统提醒队列、到点会触发的提醒';
      case _RegisteredReminderStatus.inactive:
        return '已登记但系统队列中查不到，可重新保存对应待办/习惯，或检查通知与精准闹钟权限';
      case _RegisteredReminderStatus.all:
        return '调度器登记的全部提醒对象';
    }
  }

  String _emptyMessage() {
    switch (_status) {
      case _RegisteredReminderStatus.active:
        return '暂无生效中的提醒';
      case _RegisteredReminderStatus.inactive:
        return '没有未生效的提醒，一切正常';
      case _RegisteredReminderStatus.all:
        return '暂无已注册提醒';
    }
  }
}

class _Pager extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final int rangeStart;
  final int rangeEnd;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _Pager({
    required this.currentPage,
    required this.totalPages,
    required this.rangeStart,
    required this.rangeEnd,
    required this.total,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$rangeStart-$rangeEnd / $total · 第 ${currentPage + 1}/$totalPages 页',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const ValueKey('registered_reminders_prev'),
                tooltip: '上一页',
                constraints: const BoxConstraints.tightFor(
                  width: 38,
                  height: 38,
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                key: const ValueKey('registered_reminders_next'),
                tooltip: '下一页',
                constraints: const BoxConstraints.tightFor(
                  width: 38,
                  height: 38,
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotificationHistoryEntryTile extends StatelessWidget {
  final int historyCount;
  final int unreadCount;
  final VoidCallback onOpen;

  const _NotificationHistoryEntryTile({
    required this.historyCount,
    required this.unreadCount,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titleStyle = appSecondaryMenuItemTextStyle(
      context,
    ).copyWith(color: cs.onSurface, fontWeight: DesignTokens.fontWeightRegular);
    final subtitleStyle = appSecondaryControlLabelStyle(
      context,
    ).copyWith(color: cs.onSurface.withValues(alpha: 0.62));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('notification_history_entry_tile'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.history_outlined,
                  color: Colors.blueGrey,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '通知记录',
                      key: const ValueKey('notification_history_entry_title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '共 $historyCount 条，未读 $unreadCount 条',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('notification_history_entry_view_button'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  textStyle: appSecondaryMenuItemTextStyle(context),
                ),
                onPressed: onOpen,
                child: const Text('查看'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsExpansionHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget trailing;
  final Key? iconKey;
  final Key? titleKey;
  final Key? subtitleKey;

  const _SettingsExpansionHeader({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.iconKey,
    this.titleKey,
    this.subtitleKey,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              key: iconKey,
              width: 34,
              height: 34,
              child: Center(child: Icon(icon, color: color, size: 22)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    key: titleKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appSecondaryMenuItemTextStyle(context).copyWith(
                      color: cs.onSurface,
                      fontWeight: DesignTokens.fontWeightRegular,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    key: subtitleKey,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: appSecondaryControlLabelStyle(
                      context,
                    ).copyWith(color: cs.onSurface.withValues(alpha: 0.62)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 40,
              child: Align(alignment: Alignment.centerRight, child: trailing),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationReminderSlotTile extends StatefulWidget {
  final int index;
  final DailyReminderSlot slot;

  const _NotificationReminderSlotTile({
    required this.index,
    required this.slot,
  });

  @override
  State<_NotificationReminderSlotTile> createState() =>
      _NotificationReminderSlotTileState();
}

class _NotificationReminderSlotTileState
    extends State<_NotificationReminderSlotTile> {
  bool _saving = false;

  int get index => widget.index;
  DailyReminderSlot get slot => widget.slot;

  String get _title => switch (index) {
    0 => I18n.tr('preferences.daily_reminder.one'),
    1 => I18n.tr('preferences.daily_reminder.two'),
    _ => I18n.tr('preferences.daily_reminder.three'),
  };

  String get _time =>
      I18nDateFormat.timeOfDay(hour: slot.hour, minute: slot.minute);

  Future<void> _save(BuildContext context, DailyReminderSlot next) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final needsReminderCheck =
          next.enabled &&
          (!slot.enabled ||
              slot.hour != next.hour ||
              slot.minute != next.minute ||
              slot.kind != next.kind ||
              !_sameDays(slot.repeatDays, next.repeatDays));
      if (needsReminderCheck) {
        final notif = context.read<NotificationService?>();
        final ready =
            await notif?.ensureReadyForReminder(
              scheduledTime: _nextSlotTrigger(next),
              issueTitle: I18n.tr('preferences.daily_reminder.register_failed'),
              relatedId: 'daily_reminder_$index',
            ) ??
            true;
        if (!context.mounted) return;
        if (!ready) {
          final issue = notif?.lastScheduleIssue;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                issue?.message ??
                    I18n.tr('preferences.daily_reminder.not_ready'),
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      }
      await context.read<PreferencesProvider>().setDailyReminderSlot(
        index,
        next,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.22),
          width: 0.4,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            collapsedShape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            initiallyExpanded: index == 0,
            tilePadding: EdgeInsets.zero,
            showTrailingIcon: false,
            title: _SettingsExpansionHeader(
              key: ValueKey('daily_reminder_slot_${index}_header'),
              iconKey: ValueKey('daily_reminder_slot_${index}_header_icon'),
              titleKey: ValueKey('daily_reminder_slot_${index}_header_title'),
              subtitleKey: ValueKey(
                'daily_reminder_slot_${index}_header_subtitle',
              ),
              icon: Icons.notifications_active_outlined,
              color: cs.primary,
              title: _title,
              subtitle: slot.enabled
                  ? '${_kindLabel(slot.kind)} · $_time · ${_repeatDaysLabel(slot.repeatDays)} · ${_taskScopeText(slot)}'
                  : '${I18n.tr('preferences.daily_reminder.disabled')} · $_time',
              trailing: _CompactSettingsSwitch(
                key: ValueKey('daily_reminder_slot_${index}_enabled_switch'),
                value: slot.enabled,
                onChanged: _saving
                    ? null
                    : (value) => _save(context, slot.copyWith(enabled: value)),
              ),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            children: [
              _ReminderKindSettingsTile(
                value: slot.kind,
                subtitle: _kindDescription(slot.kind),
                enabled: !_saving,
                onChanged: (kind) => _save(
                  context,
                  slot.copyWith(enabled: kind != ReminderKind.off, kind: kind),
                ),
              ),
              const SizedBox(height: 6),
              AppSettingsTile(
                key: ValueKey('daily_reminder_slot_${index}_time_tile'),
                icon: Icons.schedule,
                color: Colors.deepOrange,
                title: I18n.tr('preferences.daily_reminder.time'),
                subtitle: I18n.tr('preferences.daily_reminder.time.subtitle'),
                trailing: TextButton(
                  key: ValueKey('daily_reminder_slot_${index}_time_button'),
                  onPressed: _saving
                      ? null
                      : () async {
                          final picked = await AppTimePicker.show(
                            context,
                            initialTime: TimeOfDay(
                              hour: slot.hour,
                              minute: slot.minute,
                            ),
                            title:
                                '$_title${I18n.tr('preferences.daily_reminder.time_suffix')}',
                            subtitle: I18n.tr(
                              'preferences.daily_reminder.time_picker.subtitle',
                            ),
                          );
                          if (picked == null || !context.mounted) return;
                          await _save(
                            context,
                            slot.copyWith(
                              hour: picked.hour,
                              minute: picked.minute,
                            ),
                          );
                        },
                  child: Text(_time),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _scopeChip(
                    context,
                    I18n.tr('preferences.daily_reminder.chip.today_tasks'),
                    slot.includeTodayTasks,
                    slot.copyWith(includeTodayTasks: !slot.includeTodayTasks),
                  ),
                  _scopeChip(
                    context,
                    I18n.tr('preferences.daily_reminder.chip.tomorrow_plan'),
                    slot.includeTomorrowPlan,
                    slot.copyWith(
                      includeTomorrowPlan: !slot.includeTomorrowPlan,
                    ),
                  ),
                  _scopeChip(
                    context,
                    I18n.tr('preferences.daily_reminder.chip.overdue_tasks'),
                    slot.includeOverdue,
                    slot.copyWith(includeOverdue: !slot.includeOverdue),
                  ),
                  _scopeChip(
                    context,
                    I18n.tr('preferences.daily_reminder.chip.pause_holidays'),
                    slot.pauseHolidays,
                    slot.copyWith(pauseHolidays: !slot.pauseHolidays),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var day = 1; day <= 7; day++)
                    _compactFilterChip(
                      context,
                      key: ValueKey(
                        'daily_reminder_slot_${index}_weekday_$day',
                      ),
                      label: _weekdayLabel(day),
                      selected: slot.repeatDays.contains(day),
                      onSelected: _saving
                          ? null
                          : (_) {
                              final nextDays =
                                  slot.repeatDays.contains(day)
                                        ? slot.repeatDays
                                              .where((d) => d != day)
                                              .toList()
                                        : [...slot.repeatDays, day]
                                    ..sort();
                              _save(
                                context,
                                slot.copyWith(repeatDays: nextDays),
                              );
                            },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scopeChip(
    BuildContext context,
    String label,
    bool selected,
    DailyReminderSlot next,
  ) {
    return _compactFilterChip(
      context,
      label: label,
      selected: selected,
      onSelected: _saving ? null : (_) => _save(context, next),
    );
  }
}

class _ReminderKindSelector extends StatelessWidget {
  final ReminderKind value;
  final bool enabled;
  final ValueChanged<ReminderKind> onChanged;
  static const _options = [
    _ReminderKindOptionSpec(value: ReminderKind.push),
    _ReminderKindOptionSpec(value: ReminderKind.popup),
    _ReminderKindOptionSpec(value: ReminderKind.alarm),
    _ReminderKindOptionSpec(value: ReminderKind.off),
  ];

  const _ReminderKindSelector({
    required this.value,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = DailyReminderSlot.normalizeKind(value);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 64;
        final gap = maxWidth < 340 ? 4.0 : 6.0;
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 42),
          child: Row(
            key: const ValueKey('daily_reminder_kind_selector_row'),
            children: [
              for (var i = 0; i < _options.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: _ReminderKindOptionButton(
                      key: ValueKey(
                        'daily_reminder_kind_${_options[i].value.name}',
                      ),
                      label: _kindLabel(_options[i].value),
                      selected: selected == _options[i].value,
                      enabled: enabled,
                      onTap: () => onChanged(_options[i].value),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ReminderKindOptionSpec {
  final ReminderKind value;

  const _ReminderKindOptionSpec({required this.value});
}

class _ReminderKindSettingsTile extends StatelessWidget {
  final ReminderKind value;
  final String subtitle;
  final bool enabled;
  final ValueChanged<ReminderKind> onChanged;

  const _ReminderKindSettingsTile({
    required this.value,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  color: Colors.teal,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      I18n.tr('preferences.daily_reminder.kind.title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: appSecondaryMenuItemTextStyle(context).copyWith(
                        color: cs.onSurface,
                        fontWeight: DesignTokens.fontWeightRegular,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: appSecondaryControlLabelStyle(
                        context,
                      ).copyWith(color: cs.onSurface.withValues(alpha: 0.62)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ReminderKindSelector(
            value: value,
            enabled: enabled,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ReminderKindOptionButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ReminderKindOptionButton({
    super.key,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderColor = selected
        ? cs.primary.withValues(alpha: 0.42)
        : cs.outlineVariant.withValues(alpha: 0.45);
    final foreground = _reminderKindForeground(cs, selected, enabled);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? cs.primary.withValues(alpha: 0.12) : cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: borderColor, width: 0.45),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.normal,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Color _reminderKindForeground(ColorScheme cs, bool selected, bool enabled) {
  if (!enabled) return cs.onSurface.withValues(alpha: 0.38);
  if (selected) return cs.onSurface;
  return cs.onSurface.withValues(alpha: 0.76);
}

String _kindLabel(ReminderKind kind) {
  return switch (DailyReminderSlot.normalizeKind(kind)) {
    ReminderKind.push => I18n.tr('reminder.kind.push'),
    ReminderKind.popup => I18n.tr('reminder.kind.popup'),
    ReminderKind.alarm => I18n.tr('reminder.kind.alarm'),
    ReminderKind.off => I18n.tr('reminder.kind.off'),
    ReminderKind.email => I18n.tr('reminder.kind.push'),
  };
}

String _kindDescription(ReminderKind kind) {
  return switch (DailyReminderSlot.normalizeKind(kind)) {
    ReminderKind.push => I18n.tr(
      'preferences.daily_reminder.kind.push.description',
    ),
    ReminderKind.popup => I18n.tr(
      'preferences.daily_reminder.kind.popup.description',
    ),
    ReminderKind.alarm => I18n.tr(
      'preferences.daily_reminder.kind.alarm.description',
    ),
    ReminderKind.off => I18n.tr(
      'preferences.daily_reminder.kind.off.description',
    ),
    ReminderKind.email => I18n.tr(
      'preferences.daily_reminder.kind.push.description',
    ),
  };
}

String _registeredReminderTypeLabel(String objectType) {
  return switch (objectType) {
    'todo' => '待办',
    'goal' => '目标',
    'habit' => '习惯',
    'anniversary' => '纪念日',
    'countdown' => '倒数日',
    _ => objectType,
  };
}

String _registeredReminderDisplayTitle(
  ReminderScheduleSnapshotEntry entry,
  String typeLabel,
) {
  final value = entry.title.trim();
  if (value.isNotEmpty) return value;
  return '$typeLabel提醒（标题未同步）';
}

String _registeredReminderDisplaySubtitle(
  ReminderScheduleSnapshotEntry entry,
  String typeLabel,
) {
  final value = entry.subtitle.trim();
  if (value.isNotEmpty) return value;
  return '$typeLabel · 提醒规则暂未同步，可刷新或重新保存对应事项';
}

Color _registeredReminderTypeColor(String objectType, ColorScheme cs) {
  return switch (objectType) {
    'todo' => Colors.blue,
    'goal' => Colors.indigo,
    'habit' => Colors.green,
    'anniversary' => Colors.pink,
    'countdown' => Colors.deepOrange,
    _ => cs.primary,
  };
}

bool _sameDays(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

DateTime? _nextSlotTrigger(DailyReminderSlot slot) {
  final now = AppClock.now();
  for (var offset = 0; offset <= 7; offset++) {
    final date = AppClock.today().add(Duration(days: offset));
    final target = AppClock.date(
      date.year,
      date.month,
      date.day,
      slot.hour,
      slot.minute,
    );
    if (target.isAfter(now) && slot.repeatDays.contains(target.weekday)) {
      return target;
    }
  }
  return null;
}

class _CompactSettingsSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _CompactSettingsSwitch({
    super.key,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 30,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}

Widget _compactFilterChip(
  BuildContext context, {
  Key? key,
  required String label,
  required bool selected,
  required ValueChanged<bool>? onSelected,
}) {
  final cs = Theme.of(context).colorScheme;
  return FilterChip(
    key: key,
    label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    selected: selected,
    showCheckmark: false,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    labelPadding: const EdgeInsets.symmetric(horizontal: 2),
    labelStyle: appSecondaryControlLabelStyle(context).copyWith(
      color: selected ? cs.onSurface : cs.onSurface.withValues(alpha: 0.72),
      height: 1.0,
    ),
    selectedColor: cs.primary.withValues(alpha: 0.12),
    backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.18),
    side: BorderSide(
      color: selected
          ? cs.primary.withValues(alpha: 0.36)
          : cs.outlineVariant.withValues(alpha: 0.36),
      width: 0.45,
    ),
    onSelected: onSelected,
  );
}

class _NotificationRingtoneSection extends StatefulWidget {
  const _NotificationRingtoneSection();

  @override
  State<_NotificationRingtoneSection> createState() =>
      _NotificationRingtoneSectionState();
}

class _NotificationRingtoneSectionState
    extends State<_NotificationRingtoneSection> {
  int _volume = ReminderRingtoneSettings.defaultVolumePercent;
  String _sound = ReminderRingtoneSettings.defaultSound;
  bool _previewing = false;
  final ReminderRingtonePlatformPolicy _policy =
      ReminderRingtoneSettings.platformPolicy;

  @override
  void initState() {
    super.initState();
    if (!_policy.supportsBuiltInSoundPicker) return;
    ReminderRingtoneSettings.loadVolumePercent().then((value) {
      if (mounted) setState(() => _volume = value);
    });
    ReminderRingtoneSettings.loadSound().then((value) {
      if (mounted) setState(() => _sound = value);
    });
  }

  @override
  void dispose() {
    if (_policy.supportsBuiltInSoundPicker) {
      unawaited(ReminderRingtoneSettings.stopPreview());
    }
    super.dispose();
  }

  Future<void> _setVolume(int value) async {
    if (_previewing) return;
    setState(() {
      _volume = value;
      _previewing = true;
    });
    try {
      await _applyRingtoneChange(
        () => ReminderRingtoneSettings.setVolumePercent(value),
        successMessage: '已切换音量并开始试听',
      );
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
    await _reloadRingtoneSettings();
  }

  Future<void> _setSound(String value) async {
    if (_previewing) return;
    final label = ReminderRingtoneSettings.sounds
        .firstWhere(
          (sound) => sound.id == value,
          orElse: () => ReminderRingtoneSettings.sounds.first,
        )
        .label;
    setState(() {
      _sound = value;
      _previewing = true;
    });
    try {
      await _applyRingtoneChange(
        () => ReminderRingtoneSettings.setSound(value),
        successMessage: '已切换为 $label，并开始试听',
      );
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
    await _reloadRingtoneSettings();
  }

  Future<void> _previewCurrentSound() async {
    if (_previewing) return;
    setState(() => _previewing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ReminderRingtoneSettings.previewCurrentSound();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('正在试听当前提醒铃声'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ReminderRingtonePreviewException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(e.message), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _applyRingtoneChange(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    try {
      await action();
      if (!mounted || successMessage == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ReminderRingtonePreviewException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _reloadRingtoneSettings() async {
    if (!_policy.supportsBuiltInSoundPicker) return;
    final volume = await ReminderRingtoneSettings.loadVolumePercent();
    final sound = await ReminderRingtoneSettings.loadSound();
    if (!mounted) return;
    setState(() {
      _volume = volume;
      _sound = sound;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_policy.supportsBuiltInSoundPicker) {
      return AppSettingsSection(
        title: I18n.tr('preferences.ringtone.section'),
        subtitle: I18n.tr(_policy.sectionSubtitleKey),
        children: [
          AppSettingsTile(
            icon: Icons.notifications_active_outlined,
            color: Colors.orange,
            title: I18n.tr(_policy.tileTitleKey),
            subtitle: I18n.tr(_policy.tileSubtitleKey),
            trailing: const SizedBox.shrink(),
          ),
        ],
      );
    }

    return AppSettingsSection(
      title: I18n.tr('preferences.ringtone.section'),
      subtitle: I18n.tr(_policy.sectionSubtitleKey),
      children: [
        _RingtoneControlTile(
          icon: Icons.notifications_active_outlined,
          color: Colors.orange,
          title: I18n.tr('preferences.ringtone.sound'),
          subtitle: ReminderRingtoneSettings.sounds
              .firstWhere((sound) => sound.id == _sound)
              .label,
          control: _RingtoneSoundControl(
            sound: _sound,
            previewing: _previewing,
            onPreview: _previewCurrentSound,
            onChanged: _setSound,
          ),
        ),
        if (_policy.supportsVolumePresets)
          _RingtoneControlTile(
            icon: Icons.volume_up_outlined,
            color: Colors.deepOrange,
            title: I18n.tr('preferences.ringtone.volume'),
            subtitle: '${I18n.tr('preferences.ringtone.current')} $_volume%',
            control: _RingtoneVolumeControl(
              volume: _volume,
              onChanged: _setVolume,
            ),
          ),
      ],
    );
  }
}

class _RingtoneControlTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget control;

  const _RingtoneControlTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.control,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final targetControlWidth = availableWidth < 360
              ? 116.0
              : (availableWidth * 0.44).clamp(150.0, 220.0).toDouble();
          final maxControlWidth = (availableWidth - 96).clamp(
            0.0,
            availableWidth,
          );
          final controlWidth = targetControlWidth
              .clamp(0.0, maxControlWidth)
              .toDouble();
          final controlBox = SizedBox(
            width: controlWidth,
            height: 40,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: control,
              ),
            ),
          );

          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 54),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: appSecondaryMenuItemTextStyle(context).copyWith(
                          color: cs.onSurface,
                          fontWeight: DesignTokens.fontWeightRegular,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: appSecondaryControlLabelStyle(
                          context,
                        ).copyWith(color: cs.onSurface.withValues(alpha: 0.62)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                controlBox,
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RingtoneSoundControl extends StatelessWidget {
  final String sound;
  final bool previewing;
  final VoidCallback onPreview;
  final ValueChanged<String> onChanged;

  const _RingtoneSoundControl({
    required this.sound,
    required this.previewing,
    required this.onPreview,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 122.0;
        final previewSize = maxWidth < 144 ? 32.0 : 36.0;
        final dropdownWidth = (maxWidth - previewSize - 4)
            .clamp(76.0, 132.0)
            .toDouble();
        return Row(
          key: const ValueKey('notification_ringtone_sound_control'),
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: previewSize,
              height: 32,
              child: IconButton(
                tooltip: '试听当前铃声',
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: previewing ? null : onPreview,
                icon: previewing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.volume_up_outlined),
              ),
            ),
            const SizedBox(width: 4),
            AppCompactDropdown<String>(
              value: sound,
              width: dropdownWidth,
              items: [
                for (final sound in ReminderRingtoneSettings.sounds)
                  DropdownMenuItem(value: sound.id, child: Text(sound.label)),
              ],
              onChanged: (value) => value == null ? null : onChanged(value),
            ),
          ],
        );
      },
    );
  }
}

class _RingtoneVolumeControl extends StatelessWidget {
  final int volume;
  final ValueChanged<int> onChanged;

  const _RingtoneVolumeControl({required this.volume, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('notification_ringtone_volume_control'),
      height: 32,
      child: Row(
        children: [
          for (var i = 0; i < ReminderRingtoneSettings.presets.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _RingtoneVolumeButton(
                value: ReminderRingtoneSettings.presets[i],
                selected: volume == ReminderRingtoneSettings.presets[i],
                onTap: () => onChanged(ReminderRingtoneSettings.presets[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RingtoneVolumeButton extends StatelessWidget {
  final int value;
  final bool selected;
  final VoidCallback onTap;

  const _RingtoneVolumeButton({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foreground = selected
        ? cs.onSurface
        : cs.onSurface.withValues(alpha: 0.72);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? cs.primary.withValues(alpha: 0.12) : cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected
                ? cs.primary.withValues(alpha: 0.36)
                : cs.outlineVariant.withValues(alpha: 0.38),
            width: 0.45,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              '$value%',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: appSecondaryControlLabelStyle(
                context,
              ).copyWith(color: foreground, height: 1.0),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportReminderSection extends StatelessWidget {
  const _ReportReminderSection();

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();
    return AppSettingsSection(
      title: '报告推送',
      subtitle: '按你的节奏提醒查看每日复盘、周报、月报和年报',
      children: [
        _ReportReminderTile(
          title: '每日效率复盘',
          icon: Icons.today_outlined,
          color: Colors.blue,
          config: prefs.dailyReportReminderConfig,
          cadence: _ReportReminderCadence.daily,
        ),
        _ReportReminderTile(
          title: '每周效率周报',
          icon: Icons.summarize_outlined,
          color: Colors.indigo,
          config: prefs.weeklyReportReminderConfig,
          cadence: _ReportReminderCadence.weekly,
        ),
        _ReportReminderTile(
          title: '每月成长月报',
          icon: Icons.calendar_month_outlined,
          color: Colors.teal,
          config: prefs.monthlyReportReminderConfig,
          cadence: _ReportReminderCadence.monthly,
        ),
        _ReportReminderTile(
          title: '每年成长年报',
          icon: Icons.event_available_outlined,
          color: Colors.deepOrange,
          config: prefs.yearlyReportReminderConfig,
          cadence: _ReportReminderCadence.yearly,
        ),
      ],
    );
  }
}

enum _ReportReminderCadence { daily, weekly, monthly, yearly }

class _ReportReminderTile extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color color;
  final ReportReminderConfig config;
  final _ReportReminderCadence cadence;

  const _ReportReminderTile({
    required this.title,
    required this.icon,
    required this.color,
    required this.config,
    required this.cadence,
  });

  @override
  State<_ReportReminderTile> createState() => _ReportReminderTileState();
}

class _ReportReminderTileState extends State<_ReportReminderTile> {
  bool _saving = false;

  String get title => widget.title;
  IconData get icon => widget.icon;
  Color get color => widget.color;
  ReportReminderConfig get config => widget.config;
  _ReportReminderCadence get cadence => widget.cadence;

  String get _time =>
      I18nDateFormat.timeOfDay(hour: config.hour, minute: config.minute);

  String get _subtitle {
    final cadenceText = switch (cadence) {
      _ReportReminderCadence.daily => '每天',
      _ReportReminderCadence.weekly => '每${_weekdayLabel(config.weekday)}',
      _ReportReminderCadence.monthly => '每月 ${config.monthDay} 日',
      _ReportReminderCadence.yearly =>
        '每年 ${config.month} 月 ${config.monthDay} 日',
    };
    final state = config.enabled ? '动态摘要' : '已关闭';
    return '$state · $cadenceText $_time';
  }

  Future<void> _save(BuildContext context, ReportReminderConfig next) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final prefs = context.read<PreferencesProvider>();
      await switch (cadence) {
        _ReportReminderCadence.daily => prefs.setDailyReportReminderConfig(
          next,
        ),
        _ReportReminderCadence.weekly => prefs.setWeeklyReportReminderConfig(
          next,
        ),
        _ReportReminderCadence.monthly => prefs.setMonthlyReportReminderConfig(
          next,
        ),
        _ReportReminderCadence.yearly => prefs.setYearlyReportReminderConfig(
          next,
        ),
      };
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _timeSubtitle {
    return switch (cadence) {
      _ReportReminderCadence.daily => '到点推送今天报告动态摘要',
      _ReportReminderCadence.weekly => '到点推送上一周报告动态摘要',
      _ReportReminderCadence.monthly => '到点推送上月报告动态摘要',
      _ReportReminderCadence.yearly => '到点推送上一年报告动态摘要',
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.28),
          width: 0.45,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            collapsedShape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            tilePadding: EdgeInsets.zero,
            showTrailingIcon: false,
            title: _SettingsExpansionHeader(
              key: ValueKey('report_reminder_${cadence.name}_header'),
              iconKey: ValueKey('report_reminder_${cadence.name}_header_icon'),
              titleKey: ValueKey(
                'report_reminder_${cadence.name}_header_title',
              ),
              subtitleKey: ValueKey(
                'report_reminder_${cadence.name}_header_subtitle',
              ),
              icon: icon,
              color: color,
              title: title,
              subtitle: _subtitle,
              trailing: _CompactSettingsSwitch(
                key: ValueKey('report_reminder_${cadence.name}_enabled_switch'),
                value: config.enabled,
                onChanged: _saving
                    ? null
                    : (v) => _save(context, config.copyWith(enabled: v)),
              ),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              AppSettingsTile(
                icon: Icons.schedule,
                color: color,
                title: '推送时间',
                subtitle: _timeSubtitle,
                trailing: TextButton(
                  key: ValueKey('report_reminder_time_button_${cadence.name}'),
                  onPressed: _saving
                      ? null
                      : () async {
                          final picked = await AppTimePicker.show(
                            context,
                            initialTime: TimeOfDay(
                              hour: config.hour,
                              minute: config.minute,
                            ),
                            title: '$title推送时间',
                            subtitle: '修改后会重排下一次报告通知',
                          );
                          if (picked == null || !context.mounted) return;
                          await _save(
                            context,
                            config.copyWith(
                              hour: picked.hour,
                              minute: picked.minute,
                            ),
                          );
                        },
                  child: Text(_time),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _cadenceChips(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _cadenceChips(BuildContext context) {
    return switch (cadence) {
      _ReportReminderCadence.daily => const <Widget>[],
      _ReportReminderCadence.weekly => [
        for (var day = 1; day <= 7; day++)
          _compactFilterChip(
            context,
            key: ValueKey('report_reminder_${cadence.name}_weekday_$day'),
            label: _weekdayLabel(day),
            selected: config.weekday == day,
            onSelected: _saving
                ? null
                : (_) => _save(context, config.copyWith(weekday: day)),
          ),
      ],
      _ReportReminderCadence.monthly => _monthDayChips(context),
      _ReportReminderCadence.yearly => [
        for (var month = 1; month <= 12; month++)
          _compactFilterChip(
            context,
            key: ValueKey('report_reminder_${cadence.name}_month_$month'),
            label: '$month 月',
            selected: config.month == month,
            onSelected: _saving
                ? null
                : (_) => _save(context, config.copyWith(month: month)),
          ),
        for (final day in const [1, 5, 10, 15, 20, 25, 28, 31])
          _compactFilterChip(
            context,
            key: ValueKey('report_reminder_${cadence.name}_day_$day'),
            label: '$day 日',
            selected: config.monthDay == day,
            onSelected: _saving
                ? null
                : (_) => _save(context, config.copyWith(monthDay: day)),
          ),
      ],
    };
  }

  List<Widget> _monthDayChips(BuildContext context) {
    return [
      for (final day in const [1, 5, 10, 15, 20, 25, 28, 31])
        _compactFilterChip(
          context,
          key: ValueKey('report_reminder_${cadence.name}_day_$day'),
          label: '$day 日',
          selected: config.monthDay == day,
          onSelected: _saving
              ? null
              : (_) => _save(context, config.copyWith(monthDay: day)),
        ),
    ];
  }
}

Color _notificationColor(NotificationType type) {
  return switch (type) {
    NotificationType.todo => Colors.blue,
    NotificationType.habit => Colors.green,
    NotificationType.pomodoro => Colors.red,
    NotificationType.anniversary => Colors.pink,
    NotificationType.location => Colors.teal,
    NotificationType.general => Colors.orange,
  };
}

IconData _notificationIcon(NotificationType type) {
  return switch (type) {
    NotificationType.todo => Icons.checklist,
    NotificationType.habit => Icons.repeat,
    NotificationType.pomodoro => Icons.timer,
    NotificationType.anniversary => Icons.event_available_outlined,
    NotificationType.location => Icons.location_on_outlined,
    NotificationType.general => Icons.notifications_active_outlined,
  };
}

String _notificationTypeLabel(NotificationType type) {
  return switch (type) {
    NotificationType.todo => '待办',
    NotificationType.habit => '习惯',
    NotificationType.pomodoro => '番茄钟',
    NotificationType.anniversary => '纪念日',
    NotificationType.location => '位置',
    NotificationType.general => '系统',
  };
}

String _formatNotificationTime(DateTime value) {
  final local = AppClock.toLocal(value);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

String _repeatDaysLabel(List<int> days) {
  if (days.length == 7) return I18n.tr('repeat.every_day');
  if (days.length == 5 && days.every((day) => day >= 1 && day <= 5)) {
    return I18n.tr('repeat.weekdays');
  }
  return days.map(_weekdayLabel).join('/');
}

String _weekdayLabel(int day) {
  const keys = [
    'weekday.mon',
    'weekday.tue',
    'weekday.wed',
    'weekday.thu',
    'weekday.fri',
    'weekday.sat',
    'weekday.sun',
  ];
  if (day < 1 || day > 7) return I18n.tr('weekday.unknown');
  return I18n.tr(keys[day - 1]);
}

String _taskScopeText(DailyReminderSlot slot) {
  final parts = <String>[
    if (slot.includeTodayTasks)
      I18n.tr('preferences.daily_reminder.scope.today'),
    if (slot.includeTomorrowPlan)
      I18n.tr('preferences.daily_reminder.scope.tomorrow'),
    if (slot.includeOverdue)
      I18n.tr('preferences.daily_reminder.scope.overdue'),
  ];
  if (parts.isEmpty) return I18n.tr('preferences.daily_reminder.scope.none');
  return parts.join('/');
}
