import 'client_deployment_config.dart';

/// Public, immutable build configuration. Deployments live in
/// config/deployment.json and are injected with --dart-define-from-file.
/// The server URL is an initial installed-client value; Web uses its current origin.
/// AuthProvider owns the active runtime connection.
class AppConfig {
  static const String defaultServerUrl = '';
  static const String buildTimeServerUrl = String.fromEnvironment(
    'DUOYI_SERVER_URL',
    defaultValue: defaultServerUrl,
  );
  static const String webTarget = String.fromEnvironment(
    'DUOYI_WEB_TARGET',
    defaultValue: 'responsive',
  );
  static const String _updateRepository = String.fromEnvironment(
    'DUOYI_UPDATE_REPOSITORY',
  );
  static const String _httpTimeout = String.fromEnvironment(
    'DUOYI_HTTP_TIMEOUT_SECONDS',
    defaultValue: '12',
  );
  static const String _fileTimeout = String.fromEnvironment(
    'DUOYI_FILE_TIMEOUT_SECONDS',
    defaultValue: '30',
  );
  static const String _aiTimeout = String.fromEnvironment(
    'DUOYI_AI_TIMEOUT_SECONDS',
    defaultValue: '75',
  );
  static const String _updateTimeout = String.fromEnvironment(
    'DUOYI_UPDATE_TIMEOUT_SECONDS',
    defaultValue: '8',
  );

  static final ClientDeploymentConfig configuration =
      ClientDeploymentConfig.fromValues({
        'DUOYI_SERVER_URL': buildTimeServerUrl,
        'DUOYI_UPDATE_REPOSITORY': _updateRepository,
        'DUOYI_WEB_TARGET': webTarget,
        'DUOYI_HTTP_TIMEOUT_SECONDS': _httpTimeout,
        'DUOYI_FILE_TIMEOUT_SECONDS': _fileTimeout,
        'DUOYI_AI_TIMEOUT_SECONDS': _aiTimeout,
        'DUOYI_UPDATE_TIMEOUT_SECONDS': _updateTimeout,
      });

  static String get bakedServerUrl => configuration.serverUrl;
  static String get updateRepository => configuration.updateRepository;
  static Duration get httpTimeout => configuration.httpTimeout;
  static Duration get fileTimeout => configuration.fileTimeout;
  static Duration get aiTimeout => configuration.aiTimeout;
  static Duration get updateTimeout => configuration.updateTimeout;

  /// Accessing the immutable value validates all compile-time configuration.
  static ClientDeploymentConfig validate() => configuration;
}
