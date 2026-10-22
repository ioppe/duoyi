import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Clears data that belongs to the signed-in account.
///
/// Device-level settings such as locale and app lock are intentionally not
/// listed here. Account data, sync metadata, notification history, backup
/// targets and cached integration payloads must not survive logout or account
/// switching.
class AccountLocalDataCleaner {
  AccountLocalDataCleaner._();

  static const accountDataOwnerKey = 'duoyi_account_data_owner_v1';
  // 只有游客在外观页主动选择后才写入；登录/切换/退出仍将它一并清理。
  static const guestAppearanceMarkerKey = 'duoyi_guest_appearance_v1';
  static const appearancePreferenceKeys = <String>{
    'active_brand',
    'theme_switch_count',
    'theme_unlocked_brands',
    'theme_shop_state',
  };
  static int _accountDataGeneration = 0;

  static int get accountDataGeneration => _accountDataGeneration;

  static bool isCurrentAccountDataGeneration(int generation) {
    return generation == _accountDataGeneration;
  }

  static void invalidateInFlightAccountWrites() {
    _accountDataGeneration++;
  }

  static const accountScopedKeys = <String>{
    accountDataOwnerKey,
    guestAppearanceMarkerKey,
    'todos',
    'habits',
    'pomodoro_sessions',
    'pomodoro_focus_penalties',
    'pomodoro_config',
    'pomodoro_count_today',
    'pomodoro_last_date',
    'user_profile',
    'duoyi_notes',
    'duoyi_anniversaries_v2',
    'duoyi_countdowns',
    'duoyi_diary',
    'duoyi_goals',
    'duoyi_local_calendar_events_v1',
    'duoyi_time_entries',
    'duoyi_courses',
    'duoyi_course_settings',
    'duoyi_location_reminders_v1',
    'duoyi_achievements_unlocked',
    'duoyi_achievements_notified',
    'duoyi_virtual_rewards',
    'duoyi_custom_focus_sounds',
    'duoyi_focus_rooms',
    'active_brand',
    'theme_switch_count',
    'theme_unlocked_brands',
    'theme_shop_state',
    'duoyi_quick_capture_templates_v1',
    'duoyi_list_groups_v1',
    'ai_review_history',
    'duoyi_notif_history',
    'duoyi_notif_history_seen_at',
    'duoyi_widget_display_mode',
    'widget_display_mode',
    'todo_kanban_columns_v1',
    'reminder_scheduler_registry_v1',
    'duoyi_ics_subscriptions_v1',
    'duoyi_oauth_calendar_accounts_v1',
    'duoyi_oauth_calendar_pending_authorization_v1',
    'duoyi_caldav_write_target_v1',
    'duoyi_caldav_pushed_uids_v1',
    'duoyi_caldav_pushed_etags_v1',
    'webdav_backup_base_url',
    'webdav_backup_username',
    'webdav_backup_password',
    'webdav_backup_remote_path',
    'webdav_backup_filename',
    'sync_last_time',
    'sync_auto',
    'sync_deleted_items',
    'sync_server_updated_at',
    'sync_server_version',
    'sync_collection_hashes',
    'sync_item_hashes',
    'sync_pending_local_changes',
    'sync_preferences_updated_at',
    'sync_preferences_values_snapshot',
    'sync_preferences_changed_keys',
    'sync_quick_capture_templates_updated_at',
    'sync_merge_decisions',
    'pref_haptic_feedback',
    'pref_show_lunar',
    'pref_show_completed_todos',
    'pref_quick_capture_fab',
    'pref_notification_quick_add',
    'pref_notification_today_progress',
    'pref_daily_reminder_enabled',
    'pref_daily_reminder_today_tasks',
    'pref_daily_reminder_tomorrow_plan',
    'pref_daily_reminder_overdue',
    'pref_daily_reminder_pause_holidays',
    'pref_daily_reminder_slot2_enabled',
    'pref_daily_reminder_slot2_today',
    'pref_daily_reminder_slot2_tomorrow',
    'pref_daily_reminder_slot2_overdue',
    'pref_daily_reminder_slot2_pause_holidays',
    'pref_daily_reminder_slot3_enabled',
    'pref_daily_reminder_slot3_today',
    'pref_daily_reminder_slot3_tomorrow',
    'pref_daily_reminder_slot3_overdue',
    'pref_daily_reminder_slot3_pause_holidays',
    'pref_daily_report_reminder',
    'pref_weekly_report_reminder',
    'pref_monthly_report_reminder',
    'pref_yearly_report_reminder',
    'pref_first_day_of_week',
    'pref_default_tab',
    'pref_default_pomodoro_minutes',
    'pref_notification_history_limit',
    'pref_auto_archive_completed_days',
    'pref_daily_reminder_hour',
    'pref_daily_reminder_minute',
    'pref_daily_reminder_slot2_hour',
    'pref_daily_reminder_slot2_minute',
    'pref_daily_reminder_slot3_hour',
    'pref_daily_reminder_slot3_minute',
    'pref_daily_report_reminder_hour',
    'pref_daily_report_reminder_minute',
    'pref_weekly_report_reminder_weekday',
    'pref_weekly_report_reminder_hour',
    'pref_weekly_report_reminder_minute',
    'pref_monthly_report_reminder_day',
    'pref_monthly_report_reminder_hour',
    'pref_monthly_report_reminder_minute',
    'pref_yearly_report_reminder_month',
    'pref_yearly_report_reminder_day',
    'pref_yearly_report_reminder_hour',
    'pref_yearly_report_reminder_minute',
    'pref_reminder_ringtone_volume_percent',
    'pref_reminder_ringtone_alarm_migrated_to_soft',
    'pref_date_format',
    'pref_app_timezone_iana',
    'pref_app_timezone_mode',
    'pref_daily_reminder_kind',
    'pref_daily_reminder_slot2_kind',
    'pref_daily_reminder_slot3_kind',
    'pref_reminder_ringtone_sound',
    'pref_daily_reminder_repeat_days',
    'pref_daily_reminder_slot2_repeat_days',
    'pref_daily_reminder_slot3_repeat_days',
    'pref_bottom_nav_order',
    'pref_bottom_nav_visible',
    'pref_web_navigation_v2',
    'pref_focus_navigation_v1',
  };

