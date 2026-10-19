import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/app_clock.dart';
import '../core/local_timezone_resolver.dart';
import '../core/platform_info.dart';
import 'local_notifications.dart';
import 'native_reminder_ringtone.dart';
import 'notification_permission_exception.dart';
import 'notification_settings.dart';
import 'reminder_sinks.dart';
import 'reminder_ringtone_settings.dart';
import 'reminder_notification_id.dart';

/// 精准闹钟权限缺失异常。
///
/// Android 12+ 要求应用持有 `SCHEDULE_EXACT_ALARM` 权限才能用精准闹钟
/// 模式（`AndroidScheduleMode.exactAllowWhileIdle`）调度通知。若权限未
/// 被授予，`flutter_local_notifications` 会在 `zonedSchedule` 调用时抛出
/// `PlatformException(code: 'exact_alarms_not_permitted')`。
///
/// `AlarmService.scheduleFullScreen` 会捕获该异常并**尽力而为**降级到
/// 非精准模式重试一次（让提醒仍能发出，只是可能偏移几分钟），并记录
/// [AlarmScheduleIssue]；非精准回退也失败时才抛出本异常。
class AlarmPermissionDeniedException implements Exception {
  final String message;
  const AlarmPermissionDeniedException([this.message = '需要精准闹钟权限才能准时提醒']);

  @override
  String toString() => 'AlarmPermissionDeniedException: $message';
}

class AlarmQueueHandoffException implements Exception {
  final String message;
  const AlarmQueueHandoffException(this.message);

  @override
  String toString() => 'AlarmQueueHandoffException: $message';
}

class AlarmScheduleIssue {
  final String title;
  final String message;
  final DateTime happenedAt;
  final DateTime? scheduledTime;
  final int? id;

  const AlarmScheduleIssue({
    required this.title,
    required this.message,
    required this.happenedAt,
    this.scheduledTime,
    this.id,
  });
}

/// 闹钟通道服务（与 [LocalNotifications] 平行）。
///
/// 用于"到点必须处理"的强提醒场景：
/// - Android：`duoyi_alarm_fullscreen_v18` 渠道，`Importance.max`，可按提醒配置启用
///   `fullScreenIntent`，`category=alarm`，震动模式 `[0, 500, 500, 500]`。
/// - iOS：`interruptionLevel=.timeSensitive`（避免使用 `.critical`，
///   后者需要 Apple 单独批准的 entitlement）。
/// - Linux / macOS / Windows：退化为普通通知（无全屏效果）。
///
/// 上游用 AppClock.date 构造应用时区壁钟；zonedSchedule 前的
/// `tz.TZDateTime.from(when, tz.local)` 只保留该 occurrence 的绝对时刻。
class AlarmService implements ReminderAlarmSink, ReminderPendingSink {
  static final AlarmService instance = AlarmService._();
  AlarmService._();

  /// 独立的插件实例，与 [LocalNotifications] 互不干扰：
  /// - 各自维护自己的 `pendingNotificationRequests`；
  /// - 避免一端 `cancelAll` 误杀另一端的调度。
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _pluginInitialized = false;
  bool _launchPayloadProbed = false;
  bool _initialized = false;
  Future<void>? _pluginInitFuture;
  Future<void>? _initFuture;
  String? _launchPayload;
  AlarmScheduleIssue? _lastScheduleIssue;
  bool get isInitialized => _initialized;
  AlarmScheduleIssue? get lastScheduleIssue => _lastScheduleIssue;

  /// Tap 回调（payload）——由主入口注册处理 deep link。
  void Function(String payload)? onTap;

  void clearScheduleIssue() {
    _lastScheduleIssue = null;
  }

  void _recordScheduleIssue({
    required String title,
    required String message,
    DateTime? scheduledTime,
    int? id,
  }) {
    _lastScheduleIssue = AlarmScheduleIssue(
      title: title,
      message: message,
      happenedAt: DateTime.now(),
      scheduledTime: scheduledTime,
      id: id,
    );
    debugPrint('[AlarmService] $title: $message');
  }

  Future<bool> _tryNativeRingtone({
    required String issueTitle,
    required String issueMessage,
    required Future<void> Function() action,
    DateTime? scheduledTime,
    int? id,
  }) async {
    try {
      await action();
      return true;
    } catch (e, st) {
      if (id != null && _isAndroid) {
        try {
          await NativeReminderRingtone.cancelOrThrow(id);
        } catch (cleanupError, cleanupStack) {
          final message = '原生闹钟部分注册失败后的清理失败，已阻止注册系统通知兜底以避免重复弹出。';
          debugPrint(
            '[AlarmService] native partial schedule cleanup failed: '
            '$cleanupError\n$cleanupStack',
          );
          _recordScheduleIssue(
            title: '闹钟提醒交接失败',
            message: message,
            scheduledTime: scheduledTime,
            id: id,
          );
          throw AlarmQueueHandoffException(message);
        }
      }
      _recordScheduleIssue(
        title: issueTitle,
        message: '$issueMessage ($e)',
        scheduledTime: scheduledTime,
        id: id,
      );
      debugPrint('[AlarmService] native ringtone failed: $e\n$st');
      return false;
    }
  }

  Future<void> _cancelPartialScheduleAfterFailure(
    int id, {
    Iterable<int> pluginIds = const <int>[],
  }) async {
    if (!_initialized) return;
    var skipPluginCleanup = false;
    for (final pluginId in pluginIds) {
      if (skipPluginCleanup) break;
      try {
        await _plugin.cancel(pluginId);
      } catch (e, st) {
        debugPrint(
          '[AlarmService] plugin partial schedule cleanup failed: $e\n$st',
        );
        if (_isAndroid && _isPendingIntentLimitExceeded(e)) {
          skipPluginCleanup = true;
        }
      }
    }
    if (!skipPluginCleanup) {
      try {
        await _plugin.cancel(id);
      } catch (e, st) {
        debugPrint(
          '[AlarmService] plugin partial schedule cleanup failed: $e\n$st',
        );
      }
    }
    if (!_isAndroid) return;
    try {
      await NativeReminderRingtone.cancelOrThrow(id);
    } catch (e, st) {
      debugPrint('[AlarmService] native ringtone cleanup failed: $e\n$st');
      final message = '部分注册失败后的原生闹钟清理失败，已阻止继续注册另一条提醒以避免重复弹出。';
      _recordScheduleIssue(title: '闹钟提醒交接失败', message: message, id: id);
      throw AlarmQueueHandoffException(message);
    }
  }

