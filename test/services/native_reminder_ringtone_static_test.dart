import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Android 内置铃声链路具备服务、资源和停止动作', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneService.kt',
    ).readAsStringSync();
    final receiver = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneReceiver.kt',
    ).readAsStringSync();
    final bootReceiver = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneBootReceiver.kt',
    ).readAsStringSync();
    final scheduler = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneScheduler.kt',
    ).readAsStringSync();
    final alarmService = File(
      'lib/services/alarm_service.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final native = File(
      'lib/services/native_reminder_ringtone.dart',
    ).readAsStringSync();
    final scheduledUpdateReceiver = File(
      'android/app/src/main/kotlin/com/dexterous/flutterlocalnotifications/DuoyiScheduledNotificationUpdateReceiver.kt',
    ).readAsStringSync();

    expect(manifest, contains('android:name=".ReminderRingtoneService"'));
    expect(manifest, contains('android:name=".ReminderRingtoneReceiver"'));
    expect(manifest, contains('android:name=".ReminderRingtoneBootReceiver"'));
    final ringtoneServiceStart = manifest.indexOf(
      'android:name=".ReminderRingtoneService"',
    );
    final ringtoneServiceEnd = manifest.indexOf(
      '</service>',
      ringtoneServiceStart,
    );
    expect(ringtoneServiceStart, greaterThanOrEqualTo(0));
    expect(ringtoneServiceEnd, greaterThan(ringtoneServiceStart));
    final ringtoneServiceManifest = manifest.substring(
      ringtoneServiceStart,
      ringtoneServiceEnd,
    );
    expect(ringtoneServiceManifest, contains('android:exported="false"'));
    expect(ringtoneServiceManifest, contains('android:enabled="true"'));
    expect(ringtoneServiceManifest, contains('android:stopWithTask="false"'));
    expect(ringtoneServiceManifest, contains('mediaPlayback'));
    expect(ringtoneServiceManifest, contains('specialUse'));
    expect(
      ringtoneServiceManifest,
      contains('android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE'),
      reason: 'Android 14+ specialUse 前台服务必须声明具体用途。',
    );
    expect(
      ringtoneServiceManifest,
      contains('Scheduled reminder ringtone playback after an alarm fires'),
    );
    final nativeBootReceiverStart = manifest.indexOf(
      'android:name=".ReminderRingtoneBootReceiver"',
    );
    final nativeBootReceiverEnd = manifest.indexOf(
      '</receiver>',
      nativeBootReceiverStart,
    );
    expect(nativeBootReceiverStart, greaterThanOrEqualTo(0));
    expect(nativeBootReceiverEnd, greaterThan(nativeBootReceiverStart));
    final nativeBootReceiver = manifest.substring(
      nativeBootReceiverStart,
      nativeBootReceiverEnd,
    );
    expect(
      nativeBootReceiver,
      contains('android.intent.action.MY_PACKAGE_REPLACED'),
      reason: '应用更新仍要由自有 receiver 接管，才能跳过过期一次性提醒并清理旧队列。',
    );
    final pluginBootReceiverStart = manifest.indexOf(
      'android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver"',
    );
    final pluginBootReceiverEnd = manifest.indexOf(
      '</receiver>',
      pluginBootReceiverStart,
    );
    expect(pluginBootReceiverStart, greaterThanOrEqualTo(0));
    expect(pluginBootReceiverEnd, greaterThan(pluginBootReceiverStart));
    final pluginBootReceiver = manifest.substring(
      pluginBootReceiverStart,
      pluginBootReceiverEnd,
    );
    expect(
      pluginBootReceiver,
      isNot(contains('android.intent.action.MY_PACKAGE_REPLACED')),
      reason:
          '应用更新由 ReminderRingtoneBootReceiver 接管；插件 receiver 不应在升级后恢复旧缓存，避免过期通知马上弹出。',
    );
    final updateReceiverStart = manifest.indexOf(
      'android:name="com.dexterous.flutterlocalnotifications.DuoyiScheduledNotificationUpdateReceiver"',
    );
    final updateReceiverEnd = manifest.indexOf(
      '</receiver>',
      updateReceiverStart,
    );
    expect(updateReceiverStart, greaterThanOrEqualTo(0));
    expect(updateReceiverEnd, greaterThan(updateReceiverStart));
    final updateReceiverManifest = manifest.substring(
      updateReceiverStart,
      updateReceiverEnd,
    );
    expect(
      updateReceiverManifest,
      contains('android.intent.action.MY_PACKAGE_REPLACED'),
    );
    expect(
      updateReceiverManifest,
      isNot(contains('android.intent.action.BOOT_COMPLETED')),
    );
    expect(
      scheduledUpdateReceiver,
      contains('pruneExpiredOneShotNotifications(context)'),
    );
    expect(
      scheduledUpdateReceiver,
      contains(
        'FlutterLocalNotificationsPlugin.rescheduleNotifications(context)',
      ),
      reason: '升级后只恢复修剪过的未来插件通知，避免过期缓存立刻弹出。',
    );
    expect(
      scheduledUpdateReceiver,
      contains('scheduledNotificationsPrefsName = "scheduled_notifications"'),
    );
    expect(
      scheduledUpdateReceiver,
      contains('item.optLong("millisecondsSinceEpoch", Long.MAX_VALUE) > now'),
    );
    expect(
      scheduledUpdateReceiver,
      contains('!item.isNull("matchDateTimeComponents")'),
    );
    expect(manifest, contains('android.permission.FOREGROUND_SERVICE'));
    expect(
      manifest,
      contains('android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK'),
    );
    expect(
      manifest,
      contains('android.permission.FOREGROUND_SERVICE_SPECIAL_USE'),
    );
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    expect(manifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
    expect(manifest, contains('android.permission.USE_EXACT_ALARM'));
    expect(manifest, contains('android.permission.USE_FULL_SCREEN_INTENT'));
    expect(manifest, contains('android.permission.VIBRATE'));
    final actionReceiverStart = manifest.indexOf(
      'android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver"',
    );
    final actionReceiverEnd = manifest.indexOf('/>', actionReceiverStart);
    expect(actionReceiverStart, greaterThanOrEqualTo(0));
    expect(actionReceiverEnd, greaterThan(actionReceiverStart));
    final actionReceiverManifest = manifest.substring(
      actionReceiverStart,
      actionReceiverEnd,
    );
    expect(
      actionReceiverManifest,
      contains('android:exported="false"'),
      reason: '通知按钮回调需要插件 action receiver，但不能对外暴露。',
    );
    expect(receiver, contains('context.startForegroundService(serviceIntent)'));
    expect(
      scheduler,
      contains('(base.toLong() * 10L + weekday.toLong()).toInt()'),
      reason: '原生闹钟旧周期 ID 必须保留 Android signed Int 溢出语义。',
    );
    expect(
      service,
      contains('(base.toLong() * 10L + weekday.toLong()).toInt()'),
      reason: '铃声服务清理插件通知时必须使用相同旧周期 ID 算法。',
    );
    expect(receiver, contains('try {'));
    expect(receiver, contains('showFallbackNotification('));
    expect(service, contains('start ringtone playback failed'));
    expect(
      service,
      contains('ReminderRingtoneReceiver.showFallbackNotification'),
    );
    expect(receiver, contains('duoyi_alarm_fallback_v9'));
    expect(receiver, contains('duoyi_alarm_fallback_v7'));
    expect(receiver, contains('duoyi_alarm_fallback_v4'));
    expect(receiver, contains('duoyi_alarm_fallback_v5'));
    expect(
      receiver,
      isNot(contains('Settings.System.DEFAULT_ALARM_ALERT_URI')),
    );
    expect(receiver, contains('selectedFallbackSoundName(context)'));
    expect(receiver, contains('fallbackSoundUri(context, fallbackSoundName)'));
    expect(receiver, contains(r'/raw/duoyi_$soundName'));
    expect(receiver, contains('fallbackChannelSoundNeedsRefresh'));
    expect(receiver, contains('markFallbackChannelSoundApplied'));
    expect(
      receiver,
      contains('pref_reminder_ringtone_fallback_channel_sound_'),
    );
    expect(receiver, contains('AudioAttributes.USAGE_ALARM'));
    expect(receiver, contains('Manifest.permission.POST_NOTIFICATIONS'));
    expect(receiver, contains('ContextCompat.checkSelfPermission'));
    expect(receiver, contains('fallback notification skipped'));
    expect(receiver, contains('recordDeliveryIssue'));
    expect(receiver, contains('service_start_failed'));
    expect(receiver, contains('fallback_notification_permission_denied'));
    expect(receiver, contains('fallback_notification_failed'));
    expect(receiver, contains('runCatching {'));
    expect(receiver, contains('fallback notification failed'));
    expect(
      receiver,
      contains('NotificationCompat.Builder(context, fallbackChannelId)'),
    );
    expect(receiver, contains('.setSound(fallbackSoundUri)'));
    expect(receiver, contains('.setVibrate(longArrayOf(0, 220, 420, 220))'));
    expect(receiver, isNot(contains('ReminderRingtoneScheduler.showNow(')));
    expect(bootReceiver, contains('ReminderRingtoneScheduler.restoreAll'));
    expect(
      bootReceiver,
      contains(
        'val deliverExpired = intent.action != Intent.ACTION_MY_PACKAGE_REPLACED',
      ),
      reason: '应用更新后只恢复未来提醒，不能把已过期的一次性提醒马上弹出来。',
    );
    expect(
      bootReceiver,
      contains(
        'ReminderRingtoneScheduler.restoreAll(context, deliverExpired = deliverExpired)',
      ),
    );
    expect(bootReceiver, contains('Intent.ACTION_TIMEZONE_CHANGED'));
    expect(bootReceiver, contains('Intent.ACTION_TIME_CHANGED'));
    expect(
      bootReceiver,
      contains('ReminderRingtoneScheduler.cleanupFlutterPluginOwners(context)'),
    );
    expect(
      bootReceiver.indexOf(
        'ReminderRingtoneScheduler.cleanupFlutterPluginOwners(context)',
      ),
      lessThan(
        bootReceiver.indexOf(
          'ReminderRingtoneScheduler.restoreAll(context, deliverExpired = deliverExpired)',
        ),
      ),
      reason: '开机/升级/时区恢复时要先同步清理 Flutter 插件旧队列，再恢复原生队列，避免两条 receiver 各恢复一份。',
    );
    expect(manifest, contains('android.intent.action.TIMEZONE_CHANGED'));
    expect(manifest, contains('android.intent.action.TIME_SET'));
    expect(scheduler, contains('startRingtoneService(context, intent)'));
    expect(scheduler, contains('context.startForegroundService(intent)'));
    expect(scheduler, contains('recordPlaybackStarted'));
    expect(scheduler, contains('lastPlaybackStatus'));
    expect(scheduler, contains('clearLastPlaybackStatus'));
    expect(scheduler, contains('last_playback_status'));
    expect(scheduler, contains('service_start_failed'));
    expect(scheduler, contains('rememberSchedule'));
    expect(scheduler, contains('encodeEntry'));
    expect(scheduler, contains('fun restoreAll'));
    expect(
      scheduler,
      contains(
        'fun restoreAll(context: Context, deliverExpired: Boolean = true)',
      ),
    );
    expect(scheduler, contains('restoreOne(context, id, deliverExpired)'));
    expect(scheduler, contains('if (!deliverExpired) {'));
    expect(
      scheduler,
      contains('expired restore delivery skipped after app update'),
    );
    final expiredRestoreStart = scheduler.indexOf(
      'if (reserveDelivery(context, id, rootId, storedDeliveryToken))',
    );
    final encodeEntryStart = scheduler.indexOf(
      'private fun encodeEntry',
      expiredRestoreStart,
    );
    expect(expiredRestoreStart, greaterThanOrEqualTo(0));
    expect(encodeEntryStart, greaterThan(expiredRestoreStart));
    final expiredRestore = scheduler.substring(
      expiredRestoreStart,
      encodeEntryStart,
    );
    expect(
      expiredRestore,
      contains('recordNotificationPermissionIssueIfDenied(context, id)'),
      reason:
          'Boot restore delivery should surface denied notification permission even when native audio can still try to play.',
    );
    expect(
      expiredRestore,
      contains('if (!startRingtoneService(context, intent))'),
      reason:
          'An expired reminder delivered after boot still needs the same fallback path as a normal alarm receiver.',
    );
    expect(
      expiredRestore,
      contains('ReminderRingtoneReceiver.showFallbackNotification('),
    );
    expect(bootReceiver, contains('Intent.ACTION_BOOT_COMPLETED'));
    expect(service, contains('AudioAttributes.USAGE_ALARM'));
    expect(service, contains('playRawRingtone(selectedResId, volume, id'));
    expect(service, contains('recordPlaybackStarted'));
    expect(service, contains('prepare()'));
    expect(service, contains('start()'));
    expect(service, isNot(contains('prepareAsync()')));
    expect(service, contains('raw_selected'));
    expect(service, contains('raw_soft_fallback'));
    expect(service, contains('tone_fallback'));
    expect(service, contains('tone_fallback_failed'));
    expect(service, contains('ringtone_service_failed'));
    expect(service, contains('R.raw.duoyi_soft'));
    expect(service, isNot(contains('playSystemNotificationFallback')));
    expect(service, isNot(contains('playSystemAlarmFallback')));
    expect(
      service,
      contains(
        'selected ringtone failed, fell back to built-in soft morning chime',
      ),
    );
    expect(
      service,
      isNot(contains('raw ringtone playback failed, using system alarm')),
    );
    expect(service, contains('raw ringtone resource is too small'));
    expect(service, contains('minAudibleRawBytes = 4096L'));
    expect(
      service,
      isNot(contains('system ringtone fallback playback failed')),
    );
    expect(service, isNot(contains('Settings.System.DEFAULT_ALARM_ALERT_URI')));
    expect(
      service,
      isNot(contains('Settings.System.DEFAULT_NOTIFICATION_URI')),
    );
    expect(service, isNot(contains('Settings.System.DEFAULT_RINGTONE_URI')));
    expect(service, isNot(contains('private fun playSystemFallback')));
    expect(
      service,
      isNot(contains('setDataSource(this@ReminderRingtoneService, uri)')),
    );
    expect(
      service,
      isNot(
        contains(
          'fallbackUri?.let { playSystemFallback(volume, it) } ?: playToneFallback(volume)',
        ),
      ),
    );
    expect(
      service,
      isNot(
        contains(
          'onFailure {\n            Log.e("ReminderRingtoneService", "system ringtone fallback playback failed", it)',
        ),
      ),
    );
    expect(service, contains('ToneGenerator'));
    expect(service, contains('AudioManager.STREAM_ALARM'));
    expect(service, contains('ToneGenerator.TONE_PROP_BEEP'));
    expect(service, isNot(contains('TONE_CDMA_ALERT_CALL_GUARD')));
    expect(service, contains('playToneFallback(volume, id, audioRoute)'));
    expect(service, contains('tone fallback playback failed'));
    expect(service, contains('ringtone playback failed'));
    expect(service, contains('ringtone_playback_failed'));
    expect(service, contains('内置柔和铃声和兜底提示音都播放失败'));
    expect(service, contains('ReminderRingtoneScheduler.recordDeliveryIssue'));
    expect(service, contains('releaseToneFallback()'));
    expect(service, contains('setSound(null, null)'));
    expect(service, contains('NotificationManager.IMPORTANCE_HIGH'));
    expect(service, contains('if (shouldVibrate) vibrate()'));
    expect(service, contains('putExtra("vibrate", vibrate)'));
    expect(receiver, contains('getBooleanExtra("vibrate", true)'));
    expect(scheduler, contains('.put("vibrate"'));
    expect(manifest, contains('android:name=".ReminderFullScreenActivity"'));
    final fullScreenActivityStart = manifest.indexOf(
      'android:name=".ReminderFullScreenActivity"',
    );
    final fullScreenActivityEnd = manifest.indexOf(
      '/>',
      fullScreenActivityStart,
    );
    expect(fullScreenActivityStart, greaterThanOrEqualTo(0));
    expect(fullScreenActivityEnd, greaterThan(fullScreenActivityStart));
    final fullScreenActivityManifest = manifest.substring(
      fullScreenActivityStart,
      fullScreenActivityEnd,
    );
    expect(fullScreenActivityManifest, contains('android:exported="false"'));
    expect(
      fullScreenActivityManifest,
      contains('android:showWhenLocked="true"'),
    );
    expect(fullScreenActivityManifest, contains('android:turnScreenOn="true"'));
    expect(
      service,
      contains('launchFullScreenReminder(id, title, body, payload, rootId)'),
    );
    expect(
      service,
      contains(
        'ReminderFullScreenActivity.intent(this, id, rootId, title, body, payload)',
      ),
    );
    expect(
      receiver,
      contains(
        'ReminderFullScreenActivity.intent(context, id, rootId, title, body, payload)',
      ),
    );
    expect(
      service,
      contains('setFullScreenIntent(fullScreenIntent, fullScreen)'),
      reason:
          '原生铃声服务从后台触发时不能只依赖 startActivity；通知本身也要携带系统 full-screen intent，避免软件外全屏闹钟不弹出。',
    );
    expect(
      receiver,
      contains('setFullScreenIntent(fullScreenIntent, fullScreen)'),
      reason: '前台铃声服务启动失败后的兜底通知也要保留系统 full-screen 能力。',
    );
    expect(service, contains('NotificationCompat.VISIBILITY_PUBLIC'));
    expect(service, contains('NotificationCompat.PRIORITY_HIGH'));
    expect(service, isNot(contains('setOnlyAlertOnce(true)')));
    expect(service, contains('longArrayOf(0, 220, 420, 220)'));
    expect(service, contains('addAction(0, "停止闹钟"'));
    expect(service, contains('.setAction(actionStop)'));
    expect(service, contains('.putExtra("id", id)'));
    expect(service, contains('cancelStatusNotification'));
    expect(service, contains(r'addAction(0, "稍后提醒 $snoozeMinutes 分钟"'));
    expect(service, contains('notificationDisplayTitle()'));
    expect(service, contains('多仪 · 强提醒正在响铃'));
    expect(service, contains('notificationDisplayBody(title, body)'));
    expect(
      service,
      contains('NotificationCompat.BigTextStyle().bigText(displayBody)'),
    );
    expect(service, contains('REMINDER_RING_SNOOZE'));
    expect(service, contains('ReminderRingtoneScheduler.scheduleFollowUpOnce'));
    expect(
      service,
      contains('followUpKind = ReminderRingtoneScheduler.FOLLOW_UP_SNOOZE'),
    );
    expect(
      service,
      contains(
        'followUpKind = ReminderRingtoneScheduler.FOLLOW_UP_AUTO_REPEAT',
      ),
    );
    expect(service, contains('delayMinutes * 60_000L'));
    expect(service, contains('snoozeMinutes > 0'));
    expect(service, contains('val rootId = intent?.getIntExtra("rootId", id)'));
    expect(service, contains('.putExtra("rootId", rootId)'));
    expect(service, contains('putExtra("vibrate", shouldVibrate)'));
    expect(service, contains('putExtra("delayMinutes", snoozeMinutes)'));
    expect(service, contains('putExtra("repeatRemaining", repeatRemaining)'));
    expect(service, contains('scheduleAutoRepeat'));
    expect(
      service,
      contains('scheduleAutoRepeat(rootId, title, body, payload, fullScreen'),
    );
    expect(service, contains('repeatRemaining - 1'));
    expect(service, contains('putExtra("fullScreen", fullScreen)'));
    expect(service, contains('putExtra("repeatRemaining"'));
    expect(receiver, contains('getIntExtra("snoozeMinutes", 0)'));
    expect(receiver, contains('getIntExtra("repeatRemaining", 0)'));
    expect(receiver, contains('val rootId = intent.getIntExtra("rootId", id)'));
    expect(
      receiver,
      contains(
        'ReminderRingtoneService.intent(context, id, title, body, payload, fullScreen, vibrate, snoozeMinutes, repeatRemaining, rootId)',
      ),
    );
    expect(scheduler, contains('fun scheduleFollowUpOnce('));
    expect(scheduler, contains('const val FOLLOW_UP_SNOOZE = "snooze"'));
    expect(
      scheduler,
      contains('const val FOLLOW_UP_AUTO_REPEAT = "auto_repeat"'),
    );
    expect(scheduler, contains('private fun followUpId('));
    expect(scheduler, contains('private fun followUpIds('));
    expect(scheduler, contains('private const val followUpSnoozeNamespace'));
    expect(
      scheduler,
      contains('private const val followUpAutoRepeatNamespace'),
    );
    expect(scheduler, contains('private val reservedFollowUpIds'));
    expect(scheduler, contains('val namespace = when (kind)'));
    expect(scheduler, contains('val lowBits = hash and 0x0fffffff'));
    expect(scheduler, contains('var candidate = namespace or lowBits'));
    expect(scheduler, contains('candidate in reservedFollowUpIds'));
    expect(scheduler, isNot(contains('val positive = hash and Int.MAX_VALUE')));
    expect(scheduler, contains('.putExtra("rootId", rootId)'));
    expect(scheduler, contains('.put("rootId"'));
    expect(scheduler, contains('.put("followUpKind"'));
    expect(scheduler, contains('.put("snoozeMinutes"'));
    expect(scheduler, contains('.put("repeatCount"'));
    expect(service, contains('stopSelf()'));
    expect(alarmService, contains('NativeReminderRingtone.showNow'));
    expect(alarmService, contains('NativeReminderRingtone.scheduleOnce'));
    expect(alarmService, contains('NativeReminderRingtone.scheduleDaily'));
    expect(alarmService, contains('NativeReminderRingtone.stopActive()'));
    expect(alarmService, contains('Future<void> _cancelFlutterAlarmQueue'));
    expect(alarmService, contains('Future<void> _cancelNativeAlarmQueue'));
    expect(alarmService, contains("_plugin.cancel(pluginId)"));
    expect(native, contains('Future<void> stopActive()'));
    expect(
      native,
      contains('Future<NativeReminderPlaybackStatus?> lastPlaybackStatus()'),
    );
    expect(native, contains('class NativeReminderPlaybackStatus'));
    expect(native, contains('clearLastPlaybackStatus'));
    expect(native, contains('_waitForPreviewPlaybackStart'));
    expect(native, contains("status?.status == 'started'"));
    expect(native, contains("await _tryInvoke('stopActive'"));
    expect(native, contains('class NativeReminderRingtoneException'));
    expect(
      native,
      contains('if (!ok) throw NativeReminderRingtoneException(method)'),
    );
    expect(native, contains('Future<void> cancelOrThrow(int id)'));
    expect(
      native,
      contains("await _invoke('cancel', <String, Object?>{'id': id});"),
    );
    expect(native, contains("await _tryInvoke('cancel'"));
    expect(native, contains("await _tryInvoke('cancelAll'"));
    expect(alarmService, contains('Future<bool> _tryNativeRingtone'));
    expect(alarmService, contains('nativeRingtoneOk'));
    expect(alarmService, contains('内置闹钟铃声注册失败'));
    expect(alarmService, contains('系统未接受内置铃声调度'));
    expect(service, contains('setDeleteIntent(stopIntent)'));
    expect(service, contains('setOngoing(false)'));
    expect(service, contains('setAutoCancel(true)'));
    expect(alarmService, contains("channelId = 'duoyi_alarm_fullscreen_v18'"));
    expect(
      alarmService,
      contains('ReminderRingtoneSettings.loadAndroidRawResourceName()'),
    );
    expect(alarmService, contains('androidFallbackChannelSoundNeedsRefresh'));
    expect(alarmService, contains("'duoyi_alarm_fullscreen_v8'"));
    expect(alarmService, contains("'duoyi_alarm_fullscreen_v9'"));
    expect(alarmService, contains("'duoyi_alarm_fullscreen_v10'"));
    expect(alarmService, contains("'duoyi_alarm_fullscreen_v11'"));
    expect(alarmService, contains("'duoyi_alarm_fullscreen_v12'"));
    expect(alarmService, contains("'duoyi_alarm_fullscreen_v13'"));
    expect(alarmService, contains("'duoyi_alarm_fullscreen_v14'"));
    expect(alarmService, contains("'duoyi_alarm_fullscreen_v15'"));
    expect(alarmService, contains('ongoing: false'));
    expect(alarmService, contains('autoCancel: true'));
    expect(alarmService, isNot(contains('onlyAlertOnce: true')));
    expect(alarmService, contains('deleteNotificationChannel(legacyId)'));
    expect(
      native,
      contains("statusChannelId = 'duoyi_builtin_ringtone_status_v5'"),
    );
    expect(native, contains("fallbackChannelId = 'duoyi_alarm_fallback_v9'"));
    expect(native, contains("'duoyi_alarm_fallback_v7'"));
    expect(native, contains('legacyChannelIds'));
    expect(service, contains('duoyi_builtin_ringtone_status_v5'));
    expect(service, contains('duoyi_builtin_ringtone_status_v4'));
    expect(service, contains('duoyi_builtin_ringtone_status_v2'));
    expect(service, contains('deleteNotificationChannel(it)'));
    expect(alarmService, contains('int snoozeMinutes = 5'));
    expect(alarmService, contains('fullScreen: true'));
    expect(scheduler, contains('ReminderRingtoneService.stopIfActive'));
    expect(scheduler, contains('ReminderRingtoneService.stopActive'));
    expect(alarmService, contains('Set<int> _pluginAlarmQueueIds(int id)'));
    expect(
      alarmService,
      contains(
        'for (var weekday = 1; weekday <= 7; weekday++) _legacySubId(id, weekday)',
      ),
    );
    expect(
      alarmService,
      contains('NativeReminderRingtone.cancelOrThrow(queueId)'),
    );
    expect(
      alarmService,
      isNot(
        contains('int _subId(int base, int weekday) => base * 10 + weekday'),
      ),
    );
    expect(service, contains('.getInt(volumeKey, 60)'));
    expect(service, contains('.getString(soundKey, "soft")'));
    expect(service, contains('.coerceIn(40, 80)'));
    expect(service, contains('legacyAlarmMigrationKey'));
    expect(
      service,
      contains('private fun selectedSoundName(context: Context): String'),
    );
    expect(
      service,
      contains(
        'value == "alarm" && !prefs.getBoolean(legacyAlarmMigrationKey, false)',
      ),
      reason: '升级后如果原生提醒先触发，也要把旧默认 alarm 一次性迁移到柔和晨铃。',
    );
    expect(service, contains('.putString(soundKey, "soft")'));
    expect(receiver, contains('legacyAlarmMigrationKey'));
    expect(
      receiver,
      contains(
        'value == "alarm" && !prefs.getBoolean(legacyAlarmMigrationKey, false)',
      ),
    );
    expect(receiver, contains('.putString(soundKey, "soft")'));

    for (final name in [
      'soft',
      'forest',
      'silver',
      'paper',
      'stream',
      'star',
      'marimba',
      'lull',
      'glass',
      'bamboo',
      'dawn',
      'wood',
      'water',
      'harp',
      'mist',
      'pebble',
      'tide',
      'alarm',
      'chime',
      'bell',
      'morning',
      'pearl',
      'beep',
      'classic',
    ]) {
      expect(
        File('android/app/src/main/res/raw/duoyi_$name.wav').existsSync(),
        isTrue,
      );
      expect(service, contains('R.raw.duoyi_$name'));
    }
  });

  test('原生每日铃声保留显式 UTC，仅缺失时区时跟随手机', () {
    final scheduler = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneScheduler.kt',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final mainActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();

    expect(scheduler, contains('TimeZone.getDefault().id'));
    expect(mainActivity, contains('TimeZone.getDefault().id'));
    expect(mainActivity, contains('"getSystemTimeZoneId"'));
    expect(mainActivity, contains('result.success(TimeZone.getDefault().id)'));
    expect(scheduler, contains('if (normalized.isBlank())'));
    expect(scheduler, isNot(contains('normalized == "UTC"')));
    expect(scheduler, isNot(contains('normalized == "Etc/UTC"')));
    expect(scheduler, isNot(contains('return "Asia/Shanghai"')));
    expect(mainActivity, isNot(contains('?: "Asia/Shanghai"')));
    expect(scheduler, contains('return systemDefault'));
    expect(mainActivity, contains('call.arguments as? Map<*, *>'));
    expect(
      mainActivity,
      contains('(arguments?.get("id") as? Number)?.toInt()'),
    );
    expect(mainActivity, isNot(contains('call.argument<Int>("id")')));
  });

  test('点击内置铃声通知进入应用会停止响铃服务', () {
    final service = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneService.kt',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();
    final fullScreenActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderFullScreenActivity.kt',
    ).readAsStringSync();

    expect(service, contains('setContentIntent(contentIntent)'));
    expect(mainActivity, contains('override fun onCreate'));
    expect(mainActivity, contains('override fun onNewIntent'));
    expect(service, contains('openAppIntent(payload, stopRingtone = true)'));
    expect(
      service,
      contains(
        'ReminderFullScreenActivity.intent(this, id, rootId, title, body, payload)',
      ),
    );
    expect(
      service,
      contains('launchFullScreenReminder(id, title, body, payload, rootId)'),
    );
    expect(fullScreenActivity, contains('setShowWhenLocked(true)'));
    expect(fullScreenActivity, contains('setTurnScreenOn(true)'));
    expect(
      fullScreenActivity,
      contains('ReminderRingtoneService.stopServiceIntent'),
    );
    expect(
      fullScreenActivity,
      contains('mainActivityIntent(this, payload, stopRingtone = true)'),
    );
    expect(service, contains('reason = "full_screen_launch_failed"'));
    expect(service, contains('extraStopRingtone'));
    expect(mainActivity, contains('stopReminderRingtoneIfRequested(intent)'));
    expect(mainActivity, contains('ReminderRingtoneService.extraStopRingtone'));
    expect(mainActivity, isNot(contains('opensDuoyiReminderTarget')));
    expect(mainActivity, isNot(contains('duoyiDeepLinkFrom(intent) != null')));
    final onCreateStart = mainActivity.indexOf('override fun onCreate');
    final onNewIntentStart = mainActivity.indexOf('override fun onNewIntent');
    expect(onCreateStart, greaterThanOrEqualTo(0));
    expect(onNewIntentStart, greaterThan(onCreateStart));
    expect(
      mainActivity.substring(onCreateStart, onNewIntentStart),
      contains('stopReminderRingtoneIfRequested(intent)'),
    );
    expect(
      mainActivity.substring(onNewIntentStart),
      contains('stopReminderRingtoneIfRequested(intent)'),
    );
    expect(
      mainActivity,
      contains(
        'stopService(Intent(this, ReminderRingtoneService::class.java))',
      ),
    );

    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('bool _shouldStopActiveRingtoneForPayload('));
    expect(main, contains("uri.queryParameters['confirm'] == '1'"));
    expect(main, contains("uri.host == 'snooze'"));
    expect(main, contains("uri.host == 'alarm-test'"));
    final handlerStart = main.indexOf('void handleNotificationPayload');
    final handlerEnd = main.indexOf(
      'LocalNotifications.instance.onTap',
      handlerStart,
    );
    expect(handlerStart, greaterThanOrEqualTo(0));
    expect(handlerEnd, greaterThan(handlerStart));
    final handler = main.substring(handlerStart, handlerEnd);
    expect(handler, contains('_shouldStopActiveRingtoneForPayload(payload)'));
    expect(handler, contains('NativeReminderRingtone.stopActive()'));
    expect(
      handler.trimLeft(),
      isNot(
        startsWith(
          'void handleNotificationPayload(String payload) {\n    unawaited(NativeReminderRingtone.stopActive());',
        ),
      ),
    );
  });

  test('Android 原生强提醒不依赖先测试即可准备渠道并兜底全屏失败', () {
    final scheduler = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneScheduler.kt',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneService.kt',
    ).readAsStringSync();
    final receiver = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneReceiver.kt',
    ).readAsStringSync();
    final fullScreenActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderFullScreenActivity.kt',
    ).readAsStringSync();

    expect(scheduler, contains('prepareDeliveryInfrastructure(context)'));
    expect(
      scheduler,
      contains(
        'ReminderRingtoneService.ensureStatusNotificationChannel(context)',
      ),
      reason: '首次只注册定时闹钟时也要预先创建内置铃声状态渠道。',
    );
    expect(
      scheduler,
      contains(
        'ReminderRingtoneReceiver.ensureFallbackNotificationChannel(context)',
      ),
      reason: '首次只注册定时闹钟时也要预先创建兜底通知渠道。',
    );
    final showNowStart = scheduler.indexOf('fun showNow(');
    final scheduleOnceStart = scheduler.indexOf('fun scheduleOnce(');
    final followUpStart = scheduler.indexOf('fun scheduleFollowUpOnce(');
    final dailyStart = scheduler.indexOf('fun scheduleDaily(');
    expect(showNowStart, greaterThanOrEqualTo(0));
    expect(scheduleOnceStart, greaterThan(showNowStart));
    expect(followUpStart, greaterThan(scheduleOnceStart));
    expect(dailyStart, greaterThan(followUpStart));
    final showNow = scheduler.substring(showNowStart, scheduleOnceStart);
    final once = scheduler.substring(scheduleOnceStart, followUpStart);
    final followUp = scheduler.substring(
      followUpStart,
      scheduler.indexOf('fun reserveDelivery('),
    );
    final daily = scheduler.substring(
      dailyStart,
      scheduler.indexOf('fun rescheduleFromReceiver'),
    );
    expect(
      showNow.indexOf('prepareDeliveryInfrastructure(context)'),
      lessThan(showNow.indexOf('startRingtoneService(context, intent)')),
    );
    expect(
      once.indexOf('prepareDeliveryInfrastructure(context)'),
      lessThan(
        once.indexOf('if (!schedule(context, id, triggerAtMillis, intent))'),
      ),
    );
    expect(
      followUp.indexOf('prepareDeliveryInfrastructure(context)'),
      lessThan(
        followUp.indexOf(
          'if (!schedule(context, id, triggerAtMillis, intent))',
        ),
      ),
    );
    expect(
      daily.indexOf('prepareDeliveryInfrastructure(context)'),
      lessThan(
        daily.indexOf('if (!schedule(context, id, triggerAtMillis, intent))'),
      ),
    );

    expect(
      service,
      contains('fun ensureStatusNotificationChannel(context: Context)'),
    );
    expect(service, contains('ensureStatusNotificationChannel(this)'));
    expect(
      receiver,
      contains('fun ensureFallbackNotificationChannel(context: Context)'),
    );
    expect(
      receiver.indexOf('ensureFallbackNotificationChannel(context)'),
      lessThan(
        receiver.indexOf(
          'NotificationCompat.Builder(context, fallbackChannelId)',
        ),
      ),
    );
    expect(
      service,
      contains(
        'if (fullScreen && !launchFullScreenReminder(id, title, body, payload, rootId))',
      ),
    );
    expect(
      service,
      contains(
        'ReminderRingtoneReceiver.showFallbackNotification(this, id, title, body, payload, true, rootId)',
      ),
    );
    expect(service, contains('): Boolean'));
    expect(service, contains('}.getOrDefault(false)'));

    expect(fullScreenActivity, contains('ScrollView'));
    expect(fullScreenActivity, contains('isFillViewport = true'));
    expect(fullScreenActivity, contains('多仪 · 强提醒正在响铃'));
    expect(fullScreenActivity, contains('提醒内容'));
    expect(fullScreenActivity, contains('停止闹钟'));
    expect(fullScreenActivity, contains('打开详情'));
    expect(fullScreenActivity, contains('letterSpacing = 0f'));
    expect(fullScreenActivity, isNot(contains('🔔')));
    expect(receiver, contains('notificationDisplayTitle()'));
    expect(receiver, contains('notificationDisplayBody(title, body)'));
    expect(
      receiver,
      contains('NotificationCompat.BigTextStyle().bigText(displayBody)'),
    );
  });

  test('原生强提醒失败兜底不会和状态通知保留成两条', () {
    final receiver = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneReceiver.kt',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneService.kt',
    ).readAsStringSync();
    final scheduler = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneScheduler.kt',
    ).readAsStringSync();

    final onReceiveStart = receiver.indexOf('override fun onReceive');
    final companionStart = receiver.indexOf('companion object', onReceiveStart);
    expect(onReceiveStart, greaterThanOrEqualTo(0));
    expect(companionStart, greaterThan(onReceiveStart));
    final onReceive = receiver.substring(onReceiveStart, companionStart);
    final tryStart = onReceive.indexOf('try {');
    final catchStart = onReceive.indexOf('} catch (error: Exception)');
    final repeatStart = onReceive.indexOf('if (intent.getBooleanExtra');
    expect(tryStart, greaterThanOrEqualTo(0));
    expect(catchStart, greaterThan(tryStart));
    expect(repeatStart, greaterThan(catchStart));
    final normalStartPath = onReceive.substring(tryStart, catchStart);
    final fallbackPath = onReceive.substring(catchStart, repeatStart);
    expect(normalStartPath, isNot(contains('showFallbackNotification')));
    expect(fallbackPath, contains('showFallbackNotification'));

    expect(
      service,
      contains(
        'private fun notificationId(id: Int) = notificationIdForReminder(id)',
      ),
    );
    expect(service, contains('fun notificationIdForReminder(id: Int): Int'));
    expect(service, contains('return id or Int.MIN_VALUE'));
    expect(
      receiver,
      contains('return ReminderRingtoneService.notificationIdForReminder(id)'),
    );
    expect(service, isNot(contains('% 10_000')));
    expect(receiver, isNot(contains('% 10_000')));

    final serviceFailureIndex = service.indexOf(
      'Log.e("ReminderRingtoneService", "start ringtone playback failed", error)',
    );
    final fallbackIndex = service.indexOf(
      'ReminderRingtoneReceiver.showFallbackNotification',
      serviceFailureIndex,
    );
    final clearActiveIndex = service.indexOf(
      'activeReminderId = null',
      serviceFailureIndex,
    );
    final cancelIndex = service.indexOf(
      'cancelStatusNotification(id)',
      serviceFailureIndex,
    );
    expect(serviceFailureIndex, greaterThanOrEqualTo(0));
    expect(cancelIndex, greaterThan(serviceFailureIndex));
    expect(clearActiveIndex, greaterThan(cancelIndex));
    expect(fallbackIndex, greaterThan(clearActiveIndex));
    expect(fallbackIndex, greaterThan(cancelIndex));
    final startForegroundIndex = service.indexOf('startForeground(');
    final preStartCancelIndex = service.lastIndexOf(
      'cancelStatusNotification(id)',
      startForegroundIndex,
    );
    expect(startForegroundIndex, greaterThanOrEqualTo(0));
    expect(
      preStartCancelIndex,
      greaterThan(service.indexOf('activeReminderId = id')),
      reason: '启动同 id 前台服务通知前先清理旧状态通知，避免残留两条。',
    );
    final onDestroyIndex = service.indexOf('override fun onDestroy()');
    expect(onDestroyIndex, greaterThanOrEqualTo(0));
    expect(
      service.substring(onDestroyIndex),
      contains('activeReminderId?.let { cancelStatusNotification(it) }'),
    );
    expect(
      scheduler,
      contains('ReminderRingtoneService.cancelNotification(context, id)'),
    );
    expect(
      scheduler,
      contains('ReminderRingtoneService.cancelNotification(context, childId)'),
    );
  });

  test('Android 内置铃声先注册，通知权限失败时保留可响铃队列', () {
    final alarmService = File(
      'lib/services/alarm_service.dart',
    ).readAsStringSync();

    final onceStart = alarmService.indexOf('Future<void> scheduleFullScreen');
    final testStart = alarmService.indexOf('Future<void> showFullScreenTest');
    final dailyStart = alarmService.indexOf(
      'Future<void> scheduleDailyFullScreen',
    );
    final dailyEnd = alarmService.indexOf(
      '/// 判断一个 [PlatformException]',
      dailyStart,
    );
    expect(onceStart, greaterThanOrEqualTo(0));
    expect(testStart, greaterThan(onceStart));
    expect(dailyStart, greaterThan(testStart));
    expect(dailyEnd, greaterThan(dailyStart));

    final once = alarmService.substring(onceStart, testStart);
    expect(once, contains('NativeReminderRingtone.scheduleOnce'));
    expect(once, contains("_cancelFlutterAlarmQueue("));
    expect(once, contains("scheduleFullScreen native owner handoff"));
    expect(once, contains("_cancelNativeAlarmQueue("));
    expect(once, contains("scheduleFullScreen flutter fallback handoff"));
    expect(
      once.indexOf('NativeReminderRingtone.scheduleOnce'),
      lessThan(
        once.indexOf("_ensureNotificationPermission('scheduleFullScreen')"),
      ),
    );
    expect(once, contains('on NotificationPermissionDeniedException'));
    final oncePermissionHandler = once.substring(
      once.indexOf('on NotificationPermissionDeniedException'),
      once.indexOf('final androidDetails = AndroidNotificationDetails'),
    );
    expect(
      oncePermissionHandler,
      isNot(contains('await _cancelPartialScheduleAfterFailure(id);')),
    );
    expect(oncePermissionHandler, contains('rethrow;'));
    expect(
      oncePermissionHandler,
      contains('if (_isAndroid && nativeRingtoneOk) return;'),
    );
    expect(oncePermissionHandler, contains('已保留内置闹钟铃声，提醒仍会响铃'));
    expect(oncePermissionHandler, contains('请开启通知权限以显示停止/稍后按钮'));
    final oncePluginScheduleIndex = once.indexOf('_plugin.zonedSchedule(');
    expect(
      oncePluginScheduleIndex,
      greaterThan(
        once.indexOf('final androidDetails = AndroidNotificationDetails'),
      ),
      reason: '定时强提醒要在原生闹钟之外继续注册 Flutter 本地通知兜底。',
    );
    expect(once, contains('兜底延后触发'));
    expect(once, contains('_androidFlutterFallbackWhen('));
    expect(
      once,
      contains(
        'final tzWhen = tz.TZDateTime.from(flutterFallbackWhen, tz.local);',
      ),
    );
    final onceFinishIndex = once.indexOf(
      '_finishScheduleIssue(',
      oncePluginScheduleIndex,
    );
    expect(
      onceFinishIndex,
      greaterThan(oncePluginScheduleIndex),
      reason: '定时强提醒原生注册成功后不能早退，必须先注册 Flutter 兜底。',
    );

    final showTest = alarmService.substring(testStart, dailyStart);
    expect(showTest, contains('NativeReminderRingtone.showNow'));
    expect(
      showTest.indexOf('NativeReminderRingtone.showNow'),
      lessThan(
        showTest.indexOf("_ensureNotificationPermission('showFullScreenTest')"),
      ),
    );
    expect(showTest, contains('on NotificationPermissionDeniedException'));
    expect(showTest, contains('if (_isAndroid && nativeRingtoneOk) return;'));
    expect(showTest, contains('内置铃声已启动测试，但系统通知权限关闭，通知栏可能看不到停止按钮。'));
    final showTestNativeReturnIndex = showTest.indexOf(
      '_finishScheduleIssue(',
      showTest.indexOf("_ensureNotificationPermission('showFullScreenTest')"),
    );
    expect(
      showTestNativeReturnIndex,
      greaterThan(
        showTest.indexOf("_ensureNotificationPermission('showFullScreenTest')"),
      ),
      reason: '强提醒测试也不能同时弹原生铃声通知和 Flutter 通知。',
    );
    expect(
      showTestNativeReturnIndex,
      lessThan(showTest.indexOf('await _plugin.show')),
    );

    final daily = alarmService.substring(dailyStart, dailyEnd);
    expect(daily, contains('NativeReminderRingtone.scheduleDaily'));
    expect(daily, contains("_cancelFlutterAlarmQueue("));
    expect(daily, contains("scheduleDailyFullScreen native owner handoff"));
    expect(daily, contains("_cancelNativeAlarmQueue("));
    expect(daily, contains("scheduleDailyFullScreen flutter fallback handoff"));
    expect(
      daily.indexOf('NativeReminderRingtone.scheduleDaily'),
      lessThan(
        daily.indexOf(
          "_ensureNotificationPermission('scheduleDailyFullScreen')",
        ),
      ),
    );
    expect(daily, contains('on NotificationPermissionDeniedException'));
    final dailyPermissionHandler = daily.substring(
      daily.indexOf('on NotificationPermissionDeniedException'),
      daily.indexOf('final details = _notificationDetails'),
    );
    expect(
      dailyPermissionHandler,
      isNot(contains('await _cancelPartialScheduleAfterFailure(id);')),
    );
    expect(dailyPermissionHandler, contains('rethrow;'));
    expect(
      dailyPermissionHandler,
      contains('if (_isAndroid && nativeRingtoneOk) return;'),
    );
    expect(dailyPermissionHandler, contains('已保留内置重复闹钟铃声，提醒仍会响铃'));
    expect(dailyPermissionHandler, contains('请开启通知权限以显示停止/稍后按钮'));
    final dailyPluginScheduleIndex = daily.indexOf('_plugin.zonedSchedule(');
    expect(
      dailyPluginScheduleIndex,
      greaterThan(daily.indexOf('final details = _notificationDetails')),
      reason: '重复强提醒要在原生闹钟之外继续注册 Flutter 本地通知兜底。',
    );
    expect(daily, contains('兜底延后触发'));
    expect(daily, contains('_androidFlutterFallbackWhen('));
    final dailyFinishIndex = daily.indexOf(
      '_finishScheduleIssue(',
      dailyPluginScheduleIndex,
    );
    expect(
      dailyFinishIndex,
      greaterThan(dailyPluginScheduleIndex),
      reason: '重复强提醒原生注册成功后不能早退，必须先注册 Flutter 兜底。',
    );

    final testPermissionIndex = alarmService.indexOf(
      "_ensureNotificationPermission('showFullScreenTest')",
    );
    expect(testPermissionIndex, greaterThan(testStart));
    expect(alarmService, contains('on NotificationPermissionDeniedException'));
    expect(alarmService, isNot(contains('if (_isAndroid) return;')));
  });

  test('强提醒通知操作按钮映射到实际待办和习惯动作', () {
    final alarmService = File(
      'lib/services/alarm_service.dart',
    ).readAsStringSync();

    expect(alarmService, contains("actionId == 'todo_complete'"));
    expect(alarmService, contains("actionId == 'habit_checkin'"));
    expect(alarmService, contains("_idFromPayload(payload, 'todo')"));
    expect(alarmService, contains("_idFromPayload(payload, 'habit')"));
    expect(alarmService, contains('duoyi://action/complete_todo?id='));
    expect(alarmService, contains('duoyi://action/checkin_habit?id='));
    expect(alarmService, contains('Uri.encodeComponent(id)'));
  });

  test('强提醒注册会记录精准闹钟降级和渠道静音风险', () {
    final alarmService = File(
      'lib/services/alarm_service.dart',
    ).readAsStringSync();

    expect(alarmService, contains("import 'notification_settings.dart';"));
    expect(alarmService, contains('Future<bool> _exactAlarmPermissionMissing'));
    expect(
      alarmService,
      contains('Future<String?> _androidChannelIssueMessage'),
    );
    expect(
      alarmService,
      contains('NotificationSettings.notificationChannelStatuses'),
    );
    expect(alarmService, contains('NativeReminderRingtone.statusChannelId'));
    expect(alarmService, contains('NativeReminderRingtone.fallbackChannelId'));
    expect(alarmService, contains('statusChannel.isLowImportance'));
    expect(alarmService, contains('statusChannel.isBlocked'));
    expect(alarmService, contains('fallbackStatus.isSilent'));
    expect(alarmService, contains('void _finishScheduleIssue'));
    expect(alarmService, contains('exactAlarmMissing || exactFallbackUsed'));
    expect(alarmService, contains('精准闹钟权限未开启'));
    expect(alarmService, contains('闹钟已注册，但系统只能使用非精准唤醒'));
    expect(alarmService, contains('强提醒渠道需要检查'));
    expect(alarmService, contains('强提醒渠道状态无法确认，闹钟会继续注册'));
    expect(
      alarmService,
      contains('scheduleFullScreen inexact fallback failed'),
    );
    expect(
      alarmService,
      contains('scheduleDailyFullScreen inexact fallback failed'),
    );
    expect(alarmService, contains('非精准回退错误'));

    final onceStart = alarmService.indexOf('Future<void> scheduleFullScreen');
    final dailyStart = alarmService.indexOf(
      'Future<void> scheduleDailyFullScreen',
    );
    expect(onceStart, greaterThanOrEqualTo(0));
    expect(dailyStart, greaterThan(onceStart));
    final once = alarmService.substring(onceStart, dailyStart);
    expect(once, contains('_exactAlarmPermissionMissing('));
    expect(once, contains('_androidChannelIssueMessage()'));
    expect(once, contains('exactFallbackUsed: true'));

    final dailyEnd = alarmService.indexOf(
      '/// 判断一个 [PlatformException]',
      dailyStart,
    );
    expect(dailyEnd, greaterThan(dailyStart));
    final daily = alarmService.substring(dailyStart, dailyEnd);
    expect(daily, contains('_exactAlarmPermissionMissing('));
    expect(daily, contains('_androidChannelIssueMessage()'));
    expect(daily, contains('var exactFallbackUsed = false'));
    expect(daily, contains('exactFallbackUsed = true'));
    expect(daily, contains('_finishScheduleIssue('));
  });

  test('原生铃声注册失败不会被 Dart 视为成功', () {
    final native = File(
      'lib/services/native_reminder_ringtone.dart',
    ).readAsStringSync();
    final scheduler = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneScheduler.kt',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();

    expect(scheduler, contains('fun showNow('));
    expect(scheduler, contains('): Boolean {'));
    expect(scheduler, contains('fun scheduleOnce('));
    expect(
      scheduler,
      contains('if (triggerAtMillis <= System.currentTimeMillis())'),
    );
    expect(scheduler, contains('return false'));
    expect(
      scheduler,
      contains(
        'if (!schedule(context, id, triggerAtMillis, intent)) return false',
      ),
    );
    expect(scheduler, contains('fun scheduleDaily('));
    expect(scheduler, contains('private fun schedule('));
    expect(scheduler, contains('private fun startRingtoneService'));
    expect(scheduler, contains('}.getOrElse {'));
    expect(scheduler, contains('import android.util.Log'));
    expect(scheduler, contains('cancelScheduledOnly(context, id)'));
    expect(
      scheduler,
      contains('private const val tag = "DuoyiReminderRingtone"'),
    );
    expect(
      scheduler,
      contains(
        r'Log.w(tag, "schedule failed: id=$id triggerAtMillis=$triggerAtMillis", error)',
      ),
    );

    expect(
      mainActivity,
      contains('val ok = ReminderRingtoneScheduler.showNow'),
    );
    expect(mainActivity, contains('result.error("ringtone_show_failed"'));
    expect(
      mainActivity,
      contains('val ok = ReminderRingtoneScheduler.scheduleOnce'),
    );
    expect(mainActivity, contains('result.error("ringtone_schedule_failed"'));
    expect(
      mainActivity,
      contains('val ok = ReminderRingtoneScheduler.scheduleDaily'),
    );

    expect(native, contains("final ok = await _tryInvoke(method, arguments);"));
    expect(
      native,
      contains('if (!ok) throw NativeReminderRingtoneException(method)'),
    );
    expect(native, contains('if (result is bool) return result'));
    expect(native, contains('return false;'));
  });

  test('Android 原生铃声 AlarmManager 队列纳入闹钟诊断', () {
    final native = File(
      'lib/services/native_reminder_ringtone.dart',
    ).readAsStringSync();
    final alarmService = File(
      'lib/services/alarm_service.dart',
    ).readAsStringSync();
    final scheduler = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneScheduler.kt',
    ).readAsStringSync();
    final receiver = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneReceiver.kt',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();

    expect(native, contains('Future<List<int>> pendingIds()'));
    expect(native, contains('Future<List<int>> pendingIdsOrThrow()'));
    expect(native, contains("invokeMethod<List<dynamic>>('pendingIds')"));
    expect(native, contains('return await pendingIdsOrThrow();'));
    expect(
      native,
      contains('Future<void> _verifyPending(int id, String method)'),
    );
    expect(native, contains("await _verifyPending(id, 'scheduleOnce')"));
    expect(native, contains("await _verifyPending(id, 'scheduleDaily')"));
    expect(native, contains('final pending = await pendingIdsOrThrow();'));
    expect(native, contains('pending.contains(id)'));
    expect(native, contains('pending verification missing id'));
    expect(
      native,
      contains('Future<NativeReminderDeliveryIssue?> lastDeliveryIssue()'),
    );
    expect(native, contains('class NativeReminderDeliveryIssue'));
    expect(native, contains('class NativeReminderPlaybackStatus'));
    expect(native, contains("invokeMethod<Object?>('lastPlaybackStatus')"));
    expect(native, contains("await _tryInvoke('clearLastPlaybackStatus')"));
    expect(
      alarmService,
      contains('NativeReminderRingtone.pendingIdsOrThrow()'),
    );
    expect(alarmService, contains('ids.addAll(nativeIds)'));
    expect(scheduler, contains('fun pendingIds(context: Context): List<Int>'));
    expect(scheduler, contains('fun recordDeliveryIssue('));
    expect(scheduler, contains('fun lastDeliveryIssue('));
    expect(scheduler, contains('fun clearLastDeliveryIssue('));
    expect(scheduler, contains('last_delivery_issue'));
    expect(scheduler, contains('triggerAtMillis <= now'));
    expect(
      scheduler,
      contains('scheduledPendingIntentExists(context, id, json)'),
    );
    expect(scheduler, contains('PendingIntent.FLAG_NO_CREATE'));
    expect(
      scheduler,
      contains('if (triggerAtMillis <= System.currentTimeMillis())'),
    );
    expect(scheduler, contains('forgetId(context, id)'));
    expect(scheduler, contains('return active.distinct().sorted()'));
    expect(
      scheduler,
      contains(
        'fun markDelivered(context: Context, id: Int, rootId: Int = id)',
      ),
    );
    expect(
      scheduler,
      contains('private fun cancelScheduledOnly(context: Context, id: Int)'),
    );
    expect(scheduler, contains('for (childId in followUpIds(id))'));
    expect(receiver, contains('ReminderRingtoneScheduler.markDelivered'));
    expect(mainActivity, contains('"pendingIds"'));
    expect(mainActivity, contains('"lastDeliveryIssue"'));
    expect(mainActivity, contains('"clearLastDeliveryIssue"'));
    expect(mainActivity, contains('"lastPlaybackStatus"'));
    expect(mainActivity, contains('"clearLastPlaybackStatus"'));
    expect(
      mainActivity,
      contains('ReminderRingtoneScheduler.pendingIds(this)'),
    );
    expect(
      mainActivity,
      contains('ReminderRingtoneScheduler.lastDeliveryIssue(this)'),
    );
    expect(
      mainActivity,
      contains('ReminderRingtoneScheduler.lastPlaybackStatus(this)'),
    );
  });

  test(
    'Android native ringtone records POST_NOTIFICATIONS risk and guards update restore',
    () {
      final scheduler = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneScheduler.kt',
      ).readAsStringSync();
      final receiver = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneReceiver.kt',
      ).readAsStringSync();
      final updateReceiver = File(
        'android/app/src/main/kotlin/com/dexterous/flutterlocalnotifications/DuoyiScheduledNotificationUpdateReceiver.kt',
      ).readAsStringSync();

      expect(scheduler, contains('Manifest.permission.POST_NOTIFICATIONS'));
      expect(scheduler, contains('Build.VERSION_CODES.TIRAMISU'));
      expect(
        scheduler,
        contains('fun recordNotificationPermissionIssueIfDenied('),
      );
      expect(scheduler, contains('"notification_permission_denied"'));
      final showNowStart = scheduler.indexOf('fun showNow(');
      final scheduleOnceStart = scheduler.indexOf(
        'fun scheduleOnce(',
        showNowStart,
      );
      expect(showNowStart, greaterThanOrEqualTo(0));
      expect(scheduleOnceStart, greaterThan(showNowStart));
      final showNow = scheduler.substring(showNowStart, scheduleOnceStart);
      expect(
        showNow.indexOf(
          'recordNotificationPermissionIssueIfDenied(context, id)',
        ),
        lessThan(showNow.indexOf('startRingtoneService(context, intent)')),
      );
      expect(
        receiver,
        contains(
          'ReminderRingtoneScheduler.recordNotificationPermissionIssueIfDenied(context, id)',
        ),
      );
      expect(updateReceiver, contains('runCatching {'));
      expect(
        updateReceiver,
        contains(
          'FlutterLocalNotificationsPlugin.rescheduleNotifications(context)',
        ),
      );
      expect(
        updateReceiver,
        contains('failed to reschedule scheduled notifications after update'),
      );
    },
  );

  test('强提醒系统通知注册后保留已接受调度并记录 pending 诊断', () {
    final alarmService = File(
      'lib/services/alarm_service.dart',
    ).readAsStringSync();

    expect(alarmService, contains('Future<void> _verifyPluginPendingIds('));
    expect(alarmService, contains('_plugin.pendingNotificationRequests()'));
    expect(alarmService, contains('expected.difference(actual)'));
    expect(alarmService, contains('系统闹钟已提交注册，但待触发队列状态无法确认'));
    expect(alarmService, contains('系统闹钟已提交注册，但待触发队列未返回完整记录'));
    expect(alarmService, contains('闹钟提醒待触发队列需确认'));
    final helperStart = alarmService.indexOf(
      'Future<void> _verifyPluginPendingIds(',
    );
    final helperEnd = alarmService.indexOf(
      'Future<Set<String>?> notificationChannelIds()',
      helperStart,
    );
    expect(helperStart, greaterThanOrEqualTo(0));
    expect(helperEnd, greaterThan(helperStart));
    final helper = alarmService.substring(helperStart, helperEnd);
    expect(helper, contains('return;'));
    expect(helper, isNot(contains('throw StateError')));

    final onceStart = alarmService.indexOf('Future<void> scheduleFullScreen');
    final dailyStart = alarmService.indexOf(
      'Future<void> scheduleDailyFullScreen',
    );
    expect(onceStart, greaterThanOrEqualTo(0));
    expect(dailyStart, greaterThan(onceStart));
    final once = alarmService.substring(onceStart, dailyStart);
    expect(once, contains('_verifyPluginPendingIds('));
    expect(
      once.indexOf('_plugin.zonedSchedule('),
      lessThan(once.indexOf('_verifyPluginPendingIds(')),
    );

    final dailyEnd = alarmService.indexOf(
      '/// 判断一个 [PlatformException]',
      dailyStart,
    );
    expect(dailyEnd, greaterThan(dailyStart));
    final daily = alarmService.substring(dailyStart, dailyEnd);
    expect(daily, contains('final scheduledIds = <int>{};'));
    expect(daily, contains('scheduledIds.add(scheduleId);'));
    expect(daily, contains('_verifyPluginPendingIds('));
    expect(
      daily.indexOf('scheduledIds.add(scheduleId);'),
      lessThan(daily.lastIndexOf('_verifyPluginPendingIds(')),
    );
  });

  test('原生铃声 pending 校验失败后先清理原生队列再走 Flutter 兜底', () {
    final alarmService = File(
      'lib/services/alarm_service.dart',
    ).readAsStringSync();

    final helperStart = alarmService.indexOf('Future<bool> _tryNativeRingtone');
    final helperEnd = alarmService.indexOf(
      'Future<void> _cancelPartialScheduleAfterFailure',
      helperStart,
    );
    expect(helperStart, greaterThanOrEqualTo(0));
    expect(helperEnd, greaterThan(helperStart));
    final helper = alarmService.substring(helperStart, helperEnd);

    expect(helper, contains('await NativeReminderRingtone.cancelOrThrow(id);'));
    expect(
      helper.indexOf('await NativeReminderRingtone.cancelOrThrow(id);'),
      lessThan(helper.indexOf('_recordScheduleIssue(')),
      reason: '原生 schedule 可能已成功但 pending 读取失败，误判失败前要先撤销原生队列。',
    );
    expect(helper, contains('throw AlarmQueueHandoffException(message);'));
    expect(helper, contains('已阻止注册系统通知兜底以避免重复弹出'));
  });

  test('闹钟通道旧队列清理失败不阻断新提醒注册', () {
    final alarmService = File(
      'lib/services/alarm_service.dart',
    ).readAsStringSync();
    final scheduler = File(
      'lib/services/reminder_scheduler.dart',
    ).readAsStringSync();

    expect(alarmService, contains('class AlarmQueueHandoffException'));
    expect(
      alarmService,
      contains('throw AlarmQueueHandoffException(message);'),
    );
    expect(alarmService, contains('continues after plugin owner cleanup'));
    expect(alarmService, contains('continues after native owner cleanup'));
    expect(alarmService, contains('replacing the alarm should not be '));
    expect(
      alarmService,
      contains('blocked by stale Flutter notification cleanup'),
    );
    expect(alarmService, contains('blocked by stale native cleanup'));

    final flutterCleanupStart = alarmService.indexOf(
      'Future<void> _cancelFlutterAlarmQueue',
    );
    final nativeCleanupStart = alarmService.indexOf(
      'Future<void> _cancelNativeAlarmQueue',
    );
    final permissionStart = alarmService.indexOf(
      'Future<bool> _exactAlarmPermissionMissing',
    );
    expect(flutterCleanupStart, greaterThanOrEqualTo(0));
    expect(nativeCleanupStart, greaterThan(flutterCleanupStart));
    expect(permissionStart, greaterThan(nativeCleanupStart));

    final flutterCleanup = alarmService.substring(
      flutterCleanupStart,
      nativeCleanupStart,
    );
    final nativeCleanup = alarmService.substring(
      nativeCleanupStart,
      permissionStart,
    );
    expect(flutterCleanup, contains('final failures = <Object>[];'));
    expect(flutterCleanup, contains('failures.add(e);'));
    expect(flutterCleanup, contains('if (failures.isNotEmpty)'));
    expect(
      flutterCleanup,
      isNot(contains('throw AlarmQueueHandoffException(message);')),
    );
    expect(nativeCleanup, contains('final failures = <Object>[];'));
    expect(nativeCleanup, contains('failures.add(e);'));
    expect(nativeCleanup, contains('if (failures.isNotEmpty)'));
    expect(
      nativeCleanup,
      isNot(contains('throw AlarmQueueHandoffException(message);')),
    );
    expect(nativeCleanup, contains('NativeReminderRingtone.cancelOrThrow'));
    expect(
      nativeCleanup,
      contains('for (final nativeId in _pluginAlarmQueueIds(id))'),
    );
    expect(
      nativeCleanup,
      contains('NativeReminderRingtone.cancelOrThrow(nativeId)'),
    );
    expect(
      alarmService,
      contains(
        'for (var weekday = 1; weekday <= 7; weekday++) _legacySubId(id, weekday)',
      ),
    );

    expect(scheduler, contains('on AlarmQueueHandoffException catch (e)'));
    expect(scheduler, contains('alarm queue handoff failed'));
    expect(scheduler, contains('repeating alarm queue handoff failed'));
  });

  test('Android 重启恢复原生铃声前会清理 Flutter 插件历史队列', () {
    final scheduler = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneScheduler.kt',
    ).readAsStringSync();

    final showNowStart = scheduler.indexOf('fun showNow');
    final onceStart = scheduler.indexOf('fun scheduleOnce');
    final followUpStart = scheduler.indexOf('fun scheduleFollowUpOnce');
    final dailyStart = scheduler.indexOf('fun scheduleDaily');
    final rescheduleStart = scheduler.indexOf('fun rescheduleFromReceiver');
    final cancelStart = scheduler.indexOf('private fun cancelScheduledOnly');
    final cancelAllStart = scheduler.indexOf('fun cancelAll');
    final markDeliveredStart = scheduler.indexOf('fun markDelivered');
    final pendingIdsStart = scheduler.indexOf('fun pendingIds');
    expect(showNowStart, greaterThanOrEqualTo(0));
    expect(onceStart, greaterThanOrEqualTo(0));
    expect(onceStart, greaterThan(showNowStart));
    expect(followUpStart, greaterThan(onceStart));
    expect(dailyStart, greaterThan(followUpStart));
    expect(rescheduleStart, greaterThan(dailyStart));
    expect(cancelStart, greaterThan(rescheduleStart));
    expect(cancelAllStart, greaterThan(cancelStart));
    expect(markDeliveredStart, greaterThan(cancelAllStart));
    expect(pendingIdsStart, greaterThan(markDeliveredStart));

    final showNow = scheduler.substring(showNowStart, onceStart);
    final once = scheduler.substring(onceStart, followUpStart);
    final followUp = scheduler.substring(followUpStart, dailyStart);
    final daily = scheduler.substring(dailyStart, rescheduleStart);
    final cancel = scheduler.substring(cancelStart, cancelAllStart);
    final markDelivered = scheduler.substring(
      markDeliveredStart,
      pendingIdsStart,
    );
    expect(showNow, contains('cancelScheduledOnly(context, id)'));
    expect(
      showNow.indexOf('cancelScheduledOnly(context, id)'),
      lessThan(showNow.indexOf('val intent = ReminderRingtoneService.intent')),
      reason: '立即响铃前也必须清理同 id 旧队列，否则旧 alarm 后续还会再响。',
    );
    expect(showNow, isNot(contains('reserveDelivery(')));
    expect(
      showNow,
      contains('rapid strong-reminder retries report success without actually'),
    );
    expect(once, contains('cancelScheduledOnly(context, id)'));
    expect(
      once.indexOf('cancelScheduledOnly(context, id)'),
      lessThan(once.indexOf('val intent = baseIntent')),
      reason: '正常注册原生一次性铃声前必须先清理同 id 的 Flutter 插件旧队列。',
    );
    expect(followUp, contains('cancelScheduledOnly(context, id)'));
    expect(followUp, contains('cancelFollowUpSiblings(context, rootId, id)'));
    expect(
      followUp.indexOf('cancelFollowUpSiblings(context, rootId, id)'),
      lessThan(followUp.indexOf('cancelScheduledOnly(context, id)')),
      reason: '稍后和自动重复同属一个 root，注册当前 child 前要先清掉 sibling。',
    );
    expect(
      followUp.indexOf('cancelScheduledOnly(context, id)'),
      lessThan(followUp.indexOf('val intent = baseIntent')),
      reason: '稍后/自动重复 follow-up 注册前也要清理同 id 的插件残留。',
    );
    expect(daily, contains('cancelScheduledOnly(context, id)'));
    expect(
      daily.indexOf('cancelScheduledOnly(context, id)'),
      lessThan(daily.indexOf('val intent = baseIntent')),
      reason: '正常注册原生重复铃声前必须先清理同 id 的 Flutter 插件旧队列。',
    );
    expect(cancel, contains('cancelFlutterPluginScheduled(context, id)'));
    expect(
      cancel.indexOf('cancelFlutterPluginScheduled(context, id)'),
      lessThan(cancel.indexOf('cancelPendingIntent(')),
      reason: '取消原生队列时也必须撤销插件队列，避免保存/删除后仍双弹。',
    );
    expect(cancel, contains('cancelFlutterPluginScheduled(context, childId)'));
    expect(cancel, contains('private fun cancelFollowUpSiblings'));
    expect(cancel, contains('if (childId == keepId) continue'));
    expect(
      cancel,
      contains('ReminderRingtoneService.cancelNotification(context, childId)'),
    );
    expect(
      markDelivered,
      contains('cancelFlutterPluginScheduled(context, id)'),
    );
    expect(
      markDelivered.indexOf('cancelFlutterPluginScheduled(context, id)'),
      lessThan(markDelivered.indexOf('forgetId(context, id)')),
      reason: '一次性提醒真实触发后要清掉插件残留，再从原生 pending 记录移除。',
    );
    expect(markDelivered, contains('rootId: Int = id'));
    expect(
      markDelivered,
      contains('cancelFollowUpSiblings(context, rootId, id)'),
    );

    final restoreStart = scheduler.indexOf('fun restoreAll');
    final restoreEnd = scheduler.indexOf('private fun schedule', restoreStart);
    expect(restoreStart, greaterThanOrEqualTo(0));
    expect(restoreEnd, greaterThan(restoreStart));
    final restore = scheduler.substring(restoreStart, restoreEnd);
    expect(restore, contains('cancelFlutterPluginScheduled(context, id)'));
    expect(
      restore.indexOf('cancelFlutterPluginScheduled(context, id)'),
      lessThan(restore.indexOf('restoreOne(context, id, deliverExpired)')),
      reason: '旧 Flutter 队列必须先清理，再恢复原生闹钟，避免重启后两个 receiver 同时恢复。',
    );

    final restoreOneStart = scheduler.indexOf('private fun restoreOne');
    final encodeEntryStart = scheduler.indexOf(
      'private fun encodeEntry',
      restoreOneStart,
    );
    expect(restoreOneStart, greaterThanOrEqualTo(0));
    expect(encodeEntryStart, greaterThan(restoreOneStart));
    final restoreOne = scheduler.substring(restoreOneStart, encodeEntryStart);
    expect(restoreOne, contains('cancelScheduledOnly(context, id)'));
    expect(restoreOne, contains('cancelFollowUpSiblings(context, rootId, id)'));
    expect(
      restoreOne,
      contains('val storedDeliveryToken = json.optString("deliveryToken")'),
    );
    expect(
      restoreOne,
      contains(
        'if (reserveDelivery(context, id, rootId, storedDeliveryToken))',
      ),
    );
    expect(restoreOne, contains('if (!deliverExpired) {'));
    expect(
      restoreOne.indexOf('if (!deliverExpired) {'),
      lessThan(
        restoreOne.indexOf(
          'if (reserveDelivery(context, id, rootId, storedDeliveryToken))',
        ),
      ),
      reason: '应用升级恢复过期一次性提醒时要先跳过立即投递。',
    );
    expect(
      restoreOne.indexOf('cancelScheduledOnly(context, id)'),
      lessThan(
        restoreOne.indexOf(
          'if (reserveDelivery(context, id, rootId, storedDeliveryToken))',
        ),
      ),
      reason: '时间变化恢复过期一次性提醒时，先撤旧队列再立即响铃，避免旧 AlarmManager 再触发一次。',
    );
    expect(
      restoreOne.indexOf(
        'if (reserveDelivery(context, id, rootId, storedDeliveryToken))',
      ),
      lessThan(restoreOne.indexOf('startRingtoneService(context, intent)')),
      reason: '连续 BOOT/TIME_SET 恢复同一个过期提醒时，必须按触发 token 去重再启动铃声服务。',
    );
    expect(scheduler, contains('deliveryToken: String? = null'));
    expect(scheduler, contains('private const val deliveryTokenExtra'));
    expect(scheduler, contains('recentDeliveryTokensPrefix'));
    expect(scheduler, contains('recentDeliveryTokenMaxAgeMillis'));
    expect(scheduler, contains('fun deliveryTokenFrom(intent: Intent)'));
    expect(scheduler, contains('private fun buildDeliveryToken('));
    expect(scheduler, contains('private fun recentDeliveryTokens('));
    expect(scheduler, contains('private fun encodeRecentDeliveryTokens('));
    expect(
      scheduler,
      contains('val deliveryRootId = if (rootId == 0) id else rootId'),
    );
    expect(
      scheduler.indexOf(r'val key = "$recentDeliveryPrefix$deliveryRootId"'),
      lessThan(
        scheduler.indexOf('val normalizedToken = deliveryToken?.takeIf'),
      ),
      reason: '同 rootId 的 token/no-token 混合投递也要先过 45 秒窗口，避免立即响铃和定时广播各弹一条。',
    );
    expect(scheduler, contains('val normalizedToken = deliveryToken?.takeIf'));
    expect(
      scheduler,
      contains('if (recentTokens.containsKey(normalizedToken))'),
    );
    expect(
      scheduler,
      contains(r'val key = "$recentDeliveryPrefix$deliveryRootId"'),
    );
    expect(scheduler, contains('recentDeliveryWindowMillis = 45_000L'));
    expect(scheduler, contains('duplicate delivery skipped'));
    final receiver = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneReceiver.kt',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneService.kt',
    ).readAsStringSync();
    expect(
      receiver,
      contains(
        'val deliveryToken = ReminderRingtoneScheduler.deliveryTokenFrom(intent)',
      ),
    );
    expect(
      receiver,
      contains(
        'if (!ReminderRingtoneScheduler.reserveDelivery(context, id, rootId, deliveryToken))',
      ),
    );
    expect(
      receiver,
      contains(
        'ReminderRingtoneScheduler.cancelFlutterPluginOwner(context, id)',
      ),
    );
    expect(
      receiver,
      contains(
        'ReminderRingtoneScheduler.cancelFlutterPluginOwner(context, rootId)',
      ),
    );
    expect(
      receiver.indexOf(
        'ReminderRingtoneScheduler.cancelFlutterPluginOwner(context, id)',
      ),
      lessThan(
        receiver.indexOf(
          'if (!ReminderRingtoneScheduler.reserveDelivery(context, id, rootId, deliveryToken))',
        ),
      ),
      reason: '原生 receiver 到点时要先清旧 Flutter 定时队列，避免随后再冒出一条普通通知。',
    );
    expect(
      receiver.indexOf(
        'ReminderRingtoneScheduler.cancelFlutterPluginOwner(context, rootId)',
      ),
      lessThan(
        receiver.indexOf(
          'if (!ReminderRingtoneScheduler.reserveDelivery(context, id, rootId, deliveryToken))',
        ),
      ),
      reason: 'follow-up 子提醒到点时也必须先清 root 侧插件残留。',
    );
    expect(
      receiver.indexOf(
        'ReminderRingtoneService.cancelFlutterPluginNotification(context, id)',
      ),
      lessThan(
        receiver.indexOf('val serviceIntent = ReminderRingtoneService.intent'),
      ),
      reason: '启动原生铃声服务前先清 Flutter 已展示通知，避免同一提醒并排显示两条。',
    );
    expect(
      receiver.indexOf(
        'ReminderRingtoneService.cancelFlutterPluginNotificationSoon(context, id)',
      ),
      lessThan(
        receiver.indexOf('val serviceIntent = ReminderRingtoneService.intent'),
      ),
      reason: '服务启动前就要开始延迟清理，覆盖插件通知和原生前台通知的竞态窗口。',
    );
    final duplicateBranchStart = receiver.indexOf(
      'if (!ReminderRingtoneScheduler.reserveDelivery(context, id, rootId, deliveryToken))',
    );
    final duplicateBranchEnd = receiver.indexOf(
      'val serviceIntent = ReminderRingtoneService.intent',
      duplicateBranchStart,
    );
    expect(duplicateBranchStart, greaterThanOrEqualTo(0));
    expect(duplicateBranchEnd, greaterThan(duplicateBranchStart));
    final duplicateBranch = receiver.substring(
      duplicateBranchStart,
      duplicateBranchEnd,
    );
    expect(
      duplicateBranch,
      contains(
        'ReminderRingtoneService.cancelFlutterPluginNotificationSoon(context, id)',
      ),
    );
    expect(
      duplicateBranch,
      contains(
        'ReminderRingtoneService.cancelFlutterPluginNotificationSoon(context, rootId)',
      ),
    );
    expect(duplicateBranch, contains('return'));
    expect(
      receiver,
      contains('ReminderRingtoneScheduler.markDelivered(context, id, rootId)'),
    );
    expect(
      service,
      contains(
        'fun cancelFlutterPluginNotification(context: Context, id: Int)',
      ),
    );
    expect(
      service,
      contains(
        'fun cancelFlutterPluginNotificationSoon(context: Context, id: Int)',
      ),
    );
    expect(
      service,
      contains(
        'flutterPluginRaceCleanupDelays = longArrayOf(0L, 30L, 80L, 120L, 750L, 2_500L, 5_000L, 10_000L)',
      ),
    );
    expect(
      service,
      contains('val mainHandler = Handler(Looper.getMainLooper())'),
    );
    expect(service, contains('mainHandler.postDelayed({'));
    expect(
      service,
      contains('flutterPluginRaceCleanupDelays.forEach { delayMillis ->'),
    );
    expect(
      service,
      contains('cancelFlutterPluginNotification(appContext, pluginId)'),
    );
    expect(
      service,
      contains('private fun flutterPluginNotificationIds(id: Int)'),
    );
    expect(
      service,
      contains('val pluginIds = flutterPluginNotificationIds(id)'),
    );
    expect(service, contains('pluginIds.forEach { pluginId ->'));
    expect(
      service,
      contains('cancelFlutterPluginNotification(appContext, pluginId)'),
      reason: '延迟清理要覆盖 base id、weekday 子 id 和旧版子 id，避免 Flutter 插件晚到通知并排出现。',
    );
    expect(service, contains('private fun subId(base: Int, weekday: Int)'));
    expect(
      service,
      contains('private fun legacySubId(base: Int, weekday: Int)'),
    );
    final schedulerSubId = scheduler.substring(
      scheduler.indexOf('private fun subId(base: Int, weekday: Int)'),
      scheduler.indexOf('private fun legacySubId(base: Int, weekday: Int)'),
    );
    final serviceSubId = service.substring(
      service.indexOf('private fun subId(base: Int, weekday: Int)'),
      service.indexOf('private fun legacySubId(base: Int, weekday: Int)'),
    );
    expect(
      schedulerSubId,
      contains('hash = (hash * 0x01000193) and 0x7fffffff'),
      reason:
          'Kotlin 原生调度队列清理必须和 Dart _subId 每轮截断一致，否则每周 Flutter 子通知清不掉会和原生提醒并排出现。',
    );
    expect(
      serviceSubId,
      contains('hash = (hash * 0x01000193) and 0x7fffffff'),
      reason:
          'Kotlin 原生通知清理必须和 Dart _subId 每轮截断一致，否则每周 Flutter 子通知清不掉会和原生提醒并排出现。',
    );
    expect(
      schedulerSubId,
      isNot(contains('hash *= 0x01000193')),
      reason: '只在循环后截断会生成不同 weekday 子 id，不能覆盖 Flutter 插件真实队列 id。',
    );
    expect(
      serviceSubId,
      isNot(contains('hash *= 0x01000193')),
      reason: '只在循环后截断会生成不同 weekday 子 id，不能覆盖 Flutter 插件真实通知 id。',
    );
    expect(receiver, contains('cancelFlutterPluginNotification(context, id)'));
    expect(
      receiver,
      contains('cancelFlutterPluginNotificationSoon(context, id)'),
    );
    expect(service, contains('cancelFlutterPluginNotification(this, id)'));
    expect(service, contains('cancelFlutterPluginNotificationSoon(this, id)'));
    expect(
      service.indexOf('cancelFlutterPluginNotification(this, id)'),
      lessThan(service.indexOf('startForeground(')),
      reason: '原生铃声显示前要先清掉同 id 的 Flutter 本地通知，避免通知栏并排两条。',
    );
    expect(
      service.indexOf('startForeground('),
      lessThan(
        service.indexOf('cancelFlutterPluginNotificationSoon(this, id)'),
      ),
      reason: '原生通知显示后要延迟再清一次 Flutter 插件通知，覆盖并发 receiver 晚显示的竞态。',
    );
    expect(
      service,
      contains('private fun cancelPendingAutoRepeat(rootId: Int)'),
    );
    expect(
      service,
      contains('ReminderRingtoneScheduler.cancelFollowUps(this, rootId)'),
    );
    expect(
      service,
      contains('if (rootId != id) cancelStatusNotification(rootId)'),
    );
    expect(
      service,
      contains(
        'if (rootId != id) cancelFlutterPluginNotificationSoon(this, rootId)',
      ),
    );

    expect(
      scheduler,
      contains('flutterScheduledPrefsNames = arrayOf('),
      reason:
          'flutter_local_notifications 18.x 的调度缓存文件名是 scheduled_notifications；同时保留旧缓存名清理兼容。',
    );
    expect(scheduler, contains('"scheduled_notifications",'));
    expect(scheduler, contains('"notification_plugin_cache",'));
    expect(
      scheduler,
      contains('flutterScheduledPrefsKey = "scheduled_notifications"'),
    );
    expect(
      scheduler,
      contains(
        'import com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver',
      ),
    );
    expect(
      scheduler,
      contains('Intent(context, ScheduledNotificationReceiver::class.java)'),
      reason:
          '取消 flutter_local_notifications 队列时要和插件 new Intent(context, ScheduledNotificationReceiver.class) 同构。',
    );
    expect(
      scheduler,
      isNot(
        contains(
          '"com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"',
        ),
      ),
    );
    expect(
      scheduler,
      contains('NotificationManagerCompat.from(context).cancel(pluginId)'),
    );
    expect(scheduler, contains('removeFlutterPluginCacheIds(context, ids)'));
    expect(
      scheduler,
      contains('putString(flutterScheduledPrefsKey, kept.toString()).commit()'),
      reason:
          '原生恢复/交接时要同步删除 flutter_local_notifications 缓存，降低插件 boot receiver 随后恢复旧通知的竞态。',
    );
    expect(
      scheduler,
      contains('for (prefsName in flutterScheduledPrefsNames)'),
    );
    expect(scheduler, contains('context.getSharedPreferences('));
    expect(scheduler, contains('prefsName,'));
    expect(
      scheduler,
      contains('fun cancelFlutterPluginOwner(context: Context, id: Int)'),
    );
    expect(
      scheduler,
      contains('fun cleanupFlutterPluginOwners(context: Context)'),
    );
    expect(
      scheduler,
      contains('ids.mapNotNull { it.toIntOrNull() }.forEach { id ->'),
    );
    expect(scheduler, contains('JSONArray(raw)'));
    expect(scheduler, contains('item.optInt("id", 0) !in ids'));
    expect(scheduler, contains('pluginAlarmQueueIds(id)'));
    expect(scheduler, contains('subId(id, weekday)'));
    expect(scheduler, contains('legacySubId(id, weekday)'));
  });

  test('Android 重启恢复后会延迟清理 Flutter 插件恢复竞态', () {
    final bootReceiver = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneBootReceiver.kt',
    ).readAsStringSync();

    expect(
      bootReceiver,
      contains('scheduleFlutterPluginOwnerCleanup(context)'),
    );
    expect(bootReceiver, contains('Handler(Looper.getMainLooper())'));
    expect(
      bootReceiver,
      contains('flutterPluginBootCleanupDelays = longArrayOf('),
    );
    expect(bootReceiver, contains('500L'));
    expect(bootReceiver, contains('2_500L'));
    expect(bootReceiver, contains('10_000L'));
    expect(bootReceiver, contains('30_000L'));
    expect(bootReceiver, contains('60_000L'));
    expect(
      bootReceiver,
      contains(
        'ReminderRingtoneScheduler.cleanupFlutterPluginOwners(appContext)',
      ),
    );
    expect(
      bootReceiver.indexOf(
        'ReminderRingtoneScheduler.restoreAll(context, deliverExpired = deliverExpired)',
      ),
      lessThan(
        bootReceiver.indexOf('scheduleFlutterPluginOwnerCleanup(context)'),
      ),
      reason: '先恢复原生队列，再安排延迟清理抵消插件 boot receiver 的顺序竞态。',
    );
  });

  test('AlarmService 初始化会复用并发 init Future', () {
    final alarmService = File(
      'lib/services/alarm_service.dart',
    ).readAsStringSync();

    expect(alarmService, contains('Future<void>? _initFuture'));
    expect(alarmService, contains('final inFlight = _initFuture'));
    expect(alarmService, contains('await inFlight'));
    expect(alarmService, contains('Future<void> _doInit()'));
    expect(alarmService, contains('_initFuture = null'));
  });

  test('取消旧提醒遇到 PendingIntent 上限时不会继续扩大系统队列', () {
    final alarmService = File(
      'lib/services/alarm_service.dart',
    ).readAsStringSync();
    final localNotifications = File(
      'lib/services/local_notifications_io.dart',
    ).readAsStringSync();
    final scheduler = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/ReminderRingtoneScheduler.kt',
    ).readAsStringSync();

    final flutterCleanupStart = alarmService.indexOf(
      'Future<void> _cancelFlutterAlarmQueue(',
    );
    final nativeCleanupStart = alarmService.indexOf(
      'Future<void> _cancelNativeAlarmQueue(',
      flutterCleanupStart,
    );
    expect(flutterCleanupStart, greaterThanOrEqualTo(0));
    expect(nativeCleanupStart, greaterThan(flutterCleanupStart));
    final flutterCleanup = alarmService.substring(
      flutterCleanupStart,
      nativeCleanupStart,
    );
    expect(flutterCleanup, contains('var skipPluginCleanup = false'));
    expect(flutterCleanup, contains('_isPendingIntentLimitExceeded(e)'));
    expect(flutterCleanup, contains('skipPluginCleanup = true'));
    expect(
      flutterCleanup,
      contains('await NativeReminderRingtone.cancelOrThrow(pluginId);'),
      reason: '插件取消触发系统 PendingIntent 上限后，应改走 no-create 原生清理兜底。',
    );

    final partialCleanupStart = localNotifications.indexOf(
      'Future<void> _cancelScheduledIds(',
    );
    final exactAlarmStart = localNotifications.indexOf(
      'static bool _isExactAlarmDenied',
      partialCleanupStart,
    );
    expect(partialCleanupStart, greaterThanOrEqualTo(0));
    expect(exactAlarmStart, greaterThan(partialCleanupStart));
    final partialCleanup = localNotifications.substring(
      partialCleanupStart,
      exactAlarmStart,
    );
    expect(partialCleanup, contains('var skipPluginCleanup = false'));
    expect(partialCleanup, contains('_isPendingIntentLimitExceeded(e)'));
    expect(partialCleanup, contains('skipPluginCleanup = true'));
    expect(
      partialCleanup,
      contains('await NativeReminderRingtone.cancel(id);'),
    );

    final cancelPendingStart = scheduler.indexOf(
      'private fun cancelPendingIntent(',
    );
    final scheduledExistsStart = scheduler.indexOf(
      'private fun scheduledPendingIntentExists',
      cancelPendingStart,
    );
    expect(cancelPendingStart, greaterThanOrEqualTo(0));
    expect(scheduledExistsStart, greaterThan(cancelPendingStart));
    final cancelPending = scheduler.substring(
      cancelPendingStart,
      scheduledExistsStart,
    );
    expect(
      cancelPending,
      contains('existingPendingIntent(context, id, intent)'),
    );
    expect(cancelPending, isNot(contains('pendingIntent(context')));
    expect(scheduler, contains('PendingIntent.FLAG_NO_CREATE'));
  });

  test('AlarmService 未初始化时取消也会真实清理系统队列', () {
    final alarmService = File(
      'lib/services/alarm_service.dart',
    ).readAsStringSync();

    final cancelStart = alarmService.indexOf('Future<void> cancel(int id)');
    final cancelAllStart = alarmService.indexOf('Future<void> cancelAll()');
    final pendingStart = alarmService.indexOf(
      'Future<List<int>> pendingIds()',
      cancelAllStart,
    );
    expect(cancelStart, greaterThanOrEqualTo(0));
    expect(cancelAllStart, greaterThan(cancelStart));
    expect(pendingStart, greaterThan(cancelAllStart));

    final cancel = alarmService.substring(cancelStart, cancelAllStart);
    final cancelAll = alarmService.substring(cancelAllStart, pendingStart);
    expect(cancel, isNot(contains('if (!_initialized) return;')));
    expect(cancel, contains('if (!_initialized) await init();'));
    expect(cancel, contains('for (final queueId in _pluginAlarmQueueIds(id))'));
    expect(cancel, contains('await _plugin.cancel(queueId);'));
    expect(
      cancel,
      contains('await NativeReminderRingtone.cancelOrThrow(queueId);'),
    );
    expect(cancel, contains('final failures = <Object>[];'));
    expect(cancel, contains('failures.add(e);'));
    expect(cancel, contains('旧闹钟队列清理失败'));
    expect(
      cancel.indexOf('if (!_initialized) await init();'),
      lessThan(
        cancel.indexOf('for (final queueId in _pluginAlarmQueueIds(id))'),
      ),
      reason: '冷启动切换提醒方式时，取消旧 alarm 不能静默成功后再注册新通知。',
    );

    expect(cancelAll, isNot(contains('if (!_initialized) return;')));
    expect(cancelAll, contains('if (!_initialized) await init();'));
    expect(cancelAll, contains('await _plugin.cancelAll();'));
    expect(cancelAll, contains('await NativeReminderRingtone.cancelAll();'));
    expect(cancelAll, contains('闹钟队列批量清理失败'));

    final pendingEnd = alarmService.indexOf(
      'Future<void> _verifyPluginPendingIds',
      pendingStart,
    );
    expect(pendingEnd, greaterThan(pendingStart));
    final pending = alarmService.substring(pendingStart, pendingEnd);
    expect(pending, contains('if (!_initialized) await init();'));
    expect(pending, contains('_plugin.pendingNotificationRequests()'));
    expect(pending, contains('NativeReminderRingtone.pendingIdsOrThrow()'));
    expect(pending, isNot(contains('return const [];')));
  });
}
