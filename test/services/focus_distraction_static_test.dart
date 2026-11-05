import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Android strict focus can monitor distracting foreground apps', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();
    final service = File(
      'lib/services/focus_distraction_service.dart',
    ).readAsStringSync();
    final provider = File(
      'lib/providers/pomodoro_provider.dart',
    ).readAsStringSync();
    final model = File('lib/models/pomodoro.dart').readAsStringSync();
    final picker = File(
      'lib/widgets/focus_distraction_app_picker.dart',
    ).readAsStringSync();
    final screen = File('lib/screens/pomodoro_screen.dart').readAsStringSync();

    expect(manifest, contains('android.permission.PACKAGE_USAGE_STATS'));
    expect(manifest, contains('tools:ignore="ProtectedPermissions"'));
    expect(manifest, contains('android.permission.BIND_ACCESSIBILITY_SERVICE'));
    expect(manifest, contains('DuoyiFocusBlockerAccessibilityService'));
    expect(
      manifest,
      contains('@xml/duoyi_focus_blocker_accessibility_service'),
    );
    expect(service, contains("'duoyi/focus_distraction'"));
    expect(service, contains('openUsageAccessSettings'));
    expect(service, contains('openAccessibilitySettings'));
    expect(service, contains('setFocusBlocker'));
    expect(service, contains('accessibilityGranted'));
    expect(service, contains('blockerConfigured'));
    expect(service, contains('getForegroundApp'));
    expect(mainActivity, contains('private val focusDistractionChannel'));
    expect(mainActivity, contains('UsageStatsManager'));
    expect(mainActivity, contains('AppOpsManager.OPSTR_GET_USAGE_STATS'));
    expect(mainActivity, contains('Settings.ACTION_USAGE_ACCESS_SETTINGS'));
    expect(mainActivity, contains('Settings.ACTION_ACCESSIBILITY_SETTINGS'));
    expect(mainActivity, contains('setFocusBlocker'));
    expect(mainActivity, contains('hasFocusBlockerAccessibilityAccess'));
    expect(mainActivity, contains('FocusBlockerStore.setConfig'));
    expect(mainActivity, contains('"getInstalledApps"'));
    expect(mainActivity, contains('queryIntentActivities'));
    expect(mainActivity, contains('Intent.ACTION_MAIN'));
    expect(mainActivity, contains('Intent.CATEGORY_LAUNCHER'));
    expect(mainActivity, contains('appPackage == packageName'));
    expect(mainActivity, contains('seen.add(appPackage)'));
    expect(mainActivity, contains('loadLabel(packageManager)'));
    expect(mainActivity, contains('ApplicationInfo.FLAG_SYSTEM'));
    expect(mainActivity, contains('sortedBy'));
    expect(manifest, isNot(contains('QUERY_ALL_PACKAGES')));
    final launchQueries = manifest.substring(
      manifest.indexOf('<queries>'),
      manifest.indexOf('</queries>'),
    );
    expect(launchQueries, contains('android.intent.action.MAIN'));
    expect(launchQueries, contains('android.intent.category.LAUNCHER'));
    expect(mainActivity, contains('queryUsageStats'));
    expect(mainActivity, contains('foregroundPackageName'));
    final blocker = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiFocusBlockerAccessibilityService.kt',
    ).readAsStringSync();
    final blockerXml = File(
      'android/app/src/main/res/xml/duoyi_focus_blocker_accessibility_service.xml',
    ).readAsStringSync();
    expect(blocker, contains('class DuoyiFocusBlockerAccessibilityService'));
    expect(blocker, contains('AccessibilityService'));
    expect(blocker, contains('TYPE_WINDOW_STATE_CHANGED'));
    expect(blocker, contains('FocusBlockerStore.isBlocked'));
    expect(blocker, contains('FocusBlockerStore.recordBlockedPackage'));
    expect(blocker, contains('isDuplicateBounce'));
    expect(blocker, contains('bounceDebounceMillis = 1500L'));
    expect(blocker, contains('Uri.Builder()'));
    expect(
      blocker,
      contains('appendQueryParameter("blocked", blockedPackage)'),
    );
    // 保留精确的 startActivity 调用点，并要求失败必须留日志（等价或更强）。
    expect(blocker, contains('runCatching { startActivity(intent) }'));
    expect(blocker, contains('.onFailure { error ->'));
    expect(blocker, contains('Log.w(tag, "focus blocker bounce failed for'));
    expect(blocker, contains('MainActivity::class.java'));
    expect(blockerXml, contains('typeWindowStateChanged'));

    expect(model, contains('bool monitorDistractingApps'));
    expect(model, contains('List<String> distractingAppPackages'));
    expect(model, contains('distractingApp'));
    expect(model, contains('appPackage'));
    expect(provider, contains('FocusDistractionService.instance'));
    expect(provider, contains('Timer? _distractionTimer'));
    expect(provider, contains('setMonitorDistractingApps'));
    expect(provider, contains('setDistractingAppPackages'));
    expect(provider, contains('openFocusAccessibilitySettings'));
    expect(provider, contains('setFocusBlocker'));
    expect(provider, contains('_checkDistractingForegroundApp'));
    expect(provider, contains('FocusPenaltyReason.distractingApp'));
    expect(service, contains('class InstalledFocusApp'));
    expect(service, contains('getInstalledApps'));
    expect(service, contains('packageName'));
    expect(service, contains('isSystemApp'));
    expect(model, contains('String distractingAppSelectionMode'));
    expect(model, contains("distractionModeBlacklist = 'blacklist'"));
    expect(model, contains("distractionModeWhitelist = 'whitelist'"));
    expect(model, contains('resolveBlockedDistractionPackages'));
    expect(provider, contains('setDistractingAppSelectionMode'));
    expect(provider, contains('loadInstalledFocusApps'));
    expect(provider, contains('isDistractionWhitelistMode'));
    expect(provider, contains('focusDistractionAppScanFailed'));
    expect(picker, contains('class FocusDistractionAppPicker'));
    expect(picker, contains('SegmentedButton<String>'));
    expect(picker, contains('CheckboxListTile'));
    expect(screen, contains('focus_distraction_app_picker.dart'));
    expect(screen, contains('_showDistractingAppPicker'));
    expect(screen, isNot(contains('分心应用包名')));
    expect(screen, contains('监控分心应用'));
    expect(screen, contains('使用情况权限'));
    expect(screen, contains('辅助功能拦截'));
  });

  test('原生组件短名/拦截事件/图标/通知通道契约', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();
    final components = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/FocusBlockerComponents.kt',
    ).readAsStringSync();
    final expiry = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/FocusBlockerExpiry.kt',
    ).readAsStringSync();
    final blocker = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiFocusBlockerAccessibilityService.kt',
    ).readAsStringSync();
    final provider = File(
      'lib/providers/pomodoro_provider.dart',
    ).readAsStringSync();
    final service = File(
      'lib/services/focus_distraction_service.dart',
    ).readAsStringSync();
    final picker = File(
      'lib/widgets/focus_distraction_app_picker.dart',
    ).readAsStringSync();
    final screen = File('lib/screens/pomodoro_screen.dart').readAsStringSync();
    final model = File('lib/models/pomodoro.dart').readAsStringSync();

    // 组件短名必须被规范化后比较（真机存 `.Cls` 形式）。
    expect(components, contains('object FocusBlockerComponents'));
    expect(components, contains('normalizeClassName'));
    expect(components, contains('if (clean.startsWith("."))'));
    expect(mainActivity, contains('FocusBlockerComponents.matches'));
    expect(mainActivity, contains('ComponentName.unflattenFromString(entry)'));
    expect(
      mainActivity,
      isNot(
        contains(
          'val expected = ComponentName(\n'
          '            this,\n'
          '            DuoyiFocusBlockerAccessibilityService::class.java,\n'
          '        ).flattenToString()',
        ),
      ),
    );
    expect(mainActivity, contains('Settings.Secure.ACCESSIBILITY_ENABLED'));
    expect(mainActivity, contains('isFocusBlockerAccessibilityActive'));
    expect(mainActivity, contains('"accessibilityActive"'));
    expect(mainActivity, contains('"blockerExpiresAt"'));

    // blocker 配置必须带有限失效时刻，冷启动清理僵尸配置。
    expect(expiry, contains('object FocusBlockerExpiry'));
    expect(blocker, contains('keyExpiresAt'));
    expect(blocker, contains('fun clearIfExpired'));
    expect(blocker, contains('FocusBlockerExpiry.isActive'));
    expect(mainActivity, contains('FocusBlockerStore.clearIfExpired(this)'));
    expect(mainActivity, contains('expiresAtMs'));
    expect(blocker, contains('maxBounceAttempts'));
    expect(blocker, contains('Log.w(tag, "focus blocker bounce failed for'));

    // 应用列表在后台线程查询并回传 PNG 图标；输出顺序稳定。
    expect(mainActivity, contains('focusAppsExecutor.execute'));
    expect(mainActivity, contains('runOnUiThread'));
    expect(mainActivity, contains('private fun appIconBytes'));
    expect(mainActivity, contains('Bitmap.CompressFormat.PNG'));
    expect(mainActivity, contains('coerceIn(48, 192)'));
    expect(mainActivity, contains('"iconBytes" to'));
    expect(mainActivity, contains('"getAppLabel"'));
    expect(mainActivity, contains('sortedBy'));

    // Dart 侧图标解析要求合法 PNG，损坏即回退占位。
    expect(service, contains('_validPngBytes'));
    expect(service, contains('static InstalledFocusApp? fromMap'));
    expect(service, contains('iconBytes'));
    expect(service, contains('class FocusNativeBlockEvent'));
    expect(service, contains('class FocusBlockerLease'));
    expect(service, contains('FocusDistractionStatus copyWith('));
    expect(service, contains('withForeground'));
    expect(picker, contains('_FocusAppIcon'));
    expect(picker, contains('Image.memory'));
    expect(picker, contains('errorBuilder'));
    expect(picker, contains('Icons.apps_outlined'));

    // 轮询只更新前台包，不得重建状态丢掉授权字段。
    expect(provider, contains('withForeground'));
    expect(provider, contains('_consumeNativeBlockEvent'));
    expect(provider, contains('_applyBlockerConfig'));
    expect(provider, contains('_blockedPackagesForDetection'));
    expect(provider, contains('FocusBlockerLease.expiresAtMs'));
    expect(provider, contains('_resolveAppLabel'));
    expect(provider, contains('appLabel: resolvedAppLabel'));
    expect(provider, contains('refreshFocusDistractionStatus();'));
    expect(
      provider,
      isNot(
        contains(
          '_distractionStatus = FocusDistractionStatus(\n'
          '      supported: true,\n'
          '      accessGranted: true,',
        ),
      ),
    );

    // 惩罚记录保留包名并新增可选应用名，旧记录回退包名。
    expect(model, contains('final String? appLabel;'));
    expect(model, contains("'appLabel': appLabel"));
    expect(model, contains('get displayAppLabel'));
    expect(screen, contains('_distractionStatusText'));
    expect(screen, contains('displayAppLabel'));
    expect(screen, contains('displayAppPackage'));
    expect(
      screen,
      contains('unawaited(provider.refreshFocusDistractionStatus());'),
    );
    // 设置页返回后不再用离开前的读数当最终判断。
    expect(
      screen,
      isNot(contains('await provider.refreshFocusDistractionStatus();')),
    );
  });

  test('原生拉回：请求不等于确认返回，固定冷却不饿死后续拉回', () {
    final policy = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/FocusBlockerBouncePolicy.kt',
    ).readAsStringSync();
    final blocker = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiFocusBlockerAccessibilityService.kt',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();
    final policyTest = File(
      'android/app/src/test/kotlin/com/duoyi/duoyi/FocusBlockerBouncePolicyTest.kt',
    );

    // 纯 Kotlin 策略层：固定冷却门控 + 窗口观察 + 共享前台状态，不依赖 Android。
    expect(policy, contains('class FocusBlockerBounceGate'));
    expect(policy, contains('fun delayUntilAllowed'));
    expect(policy, contains('class FocusBlockerWindowTracker'));
    expect(policy, contains('fun normalizeObservedAt'));
    expect(policy, contains('object FocusBlockerForegroundState'));
    expect(policy, contains('fun shouldRetryReturn'));
    // 待执行状态对象是服务 generation/pending/deferred 的唯一权威。
    expect(policy, contains('class FocusBlockerPendingWorkState'));
    expect(policy, contains('fun finishVerificationCycle'));
    expect(policy, contains('fun armDeferred'));
    expect(policy, contains('fun consumeDeferred'));
    expect(policy, contains('fun isCurrent'));
    expect(policy, isNot(contains('import android.')));

    // 服务端：内部门控被拒事件不推进已接受时刻，冷却结束能再次被接受。
    expect(blocker, contains('FocusBlockerBounceGate(bounceDebounceMillis)'));
    expect(blocker, contains('bounceGate.delayUntilAllowed'));
    expect(blocker, contains('FocusBlockerWindowTracker.normalizeObservedAt'));
    expect(blocker, contains('SystemClock.uptimeMillis()'));
    expect(blocker, isNot(contains('SystemClock.elapsedRealtime')));
    // 重复事件只排一次固定截止时刻的复查，且复查前重新确认前台与配置。
    expect(blocker, contains('scheduleDeferredCheck'));
    expect(
      blocker,
      contains('workState.armDeferred(blockedPackage, deadlineUptimeMillis)'),
    );
    expect(blocker, contains('private val deferredCheck = Runnable'));
    // 验证回调独立可取消；finish-only 路径不得做整体清理（deferred 必须保留）。
    expect(blocker, contains('private val verificationCheck = Runnable'));
    expect(blocker, contains('workState.finishVerificationCycle()'));
    expect(
      blocker,
      contains('finishVerificationCycle(reason = "unconfirmed")'),
    );
    expect(blocker, isNot(contains('removeCallbacksAndMessages(null)')));
    expect(
      blocker,
      contains(
        'FocusBlockerForegroundState.foregroundPackageName() == blockedPackage',
      ),
    );
    // 延迟请求前重新读取配置；确认返回只在真的回到多仪时记录。
    expect(
      blocker,
      contains('FocusBlockerStore.isBlocked(this, blockedPackage)'),
    );
    expect(
      blocker,
      contains('FocusBlockerForegroundState.observeForeground(observedPackage'),
    );
    expect(blocker, contains('confirmPendingReturn'));
    expect(blocker, contains('focus blocker confirmed return to duoyi from'));
    expect(blocker, contains('focus blocker requested'));
    expect(blocker, isNot(contains('focus blocker bounced')));
    expect(blocker, contains('FocusBlockerForegroundState.shouldRetryReturn'));
    expect(blocker, contains('focus blocker return unconfirmed for'));
    expect(blocker, contains('cancelAllWork'));
    // 完整取消必须带触发窗口与原因：已发出的 requested 不能无声消失。
    expect(blocker, contains('focus blocker cancelled pending work: reason='));
    // 迟到回调必须用 workState 的 generation 判定，陈旧轮次不得补发。
    expect(blocker, contains('workState.isCurrent('));
    // 只为真实检测记录原生拦截事件：同轮补发与 deferred 复查不重复记账。
    expect(blocker, contains('recordDetection = true'));
    expect(
      blocker,
      contains('startBounceCycle(blockedPackage, recordDetection = true)'),
    );

    // 本应用真实前台确认：API 29+ 用 onTopResumedActivityChanged，更低版本退回 onResume。
    expect(mainActivity, contains('override fun onTopResumedActivityChanged('));
    expect(mainActivity, contains('observeOwnForegroundConfirmation'));
    expect(
      mainActivity,
      contains('FocusBlockerForegroundState.observeForeground(packageName'),
    );
    expect(
      mainActivity,
      contains('Build.VERSION.SDK_INT < Build.VERSION_CODES.Q'),
    );

    // 策略单元测试必须存在并覆盖突发/陈旧窗口/重试预算。
    expect(policyTest.existsSync(), isTrue);
    final policyTestSource = policyTest.readAsStringSync();
    expect(policyTestSource, contains('continuousDuplicateBurst'));
    expect(policyTestSource, contains('staleSplashObservation'));
    expect(policyTestSource, contains('shouldRetryReturn'));
    expect(
      policyTestSource,
      contains('cooldownIsGlobalAcrossBlockedPackageChanges'),
    );
    expect(
      policyTestSource,
      contains('eventTimelineKeepsTheEventArmedDeferredCheckAfterUnconfirmed'),
    );
  });

  test('UsageEvents 补漏：窄读取、非导出配置广播、可逆生命周期', () {
    final policy = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/FocusBlockerBouncePolicy.kt',
    ).readAsStringSync();
    final blocker = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiFocusBlockerAccessibilityService.kt',
    ).readAsStringSync();
    final usageAccess = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/FocusBlockerUsageAccess.kt',
    ).readAsStringSync();
    final blockerXml = File(
      'android/app/src/main/res/xml/duoyi_focus_blocker_accessibility_service.xml',
    ).readAsStringSync();
    final usageTest = File(
      'android/app/src/test/kotlin/com/duoyi/duoyi/FocusBlockerUsagePolicyTest.kt',
    );

    // 纯策略：reducer / 监控状态 / loss / 每轮请求上限，均无 Android 依赖。
    expect(policy, contains('class FocusBlockerUsageEventsReducer'));
    expect(policy, contains('class FocusBlockerUsageMonitorState'));
    expect(policy, contains('sealed class FocusBlockerUsageVerdict'));
    expect(policy, contains('fun observeLoss'));
    expect(policy, contains('fun attemptLimit'));
    expect(policy, contains('defaultCycleAttemptLimit'));
    expect(policy, isNot(contains('import android.')));

    // adapter：只走 public queryEvents + AppOps 授权检查，禁止内容读取与 lastTimeUsed 猜测。
    expect(usageAccess, contains('queryEvents('));
    expect(usageAccess, contains('OPSTR_GET_USAGE_STATS'));
    expect(usageAccess, contains('MODE_ALLOWED'));
    expect(usageAccess, contains('unsafeCheckOpNoThrow'));
    expect(usageAccess, contains('isInteractive'));
    expect(usageAccess, contains('isKeyguardLocked'));
    expect(usageAccess, contains('FocusBlockerUsageObservation('));
    expect(usageAccess, isNot(contains('queryUsageStats(')));
    expect(usageAccess, isNot(contains('getLastTimeUsed(')));
    expect(usageAccess, isNot(contains('event.className')));
    expect(usageAccess, isNot(contains('event.text')));
    expect(usageAccess, isNot(contains('AccessibilityNodeInfo')));
    expect(usageAccess, isNot(contains('getRootInActiveWindow')));
    expect(usageAccess, isNot(contains('Settings.ACTION')));

    // 服务：配置广播（非导出）、单线程查询、generation 复核、销毁清理。
    expect(blocker, contains('FocusBlockerUsageAccess.readRecentEvents'));
    expect(blocker, contains('FocusBlockerUsageAccess.hasUsageAccess'));
    expect(
      blocker,
      contains('FocusBlockerUsageAccess.isDeviceAwakeAndUnlocked'),
    );
    expect(blocker, contains('Context.RECEIVER_NOT_EXPORTED'));
    expect(
      blocker,
      contains('IntentFilter(FocusBlockerStore.actionConfigChanged)'),
    );
    expect(
      blocker,
      contains(
        'sendBroadcast(Intent(actionConfigChanged).setPackage(context.packageName))',
      ),
    );
    expect(blocker, contains('Executors.newSingleThreadExecutor()'));
    expect(blocker, contains('usageExecutor.execute'));
    expect(blocker, contains('usageExecutor.shutdownNow()'));
    expect(blocker, contains('unregisterReceiver(receiver)'));
    expect(blocker, contains('private val usagePoll = object : Runnable'));
    expect(blocker, contains('usageMonitor.beginQuery()'));
    expect(blocker, contains('usageMonitor.completeQuery(generation)'));
    expect(blocker, contains('usageMonitor.isCurrent(generation)'));
    expect(blocker, contains('usageMonitor.stop()'));
    expect(blocker, contains('usageReducer.consume(verdict)'));
    expect(blocker, contains('workState.attemptLimit()'));
    expect(blocker, contains('maxAttempts = usageCycleAttempts'));
    // 不得用 lastTimeUsed/轮询接口判定前台，也不得走全局动作绕过锁屏。
    expect(blocker, isNot(contains('queryUsageStats(')));
    expect(blocker, isNot(contains('lastTimeUsed')));
    expect(blocker, isNot(contains('performGlobalAction(')));
    expect(blocker, isNot(contains('AccessibilityNodeInfo')));

    // 无障碍配置保持原两事件且不读取窗口内容（不靠提高 AA 能力当修复）。
    expect(blockerXml, contains('typeWindowStateChanged|typeWindowsChanged'));
    expect(blockerXml, contains('android:canRetrieveWindowContent="false"'));
    expect(blockerXml, isNot(contains('typeWindowContentChanged')));
    expect(blockerXml, isNot(contains('canRetrieveWindowContent="true"')));

    // 真实竞态回归必须存在：旧事件/未来/过旧、loss 保留时刻、冷却不消费、监控有效期。
    expect(usageTest.existsSync(), isTrue);
    final usageTestSource = usageTest.readAsStringSync();
    expect(
      usageTestSource,
      contains(
        'emptyOldFutureAndBeforeSessionEventsAreNeverForegroundEvidence',
      ),
    );
    expect(
      usageTestSource,
      contains('lossPreservesObservationTimeSoOlderEventsCannotReviveIt'),
    );
    expect(
      usageTestSource,
      contains('cooldownRejectionKeepsTheEventForTheNextFreshQuery'),
    );
    expect(
      usageTestSource,
      contains('usageCycleAllowsOnlyOneRequestWhileAaKeepsTwo'),
    );
    expect(
      usageTestSource,
      contains(
        'monitorGenerationRejectsLateWorkerResultsAndKeepsOneInflightQuery',
      ),
    );
  });

  test('焦点状态快照离开主线程：单飞异步 + 有界等待 + 销毁回收', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();
    final query = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/FocusStatusQuery.kt',
    ).readAsStringSync();
    final queryTest = File(
      'android/app/src/test/kotlin/com/duoyi/duoyi/FocusStatusQueryTest.kt',
    );

    // 主线程只入队：两个入口都换成异步快照，不再同步回 map / 前台包名。
    expect(mainActivity, contains('"getStatus" -> requestFocusStatus(result)'));
    expect(
      mainActivity,
      contains('"getForegroundApp" -> requestFocusStatus(result)'),
    );
    expect(
      mainActivity,
      isNot(contains('"foregroundPackage" to foregroundPackageName(),')),
    );
    expect(
      mainActivity,
      isNot(
        contains(
          '"getForegroundApp" -> result.success(foregroundPackageName())',
        ),
      ),
    );
    expect(
      mainActivity,
      contains(
        'private val focusStatusExecutor = Executors.newSingleThreadExecutor()',
      ),
    );
    expect(
      mainActivity,
      contains('postToOwner = { runnable -> ownerHandler.post(runnable) }'),
    );
    expect(
      mainActivity,
      contains('readSnapshot = { readFocusStatusSnapshot(appContext) }'),
    );
    expect(mainActivity, contains('val appContext = applicationContext'));
    expect(mainActivity, contains('focusStatusExecutor.shutdownNow()'));
    expect(mainActivity, contains('focusStatusQueryHolder.value.dispose()'));
    // 诊断只保留耗时，不带包名等应用信息。
    expect(
      mainActivity,
      contains(
        r'Log.w(queryLogTag, "focus status query took ${elapsedMillis}ms")',
      ),
    );

    // 快照字段沿用旧契约，读取整体收在 Context 参数的后台函数里。
    expect(
      mainActivity,
      contains('private fun readFocusStatusSnapshot(context: Context)'),
    );
    expect(
      mainActivity,
      contains(
        '"foregroundPackage" to foregroundPackageName(context, accessGranted)',
      ),
    );
    expect(
      mainActivity,
      contains(
        'private fun foregroundPackageName(context: Context, accessGranted: Boolean)',
      ),
    );
    expect(
      mainActivity,
      contains(
        '"accessibilityActive" to isFocusBlockerAccessibilityActive(context)',
      ),
    );

    // 纯 Kotlin 查询器：无 Android 依赖、单飞、有界、owner 线程、销毁 generation。
    expect(query, isNot(contains('import android.')));
    expect(query, contains('class FocusStatusQuery<S : Any>('));
    expect(query, contains('const val defaultPendingRequestLimit = 32'));
    expect(query, contains('const val defaultSlowQueryWarnMillis = 500L'));
    expect(query, contains('FocusStatusUnavailable.BUSY'));
    expect(query, contains('FocusStatusUnavailable.DISPOSED'));
    expect(query, contains('if (token != generation) return'));
    expect(query, contains('must be used on its owner thread'));

    // 单元测试覆盖合并、上限、owner 队列不被阻塞、销毁后迟到结果丢弃。
    expect(queryTest.existsSync(), isTrue);
    final queryTestSource = queryTest.readAsStringSync();
    expect(
      queryTestSource,
      contains('readRunsOnWorkerAndNeverOnTheOwnerQueue'),
    );
    expect(
      queryTestSource,
      contains('ownerQueueKeepsRunningControlActionsWhileSnapshotIsBlocked'),
    );
    expect(
      queryTestSource,
      contains('concurrentRequestsShareOneInFlightSnapshot'),
    );
    expect(
      queryTestSource,
      contains('waitingCallbacksAreBoundedWithExplicitBusy'),
    );
    expect(
      queryTestSource,
      contains('disposeRepliesDisposedOnceAndDropsLateSuccess'),
    );
    expect(
      queryTestSource,
      contains('completionPostedBeforeDisposeIsDroppedToo'),
    );
    expect(queryTestSource, contains('requestMustBeMadeFromTheOwnerThread'));
    expect(queryTestSource, contains('slowSnapshotWarnsOnceWithDurationOnly'));
  });
}
