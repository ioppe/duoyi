import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/app_version.dart';
import 'core/app_config.dart';
import 'core/app_clock.dart';
import 'core/app_motion.dart';
import 'core/app_text_scale.dart';
import 'core/achievements.dart';
import 'core/completion_visibility_policy.dart';
import 'core/crash_guard.dart';
import 'core/design_tokens.dart';
import 'core/desktop_tokens.dart';
import 'core/i18n.dart';
import 'core/iterable_extensions.dart';
import 'core/local_timezone_resolver.dart';
import 'core/report_engine.dart';
import 'widgets/todo_create_sheet.dart';
import 'core/smart_todo_draft.dart';
import 'core/web_target.dart';
import 'l10n/generated/app_localizations.dart';
import 'providers/todo_provider.dart';
import 'providers/habit_provider.dart';
import 'providers/pomodoro_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/cloud_sync_provider.dart';
import 'providers/sync_status_presenter.dart';
import 'providers/calendar_provider.dart';
import 'providers/user_provider.dart';
import 'providers/notification_service.dart';
import 'providers/auth_provider.dart';
import 'providers/countdown_provider.dart';
import 'providers/note_provider.dart';
import 'providers/anniversary_provider.dart';
import 'providers/diary_provider.dart';
import 'providers/goal_provider.dart';
import 'providers/course_provider.dart';
import 'providers/app_lock_provider.dart';
import 'providers/preferences_provider.dart';
import 'providers/quick_capture_template_provider.dart';
import 'providers/list_group_provider.dart';
import 'providers/time_audit_provider.dart';
import 'providers/achievement_provider.dart';
import 'providers/custom_focus_sound_provider.dart';
import 'providers/focus_room_provider.dart';
import 'providers/share_provider.dart';
import 'providers/location_reminder_provider.dart';
import 'models/goal.dart' show GoalStatus, ReminderKind;
import 'models/habit.dart' show HabitKind;
import 'models/calendar_event.dart'
    show CalendarEvent, CalendarEventType, CalendarEventTypeX;
import 'models/note.dart' show NoteItem;
import 'models/pomodoro.dart' show PomodoroType;
import 'models/todo.dart' show TodoItem, TodoPriorityX;
import 'services/alarm_service.dart';
import 'services/account_local_data_cleaner.dart';
import 'services/calendar_sync_service.dart';
import 'services/deep_link_service.dart';
import 'services/system_tray.dart';
import 'services/home_widget_service.dart';
import 'services/home_widget_action.dart';
import 'services/home_widget_action_bridge.dart';
import 'services/home_widget_push_scheduler.dart';
import 'services/ai_service.dart';
import 'services/app_update_service.dart';
import 'services/backend_reminder_email_sink.dart';
import 'services/foreground_reminder_popup_sink.dart';
import 'services/holiday_calendar.dart';
import 'services/local_notifications.dart';
import 'services/native_reminder_ringtone.dart';
import 'services/location_geofence_service.dart';
import 'services/notification_permission_exception.dart';
import 'services/notification_status_bar_sync_bridge.dart';
import 'services/notification_status_bar_service.dart';
import 'services/reminder_sinks.dart';
import 'services/reminder_ringtone_settings.dart';
import 'services/reminder_scheduler.dart';
import 'screens/today_screen.dart';
import 'screens/todo_screen.dart';
import 'screens/habit_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/countdown_screen.dart';
import 'screens/pomodoro_screen.dart';
import 'screens/widget_screen.dart';
import 'screens/mine_screen.dart';
import 'screens/integrations_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/note_screen.dart';
import 'screens/anniversary_screen.dart';
import 'screens/course_schedule_screen.dart';
import 'screens/goal_screen.dart';
import 'screens/statistics_screen.dart';
import 'screens/time_audit_screen.dart';
import 'screens/today_detail_router.dart';
import 'widgets/brand_background.dart';
import 'widgets/force_update_gate.dart';
import 'widgets/web_auth_gate.dart';
import 'widgets/todo_completion_flow.dart';
import 'widgets/surface_components.dart';
import 'widgets/keyboard_dismiss_scope.dart';

final GlobalKey<MainShellState> mainShellKey = GlobalKey<MainShellState>();
final List<Uri> _pendingWidgetUris = <Uri>[];
final Map<String, DateTime> _recentWidgetActionUris = <String, DateTime>{};
typedef _ReminderResyncQueue =
    Future<void> Function({Duration delay, String reason});

/// 模块级的提醒调度器实例。
///
/// 在 `main()` 中构造后注入到各 Provider，并被 `_DuoyiAppState` 在
/// `AppLifecycleState.resumed` 检测到时区变化时读取，用于触发提醒重放。
/// 放在顶层是因为 `_DuoyiAppState` 并不持有构造时的闭包引用。
late ReminderScheduler _reminderScheduler;
bool _reminderSchedulerReady = false;
Future<bool> Function({bool force, bool requestIfNeeded})?
_syncNotificationQuickAddDedupedCallback;
_ReminderResyncQueue? _queueFullReminderResyncCallback;
bool _initialExactAlarmGranted = false;
const int _dailyDigestHolidayWindowDays = 45;
const String _notificationStatusBarStartupBuildKey =
    'notification_status_bar_startup_build';

Future<void> _refreshReminderRingtoneChannels() async {
  try {
    await ReminderRingtoneSettings.applyPersistedSettingsToNative();
    await Future.wait([
      LocalNotifications.instance.refreshAndroidRingtoneChannels(),
      AlarmService.instance.refreshAndroidRingtoneChannel(),
    ]);
  } catch (e, st) {
    debugPrint('[ReminderRingtone] channel refresh failed: $e\n$st');
  }
}

Future<void> _startupGuard(
  String label,
  Future<void> Function() task, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  try {
    await task().timeout(timeout);
  } on TimeoutException {
    debugPrint('[startup] $label timed out after ${timeout.inSeconds}s');
  } catch (e, st) {
    debugPrint('[startup] $label failed: $e\n$st');
  }
}

Future<T?> _startupValue<T>(
  String label,
  Future<T?> Function() task, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  try {
    return await task().timeout(timeout);
  } on TimeoutException {
    debugPrint('[startup] $label timed out after ${timeout.inSeconds}s');
    return null;
  } catch (e, st) {
    debugPrint('[startup] $label failed: $e\n$st');
    return null;
  }
}

String _pomodoroPersistedSignature(PomodoroProvider provider) {
  return '${provider.persistedRevision}:${provider.sessions.length}:'
      '${provider.penalties.length}:${provider.sessionCountToday}';
}

String _achievementPersistedSignature(AchievementProvider provider) {
  return '${provider.persistedRevision}:${provider.unlockedCount}:'
      '${provider.coinBalance}:${provider.lifetimeCoins}:'
      '${provider.rewardLedger.length}';
}

String _pomodoroSessionsSignature(PomodoroProvider provider) {
  final buffer = StringBuffer()
    ..write(provider.sessions.length)
    ..write(':')
    ..write(provider.sessionCountToday)
    ..write(':')
    ..write(provider.totalFocusMinutes);
  for (final session in provider.sessions) {
    buffer
      ..write('|')
      ..write(session.id)
      ..write(',')
      ..write(session.type.index)
      ..write(',')
      ..write(session.durationSeconds)
      ..write(',')
      ..write(session.updatedAt.microsecondsSinceEpoch);
  }
  return buffer.toString();
}

String _pomodoroHomeWidgetSignature(PomodoroProvider provider) {
  final state = provider.state;
  final remaining = state.isRunning ? 'active' : state.remainingSeconds;
  return '${provider.persistedRevision}:${provider.sessionCountToday}:'
      '${state.isRunning}:${state.isCountUp}:${state.type.index}:'
      '${state.totalSeconds}:$remaining';
}

Future<void> _runSyncReloadTasksInBatches(
  List<Future<void> Function()> tasks, {
  int batchSize = 1,
}) async {
  for (var i = 0; i < tasks.length; i += batchSize) {
    final end = (i + batchSize).clamp(0, tasks.length);
    await Future.wait([for (var j = i; j < end; j++) tasks[j]()]);
    if (end < tasks.length) {
      await _yieldForNextFrame();
    }
  }
}

Future<void> _yieldForNextFrame([
  Duration delay = const Duration(milliseconds: 32),
]) {
  return Future<void>.delayed(delay);
}

Future<void> _runStartupIdleQueue(
  List<Future<void> Function()> tasks, {
  Duration initialDelay = const Duration(seconds: 12),
  Duration gap = const Duration(seconds: 4),
}) async {
  await Future<void>.delayed(initialDelay);
  for (final task in tasks) {
    await task();
    await Future<void>.delayed(gap);
  }
}

Future<void> _runStartupStaggeredTask(
  String label,
  Future<void> Function() task, {
  required Duration delay,
  Duration timeout = const Duration(seconds: 12),
}) async {
  await Future<void>.delayed(delay);
  await _startupGuard(label, task, timeout: timeout);
}

