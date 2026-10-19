import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'Installed clients allow configured servers and retain system TLS trust',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final networkConfig = File(
        'android/app/src/main/res/xml/network_security_config.xml',
      ).readAsStringSync();
      final appConfig = File('lib/core/app_config.dart').readAsStringSync();

      final deployment =
          jsonDecode(File('config/deployment.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(
        Uri.parse(deployment['DUOYI_SERVER_URL'] as String).scheme,
        'https',
      );
      expect(appConfig, contains("'DUOYI_SERVER_URL'"));
      expect(appConfig, contains("String.fromEnvironment("));
      expect(appConfig, isNot(contains('todo.skydrow.site')));
      expect(appConfig, isNot(contains('6688667.xyz')));
      expect(
        manifest,
        contains(
          'android:networkSecurityConfig="@xml/network_security_config"',
        ),
      );
      expect(networkConfig, contains('cleartextTrafficPermitted="true"'));
      expect(
        networkConfig,
        contains('<base-config cleartextTrafficPermitted="true">'),
      );
      expect(networkConfig, contains('<certificates src="system" />'));
      expect(networkConfig, isNot(contains('6688667.xyz')));
      expect(networkConfig, isNot(contains('src="user"')));
      final connection = File(
        'lib/core/server_connection.dart',
      ).readAsStringSync();
      expect(connection, contains("!{'http', 'https'}.contains(uri.scheme)"));
      expect(connection, contains('uri.userInfo.isNotEmpty'));
      final ios = File('ios/Runner/Info.plist').readAsStringSync();
      expect(ios, contains('<key>NSAllowsArbitraryLoads</key>'));
      expect(ios, contains('<key>NSLocalNetworkUsageDescription</key>'));
      expect(
        manifest,
        isNot(contains('android:usesCleartextTraffic="true"')),
        reason: '明文服务器支持由网络配置文件管理，默认公开地址仍为 HTTPS。',
      );
    },
  );
}
