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
        reason: 'todo 之外的重模块本地存储仍在首帧后错峰补载，不能和首屏渲染立即抢资源。',
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
      expect(main, isNot(contains('delay: const Duration(seconds: 120)')));
      final startupTasks = main.substring(
        main.indexOf('Future<void> runPostFrameStartupTasks() async'),
        main.indexOf('// 首屏关键配置已完成'),
      );
      expect(startupTasks, contains("reason: 'initial post-frame startup'"));
      expect(startupTasks, contains('delay: Duration.zero'));
      expect(
        startupTasks.indexOf("reason: 'initial post-frame startup'"),
        lessThan(startupTasks.indexOf('const Duration(seconds: 14)')),
        reason: '公开配置与首次同步应在首帧后启动，不依赖延迟的数据补载。',
      );

      // 回归：todo 首帧后独立轻量水合，不再排进 14s 的重模块存储批次。
      expect(startupTasks, contains("'initial todo storage'"));
      expect(
        RegExp(
          r"unawaited\(\s*_startupGuard\(\s*'initial todo storage',",
        ).hasMatch(startupTasks),
        isTrue,
        reason: 'todo 首帧后水合是独立轻量任务，不能在首次公开配置与同步前被 await。',
      );
      expect(
        RegExp(
          r"_startupGuard\(\s*'initial todo storage',\s*\(\) =>\s*"
          r'cloudSyncProvider\.suppressDirtyMarkWhile\(\s*\(\) =>\s*'
          r'todoProvider\.loadFromStorage\(\)',
        ).hasMatch(startupTasks),
        isTrue,
        reason: '脏标记抑制必须包住真实读取的整个生命周期，守卫超时只结束观察。',
      );
      final initialTodoHydrationIndex = startupTasks.indexOf(
        "'initial todo storage'",
      );
      final suppressDirtyMarkIndex = startupTasks.indexOf(
        'suppressDirtyMarkWhile',
      );
      final initialTodoLoadIndex = startupTasks.indexOf(
        '() => todoProvider.loadFromStorage()',
      );
      expect(
        initialTodoHydrationIndex,
        lessThan(suppressDirtyMarkIndex),
        reason: '先进入守卫再进入抑制，保证读取全程处于抑制范围内。',
      );
      expect(
        suppressDirtyMarkIndex,
        lessThan(initialTodoLoadIndex),
        reason: '抑制必须包裹真实的 todo 存储读取入口。',
      );
      final heavyStorageDelayIndex = startupTasks.indexOf(
        'const Duration(seconds: 14)',
      );
      final deferredStorageCallIndex = startupTasks.indexOf(
        'await ensureDeferredLocalStorageStartup();',
      );
      expect(initialTodoHydrationIndex, greaterThanOrEqualTo(0));
      expect(
        initialTodoHydrationIndex,
        lessThan(startupTasks.indexOf("reason: 'initial post-frame startup'")),
        reason: 'todo 水合须在首次公开配置与同步入口之前启动。',
      );
      expect(
        initialTodoHydrationIndex,
        lessThan(heavyStorageDelayIndex),
        reason: 'todo 不再等 14s 重模块批次，升级后首帧即可看到任务。',
      );
      expect(
        heavyStorageDelayIndex,
        lessThan(deferredStorageCallIndex),
        reason: '其余 17 个 provider 的重模块读取仍在 14s 后错峰，不能被一并提前。',
      );
      expect(
        RegExp("'initial todo storage'").allMatches(main).length,
        1,
        reason: 'todo 首帧水合只能有一个启动点，不能在别处重复触发。',
      );
      expect(
        main.indexOf("'initial todo storage'"),
        greaterThan(
          main.indexOf('Future<void> runPostFrameStartupTasks() async'),
        ),
        reason: 'todo 水合只能在首帧后的 runPostFrameStartupTasks 内触发。',
      );
      expect(
        main,
        isNot(contains('await todoProvider.loadFromStorage()')),
        reason: '启动路径不得 await 阻塞 todo 读取，runApp 前更不能同步等待。',
      );
      expect(main, contains('unawaited(runPostFrameStartupTasks())'));
      expect(
        main.indexOf('unawaited(runPostFrameStartupTasks())'),
        greaterThan(main.indexOf('runApp(')),
        reason: '启动任务必须在 runApp 之后的 post-frame 回调里才启动。',
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
