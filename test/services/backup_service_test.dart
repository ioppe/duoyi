import 'dart:convert';

import 'package:duoyi/core/report_reminder_config.dart';
import 'package:duoyi/models/goal.dart' show ReminderKind;
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/quick_capture_template_provider.dart';
import 'package:duoyi/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('full backup round trip preserves historical records unchanged', () async {
    const records = <String>[
      '{"id":"legacy","date":"2026-05-01T00:00:00.000","content":"historical","mood":1,"tags":["keep"],"imagePaths":["private-image"]}',
    ];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('duoyi_diary', records);
    final raw = await BackupService.exportAll();
    final backup = jsonDecode(raw) as Map<String, dynamic>;
    expect(backup['data']['duoyi_diary']['value'], records);
    await prefs.remove('duoyi_diary');
    await BackupService.importAll(raw);
    expect(prefs.getStringList('duoyi_diary'), records);
  });

  test('exports local calendar events in full backups', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('duoyi_local_calendar_events_v1', <String>[
      '{"id":"event-1","title":"Imported event"}',
    ]);

    final raw = await BackupService.exportAll();
    final backup = json.decode(raw) as Map<String, dynamic>;
    final data = backup['data'] as Map<String, dynamic>;

    expect(data, contains('duoyi_local_calendar_events_v1'));
    expect(data['duoyi_local_calendar_events_v1'], <String, Object>{
      'type': 'stringList',
      'value': <String>['{"id":"event-1","title":"Imported event"}'],
    });
  });

  test('backup export and import keep countdown records', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('duoyi_countdowns', <String>[
      '{"id":"legacy-countdown","title":"Legacy"}',
    ]);
    await prefs.setStringList('duoyi_anniversaries_v2', <String>[
      '{"id":"normal-anniversary","title":"Normal","originDate":"2026-09-01T00:00:00.000","type":0}',
      '{"id":"birthday-anniversary","title":"Birthday","originDate":"2026-09-02T00:00:00.000","type":1}',
    ]);

    final raw = await BackupService.exportAll();
    final backup = json.decode(raw) as Map<String, dynamic>;
    final data = backup['data'] as Map<String, dynamic>;
    expect(data['duoyi_countdowns'], <String, Object>{
      'type': 'stringList',
      'value': <String>['{"id":"legacy-countdown","title":"Legacy"}'],
    });
    expect(data['duoyi_anniversaries_v2']['value'], <String>[
      '{"id":"normal-anniversary","title":"Normal","originDate":"2026-09-01T00:00:00.000","type":0}',
      '{"id":"birthday-anniversary","title":"Birthday","originDate":"2026-09-02T00:00:00.000","type":1}',
    ]);

    const incoming = '''
{
  "app": "duoyi",
  "schema": 1,
  "data": {
    "duoyi_countdowns": {
      "type": "stringList",
      "value": ["{\\"id\\":\\"imported-countdown\\",\\"title\\":\\"Blocked\\"}"]
    },
    "duoyi_anniversaries_v2": {
      "type": "stringList",
      "value": [
        "{\\"id\\":\\"imported-legacy\\",\\"title\\":\\"Legacy anniversary countdown\\",\\"originDate\\":\\"2026-09-03T00:00:00.000\\",\\"type\\":0}"
      ]
    }
  }
}
''';

    await prefs.remove('duoyi_countdowns');
    await prefs.remove('duoyi_anniversaries_v2');
    final count = await BackupService.importAll(incoming);
    expect(count, 2);
    expect(prefs.getStringList('duoyi_countdowns'), [
      '{"id":"imported-countdown","title":"Blocked"}',
    ]);
    expect(prefs.getStringList('duoyi_anniversaries_v2'), [
      '{"id":"imported-legacy","title":"Legacy anniversary countdown","originDate":"2026-09-03T00:00:00.000","type":0}',
    ]);
  });

  test('clearMissing rollback removes keys absent from the snapshot', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('todos', <String>['before']);
    final snapshot = await BackupService.exportAll();

    await prefs.setStringList('duoyi_notes', <String>['imported note']);
    await prefs.setStringList('duoyi_local_calendar_events_v1', <String>[
      'imported event',
    ]);

    await BackupService.importAll(snapshot, merge: false, clearMissing: true);

    expect(prefs.getStringList('todos'), <String>['before']);
    expect(prefs.getStringList('duoyi_notes'), isNull);
    expect(prefs.getStringList('duoyi_local_calendar_events_v1'), isNull);
  });

  test('normal overwrite keeps keys absent from the backup', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('todos', <String>['before']);
    final snapshot = await BackupService.exportAll();

    await prefs.setStringList('duoyi_notes', <String>['keep me']);

    await BackupService.importAll(snapshot, merge: false);

    expect(prefs.getStringList('todos'), <String>['before']);
    expect(prefs.getStringList('duoyi_notes'), <String>['keep me']);
  });

  test(
    'merge import replaces same-id records instead of duplicating them',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('todos', <String>[
        '{"id":"todo-1","title":"old","updatedAt":"2026-05-26T08:00:00Z"}',
        '{"id":"todo-2","title":"stay","updatedAt":"2026-05-26T09:00:00Z"}',
      ]);

      const incoming = '''
{
  "app": "duoyi",
  "schema": 1,
  "data": {
    "todos": {
      "type": "stringList",
      "value": [
        "{\\"id\\":\\"todo-1\\",\\"title\\":\\"new\\",\\"updatedAt\\":\\"2026-05-27T08:00:00Z\\"}",
        "{\\"id\\":\\"todo-3\\",\\"title\\":\\"add\\",\\"updatedAt\\":\\"2026-05-27T09:00:00Z\\"}"
      ]
    }
  }
}
''';

      await BackupService.importAll(incoming, merge: true);

      expect(prefs.getStringList('todos'), <String>[
        '{"id":"todo-1","title":"new","updatedAt":"2026-05-27T08:00:00Z"}',
        '{"id":"todo-2","title":"stay","updatedAt":"2026-05-26T09:00:00Z"}',
        '{"id":"todo-3","title":"add","updatedAt":"2026-05-27T09:00:00Z"}',
      ]);
    },
  );

  test(
    'merge import overwrites preference lists instead of unioning them',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('pref_daily_reminder_repeat_days', <String>[
        '1',
        '3',
        '5',
      ]);
      await prefs.setStringList('pref_bottom_nav_visible', <String>[
        '0',
        '1',
        '6',
      ]);
      await prefs.setStringList('todos', <String>[
        '{"id":"todo-1","title":"stay"}',
      ]);

      const incoming = '''
{
  "app": "duoyi",
  "schema": 1,
  "data": {
    "pref_daily_reminder_repeat_days": {"type": "stringList", "value": ["2", "4"]},
    "pref_bottom_nav_visible": {"type": "stringList", "value": ["0", "2", "3", "6"]},
    "todos": {"type": "stringList", "value": ["{\\"id\\":\\"todo-2\\",\\"title\\":\\"add\\"}"]}
  }
}
''';

      await BackupService.importAll(incoming, merge: true);

      // 偏好 stringList 整体覆盖（与云同步 LWW 口径一致），不做并集——
      // 否则他机备份的重复星期/隐藏导航项会只增不减地渗入本机设置。
      expect(prefs.getStringList('pref_daily_reminder_repeat_days'), <String>[
        '2',
        '4',
      ]);
      expect(prefs.getStringList('pref_bottom_nav_visible'), <String>[
        '0',
        '2',
        '3',
        '6',
      ]);
      // 业务数据列表仍按 id 去重并集。
      expect(prefs.getStringList('todos'), <String>[
        '{"id":"todo-1","title":"stay"}',
        '{"id":"todo-2","title":"add"}',
      ]);
    },
  );

  test('exports location reminders and quick capture templates', () async {
    final prefs = await SharedPreferences.getInstance();
    const locationRaw =
        '[{"id":"lr-1","title":"到家提醒","latitude":31.23,"longitude":121.47,"radiusMeters":200,"trigger":"enter"}]';
    const templateRaw =
        '[{"id":"tpl-1","name":"晨间冥想","kind":1,"habitTargetCount":10}]';
    await prefs.setString('duoyi_location_reminders_v1', locationRaw);
    await prefs.setString('duoyi_quick_capture_templates_v1', templateRaw);

    final raw = await BackupService.exportAll();
    final data =
        (json.decode(raw) as Map<String, dynamic>)['data']
            as Map<String, dynamic>;

    expect(data['duoyi_location_reminders_v1'], <String, Object>{
      'type': 'string',
      'value': locationRaw,
    });
    expect(data['duoyi_quick_capture_templates_v1'], <String, Object>{
      'type': 'string',
      'value': templateRaw,
    });
  });

  test(
    'restore makes location reminders and quick templates visible to providers',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'duoyi_location_reminders_v1',
        '[{"id":"lr-1","title":"到家提醒","latitude":31.23,"longitude":121.47,"radiusMeters":200,"trigger":"enter"}]',
      );
      await prefs.setString(
        'duoyi_quick_capture_templates_v1',
        '[{"id":"tpl-1","name":"晨间冥想","kind":1,"habitTargetCount":10}]',
      );
      // 模拟旧设备生成备份 JSON。
      final snapshot = await BackupService.exportAll();

      // 模拟新设备：本机存储为空后导入。
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final count = await BackupService.importAll(snapshot);
      expect(count, 2);

      // 与 backup_screen._reloadAll 相同的重载调用，恢复后无需重启即可见。
      final locationProvider = LocationReminderProvider();
      final templateProvider = QuickCaptureTemplateProvider();
      await Future.wait([
        locationProvider.loadFromStorage(),
        templateProvider.loadFromStorage(),
      ]);

      expect(locationProvider.isLoaded, isTrue);
      expect(locationProvider.reminders.length, 1);
      expect(locationProvider.reminders.first.title, '到家提醒');
      expect(locationProvider.reminders.first.radiusMeters, 200);
      expect(templateProvider.customTemplates.length, 1);
      expect(templateProvider.customTemplates.first.name, '晨间冥想');
      expect(templateProvider.customTemplates.first.habitTargetCount, 10);

      locationProvider.dispose();
      templateProvider.dispose();
    },
  );

  test('wipe removes location reminders and quick capture templates', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('duoyi_location_reminders_v1', '[]');
    await prefs.setString('duoyi_quick_capture_templates_v1', '[]');

    await BackupService.wipeAll();

    expect(prefs.getString('duoyi_location_reminders_v1'), isNull);
    expect(prefs.getString('duoyi_quick_capture_templates_v1'), isNull);
  });

  test(
    'preference round-trip: export, wipe, overwrite-import restores bool/int/stringList',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pref_haptic_feedback', false);
      await prefs.setBool('pref_show_lunar', false);
      await prefs.setInt('pref_default_pomodoro_minutes', 45);
      await prefs.setInt('pref_first_day_of_week', 7);
      await prefs.setInt('pref_daily_reminder_slot2_hour', 9);
      await prefs.setStringList('pref_daily_reminder_repeat_days', <String>[
        '2',
        '4',
        '6',
      ]);
      await prefs.setStringList('pref_bottom_nav_visible', <String>[
        '0',
        '1',
        '6',
      ]);
      await prefs.setString('pref_date_format', 'dd/MM/yyyy');

      final snapshot = await BackupService.exportAll();
      final data =
          (json.decode(snapshot) as Map<String, dynamic>)['data']
              as Map<String, dynamic>;

      // bool / int / double 之前会被 exportAll 静默丢弃，必须以类型化条目导出。
      expect(data['pref_haptic_feedback'], <String, Object>{
        'type': 'bool',
        'value': false,
      });
      expect(data['pref_default_pomodoro_minutes'], <String, Object>{
        'type': 'int',
        'value': 45,
      });
      expect(data['pref_daily_reminder_repeat_days'], <String, Object>{
        'type': 'stringList',
        'value': <String>['2', '4', '6'],
      });
      expect(data['pref_date_format'], <String, Object>{
        'type': 'string',
        'value': 'dd/MM/yyyy',
      });

      // 模拟换机：清空全部本地数据后偏好归零。
      await BackupService.wipeAll();
      expect(prefs.getBool('pref_haptic_feedback'), isNull);
      expect(prefs.getInt('pref_default_pomodoro_minutes'), isNull);
      expect(prefs.getStringList('pref_daily_reminder_repeat_days'), isNull);

      final count = await BackupService.importAll(snapshot);
      expect(count, 8);
      expect(prefs.getBool('pref_haptic_feedback'), isFalse);
      expect(prefs.getBool('pref_show_lunar'), isFalse);
      expect(prefs.getInt('pref_default_pomodoro_minutes'), 45);
      expect(prefs.getInt('pref_first_day_of_week'), 7);
      expect(prefs.getInt('pref_daily_reminder_slot2_hour'), 9);
      expect(prefs.getStringList('pref_daily_reminder_repeat_days'), <String>[
        '2',
        '4',
        '6',
      ]);
      expect(prefs.getStringList('pref_bottom_nav_visible'), <String>[
        '0',
        '1',
        '6',
      ]);
      expect(prefs.getString('pref_date_format'), 'dd/MM/yyyy');
    },
  );

  test(
    'device-specific timezone preferences are excluded from export and import',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pref_app_timezone_iana', 'America/New_York');
      await prefs.setString('pref_app_timezone_mode', 'fixed');

      final snapshot = await BackupService.exportAll();
      final data =
          (json.decode(snapshot) as Map<String, dynamic>)['data']
              as Map<String, dynamic>;
      expect(data.containsKey('pref_app_timezone_iana'), isFalse);
      expect(data.containsKey('pref_app_timezone_mode'), isFalse);

      // 备份文件手工携带时区键也不得写回本机（A 设备时区不能写死 B 设备）。
      const incoming = '''
{
  "app": "duoyi",
  "schema": 1,
  "data": {
    "pref_app_timezone_iana": {"type": "string", "value": "Europe/Paris"},
    "pref_app_timezone_mode": {"type": "string", "value": "fixed"},
    "pref_haptic_feedback": {"type": "bool", "value": false}
  }
}
''';
      final count = await BackupService.importAll(incoming);
      expect(count, 1);
      expect(prefs.getString('pref_app_timezone_iana'), 'America/New_York');
      expect(prefs.getString('pref_app_timezone_mode'), 'fixed');
      expect(prefs.getBool('pref_haptic_feedback'), isFalse);
    },
  );

  test(
    'legacy backup without preference keys imports and keeps local defaults',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pref_haptic_feedback', false);
      const legacy = '''
{
  "app": "duoyi",
  "schema": 1,
  "data": {
    "todos": {"type": "stringList", "value": ["{\\"id\\":\\"todo-1\\"}"]}
  }
}
''';

      final count = await BackupService.importAll(legacy);

      expect(count, 1);
      expect(prefs.getStringList('todos'), <String>['{"id":"todo-1"}']);
      // 旧备份缺新偏好键：既不清空本机偏好，也不写入默认值。
      expect(prefs.getBool('pref_haptic_feedback'), isFalse);
      expect(prefs.getInt('pref_default_pomodoro_minutes'), isNull);
    },
  );

  test('double-typed backup entries import via setDouble', () async {
    final prefs = await SharedPreferences.getInstance();
    // 借用白名单内的 int 偏好键验证 double 恢复分支（当前尚无 double 偏好键，
    // 该分支为前向防御；JSON 整数写法的 value 也要按 double 落盘）。
    const incoming = '''
{
  "app": "duoyi",
  "schema": 1,
  "data": {
    "pref_default_pomodoro_minutes": {"type": "double", "value": 1.5},
    "pref_first_day_of_week": {"type": "double", "value": 2}
  }
}
''';

    final count = await BackupService.importAll(incoming);

    expect(count, 2);
    expect(prefs.getDouble('pref_default_pomodoro_minutes'), 1.5);
    expect(prefs.getDouble('pref_first_day_of_week'), 2.0);
  });

  test(
    'preferences provider settings survive wipe and restore round-trip',
    () async {
      final writer = PreferencesProvider();
      await writer.loadFromStorage();
      await writer.setHaptic(false);
      await writer.setShowLunar(false);
      await writer.setDefaultPomodoroMinutes(50);
      await writer.setFirstDayOfWeek(7);
      await writer.setDailyReminderTime(7, 15);
      await writer.setDailyReminderSlot(
        1,
        const DailyReminderSlot(
          enabled: true,
          kind: ReminderKind.popup,
          hour: 9,
          minute: 30,
        ),
      );
      await writer.setDailyReportReminderConfig(
        const ReportReminderConfig(enabled: true, hour: 21, minute: 45),
      );

      final snapshot = await BackupService.exportAll();

      // 换机：清空后新设备读到默认值。
      await BackupService.wipeAll();
      final fresh = PreferencesProvider();
      await fresh.loadFromStorage();
      expect(fresh.haptic, isTrue);
      expect(fresh.dailyReminderHour, 20);
      expect(fresh.dailyReminderSlots[1].enabled, isFalse);

      // 同一进程内（备份页清空路径）：长驻 provider 不能继续持有旧偏好，
      // 须与备份页 _reloadAll 一致地先 resetLocalState 再 loadFromStorage。
      writer.resetLocalState();
      await writer.loadFromStorage();
      expect(writer.haptic, isTrue);
      expect(writer.dailyReminderHour, 20);
      expect(writer.dailyReminderSlots[1].enabled, isFalse);
      expect(writer.dailyReportReminderConfig.enabled, isFalse);

      // 恢复备份后偏好回到导出时的取值。
      await BackupService.importAll(snapshot);
      final restored = PreferencesProvider();
      await restored.loadFromStorage();
      expect(restored.haptic, isFalse);
      expect(restored.showLunar, isFalse);
      expect(restored.defaultPomodoroMinutes, 50);
      expect(restored.firstDayOfWeek, 7);
      expect(restored.dailyReminderHour, 7);
      expect(restored.dailyReminderMinute, 15);
      expect(restored.dailyReminderSlots[1].enabled, isTrue);
      expect(restored.dailyReminderSlots[1].hour, 9);
      expect(restored.dailyReminderSlots[1].minute, 30);
      expect(restored.dailyReminderSlots[1].kind, ReminderKind.popup);
      expect(restored.dailyReportReminderConfig.enabled, isTrue);
      expect(restored.dailyReportReminderConfig.hour, 21);
      expect(restored.dailyReportReminderConfig.minute, 45);

      // 同一进程内恢复路径：重载后长驻 provider 同步到恢复值。
      writer.resetLocalState();
      await writer.loadFromStorage();
      expect(writer.haptic, isFalse);
      expect(writer.showLunar, isFalse);
      expect(writer.defaultPomodoroMinutes, 50);
      expect(writer.firstDayOfWeek, 7);
      expect(writer.dailyReminderHour, 7);
      expect(writer.dailyReminderMinute, 15);
      expect(writer.dailyReminderSlots[1].enabled, isTrue);
      expect(writer.dailyReminderSlots[1].hour, 9);
      expect(writer.dailyReminderSlots[1].minute, 30);
      expect(writer.dailyReminderSlots[1].kind, ReminderKind.popup);
      expect(writer.dailyReportReminderConfig.enabled, isTrue);
      expect(writer.dailyReportReminderConfig.hour, 21);
      expect(writer.dailyReportReminderConfig.minute, 45);

      writer.dispose();
      fresh.dispose();
      restored.dispose();
    },
  );
}
