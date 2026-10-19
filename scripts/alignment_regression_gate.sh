#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/tool_paths.sh"
REPORT_DIR="${REPORT_DIR:-$ROOT_DIR/build/alignment-regression/latest}"
SUMMARY_TSV="$REPORT_DIR/summary.tsv"
SUMMARY_MD="$REPORT_DIR/summary.md"
FAILURES=0

cd "$ROOT_DIR"
rm -rf "$REPORT_DIR"
mkdir -p "$REPORT_DIR"
printf 'group\tstatus\tduration_seconds\tlog\n' > "$SUMMARY_TSV"
cat > "$SUMMARY_MD" <<'MSG'
# Alignment Regression Gate

| Group | Status | Duration | Log |
| --- | --- | ---: | --- |
MSG

run_group() {
  local name="$1"
  local slug
  local log_file
  local start
  local status
  local exit_code=0
  local duration
  shift

  slug="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '_' | sed -E 's/^_+|_+$//g')"
  log_file="$REPORT_DIR/${slug}.log"
  echo
  echo "== $name =="
  start="$(date +%s)"
  set +e
  "$@" 2>&1 | tee "$log_file"
  exit_code=${PIPESTATUS[0]}
  set -e
  duration=$(( $(date +%s) - start ))
  if [[ "$exit_code" -eq 0 ]]; then
    status="passed"
  else
    status="failed($exit_code)"
    FAILURES=$((FAILURES + 1))
  fi
  printf '%s\t%s\t%s\t%s\n' "$name" "$status" "$duration" "$log_file" >> "$SUMMARY_TSV"
  printf '| %s | %s | %ss | `%s` |\n' "$name" "$status" "$duration" "$log_file" >> "$SUMMARY_MD"
  if [[ "$exit_code" -ne 0 ]]; then
    echo "Group failed: $name (exit $exit_code). Report written to $REPORT_DIR"
    exit "$exit_code"
  fi
}

run_group "1/8 404 and route contracts" \
  "$FLUTTER_BIN" test \
    test/screens/today_detail_router_test.dart \
    test/screens/today_detail_router_static_test.dart \
    test/services/api_route_contract_static_test.dart \
    test/services/api_client_error_test.dart

run_group "2/8 style layout and readable selection" \
  "$FLUTTER_BIN" test \
    test/services/no_global_bold_static_test.dart \
    test/screens/style_layout_regression_static_test.dart \
    test/widgets/surface_secondary_control_static_test.dart \
    test/screens/almanac_screen_test.dart \
    test/screens/almanac_actions_static_test.dart \
    test/screens/countdown_screen_test.dart \
    test/screens/countdown_visibility_static_test.dart \
    test/services/backup_service_test.dart \
    test/screens/todo_batch_static_test.dart \
    test/screens/todo_kanban_view_test.dart \
    test/screens/feedback_screen_test.dart \
    test/screens/admin_feedback_screen_test.dart \
    test/screens/habit_screen_test.dart \
    test/screens/habit_grouping_static_test.dart \
    test/screens/profile_screen_test.dart \
    test/screens/today_mine_static_test.dart \
    test/screens/today_mine_smoke_test.dart \
    test/providers/auth_provider_profile_static_test.dart \
    test/providers/auth_provider_profile_test.dart \
    test/services/admin_user_status_test.dart \
    test/services/admin_permissions_coins_static_test.dart \
    test/services/admin_force_update_settings_test.dart

