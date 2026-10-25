import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'Android calendar handoff pre-fills the task and does not request calendar access',
    () {
      final service = File(
        'lib/services/system_calendar_service.dart',
      ).readAsStringSync();
      final screen = File(
        'lib/screens/todo_detail_screen.dart',
      ).readAsStringSync();
      final mainActivity = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
      ).readAsStringSync();
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(service, contains("MethodChannel('duoyi/system_calendar')"));
      expect(service, contains("'title': title"));
      expect(service, contains("'startAtMillis'"));
      expect(service, contains("'endAtMillis'"));
      expect(service, contains("'allDay': allDay"));
      expect(screen, contains("'todo_add_to_system_calendar'"));
      expect(screen, contains('SystemCalendarService.openCreateEvent'));
      expect(screen, contains("I18n.tr('todo.system_calendar.add')"));
      expect(mainActivity, contains('CalendarContract.Events.CONTENT_URI'));
      expect(mainActivity, contains('Intent.ACTION_INSERT'));
      expect(mainActivity, contains('CalendarContract.Events.TITLE'));
      expect(mainActivity, contains('CalendarContract.EXTRA_EVENT_BEGIN_TIME'));
      expect(mainActivity, contains('CalendarContract.EXTRA_EVENT_END_TIME'));
      expect(manifest, isNot(contains('READ_CALENDAR')));
      expect(manifest, isNot(contains('WRITE_CALENDAR')));
    },
  );
}
