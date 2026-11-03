import 'dart:convert';

import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object> guestPreferences() => {
    AccountLocalDataCleaner.guestAppearanceMarkerKey: true,
    'active_brand': 're0',
    'theme_switch_count': 4,
    'theme_shop_state': jsonEncode({
      'activeBrand': 're0',
      'activeAvatarFrameId': 'mint',
      'switchCount': 4,
    }),
    'todos': '[{"id":"stale-account-task"}]',
    'duoyi_virtual_rewards': '{"balance":88,"lifetime":144}',
  };

  test('游客主动选择的免费外观重启保留，旧账号业务缓存仍清理', () async {
    SharedPreferences.setMockInitialValues(guestPreferences());
    final auth = AuthProvider();
    // 覆盖完整应用启动时使用的清理回调分支。
    auth.onAccountLoggedOut = AccountLocalDataCleaner.clearSharedPreferences;
    await auth.loadFromStorage(refreshServerConfig: false);
    final prefs = await SharedPreferences.getInstance();
    expect(auth.state.isLoggedIn, isFalse);
    expect(prefs.getString('active_brand'), 're0');
    expect(prefs.getInt('theme_switch_count'), 4);
    expect(prefs.getString('todos'), isNull);
    expect(prefs.getString('duoyi_virtual_rewards'), isNull);
    expect(
      prefs.getBool(AccountLocalDataCleaner.guestAppearanceMarkerKey),
      isTrue,
    );
    final themes = ThemeProvider();
    await themes.loadFromStorage();
    expect(themes.brand.id, 're0');
    await auth.loadFromStorage(refreshServerConfig: false);
    expect(prefs.getString('active_brand'), 're0');
    themes.dispose();
    auth.dispose();
  });

  test('有账号归属时，即使存在游客标记也不恢复账号外观', () async {
    SharedPreferences.setMockInitialValues({
      ...guestPreferences(),
      AccountLocalDataCleaner.accountDataOwnerKey: 'id:previous-account',
    });
    final auth = AuthProvider();
    await auth.loadFromStorage(refreshServerConfig: false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('active_brand'), 're0');
    expect(prefs.getString('theme_shop_state'), isNull);
    expect(
      prefs.getBool(AccountLocalDataCleaner.guestAppearanceMarkerKey),
      isNull,
    );
    auth.dispose();
  });

  test('存在旧认证缓存时不以游客身份恢复外观', () async {
    SharedPreferences.setMockInitialValues({
      ...guestPreferences(),
      'auth_state': '{"token":null}',
    });
    final auth = AuthProvider();
    await auth.loadFromStorage(refreshServerConfig: false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('active_brand'), 're0');
    expect(prefs.getString('theme_shop_state'), isNull);
    auth.dispose();
  });

  test('登录或退出使用的账户清理会同时清除游客标记和外观', () async {
    SharedPreferences.setMockInitialValues(guestPreferences());
    await AccountLocalDataCleaner.clearSharedPreferences();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(AccountLocalDataCleaner.guestAppearanceMarkerKey),
      isNull,
    );
    expect(prefs.getString('active_brand'), 're0');
    expect(prefs.getString('theme_shop_state'), isNull);
  });
}
