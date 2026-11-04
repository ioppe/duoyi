String normalizeAppVersion(String value) =>
    value.replaceFirst(RegExp(r'^v'), '').split('-').first.split('+').first;

int compareAppVersions(String left, String right) {
  final leftParts = normalizeAppVersion(
    left,
  ).split('.').map((part) => int.tryParse(part) ?? 0).toList();
  final rightParts = normalizeAppVersion(
    right,
  ).split('.').map((part) => int.tryParse(part) ?? 0).toList();
  for (var i = 0; i < 3; i++) {
    final a = i < leftParts.length ? leftParts[i] : 0;
    final b = i < rightParts.length ? rightParts[i] : 0;
    if (a != b) return a.compareTo(b);
  }
  return 0;
}

/// build code 的可信来源。
///
/// 服务端/发布通道必须明确告知 code 从哪来：
/// - [AppVersionCodeSource.manifest]：APK 清单里的真实 versionCode；
/// - [AppVersionCodeSource.configured]：管理员显式配置的真实 build；
/// - [AppVersionCodeSource.derived]：由 versionName 推算出来的值，不是真实 build；
/// - [AppVersionCodeSource.unknown]：没有来源信息（老服务器）。
enum AppVersionCodeSource { manifest, configured, derived, unknown }

const String appVersionCodeSourceManifest = 'manifest';
const String appVersionCodeSourceConfigured = 'configured';
const String appVersionCodeSourceDerived = 'derived';
const String appVersionCodeSourceUnknown = 'unknown';

AppVersionCodeSource parseAppVersionCodeSource(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case appVersionCodeSourceManifest:
      return AppVersionCodeSource.manifest;
    case appVersionCodeSourceConfigured:
      return AppVersionCodeSource.configured;
    case appVersionCodeSourceDerived:
      return AppVersionCodeSource.derived;
    default:
      return AppVersionCodeSource.unknown;
  }
}

/// 旧的 `_versionToCode` 公式：major*100000 + minor*10000 + patch。
///
/// 仅用于识别“老服务器从 versionName 推算出来的假 build”，
/// 禁止再把它当成 Android versionCode 使用。
int legacyDerivedVersionCode(String versionName) {
  final parts = normalizeAppVersion(
    versionName,
  ).split('.').map((part) => int.tryParse(part) ?? 0).toList(growable: false);
  final major = parts.isNotEmpty ? parts[0] : 0;
  final minor = parts.length > 1 ? parts[1] : 0;
  final patch = parts.length > 2 ? parts[2] : 0;
  return major * 100000 + minor * 10000 + patch;
}

/// 解析出可信的 build code；不可信时返回 null。
///
/// 老服务器没有 `*_version_code_source` 字段，只能按“是否恰好等于旧公式推算值”
/// 反推：相等说明它是从 versionName 合成出来的，必须丢弃。真实的同名更高 build
/// （例如 140002 对 1.1.34）不等于推算值，继续保留。
int? resolveTrustedVersionCode({
  required String versionName,
  int? versionCode,
  String? codeSource,
}) {
  if (versionCode == null || versionCode <= 0) return null;
  switch (parseAppVersionCodeSource(codeSource)) {
    case AppVersionCodeSource.manifest:
    case AppVersionCodeSource.configured:
      return versionCode;
    case AppVersionCodeSource.derived:
      return null;
    case AppVersionCodeSource.unknown:
      final name = normalizeAppVersion(versionName.trim());
      if (name.isEmpty) return versionCode;
      return versionCode == legacyDerivedVersionCode(name) ? null : versionCode;
  }
}

