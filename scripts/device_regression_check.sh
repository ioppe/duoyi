#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/tool_paths.sh"
ANDROID_EVIDENCE_SCRIPT="$ROOT_DIR/scripts/android_device_evidence.sh"
IOS_EVIDENCE_SCRIPT="$ROOT_DIR/scripts/ios_device_evidence.sh"
VALIDATE_EVIDENCE_SCRIPT="$ROOT_DIR/scripts/validate_device_evidence.sh"
READINESS_SCRIPT="$ROOT_DIR/scripts/generate_device_readiness_report.sh"
VALIDATE_READINESS_SCRIPT="$ROOT_DIR/scripts/validate_device_readiness_report.sh"
READINESS_DIR="${READINESS_DIR:-$ROOT_DIR/build/device-readiness/latest}"
KVM_DEVICE="${KVM_DEVICE:-/dev/kvm}"

cd "$ROOT_DIR"

echo "== Device discovery =="
"$FLUTTER_BIN" devices

echo
echo "== Device readiness report =="
OUTPUT_DIR="$READINESS_DIR" "$READINESS_SCRIPT"
REPORT_DIR="$READINESS_DIR" "$VALIDATE_READINESS_SCRIPT"
echo "Device readiness details: $READINESS_DIR"

echo
echo "== Android adb devices =="
if [[ -x "$ADB_BIN" ]]; then
  "$ADB_BIN" devices
else
  echo "adb not found at $ADB_BIN"
fi

echo
echo "== Emulator prerequisites =="
echo "host architecture: $(uname -m)"
if [[ -x "$EMULATOR_BIN" ]]; then
  echo "emulator binary: $EMULATOR_BIN"
  "$EMULATOR_BIN" -list-avds || true
else
  echo "emulator binary missing: $EMULATOR_BIN"
  if [[ -x "$SDKMANAGER_BIN" ]]; then
    if "$SDKMANAGER_BIN" --list 2>/dev/null | grep -Eq '^ +emulator[[:space:]]'; then
      echo "sdkmanager lists Android Emulator; install it with: $SDKMANAGER_BIN \"emulator\""
    else
      echo "sdkmanager does not list Android Emulator for this host; use an attached Android device or a host with emulator support"
    fi
  else
    echo "sdkmanager missing: $SDKMANAGER_BIN"
  fi
fi
if [[ -x "$AVDMANAGER_BIN" ]]; then
  "$AVDMANAGER_BIN" list avd || true
else
  echo "avdmanager missing: $AVDMANAGER_BIN"
fi
system_image_sample="$(find "$ANDROID_SDK_ROOT/system-images" -mindepth 1 -maxdepth 4 -type d -print -quit 2>/dev/null || true)"
if [[ -n "$system_image_sample" ]]; then
  find "$ANDROID_SDK_ROOT/system-images" -mindepth 1 -maxdepth 4 -type d | sort | sed -n '1,20p'
else
  echo "Android system images missing under $ANDROID_SDK_ROOT/system-images"
fi
if [[ -e "$KVM_DEVICE" && -r "$KVM_DEVICE" && -w "$KVM_DEVICE" ]]; then
  ls -l "$KVM_DEVICE"
elif [[ -e "$KVM_DEVICE" ]]; then
  echo "$KVM_DEVICE exists but is not readable/writable by this user; accelerated Android emulator is not available"
else
  echo "$KVM_DEVICE missing; accelerated Android emulator is not available in this environment"
fi

if ! "$FLUTTER_BIN" devices --machine | grep -Eq '"targetPlatform":"(android|ios)'; then
  cat <<'MSG' >&2

No Android or iOS device/emulator is attached.
Device-only regression cannot be closed yet. Required checks:
- Android notification shade shows today's task progress and the setting can turn it off.
- Android popup/alarm/full-screen reminder fires, vibrates, and plays the selected built-in ringtone.
- Default ringtone is the softer "柔和晨铃" sound on a real device.
- Android launcher widgets can be added, resized, opened, refreshed, and complete/check in items.
- iOS WidgetKit widgets share the App Group and refresh after app data changes.

Attach a device or emulator, then rerun scripts/device_regression_check.sh.
MSG
  exit 2
fi

echo
echo "== Build debug APK =="
"$FLUTTER_BIN" build apk --debug

echo
echo "== Integration smoke test =="
"$FLUTTER_BIN" test integration_test/app_alignment_smoke_test.dart

android_evidence_status=1
ios_evidence_status=1

if "$FLUTTER_BIN" devices --machine | grep -Eq '"targetPlatform":"android'; then
  echo
  echo "== Android device evidence =="
  "$ANDROID_EVIDENCE_SCRIPT"
  if "$VALIDATE_EVIDENCE_SCRIPT" android; then
    android_evidence_status=0
  fi
else
  echo
  echo "No Android device detected for android_device_evidence.sh; iOS/manual WidgetKit checks still required where applicable."
fi

if "$FLUTTER_BIN" devices --machine | grep -Eq '"targetPlatform":"ios'; then
  echo
  echo "== iOS device evidence =="
  "$IOS_EVIDENCE_SCRIPT"
  if "$VALIDATE_EVIDENCE_SCRIPT" ios; then
    ios_evidence_status=0
  fi
else
  echo
  echo "No iOS device detected for ios_device_evidence.sh; WidgetKit gallery, App Group signing, and iOS notification checks remain manual."
fi

if [[ "$android_evidence_status" -ne 0 || "$ios_evidence_status" -ne 0 ]]; then
  cat <<'MSG' >&2

Device-only regression is not closed.
Both Android and iOS evidence must pass before the 8/8 gate can pass.
Run scripts/validate_device_evidence.sh android and scripts/validate_device_evidence.sh ios after collecting real device evidence.
MSG
  exit 2
fi

cat <<'MSG'

Automated Android and iOS device evidence passed. Continue with docs/manual-regression-checklist.md sections:
- 5. 通知 vs 闹钟
- 13. 测试套件
- 14. 黑屏 / 崩溃
- 24. 课程深链 / 倒数日可见性
- 25. 小组件完成动作
MSG