Future<void> _runStartupStoragePhase(
  String label,
  List<Future<void> Function()> tasks, {
  int batchSize = 1,
}) {
  final startedAt = DateTime.now();
  return _startupGuard(label, () async {
    await _runSyncReloadTasksInBatches(tasks, batchSize: batchSize);
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    debugPrint('[startup] $label completed in ${elapsedMs}ms');
  }, timeout: const Duration(seconds: 18));
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validate();

  // 全局未捕获异常兜底：框架/平台异常摘要落盘本地日志，绝不抛出或弹 UI。
  CrashGuard.install();

  // 首帧前初始化本地时区，保证后续 tz.TZDateTime.from(.., tz.local) 正确。
  await _startupGuard('timezone', () => LocalTimezoneResolver.init());

  final todoProvider = TodoProvider();
  final habitProvider = HabitProvider();
  final pomodoroProvider = PomodoroProvider();
  final themeProvider = ThemeProvider();
  final cloudSyncProvider = CloudSyncProvider();
  final calendarProvider = CalendarProvider();
  final userProvider = UserProvider();
  final notificationService = NotificationService();
  final systemTray = SystemTrayService();
  final authProvider = AuthProvider();
  final countdownProvider = CountdownProvider();
  final noteProvider = NoteProvider();
  final anniversaryProvider = AnniversaryProvider();
  final diaryProvider = DiaryProvider();
  final goalProvider = GoalProvider();
  final courseProvider = CourseProvider();
  final appLockProvider = AppLockProvider();
  final preferencesProvider = PreferencesProvider();
  final quickCaptureTemplateProvider = QuickCaptureTemplateProvider();
  final listGroupProvider = ListGroupProvider();
  final timeAuditProvider = TimeAuditProvider();
  final achievementProvider = AchievementProvider();
  final customFocusSoundProvider = CustomFocusSoundProvider();
  final focusRoomProvider = FocusRoomProvider();
  final shareProvider = ShareProvider();
  final localeProvider = LocaleProvider();
  final locationReminderProvider = LocationReminderProvider();
  final calendarSyncProvider = CalendarSyncProvider();
  final aiService = AiService();
  final appUpdate = AppUpdateService(
    repo: AppConfig.updateRepository,
    currentVersion: AppVersion.name,
    currentVersionCode: AppVersion.build,
    backendBaseUrlGetter: () => authProvider.baseUrl,
  );
  var cloudSyncStartSerial = 0;

  Future<void> clearAccountLocalData({required String reason}) async {
    debugPrint('[auth] clear local account data reason=$reason');
    cloudSyncStartSerial++;
    Object? criticalCleanupError;
    StackTrace? criticalCleanupStackTrace;

    void rememberCriticalFailure(Object error, StackTrace stackTrace) {
      criticalCleanupError ??= error;
      criticalCleanupStackTrace ??= stackTrace;
    }

    Future<void> guarded(
      String label,
      Future<void> Function() task, {
      bool critical = false,
    }) async {
      try {
        await task();
      } catch (e, st) {
        debugPrint('[auth] account cleanup $label failed: $e\n$st');
        if (critical) rememberCriticalFailure(e, st);
      }
    }

    void guardedSync(String label, void Function() task) {
      try {
        task();
      } catch (e, st) {
        debugPrint('[auth] account cleanup $label failed: $e\n$st');
        rememberCriticalFailure(e, st);
      }
    }

    void retryLocalFilesCleanup() {
      unawaited(() async {
        await Future<void>.delayed(const Duration(seconds: 2));
        try {
          await AccountLocalDataCleaner.clearLocalFiles();
        } catch (e, st) {
          debugPrint(
            '[auth] account cleanup local files retry failed: $e\n$st',
          );
        }
      }());
    }

    await guarded('cloud sync state', () async {
      await cloudSyncProvider.resetForAccountChange();
    }, critical: true);

    var localFilesCleaned = true;
    Future<void> clearLocalFiles() async {
      try {
        await AccountLocalDataCleaner.clearLocalFiles();
      } catch (e, st) {
        localFilesCleaned = false;
        debugPrint('[auth] account cleanup local files failed: $e\n$st');
      }
    }

    await cloudSyncProvider.suppressDirtyMarkWhile(() async {
      await guarded('notifications', notificationService.cancelAll);
      await guarded('alarms', AlarmService.instance.cancelAll);
      if (_reminderSchedulerReady) {
        await guarded(
          'reminder scheduler state',
          _reminderScheduler.resetInMemoryState,
        );
      }
      await guarded('geofences', () async {
        await LocationGeofenceService.clearReminders();
      });
      await guarded(
        'account prefs first pass',
        AccountLocalDataCleaner.clearSharedPreferences,
        critical: true,
      );
      await clearLocalFiles();

      guardedSync('todos', todoProvider.resetLocalState);
      guardedSync('habits', habitProvider.resetLocalState);
      guardedSync('pomodoro', pomodoroProvider.resetLocalState);
      guardedSync('countdowns', countdownProvider.resetLocalState);
      guardedSync('anniversaries', anniversaryProvider.resetLocalState);
      guardedSync('diary', diaryProvider.resetLocalState);
      guardedSync('goals', goalProvider.resetLocalState);
      guardedSync('courses', courseProvider.resetLocalState);
      guardedSync('notes', noteProvider.resetLocalState);
      guardedSync('calendar', calendarProvider.resetLocalState);
      guardedSync('time audit', timeAuditProvider.resetLocalState);
      guardedSync(
        'location reminders',
        locationReminderProvider.resetLocalState,
      );
      guardedSync('user', userProvider.resetLocalState);
      await guarded(
        'user profile cache',
        () => userProvider.clearAccountProfileCache(),
      );
      guardedSync('theme', themeProvider.resetLocalState);
      guardedSync('achievements', achievementProvider.resetLocalState);
      // 切号清空后，云端 `achievement_states` 尚未回填本地解锁基线。
      // 在此期间抑制成就解锁反馈，等基线恢复（或安全超时）后再放开，
      // 否则早已解锁且已读的成就会被重算成“新解锁”而重复弹窗。
      guardedSync(
        'achievements feedback suppression',
        achievementProvider.suppressUnlockFeedback,
      );
      guardedSync(
        'quick capture templates',
        quickCaptureTemplateProvider.resetLocalState,
      );
      guardedSync('list groups', listGroupProvider.resetLocalState);
      guardedSync(
        'custom focus sounds',
        customFocusSoundProvider.resetLocalState,
      );
      guardedSync('focus rooms', focusRoomProvider.resetLocalState);
      guardedSync('shares', shareProvider.resetLocalState);
      guardedSync('calendar sync', calendarSyncProvider.resetLocalState);
      guardedSync('ai service', aiService.resetLocalState);
      guardedSync('notification service', notificationService.resetLocalState);
      guardedSync('preferences', preferencesProvider.resetLocalState);
      await guarded(
        'preferences reload',
        preferencesProvider.loadFromStorage,
        critical: true,
      );
      await guarded(
        'reminder ringtone native settings',
        ReminderRingtoneSettings.applyPersistedSettingsToNative,
      );

      // Run a second pass after async platform cancellations so a stale sync
      // completion racing with cleanup cannot leave account data behind.
      await guarded(
        'account prefs second pass',
        AccountLocalDataCleaner.clearSharedPreferences,
        critical: true,
      );
      await clearLocalFiles();
    });

    if (!localFilesCleaned) retryLocalFilesCleanup();

    HomeWidgetService.resetAccountCache();
    await guarded('home widget refresh', () async {
      await HomeWidgetService.init();
      await _pushHomeWidget(
        todoProvider,
        habitProvider,
        pomodoroProvider,
        calendarProvider,
        countdownProvider,
        timeAuditProvider,
        goalProvider,
        anniversaryProvider,
        courseProvider,
        noteProvider,
        themeProvider,
      );
    });
    if (criticalCleanupError != null) {
      Error.throwWithStackTrace(
        criticalCleanupError!,
        criticalCleanupStackTrace!,
      );
    }
    // 安全兜底：即便云端基线回填未触发静默刷新（如退出登录、关闭自动同步），
    // 也要在切号窗口后恢复解锁反馈，避免开关永久卡在抑制态。
    // 捕获本轮抑制代次：若 30s 内又发生一次切号，旧定时器不会误恢复新一轮抑制。
    final suppressionGeneration =
        achievementProvider.unlockSuppressionGeneration;
    Future<void>.delayed(const Duration(seconds: 30), () {
      achievementProvider.resumeUnlockFeedback(
        generation: suppressionGeneration,
      );
    });
  }

  String firstNonEmptyProfileText(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  authProvider.onAccountProfileChanged = (state) async {
    // 登录成功/refreshMe 都走这里：先把本机字号归属到当前账号，再处理资料。
    // 必须放在 profile 相等提前 return 之前，否则同一账号重复登录不会绑定。
    if (state.isLoggedIn) {
      await preferencesProvider.bindTextScaleToAccount(
        serverUrl: authProvider.baseUrl,
        userId: state.userId,
      );
    }
    final name = firstNonEmptyProfileText([
      state.displayName,
      state.username,
      '用户',
    ]);
    final profile = userProvider.profile;
    if (profile.username == name &&
        profile.displayName == (state.displayName ?? '') &&
        profile.email == (state.email ?? '') &&
        profile.emailVerified == state.emailVerified &&
        profile.avatarUrl == (state.avatar ?? '') &&
        profile.bio == (state.bio ?? '')) {
      return;
    }
    await cloudSyncProvider.suppressDirtyMarkWhile(
      () => userProvider.applyAccountSnapshot(
        username: name,
        displayName: state.displayName ?? '',
        email: state.email ?? '',
        emailVerified: state.emailVerified,
        avatarUrl: state.avatar ?? '',
        bio: state.bio ?? '',
      ),
    );
  };
  Object? accountPayloadValue(Map<dynamic, dynamic> data, List<String> keys) {
    for (final key in keys) {
      if (data[key] != null) return data[key];
    }
    for (final wrapperKey in const ['user', 'profile', 'data', 'payload']) {
      final wrapper = data[wrapperKey];
      if (wrapper is Map) {
        final nested = accountPayloadValue(wrapper, keys);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  authProvider.onAccountPayloadChanged = (payload) async {
    final themeState = accountPayloadValue(payload, const [
      'theme_shop_state',
      'themeShopState',
    ]);
    final rewards = accountPayloadValue(payload, const [
      'virtual_rewards',
      'virtualRewards',
      'rewards',
    ]);
    if (themeState is! Map && rewards is! Map) return;
    await cloudSyncProvider.suppressDirtyMarkWhile(() async {
      if (themeState is Map) {
        await themeProvider.applyShopStateFromServer(themeState);
      }
      if (rewards is Map) {
        await achievementProvider.applyRewardsSnapshot(rewards);
      }
    });
  };
  authProvider.onAccountIdentityChanging = (_, _) =>
      clearAccountLocalData(reason: 'account switch');
  authProvider.onAccountLoggedOut = () =>
      clearAccountLocalData(reason: 'logout');

  void handleDeepLink(Uri uri) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleWidgetUri(uri, pomodoroProvider);
    });
  }

  void handleSharedText(String text) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showSharedTextImportSheet(text);
    });
  }

  DeepLinkService.onLink = handleDeepLink;
  DeepLinkService.onSharedText = handleSharedText;
  await _startupGuard('deep links', () => DeepLinkService.init());

  await cloudSyncProvider.suppressDirtyMarkWhile(
    () => _runStartupStoragePhase('critical local storage', [
      // 关键Provider必须串行加载，避免状态冲突
      () => themeProvider.loadFromStorage(),
      () => authProvider.loadFromStorage(refreshServerConfig: false),
      () => preferencesProvider.loadFromStorage(),
      // 冷启动时 auth 已还原登录态：补一次字号归属校验，避免升级/重启后
      // 已选字号被当作无主值。未登录（token 失效/退出）不绑定、不重置。
      () {
        final authState = authProvider.state;
        if (!authState.isLoggedIn) return Future<void>.value();
        return preferencesProvider.bindTextScaleToAccount(
          serverUrl: authProvider.baseUrl,
          userId: authState.userId,
        );
      },
      () => appLockProvider.loadFromStorage(),
      () => localeProvider.loadFromStorage(),
      () => userProvider.loadFromStorage(),
      () => cloudSyncProvider.loadFromStorage(),
    ]),
  );

  var deferredLocalStorageHydrated = false;
  Future<void>? deferredLocalStorageStartup;
  Future<void> ensureDeferredLocalStorageStartup() {
    final existing = deferredLocalStorageStartup;
    if (existing != null) return existing;
    deferredLocalStorageStartup = cloudSyncProvider
        .suppressDirtyMarkWhile(
          () => _runSyncReloadTasksInBatches([
            () => _startupGuard(
              'todo storage',
              () => todoProvider.loadFromStorage(),
            ),
            () => _startupGuard(
              'habit storage',
              () => habitProvider.loadFromStorage(),
            ),
            () => _startupGuard(
              'pomodoro storage',
              () => pomodoroProvider.loadFromStorage(),
            ),
            () => _startupGuard(
              'countdown storage',
              () => countdownProvider.loadFromStorage(),
            ),
            () => _startupGuard(
              'anniversary storage',
              () => anniversaryProvider.loadFromStorage(),
            ),
            () => _startupGuard(
              'diary storage',
              () => diaryProvider.loadFromStorage(),
            ),
            () => _startupGuard(
              'goal storage',
              () => goalProvider.loadFromStorage(),
            ),
            () => _startupGuard(
              'course storage',
              () => courseProvider.loadFromStorage(),
            ),
            () => _startupGuard(
              'quick capture templates storage',
              () => quickCaptureTemplateProvider.loadFromStorage(),
            ),
            () => _startupGuard(
              'list groups storage',
              () => listGroupProvider.loadFromStorage(),
            ),
            () => _startupGuard(
              'time audit storage',
              () => timeAuditProvider.loadFromStorage(),
            ),
            () => _startupGuard(
              'note storage',
              () => noteProvider.loadFromStorage(),
            ),
            () => _startupGuard(
              'achievement storage',
              () => achievementProvider.loadFromStorage(),
            ),
            () => _startupGuard(
              'custom focus sounds storage',
              () => customFocusSoundProvider.loadFromStorage(),
            ),
            () => _startupGuard(
              'focus room storage',
              () => focusRoomProvider.loadFromStorage(),
            ),
            () =>
                _startupGuard('ai storage', () => aiService.loadFromStorage()),
            () => _startupGuard(
              'location reminders storage',
              () => locationReminderProvider.loadFromStorage(),
            ),
            () => _startupGuard(
              'calendar subscriptions storage',
              () => calendarSyncProvider.loadFromStorage(),
            ),
            () => _startupGuard(
              'calendar local events',
              () => calendarProvider.loadFromStorage(),
            ),
          ]),
        )
        .whenComplete(() {
          deferredLocalStorageHydrated = true;
        });
    return deferredLocalStorageStartup!;
  }

  Future<void>? deferredPlatformStartup;

  Future<void>? homeWidgetLaunchStartup;
  Future<void> ensureHomeWidgetLaunchStartup() {
    final existing = homeWidgetLaunchStartup;
    if (existing != null) return existing;
    homeWidgetLaunchStartup = () async {
      final initialized = await HomeWidgetService.init();
      if (!initialized) {
        debugPrint('[HomeWidget] startup init completed with failures');
      }
    }();
    return homeWidgetLaunchStartup!;
  }

  Future<void> ensureDeferredPlatformStartup() {
    final existing = deferredPlatformStartup;
    if (existing != null) return existing;
    deferredPlatformStartup = () async {
      await _runSyncReloadTasksInBatches([
        () => _startupGuard('notifications', () => notificationService.init()),
        () =>
            _startupGuard('alarm service', () => AlarmService.instance.init()),
        () => _startupGuard('system tray', () => systemTray.init()),
        () => _startupGuard('home widget', ensureHomeWidgetLaunchStartup),
      ]);
      try {
        _initialExactAlarmGranted = await AlarmService.instance
            .hasExactAlarmPermission()
            .timeout(const Duration(seconds: 3));
      } catch (e, st) {
        debugPrint('[startup] exact alarm probe failed: $e\n$st');
        _initialExactAlarmGranted = false;
      }
    }();
    return deferredPlatformStartup!;
  }

  pomodoroProvider.attachNotifier(notificationService);
  pomodoroProvider.attachTimeAudit(timeAuditProvider);
  todoProvider.timeAudit = timeAuditProvider;
  habitProvider.timeAudit = timeAuditProvider;
  goalProvider.timeAudit = timeAuditProvider;
  achievementProvider.attachNotificationService(notificationService);
  shareProvider.apiClientGetter = () => authProvider.client;
  shareProvider.userIdGetter = () => authProvider.state.userId;
  focusRoomProvider.apiClientGetter = () => authProvider.client;
  // 让 PomodoroProvider 监听 AppLifecycle，以便在 resumed 时恢复白噪音。
  pomodoroProvider.attachLifecycle();

  // 提醒调度器：监听数据变化，幂等地同步本地通知队列
  final reminderScheduler = ReminderScheduler(
    notificationService,
    email: BackendReminderEmailSink(() => authProvider.client),
    popup: ForegroundReminderPopupSink(
      contextGetter: () => mainShellKey.currentContext,
      onOpenPayload: (payload) {
        final uri = Uri.tryParse(payload);
        if (uri == null) return;
        _handleWidgetUri(uri, pomodoroProvider);
      },
      notificationFallback: notificationService,
    ),
  );
  _reminderScheduler = reminderScheduler;
  _reminderSchedulerReady = true;
  // 注入到 Provider，供 Provider 内部的局部 hook（例如 postponeOverdue、
  // onTimezoneChanged）转发调度请求。
  todoProvider.scheduler = reminderScheduler;
  habitProvider.scheduler = reminderScheduler;
  anniversaryProvider.scheduler = reminderScheduler;
  countdownProvider.scheduler = reminderScheduler;
  goalProvider.scheduler = reminderScheduler;
  var reminderResyncInFlight = false;
  var reminderResyncQueued = false;
  Timer? reminderResyncDebounce;
  Completer<void>? reminderResyncDebounceCompleter;
  String reminderResyncReason = 'startup';
  var startupReminderResyncQueued = false;
  Future<void> Function()? reminderAuxiliaryResync;
  Future<void> resyncReminders() async {
    if (reminderResyncInFlight) {
      reminderResyncQueued = true;
      return;
    }
    reminderResyncInFlight = true;
    // 单条 sync 失败不应中断整轮调度（R2.8 / T-14）。
    Future<void> guarded(String label, Future<void> Function() task) async {
      try {
        await task();
      } catch (e, st) {
        debugPrint('[resyncReminders] $label failed: $e\n$st');
      }
    }

    try {
      await guarded(
        'syncTodos',
        () => reminderScheduler.syncTodos(
          todoProvider.todos,
          allowJustMissedOneShotReminders: false,
        ),
      );
      await guarded(
        'syncHabits',
        () => reminderScheduler.syncHabits(habitProvider.habits),
      );
      await guarded(
        'syncAnniversaries',
        () => reminderScheduler.syncAnniversaries(anniversaryProvider.items),
      );
      await guarded(
        'syncCountdowns',
        () => reminderScheduler.syncCountdowns(countdownProvider.items),
      );
      await guarded(
        'syncGoals',
        () => reminderScheduler.syncGoals(goalProvider.goals),
      );
      await guarded('syncAuxiliaryReminderSchedules', () async {
        final task = reminderAuxiliaryResync;
        if (task != null) await task();
      });
    } finally {
      reminderResyncInFlight = false;
    }
    if (reminderResyncQueued) {
      reminderResyncQueued = false;
      await resyncReminders();
    }
  }

  Future<void> queueFullReminderResync({
    Duration delay = const Duration(milliseconds: 350),
    String reason = 'manual',
  }) {
    reminderResyncReason = reason;
    reminderResyncDebounce?.cancel();
    final completer = reminderResyncDebounceCompleter ??= Completer<void>();
    reminderResyncDebounce = Timer(delay, () {
      reminderResyncDebounce = null;
      final pending = reminderResyncDebounceCompleter;
      reminderResyncDebounceCompleter = null;
      unawaited(() async {
        try {
          await resyncReminders();
          if (pending != null && !pending.isCompleted) pending.complete();
        } catch (e, st) {
          debugPrint(
            '[queueFullReminderResync] $reminderResyncReason failed: $e\n$st',
          );
          if (pending != null && !pending.isCompleted) {
            pending.completeError(e, st);
          }
        }
      }());
    });
    return completer.future;
  }

  Future<void> queueStartupReminderResync({
    required Duration delay,
    required String reason,
  }) {
    if (startupReminderResyncQueued) return Future<void>.value();
    startupReminderResyncQueued = true;
    return queueFullReminderResync(delay: delay, reason: reason);
  }

  _queueFullReminderResyncCallback = queueFullReminderResync;
  goalProvider.reminderResyncRequester = () => queueFullReminderResync(
    delay: Duration.zero,
    reason: 'goal timezone changed',
  );
  await notificationService.setHistoryLimit(
    preferencesProvider.notificationHistoryLimit,
  );
  preferencesProvider.onAppTimeZoneChanged = () => queueFullReminderResync(
    delay: Duration.zero,
    reason: 'app timezone changed',
  );

  Future<void> syncLocationGeofences() async {
    if (!locationReminderProvider.isLoaded) return;
    try {
      await LocationGeofenceService.syncReminders(
        locationReminderProvider.reminders,
      );
    } catch (e, st) {
      debugPrint('[location geofence] sync failed: $e\n$st');
    }
  }

  locationReminderProvider.addListener(syncLocationGeofences);

  // 本地有改动 → 交给云同步侧排队自动同步。
  void markDirty() {
    cloudSyncProvider.markPendingLocalChange();
  }

  todoProvider.addListener(markDirty);
  habitProvider.addListener(markDirty);
  anniversaryProvider.addListener(markDirty);
  countdownProvider.addListener(markDirty);
  goalProvider.addListener(markDirty);
  noteProvider.addListener(markDirty);
  diaryProvider.addListener(markDirty);
  courseProvider.addListener(markDirty);
  var lastPomodoroDirtySignature = _pomodoroPersistedSignature(
    pomodoroProvider,
  );
  void markPomodoroDirtyOnPersistedChange() {
    final next = _pomodoroPersistedSignature(pomodoroProvider);
    if (next == lastPomodoroDirtySignature) return;
    lastPomodoroDirtySignature = next;
    markDirty();
  }

  pomodoroProvider.addListener(markPomodoroDirtyOnPersistedChange);
  timeAuditProvider.addListener(markDirty);
  var lastUserProfileDirtySignature = userProvider.syncSignature();
  void markUserProfileDirtyOnEditableChange() {
    final next = userProvider.syncSignature();
    if (next == lastUserProfileDirtySignature) return;
    lastUserProfileDirtySignature = next;
    markDirty();
  }

  userProvider.addListener(markUserProfileDirtyOnEditableChange);
  locationReminderProvider.addListener(markDirty);
  var lastAchievementDirtySignature = _achievementPersistedSignature(
    achievementProvider,
  );
  void markAchievementDirtyOnPersistedChange() {
    final next = _achievementPersistedSignature(achievementProvider);
    if (next == lastAchievementDirtySignature) return;
    lastAchievementDirtySignature = next;
    if (achievementProvider.consumeServerConfirmedRewardsChange()) return;
    markDirty();
  }

  achievementProvider.addListener(markAchievementDirtyOnPersistedChange);
  focusRoomProvider.onLocalChanged = markDirty;
  themeProvider.addListener(() {
    if (themeProvider.consumeServerConfirmedChange()) return;
    markDirty();
  });
  calendarProvider.onLocalEventsChanged = markDirty;
  calendarProvider.localEventReminderCanceller =
      notificationService.cancelCalendarReminder;
  preferencesProvider.onChangedKeys = cloudSyncProvider.markPreferencesChanged;
  ReminderRingtoneSettings.onChanged = (keys) async {
    await cloudSyncProvider.markPreferencesChanged(keys);
    if (keys.contains(ReminderRingtoneSettings.soundPreferenceKey) ||
        keys.contains(ReminderRingtoneSettings.volumePreferenceKey)) {
      unawaited(() async {
        await _refreshReminderRingtoneChannels();
        await queueFullReminderResync(
          delay: Duration.zero,
          reason: 'ringtone settings changed',
        );
      }());
    }
  };
  quickCaptureTemplateProvider.addListener(
    cloudSyncProvider.markQuickCaptureTemplatesChanged,
  );
  listGroupProvider.onLocalChanged = markDirty;

  void refreshUserStats() {
    userProvider.recalc(
      completedTodos: todoProvider.completedTodos.length,
      totalFocusMinutes: pomodoroProvider.totalFocusMinutes,
      currentStreak: habitProvider.longestCurrentStreak,
      bestStreak: habitProvider.longestBestStreak,
    );
  }

  todoProvider.addListener(refreshUserStats);
  habitProvider.addListener(refreshUserStats);
  var lastPomodoroStatsSignature = _pomodoroSessionsSignature(pomodoroProvider);
  void refreshUserStatsOnPomodoroSummaryChange() {
    final next = _pomodoroSessionsSignature(pomodoroProvider);
    if (next == lastPomodoroStatsSignature) return;
    lastPomodoroStatsSignature = next;
    refreshUserStats();
  }

  pomodoroProvider.addListener(refreshUserStatsOnPomodoroSummaryChange);

  bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool isInRange(DateTime date, DateTime start, DateTime end) {
    final day = AppClock.dateOnly(date);
    return !day.isBefore(start) && day.isBefore(end);
  }

  String dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Timer? achievementRefreshDebounce;
  var achievementRefreshInFlight = false;
  var achievementRefreshQueued = false;
  var achievementRefreshQueuedSilent = false;

  Future<void> refreshAchievementsNow({
    bool silentUnlockFeedback = false,
  }) async {
    final now = AppClock.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final activeDays = <String>{};

    final todayCompletedTodos = todoProvider.todos.where((todo) {
      if (!todo.isCompleted) return false;
      final completedAt = todo.completedAt == null
          ? todo.date
          : AppClock.toLocal(todo.completedAt!);
      return isSameDay(completedAt, today);
    }).length;
    final weeklyCompletedTodos = todoProvider.todos.where((todo) {
      if (!todo.isCompleted) return false;
      final completedAt = todo.completedAt == null
          ? todo.date
          : AppClock.toLocal(todo.completedAt!);
      final inWeek = isInRange(completedAt, weekStart, weekEnd);
      if (inWeek) activeDays.add(dateKey(completedAt));
      return inWeek;
    }).length;

    final todayHabitCheckIns = habitProvider.habits
        .where((habit) => habit.activeForDate(today))
        .fold<int>(0, (sum, habit) => sum + habit.countForDate(today));
    var weeklyHabitCheckIns = 0;
    for (final habit in habitProvider.habits) {
      for (final entry in habit.completions.entries) {
        final date = DateTime.tryParse(entry.key);
        if (date == null || !isInRange(date, weekStart, weekEnd)) continue;
        if (!habit.activeForDate(date)) continue;
        weeklyHabitCheckIns += entry.value;
        if (entry.value > 0) activeDays.add(dateKey(date));
      }
    }

    final focusSessions = pomodoroProvider.sessions.where(
      (session) => session.type == PomodoroType.focus,
    );
    final todayFocusMinutes =
        focusSessions
            .where(
              (session) =>
                  isInRange(AppClock.toLocal(session.endTime), today, tomorrow),
            )
            .fold<int>(0, (sum, session) => sum + session.durationSeconds) ~/
        60;
    final weeklyFocusMinutes =
        focusSessions
            .where((session) {
              final localEnd = AppClock.toLocal(session.endTime);
              final inWeek = isInRange(localEnd, weekStart, weekEnd);
              if (inWeek) activeDays.add(dateKey(localEnd));
              return inWeek;
            })
            .fold<int>(0, (sum, session) => sum + session.durationSeconds) ~/
        60;

    await achievementProvider.updateContext(
      AchievementContext(
        totalTodos: todoProvider.todos.length,
        completedTodos: todoProvider.completedTodos.length,
        longestHabitStreak: habitProvider.longestBestStreak,
        habitCount: habitProvider.habits.length,
        focusMinutes: pomodoroProvider.totalFocusMinutes,
        focusSessions: pomodoroProvider.sessions.length,
        diaryStreak: 0,
        diaryCount: 0,
        goalsTotal: goalProvider.goals.length,
        goalsAchieved: goalProvider.goals
            .where((g) => g.status == GoalStatus.achieved)
            .length,
        anniversaries: anniversaryProvider.items.length,
        courses: courseProvider.courses.length,
        notes: noteProvider.notes.length,
        themeSwitches: themeProvider.themeSwitchCount,
        todayCompletedTodos: todayCompletedTodos,
        todayHabitCheckIns: todayHabitCheckIns,
        todayFocusMinutes: todayFocusMinutes,
        weeklyCompletedTodos: weeklyCompletedTodos,
        weeklyHabitCheckIns: weeklyHabitCheckIns,
        weeklyFocusMinutes: weeklyFocusMinutes,
        weeklyActiveDays: activeDays.length,
      ),
      silentUnlockFeedback: silentUnlockFeedback,
    );
  }

  Future<void> runQueuedAchievementRefresh({
    bool silentUnlockFeedback = false,
  }) async {
    if (achievementRefreshInFlight) {
      achievementRefreshQueued = true;
      achievementRefreshQueuedSilent |= silentUnlockFeedback;
      return;
    }
    achievementRefreshInFlight = true;
    try {
      await refreshAchievementsNow(silentUnlockFeedback: silentUnlockFeedback);
    } catch (e, st) {
      debugPrint('[achievements] refresh failed: $e\n$st');
    } finally {
      achievementRefreshInFlight = false;
    }
    if (achievementRefreshQueued) {
      achievementRefreshQueued = false;
      final queuedSilent = achievementRefreshQueuedSilent;
      achievementRefreshQueuedSilent = false;
      achievementRefreshDebounce?.cancel();
      achievementRefreshDebounce = Timer(const Duration(seconds: 2), () {
        unawaited(
          runQueuedAchievementRefresh(silentUnlockFeedback: queuedSilent),
        );
      });
    }
  }

  void refreshAchievements({
    Duration delay = const Duration(seconds: 2),
    bool silentUnlockFeedback = false,
  }) {
    achievementRefreshDebounce?.cancel();
    achievementRefreshDebounce = Timer(delay, () {
      unawaited(
        runQueuedAchievementRefresh(silentUnlockFeedback: silentUnlockFeedback),
      );
    });
  }

  todoProvider.addListener(refreshAchievements);
  habitProvider.addListener(refreshAchievements);
  var lastPomodoroAchievementSignature = _pomodoroSessionsSignature(
    pomodoroProvider,
  );
  void refreshAchievementsOnPomodoroSummaryChange() {
    final next = _pomodoroSessionsSignature(pomodoroProvider);
    if (next == lastPomodoroAchievementSignature) return;
    lastPomodoroAchievementSignature = next;
    refreshAchievements();
  }

  pomodoroProvider.addListener(refreshAchievementsOnPomodoroSummaryChange);
  goalProvider.addListener(refreshAchievements);
  anniversaryProvider.addListener(refreshAchievements);
  courseProvider.addListener(refreshAchievements);
  noteProvider.addListener(refreshAchievements);
  themeProvider.addListener(refreshAchievements);
  bool calendarSyncDue() {
    const minStartupSyncInterval = Duration(minutes: 30);
    final now = DateTime.now();
    bool stale(DateTime? lastSyncedAt) =>
        lastSyncedAt == null ||
        now.difference(lastSyncedAt) >= minStartupSyncInterval;
    return calendarSyncProvider.subscriptions.any(
          (sub) => sub.enabled && stale(sub.lastSyncedAt),
        ) ||
        calendarSyncProvider.oauthAccounts.any(
          (account) => account.enabled && stale(account.lastSyncedAt),
        );
  }

  // 启动后延迟刷新订阅日历，且 30 分钟内已同步过的不再抢首屏资源。
  // ignore: discarded_futures
  Future<void>.delayed(const Duration(seconds: 90), () {
    if (calendarSyncDue()) return calendarSyncProvider.syncAll();
  });

  // 订阅日历变化 → 写入 CalendarProvider 的外部事件，下次 rebuild 合并显示。
  void onCalendarSyncChange() {
    calendarProvider.setExternalEvents(calendarSyncProvider.allEvents());
  }

  calendarSyncProvider.addListener(onCalendarSyncChange);
  onCalendarSyncChange();
  Future<void> syncDailyDigestReminder() => _syncDailyDigestReminder(
    preferencesProvider,
    notificationService,
    todoProvider,
  );
  Future<void> syncReportDigestReminders() => _syncReportDigestReminders(
    preferencesProvider,
    notificationService,
    todos: todoProvider,
    habits: habitProvider,
    pomodoros: pomodoroProvider,
    timeAudit: timeAuditProvider,
  );
  reminderAuxiliaryResync = () async {
    await syncDailyDigestReminder();
    await syncReportDigestReminders();
  };
  Timer? reportDigestSyncDebounce;
  void queueReportDigestReminderSync() {
    reportDigestSyncDebounce?.cancel();
    reportDigestSyncDebounce = Timer(const Duration(seconds: 2), () {
      unawaited(syncReportDigestReminders());
    });
  }

  Future<bool> syncNotificationQuickAdd({
    bool requestIfNeeded = false,
    bool force = false,
  }) => _syncNotificationQuickAdd(
    preferencesProvider,
    todos: todoProvider,
    habits: habitProvider,
    goals: goalProvider,
    requestIfNeeded: requestIfNeeded,
    force: force,
  );

  Timer? dailyDigestSyncDebounce;
  void queueDailyDigestReminderSync() {
    dailyDigestSyncDebounce?.cancel();
    dailyDigestSyncDebounce = Timer(const Duration(seconds: 2), () {
      unawaited(syncDailyDigestReminder());
    });
  }

  Timer? notificationQuickAddSyncDebounce;
  var notificationQuickAddSyncInFlight = false;
  var notificationQuickAddSyncQueued = false;
  var notificationQuickAddSyncQueuedForce = false;
  var notificationQuickAddSyncQueuedRequestIfNeeded = false;
  Completer<bool>? notificationQuickAddSyncQueuedCompleter;
  var lastNotificationQuickAddSignature = '';
  var lastNotificationQuickAddFailureSignature = '';
  DateTime? lastNotificationQuickAddFailureAt;
  String notificationQuickAddSignature() {
    final todayProgress = preferencesProvider.notificationTodayProgress;
    final progressBody = todayProgress
        ? _todayTaskProgressNotificationBody(
            todoProvider.todos,
            habits: habitProvider,
            goals: goalProvider,
          )
        : '';
    return '${preferencesProvider.notificationQuickAdd}:'
        '$todayProgress:$progressBody';
  }

  Future<bool> syncNotificationQuickAddDeduped({
    bool force = false,
    bool requestIfNeeded = false,
  }) async {
    final signature = notificationQuickAddSignature();
    if (!force && signature == lastNotificationQuickAddSignature) return true;
    final lastFailureAt = lastNotificationQuickAddFailureAt;
    if (!force &&
        signature == lastNotificationQuickAddFailureSignature &&
        lastFailureAt != null &&
        DateTime.now().difference(lastFailureAt) <
            const Duration(seconds: 45)) {
      debugPrint('[NotificationStatusBar] sync skipped during failure backoff');
      return false;
    }
    if (notificationQuickAddSyncInFlight) {
      notificationQuickAddSyncQueued = true;
      notificationQuickAddSyncQueuedForce =
          notificationQuickAddSyncQueuedForce || force;
      notificationQuickAddSyncQueuedRequestIfNeeded =
          notificationQuickAddSyncQueuedRequestIfNeeded || requestIfNeeded;
      final completer = notificationQuickAddSyncQueuedCompleter ??=
          Completer<bool>();
      return completer.future;
    }
    notificationQuickAddSyncInFlight = true;
    var synced = false;
    try {
      synced = await syncNotificationQuickAdd(
        requestIfNeeded: requestIfNeeded,
        force: force,
      );
      final completedSignature = notificationQuickAddSignature();
      if (synced) {
        lastNotificationQuickAddSignature = completedSignature;
        lastNotificationQuickAddFailureSignature = '';
        lastNotificationQuickAddFailureAt = null;
      } else {
        lastNotificationQuickAddFailureSignature = completedSignature;
        lastNotificationQuickAddFailureAt = DateTime.now();
      }
    } finally {
      notificationQuickAddSyncInFlight = false;
    }
    if (notificationQuickAddSyncQueued) {
      notificationQuickAddSyncQueued = false;
      final queuedForce = notificationQuickAddSyncQueuedForce;
      final queuedRequestIfNeeded =
          notificationQuickAddSyncQueuedRequestIfNeeded;
      notificationQuickAddSyncQueuedForce = false;
      notificationQuickAddSyncQueuedRequestIfNeeded = false;
      final queuedCompleter = notificationQuickAddSyncQueuedCompleter;
      notificationQuickAddSyncQueuedCompleter = null;
      lastNotificationQuickAddSignature = '';
      final queuedSynced = await syncNotificationQuickAddDeduped(
        force: queuedForce,
        requestIfNeeded: queuedRequestIfNeeded,
      );
      if (queuedCompleter != null && !queuedCompleter.isCompleted) {
        queuedCompleter.complete(queuedSynced);
      }
      synced = queuedSynced;
    }
    return synced;
  }

  _syncNotificationQuickAddDedupedCallback = syncNotificationQuickAddDeduped;
  NotificationStatusBarSyncBridge.attach(syncNotificationQuickAddDeduped);

  Future<bool> syncNotificationStatusBarOnStartup() async {
    final todayProgress = preferencesProvider.notificationTodayProgress;
    final quickAdd = preferencesProvider.notificationQuickAdd;
    if (!todayProgress && !quickAdd) return syncNotificationQuickAddDeduped();
    final prefs = await SharedPreferences.getInstance();
    final lastBuild = prefs.getInt(_notificationStatusBarStartupBuildKey);
    if (lastBuild != AppVersion.build) {
      await prefs.setInt(
        _notificationStatusBarStartupBuildKey,
        AppVersion.build,
      );
      debugPrint('[NotificationStatusBar] startup force sync after update');
      return syncNotificationQuickAddDeduped(force: true);
    }
    return syncNotificationQuickAddDeduped();
  }

  void queueNotificationQuickAddSync({
    bool allowBeforeDeferredHydration = false,
  }) {
    if (!deferredLocalStorageHydrated && !allowBeforeDeferredHydration) return;
    notificationQuickAddSyncDebounce?.cancel();
    notificationQuickAddSyncDebounce = Timer(const Duration(seconds: 2), () {
      unawaited(syncNotificationQuickAddDeduped());
    });
  }

  void queueNotificationProgressSync() {
    if (!deferredLocalStorageHydrated) return;
    if (!preferencesProvider.notificationTodayProgress) return;
    queueNotificationQuickAddSync();
  }

  Timer? notificationProgressMidnightTimer;
  void scheduleNotificationProgressMidnightRefresh() {
    notificationProgressMidnightTimer?.cancel();
    final delay = _durationUntilNextLocalDay();
    notificationProgressMidnightTimer = Timer(delay, () {
      AppClock.notifyDayChanged();
      refreshUserStats();
      if (preferencesProvider.notificationTodayProgress) {
        unawaited(syncNotificationQuickAddDeduped());
      }
      scheduleNotificationProgressMidnightRefresh();
    });
  }

  preferencesProvider.addListener(queueDailyDigestReminderSync);
  preferencesProvider.addListener(queueReportDigestReminderSync);
  preferencesProvider.addListener(queueNotificationQuickAddSync);
  todoProvider.addListener(queueNotificationProgressSync);
  habitProvider.addListener(queueNotificationProgressSync);
  goalProvider.addListener(queueNotificationProgressSync);
  todoProvider.addListener(queueDailyDigestReminderSync);
  todoProvider.addListener(queueReportDigestReminderSync);
  habitProvider.addListener(queueReportDigestReminderSync);
  var lastPomodoroReportSignature = _pomodoroSessionsSignature(
    pomodoroProvider,
  );
  void queueReportDigestReminderSyncOnPomodoroSummaryChange() {
    final next = _pomodoroSessionsSignature(pomodoroProvider);
    if (next == lastPomodoroReportSignature) return;
    lastPomodoroReportSignature = next;
    queueReportDigestReminderSync();
  }

  pomodoroProvider.addListener(
    queueReportDigestReminderSyncOnPomodoroSummaryChange,
  );
  timeAuditProvider.addListener(queueReportDigestReminderSync);
  scheduleNotificationProgressMidnightRefresh();
  LocalTimezoneResolver.timezoneListenable.addListener(() {
    scheduleNotificationProgressMidnightRefresh();
    refreshUserStats();
    unawaited(refreshAchievementsNow(silentUnlockFeedback: true));
    unawaited(syncNotificationQuickAddDeduped());
  });
  refreshUserStats();
  refreshAchievements();

  Future<void> runDailyRolloverAfterFirstFrame() async {
    await _startupGuard(
      'daily rollover',
      () => CompletionVisibilityPolicy.runDailyRollover(
        todoProvider,
        AppClock.now(),
        goalProvider: goalProvider,
      ),
    );
    refreshUserStats();
    refreshAchievements();
    await queueStartupReminderResync(
      delay: const Duration(milliseconds: 500),
      reason: 'daily rollover completed',
    );
  }

  // 通知点击后的深链接(打开对应 Tab)
  void handleNotificationPayload(String payload) {
    if (_shouldStopActiveRingtoneForPayload(payload)) {
      unawaited(NativeReminderRingtone.stopActive());
    }
    final uri = Uri.tryParse(payload);
    if (uri == null) return;
    _handleWidgetUri(uri, pomodoroProvider);
  }

  LocalNotifications.instance.onTap = handleNotificationPayload;
  AlarmService.instance.onTap = handleNotificationPayload;
  // AI / CloudSync 依赖 AuthProvider 的 ApiClient
  aiService.attachClient(authProvider.client);
  cloudSyncProvider.apiClientGetter = () => authProvider.client;
  cloudSyncProvider.serverConfigGetter = () => authProvider.serverConfig;

  authProvider.onServerConfigChanged = (cfg) {
    aiService.updateFromServerConfig(cfg);
  };
  var lastUpdateServer = authProvider.baseUrl;
  authProvider.addListener(() {
    if (lastUpdateServer != authProvider.baseUrl) {
      lastUpdateServer = authProvider.baseUrl;
      appUpdate.resetForServerChange();
    }
    aiService.attachClient(authProvider.client);
    focusRoomProvider.apiClientGetter = () => authProvider.client;
  });
  if (authProvider.serverConfig.isNotEmpty) {
    aiService.updateFromServerConfig(authProvider.serverConfig);
  }
  cloudSyncProvider.onSynced = (changedCollections) async {
    // 同步完成后服务端回写可能覆盖本地数据；这段 reload 不应被当作“脏改动”。
    await cloudSyncProvider.suppressDirtyMarkWhile(() async {
      const achievementSyncCollections = <String>{
        'todos',
        'habits',
        'pomodoro_sessions',
        'diaries',
        'goals',
        'anniversaries',
        'courses',
        'notes',
        'theme_shop_state',
        'achievement_states',
        'virtual_rewards',
      };
      final reloadTasks = <Future<void> Function()>[];
      var shouldResyncReminders = false;
      final shouldRefreshAchievementsSilently = changedCollections.any(
        achievementSyncCollections.contains,
      );

      if (changedCollections.contains('todos')) {
        // TodoProvider 平时惰性加载；云同步回写后必须强制重读，
        // 否则内存列表停留在旧快照，下一次本地写入会覆盖同步结果。
        reloadTasks.add(() => todoProvider.loadFromStorage(force: true));
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('habits')) {
        reloadTasks.add(habitProvider.loadFromStorage);
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('pomodoro_sessions') ||
          changedCollections.contains('focus_penalties') ||
          changedCollections.contains('pomodoro_config')) {
        reloadTasks.add(pomodoroProvider.loadFromStorage);
      }
      if (changedCollections.contains('countdowns')) {
        reloadTasks.add(countdownProvider.loadFromStorage);
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('notes')) {
        reloadTasks.add(noteProvider.loadFromStorage);
      }
      if (changedCollections.contains('anniversaries')) {
        reloadTasks.add(anniversaryProvider.loadFromStorage);
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('diaries')) {
        reloadTasks.add(diaryProvider.loadFromStorage);
      }
      if (changedCollections.contains('goals')) {
        reloadTasks.add(goalProvider.loadFromStorage);
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('courses') ||
          changedCollections.contains('course_settings')) {
        reloadTasks.add(courseProvider.loadFromStorage);
      }
      if (changedCollections.contains('calendar_events')) {
        reloadTasks.add(calendarProvider.loadFromStorage);
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('user_profile')) {
        reloadTasks.add(userProvider.loadFromStorage);
      }
      if (changedCollections.contains('time_entries')) {
        reloadTasks.add(timeAuditProvider.loadFromStorage);
      }
      if (changedCollections.contains('location_reminders')) {
        reloadTasks.add(locationReminderProvider.loadFromStorage);
      }
      if (changedCollections.contains('achievement_states') ||
          changedCollections.contains('virtual_rewards')) {
        reloadTasks.add(achievementProvider.loadFromStorage);
      }
      if (changedCollections.contains('focus_rooms')) {
        reloadTasks.add(focusRoomProvider.loadFromStorage);
      }
      if (changedCollections.contains('theme_shop_state')) {
        reloadTasks.add(themeProvider.loadFromStorage);
      }
      if (changedCollections.contains('preferences')) {
        reloadTasks.add(preferencesProvider.loadFromStorage);
        shouldResyncReminders = true;
      }
      if (changedCollections.contains('quick_capture_templates')) {
        reloadTasks.add(quickCaptureTemplateProvider.loadFromStorage);
      }
      if (changedCollections.contains('list_groups')) {
        reloadTasks.add(listGroupProvider.loadFromStorage);
      }

      await _runSyncReloadTasksInBatches(reloadTasks);
      if (shouldRefreshAchievementsSilently) {
        achievementRefreshDebounce?.cancel();
        achievementRefreshQueued = false;
        achievementRefreshQueuedSilent = false;
        await refreshAchievementsNow(silentUnlockFeedback: true);
        // 云端成就基线已静默回填完毕，可恢复正常解锁反馈：
        // 此后真正的新解锁才会弹窗 / 通知。
        achievementProvider.resumeUnlockFeedback();
      }

      final accountCollectionsChanged =
          changedCollections.contains('user_profile') ||
          changedCollections.contains('virtual_rewards');
      if (accountCollectionsChanged) {
        // 云同步回写本地资料后，再拉一次账号资料，保证其它设备改过的
        // 昵称、头像、邮箱验证状态、时光币等账号字段能覆盖本地展示缓存。
        await authProvider.refreshMe(reason: 'cloud_sync_account_snapshot');
      }
      if (changedCollections.contains('workspace_payloads')) {
        await shareProvider.load();
      }
      if (changedCollections.contains('preferences')) {
        await ReminderRingtoneSettings.applyPersistedSettingsToNative();
      }
      // 拉取云端后可能覆盖了本地 reminder，也要重跑一次
      if (shouldResyncReminders) {
        unawaited(
          queueFullReminderResync(
            delay: const Duration(milliseconds: 2500),
            reason: 'cloud sync changed reminders',
          ),
        );
      }
    });
  };

  String? currentAuthReminderIdentity() {
    final state = authProvider.state;
    if (!state.isLoggedIn) return null;
    return '${authProvider.baseUrl}|${state.token}';
  }

  Future<void> startCloudSyncAfterAuth({
    required String reason,
    Duration delay = const Duration(milliseconds: 1600),
  }) async {
    final serial = ++cloudSyncStartSerial;
    await Future<void>.delayed(delay);
    if (serial != cloudSyncStartSerial) return;
    if (!authProvider.state.isLoggedIn || !cloudSyncProvider.config.autoSync) {
      cloudSyncProvider.stopRemotePolling();
      return;
    }
    await _startupGuard(
      'server config before cloud sync',
      () => authProvider.refreshServerConfigFromServer(),
      timeout: const Duration(seconds: 5),
    );
    if (serial != cloudSyncStartSerial) return;
    if (!authProvider.state.isLoggedIn || !cloudSyncProvider.config.autoSync) {
      cloudSyncProvider.stopRemotePolling();
      return;
    }
    if (authProvider.serverConfig['backup_enabled'] == false) {
      cloudSyncProvider.stopRemotePolling();
      return;
    }
    cloudSyncProvider.resumeForActiveAccount();
    await _startupGuard(
      'cloud sync $reason',
      () => cloudSyncProvider.syncNow(),
      timeout: const Duration(seconds: 12),
    );
    if (serial != cloudSyncStartSerial) return;
    if (authProvider.state.isLoggedIn && cloudSyncProvider.config.autoSync) {
      cloudSyncProvider.startRemotePolling();
    }
  }

  var lastAuthReminderIdentity = currentAuthReminderIdentity();
  authProvider.addListener(() {
    final authReminderIdentity = currentAuthReminderIdentity();
    final authChanged = authReminderIdentity != lastAuthReminderIdentity;
    lastAuthReminderIdentity = authReminderIdentity;
    if (!authChanged) return;
    shareProvider.load();
    if (authProvider.state.isLoggedIn && cloudSyncProvider.config.autoSync) {
      unawaited(
        startCloudSyncAfterAuth(
          reason: 'auth changed',
          delay: const Duration(milliseconds: 2600),
        ),
      );
      // 登录/切号后立刻重放本地提醒；云同步回写后还会幂等重放一次。
      if (authChanged) {
        unawaited(
          queueFullReminderResync(
            delay: const Duration(milliseconds: 2600),
            reason: 'auth changed',
          ),
        );
      }
    } else {
      cloudSyncStartSerial++;
      cloudSyncProvider.stopRemotePolling();
    }
  });
  if (authProvider.state.isLoggedIn) {
    shareProvider.load();
  }
  if (authProvider.state.isLoggedIn && cloudSyncProvider.config.autoSync) {
    unawaited(
      startCloudSyncAfterAuth(
        reason: 'initial logged-in startup',
        delay: const Duration(seconds: 120),
      ),
    );
    unawaited(
      queueStartupReminderResync(
        delay: const Duration(seconds: 110),
        reason: 'initial logged-in startup',
      ),
    );
  }

  Future<bool> pushHomeWidgetNow() => _pushHomeWidget(
    todoProvider,
    habitProvider,
    pomodoroProvider,
    calendarProvider,
    countdownProvider,
    timeAuditProvider,
    goalProvider,
    anniversaryProvider,
    courseProvider,
    noteProvider,
    themeProvider,
  );

  Timer? homeWidgetThemeDebounce;
  String lastHomeWidgetThemeSignature = '';

  // 小组件快照推送统一交给串行排程器：数据变化只标记 dirty 并按 2200ms 合并，
  // 退到后台/暂停时立即 flush 最新状态。旧实现在 deferred hydration 未完成时
  // 直接丢弃 push，且退出/暂停时没有 flush，会漏掉合并窗口内的最后一次更新。
  final homeWidgetPushScheduler = HomeWidgetPushScheduler(
    push: pushHomeWidgetNow,
    isReady: () => deferredLocalStorageHydrated,
    ensureReady: ensureDeferredLocalStorageStartup,
    debounce: const Duration(milliseconds: 2200),
    observeLifecycle: true,
  );

  Future<void> runQueuedHomeWidgetPush() async {
    final pushed = await homeWidgetPushScheduler.flush();
    if (!pushed) {
      debugPrint('[HomeWidget] queued push completed with failures');
    }
  }

  void queueHomeWidgetPush() => homeWidgetPushScheduler.schedule();

  String homeWidgetThemeSignature() {
    final payload = HomeWidgetThemePayload.fromThemeProvider(themeProvider);
    return '${payload.brandId}:${payload.cardSkinId}:'
        '${payload.backgroundAssetKey}:${payload.dark}:'
        '${payload.background.toARGB32()}:${payload.surface.toARGB32()}:'
        '${payload.cornerRadiusDp}:${payload.borderWidthDp}';
  }

  Future<void> updateHomeWidgetThemeNow({required String reason}) async {
    final signature = homeWidgetThemeSignature();
    if (signature == lastHomeWidgetThemeSignature) return;
    lastHomeWidgetThemeSignature = signature;
    final ok = await HomeWidgetService.updateTheme(
      HomeWidgetThemePayload.fromThemeProvider(themeProvider),
    );
    if (!ok) {
      lastHomeWidgetThemeSignature = '';
      debugPrint('[HomeWidget] theme update failed reason=$reason');
    }
  }

  void queueHomeWidgetThemeUpdate({required String reason}) {
    homeWidgetThemeDebounce?.cancel();
    homeWidgetThemeDebounce = Timer(const Duration(milliseconds: 160), () {
      unawaited(updateHomeWidgetThemeNow(reason: reason));
    });
  }

  // 预约提醒（scheduler 派发）与即时通知共用品牌标题：启动注入一次，
  // 主题切换跟随，避免非 default 主题下两路通知标题不一致。
  // 语言切换也会改变 AppBrand.strings（BrandStrings.forLocale 按 I18n 分发），
  // 因此 localeProvider 变更时同样需要重推，通知/提醒文案才能跟随语言。
  void pushBrandStringsToNotifiers() {
    reminderScheduler.setStrings(themeProvider.brand.strings);
    notificationService.setStrings(themeProvider.brand.strings);
  }

  pushBrandStringsToNotifiers();
  themeProvider.addListener(() {
    pushBrandStringsToNotifiers();
    queueHomeWidgetThemeUpdate(reason: 'theme provider changed');
    queueHomeWidgetPush();
  });
  localeProvider.addListener(() {
    pushBrandStringsToNotifiers();
    // 语言切换同样改变小组件 payload 文案（_pushHomeWidget 走 I18n）与
    // 品牌词条（brand.strings），必须重推小组件数据；主题 payload 与语言
    // 无关，updateHomeWidgetThemeNow 的签名去重会自然跳过写入。
    queueHomeWidgetPush();
  });
  unawaited(updateHomeWidgetThemeNow(reason: 'startup theme loaded'));

  systemTray.onActivate.listen((action) {
    if (action == 'pomodoro_quick_start') pomodoroProvider.startIfIdle();
  });

  void onDataChange() => queueHomeWidgetPush();
  var lastPomodoroHomeWidgetSignature = _pomodoroHomeWidgetSignature(
    pomodoroProvider,
  );
  void onPomodoroHomeWidgetChange() {
    final next = _pomodoroHomeWidgetSignature(pomodoroProvider);
    if (next == lastPomodoroHomeWidgetSignature) return;
    lastPomodoroHomeWidgetSignature = next;
    queueHomeWidgetPush();
  }

  todoProvider.addListener(onDataChange);
  habitProvider.addListener(onDataChange);
  pomodoroProvider.addListener(onPomodoroHomeWidgetChange);
  timeAuditProvider.addListener(onDataChange);
  goalProvider.addListener(onDataChange);
  anniversaryProvider.addListener(onDataChange);
  countdownProvider.addListener(onDataChange);
  courseProvider.addListener(onDataChange);
  noteProvider.addListener(onDataChange);

  try {
    HomeWidgetService.widgetClickedStream.listen((uri) {
      if (uri != null) handleDeepLink(uri);
    });
  } catch (e, st) {
    debugPrint('[startup] home widget stream failed: $e\n$st');
  }

  // 桌面小组件动作：主 isolate 仍然存活时由后台引擎转发到这里执行，写的是
  // 同一批内存 Provider，随后的普通编辑不会用陈旧副本回滚完成态/打卡。
  if (HomeWidgetService.supportsBackgroundActions) {
    HomeWidgetActionBridge.registerMainHandler((uri) async {
      final request = HomeWidgetActionRequest.parse(uri);
      if (request == null) return HomeWidgetActionAck.skipped;
      // 换号/登出后内存登录态立即失效，不能再用旧对象执行动作。
      if (!authProvider.state.isLoggedIn) {
        debugPrint('[HomeWidget] live ${request.kind.name} skipped: signedOut');
        return HomeWidgetActionAck.skipped;
      }
      await ensureDeferredLocalStorageStartup();
      final changed = await HomeWidgetService.runBackgroundAction(
        request,
        live: HomeWidgetLiveProviders(
          todos: todoProvider,
          habits: habitProvider,
          pomodoro: pomodoroProvider,
        ),
        signedIn: authProvider.state.isLoggedIn,
      );
      if (!changed) return HomeWidgetActionAck.skipped;
      // 回执等待同一串行队列补推，避免后台动作与在途常规快照并发写入。
      final pushed = await homeWidgetPushScheduler.flush(force: true);
      return pushed ? HomeWidgetActionAck.done : HomeWidgetActionAck.failed;
    });
  }

  Future<void> runPostFrameStartupTasks() async {
    unawaited(
      Future<void>.delayed(const Duration(seconds: 14), () async {
        await ensureDeferredLocalStorageStartup();
        queueHomeWidgetPush();
        queueNotificationQuickAddSync();
      }),
    );
    unawaited(
      _runStartupStaggeredTask(
        'startup notification launch payloads',
        () async {
          await LocalNotifications.instance.initForLaunchPayload();
          await AlarmService.instance.initForLaunchPayload();
          final initialNotificationPayloads = <String>[];
          final localLaunchPayload = LocalNotifications.instance
              .takeLaunchPayload();
          if (localLaunchPayload != null && localLaunchPayload.isNotEmpty) {
            initialNotificationPayloads.add(localLaunchPayload);
          }
          final alarmLaunchPayload = AlarmService.instance.takeLaunchPayload();
          if (alarmLaunchPayload != null && alarmLaunchPayload.isNotEmpty) {
            initialNotificationPayloads.add(alarmLaunchPayload);
          }
          for (final payload in initialNotificationPayloads.toSet()) {
            handleNotificationPayload(payload);
          }
        },
        delay: const Duration(milliseconds: 2400),
      ),
    );
    unawaited(
      _runStartupStaggeredTask('startup deep links', () async {
        final initialDeepLink = await _startupValue<Uri>(
          'deep link initial launch',
          () => DeepLinkService.takeInitialLink(),
        );
        final initialOAuthLink = await _startupValue<Uri>(
          'deep link initial oauth',
          () => DeepLinkService.takeInitialOAuthLink(),
        );
        final initialSharedText = await _startupValue<String>(
          'deep link initial shared text',
          () => DeepLinkService.takeInitialSharedText(),
        );
        if (initialDeepLink != null && initialDeepLink.toString().isNotEmpty) {
          _handleWidgetUri(initialDeepLink, pomodoroProvider);
        }
        if (initialOAuthLink != null) {
          _handleWidgetUri(initialOAuthLink, pomodoroProvider);
        }
        if (initialSharedText != null) {
          _showSharedTextImportSheet(initialSharedText);
        }
      }, delay: const Duration(milliseconds: 1100)),
    );
    unawaited(
      _runStartupStaggeredTask('home widget initial launch', () async {
        await ensureHomeWidgetLaunchStartup();
        final initial = await _startupValue<Uri>(
          'home widget initial launch',
          () => HomeWidgetService.initialLaunchUri(),
        );
        if (initial != null) {
          _handleWidgetUri(initial, pomodoroProvider);
        }
      }, delay: const Duration(seconds: 8)),
    );
    unawaited(
      _runStartupStaggeredTask(
        'deferred platform services',
        ensureDeferredPlatformStartup,
        delay: const Duration(seconds: 65),
        timeout: const Duration(seconds: 18),
      ),
    );
    unawaited(
      _runStartupIdleQueue(
        [
          () => _startupGuard(
            'deferred local storage',
            ensureDeferredLocalStorageStartup,
            timeout: const Duration(seconds: 20),
          ),
          () => _startupGuard(
            'server config refresh',
            () => authProvider.refreshServerConfigFromServer(),
            timeout: const Duration(seconds: 5),
          ),
          () => _startupGuard(
            'auth profile refresh',
            () => authProvider.refreshMe(),
            timeout: const Duration(seconds: 8),
          ),
          () => _startupGuard(
            'initial reminder resync',
            () => queueStartupReminderResync(
              delay: const Duration(seconds: 5),
              reason: 'post-frame startup',
            ),
          ),
          () => _startupGuard('daily digest reminder', syncDailyDigestReminder),
          () => _startupGuard(
            'report digest reminders',
            syncReportDigestReminders,
          ),
          () => _startupGuard(
            'notification quick add',
            syncNotificationStatusBarOnStartup,
          ),
          () => _startupGuard(
            'initial home widget push',
            runQueuedHomeWidgetPush,
          ),
          runDailyRolloverAfterFirstFrame,
        ],
        initialDelay: const Duration(seconds: 75),
        gap: const Duration(seconds: 12),
      ),
    );
  }

  // 首屏关键配置已完成；大数据 Provider、远端刷新和通知重放在首帧后分批执行。
  cloudSyncProvider.dirtyMarkEnabled = true;

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: todoProvider),
        ChangeNotifierProvider.value(value: habitProvider),
        ChangeNotifierProvider.value(value: pomodoroProvider),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: cloudSyncProvider),
        // 云同步状态只读展示层：状态卡仅消费状态，无手动触发入口。
        ChangeNotifierProvider.value(
          value: SyncStatusController(source: cloudSyncProvider),
        ),
        ChangeNotifierProvider.value(value: calendarProvider),
        ChangeNotifierProvider.value(value: userProvider),
        ChangeNotifierProvider.value(value: countdownProvider),
        ChangeNotifierProvider.value(value: noteProvider),
        ChangeNotifierProvider.value(value: anniversaryProvider),
        ChangeNotifierProvider.value(value: diaryProvider),
        ChangeNotifierProvider.value(value: goalProvider),
        ChangeNotifierProvider.value(value: courseProvider),
        ChangeNotifierProvider.value(value: appLockProvider),
        ChangeNotifierProvider.value(value: preferencesProvider),
        ChangeNotifierProvider.value(value: quickCaptureTemplateProvider),
        ChangeNotifierProvider.value(value: listGroupProvider),
        ChangeNotifierProvider.value(value: timeAuditProvider),
        ChangeNotifierProvider.value(value: achievementProvider),
        ChangeNotifierProvider.value(value: customFocusSoundProvider),
        ChangeNotifierProvider.value(value: focusRoomProvider),
        ChangeNotifierProvider.value(value: shareProvider),
        ChangeNotifierProvider.value(value: localeProvider),
        ChangeNotifierProvider.value(value: locationReminderProvider),
        ChangeNotifierProvider.value(value: calendarSyncProvider),
        ChangeNotifierProvider.value(value: notificationService),
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: aiService),
        ChangeNotifierProvider.value(value: appUpdate),
        Provider<ReminderScheduler>.value(value: reminderScheduler),
        Provider.value(value: systemTray),
      ],
      child: const DuoyiApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      _startupGuard(
        'startup app update policy',
        () => appUpdate.checkServerPolicyNow(),
        timeout: const Duration(seconds: 6),
      ),
    );
    unawaited(runPostFrameStartupTasks());
  });
}

