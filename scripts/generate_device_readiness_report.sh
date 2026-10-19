#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/tool_paths.sh"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/build/device-readiness/latest}"
OUTPUT_PARENT="$(dirname "$OUTPUT_DIR")"
mkdir -p "$OUTPUT_PARENT"
TEMP_OUTPUT_DIR="$(mktemp -d "$OUTPUT_PARENT/.device-readiness.tmp.XXXXXX")"
SUMMARY_TSV="$TEMP_OUTPUT_DIR/summary.tsv"
SUMMARY_MD="$TEMP_OUTPUT_DIR/summary.md"
FLUTTER_DEVICES="$TEMP_OUTPUT_DIR/flutter_devices.txt"
FLUTTER_DEVICES_MACHINE="$TEMP_OUTPUT_DIR/flutter_devices_machine.json"
ADB_DEVICES="$TEMP_OUTPUT_DIR/adb_devices.txt"
SDKMANAGER_LIST="$TEMP_OUTPUT_DIR/sdkmanager_list.txt"
AVD_LIST="$TEMP_OUTPUT_DIR/avd_list.txt"
HOST_UNAME="$TEMP_OUTPUT_DIR/host_uname.txt"

HOST_ARCH="$(uname -m)"
HOST_OS="$(uname -s)"
KVM_DEVICE="${KVM_DEVICE:-/dev/kvm}"

write_row() {
  local check="$1"
  local status="$2"
  local detail="$3"
  printf '%s\t%s\t%s\n' "$check" "$status" "$detail" >> "$SUMMARY_TSV"
  printf '| %s | %s | %s |\n' "$check" "$status" "$detail" >> "$SUMMARY_MD"
}

printf 'check\tstatus\tdetail\n' > "$SUMMARY_TSV"
cat > "$SUMMARY_MD" <<'MSG'
# Device Readiness Report

| Check | Status | Detail |
| --- | --- | --- |
MSG

if [[ -x "$FLUTTER_BIN" ]]; then
  "$FLUTTER_BIN" devices > "$FLUTTER_DEVICES" 2>&1 || true
  "$FLUTTER_BIN" devices --machine > "$FLUTTER_DEVICES_MACHINE" 2>&1 || true
else
  printf 'flutter missing: %s\n' "$FLUTTER_BIN" > "$FLUTTER_DEVICES"
  printf '[]\n' > "$FLUTTER_DEVICES_MACHINE"
fi

uname -a > "$HOST_UNAME" 2>&1 || true
write_row host_architecture available "Host OS is $HOST_OS and architecture is $HOST_ARCH."

if grep -Eq '"targetPlatform":"android' "$FLUTTER_DEVICES_MACHINE"; then
  write_row android_runtime ready 'Flutter detects an Android device or emulator.'
else
  write_row android_runtime missing 'Flutter does not detect an Android device or emulator.'
fi

if grep -Eq '"targetPlatform":"ios' "$FLUTTER_DEVICES_MACHINE"; then
  write_row ios_runtime ready 'Flutter detects an iOS device.'
else
  write_row ios_runtime missing 'Flutter does not detect an iOS device.'
fi

if [[ -x "$ADB_BIN" ]]; then
  "$ADB_BIN" devices > "$ADB_DEVICES" 2>&1 || true
  if awk 'NR > 1 && $2 == "device" { found = 1 } END { exit found ? 0 : 1 }' "$ADB_DEVICES"; then
    write_row adb_device ready 'adb lists at least one connected Android device.'
  else
    write_row adb_device missing 'adb lists no connected Android device.'
  fi
else
  printf 'adb missing: %s\n' "$ADB_BIN" > "$ADB_DEVICES"
  write_row adb_device missing "adb is missing at $ADB_BIN."
fi

if [[ -x "$EMULATOR_BIN" ]]; then
  write_row android_emulator_binary ready "Android Emulator binary exists at $EMULATOR_BIN."
else
  write_row android_emulator_binary missing "Android Emulator binary is missing at $EMULATOR_BIN."
fi

