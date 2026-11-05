import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';
import '../core/server_connection.dart';
import '../core/app_update_policy.dart';
import 'api_client.dart';
import 'app_update_installer.dart';

/// Polls a GitHub repo's latest release and exposes update info.
class AppUpdateService extends ChangeNotifier {
  static const _downloadedPathKey = 'duoyi_update_downloaded_apk_path';
  static const _downloadedVersionKey = 'duoyi_update_downloaded_apk_version';
  static const _downloadedVersionCodeKey =
      'duoyi_update_downloaded_apk_version_code';
  static const _downloadedVersionCodeSourceKey =
      'duoyi_update_downloaded_apk_version_code_source';
  static const _downloadedUrlKey = 'duoyi_update_downloaded_apk_url';
  static const _downloadedAssetNameKey =
      'duoyi_update_downloaded_apk_asset_name';

  final String repo; // owner/repository, supplied by deployment configuration.
  final String currentVersion; // e.g. "1.0.0"
  final int? currentVersionCode;
  final String? backendBaseUrl;
  final String Function()? backendBaseUrlGetter;
  final http.Client _httpClient;

  AppUpdateService({
    required this.repo,
    required this.currentVersion,
    this.currentVersionCode,
    this.backendBaseUrl,
    this.backendBaseUrlGetter,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  String? _latestVersion;
  int? _latestVersionCode;

  /// 只保留可信来源（清单/显式配置/老接口真实值）的 build code。
  int? _latestVersionCodeTrusted;
  int? _minimumSupportedVersionCodeTrusted;
  int? _latestVersionCodeRaw;
  String? _latestVersionCodeSourceText;
  String? _latestUrl;
  String? _latestAssetName;
  String? _latestNotes;
  String? _minimumSupportedVersion;
  int? _minimumSupportedVersionCode;
  String? _forceUpdateBlockedReason;
  bool _forceUpdateRequired = false;
  bool _serverPolicyLoaded = false;
  bool _checking = false;
  bool _serverPolicyRefreshQueued = false;
  bool _downloading = false;
  bool _installing = false;
  double? _downloadProgress;
  String? _downloadedFilePath;
  String? _error;
  DateTime? _lastDownloadProgressNotifyAt;
  double? _lastNotifiedDownloadProgress;
  AppUpdateDownloadStatus? _downloadStatus;
  int? _downloadId;
  int? _downloadReceivedBytes;
  int? _downloadTotalBytes;
  String? _downloadFailureReason;
  Timer? _downloadPollTimer;
  bool _disposed = false;

  String? get latestVersion => _latestVersion;
  int? get latestVersionCode => _latestVersionCode;
  int? get latestVersionCodeRaw => _latestVersionCodeRaw;
  String? get latestVersionCodeSource => _latestVersionCodeSourceText;
  AppUpdateDownloadStatus? get downloadStatus => _downloadStatus;
  int? get downloadId => _downloadId;
  int? get downloadReceivedBytes => _downloadReceivedBytes;
  int? get downloadTotalBytes => _downloadTotalBytes;
  String? get downloadFailureReason => _downloadFailureReason;

  /// 系统 DownloadManager 任务仍在进行（pending/running/paused）。
  bool get backgroundDownloadActive => _downloadStatus?.isActive ?? false;

  /// 已下载完成但还没安装。
  bool get downloadCompleted => _downloadStatus?.isSuccessful ?? false;

  bool get _backgroundDownloadAvailable =>
      AppUpdateInstaller.supportsBackgroundDownload ||
      debugForceAppUpdateBackgroundDownload;
  String? get latestUrl => _latestUrl;
  String? get latestAssetName => _latestAssetName;
  String? get latestNotes => _latestNotes;
  String? get minimumSupportedVersion => _minimumSupportedVersion;
  int? get minimumSupportedVersionCode => _minimumSupportedVersionCode;
  String? get forceUpdateBlockedReason => _forceUpdateBlockedReason;
  bool get forceUpdateRequired => _forceUpdateRequired;
  String get latestNotesForDisplay {
    final notes = _formatReleaseNotes(_latestNotes);
    if (notes.isNotEmpty) return notes;
    if (_latestVersion != null) return '此版本没有填写更新说明。';
    return '';
  }

  bool get checking => _checking;
  bool get downloading => _downloading;
  bool get installing => _installing;
  bool get busy => _checking || _downloading || _installing;
  double? get downloadProgress => _downloadProgress;
  String? get downloadedFilePath => _downloadedFilePath;
  String? get error => _error;
  bool get hasDownloadedInstaller =>
      _downloadedFilePath != null && _downloadedFilePath!.trim().isNotEmpty;

  bool get hasUpdate {
    return hasNewerAppVersion(
      currentVersion: currentVersion,
      currentVersionCode: currentVersionCode,
      latestVersion: _latestVersion,
      latestVersionCode: _latestVersionCodeTrusted,
    );
  }

  bool get mustUpdate => shouldForceAppUpdate(
    currentVersion: currentVersion,
    latestVersion: _latestVersion,
    minimumSupportedVersion: _minimumSupportedVersion,
    forceUpdateRequired: _forceUpdateRequired,
    currentVersionCode: currentVersionCode,
    latestVersionCode: _latestVersionCodeTrusted,
    minimumSupportedVersionCode: _minimumSupportedVersionCodeTrusted,
  );

  void resetForServerChange() {
    _latestVersion = null;
    _latestVersionCode = null;
    _latestVersionCodeTrusted = null;
    _latestVersionCodeRaw = null;
    _latestVersionCodeSourceText = null;
    _latestUrl = null;
    _latestAssetName = null;
    _latestNotes = null;
    _minimumSupportedVersion = null;
    _minimumSupportedVersionCode = null;
    _minimumSupportedVersionCodeTrusted = null;
    _forceUpdateBlockedReason = null;
    _forceUpdateRequired = false;
    _serverPolicyLoaded = false;
    _error = null;
    notifyListeners();
    _serverPolicyRefreshQueued = true;
    _runQueuedServerPolicyRefresh();
  }

  void _runQueuedServerPolicyRefresh() {
    if (_checking || !_serverPolicyRefreshQueued) return;
    _serverPolicyRefreshQueued = false;
    unawaited(checkServerPolicyNow());
  }

  Future<void> checkNow() async {
    if (_checking) return;
    _checking = true;
    _error = null;
    notifyListeners();
    try {
      await _restoreDownloadedInstaller(allowPopulateUpdateInfo: true);
      await _restoreBackgroundDownload();
      bool? mobileUpdateLoaded;
      try {
        mobileUpdateLoaded = await _checkBackendMobileUpdate();
      } on _BackendUpdateCheckException catch (e) {
        if (!e.allowGitHubFallback) rethrow;
        debugPrint('[AppUpdate] backend compatibility fallback: ${e.message}');
        mobileUpdateLoaded = null;
      }
      bool? configLoaded;
      if (mobileUpdateLoaded == true) {
        configLoaded = true;
      } else {
        try {
          configLoaded = await _checkServerConfig();
        } on _BackendUpdateCheckException catch (e) {
          if (!e.allowGitHubFallback) rethrow;
          debugPrint(
            '[AppUpdate] backend compatibility fallback: ${e.message}',
          );
          configLoaded = null;
        }
      }
      if (configLoaded == false) {
        _latestVersion = null;
        _latestVersionCode = null;
        _latestVersionCodeTrusted = null;
        _latestVersionCodeRaw = null;
        _latestVersionCodeSourceText = null;
        _latestUrl = null;
        _latestAssetName = null;
        _latestNotes = null;
        _minimumSupportedVersion = null;
        _minimumSupportedVersionCode = null;
        _minimumSupportedVersionCodeTrusted = null;
        _forceUpdateBlockedReason = null;
        _forceUpdateRequired = false;
        _serverPolicyLoaded = false;
      }
      if (configLoaded != true) {
        await _mergeGitHubLatestRelease(
          keepServerPolicy: false,
          fillMissingOnly: false,
        );
      } else {
        await _fillMissingDisplayDataFromGitHub();
      }
      if (_serverPolicyLoaded && _latestNotes == null) {
        _latestNotes = _fallbackUpdateNotes(_latestVersion);
      }
      await _restoreDownloadedInstaller(allowPopulateUpdateInfo: false);
    } catch (e) {
      _error = userVisibleApiError(e);
      await _restoreDownloadedInstaller(allowPopulateUpdateInfo: true);
      if (hasDownloadedInstaller) _error = null;
    } finally {
      _checking = false;
      notifyListeners();
      _runQueuedServerPolicyRefresh();
    }
  }

  Future<void> checkServerPolicyNow() async {
    if (_checking) return;
    _checking = true;
    _error = null;
    notifyListeners();
    try {
      await _restoreDownloadedInstaller(allowPopulateUpdateInfo: true);
      await _restoreBackgroundDownload();
      bool? mobileUpdateLoaded;
      try {
        mobileUpdateLoaded = await _checkBackendMobileUpdate();
      } on _BackendUpdateCheckException catch (e) {
        if (!e.allowGitHubFallback) rethrow;
        debugPrint('[AppUpdate] backend compatibility fallback: ${e.message}');
        mobileUpdateLoaded = null;
      }
      final configLoaded = mobileUpdateLoaded == true
          ? true
          : await _checkServerConfigForStartup();
      if (configLoaded == false) {
        _latestVersion = null;
        _latestVersionCode = null;
        _latestVersionCodeTrusted = null;
        _latestVersionCodeRaw = null;
        _latestVersionCodeSourceText = null;
        _latestUrl = null;
        _latestAssetName = null;
        _latestNotes = null;
        _minimumSupportedVersion = null;
        _minimumSupportedVersionCode = null;
        _minimumSupportedVersionCodeTrusted = null;
        _forceUpdateBlockedReason = null;
        _forceUpdateRequired = false;
        _serverPolicyLoaded = false;
      }
      if (configLoaded == true) {
        if ((_latestUrl == null || _latestUrl!.trim().isEmpty) &&
            (mustUpdate || hasUpdate)) {
          await _fillMissingDisplayDataFromGitHub();
        }
        _latestNotes ??= _fallbackUpdateNotes(_latestVersion);
      }
      await _restoreDownloadedInstaller(allowPopulateUpdateInfo: false);
    } catch (e) {
      _error = userVisibleApiError(e);
      await _restoreDownloadedInstaller(allowPopulateUpdateInfo: true);
      if (hasDownloadedInstaller) _error = null;
    } finally {
      _checking = false;
      notifyListeners();
      _runQueuedServerPolicyRefresh();
    }
  }

  Future<bool?> _checkServerConfigForStartup() async {
    try {
      return await _checkServerConfig();
    } on _BackendUpdateCheckException catch (e) {
      if (!e.allowGitHubFallback) rethrow;
      debugPrint(
        '[AppUpdate] startup backend compatibility fallback: ${e.message}',
      );
      return null;
    }
  }

  Future<bool?> _checkServerConfig() async {
    try {
      final base = _serverBaseUrl;
      if (base.isEmpty && !kIsWeb) return null;
      final uri = _backendUri(base, '/api/config');
      final resp = await _httpClient
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(AppConfig.updateTimeout);
      if (base != _serverBaseUrl) return null;
      if (resp.statusCode == 404) return null;
      if (resp.statusCode != 200) {
        throw _BackendUpdateCheckException(
          '检查更新失败：/api/config 返回 ${resp.statusCode}',
        );
      }
      final decoded = json.decode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map) {
        throw const _BackendUpdateCheckException('检查更新失败：/api/config 返回结构错误');
      }
      final rawConfig = Map<String, dynamic>.from(decoded);
      final contractDiagnosis = _backendContractDiagnosisText(rawConfig);
      if (contractDiagnosis != null) {
        throw _BackendUpdateCheckException(
          '检查更新失败：当前后端未部署本版本更新接口：/api/mobile/apps/duoyi/update。$contractDiagnosis',
          allowGitHubFallback: true,
        );
      }
      final data = decoded['app_update'] is Map
          ? Map<String, dynamic>.from(decoded['app_update'] as Map)
          : rawConfig;
      final rawLatest = _stringValue(data['latest_version']);
      final latest = _versionAtLeastCurrent(rawLatest);
      final latestCodeRaw = _intValue(data['latest_version_code']);
      final latestCode = _versionCodeAtLeastCurrent(rawLatest, latestCodeRaw);
      final latestCodeTrusted = _trustedIncomingVersionCode(
        versionName: rawLatest,
        versionCode: latestCodeRaw,
        codeSource: _stringValue(data['latest_version_code_source']),
      );
      final rawDownloadUrl = _resolveBackendUrl(
        base,
        _stringValue(data['update_download_url']),
      );
      final notes = _stringValue(data['update_notes']);
      final rawMinimum = _stringValue(data['minimum_supported_version']);
      final minimum = _versionAtLeastCurrent(rawMinimum);
      final minimumCodeRaw = _intValue(data['minimum_supported_version_code']);
      final minimumCode = _versionCodeAtLeastCurrent(
        rawMinimum,
        minimumCodeRaw,
      );
      final minimumCodeTrusted = _trustedIncomingVersionCode(
        versionName: rawMinimum,
        versionCode: minimumCodeRaw,
        codeSource: _stringValue(data['minimum_supported_version_code_source']),
      );
      final downloadUrl = _sanitizeDownloadUrlForVersion(
        rawDownloadUrl,
        latest.isEmpty ? minimum : latest,
      );
      final hasNewerLatest = hasNewerAppVersion(
        currentVersion: currentVersion,
        currentVersionCode: currentVersionCode,
        latestVersion: rawLatest,
        latestVersionCode: latestCodeTrusted,
      );
      final hasRaisedMinimum = hasNewerAppVersion(
        currentVersion: currentVersion,
        currentVersionCode: currentVersionCode,
        latestVersion: rawMinimum,
        latestVersionCode: minimumCodeTrusted,
      );
      final policyEnabled =
          data['force_update_required'] == true ||
          data['force_app_update_enabled'] == true;
      final hasPolicy =
          downloadUrl.isNotEmpty ||
          notes.isNotEmpty ||
          hasNewerLatest ||
          hasRaisedMinimum ||
          policyEnabled;
      if (!hasPolicy) return false;
      _latestVersion = latest.isEmpty ? null : latest;
      _latestVersionCode = latestCode;
      _latestVersionCodeRaw = latestCodeRaw;
      _latestVersionCodeSourceText = _stringValue(
        data['latest_version_code_source'],
      );
      _latestVersionCodeTrusted = latestCodeTrusted;
      _latestUrl = downloadUrl.isEmpty ? null : downloadUrl;
      _latestAssetName = _assetNameFromUrl(downloadUrl);
      _latestNotes = notes.isEmpty ? null : notes;
      _minimumSupportedVersion = minimum.isEmpty ? null : minimum;
      _minimumSupportedVersionCode = minimumCode;
      _minimumSupportedVersionCodeTrusted = minimumCodeTrusted;
      _forceUpdateBlockedReason = null;
      _forceUpdateRequired = policyEnabled;
      _serverPolicyLoaded = true;
      return true;
    } on _BackendUpdateCheckException {
      rethrow;
    } catch (e) {
      throw _BackendUpdateCheckException('检查更新失败：读取 /api/config 失败：$e');
    }
  }

  Future<bool?> _checkBackendMobileUpdate() async {
    try {
      final base = _serverBaseUrl;
      if (base.isEmpty && !kIsWeb) return null;
      final effectiveCurrentVersionCode =
          currentVersionCode ?? _versionToCode(currentVersion);
      final uri = _backendUri(
        base,
        '/api/mobile/apps/duoyi/update',
        queryParameters: {
          'current_version': currentVersion,
          'current_version_code': effectiveCurrentVersionCode.toString(),
        },
      );
      final resp = await _httpClient
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(AppConfig.updateTimeout);
      if (base != _serverBaseUrl) return null;
      if (resp.statusCode == 404) return null;
      if (resp.statusCode != 200) {
        throw _BackendUpdateCheckException(
          '检查更新失败：移动端更新接口返回 ${resp.statusCode}',
        );
      }
      final decoded = json.decode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map) {
        throw const _BackendUpdateCheckException('检查更新失败：移动端更新接口返回结构错误');
      }
      final data = Map<String, dynamic>.from(decoded);
      final contractDiagnosis = _backendContractDiagnosisText(data);
      if (contractDiagnosis != null) {
        throw _BackendUpdateCheckException(
          '检查更新失败：当前后端未部署本版本更新接口：/api/mobile/apps/duoyi/update。$contractDiagnosis',
          allowGitHubFallback: true,
        );
      }
      final rawLatest = _stringValue(data['latest_version_name']);
      final latest = _versionAtLeastCurrent(rawLatest);
      final latestCodeRaw = _intValue(data['latest_version_code']);
      final latestCode = _versionCodeAtLeastCurrent(rawLatest, latestCodeRaw);
      final latestCodeTrusted = _trustedIncomingVersionCode(
        versionName: rawLatest,
        versionCode: latestCodeRaw,
        codeSource: _stringValue(data['latest_version_code_source']),
      );
      final rawDownloadUrl = _resolveBackendUrl(
        base,
        _stringValue(data['download_url']),
      );
      final notes = _stringValue(data['release_notes']);
      final rawMinimum = _stringValue(data['minimum_supported_version']);
      final minimum = _versionAtLeastCurrent(rawMinimum);
      final minimumCodeRaw = _intValue(data['minimum_supported_version_code']);
      final minimumCode = _versionCodeAtLeastCurrent(
        rawMinimum,
        minimumCodeRaw,
      );
      final minimumCodeTrusted = _trustedIncomingVersionCode(
        versionName: rawMinimum,
        versionCode: minimumCodeRaw,
        codeSource: _stringValue(data['minimum_supported_version_code_source']),
      );
      final downloadUrl = _sanitizeDownloadUrlForVersion(
        rawDownloadUrl,
        latest.isEmpty ? minimum : latest,
      );
      final blockedReason = _stringValue(data['force_update_blocked_reason']);
      // 版本名语义优先：远端 name 更旧时不因 code 更大而提示更新；
      // name 相同只有可信的真实 build 更高才算更新。
      final available = hasNewerAppVersion(
        currentVersion: currentVersion,
        currentVersionCode: currentVersionCode,
        latestVersion: rawLatest,
        latestVersionCode: latestCodeTrusted,
      );
      final belowMinimum = hasNewerAppVersion(
        currentVersion: currentVersion,
        currentVersionCode: currentVersionCode,
        latestVersion: rawMinimum,
        latestVersionCode: minimumCodeTrusted,
      );
      final policyEnabled =
          data['force_update_required'] == true ||
          data['force_app_update_enabled'] == true;
      final forceUpdate =
          data['force_update'] == true ||
          (policyEnabled && (available || belowMinimum));
      if (!available && !forceUpdate && notes.isEmpty && downloadUrl.isEmpty) {
        return false;
      }
      _latestVersion = latest.isEmpty ? null : latest;
      _latestVersionCode = latestCode;
      _latestVersionCodeRaw = latestCodeRaw;
      _latestVersionCodeSourceText = _stringValue(
        data['latest_version_code_source'],
      );
      _latestVersionCodeTrusted = latestCodeTrusted;
      _latestUrl = downloadUrl.isEmpty ? null : downloadUrl;
      _latestAssetName = _assetNameFromUrl(downloadUrl);
      _latestNotes = notes.isEmpty ? null : notes;
      _minimumSupportedVersion = minimum.isEmpty ? null : minimum;
      _minimumSupportedVersionCode = minimumCode;
      _minimumSupportedVersionCodeTrusted = minimumCodeTrusted;
      _forceUpdateBlockedReason = blockedReason.isEmpty ? null : blockedReason;
      _forceUpdateRequired = forceUpdate;
      _serverPolicyLoaded = true;
      return true;
    } on _BackendUpdateCheckException {
      rethrow;
    } catch (e) {
      throw _BackendUpdateCheckException('检查更新失败：读取移动端更新接口失败：$e');
    }
  }