bool _shouldStopActiveRingtoneForPayload(String payload) {
  final uri = Uri.tryParse(payload);
  if (uri == null || uri.scheme != 'duoyi') return false;
  if (uri.queryParameters['confirm'] == '1') return true;
  return uri.host == 'snooze' || uri.host == 'alarm-test';
}

Future<bool> _pushHomeWidget(
  TodoProvider t,
  HabitProvider h,
  PomodoroProvider p,
  CalendarProvider cal,
  CountdownProvider countdowns,
  TimeAuditProvider timeAudit,
  GoalProvider g,
  AnniversaryProvider a,
  CourseProvider c,
  NoteProvider n,
  ThemeProvider tp,
) async {
  final now = AppClock.now();
  final today = DateTime(now.year, now.month, now.day);
  final activeToday = t.visibleTodayTodos(now)
    ..sort((a, b) {
      // 按优先级倒序
      final r = b.priority.rank.compareTo(a.priority.rank);
      if (r != 0) return r;
      return a.sortOrder.compareTo(b.sortOrder);
    });
  final activeTodayTodos = activeToday.length;
  final top3 = activeToday.take(3).map((e) => e.title).toList();
  final top3Ids = activeToday.take(3).map((e) => e.id).toList();
  final habitPercent = (h.todayCompletionRate * 100).round();
  final quickCheckHabits =
      h.habits
          .where(
            (habit) =>
                habit.kind == HabitKind.positive &&
                habit.isActiveToday() &&
                !habit.isCompletedToday(),
          )
          .toList()
        ..sort((a, b) {
          final order = a.sortOrder.compareTo(b.sortOrder);
          if (order != 0) return order;
          return a.createdAt.compareTo(b.createdAt);
        });
  final quickCheckHabit = quickCheckHabits.firstOrNull;
  final activeGoalItems = g.activeGoals.take(3).toList();
  final goalHighlights = activeGoalItems
      .map(
        (goal) => '${goal.title} · ${(goal.computedProgress * 100).round()}%',
      )
      .toList();
  final goalHighlightIds = activeGoalItems
      .map((goal) => 'duoyi://goal/${Uri.encodeComponent(goal.id)}')
      .toList();
  final anniversaryItems = a.items
      .where((item) => item.daysRemaining >= 0)
      .take(2)
      .toList();
  final anniversaryHighlights = anniversaryItems
      .map(
        (item) =>
            '${item.title} · ${I18n.tr('widget.days_remaining_prefix')}'
            '${item.daysRemaining}${I18n.tr('widget.days_remaining_suffix')}',
      )
      .toList();
  final anniversaryHighlightIds = anniversaryItems
      .map((item) => 'duoyi://anniversary/${Uri.encodeComponent(item.id)}')
      .toList();
  final memorialItems = a.memorials
      .where((item) => item.daysRemaining >= 0)
      .take(3)
      .toList();
  final memorialHighlights = memorialItems
      .map(
        (item) =>
            '${item.title} · ${I18n.tr('widget.days_remaining_prefix')}'
            '${item.daysRemaining}${I18n.tr('widget.days_remaining_suffix')}',
      )
      .toList();
  final memorialHighlightIds = memorialItems
      .map((item) => 'duoyi://anniversary/${Uri.encodeComponent(item.id)}')
      .toList();
  final courseItems = c.todayCourses.take(3).toList();
  final courseHighlights = courseItems.map((course) {
    final location = course.location.isEmpty ? '' : ' · ${course.location}';
    return '${I18n.tr('widget.course_section_prefix')}'
        '${course.startSection}-${course.endSection}'
        '${I18n.tr('widget.course_section_suffix')}${course.name}$location';
  }).toList();
  final courseHighlightIds = courseItems
      .map((course) => 'duoyi://course/${Uri.encodeComponent(course.id)}')
      .toList();
  final noteItems = n.notes.take(3).toList();
  final noteHighlights = noteItems.map((note) => note.title).toList();
  final noteHighlightIds = noteItems
      .map((note) => 'duoyi://note/${Uri.encodeComponent(note.id)}')
      .toList();
  final calendarEvents = _homeWidgetEventsForToday(
    cal,
    today,
    t,
    h,
    p,
    a,
    c,
    countdowns,
    g,
    timeAudit,
    tp,
  );
  final scheduleHighlights = calendarEvents
      .take(3)
      .map(_homeWidgetEventLabel)
      .toList();
  final scheduleHighlightIds = calendarEvents
      .take(3)
      .map(_homeWidgetEventDeepLink)
      .toList();
  final todayEventSummary = scheduleHighlights.isEmpty
      ? I18n.tr('widget.no_schedule_today')
      : "${I18n.tr('widget.today_prefix')}${scheduleHighlights.first}";
  final focusState = p.state;
  final focusTimerEndsAtMillis = focusState.isRunning && !focusState.isCountUp
      ? DateTime.now()
            .add(Duration(seconds: focusState.remainingSeconds))
            .millisecondsSinceEpoch
      : 0;
  final focusTimerLabel = switch (focusState.type) {
    PomodoroType.focus =>
      focusState.isCountUp
          ? I18n.tr('widget.focus_counting_up')
          : I18n.tr('widget.focus_countdown'),
    PomodoroType.shortBreak => I18n.tr('widget.short_break_countdown'),
    PomodoroType.longBreak => I18n.tr('widget.long_break_countdown'),
  };
  return HomeWidgetService.push(
    todoCount: activeTodayTodos,
    habitPercent: habitPercent,
    pomodoroToday: p.sessionCountToday,
    focusMinutesToday:
        p.todayFocusSessions.fold<int>(
          0,
          (sum, session) => sum + session.durationSeconds,
        ) ~/
        60,
    strings: tp.brand.strings,
    todoTop3: top3,
    todoTop3Ids: top3Ids,
    goalHighlights: goalHighlights,
    goalHighlightIds: goalHighlightIds,
    anniversaryHighlights: anniversaryHighlights,
    anniversaryHighlightIds: anniversaryHighlightIds,
    courseHighlights: courseHighlights,
    courseHighlightIds: courseHighlightIds,
    noteHighlights: noteHighlights,
    noteHighlightIds: noteHighlightIds,
    memorialHighlights: memorialHighlights,
    memorialHighlightIds: memorialHighlightIds,
    scheduleHighlights: scheduleHighlights,
    scheduleHighlightIds: scheduleHighlightIds,
    todayEventSummary: todayEventSummary,
    focusSummary: p.sessionCountToday == 0
        ? I18n.tr('widget.focus_not_started')
        : "${I18n.tr('widget.focus_today_prefix')}${p.sessionCountToday}"
              "${I18n.tr('widget.focus_today_suffix')}",
    habitSummary: habitPercent >= 100
        ? I18n.tr('widget.habit_all_done')
        : "${I18n.tr('widget.habit_progress_prefix')}$habitPercent"
              "${I18n.tr('widget.habit_progress_suffix')}",
    streakSummary:
        "${I18n.tr('widget.streak_prefix')}${h.longestCurrentStreak}"
        "${I18n.tr('widget.streak_suffix')}",
    nextFocusLabel:
        "${p.config.focusDuration ~/ 60}${I18n.tr('widget.next_focus_suffix')}",
    focusTimerRunning: focusState.isRunning,
    focusTimerRemainingSeconds: focusState.remainingSeconds,
    focusTimerTotalSeconds: focusState.totalSeconds,
    focusTimerEndsAtMillis: focusTimerEndsAtMillis,
    focusTimerLabel: focusTimerLabel,
    habitQuickCheckId: quickCheckHabit?.id ?? '',
    habitQuickCheckLabel: quickCheckHabit == null
        ? I18n.tr('widget.habit_quick_check_hint')
        : "${I18n.tr('widget.habit_checkin_prefix')}${quickCheckHabit.name}",
    theme: HomeWidgetThemePayload.fromThemeProvider(tp),
  );
}

