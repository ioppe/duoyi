import 'package:duoyi/core/app_text_scale.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore({required this.throwOnFailure, bool migrationDone = true})
    : super.withData({
        'flutter.pref_text_scale': 1.0,
        if (migrationDone)
          'flutter.device_text_scale_default_migration_v2': true,
      });

  final bool throwOnFailure;
  bool failWrites = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (failWrites && key == 'flutter.pref_text_scale') {
      if (throwOnFailure) {
        return Future<bool>.error(StateError('storage failed'));
      }
      return Future<bool>.value(false);
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalTimezoneResolver.debugSystemTimeZoneReader = () async => 'UTC';
  });
  tearDown(() {
    SharedPreferences.setMockInitialValues({});
    LocalTimezoneResolver.debugSystemTimeZoneReader = null;
  });

  for (final throwing in [false, true]) {
    test('底层${throwing ? '抛异常' : '返回false'}后重新载入不采用失败草稿，且队列可恢复', () async {
      final store = _FailingStore(throwOnFailure: throwing);
      SharedPreferencesStorePlatform.instance = store;
      final p = PreferencesProvider();
      await p.loadFromStorage();
      await p.bindTextScaleToAccount(
        serverUrl: 'https://duoyi.test',
        userId: 'a',
      );
      final owner = p.textScaleOwner;
      store.failWrites = true;
      await expectLater(p.setTextScale(1.9), throwsStateError);
      final cached = await SharedPreferences.getInstance();
      expect(cached.getDouble('pref_text_scale'), 1.0);
      expect(p.textScale, 1.0);
      await p.loadFromStorage();
      expect(p.textScale, 1.0);
      await expectLater(
        p.bindTextScaleToAccount(serverUrl: 'https://duoyi.test', userId: 'b'),
        throwsStateError,
      );
      await p.loadFromStorage();
      expect(p.textScaleOwner, owner);
      expect(p.textScale, 1.0);
      store.failWrites = false;
      await p.setTextScale(1.75);
      await p.loadFromStorage();
      expect(p.textScale, 1.75);
      expect(cached.getDouble('pref_text_scale'), 1.75);
      p.dispose();
    });

    test('字号默认迁移${throwing ? '抛异常' : '返回false'}时不标记完成，恢复后可重试', () async {
      final store = _FailingStore(
        throwOnFailure: throwing,
        migrationDone: false,
      );
      SharedPreferencesStorePlatform.instance = store;
      final p = PreferencesProvider();
      store.failWrites = true;
      await expectLater(p.loadFromStorage(), throwsStateError);
      final cached = await SharedPreferences.getInstance();
      // 迁移值写失败：磁盘与缓存都还是旧的 100%，也没有完成标记。
      expect(cached.getDouble('pref_text_scale'), 1.0);
      expect(cached.getBool('device_text_scale_default_migration_v2'), isNull);

      store.failWrites = false;
      await p.loadFromStorage();
      expect(p.textScale, AppTextScale.defaultScale);
      expect(cached.getDouble('pref_text_scale'), AppTextScale.defaultScale);
      expect(cached.getBool('device_text_scale_default_migration_v2'), isTrue);

      // 迁移真正落盘后，重启的 provider 读到的是默认真档而不是 100%。
      SharedPreferences.resetStatic();
      final restarted = PreferencesProvider();
      await restarted.loadFromStorage();
      expect(restarted.textScale, AppTextScale.defaultScale);
      p.dispose();
      restarted.dispose();
    });
  }
}
