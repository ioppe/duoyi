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
}
