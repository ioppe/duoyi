import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/screens/notification_history_screen.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('通知设置 320px 下主要控件可滚动且不溢出', (tester) async {
    await _setNarrowPhone(tester);
    final service = _notificationServiceWithHistory();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<NotificationService>.value(value: service),
          ChangeNotifierProvider(create: (_) => PreferencesProvider()),
        ],
        child: const MaterialApp(home: NotificationSettingsScreen()),
      ),
    );
    await _pumpFixedFrames(tester);

    _expectNoLayoutException(tester);
    expect(
      find.byKey(const ValueKey('notification_settings_scroll_view')),
      findsOneWidget,
    );
    expect(find.text('通知设置'), findsAtLeastNWidgets(1));

    _expectSettingsTileReadable(
      tester,
      key: const ValueKey('notification_permission_tile'),
      title: '通知权限',
    );

    await _scrollTo(tester, find.text('普通提醒渠道'));
    _expectSettingsTileReadable(
      tester,
      title: '普通提醒渠道',
      actionKey: const ValueKey(
        'notification_channel_status_duoyi_general_alerts_v18',
      ),
    );
    _expectNoLayoutException(tester);

    await _scrollTo(
      tester,
      find.byKey(const ValueKey('notification_pending_push_tile')),
    );
    _expectSettingsTileReadable(
      tester,
      key: const ValueKey('notification_pending_push_tile'),
      title: '已调度普通提醒',
      actionKey: const ValueKey('notification_pending_push_refresh_button'),
    );
    _expectSettingsTileReadable(
      tester,
      key: const ValueKey('notification_pending_alarm_tile'),
      title: '已调度闹钟提醒',
      actionKey: const ValueKey('notification_pending_alarm_exact_button'),
    );
    _expectNoLayoutException(tester);

    await _scrollTo(
      tester,
      find.byKey(const ValueKey('notification_registered_reminders_tile')),
    );
    _expectSettingsTileReadable(
      tester,
      key: const ValueKey('notification_registered_reminders_tile'),
      title: '已注册提醒明细',
      actionKey: const ValueKey(
        'notification_registered_reminders_view_button',
      ),
    );
    _expectSettingsTileReadable(
      tester,
      key: const ValueKey('notification_registered_reminders_tile'),
      title: '已注册提醒明细',
      actionKey: const ValueKey(
        'notification_registered_reminders_refresh_button',
      ),
    );
    _expectNoLayoutException(tester);

    await _scrollTo(
      tester,
      find.byKey(const ValueKey('notification_history_entry_tile')),
    );
    _expectHistoryEntryReadable(tester);
    _expectSettingsTileReadable(
      tester,
      key: const ValueKey('notification_history_limit_tile'),
      title: '通知记录保留',
      actionKey: const ValueKey('notification_history_limit_dropdown'),
    );
    _expectNoLayoutException(tester);

    final quickAdd = find.byKey(
      const ValueKey('notification_quick_add_switch'),
    );
    if (quickAdd.evaluate().isNotEmpty) {
      _expectSettingsTileReadable(
        tester,
        key: const ValueKey('notification_quick_add_tile'),
        title: '通知栏快捷添加',
        actionKey: const ValueKey('notification_quick_add_switch'),
      );
      _expectSettingsTileReadable(
        tester,
        key: const ValueKey('notification_today_progress_tile'),
        title: '通知栏今日任务进展',
        actionKey: const ValueKey('notification_today_progress_switch'),
      );
    } else {
      await _scrollTo(tester, find.text('通知栏快捷入口'));
      _expectRectOnScreen(tester, find.text('通知栏快捷入口'));
    }

    await _scrollTo(
      tester,
      find.byKey(const ValueKey('daily_reminder_slot_0_header')),
    );
    _expectExpansionHeaderReadable(
      tester,
      header: const ValueKey('daily_reminder_slot_0_header'),
      icon: const ValueKey('daily_reminder_slot_0_header_icon'),
      title: const ValueKey('daily_reminder_slot_0_header_title'),
      subtitle: const ValueKey('daily_reminder_slot_0_header_subtitle'),
      action: const ValueKey('daily_reminder_slot_0_enabled_switch'),
    );
    _expectReminderKindSelectorReadable(tester);
    _expectNoLayoutException(tester);

    final soundControl = find.byKey(
      const ValueKey('notification_ringtone_sound_control'),
    );
    if (soundControl.evaluate().isNotEmpty) {
      await _scrollTo(tester, soundControl);
      _expectRectOnScreen(tester, soundControl);
    } else {
      await _scrollTo(tester, find.text('内置提醒铃声'));
      _expectRectOnScreen(tester, find.text('内置提醒铃声'));
    }
    final volumeControl = find.byKey(
      const ValueKey('notification_ringtone_volume_control'),
    );
    if (volumeControl.evaluate().isNotEmpty) {
      _expectRectOnScreen(tester, volumeControl);
    }
    _expectNoLayoutException(tester);

    await _scrollTo(
      tester,
      find.byKey(const ValueKey('report_reminder_daily_header')),
    );
    _expectExpansionHeaderReadable(
      tester,
      header: const ValueKey('report_reminder_daily_header'),
      icon: const ValueKey('report_reminder_daily_header_icon'),
      title: const ValueKey('report_reminder_daily_header_title'),
      subtitle: const ValueKey('report_reminder_daily_header_subtitle'),
      action: const ValueKey('report_reminder_daily_enabled_switch'),
    );
    _expectNoLayoutException(tester);
  });

  testWidgets('通知记录 320px 下筛选和批量按钮不挤压', (tester) async {
    await _setNarrowPhone(tester);
    final service = _notificationServiceWithHistory();

    await tester.pumpWidget(
      ChangeNotifierProvider<NotificationService>.value(
        value: service,
        child: const MaterialApp(home: NotificationHistoryScreen()),
      ),
    );
    await _pumpFixedFrames(tester);

    _expectNoLayoutException(tester);
    expect(find.text('通知记录'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('notification_history_mark_all_read_button')),
      findsOneWidget,
    );
    expect(find.text('全部'), findsAtLeastNWidgets(1));
    expect(find.text('未读'), findsAtLeastNWidgets(1));
    expect(find.text('已读'), findsAtLeastNWidgets(1));

    final filterRect = tester.getRect(
      find
          .ancestor(
            of: find.text('未读'),
            matching: find.byType(SingleChildScrollView),
          )
          .last,
    );
    final searchRect = tester.getRect(find.byType(TextField));
    final markReadRect = tester.getRect(
      find.byKey(const ValueKey('notification_history_mark_all_read_button')),
    );
    final summaryRect = tester.getRect(find.textContaining('共 1 条'));

    expect(filterRect.left, greaterThanOrEqualTo(0));
    expect(filterRect.right, lessThanOrEqualTo(320));
    expect(searchRect.left, greaterThanOrEqualTo(0));
    expect(searchRect.right, lessThanOrEqualTo(320));
    expect(markReadRect.left, greaterThanOrEqualTo(0));
    expect(markReadRect.right, lessThanOrEqualTo(320));
    expect(summaryRect.left, greaterThanOrEqualTo(0));
    expect(summaryRect.right, lessThanOrEqualTo(320));

    await tester.tap(
      find.byKey(const ValueKey('notification_history_mark_all_read_button')),
    );
    await _pumpFixedFrames(tester, frames: 3);

    expect(service.unreadCount, 0);
    expect(
      find.byKey(const ValueKey('notification_history_mark_all_read_button')),
      findsNothing,
    );
    _expectNoLayoutException(tester);
  });
}

