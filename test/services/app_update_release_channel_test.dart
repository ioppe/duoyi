import 'dart:convert';
import 'dart:io';

import 'package:duoyi/core/app_config.dart';
import 'package:duoyi/core/app_release_channel.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_update_installer.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _official = AppReleaseChannel.repository;

Map<String, dynamic> _backend({
  String source = 'ioppe/duoyi',
  String version = '2.0.0',
  bool force = true,
}) => {
  'api_contract_version': ApiClient.requiredApiContractVersion,
  'required_routes_hash': ApiClient.requiredApiContractRoutesHash,
  'latest_version_name': version,
  'latest_version_code': 142027,
  'latest_version_code_source': 'manifest',
  'minimum_supported_version': source == _official ? version : '1.1.47',
  'minimum_supported_version_code': 142027,
  'minimum_supported_version_code_source': 'manifest',
  'force_update': force,
  'force_app_update_enabled': force,
  'download_url':
      'https://github.com/$source/releases/download/v$version/duoyi-v$version.apk',
  'release_url': 'https://github.com/$source/releases/tag/v$version',
  'release_notes': source == _official
      ? 'Current channel notes'
      : 'Legacy release notes',
};

http.Response _release([String version = '0.1.0']) => http.Response(
  jsonEncode({
    'tag_name': 'v$version',
    'body': 'Current channel features',
    'assets': [
      {
        'name': 'duoyi-v$version.apk',
        'browser_download_url':
            'https://github.com/$_official/releases/download/v$version/duoyi-v$version.apk',
      },
    ],
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'public profile and unconfigured clients use the initial release channel',
    () {
      final profile = jsonDecode(
        File('config/deployment.json').readAsStringSync(),
      );
      expect(profile['DUOYI_UPDATE_REPOSITORY'], _official);
      expect(AppConfig.updateRepository, _official);
      expect(
        AppReleaseChannel.conflictsWithOfficialChannel(
          _official,
          'https://github.com/ioppe/duoyi/releases/tag/v2.0.0',
        ),
        isTrue,
      );
      expect(
        AppReleaseChannel.conflictsWithOfficialChannel(
          _official,
          'https://github.com.evil.test/ioppe/duoyi',
        ),
        isFalse,
      );
    },
  );

  for (final field in [
    'release_repository',
    'update_repository',
    'app_update_repository',
  ]) {
    test(
      'declared $field isolates an old channel without GitHub URLs',
      () async {
        final service = AppUpdateService(
          repo: _official,
          currentVersion: '0.1.0',
          currentVersionCode: 142026,
          backendBaseUrl: 'https://server.test',
          httpClient: MockClient((request) async {
            if (request.url.path == '/api/mobile/apps/duoyi/update') {
              return http.Response(
                jsonEncode({
                  ..._backend(),
                  field: 'ioppe/duoyi',
                  'download_url': '',
                  'release_url': '',
                }),
                200,
              );
            }
            expect(request.url.path, '/repos/$_official/releases/latest');
            return _release();
          }),
        );
        addTearDown(service.dispose);
        await service.checkNow();
        expect(service.latestVersion, 'v0.1.0');
        expect(service.minimumSupportedVersion, isNull);
        expect(service.hasUpdate, isFalse);
        expect(service.mustUpdate, isFalse);
      },
    );
  }

  test(
    'historical build arguments migrate without changing custom sources',
    () {
      for (final old in ['ioppe/duoyi', 'DQ52099/DUOYI']) {
        expect(AppReleaseChannel.resolveConfiguredRepository(old), _official);
      }
      expect(
        AppReleaseChannel.resolveConfiguredRepository('custom/fork'),
        'custom/fork',
      );
      expect(AppReleaseChannel.resolveConfiguredRepository(''), isEmpty);
    },
  );

  for (final startup in [false, true]) {
    for (final legacy in ['ioppe/duoyi', 'dq52099/duoyi']) {
      test(
        '${startup ? 'startup' : 'manual'} check ignores $legacy versions and minimum policy',
        () async {
          final paths = <String>[];
          final service = AppUpdateService(
            repo: _official,
            currentVersion: '0.1.0',
            currentVersionCode: 142026,
            backendBaseUrl: 'https://server.test',
            httpClient: MockClient((request) async {
              paths.add(request.url.path);
              if (request.url.path == '/api/mobile/apps/duoyi/update') {
                return http.Response(jsonEncode(_backend(source: legacy)), 200);
              }
              expect(request.url.host, 'api.github.com');
              expect(request.url.path, '/repos/$_official/releases/latest');
              return _release();
            }),
          );
          addTearDown(service.dispose);

          if (startup) {
            await service.checkServerPolicyNow();
          } else {
            await service.checkNow();
          }

          expect(service.error, isNull);
          expect(service.latestVersion, 'v0.1.0');
          expect(service.latestNotes, 'Current channel features');
          expect(service.latestUrl, contains('github.com/$_official/'));
          expect(service.hasUpdate, isFalse);
          expect(service.mustUpdate, isFalse);
          expect(service.minimumSupportedVersion, isNull);
          expect(paths, [
            '/api/mobile/apps/duoyi/update',
            '/repos/$_official/releases/latest',
          ]);
        },
      );
    }
  }

  test(
    'legacy config source is isolated when the mobile endpoint is absent',
    () async {
      final service = AppUpdateService(
        repo: _official,
        currentVersion: '0.1.0',
        currentVersionCode: 142026,
        backendBaseUrl: 'https://server.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/mobile/apps/duoyi/update') {
            return http.Response('{}', 404);
          }
          if (request.url.path == '/api/config') {
            return http.Response(
              jsonEncode({
                'api_contract_version': ApiClient.requiredApiContractVersion,
                'required_routes_hash': ApiClient.requiredApiContractRoutesHash,
                'app_update': {
                  ..._backend(),
                  'latest_version': '2.0.0',
                  'update_download_url':
                      'https://github.com/ioppe/duoyi/releases/download/v2.0.0/duoyi-v2.0.0.apk',
                },
              }),
              200,
            );
          }
          expect(request.url.path, '/repos/$_official/releases/latest');
          return _release();
        }),
      );
      addTearDown(service.dispose);
      await service.checkNow();
      expect(service.hasUpdate, isFalse);
      expect(service.mustUpdate, isFalse);
      expect(service.minimumSupportedVersion, isNull);
      expect(service.latestVersion, 'v0.1.0');
    },
  );

  test('a subsequent release from the new channel is still offered', () async {
    final service = AppUpdateService(
      repo: _official,
      currentVersion: '0.1.0',
      currentVersionCode: 142026,
      backendBaseUrl: 'https://server.test',
      httpClient: MockClient(
        (request) async => request.url.host == 'server.test'
            ? http.Response(jsonEncode(_backend()), 200)
            : _release('0.1.1'),
      ),
    );
    addTearDown(service.dispose);
    await service.checkNow();
    expect(service.latestVersion, 'v0.1.1');
    expect(service.hasUpdate, isTrue);
    expect(service.mustUpdate, isFalse);
  });

  test(
    'official backend force policy and trusted same-version build remain effective',
    () async {
      final service = AppUpdateService(
        repo: _official,
        currentVersion: '0.1.0',
        currentVersionCode: 142026,
        backendBaseUrl: 'https://server.test',
        httpClient: MockClient((request) async {
          expect(request.url.host, 'server.test');
          return http.Response(
            jsonEncode(_backend(source: _official, version: '0.1.0')),
            200,
          );
        }),
      );
      addTearDown(service.dispose);
      await service.checkNow();
      expect(service.latestVersion, '0.1.0');
      expect(service.hasUpdate, isTrue);
      expect(service.mustUpdate, isTrue);
      expect(service.latestVersionCode, 142027);
    },
  );

  test(
    'explicit custom repositories retain their existing backend policy',
    () async {
      final service = AppUpdateService(
        repo: 'custom/duoyi',
        currentVersion: '0.1.0',
        currentVersionCode: 142026,
        backendBaseUrl: 'https://server.test',
        httpClient: MockClient((request) async {
          expect(request.url.host, 'server.test');
          return http.Response(jsonEncode(_backend()), 200);
        }),
      );
      addTearDown(service.dispose);
      await service.checkNow();
      expect(service.latestVersion, '2.0.0');
      expect(service.hasUpdate, isTrue);
      expect(service.mustUpdate, isTrue);
    },
  );

  test('saved legacy installers cannot restore a cross-channel update', () async {
    final directory = Directory.systemTemp.createTempSync(
      'duoyi-channel-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/old.apk')
      ..writeAsStringSync('fixture');
    SharedPreferences.setMockInitialValues({
      'duoyi_update_downloaded_apk_path': file.path,
      'duoyi_update_downloaded_apk_version': '2.0.0',
      'duoyi_update_downloaded_apk_url':
          'https://github.com/ioppe/duoyi/releases/download/v2.0.0/duoyi-v2.0.0.apk',
      'unrelated_preference': 'preserved',
    });
    final service = AppUpdateService(
      repo: _official,
      currentVersion: '0.1.0',
      currentVersionCode: 142026,
      backendBaseUrl: '',
      httpClient: MockClient((request) async => _release()),
    );
    addTearDown(service.dispose);
    await service.checkNow();
    expect(service.hasDownloadedInstaller, isFalse);
    expect(service.hasUpdate, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('duoyi_update_downloaded_apk_path'), isNull);
    expect(prefs.getString('unrelated_preference'), 'preserved');
    expect(file.existsSync(), isTrue);
  });

  test('background download from the old channel is not resurrected', () async {
    const channel = MethodChannel('duoyi/update');
    final calls = <String>[];
    debugForceAppUpdateBackgroundDownload = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'queryBackgroundDownload') {
            return {
              'downloadId': 52,
              'status': 'running',
              'versionName': '2.0.0',
              'url':
                  'https://github.com/ioppe/duoyi/releases/download/v2.0.0/duoyi-v2.0.0.apk',
            };
          }
          return null;
        });
    addTearDown(() {
      debugForceAppUpdateBackgroundDownload = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final service = AppUpdateService(
      repo: _official,
      currentVersion: '0.1.0',
      currentVersionCode: 142026,
      backendBaseUrl: '',
      httpClient: MockClient((request) async => _release()),
    );
    addTearDown(service.dispose);
    await service.refreshDownloadState();
    expect(calls, contains('cancelBackgroundDownload'));
    expect(service.backgroundDownloadActive, isFalse);
    expect(service.latestVersion, isNull);
    expect(service.downloading, isFalse);
  });
}