List<CalendarEvent> _homeWidgetEventsForToday(
  CalendarProvider calendar,
  DateTime today,
  TodoProvider todos,
  HabitProvider habits,
  PomodoroProvider pomodoros,
  AnniversaryProvider anniversaries,
  CourseProvider courses,
  CountdownProvider countdowns,
  GoalProvider goals,
  TimeAuditProvider timeAudit,
  ThemeProvider themeProvider,
) {
  calendar.rebuild(
    todos.todos,
    habits.habits,
    pomodoros.sessions,
    themeProvider.brand.theme.colorScheme,
    anniversaries: anniversaries.items,
    courses: courses.courses,
    courseSettings: courses.settings,
    countdowns: countdowns.items,
    goals: goals.goals,
    timeEntries: timeAudit.entries,
  );
  final events = calendar.getEventsForDate(today).where((event) {
    if (event.type == CalendarEventType.todo && event.isCompleted) {
      return false;
    }
    return event.sourceId?.trim().isNotEmpty == true;
  }).toList();
  events.sort((a, b) {
    final aTime = a.date;
    final bTime = b.date;
    final timeOrder = aTime.compareTo(bTime);
    if (timeOrder != 0) return timeOrder;
    return a.title.compareTo(b.title);
  });
  return events;
}

String _homeWidgetEventLabel(CalendarEvent event) {
  final time = event.time == null
      ? ''
      : '${event.time!.hour.toString().padLeft(2, '0')}:'
            '${event.time!.minute.toString().padLeft(2, '0')} ';
  return '$time${event.type.label} · ${event.title}';
}