  String get _serverBaseUrl =>
      backendBaseUrlGetter?.call() ??
      backendBaseUrl ??
      ServerConnection.defaultBaseUrl();

  String _stringValue(dynamic value) => (value ?? '').toString().trim();

  String _versionAtLeastCurrent(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return '';
    return compareAppVersions(currentVersion, normalized) > 0
        ? currentVersion
        : normalized;
  }

  int? _versionCodeAtLeastCurrent(String version, int? code) {
    if (code == null) return null;
    final normalized = version.trim();
    if (normalized.isEmpty) return code;
    if (compareAppVersions(currentVersion, normalized) <= 0) return code;
    final currentCode = currentVersionCode ?? _versionToCode(currentVersion);
    return code < currentCode ? currentCode : code;
  }

  int? _trustedIncomingVersionCode({
    required String versionName,
    int? versionCode,
    String? codeSource,
  }) {
    if (versionName.trim().isNotEmpty &&
        compareAppVersions(versionName, currentVersion) < 0) {
      return null;
    }
    return resolveTrustedVersionCode(
      versionName: versionName,
      versionCode: versionCode,
      codeSource: codeSource,
    );
  }

  int? _intValue(dynamic value) {
    if (value is int) return value;
    return int.tryParse(_stringValue(value));
  }

