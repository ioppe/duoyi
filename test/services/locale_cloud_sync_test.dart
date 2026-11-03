import 'dart:convert';
import 'dart:ui';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/cloud_sync_provider.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 语言偏好跨端同步：真实 LocaleProvider + 真实 CloudSyncProvider（MockClient
/// 只替换网络层），走实际公开的 `syncNow()` / `markPreferencesChanged()`。
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    binding.platformDispatcher.localeTestValue = const Locale('en', 'US');
  });

  tearDown(() {
    binding.platformDispatcher.clearLocaleTestValue();
    I18n.setLocale(AppLocale.zh);
  });

  CloudSyncProvider buildCloudSync({
    required List<Map<String, dynamic>> requests,
    required Map<String, dynamic> Function(
      String path,
      Map<String, dynamic> body,
    )
    respond,
  }) {
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      token: 'test-token',
      httpClient: MockClient((request) async {
        final decoded = request.body.isEmpty
            ? <String, dynamic>{}
            : json.decode(request.body) as Map<String, dynamic>;
        requests.add({'path': request.url.path, 'body': decoded});
        return http.Response(
          json.encode(respond(request.url.path, decoded)),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    final provider = CloudSyncProvider();
    provider.apiClientGetter = () => client;
    provider.serverConfigGetter = () => <String, dynamic>{
      'backup_enabled': true,
    };
    return provider;
  }

  Map<String, dynamic> emptySyncResponse() => <String, dynamic>{
    'server_updated_at': '2026-06-07T00:00:00.000Z',
    'server_version': 1,
  };

  test('设备A显式选中文后，同步负载带语言值与变更键', () async {
    final requests = <Map<String, dynamic>>[];
    final cloud = buildCloudSync(
      requests: requests,
      respond: (path, body) => emptySyncResponse(),
    );
    addTearDown(cloud.dispose);
    cloud.dirtyMarkEnabled = true;

    final locale = LocaleProvider();
    addTearDown(locale.dispose);
    await locale.loadFromStorage();
    // 复刻 main.dart 的接线。
    locale.onChangedKeys = cloud.markPreferencesChanged;

    await locale.setLocale(AppLocale.zh);
    await cloud.syncNow().timeout(const Duration(seconds: 5));

    expect(requests, isNotEmpty);
    expect(requests.last['path'], '/api/sync');
    final payload = requests.last['body'] as Map<String, dynamic>;
    final preferences = payload['preferences'] as Map<String, dynamic>;
    expect(
      (preferences['values'] as Map<String, dynamic>)['duoyi_locale_v1'],
      'zh',
    );
    expect(preferences['changedKeys'], contains('duoyi_locale_v1'));
    expect(preferences['updatedAt'], isNotEmpty);
  });

  test('新设备跟随英文系统，同步后切换到账号选择的中文', () async {
    final requests = <Map<String, dynamic>>[];
    final cloud = buildCloudSync(
      requests: requests,
      respond: (path, body) => <String, dynamic>{
        ...emptySyncResponse(),
        'preferences': <String, dynamic>{
          'updatedAt': '2026-06-07T00:00:00.000Z',
          'values': <String, dynamic>{'duoyi_locale_v1': 'zh'},
          'changedKeys': <String>['duoyi_locale_v1'],
        },
      },
    );
    addTearDown(cloud.dispose);

    final locale = LocaleProvider();
    addTearDown(locale.dispose);
    await locale.loadFromStorage();
    expect(locale.locale, AppLocale.en);
    expect(locale.followsSystem, isTrue);

    // 复刻 main.dart：preferences 集合回写后重新加载语言。
    cloud.onSynced = (changedCollections) async {
      if (changedCollections.contains('preferences')) {
        await locale.loadFromStorage();
      }
    };

    await cloud.syncNow().timeout(const Duration(seconds: 5));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('duoyi_locale_v1'), 'zh');
    expect(locale.selection, 'zh');
    expect(locale.locale, AppLocale.zh);
    expect(I18n.current, AppLocale.zh);
  });

  test('另一台设备显式选择跟随系统后，本机按自身系统语言生效', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'duoyi_locale_v1': 'zh',
      'sync_preferences_updated_at': '2026-06-07T00:00:00.000Z',
    });
    final requests = <Map<String, dynamic>>[];
    final cloud = buildCloudSync(
      requests: requests,
      respond: (path, body) => <String, dynamic>{
        ...emptySyncResponse(),
        'preferences': <String, dynamic>{
          'updatedAt': '2026-06-08T00:00:00.000Z',
          'values': <String, dynamic>{'duoyi_locale_v1': 'system'},
          'changedKeys': <String>['duoyi_locale_v1'],
        },
      },
    );
    addTearDown(cloud.dispose);

    final locale = LocaleProvider();
    addTearDown(locale.dispose);
    await locale.loadFromStorage();
    expect(locale.locale, AppLocale.zh);

    cloud.onSynced = (changedCollections) async {
      if (changedCollections.contains('preferences')) {
        await locale.loadFromStorage();
      }
    };

    await cloud.syncNow().timeout(const Duration(seconds: 5));

    expect(locale.selection, 'system');
    expect(locale.followsSystem, isTrue);
    // 本机系统语言是英文，所以恢复 system 后应显示英文。
    expect(locale.locale, AppLocale.en);
    expect(I18n.current, AppLocale.en);
  });

  test('旧服务端负载不含语言键时不会清掉本地语言选择', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'duoyi_locale_v1': 'zh',
      'sync_preferences_updated_at': '2026-06-01T00:00:00.000Z',
    });
    final requests = <Map<String, dynamic>>[];
    final cloud = buildCloudSync(
      requests: requests,
      respond: (path, body) => <String, dynamic>{
        ...emptySyncResponse(),
        'preferences': <String, dynamic>{
          'updatedAt': '2026-06-08T00:00:00.000Z',
          'values': <String, dynamic>{'pref_haptic_feedback': true},
        },
      },
    );
    addTearDown(cloud.dispose);

    final locale = LocaleProvider();
    addTearDown(locale.dispose);
    await locale.loadFromStorage();
    expect(locale.selection, 'zh');

    cloud.onSynced = (changedCollections) async {
      if (changedCollections.contains('preferences')) {
        await locale.loadFromStorage();
      }
    };

    await cloud.syncNow().timeout(const Duration(seconds: 5));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('pref_haptic_feedback'), isTrue);
    expect(prefs.getString('duoyi_locale_v1'), 'zh');
    expect(locale.selection, 'zh');
    expect(locale.locale, AppLocale.zh);
  });

  test('其它偏好改动不会被当作语言改动，也不会覆盖语言值', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'duoyi_locale_v1': 'zh',
    });
    final requests = <Map<String, dynamic>>[];
    final cloud = buildCloudSync(
      requests: requests,
      respond: (path, body) => emptySyncResponse(),
    );
    addTearDown(cloud.dispose);
    cloud.dirtyMarkEnabled = true;

    await cloud.markPreferencesChanged(const ['pref_haptic_feedback']);
    await cloud.syncNow().timeout(const Duration(seconds: 5));

    expect(requests, isNotEmpty);
    final preferences =
        (requests.last['body'] as Map<String, dynamic>)['preferences']
            as Map<String, dynamic>;
    final changedKeys = preferences['changedKeys'] as List<dynamic>;
    expect(changedKeys, contains('pref_haptic_feedback'));
    expect(changedKeys, isNot(contains('duoyi_locale_v1')));
    // 语言值仍随快照上行，供服务端按 changedKeys 合并，不会被本地改动清空。
    expect(
      (preferences['values'] as Map<String, dynamic>)['duoyi_locale_v1'],
      'zh',
    );
  });
}
