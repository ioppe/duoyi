import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'startup keeps heavy reload sync notification and widget work staggered',
    () {
      final main = File('lib/main.dart').readAsStringSync();

      expect(main, contains('Future<void> _runStartupIdleQueue('));
      expect(main, contains('Future<void> _runStartupStaggeredTask('));
      expect(main, contains('Future<void> _runSyncReloadTasksInBatches('));
      expect(
        main,
        isNot(contains('Future<void> ensureNotificationLaunchStartup()')),
        reason: '启动阶段不能再完整初始化通知和闹钟渠道，避免冷启动抢首屏。',
      );
      expect(
        main,
        isNot(contains('unawaited(ensureNotificationLaunchStartup())')),
      );
      expect(
        main,
        contains('LocalNotifications.instance.initForLaunchPayload()'),
      );
      expect(main, contains('AlarmService.instance.initForLaunchPayload()'));
      expect(main, contains('Future<void> ensureHomeWidgetLaunchStartup()'));
      expect(main, contains('await _yieldForNextFrame();'));
      expect(main, contains("'deferred local storage'"));
      expect(main, contains("'deferred platform services'"));
      expect(main, contains("'startup notification launch payloads'"));
      expect(main, contains("'startup deep links'"));
      expect(main, contains("'home widget initial launch'"));
      expect(main, contains("'server config refresh'"));
      expect(main, contains("'auth profile refresh'"));
      expect(main, contains("'notification quick add'"));
      expect(main, contains("'initial home widget push'"));
      expect(main, contains('initialDelay: const Duration(seconds: 75)'));
      expect(main, contains('gap: const Duration(seconds: 12)'));
      expect(
        main,
        contains('const Duration(seconds: 14)'),
        reason: '首帧后的延迟本地加载不能和首屏渲染立即抢资源。',
      );
      expect(main, contains('delay: const Duration(milliseconds: 2400)'));
      expect(main, contains('delay: const Duration(milliseconds: 1100)'));
      expect(main, contains('delay: const Duration(seconds: 8)'));
      expect(main, contains('delay: const Duration(seconds: 65)'));
      expect(
        main,
        contains('Future<void>.delayed(const Duration(seconds: 90)'),
      );
      expect(main, contains('delay: const Duration(seconds: 110)'));
      expect(main, contains('delay: const Duration(seconds: 120)'));
      final startupTasks = main.substring(
        main.indexOf('Future<void> runPostFrameStartupTasks() async'),
        main.indexOf('// 首屏关键配置已完成'),
      );
      expect(
        startupTasks,
        isNot(contains('Duration(seconds: 30)')),
        reason: '30 秒附近不能再启动重型同步、通知或小组件任务。',
      );
      expect(main, contains('achievementProvider.resumeUnlockFeedback'));
      expect(
        main,
        contains('debounce: const Duration(milliseconds: 2200)'),
        reason: '小组件推送保持 2200ms 合并窗口，不能在启动与连续数据变化时抢 UI。',
      );
      final homeWidgetPushScheduler = File(
        'lib/services/home_widget_push_scheduler.dart',
      ).readAsStringSync();
      expect(
        main,
        contains('final homeWidgetPushScheduler = HomeWidgetPushScheduler('),
      );
      expect(main, contains('observeLifecycle: true'));
      expect(
        homeWidgetPushScheduler,
        contains('var homeWidgetPushInFlight = false'),
      );
      expect(homeWidgetPushScheduler, contains('homeWidgetPushQueued = true'));
      expect(
        homeWidgetPushScheduler,
        contains('Duration(milliseconds: 2200)'),
        reason: '串行排程器默认合并窗口必须与 main 一致。',
      );
      expect(main, contains('var deferredLocalStorageHydrated = false'));
      expect(main, contains('deferredLocalStorageHydrated = true'));
      expect(
        main,
        contains('isReady: () => deferredLocalStorageHydrated'),
        reason: '未完成 deferred hydration 时排程器只保留 dirty，不能写空快照。',
      );
      expect(main, contains('bool allowBeforeDeferredHydration = false'));
      expect(main, contains('queueNotificationQuickAddSync();'));

      final localNotifications = File(
        'lib/services/local_notifications_io.dart',
      ).readAsStringSync();
      expect(
        localNotifications,
        contains('Future<void> initForLaunchPayload() async'),
      );
      expect(localNotifications, contains('await _ensurePluginInitialized();'));
      expect(localNotifications, contains('await _probeLaunchPayload();'));

      final alarmService = File(
        'lib/services/alarm_service.dart',
      ).readAsStringSync();
      expect(
        alarmService,
        contains('Future<void> initForLaunchPayload() async'),
      );
      expect(alarmService, contains('await _ensurePluginInitialized();'));
      expect(alarmService, contains('await _probeLaunchPayload();'));

      final background = File(
        'lib/widgets/brand_background.dart',
      ).readAsStringSync();
      expect(background, contains('LayoutBuilder('));
      expect(background, contains('MediaQuery.devicePixelRatioOf(context)'));
      expect(background, contains('cacheWidth: cacheWidth'));
      expect(background, contains('cacheHeight: cacheHeight'));

      final notificationSettings = File(
        'lib/screens/notification_history_screen.dart',
      ).readAsStringSync();
      expect(
        notificationSettings,
        contains("key: const ValueKey('notification_settings_scroll_view')"),
      );
      expect(notificationSettings, contains('CustomScrollView('));
      expect(notificationSettings, contains('SliverSafeArea('));
      expect(notificationSettings, contains('通知状态读取失败，请稍后重试或打开系统通知设置检查。'));
      expect(
        main,
        isNot(contains('_builtTabs.contains(tab) && tab == safeIndex')),
        reason: '已访问底部 tab 必须保留挂载，避免返回日历/习惯/专注时整页重建。',
      );
    },
  );
}
