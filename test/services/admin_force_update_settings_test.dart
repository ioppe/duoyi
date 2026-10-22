import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('force update defaults use current 1.1.44 version floor', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final appVersion = File('lib/core/app_version.dart').readAsStringSync();
    final backend = File('backend/main.py').readAsStringSync();
    final adminScreen = File(
      'lib/screens/admin_screen.dart',
    ).readAsStringSync();

    expect(pubspec, contains('version: 1.1.44+140010'));
    expect(appVersion, contains("static const name = '1.1.44';"));
    expect(appVersion, contains('static const build = 140010;'));
    final backendConfig = File('backend/config.py').readAsStringSync();
    expect(backendConfig, contains('def _pubspec_app_version('));
    expect(backendConfig, contains('"pubspec.yaml"'));
    expect(
      backend,
      contains('APP_CURRENT_VERSION = SETTINGS.app_current_version'),
    );
    expect(backend, contains('def _normalize_update_version_floor'));
    expect(
      backend,
      contains('_normalize_update_version_floor(latest_version)'),
    );
    expect(
      backend,
      contains('_normalize_update_version_floor(minimum_supported_version)'),
    );
    expect(adminScreen, contains('当前客户端版本 \${AppVersion.name}'));
    expect(
      '$pubspec$appVersion$backend$adminScreen',
      isNot(contains('1.1.20')),
    );
  });

  test('admin settings expose force update policy through config', () {
    final backend = File('backend/main.py').readAsStringSync();
    final adminApi = File('lib/services/admin_api.dart').readAsStringSync();
    final adminScreen = File(
      'lib/screens/admin_screen.dart',
    ).readAsStringSync();
    final updateService = File(
      'lib/services/app_update_service.dart',
    ).readAsStringSync();
    final updatePolicy = File(
      'lib/core/app_update_policy.dart',
    ).readAsStringSync();
    final mainApp = File('lib/main.dart').readAsStringSync();
    final forceUpdateGate = File(
      'lib/widgets/force_update_gate.dart',
    ).readAsStringSync();

    for (final key in [
      'force_update_required',
      'latest_version',
      'minimum_supported_version',
      'update_notes',
      'update_download_url',
    ]) {
      expect(backend, contains(key));
      expect(adminScreen, contains(key));
    }

    expect(backend, contains('"app_update": update_policy'));
    expect(backend, contains('@app.get("/api/config")'));
    expect(adminApi, contains('forceUpdateRequired'));
    expect(adminApi, contains('minimumSupportedVersion'));
    expect(adminApi, contains('updateDownloadUrl'));
    expect(adminApi, contains('client.patch'));
    expect(adminScreen, contains("title: '应用更新'"));
    expect(adminScreen, contains("labelText: '版本策略'"));
    expect(adminScreen, contains("title: '版本选择'"));
    expect(adminScreen, contains('管理员只需选择上方策略'));
    expect(adminScreen, contains("_data['version_options']"));
    expect(
      adminScreen,
      contains('List<_AdminUpdateVersionOption> get _updateVersionOptions'),
    );
    expect(adminScreen, contains('_updateVersionOptionLabel'));
    expect(adminScreen, contains('_serverCurrentVersion'));
    expect(adminScreen, isNot(contains("labelText: '最新版本'")));
    expect(adminScreen, isNot(contains("labelText: '最低支持版本'")));
    expect(adminScreen, isNot(contains("hintText: '默认当前版本'")));
    expect(adminScreen, isNot(contains("hintText: '默认当前版本，低于该版本时强制更新'")));
    expect(adminScreen, contains("title: '更新内容预览'"));
    expect(adminScreen, contains('_updateNotesPreview'));
    expect(adminScreen, contains('保存时会自动写入以上摘要'));
    expect(adminScreen, isNot(contains("labelText: '更新内容摘要'")));
    expect(
      adminScreen,
      isNot(contains('final _updateNotesCtrl = TextEditingController()')),
    );
    expect(adminScreen, isNot(contains('_updateNotesForPolicy')));
    expect(adminScreen, isNot(contains('_updateNotesForSave')));
    expect(adminScreen, contains('_defaultUpdateNotesFor'));
    expect(adminScreen, contains("updateDownloadUrl: ''"));
    expect(adminScreen, contains('安装包与完整发布说明由后端发布通道自动读取'));
    expect(adminScreen, contains('_adminUpdatePresetCurrent'));
    expect(adminScreen, contains('_adminUpdatePresetNextPatch'));
    expect(adminScreen, contains('_adminUpdatePresetNextMinor'));
    expect(adminScreen, contains('_adminUpdatePresetMinimumNextPatch'));
    expect(adminScreen, contains('String _latestVersionForSave()'));
    expect(adminScreen, contains('String _minimumSupportedVersionForSave()'));
    expect(adminScreen, contains('_normalizedUpdateVersionsForSave'));
    expect(adminScreen, contains('isDefaultCurrentVersions'));
    expect(
      adminScreen,
      contains(
        "return (latestVersion: '', minimumSupportedVersion: '', updateNotes: '')",
      ),
    );
    expect(
      adminScreen,
      contains('String get _nextPatchMinimumVersion => _nextPatchVersion'),
    );
    expect(adminScreen, contains('void _syncUpdateVersionPreset()'));
    expect(adminScreen, contains('_syncUpdateVersionPreset();'));
    expect(adminScreen, contains('当前版本'));
    expect(adminScreen, contains('下一补丁'));
    expect(adminScreen, contains('下一小版本'));
    expect(adminScreen, contains('强制低于'));
    expect(adminScreen, contains("label: const Text('保存更新配置')"));
    expect(adminScreen, contains('Future<void> _saveUpdateConfig() async'));
    expect(adminScreen, contains('Future<void> _saveForceUpdateRequired'));
    expect(adminScreen, contains('_validateUpdatePolicy'));
    expect(adminScreen, isNot(contains('强制更新未生效')));
    expect(adminScreen, isNot(contains('hasRaisedMinimum')));
    expect(adminScreen, contains('当前版本也允许保存强制更新开关'));
    expect(adminScreen, contains('由后端发布通道'));
    expect(adminScreen, contains('客户端全屏阻断'));
    expect(adminScreen, contains('当前客户端版本 \${AppVersion.name}'));

    expect(updateService, contains("_backendUri("));
    expect(updateService, contains("'/api/mobile/apps/duoyi/update'"));
    expect(updateService, contains('_checkBackendMobileUpdate'));
    expect(updateService, contains('current_version_code'));
    expect(mainApp, contains('currentVersionCode: AppVersion.build'));
    expect(updateService, contains("data['release_notes']"));
    expect(updateService, contains("data['force_update']"));
    expect(updateService, contains("'/api/config'"));
    expect(updateService, contains("decoded['app_update']"));
    expect(updateService, contains('final hasNewerLatest'));
    expect(updateService, contains('final hasRaisedMinimum'));
    expect(updateService, contains('bool get forceUpdateRequired'));
    expect(updateService, contains('bool get mustUpdate'));
    expect(updateService, contains('final policyEnabled ='));
    expect(updateService, contains('_forceUpdateRequired = policyEnabled;'));
    expect(updateService, contains('formatUpdateNotesForDisplay'));
    expect(updatePolicy, contains('本次更新摘要'));
    expect(updatePolicy, contains('full changelog'));
    expect(updateService, contains('if (_checking) return;'));
    expect(updatePolicy, contains("split('+').first"));

    expect(mainApp, contains('void _checkUpdatePolicy({bool force = false})'));
    expect(mainApp, contains('_checkUpdatePolicy(force: true)'));
    expect(mainApp, contains("'startup app update policy'"));
    expect(mainApp, contains('() => appUpdate.checkServerPolicyNow()'));
    expect(
      mainApp,
      contains('Future<void> _runStartupIdleQueue('),
      reason: '启动后仍保留其它 idle 任务队列，但强更策略应首帧后立即检查。',
    );
    expect(mainApp, contains('initialDelay: const Duration(seconds: 75)'));
    expect(mainApp, contains('gap: const Duration(seconds: 12)'));
    expect(mainApp, contains('timeout: const Duration(seconds: 6)'));
    expect(
      mainApp,
      isNot(contains('Future<void>.delayed(const Duration(seconds: 6), ()')),
      reason: '启动更新策略检查不再使用独立定时器，避免和提醒、通知栏、小组件任务并发抢首屏。',
    );
    expect(mainApp, contains('home: updater.mustUpdate'));
    expect(
      mainApp,
      contains('? const Stack(children: [ForceUpdateGate()])'),
      reason: '强制更新首帧不能先构建 MainShell，再用弹层覆盖。',
    );
    expect(mainApp, contains('const ForceUpdateGate()'));
    expect(mainApp, contains("import 'widgets/force_update_gate.dart';"));
    expect(
      forceUpdateGate,
      contains('class ForceUpdateGate extends StatefulWidget'),
    );
    expect(
      forceUpdateGate,
      contains('final ScrollController _notesScrollController'),
    );
    expect(forceUpdateGate, contains('PopScope('));
    expect(forceUpdateGate, contains('canPop: false'));
    expect(forceUpdateGate, contains('AppUpdateInstaller.supportsInstall'));
    expect(forceUpdateGate, contains('需要更新后才能继续使用'));
    expect(forceUpdateGate, contains('BrandBackground('));
    expect(forceUpdateGate, contains('管理员已开启强制更新策略'));
    expect(forceUpdateGate, contains('管理员未配置下载地址'));
    expect(forceUpdateGate, contains('当前平台不支持应用内安装'));
    expect(forceUpdateGate, contains('downloadAndInstallLatest()'));
    expect(forceUpdateGate, contains('updater.hasDownloadedInstaller'));
    expect(
      mainApp,
      contains(
        'final showMineBadge = notification.hasUnreadHistory || updateHasUpdate',
      ),
    );
    expect(mainApp, contains('context.select<AppUpdateService, bool>'));
    expect(mainApp, contains('(updater) => updater.hasUpdate'));
    expect(
      mainApp,
      contains('class _BottomNavBadgeIcon extends StatelessWidget'),
    );
    expect(mainApp, contains('width: 8'));
    // 底导航文案已迁移到 BrandStrings（主题换文案对导航生效），
    // 见 test/core/brand_navigation_strings_test.dart 的静态锚点。
    expect(mainApp, contains('label: brand.navMine'));
    expect(forceUpdateGate, contains("'更新内容'"));
    expect(backend, contains('APP_CURRENT_VERSION'));
    expect(backend, contains('APP_UPDATE_DEFAULT_NOTES'));
    expect(backend, contains('def _update_release_defaults'));
    expect(backend, contains('def _has_effective_update_policy'));
    expect(backend, contains('def _coerce_update_settings'));
    expect(backend, isNot(contains('发布更新策略时必须填写更新内容')));
    expect(backend, contains('@app.get("/api/mobile/apps/{app_id}/update")'));
  });

  test('release builds refuse debug signing fallback', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final workflow = File('.github/workflows/build-apk.yml').readAsStringSync();

    expect(gradle, contains('Release signing is not configured'));
    expect(gradle, contains('GradleException'));
    expect(gradle, contains('DUOYI_KEYSTORE_* env vars'));
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    expect(workflow, contains('DUOYI_KEYSTORE_BASE64'));
    expect(workflow, contains('Restore release keystore'));
    expect(
      workflow,
      contains('base64 -d > android/app/keys/duoyi-release.jks'),
    );
    expect(workflow, contains('storeFile=keys/duoyi-release.jks'));
    expect(workflow, contains('android/key.properties'));
    expect(workflow, contains('Require release keystore'));
    expect(
      workflow,
      contains('refusing to build release artifacts with debug signing'),
    );
    expect(workflow, contains('exit 1'));
    expect(workflow, isNot(contains('APK will use debug signing')));
    final toolchain =
        jsonDecode(File('config/toolchain.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(toolchain['flutter'], '3.44.1');
    expect(workflow, contains('needs.configuration.outputs.flutter_version'));
    expect(workflow, isNot(contains("FLUTTER_VERSION: '3.41.9'")));
  });

  test(
    'registration email required toggle saves without global button flicker',
    () {
      final adminScreen = File(
        'lib/screens/admin_screen.dart',
      ).readAsStringSync();
      final settingsTab = adminScreen.substring(
        adminScreen.indexOf('class _SettingsTabState'),
        adminScreen.indexOf('// AI 配置'),
      );

      expect(settingsTab, isNot(contains('bool _saving = false')));
      expect(settingsTab, contains('final Set<String> _savingKeys'));
      expect(
        settingsTab,
        contains("onChanged: _saving('registration_email_required')"),
      );
      expect(
        settingsTab,
        contains("onChanged: _saving('registration_enabled')"),
      );
      expect(
        settingsTab,
        contains("onChanged: _saving('invite_code_required')"),
      );
    },
  );

  test('admin user list keeps paginated API for large data sets', () {
    final backend = File('backend/main.py').readAsStringSync();
    final adminApi = File('lib/services/admin_api.dart').readAsStringSync();

    expect(backend, contains('@app.get("/api/admin/users")'));
    expect(
      backend,
      contains('limit, offset = _admin_page_window(limit, offset)'),
    );
    expect(
      backend,
      contains('return _admin_page_response(items, total, limit, offset)'),
    );
    expect(adminApi, contains('Future<AdminPage> listUsersPage'));
    expect(adminApi, contains("'/api/admin/users'"));
    expect(adminApi, contains("final path = _path('/api/admin/settings'"));
    expect(
      adminApi,
      contains('Future<Map<String, dynamic>> getSystemSettings()'),
    );
    expect(
      adminApi,
      contains(
        "client.requestWithoutRouteDiagnosis(\n        'GET',\n        '/api/admin/system-settings',",
      ),
    );
    expect(
      adminApi,
      contains(
        "client.requestWithoutRouteDiagnosis(\n        'POST',\n        '/api/admin/system-settings',\n        settings,",
      ),
    );
    expect(adminApi, contains("featureName: '管理员系统设置'"));
    expect(adminApi, contains("featureName: '管理员更新设置'"));
    expect(
      adminApi,
      contains("const ['/api/admin/settings', '/api/admin/system-settings']"),
    );
  });
}
