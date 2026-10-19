import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('alignment regression gate keeps eight required groups', () {
    final script = File('scripts/alignment_regression_gate.sh');
    expect(script.existsSync(), isTrue);
    final source = script.readAsStringSync();

    for (final marker in [
      '1/8 404 and route contracts',
      '2/8 style layout and readable selection',
      '3/8 notification ringtone and status progress',
      '4/8 widgets Android and iOS static contracts',
      '5/8 admin groups default coins and permissions',
      '6/8 Flutter analyzer',
      '7/8 debug APK build',
      '8/8 device-only notification alarm widget regression',
    ]) {
      expect(source, contains(marker));
    }

    expect(source, contains('test/screens/today_detail_router_test.dart'));
    expect(
      source,
      contains('test/screens/today_detail_router_static_test.dart'),
    );
    expect(
      source,
      contains('test/services/api_route_contract_static_test.dart'),
    );
    expect(source, contains('test/services/api_client_error_test.dart'));
    expect(source, contains('test/services/no_global_bold_static_test.dart'));
    expect(
      source,
      contains('test/screens/style_layout_regression_static_test.dart'),
    );
    expect(source, contains('test/services/admin_user_status_test.dart'));
    for (final styleTest in const [
      'test/services/backup_service_test.dart',
      'test/screens/todo_kanban_view_test.dart',
      'test/screens/feedback_screen_test.dart',
      'test/screens/admin_feedback_screen_test.dart',
      'test/screens/habit_screen_test.dart',
      'test/screens/habit_grouping_static_test.dart',
      'test/screens/profile_screen_test.dart',
      'test/screens/today_mine_static_test.dart',
      'test/screens/today_mine_smoke_test.dart',
      'test/providers/auth_provider_profile_static_test.dart',
      'test/providers/auth_provider_profile_test.dart',
    ]) {
      expect(source, contains(styleTest));
    }
    expect(
      source,
      contains('test/services/admin_permissions_coins_static_test.dart'),
    );
    expect(
      source,
      contains('test/services/admin_force_update_settings_test.dart'),
    );
    expect(
      source,
      contains('test/services/reminder_ringtone_settings_test.dart'),
    );
    for (final notificationTest in const [
      'test/services/reminder_scheduler_integration_test.dart',
      'test/services/reminder_resync_static_test.dart',
      'test/services/reminder_email_channel_test.dart',
      'test/services/channel_routing_pbt_test.dart',
      'test/services/foreground_reminder_popup_sink_test.dart',
      'test/services/notification_quick_add_static_test.dart',
      'test/providers/preferences_provider_test.dart',
      'test/providers/notification_service_test.dart',
      'test/screens/ai_schedule_flow_static_test.dart',
      'test/widgets/calendar_local_event_static_test.dart',
      'test/services/native_reminder_ringtone_static_test.dart',
      'test/services/notification_status_bar_service_test.dart',
      'test/services/notification_today_progress_preferences_test.dart',
    ]) {
      expect(source, contains(notificationTest));
    }
    expect(source, contains('test/services/device_readiness_report_test.dart'));
    expect(
      source,
      contains('test/services/device_evidence_validator_test.dart'),
    );
    expect(
      source,
      contains('test/services/alignment_report_validator_test.dart'),
    );
    expect(source, contains('test/services/goal_closure_validator_test.dart'));
    expect(
      source,
      contains('test/services/notification_status_bar_service_test.dart'),
    );
    expect(
      source,
      contains('test/services/android_widget_resources_test.dart'),
    );
    expect(source, contains('test/services/ios_widget_resources_test.dart'));
    expect(
      source,
      contains(
        'test_admin_group_assignment_grants_target_group_default_coins_once',
      ),
    );
    for (final backendTest in const [
      'test_public_health_and_config_include_api_contract',
      'test_api_contract_required_routes_are_registered',
      'test_auth_email_code_profile_and_email_alias_routes_are_live',
      'test_profile_email_login_and_avatar_compat_routes_do_not_404',
      'test_admin_re0_named_routes_for_users_coins_invites_and_settings',
      'test_account_api_fallback_routes_match_client_contracts',
      'test_admin_coin_fallback_routes_match_client_contracts',
      'test_admin_large_data_lists_return_paged_responses',
      'test_admin_large_data_lists_support_sort_contracts',
      'test_admin_user_export_online_filter_and_bulk_status',
      'test_admin_backup_exports_use_filters_and_escape_formulas',
      'test_password_reset_request_returns_dev_code_without_mail_provider',
      'test_admin_feedback_reply_and_delete_validate_targets',
      'test_my_feedback_supports_pagination_without_breaking_legacy_list',
      'test_admin_feedback_export_csv_uses_filters_and_escapes_formulas',
    ]) {
      expect(source, contains(backendTest));
    }
    expect(source, contains('analyze'));
    expect(source, contains('build apk --debug'));
    expect(source, contains('scripts/device_regression_check.sh'));
    expect(source, contains('REPORT_DIR'));
    expect(source, contains('build/alignment-regression/latest'));
    expect(source, contains('SUMMARY_TSV'));
    expect(source, contains('SUMMARY_MD'));
    expect(source, contains('summary.tsv'));
    expect(source, contains('summary.md'));
    expect(source, contains(r'tee "$log_file"'));
    expect(source, contains('duration_seconds'));
    expect(source, contains('Group failed:'));
    expect(File('scripts/validate_device_evidence.sh').existsSync(), isTrue);
    expect(File('scripts/validate_alignment_report.sh').existsSync(), isTrue);
    expect(File('scripts/validate_goal_closure.sh').existsSync(), isTrue);
  });

  test(
    'goal closure validator requires all eight gates and device evidence',
    () {
      final script = File('scripts/validate_goal_closure.sh');
      expect(script.existsSync(), isTrue);
      final source = script.readAsStringSync();

      expect(source, contains('validate_alignment_report.sh'));
      expect(source, contains('validate_goal_requirement_matrix.sh'));
      expect(source, contains('generate_device_readiness_report.sh'));
      expect(source, contains('validate_device_readiness_report.sh'));
      expect(source, contains('summarize_device_readiness_missing.sh'));
      expect(source, contains('validate_device_readiness_missing.sh'));
      expect(source, contains('generate_goal_requirement_status.sh'));
      expect(source, contains('validate_goal_requirement_status.sh'));
      expect(source, contains('validate_device_evidence.sh'));
      expect(source, contains('GOAL_REPORT_DIR'));
      expect(source, contains('build/goal-closure/latest'));
      expect(source, contains('alignment_report.log'));
      expect(source, contains('goal_requirement_matrix.log'));
      expect(source, contains('device_readiness.log'));
      expect(source, contains('device_readiness_validation.log'));
      expect(source, contains('device_readiness_missing.log'));
      expect(source, contains('device_readiness_missing_validation.log'));
      expect(source, contains('goal_requirement_status.log'));
      expect(source, contains('goal_requirement_status_validation.log'));
      expect(source, contains('android_device_evidence.log'));
      expect(source, contains('ios_device_evidence.log'));
      expect(source, contains('Goal Closure Validation'));
      expect(source, contains('android'));
      expect(source, contains('ios'));
      expect(source, contains('is not closed'));
      expect(source, contains('Goal closure validation failed'));
      expect(source, contains('Goal closure validation passed'));
    },
  );

  test('alignment report validator enforces eight group summary and logs', () {
    final script = File('scripts/validate_alignment_report.sh');
    expect(script.existsSync(), isTrue);
    final source = script.readAsStringSync();

    expect(source, contains('REPORT_DIR'));
    expect(source, contains('summary.tsv'));
    expect(source, contains('summary.md'));
    expect(source, contains(r"group\tstatus\tduration_seconds\tlog"));
    expect(source, contains('summary.tsv must contain exactly 8 group rows'));
    expect(source, contains('1/8 404 and route contracts'));
    expect(
      source,
      contains('8/8 device-only notification alarm widget regression'),
    );
    expect(source, contains('invalid status'));
    expect(source, contains('invalid duration'));
    expect(source, contains(r'require_file "$log_path"'));
    expect(source, contains('Alignment report validation failed'));
  });

  test('android device evidence script captures runtime proof points', () {
    final script = File('scripts/android_device_evidence.sh');
    expect(script.existsSync(), isTrue);
    final source = script.readAsStringSync();

    expect(
      source,
      contains(r'PACKAGE_NAME="${PACKAGE_NAME:-com.duoyi.duoyi}"'),
    );
    expect(source, contains('build/app/outputs/flutter-apk/app-debug.apk'));
    expect(source, contains('build/device-regression/android'));
    expect(source, contains(r'install -r "$APK_PATH"'));
    expect(source, contains(r'monkey -p "$PACKAGE_NAME"'));
    expect(source, contains('duoyi://tab/today'));
    expect(source, contains('duoyi://calendar'));
    expect(source, contains('duoyi://countdown/device-regression-missing'));
    expect(source, contains('duoyi://action/quick_todo'));
    expect(
      source,
      contains('duoyi://action/complete_todo?id=device-regression-missing'),
    );
    expect(
      source,
      contains('duoyi://action/checkin_habit?id=device-regression-missing'),
    );
    expect(source, contains(r'dumpsys package "$PACKAGE_NAME"'));
    expect(source, contains(r'appops get "$PACKAGE_NAME"'));
    expect(source, contains('shared_prefs_files.txt'));
    expect(source, contains('reminder_preferences.txt'));
    expect(source, contains('notification_channels.txt'));
    expect(source, contains('dumpsys notification --noredact'));
    expect(source, contains('dumpsys alarm'));
    expect(source, contains('dumpsys appwidget'));
    expect(source, contains('notification_today_progress.txt'));
    expect(source, contains('pref_notification_today_progress'));
    expect(
      source,
      contains(
        r'''"$ADB_BIN" shell run-as "$PACKAGE_NAME" grep -R -E 'pref_notification_today_progress' shared_prefs''',
      ),
    );
    expect(
      source.split('\n'),
      isNot(
        contains(
          "grep -R -E 'pref_notification_today_progress' shared_prefs 2>/dev/null \\",
        ),
      ),
    );
    expect(source, contains('reminder_alarm_queue.txt'));
    expect(source, contains('default_soft_ringtone.txt'));
    expect(source, contains('status_bar_excluded=pending'));
    expect(source, contains('widget_providers.txt'));
    expect(source, contains('logcat -d -v time'));
    expect(source, contains('manual_required.md'));
    expect(source, contains('manual_evidence_manifest.md'));
    expect(source, contains('notification_shade_progress'));
    expect(source, contains('launcher_widgets_10_added'));
    expect(source, contains('android_widget_style_matrix'));
    expect(source, contains('widget_refresh_before_after'));
    expect(source, contains('widget_todo_complete'));
    expect(source, contains('widget_quick_add'));
    expect(source, contains('widget_habit_checkin'));
    expect(source, contains('calendar_countdown_deeplink'));
    expect(source, contains('DuoyiTodoWidgetProvider'));
    expect(source, contains('DuoyiHabitWidgetProvider'));
    expect(source, contains('DuoyiCalendarWidgetProvider'));
    expect(source, contains('DuoyiScheduleWidgetProvider'));
    expect(source, contains('DuoyiGoalWidgetProvider'));
    expect(source, contains('DuoyiCourseWidgetProvider'));
    expect(source, contains('DuoyiNoteWidgetProvider'));
    expect(source, contains('DuoyiAnniversaryWidgetProvider'));
    expect(source, contains('DuoyiDiaryWidgetProvider'));
    expect(source, contains('DuoyiFocusHabitWidgetProvider'));
    expect(
      source,
      contains('evidence/manual/android_notification_progress.png'),
    );
    expect(
      source,
      contains('evidence/manual/android_launcher_widgets_10_added.mp4'),
    );
    expect(source, contains('evidence/manual/android_widget_style_matrix.mp4'));
    expect(
      source,
      contains('evidence/manual/android_calendar_countdown_deeplink.mp4'),
    );
    expect(source, contains('ReminderRingtone'));
    expect(source, contains('NotificationStatusBar'));
    expect(source, contains('Manual verification still required'));
    expect(source, contains('Pull down notification shade'));
    expect(source, contains('Schedule a reminder for 1 minute later'));
    expect(
      source,
      contains('do not count the ongoing notification shade progress row'),
    );
    expect(source, contains('Add launcher widgets'));
    expect(
      source,
      contains('Today schedule/calendar aggregate deep links only'),
    );
    expect(source, isNot(contains('DuoyiCountdownWidget')));
  });

  test('ios device evidence script captures WidgetKit proof points', () {
    final script = File('scripts/ios_device_evidence.sh');
    expect(script.existsSync(), isTrue);
    final source = script.readAsStringSync();

    expect(source, contains('iOS device evidence requires macOS'));
    expect(source, contains('xcrun'));
    expect(source, contains('xcodebuild'));
    expect(source, contains('Runner.xcworkspace'));
    expect(source, contains('com.duoyi.duoyi'));
    expect(source, contains('com.duoyi.duoyi.DuoyiWidgets'));
    expect(source, contains('group.com.duoyi.duoyi'));
    expect(source, contains('build/device-regression/ios'));
    expect(source, contains('xcrun xctrace list devices'));
    expect(
      source,
      contains('No physical iPhone or iPad is visible to xctrace'),
    );
    expect(source, contains('Runner/Runner.entitlements'));
    expect(source, contains('DuoyiWidgets/DuoyiWidgets.entitlements'));
    expect(source, contains('DuoyiWidgets.appex'));
    expect(source, contains('DuoyiWidgets.swift in Sources'));
    expect(source, contains('Embed App Extensions'));
    expect(source, contains('CODE_SIGNING_ALLOWED=YES'));
    expect(source, contains('log show --last 20m'));
    expect(source, contains('WidgetKit'));
    expect(source, contains('duoyi://'));
    expect(source, contains('widgetkit_calendar_countdown_deeplink.log'));
    expect(source, contains('duoyi://(calendar|countdown/)'));
    expect(source, contains('Add all 10 Duoyi WidgetKit widgets'));
    expect(source, contains('no overview/combo widget appears'));
    expect(source, contains('Tap widget quick actions and footer links'));
    expect(source, contains('manual_evidence_manifest.md'));
    expect(source, contains('widget_gallery_10_widgets'));
    expect(source, contains('widgetkit_family_matrix'));
    expect(source, contains('widget_todo_complete'));
    expect(source, contains('widget_quick_add'));
    expect(source, contains('widget_habit_checkin'));
    expect(source, contains('widget_focus_start'));
    expect(source, contains('widget_footer_navigation'));
    expect(source, contains('calendar_countdown_deeplink'));
    expect(source, contains('ios_notification_behavior'));
    expect(source, contains('evidence/manual/ios_widget_gallery.png'));
    expect(
      source,
      contains('evidence/manual/ios_calendar_countdown_deeplink.mp4'),
    );
    expect(source, contains('evidence/manual/ios_notification_behavior.mp4'));
    expect(
      source,
      contains('Today schedule/calendar aggregate deep links only'),
    );
    expect(source, isNot(contains('DuoyiCountdownWidget')));
  });

  test(
    'device regression script gates notification alarm and widget closure',
    () {
      final script = File('scripts/device_regression_check.sh');
      expect(script.existsSync(), isTrue);
      final source = script.readAsStringSync();

      expect(source, contains('source "\$ROOT_DIR/scripts/tool_paths.sh"'));
      final tools = File('scripts/tool_paths.sh').readAsStringSync();
      expect(tools, contains('FLUTTER_BIN:-flutter'));
      expect(tools, contains('ADB_BIN:-adb'));
      expect(tools, contains('ANDROID_HOME'));
      expect(tools, isNot(contains('/home/ubuntu/')));
      expect(source, contains('ANDROID_SDK_ROOT'));
      expect(source, contains('== Emulator prerequisites =='));
      expect(source, contains('== Device readiness report =='));
      expect(source, contains('READINESS_SCRIPT'));
      expect(source, contains('VALIDATE_READINESS_SCRIPT'));
      expect(source, contains('READINESS_DIR'));
      expect(source, contains('KVM_DEVICE'));
      expect(
        source,
        contains(r'OUTPUT_DIR="$READINESS_DIR" "$READINESS_SCRIPT"'),
      );
      expect(
        source,
        contains(r'REPORT_DIR="$READINESS_DIR" "$VALIDATE_READINESS_SCRIPT"'),
      );
      expect(source, contains('Device readiness details:'));
      expect(source, contains('host architecture:'));
      expect(source, contains('emulator binary missing'));
      expect(
        source,
        contains('sdkmanager does not list Android Emulator for this host'),
      );
      expect(source, contains('avdmanager'));
      expect(source, contains('Android system images missing'));
      expect(source, contains('system_image_sample'));
      expect(source, contains('readable/writable'));
      expect(source, contains('accelerated Android emulator is not available'));
      expect(source, contains('devices --machine'));
      expect(source, contains('"targetPlatform":"(android|ios)'));
      expect(source, contains('No Android or iOS device/emulator is attached'));
      expect(source, contains('ANDROID_EVIDENCE_SCRIPT'));
      expect(source, contains('scripts/android_device_evidence.sh'));
      expect(source, contains('== Android device evidence =='));
      expect(source, contains('VALIDATE_EVIDENCE_SCRIPT'));
      expect(source, contains('validate_device_evidence.sh'));
      expect(source, contains(r'"$VALIDATE_EVIDENCE_SCRIPT" android'));
      expect(source, contains('android_evidence_status=1'));
      expect(source, contains('android_evidence_status=0'));
      expect(source, contains('IOS_EVIDENCE_SCRIPT'));
      expect(source, contains('scripts/ios_device_evidence.sh'));
      expect(source, contains('== iOS device evidence =='));
      expect(source, contains(r'"$VALIDATE_EVIDENCE_SCRIPT" ios'));
      expect(source, contains('ios_evidence_status=1'));
      expect(source, contains('ios_evidence_status=0'));
      expect(
        source,
        contains('No iOS device detected for ios_device_evidence.sh'),
      );
      expect(source, contains('Both Android and iOS evidence must pass'));
      expect(
        source,
        contains('Automated Android and iOS device evidence passed'),
      );
      expect(
        source,
        contains("Android notification shade shows today's task progress"),
      );
      expect(
        source,
        contains('Android popup/alarm/full-screen reminder fires'),
      );
      expect(source, contains('柔和晨铃'));
      expect(source, contains('Android launcher widgets can be added'));
      expect(source, contains('iOS WidgetKit widgets share the App Group'));
      expect(source, contains('build apk --debug'));
      expect(
        source,
        contains('test integration_test/app_alignment_smoke_test.dart'),
      );
      expect(source, contains('docs/manual-regression-checklist.md'));
    },
  );

  test('manual regression checklist requires the device gate', () {
    final checklist = File(
      'docs/manual-regression-checklist.md',
    ).readAsStringSync();

    expect(checklist, contains('scripts/device_regression_check.sh'));
    expect(checklist, contains('scripts/alignment_regression_gate.sh'));
    expect(checklist, contains('scripts/generate_device_readiness_report.sh'));
    expect(checklist, contains('scripts/validate_device_readiness_report.sh'));
    expect(checklist, contains('build/device-readiness/latest'));
    expect(checklist, contains('docs/device-regression-evidence.md'));
    expect(checklist, contains('收集 Android / iOS 设备证据文件、截图或录屏'));
    expect(checklist, contains('404、样式、通知、小组件、后台、analyze、APK 构建和设备门禁'));
    expect(checklist, contains('没有设备时该脚本必须失败'));
    expect(checklist, contains('不能把通知、闹钟、小组件真机项视为闭环'));
    expect(
      checklist.indexOf('scripts/device_regression_check.sh'),
      lessThan(
        checklist.indexOf(
          'flutter test integration_test/app_alignment_smoke_test.dart',
        ),
      ),
      reason: '设备门禁应在普通 integration smoke 前明确列出。',
    );
  });

  test('device regression evidence document defines auditable outputs', () {
    final doc = File('docs/device-regression-evidence.md');
    expect(doc.existsSync(), isTrue);
    final source = doc.readAsStringSync();

    expect(source, contains('scripts/alignment_regression_gate.sh'));
    expect(source, contains('scripts/device_regression_check.sh'));
    expect(source, contains('scripts/generate_device_readiness_report.sh'));
    expect(source, contains('scripts/validate_device_readiness_report.sh'));
    expect(source, contains('scripts/android_device_evidence.sh'));
    expect(source, contains('scripts/ios_device_evidence.sh'));
    expect(source, contains('scripts/validate_device_evidence.sh'));
    expect(source, contains('build/device-regression/android'));
    expect(source, contains('build/device-regression/ios'));
    expect(source, contains('build/device-readiness/latest'));
    expect(source, contains('reminder_preferences.txt'));
    expect(source, contains('notification_channels.txt'));
    expect(source, contains('dumpsys_notification.txt'));
    expect(source, contains('dumpsys_alarm.txt'));
    expect(source, contains('dumpsys_appwidget.txt'));
    expect(source, contains('notification_today_progress.txt'));
    expect(source, contains('notification shade progress row'));
    expect(source, contains('reminder_alarm_queue.txt'));
    expect(source, contains('default_soft_ringtone.txt'));
    expect(source, contains('logcat_duoyi.txt'));
    expect(source, contains('manual_required.md'));
    expect(source, contains('manual_evidence_manifest.md'));
    expect(
      source,
      contains('must list all 10 base Android launcher widget providers'),
    );
    expect(source, contains('DuoyiDiaryWidgetProvider'));
    expect(source, contains('deep-link files must show `Status: ok`'));
    expect(source, contains('notification_shade_progress'));
    expect(source, contains('widget_gallery_10_widgets'));
    expect(source, contains('widgetkit_family_matrix'));
    expect(source, contains('widgetkit_recent.log'));
    expect(source, contains('calendar_countdown_deeplink'));
    expect(source, contains('widgetkit_calendar_countdown_deeplink.log'));
    expect(source, contains('xcodebuild_device.log'));
    expect(source, contains('notification shade'));
    expect(source, contains('alarm/full-screen mode'));
    expect(source, contains('柔和晨铃'));
    expect(source, contains('all 10 Duoyi WidgetKit widgets'));
    expect(source, contains('group.com.duoyi.duoyi'));
    expect(source, contains('The goal is not complete'));
    expect(
      source,
      contains('ongoing today-progress notification is not counted'),
    );
    expect(
      source,
      contains('Static tests and APK builds are necessary evidence'),
    );
    expect(source, contains('does not replace Android or iOS evidence'));
    expect(
      source,
      contains(
        'Countdown deep links are only evidence for the Today schedule/calendar aggregate',
      ),
    );
    expect(source, isNot(contains('countdown widget')));
  });

  test(
    'device evidence validator enforces required Android and iOS proof files',
    () {
      final script = File('scripts/validate_device_evidence.sh');
      expect(script.existsSync(), isTrue);
      final source = script.readAsStringSync();

      expect(source, contains('validate_android'));
      expect(source, contains('validate_ios'));
      expect(source, contains('ANDROID_EVIDENCE_DIR'));
      expect(source, contains('IOS_EVIDENCE_DIR'));
      expect(source, contains('require_non_empty'));
      expect(source, contains('require_pattern'));
      expect(source, contains('require_manual_evidence'));
      expect(source, contains(r'require_non_empty "$evidence_file"'));
      expect(
        source,
        contains('manual proof path must stay under the evidence directory'),
      );
      expect(source, contains(r'\.(png|jpe?g|mp4|mov|webm)$'));
      expect(
        source,
        contains('manual proof must reference a screenshot or recording'),
      );
      expect(source, contains('install.txt'));
      expect(source, contains('deeplink_duoyi___tab_today.txt'));
      expect(source, contains('deeplink_duoyi___calendar.txt'));
      expect(
        source,
        contains('deeplink_duoyi___countdown_device_regression_missing.txt'),
      );
      expect(source, contains('deeplink_duoyi___action_quick_todo.txt'));
      expect(
        source,
        contains(
          'deeplink_duoyi___action_complete_todo_id_device_regression_missing.txt',
        ),
      );
      expect(
        source,
        contains(
          'deeplink_duoyi___action_checkin_habit_id_device_regression_missing.txt',
        ),
      );
      expect(source, contains('notification_assistant.txt'));
      expect(source, contains('notification_today_progress.txt'));
      expect(source, contains('notification shade today progress evidence'));
      expect(source, contains('reminder_alarm_queue.txt'));
      expect(source, contains('default_soft_ringtone.txt'));
      expect(source, contains('widget_providers.txt'));
      expect(source, contains('require_widget_provider'));
      expect(source, contains(r'Android launcher widget provider $provider'));
      expect(
        source,
        contains(
          r'require_pattern "$ANDROID_EVIDENCE_DIR/default_soft_ringtone.txt"',
        ),
      );
      expect(source, contains('default soft ringtone evidence'));
      expect(source, contains('single delivery status bar exclusion'));
      expect(source, contains('Today deep link success'));
      expect(source, contains('Calendar deep link success'));
      expect(source, contains('Countdown aggregate deep link success'));
      expect(source, contains('Quick todo deep link success'));
      expect(source, contains('Complete todo deep link success'));
      expect(source, contains('Habit check-in deep link success'));
      expect(source, contains('DuoyiTodoWidgetProvider'));
      expect(source, contains('DuoyiHabitWidgetProvider'));
      expect(source, contains('DuoyiCalendarWidgetProvider'));
      expect(source, contains('DuoyiScheduleWidgetProvider'));
      expect(source, contains('DuoyiGoalWidgetProvider'));
      expect(source, contains('DuoyiCourseWidgetProvider'));
      expect(source, contains('DuoyiNoteWidgetProvider'));
      expect(source, contains('DuoyiAnniversaryWidgetProvider'));
      expect(source, contains('DuoyiDiaryWidgetProvider'));
      expect(source, contains('DuoyiFocusHabitWidgetProvider'));
      expect(source, contains('manual_required.md'));
      expect(source, contains('manual_evidence_manifest.md'));
      expect(source, contains('notification_shade_progress'));
      expect(source, contains('launcher_widgets_10_added'));
      expect(source, contains('android_widget_style_matrix'));
      expect(source, contains('widget_refresh_before_after'));
      expect(source, contains('widget_todo_complete'));
      expect(source, contains('widget_quick_add'));
      expect(source, contains('widget_habit_checkin'));
      expect(source, contains('widget_gallery_10_widgets'));
      expect(source, contains('widgetkit_family_matrix'));
      expect(source, contains('calendar_countdown_deeplink'));
      expect(source, contains('ios_notification_behavior'));
      expect(source, contains('xcodebuild_device.log'));
      expect(source, contains('widgetkit_recent.log'));
      expect(source, contains('widgetkit_calendar_countdown_deeplink.log'));
      expect(source, contains('BUILD SUCCEEDED'));
      expect(source, contains('Device evidence validation failed'));
    },
  );
}
