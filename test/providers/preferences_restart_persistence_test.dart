import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/report_reminder_config.dart';
import 'package:duoyi/models/goal.dart' show ReminderKind;
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设备/用户习惯偏好：登出、切号、401 清理后都应当保留。
const _devicePreferences = <String, Object>{
  'pref_show_lunar': false,
  'pref_date_format': 'dd/MM/yyyy',
  'pref_first_day_of_week': 7,
  'pref_bottom_nav_order': <String>['2', '0', '6'],
  'pref_daily_reminder_hour': 7,
  'pref_app_timezone_iana': 'UTC',
  'pref_app_timezone_mode': 'fixed',
  'active_brand': 're0',
  'theme_switch_count': 4,
};

/// 账号私有数据：任何一次清理都必须消失。
const _accountData = <String, Object>{
  'todos': '[{"id":"stale-account-task"}]',
  'theme_shop_state':
      '{"activeBrand":"re0","unlockedBrandIds":["re0","starRail"]}',
  'theme_unlocked_brands': <String>['re0', 'starRail'],
  'duoyi_notif_history': '[{"title":"admin notification"}]',
  'sync_pending_local_changes': true,
  'sync_preferences_updated_at': '2026-06-01T00:00:00.000Z',
  'webdav_backup_username': 'admin',
  'duoyi_oauth_calendar_accounts_v1': '[]',
};

Map<String, String> get _jsonHeaders => const {
  'content-type': 'application/json',
};

void _expectDevicePreferencesKept(SharedPreferences prefs) {
  expect(prefs.getBool('pref_show_lunar'), isFalse);
  expect(prefs.getString('pref_date_format'), 'dd/MM/yyyy');
  expect(prefs.getInt('pref_first_day_of_week'), 7);
  expect(prefs.getStringList('pref_bottom_nav_order'), <String>['2', '0', '6']);
  expect(prefs.getInt('pref_daily_reminder_hour'), 7);
  expect(prefs.getString('pref_app_timezone_iana'), 'UTC');
  expect(prefs.getString('pref_app_timezone_mode'), 'fixed');
  expect(prefs.getString('active_brand'), 're0');
  expect(prefs.getInt('theme_switch_count'), 4);
}

