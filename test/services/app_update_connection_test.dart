import 'dart:async';
import 'dart:convert';

import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'server switch queues its force-update policy behind an older check',
    () async {
      SharedPreferences.setMockInitialValues({});
      var server = 'https://old.test';
      final oldResponse = Completer<http.Response>();
      final oldRequested = Completer<void>();
      final newChecked = Completer<void>();
      final service = AppUpdateService(
        repo: '',
        currentVersion: '1.0.0',
        currentVersionCode: 1,
        backendBaseUrlGetter: () => server,
        httpClient: MockClient((request) async {
          if (request.url.host == 'old.test') {
            if (!oldRequested.isCompleted) oldRequested.complete();
            return oldResponse.future;
          }
          if (request.url.path == '/api/mobile/apps/duoyi/update') {
            if (!newChecked.isCompleted) newChecked.complete();
            return http.Response(
              jsonEncode({
                'api_contract_version': ApiClient.requiredApiContractVersion,
                'required_routes_hash': ApiClient.requiredApiContractRoutesHash,
                'available': true,
                'force_update': true,
                'latest_version_name': '9.0.0',
                'latest_version_code': 900000,
                'minimum_supported_version': '9.0.0',
                'download_url': 'https://new.test/update.apk',
                'release_notes': 'new server policy',
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );
      final oldCheck = service.checkServerPolicyNow();
      await oldRequested.future;
      server = 'https://new.test';
      service.resetForServerChange();
      oldResponse.complete(http.Response('{}', 404));
      await oldCheck;
      await newChecked.future;
      for (var i = 0; i < 20 && service.checking; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(service.mustUpdate, isTrue);
      expect(service.latestUrl, 'https://new.test/update.apk');
    },
  );
}
