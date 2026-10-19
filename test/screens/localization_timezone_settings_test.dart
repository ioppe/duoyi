import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/screens/preferences_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    binding.platformDispatcher.localeTestValue = const Locale('en');
    AppClock.debugNow = () => DateTime.utc(2026, 6, 1, 2, 30);
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async =>
        'America/New_York';
  });
  tearDown(() {
    AppClock.debugNow = null;
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
    binding.platformDispatcher.clearLocaleTestValue();
    I18n.setLocale(AppLocale.zh);
  });

  testWidgets('personalization shows live language and application time zone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final locale = LocaleProvider();
    final preferences = PreferencesProvider();
    await locale.loadFromStorage();
    await preferences.loadFromStorage();
    addTearDown(locale.dispose);
    addTearDown(preferences.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleProvider>.value(value: locale),
          ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
        ],
        child: MaterialApp(
          theme: AppBrands.defaultBrand.theme,
          builder: (context, child) => AppClockScope(child: child!),
          home: const PersonalizationSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Display and behavior'), findsOneWidget);
    expect(find.byKey(const ValueKey('language-selection')), findsOneWidget);
    expect(find.textContaining('America/New_York'), findsOneWidget);
    expect(find.textContaining('May 31'), findsOneWidget);

    await tester.runAsync(() => preferences.setAppTimeZone('Asia/Shanghai'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Asia/Shanghai'), findsOneWidget);
    expect(find.textContaining('Jun 1'), findsOneWidget);
    await tester.runAsync(() => locale.setLocale(AppLocale.zh));
    await tester.pumpAndSettle();
    expect(find.text('显示与行为'), findsOneWidget);
    expect(find.text('界面语言'), findsOneWidget);
    expect(find.textContaining('2026年6月1日'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
