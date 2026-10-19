import 'package:flutter/foundation.dart';

import 'app_config.dart';

/// Runtime connection defaults and canonical server identities.
class ServerConnection {
  ServerConnection._();

  static String defaultBaseUrl({bool isWeb = kIsWeb, String? configuredUrl}) =>
      isWeb ? '' : (configuredUrl ?? AppConfig.bakedServerUrl);

  static String normalize(String value) {
    final text = value.trim();
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        RegExp(r'\s').hasMatch(text) ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535))) {
      throw const FormatException('Invalid server URL');
    }
    var path = uri.normalizePath().path.replaceFirst(RegExp(r'/+$'), '');
    if (path.split('/').last == 'api') {
      path = path.substring(0, path.length - 4);
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host.toLowerCase(),
      port: uri.hasPort ? uri.port : null,
      path: path,
    ).toString();
  }

  static String identity(String baseUrl, {bool isWeb = kIsWeb}) {
    if (baseUrl.isNotEmpty) return normalize(baseUrl);
    return isWeb && Uri.base.hasAuthority ? Uri.base.origin : '';
  }
}
