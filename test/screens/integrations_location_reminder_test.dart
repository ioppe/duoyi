import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/screens/integrations_screen.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Finder actionText(String zh, String en) => find.byWidgetPredicate(
    (widget) => widget is Text && (widget.data == zh || widget.data == en),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'integrations screen standalone route renders without provider black screen',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: IntegrationsScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(IntegrationsScreen), findsOneWidget);
      expect(find.text('扩展功能'), findsOneWidget);

      await tester.tap(find.text('位置提醒'));
      await tester.pumpAndSettle();
      expect(find.text('输入当前位置测试'), findsOneWidget);

      await tester.tap(find.text('语言'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'location reminder tab can create and manually trigger reminder',
    (tester) async {
      final locationProvider = LocationReminderProvider();
      final notificationService = NotificationService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocationReminderProvider>.value(
              value: locationProvider,
            ),
            ChangeNotifierProvider<NotificationService>.value(
              value: notificationService,
            ),
            ChangeNotifierProvider(create: (_) => CalendarSyncProvider()),
          ],
          child: const MaterialApp(home: IntegrationsScreen()),
        ),
      );

      await tester.tap(find.text('位置提醒'));
      await tester.pumpAndSettle();
      expect(find.text('输入当前位置测试'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.byType(AppModalSheet), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, '标题'), '到办公室');
      await tester.enterText(find.widgetWithText(TextField, '纬度'), '39.9042');
      await tester.enterText(find.widgetWithText(TextField, '经度'), '116.4074');
      await tester.enterText(find.widgetWithText(TextField, '半径（米）'), '500');
      await tester.ensureVisible(actionText('保存', 'Save').first);
      await tester.pumpAndSettle();
      await tester.tap(actionText('保存', 'Save').first);
      await tester.pumpAndSettle();

      expect(locationProvider.reminders, hasLength(1));
      expect(find.text('到办公室'), findsOneWidget);

      await tester.tap(find.text('输入当前位置测试'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '纬度'), '39.9042');
      await tester.enterText(find.widgetWithText(TextField, '经度'), '116.4074');
      await tester.tap(find.text('测试'));
      await tester.pumpAndSettle();

      expect(find.text('已触发 1 条位置提醒'), findsOneWidget);
      expect(notificationService.history, hasLength(1));
      expect(
        notificationService.history.single.type,
        NotificationType.location,
      );
      expect(notificationService.history.single.title, '位置提醒：到办公室');
    },
  );
}
