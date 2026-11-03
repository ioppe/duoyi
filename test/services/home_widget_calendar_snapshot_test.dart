import 'dart:convert';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/home_widget_calendar.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `home_widget` 插件的原生通道（与 `package:home_widget` 保持一致）。
const MethodChannel _widgetChannel = MethodChannel('home_widget');

/// 记录所有小组件原生调用，用于断言 payload 内容。
final List<MethodCall> _widgetCalls = <MethodCall>[];

Future<Object?> _handleWidgetCall(MethodCall call) async {
  _widgetCalls.add(call);
  return true;
}

Object? _savedValue(String key) {
  final saves = _widgetCalls.where(
    (call) =>
        call.method == 'saveWidgetData' && (call.arguments as Map)['id'] == key,
  );
  if (saves.isEmpty) return null;
  return (saves.last.arguments as Map)['data'];
}

/// 与 accountPayloadDefaults 对齐的最小主题：只为触发 push 的 signature 计算。
const HomeWidgetThemePayload _theme = HomeWidgetThemePayload(
  brandId: 'defaultBrand',
  cardSkinId: 'plain_card',
  dark: false,
  primary: Color(0xFFFF6B6B),
  background: Color(0xFFFFFFFF),
  surface: Color(0xFFFFFFFF),
  navBackground: Color(0xFFFFF6F2),
  border: Color(0x22FF6B6B),
  text: Color(0xFF333333),
  mutedText: Color(0xFF666666),
  onPrimary: Color(0xFFFFFFFF),
  accentStart: Color(0xFFFF6B6B),
  accentEnd: Color(0xFFFFB088),
  backgroundAssetKey: '',
  cornerRadiusDp: 13,
  controlRadiusDp: 8,
  borderWidthDp: 0,
);

