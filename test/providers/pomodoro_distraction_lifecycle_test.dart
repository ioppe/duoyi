import 'dart:async';
import 'dart:convert';

import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('duoyi/focus_distraction');
  const timerChannel = MethodChannel('duoyi/focus_timer');
  const distractingPackage = 'com.example.distraction';

  for (final action in ['pause', 'reset']) {
    testWidgets(
      'a late foreground response cannot re-enable blocking after $action',
      (tester) async {
        expect(defaultTargetPlatform, TargetPlatform.android);
        SharedPreferences.setMockInitialValues({
          'pomodoro_config': json.encode(
            PomodoroConfig(
              strictFocusMode: true,
              monitorDistractingApps: true,
              distractingAppPackages: [distractingPackage],
            ).toJson(),
          ),
        });
        final configurations = <bool>[];
        final delayed = Completer<Map<String, Object?>>();
        var holdStatus = false;
        var heldRequests = 0;
        Map<String, Object?> status({bool distracting = false}) => {
          'supported': true,
          'accessGranted': true,
          'accessibilityGranted': true,
          'accessibilityActive': true,
          'blockerConfigured': true,
          'foregroundPackage': distracting
              ? distractingPackage
              : 'com.duoyi.duoyi',
        };
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getStatus':
              if (holdStatus) {
                heldRequests++;
                return delayed.future;
              }
              return status();
            case 'setFocusBlocker':
              configurations.add((call.arguments as Map)['enabled'] == true);
              return true;
            case 'getAppLabel':
              return 'Example distraction';
            case 'getInstalledApps':
              return [
                {
                  'packageName': distractingPackage,
                  'label': 'Example distraction',
                },
              ];
          }
          return null;
        });
        messenger.setMockMethodCallHandler(timerChannel, (_) async => null);
        addTearDown(() {
          messenger.setMockMethodCallHandler(channel, null);
          messenger.setMockMethodCallHandler(timerChannel, null);
        });
        final provider = PomodoroProvider();
        addTearDown(provider.dispose);
        await provider.loadFromStorage();
        provider.startIfIdle();
        for (var i = 0; i < 5; i++) {
          await tester.pump();
        }
        expect(provider.state.isRunning, isTrue);
        expect(configurations, contains(true));

        holdStatus = true;
        await tester.pump(const Duration(seconds: 20));
        expect(heldRequests, greaterThan(0));
        if (action == 'pause') {
          provider.toggleTimer();
        } else {
          provider.resetTimer();
        }
        await tester.pump();
        expect(provider.state.isRunning, isFalse);
        expect(configurations.last, isFalse);
        final afterStop = configurations.length;

        delayed.complete(status(distracting: true));
        for (var i = 0; i < 5; i++) {
          await tester.pump();
        }
        expect(configurations.skip(afterStop), isNot(contains(true)));
        expect(configurations.last, isFalse);
        expect(
          provider.penalties.where(
            (p) => p.reason == FocusPenaltyReason.distractingApp,
          ),
          isEmpty,
        );
      },
    );
  }
}
