import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/platform_info.dart';

/// Opens the platform calendar's create-event screen with prefilled data.
///
/// The system calendar owns the new event after the user taps Save; Duoyi does
/// not store an event id or try to update/delete it later.
class SystemCalendarService {
  SystemCalendarService._();

  static const MethodChannel _channel = MethodChannel('duoyi/system_calendar');

  static Future<bool> openCreateEvent({
    required String title,
    required String description,
    required DateTime start,
    required DateTime end,
    required bool allDay,
    required String timeZone,
  }) async {
    if (kIsWeb || !PlatformInfo.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('createEvent', {
            'title': title,
            'description': description,
            'startAtMillis': allDay
                ? DateTime.utc(
                    start.year,
                    start.month,
                    start.day,
                  ).millisecondsSinceEpoch
                : start.toUtc().millisecondsSinceEpoch,
            'endAtMillis': allDay
                ? DateTime.utc(
                    end.year,
                    end.month,
                    end.day,
                  ).millisecondsSinceEpoch
                : end.toUtc().millisecondsSinceEpoch,
            'allDay': allDay,
            'timeZone': timeZone,
          }) ??
          false;
    } catch (error, stackTrace) {
      debugPrint(
        '[SystemCalendarService] open create event failed: $error\n$stackTrace',
      );
      return false;
    }
  }
}
