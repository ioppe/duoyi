import 'package:duoyi/core/pomodoro_floating_window_size.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('尺寸枚举使用稳定的存储值并容错解析', () {
    expect(PomodoroFloatingWindowSize.large.storageValue, 'large');
    expect(PomodoroFloatingWindowSize.compact.storageValue, 'compact');
    expect(
      PomodoroFloatingWindowSize.defaultSize,
      PomodoroFloatingWindowSize.large,
    );

    expect(
      PomodoroFloatingWindowSize.parse(null),
      PomodoroFloatingWindowSize.large,
    );
    expect(
      PomodoroFloatingWindowSize.parse(''),
      PomodoroFloatingWindowSize.large,
    );
    expect(
      PomodoroFloatingWindowSize.parse('  '),
      PomodoroFloatingWindowSize.large,
    );
    expect(
      PomodoroFloatingWindowSize.parse('gigantic'),
      PomodoroFloatingWindowSize.large,
    );
    expect(
      PomodoroFloatingWindowSize.parse('compact'),
      PomodoroFloatingWindowSize.compact,
    );
    expect(
      PomodoroFloatingWindowSize.parse(' Compact '),
      PomodoroFloatingWindowSize.compact,
    );
  });

  test('默认 large，设置后持久化并可重载', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = PreferencesProvider();
    await preferences.loadFromStorage();
    expect(
      preferences.pomodoroFloatingWindowSize,
      PomodoroFloatingWindowSize.large,
      reason: '未配置时沿用现有大卡片',
    );

    var notifications = 0;
    final syncedKeys = <String>[];
    preferences.addListener(() => notifications++);
    preferences.onChangedKeys = (keys) => syncedKeys.addAll(keys);

    await preferences.setPomodoroFloatingWindowSize(
      PomodoroFloatingWindowSize.compact,
    );
    expect(
      preferences.pomodoroFloatingWindowSize,
      PomodoroFloatingWindowSize.compact,
    );
    expect(notifications, 1);
    expect(syncedKeys, isEmpty, reason: '设备本地外观偏好不能标记为云同步改动');

    final reloaded = PreferencesProvider();
    await reloaded.loadFromStorage();
    expect(
      reloaded.pomodoroFloatingWindowSize,
      PomodoroFloatingWindowSize.compact,
    );

    preferences.dispose();
    reloaded.dispose();
  });

  test('清除账号本地状态后内存回退 large', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = PreferencesProvider();
    await preferences.setPomodoroFloatingWindowSize(
      PomodoroFloatingWindowSize.compact,
    );
    expect(
      preferences.pomodoroFloatingWindowSize,
      PomodoroFloatingWindowSize.compact,
    );

    preferences.resetLocalState();
    expect(
      preferences.pomodoroFloatingWindowSize,
      PomodoroFloatingWindowSize.large,
    );
    preferences.dispose();
  });

  test('存储中的未知尺寸按 large 载入', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pref_pomodoro_floating_window_size': 'gigantic',
    });
    final preferences = PreferencesProvider();
    await preferences.loadFromStorage();
    expect(
      preferences.pomodoroFloatingWindowSize,
      PomodoroFloatingWindowSize.large,
    );
    preferences.dispose();
  });
}
