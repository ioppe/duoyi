#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/tool_paths.sh"
PACKAGE_NAME="${PACKAGE_NAME:-com.duoyi.duoyi}"
APK_PATH="${APK_PATH:-$ROOT_DIR/build/app/outputs/flutter-apk/app-debug.apk}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$ROOT_DIR/build/device-regression/android}"
ANDROID_BASE_WIDGET_PROVIDERS=(
  DuoyiTodoWidgetProvider
  DuoyiHabitWidgetProvider
  DuoyiCalendarWidgetProvider
  DuoyiScheduleWidgetProvider
  DuoyiGoalWidgetProvider
  DuoyiCourseWidgetProvider
  DuoyiNoteWidgetProvider
  DuoyiAnniversaryWidgetProvider
  DuoyiDiaryWidgetProvider
  DuoyiFocusHabitWidgetProvider
)

cd "$ROOT_DIR"
mkdir -p "$EVIDENCE_DIR"

if [[ ! -x "$ADB_BIN" ]]; then
  echo "adb not found at $ADB_BIN" >&2
  exit 2
fi

if ! "$ADB_BIN" get-state >/dev/null 2>&1; then
  "$ADB_BIN" devices > "$EVIDENCE_DIR/adb_devices.txt" 2>&1 || true
  cat > "$EVIDENCE_DIR/no_android_device.md" <<MSG
# No Android Device