Future<void> _setNarrowPhone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(320, 760);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

NotificationService _notificationServiceWithHistory() {
  final service = NotificationService();
  service.addHistoryForTest(
    NotificationItem(
      id: 'layout-unread',
      title: '待办提醒：一条很长的通知标题用于验证窄屏布局',
      body: '这里是一段较长的通知内容，用来覆盖 320px 下通知记录卡片和筛选区域的换行表现。',
      scheduledTime: DateTime(2026, 6, 9, 8),
      type: NotificationType.todo,
      isRead: false,
    ),
  );
  return service;
}

Future<void> _pumpFixedFrames(
  WidgetTester tester, {
  int frames = 6,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  final scrollable = find.byType(Scrollable).last;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump();
  for (var step = 0; step < 20 && target.evaluate().isEmpty; step++) {
    await tester.drag(scrollable, const Offset(0, -360));
    await tester.pump();
  }
  expect(target, findsAtLeastNWidgets(1));
  await tester.ensureVisible(target.first);
  await tester.pump();
}

void _expectSettingsTileReadable(
  WidgetTester tester, {
  Key? key,
  String? title,
  Key? actionKey,
  String? actionText,
}) {
  assert(key != null || title != null);

  final tile = key == null
      ? find.ancestor(
          of: find.text(title!),
          matching: find.byType(AppSettingsTile),
        )
      : find.byKey(key);
  final titleFinder = find.descendant(
    of: tile,
    matching: find.text(title ?? ''),
  );
  final action = actionKey == null
      ? actionText == null
            ? find.descendant(of: tile, matching: find.byType(TextButton)).last
            : find.descendant(of: tile, matching: find.text(actionText))
      : find.descendant(of: tile, matching: find.byKey(actionKey));

  expect(tile, findsOneWidget);
  expect(titleFinder, findsOneWidget);
  expect(action, findsOneWidget);

  final tileRect = tester.getRect(tile);
  final titleRect = tester.getRect(titleFinder);
  final actionRect = tester.getRect(action);
  final subtitle = tester.widget<AppSettingsTile>(tile).subtitle;
  final textBottom = subtitle == null
      ? titleRect.bottom
      : tester
            .getRect(find.descendant(of: tile, matching: find.text(subtitle)))
            .bottom;

  _expectRectOnScreen(tester, tile);
  expect(titleRect.left, greaterThan(tileRect.left));
  expect(actionRect.left, greaterThanOrEqualTo(titleRect.left));
  expect(actionRect.right, lessThanOrEqualTo(tileRect.right + 0.5));
  expect(actionRect.top, greaterThanOrEqualTo(textBottom));
}

void _expectHistoryEntryReadable(WidgetTester tester) {
  final tile = find.byKey(const ValueKey('notification_history_entry_tile'));
  final title = find.byKey(const ValueKey('notification_history_entry_title'));
  final action = find.byKey(
    const ValueKey('notification_history_entry_view_button'),
  );
  final subtitle = find.text('共 1 条，未读 1 条');

  expect(tile, findsOneWidget);
  expect(title, findsOneWidget);
  expect(action, findsOneWidget);
  expect(subtitle, findsOneWidget);

  final tileRect = tester.getRect(tile);
  final titleRect = tester.getRect(title);
  final actionRect = tester.getRect(action);
  final subtitleRect = tester.getRect(subtitle);
  final textCenterDy = _textBlockCenterDy(titleRect, subtitleRect);

  _expectRectOnScreen(tester, tile);
  expect(titleRect.right, lessThan(actionRect.left));
  expect(subtitleRect.top, greaterThan(titleRect.bottom));
  expect(actionRect.right, lessThanOrEqualTo(tileRect.right + 0.5));
  expect((actionRect.center.dy - textCenterDy).abs(), lessThan(8));
}

void _expectExpansionHeaderReadable(
  WidgetTester tester, {
  required Key header,
  required Key icon,
  required Key title,
  required Key subtitle,
  required Key action,
}) {
  final headerFinder = find.byKey(header);
  final iconFinder = find.byKey(icon);
  final titleFinder = find.byKey(title);
  final subtitleFinder = find.byKey(subtitle);
  final actionFinder = find.byKey(action);

  expect(headerFinder, findsOneWidget);
  expect(iconFinder, findsOneWidget);
  expect(titleFinder, findsOneWidget);
  expect(subtitleFinder, findsOneWidget);
  expect(actionFinder, findsOneWidget);

  final headerRect = tester.getRect(headerFinder);
  final iconRect = tester.getRect(iconFinder);
  final titleRect = tester.getRect(titleFinder);
  final subtitleRect = tester.getRect(subtitleFinder);
  final actionRect = tester.getRect(actionFinder);
  final textCenterDy = _textBlockCenterDy(titleRect, subtitleRect);

  _expectRectOnScreen(tester, headerFinder);
  expect(titleRect.right, lessThan(actionRect.left));
  expect(subtitleRect.top, greaterThan(titleRect.bottom));
  expect(actionRect.right, lessThanOrEqualTo(headerRect.right + 0.5));
  expect((iconRect.center.dy - textCenterDy).abs(), lessThan(6));
  expect((actionRect.center.dy - textCenterDy).abs(), lessThan(8));
}

double _textBlockCenterDy(Rect titleRect, Rect subtitleRect) {
  final top = titleRect.top < subtitleRect.top
      ? titleRect.top
      : subtitleRect.top;
  final bottom = titleRect.bottom > subtitleRect.bottom
      ? titleRect.bottom
      : subtitleRect.bottom;
  return (top + bottom) / 2;
}

void _expectReminderKindSelectorReadable(WidgetTester tester) {
  final buttons = [
    find.byKey(const ValueKey('daily_reminder_kind_push')),
    find.byKey(const ValueKey('daily_reminder_kind_popup')),
    find.byKey(const ValueKey('daily_reminder_kind_alarm')),
    find.byKey(const ValueKey('daily_reminder_kind_off')),
  ];
  for (final button in buttons) {
    expect(button, findsOneWidget);
    _expectRectOnScreen(tester, button);
  }

  final rects = buttons.map(tester.getRect).toList(growable: false);
  for (var i = 1; i < rects.length; i++) {
    expect(rects[i].left, greaterThan(rects[i - 1].right - 0.5));
  }
  expect(rects.last.right, lessThanOrEqualTo(320));
}

void _expectRectOnScreen(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(320));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(760));
}

void _expectNoLayoutException(WidgetTester tester) {
  final exception = tester.takeException();
  expect(exception, isNull);
}
