import 'package:test/test.dart';

import 'package:duoyi/core/client_deployment_config.dart';

void main() {
  test(
    'configuration normalizes URLs and keeps independent timeout budgets',
    () {
      final config = ClientDeploymentConfig.fromValues({
        'DUOYI_SERVER_URL': ' https://todo.example/app/ ',
        'DUOYI_UPDATE_REPOSITORY': 'owner/fork',
        'DUOYI_WEB_TARGET': 'desktop',
        'DUOYI_HTTP_TIMEOUT_SECONDS': '15',
        'DUOYI_FILE_TIMEOUT_SECONDS': '40',
        'DUOYI_AI_TIMEOUT_SECONDS': '90',
        'DUOYI_UPDATE_TIMEOUT_SECONDS': '9',
      });
      expect(config.serverUrl, 'https://todo.example/app');
      expect(config.updateRepository, 'owner/fork');
      expect(config.webTarget, 'desktop');
      expect(config.httpTimeout, const Duration(seconds: 15));
      expect(config.fileTimeout, const Duration(seconds: 40));
      expect(config.aiTimeout, const Duration(seconds: 90));
      expect(config.updateTimeout, const Duration(seconds: 9));
    },
  );

  test('an explicit empty backend URL supports same-origin deployment', () {
    final config = ClientDeploymentConfig.fromValues({
      'DUOYI_SERVER_URL': '',
      'DUOYI_UPDATE_REPOSITORY': '',
    });
    expect(config.serverUrl, isEmpty);
    expect(config.updateRepository, isEmpty);
  });

  test('unconfigured builds keep a longer AI timeout and neutral defaults', () {
    final config = ClientDeploymentConfig();
    expect(config.serverUrl, isEmpty);
    expect(config.updateRepository, isEmpty);
    expect(config.webTarget, 'responsive');
    expect(config.httpTimeout, const Duration(seconds: 12));
    expect(config.fileTimeout, const Duration(seconds: 30));
    expect(config.aiTimeout, const Duration(seconds: 180));
    expect(config.updateTimeout, const Duration(seconds: 8));
    expect(
      ClientDeploymentConfig.fromValues({}).aiTimeout,
      const Duration(seconds: 180),
    );
  });

  test('invalid URLs fail without revealing credentials', () {
    for (final value in [
      '/relative',
      'ftp://example.com',
      'https://user:private-secret@example.com',
      'https://example.com?key=private-secret',
      'https://example.com#private-secret',
      'https://example.com:0',
    ]) {
      try {
        ClientDeploymentConfig(serverUrl: value);
        fail('Expected an invalid deployment URL to be rejected');
      } on ArgumentError catch (error) {
        expect(error.toString(), isNot(contains('private-secret')));
        expect(error.toString(), contains('DUOYI_SERVER_URL'));
      }
    }
  });

  test('timeout values require bounded positive integers', () {
    for (final value in ['', 'not-a-number', '1.5', '0', '-1', '3601']) {
      expect(
        () => ClientDeploymentConfig.fromValues({
          'DUOYI_HTTP_TIMEOUT_SECONDS': value,
        }),
        throwsArgumentError,
      );
    }
  });

  test('invalid repository and Web target are rejected', () {
    expect(
      () => ClientDeploymentConfig(updateRepository: 'https://github.com/a/b'),
      throwsArgumentError,
    );
    expect(
      () => ClientDeploymentConfig(updateRepository: '../fork'),
      throwsArgumentError,
    );
    expect(
      () => ClientDeploymentConfig(webTarget: 'unknown'),
      throwsArgumentError,
    );
  });
}
