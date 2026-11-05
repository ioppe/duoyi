import 'dart:convert';
import 'dart:io';

import 'package:duoyi/core/app_update_policy.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

/// 覆盖「已装 2.0.0/142023 但服务端用 versionName 合成 code」的真实事故场景。
///
/// 规则：版本名语义优先；name 相同只有可信 build 才算更新；
/// 旧服务器从 versionName 推算出来的假 code 必须当成 unknown。
void main() {
  group('版本比较统一规则', () {
    test('远端版本名更旧时即便 code 更大也不算更新', () {
      expect(
        hasNewerAppVersion(
          currentVersion: '2.0.0',
          currentVersionCode: 142023,
          latestVersion: '1.1.20',
          latestVersionCode: 200000,
        ),
        isFalse,
      );
    });

    test('版本名更高时不需要 build code', () {
      expect(
        hasNewerAppVersion(
          currentVersion: '2.0.0',
          currentVersionCode: 142023,
          latestVersion: '2.0.1',
          latestVersionCode: null,
        ),
        isTrue,
      );
    });

    test('版本名相同时只有真正更高的 build 才算更新', () {
      expect(
        hasNewerAppVersion(
          currentVersion: '2.0.0',
          currentVersionCode: 142023,
          latestVersion: '2.0.0',
          latestVersionCode: 202000,
        ),
        isTrue,
      );
      expect(
        hasNewerAppVersion(
          currentVersion: '2.0.0',
          currentVersionCode: 142023,
          latestVersion: '2.0.0',
          latestVersionCode: null,
        ),
        isFalse,
      );
    });

    test('旧公式推算出来的 code 被判定为不可信', () {
      expect(legacyDerivedVersionCode('2.0.0'), 200000);
      expect(
        resolveTrustedVersionCode(versionName: '2.0.0', versionCode: 200000),
        isNull,
      );
      expect(
        resolveTrustedVersionCode(
          versionName: '2.0.0',
          versionCode: 200000,
          codeSource: appVersionCodeSourceDerived,
        ),
        isNull,
      );
    });

    test('真实同名更高 build 与显式来源仍然可信', () {
      expect(
        resolveTrustedVersionCode(versionName: '1.1.34', versionCode: 140002),
        140002,
      );
      expect(
        resolveTrustedVersionCode(
          versionName: '2.0.0',
          versionCode: 202000,
          codeSource: appVersionCodeSourceManifest,
        ),
        202000,
      );
      expect(
        resolveTrustedVersionCode(
          versionName: '2.0.0',
          versionCode: 203000,
          codeSource: appVersionCodeSourceConfigured,
        ),
        203000,
      );
    });

    test('强制更新同样遵守名字优先规则', () {
      expect(
        shouldForceAppUpdate(
          currentVersion: '2.0.0',
          latestVersion: '1.1.20',
          minimumSupportedVersion: '1.1.20',
          forceUpdateRequired: true,
          currentVersionCode: 142023,
          latestVersionCode: 200000,
        ),
        isFalse,
      );
      expect(
        shouldForceAppUpdate(
          currentVersion: '2.0.0',
          latestVersion: '2.0.0',
          minimumSupportedVersion: '2.0.0',
          forceUpdateRequired: true,
          currentVersionCode: 142023,
          latestVersionCode: null,
        ),
        isFalse,
      );
      expect(
        shouldForceAppUpdate(
          currentVersion: '2.0.0',
          latestVersion: '2.0.0',
          minimumSupportedVersion: '2.0.0',
          forceUpdateRequired: true,
          currentVersionCode: 142023,
          latestVersionCode: 202000,
        ),
        isTrue,
      );
    });
  });

  group('服务端返回的假 build 不触发更新', () {
    test('已装 2.0.0/142023 时 2.0.0+legacy 200000 不更新也不强更', () async {
      final service = AppUpdateService(
        repo: '',
        currentVersion: '2.0.0',
        currentVersionCode: 142023,
        backendBaseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/mobile/apps/duoyi/update') {
            return http.Response(
              json.encode(
                _mobilePayload(
                  latestVersion: '2.0.0',
                  latestVersionCode: 200000,
                  available: true,
                  forceUpdate: false,
                  forceUpdateRequired: true,
                  minimumSupportedVersion: '2.0.0',
                  minimumSupportedVersionCode: 200000,
                  downloadUrl: 'https://cdn.duoyi.test/duoyi-2.0.0.apk',
                ),
              ),
              200,
            );
          }
          return http.Response('{"detail":"Not Found"}', 404);
        }),
      );

      await service.checkNow();

      expect(service.error, isNull);
      expect(service.latestVersion, '2.0.0');
      expect(service.hasUpdate, isFalse);
      expect(service.mustUpdate, isFalse);
    });

    test('远端版本名更旧时大 code 不会造成降级提示', () async {
      final service = AppUpdateService(
        repo: '',
        currentVersion: '2.0.0',
        currentVersionCode: 142023,
        backendBaseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/mobile/apps/duoyi/update') {
            return http.Response(
              json.encode(
                _mobilePayload(
                  latestVersion: '1.1.20',
                  latestVersionCode: 200000,
                  available: false,
                  forceUpdate: false,
                  forceUpdateRequired: true,
                  minimumSupportedVersion: '1.1.20',
                  minimumSupportedVersionCode: 200000,
                  releaseNotes: '旧版本不应提示',
                  downloadUrl: 'https://cdn.duoyi.test/duoyi-1.1.20.apk',
                ),
              ),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('{"detail":"Not Found"}', 404);
        }),
      );

      await service.checkNow();

      expect(service.hasUpdate, isFalse);
      expect(service.mustUpdate, isFalse);
      expect(service.latestVersion, '2.0.0');
    });

    test('2.0.1 即使 code 也是推算值也能提示更新', () async {
      final service = AppUpdateService(
        repo: '',
        currentVersion: '2.0.0',
        currentVersionCode: 142023,
        backendBaseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/mobile/apps/duoyi/update') {
            return http.Response(
              json.encode(
                _mobilePayload(
                  latestVersion: '2.0.1',
                  latestVersionCode: 200001,
                  available: true,
                  forceUpdate: true,
                  forceUpdateRequired: true,
                  minimumSupportedVersion: '2.0.0',
                  minimumSupportedVersionCode: 200000,
                  downloadUrl: 'https://cdn.duoyi.test/duoyi-2.0.1.apk',
                ),
              ),
              200,
            );
          }
          return http.Response('{"detail":"Not Found"}', 404);
        }),
      );

      await service.checkNow();

      expect(service.latestVersion, '2.0.1');
      expect(service.hasUpdate, isTrue);
      expect(service.mustUpdate, isTrue);
    });

    test('同名真实更高 build（manifest 来源）仍然提示更新', () async {
      final service = AppUpdateService(
        repo: '',
        currentVersion: '2.0.0',
        currentVersionCode: 142023,
        backendBaseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/mobile/apps/duoyi/update') {
            return http.Response(
              json.encode(
                _mobilePayload(
                  latestVersion: '2.0.0',
                  latestVersionCode: 202000,
                  latestVersionCodeSource: appVersionCodeSourceManifest,
                  available: true,
                  forceUpdate: true,
                  forceUpdateRequired: true,
                  minimumSupportedVersion: '2.0.0',
                  minimumSupportedVersionCode: 202000,
                  minimumSupportedVersionCodeSource:
                      appVersionCodeSourceManifest,
                  downloadUrl: 'https://cdn.duoyi.test/duoyi-2.0.0-202000.apk',
                ),
              ),
              200,
            );
          }
          return http.Response('{"detail":"Not Found"}', 404);
        }),
      );

      await service.checkNow();

      expect(service.hasUpdate, isTrue);
      expect(service.mustUpdate, isTrue);
    });

    test('code 缺失时只按 semver 判断', () async {
      final service = AppUpdateService(
        repo: '',
        currentVersion: '2.0.0',
        currentVersionCode: 142023,
        backendBaseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/mobile/apps/duoyi/update') {
            return http.Response(
              json.encode(
                _mobilePayload(
                  latestVersion: '2.0.0',
                  latestVersionCode: null,
                  available: false,
                  forceUpdate: false,
                  forceUpdateRequired: true,
                  downloadUrl: 'https://cdn.duoyi.test/duoyi-2.0.0.apk',
                ),
              ),
              200,
            );
          }
          return http.Response('{"detail":"Not Found"}', 404);
        }),
      );

      await service.checkNow();

      expect(service.hasUpdate, isFalse);
      expect(service.mustUpdate, isFalse);
    });
  });

  group('旧缓存里的假 build 不误报', () {
    test('缓存 2.0.0 + 推算 code 200000 会被清理', () async {
      final tmp = await Directory.systemTemp.createTemp('duoyi_update_legacy_');
      addTearDown(() async {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      });
      final apk = File('${tmp.path}/duoyi-2.0.0.apk');
      await apk.writeAsBytes(const [1, 2, 3]);
      SharedPreferences.setMockInitialValues({
        'duoyi_update_downloaded_apk_path': apk.path,
        'duoyi_update_downloaded_apk_version': '2.0.0',
        'duoyi_update_downloaded_apk_version_code': 200000,
        'duoyi_update_downloaded_apk_url':
            'https://cdn.duoyi.test/duoyi-2.0.0.apk',
        'duoyi_update_downloaded_apk_asset_name': 'duoyi-2.0.0.apk',
      });
      final service = AppUpdateService(
        repo: '',
        currentVersion: '2.0.0',
        currentVersionCode: 142023,
        backendBaseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          throw const SocketException('offline');
        }),
      );

      await service.checkNow();

      expect(service.hasDownloadedInstaller, isFalse);
      expect(service.downloadedFilePath, isNull);
      expect(service.hasUpdate, isFalse);
    });

    test('缓存 2.0.0 + 真实更高 build 202000 仍然可用', () async {
      final tmp = await Directory.systemTemp.createTemp('duoyi_update_real_');
      addTearDown(() async {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      });
      final apk = File('${tmp.path}/duoyi-2.0.0-202000.apk');
      await apk.writeAsBytes(const [1, 2, 3]);
      SharedPreferences.setMockInitialValues({
        'duoyi_update_downloaded_apk_path': apk.path,
        'duoyi_update_downloaded_apk_version': '2.0.0',
        'duoyi_update_downloaded_apk_version_code': 202000,
        'duoyi_update_downloaded_apk_version_code_source':
            appVersionCodeSourceManifest,
        'duoyi_update_downloaded_apk_url':
            'https://cdn.duoyi.test/duoyi-2.0.0-202000.apk',
        'duoyi_update_downloaded_apk_asset_name': 'duoyi-2.0.0-202000.apk',
      });
      final service = AppUpdateService(
        repo: '',
        currentVersion: '2.0.0',
        currentVersionCode: 142023,
        backendBaseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          throw const SocketException('offline');
        }),
      );

      await service.checkNow();

      expect(service.hasDownloadedInstaller, isTrue);
      expect(service.downloadedFilePath, apk.path);
      expect(service.hasUpdate, isTrue);
    });
  });
}

