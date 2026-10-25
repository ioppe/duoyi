import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('clearHistory only clears notification history and refreshes UI', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> clearHistory()');
    final end = source.indexOf('@override', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final method = source.substring(start, end);

    expect(method, contains('_history.clear();'));
    expect(method, contains('_historyLastSeenAt = DateTime.now();'));
    expect(method, isNot(contains('_pendingNotifications = 0;')));
    expect(method, contains('await _saveHistory();'));
    expect(method, contains('await _saveHistorySeen();'));
    expect(method, contains('notifyListeners();'));
    expect(
      method.indexOf('_history.clear();'),
      lessThan(method.indexOf('await _saveHistory();')),
    );
    expect(
      method.indexOf('await _saveHistory();'),
      lessThan(method.indexOf('notifyListeners();')),
    );
  });

  test('cancel decrements pending notification count and refreshes UI', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> cancel(int id)');
    final end = source.indexOf('/// 取消全部已调度通知', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final method = source.substring(start, end);

    expect(method, contains('LocalNotifications.instance.cancel(id)'));
    expect(method, contains('if (_pendingNotifications > 0)'));
    expect(method, contains('_pendingNotifications--;'));
    expect(method, contains('notifyListeners();'));
  });

  test(
    'LocalNotifications cancel initializes before clearing system queues',
    () {
      final source = File(
        'lib/services/local_notifications_io.dart',
      ).readAsStringSync();

      final quickAddCancelStart = source.indexOf(
        'Future<void> cancelQuickAddOngoing()',
      );
      final cancelStart = source.indexOf('Future<void> cancel(int id)');
      final cancelAllStart = source.indexOf('Future<void> cancelAll()');
      final pendingStart = source.indexOf(
        'Future<List<int>> pendingIds()',
        cancelAllStart,
      );
      final scheduleOnceStart = source.indexOf(
        'Future<void> scheduleOnce({',
        quickAddCancelStart,
      );
      expect(quickAddCancelStart, greaterThanOrEqualTo(0));
      expect(cancelStart, greaterThanOrEqualTo(0));
      expect(cancelAllStart, greaterThan(cancelStart));
      expect(pendingStart, greaterThan(cancelAllStart));
      expect(scheduleOnceStart, greaterThan(quickAddCancelStart));

      final cancel = source.substring(cancelStart, cancelAllStart);
      final cancelAll = source.substring(cancelAllStart, pendingStart);
      final quickAddCancel = source.substring(
        quickAddCancelStart,
        scheduleOnceStart,
      );

      expect(cancel, isNot(contains('if (!_initialized) return;')));
      expect(cancel, contains('if (!_initialized) await init();'));
      expect(cancel, contains('for (final queueId in _queueIdsFor(id))'));
      expect(cancel, contains('await _plugin.cancel(queueId);'));
      expect(cancel, contains('await NativeReminderRingtone.cancel(queueId);'));
      expect(
        cancel.indexOf('if (!_initialized) await init();'),
        lessThan(cancel.indexOf('for (final queueId in _queueIdsFor(id))')),
        reason: '冷启动切换到弹框/闹钟/关闭时，普通通知旧队列不能静默保留。',
      );
      expect(quickAddCancel, contains('if (!_initialized) await init();'));
      expect(
        quickAddCancel,
        contains('_plugin.cancel(quickAddNotificationId)'),
      );
      expect(quickAddCancel, isNot(contains('_queueIdsFor')));
      expect(quickAddCancel, isNot(contains('NativeReminderRingtone.cancel')));

      expect(cancelAll, isNot(contains('if (!_initialized) return;')));
      expect(cancelAll, contains('if (!_initialized) await init();'));
      expect(cancelAll, contains('_lastQuickAddOngoingSignature = null;'));
      expect(cancelAll, contains('_recentVisibleNotificationIds.clear();'));
      expect(
        cancelAll,
        contains('_recentVisibleNotificationSignatures.clear();'),
      );
      expect(
        cancelAll,
        contains('_recentVisibleNotificationContentSignatures.clear();'),
      );
      expect(cancelAll, contains('await _plugin.cancelAll();'));
      expect(cancelAll, contains('await NativeReminderRingtone.cancelAll();'));
      expect(cancelAll, contains('cancelAll native failed'));
    },
  );

  test('NotificationService cancelAll documents global queue cleanup', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();
    final start = source.indexOf('/// 取消全部已调度通知');
    final end = source.indexOf('@override', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final block = source.substring(start, end);

    expect(block, contains('清扫 Android 原生铃声残留队列'));
    expect(block, contains('LocalNotifications.instance.cancelAll()'));
    expect(block, contains('_pendingNotifications = 0'));
  });

  test('Mine notification history entry hides zero history count', () {
    final source = File('lib/screens/mine_screen.dart').readAsStringSync();
    final start = source.indexOf(
      "label: I18n.tr('mine.tile.notification_history')",
    );
    final end = source.indexOf(
      "label: I18n.tr('mine.tile.notification_settings')",
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final entry = source.substring(start, end);

    expect(entry, contains('hasUnreadNotificationHistory'));
    expect(entry, contains('const _UnreadDot()'));
    expect(entry, contains('notificationHistoryCount == 0'));
    expect(entry, contains('? null'));
    expect(
      entry,
      contains(
        r"'$notificationHistoryCount${I18n.tr('mine.tile.notification_history.count_suffix')}'",
      ),
    );
  });

  test(
    'Mine notification history and reminder preferences are separate entries',
    () {
      final source = File('lib/screens/mine_screen.dart').readAsStringSync();
      final groupStart = source.indexOf(
        "title: I18n.tr('mine.group.notifications')",
      );
      final groupEnd = source.indexOf(
        "label: I18n.tr('announcement.title')",
        groupStart,
      );
      expect(groupStart, greaterThanOrEqualTo(0));
      expect(groupEnd, greaterThan(groupStart));
      final group = source.substring(groupStart, groupEnd);

      expect(
        group,
        contains("label: I18n.tr('mine.tile.notification_history')"),
      );
      expect(group, contains('onTap: () => _openNotificationHistory(context)'));
      expect(
        group,
        contains("label: I18n.tr('mine.tile.notification_settings')"),
      );
      expect(
        group,
        contains(
          "subtitle: I18n.tr('mine.tile.notification_settings.subtitle')",
        ),
      );
      expect(
        group,
        contains('onTap: () => _openNotificationSettings(context)'),
      );
      expect(
        group.indexOf("label: I18n.tr('mine.tile.notification_history')"),
        lessThan(
          group.indexOf("label: I18n.tr('mine.tile.notification_settings')"),
        ),
      );
      expect(
        group,
        contains('hasUnreadNotificationHistory'),
        reason: '通知记录入口展示未读红点。',
      );
      final settingsEntry = group.substring(
        group.indexOf("label: I18n.tr('mine.tile.notification_settings')"),
      );
      expect(
        settingsEntry,
        isNot(contains('trailing: hasUnreadNotificationHistory')),
        reason: '通知设置是配置入口，不应该因为通知记录未读而挂红点。',
      );
      expect(group, isNot(contains("label: I18n.tr('mine.tile.more_apps')")));

      final actionStart = source.indexOf(
        "title: I18n.tr('mine.group.action_plan')",
      );
      final actionEnd = source.indexOf(
        "title: I18n.tr('mine.group.review')",
        actionStart,
      );
      expect(actionStart, greaterThanOrEqualTo(0));
      expect(actionEnd, greaterThan(actionStart));
      final actionGroup = source.substring(actionStart, actionEnd);
      expect(actionGroup, contains("label: I18n.tr('mine.tile.more_apps')"));
      expect(
        actionGroup,
        contains('onTap: () => _openMoreApplications(context)'),
      );
    },
  );

  test(
    'Mine notification settings opens independent notification settings',
    () {
      final source = File('lib/screens/mine_screen.dart').readAsStringSync();

      expect(
        source,
        contains(
          'Future<void> _openNotificationSettings(BuildContext context)',
        ),
      );
      expect(source, contains('const NotificationSettingsScreen()'));
      final settingsStart = source.indexOf(
        'Future<void> _openNotificationSettings(BuildContext context)',
      );
      final settingsEnd = source.indexOf(
        'void _openMoreApplications',
        settingsStart,
      );
      expect(settingsStart, greaterThanOrEqualTo(0));
      expect(settingsEnd, greaterThan(settingsStart));
      final settingsMethod = source.substring(settingsStart, settingsEnd);
      expect(settingsMethod, isNot(contains('markAllHistoryRead')));
      expect(
        source,
        contains('void _openNotificationHistory(BuildContext context)'),
      );
      expect(source, contains("import 'notification_history_screen.dart';"));
      final historyStart = source.indexOf(
        'void _openNotificationHistory(BuildContext context)',
      );
      final historyEnd = source.indexOf('void _openFeedback', historyStart);
      expect(historyStart, greaterThanOrEqualTo(0));
      expect(historyEnd, greaterThan(historyStart));
      final historyMethod = source.substring(historyStart, historyEnd);
      expect(historyMethod, contains('NotificationHistoryScreen('));
      expect(historyMethod, contains('markReadOnOpen: true'));
      expect(source, isNot(contains('void _notifDialog')));
      expect(source, isNot(contains('onTap: () => _notifDialog')));
    },
  );

  test(
    'profile route exposes account password change and dialogs can opt into scoped keyboard shifting',
    () {
      final profile = File(
        'lib/screens/profile_screen.dart',
      ).readAsStringSync();
      final surface = File(
        'lib/widgets/surface_components.dart',
      ).readAsStringSync();

      expect(surface, contains('final bool shiftForKeyboard'));
      expect(surface, contains('this.shiftForKeyboard = true'));
      expect(surface, contains('if (!shiftForKeyboard) return scopedDialog;'));
      expect(surface, contains('MediaQuery.removeViewInsets'));
      expect(surface, contains('bool shiftForKeyboard = true'));
      expect(surface, contains('final viewInsets = shiftForKeyboard'));

      expect(profile, contains('class _ChangePasswordDialog'));
      expect(profile, contains("I18n.tr('profile.change_password')"));
      expect(profile, contains('changePassword('));
    },
  );

  test('notification service tracks unread history for red dot badges', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();

    expect(source, contains("static const _kHistorySeenKey"));
    expect(source, contains('DateTime? _historyLastSeenAt'));
    expect(source, contains('final bool isRead'));
    expect(source, contains("'isRead': isRead"));
    expect(source, contains('int get unreadCount'));
    expect(source, contains('bool get hasUnreadHistory'));
    expect(source, contains('unreadCount > 0'));
    expect(source, contains('void markHistorySeen()'));
    expect(source, contains('final nextSeenAt = _history.isEmpty'));
    expect(source, contains('_historyLastSeenAt ?? DateTime.now()'));
    expect(
      source,
      contains('final seenChanged = _historyLastSeenAt != nextSeenAt'),
    );
    expect(source, contains('Future<void> markHistoryItemRead'));
    expect(source, contains('Future<void> markAllHistoryRead'));
    expect(source, contains('Future<void> markAllHistoryUnread'));
    expect(source, contains('copyWith({bool? isRead})'));
    expect(source, contains('unawaited(_saveHistorySeen())'));
    final addStart = source.indexOf(
      'void _addToHistory(NotificationItem item)',
    );
    final addEnd = source.indexOf('Future<void> clearHistory()', addStart);
    expect(addStart, greaterThanOrEqualTo(0));
    expect(addEnd, greaterThan(addStart));
    final addMethod = source.substring(addStart, addEnd);
    expect(addMethod, contains('notifyListeners();'));
  });

  test('opening notification history keeps unread until manual action', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();
    final mine = File('lib/screens/mine_screen.dart').readAsStringSync();
    final settingsScreen = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();

    final start = source.indexOf('void markHistorySeen()');
    final end = source.indexOf('Future<void> markHistoryItemRead', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final method = source.substring(start, end);

    expect(method, contains('final nextSeenAt = _history.isEmpty'));
    expect(method, contains('_historyLastSeenAt ?? DateTime.now()'));
    expect(
      method,
      contains('final seenChanged = _historyLastSeenAt != nextSeenAt'),
    );
    expect(method, contains('_historyLastSeenAt = nextSeenAt'));
    expect(method, contains('if (seenChanged || changed)'));
    expect(
      method,
      contains('_history[i] = _history[i].copyWith(isRead: true)'),
    );
    expect(method, contains('unawaited(_saveHistory())'));
    expect(method, contains('unawaited(_saveHistorySeen())'));
    expect(method, contains('notifyListeners();'));
    expect(source, contains('if (!hasReadState) {'));
    expect(source, contains('return item;'));

    final settingsStart = mine.indexOf(
      'Future<void> _openNotificationSettings(BuildContext context)',
    );
    final settingsEnd = mine.indexOf(
      'void _openMoreApplications',
      settingsStart,
    );
    final historyStart = mine.indexOf(
      'void _openNotificationHistory(BuildContext context)',
    );
    final historyEnd = mine.indexOf('void _openFeedback', historyStart);
    expect(settingsStart, greaterThanOrEqualTo(0));
    expect(settingsEnd, greaterThan(settingsStart));
    expect(historyStart, greaterThanOrEqualTo(0));
    expect(historyEnd, greaterThan(historyStart));
    expect(
      mine.substring(settingsStart, settingsEnd),
      isNot(contains('markAllHistoryRead')),
    );
    expect(
      mine.substring(historyStart, historyEnd),
      contains('NotificationHistoryScreen(markReadOnOpen: true)'),
    );
    expect(mine.substring(historyStart, historyEnd), isNot(contains('await')));

    final settingsClassStart = settingsScreen.indexOf(
      'class _NotificationSettingsScreenState',
    );
    final settingsClassEnd = settingsScreen.indexOf(
      'Future<void> _refreshStatus',
      settingsClassStart,
    );
    expect(settingsClassStart, greaterThanOrEqualTo(0));
    expect(settingsClassEnd, greaterThan(settingsClassStart));
    final settingsInit = settingsScreen.substring(
      settingsClassStart,
      settingsClassEnd,
    );
    expect(settingsInit, isNot(contains('service.unreadCount > 0')));
    expect(settingsInit, isNot(contains('markAllHistoryRead')));
    expect(settingsInit, contains('unawaited(_refreshStatus())'));
    expect(settingsScreen, contains('this.markReadOnOpen = false'));
    expect(settingsScreen, isNot(contains('service.markHistorySeen()')));

    final supportStart = mine.indexOf(
      "title: I18n.tr('mine.group.notifications')",
    );
    final supportEnd = mine.indexOf(
      "label: I18n.tr('mine.tile.admin')",
      supportStart,
    );
    expect(supportStart, greaterThanOrEqualTo(0));
    expect(supportEnd, greaterThan(supportStart));
    final supportGroup = mine.substring(supportStart, supportEnd);
    expect(
      supportGroup,
      contains("label: I18n.tr('mine.tile.notification_history')"),
    );
    expect(
      supportGroup,
      contains("label: I18n.tr('mine.tile.notification_settings')"),
    );
    expect(supportGroup, contains('hasUnreadNotificationHistory'));
    final settingsEntry = supportGroup.substring(
      supportGroup.indexOf("label: I18n.tr('mine.tile.notification_settings')"),
    );
    expect(
      settingsEntry,
      isNot(contains('trailing: hasUnreadNotificationHistory')),
      reason: '通知设置不应和通知记录共用未读红点。',
    );
  });

  test('individual notification records can toggle read state statically', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();

    final itemStart = source.indexOf('Future<void> markHistoryItemRead');
    final itemEnd = source.indexOf(
      'Future<void> markAllHistoryRead',
      itemStart,
    );
    final readStart = source.indexOf('Future<void> markAllHistoryRead');
    final readEnd = source.indexOf(
      'Future<void> markAllHistoryUnread',
      readStart,
    );
    final unreadStart = source.indexOf('Future<void> markAllHistoryUnread');
    final unreadEnd = source.indexOf('DateTime? _latestReadTime', unreadStart);
    expect(itemStart, greaterThanOrEqualTo(0));
    expect(itemEnd, greaterThan(itemStart));
    expect(readStart, greaterThanOrEqualTo(0));
    expect(readEnd, greaterThan(readStart));
    expect(unreadStart, greaterThanOrEqualTo(0));
    expect(unreadEnd, greaterThan(unreadStart));

    final itemMethod = source.substring(itemStart, itemEnd);
    final readMethod = source.substring(readStart, readEnd);
    final unreadMethod = source.substring(unreadStart, unreadEnd);

    expect(itemMethod, contains('_history[index].copyWith(isRead: read)'));
    expect(itemMethod, contains('_historyLastSeenAt = _latestReadTime()'));
    expect(itemMethod, contains('await _saveHistory();'));
    expect(itemMethod, contains('await _saveHistorySeen();'));
    expect(itemMethod, contains('notifyListeners();'));
    expect(readMethod, contains('if (_history.isEmpty)'));
    expect(readMethod, isNot(contains('markHistorySeen();')));
    expect(readMethod, contains('copyWith(isRead: true)'));
    expect(
      readMethod,
      contains('final nextSeenAt = _history.first.scheduledTime'),
    );
    expect(
      readMethod,
      contains('final seenChanged = _historyLastSeenAt != nextSeenAt'),
    );
    expect(readMethod, contains('if (!changed && !seenChanged) return;'));
    expect(readMethod, contains('_historyLastSeenAt = nextSeenAt'));
    expect(unreadMethod, contains('copyWith(isRead: false)'));
    expect(unreadMethod, contains('_historyLastSeenAt = null'));
  });

  test('notification history is a dedicated scrollable page', () {
    final screen = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();

    expect(screen, contains('class NotificationHistoryScreen'));
    expect(screen, contains('class _NotificationHistoryScreenState'));
    expect(screen, contains("title: const Text('通知记录')"));
    expect(screen, contains('this.markReadOnOpen = false'));
    expect(screen, isNot(contains('service.markHistorySeen()')));
    final settingsStart = screen.indexOf(
      'class _NotificationSettingsScreenState',
    );
    final settingsEnd = screen.indexOf(
      'Future<void> _refreshStatus',
      settingsStart,
    );
    expect(settingsStart, greaterThanOrEqualTo(0));
    expect(settingsEnd, greaterThan(settingsStart));
    expect(
      screen.substring(settingsStart, settingsEnd),
      isNot(contains('markAllHistoryRead')),
      reason: '打开通知设置不能把通知记录红点清成已读。',
    );
    expect(screen, contains('TextField('));
    expect(screen, contains("hintText: '搜索标题、内容或关联 ID'"));
    expect(screen, contains('NotificationType? _typeFilter'));
    expect(screen, contains('_NotificationReadFilter _readFilter'));
    expect(screen, contains('List<NotificationItem> _filteredHistory'));
    expect(screen, contains('ChoiceChip('));
    expect(screen, contains('SegmentedButton<_NotificationReadFilter>'));
    expect(screen, contains('for (final type in NotificationType.values)'));
    expect(screen, contains('_notificationTypeLabel(type)'));
    expect(screen, contains('static const _pageSize = 50;'));
    expect(screen, contains('final visibleHistory = filteredHistory.sublist'));
    expect(screen, contains('itemCount: visibleHistory.length'));
    expect(screen, contains("tooltip: '上一页'"));
    expect(screen, contains("tooltip: '下一页'"));
    expect(screen, contains('setState(_resetPaging)'));
    expect(screen, contains('ListView.separated'));
    expect(screen, contains('clearHistory()'));
    expect(screen, contains('markHistoryItemRead'));
    expect(screen, contains('markAllHistoryRead'));
    expect(screen, contains('service.unreadCount'));
    expect(screen, contains("label: item.isRead ? '已读' : '未读'"));
    expect(screen, contains('Future<void> _confirmClearHistory(int count)'));
    expect(screen, contains("title: const Text('清空通知记录？')"));
    expect(screen, contains('已调度的提醒不会被取消'));
    expect(screen, contains("const Center(child: Text('暂无通知记录'))"));
    expect(screen, contains("message: '没有匹配的通知记录'"));
    expect(screen, contains('支持搜索、筛选和分页浏览'));
    expect(screen, isNot(contains('take(10)')));
  });

  test('notification settings has an independent settings screen', () {
    final screen = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();
    final preferences = File(
      'lib/screens/preferences_screen.dart',
    ).readAsStringSync();

    expect(screen, contains('class NotificationSettingsScreen'));
    expect(screen, contains("title: const Text('通知设置')"));
    expect(screen, contains('backgroundColor: routeBackground'));
    expect(screen, contains('surfaceTintColor: Colors.transparent'));
    final settingsClassStart = screen.indexOf(
      'class _NotificationSettingsScreenState',
    );
    final settingsClassEnd = screen.indexOf(
      'Future<void> _refreshStatus',
      settingsClassStart,
    );
    expect(settingsClassStart, greaterThanOrEqualTo(0));
    expect(settingsClassEnd, greaterThan(settingsClassStart));
    final settingsInit = screen.substring(settingsClassStart, settingsClassEnd);
    expect(settingsInit, isNot(contains('service.unreadCount > 0')));
    expect(settingsInit, isNot(contains('markAllHistoryRead')));
    expect(
      preferences,
      isNot(
        contains(
          'class ReminderNotificationSettingsScreen extends StatefulWidget',
        ),
      ),
    );
    expect(preferences, isNot(contains('NotificationService')));
    expect(preferences, isNot(contains('ReminderRingtoneSettings')));
    expect(preferences, isNot(contains('setDailyReminderSlot')));
    expect(preferences, isNot(contains('setNotificationQuickAdd')));
    expect(preferences, isNot(contains('_sendStrongTest')));
    expect(screen, contains("title: '系统通知'"));
    expect(screen, contains("title: '提醒入口'"));
    expect(screen, contains("preferences.section.daily_reminder"));
    expect(screen, contains("title: '通知记录保留'"));
    expect(screen, contains('NotificationHistoryPolicy.options'));
    expect(screen, contains('setNotificationHistoryLimit'));
    expect(screen, contains('setHistoryLimit'));
    expect(screen, contains('setNotificationQuickAdd'));
    expect(screen, contains('_setNotificationStatusBarPreference'));
    expect(screen, contains('_syncNotificationStatusBarNow'));
    expect(screen, contains('preferences.notification_status_bar.sync_failed'));
    expect(screen, contains('markReadOnOpen: false'));
    expect(screen, contains('setDailyReminderSlot'));
    expect(screen, contains('ReminderRingtoneSettings'));
    expect(screen, isNot(contains('PreferencesInitialSection')));
  });

  test('notification history keeps enough records for the dedicated list', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();
    final policy = File(
      'lib/core/notification_history_policy.dart',
    ).readAsStringSync();
    final preferences = File(
      'lib/providers/preferences_provider.dart',
    ).readAsStringSync();
    final notificationScreen = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();

    expect(
      policy,
      contains("preferenceKey = 'pref_notification_history_limit'"),
    );
    expect(policy, contains('defaultLimit = 500'));
    expect(policy, contains('maxLimit = 5000'));
    expect(policy, contains('options = <int>[100, 500, 1000, 2000, 5000]'));
    expect(
      source,
      contains('int _historyLimit = NotificationHistoryPolicy.defaultLimit'),
    );
    expect(source, contains('int get historyLimit => _historyLimit'));
    expect(
      source,
      contains('p.getInt(NotificationHistoryPolicy.preferenceKey)'),
    );
    expect(source, contains('Future<void> setHistoryLimit(int value)'));
    expect(
      source,
      contains('_history.removeRange(_historyLimit, _history.length)'),
    );
    expect(source, contains('_history'));
    expect(source, contains('.take(_historyLimit)'));
    expect(source, isNot(contains('_history.take(50)')));
    expect(source, isNot(contains('_history.length > 50')));
    expect(source, isNot(contains('static const _maxHistoryItems = 500;')));
    expect(preferences, contains('int get notificationHistoryLimit'));
    expect(preferences, contains('setNotificationHistoryLimit'));
    expect(notificationScreen, contains("title: '通知记录保留'"));
    expect(notificationScreen, contains('prefs.notificationHistoryLimit'));
    expect(notificationScreen, contains('notif.setHistoryLimit'));
  });

  test('all normal notification paths are recorded in history', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();

    void expectMethodRecordsHistory(
      String startNeedle,
      String endNeedle, {
      String recordNeedle = '_addToHistory(',
    }) {
      final start = source.indexOf(startNeedle);
      final end = source.indexOf(endNeedle, start);
      expect(start, greaterThanOrEqualTo(0), reason: startNeedle);
      expect(end, greaterThan(start), reason: endNeedle);
      final method = source.substring(start, end);
      expect(method, contains(recordNeedle), reason: startNeedle);
      expect(method, contains('NotificationItem('), reason: startNeedle);
    }

    expectMethodRecordsHistory(
      'Future<void> show({',
      '/// 稍后提醒（Snooze, Task T-12）。',
    );
    expectMethodRecordsHistory(
      'Future<void> snooze({',
      '/// 通过 deep-link `duoyi://snooze/{id}?delay={minutes}` 触发的快捷路径。',
      recordNeedle: '_addScheduledToHistory(',
    );
    expectMethodRecordsHistory(
      'Future<void> scheduleOnce({',
      '/// 每日固定时间的 push 通知',
      recordNeedle: '_addScheduledToHistory(',
    );
    expectMethodRecordsHistory(
      'Future<void> scheduleDaily({',
      '/// 取消某个已调度的通知。',
      recordNeedle: '_addScheduledToHistory(',
    );
    expectMethodRecordsHistory(
      'Future<void> scheduleTodoReminder({',
      'Future<void> cancelTodoReminder',
      recordNeedle: '_addScheduledToHistory(',
    );
    expectMethodRecordsHistory(
      'Future<void> scheduleHabitReminder({',
      'Future<void> cancelHabitReminder',
      recordNeedle: '_addScheduledToHistory(',
    );
    expectMethodRecordsHistory(
      'Future<void> scheduleAnniversary({',
      'Future<void> cancelAnniversary',
      recordNeedle: '_addScheduledToHistory(',
    );

    final scheduledStart = source.indexOf('void _addScheduledToHistory');
    final scheduledEnd = source.indexOf(
      'Future<bool> ensureReadyForReminder',
      scheduledStart,
    );
    expect(scheduledStart, greaterThanOrEqualTo(0));
    expect(scheduledEnd, greaterThan(scheduledStart));
    final scheduledHelper = source.substring(scheduledStart, scheduledEnd);
    expect(scheduledHelper, contains('final record = item;'));
    expect(scheduledHelper, isNot(contains('item.copyWith(isRead: true)')));

    expect(source, contains('NotificationType.todo'));
    expect(source, contains('NotificationType.habit'));
    expect(source, contains('NotificationType.anniversary'));
  });

  test(
    'diagnostic test notification history stays read and does not light badge',
    () {
      final source = File(
        'lib/providers/notification_service.dart',
      ).readAsStringSync();
      final start = source.indexOf('Future<void> sendTest()');
      final end = source.indexOf('Future<void> sendScheduledTest', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final method = source.substring(start, end);

      expect(method, contains("title: '测试通知'"));
      expect(method, contains('isRead: true'));
      expect(method, contains('_addToHistory('));
    },
  );

  test('notification settings screen is independent from preferences', () {
    final preferences = File(
      'lib/screens/preferences_screen.dart',
    ).readAsStringSync();
    final notificationScreen = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();

    expect(notificationScreen, contains('class NotificationSettingsScreen'));
    expect(notificationScreen, contains("title: const Text('通知设置')"));
    expect(notificationScreen, contains('backgroundColor: routeBackground'));
    expect(
      notificationScreen,
      contains('surfaceTintColor: Colors.transparent'),
    );
    expect(notificationScreen, contains("title: '系统通知'"));
    expect(notificationScreen, contains("title: '普通提醒渠道'"));
    expect(notificationScreen, contains("title: '强提醒渠道'"));
    expect(notificationScreen, contains("title: '闹钟降级兜底'"));
    expect(notificationScreen, contains('强提醒或内置铃声注册失败时会改用普通提醒'));
    expect(notificationScreen, contains('普通提醒渠道静音，兜底也可能无声'));
    expect(notificationScreen, contains("title: '内置铃声状态渠道'"));
    expect(notificationScreen, contains("title: '1 分钟后普通定时'"));
    expect(notificationScreen, contains("title: '1 分钟后弹出测试'"));
    expect(notificationScreen, contains("title: '1 分钟后闹钟测试'"));
    expect(notificationScreen, contains("title: '1 分钟后全屏闹钟'"));
    expect(notificationScreen, contains("title: '1 分钟后默认方式'"));
    expect(notificationScreen, contains("title: '已注册提醒明细'"));
    expect(notificationScreen, contains('registeredRemindersSnapshot()'));
    expect(notificationScreen, contains('_RegisteredReminderDetailRow'));
    expect(
      notificationScreen,
      isNot(contains('_RegisteredReminderSnapshotRow')),
    );
    expect(notificationScreen, isNot(contains('队列 ID')));
    expect(
      notificationScreen,
      contains('NativeReminderRingtone.statusChannelId'),
    );
    expect(notificationScreen, contains('AlarmService.channelId'));
    expect(notificationScreen, contains('sendScheduledTest('));
    expect(
      notificationScreen,
      contains('NotificationSettings.notificationChannelStatuses'),
    );
    expect(
      notificationScreen,
      contains('Map<String, NotificationChannelStatus>'),
    );
    expect(notificationScreen, contains('_channelStatusLabel'));
    expect(notificationScreen, contains('_channelStatusTrailing'));
    expect(notificationScreen, contains("'声音正常'"));
    expect(notificationScreen, contains("'已静音'"));
    expect(notificationScreen, contains("'已关闭'"));
    expect(notificationScreen, contains("'未创建'"));
    expect(notificationScreen, contains("title: '提醒入口'"));
    expect(notificationScreen, contains("preferences.section.daily_reminder"));
    expect(notificationScreen, contains("title: '通知记录保留'"));
    expect(notificationScreen, contains('setNotificationHistoryLimit'));
    expect(notificationScreen, contains('setHistoryLimit'));
    expect(notificationScreen, contains('setNotificationQuickAdd'));
    expect(notificationScreen, contains('_setNotificationStatusBarPreference'));
    expect(notificationScreen, contains('_syncNotificationStatusBarNow'));
    expect(notificationScreen, contains('setDailyReminderSlot'));
    expect(notificationScreen, contains('ReminderRingtoneSettings'));
    expect(notificationScreen, isNot(contains('PreferencesInitialSection')));
    expect(preferences, isNot(contains('showAppModalSheet<void>')));
  });

  test('scheduled diagnostic test supports reminder mode routing', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> sendScheduledTest');
    final end = source.indexOf('void notifyAchievementUnlocked', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final method = source.substring(start, end);

    expect(method, contains('ReminderKind reminderKind = ReminderKind.push'));
    expect(method, contains('bool fullScreenAlarm = true'));
    expect(method, contains('_scheduledDiagnosticIdFor('));
    expect(method, contains('_cancelScheduledDiagnosticAcrossChannels('));
    expect(method, contains('_scheduleOnceOrRecord('));
    expect(method, contains('_schedulePopupDiagnosticOrRecord('));
    expect(method, contains('_scheduleAlarmDiagnosticOrRecord('));
    expect(method, contains('alarm.scheduleFullScreen('));
    expect(method, contains('fullScreen: fullScreenAlarm'));
    expect(method, contains('snoozeMinutes: fullScreen ? 5 : 0'));
    expect(method, contains('popup.scheduleOnce('));
  });

  test('scheduled notifications require permission before registering', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();
    final local = File(
      'lib/services/local_notifications_io.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<bool> _scheduleOnceOrRecord');
    final end = source.indexOf('Future<bool> _scheduleDailyOrRecord', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final helper = source.substring(start, end);

    final scheduleIndex = helper.indexOf(
      'LocalNotifications.instance.scheduleOnce',
    );
    final permissionCatchIndex = helper.indexOf(
      'on NotificationPermissionDeniedException',
    );
    expect(scheduleIndex, greaterThanOrEqualTo(0));
    expect(permissionCatchIndex, greaterThan(scheduleIndex));
    expect(helper, contains('系统通知权限未开启，提醒未注册'));
    expect(
      helper,
      isNot(contains('LocalNotifications.instance.ensurePermission')),
    );
    final localStart = local.indexOf('Future<void> scheduleOnce({');
    final localEnd = local.indexOf('/// 每日固定时间', localStart);
    expect(localStart, greaterThanOrEqualTo(0));
    expect(localEnd, greaterThan(localStart));
    expect(local.substring(localStart, localEnd), contains("'scheduleOnce',"));
    expect(
      local.substring(localStart, localEnd),
      contains('requestIfNeeded: requestIfNeeded'),
    );
  });

  test('daily reminders require permission before registering', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();
    final local = File(
      'lib/services/local_notifications_io.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<bool> _scheduleDailyOrRecord');
    final end = source.indexOf('String _notificationBodyForPayload', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final helper = source.substring(start, end);

    final scheduleIndex = helper.indexOf(
      'LocalNotifications.instance.scheduleDaily',
    );
    final permissionCatchIndex = helper.indexOf(
      'on NotificationPermissionDeniedException',
    );
    expect(scheduleIndex, greaterThanOrEqualTo(0));
    expect(permissionCatchIndex, greaterThan(scheduleIndex));
    expect(helper, contains('系统通知权限未开启，重复提醒未注册'));
    expect(
      helper,
      isNot(contains('LocalNotifications.instance.ensurePermission')),
    );
    final localStart = local.indexOf('Future<void> scheduleDaily({');
    final localEnd = local.indexOf('int _subId', localStart);
    expect(localStart, greaterThanOrEqualTo(0));
    expect(localEnd, greaterThan(localStart));
    expect(local.substring(localStart, localEnd), contains("'scheduleDaily',"));
    expect(
      local.substring(localStart, localEnd),
      contains('requestIfNeeded: requestIfNeeded'),
    );
  });

  test(
    'local notification schedules log pending queue verification after enqueue',
    () {
      final local = File(
        'lib/services/local_notifications_io.dart',
      ).readAsStringSync();

      final onceStart = local.indexOf('Future<void> scheduleOnce({');
      final onceEnd = local.indexOf('/// 每日固定时间', onceStart);
      expect(onceStart, greaterThanOrEqualTo(0));
      expect(onceEnd, greaterThan(onceStart));
      final once = local.substring(onceStart, onceEnd);
      expect(
        once,
        contains("_ensureAndroidFallbackChannelsForOperation('scheduleOnce')"),
      );
      expect(
        once,
        contains(
          "_cancelPluginNotificationOnly(id, operation: 'scheduleOnce replace')",
        ),
      );
      expect(
        once.indexOf('_cancelPluginNotificationOnly'),
        lessThan(once.indexOf('_plugin.zonedSchedule(')),
        reason: '同一 id 重复注册前必须先清理旧队列，但清理失败不能阻断新注册。',
      );
      expect(once, contains('_logPendingVerification('));
      expect(
        once.indexOf('_plugin.zonedSchedule('),
        lessThan(once.indexOf('_logPendingVerification(')),
      );
      expect(once, isNot(contains('strict: true')));
      expect(once, isNot(contains('await _cancelScheduledIds(<int>{id});')));

      final dailyStart = local.indexOf('Future<void> scheduleDaily({');
      final dailyEnd = local.indexOf(
        'Future<void> _scheduleRepeating',
        dailyStart,
      );
      expect(dailyStart, greaterThanOrEqualTo(0));
      expect(dailyEnd, greaterThan(dailyStart));
      final daily = local.substring(dailyStart, dailyEnd);
      expect(
        daily,
        contains("_ensureAndroidFallbackChannelsForOperation('scheduleDaily')"),
      );
      expect(
        daily,
        contains(
          "_cancelPluginNotificationOnly(id, operation: 'scheduleDaily replace')",
        ),
      );
      expect(
        daily.indexOf('_cancelPluginNotificationOnly'),
        lessThan(daily.indexOf('_scheduleRepeating(')),
        reason: '重复提醒重入注册前必须清理 base id 和 weekday 子 id，但清理失败不能阻断新注册。',
      );
      expect(daily, contains('final expectedIds = <int>{};'));
      expect(daily, contains('expectedIds.add(id);'));
      expect(daily, contains('expectedIds.add(subId);'));
      expect(daily, contains('_logPendingVerification('));
      expect(daily, isNot(contains('strict: true')));
      expect(daily, isNot(contains('重复提醒注册后未出现在待触发队列，提醒未确认成功')));
      expect(
        daily,
        contains('await _cancelScheduledIds(expectedIds);'),
        reason: '真正的调度异常仍要清理本轮已注册的子任务，避免半成功队列残留。',
      );

      final replaceCleanupStart = local.indexOf(
        'Future<void> _cancelPluginNotificationOnly(',
      );
      final onceStartAfterCleanup = local.indexOf(
        'Future<void> scheduleOnce({',
        replaceCleanupStart,
      );
      expect(replaceCleanupStart, greaterThanOrEqualTo(0));
      expect(onceStartAfterCleanup, greaterThan(replaceCleanupStart));
      final replaceCleanup = local.substring(
        replaceCleanupStart,
        onceStartAfterCleanup,
      );
      expect(replaceCleanup, contains('var skipPluginCleanup = false'));
      expect(replaceCleanup, contains('_isPendingIntentLimitExceeded(e)'));
      expect(replaceCleanup, contains('skipPluginCleanup = true'));
      expect(
        replaceCleanup,
        contains('await NativeReminderRingtone.cancel(queueId);'),
        reason:
            '插件 cancel 触发 Android PendingIntent 上限后，要停止继续插件取消并走 no-create 原生清理。',
      );

      final helperStart = local.indexOf(
        'Future<void> _logPendingVerification(',
      );
      final helperEnd = local.indexOf(
        'static bool _isExactAlarmDenied',
        helperStart,
      );
      expect(helperStart, greaterThanOrEqualTo(0));
      expect(helperEnd, greaterThan(helperStart));
      final helper = local.substring(helperStart, helperEnd);
      expect(helper, contains('_plugin.pendingNotificationRequests()'));
      expect(helper, contains('expected.difference(actual)'));
      expect(helper, isNot(contains('bool strict = false')));
      expect(helper, isNot(contains('await _cancelScheduledIds(expected);')));
      expect(helper, isNot(contains('throw StateError')));
      expect(helper, contains('debugPrint'));

      final channelGuardStart = local.indexOf(
        'Future<void> _ensureAndroidFallbackChannelsForOperation',
      );
      final channelGuardEnd = local.indexOf(
        'Future<void> _ensureAndroidFallbackChannelSound',
        channelGuardStart,
      );
      expect(channelGuardStart, greaterThanOrEqualTo(0));
      expect(channelGuardEnd, greaterThan(channelGuardStart));
      final channelGuard = local.substring(channelGuardStart, channelGuardEnd);
      expect(channelGuard, contains('try {'));
      expect(channelGuard, contains('await _ensureAndroidFallbackChannels();'));
      expect(
        channelGuard,
        contains('channel setup failed; continuing'),
        reason:
            'Channel recreation failures should be diagnostic-only; the '
            'registration attempt still gets a chance to run.',
      );
      expect(channelGuard, isNot(contains('rethrow')));
    },
  );

  test(
    'local notification permission probes Android app switch and pending IDs initialize plugin',
    () {
      final local = File(
        'lib/services/local_notifications_io.dart',
      ).readAsStringSync();
      final service = File(
        'lib/providers/notification_service.dart',
      ).readAsStringSync();

      final requestStart = local.indexOf('Future<bool> requestPermission()');
      final probeStart = local.indexOf('Future<void> _probePermission()');
      final ensureStart = local.indexOf(
        'Future<void> _ensureDeliveryPermission',
      );
      expect(requestStart, greaterThanOrEqualTo(0));
      expect(probeStart, greaterThan(requestStart));
      expect(ensureStart, greaterThan(probeStart));
      final permissionBlock = local.substring(requestStart, ensureStart);
      expect(
        permissionBlock,
        contains('_requestAndroidNotificationPermission()'),
      );
      expect(permissionBlock, contains('_androidNotificationsEnabled()'));
      expect(permissionBlock, contains('areNotificationsEnabled()'));
      expect(
        permissionBlock,
        contains('_permissionHandlerNotificationGranted('),
      );
      expect(permissionBlock, contains('_combineKnownPermissionSignals('));
      expect(
        permissionBlock,
        contains('if (signals.isEmpty) return false;'),
        reason:
            'Android 13+ permission probes that all fail must not be treated as granted.',
      );

      final pendingStart = local.indexOf('Future<List<int>> pendingIds()');
      final launchPayloadStart = local.indexOf(
        'String? takeLaunchPayload()',
        pendingStart,
      );
      expect(pendingStart, greaterThanOrEqualTo(0));
      expect(launchPayloadStart, greaterThan(pendingStart));
      final pendingIds = local.substring(pendingStart, launchPayloadStart);
      expect(pendingIds, contains('if (!_initialized) await init();'));
      expect(pendingIds, contains('pendingIds failed'));
      expect(pendingIds, contains('return <int>[];'));
      expect(pendingIds, isNot(contains('return const [];')));

      final initStart = service.indexOf('Future<void> init() async');
      final requestPermissionStart = service.indexOf(
        'Future<bool> requestPermission()',
        initStart,
      );
      expect(initStart, greaterThanOrEqualTo(0));
      expect(requestPermissionStart, greaterThan(initStart));
      final initBlock = service.substring(initStart, requestPermissionStart);
      expect(initBlock, contains('try {'));
      expect(initBlock, contains('LocalNotifications.instance.init()'));
      expect(initBlock, contains('local notification init failed'));
      expect(initBlock, contains('_recordScheduleIssue('));
      expect(initBlock, contains('await _loadHistory();'));

      final refreshStart = service.indexOf('Future<bool> refreshPermission()');
      final saveHistoryStart = service.indexOf(
        'Future<void> _saveHistory()',
        refreshStart,
      );
      expect(refreshStart, greaterThanOrEqualTo(0));
      expect(saveHistoryStart, greaterThan(refreshStart));
      final refresh = service.substring(refreshStart, saveHistoryStart);
      expect(
        refresh,
        contains('granted && _lastScheduleIssueIsPermissionOnly'),
      );
      expect(refresh, contains('_clearScheduleIssueState();'));
    },
  );

  test('failed schedule attempts are not counted as pending or history', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();

    void expectPublicScheduleGuardsSuccess(
      String startNeedle,
      String endNeedle, {
      required String scheduleCall,
      bool incrementsPending = true,
    }) {
      final start = source.indexOf(startNeedle);
      final end = source.indexOf(endNeedle, start);
      expect(start, greaterThanOrEqualTo(0), reason: startNeedle);
      expect(end, greaterThan(start), reason: endNeedle);
      final method = source.substring(start, end);

      final scheduledIndex = method.indexOf(scheduleCall);
      final guardIndex = method.indexOf('if (!scheduled) return;');
      final pendingIndex = method.indexOf('_pendingNotifications++;');
      final historyIndex = method.indexOf('_addScheduledToHistory(');
      expect(scheduledIndex, greaterThanOrEqualTo(0), reason: startNeedle);
      expect(guardIndex, greaterThan(scheduledIndex), reason: startNeedle);
      if (incrementsPending) {
        expect(pendingIndex, greaterThan(guardIndex), reason: startNeedle);
      } else {
        expect(pendingIndex, lessThan(0), reason: startNeedle);
      }
      expect(historyIndex, greaterThan(guardIndex), reason: startNeedle);
    }

    expectPublicScheduleGuardsSuccess(
      'Future<void> snooze({',
      '/// 通过 deep-link `duoyi://snooze/{id}?delay={minutes}` 触发的快捷路径。',
      scheduleCall: '_scheduleOnceOrRecord(',
    );
    expectPublicScheduleGuardsSuccess(
      'Future<void> scheduleOnce({',
      '/// 每日固定时间的 push 通知',
      scheduleCall: '_scheduleOnceOrRecord(',
    );
    expectPublicScheduleGuardsSuccess(
      'Future<void> scheduleDaily({',
      '/// 取消某个已调度的通知。',
      scheduleCall: '_scheduleDailyOrRecord(',
    );
    expectPublicScheduleGuardsSuccess(
      'Future<void> scheduleTodoReminder({',
      'Future<void> cancelTodoReminder',
      scheduleCall: '_scheduleOnceOrRecord(',
    );
    expectPublicScheduleGuardsSuccess(
      'Future<void> scheduleHabitReminder({',
      'Future<void> cancelHabitReminder',
      scheduleCall: '_scheduleDailyOrRecord(',
    );
    expectPublicScheduleGuardsSuccess(
      'Future<void> scheduleAnniversary({',
      'Future<void> cancelAnniversary',
      scheduleCall: '_scheduleOnceOrRecord(',
    );
  });

  test('scheduled history records infer todo/habit type from payload', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();

    void expectPayloadTypedHistory(String startNeedle, String endNeedle) {
      final start = source.indexOf(startNeedle);
      final end = source.indexOf(endNeedle, start);
      expect(start, greaterThanOrEqualTo(0), reason: startNeedle);
      expect(end, greaterThan(start), reason: endNeedle);
      final method = source.substring(start, end);
      final historyIndex = method.indexOf('_addScheduledToHistory(');
      expect(historyIndex, greaterThanOrEqualTo(0), reason: startNeedle);
      expect(
        method.substring(historyIndex),
        contains('type: _historyTypeFromPayload(payload)'),
        reason:
            '$startNeedle 的调度历史必须按 payload 推断类型，'
            '否则通知记录页“点卡片跳详情”动线在真机上是断的。',
      );
    }

    // 通用 push 出口（ReminderScheduler 待办/习惯提醒的真实路径）：
    expectPayloadTypedHistory(
      'Future<bool> scheduleOnceWithResult({',
      '/// 上层（通知中心、深链处理或通知 action）调用此通用方法重新调度提醒。',
    );
    expectPayloadTypedHistory(
      'Future<void> scheduleOnce({',
      'Future<void> scheduleCalendarReminder({',
    );
    expectPayloadTypedHistory(
      'Future<bool> scheduleDailyWithResult({',
      '/// 每日固定时间的 push 通知',
    );
    expectPayloadTypedHistory(
      'Future<void> scheduleDaily({',
      '/// 取消某个已调度的通知。',
    );
    // “稍后提醒”沿用原 payload，应保持同样的类型标注。
    expectPayloadTypedHistory(
      'Future<void> snooze({',
      '/// 通过 deep-link `duoyi://snooze/{id}?delay={minutes}` 触发的快捷路径。',
    );

    // snooze / scheduleOnce / scheduleDaily 三处原本不带 relatedId，
    // 必须从 payload 补齐，否则跳详情拿不到对象 id。
    for (final needle in [
      'Future<void> snooze({',
      'Future<void> scheduleOnce({',
      'Future<void> scheduleDaily({',
    ]) {
      final start = source.indexOf(needle);
      expect(start, greaterThanOrEqualTo(0), reason: needle);
      final method = source.substring(start);
      expect(
        method.substring(method.indexOf('_addScheduledToHistory(')),
        contains('relatedId: _relatedIdFromPayload(payload)'),
        reason: needle,
      );
    }

    // 推断规则：todo/habit deep-link 分别落到对应类型，其余保持 general。
    expect(
      source,
      contains("'todo' => NotificationType.todo"),
      reason: '缺少 todo payload 的类型推断',
    );
    expect(
      source,
      contains("'habit' => NotificationType.habit"),
      reason: '缺少 habit payload 的类型推断',
    );
    expect(source, contains('_ => NotificationType.general'));
  });

  test(
    'schedule helper records permission and plugin failures without crashing callers',
    () {
      final source = File(
        'lib/providers/notification_service.dart',
      ).readAsStringSync();

      final onceStart = source.indexOf('Future<bool> _scheduleOnceOrRecord');
      final onceEnd = source.indexOf(
        'Future<bool> _scheduleDailyOrRecord',
        onceStart,
      );
      final dailyStart = source.indexOf('Future<bool> _scheduleDailyOrRecord');
      final dailyEnd = source.indexOf(
        'String _notificationBodyForPayload',
        dailyStart,
      );
      expect(onceStart, greaterThanOrEqualTo(0));
      expect(onceEnd, greaterThan(onceStart));
      expect(dailyStart, greaterThanOrEqualTo(0));
      expect(dailyEnd, greaterThan(dailyStart));

      for (final helper in [
        source.substring(onceStart, onceEnd),
        source.substring(dailyStart, dailyEnd),
      ]) {
        expect(helper, contains('on NotificationPermissionDeniedException'));
        expect(helper, contains('catch (e, st)'));
        expect(helper, contains('debugPrint('));
        expect(helper, contains('_recordScheduleIssue('));
        expect(helper, contains('return false;'));
        expect(helper, isNot(contains('rethrow;')));
      }
      expect(
        source.substring(onceStart, onceEnd),
        contains('if (!when.isAfter(now))'),
      );
      expect(
        source.substring(onceStart, onceEnd),
        isNot(contains('throw NotificationPermissionDeniedException')),
      );
    },
  );

  test(
    'alarm push fallback records a visible diagnostic on successful push registration',
    () {
      final source = File(
        'lib/providers/notification_service.dart',
      ).readAsStringSync();
      final scheduler = File(
        'lib/services/reminder_scheduler.dart',
      ).readAsStringSync();
      final todoDetail = File(
        'lib/screens/todo_detail_screen.dart',
      ).readAsStringSync();

      expect(source, contains('bool _isAlarmPushFallbackPayload'));
      expect(source, contains("queryParameters['fallback'] == 'push'"));
      expect(source, contains('void _recordAlarmPushFallback'));
      expect(source, contains('闹钟提醒已降级为普通通知'));
      expect(source, contains('强提醒或内置铃声注册失败，已改用普通通知提醒'));
      expect(source, contains('普通提醒渠道声音'));
      expect(source, contains("_relatedIdFromPayload(payload)"));

      final onceStart = source.indexOf('Future<void> scheduleOnce({');
      final onceEnd = source.indexOf('/// 每日固定时间的 push 通知', onceStart);
      expect(onceStart, greaterThanOrEqualTo(0));
      expect(onceEnd, greaterThan(onceStart));
      final once = source.substring(onceStart, onceEnd);
      expect(once, contains('_isAlarmPushFallbackPayload(payload)'));
      expect(once, contains("_recordAlarmPushFallback("));
      expect(once, contains("issueTitle: '提醒注册降级'"));

      final dailyStart = source.indexOf('Future<void> scheduleDaily({');
      final dailyEnd = source.indexOf('/// 取消某个已调度的通知。', dailyStart);
      expect(dailyStart, greaterThanOrEqualTo(0));
      expect(dailyEnd, greaterThan(dailyStart));
      final daily = source.substring(dailyStart, dailyEnd);
      expect(daily, contains('_isAlarmPushFallbackPayload(payload)'));
      expect(daily, contains("_recordAlarmPushFallback("));
      expect(daily, contains("issueTitle: '重复提醒注册降级'"));

      expect(scheduler, contains("..['fallback'] = 'push'"));
      expect(scheduler, contains("..remove('confirm')"));
      expect(
        todoDetail,
        isNot(
          contains("context.read<NotificationService?>()?.lastScheduleIssue"),
        ),
      );
      expect(
        todoDetail,
        isNot(contains("content: Text('\${issue.title}：\${issue.message}')")),
      );
    },
  );

  test(
    'daily digest reminders use repeating schedule unless holiday pause is on',
    () {
      final source = File('lib/main.dart').readAsStringSync();
      final start = source.indexOf('Future<void> _syncDailyDigestReminder');
      final end = source.indexOf('DateTime _nextDailyReminderTime', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final method = source.substring(start, end);

      expect(method, contains('notification.scheduleDaily('));
      expect(method, contains('Future<void> schedulePushFallback()'));
      expect(method, contains('await schedulePushFallback();'));
      expect(method, contains('fallback to push'));
      expect(method, contains('_dailyDigestAlarmQueueAlreadyOwns('));
      expect(method, contains('daily repeating digest'));
      expect(method, contains('daily one-shot digest'));
      expect(method, contains('alarm queue already registered'));
      expect(
        method,
        contains('skip push fallback to avoid duplicate delivery'),
      );
      expect(method, contains('Set<int> _dailyDigestExpectedAlarmIds'));
      expect(method, contains('int _dailyDigestSubId'));
      expect(method, contains('if (slot.pauseHolidays)'));
      expect(method, contains('_scheduleHolidayAwareDailyDigest('));
      expect(method, contains('notification.scheduleOnce('));
      expect(method, contains('_dailyDigestHolidayWindowDays'));
      expect(method, isNot(contains('derived < 14')));
      expect(method, isNot(contains('scheduled < 14')));
      expect(
        method.indexOf('notification.scheduleDaily('),
        greaterThan(method.indexOf('if (slot.pauseHolidays)')),
      );
    },
  );

  test('immediate diagnostic test uses ordinary notification path', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> sendTest');
    final end = source.indexOf('Future<void> sendScheduledTest', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final method = source.substring(start, end);

    expect(
      method,
      contains('LocalNotifications.diagnosticNotificationId'),
      reason: '连续点测试通知时应更新同一条系统通知，不能堆出两条。',
    );
    expect(method, contains('LocalNotifications.instance.show'));
    expect(
      method,
      contains("_ensureChannelReadyOrRecord(issueTitle: '普通通知测试异常')"),
    );
    expect(method, contains('LocalNotifications.instance.refreshPermission()'));
    expect(method, contains('系统通知权限未开启，测试通知未发送'));
    expect(method, contains('测试通知发送失败'));
    expect(method, contains('return;'));
    expect(method, isNot(contains('rethrow;')));
    expect(method, contains('多仪 · 通知测试'));
    expect(method, isNot(contains('AlarmService.instance.showFullScreenTest')));
    expect(method, isNot(contains('HapticFeedback.vibrate')));
    expect(method, isNot(contains('LocalNotifications.instance.scheduleOnce')));
  });

  test(
    'strong reminder diagnostic is wired outside ordinary notification test',
    () {
      final prefs = File(
        'lib/screens/notification_history_screen.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final preferences = File(
        'lib/screens/preferences_screen.dart',
      ).readAsStringSync();
      final card = File(
        'lib/widgets/notification_health_card.dart',
      ).readAsStringSync();

      expect(prefs, contains('Future<void> _sendStrongTest()'));
      for (final methodName in const [
        '_sendTest',
        '_sendScheduledDiagnostic',
        '_sendStrongTest',
      ]) {
        final start = prefs.indexOf('Future<void> $methodName');
        final end = prefs.indexOf('\n  Future<void>', start + 1);
        expect(start, greaterThanOrEqualTo(0), reason: methodName);
        expect(end, greaterThan(start), reason: methodName);
        final method = prefs.substring(start, end);
        expect(method, contains('if (_busy) return;'), reason: methodName);
        expect(
          method,
          contains('setState(() => _busy = true);'),
          reason: methodName,
        );
        expect(
          method,
          contains(
            'finally {\n      if (mounted) setState(() => _busy = false);',
          ),
          reason: methodName,
        );
      }
      expect(prefs, contains('AlarmService.instance.showFullScreenTest()'));
      final scheduledStart = prefs.indexOf('Future<void> _sendScheduledTest()');
      final scheduledEnd = prefs.indexOf(
        'Future<void> _sendStrongTest()',
        scheduledStart,
      );
      expect(scheduledStart, greaterThanOrEqualTo(0));
      expect(scheduledEnd, greaterThan(scheduledStart));
      final scheduledTest = prefs.substring(scheduledStart, scheduledEnd);
      expect(
        scheduledTest,
        contains('final service = context.read<NotificationService>();'),
      );
      expect(
        scheduledTest,
        contains('final granted = await service.requestPermission();'),
      );
      expect(
        scheduledTest,
        contains('throw const NotificationPermissionDeniedException();'),
      );
      expect(
        scheduledTest.indexOf('service.requestPermission()'),
        lessThan(scheduledTest.indexOf('service.sendScheduledTest(')),
      );
      expect(scheduledTest, contains('_scheduledTestReminderKind(context)'));
      expect(scheduledTest, contains('context.read<ReminderScheduler?>()'));
      expect(scheduledTest, contains('reminderKind: kind'));
      expect(scheduledTest, contains('fullScreenAlarm: fullScreenAlarm'));
      expect(scheduledTest, contains('popup: scheduler?.popup'));
      expect(scheduledTest, contains('alarm: scheduler?.alarm'));
      expect(prefs, contains('Future<void> _sendScheduledPushTest()'));
      expect(prefs, contains('Future<void> _sendScheduledPopupTest()'));
      expect(prefs, contains('Future<void> _sendScheduledAlarmTest()'));
      expect(
        prefs,
        contains('Future<void> _sendScheduledFullScreenAlarmTest()'),
      );
      expect(scheduledTest, contains('hasExactAlarmPermission()'));
      expect(scheduledTest, contains('requestExactAlarmPermission()'));
      expect(scheduledTest, contains('hasFullScreenIntentPermission()'));
      expect(scheduledTest, contains('requestFullScreenIntentPermission()'));

      final strongStart = prefs.indexOf('Future<void> _sendStrongTest()');
      final strongEnd = prefs.indexOf(
        'Future<void> _openSystemSettings',
        strongStart,
      );
      expect(strongStart, greaterThanOrEqualTo(0));
      expect(strongEnd, greaterThan(strongStart));
      final strongTest = prefs.substring(strongStart, strongEnd);
      expect(
        strongTest,
        contains(
          'final notificationGranted = await service.requestPermission();',
        ),
      );
      expect(strongTest, contains('hasExactAlarmPermission()'));
      expect(strongTest, contains('requestExactAlarmPermission()'));
      expect(strongTest, contains('hasFullScreenIntentPermission()'));
      expect(strongTest, contains('requestFullScreenIntentPermission()'));
      expect(strongTest, contains('_strongTestMessage('));
      expect(prefs, contains('String _strongTestMessage({'));
      expect(prefs, contains('全屏提醒权限'));
      expect(prefs, contains('onTap: _busy ? null : _sendStrongTest'));
      expect(preferences, isNot(contains('_sendStrongTest')));
      expect(preferences, isNot(contains('showFullScreenTest')));
      expect(card, contains('测试强提醒铃声'));
      expect(card, contains('onSendStrongTest'));
    },
  );

  test('diagnostic scheduled tests use fixed reserved ids per channel', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();
    final scheduler = File(
      'lib/services/reminder_scheduler.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> sendScheduledTest');
    final end = source.indexOf('void notifyAchievementUnlocked', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final method = source.substring(start, end);

    expect(
      method,
      contains('LocalNotifications.scheduledDiagnosticNotificationId'),
      reason: '重复注册定时测试时应替换同一条测试通知，不应保留两条。',
    );
    expect(
      source,
      contains('LocalNotifications.scheduledDiagnosticNotificationId,'),
      reason: '普通定时诊断 ID 也必须避让业务提醒 hash，避免测试队列和业务队列撞号。',
    );
    expect(
      source,
      contains('_scheduledPopupDiagnosticNotificationId = 919005'),
    );
    expect(
      source,
      contains('_scheduledAlarmDiagnosticNotificationId = 919006'),
    );
    expect(
      source,
      contains('_scheduledFullScreenDiagnosticNotificationId = 919007'),
    );
    expect(source, contains('_diagnosticNotificationIds'));
    expect(source, contains('_scheduledDiagnosticIdFor('));
    expect(source, contains('_diagnosticReminderTitle('));
    expect(source, contains('多仪 · 弹出提醒测试'));
    expect(source, contains('多仪 · 闹钟测试'));
    expect(source, contains('多仪 · 全屏闹钟测试'));
    expect(method, contains('_scheduleOnceOrRecord('));
    expect(method, contains('_schedulePopupDiagnosticOrRecord('));
    expect(method, contains('_scheduleAlarmDiagnosticOrRecord('));
    expect(method, contains('fullScreen: fullScreenAlarm'));
    expect(method, contains('_cancelScheduledDiagnosticAcrossChannels('));
    for (final id in const [919005, 919006, 919007]) {
      expect(scheduler, contains('$id'));
    }
  });

  test('location reminders use local notification, history and deep link', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();
    final start = source.indexOf('void notifyLocationReminderHit');
    final end = source.indexOf('/// 调度一次性待办到期提醒', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final method = source.substring(start, end);

    expect(method, contains('_showImmediate'));
    expect(method, contains('NotificationType.location'));
    expect(method, contains('relatedId: reminder.id'));
    expect(method, contains("return 'duoyi://location/"));
    expect(method, contains("return 'duoyi://todo/"));
    expect(method, contains("return 'duoyi://goal/"));
  });

  test('immediate notifications use one local notification outlet only', () {
    final source = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();

    expect(
      source,
      isNot(contains("import '../services/desktop_notification.dart';")),
    );
    expect(source, isNot(contains('DesktopNotification')));
    expect(source, isNot(contains('_desktopShow')));
    expect(source, isNot(contains('desktopReady')));
    expect(source, contains('int _ephemeralNotificationId()'));
    expect(
      source,
      contains('return _avoidReservedNotificationId('),
      reason: '时间戳生成的测试/番茄钟通知也必须避开固定通知 ID。',
    );
    expect(source, contains('required int id'));
    final localNotifications = File(
      'lib/services/local_notifications_io.dart',
    ).readAsStringSync();
    expect(
      localNotifications,
      contains('static const Duration _visibleNotificationDuplicateWindow'),
      reason: 'NotificationService 之外的临时实例也必须由底层单例兜住重复弹出。',
    );
    expect(
      localNotifications,
      contains('final Map<int, DateTime> _recentVisibleNotificationIds'),
    );
    expect(
      localNotifications,
      contains(
        'final Map<String, DateTime> _recentVisibleNotificationSignatures',
      ),
    );
    expect(
      localNotifications,
      contains(
        'final Map<String, DateTime> _recentVisibleNotificationContentSignatures',
      ),
    );
    expect(
      localNotifications,
      contains('bool _reserveVisibleNotificationSlot({'),
    );
    expect(
      localNotifications,
      contains('_visibleNotificationContentSignature('),
    );
    expect(
      localNotifications,
      contains('final lastShownWithSameContent ='),
      reason: '底层单例必须兜住同内容不同 payload/id 的重复弹出。',
    );
    expect(
      localNotifications,
      contains(
        "debugPrint('[LocalNotifications] duplicate visible notification skipped')",
      ),
    );
    final showStart = localNotifications.indexOf('Future<void> show({');
    final quickAddStart = localNotifications.indexOf(
      'Future<void> showQuickAddOngoing',
      showStart,
    );
    expect(showStart, greaterThanOrEqualTo(0));
    expect(quickAddStart, greaterThan(showStart));
    final showMethod = localNotifications.substring(showStart, quickAddStart);
    expect(showMethod, contains('_reserveVisibleNotificationSlot('));
    expect(showMethod, contains('return;'));
    expect(
      showMethod,
      contains("_cancelPluginNotificationOnly(id, operation: 'show replace')"),
    );
    expect(
      showMethod.indexOf('_reserveVisibleNotificationSlot('),
      lessThan(showMethod.indexOf('_cancelPluginNotificationOnly')),
    );
    expect(
      showMethod.indexOf('_cancelPluginNotificationOnly'),
      lessThan(showMethod.indexOf('await _plugin.show(')),
      reason: '同 ID 即时通知展示前先清旧 row，但清理失败不能阻断本次展示。',
    );

    for (final range in <({String start, String end})>[
      (start: 'void notifyLocationReminderHit', end: '/// 调度一次性待办到期提醒'),
      (start: 'void notifyPomodoroComplete', end: '/// 番茄钟休息结束提示'),
      (start: 'void notifyBreakComplete', end: '/// 发送一条普通测试通知'),
      (start: 'void notifyAchievementUnlocked', end: 'void _addToHistory'),
    ]) {
      final start = source.indexOf(range.start);
      final end = source.indexOf(range.end, start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final method = source.substring(start, end);
      expect(method, contains('_showImmediate('));
      expect(
        method,
        anyOf(contains('_ephemeralNotificationId()'), contains('_idFor(')),
      );
      expect(method, contains('return;'));
      expect(method, isNot(contains('DesktopNotification')));
      expect(method, isNot(contains('_desktopShow')));
    }
  });

  test(
    'scheduled push reminders clear native alarm leftovers before enqueue',
    () {
      final local = File(
        'lib/services/local_notifications_io.dart',
      ).readAsStringSync();

      expect(local, contains('Future<void> _cancelNativeRingtoneQueue'));
      expect(local, contains('NativeReminderRingtone.cancelOrThrow(nativeId)'));
      expect(local, contains('continues after native owner cleanup'));
      expect(
        local,
        contains('must not be blocked by stale strong-reminder cleanup'),
      );

      final onceStart = local.indexOf('Future<void> scheduleOnce({');
      final dailyStart = local.indexOf(
        'Future<void> scheduleDaily({',
        onceStart,
      );
      expect(onceStart, greaterThanOrEqualTo(0));
      expect(dailyStart, greaterThan(onceStart));
      final once = local.substring(onceStart, dailyStart);

      expect(
        once,
        contains(
          "_cancelNativeRingtoneQueue(id, operation: 'scheduleOnce handoff')",
        ),
      );
      expect(
        once.indexOf('_cancelNativeRingtoneQueue'),
        lessThan(once.indexOf('_cancelPluginNotificationOnly')),
        reason: '普通通知注册前先尝试清旧强提醒队列，但失败不能阻断新通知注册。',
      );
      expect(
        once.indexOf('_cancelPluginNotificationOnly'),
        lessThan(once.indexOf('_plugin.zonedSchedule')),
      );
      expect(
        once,
        contains(
          "_cancelPluginNotificationOnly(id, operation: 'scheduleOnce replace')",
        ),
      );

      final showStart = local.indexOf('Future<void> show({');
      final quickAddStart = local.indexOf(
        'Future<void> showQuickAddOngoing({',
        showStart,
      );
      expect(showStart, greaterThanOrEqualTo(0));
      expect(quickAddStart, greaterThan(showStart));
      final show = local.substring(showStart, quickAddStart);
      expect(show, contains('Future<void> _cancelPluginNotificationOnly'));
      expect(
        show,
        contains(
          "_cancelPluginNotificationOnly(id, operation: 'show replace')",
        ),
      );
      expect(
        show,
        contains("_cancelNativeRingtoneQueue(id, operation: 'show handoff')"),
      );
      expect(
        show.indexOf('_cancelPluginNotificationOnly'),
        lessThan(show.indexOf('_plugin.show')),
      );
      expect(
        show.indexOf('_cancelNativeRingtoneQueue'),
        lessThan(show.indexOf('_plugin.show')),
      );

      final quickAddCancelStart = local.indexOf(
        'Future<void> cancelQuickAddOngoing()',
      );
      final cancelStart = local.indexOf('Future<void> cancel(int id)');
      final cancelAllStart = local.indexOf(
        'Future<void> cancelAll()',
        cancelStart,
      );
      final pendingStart = local.indexOf(
        'Future<List<int>> pendingIds()',
        cancelAllStart,
      );
      final scheduleOnceStart = local.indexOf(
        'Future<void> scheduleOnce({',
        quickAddCancelStart,
      );
      expect(quickAddCancelStart, greaterThanOrEqualTo(0));
      expect(cancelStart, greaterThan(quickAddCancelStart));
      expect(cancelAllStart, greaterThan(cancelStart));
      expect(pendingStart, greaterThan(cancelAllStart));
      expect(scheduleOnceStart, greaterThan(quickAddCancelStart));
      final cancel = local.substring(cancelStart, cancelAllStart);
      final cancelAll = local.substring(cancelAllStart, pendingStart);
      final quickAddCancel = local.substring(
        quickAddCancelStart,
        scheduleOnceStart,
      );

      expect(cancel, contains('for (final queueId in _queueIdsFor(id))'));
      expect(cancel, contains('await _plugin.cancel(queueId);'));
      expect(cancel, contains('await NativeReminderRingtone.cancel(queueId);'));
      expect(cancel, contains('Error.throwWithStackTrace'));
      expect(
        quickAddCancel,
        contains('_plugin.cancel(quickAddNotificationId)'),
      );
      expect(quickAddCancel, isNot(contains('_queueIdsFor')));
      expect(quickAddCancel, isNot(contains('NativeReminderRingtone.cancel')));
      expect(cancelAll, contains('await _plugin.cancelAll();'));
      expect(cancelAll, contains('_lastQuickAddOngoingSignature = null;'));
      expect(cancelAll, contains('_recentVisibleNotificationIds.clear();'));
      expect(cancelAll, contains('await NativeReminderRingtone.cancelAll();'));
      expect(cancelAll, contains('cancelAll native failed'));
      expect(cancelAll, contains('Error.throwWithStackTrace'));
    },
  );

  test('location notification deep link opens integrations center', () {
    final source = File('lib/main.dart').readAsStringSync();
    final start = source.indexOf("uri.host == 'location'");
    final end = source.indexOf("uri.host == 'snooze'", start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final branch = source.substring(start, end);

    expect(branch, contains('navigateTo(6, allowHidden: true)'));
    expect(
      branch,
      contains('const BrandRouteSurface(child: IntegrationsScreen())'),
    );
  });

  test('todo completion deep link completes directly with feedback', () {
    final source = File('lib/main.dart').readAsStringSync();
    final start = source.indexOf("action == 'complete_todo'");
    final end = source.indexOf("action == 'checkin_habit'", start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final branch = source.substring(start, end);
    expect(branch, contains('switch (homeWidgetTodoTargetState(target))'));
    expect(branch, contains('case HomeWidgetTodoTargetState.ready:'));

    expect(
      branch,
      contains('_completeTodoFromWidgetAction(ctx, todos, target!)'),
    );
    expect(branch, contains('navigateTo(1, allowHidden: true)'));
    expect(source, contains('todos.completeTodos([target.id])'));
    expect(source, contains('已完成：'));
    expect(branch, isNot(contains('completeTodoWithOptionalTimeRecord')));
    expect(branch, isNot(contains('todos.toggleTodo(id);')));
  });

  test(
    'snooze deep link and todo action path reuse the same reminder payload',
    () {
      final notificationService = File(
        'lib/providers/notification_service.dart',
      ).readAsStringSync();
      final localNotifications = File(
        'lib/services/local_notifications_io.dart',
      ).readAsStringSync();
      final main = File('lib/main.dart').readAsStringSync();

      final snoozeStart = notificationService.indexOf('Future<void> snooze({');
      final snoozeEnd = notificationService.indexOf(
        '/// 通过 deep-link `duoyi://snooze/{id}?delay={minutes}` 触发的快捷路径。',
        snoozeStart,
      );
      expect(snoozeStart, greaterThanOrEqualTo(0));
      expect(snoozeEnd, greaterThan(snoozeStart));
      final snoozeMethod = notificationService.substring(
        snoozeStart,
        snoozeEnd,
      );
      expect(snoozeMethod, contains('LocalNotifications.instance.cancel(id);'));
      expect(snoozeMethod, contains('DateTime.now().add(delay)'));
      expect(snoozeMethod, contains('_scheduleOnceOrRecord('));
      expect(snoozeMethod, contains('payload: payload,'));
      expect(snoozeMethod, contains("issueTitle: '稍后提醒注册失败'"));

      final handleStart = notificationService.indexOf(
        'Future<void> handleSnoozeDeepLink(Uri uri)',
      );
      final handleEnd = notificationService.indexOf(
        '/// 上层（通知中心、深链处理或通知 action）调用此通用方法重新调度提醒。',
        handleStart,
      );
      expect(handleStart, greaterThan(snoozeEnd));
      expect(handleEnd, greaterThan(handleStart));
      final handleMethod = notificationService.substring(
        handleStart,
        handleEnd,
      );
      expect(handleMethod, contains("if (uri.host != 'snooze') return;"));
      expect(
        handleMethod,
        contains(
          "final minutes = int.tryParse(uri.queryParameters['delay'] ?? '5') ?? 5;",
        ),
      );
      expect(
        handleMethod,
        contains("final payload = uri.queryParameters['payload'];"),
      );
      expect(handleMethod, contains('await snooze('));
      expect(handleMethod, contains('Duration(minutes: minutes)'));

      expect(
        localNotifications,
        contains("if (actionId.startsWith('todo_snooze_'))"),
      );
      expect(localNotifications, contains(r"duoyi://snooze/${resp.id ?? 0}"));
      expect(
        localNotifications,
        contains(r'?delay=5&payload=${Uri.encodeComponent(originalPayload)}'),
      );
      expect(localNotifications, contains(r'todo_snooze_$id'));
      expect(localNotifications, contains("I18n.tr('reminder.snooze_5min')"));
      expect(
        localNotifications,
        contains('String? _payloadForResponse(NotificationResponse resp)'),
      );
      expect(
        localNotifications,
        contains('final launchPayload = response == null'),
      );
      expect(localNotifications, contains(': _payloadForResponse(response);'));

      final snoozeBranchStart = main.indexOf("uri.host == 'snooze'");
      final snoozeBranchEnd = main.indexOf(
        "uri.host == 'action'",
        snoozeBranchStart,
      );
      expect(snoozeBranchStart, greaterThanOrEqualTo(0));
      expect(snoozeBranchEnd, greaterThan(snoozeBranchStart));
      final snoozeBranch = main.substring(snoozeBranchStart, snoozeBranchEnd);
      expect(
        snoozeBranch,
        contains('Provider.of<NotificationService>(ctx, listen: false)'),
      );
      expect(snoozeBranch, contains('ns.handleSnoozeDeepLink(uri)'));
    },
  );

  test(
    'scheduled notifications keep registering when Android reminder channel is muted',
    () {
      final source = File(
        'lib/providers/notification_service.dart',
      ).readAsStringSync();

      expect(
        source,
        contains("import '../services/notification_settings.dart';"),
      );
      final helperStart = source.indexOf(
        'Future<bool> _ensureChannelReadyOrRecord',
      );
      final helperEnd = source.indexOf(
        'Future<bool> _scheduleOnceOrRecord',
        helperStart,
      );
      expect(helperStart, greaterThanOrEqualTo(0));
      expect(helperEnd, greaterThan(helperStart));
      final helper = source.substring(helperStart, helperEnd);

      expect(
        helper,
        contains('NotificationSettings.notificationChannelStatuses'),
      );
      expect(helper, contains('status.isBlocked'));
      expect(helper, contains('status.isSilent'));
      expect(helper, contains('普通提醒渠道已关闭，提醒已注册但到点可能不会显示'));
      expect(helper, contains('普通提醒渠道声音已关闭，提醒已注册但到点可能无声'));
      expect(helper, contains('普通提醒渠道状态无法确认，提醒会继续注册'));
      expect(helper, contains('blocking: false'));
      expect(helper, contains('return true;'));

      final onceStart = source.indexOf('Future<bool> _scheduleOnceOrRecord');
      final onceEnd = source.indexOf(
        'Future<bool> _scheduleDailyOrRecord',
        onceStart,
      );
      final once = source.substring(onceStart, onceEnd);
      expect(
        once.indexOf('_ensureChannelReadyOrRecord('),
        lessThan(once.indexOf('LocalNotifications.instance.scheduleOnce')),
      );
      expect(once, contains('return false;'));
      expect(
        once,
        isNot(contains('throw NotificationPermissionDeniedException')),
      );
      expect(once, contains('channelWarningRecorded'));
      expect(once, contains('!channelWarningRecorded'));

      final readyStart = source.indexOf('Future<bool> ensureReadyForReminder');
      final readyEnd = source.indexOf(
        '// ——————————————————————————————————————————————',
        readyStart,
      );
      final ready = source.substring(readyStart, readyEnd);
      expect(ready, contains('_ensureChannelReadyOrRecord('));
    },
  );

  test(
    'todo reminder save preflight checks notification permission for alarm-only reminders',
    () {
      final source = File(
        'lib/screens/todo_detail_screen.dart',
      ).readAsStringSync();
      final start = source.indexOf('Future<bool> preflightTodoReminderSave(');
      final end = source.indexOf('Future<void> _openSystemSettings', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final method = source.substring(start, end);

      expect(method, contains('preflightTodoReminderPlan(todo)'));
      expect(
        method,
        contains('final usesPush = result.kinds.contains(ReminderKind.push);'),
      );
      expect(
        method,
        contains(
          'final usesAlarm = result.kinds.contains(ReminderKind.alarm);',
        ),
      );
      expect(
        method,
        contains(
          'final usesPopup = result.kinds.contains(ReminderKind.popup);',
        ),
      );
      expect(method, contains('if ((usesPush || usesPopup) && notif != null)'));
      final ensureReadyIndex = method.indexOf('ensureReadyForReminder(');
      expect(ensureReadyIndex, greaterThanOrEqualTo(0));
      expect(method, contains('if (usesAlarm && !usesPush && !usesPopup)'));
      expect(method, contains('LocalNotifications.instance'));
      expect(method, contains('.ensurePermission()'));
      expect(method, contains('闹钟提醒注册失败：系统通知权限未开启'));
      expect(method, contains('scheduledTime: result.firstScheduledTime'));
      expect(method, contains('relatedId: todo.id'));
      expect(method, isNot(contains('notif.requestPermission()')));
      expect(
        method.indexOf('final usesPush = result.kinds.contains'),
        lessThan(ensureReadyIndex),
      );
      expect(
        method.indexOf('final usesAlarm = result.kinds.contains'),
        lessThan(method.indexOf('if (usesAlarm && !usesPush && !usesPopup)')),
      );
    },
  );

  test(
    'AlarmService keeps native alarm ringtone when notification permission is denied',
    () {
      final source = File('lib/services/alarm_service.dart').readAsStringSync();

      final onceStart = source.indexOf(
        "await _ensureNotificationPermission('scheduleFullScreen')",
      );
      final onceEnd = source.indexOf('final androidDetails =', onceStart);
      expect(onceStart, greaterThanOrEqualTo(0));
      expect(onceEnd, greaterThan(onceStart));
      final once = source.substring(onceStart, onceEnd);
      expect(once, contains('闹钟提醒通知权限未开启'));
      expect(
        once,
        isNot(contains('await _cancelPartialScheduleAfterFailure(id);')),
      );
      expect(once, contains('if (_isAndroid && nativeRingtoneOk) return;'));
      expect(once, contains('rethrow;'));
      expect(once, contains('已保留内置闹钟铃声，提醒仍会响铃'));

      final dailyStart = source.indexOf(
        "await _ensureNotificationPermission('scheduleDailyFullScreen')",
      );
      final dailyEnd = source.indexOf(
        'final details = _notificationDetails',
        dailyStart,
      );
      expect(dailyStart, greaterThanOrEqualTo(0));
      expect(dailyEnd, greaterThan(dailyStart));
      final daily = source.substring(dailyStart, dailyEnd);
      expect(daily, contains('闹钟提醒通知权限未开启'));
      expect(
        daily,
        isNot(contains('await _cancelPartialScheduleAfterFailure(id);')),
      );
      expect(daily, contains('if (_isAndroid && nativeRingtoneOk) return;'));
      expect(daily, contains('rethrow;'));
      expect(daily, contains('已保留内置重复闹钟铃声，提醒仍会响铃'));
    },
  );

  test(
    'ReminderScheduler bridges AlarmService diagnostics into notification issue sink',
    () {
      final scheduler = File(
        'lib/services/reminder_scheduler.dart',
      ).readAsStringSync();

      expect(scheduler, contains('void _recordAlarmScheduleIssue({'));
      expect(scheduler, contains('alarm is! AlarmService'));
      expect(scheduler, contains('(alarm as AlarmService).lastScheduleIssue'));
      expect(scheduler, contains('clearReminderScheduleIssue()'));
      expect(scheduler, contains('issueSink.recordReminderScheduleIssue('));
      expect(
        scheduler,
        contains('scheduledTime: issue.scheduledTime ?? scheduledTime'),
      );
      expect(
        scheduler,
        contains('_recordAlarmScheduleIssue(relatedId: habit.id'),
      );
      expect(
        scheduler,
        contains('_recordAlarmScheduleIssue(relatedId: rule.key'),
      );
      expect(scheduler, contains('scheduledTime: payload.when'));
      expect(scheduler, contains('scheduledTime: remindAt'));
    },
  );
}
