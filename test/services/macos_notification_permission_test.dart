import 'dart:io';

import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/services/local_notifications_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  var enabled = false;
  var queryFails = false;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    MacOSFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({});
    await LocalTimezoneResolver.setApplicationTimeZone('UTC');
    calls.clear();
    enabled = false;
    queryFails = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'initialize':
              return true;
            case 'getNotificationAppLaunchDetails':
              return {'notificationLaunchedApp': false};
            case 'checkPermissions':
              if (queryFails) throw PlatformException(code: 'unavailable');
              return {'isEnabled': enabled};
            case 'requestPermissions':
              return enabled;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('macOS notification authorization', () {
    test('refresh reads system permission without asking again', () async {
      final notifications = LocalNotifications.instance;
      expect(await notifications.refreshPermission(), isFalse);
      expect(notifications.permissionGranted, isFalse);
      enabled = true;
      calls.clear();
      expect(await notifications.refreshPermission(), isTrue);
      expect(calls.map((call) => call.method), contains('checkPermissions'));
      expect(
        calls.map((call) => call.method),
        isNot(contains('requestPermissions')),
      );
      enabled = false;
      expect(await notifications.refreshPermission(), isFalse);
    });

    test('explicit request reflects grant and denial', () async {
      final notifications = LocalNotifications.instance;
      enabled = true;
      expect(await notifications.requestPermission(), isTrue);
      final request = calls.lastWhere(
        (call) => call.method == 'requestPermissions',
      );
      expect(request.arguments, containsPair('alert', true));
      expect(request.arguments, containsPair('sound', true));
      enabled = false;
      expect(await notifications.requestPermission(), isFalse);
      expect(notifications.permissionGranted, isFalse);
    });

    test('failed query clears previously granted state', () async {
      final notifications = LocalNotifications.instance;
      enabled = true;
      expect(await notifications.refreshPermission(), isTrue);
      queryFails = true;
      expect(await notifications.refreshPermission(), isFalse);
      expect(notifications.permissionGranted, isFalse);
    });
  }, skip: !Platform.isMacOS);
}
