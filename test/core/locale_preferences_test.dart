import 'dart:ui';

import 'package:duoyi/core/i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    binding.platformDispatcher.localeTestValue = const Locale('en', 'US');
  });
  tearDown(() {
    binding.platformDispatcher.clearLocaleTestValue();
    I18n.setLocale(AppLocale.zh);
  });

  test(
    'unset language follows system without persisting an override',
    () async {
      final provider = LocaleProvider();
      addTearDown(provider.dispose);
      await provider.loadFromStorage();
      expect(provider.selection, 'system');
      expect(provider.locale, AppLocale.en);
      expect(
        (await SharedPreferences.getInstance()).getString('duoyi_locale_v1'),
        isNull,
      );
      provider.didChangeLocales(const [Locale('zh', 'CN')]);
      expect(provider.locale, AppLocale.zh);
      expect(I18n.tr('settings.language'), '界面语言');
    },
  );

  test(
    'choosing the effective system language still saves an explicit override',
    () async {
      final provider = LocaleProvider();
      addTearDown(provider.dispose);
      await provider.loadFromStorage();
      await provider.setLocale(AppLocale.en);
      expect(provider.followsSystem, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getString('duoyi_locale_v1'),
        'en',
      );
      provider.didChangeLocales(const [Locale('zh')]);
      expect(provider.locale, AppLocale.en);
      final restored = LocaleProvider();
      addTearDown(restored.dispose);
      await restored.loadFromStorage();
      expect(restored.selection, 'en');
      expect(restored.locale, AppLocale.en);
    },
  );

  test(
    'returning to system removes the manual language behavior and survives reload',
    () async {
      final provider = LocaleProvider();
      addTearDown(provider.dispose);
      await provider.loadFromStorage();
      await provider.setLocale(AppLocale.zh);
      await provider.followSystem();
      expect(provider.selection, 'system');
      expect(provider.locale, AppLocale.en);
      expect(
        (await SharedPreferences.getInstance()).getString('duoyi_locale_v1'),
        'system',
      );
      binding.platformDispatcher.localeTestValue = const Locale('zh');
      provider.didChangeLocales(const [Locale('zh')]);
      expect(provider.locale, AppLocale.zh);
      final restored = LocaleProvider();
      addTearDown(restored.dispose);
      await restored.loadFromStorage();
      expect(restored.followsSystem, isTrue);
      expect(restored.locale, AppLocale.zh);
    },
  );
}