String _homeWidgetEventDeepLink(CalendarEvent event) {
  final sourceId = event.sourceId?.trim();
  if (sourceId == null || sourceId.isEmpty) return '';
  final id = Uri.encodeComponent(sourceId);
  return switch (event.type) {
    CalendarEventType.todo => 'duoyi://todo/$id',
    CalendarEventType.habit => 'duoyi://habit/$id',
    CalendarEventType.anniversary => 'duoyi://anniversary/$id',
    CalendarEventType.course => 'duoyi://course/$id',
    CalendarEventType.diary => '',
    CalendarEventType.goal => 'duoyi://goal/$id',
    CalendarEventType.countdown => 'duoyi://countdown/$id',
    CalendarEventType.event => 'duoyi://calendar',
    CalendarEventType.pomodoro => 'duoyi://focus',
    CalendarEventType.timeEntry => 'duoyi://time-entry/$id',
  };
}

Future<void> _dailyDigestReminderSyncQueue = Future<void>.value();

Future<void> _syncDailyDigestReminder(
  PreferencesProvider prefs,
  NotificationService notification,
  TodoProvider todos,
) {
  return _runDailyDigestReminderSyncSerialized(
    () => _syncDailyDigestReminderLocked(prefs, notification, todos),
  );
}

Future<void> _runDailyDigestReminderSyncSerialized(
  Future<void> Function() action,
) async {
  final run = _dailyDigestReminderSyncQueue.then((_) => action());
  _dailyDigestReminderSyncQueue = run.then<void>((_) {}, onError: (_) {});
  return run;
}

Future<void> _syncDailyDigestReminderLocked(
  PreferencesProvider prefs,
  NotificationService notification,
  TodoProvider todos,
) async {
  const baseId = 880017;
  final cancelled = await _cancelDailyDigestReminderIds(
    notification,
    baseId: baseId,
    slotCount: 3,
  );
  if (!cancelled) {
    debugPrint(
      '[DailyDigest] cancel incomplete; skip scheduling to avoid duplicate delivery',
    );
    return;
  }

  final now = DateTime.now();
  final scheduleSlots = effectiveDailyReminderScheduleSlots(
    prefs.dailyReminderSlots,
  );
  const slotLabels = ['一', '二', '三'];
  for (final entry in scheduleSlots) {
    final i = entry.index;
    final slot = entry.slot;
    final body = _dailyDigestBody(now, todos, slot);

    try {
      final id = baseId + i;
      final label = i < slotLabels.length ? slotLabels[i] : '${i + 1}';
      final title = '每日提醒$label';
      final repeatDays = slot.repeatDays;
      if (slot.pauseHolidays) {
        await _scheduleHolidayAwareDailyDigest(
          notification: notification,
          baseId: id,
          title: title,
          body: body,
          now: now,
          slot: slot,
        );
      } else {
        await _scheduleDailyDigestRepeating(
          notification: notification,
          id: id,
          title: title,
          body: body,
          slot: slot,
          repeatDays: repeatDays,
        );
      }
    } on NotificationPermissionDeniedException catch (e) {
      debugPrint('[DailyDigest] notification permission denied: $e');
    } catch (e, st) {
      debugPrint('[DailyDigest] schedule failed: $e\n$st');
    }
  }
}

Future<bool> _cancelDailyDigestReminderIds(
  NotificationService notification, {
  required int baseId,
  required int slotCount,
}) async {
  var ok = true;
  for (var slot = 0; slot < slotCount; slot++) {
    final id = baseId + slot;
    ok = await _cancelDailyDigestChannelId(notification, id) && ok;
    for (var derived = 0; derived < _dailyDigestHolidayWindowDays; derived++) {
      ok =
          await _cancelDailyDigestChannelId(notification, id * 100 + derived) &&
          ok;
    }
  }
  return ok;
}

Future<bool> _cancelDailyDigestChannelId(
  NotificationService notification,
  int id,
) async {
  var ok = true;
  Future<void> cancelSafely(
    String label,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e, st) {
      ok = false;
      debugPrint('[DailyDigest] cancel $label failed for $id: $e\n$st');
    }
  }

  await cancelSafely('notification', () => notification.cancel(id));
  await cancelSafely('alarm', () => _reminderScheduler.alarm.cancel(id));
  await cancelSafely('popup', () => _reminderScheduler.popup.cancel(id));
  return ok;
}

Future<void> _scheduleDailyDigestRepeating({
  required NotificationService notification,
  required int id,
  required String title,
  required String body,
  required DailyReminderSlot slot,
  required List<int> repeatDays,
}) async {
  final weekdays = repeatDays.length == 7 ? null : repeatDays;
  final payload = 'duoyi://tab/today';
  Future<void> schedulePushFallback() => notification.scheduleDaily(
    id: id,
    title: title,
    body: body,
    hour: slot.hour,
    minute: slot.minute,
    weekdays: weekdays,
    payload: payload,
  );

  switch (DailyReminderSlot.normalizeKind(slot.kind)) {
    case ReminderKind.push:
      await schedulePushFallback();
    case ReminderKind.popup:
      try {
        await _reminderScheduler.popup.scheduleRepeating(
          id: id,
          title: title,
          body: body,
          hour: slot.hour,
          minute: slot.minute,
          weekdays: weekdays,
          payload: payload,
        );
      } catch (e, st) {
        debugPrint(
          '[DailyDigest] popup schedule failed, fallback to push: $e\n$st',
        );
        await schedulePushFallback();
      }
    case ReminderKind.alarm:
      try {
        await _reminderScheduler.alarm.scheduleDailyFullScreen(
          id: id,
          title: title,
          body: body,
          hour: slot.hour,
          minute: slot.minute,
          weekdays: weekdays,
          payload: payload,
          fullScreen: true,
          vibrate: true,
          snoozeMinutes: 5,
          repeatCount: 0,
        );
      } on AlarmQueueHandoffException catch (e) {
        debugPrint(
          '[DailyDigest] alarm schedule handoff failed; skip push fallback to avoid duplicate delivery: $e',
        );
      } catch (e, st) {
        debugPrint('[DailyDigest] alarm schedule failed: $e\n$st');
        if (await _dailyDigestAlarmQueueAlreadyOwns(
          id: id,
          weekdays: weekdays,
          label: 'daily repeating digest',
        )) {
          return;
        }
        debugPrint('[DailyDigest] alarm schedule failed, fallback to push');
        await schedulePushFallback();
      }
    case ReminderKind.off:
      return;
    case ReminderKind.email:
      await schedulePushFallback();
  }
}

Future<void> _scheduleHolidayAwareDailyDigest({
  required NotificationService notification,
  required int baseId,
  required String title,
  required String body,
  required DateTime now,
  required DailyReminderSlot slot,
}) async {
  var cursor = DateTime(now.year, now.month, now.day, slot.hour, slot.minute);
  var scheduled = 0;
  for (
    var offset = 0;
    offset < _dailyDigestHolidayWindowDays &&
        scheduled < _dailyDigestHolidayWindowDays;
    offset++
  ) {
    final target = cursor.add(Duration(days: offset));
    if (!target.isAfter(now)) continue;
    final weekdayAllowed = slot.repeatDays.contains(target.weekday);
    final holidayPaused = HolidayCalendar.isHoliday(target);
    if (!weekdayAllowed || holidayPaused) continue;
    await _scheduleDailyDigestOnce(
      notification: notification,
      id: baseId * 100 + scheduled,
      title: title,
      body: body,
      when: target,
      slot: slot,
    );
    scheduled++;
  }
  if (scheduled == 0) {
    final target = _nextDailyReminderTime(now, slot);
    await _scheduleDailyDigestOnce(
      notification: notification,
      id: baseId * 100,
      title: title,
      body: body,
      when: target,
      slot: slot,
    );
  }
}

Future<void> _scheduleDailyDigestOnce({
  required NotificationService notification,
  required int id,
  required String title,
  required String body,
  required DateTime when,
  required DailyReminderSlot slot,
}) async {
  final payload = 'duoyi://tab/today';
  Future<void> schedulePushFallback() => notification.scheduleOnce(
    id: id,
    title: title,
    body: body,
    when: when,
    payload: payload,
  );

  switch (DailyReminderSlot.normalizeKind(slot.kind)) {
    case ReminderKind.push:
      await schedulePushFallback();
    case ReminderKind.popup:
      try {
        await _reminderScheduler.popup.scheduleOnce(
          id: id,
          title: title,
          body: body,
          when: when,
          payload: payload,
        );
      } catch (e, st) {
        debugPrint(
          '[DailyDigest] popup one-shot failed, fallback to push: $e\n$st',
        );
        await schedulePushFallback();
      }
    case ReminderKind.alarm:
      try {
        await _reminderScheduler.alarm.scheduleFullScreen(
          id: id,
          title: title,
          body: body,
          when: when,
          payload: payload,
          fullScreen: true,
          vibrate: true,
          snoozeMinutes: 5,
          repeatCount: 0,
        );
      } on AlarmQueueHandoffException catch (e) {
        debugPrint(
          '[DailyDigest] alarm one-shot handoff failed; skip push fallback to avoid duplicate delivery: $e',
        );
      } catch (e, st) {
        debugPrint('[DailyDigest] alarm one-shot failed: $e\n$st');
        if (await _dailyDigestAlarmQueueAlreadyOwns(
          id: id,
          label: 'daily one-shot digest',
        )) {
          return;
        }
        debugPrint('[DailyDigest] alarm one-shot failed, fallback to push');
        await schedulePushFallback();
      }
    case ReminderKind.off:
      return;
    case ReminderKind.email:
      await schedulePushFallback();
  }
}

Future<bool> _dailyDigestAlarmQueueAlreadyOwns({
  required int id,
  required String label,
  List<int>? weekdays,
}) async {
  final alarm = _reminderScheduler.alarm;
  if (alarm is! ReminderPendingSink) return false;
  final pendingAlarm = alarm as ReminderPendingSink;
  final expected = _dailyDigestExpectedAlarmIds(id, weekdays);
  final acceptedSets = <Set<int>>[
    <int>{id},
    if (expected.length > 1) expected,
  ];
  try {
    final actual = (await pendingAlarm.pendingIds()).toSet();
    final owns = acceptedSets.any(
      (ids) => ids.isNotEmpty && actual.containsAll(ids),
    );
    if (owns) {
      debugPrint(
        '[DailyDigest] $label alarm queue already registered; skip push fallback to avoid duplicate delivery.',
      );
    }
    return owns;
  } catch (e, st) {
    debugPrint(
      '[DailyDigest] $label pending probe failed; skip push fallback to avoid duplicate delivery: $e\n$st',
    );
    return true;
  }
}

Set<int> _dailyDigestExpectedAlarmIds(int id, List<int>? weekdays) {
  final normalized = weekdays == null || weekdays.isEmpty
      ? const <int>[]
      : weekdays.where((w) => w >= 1 && w <= 7).toSet().toList();
  if (normalized.isEmpty) return <int>{id};
  return {for (final weekday in normalized) _dailyDigestSubId(id, weekday)};
}

int _dailyDigestSubId(int base, int weekday) {
  var hash = 0x811c9dc5;
  final key = '$base:$weekday';
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash == 0 ? weekday : hash;
}

DateTime _nextDailyReminderTime(DateTime now, DailyReminderSlot slot) {
  var target = DateTime(now.year, now.month, now.day, slot.hour, slot.minute);
  if (!target.isAfter(now)) target = target.add(const Duration(days: 1));

  for (var i = 0; i < _dailyDigestHolidayWindowDays; i++) {
    final weekdayAllowed = slot.repeatDays.contains(target.weekday);
    final holidayPaused =
        slot.pauseHolidays && HolidayCalendar.isHoliday(target);
    if (weekdayAllowed && !holidayPaused) break;
    target = target.add(const Duration(days: 1));
  }
  return target;
}

String _dailyDigestBody(
  DateTime now,
  TodoProvider todos,
  DailyReminderSlot slot,
) {
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));
  final todayCount = todos.visibleTodayTodos(now).length;
  final tomorrowCount = todos.todos.where((t) {
    final d = DateTime(t.date.year, t.date.month, t.date.day);
    return d.isAtSameMomentAs(tomorrow) && !t.isCompleted;
  }).length;
  final overdueCount = todos.todos.where((t) => t.isOverdue).length;

  final pieces = <String>[];
  if (slot.includeTodayTasks) pieces.add('今日 $todayCount 项');
  if (slot.includeTomorrowPlan) pieces.add('明日 $tomorrowCount 项');
  if (slot.includeOverdue) pieces.add('逾期 $overdueCount 项');
  return pieces.isEmpty ? '打开多仪整理任务与计划' : pieces.join(' · ');
}