  String _resolveBackendUrl(String base, String value) {
    final raw = value.trim();
    if (raw.isEmpty) return '';
    final parsed = Uri.tryParse(raw);
    if (parsed != null && parsed.hasScheme) return raw;
    if (raw.startsWith('//')) return 'https:$raw';
    final baseUri = _backendUri(base, '/');
    return baseUri.resolve(raw).toString();
  }

  String _sanitizeDownloadUrlForVersion(String url, String targetVersion) {
    if (_downloadUrlLooksStaleForVersion(url, targetVersion)) return '';
    return url;
  }

  bool _downloadUrlLooksStaleForVersion(String url, String targetVersion) {
    final clean = Uri.decodeFull(url.trim()).toLowerCase();
    final target = _normalizeVersionToken(targetVersion);
    if (clean.isEmpty || target.isEmpty) return false;
    if (clean.contains(target)) return false;

    final matches = RegExp(
      r'(?:^|[^0-9])v?([0-9]+\.[0-9]+\.[0-9]+)(?:[^0-9]|$)',
    ).allMatches(clean);
    for (final match in matches) {
      final found = _normalizeVersionToken(match.group(1) ?? '');
      if (found.isEmpty) continue;
      if (compareAppVersions(found, target) < 0) return true;
    }
    return false;
  }

