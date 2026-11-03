import 'dart:async';

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

  test(
    'explicit selection persists before the sync callback and reports the key',
    () async {
      final provider = LocaleProvider();
      addTearDown(provider.dispose);
      await provider.loadFromStorage();

      final calls = <List<String>>[];
      String? storedAtCallback;
      provider.onChangedKeys = (keys) async {
        final prefs = await SharedPreferences.getInstance();
        storedAtCallback = prefs.getString('duoyi_locale_v1');
        calls.add(keys.toList());
      };

      await provider.setLocale(AppLocale.zh);

      expect(calls, [
        <String>['duoyi_locale_v1'],
      ]);
      // 回调可 await：setLocale 完成时选择已落盘，同步层不会拿到未落盘的值。
      expect(storedAtCallback, 'zh');
      expect(provider.selection, 'zh');
      expect(provider.locale, AppLocale.zh);
    },
  );

  test(
    'loading and system language changes never mark the language dirty',
    () async {
      final provider = LocaleProvider();
      addTearDown(provider.dispose);
      var callbackCount = 0;
      provider.onChangedKeys = (keys) async {
        callbackCount += 1;
      };

      await provider.loadFromStorage();
      provider.didChangeLocales(const [Locale('zh', 'CN')]);
      expect(provider.locale, AppLocale.zh);
      expect(callbackCount, 0);

      // 已有显式选择时，系统语言变化同样不算本地改动。
      await provider.setLocale(AppLocale.zh);
      callbackCount = 0;
      provider.didChangeLocales(const [Locale('en')]);
      expect(provider.locale, AppLocale.zh);
      expect(callbackCount, 0);
    },
  );

  test(
    'explicitly choosing system without a stored value still syncs',
    () async {
      final provider = LocaleProvider();
      addTearDown(provider.dispose);
      await provider.loadFromStorage();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('duoyi_locale_v1'), isFalse);

      final calls = <List<String>>[];
      provider.onChangedKeys = (keys) async {
        calls.add(keys.toList());
      };

      await provider.followSystem();

      expect(provider.selection, 'system');
      expect(prefs.getString('duoyi_locale_v1'), 'system');
      expect(calls, [
        <String>['duoyi_locale_v1'],
      ]);
    },
  );

  test(
    'rapid consecutive selections keep the newest choice and notify for it',
    () async {
      final provider = LocaleProvider();
      addTearDown(provider.dispose);
      await provider.loadFromStorage();

      final notifiedKeys = <String>[];
      provider.onChangedKeys = (keys) async {
        notifiedKeys.addAll(keys);
      };

      // 两次选择都不 await，模拟用户快速连点语言项。
      final first = provider.setLocale(AppLocale.zh);
      final second = provider.setLocale(AppLocale.en);
      await Future.wait<void>([first, second]);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('duoyi_locale_v1'), 'en');
      expect(provider.selection, 'en');
      expect(provider.locale, AppLocale.en);
      expect(notifiedKeys, isNotEmpty);
      expect(notifiedKeys.toSet(), <String>{'duoyi_locale_v1'});

      final restored = LocaleProvider();
      addTearDown(restored.dispose);
      await restored.loadFromStorage();
      expect(restored.selection, 'en');
    },
  );

  test(
    'a storage reload racing with a selection keeps the user choice',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'duoyi_locale_v1': 'en',
      });
      final provider = LocaleProvider();
      addTearDown(provider.dispose);
      await provider.loadFromStorage();
      expect(provider.locale, AppLocale.en);

      // 模拟云同步回写触发的 reload 与用户选择并发：reload 先发起，
      // 用户选择在其 await 期间完成，最终必须以用户的选择为准。
      final reload = provider.loadFromStorage();
      final selection = provider.setLocale(AppLocale.zh);
      await Future.wait<void>([reload, selection]);

      expect(provider.selection, 'zh');
      expect(provider.locale, AppLocale.zh);
      expect(
        (await SharedPreferences.getInstance()).getString('duoyi_locale_v1'),
        'zh',
      );
    },
  );

  test('reload waits for a selection that was queued first', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'duoyi_locale_v1': 'en',
    });
    final provider = LocaleProvider();
    addTearDown(provider.dispose);
    await provider.loadFromStorage();

    final selection = provider.setLocale(AppLocale.zh);
    final reload = provider.loadFromStorage();
    await Future.wait<void>([selection, reload]);

    expect(provider.selection, 'zh');
    expect(provider.locale, AppLocale.zh);
    expect(
      (await SharedPreferences.getInstance()).getString('duoyi_locale_v1'),
      'zh',
    );
  });

  test(
    'cloud selection notifies even when the effective language is unchanged',
    () async {
      final provider = LocaleProvider();
      addTearDown(provider.dispose);
      await provider.loadFromStorage();
      expect(provider.followsSystem, isTrue);
      expect(provider.locale, AppLocale.en);
      var notifications = 0;
      provider.addListener(() => notifications++);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('duoyi_locale_v1', 'en');

      await provider.loadFromStorage();

      expect(provider.selection, 'en');
      expect(provider.locale, AppLocale.en);
      expect(notifications, 1);
    },
  );

  test('selection waits for sync metadata before completing', () async {
    final provider = LocaleProvider();
    addTearDown(provider.dispose);
    await provider.loadFromStorage();
    final callbackStarted = Completer<void>();
    final releaseCallback = Completer<void>();
    provider.onChangedKeys = (_) async {
      callbackStarted.complete();
      await releaseCallback.future;
    };
    var completed = false;
    final selection = provider.setLocale(AppLocale.zh).then((_) {
      completed = true;
    });
    await callbackStarted.future;
    expect(completed, isFalse);

    releaseCallback.complete();
    await selection;
    expect(completed, isTrue);
  });
}