Future<void> _syncReportDigestReminders(
  PreferencesProvider prefs,
  NotificationService notification, {
  required TodoProvider todos,
  required HabitProvider habits,
  required PomodoroProvider pomodoros,
  required TimeAuditProvider timeAudit,
}) async {
  const weeklyId = 880020;
  const monthlyId = 880021;
  const yearlyId = 880022;
  const dailyId = 880023;
  await notification.cancel(dailyId);
  await notification.cancel(weeklyId);
  await notification.cancel(monthlyId);
  await notification.cancel(yearlyId);

  final now = DateTime.now();
  final dailyConfig = prefs.dailyReportReminderConfig;
  if (dailyConfig.enabled) {
    try {
      final when = dailyConfig.nextDailyReminderTime(now);
      await notification.scheduleOnce(
        id: dailyId,
        title: '多仪每日复盘已生成',
        body: _reportDigestNotificationBody(
          kind: PeriodReportKind.daily,
          now: now,
          scheduledFor: when,
          todos: todos,
          habits: habits,
          pomodoros: pomodoros,
          timeAudit: timeAudit,
        ),
        when: when,
        payload: 'duoyi://report/daily',
      );
    } on NotificationPermissionDeniedException catch (e) {
      debugPrint('[ReportDigest] daily notification permission denied: $e');
    } catch (e, st) {
      debugPrint('[ReportDigest] daily schedule failed: $e\n$st');
    }
  }

  final weeklyConfig = prefs.weeklyReportReminderConfig;
  if (weeklyConfig.enabled) {
    try {
      final when = weeklyConfig.nextWeeklyReminderTime(now);
      await notification.scheduleOnce(
        id: weeklyId,
        title: '多仪周报已生成',
        body: _reportDigestNotificationBody(
          kind: PeriodReportKind.weekly,
          now: now,
          scheduledFor: when,
          todos: todos,
          habits: habits,
          pomodoros: pomodoros,
          timeAudit: timeAudit,
        ),
        when: when,
        payload: 'duoyi://report/weekly',
      );
    } on NotificationPermissionDeniedException catch (e) {
      debugPrint('[ReportDigest] weekly notification permission denied: $e');
    } catch (e, st) {
      debugPrint('[ReportDigest] weekly schedule failed: $e\n$st');
    }
  }

  final monthlyConfig = prefs.monthlyReportReminderConfig;
  if (monthlyConfig.enabled) {
    try {
      final when = monthlyConfig.nextMonthlyReminderTime(now);
      await notification.scheduleOnce(
        id: monthlyId,
        title: '多仪月报已生成',
        body: _reportDigestNotificationBody(
          kind: PeriodReportKind.monthly,
          now: now,
          scheduledFor: when,
          todos: todos,
          habits: habits,
          pomodoros: pomodoros,
          timeAudit: timeAudit,
        ),
        when: when,
        payload: 'duoyi://report/monthly',
      );
    } on NotificationPermissionDeniedException catch (e) {
      debugPrint('[ReportDigest] monthly notification permission denied: $e');
    } catch (e, st) {
      debugPrint('[ReportDigest] monthly schedule failed: $e\n$st');
    }
  }

  final yearlyConfig = prefs.yearlyReportReminderConfig;
  if (yearlyConfig.enabled) {
    try {
      final when = yearlyConfig.nextYearlyReminderTime(now);
      await notification.scheduleOnce(
        id: yearlyId,
        title: '多仪年度报告已生成',
        body: _reportDigestNotificationBody(
          kind: PeriodReportKind.yearly,
          now: now,
          scheduledFor: when,
          todos: todos,
          habits: habits,
          pomodoros: pomodoros,
          timeAudit: timeAudit,
        ),
        when: when,
        payload: 'duoyi://report/yearly',
      );
    } on NotificationPermissionDeniedException catch (e) {
      debugPrint('[ReportDigest] yearly notification permission denied: $e');
    } catch (e, st) {
      debugPrint('[ReportDigest] yearly schedule failed: $e\n$st');
    }
  }
}

String _reportDigestNotificationBody({
  required PeriodReportKind kind,
  required DateTime now,
  required DateTime scheduledFor,
  required TodoProvider todos,
  required HabitProvider habits,
  required PomodoroProvider pomodoros,
  required TimeAuditProvider timeAudit,
}) {
  final (start, end) = _reportDigestRange(
    kind: kind,
    now: now,
    scheduledFor: scheduledFor,
  );
  final (previousStart, previousEnd) = _previousReportRange(start, end);
  final report = ReportEngine.buildReport(
    start: start,
    end: end,
    todos: todos.todos,
    habits: habits.habits,
    sessions: pomodoros.sessions,
    timeEntries: timeAudit.entries,
  );
  final previousReport = ReportEngine.buildReport(
    start: previousStart,
    end: previousEnd,
    todos: todos.todos,
    habits: habits.habits,
    sessions: pomodoros.sessions,
    timeEntries: timeAudit.entries,
  );
  return PeriodReportDigest(
    kind: kind,
    report: report,
    comparison: ReportEngine.compare(current: report, previous: previousReport),
    generatedAt: now,
  ).notificationBody;
}

(DateTime, DateTime) _reportDigestRange({
  required PeriodReportKind kind,
  required DateTime now,
  required DateTime scheduledFor,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final scheduledDate = DateTime(
    scheduledFor.year,
    scheduledFor.month,
    scheduledFor.day,
  );
  final DateTime start;
  final DateTime completedEnd;
  switch (kind) {
    case PeriodReportKind.daily:
      start = scheduledDate;
      completedEnd = scheduledDate;
    case PeriodReportKind.weekly:
      start = scheduledDate.subtract(const Duration(days: 7));
      completedEnd = scheduledDate.subtract(const Duration(days: 1));
    case PeriodReportKind.monthly:
      start = DateTime(scheduledDate.year, scheduledDate.month - 1);
      completedEnd = DateTime(scheduledDate.year, scheduledDate.month, 0);
    case PeriodReportKind.yearly:
      start = DateTime(scheduledDate.year - 1);
      completedEnd = DateTime(scheduledDate.year - 1, 12, 31);
  }
  final end = completedEnd.isAfter(today) ? today : completedEnd;
  return (start, end.isBefore(start) ? start : end);
}

(DateTime, DateTime) _previousReportRange(DateTime start, DateTime end) {
  final startDate = DateTime(start.year, start.month, start.day);
  final endDate = DateTime(end.year, end.month, end.day);
  final days = endDate.difference(startDate).inDays + 1;
  final previousEnd = startDate.subtract(const Duration(days: 1));
  final previousStart = previousEnd.subtract(Duration(days: days - 1));
  return (previousStart, previousEnd);
}

void _queuePendingWidgetUri(Uri uri, String reason) {
  if (_pendingWidgetUris.any(
    (pending) => pending.toString() == uri.toString(),
  )) {
    return;
  }
  if (_pendingWidgetUris.length >= 20) {
    _pendingWidgetUris.removeAt(0);
  }
  _pendingWidgetUris.add(uri);
  debugPrint('[DeepLink] queued $uri: $reason');
}

void _drainPendingWidgetUris(PomodoroProvider pomodoro) {
  if (_pendingWidgetUris.isEmpty) return;
  final pending = List<Uri>.of(_pendingWidgetUris);
  _pendingWidgetUris.clear();
  for (final uri in pending) {
    _handleWidgetUri(uri, pomodoro, allowQueue: false);
  }
}

bool _reserveWidgetActionUri(Uri uri) {
  final now = DateTime.now();
  _recentWidgetActionUris.removeWhere(
    (_, at) => now.difference(at) > const Duration(seconds: 5),
  );
  final key = uri.toString();
  final last = _recentWidgetActionUris[key];
  if (last != null && now.difference(last) <= const Duration(seconds: 5)) {
    debugPrint('[DeepLink] duplicate widget action skipped: $uri');
    return false;
  }
  _recentWidgetActionUris[key] = now;
  return true;
}

void _handleWidgetUri(
  Uri? uri,
  PomodoroProvider pomodoro, {
  int retry = 0,
  bool allowQueue = true,
}) {
  if (uri == null) return;
  if (uri.scheme != 'duoyi') return;

  final state = mainShellKey.currentState;
  final ctx = mainShellKey.currentContext;
  if (state == null && retry < 8) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleWidgetUri(uri, pomodoro, retry: retry + 1);
    });
    return;
  }
  if (state == null) {
    if (allowQueue) {
      _queuePendingWidgetUri(uri, 'main shell not ready after $retry frames');
    } else {
      debugPrint('[DeepLink] dropped $uri: main shell not ready');
    }
    return;
  }

  if (uri.host == 'tab') {
    final tab = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    final idx = switch (tab) {
      'today' => 0,
      'todo' => 1,
      'habit' => 2,
      'calendar' => 3,
      'focus' => 4,
      'widget' => 5,
      'mine' => 6,
      _ => 3,
    };
    state.navigateTo(idx, allowHidden: true);
  } else if (uri.host == 'oauth' && ctx != null) {
    state.navigateTo(6, allowHidden: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final latestContext = mainShellKey.currentContext ?? ctx;
      Navigator.of(latestContext).push(
        MaterialPageRoute(
          builder: (_) => BrandRouteSurface(
            child: IntegrationsScreen(initialOAuthCallbackUri: uri),
          ),
        ),
      );
    });
  } else if (uri.host == 'todo' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (id == null || id.isEmpty) {
      state.navigateTo(1, allowHidden: true);
      return;
    }
    state.navigateTo(1, allowHidden: true);
    final confirm = uri.queryParameters['confirm'] == '1';
    if (confirm) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showTodoCompletePrompt(ctx, id);
      });
    } else {
      // ignore: discarded_futures
      TodayDetailRouter.open(ctx, TodaySectionKind.todos, id: id);
    }
  } else if (uri.host == 'goal' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (id == null || id.isEmpty) {
      _pushHiddenWidgetFallbackRoute(ctx, const GoalScreen());
      return;
    }
    state.navigateTo(0, allowHidden: true);
    // ignore: discarded_futures
    TodayDetailRouter.open(ctx, TodaySectionKind.goals, id: id);
  } else if (uri.host == 'habit' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    state.navigateTo(2, allowHidden: true);
    if (id == null || id.isEmpty) return;
    final confirm = uri.queryParameters['confirm'] == '1';
    if (confirm) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showHabitCheckInPrompt(ctx, id);
      });
    } else {
      // ignore: discarded_futures
      TodayDetailRouter.open(ctx, TodaySectionKind.habits, id: id);
    }
  } else if (uri.host == 'calendar') {
    state.navigateTo(3, allowHidden: true);
  } else if (uri.host == 'focus') {
    state.navigateTo(4, allowHidden: true);
  } else if (uri.host == 'widget') {
    state.navigateTo(5, allowHidden: true);
  } else if (uri.host == 'course' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (id == null || id.isEmpty) {
      _pushHiddenWidgetFallbackRoute(ctx, const CourseScheduleScreen());
      return;
    }
    state.navigateTo(0, allowHidden: true);
    // ignore: discarded_futures
    TodayDetailRouter.open(ctx, TodaySectionKind.courses, id: id);
  } else if (uri.host == 'anniversary' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (id == null || id.isEmpty) {
      _pushHiddenWidgetFallbackRoute(ctx, const AnniversaryScreen());
      return;
    }
    state.navigateTo(0, allowHidden: true);
    // ignore: discarded_futures
    TodayDetailRouter.open(ctx, TodaySectionKind.anniversaries, id: id);
  } else if (uri.host == 'countdown' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    _pushHiddenWidgetFallbackRoute(
      ctx,
      CountdownScreen(initialCountdownId: id),
    );
  } else if (uri.host == 'note' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (id == null || id.isEmpty) {
      _pushHiddenWidgetFallbackRoute(ctx, const NoteScreen());
    } else {
      state.navigateTo(0, allowHidden: true);
      // ignore: discarded_futures
      TodayDetailRouter.open(ctx, TodaySectionKind.notes, id: id);
    }
  } else if (uri.host == 'time-entry' && ctx != null) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    state.navigateTo(6, allowHidden: true);
    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) =>
            BrandRouteSurface(child: TimeAuditScreen(initialEntryId: id)),
      ),
    );
  } else if (uri.host == 'report' && ctx != null) {
    state.navigateTo(6, allowHidden: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final latestContext = mainShellKey.currentContext ?? ctx;
      Navigator.of(latestContext).push(
        MaterialPageRoute(
          builder: (_) => const BrandRouteSurface(child: StatisticsScreen()),
        ),
      );
    });
  } else if (uri.host == 'location' && ctx != null) {
    state.navigateTo(6, allowHidden: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final latestContext = mainShellKey.currentContext ?? ctx;
      Navigator.of(latestContext).push(
        MaterialPageRoute(
          builder: (_) => const BrandRouteSurface(child: IntegrationsScreen()),
        ),
      );
    });
  } else if (uri.host == 'snooze' && ctx != null) {
    // 稍后提醒深链：duoyi://snooze/<id>?delay=<minutes>&title=...&body=...&payload=...
    final ns = Provider.of<NotificationService>(ctx, listen: false);
    // ignore: discarded_futures
    ns.handleSnoozeDeepLink(uri);
  } else if (uri.host == 'action') {
    final action = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    if (!_reserveWidgetActionUri(uri)) return;
    if (action == 'start_pomodoro') {
      state.navigateTo(4, allowHidden: true);
      if (pomodoro.state.isRunning) {
        if (ctx != null) _showWidgetActionFeedback(ctx, '专注计时正在进行');
      } else {
        pomodoro.startIfIdle();
        if (ctx != null) _showWidgetActionFeedback(ctx, '已开始专注');
      }
    } else if (action == 'quick_todo' && ctx != null) {
      final text = uri.queryParameters['text']?.trim();
      state.navigateTo(1, allowHidden: true);
      if (text != null && text.isNotEmpty) {
        final draft = SmartTodoDraftBuilder.fromText(text);
        unawaited(_createQuickTodoFromAction(ctx, draft.toTodo()));
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_showQuickTodoDialog(ctx));
      });
    } else if (action == 'complete_todo' && ctx != null) {
      final id = uri.queryParameters['id'];
      if (id == null || id.isEmpty) return;
      state.navigateTo(1, allowHidden: true);
      final todos = Provider.of<TodoProvider>(ctx, listen: false);
      final target = todos.todos.where((todo) => todo.id == id).firstOrNull;
      // 与后台动作共用同一套目标校验，避免两处判断漂移。
      switch (homeWidgetTodoTargetState(target)) {
        case HomeWidgetTodoTargetState.missing:
          _showWidgetActionFeedback(ctx, '这个任务不存在或已被删除');
        case HomeWidgetTodoTargetState.alreadyCompleted:
          _showWidgetActionFeedback(ctx, '“${target!.title}”已经完成');
        case HomeWidgetTodoTargetState.ready:
          unawaited(_completeTodoFromWidgetAction(ctx, todos, target!));
      }
    } else if (action == 'checkin_habit' && ctx != null) {
      final id = uri.queryParameters['id'];
      state.navigateTo(2, allowHidden: true);
      if (id == null || id.isEmpty) return;
      final habits = Provider.of<HabitProvider>(ctx, listen: false);
      final target = habits.habits.where((habit) => habit.id == id).firstOrNull;
      // 与后台动作共用同一套目标校验，避免两处判断漂移。
      switch (homeWidgetHabitTargetState(target)) {
        case HomeWidgetHabitTargetState.missing:
          _showWidgetActionFeedback(ctx, '这个习惯不存在或已被删除');
        case HomeWidgetHabitTargetState.unsupportedKind:
          _showWidgetActionFeedback(ctx, '这个习惯不支持快捷打卡');
        case HomeWidgetHabitTargetState.notActiveToday:
          _showWidgetActionFeedback(ctx, '“${target!.name}”今天不需要打卡');
        case HomeWidgetHabitTargetState.alreadyCompleted:
          _showWidgetActionFeedback(ctx, '“${target!.name}”今天已经完成');
        case HomeWidgetHabitTargetState.ready:
          final habit = target!;
          unawaited(
            habits.incrementHabit(id).then((_) {
              _showWidgetActionFeedbackFromShell('已打卡：${habit.name}');
            }),
          );
      }
    }
  } else {
    debugPrint('[DeepLink] unknown duoyi host: ${uri.host} uri=$uri');
    state.navigateTo(6, allowHidden: true);
    if (ctx != null) {
      _showWidgetActionFeedback(ctx, '无法识别的入口，已返回我的');
    }
  }
}

void _pushHiddenWidgetFallbackRoute(BuildContext context, Widget child) {
  mainShellKey.currentState?.navigateTo(6, allowHidden: true);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final latestContext = mainShellKey.currentContext ?? context;
    if (!latestContext.mounted) return;
    Navigator.of(
      latestContext,
    ).push(MaterialPageRoute(builder: (_) => BrandRouteSurface(child: child)));
  });
}

void _showWidgetActionFeedback(BuildContext context, String message) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final latestContext = mainShellKey.currentContext ?? context;
    if (!latestContext.mounted) return;
    ScaffoldMessenger.of(latestContext)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1400),
        ),
      );
  });
}

void _showWidgetActionFeedbackFromShell(String message) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final latestContext = mainShellKey.currentContext;
    if (latestContext == null || !latestContext.mounted) return;
    ScaffoldMessenger.of(latestContext)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1400),
        ),
      );
  });
}

Future<void> _createQuickTodoFromAction(
  BuildContext context,
  TodoItem todo,
) async {
  try {
    if (!await _preflightQuickTodoReminder(
      context,
      todo,
      feedback: _showWidgetActionFeedbackFromShell,
    )) {
      return;
    }
    final latestContext = mainShellKey.currentContext ?? context;
    if (!latestContext.mounted) return;
    final todos = Provider.of<TodoProvider?>(latestContext, listen: false);
    if (todos == null) {
      debugPrint(
        '[QuickTodoAction] TodoProvider unavailable for action create',
      );
      _showWidgetActionFeedbackFromShell('快捷待办暂不可用，请打开待办页后重试');
      return;
    }
    await todos.addTodo(todo);
    _showWidgetActionFeedbackFromShell(_quickTodoCreatedMessage(todo));
  } catch (e, st) {
    debugPrint('[QuickTodoAction] create failed: $e\n$st');
    _showWidgetActionFeedbackFromShell('快捷待办创建失败，请稍后重试');
  }
}

Future<void> _completeTodoFromWidgetAction(
  BuildContext context,
  TodoProvider todos,
  TodoItem target,
) async {
  final title = target.title;
  final changed = await todos.completeTodos([target.id]);
  if (!context.mounted && mainShellKey.currentContext == null) return;
  _showWidgetActionFeedbackFromShell(
    changed > 0 ? '已完成：$title' : '“$title”已经完成',
  );
}

