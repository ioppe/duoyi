import 'package:duoyi/core/web_target.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/screens/more_apps_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    WebTarget.debugWebBuild = true;
    WebTarget.debugDesktopWebBuild = false;
    SharedPreferences.setMockInitialValues({
      'pref_app_timezone_mode': 'fixed',
      'pref_app_timezone_iana': 'UTC',
    });
  });

  tearDown(() {
    WebTarget.debugWebBuild = null;
    WebTarget.debugDesktopWebBuild = null;
  });

  for (final desktop in [false, true]) {
    test('Web desktop=$desktop 初始及重载均默认四个一级入口', () async {
      WebTarget.debugDesktopWebBuild = desktop;
      final provider = PreferencesProvider();
      addTearDown(provider.dispose);
      expect(provider.visibleBottomNavTabs, [0, 1, 2, 6]);
      await provider.loadFromStorage();
      expect(provider.visibleBottomNavTabs, [0, 1, 2, 6]);
      expect(provider.bottomNavOrder, isNot(contains(5)));
      expect(PreferencesProvider.isBottomNavTabSupported(5), isFalse);
      expect(PreferencesProvider.normalizeDefaultTab(5), 0);
      expect(
        MoreApplicationsScreen.hiddenBottomNavApps(
          provider,
        ).map((app) => app.tab),
        isNot(contains(5)),
      );
      await provider.setBottomNavVisible(5, true);
      expect(provider.visibleBottomNavTabs, [0, 1, 2, 6]);
    });
  }

  for (final previous in [
    ['0', '1', '2', '5', '6'],
    ['0', '1', '2', '3', '6'],
  ]) {
    test('旧Web默认导航 $previous 升级为四项并保存', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('pref_bottom_nav_order', [
        '0',
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
      ]);
      await prefs.setStringList('pref_bottom_nav_visible', previous);
      await prefs.setInt('pref_default_tab', 5);
      final provider = PreferencesProvider();
      addTearDown(provider.dispose);
      await provider.loadFromStorage();
      expect(provider.visibleBottomNavTabs, [0, 1, 2, 6]);
      expect(provider.defaultTab, 0);
      expect(prefs.getStringList('pref_bottom_nav_visible'), [
        '0',
        '1',
        '2',
        '6',
      ]);
      final reloaded = PreferencesProvider();
      addTearDown(reloaded.dispose);
      await reloaded.loadFromStorage();
      expect(reloaded.visibleBottomNavTabs, [0, 1, 2, 6]);
    });
  }

  test('Web自定义导航保留顺序和其他选择，仅移除小组件', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pref_bottom_nav_order', [
      '3',
      '0',
      '5',
      '6',
      '1',
      '2',
      '4',
    ]);
    await prefs.setStringList('pref_bottom_nav_visible', ['3', '0', '5', '6']);
    final provider = PreferencesProvider();
    addTearDown(provider.dispose);
    await provider.loadFromStorage();
    expect(provider.visibleBottomNavTabs, [3, 0, 6]);
    expect(provider.bottomNavVisible, {3, 0, 6});
    expect(prefs.getStringList('pref_bottom_nav_visible'), ['3', '0', '6']);
  });

  test('Web默认导航迁移只执行一次，之后的自定义选择可重载', () async {
    final provider = PreferencesProvider();
    addTearDown(provider.dispose);
    await provider.loadFromStorage();
    await provider.setBottomNavVisible(3, true);
    expect(provider.visibleBottomNavTabs, [0, 1, 2, 3, 6]);
    final reloaded = PreferencesProvider();
    addTearDown(reloaded.dispose);
    await reloaded.loadFromStorage();
    expect(reloaded.visibleBottomNavTabs, [0, 1, 2, 3, 6]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('pref_web_navigation_v2'), isTrue);
    await AccountLocalDataCleaner.clearSharedPreferences();
    expect(prefs.getBool('pref_web_navigation_v2'), isNull);
  });

  test('原生客户端默认导航保持兼容', () {
    WebTarget.debugWebBuild = false;
    final provider = PreferencesProvider();
    addTearDown(provider.dispose);
    expect(provider.visibleBottomNavTabs, [0, 1, 2, 5, 6]);
    expect(PreferencesProvider.isBottomNavTabSupported(5), isTrue);
  });
}