if [[ -x "$SDKMANAGER_BIN" ]]; then
  "$SDKMANAGER_BIN" --list > "$SDKMANAGER_LIST" 2>&1 || true
  if grep -Eq '^ +emulator[[:space:]]' "$SDKMANAGER_LIST"; then
    write_row android_emulator_package available 'sdkmanager lists the Android Emulator package.'
  else
    write_row android_emulator_package missing 'sdkmanager does not list Android Emulator for this host.'
  fi
else
  printf 'sdkmanager missing: %s\n' "$SDKMANAGER_BIN" > "$SDKMANAGER_LIST"
  write_row android_emulator_package missing "sdkmanager is missing at $SDKMANAGER_BIN."
fi

if [[ -x "$AVDMANAGER_BIN" ]]; then
  "$AVDMANAGER_BIN" list avd > "$AVD_LIST" 2>&1 || true
  if grep -Eq '^ +Name:' "$AVD_LIST"; then
    write_row android_avd ready 'At least one Android Virtual Device is configured.'
  else
    write_row android_avd missing 'No Android Virtual Device is configured.'
  fi
else
  printf 'avdmanager missing: %s\n' "$AVDMANAGER_BIN" > "$AVD_LIST"
  write_row android_avd missing "avdmanager is missing at $AVDMANAGER_BIN."
fi

ANDROID_SYSTEM_IMAGE_SAMPLE="$(find "$ANDROID_SDK_ROOT/system-images" -mindepth 1 -maxdepth 4 -type d -print -quit 2>/dev/null || true)"
if [[ -n "$ANDROID_SYSTEM_IMAGE_SAMPLE" ]]; then
  write_row android_system_images ready "Android system images exist under $ANDROID_SDK_ROOT/system-images."
else
  write_row android_system_images missing "Android system images are missing under $ANDROID_SDK_ROOT/system-images."
fi

if [[ -e "$KVM_DEVICE" && -r "$KVM_DEVICE" && -w "$KVM_DEVICE" ]]; then
  write_row kvm available "$KVM_DEVICE exists and is readable/writable for accelerated Android emulator support."
elif [[ -e "$KVM_DEVICE" ]]; then
  write_row kvm missing "$KVM_DEVICE exists but is not readable/writable by this user; accelerated Android emulator support is unavailable."
else
  write_row kvm missing "$KVM_DEVICE is missing; accelerated Android emulator is unavailable."
fi

if [[ ! -x "$EMULATOR_BIN" ]]; then
  write_row android_emulator_launchability missing 'Android Emulator binary is missing, so no local emulator launch can be trusted.'
elif [[ "$HOST_OS" == "Linux" && "$HOST_ARCH" != "x86_64" && "$HOST_ARCH" != "amd64" ]]; then
  write_row android_emulator_launchability missing "Linux host architecture $HOST_ARCH is not x86_64; use an attached Android device or a matching host."
elif [[ "$HOST_OS" == "Linux" && ( ! -r "$KVM_DEVICE" || ! -w "$KVM_DEVICE" ) ]]; then
  write_row android_emulator_launchability missing "Linux Android Emulator launchability is not ready because $KVM_DEVICE is missing or not accessible."
elif [[ -x "$AVDMANAGER_BIN" ]] && grep -Eq '^ +Name:' "$AVD_LIST"; then
  write_row android_emulator_launchability ready 'Android Emulator binary and at least one AVD are present for this host.'
else
  write_row android_emulator_launchability missing 'No configured AVD is available for the Android Emulator.'
fi

if [[ "$(uname -s)" == "Darwin" ]] && command -v xcrun >/dev/null 2>&1 && command -v xcodebuild >/dev/null 2>&1; then
  write_row ios_host ready 'macOS, xcrun, and xcodebuild are available.'
else
  write_row ios_host missing 'iOS evidence requires macOS with xcrun and xcodebuild.'
fi

rm -rf "$OUTPUT_DIR"
mv "$TEMP_OUTPUT_DIR" "$OUTPUT_DIR"
echo "Device readiness report written to $OUTPUT_DIR"