Future<bool> _pushSnapshot({
  Map<String, int> counts = const <String, int>{},
  String timezone = 'Asia/Shanghai',
}) => HomeWidgetService.push(
  todoCount: 1,
  habitPercent: 0,
  pomodoroToday: 0,
  focusMinutesToday: 0,
  strings: AppBrands.defaultBrand.strings,
  todoTop3: <String>['写报告'],
  theme: _theme,
  calendarDayCounts: counts,
  calendarTimezone: timezone,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async => 'UTC';
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = () async => 'UTC';
  });

  tearDownAll(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    LocalTimezoneResolver.debugNativeSystemTimeZoneReader = null;
  });

  setUp(() async {
    _widgetCalls.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalTimezoneResolver.init();
    I18n.setLocale(AppLocale.zh);
    HomeWidgetService.debugForceSupported = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_widgetChannel, _handleWidgetCall);
  });

  tearDown(() async {
    HomeWidgetService.debugForceSupported = false;
    HomeWidgetService.debugRefreshAllWidgetsOverride = null;
    AppClock.debugNow = null;
    I18n.setLocale(AppLocale.zh);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_widgetChannel, null);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalTimezoneResolver.init();
  });

  test('月计数或时区单独变化都会刷新，同数据仍然去重', () async {
    var refreshes = 0;
    HomeWidgetService.debugRefreshAllWidgetsOverride = () async {
      refreshes++;
      return 1;
    };

    const countsA = <String, int>{'2026-07-01': 2};
    const countsB = <String, int>{'2026-07-01': 2, '2026-07-02': 1};

    expect(await _pushSnapshot(counts: countsA), isTrue);
    expect(refreshes, 1);

    expect(await _pushSnapshot(counts: countsA), isTrue);
    expect(refreshes, 1, reason: '同数据必须走 signature 去重，不重复刷新');

    expect(await _pushSnapshot(counts: countsB), isTrue);
    expect(refreshes, 2, reason: '只有月计数变化也必须刷新原生组件');

    expect(
      await _pushSnapshot(counts: countsB, timezone: 'America/New_York'),
      isTrue,
    );
    expect(refreshes, 3, reason: '时区变化必须刷新');

    // 五个协议字段与语义更新后的 summary 都在同一批写入里。
    expect(
      _savedValue('calendar_day_counts_json'),
      '{"2026-07-01":2,"2026-07-02":1}',
    );
    expect(_savedValue('calendar_timezone'), 'America/New_York');
    expect(
      jsonDecode(_savedValue('calendar_weekdays_json')! as String),
      <String>['一', '二', '三', '四', '五', '六', '日'],
    );
    expect(
      _savedValue('calendar_day_count_label'),
      I18n.tr('widget.calendar_day_count_label'),
    );
    expect(
      _savedValue('calendar_month_title'),
      I18n.tr('widget.calendar_month_title'),
    );
    expect(
      _savedValue('calendar_month_summary'),
      I18n.tr('widget.calendar_month_summary'),
    );
    // UI 纯展示文案与数值/协议同批写入。
    expect(
      _savedValue('widget_todo_empty_hint'),
      I18n.tr(
        'widget.todo_empty_hint',
      ).replaceAll('{tab}', AppBrands.defaultBrand.strings.navTodo),
    );
    expect(
      _savedValue('widget_todo_count_unit'),
      I18n.tr('widget.todo_count_unit'),
    );
    expect(
      _savedValue('widget_habit_today_label'),
      I18n.tr('widget.habit_today_label'),
    );
    expect(
      _savedValue('widget_focus_count_label'),
      I18n.tr('widget.focus_count_label'),
    );
    expect(
      _savedValue('widget_focus_minutes_label'),
      I18n.tr('widget.focus_minutes_label'),
    );
    expect(
      _savedValue('widget_focus_next_label'),
      I18n.tr('widget.focus_next_label'),
    );
    expect(
      _savedValue('widget_focus_remaining_label'),
      I18n.tr('widget.focus_remaining_label'),
    );
    expect(
      _savedValue('widget_focus_open_label'),
      I18n.tr('widget.focus_open_label'),
    );
    expect(
      _savedValue('widget_focus_running_label'),
      I18n.tr('widget.focus_running_label'),
    );
    expect(_savedValue('widget_today_label'), I18n.tr('widget.today_label'));
  });

  test('清账号后月历 key 归零且不残留上一账号的计数', () async {
    HomeWidgetService.debugRefreshAllWidgetsOverride = () async => 1;
    expect(
      await _pushSnapshot(
        counts: const <String, int>{'2026-07-01': 3},
        timezone: 'Asia/Shanghai',
      ),
      isTrue,
    );
    expect(_savedValue('calendar_day_counts_json'), '{"2026-07-01":3}');

    _widgetCalls.clear();
    expect(await HomeWidgetService.clearAccountWidgetData(), isTrue);

    expect(_savedValue('calendar_day_counts_json'), '{}');
    expect(_savedValue('calendar_timezone'), '');
    expect(
      _savedValue('calendar_weekdays_json'),
      homeWidgetCalendarWeekdayLabelsJson(),
    );
    expect(
      _savedValue('calendar_day_count_label'),
      I18n.tr('widget.calendar_day_count_label'),
    );
    expect(
      _savedValue('calendar_month_title'),
      I18n.tr('widget.calendar_month_title'),
    );
    expect(
      _savedValue('calendar_month_summary'),
      I18n.tr('widget.calendar_month_summary'),
    );
    // 账号清理也要把新增 UI 文案写回当前语言的兜底词。
    expect(
      _savedValue('widget_todo_empty_hint'),
      I18n.tr(
        'widget.todo_empty_hint',
      ).replaceAll('{tab}', I18n.tr('nav.todo')),
    );
    expect(
      _savedValue('widget_habit_today_label'),
      I18n.tr('widget.habit_today_label'),
    );
    expect(
      _savedValue('widget_focus_open_label'),
      I18n.tr('widget.focus_open_label'),
    );
    expect(
      _savedValue('widget_focus_running_label'),
      I18n.tr('widget.focus_running_label'),
    );
    expect(_savedValue('widget_today_label'), I18n.tr('widget.today_label'));

    // 兜底集合必须覆盖全部月历 key，否则切号会残留上一账号快照。
    final defaults = HomeWidgetService.accountPayloadDefaults;
    expect(defaults, contains('calendar_day_counts_json'));
    expect(defaults, contains('calendar_timezone'));
    expect(defaults, contains('calendar_weekdays_json'));
    expect(defaults, contains('calendar_day_count_label'));
    expect(defaults, contains('calendar_month_title'));
    for (final key in const <String>[
      'widget_todo_empty_hint',
      'widget_todo_count_unit',
      'widget_habit_today_label',
      'widget_focus_count_label',
      'widget_focus_minutes_label',
      'widget_focus_next_label',
      'widget_focus_remaining_label',
      'widget_focus_open_label',
      'widget_focus_running_label',
      'widget_today_label',
    ]) {
      expect(defaults, contains(key), reason: '$key 必须进账号清理兜底集合');
    }
  });

  test('冷后台 payload 复用同一套月计数口径', () async {
    final todos = TodoProvider();
    await todos.loadFromStorage();
    await todos.addTodo(
      TodoItem(
        id: 't1',
        title: '写报告',
        date: DateTime(2026, 7, 1),
        dueDate: DateTime(2026, 7, 4),
        createdAt: DateTime(2026, 7, 1, 9),
      ),
      waitForReminderSync: false,
    );
    await LocalTimezoneResolver.setApplicationTimeZone('Asia/Shanghai');

    final payload = HomeWidgetService.todoHomeWidgetActionPayload(todos);

    expect(payload['calendar_day_counts_json'], '{"2026-07-04":1}');
    expect(payload['calendar_timezone'], 'Asia/Shanghai');
    expect(
      payload['calendar_weekdays_json'],
      homeWidgetCalendarWeekdayLabelsJson(),
    );
    expect(
      payload['calendar_day_count_label'],
      I18n.tr('widget.calendar_day_count_label'),
    );
    expect(
      payload['calendar_month_title'],
      I18n.tr('widget.calendar_month_title'),
    );
    for (final key in const <String>[
      'widget_todo_count_unit',
      'widget_habit_today_label',
      'widget_focus_count_label',
      'widget_focus_minutes_label',
      'widget_focus_next_label',
      'widget_focus_remaining_label',
      'widget_focus_open_label',
      'widget_focus_running_label',
      'widget_today_label',
    ]) {
      expect(payload[key], I18n.tr(key.replaceFirst('widget_', 'widget.')));
    }
    expect(
      payload['widget_todo_empty_hint'],
      I18n.tr(
        'widget.todo_empty_hint',
      ).replaceAll('{tab}', I18n.tr('nav.todo')),
    );
  });

  test('只改语言的新 UI 文案也会触发刷新', () async {
    var refreshes = 0;
    HomeWidgetService.debugRefreshAllWidgetsOverride = () async {
      refreshes++;
      return 1;
    };

    // 用其它用例没出现过的月计数，保证首次推送一定不命中上一次的 signature。
    const counts = <String, int>{'2026-09-09': 3};
    expect(await _pushSnapshot(counts: counts), isTrue);
    final afterZh = refreshes;
    expect(_savedValue('widget_today_label'), '今天');

    I18n.setLocale(AppLocale.en);
    expect(await _pushSnapshot(counts: counts), isTrue);
    expect(refreshes, afterZh + 1, reason: '数据完全不变，只是 UI copy 换了语言，也必须重新写盘并刷新');
    expect(_savedValue('widget_today_label'), 'Today');
    expect(
      _savedValue('widget_todo_empty_hint'),
      'Open ${AppBrands.defaultBrand.strings.navTodo} to plan what’s next',
    );

    expect(await _pushSnapshot(counts: counts), isTrue);
    expect(refreshes, afterZh + 1, reason: '语言与数据都不变时仍然去重');
  });
}