Future<bool> _preflightQuickTodoReminder(
  BuildContext context,
  TodoItem todo, {
  required void Function(String message) feedback,
  String issueTitle = '待办提醒注册失败',
}) async {
  late final TodoReminderPreflightResult preflight;
  try {
    preflight = preflightTodoReminderPlan(todo);
  } catch (e, st) {
    debugPrint('[QuickTodoAction] reminder preflight failed: $e\n$st');
    feedback('$issueTitle：提醒配置异常，请在待办详情中重新设置提醒。');
    return false;
  }
  if (!preflight.hasEnabledPlan) return true;

  final blocking = preflight.blockingIssue;
  if (blocking != null) {
    feedback('${blocking.title}：${blocking.message}');
    return false;
  }

  final usesPush = preflight.kinds.contains(ReminderKind.push);
  final usesPopup = preflight.kinds.contains(ReminderKind.popup);
  final usesAlarm = preflight.kinds.contains(ReminderKind.alarm);
  if (!usesPush && !usesPopup && !usesAlarm) return true;
  final latestContext = mainShellKey.currentContext ?? context;
  if (!latestContext.mounted) return false;
  NotificationService? notification;
  try {
    notification = Provider.of<NotificationService?>(
      latestContext,
      listen: false,
    );
  } catch (e, st) {
    debugPrint('[QuickTodoAction] notification provider unavailable: $e\n$st');
  }
  if (notification != null && (usesPush || usesPopup)) {
    final ready = await notification
        .ensureReadyForReminder(
          scheduledTime: preflight.firstScheduledTime,
          issueTitle: issueTitle,
          relatedId: todo.id,
        )
        .catchError((Object e, StackTrace st) {
          debugPrint(
            '[QuickTodoAction] notification preflight failed: $e\n$st',
          );
          return false;
        });
    if (ready) return true;
    final issue = notification.lastScheduleIssue;
    feedback(
      issue == null
          ? '$issueTitle：提醒未注册，请检查通知权限、渠道声音和提醒时间。'
          : '${issue.title}：${issue.message}',
    );
    return false;
  }
  if (usesAlarm) {
    final granted = await LocalNotifications.instance
        .ensurePermission()
        .catchError((Object e, StackTrace st) {
          debugPrint(
            '[QuickTodoAction] alarm permission preflight failed: $e\n$st',
          );
          return false;
        });
    if (!granted) {
      feedback('$issueTitle：系统通知权限未开启，闹钟提醒未注册。请开启通知权限后重新保存提醒。');
      return false;
    }
    // 与待办详情保存保持一致：主动申请精准闹钟 / 全屏 intent 权限，
    // 否则首条闹钟提醒会静默降级，必须先点一次“测试强提醒”才会被授权。
    try {
      final hasExact = await AlarmService.instance.hasExactAlarmPermission();
      if (!hasExact) await AlarmService.instance.requestExactAlarmPermission();
      final hasFullScreen = await AlarmService.instance
          .hasFullScreenIntentPermission();
      if (!hasFullScreen) {
        await AlarmService.instance.requestFullScreenIntentPermission();
      }
    } catch (e, st) {
      debugPrint(
        '[QuickTodoAction] alarm exact/fullscreen request failed: $e\n$st',
      );
    }
    return true;
  }
  return true;
}

String _quickTodoCreatedMessage(TodoItem todo) {
  try {
    final preflight = preflightTodoReminderPlan(todo);
    return preflight.hasEnabledPlan ? '已创建待办，提醒状态可在通知设置/待办详情检查' : '已创建待办';
  } catch (e, st) {
    debugPrint('[QuickTodoAction] created message preflight failed: $e\n$st');
    return '已创建待办，提醒状态可在待办详情中检查';
  }
}

Future<bool> _syncNotificationQuickAdd(
  PreferencesProvider prefs, {
  required TodoProvider todos,
  required HabitProvider habits,
  required GoalProvider goals,
  bool requestIfNeeded = false,
  bool force = false,
}) async {
  final todayProgress = prefs.notificationTodayProgress;
  final progress = todayProgress
      ? _todayTaskProgressNotificationBody(
          todos.todos,
          habits: habits,
          goals: goals,
        )
      : '';
  final plan = buildNotificationStatusBarPlan(
    notificationQuickAdd: prefs.notificationQuickAdd,
    notificationTodayProgress: todayProgress,
    todayProgressBody: progress,
  );
  if (plan.shouldShow) {
    try {
      await LocalNotifications.instance.showQuickAddOngoing(
        title: plan.title,
        body: plan.body,
        enableQuickActions: plan.enableQuickActions,
        requestIfNeeded: requestIfNeeded,
        force: force,
      );
      return true;
    } on NotificationPermissionDeniedException catch (e) {
      debugPrint('[NotificationStatusBar] notification permission denied: $e');
      return false;
    } catch (e, st) {
      debugPrint('[NotificationStatusBar] show failed: $e\n$st');
      return false;
    }
  } else {
    try {
      await LocalNotifications.instance.cancelQuickAddOngoing();
      return true;
    } catch (e, st) {
      debugPrint('[NotificationStatusBar] cancel failed: $e\n$st');
      return false;
    }
  }
}

Duration _durationUntilNextLocalDay() {
  final now = AppClock.now();
  final nextDay = AppClock.date(now.year, now.month, now.day + 1, 0, 0, 2);
  final delay = nextDay.difference(now);
  return delay.isNegative ? const Duration(seconds: 2) : delay;
}

String _todayTaskProgressNotificationBody(
  List<TodoItem> todos, {
  required HabitProvider habits,
  required GoalProvider goals,
}) {
  final now = AppClock.now();
  final visibleTodos = todos
      .where((todo) => CompletionVisibilityPolicy.shouldShowInToday(todo, now))
      .toList(growable: false);
  final todoCount = visibleTodos.length;
  final dailyCount = habits.habits
      .where(
        (habit) => habit.activeForDate(now) && !habit.isCompletedForDate(now),
      )
      .length;
  final goalCount = goals.activeGoals.length;
  final remaining = dailyCount + todoCount + goalCount;
  return formatNotificationTodayProgressBody(
    remaining: remaining,
    dailyCount: dailyCount,
    todoCount: todoCount,
    goalCount: goalCount,
  );
}

Future<void> _showQuickTodoDialog(BuildContext context) async {
  if (!context.mounted) return;
  await showTodoCreateSheet(context);
}

