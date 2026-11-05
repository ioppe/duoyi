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

    // 可见时间：正文以本地化时间开头，任务名放 BigText 展开详情。
    expect(model, contains('val contentText: String'));
    expect(model, contains('val detailText: String'));
    expect(
      model,
      contains('fun formatDuration(millis: Long, roundUp: Boolean = false)'),
    );
    expect(model, contains('val remainingLabel: String'));
    expect(model, contains('val elapsedLabel: String'));
    expect(service, contains('setContentText(model.contentText)'));
    expect(
      service,
      contains('NotificationCompat.BigTextStyle().bigText(model.detailText)'),
    );

    // 秒级刷新由原生单调时钟推进；没有 wakelock，也不靠 15s 进度节流。
    expect(service, contains('handler.postDelayed(this, tickMillis)'));
    expect(service, contains('private const val tickMillis = 1_000L'));
    expect(service, isNot(contains('15_000L')));
    expect(service, isNot(contains('WakeLock')));
    expect(service, isNot(contains('PARTIAL_WAKE_LOCK')));

    // canonical 锚点：首次同步折算当前时间，到期只用锚点，重推不延长期限。
    expect(model, contains('val anchorMillis: Long = 0L'));
    expect(model, contains('fun rebasedAt(wallClockNow: Long)'));
    expect(
      model,
      contains('fun expiryDelayMillisAt(wallClockNow: Long): Long'),
    );
    expect(service, contains('val base = model.rebasedAt(nowWallClock)'));
    expect(service, contains('model.expiryDelayMillisAt(nowWallClock)'));
    expect(
      service,
      contains('scheduleTicker(base, SystemClock.elapsedRealtime())'),
    );

    // 通知按钮：标准 actions，显式 MainActivity + 独立 data URI。
    expect(model, contains('enum class FocusTimerControlAction'));
    expect(model, contains('val hasControlBinding: Boolean'));
    expect(
      model,
      contains('val controlActions: List<FocusTimerControlAction>'),
    );
    expect(
      model,
      contains('fun controlUri(action: FocusTimerControlAction): String'),
    );
    expect(model, contains('const val controlHost = "focus-timer"'));
    expect(
      service,
      contains('builder.addAction(actionIcon(action), label, pending)'),
    );
    expect(service, contains('Intent.ACTION_VIEW'));
    expect(service, contains('PendingIntent.getActivity('));
    expect(service, contains('Uri.parse(model.controlUri(action))'));
    expect(
      service,
      contains(
        'PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE',
      ),
    );

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
      // 可见时间/按钮文案与绑定身份都在同一条 payload 上注入。
      expect(dartService, contains("'anchorMillis': anchorMillis"));
      expect(dartService, contains("'controlSessionId': controlSessionId"));
      expect(dartService, contains("'controlRevision': controlRevision"));
      expect(dartService, contains("'controlState': controlState"));
      expect(dartService, contains("'remainingLabel': remainingLabel"));
      expect(dartService, contains("'elapsedLabel': elapsedLabel"));
      expect(dartService, contains("'startActionLabel': startActionLabel"));
      expect(dartService, contains("'pauseActionLabel': pauseActionLabel"));
      expect(dartService, contains("'resetActionLabel': resetActionLabel"));
      // 主题/语言重推必须复用同一锚点与绑定，不能丢按钮或延长期限。
      expect(dartService, contains('anchorMillis: _lastAnchorMillis'));
      expect(dartService, contains('controlSessionId: _lastControlSessionId'));
      expect(dartService, contains('controlRevision: _lastControlRevision'));
      expect(dartService, contains('controlState: _lastControlState'));
      // 通知按钮深链解析器就在同一文件，供 main 分发复用。
      expect(dartService, contains('class FocusTimerNotificationControl'));
      expect(
        dartService,
        contains('static FocusTimerNotificationControl? parse('),
      );
      expect(dartService, contains("static const String host = 'focus-timer'"));
      expect(
        dartService,
        contains('static const int maxSessionIdLength = 128'),
      );
      expect(
        dartService,
        contains('static const Set<String> controlStates = <String>{'),
      );
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
      // provider 在所有状态出口同步或清理通知，且运行/暂停都带 canonical 锚点与控制身份。
      expect(provider, contains('anchorMillis: focusTimerAnchorMillis'));
      expect(provider, contains('int get focusTimerAnchorMillis =>'));
      expect(provider, contains('controlSessionId: _widgetSessionId'));
      expect(provider, contains('controlState: _widgetTimerState.wireName'));
      expect(provider, contains('_focusTimer.sync('));
      expect(provider, contains('paused: false,'));
      expect(provider, contains('paused: true,'));
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
      expect(main, contains('I18n.tr(\'focus.timer.notif.remaining\')'));
      expect(main, contains('I18n.tr(\'focus.timer.notif.elapsed\')'));
      expect(main, contains('I18n.tr(\'focus.timer.notif.action.start\')'));
      expect(main, contains('I18n.tr(\'focus.timer.notif.action.pause\')'));
      expect(main, contains('I18n.tr(\'focus.timer.notif.action.reset\')'));

      // 通知按钮落回既有深链分发：先回到专注页，再复用小组件绑定校验。
      expect(main, contains('FocusTimerNotificationControl.parse(uri)'));
      expect(main, contains('uri.host == FocusTimerNotificationControl.host'));
      expect(main, contains('state.navigateTo(4, allowHidden: true);'));
      expect(main, contains('pomodoro.applyWidgetControl('));
      // 不得新增第二套深链/广播转发，也不得让畸形控制请求落到 unknown 兜底。
      expect(main, isNot(contains("Uri.parse('duoyi://focus-timer")));
      expect(
        main,
        contains('debugPrint(\'[DeepLink] rejected focus timer control:'),
      );

      // 中英双语文案键必须成对存在。
      for (final key in <String>[
        'focus.timer.notif.channel_name',
        'focus.timer.notif.no_task',
        'focus.timer.notif.paused',
        'focus.timer.notif.remaining',
        'focus.timer.notif.elapsed',
        'focus.timer.notif.action.start',
        'focus.timer.notif.action.pause',
        'focus.timer.notif.action.reset',
        'focus.distraction.status.accessibility_active',
        'focus.distraction.status.accessibility_pending',
        'focus.distraction.status.blocker_unconfigured',
        'focus.distraction.status.usage_only',
        'focus.distraction.status.missing',
      ]) {
        final occurrences = RegExp("'$key':").allMatches(i18n).length;
        expect(occurrences, 2, reason: 'missing zh/en pair for $key');
      }

      // ARB 模板与 checked-in generated 必须同步，避免只改 i18n.dart 造成缺词。
      final zhArb = File('lib/l10n/app_zh.arb').readAsStringSync();
      final enArb = File('lib/l10n/app_en.arb').readAsStringSync();
      final generatedZh = File(
        'lib/l10n/generated/app_localizations_zh.dart',
      ).readAsStringSync();
      final generatedEn = File(
        'lib/l10n/generated/app_localizations_en.dart',
      ).readAsStringSync();
      for (final arbKey in <String>[
        'focusTimerNotifRemaining',
        'focusTimerNotifElapsed',
        'focusTimerNotifActionStart',
        'focusTimerNotifActionPause',
        'focusTimerNotifActionReset',
      ]) {
        expect(zhArb, contains('"$arbKey"'), reason: 'missing zh ARB $arbKey');
        expect(enArb, contains('"$arbKey"'), reason: 'missing en ARB $arbKey');
        expect(
          generatedZh,
          contains('get $arbKey =>'),
          reason: 'missing zh generated getter $arbKey',
        );
        expect(
          generatedEn,
          contains('get $arbKey =>'),
          reason: 'missing en generated getter $arbKey',
        );
      }
    },
  );
}
