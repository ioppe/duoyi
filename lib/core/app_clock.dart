import 'package:flutter/widgets.dart';
import 'package:timezone/timezone.dart' as tz;

import 'local_timezone_resolver.dart';

/// Calendar/wall-clock time in the selected application zone.
/// IDs, wire timestamps and elapsed-time measurements should use real instants.
class AppClock {
  AppClock._();
  static final ValueNotifier<int> _dayRevision = ValueNotifier(0);
  static final Listenable changes = Listenable.merge([
    LocalTimezoneResolver.timezoneListenable,
    _dayRevision,
  ]);
  static void notifyDayChanged() => _dayRevision.value++;

  @visibleForTesting
  static DateTime Function()? debugNow;

  static DateTime now() => toLocal(debugNow?.call() ?? DateTime.now());

  static DateTime toLocal(DateTime instant) =>
      LocalTimezoneResolver.isInitialized
      ? tz.TZDateTime.from(instant, tz.local)
      : instant.toLocal();

  /// A user-entered wall time, interpreted in the application time zone.
  static DateTime date(
    int year, [
    int month = 1,
    int day = 1,
    int hour = 0,
    int minute = 0,
    int second = 0,
    int millisecond = 0,
    int microsecond = 0,
  ]) => LocalTimezoneResolver.isInitialized
      ? tz.TZDateTime(
          tz.local,
          year,
          month,
          day,
          hour,
          minute,
          second,
          millisecond,
          microsecond,
        )
      : DateTime(
          year,
          month,
          day,
          hour,
          minute,
          second,
          millisecond,
          microsecond,
        );

  /// Floating calendar dates retain their stored year/month/day without shifting.
  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
  static DateTime today() => dateOnly(now());

  static void watch(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<AppClockScope>();
  }
}

/// Refreshes time-dependent views without replacing navigation or form state.
class AppClockScope extends InheritedNotifier<Listenable> {
  AppClockScope({super.key, required super.child})
    : super(notifier: AppClock.changes);
}
