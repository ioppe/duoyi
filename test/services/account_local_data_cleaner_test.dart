import 'dart:io';

import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('clears every declared account-scoped key', () async {
    SharedPreferences.setMockInitialValues({
      for (final key in AccountLocalDataCleaner.accountScopedKeys) key: 'stale',
    });

    await AccountLocalDataCleaner.clearSharedPreferences();

    final prefs = await SharedPreferences.getInstance();
    for (final key in AccountLocalDataCleaner.accountScopedKeys) {
      expect(prefs.containsKey(key), isFalse, reason: key);
    }
  });

  test('clears dynamic account-scoped prefixes', () async {
    SharedPreferences.setMockInitialValues({
      for (final prefix in AccountLocalDataCleaner.accountScopedPrefixes)
        '${prefix}legacy': 'stale',
      'sync_future_metadata': 'stale',
      'pref_daily_reminder_slot9_enabled': true,
      'pref_reminder_ringtone_fallback_channel_sound_duoyi_general_alerts_v18':
          'duoyi_soft',
      'pref_reminder_ringtone_fallback_channel_sound_schema_duoyi_general_alerts_v18':
          2,
      'duoyi_ics_events_work': '[{"summary":"admin calendar"}]',
      'duoyi_oauth_calendar_events_google': '[{"summary":"admin oauth"}]',
      'todos_corrupt_backup_20260607': '[{"title":"old backup"}]',
      'widget_display_mode_42': 'detailed',
    });

    await AccountLocalDataCleaner.clearSharedPreferences();

    final prefs = await SharedPreferences.getInstance();
    for (final prefix in AccountLocalDataCleaner.accountScopedPrefixes) {
      expect(prefs.containsKey('${prefix}legacy'), isFalse, reason: prefix);
    }
    expect(prefs.containsKey('sync_future_metadata'), isFalse);
    // 动态 pref 键属于设备习惯：不再声明 pref 清理前缀后必须保留。
    expect(prefs.getBool('pref_daily_reminder_slot9_enabled'), isTrue);
    expect(
      prefs.getString(
        'pref_reminder_ringtone_fallback_channel_sound_duoyi_general_alerts_v18',
      ),
      'duoyi_soft',
    );
    expect(
      prefs.getInt(
        'pref_reminder_ringtone_fallback_channel_sound_schema_duoyi_general_alerts_v18',
      ),
      2,
    );
    expect(prefs.containsKey('duoyi_ics_events_work'), isFalse);
    expect(prefs.containsKey('duoyi_oauth_calendar_events_google'), isFalse);
    expect(prefs.containsKey('todos_corrupt_backup_20260607'), isFalse);
    expect(prefs.containsKey('widget_display_mode_42'), isFalse);
  });

  test('clears account-scoped document directories only', () async {
    final root = await Directory.systemTemp.createTemp(
      'duoyi_account_cleaner_',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    for (final name
        in AccountLocalDataCleaner.accountScopedDocumentDirectories) {
      final dir = Directory('${root.path}/$name');
      await dir.create(recursive: true);
      await File('${dir.path}/admin_payload.dat').writeAsString('admin');
    }
    final deviceDir = Directory('${root.path}/device_exports');
    await deviceDir.create();
    await File('${deviceDir.path}/report.csv').writeAsString('keep');

    await AccountLocalDataCleaner.clearLocalFiles(documentsDirectory: root);

    for (final name
        in AccountLocalDataCleaner.accountScopedDocumentDirectories) {
      expect(
        await Directory('${root.path}/$name').exists(),
        isFalse,
        reason: name,
      );
    }
    expect(await File('${deviceDir.path}/report.csv').exists(), isTrue);
  });

  test('keeps device settings and current auth state', () async {
    SharedPreferences.setMockInitialValues({
      'todos': '[{"title":"admin task"}]',
      'habits': '[{"title":"admin habit"}]',
      'user_profile': '{"coin_balance":999}',
      'active_brand': 'admin-theme',
      'theme_switch_count': 12,
      'theme_unlocked_brands': <String>['admin-brand'],
      'theme_shop_state': '{"activeBrand":"admin-theme"}',
      'pref_show_lunar': false,
      'pref_first_day_of_week': 7,
      'pref_date_format': 'dd/MM/yyyy',
      'pref_bottom_nav_order': <String>['1', '0'],
      'pref_app_timezone_iana': 'Asia/Tokyo',
      'duoyi_notif_history': '[{"title":"admin notification"}]',
      'ai_review_history': '[{"summary":"admin review"}]',
      'sync_pending_local_changes': true,
      'reminder_scheduler_registry_v1': '{"1":{"title":"admin alarm"}}',
      'duoyi_locale_v1': 'zh_CN',
      'app_lock_enabled': true,
      'app_lock_pin_hash': 'device-pin',
      'app_lock_auto_minutes': 10,
      'app_lock_last_active': '2026-06-07T00:00:00.000',
      'duoyi_widget_display_mode': 'compact',
      'widget_display_mode': 'compact',
      'notification_status_bar_startup_build': 7,
      'webdav_backup_base_url': 'https://example.com/webdav',
      'webdav_backup_username': 'device-user',
      'webdav_backup_password': 'device-password',
      'webdav_backup_remote_path': '/duoyi-backups',
      'webdav_backup_filename': 'duoyi-latest.json',
      'auth_state': '{"user_id":"test","token":"test-token"}',
    });

    await AccountLocalDataCleaner.clearSharedPreferences();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('todos'), isNull);
    expect(prefs.getString('habits'), isNull);
    expect(prefs.getString('user_profile'), isNull);
    // 设备视图选择与设备习惯保留。
    expect(prefs.getString('active_brand'), 'admin-theme');
    expect(prefs.getInt('theme_switch_count'), 12);
    expect(prefs.getBool('pref_show_lunar'), isFalse);
    expect(prefs.getInt('pref_first_day_of_week'), 7);
    expect(prefs.getString('pref_date_format'), 'dd/MM/yyyy');
    expect(prefs.getStringList('pref_bottom_nav_order'), <String>['1', '0']);
    expect(prefs.getString('pref_app_timezone_iana'), 'Asia/Tokyo');
    // 账号奖励/商店状态与通知历史仍按账号清理。
    expect(prefs.getStringList('theme_unlocked_brands'), isNull);
    expect(prefs.getString('theme_shop_state'), isNull);
    expect(prefs.getString('duoyi_notif_history'), isNull);
    expect(prefs.getString('ai_review_history'), isNull);
    expect(prefs.getBool('sync_pending_local_changes'), isNull);
    expect(prefs.getString('reminder_scheduler_registry_v1'), isNull);

    expect(prefs.getString('duoyi_locale_v1'), 'zh_CN');
    expect(prefs.getBool('app_lock_enabled'), isTrue);
    expect(prefs.getString('app_lock_pin_hash'), 'device-pin');
    expect(prefs.getInt('app_lock_auto_minutes'), 10);
    expect(prefs.getString('app_lock_last_active'), '2026-06-07T00:00:00.000');
    expect(prefs.getString('duoyi_widget_display_mode'), isNull);
    expect(prefs.getString('widget_display_mode'), isNull);
    expect(prefs.getInt('notification_status_bar_startup_build'), 7);
    expect(prefs.getString('webdav_backup_base_url'), isNull);
    expect(prefs.getString('webdav_backup_username'), isNull);
    expect(prefs.getString('webdav_backup_password'), isNull);
    expect(prefs.getString('webdav_backup_remote_path'), isNull);
    expect(prefs.getString('webdav_backup_filename'), isNull);
    expect(
      prefs.getString('auth_state'),
      '{"user_id":"test","token":"test-token"}',
    );
  });

  test(
    'declares notification, alarm, geofence, AI and calendar cache keys',
    () {
      expect(
        AccountLocalDataCleaner.accountScopedKeys,
        containsAll(<String>[
          'duoyi_notif_history',
          'duoyi_notif_history_seen_at',
          'ai_review_history',
          'reminder_scheduler_registry_v1',
          'duoyi_location_reminders_v1',
          'duoyi_ics_subscriptions_v1',
          'duoyi_oauth_calendar_accounts_v1',
          'duoyi_oauth_calendar_pending_authorization_v1',
          'duoyi_caldav_write_target_v1',
          'duoyi_caldav_pushed_uids_v1',
          'duoyi_caldav_pushed_etags_v1',
          'theme_unlocked_brands',
          'theme_shop_state',
        ]),
      );
      expect(
        AccountLocalDataCleaner.accountScopedPrefixes,
        containsAll(<String>[
          'duoyi_ics_',
          'duoyi_ics_events_',
          'duoyi_oauth_calendar_',
          'duoyi_oauth_calendar_events_',
          'duoyi_caldav_',
          'widget_display_mode_',
        ]),
      );
      expect(
        AccountLocalDataCleaner.accountScopedDocumentDirectories,
        containsAll(<String>[
          'custom_focus_sounds',
          'profile_avatars',
          'avatar_cache',
        ]),
      );
    },
  );

  test('设备偏好与设备外观视图不属于账号清理范围', () {
    final accountKeys = AccountLocalDataCleaner.accountScopedKeys;
    expect(
      accountKeys.where((key) => key.startsWith('pref_')),
      isEmpty,
      reason: 'pref_* 是设备/用户习惯，不应按账号清理',
    );
    expect(
      AccountLocalDataCleaner.accountScopedPrefixes.where(
        (prefix) => prefix.startsWith('pref_'),
      ),
      isEmpty,
    );
    expect(
      AccountLocalDataCleaner.devicePreferenceKeys.intersection(accountKeys),
      isEmpty,
    );
    for (final key in const [
      'active_brand',
      'theme_switch_count',
      'pref_show_lunar',
      'pref_date_format',
      'pref_first_day_of_week',
      'pref_bottom_nav_order',
      'pref_daily_reminder_hour',
      'pref_app_timezone_iana',
      'pref_reminder_ringtone_sound',
    ]) {
      expect(
        AccountLocalDataCleaner.devicePreferenceKeys,
        contains(key),
        reason: key,
      );
    }
  });

  test(
    'account cleanup entrypoint clears native schedulers and service caches',
    () {
      final source = File('lib/main.dart').readAsStringSync();
      final block = _sourceBlock(
        source,
        'Future<void> clearAccountLocalData({required String reason}) async {',
        'String firstNonEmptyProfileText',
      );

      expect(block, contains('cloudSyncProvider.resetForAccountChange'));
      expect(block, contains('notificationService.cancelAll'));
      expect(block, contains('AlarmService.instance.cancelAll'));
      expect(block, contains('LocationGeofenceService.clearReminders()'));
      expect(block, contains('AccountLocalDataCleaner.clearSharedPreferences'));
      expect(block, contains('AccountLocalDataCleaner.clearLocalFiles'));
      expect(block, contains("'account prefs first pass'"));
      expect(block, contains("'account prefs second pass'"));
      expect(block, contains('retryLocalFilesCleanup()'));
      expect(block, contains("guardedSync('habits'"));
      expect(block, contains("guardedSync('theme'"));
      expect(block, contains("guardedSync('achievements'"));
      expect(block, contains("guardedSync('preferences'"));
      expect(block, contains("guardedSync('calendar sync'"));
      expect(block, contains('userProvider.clearAccountProfileCache()'));
      expect(block, contains("guardedSync('ai service'"));
      expect(block, contains("guardedSync('notification service'"));
      expect(block, contains('HomeWidgetService.resetAccountCache()'));
      expect(block, contains('await _pushHomeWidget('));
      expect(
        block.indexOf("'account prefs first pass'"),
        lessThan(block.indexOf("guardedSync('habits'")),
      );
      expect(
        block.indexOf("guardedSync('achievements'"),
        lessThan(block.indexOf("'account prefs second pass'")),
      );
      expect(
        block.indexOf('HomeWidgetService.resetAccountCache()'),
        lessThan(block.indexOf('await _pushHomeWidget(')),
      );
    },
  );

  test('home widget reset clears every native account payload key', () {
    final source = File(
      'lib/services/home_widget_service.dart',
    ).readAsStringSync();
    // accountPayloadDefaults 已从 const map 改为取词 getter（登出兜底文案
    // 随语言），键集合不变；锚点同步迁移为 getter 形态。
    final defaultBlock = _sourceBlock(
      source,
      'accountPayloadDefaults => <String, Object>{',
      '  };',
    );
    final savedKeys = RegExp(
      r"HomeWidget\.saveWidgetData<[^>]+>\(\s*'([^']+)'",
      multiLine: true,
    ).allMatches(source).map((match) => match.group(1)!).toSet();
    final defaultKeys = RegExp(
      r"'([^']+)'\s*:",
    ).allMatches(defaultBlock).map((match) => match.group(1)!).toSet();

    expect(
      defaultKeys,
      containsAll(savedKeys.difference({'widget_display_mode'})),
    );
    expect(defaultKeys, isNot(contains('widget_display_mode')));
    expect(defaultKeys, contains('todo_top3_1_id'));
    expect(defaultKeys, contains('calendar_month_summary'));
    expect(defaultKeys, contains('habit_quick_check_id'));
    expect(defaultKeys, contains('widget_theme_background_asset_key'));
    expect(source, contains('static Future<bool> clearAccountWidgetData()'));
    expect(source, contains('HomeWidget.saveWidgetData<bool>'));
    expect(source, contains('HomeWidget.saveWidgetData<int>'));
    expect(source, contains('HomeWidget.saveWidgetData<String>'));

    final resetBlock = _sourceBlock(
      source,
      'static void resetAccountCache() {',
      'static Future<bool> clearAccountWidgetData()',
    );
    expect(resetBlock, contains('_lastThemeSignature = \'\';'));
    expect(resetBlock, contains('_lastPushSignature = \'\';'));
    expect(resetBlock, contains('clearAccountWidgetData()'));

    final pushBlock = _sourceBlock(
      source,
      'static Future<bool> push({',
      'final signature = _pushSignature(',
    );
    expect(pushBlock, contains('await _drainPendingAccountClear();'));
  });

  test('service reset methods drop in-memory account state', () {
    final notification = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();
    final notificationReset = _sourceBlock(
      notification,
      'void resetLocalState() {',
      'void clearScheduleIssue()',
    );
    expect(notificationReset, contains('_pomodoroNotificationTimer?.cancel()'));
    expect(notificationReset, contains('_pendingNotifications = 0'));
    expect(notificationReset, contains('_history.clear()'));
    expect(notificationReset, contains('_historyLastSeenAt = null'));
    expect(notificationReset, contains('_clearScheduleIssueState()'));

    final ai = File('lib/services/ai_service.dart').readAsStringSync();
    final aiReset = _sourceBlock(
      ai,
      'void resetLocalState() {',
      'Future<void> _saveHistory()',
    );
    expect(aiReset, contains('_reviewHistory = []'));

    final calendar = File(
      'lib/services/calendar_sync_service.dart',
    ).readAsStringSync();
    final calendarReset = _sourceBlock(
      calendar,
      'void resetLocalState() {',
      'Future<void> addSubscription',
    );
    expect(calendarReset, contains('_subscriptions.clear()'));
    expect(calendarReset, contains('_oauthAccounts.clear()'));
    expect(calendarReset, contains('_eventsBySubscription.clear()'));
    expect(calendarReset, contains('_eventsByOAuthAccount.clear()'));
    expect(calendarReset, contains('_writeTarget = null'));
    expect(calendarReset, contains('_lastCalDavConflicts.clear()'));
  });
}

String _sourceBlock(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  expect(start, isNonNegative, reason: startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(end, isNonNegative, reason: endMarker);
  return source.substring(start, end);
}
