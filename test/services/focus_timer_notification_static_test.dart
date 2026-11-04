import 'dart:io';

import 'package:test/test.dart';

/// 专注计时持续通知的原生/Flutter 契约守卫。
///
/// 这里只断言实现必须存在的结构与行为，不依赖运行 Android 设备：
/// - 独立 specialUse 前台服务，不伪装 mediaPlayback；
/// - 渠道/通知 ID 固定且复用固定 Logo；
/// - Dart 注入品牌文案与主色，原生不硬编码中文；
/// - provider 在启动/暂停/完成/重置/dispose/恢复时正确同步或清理。
void main() {
  test('focus timer notification uses an independent specialUse service', () {
    final service = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/services/FocusTimerForegroundService.kt',
    ).readAsStringSync();
    final model = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/services/FocusTimerNotificationModel.kt',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();

    expect(service, contains('class FocusTimerForegroundService : Service()'));
    expect(
      service,
      contains('ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE'),
    );
    expect(service, isNot(contains('mediaPlayback')));
    expect(service, contains('R.drawable.ic_stat_duoyi'));
    expect(service, contains('const val channelId = "duoyi_focus_timer_v1"'));
    expect(service, contains('const val notificationId = 951_101'));
    expect(service, contains('setOngoing(true)'));
    expect(service, contains('setSilent(true)'));
    expect(service, contains('setOnlyAlertOnce(true)'));
    expect(service, contains('setUsesChronometer(true)'));
    expect(service, contains('setChronometerCountDown'));
    expect(service, contains('setProgress(progressMax'));
    expect(service, contains('SystemClock.elapsedRealtime()'));
    expect(service, contains('setShowWhen(model.usesChronometer)'));
    expect(
      service,
      contains('setWhen(model.notificationWhen(System.currentTimeMillis()))'),
    );
    expect(model, contains('duoyi://tab/focus'));
    expect(service, contains('MainActivity::class.java'));
    expect(service, contains('STOP_FOREGROUND_REMOVE'));
    expect(service, contains('manager.cancel(notificationId)'));
    expect(service, contains('expiryCallback'));
    expect(
      service,
      contains('Log.w(tag, "focus timer foreground start failed", error)'),
    );
    expect(
      service,
      contains('Log.w(tag, "focus timer service start failed", error)'),
    );
    // 反向断言：原生字符串字面量不写死中文品牌文案（全部由 Dart 注入）。
    final chineseLiteral = RegExp(r'"[^"\n]*[\u4e00-\u9fff][^"\n]*"');
    expect(chineseLiteral.hasMatch(service), isFalse);
    expect(chineseLiteral.hasMatch(model), isFalse);

    // 渠道名/阶段名/任务名都来自注入的 payload。
    expect(model, contains('val noTaskLabel: String'));
    expect(model, contains('val pausedLabel: String'));
    expect(model, contains('val phaseLabel: String'));
    expect(model, contains('val accentColorArgb: Int'));
    expect(model, contains('fun chronometerBaseElapsed'));
    expect(model, contains('val expiryDelayMillis: Long'));

    // MainActivity 注册独立通道并转发到期事件，不改既有 duoyi/update 段。
    expect(
      mainActivity,
      contains('private val focusTimerChannel = "duoyi/focus_timer"'),
    );
    expect(mainActivity, contains('FocusTimerForegroundService.sync(this'));
    expect(mainActivity, contains('FocusTimerForegroundService.stop(this'));
    expect(
      mainActivity,
      contains('focusTimerMethodChannel.invokeMethod("expired"'),
    );
    expect(mainActivity, contains('private var focusTimerMethodChannel'));
  });

  test(
    'dart timer service injects brand, color and cleans up on every exit',
    () {
      final dartService = File(
        'lib/services/focus_timer_notification_service.dart',
      ).readAsStringSync();
      final provider = File(
        'lib/providers/pomodoro_provider.dart',
      ).readAsStringSync();
      final main = File('lib/main.dart').readAsStringSync();
      final i18n = File('lib/core/i18n.dart').readAsStringSync();

      expect(dartService, contains("MethodChannel('duoyi/focus_timer')"));
      expect(dartService, contains('class FocusTimerNotificationBrand'));
      expect(dartService, contains('class FocusTimerNotificationPayload'));
      expect(dartService, contains('static const String returnUri'));
      expect(dartService, contains("'paused': paused"));
      expect(dartService, contains("'remainingMillis': remainingMillis"));
      expect(dartService, contains("'progressPermille': progressPermille"));
      expect(dartService, contains("'accentColorArgb': accentColorArgb"));
      expect(dartService, contains('setBrand'));
      expect(
        dartService,
        contains("_channel.invokeMethod<void>(method, arguments)"),
      );
      // 通知失败不得打断计时。
      expect(dartService, contains('debugPrint('));
      expect(dartService, contains("call.method == 'expired'"));

      // provider 在全部状态出口同步或清理通知。
      expect(provider, contains('FocusTimerNotificationService _focusTimer'));
      expect(provider, contains('void _syncFocusTimerNotification()'));
      expect(
        provider,
        contains('unawaited(_focusTimer.sync(_state, paused: false))'),
      );
      expect(
        provider,
        contains('unawaited(_focusTimer.sync(_state, paused: true))'),
      );
      expect(provider, contains('unawaited(_focusTimer.stop())'));
      expect(provider, contains('_handleNativeFocusTimerExpired'));
      expect(
        provider,
        contains('_focusTimer.onExpired = _handleNativeFocusTimerExpired'),
      );
      final syncCalls = RegExp(
        r'_syncFocusTimerNotification\(\);',
      ).allMatches(provider);
      // start（两处分支）、pause、complete、skip、reset、countUp、config、
      // loadFromStorage、setTaskName、setTaskTarget、resumed 至少 10 个出口。
      expect(syncCalls.length, greaterThanOrEqualTo(10));

      // 品牌文案与主色在同一条注入路径上推给原生，切换主题/语言立即生效。
      expect(
        main,
        contains("import 'services/focus_timer_notification_service.dart';"),
      );
      expect(
        main,
        contains('FocusTimerNotificationService.instance.setBrand('),
      );
      expect(main, contains('brand.strings.focusStateFocus'));
      expect(main, contains('brand.strings.focusStateShortBreak'));
      expect(main, contains('brand.strings.focusStateLongBreak'));
      expect(main, contains('brand.theme.colorScheme.primary.toARGB32()'));
      expect(main, contains('I18n.tr(\'focus.timer.notif.channel_name\')'));
      expect(main, contains('I18n.tr(\'focus.timer.notif.no_task\')'));
      expect(main, contains('I18n.tr(\'focus.timer.notif.paused\')'));

      // 中英双语文案键必须成对存在。
      for (final key in <String>[
        'focus.timer.notif.channel_name',
        'focus.timer.notif.no_task',
        'focus.timer.notif.paused',
        'focus.distraction.status.accessibility_active',
        'focus.distraction.status.accessibility_pending',
        'focus.distraction.status.blocker_unconfigured',
        'focus.distraction.status.usage_only',
        'focus.distraction.status.missing',
      ]) {
        final occurrences = RegExp("'$key':").allMatches(i18n).length;
        expect(occurrences, 2, reason: 'missing zh/en pair for $key');
      }
    },
  );
}