/// 统一的新版本判定：版本名语义优先，name 相同才比可信 build。
///
/// - 远端版本名比当前旧：一律不算更新（即便 code 更大）；
/// - 远端版本名比当前新：算更新（不依赖 code）；
/// - name 相同：只有可信且更大的 code 才算更新；
/// - 没有版本名时退回 code 比较，兼容只会给 code 的老接口。
bool hasNewerAppVersion({
  required String currentVersion,
  int? currentVersionCode,
  String? latestVersion,
  int? latestVersionCode,
}) {
  final latest = latestVersion?.trim() ?? '';
  final hasCurrentCode = currentVersionCode != null && currentVersionCode > 0;
  final codeIsNewer =
      hasCurrentCode &&
      latestVersionCode != null &&
      latestVersionCode > currentVersionCode;
  if (latest.isEmpty) return codeIsNewer;
  final comparison = compareAppVersions(latest, currentVersion);
  if (comparison != 0) return comparison > 0;
  return codeIsNewer;
}

bool shouldForceAppUpdate({
  required String currentVersion,
  required String? latestVersion,
  required String? minimumSupportedVersion,
  required bool forceUpdateRequired,
  int? currentVersionCode,
  int? latestVersionCode,
  int? minimumSupportedVersionCode,
}) {
  if (!forceUpdateRequired) return false;
  final hasCurrentCode = currentVersionCode != null && currentVersionCode > 0;
  bool codeIsNewer(int? code) =>
      hasCurrentCode && code != null && code > currentVersionCode;
  final latest = latestVersion?.trim() ?? '';
  if (latest.isNotEmpty) {
    final comparison = compareAppVersions(latest, currentVersion);
    if (comparison > 0) return true;
    // name 相同：只有可信且更大的 build 才算强制更新；name 更旧：忽略 code。
    if (comparison == 0 && codeIsNewer(latestVersionCode)) return true;
  } else if (codeIsNewer(latestVersionCode)) {
    return true;
  }
  final minimum = minimumSupportedVersion?.trim() ?? '';
  if (minimum.isEmpty) return false;
  final minimumComparison = compareAppVersions(currentVersion, minimum);
  if (minimumComparison < 0) return true;
  return minimumComparison == 0 && codeIsNewer(minimumSupportedVersionCode);
}

String formatUpdateNotesForDisplay(String? notes) {
  final raw = notes?.trim();
  if (raw == null || raw.isEmpty) return '';
  final normalized = raw
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
      .replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^)]+\)'),
        (match) => match.group(1) ?? '',
      );
  final summaryLines = <String>[];
  for (final rawLine in normalized.split('\n')) {
    final line = updateNoteSummaryLine(rawLine);
    if (line == null || summaryLines.contains(line)) continue;
    summaryLines.add(line);
    if (summaryLines.length >= 8) break;
  }
  if (summaryLines.isEmpty) return '';
  return '本次更新摘要：\n${summaryLines.map((line) => '- $line').join('\n')}';
}

String? updateNoteSummaryLine(String rawLine) {
  var line = rawLine
      .trim()
      .replaceFirst(RegExp(r'^#{1,6}\s*'), '')
      .replaceFirst(RegExp(r'^[>\-\*\u2022\d\.\)\s]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (line.isEmpty) return null;

  final normalized = line
      .replaceFirst(RegExp(r'^[*_\\s]+'), '')
      .replaceAll('*', '')
      .replaceAll('_', '')
      .trim()
      .toLowerCase();
  if (normalized.startsWith('full changelog') ||
      normalized.startsWith('compare changes') ||
      normalized == 'what\'s changed' ||
      normalized == '更新内容' ||
      normalized == '更新说明' ||
      normalized == '本次更新' ||
      normalized == '本次更新摘要') {
    return null;
  }
  if (normalized.contains('github.com') &&
      (normalized.contains('/compare/') ||
          normalized.contains('/releases/tag/'))) {
    return null;
  }
  line = line
      .replaceFirst(RegExp(r'^本次更新[：:]\s*'), '')
      .replaceFirst(RegExp(r'^更新内容[：:]\s*'), '')
      .trim();
  return line.isEmpty ? null : line;
}