Map<String, Object?> _mobilePayload({
  required String latestVersion,
  int? latestVersionCode,
  String? latestVersionCodeSource,
  bool available = true,
  bool forceUpdate = true,
  bool forceUpdateRequired = true,
  String minimumSupportedVersion = '2.0.0',
  int? minimumSupportedVersionCode,
  String? minimumSupportedVersionCodeSource,
  String releaseNotes = '',
  String downloadUrl = 'https://cdn.duoyi.test/duoyi-2.0.0.apk',
}) {
  final payload = <String, Object?>{
    'api_contract_version': ApiClient.requiredApiContractVersion,
    'required_routes_hash': ApiClient.requiredApiContractRoutesHash,
    'available': available,
    'latest_version_name': latestVersion,
    'minimum_supported_version': minimumSupportedVersion,
    'download_url': downloadUrl,
    'release_notes': releaseNotes,
    'force_update': forceUpdate,
    'force_update_required': forceUpdateRequired,
    'force_app_update_enabled': forceUpdateRequired,
  };
  if (latestVersionCode != null) {
    payload['latest_version_code'] = latestVersionCode;
  }
  if (latestVersionCodeSource != null) {
    payload['latest_version_code_source'] = latestVersionCodeSource;
  }
  if (minimumSupportedVersionCode != null) {
    payload['minimum_supported_version_code'] = minimumSupportedVersionCode;
  }
  if (minimumSupportedVersionCodeSource != null) {
    payload['minimum_supported_version_code_source'] =
        minimumSupportedVersionCodeSource;
  }
  return payload;
}
