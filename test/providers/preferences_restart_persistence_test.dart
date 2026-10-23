import 'dart:async';

import 'package:duoyi/core/app_text_scale.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/report_reminder_config.dart';
import 'package:duoyi/models/goal.dart' show ReminderKind;
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 故障链回归：安卓冷启动时 AuthProvider 发现旧账号残留数据（todos、sync_*、
/// 通知历史等）会走 onAccountLoggedOut → 重置并重载 PreferencesProvider。
/// 若本机 `pref_*` 偏好被列入账号清理集，这次重载只能读到空值，用户的触感、
/// 农历、日期格式、默认页、时区、底部导航、提醒配置全部回落默认值。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = null;
  });

  const devicePreferences = <String, Object>{
    'pref_haptic_feedback': false,
    'pref_show_lunar': false,
    'pref_show_home_calendar': true,
    'pref_text_scale': 1.15,
    'pref_date_format': 'dd/MM/yyyy',
    'pref_default_tab': 2,
    'pref_app_timezone_mode': 'fixed',
    'pref_app_timezone_iana': 'Asia/Tokyo',
    'pref_bottom_nav_order': <String>['0', '1', '2', '4', '6'],
    'pref_bottom_nav_visible': <String>['0', '1', '2', '4', '6'],
    'pref_daily_reminder_enabled': true,
    'pref_daily_reminder_kind': 'popup',
    'pref_daily_reminder_hour': 7,
    'pref_daily_reminder_minute': 30,
    'pref_daily_reminder_slot2_enabled': true,
    'pref_daily_reminder_slot2_kind': 'alarm',
    'pref_daily_reminder_slot2_hour': 21,
    'pref_daily_reminder_slot2_minute': 5,
    'pref_weekly_report_reminder': true,
    'pref_reminder_ringtone_volume_percent': 65,
    'pref_reminder_ringtone_sound': 'duoyi_soft',
  };

  /// 与 main.dart 的 clearAccountLocalData 对齐的最小账号边界回调：
  /// 重置内存 → 重新载入偏好 → 清理账号偏好。
  Future<void> clearAccountLocalData(PreferencesProvider preferences) async {
    preferences.resetLocalState();
    await preferences.loadFromStorage();
    await AccountLocalDataCleaner.clearSharedPreferences();
  }

  Future<PreferencesProvider> coldStart() async {
    final preferences = PreferencesProvider();
    final auth = AuthProvider();
    auth.onAccountLoggedOut = () => clearAccountLocalData(preferences);
    await auth.loadFromStorage(refreshServerConfig: false);
    await preferences.loadFromStorage();
    auth.dispose();
    return preferences;
  }

  void expectDevicePreferences(PreferencesProvider preferences) {
    expect(preferences.haptic, isFalse, reason: 'haptic');
    expect(preferences.showLunar, isFalse, reason: 'lunar');
    expect(preferences.showHomeCalendar, isTrue, reason: 'home calendar');
    expect(preferences.textScale, AppTextScale.large, reason: 'text scale');
    expect(preferences.dateFormat, 'dd/MM/yyyy', reason: 'date format');
    expect(preferences.defaultTab, 2, reason: 'default tab');
    expect(preferences.appTimeZone, 'Asia/Tokyo', reason: 'timezone');
    expect(preferences.followSystemTimeZone, isFalse, reason: 'timezone mode');
    expect(preferences.bottomNavOrder, <int>[0, 1, 2, 4, 6, 3, 5]);
    expect(preferences.visibleBottomNavTabs, <int>[0, 1, 2, 4, 6]);
    expect(preferences.dailyReminderEnabled, isTrue);
    expect(preferences.dailyReminderSlots[0].kind, ReminderKind.popup);
    expect(preferences.dailyReminderHour, 7);
    expect(preferences.dailyReminderMinute, 30);
    expect(preferences.dailyReminderSlots[1].enabled, isTrue);
    expect(preferences.dailyReminderSlots[1].kind, ReminderKind.alarm);
    expect(preferences.dailyReminderSlots[1].hour, 21);
    expect(preferences.dailyReminderSlots[1].minute, 5);
    expect(preferences.weeklyReportReminder, isTrue);
  }

  test('账号残留清理链路上连续两次冷启动都保留本机偏好', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ...devicePreferences,
      // 上一账号/游客残留：触发 AuthProvider 的未登录清理分支。
      'todos': '[{"id":"stale","title":"上一账号的任务"}]',
      'duoyi_notif_history': '[{"title":"上一账号通知"}]',
      'sync_preferences_updated_at': '2026-06-07T00:00:00.000Z',
      'sync_pending_local_changes': true,
      'webdav_backup_password': 'secret',
      'active_brand': 're0',
    });
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Europe/Berlin';

    final first = await coldStart();
    expectDevicePreferences(first);
    final prefs = await SharedPreferences.getInstance();
    // 账号私有数据仍必须清干净。
    expect(prefs.getString('todos'), isNull);
    expect(prefs.getString('duoyi_notif_history'), isNull);
    expect(prefs.getString('sync_preferences_updated_at'), isNull);
    expect(prefs.getBool('sync_pending_local_changes'), isNull);
    expect(prefs.getString('webdav_backup_password'), isNull);
    expect(prefs.getString('active_brand'), isNull);
    expect(prefs.getDouble('pref_text_scale'), AppTextScale.large);
    first.dispose();

    // 第二次冷启动使用同一份持久化存储，模拟用户重启 App。
    final second = await coldStart();
    expectDevicePreferences(second);
    second.dispose();
  });

  test('偏好 setter 返回时异步同步回调已完成，且通知先到', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final order = <String>[];
    final provider = PreferencesProvider();
    provider.addListener(() => order.add('notify'));
    provider.onChangedKeys = (keys) async {
      order.add('callback:${keys.join(',')}');
      await Future<void>.delayed(const Duration(milliseconds: 1));
      order.add('callback-done');
    };

    await provider.setHaptic(false);

    expect(order, <String>[
      'notify',
      'callback:pref_haptic_feedback',
      'callback-done',
    ]);
    expect(provider.haptic, isFalse);
    provider.dispose();
  });

  test('载入期间的用户设置不会被旧快照覆盖，公共 load 返回即全部生效', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_haptic_feedback': true,
      'pref_show_lunar': false,
    });
    final readerStarted = Completer<void>();
    final releaseReader = Completer<String?>();
    LocalTimezoneResolver.debugSystemTimeZoneReader = () {
      if (!readerStarted.isCompleted) readerStarted.complete();
      return releaseReader.future;
    };

    final provider = PreferencesProvider();
    final loadFuture = provider.loadFromStorage();
    await readerStarted.future.timeout(const Duration(seconds: 1));
    // 载入停在时区解析：此时用户改写设置。
    await provider.setHaptic(false);
    releaseReader.complete('Asia/Shanghai');
    await loadFuture.timeout(const Duration(seconds: 2));

    expect(provider.haptic, isFalse, reason: '最后一次用户设置必须保留');
    expect(
      provider.showLunar,
      isFalse,
      reason: '公共 load 返回时其余已存偏好也已载入，不再放弃整次载入',
    );
    provider.dispose();
  });

  test('载入与首页设置同轮发起时以最后写入为准，其余偏好仍载入', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_first_day_of_week': 1,
      'pref_show_lunar': false,
      'pref_haptic_feedback': true,
    });
    final readerStarted = Completer<void>();
    final releaseReader = Completer<String?>();
    LocalTimezoneResolver.debugSystemTimeZoneReader = () {
      if (!readerStarted.isCompleted) readerStarted.complete();
      return releaseReader.future;
    };

    final provider = PreferencesProvider();
    // 同一轮事件里发起载入与写入：首段读取必须看到写入后的值。
    final loadFuture = provider.loadFromStorage();
    final writeFuture = provider.setFirstDayOfWeek(7);
    await readerStarted.future.timeout(const Duration(seconds: 1));
    releaseReader.complete('Asia/Shanghai');
    await writeFuture.timeout(const Duration(seconds: 2));
    await loadFuture.timeout(const Duration(seconds: 2));

    final prefs = await SharedPreferences.getInstance();
    expect(provider.firstDayOfWeek, 7);
    expect(prefs.getInt('pref_first_day_of_week'), 7);
    expect(provider.showLunar, isFalse);
    expect(provider.haptic, isTrue);
    provider.dispose();
  });

  test('提醒与无关设置在载入并发时最终一致', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_daily_reminder_enabled': true,
      'pref_daily_reminder_kind': 'popup',
      'pref_daily_reminder_hour': 6,
      'pref_daily_reminder_minute': 45,
      'pref_weekly_report_reminder': false,
      'pref_notification_quick_add': false,
      'pref_show_completed_todos': true,
    });
    final readerStarted = Completer<void>();
    final releaseReader = Completer<String?>();
    LocalTimezoneResolver.debugSystemTimeZoneReader = () {
      if (!readerStarted.isCompleted) readerStarted.complete();
      return releaseReader.future;
    };

    final provider = PreferencesProvider();
    final loadFuture = provider.loadFromStorage();
    await readerStarted.future.timeout(const Duration(seconds: 1));
    final weekly = provider.setWeeklyReportReminderConfig(
      const ReportReminderConfig(
        enabled: true,
        weekday: 3,
        hour: 9,
        minute: 15,
      ),
    );
    final quickAdd = provider.setNotificationQuickAdd(true);
    releaseReader.complete('Asia/Shanghai');
    await Future.wait<void>([
      weekly,
      quickAdd,
    ]).timeout(const Duration(seconds: 2));
    await loadFuture.timeout(const Duration(seconds: 2));

    expect(provider.dailyReminderEnabled, isTrue);
    expect(provider.dailyReminderSlots[0].kind, ReminderKind.popup);
    expect(provider.dailyReminderHour, 6);
    expect(provider.dailyReminderMinute, 45);
    expect(provider.showCompletedTodos, isTrue);
    expect(provider.weeklyReportReminder, isTrue);
    expect(provider.weeklyReportReminderWeekday, 3);
    expect(provider.weeklyReportReminderHour, 9);
    expect(provider.weeklyReportReminderMinute, 15);
    expect(provider.notificationQuickAdd, isTrue);
    provider.dispose();
  });
}
