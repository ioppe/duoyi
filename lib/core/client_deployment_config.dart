/// Immutable client deployment values. Contains public configuration only.
class ClientDeploymentConfig {
  final String serverUrl;
  final String updateRepository;
  final String webTarget;
  final Duration httpTimeout;
  final Duration fileTimeout;
  final Duration aiTimeout;
  final Duration updateTimeout;

  ClientDeploymentConfig({
    String serverUrl = '',
    String updateRepository = '',
    String webTarget = 'responsive',
    int httpTimeoutSeconds = 12,
    int fileTimeoutSeconds = 30,
    int aiTimeoutSeconds = 180,
    int updateTimeoutSeconds = 8,
  }) : serverUrl = _serverUrl(serverUrl),
       updateRepository = _repository(updateRepository),
       webTarget = _target(webTarget),
       httpTimeout = _timeout('DUOYI_HTTP_TIMEOUT_SECONDS', httpTimeoutSeconds),
       fileTimeout = _timeout('DUOYI_FILE_TIMEOUT_SECONDS', fileTimeoutSeconds),
       aiTimeout = _timeout('DUOYI_AI_TIMEOUT_SECONDS', aiTimeoutSeconds),
       updateTimeout = _timeout(
         'DUOYI_UPDATE_TIMEOUT_SECONDS',
         updateTimeoutSeconds,
       );

  factory ClientDeploymentConfig.fromValues(Map<String, String> values) {
    return ClientDeploymentConfig(
      serverUrl: values['DUOYI_SERVER_URL'] ?? '',
      updateRepository: values['DUOYI_UPDATE_REPOSITORY'] ?? '',
      webTarget: values['DUOYI_WEB_TARGET'] ?? 'responsive',
      httpTimeoutSeconds: _seconds(values, 'DUOYI_HTTP_TIMEOUT_SECONDS', 12),
      fileTimeoutSeconds: _seconds(values, 'DUOYI_FILE_TIMEOUT_SECONDS', 30),
      aiTimeoutSeconds: _seconds(values, 'DUOYI_AI_TIMEOUT_SECONDS', 180),
      updateTimeoutSeconds: _seconds(values, 'DUOYI_UPDATE_TIMEOUT_SECONDS', 8),
    );
  }

  static int _seconds(Map<String, String> values, String key, int fallback) {
    final raw = values[key]?.trim();
    if (raw == null) return fallback;
    if (!RegExp(r'^[0-9]+$').hasMatch(raw)) {
      throw ArgumentError('$key must be an integer between 1 and 3600');
    }
    final number = int.tryParse(raw);
    if (number == null || number < 1 || number > 3600) {
      throw ArgumentError('$key must be an integer between 1 and 3600');
    }
    return number;
  }

  static Duration _timeout(String key, int seconds) {
    if (seconds < 1 || seconds > 3600) {
      throw ArgumentError('$key must be an integer between 1 and 3600');
    }
    return Duration(seconds: seconds);
  }

  static String _serverUrl(String value) {
    final text = value.trim();
    if (text.isEmpty) return '';
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        RegExp(r'\s').hasMatch(text) ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535))) {
      throw ArgumentError(
        'DUOYI_SERVER_URL must be an HTTP(S) URL without credentials, '
        'query, or fragment',
      );
    }
    return text.replaceFirst(RegExp(r'/+$'), '');
  }

  static String _repository(String value) {
    final text = value.trim();
    if (text.isEmpty) return '';
    if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(text) ||
        text.split('/').any((part) => part == '.' || part == '..')) {
      throw ArgumentError('DUOYI_UPDATE_REPOSITORY must use owner/repository');
    }
    return text;
  }

  static String _target(String value) {
    final text = value.trim();
    if (!{'responsive', 'desktop', 'mobile'}.contains(text)) {
      throw ArgumentError(
        'DUOYI_WEB_TARGET must be responsive, desktop, or mobile',
      );
    }
    return text;
  }
}