adb did not report a connected Android device for package \`$PACKAGE_NAME\`.
Android device evidence was not collected, and this file is not proof of runtime behavior.
Attach an Android phone or emulator, then rerun scripts/device_regression_check.sh.
MSG
  echo "No adb device is connected. Attach an Android phone or emulator first." >&2
  exit 2
fi

if [[ ! -f "$APK_PATH" ]]; then
  echo "APK missing at $APK_PATH. Run /home/ubuntu/flutter/bin/flutter build apk --debug first." >&2
  exit 2
fi

echo "== Android device evidence =="
"$ADB_BIN" shell getprop ro.product.manufacturer | tee "$EVIDENCE_DIR/device_manufacturer.txt"
"$ADB_BIN" shell getprop ro.product.model | tee "$EVIDENCE_DIR/device_model.txt"
"$ADB_BIN" shell getprop ro.build.version.release | tee "$EVIDENCE_DIR/android_version.txt"
"$ADB_BIN" shell getprop ro.build.version.sdk | tee "$EVIDENCE_DIR/android_sdk.txt"

echo
echo "== Install debug APK =="
"$ADB_BIN" install -r "$APK_PATH" | tee "$EVIDENCE_DIR/install.txt"

echo
echo "== Launch app and exercise representative deep links =="
"$ADB_BIN" shell monkey -p "$PACKAGE_NAME" -c android.intent.category.LAUNCHER 1 | tee "$EVIDENCE_DIR/launch.txt"
sleep 3
for uri in \
  'duoyi://tab/today' \
  'duoyi://calendar' \
  'duoyi://countdown/device-regression-missing' \
  'duoyi://action/quick_todo' \
  'duoyi://action/complete_todo?id=device-regression-missing' \
  'duoyi://action/checkin_habit?id=device-regression-missing'; do
  safe_name="$(printf '%s' "$uri" | tr -c 'A-Za-z0-9' '_')"
  "$ADB_BIN" shell am start -W -a android.intent.action.VIEW -d "$uri" "$PACKAGE_NAME" \
    | tee "$EVIDENCE_DIR/deeplink_${safe_name}.txt"
done

echo
echo "== Permissions and app ops =="
"$ADB_BIN" shell dumpsys package "$PACKAGE_NAME" > "$EVIDENCE_DIR/package.txt" || true
"$ADB_BIN" shell appops get "$PACKAGE_NAME" > "$EVIDENCE_DIR/appops.txt" || true
"$ADB_BIN" shell cmd notification get_approved_assistant 2>/dev/null > "$EVIDENCE_DIR/notification_assistant.txt" || true

echo
echo "== Shared preferences and notification channel state =="
"$ADB_BIN" shell run-as "$PACKAGE_NAME" find shared_prefs -maxdepth 1 -type f 2>/dev/null \
  > "$EVIDENCE_DIR/shared_prefs_files.txt" || true
"$ADB_BIN" shell run-as "$PACKAGE_NAME" grep -R \
  -E 'pref_reminder_ringtone_sound|pref_reminder_ringtone_volume_percent|pref_notification_today_progress|reminder_method|popup|alarm' \
  shared_prefs 2>/dev/null > "$EVIDENCE_DIR/reminder_preferences.txt" || true
"$ADB_BIN" shell cmd notification channels "$PACKAGE_NAME" 2>/dev/null \
  > "$EVIDENCE_DIR/notification_channels.txt" || true

echo
echo "== Notification alarm and widget dumpsys evidence =="
"$ADB_BIN" shell dumpsys notification --noredact > "$EVIDENCE_DIR/dumpsys_notification.txt" || true
"$ADB_BIN" shell dumpsys alarm > "$EVIDENCE_DIR/dumpsys_alarm.txt" || true
"$ADB_BIN" shell dumpsys appwidget > "$EVIDENCE_DIR/dumpsys_appwidget.txt" || true

grep -E 'today|progress|NotificationStatusBar|常驻|进度|Duoyi' \
  "$EVIDENCE_DIR/dumpsys_notification.txt" > "$EVIDENCE_DIR/notification_today_progress.txt" || true
"$ADB_BIN" shell run-as "$PACKAGE_NAME" grep -R -E 'pref_notification_today_progress' shared_prefs 2>/dev/null \
  >> "$EVIDENCE_DIR/notification_today_progress.txt" || true
grep -E 'ReminderRingtone|duoyi_|AlarmManager|RTC_WAKEUP|ELAPSED' \
  "$EVIDENCE_DIR/dumpsys_alarm.txt" > "$EVIDENCE_DIR/reminder_alarm_queue.txt" || true
grep -E 'duoyi_soft|柔和晨铃|pref_reminder_ringtone_sound[^[:space:]]*soft|sound[[:space:]_:-]*=[[:space:]]*soft|id[[:space:]_:-]*=[[:space:]]*soft' \
  "$EVIDENCE_DIR/reminder_preferences.txt" "$EVIDENCE_DIR/notification_channels.txt" \
  > "$EVIDENCE_DIR/default_soft_ringtone.txt" || true
cat > "$EVIDENCE_DIR/single_delivery_no_duplicate.txt" <<'MSG'
# Fill after the single-delivery manual run on this device.
# The validator requires duplicate_delivery_count=0.
# Exclude the ongoing notification shade progress row from delivery counts.
reminder_id=device-regression-single-delivery
flutter_pending_count=manual
native_pending_count=manual
status_bar_excluded=pending
delivered_count=manual
duplicate_delivery_count=pending
MSG

echo
echo "== Widget provider registration evidence =="
widget_provider_pattern="$(IFS='|'; printf '%s' "${ANDROID_BASE_WIDGET_PROVIDERS[*]}")"
grep -E "$widget_provider_pattern" \
  "$EVIDENCE_DIR/package.txt" > "$EVIDENCE_DIR/widget_providers.txt" || true

echo
echo "== Recent logcat evidence =="
"$ADB_BIN" logcat -d -v time \
  | grep -E 'Duoyi|ReminderRingtone|NotificationStatusBar|AppWidget|Flutter' \
  | tail -n 400 > "$EVIDENCE_DIR/logcat_duoyi.txt" || true

cat > "$EVIDENCE_DIR/manual_required.md" <<'MSG'
# Android Manual Proof Required

- Notification shade: capture today task progress, then disable the setting and capture the notification removed.
- Reminder methods: schedule notification, popup, and alarm/full-screen reminders one minute ahead; capture firing, vibration, and selected ringtone.
- Single delivery: repeat-save and cold-start the same reminder, then capture that only one notification/dialog/alarm fires for that reminder id; do not count the ongoing notification shade progress row as a reminder delivery.
- Default ringtone: capture the picker/default state showing `柔和晨铃`, and verify it plays softer than the old alarm sound.
- Launcher widgets: confirm `widget_providers.txt` lists Todo, Habit, Calendar, Schedule, Goal, Course, Note, Anniversary, Diary, and FocusHabit providers; add all visible Duoyi widgets, resize them, open details, refresh, complete a todo, quick-add a todo, and check in a habit.
- Widget style matrix: record compact, standard, and detailed widget sizes/display modes on the launcher where supported.
- Countdown deep link: use the Today schedule/calendar aggregate evidence only; do not add or expect a standalone countdown widget.
MSG

cat > "$EVIDENCE_DIR/manual_evidence_manifest.md" <<'MSG'
# Android Manual Evidence Manifest

Set each item to `passed - relative/path` only after the screenshot or recording exists in the release evidence bundle.

- notification_shade_progress: pending - evidence/manual/android_notification_progress.png
- notification_shade_toggle_off: pending - evidence/manual/android_notification_toggle_off.png
- reminder_notification_popup_alarm: pending - evidence/manual/android_reminder_modes.mp4
- single_delivery_no_duplicate: pending - evidence/manual/android_single_delivery_no_duplicate.mp4
- default_soft_ringtone: pending - evidence/manual/android_default_soft_ringtone.mp4
- launcher_widgets_10_added: pending - evidence/manual/android_launcher_widgets_10_added.mp4
- android_widget_style_matrix: pending - evidence/manual/android_widget_style_matrix.mp4
- widget_refresh_before_after: pending - evidence/manual/android_widget_refresh_before_after.mp4
- widget_todo_complete: pending - evidence/manual/android_widget_todo_complete.mp4
- widget_quick_add: pending - evidence/manual/android_widget_quick_add.mp4
- widget_habit_checkin: pending - evidence/manual/android_widget_habit_checkin.mp4
- calendar_countdown_deeplink: pending - evidence/manual/android_calendar_countdown_deeplink.mp4
MSG

cat <<MSG

Android device evidence written to:
$EVIDENCE_DIR

Manual verification still required on the same device:
- Pull down notification shade and confirm today's task progress notification appears/updates/cancels by setting.
- Schedule a reminder for 1 minute later and confirm popup/alarm/full-screen behavior, vibration, and selected ringtone.
- Save/resync the same reminder more than once and confirm only one notification/dialog/alarm fires.
- After the single-delivery run, update `single_delivery_no_duplicate.txt` with observed counts, set `status_bar_excluded=true`, and keep `duplicate_delivery_count=0`.
- Confirm the default ringtone is 柔和晨铃 and the evidence file default_soft_ringtone.txt contains a soft/default marker after settings are initialized.
- Add launcher widgets after confirming widget_providers.txt lists all 10 base launcher widget providers; resize them, tap item/detail/complete/check-in/quick-add actions, and confirm app state updates.
- Confirm countdown opens from Today schedule/calendar aggregate deep links only; no standalone countdown widget is required or expected.
MSG
