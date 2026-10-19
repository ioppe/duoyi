import 'dart:math';

import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/services/reminder_scheduler.dart';
import 'package:duoyi/services/reminder_sinks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

// Observe actual sink arguments, with the OS kept in UTC and the application
// deliberately in a different zone. Reconstructing wall time in the assertion
// would hide the original bug: TZDateTime.from only preserves an instant.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final instant = DateTime.utc(2026, 1, 1, 2, 15, 40);
  const zones = [
    'Asia/Shanghai',
    'America/New_York',
    'Europe/London',
    'Australia/Sydney',
    'Pacific/Honolulu',
    'Asia/Tokyo',
    'America/Los_Angeles',
    'UTC',
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppClock.debugNow = () => instant;
  });
  tearDown(() => AppClock.debugNow = null);

  TodoItem todoAt(DateTime date, int hour, int minute) => TodoItem(
    title: 'wall time',
    dueDate: date,
    reminder: ReminderConfig(
      enabled: true,
      kind: ReminderKind.alarm,
      hour: hour,
      minute: minute,
    ),
  );

  test(
    '50 occurrences preserve actual epoch, application zone and H:M',
    () async {
      final rng = Random(42);
      for (var iteration = 0; iteration < 50; iteration++) {
        final zone = zones[rng.nextInt(zones.length)];
        await LocalTimezoneResolver.setApplicationTimeZone(zone);
        final hour = rng.nextInt(24);
        final minute = rng.nextInt(60);
        final alarm = _Alarm();
        final scheduler = ReminderScheduler(_Notifications(), alarm: alarm);
        final todo = todoAt(DateTime(2026, 1, 3), hour, minute);
        await scheduler.syncTodos([todo]);
        final actual = alarm.once.single;
        final expected = tz.TZDateTime(
          tz.getLocation(zone),
          2026,
          1,
          3,
          hour,
          minute,
        );
        expect(actual, isA<tz.TZDateTime>());
        expect((actual as tz.TZDateTime).location.name, zone);
        expect(actual.millisecondsSinceEpoch, expected.millisecondsSinceEpoch);
        // Exercise exactly the conversion used by the downstream alarm service.
        final delivered = tz.TZDateTime.from(actual, tz.local);
        expect(delivered.hour, hour);
        expect(delivered.minute, minute);
        expect(delivered.day, 3);
      }
    },
  );

  test('50 resyncs change actual epoch while preserving user H:M', () async {
    final rng = Random(43);
    for (var iteration = 0; iteration < 50; iteration++) {
      final hour = rng.nextInt(24);
      final minute = rng.nextInt(60);
      final alarm = _Alarm();
      final scheduler = ReminderScheduler(_Notifications(), alarm: alarm);
      final todo = todoAt(DateTime(2026, 1, 3), hour, minute);
      await LocalTimezoneResolver.setApplicationTimeZone('America/New_York');
      await scheduler.syncTodos([todo]);
      final before = alarm.once.single;
      await LocalTimezoneResolver.setApplicationTimeZone('Asia/Shanghai');
      await scheduler.resyncAll(
        todos: [todo],
        habits: [],
        annis: [],
        goals: [],
      );
      final after = alarm.once.last;
      expect(alarm.once.length, 2);
      expect(alarm.cancelled, isNotEmpty);
      expect((before as tz.TZDateTime).location.name, 'America/New_York');
      expect((after as tz.TZDateTime).location.name, 'Asia/Shanghai');
      expect(before.difference(after), const Duration(hours: 13));
      expect(after.hour, hour);
      expect(after.minute, minute);
    }
  });

  test(
    'preflight and formal same-minute grace use the same real instant',
    () async {
      for (final zone in ['America/New_York', 'Asia/Shanghai']) {
        await LocalTimezoneResolver.setApplicationTimeZone(zone);
        final now = AppClock.now();
        final todo = todoAt(AppClock.today(), now.hour, now.minute);
        final preflight = preflightTodoReminderPlan(todo, now: instant);
        final alarm = _Alarm();
        final scheduler = ReminderScheduler(_Notifications(), alarm: alarm);
        await scheduler.syncTodos([todo]);
        expect(preflight.ok, isTrue);
        expect(
          preflight.firstScheduledTime!.toUtc(),
          DateTime.utc(2026, 1, 1, 2, 16),
        );
        expect(
          alarm.once.single.isAtSameMomentAs(preflight.firstScheduledTime!),
          isTrue,
        );
        expect((alarm.once.single as tz.TZDateTime).location.name, zone);
        await scheduler.resyncAll(
          todos: [todo],
          habits: [],
          annis: [],
          goals: [],
        );
        expect(
          alarm.once.length,
          1,
          reason: 'resync must never replay a past one-shot',
        );
        final stale = todoAt(AppClock.today(), now.hour, now.minute - 1);
        expect(preflightTodoReminderPlan(stale, now: instant).ok, isFalse);
      }
    },
  );

  test(
    'countdown days-before keeps H:M across spring and autumn DST',
    () async {
      await LocalTimezoneResolver.setApplicationTimeZone('America/New_York');
      for (final target in [DateTime(2026, 3, 9), DateTime(2026, 11, 2)]) {
        final notifications = _Notifications();
        final scheduler = ReminderScheduler(notifications, alarm: _Alarm());
        await scheduler.syncCountdowns([
          CountdownItem(
            id: 'dst',
            title: 'DST countdown',
            targetDate: target,
            remind: true,
            reminderKind: ReminderKind.push,
            remindDaysBefore: 1,
            remindHour: 9,
            remindMinute: 20,
          ),
        ]);
        final actual = notifications.once.single;
        final expected = tz.TZDateTime(
          tz.local,
          target.year,
          target.month,
          target.day - 1,
          9,
          20,
        );
        expect(actual.millisecondsSinceEpoch, expected.millisecondsSinceEpoch);
        expect(actual.hour, 9);
        expect(actual.minute, 20);
      }
    },
  );
}

class _Notifications extends Fake implements ReminderNotificationSink {
  final once = <DateTime>[];
  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async => once.add(when);
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> cancelTodoReminder(String todoId) async {}
  @override
  Future<void> cancelHabitReminder(String habitId) async {}
  @override
  Future<void> cancelAnniversary(String annId) async {}
}

class _Alarm extends Fake implements ReminderAlarmSink {
  final once = <DateTime>[];
  final cancelled = <int>[];
  @override
  Future<void> scheduleFullScreen({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    bool requireExactAlarm = true,
    bool fullScreen = true,
    bool vibrate = true,
    int snoozeMinutes = 0,
    int repeatCount = 0,
  }) async => once.add(when);
  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}
