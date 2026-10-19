import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppClock.debugNow = () => DateTime.utc(2026, 6, 1, 2, 30);
  });
  tearDown(() => AppClock.debugNow = null);

  test('one instant has the app day and clock in the selected zone', () async {
    await LocalTimezoneResolver.setApplicationTimeZone('America/New_York');
    expect(AppClock.now().hour, 22);
    expect(AppClock.today(), DateTime(2026, 5, 31));
    final epoch = AppClock.now().millisecondsSinceEpoch;
    await LocalTimezoneResolver.setApplicationTimeZone('Asia/Shanghai');
    expect(AppClock.now().hour, 10);
    expect(AppClock.today(), DateTime(2026, 6, 1));
    expect(AppClock.now().millisecondsSinceEpoch, epoch);
  });

  test(
    'floating dates retain their selected day; wall clocks preserve the zone',
    () async {
      final day = DateTime(2026, 6, 1);
      await LocalTimezoneResolver.setApplicationTimeZone('America/New_York');
      expect(AppClock.dateOnly(day), day);
      final occurrence = AppClock.date(day.year, day.month, day.day, 9, 15);
      expect(occurrence.toUtc(), DateTime.utc(2026, 6, 1, 13, 15));
      await LocalTimezoneResolver.setApplicationTimeZone('Asia/Shanghai');
      expect(AppClock.dateOnly(day), day);
      final newOccurrence = AppClock.date(day.year, day.month, day.day, 9, 15);
      expect(newOccurrence.toUtc(), DateTime.utc(2026, 6, 1, 1, 15));
    },
  );

  testWidgets('an already mounted view rebuilds on a timezone change', (
    tester,
  ) async {
    await LocalTimezoneResolver.setApplicationTimeZone('America/New_York');
    await tester.pumpWidget(
      AppClockScope(
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: _ClockLabel(),
        ),
      ),
    );
    expect(find.text('2026-5-31 22'), findsOneWidget);
    await tester.runAsync(
      () => LocalTimezoneResolver.setApplicationTimeZone('Asia/Shanghai'),
    );
    await tester.pump();
    expect(find.text('2026-6-1 10'), findsOneWidget);
  });
}

class _ClockLabel extends StatelessWidget {
  const _ClockLabel();
  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final value = AppClock.now();
    return Text('${value.year}-${value.month}-${value.day} ${value.hour}');
  }
}
