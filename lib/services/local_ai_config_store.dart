import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// macOS keychain backend selection, fixed at compile time.
///
/// Developer builds signed with a real Apple team keep the Data Protection
/// Keychain (the default `true`). The ad-hoc release build in CI has no team
/// identifier and no `keychain-access-groups`, so macOS rejects Data Protection
/// keychain writes with `errSecMissingEntitlement (-34018)`; that workflow
/// passes `--dart-define=DUOYI_MACOS_USE_DATA_PROTECTION_KEYCHAIN=false` and
/// uses the classic login keychain instead. Only that explicitly flagged build
/// changes where the value lives; no migration or deletion is attempted.
const bool macOsUseDataProtectionKeychain = bool.fromEnvironment(
  'DUOYI_MACOS_USE_DATA_PROTECTION_KEYCHAIN',
  defaultValue: true,
);

/// Device configuration; intentionally absent from preferences and backups.
class LocalAiConfig {
  final bool enabled;
  final String baseUrl;
  final String model;
  final String apiKey;

  const LocalAiConfig({
    this.enabled = false,
    this.baseUrl = '',
    this.model = '',
    this.apiKey = '',
  });

  bool get hasApiKey => apiKey.isNotEmpty;

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'baseUrl': baseUrl,
    'model': model,
    'apiKey': apiKey,
  };

  factory LocalAiConfig.fromJson(Map<String, dynamic> json) => LocalAiConfig(
    enabled: json['enabled'] == true,
    baseUrl: json['baseUrl'] is String ? json['baseUrl'] as String : '',
    model: json['model'] is String ? json['model'] as String : '',
    apiKey: json['apiKey'] is String ? json['apiKey'] as String : '',
  );

  @override
  String toString() =>
      'LocalAiConfig(enabled: $enabled, keyConfigured: $hasApiKey)';
}

abstract class LocalAiConfigStore {
  Future<LocalAiConfig> read();
  Future<void> write(LocalAiConfig config);
  Future<void> clear();
}

class SecureLocalAiConfigStore implements LocalAiConfigStore {
  static const storageKey = 'duoyi_local_ai_config_v1';
  final FlutterSecureStorage _storage;

  SecureLocalAiConfigStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            mOptions: MacOsOptions(
              useDataProtectionKeyChain: macOsUseDataProtectionKeychain,
            ),
          );

  /// Effective plugin configuration, exposed so tests can assert the compiled
  /// keychain mode without touching a real keychain.
  @visibleForTesting
  FlutterSecureStorage get storage => _storage;

  @override
  Future<LocalAiConfig> read() async {
    final raw = await _storage.read(key: storageKey);
    if (raw == null || raw.isEmpty) return const LocalAiConfig();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid local AI configuration');
    }
    return LocalAiConfig.fromJson(decoded);
  }

  @override
  Future<void> write(LocalAiConfig config) =>
      _storage.write(key: storageKey, value: jsonEncode(config.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: storageKey);
}
