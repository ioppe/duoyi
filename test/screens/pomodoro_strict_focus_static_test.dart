import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Pomodoro strict focus mode records interruption penalties', () {
    final model = File('lib/models/pomodoro.dart').readAsStringSync();
    final provider = File(
      'lib/providers/pomodoro_provider.dart',
    ).readAsStringSync();
    final screen = File('lib/screens/pomodoro_screen.dart').readAsStringSync();
    final backup = File('lib/services/backup_service.dart').readAsStringSync();
    final sync = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();

    expect(model, contains('bool strictFocusMode'));
    expect(model, contains('enum FocusPenaltyReason'));
    expect(model, contains('class PomodoroFocusPenalty'));
    expect(model, contains("'reasonLabel': reason.label"));

    expect(provider, contains('pomodoro_focus_penalties'));
    expect(provider, contains('setStrictFocusMode'));
    expect(provider, contains('recordFocusLeaveAppPenalty'));
    expect(provider, contains('_recordStrictFocusPenalty'));
    expect(provider, contains('FocusPenaltyReason.pause'));
    expect(provider, contains('FocusPenaltyReason.skip'));
    expect(provider, contains('FocusPenaltyReason.reset'));
    expect(provider, contains('FocusPenaltyReason.leaveApp'));
    expect(provider, contains('FocusPenaltyReason.distractingApp'));
    expect(provider, contains('FocusDistractionService.instance'));
    expect(provider, contains('setMonitorDistractingApps'));
    expect(provider, contains('setDistractingAppPackages'));
    expect(provider, contains('_syncDistractionMonitorToState'));
    expect(provider, contains('_checkDistractingForegroundApp'));
    expect(provider, contains('todayPenalties'));
    expect(provider, contains('_consumeNativeBlockEvent'));
    expect(provider, contains('FocusNativeBlockEvent.fromStatus'));
    expect(provider, contains('FocusBlockerLease.expiresAtMs'));
    expect(provider, contains('_resolveAppLabel'));
    expect(provider, contains('refreshFocusDistractionStatus();'));

    expect(screen, contains('_StrictFocusTile'));
    expect(screen, contains('_PenaltyListTile'));
    expect(screen, contains('_distractionStatusText'));
    expect(screen, contains('focus.distraction.status.accessibility_active'));
    expect(screen, contains('displayAppLabel'));
    expect(screen, contains('displayAppPackage'));
    expect(
      screen,
      isNot(contains('await provider.refreshFocusDistractionStatus();')),
    );
    expect(screen, contains('_confirmStrictFocusExit'));
    expect(screen, contains('_showStrictFocusSheet'));
    expect(screen, contains('严格专注'));
    expect(screen, contains('确认记录'));
    expect(screen, contains('监控分心应用'));
    expect(screen, contains('AppSettingsTile('));
    expect(screen, contains('_showDistractingAppPicker'));
    expect(screen, contains('FocusDistractionAppPicker'));
    expect(screen, contains('focus.distraction.tile.title'));
    expect(screen, isNot(contains('分心应用包名')));
    expect(screen, isNot(contains('packageCtrl')));
    expect(screen, contains('使用情况权限'));
    expect(screen, contains('辅助功能拦截'));
    expect(screen, contains("I18n.tr('focus.distraction.permission_hint')"));
    final i18n = File('lib/core/i18n.dart').readAsStringSync();
    expect(
      RegExp(r"'focus\.distraction\.permission_hint':").allMatches(i18n),
      hasLength(2),
      reason: '严格专注权限提示必须保留中英文映射',
    );
    for (final entry in <String, List<String>>{
      'zh': ['已连接的辅助功能服务', '后台弹出界面', '使用情况访问', '不发送辅助功能窗口事件'],
      'en': [
        'accessibility service to be enabled and connected',
        'Display pop-up windows while running in the background',
        'usage access is also needed',
        'cannot replace the accessibility service',
      ],
    }.entries) {
      final arb =
          jsonDecode(File('lib/l10n/app_${entry.key}.arb').readAsStringSync())
              as Map<String, dynamic>;
      final hint = arb['focusDistractionPermissionHint'];
      final generated = File(
        'lib/l10n/generated/app_localizations_${entry.key}.dart',
      ).readAsStringSync();
      expect(generated, contains('String get focusDistractionPermissionHint'));
      for (final prerequisite in entry.value) {
        expect(
          hint,
          contains(prerequisite),
          reason: '${entry.key} 权限说明不能遗漏系统许可或补漏条件',
        );
        expect(generated, contains(prerequisite));
      }
    }

    expect(backup, contains("'pomodoro_focus_penalties'"));
    expect(sync, contains("'pomodoro_focus_penalties': 'focus_penalties'"));
  });
}