Future<void> _showSharedTextImportSheet(String rawText) async {
  final text = rawText.trim();
  final context = mainShellKey.currentContext;
  if (text.isEmpty || context == null || !context.mounted) return;

  final action = await showAppModalSheet<String>(
    context: context,
    builder: (sheetContext) => AppModalSheet(
      title: '导入分享文本',
      subtitle: '选择保存位置',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(
                  sheetContext,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(sheetContext).colorScheme.outlineVariant,
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  text,
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (buttonContext, constraints) {
              final compact = constraints.maxWidth < 420;
              final saveNote = OutlinedButton.icon(
                icon: const Icon(Icons.notes_outlined),
                onPressed: () => Navigator.of(buttonContext).pop('note'),
                label: const Text('保存笔记'),
              );
              final createTodo = FilledButton.icon(
                icon: const Icon(Icons.checklist),
                onPressed: () => Navigator.of(buttonContext).pop('todo'),
                label: const Text('创建待办'),
              );
              final cancel = TextButton(
                onPressed: () => Navigator.of(buttonContext).pop(),
                child: Text(I18n.tr('action.cancel')),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    createTodo,
                    const SizedBox(height: 8),
                    saveNote,
                    const SizedBox(height: 4),
                    cancel,
                  ],
                );
              }
              return Row(
                children: [
                  cancel,
                  const Spacer(),
                  Expanded(child: saveNote),
                  const SizedBox(width: 8),
                  Expanded(child: createTodo),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
  if (action == null) return;

  final latestContext = mainShellKey.currentContext;
  if (latestContext == null || !latestContext.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(latestContext);

  if (action == 'todo') {
    final draft = SmartTodoDraftBuilder.fromText(text);
    final todo = draft.toTodo();
    if (!await _preflightQuickTodoReminder(
      latestContext,
      todo,
      feedback: (message) => _showContextSnackBar(latestContext, message),
    )) {
      return;
    }
    if (!latestContext.mounted) return;
    await latestContext.read<TodoProvider>().addTodo(todo);
    mainShellKey.currentState?.navigateTo(1, allowHidden: true);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(_quickTodoCreatedMessage(todo)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  } else if (action == 'note') {
    final now = DateTime.now();
    latestContext.read<NoteProvider>().addOrUpdateNote(
      NoteItem(
        id: now.millisecondsSinceEpoch.toString(),
        content: text,
        createdAt: now,
        updatedAt: now,
      ),
    );
    Navigator.of(latestContext).push(
      MaterialPageRoute(
        builder: (_) => const BrandRouteSurface(child: NoteScreen()),
      ),
    );
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('已保存笔记'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

void _showContextSnackBar(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
}

Future<void> _showTodoCompletePrompt(
  BuildContext context,
  String todoId,
) async {
  if (!context.mounted) return;
  final todos = Provider.of<TodoProvider>(context, listen: false);
  final todo = todos.todos.where((t) => t.id == todoId).firstOrNull;
  final messenger = ScaffoldMessenger.of(context);
  if (todo == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('这个任务不存在或已被删除'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }
  if (todo.isCompleted) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('“${todo.title}”已经完成'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  await completeTodoWithOptionalTimeRecord(context, todo);
}

Future<void> _showHabitCheckInPrompt(
  BuildContext context,
  String habitId,
) async {
  if (!context.mounted) return;
  final habits = Provider.of<HabitProvider>(context, listen: false);
  final habit = habits.habits.where((h) => h.id == habitId).firstOrNull;
  final messenger = ScaffoldMessenger.of(context);
  if (habit == null) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('这个习惯不存在或已被删除'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }
  if (habit.isCompletedToday()) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('“${habit.name}”今天已经完成'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  // 习惯打卡默认弹出框，但不再提供"稍后/完成"二选一选项：
  // 弹窗内只保留单个"完成打卡"按钮，点击即打卡，避免打断节奏。
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AppDialog(
      icon: const Icon(Icons.check_circle_outline),
      title: Text('打卡：${habit.name}'),
      content: Text(
        habit.targetCount > 1
            ? '今天已打卡 ${habit.todayCount()} / ${habit.targetCount} 次，继续打卡吗？'
            : '现在完成“${habit.name}”打卡吗？',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogCtx).pop(true),
          child: const Text('完成打卡'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await habits.incrementHabit(habitId);
  if (!context.mounted) return;
  final done =
      habits.habits
          .where((h) => h.id == habitId)
          .firstOrNull
          ?.isCompletedToday() ??
      false;
  messenger.showSnackBar(
    SnackBar(
      content: Text(done ? '“${habit.name}”今日已达标，真棒！' : '已打卡：${habit.name}'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

class DuoyiApp extends StatefulWidget {
  const DuoyiApp({super.key});

  @override
  State<DuoyiApp> createState() => _DuoyiAppState();
}

class _DuoyiAppState extends State<DuoyiApp> with WidgetsBindingObserver {
  final _keyboardObserver = KeyboardDismissNavigatorObserver();

  /// 缓存上一次已知的"本地日"，用于在 resumed 时判定是否跨天。
  /// 初始值写入于 [initState]。
  DateTime? _lastLifecycleDay;

  /// 缓存上一次已知的系统 IANA 时区名。
  ///
  /// 在 [initState] 初始化为 `LocalTimezoneResolver.currentIana`；
  /// 之后每次 `AppLifecycleState.resumed` 都会先刷新时区再与此值比较，
  /// 差异即排队重放提醒（Requirements 8.6 / 8.8）。
  String? _lastIana;
  bool? _lastExactAlarmGranted;
  AchievementProvider? _achievementProvider;
  FocusRoomProvider? _focusRoomProvider;
  AppUpdateService? _appUpdateService;
  DateTime? _lastUpdatePolicyCheckAt;
  DateTime? _lastAccountProfileRefreshAt;
  Timer? _updatePolicyCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = AppClock.now();
    _lastLifecycleDay = DateTime(now.year, now.month, now.day);
    _lastIana = LocalTimezoneResolver.currentIana;
    _lastExactAlarmGranted = _initialExactAlarmGranted;
    _lastUpdatePolicyCheckAt = null;
    _lastAccountProfileRefreshAt = now;
  }

  @override
  void dispose() {
    _achievementProvider?.removeListener(_showAchievementFeedback);
    _focusRoomProvider?.stopRealtimeRankings();
    _updatePolicyCheckTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<AchievementProvider>();
    if (_achievementProvider != provider) {
      _achievementProvider?.removeListener(_showAchievementFeedback);
      _achievementProvider = provider;
      provider.addListener(_showAchievementFeedback);
    }
    _focusRoomProvider = context.read<FocusRoomProvider>();
    _appUpdateService = context.read<AppUpdateService>();
  }

  void _showAchievementFeedback() {
    final provider = _achievementProvider;
    if (provider == null) return;
    final unlocked = provider.takeUnlockedFeedback();
    if (unlocked.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      for (final achievement in unlocked) {
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                Icon(achievement.icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('解锁成就：${achievement.title}')),
              ],
            ),
          ),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = context.read<AppLockProvider>();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      lock.onAppLifecycleInactive();
    } else if (state == AppLifecycleState.resumed) {
      lock.onAppLifecycleResume();
      _checkUpdatePolicy(force: true);
      _refreshAccountProfileOnResume();
      // 先处理时区变更（可能影响调度），再做跨日 rollover。
      unawaited(() async {
        await _maybeResyncOnTimezoneChange();
        if (!mounted) return;
        _maybeRunDailyRolloverOnResume();
        _refreshNotificationProgressOnResume();
      }());
      _refreshNotificationPermissionsOnResume();
    }
  }

  /// App 回到前台时刷新账号资料。
  ///
  /// 账号资料保存在后端 users 表，不一定会跟随云同步 payload 变化；这里用
  /// `/api/auth/me` 轻量刷新，避免多设备修改昵称、头像、邮箱验证状态后，本机
  /// 只有重启才更新。
  void _refreshAccountProfileOnResume() {
    final ctx = mainShellKey.currentContext ?? context;
    final auth = Provider.of<AuthProvider>(ctx, listen: false);
    if (!auth.state.isLoggedIn) return;
    final now = DateTime.now();
    final previous = _lastAccountProfileRefreshAt;
    if (previous != null &&
        now.difference(previous) < const Duration(minutes: 10)) {
      return;
    }
    _lastAccountProfileRefreshAt = now;

    // ignore: discarded_futures
    Future.microtask(() async {
      try {
        await auth.refreshMe();
      } catch (e, st) {
        debugPrint('[DuoyiApp] refresh account profile failed: $e\n$st');
      }
    });
  }

  void _checkUpdatePolicy({bool force = false}) {
    if (!force && _updatePolicyCheckTimer?.isActive == true) return;
    // 首帧之后尽快刷新强更策略；同一轮生命周期只保留一个待执行任务。
    _updatePolicyCheckTimer?.cancel();
    _updatePolicyCheckTimer = Timer(
      force ? Duration.zero : const Duration(seconds: 2),
      () {
        final now = DateTime.now();
        final previous = _lastUpdatePolicyCheckAt;
        if (!force &&
            previous != null &&
            now.difference(previous) < const Duration(minutes: 30)) {
          return;
        }
        _lastUpdatePolicyCheckAt = now;
        final updater = _appUpdateService;
        if (updater == null) return;
        if (updater.checking) return;
        // ignore: discarded_futures
        updater.checkServerPolicyNow();
      },
    );
  }

  /// 检测系统时区在后台是否被修改；若有变化则刷新 `tz.local` 并排队
  /// 重放提醒，保证壁钟时间不变。
  ///
  /// 对应 Requirements 8.6 / 8.8：
  /// - 8.6：resumed 且 IANA 变化时重新 `tz.setLocalLocation` 并 resync；
  /// - 8.8：resync 后新调度的 `(hour, minute)` 仍等于用户原设定。
  Future<void> _maybeResyncOnTimezoneChange() async {
    final prevIana = _lastIana;
    try {
      await LocalTimezoneResolver.refresh();
      if (!mounted) return;
      context.read<PreferencesProvider>().refreshResolvedTimeZone();
      final currentIana = LocalTimezoneResolver.currentIana;
      if (prevIana != null && prevIana == currentIana) return;
      _lastIana = currentIana;
      await _queueFullReminderResyncCallback?.call(
        delay: Duration.zero,
        reason: 'system timezone changed',
      );
    } catch (e, st) {
      debugPrint('[DuoyiApp] timezone refresh/resync failed: $e\n$st');
    }
  }

  /// 从系统设置返回时刷新通知 / 闹钟权限状态。
  ///
  /// 若通知权限或精准闹钟权限发生变化，则重放一轮提醒调度，保证
  /// 现有提醒使用最新的系统授权状态。
  void _refreshNotificationPermissionsOnResume() {
    final ctx = mainShellKey.currentContext ?? context;
    final notif = Provider.of<NotificationService>(ctx, listen: false);

    final prevNotifGranted = notif.permissionGranted;
    final prevExactGranted = _lastExactAlarmGranted;

    // ignore: discarded_futures
    Future.microtask(() async {
      try {
        final notifGranted = await notif.refreshPermission();
        final exactGranted = await AlarmService.instance
            .hasExactAlarmPermission();
        _lastExactAlarmGranted = exactGranted;
        final exactChanged =
            prevExactGranted != null && prevExactGranted != exactGranted;
        if (prevNotifGranted == notifGranted && !exactChanged) return;
        await _queueFullReminderResyncCallback?.call(
          delay: Duration.zero,
          reason: 'notification permission changed',
        );
      } catch (e, st) {
        debugPrint('[DuoyiApp] refresh permission/resync failed: $e\n$st');
      }
    });
  }

  /// 当 App 从后台回到前台时，若"本地日"发生变化则触发一次
  /// [CompletionVisibilityPolicy.runDailyRollover]。
  ///
  /// 调用路径对应 `requirements.md` 3.3：滚动归档必须在进程复用的长时间
  /// 后台场景下也能按时执行。时区刷新由 [_maybeResyncOnTimezoneChange]
  /// 负责，不在这里重复。
  void _maybeRunDailyRolloverOnResume() {
    final now = AppClock.now();
    final today = DateTime(now.year, now.month, now.day);
    final last = _lastLifecycleDay;
    _lastLifecycleDay = today;
    if (last != null && last.isAtSameMomentAs(today)) {
      return;
    }
    // 本地日发生滚动：通知 AppClock 的监听方（今日页、统计等）刷新。
    AppClock.notifyDayChanged();

    // 同步读取 TodoProvider / GoalProvider，避免在异步 gap 之后再使用 BuildContext。
    // `DuoyiApp` 是应用根 widget，`mainShellKey` 在冷启动初期可能尚未 attach，
    // 两处都位于 MultiProvider 之下，任一命中即可拿到实例。
    final ctx = mainShellKey.currentContext ?? context;
    final provider = Provider.of<TodoProvider>(ctx, listen: false);
    final habitProv = Provider.of<HabitProvider>(ctx, listen: false);
    final pomodoroProv = Provider.of<PomodoroProvider>(ctx, listen: false);
    final timeAuditProv = Provider.of<TimeAuditProvider>(ctx, listen: false);
    final goalProv = Provider.of<GoalProvider>(ctx, listen: false);
    final prefs = Provider.of<PreferencesProvider>(ctx, listen: false);
    final notif = Provider.of<NotificationService>(ctx, listen: false);

    // 异步触发，不阻塞 lifecycle 回调。
    // ignore: discarded_futures
    Future.microtask(() async {
      await CompletionVisibilityPolicy.runDailyRollover(
        provider,
        now,
        goalProvider: goalProv,
      );
      await _syncDailyDigestReminder(prefs, notif, provider);
      await _syncReportDigestReminders(
        prefs,
        notif,
        todos: provider,
        habits: habitProv,
        pomodoros: pomodoroProv,
        timeAudit: timeAuditProv,
      );
    });
  }

  void _refreshNotificationProgressOnResume() {
    // ignore: discarded_futures
    Future.microtask(() async {
      await _syncNotificationQuickAddDedupedCallback?.call(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.watch<ThemeProvider>().brand;
    final lock = context.watch<AppLockProvider>();
    final locale = context.watch<LocaleProvider>();
    final mustUpdate = context.select<AppUpdateService, bool>(
      (updater) => updater.mustUpdate,
    );
    return MaterialApp(
      // Static force-update contract: home: updater.mustUpdate.
      title: brand.strings.appTitle,
      debugShowCheckedModeBanner: false,
      locale: locale.flutterLocale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      scrollBehavior: const KeyboardDismissScrollBehavior(),
      navigatorObservers: [_keyboardObserver],
      builder: (context, child) {
        // 应用字号是设备本地偏好，与系统字号相乘后只作用于多仪内部文字；
        // 这里只替换 textScaler，padding / viewInsets 仍沿用系统值。
        final mediaQuery = MediaQuery.of(context);
        final textScale = context.select<PreferencesProvider, double>(
          (prefs) => prefs.textScale,
        );
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: AppTextScale.resolve(
              system: mediaQuery.textScaler,
              appScale: textScale,
            ),
          ),
          child: KeyboardDismissScope(
            child: Theme(
              data: AppMotion.themeFor(context, Theme.of(context)),
              child: AppClockScope(
                child: WebAuthGate(
                  enabled: WebTarget.isWebBuild && !mustUpdate,
                  child: child!,
                ),
              ),
            ),
          ),
        );
      },
      theme: brand.theme,
      themeAnimationStyle: AppMotion.overlayStyle(context),
      home: mustUpdate
          ? const Stack(children: [ForceUpdateGate()])
          : Stack(
              children: [
                MainShell(key: mainShellKey),
                if (lock.isLocked)
                  const Positioned.fill(child: Material(child: LockScreen())),
                const ForceUpdateGate(),
              ],
            ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  static const _tabCount = 7;
  static const _fallbackVisibleTabs = <int>[0, 1, 2, 4, 6];

  int _currentIndex = 0; // Today first
  bool _allowHiddenCurrentIndex = false;
  bool _hasExplicitNavigation = false;
  final Set<int> _builtTabs = <int>{0};

  static final GlobalKey todayKey = GlobalKey();
  static final GlobalKey todoKey = GlobalKey();
  static final GlobalKey habitKey = GlobalKey();
  static final GlobalKey calendarKey = GlobalKey();
  static final GlobalKey pomodoroKey = GlobalKey();
  static final GlobalKey widgetKey = GlobalKey();
  static final GlobalKey mineKey = GlobalKey();

  List<int> _visibleBottomNavTabs(PreferencesProvider prefs) {
    final result = prefs.visibleBottomNavTabs
        .where(
          (tab) =>
              tab >= 0 &&
              tab < _tabCount &&
              PreferencesProvider.isBottomNavTabSupported(tab),
        )
        .toList(growable: false);
    final visible = result.length < 2 ? _fallbackVisibleTabs : result;
    return List.unmodifiable(visible);
  }

  int _coerceTabIndex(int index) {
    final visibleTabs = _visibleBottomNavTabs(
      context.read<PreferencesProvider>(),
    );
    if (index >= 0 &&
        index < _tabCount &&
        (visibleTabs.isEmpty || visibleTabs.contains(index))) {
      return index;
    }
    if (visibleTabs.isNotEmpty) return visibleTabs.first;
    return index.clamp(0, _tabCount - 1);
  }

  void navigateTo(int index, {bool allowHidden = false}) {
    if (!mounted) return;
    final target = allowHidden
        ? index.clamp(0, _tabCount - 1)
        : _coerceTabIndex(index);
    KeyboardDismissScope.dismiss();
    setState(() {
      _currentIndex = target;
      _builtTabs.add(target);
      _allowHiddenCurrentIndex = allowHidden;
      _hasExplicitNavigation = true;
    });
  }

  @override
  void initState() {
    super.initState();
    // 延迟一帧再读 PreferencesProvider，避免 initState 中 read 异常
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _drainPendingWidgetUris(context.read<PomodoroProvider>());
      if (_hasExplicitNavigation) return;
      final target = _coerceTabIndex(
        context.read<PreferencesProvider>().defaultTab,
      );
      if (target != _currentIndex) {
        setState(() {
          _currentIndex = target;
          _builtTabs.add(target);
          _allowHiddenCurrentIndex = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();
    // 底导航标签随主题品牌文案变化（BrandStrings.nav*）。
    final brand = context.watch<ThemeProvider>().brand.strings;
    final safeVisibleTabs = _visibleBottomNavTabs(prefs);
    var safeIndex = _currentIndex.clamp(0, _tabCount - 1);
    if (!safeVisibleTabs.contains(safeIndex) && !_allowHiddenCurrentIndex) {
      safeIndex = safeVisibleTabs.first;
    }
    _builtTabs.add(safeIndex);
    if (safeIndex != _currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _currentIndex = safeIndex;
            _builtTabs.add(safeIndex);
            _allowHiddenCurrentIndex = false;
          });
        }
      });
    }
    final allDestinations = [
      NavigationDestination(
        icon: const Icon(Icons.today_outlined),
        selectedIcon: const Icon(Icons.today),
        label: brand.navToday,
      ),
      NavigationDestination(
        icon: const Icon(Icons.checklist),
        selectedIcon: const Icon(Icons.checklist_rounded),
        label: brand.navTodo,
      ),
      NavigationDestination(
        icon: const Icon(Icons.repeat),
        selectedIcon: const Icon(Icons.repeat_rounded),
        label: brand.navHabit,
      ),
      NavigationDestination(
        icon: const Icon(Icons.calendar_month_outlined),
        selectedIcon: const Icon(Icons.calendar_month),
        label: brand.navCalendar,
      ),
      NavigationDestination(
        icon: const Icon(Icons.timer_outlined),
        selectedIcon: const Icon(Icons.timer),
        label: brand.navFocus,
      ),
      NavigationDestination(
        icon: const Icon(Icons.widgets_outlined),
        selectedIcon: const Icon(Icons.widgets_rounded),
        label: brand.navWidget,
      ),
      NavigationDestination(
        icon: const Icon(Icons.person_outline),
        selectedIcon: const Icon(Icons.person),
        label: brand.navMine,
      ),
    ];
    final selectedNavIndex = safeVisibleTabs.indexOf(safeIndex);
    final showingHiddenTab =
        _allowHiddenCurrentIndex && !safeVisibleTabs.contains(safeIndex);
    final notification = context
        .select<NotificationService, ({bool hasUnreadHistory})>(
          (notification) => (hasUnreadHistory: notification.hasUnreadHistory),
        );
    final updateHasUpdate = context.select<AppUpdateService, bool>(
      (updater) => updater.hasUpdate,
    );
    final showMineBadge = notification.hasUnreadHistory || updateHasUpdate;
    final navDestinations = safeVisibleTabs
        .map((tab) {
          final destination = allDestinations[tab];
          if (tab != 6 || !showMineBadge) return destination;
          return NavigationDestination(
            icon: const _BottomNavBadgeIcon(child: Icon(Icons.person_outline)),
            selectedIcon: const _BottomNavBadgeIcon(child: Icon(Icons.person)),
            label: brand.navMine,
          );
        })
        .toList(growable: false);

    // 宽屏外壳分派不再吃编译期 DUOYI_WEB_TARGET 档位：此前只有 desktop
    // 包能进 rail 壳，responsive 包、dev web 与 Linux 桌面端（kIsWeb=false）
    // 永远走移动壳（底导航全宽拉伸），是宽屏"大号手机感"的根因。改为
    // 无条件按运行时宽度分派：≥900 走 rail 壳，<900 原样落回移动壳——
    // Android 手机视口恒 <900，行为零变化；平板/折叠屏展开 >900 与
    // today 桌面档（纯宽度判定）同口径升级为 rail 壳。tab 集过滤（隐藏
    // 小组件 tab）统一走 WebTarget.isWebBuild，原生移动包不受影响。
    return LayoutBuilder(
      builder: (context, constraints) {
        AppClock.watch(context);
        if (WebTarget.isWidescreenLayout(constraints.maxWidth)) {
          return _buildDesktopWebShell(
            context: context,
            prefs: prefs,
            safeIndex: safeIndex,
            safeVisibleTabs: safeVisibleTabs,
            selectedNavIndex: selectedNavIndex,
            showingHiddenTab: showingHiddenTab,
            destinations: navDestinations,
          );
        }
        return _buildMobileShell(
          prefs: prefs,
          safeIndex: safeIndex,
          safeVisibleTabs: safeVisibleTabs,
          selectedNavIndex: selectedNavIndex,
          showingHiddenTab: showingHiddenTab,
          destinations: navDestinations,
        );
      },
    );
  }

  Widget _buildMobileShell({
    required PreferencesProvider prefs,
    required int safeIndex,
    required List<int> safeVisibleTabs,
    required int selectedNavIndex,
    required bool showingHiddenTab,
    required List<NavigationDestination> destinations,
  }) {
    // 底部导航"液态玻璃"：仅注册了 AppSurfaceStyle（默认主题）时启用——
    // 半透明底色由 navigationBarTheme 档位控制，模糊在此包 BackdropFilter，
    // 其余 7 套主题（navBarBlurSigma=0）保持原样，不引入模糊开销。
    final navBarBlurSigma = appSurfaceStyleOf(context)?.navBarBlurSigma ?? 0;
    final navBar = NavigationBar(
      selectedIndex: selectedNavIndex < 0 ? 0 : selectedNavIndex,
      onDestinationSelected: (i) => navigateTo(safeVisibleTabs[i]),
      destinations: destinations,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    );
    // 液态玻璃需要真实内容垫在导航条下：Scaffold 默认（extendBody=false）
    // 的 body 不延伸到 bottomNavigationBar 之下，BackdropFilter 无内容可
    // 模糊，半透明白底色只能合成在根背景上呈灰条。仅对玻璃主题开启
    // extendBody，让 BrandBackground 铺到条下；页面内容用与导航条等高的
    // 内层 Padding 避让，并把 Scaffold 因 extendBody 对 body 提升的
    // MediaQuery bottom padding/viewInsets 归零——不延伸时 Scaffold 对 body
    // 的基线本就是移除这两个 bottom 值（bottomNavigationBar 槽位
    // removeBottomPadding、resizeToAvoidBottomInset 时 removeBottomInset），
    // 归零后屏内 SafeArea/滚动尾部 padding/键盘消费者与 7 套非玻璃主题一致。
    // 隐藏页返回条（不透明）与其余 7 套主题不延伸，观感不变。
    final glassNavBarActive = navBarBlurSigma > 0 && !showingHiddenTab;
    // web 渲染器下 BackdropFilter 逐帧回读像素、开销显著高于原生：模糊
    // 降到轻量档（毛玻璃观感保留、像素回读量减半），原生保持全档。
    final navBarBlurEffectiveSigma =
        WebTarget.shouldReduceNavBarBlur &&
            navBarBlurSigma > DesignTokens.navBarWebBlurSigma
        ? DesignTokens.navBarWebBlurSigma
        : navBarBlurSigma;
    final rootMediaQuery = MediaQuery.of(context);
    // NavigationBar 结构为 Material > SafeArea > SizedBox(height)，
    // 总高 = navigationBarTheme.height + 系统底部 inset。
    final navBarTotalHeight =
        (NavigationBarTheme.of(context).height ?? 80.0) +
        rootMediaQuery.padding.bottom;
    final tabStack = IndexedStack(
      index: safeIndex,
      children: List.generate(
        _tabCount,
        (tab) => _builtTabs.contains(tab)
            ? _buildTab(tab, safeVisibleTabs)
            : _LazyTabPlaceholder(tab: tab),
      ),
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: glassNavBarActive,
      body: glassNavBarActive
          ? MediaQuery(
              // 对齐不延伸时的 Scaffold body 基线：两个 bottom 值归零，而非
              // 还原为系统原值。系统 inset 已由导航条内部 SafeArea 消费
              // （条高 = height + inset），也含在内层 Padding 里；若还原成
              // 系统原值，屏内 SafeArea/滚动尾部 padding 会在其上再多避让
              // 一次 inset（如批量操作条与导航条之间露出背景空条）。
              data: rootMediaQuery.copyWith(
                padding: rootMediaQuery.padding.copyWith(bottom: 0),
                viewInsets: rootMediaQuery.viewInsets.copyWith(bottom: 0),
              ),
              child: BrandBackground(
                child: Padding(
                  padding: EdgeInsets.only(bottom: navBarTotalHeight),
                  child: tabStack,
                ),
              ),
            )
          : BrandBackground(child: tabStack),
      bottomNavigationBar: showingHiddenTab
          ? _HiddenTabReturnBar(
              onClose: () => navigateTo(
                safeVisibleTabs.contains(6) ? 6 : safeVisibleTabs.first,
              ),
            )
          : glassNavBarActive
          ? ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: navBarBlurEffectiveSigma,
                  sigmaY: navBarBlurEffectiveSigma,
                ),
                child: navBar,
              ),
            )
          : navBar,
    );
  }

  Widget _buildDesktopWebShell({
    required BuildContext context,
    required PreferencesProvider prefs,
    required int safeIndex,
    required List<int> safeVisibleTabs,
    required int selectedNavIndex,
    required bool showingHiddenTab,
    required List<NavigationDestination> destinations,
  }) {
    final appTitle = AppLocalizations.of(context).appTitle;
    final content = IndexedStack(
      index: safeIndex,
      children: List.generate(
        _tabCount,
        (tab) => _builtTabs.contains(tab)
            ? _buildTab(tab, safeVisibleTabs)
            : _LazyTabPlaceholder(tab: tab),
      ),
    );
    final body = showingHiddenTab
        ? Column(
            children: [
              _HiddenTabReturnBar(
                onClose: () => navigateTo(
                  safeVisibleTabs.contains(6) ? 6 : safeVisibleTabs.first,
                ),
              ),
              Expanded(child: content),
            ],
          )
        : content;

    // rail 几何一次算清（浮岛卡面四周各留 DesignTokens.spaceMd 一圈）：
    // 内容列宽 = 窗口 - rail 卡宽 - 2×spaceMd，超过 maxContentWidth 后由
    // Center 两侧留白；FAB 右距据此贴住内容列右缘。
    final windowWidth = MediaQuery.widthOf(context);
    final railExtended = windowWidth >= DesktopTokens.railExtendedBreakpoint;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BrandBackground(
        child: Row(
          children: [
            // 桌面侧栏走 iOS/液态玻璃语言的"浮岛"卡面：AppSurfaceCard
            // 继承各主题卡面档（默认主题 16 圆角 + 极淡阴影、玻璃主题
            // 半透明白高光描边、其余主题淡描边卡面），四周留缝透出
            // BrandBackground，柔和分隔由留白与圆角承担，不再压一条
            // 满高硬分隔线。
            AppSurfaceCard(
              margin: const EdgeInsets.all(DesignTokens.spaceMd),
              padding: EdgeInsets.zero,
              child: SafeArea(
                right: false,
                child: NavigationRail(
                  selectedIndex: selectedNavIndex < 0 ? null : selectedNavIndex,
                  onDestinationSelected: (i) => navigateTo(safeVisibleTabs[i]),
                  extended: railExtended,
                  minExtendedWidth: DesktopTokens.railExtendedWidth,
                  backgroundColor: Colors.transparent,
                  leading: _DesktopRailHeader(
                    appTitle: appTitle,
                    extended: railExtended,
                  ),
                  destinations: destinations
                      .map(
                        (destination) => NavigationRailDestination(
                          icon: Tooltip(
                            message: destination.label,
                            child: destination.icon,
                          ),
                          selectedIcon: Tooltip(
                            message: destination.label,
                            child: destination.selectedIcon,
                          ),
                          label: Text(
                            destination.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
            Expanded(
              // 宽屏内容限宽：todo/habit/calendar/mine 的 body 均为全幅
              // Column/ListView，玻璃/实底卡面在无限宽下拉成大平板；用
              // 今日页桌面档同款 maxContentWidth（DesktopTokens 既有档位，
              // 不新增档位）一处约束全部 tab，两侧留白透出 BrandBackground。
              child: Center(
                child: ConstrainedBox(
                  key: const ValueKey('desktop_web_body_max_width'),
                  constraints: BoxConstraints(
                    maxWidth: DesktopTokens.maxContentWidth,
                  ),
                  child: body,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(int tab, List<int> safeVisibleTabs) {
    return switch (tab) {
      0 => TodayScreen(
        key: todayKey,
        showCaptureFab: context.read<PreferencesProvider>().quickCaptureFab,
      ),
      1 => TodoScreen(key: todoKey),
      2 => HabitScreen(key: habitKey),
      3 => CalendarScreen(key: calendarKey),
      4 => PomodoroScreen(key: pomodoroKey, useShellBackground: true),
      5 => WidgetScreen(key: widgetKey),
      6 => MineScreen(
        key: mineKey,
        useShellBackground: true,
        visibleBottomNavTabs: safeVisibleTabs,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _DesktopRailHeader extends StatelessWidget {
  final String appTitle;
  final bool extended;

  const _DesktopRailHeader({required this.appTitle, required this.extended});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(color: cs.onSurface);
    final icon = Icon(Icons.dashboard_customize_rounded, color: cs.primary);

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 14, 12, extended ? 18 : 10),
      child: extended
          ? SizedBox(
              width: 172,
              child: Row(
                children: [
                  icon,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      appTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                  ),
                ],
              ),
            )
          : Tooltip(message: appTitle, child: icon),
    );
  }
}

class _LazyTabPlaceholder extends StatelessWidget {
  final int tab;

  const _LazyTabPlaceholder({required this.tab});

  @override
  Widget build(BuildContext context) {
    return SizedBox.shrink(key: ValueKey('lazy-tab-$tab'));
  }
}

class _HiddenTabReturnBar extends StatelessWidget {
  final VoidCallback onClose;

  const _HiddenTabReturnBar({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface.withValues(alpha: 0.96),
      elevation: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '隐藏应用',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.58),
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onClose,
                icon: const Icon(Icons.keyboard_return_rounded, size: 18),
                label: const Text('返回我的'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: appSecondaryMenuItemTextStyle(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavBadgeIcon extends StatelessWidget {
  final Widget child;

  const _BottomNavBadgeIcon({required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          child,
          Positioned(
            top: 3,
            right: 3,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