  Set<int> _pluginAlarmQueueIds(int id) {
    return <int>{
      id,
      for (var weekday = 1; weekday <= 7; weekday++) _subId(id, weekday),
      for (var weekday = 1; weekday <= 7; weekday++) _legacySubId(id, weekday),
    };
  }

  Future<void> _cancelFlutterAlarmQueue(
    int id, {
    required String operation,
  }) async {
    final failures = <Object>[];
    var skipPluginCleanup = false;
    for (final pluginId in _pluginAlarmQueueIds(id)) {
      if (!skipPluginCleanup) {
        try {
          await _plugin.cancel(pluginId);
          continue;
        } catch (e, st) {
          debugPrint(
            '[AlarmService] $operation plugin owner cleanup failed: $e\n$st',
          );
          if (_isAndroid && _isPendingIntentLimitExceeded(e)) {
            skipPluginCleanup = true;
          } else {
            failures.add(e);
            continue;
          }
        }
      }
      if (_isAndroid) {
        try {
          await NativeReminderRingtone.cancelOrThrow(pluginId);
        } catch (e, st) {
          failures.add(e);
          debugPrint(
            '[AlarmService] $operation native plugin cleanup failed: $e\n$st',
          );
        }
      }
    }
    if (failures.isNotEmpty) {
      debugPrint(
        '[AlarmService] $operation continues after plugin owner cleanup '
        'failure count=${failures.length}; replacing the alarm should not be '
        'blocked by stale Flutter notification cleanup.',
      );
    }
  }

  Future<void> _cancelNativeAlarmQueue(
    int id, {
    required String operation,
  }) async {
    if (!_isAndroid) return;
    final failures = <Object>[];
    for (final nativeId in _pluginAlarmQueueIds(id)) {
      try {
        await NativeReminderRingtone.cancelOrThrow(nativeId);
      } catch (e, st) {
        failures.add(e);
        debugPrint(
          '[AlarmService] $operation native owner cleanup failed: $e\n$st',
        );
      }
    }
    if (failures.isNotEmpty) {
      debugPrint(
        '[AlarmService] $operation continues after native owner cleanup '
        'failure count=${failures.length}; replacing the alarm should not be '
        'blocked by stale native cleanup.',
      );
    }
  }

  Future<bool> _exactAlarmPermissionMissing(bool requireExactAlarm) async {
    if (!requireExactAlarm || !_isAndroid) return false;
    return !await hasExactAlarmPermission();
  }

  Future<String?> _androidChannelIssueMessage() async {
    if (!_isAndroid) return null;
    try {
      final statuses =
          await NotificationSettings.notificationChannelStatuses(const [
            channelId,
            NativeReminderRingtone.statusChannelId,
            NativeReminderRingtone.fallbackChannelId,
          ]);
      final alarmStatus = statuses?[channelId];
      if (alarmStatus != null && alarmStatus.exists) {
        if (alarmStatus.isBlocked) {
          return '强提醒渠道已关闭，系统闹钟通知可能不会显示。请在系统通知设置里开启“多仪 · 柔和强提醒”。';
        }
        if (alarmStatus.isSilent) {
          return '强提醒渠道声音已关闭，系统兜底通知可能静音。请在系统通知设置里恢复“多仪 · 柔和强提醒”的声音。';
        }
      }

      final statusChannel = statuses?[NativeReminderRingtone.statusChannelId];
      if (statusChannel != null && statusChannel.exists) {
        if (statusChannel.isBlocked) {
          return '内置铃声状态渠道已关闭，到点响铃时可能看不到停止按钮。请在系统通知设置里开启内置铃声状态渠道。';
        }
        if (statusChannel.isLowImportance) {
          return '内置铃声状态渠道提醒级别过低，到点响铃时可能无法弹出全屏闹钟。请在系统通知设置里打开内置铃声状态渠道的弹窗或高优先级提醒。';
        }
      }

      final fallbackStatus =
          statuses?[NativeReminderRingtone.fallbackChannelId];
      if (fallbackStatus != null && fallbackStatus.exists) {
        if (fallbackStatus.isBlocked) {
          return '闹钟兜底通知渠道已关闭，内置铃声失败时可能没有备用提醒。请在系统通知设置里开启闹钟兜底通知。';
        }
        if (fallbackStatus.isSilent) {
          return '闹钟兜底通知渠道声音已关闭，内置铃声失败时备用提醒可能静音。请在系统通知设置里恢复闹钟兜底通知声音。';
        }
      }
    } catch (e, st) {
      debugPrint('[AlarmService] channel readiness probe failed: $e\n$st');
      return '强提醒渠道状态无法确认，闹钟会继续注册，但到点弹出、停止按钮或兜底声音可能受系统设置影响。请检查系统通知设置后重新保存提醒。($e)';
    }
    return null;
  }

  void _finishScheduleIssue({
    required bool nativeRingtoneOk,
    required bool exactAlarmMissing,
    required bool exactFallbackUsed,
    required bool fullScreenIntentMissing,
    required String? channelIssueMessage,
    DateTime? scheduledTime,
    int? id,
  }) {
    final exactDegraded = exactAlarmMissing || exactFallbackUsed;
    if (!nativeRingtoneOk && exactDegraded) {
      _recordScheduleIssue(
        title: '闹钟提醒已降级注册',
        message: '内置铃声注册失败，且精准闹钟权限未开启；已继续使用非精准系统通知提醒。请检查后台限制并开启精准闹钟权限后重新保存提醒。',
        scheduledTime: scheduledTime,
        id: id,
      );
      return;
    }
    if (!nativeRingtoneOk) return;
    if (exactDegraded) {
      _recordScheduleIssue(
        title: '精准闹钟权限未开启',
        message: '闹钟已注册，但系统只能使用非精准唤醒，到点可能延后。请开启精准闹钟权限后重新保存提醒。',
        scheduledTime: scheduledTime,
        id: id,
      );
      return;
    }
    if (fullScreenIntentMissing) {
      _recordScheduleIssue(
        title: '强提醒弹屏权限未开启',
        message: '闹钟和内置铃声已注册，但系统可能不会遮挡当前页面或锁屏弹出。请开启弹屏权限后重新保存提醒。',
        scheduledTime: scheduledTime,
        id: id,
      );
      return;
    }
    if (channelIssueMessage != null) {
      _recordScheduleIssue(
        title: '强提醒渠道需要检查',
        message: channelIssueMessage,
        scheduledTime: scheduledTime,
        id: id,
      );
      return;
    }
    _lastScheduleIssue = null;
  }

