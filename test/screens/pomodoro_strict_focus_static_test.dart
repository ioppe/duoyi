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

    expect(screen, contains('_StrictFocusTile'));
    expect(screen, contains('_PenaltyListTile'));
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
    expect(screen, contains('开启辅助功能后'));

    expect(backup, contains("'pomodoro_focus_penalties'"));
    expect(sync, contains("'pomodoro_focus_penalties': 'focus_penalties'"));
  });
}