  String _normalizeVersionToken(String value) => value
      .trim()
      .toLowerCase()
      .replaceFirst(RegExp(r'^v'), '')
      .split('-')
      .first
      .split('+')
      .first;

  Uri _backendUri(
    String base,
    String path, {
    Map<String, String>? queryParameters,
  }) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    if (base.trim().isEmpty) {
      return Uri.parse(cleanPath).replace(queryParameters: queryParameters);
    }
    var cleanBase = base.trim().replaceFirst(RegExp(r'/+$'), '');
    if (_hasBackendApiPrefix(cleanPath) &&
        cleanBase.endsWith(String.fromCharCodes(const [47, 97, 112, 105]))) {
      cleanBase = cleanBase.substring(0, cleanBase.length - 4);
    }
    return Uri.parse(
      '$cleanBase$cleanPath',
    ).replace(queryParameters: queryParameters);
  }

  bool _hasBackendApiPrefix(String value) {
    if (value.length < 4) return false;
    return value.codeUnitAt(0) == 47 &&
        value.codeUnitAt(1) == 97 &&
        value.codeUnitAt(2) == 112 &&
        value.codeUnitAt(3) == 105 &&
        (value.length == 4 || value.codeUnitAt(4) == 47);
  }

  String? _backendContractDiagnosisText(Map<String, dynamic> decoded) {
    final contractVersion = _stringValue(decoded['api_contract_version']);
    final routesHash = _stringValue(decoded['required_routes_hash']);
    final missingContract = contractVersion.isEmpty;
    final outdatedContract =
        contractVersion.isNotEmpty &&
        _compareApiContractVersions(
              contractVersion,
              ApiClient.requiredApiContractVersion,
            ) <
            0;
    final missingRoutesHash = routesHash.isEmpty;
    final mismatchedRoutesHash =
        routesHash.isNotEmpty &&
        routesHash != ApiClient.requiredApiContractRoutesHash;
    if (!missingContract &&
        !outdatedContract &&
        !missingRoutesHash &&
        !mismatchedRoutesHash) {
      return null;
    }

    final serverVersion = _stringValue(decoded['version']);
    final features = decoded['features'];
    final featureSummary = features is Map
        ? features.entries
              .where((entry) => entry.value == true)
              .map((entry) => entry.key.toString())
              .join(', ')
        : '';
    final parts = <String>[
      if (serverVersion.isNotEmpty) '后端版本 $serverVersion。',
      if (missingContract)
        '缺少接口契约 api_contract_version。'
      else if (outdatedContract)
        '接口契约 $contractVersion 低于客户端要求 ${ApiClient.requiredApiContractVersion}。',
      if (missingRoutesHash)
        '缺少必备路由摘要 required_routes_hash。'
      else if (mismatchedRoutesHash)
        '必备路由摘要 $routesHash 与客户端要求 ${ApiClient.requiredApiContractRoutesHash} 不一致。',
      '请部署当前 backend/main.py 后再重试。',
      if (featureSummary.isNotEmpty) '已声明能力：$featureSummary。',
    ];
    return parts.join('');
  }

  int _compareApiContractVersions(String left, String right) {
    final a = _apiContractVersionParts(left);
    final b = _apiContractVersionParts(right);
    for (var i = 0; i < a.length; i++) {
      final diff = a[i].compareTo(b[i]);
      if (diff != 0) return diff;
    }
    return 0;
  }

  List<int> _apiContractVersionParts(String value) {
    final match = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:\.(\d+))?$',
    ).firstMatch(value.trim());
    if (match != null) {
      return [
        int.tryParse(match.group(1) ?? '') ?? 0,
        int.tryParse(match.group(2) ?? '') ?? 0,
        int.tryParse(match.group(3) ?? '') ?? 0,
        int.tryParse(match.group(4) ?? '') ?? 0,
      ];
    }
    final parts = value
        .trim()
        .split(RegExp(r'[^0-9]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    return [for (var i = 0; i < 4; i++) i < parts.length ? parts[i] : 0];
  }

  int _versionToCode(String value) {
    final parts = value
        .trim()
        .replaceFirst(RegExp(r'^v'), '')
        .split('-')
        .first
        .split('+')
        .first
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
    final major = parts.isNotEmpty ? parts[0] : 0;
    final minor = parts.length > 1 ? parts[1] : 0;
    final patch = parts.length > 2 ? parts[2] : 0;
    return major * 100000 + minor * 10000 + patch;
  }

  String? _assetNameFromUrl(String url) {
    if (url.trim().isEmpty) return null;
    final parsed = Uri.tryParse(url);
    final segment = parsed == null || parsed.pathSegments.isEmpty
        ? ''
        : parsed.pathSegments.last.trim();
    return segment.isEmpty ? null : Uri.decodeComponent(segment);
  }

  Future<void> _mergeGitHubLatestRelease({
    required bool keepServerPolicy,
    required bool fillMissingOnly,
  }) async {
    if (repo.trim().isEmpty) return;
    final uri = Uri.parse('https://api.github.com/repos/$repo/releases/latest');
    final resp = await _httpClient
        .get(
          uri,
          headers: {
            'User-Agent': 'duoyi/1.0',
            'Accept': 'application/vnd.github+json',
          },
        )
        .timeout(AppConfig.updateTimeout);
    if (resp.statusCode == 404) {
      if (!keepServerPolicy) {
        _latestVersion = null;
        _error = '尚未发布 Release';
      }
      return;
    }
    if (resp.statusCode != 200) {
      if (!keepServerPolicy) {
        _error = '检查更新失败: ${resp.statusCode}';
      }
      return;
    }
    final data = json.decode(utf8.decode(resp.bodyBytes));
    final releaseVersion = (data['tag_name'] as String?)?.trim();
    final releaseNotes = (data['body'] as String?)?.trim();
    final assets = data['assets'];
    Map? asset;
    if (assets is List) {
      asset = _selectBestApkAsset(assets, targetVersion: releaseVersion);
    }
    if (!fillMissingOnly) {
      _latestVersion = releaseVersion;
      // GitHub tag 里没有真实 Android build 元数据，禁止从 tag 合成 versionCode。
      _latestVersionCode = null;
      _latestVersionCodeRaw = null;
      _latestVersionCodeTrusted = null;
      _latestVersionCodeSourceText = null;
      _latestNotes = releaseNotes;
      _latestUrl = asset?['browser_download_url'] as String?;
      _latestAssetName = asset?['name'] as String?;
      return;
    }
    final releaseIsNewerThanCurrent =
        releaseVersion != null &&
        releaseVersion.isNotEmpty &&
        compareAppVersions(releaseVersion, currentVersion) > 0;
    final releaseIsNewerThanLoaded =
        releaseVersion != null &&
        releaseVersion.isNotEmpty &&
        (_latestVersion == null ||
            _latestVersion!.trim().isEmpty ||
            compareAppVersions(releaseVersion, _latestVersion!) > 0);
    if (releaseIsNewerThanCurrent && releaseIsNewerThanLoaded) {
      _latestVersion = releaseVersion;
      _latestVersionCode = null;
      _latestVersionCodeRaw = null;
      _latestVersionCodeTrusted = null;
      _latestVersionCodeSourceText = null;
      if (releaseNotes != null && releaseNotes.isNotEmpty) {
        _latestNotes = releaseNotes;
      }
      if (asset != null) {
        _latestUrl = asset['browser_download_url'] as String?;
        _latestAssetName = asset['name'] as String?;
      }
      return;
    }
    if ((_latestVersion == null || _latestVersion!.trim().isEmpty) &&
        releaseVersion != null &&
        releaseVersion.isNotEmpty) {
      _latestVersion = releaseVersion;
    }
    if ((_latestNotes == null || _latestNotes!.trim().isEmpty) &&
        releaseNotes != null &&
        releaseNotes.isNotEmpty) {
      _latestNotes = releaseNotes;
    }
    if ((_latestUrl == null || _latestUrl!.trim().isEmpty) && asset != null) {
      _latestUrl = asset['browser_download_url'] as String?;
      _latestAssetName = asset['name'] as String?;
    }
  }

  Future<void> _fillMissingDisplayDataFromGitHub() async {
    if (!_serverPolicyLoaded) return;
    final versionMissing =
        _latestVersion == null || _latestVersion!.trim().isEmpty;
    final notesMissing = _latestNotes == null || _latestNotes!.trim().isEmpty;
    final urlMissing = _latestUrl == null || _latestUrl!.trim().isEmpty;
    if (!versionMissing && !notesMissing && !urlMissing) {
      return;
    }
    await _mergeGitHubLatestRelease(
      keepServerPolicy: true,
      fillMissingOnly: true,
    );
  }

  @visibleForTesting
  String debugFormatReleaseNotesForTest(String? notes) =>
      _formatReleaseNotes(notes);

  @visibleForTesting
  void debugSetUpdatePolicyForTest({
    String? latestVersion,
    int? latestVersionCode,
    String? minimumSupportedVersion,
    int? minimumSupportedVersionCode,
    bool forceUpdateRequired = false,
    String? latestUrl,
  }) {
    _latestVersion = latestVersion;
    _latestVersionCode = latestVersionCode;
    _latestVersionCodeRaw = latestVersionCode;
    _latestVersionCodeSourceText = null;
    _latestVersionCodeTrusted = resolveTrustedVersionCode(
      versionName: latestVersion ?? '',
      versionCode: latestVersionCode,
      codeSource: null,
    );
    _minimumSupportedVersion = minimumSupportedVersion;
    _minimumSupportedVersionCode = minimumSupportedVersionCode;
    _minimumSupportedVersionCodeTrusted = resolveTrustedVersionCode(
      versionName: minimumSupportedVersion ?? '',
      versionCode: minimumSupportedVersionCode,
      codeSource: null,
    );
    _forceUpdateRequired = forceUpdateRequired;
    _latestUrl = latestUrl;
    _latestAssetName = _assetNameFromUrl(latestUrl ?? '');
  }

  @visibleForTesting
  bool debugWouldServerPolicyForceForTest({
    required Map<String, dynamic> data,
  }) {
    final latest = _stringValue(data['latest_version']);
    final minimum = _stringValue(data['minimum_supported_version']);
    final force = data['force_update_required'] == true;
    return shouldForceAppUpdate(
      currentVersion: currentVersion,
      latestVersion: latest.isEmpty ? null : latest,
      minimumSupportedVersion: minimum.isEmpty ? null : minimum,
      forceUpdateRequired: force,
    );
  }

  Future<void> _restoreDownloadedInstaller({
    required bool allowPopulateUpdateInfo,
  }) async {
    final prefs = await _downloadedInstallerPrefs();
    if (prefs == null) {
      _downloadedFilePath = null;
      return;
    }
    final path = (prefs.getString(_downloadedPathKey) ?? '').trim();
    if (path.isEmpty) {
      _downloadedFilePath = null;
      return;
    }
    final exists = await AppUpdateInstaller.downloadedFileExists(path);
    if (!exists) {
      await _clearDownloadedInstaller(prefs);
      return;
    }

    final cachedVersion = (prefs.getString(_downloadedVersionKey) ?? '').trim();
    final cachedVersionCode = prefs.getInt(_downloadedVersionCodeKey);
    final cachedVersionCodeSource = prefs.getString(
      _downloadedVersionCodeSourceKey,
    );
    final cachedTrustedCode = resolveTrustedVersionCode(
      versionName: cachedVersion,
      versionCode: cachedVersionCode,
      codeSource: cachedVersionCodeSource,
    );
    final cachedUrl = (prefs.getString(_downloadedUrlKey) ?? '').trim();
    if (_downloadUrlLooksStaleForVersion(cachedUrl, cachedVersion)) {
      await _clearDownloadedInstaller(prefs);
      return;
    }
    // 旧缓存里由 versionName 合成的假 build 不能让已最新版误报。
    if (!_isNewerThanCurrent(cachedVersion, cachedTrustedCode)) {
      await _clearDownloadedInstaller(prefs);
      return;
    }
    if (!_cachedInstallerMatchesLoadedUpdate(
      version: cachedVersion,
      versionCode: cachedTrustedCode,
      url: cachedUrl,
      allowPopulateUpdateInfo: allowPopulateUpdateInfo,
    )) {
      _downloadedFilePath = null;
      return;
    }

    _downloadedFilePath = path;
    if (allowPopulateUpdateInfo) {
      _latestVersion ??= cachedVersion.isEmpty ? null : cachedVersion;
      _latestVersionCode ??= cachedVersionCode;
      _latestVersionCodeTrusted ??= cachedTrustedCode;
      if ((_latestUrl == null || _latestUrl!.trim().isEmpty) &&
          cachedUrl.isNotEmpty) {
        _latestUrl = cachedUrl;
      }
      final cachedAssetName = (prefs.getString(_downloadedAssetNameKey) ?? '')
          .trim();
      _latestVersionCodeSourceText ??= cachedVersionCodeSource;
      if ((_latestAssetName == null || _latestAssetName!.trim().isEmpty) &&
          cachedAssetName.isNotEmpty) {
        _latestAssetName = cachedAssetName;
      }
      _latestNotes ??= _fallbackUpdateNotes(_latestVersion);
    }
  }

  bool _cachedInstallerMatchesLoadedUpdate({
    required String version,
    required int? versionCode,
    required String url,
    required bool allowPopulateUpdateInfo,
  }) {
    final loadedHasUpdate = _isNewerThanCurrent(
      _latestVersion,
      _latestVersionCodeTrusted,
    );
    if (!loadedHasUpdate) return allowPopulateUpdateInfo;

    final loadedVersion = _latestVersion?.trim();
    if (loadedVersion != null &&
        loadedVersion.isNotEmpty &&
        version.isNotEmpty &&
        compareAppVersions(loadedVersion, version) != 0) {
      return false;
    }
    if (_latestVersionCodeTrusted != null &&
        versionCode != null &&
        _latestVersionCodeTrusted != versionCode) {
      return false;
    }
    final loadedUrl = _latestUrl?.trim();
    if (loadedUrl != null &&
        loadedUrl.isNotEmpty &&
        url.isNotEmpty &&
        loadedUrl != url) {
      return false;
    }
    return true;
  }

  bool _isNewerThanCurrent(String? version, int? versionCode) =>
      hasNewerAppVersion(
        currentVersion: currentVersion,
        currentVersionCode: currentVersionCode,
        latestVersion: version,
        latestVersionCode: versionCode,
      );

  Future<void> _rememberDownloadedInstaller(String path) async {
    final prefs = await _downloadedInstallerPrefs();
    if (prefs == null) return;
    await prefs.setString(_downloadedPathKey, path);
    final version = _latestVersion?.trim();
    if (version != null && version.isNotEmpty) {
      await prefs.setString(_downloadedVersionKey, version);
    }
    final versionCode = _latestVersionCodeTrusted;
    if (versionCode != null) {
      await prefs.setInt(_downloadedVersionCodeKey, versionCode);
    }
    final versionCodeSource = _latestVersionCodeSourceText;
    if (versionCodeSource != null && versionCodeSource.isNotEmpty) {
      await prefs.setString(_downloadedVersionCodeSourceKey, versionCodeSource);
    }
    final url = _latestUrl?.trim();
    if (url != null && url.isNotEmpty) {
      await prefs.setString(_downloadedUrlKey, url);
    }
    final assetName = _latestAssetName?.trim();
    if (assetName != null && assetName.isNotEmpty) {
      await prefs.setString(_downloadedAssetNameKey, assetName);
    }
  }

  Future<void> _clearDownloadedInstaller([SharedPreferences? prefs]) async {
    _downloadedFilePath = null;
    final storage = prefs ?? await _downloadedInstallerPrefs();
    if (storage == null) return;
    await storage.remove(_downloadedPathKey);
    await storage.remove(_downloadedVersionKey);
    await storage.remove(_downloadedVersionCodeKey);
    await storage.remove(_downloadedVersionCodeSourceKey);
    await storage.remove(_downloadedUrlKey);
    await storage.remove(_downloadedAssetNameKey);
  }

  Future<SharedPreferences?> _downloadedInstallerPrefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _tryInstallDownloadedInstaller() async {
    await _restoreDownloadedInstaller(allowPopulateUpdateInfo: true);
    final path = _downloadedFilePath;
    if (path == null || path.trim().isEmpty) return false;
    final canInstall = await AppUpdateInstaller.canInstallPackages();
    if (!canInstall) {
      _error = '需要允许多仪安装未知应用；授权后返回这里再次点击安装';
      notifyListeners();
      await AppUpdateInstaller.openInstallPermissionSettings();
      return true;
    }
    _error = null;
    _installing = true;
    notifyListeners();
    try {
      await AppUpdateInstaller.installApk(path);
    } finally {
      _installing = false;
      notifyListeners();
    }
    return true;
  }

  /// 下载并安装最新版本。
  ///
  /// Android 交给系统 DownloadManager 在后台下载，本方法启动任务后立即返回；
  /// 进度/结果通过 [downloadStatus]、[downloadProgress] 暴露，UI 可关闭弹窗，
  /// 下载不会因此中断。桌面/Web 仍沿用页内 http 流。
  Future<void> downloadAndInstallLatest({
    int? accentColor,
    String? appName,
    String? notificationTitle,
    String? notificationText,
    String? installActionLabel,
    String? channelName,
    String? channelDescription,
  }) async {
    if (!AppUpdateInstaller.supportsInstall && !_backgroundDownloadAvailable) {
      _error = '当前平台不支持应用内 APK 更新';
      _safeNotify();
      return;
    }
    if (await _tryInstallDownloadedInstaller()) return;
    if (_latestUrl == null) {
      _error = '没有可下载的 APK';
      _safeNotify();
      return;
    }
    if (_backgroundDownloadAvailable) {
      await startBackgroundDownload(
        accentColor: accentColor,
        appName: appName,
        notificationTitle: notificationTitle,
        notificationText: notificationText,
        installActionLabel: installActionLabel,
        channelName: channelName,
        channelDescription: channelDescription,
      );
      return;
    }

    _error = null;
    _downloading = true;
    _installing = false;
    _downloadProgress = 0;
    _lastDownloadProgressNotifyAt = null;
    _lastNotifiedDownloadProgress = null;
    notifyListeners();

    try {
      final path = await AppUpdateInstaller.downloadApk(
        url: _latestUrl!,
        fileName: _latestAssetName ?? 'duoyi-${latestVersion ?? 'latest'}.apk',
        onProgress: (received, total) {
          if (total != null && total > 0) {
            _downloadProgress = (received / total).clamp(0, 1).toDouble();
            if (_shouldNotifyDownloadProgress(_downloadProgress!)) {
              notifyListeners();
            }
          }
        },
      );
      _downloadedFilePath = path;
      await _rememberDownloadedInstaller(path);
      _downloading = false;
      _installing = true;
      _downloadProgress = 1;
      notifyListeners();

      final canInstall = await AppUpdateInstaller.canInstallPackages();
      if (!canInstall) {
        _installing = false;
        _error = '需要允许多仪安装未知应用；授权后返回这里再次点击安装';
        notifyListeners();
        await AppUpdateInstaller.openInstallPermissionSettings();
        return;
      }

      await AppUpdateInstaller.installApk(path);
    } catch (e) {
      _error = '更新失败: $e';
    } finally {
      _downloading = false;
      _installing = false;
      notifyListeners();
    }
  }

  /// 启动系统后台下载；同一任务不会重复创建。
  ///
  /// [accentColor]、[notificationTitle] 等外观参数由调用方传入
  /// 当前主题主色与品牌文案（原生侧不能读 I18n）。
  Future<void> startBackgroundDownload({
    int? accentColor,
    String? appName,
    String? notificationTitle,
    String? notificationText,
    String? installActionLabel,
    String? channelName,
    String? channelDescription,
  }) async {
    if (!_backgroundDownloadAvailable) {
      _error = '当前平台不支持系统后台下载';
      _safeNotify();
      return;
    }
    if (_downloading || backgroundDownloadActive) return;
    final url = _latestUrl?.trim() ?? '';
    if (url.isEmpty) {
      _error = '没有可下载的 APK';
      _safeNotify();
      return;
    }
    final versionName = _latestVersion?.trim() ?? '';
    final brand = appName?.trim().isNotEmpty == true ? appName!.trim() : '多仪';
    _error = null;
    _downloading = true;
    _downloadStatus = AppUpdateDownloadStatus.pending;
    _downloadFailureReason = null;
    _downloadProgress = null;
    _downloadReceivedBytes = 0;
    _downloadTotalBytes = null;
    _safeNotify();
    try {
      final snapshot = await AppUpdateInstaller.startBackgroundDownload(
        url: url,
        fileName: _latestAssetName ?? 'duoyi-$versionName.apk',
        versionName: versionName,
        versionCode: _latestVersionCode,
        accentColor: accentColor ?? defaultAppUpdateAccentColor,
        notificationTitle: notificationTitle ?? brand,
        notificationText: notificationText ?? '正在下载更新包 $versionName'.trim(),
        installActionLabel: installActionLabel ?? '点击安装',
        channelName: channelName ?? '应用更新',
        channelDescription: channelDescription ?? '应用更新包后台下载与安装提醒',
      );
      if (snapshot == null) {
        _downloading = false;
        _downloadStatus = null;
        _error = '无法启动后台下载';
        _safeNotify();
        return;
      }
      await _applyDownloadSnapshot(snapshot);
      if (snapshot.status.isActive) _startDownloadPolling();
    } catch (e) {
      _downloading = false;
      _downloadStatus = AppUpdateDownloadStatus.failed;
      _downloadFailureReason = '$e';
      _error = '更新失败: $e';
      _safeNotify();
    }
  }

  /// 取消当前下载任务（只删除本应用持有的那一个）。
  Future<void> cancelDownload() async {
    _downloadPollTimer?.cancel();
    _downloadPollTimer = null;
    try {
      await AppUpdateInstaller.cancelBackgroundDownload();
    } catch (_) {
      // 取消失败不阻塞 UI；下一次查询会纠正真实状态。
    }
    _downloading = false;
    _downloadStatus = null;
    _downloadId = null;
    _downloadProgress = null;
    _downloadReceivedBytes = null;
    _downloadTotalBytes = null;
    _downloadFailureReason = null;
    _safeNotify();
  }

  /// 安装已下载的安装包（不会自动触发，必须由用户操作）。
  Future<void> installDownloadedInstaller() async {
    await _tryInstallDownloadedInstaller();
  }

  /// 重新读取原生下载任务状态（应用回到前台/服务重建时调用）。
  Future<void> refreshDownloadState() async {
    await _restoreBackgroundDownload();
  }

  Future<void> _restoreBackgroundDownload() async {
    if (!_backgroundDownloadAvailable) return;
    AppUpdateDownloadSnapshot? snapshot;
    try {
      snapshot = await AppUpdateInstaller.queryBackgroundDownload();
    } catch (_) {
      return;
    }
    if (snapshot == null) {
      _downloadPollTimer?.cancel();
      _downloadPollTimer = null;
      _downloadStatus = null;
      _downloadId = null;
      _downloadReceivedBytes = null;
      _downloadTotalBytes = null;
      if (!hasDownloadedInstaller) {
        _downloading = false;
        _downloadProgress = null;
      }
      return;
    }
    await _applyDownloadSnapshot(snapshot);
    if (snapshot.status.isActive) {
      _startDownloadPolling();
    }
  }

  Future<void> _applyDownloadSnapshot(
    AppUpdateDownloadSnapshot snapshot,
  ) async {
    _downloadId = snapshot.downloadId;
    _downloadStatus = snapshot.status;
    _downloadReceivedBytes = snapshot.receivedBytes;
    _downloadTotalBytes = snapshot.totalBytes;
    _latestVersion ??= snapshot.versionName;
    if ((_latestUrl == null || _latestUrl!.trim().isEmpty) &&
        (snapshot.url?.trim().isNotEmpty ?? false)) {
      _latestUrl = snapshot.url!.trim();
    }
    if ((_latestAssetName == null || _latestAssetName!.trim().isEmpty) &&
        (snapshot.fileName?.trim().isNotEmpty ?? false)) {
      _latestAssetName = snapshot.fileName!.trim();
    }
    if (snapshot.status.isSuccessful) {
      _downloadPollTimer?.cancel();
      _downloadPollTimer = null;
      _downloading = false;
      final path = snapshot.trimmedLocalPath;
      final exists =
          path != null && await AppUpdateInstaller.downloadedFileExists(path);
      if (path != null && exists) {
        _downloadedFilePath = path;
        _downloadProgress = 1;
        _downloadFailureReason = null;
        _error = null;
        await _rememberDownloadedInstaller(path);
      } else {
        _downloadStatus = AppUpdateDownloadStatus.failed;
        _downloadFailureReason = 'missing_file';
        _downloadProgress = null;
        _error = '更新包下载完成但文件缺失，请重试';
      }
    } else if (snapshot.status.isFailed) {
      _downloadPollTimer?.cancel();
      _downloadPollTimer = null;
      _downloading = false;
      _downloadProgress = null;
      _downloadFailureReason = snapshot.reason ?? 'failed';
      _error = '更新下载失败，请重试';
    } else {
      _downloading = true;
      _downloadProgress = snapshot.progress;
      _downloadFailureReason = null;
      _error = null;
    }
    _safeNotify();
  }

  void _startDownloadPolling() {
    _downloadPollTimer?.cancel();
    _downloadPollTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      unawaited(_pollBackgroundDownload(timer));
    });
  }

  @visibleForTesting
  Future<void> debugPollDownloadForTest() => _pollBackgroundDownload();

  Future<void> _pollBackgroundDownload([Timer? timer]) async {
    if (_disposed) {
      timer?.cancel();
      return;
    }
    AppUpdateDownloadSnapshot? snapshot;
    try {
      snapshot = await AppUpdateInstaller.queryBackgroundDownload();
    } catch (_) {
      return;
    }
    if (_disposed) return;
    if (snapshot == null) {
      timer?.cancel();
      _downloadStatus = null;
      _downloadId = null;
      _downloading = false;
      _downloadProgress = null;
      _safeNotify();
      return;
    }
    await _applyDownloadSnapshot(snapshot);
    if (!snapshot.status.isActive) timer?.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    _downloadPollTimer?.cancel();
    _downloadPollTimer = null;
    super.dispose();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  bool _shouldNotifyDownloadProgress(double progress) {
    final now = DateTime.now();
    final lastProgress = _lastNotifiedDownloadProgress;
    final lastAt = _lastDownloadProgressNotifyAt;
    if (lastProgress == null ||
        progress >= 1 ||
        progress - lastProgress >= 0.01 ||
        lastAt == null ||
        now.difference(lastAt) >= const Duration(milliseconds: 160)) {
      _lastNotifiedDownloadProgress = progress;
      _lastDownloadProgressNotifyAt = now;
      return true;
    }
    return false;
  }

  Map? _selectBestApkAsset(List assets, {String? targetVersion}) {
    final apkAssets =
        assets.whereType<Map>().where((a) {
          final name = ((a['name'] as String?) ?? '').toLowerCase();
          return name.endsWith('.apk');
        }).toList()..sort(
          (a, b) => _apkScore(
            b,
            targetVersion: targetVersion,
          ).compareTo(_apkScore(a, targetVersion: targetVersion)),
        );

    if (apkAssets.isEmpty) return null;
    return apkAssets.first;
  }

  int _apkScore(Map asset, {String? targetVersion}) {
    final name = ((asset['name'] as String?) ?? '').toLowerCase();
    final version = (targetVersion ?? _latestVersion)?.toLowerCase();
    if (version != null && name == 'duoyi-$version.apk') {
      return 100;
    }
    if (name.contains('universal')) return 90;
    if (!RegExp(r'-(armeabi-v7a|arm64-v8a|x86_64)\.apk$').hasMatch(name)) {
      return 80;
    }
    if (name.contains('arm64-v8a')) return 70;
    if (name.contains('armeabi-v7a')) return 60;
    if (name.contains('x86_64')) return 50;
    return 10;
  }

  String _formatReleaseNotes(String? notes) =>
      formatUpdateNotesForDisplay(notes);

  String _fallbackUpdateNotes(String? version) {
    final target = version?.trim();
    if (target == null || target.isEmpty) {
      return '本次更新会修复已知问题并优化稳定性。';
    }
    return '版本 $target 包含已知问题修复、稳定性优化和体验改进。';
  }
}

class _BackendUpdateCheckException implements Exception {
  final String message;
  final bool allowGitHubFallback;

  const _BackendUpdateCheckException(
    this.message, {
    this.allowGitHubFallback = false,
  });

  @override
  String toString() => message;
}

// ignore: unused_element
void _appUpdateRouteContract(ApiClient client) {
  client.get('/api/mobile/apps/duoyi/update');
}
