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

    test('底层${throwing ? '抛异常' : '返回false'}时载入仍读取已存的 100%，且不写迁移标记', () async {
      final store = _FailingStore(
        throwOnFailure: throwing,
        migrationDone: false,
      );
      SharedPreferencesStorePlatform.instance = store;
      final p = PreferencesProvider();
      store.failWrites = true;
      await p.loadFromStorage();
      final cached = await SharedPreferences.getInstance();
      expect(p.textScale, AppTextScale.standard);
      expect(cached.getDouble('pref_text_scale'), AppTextScale.standard);
      // 载入不再做默认档迁移：既不改写档位，也不写旧版完成标记。
      expect(cached.getBool('device_text_scale_default_migration_v2'), isNull);

      store.failWrites = false;
      await p.loadFromStorage();
      expect(p.textScale, AppTextScale.standard);
      expect(cached.getDouble('pref_text_scale'), AppTextScale.standard);
      expect(cached.getBool('device_text_scale_default_migration_v2'), isNull);

      SharedPreferences.resetStatic();
      final restarted = PreferencesProvider();
      await restarted.loadFromStorage();
      expect(restarted.textScale, AppTextScale.standard);
      p.dispose();
      restarted.dispose();
    });
  }
}
