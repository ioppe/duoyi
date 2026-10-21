import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/services/reminder_scheduler.dart';
import 'package:duoyi/services/reminder_sinks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Sink implements ReminderNotificationSink, ReminderAlarmSink {
  final scheduled = <DateTime>[];
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
  }) async {}
  @override
  Future<void> scheduleDailyFullScreen({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
    bool requireExactAlarm = true,
    bool fullScreen = true,
    bool vibrate = true,
    int snoozeMinutes = 0,
    int repeatCount = 0,
  }) async {}
  @override
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) async => scheduled.add(when);
  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    List<int>? weekdays,
    String? payload,
  }) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> cancelTodoReminder(String todoId) async {}
  @override
  Future<void> cancelHabitReminder(String habitId) async {}
  @override
  Future<void> cancelAnniversary(String annId) async {}
  @override
  Future<void> scheduleHabitReminder({
    required String habitId,
    required String habitName,
    required int hour,
    required int minute,
    List<int>? weekdays,
  }) async {}
  @override
  Future<void> scheduleAnniversary({
    required String annId,
    required String title,
    required DateTime whenDate,
    int daysBefore = 1,
    int hour = 9,
    int minute = 0,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => AppClock.debugNow = null);

  for (final item in [
    (
      zone: 'Asia/Shanghai',
      now: DateTime.utc(2026, 10, 21),
      at: DateTime.utc(2026, 10, 22, 16, 30),
    ),
    (
      zone: 'America/New_York',
      now: DateTime.utc(2026, 11, 1, 5, 45),
      at: DateTime.utc(2026, 11, 1, 6, 30),
    ),
  ]) {
    test(
      '${item.zone} reminder retains its instant after serialization and resync',
      () async {
        await LocalTimezoneResolver.setApplicationTimeZone(item.zone);
        AppClock.debugNow = () => item.now;
        final local = AppClock.toLocal(item.at);
        final plan = ReminderPlan(
          enabled: true,
          rules: [
            ReminderRule(
              id: 'at-time',
              type: ReminderRuleType.absolute,
              kind: ReminderKind.push,
              hour: local.hour,
              minute: local.minute,
            ),
          ],
        );
        final source = TodoItem(
          title: '提醒往返验收',
          date: local,
          dueDate: local,
          reminderPlan: plan,
          reminderAt: local,
        );
        final restored = TodoItem.fromJson(source.toJson());
        final preflight = preflightTodoReminderPlan(restored);
        expect(preflight.blockingIssue, isNull);
        expect(preflight.firstScheduledTime!.toUtc(), item.at);
        final sink = _Sink();
        final scheduler = ReminderScheduler(
          sink,
          registry: InMemoryReminderScheduleRegistry(),
          alarm: sink,
        );
        await scheduler.syncTodos([restored]);
        expect(sink.scheduled.single.toUtc(), item.at);
      },
    );
  }
}