run_group "3/8 notification ringtone and status progress" \
  "$FLUTTER_BIN" test \
    test/services/device_regression_script_static_test.dart \
    test/services/device_readiness_report_test.dart \
    test/services/device_evidence_validator_test.dart \
    test/services/alignment_report_validator_test.dart \
    test/services/goal_closure_validator_test.dart \
    test/services/goal_requirement_matrix_test.dart \
    test/services/goal_requirement_status_test.dart \
    test/services/reminder_scheduler_integration_test.dart \
    test/services/reminder_resync_static_test.dart \
    test/services/reminder_email_channel_test.dart \
    test/services/channel_routing_pbt_test.dart \
    test/services/foreground_reminder_popup_sink_test.dart \
    test/services/notification_quick_add_static_test.dart \
    test/providers/preferences_provider_test.dart \
    test/providers/notification_service_test.dart \
    test/screens/ai_schedule_flow_static_test.dart \
    test/widgets/calendar_local_event_static_test.dart \
    test/services/reminder_ringtone_settings_test.dart \
    test/services/native_reminder_ringtone_static_test.dart \
    test/services/notification_status_bar_service_test.dart \
    test/services/notification_today_progress_preferences_test.dart

run_group "4/8 widgets Android and iOS static contracts" \
  "$FLUTTER_BIN" test \
    test/services/android_widget_resources_test.dart \
    test/services/ios_widget_resources_test.dart

run_group "5/8 admin groups default coins and permissions" \
  bash -lc "cd backend && '$PYTHON_BIN' -m unittest \
    test_workspaces.WorkspaceApiTest.test_public_health_and_config_include_api_contract \
    test_workspaces.WorkspaceApiTest.test_api_contract_required_routes_are_registered \
    test_workspaces.WorkspaceApiTest.test_auth_email_code_profile_and_email_alias_routes_are_live \
    test_workspaces.WorkspaceApiTest.test_profile_email_login_and_avatar_compat_routes_do_not_404 \
    test_workspaces.WorkspaceApiTest.test_user_reported_empty_endpoint_contracts_do_not_404 \
    test_workspaces.WorkspaceApiTest.test_admin_coin_adjustment_compat_routes_and_fields_do_not_404 \
    test_workspaces.WorkspaceApiTest.test_admin_test_buttons_http_routes_do_not_404 \
    test_workspaces.WorkspaceApiTest.test_re0_feedback_password_overview_and_backup_alias_routes_do_not_404 \
    test_workspaces.WorkspaceApiTest.test_admin_re0_named_routes_for_users_coins_invites_and_settings \
    test_workspaces.WorkspaceApiTest.test_admin_current_management_routes_do_not_404 \
    test_workspaces.WorkspaceApiTest.test_account_api_fallback_routes_match_client_contracts \
    test_workspaces.WorkspaceApiTest.test_admin_coin_fallback_routes_match_client_contracts \
    test_workspaces.WorkspaceApiTest.test_admin_large_data_lists_return_paged_responses \
    test_workspaces.WorkspaceApiTest.test_admin_large_data_lists_support_sort_contracts \
    test_workspaces.WorkspaceApiTest.test_admin_user_export_online_filter_and_bulk_status \
    test_workspaces.WorkspaceApiTest.test_admin_backup_exports_use_filters_and_escape_formulas \
    test_workspaces.WorkspaceApiTest.test_password_reset_request_returns_dev_code_without_mail_provider \
    test_workspaces.WorkspaceApiTest.test_change_password_requires_current_password_and_rotates_login \
    test_workspaces.WorkspaceApiTest.test_admin_feedback_reply_and_delete_validate_targets \
    test_workspaces.WorkspaceApiTest.test_my_feedback_supports_pagination_without_breaking_legacy_list \
    test_workspaces.WorkspaceApiTest.test_admin_feedback_export_csv_uses_filters_and_escapes_formulas \
    test_workspaces.WorkspaceApiTest.test_admin_groups_roles_permissions_routes_match_re0_contracts \
    test_workspaces.WorkspaceApiTest.test_admin_group_assignment_grants_target_group_default_coins_once \
    test_workspaces.WorkspaceApiTest.test_admin_cannot_create_or_assign_disabled_group"

run_group "6/8 Flutter analyzer" \
  "$FLUTTER_BIN" analyze

run_group "7/8 debug APK build" \
  "$FLUTTER_BIN" build apk --debug

run_group "8/8 device-only notification alarm widget regression" \
  scripts/device_regression_check.sh

echo
echo "Alignment regression gate passed. Report written to $REPORT_DIR"
