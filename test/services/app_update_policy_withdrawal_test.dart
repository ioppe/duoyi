import 'dart:convert';

import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final startupOnly in [true, false]) {
    test(
      'withdrawing a force-update policy clears the gate (startup=$startupOnly)',
      () async {
        SharedPreferences.setMockInitialValues({});
        var policyEnabled = true;
        Map<String, Object?> payload() => {
          'api_contract_version': ApiClient.requiredApiContractVersion,
          'required_routes_hash': ApiClient.requiredApiContractRoutesHash,
          'latest_version': policyEnabled ? '2.0.1' : '2.0.0',
          'latest_version_name': policyEnabled ? '2.0.1' : '2.0.0',
          'latest_version_code': policyEnabled ? 142024 : 142023,
          'latest_version_code_source': 'manifest',
          'minimum_supported_version': '2.0.0',
          'minimum_supported_version_code': 142023,
          'minimum_supported_version_code_source': 'manifest',
          'force_update': policyEnabled,
          'force_update_required': policyEnabled,
          'force_app_update_enabled': policyEnabled,
          'available': policyEnabled,
          'download_url': policyEnabled
              ? 'https://example.test/duoyi-2.0.1.apk'
              : '',
          'update_download_url': policyEnabled
              ? 'https://example.test/duoyi-2.0.1.apk'
              : '',
          'release_notes': policyEnabled ? 'Test update' : '',
          'update_notes': policyEnabled ? 'Test update' : '',
        };
        final service = AppUpdateService(
          repo: '',
          currentVersion: '2.0.0',
          currentVersionCode: 142023,
          backendBaseUrl: 'https://example.test',
          httpClient: MockClient((request) async {
            if (request.url.path == '/api/config' ||
                request.url.path == '/api/mobile/apps/duoyi/update') {
              return http.Response(
                json.encode(payload()),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            return http.Response('Not found', 404);
          }),
        );
        addTearDown(service.dispose);
        await service.checkServerPolicyNow();
        expect(service.mustUpdate, isTrue);

        policyEnabled = false;
        if (startupOnly) {
          await service.checkServerPolicyNow();
        } else {
          await service.checkNow();
        }
        expect(service.error, isNull);
        expect(service.mustUpdate, isFalse);
        expect(service.hasUpdate, isFalse);
        expect(service.forceUpdateRequired, isFalse);
        expect(service.latestUrl, isNull);
      },
    );
  }
}