  static const accountScopedPrefixes = <String>[
    'sync_',
    'widget_display_mode_',
    'pref_daily_reminder_slot',
    'pref_reminder_ringtone_fallback_channel_sound_',
    'pref_reminder_ringtone_fallback_channel_sound_schema_',
    'duoyi_ics_',
    'duoyi_ics_events_',
    'duoyi_oauth_calendar_',
    'duoyi_oauth_calendar_events_',
    'duoyi_caldav_',
    'todos_corrupt_backup_',
  ];

  static const accountScopedDocumentDirectories = <String>{
    'custom_focus_sounds',
    'profile_avatars',
    'avatar_cache',
  };

  static Future<void> clearSharedPreferences() async {
    invalidateInFlightAccountWrites();
    final prefs = await SharedPreferences.getInstance();
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> removeKey(String key) async {
      try {
        await prefs.remove(key);
      } catch (e, st) {
        firstError ??= e;
        firstStackTrace ??= st;
      }
    }

    for (final key in accountScopedKeys) {
      await removeKey(key);
    }
    final dynamicKeys = prefs.getKeys().where(
      (key) => accountScopedPrefixes.any((prefix) => key.startsWith(prefix)),
    );
    for (final key in dynamicKeys.toList(growable: false)) {
      await removeKey(key);
    }
    final error = firstError;
    final stackTrace = firstStackTrace;
    if (error != null && stackTrace != null) {
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static Future<void> clearLocalFiles({Directory? documentsDirectory}) async {
    final root = documentsDirectory ?? await getApplicationDocumentsDirectory();
    Object? firstError;
    StackTrace? firstStackTrace;

    for (final name in accountScopedDocumentDirectories) {
      try {
        final dir = Directory('${root.path}${Platform.pathSeparator}$name');
        if (!await dir.exists()) continue;
        await dir.delete(recursive: true);
      } catch (e, st) {
        firstError ??= e;
        firstStackTrace ??= st;
      }
    }
    final error = firstError;
    final stackTrace = firstStackTrace;
    if (error != null && stackTrace != null) {
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
