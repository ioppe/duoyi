import 'dart:convert';
import 'dart:io';

import 'package:duoyi/core/web_target.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WebTarget.debugWebBuild = false;
  });
  tearDown(() => WebTarget.debugWebBuild = null);

  test(
    'editing a server while signed out does not erase local data on restart',
    () async {
      final auth = AuthProvider();
      await auth.loadFromStorage(refreshServerConfig: false);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('todos', '[{"id":"local-task"}]');
      await auth.configureServer('https://changed.example');
      expect(prefs.containsKey('auth_state'), isFalse);
      final restarted = AuthProvider();
      await restarted.loadFromStorage(refreshServerConfig: false);
      expect(prefs.getString('todos'), contains('local-task'));
      expect(restarted.state.isLoggedIn, isFalse);
      auth.dispose();
      restarted.dispose();
    },
  );

  test(
    'native local account keeps its tasks and history after restart',
    () async {
      final first = AuthProvider();
      await first.loadFromStorage(refreshServerConfig: false);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(AccountLocalDataCleaner.localAccountMarkerKey),
        isTrue,
      );
      await prefs.setString('todos', '[{"id":"local-task","title":"本地任务"}]');
      await prefs.setStringList('ai_review_history', ['{"id":"local-review"}']);

      final restarted = AuthProvider();
      await restarted.loadFromStorage(refreshServerConfig: false);
      expect(restarted.state.isLoggedIn, isFalse);
      expect(prefs.getString('todos'), contains('local-task'));
      expect(prefs.getStringList('ai_review_history'), [
        '{"id":"local-review"}',
      ]);
      expect(
        prefs.getString(AccountLocalDataCleaner.accountDataOwnerKey),
        isNull,
      );
      first.dispose();
      restarted.dispose();
    },
  );

  test('local marker cannot preserve a remote account cache', () async {
    SharedPreferences.setMockInitialValues({
      AccountLocalDataCleaner.localAccountMarkerKey: true,
      AccountLocalDataCleaner.accountDataOwnerKey: 'id:old-remote-user',
      'todos': '[{"id":"private-remote-task"}]',
      'ai_review_history': ['{"id":"private-remote-review"}'],
    });
    final auth = AuthProvider();
    await auth.loadFromStorage(refreshServerConfig: false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('todos'), isNull);
    expect(prefs.getStringList('ai_review_history'), isNull);
    expect(
      prefs.getString(AccountLocalDataCleaner.accountDataOwnerKey),
      isNull,
    );
    expect(
      prefs.getBool(AccountLocalDataCleaner.localAccountMarkerKey),
      isTrue,
    );
    auth.dispose();
  });

  test(
    'Web signed-out startup does not retain native local account data',
    () async {
      WebTarget.debugWebBuild = true;
      SharedPreferences.setMockInitialValues({
        AccountLocalDataCleaner.localAccountMarkerKey: true,
        'todos': '[{"id":"local-task"}]',
      });
      final auth = AuthProvider();
      await auth.loadFromStorage(refreshServerConfig: false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('todos'), isNull);
      expect(
        prefs.getBool(AccountLocalDataCleaner.localAccountMarkerKey),
        isNull,
      );
      auth.dispose();
    },
  );

  test(
    'account cleanup removes local identity before another account is used',
    () async {
      SharedPreferences.setMockInitialValues({
        AccountLocalDataCleaner.localAccountMarkerKey: true,
        'todos': '[{"id":"local-task"}]',
      });
      await AccountLocalDataCleaner.clearSharedPreferences();
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(AccountLocalDataCleaner.localAccountMarkerKey),
        isNull,
      );
      expect(prefs.getString('todos'), isNull);
    },
  );

  test(
    'backup export and import exclude local AI connection and key',
    () async {
      const secret = 'local-key-not-for-backups';
      const storageKey = 'duoyi_local_ai_config_v1';
      SharedPreferences.setMockInitialValues({
        storageKey: jsonEncode({'apiKey': secret, 'model': 'private-model'}),
        'todos': '[{"id":"backup-task"}]',
      });
      final exported = await BackupService.exportAll();
      expect(exported, contains('backup-task'));
      expect(exported, isNot(contains(secret)));
      expect(exported, isNot(contains(storageKey)));
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
      await BackupService.importAll(
        jsonEncode({
          'app': 'duoyi',
          'schema': 1,
          'data': {
            storageKey: {'type': 'string', 'value': secret},
          },
        }),
      );
      expect(prefs.getString(storageKey), isNull);
    },
  );

  test('Android cloud backup and device transfer exclude secure storage', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    final oldRules = File(
      'android/app/src/main/res/xml/backup_rules.xml',
    ).readAsStringSync();
    final newRules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();
    for (final file in [
      'FlutterSecureStorage.xml',
      'FlutterSecureKeyStorage.xml',
    ]) {
      expect(oldRules, contains('<exclude domain="sharedpref" path="$file"'));
      final cloud = newRules
          .split('<cloud-backup>')[1]
          .split('</cloud-backup>')[0];
      final transfer = newRules
          .split('<device-transfer>')[1]
          .split('</device-transfer>')[0];
      expect(cloud, contains('<exclude domain="sharedpref" path="$file"'));
      expect(transfer, contains('<exclude domain="sharedpref" path="$file"'));
    }
  });
}
