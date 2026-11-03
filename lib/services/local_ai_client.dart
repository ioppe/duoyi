import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import 'local_ai_config_store.dart';

/// A stable message key, never a provider payload or credential-bearing error.
class LocalAiError implements Exception {
  final String messageKey;
  const LocalAiError(this.messageKey);
  @override
  String toString() => 'LocalAiError($messageKey)';
}

class LocalAiClient {
  final http.Client _client;
  final bool _ownsClient;

  LocalAiClient({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  static String normalizeBaseUrl(String value) {
    final raw = value.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !const ['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.host.contains(RegExp(r'\s')) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const LocalAiError('ai.local.error_url');
    }
    return uri
        .replace(path: uri.path.replaceAll(RegExp(r'/+$'), ''))
        .toString();
  }

  static Uri endpointFor(String baseUrl) {
    final normalized = normalizeBaseUrl(baseUrl);
    final uri = Uri.parse(normalized);
    if (uri.path.endsWith('/chat/completions')) return uri;
    return uri.replace(
      path:
          '${uri.path}${uri.path.endsWith('/v1') ? '' : '/v1'}/chat/completions',
    );
  }

  Future<String> chat({
    required LocalAiConfig config,
    required String system,
    required String user,
    required double temperature,
    required int maxTokens,
  }) async {
    final endpoint = endpointFor(config.baseUrl);
    if (config.model.trim().isEmpty) {
      throw const LocalAiError('ai.local.error_model');
    }
    try {
      final request = http.Request('POST', endpoint)
        ..followRedirects = false
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (config.hasApiKey) 'Authorization': 'Bearer ${config.apiKey}',
        })
        ..body = jsonEncode({
          'model': config.model,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
          ],
          'temperature': temperature,
          'max_tokens': maxTokens,
          'stream': false,
        });
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(AppConfig.aiTimeout);
      final code = response.statusCode;
      if (code == 401 || code == 403) {
        throw const LocalAiError('ai.local.error_auth');
      }
      if (code == 404 || (code >= 300 && code < 400)) {
        throw const LocalAiError('ai.local.error_endpoint');
      }
      if (code == 429) throw const LocalAiError('ai.local.error_rate');
      if (code >= 500) throw const LocalAiError('ai.local.error_server');
      if (code < 200 || code >= 300) {
        throw const LocalAiError('ai.local.error_response');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['choices'] is! List) {
        throw const LocalAiError('ai.local.error_response');
      }
      final choices = decoded['choices'] as List;
      if (choices.isEmpty || choices.first is! Map) {
        throw const LocalAiError('ai.local.error_empty');
      }
      final message = (choices.first as Map)['message'];
      if (message is! Map) throw const LocalAiError('ai.local.error_response');
      final raw = message['content'];
      String content;
      if (raw is String) {
        content = raw;
      } else if (raw is List) {
        content = raw
            .whereType<Map>()
            .where(
              (part) => part['type'] == 'text' || part['type'] == 'output_text',
            )
            .map((part) => part['text'] is String ? part['text'] as String : '')
            .join();
      } else {
        content = '';
      }
      content = content.replaceAll(
        RegExp(r'<think>.*?</think>', dotAll: true, caseSensitive: false),
        '',
      );
      final unclosed = content.toLowerCase().indexOf('<think>');
      if (unclosed >= 0) content = content.substring(0, unclosed);
      content = content.trim();
      if (content.isEmpty) throw const LocalAiError('ai.local.error_empty');
      return content;
    } on LocalAiError {
      rethrow;
    } on TimeoutException {
      throw const LocalAiError('ai.local.error_timeout');
    } on FormatException {
      throw const LocalAiError('ai.local.error_response');
    } catch (_) {
      throw const LocalAiError('ai.local.error_network');
    }
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
