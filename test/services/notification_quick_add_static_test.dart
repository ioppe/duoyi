import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Android 通知栏快捷添加接入偏好、常驻通知和智能待办创建', () {
    final preferences = File(
      'lib/providers/preferences_provider.dart',
    ).readAsStringSync();
    final localNotifications = File(
      'lib/services/local_notifications_io.dart',
    ).readAsStringSync();
    final localNotificationsStub = File(
      'lib/services/local_notifications_stub.dart',
    ).readAsStringSync();
    final notificationSettingsScreen = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();
    final preferencesScreen = File(
      'lib/screens/preferences_screen.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final deepLinkService = File(
      'lib/services/deep_link_service.dart',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();
    final i18n = File('lib/core/i18n.dart').readAsStringSync();
    final zhArb = File('lib/l10n/app_zh.arb').readAsStringSync();
    final enArb = File('lib/l10n/app_en.arb').readAsStringSync();
    final requirement = File('docs/requirement-v2.md').readAsStringSync();

    expect(preferences, contains("_kNotificationQuickAdd"));
    expect(preferences, contains("pref_notification_quick_add"));
    expect(preferences, contains("bool get notificationQuickAdd"));
    expect(preferences, contains("setNotificationQuickAdd"));
    expect(
      preferences,
      contains("_notificationQuickAdd = p.getBool(_kNotificationQuickAdd)"),
    );

    expect(localNotifications, contains("quickAddChannelId"));
    expect(localNotifications, contains("duoyi_quick_add_ongoing_v2"));
    expect(localNotifications, contains("_quickAddLegacyChannelIds"));
    expect(localNotifications, contains("duoyi_quick_add_ongoing_v1"));
    expect(
      localNotifications,
      contains("await android?.deleteNotificationChannel(channelId);"),
      reason: '旧常驻通知渠道可能被系统或用户改成有声，升级时必须清理。',
    );
    expect(localNotifications, contains("quickAddNotificationId = 880016"));
    expect(localNotifications, contains('reservedNotificationIds = <int>{'));
    for (final id in <int>[
      880016,
      880017,
      880018,
      880019,
      880020,
      880021,
      880022,
      880023,
      919001,
      919003,
      919004,
    ]) {
      expect(localNotifications, contains('$id'));
    }
    expect(
      localNotifications,
      contains('NativeReminderRingtone.previewNotificationId'),
    );
    expect(localNotifications, contains("showQuickAddOngoing"));
    expect(
      localNotifications,
      contains("String? _lastQuickAddOngoingSignature"),
    );
    expect(
      localNotifications,
      contains(
        "if (!force && _lastQuickAddOngoingSignature == signature) return;",
      ),
      reason: '设置页立即同步和 main 延迟同步内容相同时不能重复刷新常驻通知，但手动同步需要可强制刷新以修复状态不一致。',
    );
    expect(
      localNotifications,
      contains("_lastQuickAddOngoingSignature = null"),
      reason: '关闭通知栏入口后必须清空去重签名，重新开启才能恢复展示。',
    );
    expect(localNotifications, contains("Future<void>? _initFuture"));
    expect(localNotifications, contains("final inFlight = _initFuture"));
    expect(localNotifications, contains("await inFlight"));
    expect(localNotifications, contains("Future<void> _initLocked()"));
    expect(
      localNotifications,
      contains("_initFuture = null"),
      reason: '首次并发初始化必须复用同一个 Future，避免重复注册插件回调和通知渠道。',
    );
    expect(localNotifications, contains("ongoing: true"));
    expect(localNotifications, contains("autoCancel: false"));
    expect(localNotifications, contains("BigTextStyleInformation("));
    expect(localNotifications, contains("playSound: false"));
    expect(localNotifications, contains("enableVibration: false"));
    expect(localNotifications, contains("silent: true"));
    expect(localNotifications, contains("onlyAlertOnce: true"));
    expect(localNotifications, contains("AndroidNotificationAction("));
    expect(localNotifications, contains("enableQuickActions"));
    expect(localNotifications, contains("actions: enableQuickActions"));
    expect(localNotifications, contains("'quick_todo'"));
    expect(localNotifications, contains("AndroidNotificationActionInput"));
    expect(localNotifications, contains("'quick_focus'"));
    expect(localNotifications, contains("duoyi://action/quick_todo'"));
    expect(localNotifications, contains("Uri.encodeComponent(text)"));
    expect(localNotifications, contains("duoyi://action/start_pomodoro"));
    expect(localNotifications, contains("'duoyi://tab/todo'"));
    expect(localNotificationsStub, contains("showQuickAddOngoing"));
    expect(localNotificationsStub, contains("bool enableQuickActions = true"));
    expect(localNotificationsStub, contains("quickAddNotificationId = 880016"));
    expect(
      localNotificationsStub,
      contains('reservedNotificationIds = <int>{'),
    );

    expect(notificationSettingsScreen, contains("prefs.notificationQuickAdd"));
    expect(notificationSettingsScreen, contains("PlatformInfo.isAndroid"));
    expect(
      notificationSettingsScreen,
      contains("preferences.notification_status_bar.unsupported"),
    );
    expect(
      notificationSettingsScreen,
      contains("preferences.notification_quick_add.title"),
    );
    expect(notificationSettingsScreen, contains("setNotificationQuickAdd"));
    expect(
      notificationSettingsScreen,
      contains("_setNotificationStatusBarPreference"),
    );
    expect(
      notificationSettingsScreen,
      contains("_syncNotificationStatusBarNow"),
    );
    expect(
      notificationSettingsScreen,
      contains("preferences.notification_status_bar.sync_failed"),
    );
    expect(notificationSettingsScreen, contains("markReadOnOpen: false"));
    expect(preferencesScreen, isNot(contains("p.notificationQuickAdd")));
    expect(preferencesScreen, isNot(contains("setNotificationQuickAdd")));

    expect(main, contains("_syncNotificationQuickAdd"));
    expect(
      main,
      contains("import 'services/notification_status_bar_service.dart';"),
    );
    expect(main, contains("Future<bool> syncNotificationQuickAdd({"));
    expect(main, contains("bool requestIfNeeded = false"));
    expect(main, contains("Future<bool> syncNotificationQuickAddDeduped({"));
    expect(main, contains("bool force = false"));
    expect(main, contains("_syncNotificationQuickAddDedupedCallback"));
    expect(main, contains("void queueNotificationQuickAddSync({"));
    expect(main, contains("bool allowBeforeDeferredHydration = false"));
    expect(main, contains("var notificationQuickAddSyncInFlight = false"));
    expect(main, contains("var notificationQuickAddSyncQueued = false"));
    expect(
      main,
      contains("Completer<bool>? notificationQuickAddSyncQueuedCompleter"),
    );
    expect(main, contains("var lastNotificationQuickAddSignature = ''"));
    expect(main, contains("return completer.future"));
    expect(
      main,
      contains("final completedSignature = notificationQuickAddSignature()"),
    );
    expect(
      main,
      contains("lastNotificationQuickAddSignature = completedSignature"),
    );
    expect(main, contains("queuedCompleter.complete(queuedSynced)"));
    expect(
      main,
      contains(
        "preferencesProvider.addListener(queueNotificationQuickAddSync)",
      ),
    );
    expect(
      main,
      contains("todoProvider.addListener(queueNotificationProgressSync)"),
    );
    expect(
      main,
      contains("habitProvider.addListener(queueNotificationProgressSync)"),
    );
    expect(
      main,
      contains("goalProvider.addListener(queueNotificationProgressSync)"),
    );
    expect(main, contains('Future<void> runPostFrameStartupTasks()'));
    expect(main, contains('syncNotificationStatusBarOnStartup'));
    expect(main, contains('_notificationStatusBarStartupBuildKey'));
    expect(main, contains('lastBuild != AppVersion.build'));
    expect(main, contains('String notificationQuickAddSignature()'));
    expect(
      main,
      contains('lastNotificationQuickAddSignature = completedSignature;'),
      reason: '常驻通知同步成功后记录签名，避免随后 resume/data-change 重复刷新同内容通知。',
    );
    expect(
      main,
      contains(
        'lastNotificationQuickAddFailureSignature = completedSignature;',
      ),
      reason: '同步失败时记录失败签名，配合退避避免 30 秒后进入高频重试卡顿。',
    );
    expect(
      main,
      contains('const Duration(seconds: 45)'),
      reason: '通知栏同步失败后必须退避，不能持续重试拖慢页面。',
    );
    expect(main, contains("LocalNotifications.instance.showQuickAddOngoing"));
    expect(main, contains("buildNotificationStatusBarPlan("));
    expect(main, contains("notificationQuickAdd: prefs.notificationQuickAdd"));
    expect(main, contains("notificationTodayProgress: todayProgress"));
    expect(main, contains("enableQuickActions: plan.enableQuickActions"));
    expect(main, contains("LocalNotifications.instance.cancelQuickAddOngoing"));
    expect(main, isNot(contains("LocalNotifications.quickAddNotificationId")));
    expect(main, contains("Timer? notificationProgressMidnightTimer"));
    expect(main, contains("scheduleNotificationProgressMidnightRefresh"));
    expect(main, contains("_refreshNotificationProgressOnResume"));
    expect(
      main,
      contains("_syncNotificationQuickAddDedupedCallback?.call(force: true)"),
      reason: 'App 回到前台刷新今日进展时复用同一入口，并强制修正可能不一致的常驻通知状态。',
    );
    expect(main, contains("_durationUntilNextLocalDay"));
    expect(
      main,
      contains('CompletionVisibilityPolicy.shouldShowInToday(todo, now)'),
      reason: '通知栏今日任务进展必须复用今日待办可见规则，避免漏掉今日实例或归档状态口径不一致。',
    );
    expect(
      main,
      contains('habit.activeForDate(now)'),
      reason: '通知栏今日任务进展中的“日常”只应统计今天还没完成的习惯，避免打卡后摘要不刷新。',
    );
    expect(main, contains('!habit.isCompletedForDate(now)'));
    expect(main, contains('formatNotificationTodayProgressBody('));
    expect(main, contains("uri.queryParameters['text']"));
    expect(main, contains("SmartTodoDraftBuilder.fromText(text)"));
    expect(main, contains("SmartTodoDraftBuilder.fromText(text)"));
    expect(main, contains("draft.toTodo()"));
    expect(main, contains(".addTodo(todo)"));
    expect(main, contains("action == 'quick_todo'"));
    expect(main, contains("action == 'start_pomodoro'"));
    expect(main, contains('DeepLinkService.takeInitialLink()'));
    expect(main, contains('var reminderResyncInFlight = false'));
    expect(main, contains('var reminderResyncQueued = false'));
    expect(main, contains('if (reminderResyncInFlight)'));
    expect(main, contains('reminderResyncQueued = true'));
    expect(main, contains('reminderResyncInFlight = false'));
    expect(main, contains('Future<void> queueFullReminderResync({'));
    expect(main, contains('Timer? reminderResyncDebounce'));
    expect(main, contains('_queueFullReminderResyncCallback'));
    expect(
      main,
      contains("reason: 'post-frame startup'"),
      reason: '启动阶段提醒重放必须走合并队列，避免和登录/云同步回写连续重复注册。',
    );
    expect(main, contains('task().timeout(timeout)'));
    expect(main, contains('timed out after'));
    expect(main, contains('bool calendarSyncDue()'));
    expect(
      main,
      contains('const minStartupSyncInterval = Duration(minutes: 30)'),
    );
    final startupTasks = main.substring(
      main.indexOf('Future<void> runPostFrameStartupTasks() async'),
      main.indexOf('// 首屏关键配置已完成'),
    );
    expect(
      startupTasks,
      isNot(contains('Duration(seconds: 30)')),
      reason: '用户反馈进入 App 约 30 秒后持续卡顿，启动期重任务不能集中在 30 秒附近触发。',
    );
    expect(main, contains('achievementProvider.resumeUnlockFeedback'));
    for (final delayed in const [65, 75, 90, 110]) {
      expect(
        main,
        contains('Duration(seconds: $delayed)'),
        reason: '启动后平台服务、通知恢复与日历同步需要错峰，避免 30 秒附近形成持续卡顿。',
      );
    }
    expect(
      startupTasks,
      contains("reason: 'initial post-frame startup'"),
      reason: '轻量后端配置刷新与按需云同步应由首帧入口触发。',
    );
    expect(startupTasks, contains('delay: Duration.zero'));
    expect(
      startupTasks,
      isNot(contains('Duration(seconds: 120)')),
      reason: '首次配置刷新不能再随平台重任务延迟 120 秒。',
    );
    expect(deepLinkService, contains('takeInitialLink'));
    expect(deepLinkService, contains('_isDuoyiDeepLink(uri)'));
    expect(mainActivity, contains('pendingInitialDeepLink'));
    expect(mainActivity, contains('duoyiDeepLinkFrom(intent)'));
    expect(mainActivity, contains('"takeInitialLink"'));
    expect(mainActivity, contains('channel.invokeMethod("onLink", deepLink)'));

    for (final key in const [
      'preferences.notification_quick_add.title',
      'preferences.notification_quick_add.subtitle',
    ]) {
      expect(i18n, contains("'$key'"), reason: key);
    }
    for (final arbKey in const [
      'preferencesNotificationQuickAddTitle',
      'preferencesNotificationQuickAddSubtitle',
    ]) {
      expect(zhArb, contains('"$arbKey"'), reason: arbKey);
      expect(enArb, contains('"$arbKey"'), reason: arbKey);
    }

    expect(requirement, contains("R16.1 Android 通知栏常驻快捷入口"));
    expect(requirement, contains("**[已实现 Android 基础]**"));
  });

  test('待办通知 action 在一次性和重复提醒中都保留 payload', () {
    final localNotifications = File(
      'lib/services/local_notifications_io.dart',
    ).readAsStringSync();

    expect(
      localNotifications,
      contains('List<AndroidNotificationAction>? _todoActionsFor'),
    );
    expect(localNotifications, contains('Uri.encodeComponent('));
    expect(
      localNotifications,
      contains("actionId.startsWith('todo_complete_')"),
    );
    expect(localNotifications, contains("actionId.startsWith('todo_snooze_')"));
    expect(localNotifications, contains('resp.payload ??'));
    expect(
      localNotifications,
      contains("'?delay=5&payload=\${Uri.encodeComponent(originalPayload)}'"),
    );

    final scheduleDailyStart = localNotifications.indexOf(
      'Future<void> scheduleDaily({',
    );
    final scheduleDailyEnd = localNotifications.indexOf(
      'Future<void> _scheduleRepeating({',
      scheduleDailyStart,
    );
    expect(scheduleDailyStart, greaterThanOrEqualTo(0));
    expect(scheduleDailyEnd, greaterThan(scheduleDailyStart));
    final scheduleDaily = localNotifications.substring(
      scheduleDailyStart,
      scheduleDailyEnd,
    );

    expect(scheduleDaily, contains('androidActions: _todoActionsFor(payload)'));
  });

  test('通知栏今日任务进展开启、降级和关闭路径保持明确', () {
    final main = File('lib/main.dart').readAsStringSync();
    final preferences = File(
      'lib/providers/preferences_provider.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();
    final service = File(
      'lib/services/notification_status_bar_service.dart',
    ).readAsStringSync();

    expect(preferences, contains("_kNotificationTodayProgress"));
    expect(preferences, contains("pref_notification_today_progress"));
    expect(preferences, contains("bool get notificationTodayProgress"));
    expect(preferences, contains("setNotificationTodayProgress"));
    expect(screen, contains("preferences.notification_today_progress.title"));
    expect(screen, contains("_setNotificationStatusBarPreference"));
    expect(screen, contains("quickAdd: false"));
    expect(screen, contains("setNotificationTodayProgress(value)"));
    expect(
      screen,
      contains('NotificationStatusBarSyncBridge.sync(\n        force: true,'),
    );
    expect(
      screen,
      contains('requestIfNeeded: requestIfNeeded'),
      reason: '开启今日进展时必须允许同步层请求通知权限，避免 UI 假成功但通知未出现。',
    );
    expect(
      screen,
      isNot(contains('LocalNotifications.instance.showQuickAddOngoing')),
    );

    final syncStart = main.indexOf('Future<bool> _syncNotificationQuickAdd(');
    final syncEnd = main.indexOf(
      'Duration _durationUntilNextLocalDay()',
      syncStart,
    );
    expect(syncStart, greaterThanOrEqualTo(0));
    expect(syncEnd, greaterThan(syncStart));
    final syncMethod = main.substring(syncStart, syncEnd);
    final dedupeStart = main.indexOf(
      'Future<bool> syncNotificationQuickAddDeduped({',
    );
    final dedupeEnd = main.indexOf(
      'Timer? notificationProgressMidnightTimer',
      dedupeStart,
    );
    expect(dedupeStart, greaterThanOrEqualTo(0));
    expect(dedupeEnd, greaterThan(dedupeStart));
    final dedupeMethod = main.substring(dedupeStart, dedupeEnd);

    expect(syncMethod, contains('if (plan.shouldShow)'));
    expect(syncMethod, contains('return true;'));
    expect(syncMethod, contains('return false;'));
    expect(dedupeMethod, contains('var synced = false;'));
    expect(
      dedupeMethod,
      contains(
        'synced = await syncNotificationQuickAdd(\n        requestIfNeeded: requestIfNeeded,',
      ),
    );
    expect(dedupeMethod, contains('force: force,'));
    expect(dedupeMethod, contains('if (synced) {'));
    expect(
      dedupeMethod,
      contains('lastNotificationQuickAddSignature = completedSignature;'),
    );
    expect(
      syncMethod,
      contains('buildNotificationStatusBarPlan('),
      reason: '通知栏常驻通知显示、降级和取消决策必须走可行为测试的 helper。',
    );
    expect(
      service,
      contains("I18n.tr('notification.status_bar.today_progress_title')"),
      reason: '仅进展开启时通知标题不能仍显示快捷记录。',
    );
    expect(
      service,
      contains("I18n.tr('notification.quick_add.title')"),
      reason: '关闭进展但快捷添加仍开启时应降级为快捷记录常驻通知。',
    );
    expect(
      syncMethod,
      contains('enableQuickActions: plan.enableQuickActions'),
      reason: '仅今日任务进展开启时不应暴露快捷操作按钮。',
    );
    expect(service, contains('NotificationStatusBarPlan.cancel()'));
    expect(
      service,
      contains('!notificationQuickAdd && !notificationTodayProgress'),
    );
    expect(service, contains("notification.status_bar.quick_hint"));
    expect(
      syncMethod,
      contains('LocalNotifications.instance.cancelQuickAddOngoing'),
    );
    expect(
      syncMethod,
      isNot(contains('LocalNotifications.quickAddNotificationId')),
    );
    expect(
      syncMethod.indexOf('LocalNotifications.instance.cancelQuickAddOngoing'),
      greaterThan(syncMethod.indexOf('} else {')),
      reason: '两个通知栏开关都关闭时必须显式取消 ongoing 通知。',
    );
  });

  test('每日提醒支持通知、弹窗、闹钟三种方式、关闭并清理旧通道', () {
    final main = File('lib/main.dart').readAsStringSync();
    final preferences = File(
      'lib/providers/preferences_provider.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();

    expect(preferences, contains('final ReminderKind kind;'));
    expect(preferences, contains("_kDailyReminderKind"));
    expect(preferences, contains('DailyReminderSlot.parseKind'));
    expect(preferences, contains("ReminderKind.off => ReminderKind.off"));

    expect(screen, contains("preferences.daily_reminder.kind.title"));
    expect(screen, contains('class _ReminderKindSelector'));
    expect(screen, contains('value: ReminderKind.push'));
    expect(screen, contains('value: ReminderKind.popup'));
    expect(screen, contains('value: ReminderKind.alarm'));
    expect(screen, contains('value: ReminderKind.off'));
    expect(screen, contains('enabled: kind != ReminderKind.off'));
    expect(screen, contains('preferences.daily_reminder.kind.off.description'));
    final kindTile = screen.substring(
      screen.indexOf('class _ReminderKindSettingsTile'),
      screen.indexOf('class _ReminderKindOptionButton'),
    );
    expect(kindTile, contains('const SizedBox(height: 10)'));
    expect(
      kindTile.indexOf('preferences.daily_reminder.kind.title'),
      lessThan(kindTile.indexOf('_ReminderKindSelector(')),
    );
    final kindSelector = screen.substring(
      screen.indexOf('class _ReminderKindSelector'),
      screen.indexOf('class _ReminderKindOptionSpec'),
    );
    expect(kindSelector, contains('ConstrainedBox('));
    expect(kindSelector, contains('minHeight: 42'));
    final kindButton = screen.substring(
      screen.indexOf('class _ReminderKindOptionButton'),
      screen.indexOf('Color _reminderKindForeground'),
    );
    expect(kindButton, isNot(contains('FittedBox(')));
    expect(kindButton, contains('labelMedium'));

    expect(main, contains('Future<void> _scheduleDailyDigestRepeating({'));
    expect(main, contains('Future<void> _scheduleDailyDigestOnce({'));
    expect(
      main,
      contains(
        'Future<void> _dailyDigestReminderSyncQueue = Future<void>.value();',
      ),
    );
    expect(
      main,
      contains('Future<void> _runDailyDigestReminderSyncSerialized'),
      reason: '每日提醒可能由偏好监听和生命周期恢复同时触发，必须串行避免跨通道重复注册。',
    );
    expect(main, contains('_syncDailyDigestReminderLocked('));
    expect(
      main,
      contains(
        '_dailyDigestReminderSyncQueue = run.then<void>((_) {}, onError: (_) {});',
      ),
    );
    expect(main, contains('_reminderScheduler.popup.scheduleRepeating'));
    expect(main, contains('_reminderScheduler.popup.scheduleOnce'));
    expect(main, contains('_reminderScheduler.alarm.scheduleDailyFullScreen'));
    expect(main, contains('_reminderScheduler.alarm.scheduleFullScreen'));
    expect(main, contains('Future<void> schedulePushFallback()'));
    expect(main, contains('popup schedule failed, fallback to push'));
    expect(main, contains('alarm schedule failed, fallback to push'));
    expect(main, contains('popup one-shot failed, fallback to push'));
    expect(main, contains('alarm one-shot failed, fallback to push'));
    expect(main, contains('_dailyDigestAlarmQueueAlreadyOwns('));
    expect(main, contains('ReminderPendingSink'));
    expect(main, contains('alarm queue already registered'));
    expect(main, contains('Set<int> _dailyDigestExpectedAlarmIds'));
    expect(main, contains('int _dailyDigestSubId'));
    expect(main, contains('on AlarmQueueHandoffException catch (e)'));
    expect(main, contains('skip push fallback to avoid duplicate delivery'));
    expect(main, contains('Future<bool> _cancelDailyDigestReminderIds'));
    expect(
      main,
      contains('effectiveDailyReminderScheduleSlots('),
      reason: '多个每日提醒槽位如果同一时间重复开启，只能调度一次，避免到点弹两条。',
    );
    expect(preferences, contains('class DailyReminderScheduleSlot'));
    expect(preferences, contains('claimedDaysByWallClock'));
    expect(
      main,
      contains('final cancelled = await _cancelDailyDigestReminderIds('),
    );
    expect(main, contains('skip scheduling to avoid duplicate delivery'));
    expect(main, contains('Future<bool> _cancelDailyDigestChannelId'));
    expect(main, contains('Future<void> cancelSafely('));
    expect(main, contains("cancelSafely('notification'"));
    expect(main, contains("cancelSafely('alarm'"));
    expect(main, contains("cancelSafely('popup'"));
    expect(main, contains('_reminderScheduler.alarm.cancel(id)'));
    expect(main, contains('_reminderScheduler.popup.cancel(id)'));
  });

  test('普通提醒 id 会避开通知栏常驻通知 id', () {
    final notification = File(
      'lib/providers/notification_service.dart',
    ).readAsStringSync();
    final scheduler = File(
      'lib/services/reminder_scheduler.dart',
    ).readAsStringSync();

    expect(
      notification,
      contains('LocalNotifications.reservedNotificationIds'),
    );
    expect(notification, contains('_avoidReservedNotificationId'));
    expect(scheduler, contains('_avoidReservedNotificationId'));
    expect(scheduler, contains('_reservedNotificationIds.contains(next)'));
    for (final id in <int>[
      880016,
      880017,
      880018,
      880019,
      880020,
      880021,
      880022,
      880023,
      919001,
      919002,
      919003,
      919004,
      919005,
      919006,
      919007,
    ]) {
      expect(scheduler, contains('$id'));
    }
  });

  test('每日提醒闹钟兜底前确认 pending，避免重复弹出', () {
    final main = File('lib/main.dart').readAsStringSync();

    final repeatingStart = main.indexOf(
      'Future<void> _scheduleDailyDigestRepeating({',
    );
    final holidayStart = main.indexOf(
      'Future<void> _scheduleHolidayAwareDailyDigest({',
      repeatingStart,
    );
    expect(repeatingStart, greaterThanOrEqualTo(0));
    expect(holidayStart, greaterThan(repeatingStart));
    final repeating = main.substring(repeatingStart, holidayStart);
    expect(
      repeating,
      contains('_reminderScheduler.alarm.scheduleDailyFullScreen'),
    );
    final repeatingAlarmStart = repeating.indexOf('case ReminderKind.alarm:');
    expect(repeatingAlarmStart, greaterThanOrEqualTo(0));
    final repeatingAlarmBranch = repeating.substring(repeatingAlarmStart);
    expect(
      repeatingAlarmBranch,
      contains('_dailyDigestAlarmQueueAlreadyOwns('),
    );
    expect(
      repeatingAlarmBranch.indexOf('_dailyDigestAlarmQueueAlreadyOwns('),
      lessThan(repeatingAlarmBranch.indexOf('await schedulePushFallback();')),
      reason: '重复闹钟失败后必须先确认原生队列未接管，再允许普通通知兜底。',
    );
    expect(
      repeating,
      contains('return;'),
      reason: '原生闹钟已入队时必须直接返回，不能继续注册 push 造成两条。',
    );

    final onceStart = main.indexOf('Future<void> _scheduleDailyDigestOnce({');
    final pendingStart = main.indexOf(
      'Future<bool> _dailyDigestAlarmQueueAlreadyOwns({',
      onceStart,
    );
    expect(onceStart, greaterThanOrEqualTo(0));
    expect(pendingStart, greaterThan(onceStart));
    final once = main.substring(onceStart, pendingStart);
    expect(once, contains('_reminderScheduler.alarm.scheduleFullScreen'));
    final onceAlarmStart = once.indexOf('case ReminderKind.alarm:');
    expect(onceAlarmStart, greaterThanOrEqualTo(0));
    final onceAlarmBranch = once.substring(onceAlarmStart);
    expect(onceAlarmBranch, contains('_dailyDigestAlarmQueueAlreadyOwns('));
    expect(
      onceAlarmBranch.indexOf('_dailyDigestAlarmQueueAlreadyOwns('),
      lessThan(onceAlarmBranch.indexOf('await schedulePushFallback();')),
      reason: '一次性闹钟失败后必须先确认原生队列未接管，再允许普通通知兜底。',
    );
    expect(
      once,
      contains('return;'),
      reason: '一次性原生闹钟已入队时必须直接返回，不能继续注册 push 造成两条。',
    );

    final pendingEnd = main.indexOf(
      'Set<int> _dailyDigestExpectedAlarmIds',
      pendingStart,
    );
    expect(pendingEnd, greaterThan(pendingStart));
    final pendingHelper = main.substring(pendingStart, pendingEnd);
    expect(
      pendingHelper,
      contains('if (alarm is! ReminderPendingSink) return false;'),
    );
    expect(
      pendingHelper,
      contains('final actual = (await pendingAlarm.pendingIds()).toSet();'),
    );
    expect(pendingHelper, contains('acceptedSets.any('));
    expect(pendingHelper, contains('actual.containsAll(ids)'));
    expect(
      pendingHelper,
      contains('return true;'),
      reason: 'pending 查询失败时宁可跳过 push fallback，也不能冒险双弹。',
    );
    expect(
      pendingHelper,
      contains(
        'pending probe failed; skip push fallback to avoid duplicate delivery',
      ),
    );
  });
}
