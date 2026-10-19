import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/report_reminder_config.dart';
import 'package:duoyi/models/goal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = null;
  });

  test('旧版底部导航偏好升级后保留我的并限制 5 个', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_default_tab': 5,
      'pref_bottom_nav_order': <String>['0', '1', '2', '3', '4', '5'],
      'pref_bottom_nav_visible': <String>['0', '1', '2', '3', '4', '5'],
    });

    final provider = PreferencesProvider();
    await provider.loadFromStorage();

    expect(provider.defaultTab, 6);
    expect(provider.bottomNavOrder, <int>[0, 1, 2, 3, 4, 5, 6]);
    expect(provider.bottomNavVisible.contains(6), isTrue);
    expect(provider.bottomNavVisible.length, lessThanOrEqualTo(5));
    expect(provider.visibleBottomNavTabs.length, lessThanOrEqualTo(5));
    expect(provider.visibleBottomNavTabs.contains(6), isTrue);
  });

  test('我的入口不能隐藏，小组件可隐藏并进入更多应用', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_bottom_nav_order': <String>['0', '1', '2', '3', '4', '5', '6'],
      'pref_bottom_nav_visible': <String>['0', '1', '2', '3', '4'],
    });

    final provider = PreferencesProvider();
    await provider.loadFromStorage();

    expect(provider.bottomNavVisible.contains(6), isTrue);
    expect(provider.bottomNavVisible.length, lessThanOrEqualTo(5));
    expect(provider.visibleBottomNavTabs, <int>[0, 1, 2, 3, 6]);

    await provider.setBottomNavVisible(5, false);
    await provider.setBottomNavVisible(6, false);

    expect(provider.bottomNavVisible.contains(5), isFalse);
    expect(provider.bottomNavVisible.contains(6), isTrue);
  });

  test('底部导航最多显示 5 个入口，新增入口超过上限时不生效', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_bottom_nav_order': <String>['0', '1', '2', '3', '4', '5', '6'],
      'pref_bottom_nav_visible': <String>['0', '1', '2', '3', '6'],
    });

    final provider = PreferencesProvider();
    await provider.loadFromStorage();

    expect(provider.bottomNavVisible, <int>{0, 1, 2, 3, 6});
    expect(provider.visibleBottomNavTabs, <int>[0, 1, 2, 3, 6]);
    await provider.setBottomNavVisible(5, true);
    expect(provider.bottomNavVisible, <int>{0, 1, 2, 3, 6});
    expect(provider.visibleBottomNavTabs, <int>[0, 1, 2, 3, 6]);

    await provider.setBottomNavVisible(2, false);
    await provider.setBottomNavVisible(5, true);
    expect(provider.bottomNavVisible, <int>{0, 1, 3, 5, 6});
    expect(provider.visibleBottomNavTabs, <int>[0, 1, 3, 5, 6]);
  });

  test('底部导航设置将我的标记为固定显示并提示上限', () {
    final source = File(
      'lib/screens/preferences_screen.dart',
    ).readAsStringSync();

    expect(source, contains('class BottomNavSettingsScreen'));
    expect(source, contains('const _BottomNavSettingsSection()'));
    expect(
      source,
      contains('PreferencesProvider.fixedBottomNavTabs.contains(tab)'),
    );
    expect(source, contains("I18n.tr('preferences.nav.fixed')"));
    expect(source, contains('class _NavConfigActions'));
    expect(source, contains(r"ValueKey('bottom_nav_actions_$tab')"));
    expect(source, contains('width: 138'));
    expect(source, contains('BoxConstraints.tightFor(width: 36, height: 36)'));
    expect(source, contains('PreferencesProvider.maxBottomNavTabs'));
    expect(source, contains('reachedLimit'));
    expect(source, contains('? null'));
  });

  test('底部导航设置 320px trailing 操作组使用固定紧凑宽度', () {
    final source = File(
      'lib/screens/preferences_screen.dart',
    ).readAsStringSync();
    final navTileSource = source.substring(
      source.indexOf('class _NavConfigTile'),
      source.indexOf('class _NavConfigActions'),
    );
    final actionsSource = source.substring(
      source.indexOf('class _NavConfigActions'),
      source.indexOf('class _SliderSetting'),
    );

    expect(navTileSource, contains('trailing: _NavConfigActions('));
    expect(actionsSource, contains(r"ValueKey('bottom_nav_actions_$tab')"));
    expect(actionsSource, contains('width: 138'));
    expect(
      actionsSource,
      contains('BoxConstraints.tightFor(width: 36, height: 36)'),
    );
    expect(actionsSource, contains('width: 56'));
    expect(actionsSource, isNot(contains('mainAxisSize: MainAxisSize.max')));
  });

  test('主导航兜底也限制最多 5 个入口', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(
      source,
      contains('static const _fallbackVisibleTabs = <int>[0, 1, 2, 6]'),
    );
    expect(source, contains('List<int> _visibleBottomNavTabs'));
    expect(source, contains('prefs.visibleBottomNavTabs'));
    expect(source, isNot(contains('const [0, 1, 2, 3, 4, 5, 6]')));
  });

  test('个性设置页二级菜单按场景分组', () {
    final source = File(
      'lib/screens/preferences_screen.dart',
    ).readAsStringSync();

    expect(source, contains('class _PreferenceMenuGroup'));
    expect(source, contains('_PreferenceSectionMenu('));
    expect(source, contains("title: I18n.tr('preferences.menu.display')"));
    expect(source, contains("label: I18n.tr('preferences.menu.calendar')"));
    expect(source, contains("label: I18n.tr('preferences.section.defaults')"));
    expect(
      source,
      contains("label: I18n.tr('preferences.menu.interaction_archive')"),
    );
    expect(source, contains("title: I18n.tr('preferences.navigation.title')"));
    expect(source, contains('const BottomNavSettingsScreen()'));
    expect(source, contains('fontSize: 11'));
    expect(source, contains('appSecondaryMenuItemTextStyle('));
    expect(source, isNot(contains("label: '通知设置'")));
  });

  test('我的页中个性设置是菜单入口，底部导航栏只在设置页出现', () {
    final source = File('lib/screens/mine_screen.dart').readAsStringSync();

    final preferencesStart = source.indexOf(
      "label: I18n.tr('preferences.title')",
    );
    expect(preferencesStart, greaterThanOrEqualTo(0));

    final preferencesEnd = source.indexOf(
      "label: I18n.tr('app_lock.title')",
      preferencesStart,
    );
    expect(preferencesEnd, greaterThan(preferencesStart));
    final preferencesEntry = source.substring(preferencesStart, preferencesEnd);

    expect(preferencesEntry, contains('PreferencesScreen()'));
    expect(source, isNot(contains("label: '底部导航栏'")));
    expect(source, isNot(contains('const BottomNavSettingsScreen()')));
    expect(
      source,
      isNot(contains('initialSection: PreferencesInitialSection.bottomNav')),
    );
  });

  test('通知记录保留数量可配置并按范围归一化', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_notification_history_limit': 2000,
    });

    final provider = PreferencesProvider();
    await provider.loadFromStorage();

    expect(provider.notificationHistoryLimit, 2000);

    await provider.setNotificationHistoryLimit(20);
    expect(provider.notificationHistoryLimit, 100);

    await provider.setNotificationHistoryLimit(9000);
    expect(provider.notificationHistoryLimit, 5000);
  });

  test('每日提醒方式按 slot 持久化并归一化重复日期', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_daily_reminder_enabled': true,
      'pref_daily_reminder_kind': 'popup',
      'pref_daily_reminder_repeat_days': <String>['1', '9', '2', 'x'],
      'pref_daily_reminder_slot2_enabled': true,
      'pref_daily_reminder_slot2_kind': 'alarm',
      'pref_daily_reminder_slot2_repeat_days': <String>['0', '8'],
      'pref_daily_reminder_slot3_enabled': true,
      'pref_daily_reminder_slot3_kind': 'off',
    });

    final provider = PreferencesProvider();
    await provider.loadFromStorage();

    expect(provider.dailyReminderSlots[0].kind, ReminderKind.popup);
    expect(provider.dailyReminderSlots[0].repeatDays, <int>[1, 2]);
    expect(provider.dailyReminderSlots[1].kind, ReminderKind.alarm);
    expect(provider.dailyReminderSlots[1].repeatDays, <int>[
      1,
      2,
      3,
      4,
      5,
      6,
      7,
    ]);
    expect(provider.dailyReminderSlots[2].kind, ReminderKind.off);
    expect(provider.dailyReminderSlots[2].enabled, isFalse);

    await provider.setDailyReminderSlot(
      2,
      provider.dailyReminderSlots[2].copyWith(
        enabled: true,
        kind: ReminderKind.popup,
        repeatDays: const [7, 7, 2],
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pref_daily_reminder_slot3_kind'), 'popup');
    expect(
      prefs.getStringList('pref_daily_reminder_slot3_repeat_days'),
      <String>['2', '7'],
    );
  });

  test('enabling a legacy off daily reminder restores a push slot', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_daily_reminder_enabled': false,
      'pref_daily_reminder_kind': 'off',
    });

    final provider = PreferencesProvider();
    await provider.loadFromStorage();

    expect(provider.dailyReminderSlots[0].kind, ReminderKind.off);
    expect(provider.dailyReminderSlots[0].enabled, isFalse);

    await provider.setDailyReminderEnabled(true);

    expect(provider.dailyReminderEnabled, isTrue);
    expect(provider.dailyReminderSlots[0].enabled, isTrue);
    expect(provider.dailyReminderSlots[0].kind, ReminderKind.push);
    expect(
      effectiveDailyReminderScheduleSlots(provider.dailyReminderSlots),
      hasLength(1),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('pref_daily_reminder_enabled'), isTrue);
    expect(prefs.getString('pref_daily_reminder_kind'), 'push');

    final reloaded = PreferencesProvider();
    await reloaded.loadFromStorage();

    expect(reloaded.dailyReminderEnabled, isTrue);
    expect(reloaded.dailyReminderSlots[0].enabled, isTrue);
    expect(reloaded.dailyReminderSlots[0].kind, ReminderKind.push);
  });

  test('每日提醒调度槽位会按同一时间去重，避免同一时刻弹两条', () {
    final slots = effectiveDailyReminderScheduleSlots(const [
      DailyReminderSlot(
        enabled: true,
        kind: ReminderKind.push,
        hour: 8,
        minute: 30,
        repeatDays: [1, 2, 3],
      ),
      DailyReminderSlot(
        enabled: true,
        kind: ReminderKind.alarm,
        hour: 8,
        minute: 30,
        repeatDays: [2, 3, 4],
      ),
      DailyReminderSlot(
        enabled: true,
        kind: ReminderKind.popup,
        hour: 21,
        minute: 0,
        repeatDays: [1, 2],
      ),
    ]);

    expect(slots.map((slot) => slot.index), <int>[0, 1, 2]);
    expect(slots[0].slot.repeatDays, <int>[1, 2, 3]);
    expect(slots[1].slot.repeatDays, <int>[4]);
    expect(slots[2].slot.repeatDays, <int>[1, 2]);
  });

  test('每日提醒完全重复的后续槽位不会参与系统调度', () {
    final slots = effectiveDailyReminderScheduleSlots(const [
      DailyReminderSlot(
        enabled: true,
        kind: ReminderKind.push,
        hour: 20,
        minute: 0,
      ),
      DailyReminderSlot(
        enabled: true,
        kind: ReminderKind.alarm,
        hour: 20,
        minute: 0,
      ),
      DailyReminderSlot(
        enabled: true,
        kind: ReminderKind.off,
        hour: 22,
        minute: 0,
      ),
    ]);

    expect(slots, hasLength(1));
    expect(slots.single.index, 0);
    expect(slots.single.slot.repeatDays, <int>[1, 2, 3, 4, 5, 6, 7]);
  });

  test('每日提醒相同配置重复保存不会再次通知监听器', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_daily_reminder_enabled': true,
      'pref_daily_reminder_kind': 'push',
      'pref_daily_reminder_hour': 8,
      'pref_daily_reminder_minute': 30,
      'pref_daily_reminder_repeat_days': <String>['1', '2', '3'],
    });
    final provider = PreferencesProvider();
    await provider.loadFromStorage();

    var notifyCount = 0;
    provider.addListener(() {
      notifyCount++;
    });

    await provider.setDailyReminderSlot(
      0,
      const DailyReminderSlot(
        enabled: true,
        kind: ReminderKind.push,
        hour: 8,
        minute: 30,
        repeatDays: [3, 2, 1],
      ),
    );

    expect(notifyCount, 0);
  });

  test('报告提醒相同配置重复保存不会再次通知监听器', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_daily_report_reminder': true,
      'pref_daily_report_reminder_hour': 9,
      'pref_daily_report_reminder_minute': 15,
      'pref_weekly_report_reminder': true,
      'pref_weekly_report_reminder_weekday': 5,
      'pref_weekly_report_reminder_hour': 18,
      'pref_weekly_report_reminder_minute': 30,
      'pref_monthly_report_reminder': true,
      'pref_monthly_report_reminder_day': 28,
      'pref_monthly_report_reminder_hour': 19,
      'pref_monthly_report_reminder_minute': 45,
      'pref_yearly_report_reminder': true,
      'pref_yearly_report_reminder_month': 12,
      'pref_yearly_report_reminder_day': 31,
      'pref_yearly_report_reminder_hour': 20,
      'pref_yearly_report_reminder_minute': 0,
    });
    final provider = PreferencesProvider();
    await provider.loadFromStorage();

    var notifyCount = 0;
    provider.addListener(() {
      notifyCount++;
    });

    await provider.setDailyReportReminderConfig(
      const ReportReminderConfig(enabled: true, hour: 9, minute: 15),
    );
    await provider.setWeeklyReportReminderConfig(
      const ReportReminderConfig(
        enabled: true,
        weekday: 5,
        hour: 18,
        minute: 30,
      ),
    );
    await provider.setMonthlyReportReminderConfig(
      const ReportReminderConfig(
        enabled: true,
        monthDay: 28,
        hour: 19,
        minute: 45,
      ),
    );
    await provider.setYearlyReportReminderConfig(
      const ReportReminderConfig(
        enabled: true,
        month: 12,
        monthDay: 31,
        hour: 20,
        minute: 0,
      ),
    );

    expect(notifyCount, 0);
  });

  test('通知设置页提供通知记录保留数量控制', () {
    final source = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();
    final preferences = File(
      'lib/screens/preferences_screen.dart',
    ).readAsStringSync();

    expect(source, contains('class NotificationSettingsScreen'));
    expect(source, contains('NotificationHistoryPolicy.options'));
    expect(source, contains("title: '通知记录保留'"));
    expect(source, contains('prefs.notificationHistoryLimit'));
    expect(source, contains('setNotificationHistoryLimit'));
    expect(source, contains('notif.setHistoryLimit'));
    expect(preferences, isNot(contains("title: '通知记录保留'")));
  });

  test('应用时区默认跟随手机，切换固定时区后触发提醒重同步回调', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'America/Mexico_City';

    var resyncCount = 0;
    final provider = PreferencesProvider()
      ..onAppTimeZoneChanged = () async {
        resyncCount++;
      };

    await provider.loadFromStorage();
    expect(provider.followSystemTimeZone, isTrue);
    expect(provider.appTimeZone, 'America/Mexico_City');

    await provider.setAppTimeZone('Asia/Tokyo');

    expect(provider.followSystemTimeZone, isFalse);
    expect(provider.appTimeZone, 'Asia/Tokyo');
    expect(resyncCount, 1);
  });
}
