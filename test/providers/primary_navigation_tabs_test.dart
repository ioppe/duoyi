import 'package:duoyi/core/web_target.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/screens/more_apps_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一级导航移除待办（Todo）：
/// - 底栏 / 桌面 rail / 默认页 / 导航设置都不再列出待办；
/// - 槽位 1 保留在 main 的 allDestinations/_buildTab 中，深链与“更多应用”
///   仍能打开真实的待办页面；
/// - 旧存储里含 1 的 visible/order/default 在载入时清洗并回写。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    WebTarget.debugWebBuild = false;
    WebTarget.debugDesktopWebBuild = false;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_app_timezone_mode': 'fixed',
      'pref_app_timezone_iana': 'UTC',
    });
  });

  tearDown(() {
    WebTarget.debugWebBuild = null;
    WebTarget.debugDesktopWebBuild = null;
  });

  test('移动/Web 默认一级入口都是四项且不含待办', () async {
    expect(PreferencesProvider.mobileDefaultBottomNavTabs, <int>{0, 2, 4, 6});
    expect(PreferencesProvider.webDefaultBottomNavTabs, <int>{0, 2, 4, 6});

    final mobile = PreferencesProvider();
    addTearDown(mobile.dispose);
    expect(mobile.visibleBottomNavTabs, <int>[0, 2, 4, 6]);
    expect(mobile.bottomNavVisible, <int>{0, 2, 4, 6});
    expect(mobile.bottomNavOrder, isNot(contains(1)));
    await mobile.loadFromStorage();
    expect(mobile.visibleBottomNavTabs, <int>[0, 2, 4, 6]);

    WebTarget.debugWebBuild = true;
    final web = PreferencesProvider();
    addTearDown(web.dispose);
    await web.loadFromStorage();
    expect(web.visibleBottomNavTabs, <int>[0, 2, 4, 6]);
    expect(web.bottomNavOrder, isNot(contains(1)));
    expect(web.bottomNavOrder, isNot(contains(5)));
  });

  test('待办保留平台能力标记但不再是可配置一级入口', () {
    expect(PreferencesProvider.isBottomNavTabSupported(1), isTrue);
    expect(PreferencesProvider.isPrimaryNavigationTabSupported(1), isFalse);
    expect(PreferencesProvider.isPrimaryNavigationTabSupported(2), isTrue);
    expect(PreferencesProvider.normalizeDefaultTab(1), 0);
    expect(PreferencesProvider.normalizeDefaultTab(0), 0);

    WebTarget.debugWebBuild = true;
    expect(PreferencesProvider.isBottomNavTabSupported(5), isFalse);
    expect(PreferencesProvider.isPrimaryNavigationTabSupported(5), isFalse);
    expect(PreferencesProvider.isBottomNavTabSupported(1), isTrue);
    expect(PreferencesProvider.isPrimaryNavigationTabSupported(1), isFalse);
  });

  test('旧存储 visible/order/default 里的待办在载入时清洗并回写', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pref_bottom_nav_order', <String>[
      '1',
      '0',
      '2',
      '3',
      '4',
      '5',
      '6',
    ]);
    await prefs.setStringList('pref_bottom_nav_visible', <String>[
      '0',
      '1',
      '2',
      '4',
      '6',
    ]);
    await prefs.setInt('pref_default_tab', 1);

    final provider = PreferencesProvider();
    addTearDown(provider.dispose);
    await provider.loadFromStorage();

    expect(provider.visibleBottomNavTabs, <int>[0, 2, 4, 6]);
    expect(provider.bottomNavOrder, <int>[0, 2, 3, 4, 5, 6]);
    expect(provider.defaultTab, 0);
    expect(prefs.getStringList('pref_bottom_nav_visible'), <String>[
      '0',
      '2',
      '4',
      '6',
    ]);
    expect(prefs.getStringList('pref_bottom_nav_order'), <String>[
      '0',
      '2',
      '3',
      '4',
      '5',
      '6',
    ]);
    expect(prefs.getInt('pref_default_tab'), 0);

    // 兜底逻辑不能把待办重新引回一级导航。
    final reloaded = PreferencesProvider();
    addTearDown(reloaded.dispose);
    await reloaded.loadFromStorage();
    expect(reloaded.visibleBottomNavTabs, <int>[0, 2, 4, 6]);
    expect(reloaded.bottomNavOrder, isNot(contains(1)));
    expect(reloaded.defaultTab, 0);
  });

  test('setter 与排序都拒绝待办槽位', () async {
    final prefs = await SharedPreferences.getInstance();
    final provider = PreferencesProvider();
    addTearDown(provider.dispose);
    await provider.loadFromStorage();
    final orderBefore = provider.bottomNavOrder;

    await provider.setBottomNavVisible(1, true);
    expect(provider.bottomNavVisible, <int>{0, 2, 4, 6});
    expect(provider.visibleBottomNavTabs, <int>[0, 2, 4, 6]);
    // 被拒绝的写入不落盘：默认载入本身不会创建这个键。
    expect(prefs.getStringList('pref_bottom_nav_visible'), isNull);

    await provider.moveBottomNavTab(1, 2);
    expect(provider.bottomNavOrder, orderBefore);
    expect(provider.bottomNavOrder, isNot(contains(1)));

    await provider.setDefaultTab(1);
    expect(provider.defaultTab, 0);
    expect(prefs.getInt('pref_default_tab'), 0);
  });

  test('自定义顺序里夹带待办时只清洗该项，其他选择与顺序保留', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pref_bottom_nav_order', <String>[
      '3',
      '1',
      '0',
      '6',
      '4',
      '2',
      '5',
    ]);
    await prefs.setStringList('pref_bottom_nav_visible', <String>[
      '3',
      '1',
      '6',
      '4',
    ]);

    final provider = PreferencesProvider();
    addTearDown(provider.dispose);
    await provider.loadFromStorage();

    expect(provider.bottomNavOrder, <int>[3, 0, 6, 4, 2, 5]);
    expect(provider.visibleBottomNavTabs, <int>[3, 6, 4]);
    expect(provider.bottomNavVisible, <int>{3, 4, 6});
    expect(prefs.getStringList('pref_bottom_nav_order'), <String>[
      '3',
      '0',
      '6',
      '4',
      '2',
      '5',
    ]);
  });

  test('待办仍留在“更多应用”的隐藏入口里', () async {
    final provider = PreferencesProvider();
    addTearDown(provider.dispose);
    await provider.loadFromStorage();
    final hidden = MoreApplicationsScreen.hiddenBottomNavApps(
      provider,
    ).map((app) => app.tab);
    expect(hidden, contains(1));
    expect(hidden, isNot(contains(0)));

    WebTarget.debugWebBuild = true;
    final web = PreferencesProvider();
    addTearDown(web.dispose);
    await web.loadFromStorage();
    final webHidden = MoreApplicationsScreen.hiddenBottomNavApps(
      web,
    ).map((app) => app.tab);
    expect(webHidden, contains(1));
    expect(webHidden, isNot(contains(5)));
  });
}
