import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
          );

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