  /// Android 闹钟通道标识。
  ///
  /// Android 通知渠道一旦在用户手机上创建，声音/弹窗等级无法通过代码修改。
  /// 使用新的 channel id 强制创建强提醒渠道，避免旧包遗留的静音/低优先级渠道
  /// 继续吞掉习惯提醒。
  static const String channelId = 'duoyi_alarm_fullscreen_v18';
  static const Set<String> legacyChannelIds = <String>{
    'duoyi_alarm',
    'duoyi_alarm_fullscreen_v3',
    'duoyi_alarm_fullscreen_v4',
    'duoyi_alarm_fullscreen_v5',
    'duoyi_alarm_fullscreen_v6',
    'duoyi_alarm_fullscreen_v7',
    'duoyi_alarm_fullscreen_v8',
    'duoyi_alarm_fullscreen_v9',
    'duoyi_alarm_fullscreen_v10',
    'duoyi_alarm_fullscreen_v11',
    'duoyi_alarm_fullscreen_v12',
    'duoyi_alarm_fullscreen_v13',
    'duoyi_alarm_fullscreen_v14',
    'duoyi_alarm_fullscreen_v15',
    'duoyi_alarm_fullscreen_v16',
    'duoyi_alarm_fullscreen_v17',
  };
  static const String _channelName = '多仪 · 柔和强提醒';
  static const String _channelDesc = '到点用柔和内置铃声提醒，可在通知上手动停止';
  String _androidSoundResourceName =
      ReminderRingtoneSettings.androidRawResourceNameFor(
        ReminderRingtoneSettings.defaultSound,
      );
  RawResourceAndroidNotificationSound get _alarmSound =>
      RawResourceAndroidNotificationSound(_androidSoundResourceName);

  /// 震动模式：静 0 → 震 220 → 静 420 → 震 220（毫秒）。
  /// `Int64List` 无法 const 化，使用 late final 缓存。
  static final Int64List _vibrationPattern = Int64List.fromList(<int>[
    0,
    220,
    420,
    220,
  ]);
  static const List<AndroidNotificationAction> _habitActions =
      <AndroidNotificationAction>[
        AndroidNotificationAction(
          'habit_checkin',
          '完成打卡',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'habit_open',
          '打开',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ];
  static const List<AndroidNotificationAction> _todoActions =
      <AndroidNotificationAction>[
        AndroidNotificationAction(
          'todo_complete',
          '完成任务',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'todo_open',
          '打开',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ];
  static const Duration _androidNativeFallbackDelay = Duration(minutes: 1);

  DateTime _androidFlutterFallbackWhen(DateTime when, bool nativeRingtoneOk) {
    if (_isAndroid && nativeRingtoneOk) {
      return when.add(_androidNativeFallbackDelay);
    }
    return when;
  }

  /// 初始化插件与通道；幂等。
  Future<void> init() async {
    if (_initialized) return;
    final inFlight = _initFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final initFuture = _doInit();
    _initFuture = initFuture;
    try {
      await initFuture;
    } finally {
      _initFuture = null;
    }
  }

  Future<void> _doInit() async {
    if (_initialized) return;

    if (!LocalTimezoneResolver.isInitialized) {
      await LocalTimezoneResolver.init();
    }
    await _ensurePluginInitialized();
    await _probeLaunchPayload();

    if (_isAndroid) {
      try {
        await _ensureAndroidFallbackChannelSound();
        // 同步持久化的铃声 / 音量 / 震动设置到原生层。
        // showFullScreenTest 会做这件事，但定时调度路径（scheduleFullScreen）
        // 之前没有，导致登录后首条定时闹钟可能因原生铃声未配置而不响，
        // 必须先点一次"测试强提醒铃声"才会触发配置——这正是用户反馈的
        // "到点没提醒"成因之一。在 init 阶段统一应用，幂等且无阻塞。
        await ReminderRingtoneSettings.applyPersistedSettingsToNative();
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        for (final legacyId in legacyChannelIds) {
          await android?.deleteNotificationChannel(legacyId);
        }
        for (final legacyId in NativeReminderRingtone.legacyChannelIds) {
          await android?.deleteNotificationChannel(legacyId);
        }
      } catch (e, st) {
        debugPrint('[AlarmService] channel setup failed: $e\n$st');
      }
    }

    _initialized = true;
  }

  Future<void> initForLaunchPayload() async {
    if (_initialized || (_pluginInitialized && _launchPayloadProbed)) return;
    await _ensurePluginInitialized();
    await _probeLaunchPayload();
  }

  Future<void> _ensurePluginInitialized() async {
    if (_pluginInitialized) return;
    final inFlight = _pluginInitFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final future = _initializePlugin();
    _pluginInitFuture = future;
    try {
      await future;
    } finally {
      _pluginInitFuture = null;
    }
  }

  Future<void> _initializePlugin() async {
    if (_pluginInitialized) return;
    const androidInit = AndroidInitializationSettings(
      '@drawable/ic_stat_duoyi',
    );
    // 不在 AlarmService 初始化时弹权限，权限由 LocalNotifications 或显式调用
    // [requestExactAlarmPermission] / 系统设置流程负责，避免重复弹窗。
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linuxInit = LinuxInitializationSettings(defaultActionName: 'Open');

    await _plugin.initialize(
      const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
        macOS: iosInit,
        linux: linuxInit,
      ),
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        final actionId = resp.actionId;
        unawaited(NativeReminderRingtone.stopActive());
        if (onTap == null) return;
        if (actionId == 'todo_complete' && payload != null) {
          final id = _idFromPayload(payload, 'todo');
          if (id != null && id.isNotEmpty) {
            onTap!(
              'duoyi://action/complete_todo?id=${Uri.encodeComponent(id)}',
            );
            return;
          }
        }
        if (actionId == 'habit_checkin' && payload != null) {
          final id = _idFromPayload(payload, 'habit');
          if (id != null && id.isNotEmpty) {
            onTap!(
              'duoyi://action/checkin_habit?id=${Uri.encodeComponent(id)}',
            );
            return;
          }
        }
        if (payload != null) onTap!(payload);
      },
    );
    _pluginInitialized = true;
  }

