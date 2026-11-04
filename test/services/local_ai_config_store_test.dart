import 'dart:convert';
import 'dart:io';

import 'package:duoyi/services/local_ai_config_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// `flutter_secure_storage` 9.2.4 的原生通道；这里用内存后端记录真实入参。
const MethodChannel _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// 设备 AI 配置若落到 SharedPreferences 就失去了安全存储边界。
const MethodChannel _sharedPreferencesChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

/// 与 `lib/services/local_ai_config_store.dart` 使用同一个编译期开关。
///
/// 默认 `flutter test` 期望 Data Protection Keychain（true）；
/// `flutter test --dart-define=DUOYI_MACOS_USE_DATA_PROTECTION_KEYCHAIN=false`
/// 期望 classic login keychain（false）。预期值来自构建输入而不是字面量，
/// 因此写死开关或忽略开关的实现会在其中一次运行里失败。
const bool _expectedDataProtectionKeychain = bool.fromEnvironment(
  'DUOYI_MACOS_USE_DATA_PROTECTION_KEYCHAIN',
  defaultValue: true,
);

class _MethodChannelBackend {
  final Map<String, String> values = <String, String>{};
  final List<MethodCall> calls = <MethodCall>[];
  int sharedPreferencesCalls = 0;
  Object? failure;

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secureStorageChannel, (call) async {
      calls.add(call);
      if (failure != null) throw failure!;
      final arguments = (call.arguments as Map).cast<String, Object?>();
      final key = arguments['key'] as String?;
      switch (call.method) {
        case 'write':
          values[key!] = arguments['value']! as String;
          return null;
        case 'read':
          return values[key];
        case 'delete':
          values.remove(key);
          return null;
        case 'containsKey':
          return values.containsKey(key);
        case 'readAll':
          return Map<String, String>.of(values);
        case 'deleteAll':
          values.clear();
          return null;
        default:
          throw PlatformException(
            code: 'unexpected_method',
            message: call.method,
          );
      }
    });
    messenger.setMockMethodCallHandler(_sharedPreferencesChannel, (call) async {
      sharedPreferencesCalls += 1;
      throw StateError('SharedPreferences 不得保存设备 AI 密钥: ${call.method}');
    });
  }

  void uninstall() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secureStorageChannel, null);
    messenger.setMockMethodCallHandler(_sharedPreferencesChannel, null);
  }

  Map<String, String> lastOptions(String method) {
    final call = calls.lastWhere((entry) => entry.method == method);
    return ((call.arguments as Map)['options'] as Map).cast<String, String>();
  }

  Object? lastKey() {
    final call = calls.lastWhere((entry) => entry.method == 'write');
    return (call.arguments as Map)['key'];
  }
}

