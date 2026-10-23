import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/screens/notification_history_screen.dart';
import 'package:duoyi/services/alarm_service.dart';
import 'package:duoyi/services/native_reminder_ringtone.dart';
import 'package:duoyi/services/reminder_scheduler.dart';
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

  testWidgets('通知记录 320px 下批量已读和筛选区不挤压', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = NotificationService();
    service.addHistoryForTest(
      NotificationItem(
        id: 'unread-long-title',
        title: '待办提醒：一条很长的通知标题用于验证窄屏布局',
        body: '这里是一段较长的通知内容，用来覆盖 320px 下通知记录卡片和筛选区域的换行表现。',
        scheduledTime: DateTime(2026, 6, 9, 8),
        type: NotificationType.todo,
        isRead: false,
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<NotificationService>.value(
        value: service,
        child: const MaterialApp(home: NotificationHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('通知记录'), findsOneWidget);
    expect(find.text('全部'), findsAtLeastNWidgets(1));
    expect(find.text('未读'), findsAtLeastNWidgets(1));
    expect(find.text('已读'), findsAtLeastNWidgets(1));
    expect(
      find.byKey(const ValueKey('notification_history_mark_all_read_button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('notification_history_mark_all_read_button')),
    );
    await tester.pumpAndSettle();

    expect(service.unreadCount, 0);
    expect(
      find.byKey(const ValueKey('notification_history_mark_all_read_button')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('通知设置 320px 下多个设置按钮保持同一行', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = NotificationService();
    service.addHistoryForTest(
      NotificationItem(
        id: 'unread-entry',
        title: '待办提醒',
        body: '通知设置入口布局验证',
        scheduledTime: DateTime(2026, 6, 9, 9),
        type: NotificationType.todo,
        isRead: false,
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<NotificationService>.value(value: service),
          ChangeNotifierProvider(create: (_) => PreferencesProvider()),
        ],
        child: const MaterialApp(home: NotificationSettingsScreen()),
      ),
    );
    await tester.pump();
    final permissionTile = find.byKey(
      const ValueKey('notification_permission_tile'),
    );
    _expectTileIconAndActionCenteredWithReadableText(
      tester,
      title: find.descendant(of: permissionTile, matching: find.text('通知权限')),
      subtitle: find.descendant(
        of: permissionTile,
        matching: find.text('开启后才能收到普通通知和提醒'),
      ),
      icon: find.descendant(
        of: permissionTile,
        matching: find.byIcon(Icons.notifications_off_outlined),
      ),
      action: find.descendant(of: permissionTile, matching: find.text('开启')),
    );
    final normalChannelTile = find.ancestor(
      of: find.text('普通提醒渠道'),
      matching: find.byType(AppSettingsTile),
    );
    _expectTileIconAndActionCenteredWithReadableText(
      tester,
      title: find.descendant(
        of: normalChannelTile,
        matching: find.text('普通提醒渠道'),
      ),
      subtitle: find.descendant(
        of: normalChannelTile,
        matching: find.textContaining('检查普通通知的声音、横幅和锁屏权限'),
      ),
      icon: find.descendant(
        of: normalChannelTile,
        matching: find.byIcon(Icons.settings_outlined),
      ),
      action: find.byKey(
        const ValueKey(
          'notification_channel_status_${NotificationService.channelId}',
        ),
      ),
    );
    final alarmChannelTile = find.ancestor(
      of: find.text('强提醒渠道'),
      matching: find.byType(AppSettingsTile),
    );
    _expectTileIconAndActionCenteredWithReadableText(
      tester,
      title: find.descendant(
        of: alarmChannelTile,
        matching: find.text('强提醒渠道'),
      ),
      subtitle: find.descendant(
        of: alarmChannelTile,
        matching: find.textContaining('检查闹钟提醒的声音、横幅和全屏展示权限'),
      ),
      icon: find.descendant(
        of: alarmChannelTile,
        matching: find.byIcon(Icons.alarm_on_outlined),
      ),
      action: find.byKey(
        const ValueKey('notification_channel_status_${AlarmService.channelId}'),
      ),
    );
    final fallbackChannelTile = find.ancestor(
      of: find.text('闹钟降级兜底'),
      matching: find.byType(AppSettingsTile),
    );
    _expectTileIconAndActionCenteredWithReadableText(
      tester,
      title: find.descendant(
        of: fallbackChannelTile,
        matching: find.text('闹钟降级兜底'),
      ),
      subtitle: find.descendant(
        of: fallbackChannelTile,
        matching: find.textContaining('强提醒或内置铃声注册失败时会改用普通提醒'),
      ),
      icon: find.descendant(
        of: fallbackChannelTile,
        matching: find.byIcon(Icons.alt_route_outlined),
      ),
      action: find.byKey(
        const ValueKey(
          'notification_channel_status_${NativeReminderRingtone.fallbackChannelId}',
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('已调度闹钟提醒'),
      900,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    final pendingPushTile = find.byKey(
      const ValueKey('notification_pending_push_tile'),
    );
    _expectTileIconAndActionCenteredWithReadableText(
      tester,
      title: find.descendant(
        of: pendingPushTile,
        matching: find.text('已调度普通提醒'),
      ),
      subtitle: find.descendant(
        of: pendingPushTile,
        matching: find.textContaining('待触发'),
      ),
      icon: find.descendant(
        of: pendingPushTile,
        matching: find.byIcon(Icons.schedule),
      ),
      action: find.byKey(
        const ValueKey('notification_pending_push_refresh_button'),
      ),
    );
    final pendingAlarmTile = find.byKey(
      const ValueKey('notification_pending_alarm_tile'),
    );
    _expectTileIconAndActionCenteredWithReadableText(
      tester,
      title: find.descendant(
        of: pendingAlarmTile,
        matching: find.text('已调度闹钟提醒'),
      ),
      subtitle: find.descendant(
        of: pendingAlarmTile,
        matching: find.textContaining('强提醒队列'),
      ),
      icon: find.descendant(
        of: pendingAlarmTile,
        matching: find.byIcon(Icons.alarm_on_outlined),
      ),
      action: find.byKey(
        const ValueKey('notification_pending_alarm_exact_button'),
      ),
    );
    final registeredTile = find.byKey(
      const ValueKey('notification_registered_reminders_tile'),
    );
    final registeredSubtitle = _firstExisting(tester, [
      find.descendant(
        of: registeredTile,
        matching: find.textContaining('提醒注册表'),
      ),
      find.descendant(
        of: registeredTile,
        matching: find.textContaining('提醒调度器'),
      ),
      find.descendant(
        of: registeredTile,
        matching: find.textContaining('提醒对象'),
      ),
    ]);
    _expectTileIconAndActionCenteredWithReadableText(
      tester,
      title: find.descendant(
        of: registeredTile,
        matching: find.text('已注册提醒明细'),
      ),
      subtitle: registeredSubtitle,
      icon: find.descendant(
        of: registeredTile,
        matching: find.byIcon(Icons.fact_check_outlined),
      ),
      action: find.byKey(
        const ValueKey('notification_registered_reminders_refresh_button'),
      ),
    );
    _expectTileIconAndActionCenteredWithReadableText(
      tester,
      title: find.descendant(
        of: registeredTile,
        matching: find.text('已注册提醒明细'),
      ),
      subtitle: registeredSubtitle,
      icon: find.descendant(
        of: registeredTile,
        matching: find.byIcon(Icons.fact_check_outlined),
      ),
      action: find.byKey(
        const ValueKey('notification_registered_reminders_view_button'),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('notification_history_entry_tile')),
      1200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();

    final titleRect = tester.getRect(
      find.byKey(const ValueKey('notification_history_entry_title')),
    );
    final historyTileRect = tester.getRect(
      find.byKey(const ValueKey('notification_history_entry_tile')),
    );
    final historyIconRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('notification_history_entry_tile')),
        matching: find.byIcon(Icons.history_outlined),
      ),
    );
    final subtitleRect = tester.getRect(find.text('共 1 条，未读 1 条'));
    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('notification_history_entry_view_button')),
    );
    final historyTextCenterDy = _textBlockCenterDy(titleRect, subtitleRect);

    expect(historyTileRect.height, greaterThan(historyIconRect.height));
    expect(
      (historyIconRect.center.dy - historyTextCenterDy).abs(),
      lessThan(5),
    );
    expect((buttonRect.center.dy - historyTextCenterDy).abs(), lessThan(5));
    expect(subtitleRect.top, greaterThan(titleRect.bottom));
    expect(buttonRect.left, greaterThan(titleRect.right));
    expect(find.text('共 1 条，未读 1 条'), findsOneWidget);
    final historyLimitTile = find.byKey(
      const ValueKey('notification_history_limit_tile'),
    );
    _expectTileIconAndActionCenteredWithReadableText(
      tester,
      title: find.descendant(
        of: historyLimitTile,
        matching: find.text('通知记录保留'),
      ),
      subtitle: find.descendant(
        of: historyLimitTile,
        matching: find.textContaining('最多保留'),
      ),
      icon: find.descendant(
        of: historyLimitTile,
        matching: find.byIcon(Icons.inventory_2_outlined),
      ),
      action: find.byKey(const ValueKey('notification_history_limit_dropdown')),
    );

    if (find
        .byKey(const ValueKey('notification_quick_add_switch'))
        .evaluate()
        .isNotEmpty) {
      final quickAddTile = find.byKey(
        const ValueKey('notification_quick_add_tile'),
      );
      _expectTileIconAndActionCenteredWithReadableText(
        tester,
        title: find.descendant(of: quickAddTile, matching: find.text('通知快捷记录')),
        subtitle: find.descendant(
          of: quickAddTile,
          matching: find.textContaining('通知栏'),
        ),
        icon: find.descendant(
          of: quickAddTile,
          matching: find.byIcon(Icons.add_alert_outlined),
        ),
        action: find.byKey(const ValueKey('notification_quick_add_switch')),
      );
      final todayProgressTile = find.byKey(
        const ValueKey('notification_today_progress_tile'),
      );
      _expectTileIconAndActionCenteredWithReadableText(
        tester,
        title: find.descendant(
          of: todayProgressTile,
          matching: find.text('今日任务进展'),
        ),
        subtitle: find.descendant(
          of: todayProgressTile,
          matching: find.textContaining('今日'),
        ),
        icon: find.descendant(
          of: todayProgressTile,
          matching: find.byIcon(Icons.today_outlined),
        ),
        action: find.byKey(
          const ValueKey('notification_today_progress_switch'),
        ),
      );
    }

    await tester.scrollUntilVisible(
      find.text('每日效率复盘'),
      1200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('每日效率复盘'));
    await tester.pumpAndSettle();
    final dailyReportTimeTile = find.ancestor(
      of: find.text('推送时间'),
      matching: find.byType(AppSettingsTile),
    );
    _expectTileIconAndActionCenteredWithReadableText(
      tester,
      title: find.descendant(
        of: dailyReportTimeTile,
        matching: find.text('推送时间'),
      ),
      subtitle: find.descendant(
        of: dailyReportTimeTile,
        matching: find.text('到点推送今天报告动态摘要'),
      ),
      icon: find.descendant(
        of: dailyReportTimeTile,
        matching: find.byIcon(Icons.schedule),
      ),
      action: find.byKey(const ValueKey('report_reminder_time_button_daily')),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('每日提醒 320px 下四种提醒方式保持一行', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => NotificationService()),
          ChangeNotifierProvider(create: (_) => PreferencesProvider()),
        ],
        child: const MaterialApp(home: NotificationSettingsScreen()),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('daily_reminder_kind_selector_row')),
      1200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();

    final buttons = [
      find.byKey(const ValueKey('daily_reminder_kind_push')),
      find.byKey(const ValueKey('daily_reminder_kind_popup')),
      find.byKey(const ValueKey('daily_reminder_kind_alarm')),
      find.byKey(const ValueKey('daily_reminder_kind_off')),
    ];
    for (final button in buttons) {
      expect(button, findsOneWidget);
    }

    final rects = buttons.map(tester.getRect).toList(growable: false);
    final centers = rects.map((rect) => rect.center.dy).toList(growable: false);
    final minCenter = centers.reduce((a, b) => a < b ? a : b);
    final maxCenter = centers.reduce((a, b) => a > b ? a : b);
    expect(maxCenter - minCenter, lessThan(6));
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].left, greaterThan(rects[i - 1].left));
    }
    expect(rects.last.right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('通知设置 320px 下展开头部图标和开关垂直居中', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => NotificationService()),
          ChangeNotifierProvider(create: (_) => PreferencesProvider()),
        ],
        child: const MaterialApp(home: NotificationSettingsScreen()),
      ),
    );
    await tester.pump();

    final firstReminderHeader = find.byKey(
      const ValueKey('daily_reminder_slot_0_header'),
    );
    await tester.scrollUntilVisible(
      firstReminderHeader,
      1200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    _expectExpansionHeaderAligned(
      tester,
      header: firstReminderHeader,
      icon: find.byKey(const ValueKey('daily_reminder_slot_0_header_icon')),
      title: find.byKey(const ValueKey('daily_reminder_slot_0_header_title')),
      subtitle: find.byKey(
        const ValueKey('daily_reminder_slot_0_header_subtitle'),
      ),
      action: find.byKey(
        const ValueKey('daily_reminder_slot_0_enabled_switch'),
      ),
    );

    final dailyReportHeader = find.byKey(
      const ValueKey('report_reminder_daily_header'),
    );
    await tester.scrollUntilVisible(
      dailyReportHeader,
      1200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    _expectExpansionHeaderAligned(
      tester,
      header: dailyReportHeader,
      icon: find.byKey(const ValueKey('report_reminder_daily_header_icon')),
      title: find.byKey(const ValueKey('report_reminder_daily_header_title')),
      subtitle: find.byKey(
        const ValueKey('report_reminder_daily_header_subtitle'),
      ),
      action: find.byKey(
        const ValueKey('report_reminder_daily_enabled_switch'),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('已注册提醒明细 320px 下可以打开独立页面', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => NotificationService()),
          ChangeNotifierProvider(create: (_) => PreferencesProvider()),
        ],
        child: const MaterialApp(home: NotificationSettingsScreen()),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(
        const ValueKey('notification_registered_reminders_view_button'),
      ),
      1200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    await tester.tap(
      find.byKey(
        const ValueKey('notification_registered_reminders_view_button'),
      ),
    );
    await tester.pumpAndSettle();
    // 后台系统队列解析驱动到完成，避免遗留计时器影响断言。
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();

    expect(find.byType(RegisteredRemindersScreen), findsOneWidget);
    expect(find.text('已注册提醒'), findsAtLeastNWidgets(1));
    // 默认展示“生效中”过滤，且无注册提醒时给出空态。
    expect(find.text('暂无生效中的提醒'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已注册提醒独立页默认展示生效提醒并支持分页和状态过滤', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final service = NotificationService();
    addTearDown(service.dispose);
    final registry = InMemoryReminderScheduleRegistry();
    final activeIds = <int>{};
    for (var i = 1; i <= 21; i++) {
      final id = 9100 + i;
      activeIds.add(id);
      final number = i.toString().padLeft(2, '0');
      await registry.replaceObject(
        'todo',
        'todo-$number',
        {id},
        display: ReminderScheduleDisplayInfo(
          title: '客户回访 $number',
          subtitle: '待办 · 一次提醒 · 普通通知 · 明天 09:00',
        ),
      );
    }
    await registry.replaceObject(
      'habit',
      'drink-water',
      {9801},
      display: const ReminderScheduleDisplayInfo(
        title: '喝水',
        subtitle: '习惯 · 重复提醒 · 闹钟提醒 · 每天 21:00',
      ),
    );
    final scheduler = ReminderScheduler(service, registry: registry);

    await tester.pumpWidget(
      Provider<ReminderScheduler?>.value(
        value: scheduler,
        child: MaterialApp(
          home: RegisteredRemindersScreen(
            pendingQueueLoader: () async => activeIds,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RegisteredRemindersScreen), findsOneWidget);
    expect(find.text('生效中 · 21'), findsOneWidget);
    expect(find.text('未生效 · 1'), findsOneWidget);
    expect(find.text('全部 · 22'), findsOneWidget);
    expect(find.text('提醒事项：客户回访 01'), findsOneWidget);
    expect(find.text('提醒规则：待办 · 一次提醒 · 普通通知 · 明天 09:00'), findsWidgets);
    expect(find.text('待触发提醒：1 条'), findsWidgets);
    expect(find.text('1-20 / 21 · 第 1/2 页'), findsOneWidget);
    expect(find.textContaining('todo-01'), findsNothing);
    expect(find.textContaining('9101'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('registered_reminders_next')));
    await tester.pump();

    expect(find.text('提醒事项：客户回访 21'), findsOneWidget);
    expect(find.text('21-21 / 21 · 第 2/2 页'), findsOneWidget);

    await tester.tap(find.text('未生效 · 1'));
    await tester.pump();

    expect(find.text('提醒事项：喝水'), findsOneWidget);
    expect(find.text('提醒规则：习惯 · 重复提醒 · 闹钟提醒 · 每天 21:00'), findsOneWidget);
    expect(find.text('未生效'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Finder _firstExisting(WidgetTester tester, List<Finder> candidates) {
  for (final candidate in candidates) {
    if (candidate.evaluate().isNotEmpty) return candidate;
  }
  throw TestFailure('No finder matched any expected widget.');
}

void _expectTileIconAndActionCenteredWithReadableText(
  WidgetTester tester, {
  required Finder title,
  required Finder subtitle,
  required Finder icon,
  required Finder action,
}) {
  final titleRect = tester.getRect(title);
  final subtitleRect = tester.getRect(subtitle);
  final iconRect = tester.getRect(icon);
  final actionRect = tester.getRect(action);
  final textCenterDy = _textBlockCenterDy(titleRect, subtitleRect);

  expect((iconRect.center.dy - textCenterDy).abs(), lessThan(5));
  expect(actionRect.top, greaterThan(subtitleRect.bottom));
  expect(subtitleRect.top, greaterThan(titleRect.bottom));
  expect(actionRect.left, greaterThan(titleRect.left));
}

void _expectExpansionHeaderAligned(
  WidgetTester tester, {
  required Finder header,
  required Finder icon,
  required Finder title,
  required Finder subtitle,
  required Finder action,
}) {
  final headerRect = tester.getRect(header);
  final iconRect = tester.getRect(icon);
  final titleRect = tester.getRect(title);
  final subtitleRect = tester.getRect(subtitle);
  final actionRect = tester.getRect(action);
  final textCenterDy = _textBlockCenterDy(titleRect, subtitleRect);

  expect(headerRect.height, greaterThan(iconRect.height));
  expect((iconRect.center.dy - textCenterDy).abs(), lessThan(4));
  expect((actionRect.center.dy - textCenterDy).abs(), lessThan(5));
  expect(subtitleRect.top, greaterThan(titleRect.bottom));
  expect(actionRect.left, greaterThan(titleRect.left));
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