  Future<void> _probeLaunchPayload() async {
    if (_launchPayloadProbed) return;
    _launchPayloadProbed = true;

    try {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      final launchPayload = launchDetails?.notificationResponse?.payload;
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchPayload != null &&
          launchPayload.isNotEmpty) {
        _launchPayload = launchPayload;
      }
    } catch (e, st) {
      debugPrint('[AlarmService] launch payload probe failed: $e\n$st');
    }
  }

  bool get _isAndroid {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// 调度一个闹钟。[when] 采用本地时区 `DateTime`。
  ///
  /// - `requireExactAlarm=true` 时优先使用 [AndroidScheduleMode.exactAllowWhileIdle]，
  ///   需要 Android 12+ 的 `SCHEDULE_EXACT_ALARM` 权限。缺权限时底层插件会
  ///   抛出 `PlatformException(code: 'exact_alarms_not_permitted')`，本方法
  ///   会**尽力而为**降级到 [AndroidScheduleMode.inexactAllowWhileIdle] 重试
  ///   一次（让提醒仍能发出，只是可能偏移几分钟），并记录可展示的
  ///   [AlarmScheduleIssue]；非精准回退也失败时才抛出
  ///   [AlarmPermissionDeniedException]。
  /// - `requireExactAlarm=false` 时直接使用非精准模式，不触发回退逻辑。
  /// - `when` 已过去时直接丢弃，保持幂等。
  @override
  Future<void> scheduleFullScreen({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    bool requireExactAlarm = true,
    bool fullScreen = true,
    bool vibrate = true,
    int snoozeMinutes = 5,
    int repeatCount = 0,
  }) async {
    if (!_initialized) await init();
    if (!when.isAfter(DateTime.now())) {
      _recordScheduleIssue(
        title: '闹钟提醒注册失败',
        message: '提醒时间已过去，未注册到系统闹钟。请把提醒时间改到未来时间。',
        scheduledTime: when,
        id: id,
      );
      throw const AlarmPermissionDeniedException(
        '提醒时间已过去，未注册到系统闹钟。请把提醒时间改到未来时间。',
      );
    }
    final exactAlarmMissing = await _exactAlarmPermissionMissing(
      requireExactAlarm,
    );
    final fullScreenIntentMissing =
        fullScreen && _isAndroid && !await hasFullScreenIntentPermission();
    String? channelIssueMessage;
    var nativeRingtoneOk = true;
    if (_isAndroid) {
      await _cancelFlutterAlarmQueue(
        id,
        operation: 'scheduleFullScreen native owner handoff',
      );
      await _ensureAndroidFallbackChannelSound();
      channelIssueMessage = await _androidChannelIssueMessage();
      nativeRingtoneOk = await _tryNativeRingtone(
        issueTitle: '内置闹钟铃声注册失败',
        issueMessage: '系统未接受内置铃声调度，已继续注册系统通知提醒。请检查后台限制或系统闹钟权限。',
        id: id,
        scheduledTime: when,
        action: () => NativeReminderRingtone.scheduleOnce(
          id: id,
          title: title,
          body: body,
          when: when,
          payload: payload,
          fullScreen: fullScreen,
          vibrate: vibrate,
          snoozeMinutes: snoozeMinutes,
          repeatCount: repeatCount,
        ),
      );
    }
    try {
      await _ensureNotificationPermission('scheduleFullScreen');
    } on NotificationPermissionDeniedException {
      _recordScheduleIssue(
        title: '闹钟提醒通知权限未开启',
        message: nativeRingtoneOk
            ? '系统通知权限未开启，系统通知可能不可见；已保留内置闹钟铃声，提醒仍会响铃。请开启通知权限以显示停止/稍后按钮。'
            : '系统通知权限未开启，且内置闹钟铃声未注册成功，请开启通知权限后重试。',
        scheduledTime: when,
        id: id,
      );
      if (_isAndroid && nativeRingtoneOk) return;
      rethrow;
    }
    if (_isAndroid && !nativeRingtoneOk) {
      await _cancelNativeAlarmQueue(
        id,
        operation: 'scheduleFullScreen flutter fallback handoff',
      );
    }

    // Android 原生接收器到点后会取消同 id 的 Flutter 兜底。原生队列成功时
    // 兜底延后触发，避免和原生全屏 Activity 同一秒抢启动造成闪屏双弹。
    final flutterFallbackWhen = _androidFlutterFallbackWhen(
      when,
      nativeRingtoneOk,
    );
    final androidDetails = AndroidNotificationDetails(
      channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: fullScreen,
      playSound: true,
      sound: _alarmSound,
      enableVibration: vibrate,
      vibrationPattern: vibrate ? _vibrationPattern : null,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      visibility: NotificationVisibility.public,
      actions: _actionsForPayload(payload),
      icon: '@drawable/ic_stat_duoyi',
      ongoing: false,
      autoCancel: true,
    );
    const iosDetails = DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );
    const linuxDetails = LinuxNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
      linux: linuxDetails,
    );
    final tzWhen = tz.TZDateTime.from(flutterFallbackWhen, tz.local);

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzWhen,
        details,
        androidScheduleMode: requireExactAlarm
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
      await _verifyPluginPendingIds(
        <int>{id},
        operation: 'scheduleFullScreen',
        scheduledTime: flutterFallbackWhen,
      );
      if (!_isAndroid) {
        await NativeReminderRingtone.scheduleOnce(
          id: id,
          title: title,
          body: body,
          when: when,
          payload: payload,
          fullScreen: fullScreen,
          vibrate: vibrate,
          snoozeMinutes: snoozeMinutes,
          repeatCount: repeatCount,
        );
      }
      _finishScheduleIssue(
        nativeRingtoneOk: nativeRingtoneOk,
        exactAlarmMissing: exactAlarmMissing,
        exactFallbackUsed: false,
        fullScreenIntentMissing: fullScreenIntentMissing,
        channelIssueMessage: channelIssueMessage,
        scheduledTime: when,
        id: id,
      );
    } on PlatformException catch (e) {
      if (!_isExactAlarmDenied(e)) {
        if (_isAndroid && nativeRingtoneOk) {
          _recordScheduleIssue(
            title: '闹钟兜底通知注册失败',
            message: '内置闹钟已注册，但系统通知兜底注册失败。若到点未弹出，请检查后台限制或重新保存提醒。($e)',
            scheduledTime: when,
            id: id,
          );
          debugPrint(
            '[AlarmService] scheduleFullScreen plugin fallback failed; '
            'keeping native alarm: $e',
          );
          return;
        }
        await _cancelPartialScheduleAfterFailure(id);
        rethrow;
      }
      // 降级重试：精准闹钟权限缺失时，退化为非精准模式，让提醒至少还能响，
      // 只是可能偏移几分钟。降级成功时视为已调度，避免上层误以为队列为空。
      Object? inexactFallbackError;
      if (requireExactAlarm) {
        try {
          await _plugin.zonedSchedule(
            id,
            title,
            body,
            tzWhen,
            details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: payload,
          );
          await _verifyPluginPendingIds(
            <int>{id},
            operation: 'scheduleFullScreenFallback',
            scheduledTime: flutterFallbackWhen,
          );
          if (!_isAndroid) {
            await NativeReminderRingtone.scheduleOnce(
              id: id,
              title: title,
              body: body,
              when: when,
              payload: payload,
              fullScreen: fullScreen,
              vibrate: vibrate,
              snoozeMinutes: snoozeMinutes,
              repeatCount: repeatCount,
            );
          }
          _finishScheduleIssue(
            nativeRingtoneOk: nativeRingtoneOk,
            exactAlarmMissing: exactAlarmMissing,
            exactFallbackUsed: true,
            fullScreenIntentMissing: fullScreenIntentMissing,
            channelIssueMessage: channelIssueMessage,
            scheduledTime: when,
            id: id,
          );
          return;
        } catch (e, st) {
          inexactFallbackError = e;
          debugPrint(
            '[AlarmService] scheduleFullScreen inexact fallback failed: $e\n$st',
          );
          // 回退也失败时下方一并抛出业务异常让调用方处理。
        }
      }
      if (_isAndroid && nativeRingtoneOk) {
        final inexactFallbackDetail = inexactFallbackError == null
            ? ''
            : ' 非精准回退错误：$inexactFallbackError';
        _recordScheduleIssue(
          title: '闹钟兜底通知注册失败',
          message:
              '内置闹钟已注册，但系统通知兜底未注册成功。请开启精准闹钟权限或检查后台限制后重新保存提醒。$inexactFallbackDetail',
          scheduledTime: when,
          id: id,
        );
        return;
      }
      await _cancelPartialScheduleAfterFailure(id);
      final inexactFallbackDetail = inexactFallbackError == null
          ? ''
          : ' 非精准回退错误：$inexactFallbackError';
      _recordScheduleIssue(
        title: '闹钟提醒注册失败',
        message: '系统精准闹钟权限未开启，非精准回退也失败。请开启精准闹钟权限后重新保存提醒。$inexactFallbackDetail',
        scheduledTime: when,
        id: id,
      );
      throw const AlarmPermissionDeniedException();
    } on StateError catch (e, st) {
      if (_isAndroid && nativeRingtoneOk) {
        _recordScheduleIssue(
          title: '闹钟兜底通知待触发队列需确认',
          message: '内置闹钟已注册，但系统通知兜底队列未确认。若到点未弹出，请重新保存提醒。($e)',
          scheduledTime: when,
          id: id,
        );
        debugPrint(
          '[AlarmService] scheduleFullScreen plugin fallback not confirmed; '
          'keeping native alarm: $e\n$st',
        );
        return;
      }
      await _cancelPartialScheduleAfterFailure(id, pluginIds: <int>{id});
      debugPrint('[AlarmService] scheduleFullScreen not confirmed: $e\n$st');
      rethrow;
    } catch (e, st) {
      if (_isAndroid && nativeRingtoneOk) {
        _recordScheduleIssue(
          title: '闹钟兜底通知注册失败',
          message: '内置闹钟已注册，但系统通知兜底注册失败。若到点未弹出，请检查后台限制或重新保存提醒。($e)',
          scheduledTime: when,
          id: id,
        );
        debugPrint(
          '[AlarmService] scheduleFullScreen plugin fallback failed; '
          'keeping native alarm: $e\n$st',
        );
        return;
      }
      await _cancelPartialScheduleAfterFailure(id, pluginIds: <int>{id});
      _recordScheduleIssue(
        title: '闹钟提醒注册失败',
        message: '系统闹钟注册失败：$e',
        scheduledTime: when,
        id: id,
      );
      debugPrint('[AlarmService] scheduleFullScreen failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> showFullScreenTest({
    int id = 919001,
    String title = '强提醒测试',
    String body = '如果你看到弹屏、听到声音并有震动，强提醒通道正常。',
    String payload = 'duoyi://alarm-test',
  }) async {
    if (!_initialized) await init();
    String? channelIssueMessage;
    var nativeRingtoneOk = true;
    if (_isAndroid) {
      await _cancelFlutterAlarmQueue(
        id,
        operation: 'scheduleDailyFullScreen native owner handoff',
      );
      await NativeReminderRingtone.stopPreview();
      await ReminderRingtoneSettings.applyPersistedSettingsToNative();
      await _ensureAndroidFallbackChannelSound();
      channelIssueMessage = await _androidChannelIssueMessage();
      nativeRingtoneOk = await _tryNativeRingtone(
        issueTitle: '强提醒铃声测试失败',
        issueMessage: '内置铃声测试未能启动，已继续发送系统通知测试。请检查通知权限、渠道声音或系统后台限制。',
        id: id,
        action: () => NativeReminderRingtone.showNow(
          id: id,
          title: title,
          body: body,
          payload: payload,
          fullScreen: true,
          snoozeMinutes: 5,
        ),
      );
    }
    try {
      await _ensureNotificationPermission('showFullScreenTest');
    } on NotificationPermissionDeniedException {
      _recordScheduleIssue(
        title: '强提醒测试通知权限未开启',
        message: '内置铃声已启动测试，但系统通知权限关闭，通知栏可能看不到停止按钮。',
        id: id,
      );
      if (_isAndroid && nativeRingtoneOk) return;
      rethrow;
    }
    if (_isAndroid && nativeRingtoneOk) {
      _finishScheduleIssue(
        nativeRingtoneOk: nativeRingtoneOk,
        exactAlarmMissing: false,
        exactFallbackUsed: false,
        fullScreenIntentMissing: false,
        channelIssueMessage: channelIssueMessage,
        id: id,
      );
      return;
    }
    await _plugin.show(
      id,
      title,
      body,
      _notificationDetails(fullScreen: true, payload: payload),
      payload: payload,
    );
    if (!_isAndroid) {
      await NativeReminderRingtone.showNow(
        id: id,
        title: title,
        body: body,
        payload: payload,
      );
    }
    _finishScheduleIssue(
      nativeRingtoneOk: nativeRingtoneOk,
      exactAlarmMissing: false,
      exactFallbackUsed: false,
      fullScreenIntentMissing: false,
      channelIssueMessage: channelIssueMessage,
      id: id,
    );
  }

  @override
  Future<void> scheduleDailyFullScreen({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
    bool requireExactAlarm = true,
    bool fullScreen = true,
    bool vibrate = true,
    int snoozeMinutes = 5,
    int repeatCount = 0,
  }) async {
    if (!_initialized) await init();
    final exactAlarmMissing = await _exactAlarmPermissionMissing(
      requireExactAlarm,
    );
    final fullScreenIntentMissing =
        fullScreen && _isAndroid && !await hasFullScreenIntentPermission();
    String? channelIssueMessage;
    var nativeRingtoneOk = true;
    if (_isAndroid) {
      await _cancelFlutterAlarmQueue(
        id,
        operation: 'scheduleDailyFullScreen native owner handoff',
      );
      await _ensureAndroidFallbackChannelSound();
      channelIssueMessage = await _androidChannelIssueMessage();
      nativeRingtoneOk = await _tryNativeRingtone(
        issueTitle: '内置重复闹钟铃声注册失败',
        issueMessage: '系统未接受内置重复铃声调度，已继续注册系统通知提醒。请检查后台限制或系统闹钟权限。',
        id: id,
        action: () => NativeReminderRingtone.scheduleDaily(
          id: id,
          title: title,
          body: body,
          hour: hour,
          minute: minute,
          weekdays: weekdays,
          payload: payload,
          fullScreen: fullScreen,
          vibrate: vibrate,
          snoozeMinutes: snoozeMinutes,
          repeatCount: repeatCount,
        ),
      );
    }
    try {
      await _ensureNotificationPermission('scheduleDailyFullScreen');
    } on NotificationPermissionDeniedException {
      _recordScheduleIssue(
        title: '闹钟提醒通知权限未开启',
        message: nativeRingtoneOk
            ? '系统通知权限未开启，系统通知可能不可见；已保留内置重复闹钟铃声，提醒仍会响铃。请开启通知权限以显示停止/稍后按钮。'
            : '系统通知权限未开启，且内置重复闹钟铃声未注册成功，请开启通知权限后重试。',
        id: id,
      );
      if (_isAndroid && nativeRingtoneOk) return;
      rethrow;
    }
    if (_isAndroid && !nativeRingtoneOk) {
      await _cancelNativeAlarmQueue(
        id,
        operation: 'scheduleDailyFullScreen flutter fallback handoff',
      );
    }

    // Android 原生重复闹钟触发时会取消同 id 的 Flutter 兜底。原生队列成功时
    // 兜底延后触发，避免和原生全屏 Activity 同一秒抢启动造成闪屏双弹。
    final details = _notificationDetails(
      fullScreen: fullScreen,
      payload: payload,
      vibrate: vibrate,
    );
    final normalized = weekdays == null || weekdays.isEmpty
        ? const <int>[]
        : weekdays.where((w) => w >= 1 && w <= 7).toSet().toList();

    final targets = normalized.isEmpty ? <int?>[null] : normalized.cast<int?>();
    var exactFallbackUsed = false;
    var pluginFallbackIssueRecorded = false;
    final scheduledIds = <int>{};
    for (final weekday in targets) {
      final scheduleId = weekday == null ? id : _subId(id, weekday);
      final when = weekday == null
          ? _nextInstanceOfTime(hour, minute)
          : _nextInstanceOfWeekdayTime(weekday, hour, minute);
      final flutterFallbackWhen = _androidFlutterFallbackWhen(
        when,
        nativeRingtoneOk,
      );
      final tzWhen = tz.TZDateTime.from(flutterFallbackWhen, tz.local);

      try {
        await _plugin.zonedSchedule(
          scheduleId,
          title,
          body,
          tzWhen,
          details,
          androidScheduleMode: requireExactAlarm
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: weekday == null
              ? DateTimeComponents.time
              : DateTimeComponents.dayOfWeekAndTime,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
        );
        scheduledIds.add(scheduleId);
        if (!_isAndroid) {
          await NativeReminderRingtone.scheduleDaily(
            id: scheduleId,
            title: title,
            body: body,
            hour: hour,
            minute: minute,
            weekdays: weekday == null ? null : <int>[weekday],
            payload: payload,
            fullScreen: fullScreen,
            vibrate: vibrate,
            snoozeMinutes: snoozeMinutes,
            repeatCount: repeatCount,
          );
        }
      } on PlatformException catch (e) {
        if (!_isExactAlarmDenied(e)) {
          if (_isAndroid && nativeRingtoneOk) {
            pluginFallbackIssueRecorded = true;
            _recordScheduleIssue(
              title: '重复闹钟兜底通知注册失败',
              message: '内置重复闹钟已注册，但系统通知兜底注册失败。若到点未弹出，请检查后台限制或重新保存提醒。($e)',
              id: scheduleId,
            );
            debugPrint(
              '[AlarmService] scheduleDailyFullScreen plugin fallback failed; '
              'keeping native alarm: $e',
            );
            continue;
          }
          await _cancelPartialScheduleAfterFailure(id, pluginIds: scheduledIds);
          rethrow;
        }
        Object? inexactFallbackError;
        if (requireExactAlarm) {
          try {
            await _plugin.zonedSchedule(
              scheduleId,
              title,
              body,
              tzWhen,
              details,
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              matchDateTimeComponents: weekday == null
                  ? DateTimeComponents.time
                  : DateTimeComponents.dayOfWeekAndTime,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
              payload: payload,
            );
            scheduledIds.add(scheduleId);
            if (!_isAndroid) {
              await NativeReminderRingtone.scheduleDaily(
                id: scheduleId,
                title: title,
                body: body,
                hour: hour,
                minute: minute,
                weekdays: weekday == null ? null : <int>[weekday],
                payload: payload,
                fullScreen: fullScreen,
                vibrate: vibrate,
                snoozeMinutes: snoozeMinutes,
                repeatCount: repeatCount,
              );
            }
            exactFallbackUsed = true;
            continue;
          } catch (fallbackError, fallbackStack) {
            inexactFallbackError = fallbackError;
            debugPrint(
              '[AlarmService] scheduleDailyFullScreen inexact fallback failed: $fallbackError\n$fallbackStack',
            );
            // 回退也失败时下方一并抛出业务异常让调用方处理。
          }
        }
        if (_isAndroid && nativeRingtoneOk) {
          pluginFallbackIssueRecorded = true;
          final inexactFallbackDetail = inexactFallbackError == null
              ? ''
              : ' 非精准回退错误：$inexactFallbackError';
          _recordScheduleIssue(
            title: '重复闹钟兜底通知注册失败',
            message:
                '内置重复闹钟已注册，但系统通知兜底未注册成功。请开启精准闹钟权限或检查后台限制后重新保存提醒。$inexactFallbackDetail',
            id: scheduleId,
          );
          continue;
        }
        await _cancelPartialScheduleAfterFailure(id, pluginIds: scheduledIds);
        final inexactFallbackDetail = inexactFallbackError == null
            ? ''
            : ' 非精准回退错误：$inexactFallbackError';
        _recordScheduleIssue(
          title: '重复闹钟注册失败',
          message:
              '系统精准闹钟权限未开启，非精准回退也失败。请开启精准闹钟权限后重新保存提醒。$inexactFallbackDetail',
          id: scheduleId,
        );
        throw const AlarmPermissionDeniedException();
      } catch (e, st) {
        if (_isAndroid && nativeRingtoneOk) {
          pluginFallbackIssueRecorded = true;
          _recordScheduleIssue(
            title: '重复闹钟兜底通知注册失败',
            message: '内置重复闹钟已注册，但系统通知兜底注册失败。若到点未弹出，请检查后台限制或重新保存提醒。($e)',
            id: scheduleId,
          );
          debugPrint(
            '[AlarmService] scheduleDailyFullScreen plugin fallback failed; '
            'keeping native alarm: $e\n$st',
          );
          continue;
        }
        await _cancelPartialScheduleAfterFailure(id, pluginIds: scheduledIds);
        _recordScheduleIssue(
          title: '重复闹钟注册失败',
          message: '系统重复闹钟注册失败：$e',
          id: scheduleId,
        );
        debugPrint('[AlarmService] scheduleDailyFullScreen failed: $e\n$st');
        rethrow;
      }
    }
    try {
      await _verifyPluginPendingIds(
        scheduledIds,
        operation: 'scheduleDailyFullScreen',
        id: id,
      );
    } on StateError {
      if (_isAndroid && nativeRingtoneOk) {
        pluginFallbackIssueRecorded = true;
        _recordScheduleIssue(
          title: '重复闹钟兜底通知待触发队列需确认',
          message: '内置重复闹钟已注册，但系统通知兜底队列未确认。若到点未弹出，请重新保存提醒。',
          id: id,
        );
      } else {
        await _cancelPartialScheduleAfterFailure(id, pluginIds: scheduledIds);
        rethrow;
      }
    }
    if (pluginFallbackIssueRecorded) return;
    _finishScheduleIssue(
      nativeRingtoneOk: nativeRingtoneOk,
      exactAlarmMissing: exactAlarmMissing,
      exactFallbackUsed: exactFallbackUsed,
      fullScreenIntentMissing: fullScreenIntentMissing,
      channelIssueMessage: channelIssueMessage,
      id: id,
    );
  }

  /// 判断一个 [PlatformException] 是否由 Android 12+ 精准闹钟权限缺失引起。
  static bool _isExactAlarmDenied(PlatformException e) {
    if (e.code == 'exact_alarms_not_permitted') return true;
    final msg = '${e.message ?? ''} ${e.details ?? ''}';
    return msg.contains('SCHEDULE_EXACT_ALARM') ||
        msg.contains('exact_alarms_not_permitted');
  }

  static bool _isPendingIntentLimitExceeded(Object e) {
    final msg = e.toString();
    return msg.contains('Too many PendingIntent created') ||
        msg.contains('10000 PendingIntents');
  }

  @override
  Future<void> cancel(int id) async {
    if (!_initialized) await init();
    final failures = <Object>[];
    var skipPluginCancel = false;
    for (final queueId in _pluginAlarmQueueIds(id)) {
      if (!skipPluginCancel) {
        try {
          await _plugin.cancel(queueId);
        } catch (e, st) {
          debugPrint('[AlarmService] cancel plugin queue failed: $e\n$st');
          if (_isAndroid && _isPendingIntentLimitExceeded(e)) {
            skipPluginCancel = true;
          } else {
            failures.add(e);
          }
        }
      }
      try {
        await NativeReminderRingtone.cancelOrThrow(queueId);
      } catch (e, st) {
        failures.add(e);
        debugPrint('[AlarmService] cancel native queue failed: $e\n$st');
      }
    }
    if (failures.isEmpty) return;
    const message = '旧闹钟队列清理失败，已尝试清理 Flutter 与原生队列；请重新保存提醒以避免重复弹出。';
    _recordScheduleIssue(title: '闹钟提醒取消失败', message: message, id: id);
    throw const AlarmQueueHandoffException(message);
  }

  Future<void> cancelAll() async {
    if (!_initialized) await init();
    final failures = <Object>[];
    try {
      await _plugin.cancelAll();
    } catch (e, st) {
      failures.add(e);
      debugPrint('[AlarmService] cancelAll plugin queue failed: $e\n$st');
    }
    try {
      await NativeReminderRingtone.cancelAll();
    } catch (e, st) {
      failures.add(e);
      debugPrint('[AlarmService] cancelAll native queue failed: $e\n$st');
    }
    if (failures.isEmpty) return;
    const message = '闹钟队列批量清理失败，已尝试同时清理 Flutter 与原生队列。';
    _recordScheduleIssue(title: '闹钟提醒取消失败', message: message);
    throw const AlarmQueueHandoffException(message);
  }

  /// 查询当前 AlarmService 下发的 pending id 列表（便于测试与诊断）。
  @override
  Future<List<int>> pendingIds() async {
    if (!_initialized) await init();
    final pending = await _plugin.pendingNotificationRequests();
    final ids = pending.map((e) => e.id).toSet();
    final nativeIds = await NativeReminderRingtone.pendingIdsOrThrow();
    ids.addAll(nativeIds);
    return ids.toList(growable: false)..sort();
  }

  Future<void> _verifyPluginPendingIds(
    Iterable<int> ids, {
    required String operation,
    DateTime? scheduledTime,
    int? id,
  }) async {
    final expected = ids.toSet();
    if (expected.isEmpty) return;
    Set<int> actual;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      actual = pending.map((request) => request.id).toSet();
    } catch (e, st) {
      const message = '系统闹钟已提交注册，但待触发队列状态无法确认';
      _recordScheduleIssue(
        title: '闹钟提醒待触发队列需确认',
        message: '$message。已保留系统接受的提醒调度，若到点未弹出请重新保存提醒。($e)',
        scheduledTime: scheduledTime,
        id: id,
      );
      debugPrint(
        '[AlarmService] $operation pending verification skipped: $e\n$st',
      );
      return;
    }
    final missing = expected.difference(actual);
    if (missing.isEmpty) return;
    const message = '系统闹钟已提交注册，但待触发队列未返回完整记录';
    _recordScheduleIssue(
      title: '闹钟提醒待触发队列需确认',
      message: '$message。缺失队列 id：${missing.join(',')}，已保留系统接受的提醒调度。',
      scheduledTime: scheduledTime,
      id: id,
    );
    debugPrint(
      '[AlarmService] $operation pending verification missing ids: '
      '${missing.join(',')}; actual=${actual.join(',')}; keeping schedule '
      'because pendingNotificationRequests can be incomplete after '
      'zonedSchedule succeeds.',
    );
  }

  Future<Set<String>?> notificationChannelIds() async {
    if (!_isAndroid) return const <String>{};
    if (!_initialized) await init();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final channels = await android?.getNotificationChannels();
      if (channels == null) return null;
      return channels.map((c) => c.id).toSet();
    } catch (_) {
      return null;
    }
  }

  Future<void> refreshAndroidRingtoneChannel() async {
    if (!_isAndroid) return;
    if (!_initialized) await init();
    await _ensureAndroidFallbackChannelSound();
  }

  /// 请求 Android 12+ 精准闹钟权限。
  ///
  /// - 非 Android 平台直接返回 `true`（视为已授权）。
  /// - Android 低于 12 的系统默认即授权，`permission_handler` 也返回 granted。
  /// - 失败时返回 `false`，调用方可据此弹出引导至系统设置的提示。
  Future<bool> requestExactAlarmPermission() async {
    if (!_isAndroid) return true;
    try {
      if (!_initialized) await init();
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final exactGranted = await android?.requestExactAlarmsPermission();
      return exactGranted ?? true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestFullScreenIntentPermission() async {
    if (!_isAndroid) return true;
    try {
      if (!_initialized) await init();
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestFullScreenIntentPermission() ?? true;
    } catch (e, st) {
      debugPrint(
        '[AlarmService] full screen intent permission failed: $e\n$st',
      );
      return hasFullScreenIntentPermission();
    }
  }

  Future<void> _ensureNotificationPermission(String operation) async {
    try {
      final granted = await LocalNotifications.instance.ensurePermission();
      if (granted) return;
      debugPrint(
        '[AlarmService] $operation skipped: notification permission denied',
      );
      throw const NotificationPermissionDeniedException();
    } catch (e, st) {
      if (e is NotificationPermissionDeniedException) rethrow;
      debugPrint(
        '[AlarmService] $operation permission request failed: $e\n$st',
      );
      throw const NotificationPermissionDeniedException();
    }
  }

  Future<bool> hasFullScreenIntentPermission() async {
    if (!_isAndroid) return true;
    return PlatformInfo.canUseFullScreenIntent();
  }

  /// 查询当前是否已授予精准闹钟权限（不弹系统对话框）。
  ///
  /// - 非 Android 平台直接返回 `true`。
  /// - Android 低于 12 的系统默认即授权。
  /// - 失败时返回 `false`，调用方可据此决定是否弹引导。
  Future<bool> hasExactAlarmPermission() async {
    if (!_isAndroid) return true;
    try {
      if (!_initialized) await init();
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.canScheduleExactNotifications() ?? true;
    } catch (_) {
      return false;
    }
  }

  String? takeLaunchPayload() {
    final payload = _launchPayload;
    _launchPayload = null;
    return payload;
  }

  NotificationDetails _notificationDetails({
    required bool fullScreen,
    String? payload,
    bool vibrate = true,
  }) {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: fullScreen,
      playSound: true,
      sound: _alarmSound,
      enableVibration: vibrate,
      vibrationPattern: vibrate ? _vibrationPattern : null,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      visibility: NotificationVisibility.public,
      actions: _actionsForPayload(payload),
      icon: '@drawable/ic_stat_duoyi',
      ongoing: false,
      autoCancel: true,
    );
    const iosDetails = DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );
    const linuxDetails = LinuxNotificationDetails();
    return NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
      linux: linuxDetails,
    );
  }

  Future<void> _refreshFallbackRingtoneSound() async {
    if (!_isAndroid) return;
    _androidSoundResourceName =
        await ReminderRingtoneSettings.loadAndroidRawResourceName();
  }

  Future<void> _ensureAndroidFallbackChannelSound() async {
    if (!_isAndroid) return;
    await _refreshFallbackRingtoneSound();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final shouldRecreateChannel =
        await ReminderRingtoneSettings.androidFallbackChannelSoundNeedsRefresh(
          channelId,
          _androidSoundResourceName,
        );
    final brokenChannel = await _androidChannelNeedsSoundRepair(channelId);
    if (shouldRecreateChannel || brokenChannel) {
      await android?.deleteNotificationChannel(channelId);
    }
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.max,
        enableVibration: true,
        vibrationPattern: _vibrationPattern,
        playSound: true,
        sound: _alarmSound,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );
    await ReminderRingtoneSettings.markAndroidFallbackChannelSoundApplied(
      channelId,
      _androidSoundResourceName,
    );
  }

  Future<bool> _androidChannelNeedsSoundRepair(String channelId) async {
    final statuses = await NotificationSettings.notificationChannelStatuses([
      channelId,
    ]);
    final status = statuses?[channelId];
    return status != null &&
        (status.isSilent || status.isLowImportance || status.isBlocked);
  }

  int _subId(int base, int weekday) {
    var h = 0x811c9dc5;
    final key = '$base:$weekday';
    for (final unit in key.codeUnits) {
      h ^= unit;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h == 0 ? weekday : h;
  }

  int _legacySubId(int base, int weekday) =>
      legacyWeekdayNotificationId(base, weekday);

  List<AndroidNotificationAction>? _actionsForPayload(String? payload) {
    if (payload == null) return null;
    if (payload.startsWith('duoyi://habit/')) return _habitActions;
    if (payload.startsWith('duoyi://todo/')) return _todoActions;
    return null;
  }

  String? _idFromPayload(String payload, String host) {
    final uri = Uri.tryParse(payload);
    if (uri == null || uri.host != host || uri.pathSegments.isEmpty) {
      return null;
    }
    return uri.pathSegments.first;
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = AppClock.now();
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + 1,
        hour,
        minute,
      );
    }
    return scheduled;
  }

  tz.TZDateTime _nextInstanceOfWeekdayTime(int weekday, int hour, int minute) {
    var scheduled = _nextInstanceOfTime(hour, minute);
    while (scheduled.weekday != weekday) {
      scheduled = tz.TZDateTime(
        tz.local,
        scheduled.year,
        scheduled.month,
        scheduled.day + 1,
        hour,
        minute,
      );
    }
    return scheduled;
  }
}