const LocalAiConfig _dummyConfig = LocalAiConfig(
  enabled: true,
  baseUrl: 'https://dummy.invalid/v1',
  model: 'dummy-model',
  apiKey: 'dummy-secret-value',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MethodChannelBackend backend;

  setUp(() {
    // 插件按 dart:io 平台选择选项，这个 override 让依赖 defaultTargetPlatform
    // 的代码路径保持在 macOS；通道选项断言只在 macOS 主机上执行。
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    backend = _MethodChannelBackend()..install();
  });

  tearDown(() {
    backend.uninstall();
    debugDefaultTargetPlatformOverride = null;
  });

  test('macOS 通道 serialized 选项跟随编译期 keychain 模式 '
      '(dataProtection=$_expectedDataProtectionKeychain)', () async {
    final store = SecureLocalAiConfigStore();
    await store.write(_dummyConfig);
    await store.read();
    await store.clear();

    final writeOptions = backend.lastOptions('write');
    expect(
      writeOptions['useDataProtectionKeyChain'],
      '$_expectedDataProtectionKeychain',
      reason: 'macOS 必须使用编译期选定的 keychain 实现',
    );
    expect(writeOptions['accountName'], AppleOptions.defaultAccountName);
    expect(writeOptions['accessibility'], 'unlocked');
    expect(writeOptions['synchronizable'], 'false');
    expect(
      writeOptions.containsKey('encryptedSharedPreferences'),
      isFalse,
      reason: 'macOS 通道不得混入 Android 参数',
    );
    expect(
      writeOptions.containsKey('groupId'),
      isFalse,
      reason: 'ad-hoc 发行构建不得携带受限 keychain access group',
    );
    expect(backend.lastKey(), SecureLocalAiConfigStore.storageKey);
    expect(backend.sharedPreferencesCalls, 0);
    expect(backend.values, isEmpty);
  }, skip: Platform.isMacOS ? null : 'macOS 通道选项只能在 macOS 主机上验证');

  test('默认插件配置保留 Android encryptedSharedPreferences 与账户名', () {
    final store = SecureLocalAiConfigStore();
    final android = store.storage.aOptions.toMap();
    expect(
      android['encryptedSharedPreferences'],
      'true',
      reason: 'Android 安全存储参数必须保持不变',
    );
    expect(android['resetOnError'], 'false');

    final macos = store.storage.mOptions.toMap();
    expect(
      macos['useDataProtectionKeyChain'],
      '$_expectedDataProtectionKeychain',
      reason: '默认签名构建必须继续使用原来的 Data Protection Keychain 路径',
    );
    expect(macos['accountName'], AppleOptions.defaultAccountName);
    expect(macos.containsKey('groupId'), isFalse);
  });

  test('dummy 配置跨 store 实例持久化，clear 只删除安全存储 key', () async {
    final first = SecureLocalAiConfigStore();
    await first.write(_dummyConfig);
    expect(backend.values.keys, <String>[SecureLocalAiConfigStore.storageKey]);

    final second = SecureLocalAiConfigStore();
    final restored = await second.read();
    expect(restored.enabled, isTrue);
    expect(restored.baseUrl, _dummyConfig.baseUrl);
    expect(restored.model, _dummyConfig.model);
    expect(restored.apiKey, _dummyConfig.apiKey);

    await second.clear();
    final cleared = await first.read();
    expect(cleared.enabled, isFalse);
    expect(cleared.baseUrl, isEmpty);
    expect(cleared.model, isEmpty);
    expect(cleared.apiKey, isEmpty);
    expect(backend.values, isEmpty);
    expect(backend.sharedPreferencesCalls, 0);
  });

  test('API key 不进入 toString 或 SharedPreferences', () async {
    final store = SecureLocalAiConfigStore();
    await store.write(_dummyConfig);

    expect(_dummyConfig.toString(), isNot(contains(_dummyConfig.apiKey)));
    expect(_dummyConfig.toString(), contains('keyConfigured: true'));
    expect(
      jsonEncode(_dummyConfig.toJson()),
      contains(_dummyConfig.apiKey),
      reason: '密钥只能作为安全存储载荷存在',
    );
    expect(backend.values.values.single, contains(_dummyConfig.apiKey));
    expect(backend.sharedPreferencesCalls, 0);
  });

  test('keychain 错误原样传播，损坏的载荷抛 FormatException', () async {
    final store = SecureLocalAiConfigStore();
    backend.failure = PlatformException(
      code: '-34018',
      message: 'errSecMissingEntitlement',
    );
    await expectLater(
      store.read(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          '-34018',
        ),
      ),
    );
    await expectLater(
      store.write(_dummyConfig),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          '-34018',
        ),
      ),
    );

    backend.failure = null;
    backend.values[SecureLocalAiConfigStore.storageKey] = 'not-json';
    await expectLater(store.read(), throwsA(isA<FormatException>()));

    backend.values[SecureLocalAiConfigStore.storageKey] = '[1, 2, 3]';
    await expectLater(store.read(), throwsA(isA<FormatException>()));
  });
}
