import 'dart:convert';

import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/reminder_ringtone_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('部署后两次冷启动保留设备偏好，旧账号私有缓存仍清除', () async {
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'Asia/Shanghai';
    addTearDown(() {
      LocalTimezoneResolver.debugSystemTimeZoneReader = null;
      ReminderRingtoneSettings.onChanged = null;
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_show_lunar': false,
      'pref_haptic_feedback': false,
      'pref_first_day_of_week': 7,
      'pref_date_format': 'MM/dd/yyyy',
      'pref_default_pomodoro_minutes': 35,
      'pref_daily_reminder_slot2_enabled': true,
      'pref_daily_reminder_slot2_hour': 9,
      'pref_app_timezone_mode': 'fixed',
      'pref_app_timezone_iana': 'Asia/Tokyo',
      'pref_reminder_ringtone_sound': 'bell',
      'pref_reminder_ringtone_volume_percent': 80,
      'pref_bottom_nav_visible': <String>['0', '2', '4', '6'],
      'pref_bottom_nav_order': <String>['2', '0', '4', '6', '1', '3', '5'],
      'pref_web_navigation_v2': true,
      'pref_focus_navigation_v1': true,
      'active_brand': 're0',
      'theme_switch_count': 7,
      AccountLocalDataCleaner.accountDataOwnerKey: 'old-account-fixture',
      'todos': jsonEncode([
        {'id': 'private-old-account'},
      ]),
      'sync_preferences_updated_at': '2026-01-01T00:00:00Z',
      'duoyi_notif_history': '[{"title":"private fixture"}]',
      'webdav_backup_password': 'not-a-real-password',
      'theme_unlocked_brands': <String>['old-account-only'],
      'theme_shop_state': '{"activeBrand":"genshin"}',
    });

    for (var round = 0; round < 2; round++) {
      SharedPreferences.resetStatic();
      final preferences = PreferencesProvider();
      final themes = ThemeProvider();
      final auth = AuthProvider();
      auth.onAccountLoggedOut = () async {
        await AccountLocalDataCleaner.clearSharedPreferences();
        preferences.resetLocalState();
        themes.resetLocalState();
        await preferences.loadFromStorage();
        await AccountLocalDataCleaner.clearSharedPreferences();
        await themes.loadFromStorage();
      };
      await auth.loadFromStorage(refreshServerConfig: false);
      await preferences.loadFromStorage();
      await themes.loadFromStorage();
      final stored = await SharedPreferences.getInstance();
      expect(auth.state.isLoggedIn, isFalse);
      expect(preferences.showLunar, isFalse);
      expect(preferences.haptic, isFalse);
      expect(preferences.firstDayOfWeek, 7);
      expect(preferences.dateFormat, 'MM/dd/yyyy');
      expect(preferences.defaultPomodoroMinutes, 35);
      expect(preferences.dailyReminderSlots[1].enabled, isTrue);
      expect(preferences.dailyReminderSlots[1].hour, 9);
      expect(preferences.appTimeZone, 'Asia/Tokyo');
      expect(preferences.followSystemTimeZone, isFalse);
      expect(preferences.bottomNavVisible, <int>{0, 2, 4, 6});
      expect(themes.brand.id, 're0');
      expect(stored.getInt('theme_switch_count'), 7);
      expect(await ReminderRingtoneSettings.loadSound(), 'bell');
      expect(await ReminderRingtoneSettings.loadVolumePercent(), 80);
      for (final key in <String>[
        AccountLocalDataCleaner.accountDataOwnerKey,
        'todos',
        'sync_preferences_updated_at',
        'duoyi_notif_history',
        'webdav_backup_password',
        'theme_unlocked_brands',
        'theme_shop_state',
      ]) {
        expect(stored.containsKey(key), isFalse, reason: 'round $round: $key');
      }
      preferences.dispose();
      themes.dispose();
      auth.dispose();
    }
  });
}