void _expectAccountDataCleared(SharedPreferences prefs) {
  expect(prefs.getString('todos'), isNull);
  expect(prefs.getString('theme_shop_state'), isNull);
  expect(prefs.getStringList('theme_unlocked_brands'), isNull);
  expect(prefs.getString('duoyi_notif_history'), isNull);
  expect(prefs.getBool('sync_pending_local_changes'), isNull);
  expect(prefs.getString('sync_preferences_updated_at'), isNull);
  expect(prefs.getString('webdav_backup_username'), isNull);
  expect(prefs.getString('duoyi_oauth_calendar_accounts_v1'), isNull);
  expect(prefs.getString(AccountLocalDataCleaner.accountDataOwnerKey), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('设备偏好在登出、401 与 403 边界后保持', () {
    test('登出冷启动清理后设备偏好在两次重启中保持，账号数据被清', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ..._devicePreferences,
        ..._accountData,
        AccountLocalDataCleaner.accountDataOwnerKey: 'id:previous-account',
      });

      final auth = AuthProvider();
      auth.onAccountLoggedOut = AccountLocalDataCleaner.clearSharedPreferences;
      await auth.loadFromStorage(refreshServerConfig: false);
      expect(auth.state.isLoggedIn, isFalse);

      var prefs = await SharedPreferences.getInstance();
      _expectDevicePreferencesKept(prefs);
      _expectAccountDataCleared(prefs);

      // 两次真实重启：每次重置静态缓存后用新 Provider 重新载入。
      for (var restart = 0; restart < 2; restart++) {
        SharedPreferences.resetStatic();
        prefs = await SharedPreferences.getInstance();
        _expectDevicePreferencesKept(prefs);
        _expectAccountDataCleared(prefs);

        final preferences = PreferencesProvider();
        await preferences.loadFromStorage();
        expect(preferences.showLunar, isFalse);
        expect(preferences.dateFormat, 'dd/MM/yyyy');
        expect(preferences.firstDayOfWeek, 7);
        expect(preferences.dailyReminderHour, 7);
        expect(preferences.followSystemTimeZone, isFalse);
        expect(preferences.appTimeZoneSelection, 'UTC');
        expect(preferences.bottomNavOrder.first, 2);

        final theme = ThemeProvider();
        await theme.loadFromStorage();
        expect(theme.brand.id, 're0');
        theme.dispose();
        preferences.dispose();
      }

      auth.dispose();
    });

    test('401 清理后重登同账号，设备偏好与主题视图仍保留', () async {
      var unauthorized = true;
      SharedPreferences.setMockInitialValues(<String, Object>{
        ..._devicePreferences,
        ..._accountData,
        'auth_state': json.encode(
          const AuthState(
            userId: 'same-id',
            username: 'same',
            token: 'old-token',
          ).toJson(),
        ),
      });
      final httpClient = MockClient((request) async {
        final path = request.url.path;
        if (path == '/api/auth/me' || path == '/api/me') {
          if (unauthorized) {
            return http.Response(
              json.encode({'detail': 'token expired'}),
              401,
              headers: _jsonHeaders,
            );
          }
          return http.Response(
            json.encode({'user_id': 'same-id', 'username': 'same'}),
            200,
            headers: _jsonHeaders,
          );
        }
        if (path == '/api/auth/login') {
          return http.Response(
            json.encode({
              'user_id': 'same-id',
              'username': 'same',
              'token': 'new-token',
            }),
            200,
            headers: _jsonHeaders,
          );
        }
        return http.Response('{}', 200, headers: _jsonHeaders);
      });
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'same-id',
          username: 'same',
          token: 'old-token',
        ),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'old-token',
          httpClient: httpClient,
        ),
        // 登出会重建 ApiClient；工厂保证重登仍走同一个 mock。
        clientFactory: (baseUrl, token) =>
            ApiClient(baseUrl: baseUrl, token: token, httpClient: httpClient),
      );
      auth.onAccountLoggedOut = AccountLocalDataCleaner.clearSharedPreferences;

      await auth.refreshMe(force: true);

      var prefs = await SharedPreferences.getInstance();
      expect(auth.state.isLoggedIn, isFalse);
      expect(prefs.getString('auth_state'), isNull);
      _expectAccountDataCleared(prefs);
      _expectDevicePreferencesKept(prefs);

      unauthorized = false;
      await auth.login(username: 'same', password: 'pw');
      expect(auth.state.isLoggedIn, isTrue);
      expect(auth.state.token, 'new-token');

      prefs = await SharedPreferences.getInstance();
      _expectDevicePreferencesKept(prefs);
      expect(prefs.getString('theme_shop_state'), isNull);

      final preferences = PreferencesProvider();
      await preferences.loadFromStorage();
      expect(preferences.showLunar, isFalse);
      expect(preferences.dateFormat, 'dd/MM/yyyy');
      expect(preferences.dailyReminderHour, 7);

      final theme = ThemeProvider();
      await theme.loadFromStorage();
      expect(theme.brand.id, 're0');

      theme.dispose();
      preferences.dispose();
      auth.dispose();
    });

    test('通用 403 权限不足不会清理设备偏好与账号数据', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ..._devicePreferences,
        ..._accountData,
        'auth_state': json.encode(
          const AuthState(
            userId: 'same-id',
            username: 'same',
            token: 'same-token',
          ).toJson(),
        ),
      });
      final client = ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'same-token',
        httpClient: MockClient((request) async {
          return http.Response(
            json.encode({'detail': 'permission denied'}),
            403,
            headers: _jsonHeaders,
          );
        }),
      );
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'same-id',
          username: 'same',
          token: 'same-token',
        ),
        client: client,
      );
      var cleanupCalls = 0;
      auth.onAccountLoggedOut = () async {
        cleanupCalls++;
        await AccountLocalDataCleaner.clearSharedPreferences();
      };

      await auth.refreshMe(force: true);

      final prefs = await SharedPreferences.getInstance();
      expect(cleanupCalls, 0);
      expect(auth.state.isLoggedIn, isTrue);
      expect(prefs.getString('todos'), isNotNull);
      expect(prefs.getString('theme_shop_state'), isNotNull);
      _expectDevicePreferencesKept(prefs);

      auth.dispose();
    });

    test('偏好 setter 等云同步标记落盘后才结束，但内存立即更新', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = PreferencesProvider();
      final gate = Completer<void>();
      var notifiedKeys = <String>{};
      preferences.onChangedKeys = (keys) async {
        notifiedKeys = keys.toSet();
        await gate.future;
      };

      final save = preferences.setShowLunar(false);
      var completed = false;
      unawaited(save.then((_) => completed = true));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(preferences.showLunar, isFalse);
      expect(notifiedKeys, contains('pref_show_lunar'));
      expect(completed, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pref_show_lunar'), isFalse);

      gate.complete();
      await save;
      expect(completed, isTrue);

      preferences.dispose();
    });

    test('载入进行中保存的偏好不会被载入结果覆盖', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'pref_show_lunar': true,
        'pref_first_day_of_week': 7,
        'pref_daily_reminder_hour': 6,
        'pref_daily_reminder_minute': 45,
      });
      final preferences = PreferencesProvider();

      final load = preferences.loadFromStorage();
      final save = preferences.setDateFormat('dd/MM/yyyy');
      await Future.wait(<Future<void>>[load, save]);

      expect(preferences.dateFormat, 'dd/MM/yyyy');
      expect(preferences.showLunar, isTrue);
      expect(preferences.firstDayOfWeek, 7);
      expect(preferences.dailyReminderHour, 6);
      expect(preferences.dailyReminderMinute, 45);

      final reloaded = PreferencesProvider();
      await reloaded.loadFromStorage();
      expect(reloaded.dateFormat, 'dd/MM/yyyy');
      expect(reloaded.showLunar, isTrue);

      reloaded.dispose();
      preferences.dispose();
    });
    test('重载已进入异步读取时，周首日保存仍使用请求值', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'pref_first_day_of_week': 1,
        'pref_show_lunar': false,
        'pref_daily_reminder_hour': 6,
      });
      final stored = await SharedPreferences.getInstance();
      final preferences = PreferencesProvider();
      final load = preferences.loadFromStorage();
      await Future<void>.value();
      final save = preferences.setFirstDayOfWeek(2);
      await Future.wait<void>([load, save]);
      expect(preferences.firstDayOfWeek, 2);
      expect(stored.getInt('pref_first_day_of_week'), 2);
      expect(preferences.showLunar, isFalse);
      expect(preferences.dailyReminderHour, 6);
      preferences.dispose();
    });
  });

  group('偏好重启持久化与载入并发', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    tearDown(() {
      LocalTimezoneResolver.debugSystemTimeZoneReader = null;
      LocalTimezoneResolver.debugNativeSystemTimeZoneReader = null;
    });

    const devicePreferences = <String, Object>{
      'pref_haptic_feedback': false,
      'pref_show_lunar': false,
      'pref_show_home_calendar': true,
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
      expect(preferences.dateFormat, 'dd/MM/yyyy', reason: 'date format');
      expect(preferences.defaultTab, 2, reason: 'default tab');
      expect(preferences.appTimeZone, 'Asia/Tokyo', reason: 'timezone');
      expect(
        preferences.followSystemTimeZone,
        isFalse,
        reason: 'timezone mode',
      );
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
  });
}
