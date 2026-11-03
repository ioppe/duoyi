import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/web_target.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/local_ai_client.dart';
import 'package:duoyi/services/local_ai_config_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryStore implements LocalAiConfigStore {
  LocalAiConfig value = const LocalAiConfig();
  Completer<LocalAiConfig>? pendingRead;
  int writes = 0;
  @override
  Future<LocalAiConfig> read() async =>
      pendingRead == null ? value : pendingRead!.future;
  @override
  Future<void> write(LocalAiConfig config) async {
    value = config;
    writes++;
  }

  @override
  Future<void> clear() async {
    value = const LocalAiConfig();
    writes++;
  }
}

http.Response reply(Object content) => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'choices': [
        {
          'message': {'content': content},
        },
      ],
    }),
  ),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WebTarget.debugWebBuild = false;
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => WebTarget.debugWebBuild = null);

  test(
    'local AI persists independently and requests never use the Duoyi proxy token',
    () async {
      final store = MemoryStore();
      var localRequests = 0;
      final ai = AiService(
        localConfigStore: store,
        localHttpClient: MockClient((request) async {
          localRequests++;
          expect(
            request.url.toString(),
            'https://models.example/v1/chat/completions',
          );
          expect(request.headers['authorization'], 'Bearer user-model-key');
          expect(request.headers.toString(), isNot(contains('duoyi-session')));
          final body = jsonDecode(request.body) as Map;
          expect(body['model'], 'my-model');
          expect(body['stream'], isFalse);
          expect(body['messages'], hasLength(2));
          return reply('第一步\n第二步');
        }),
      );
      ai.attachClient(
        ApiClient(
          token: 'duoyi-session',
          httpClient: MockClient(
            (_) async => fail('Local AI must not call the backend'),
          ),
        ),
      );
      ai.setRemoteAccountActive(false);
      await ai.saveLocalConfiguration(
        enabled: true,
        baseUrl: 'https://models.example/v1/',
        model: 'my-model',
        apiKey: 'user-model-key',
      );
      ai.updateFromServerConfig({
        'ai_enabled': false,
        'ai_model': 'server-model',
      });
      expect(ai.enabled, isTrue);
      expect(await ai.breakDownTask('整理资料'), ['第一步', '第二步']);
      expect(localRequests, 1);
      final restarted = AiService(localConfigStore: store);
      restarted.setRemoteAccountActive(false);
      await restarted.loadFromStorage();
      expect(restarted.enabled, isTrue);
      expect(restarted.model, 'my-model');
      expect(restarted.localConfig.hasApiKey, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().any((key) => key.contains('local_ai')), isFalse);
      ai.dispose();
      restarted.dispose();
    },
  );

  test(
    'remote policy owns signed-in requests and local settings resume after sign-out',
    () async {
      final store = MemoryStore()
        ..value = const LocalAiConfig(
          enabled: true,
          baseUrl: 'https://local.example',
          model: 'local',
          apiKey: 'local-secret',
        );
      final ai = AiService(
        localConfigStore: store,
        localHttpClient: MockClient(
          (_) async => fail('Signed-in AI must not call local service'),
        ),
      );
      ai.setRemoteAccountActive(false);
      await ai.loadLocalConfiguration();
      ai.attachClient(
        ApiClient(
          baseUrl: 'https://backend.example',
          token: 'remote-token',
          httpClient: MockClient((request) async {
            expect(request.url.path, '/api/ai/chat');
            expect(request.headers['authorization'], 'Bearer remote-token');
            expect(request.body, isNot(contains('local-secret')));
            return http.Response(
              jsonEncode({'content': '远程结果'}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
      ai.setRemoteAccountActive(true);
      ai.updateFromServerConfig({'ai_enabled': false});
      expect(ai.enabled, isFalse);
      await expectLater(ai.breakDownTask('任务'), throwsA(isA<AiException>()));
      await expectLater(
        ai.saveLocalConfiguration(
          enabled: true,
          baseUrl: 'https://other.example',
          model: 'x',
        ),
        throwsA(isA<AiException>()),
      );
      ai.updateFromServerConfig({
        'ai_enabled': true,
        'ai_model': 'server-model',
      });
      expect(await ai.breakDownTask('任务'), ['远程结果']);
      ai.setRemoteAccountActive(false);
      expect(ai.model, 'local');
      expect(ai.enabled, isTrue);
      expect(ai.localConfig.apiKey, 'local-secret');
      ai.dispose();
    },
  );

  test(
    'endpoint normalization supports root, v1 and complete endpoint and refuses URL credentials',
    () {
      for (final url in [
        'https://models.example',
        'https://models.example/v1/',
        'https://models.example/v1/chat/completions',
      ]) {
        expect(
          LocalAiClient.endpointFor(url).toString(),
          'https://models.example/v1/chat/completions',
        );
      }
      for (final url in [
        'ftp://models.example',
        'https://user:secret@models.example',
        'https://models.example?key=secret',
        'https://models.example/#key',
      ]) {
        expect(
          () => LocalAiClient.endpointFor(url),
          throwsA(isA<LocalAiError>()),
        );
      }
    },
  );

  test(
    'testing a draft does not save it; changing hosts requires a replacement key',
    () async {
      final store = MemoryStore()
        ..value = const LocalAiConfig(
          enabled: true,
          baseUrl: 'https://models.example/v1',
          model: 'saved-model',
          apiKey: 'saved-key',
        );
      final ai = AiService(
        localConfigStore: store,
        localHttpClient: MockClient((request) async {
          expect(request.followRedirects, isFalse);
          expect(request.headers['authorization'], 'Bearer saved-key');
          expect(jsonDecode(request.body)['model'], 'draft-model');
          return reply('ok');
        }),
      );
      ai.setRemoteAccountActive(false);
      await ai.loadLocalConfiguration();
      expect(
        await ai.testLocalConfiguration(
          baseUrl: 'https://models.example',
          model: 'draft-model',
        ),
        'ok',
      );
      expect(store.writes, 0);
      expect(ai.model, 'saved-model');
      expect(ai.reviewHistory, isEmpty);
      await expectLater(
        ai.saveLocalConfiguration(
          enabled: true,
          baseUrl: 'https://different.example',
          model: 'new',
        ),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            I18n.tr('ai.local.key_new_host'),
          ),
        ),
      );
      await ai.saveLocalConfiguration(
        enabled: true,
        baseUrl: 'https://different.example',
        model: 'new',
        apiKey: 'replacement',
      );
      expect(store.value.apiKey, 'replacement');
      await ai.clearLocalConfiguration();
      expect(ai.enabled, isFalse);
      expect(store.value.hasApiKey, isFalse);
      ai.dispose();
    },
  );

  test(
    'keyless self-hosted models work and error payloads never expose credentials',
    () async {
      var status = 200;
      var content = 'ok';
      final ai = AiService(
        localConfigStore: MemoryStore(),
        localHttpClient: MockClient((request) async {
          expect(request.headers.containsKey('authorization'), isFalse);
          return status == 200
              ? reply(content)
              : http.Response(
                  'echoed-secret',
                  status,
                  headers: {'location': 'https://redirect.example'},
                );
        }),
      );
      ai.setRemoteAccountActive(false);
      await ai.saveLocalConfiguration(
        enabled: true,
        baseUrl: 'http://127.0.0.1:11434/v1',
        model: 'local-model',
      );
      expect(await ai.breakDownTask('目标'), ['ok']);
      for (final code in [401, 404, 429, 502, 302]) {
        status = code;
        await expectLater(
          ai.breakDownTask('目标'),
          throwsA(
            isA<AiException>().having(
              (e) => e.message,
              'redacted',
              isNot(contains('echoed-secret')),
            ),
          ),
        );
      }
      status = 200;
      content = '<think>hidden analysis</think>';
      await expectLater(
        ai.breakDownTask('目标'),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'empty',
            I18n.tr('ai.local.error_empty'),
          ),
        ),
      );
      ai.dispose();
    },
  );

  test(
    'late model response cannot write a report after account change',
    () async {
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      final ai = AiService(
        localConfigStore: MemoryStore(),
        localHttpClient: MockClient((_) {
          started.complete();
          return pending.future;
        }),
      );
      ai.setRemoteAccountActive(false);
      await ai.saveLocalConfiguration(
        enabled: true,
        baseUrl: 'https://models.example',
        model: 'test',
      );
      final review = ai.personalizedReportReview(
        periodLabel: '本周',
        reportMarkdown: 'private report',
      );
      final assertion = expectLater(review, throwsA(isA<AiException>()));
      await started.future;
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      ai.setRemoteAccountActive(true);
      pending.complete(reply('旧账号的报告'));
      await assertion;
      expect(ai.reviewHistory, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('ai_review_history'), isNull);
      ai.dispose();
    },
  );

  test(
    'clearing while secure storage is loading wins over the late read',
    () async {
      final pending = Completer<LocalAiConfig>();
      final store = MemoryStore()..pendingRead = pending;
      final ai = AiService(localConfigStore: store);
      ai.setRemoteAccountActive(false);
      final loading = ai.loadLocalConfiguration();
      await ai.clearLocalConfiguration();
      pending.complete(
        const LocalAiConfig(
          enabled: true,
          baseUrl: 'https://old.example',
          model: 'old',
          apiKey: 'old-key',
        ),
      );
      await loading;
      expect(ai.localConfig.hasApiKey, isFalse);
      expect(ai.enabled, isFalse);
      expect(store.value.hasApiKey, isFalse);
      ai.dispose();
    },
  );

  test('Web cannot enable the native local AI path', () async {
    WebTarget.debugWebBuild = true;
    final ai = AiService(localConfigStore: MemoryStore());
    ai.setRemoteAccountActive(false);
    expect(ai.supportsLocalConfiguration, isFalse);
    expect(ai.usingLocalConfiguration, isFalse);
    await expectLater(
      ai.saveLocalConfiguration(
        enabled: true,
        baseUrl: 'https://models.example',
        model: 'model',
        apiKey: 'key',
      ),
      throwsA(isA<AiException>()),
    );
    ai.dispose();
  });
  test(
    'an account change during secure loading never sends the old draft',
    () async {
      final pending = Completer<LocalAiConfig>();
      final store = MemoryStore()..pendingRead = pending;
      var requests = 0;
      final httpClient = MockClient((_) async {
        requests++;
        return reply('unexpected');
      });
      final ai = AiService(
        localConfigStore: store,
        localHttpClient: httpClient,
      );
      ai.attachClient(
        ApiClient(
          baseUrl: 'https://backend.example',
          token: 'new-user',
          httpClient: httpClient,
        ),
      );
      ai.setRemoteAccountActive(false);
      final response = ai.breakDownTask('private local draft');
      final assertion = expectLater(response, throwsA(isA<AiException>()));
      ai.setRemoteAccountActive(true);
      ai.updateFromServerConfig({'ai_enabled': true});
      pending.complete(
        const LocalAiConfig(
          enabled: true,
          baseUrl: 'https://models.example',
          model: 'test',
        ),
      );
      await assertion;
      expect(requests, 0);
      ai.dispose();
    },
  );
  test(
    'a pending save cannot restore a configuration cleared after it started',
    () async {
      final pending = Completer<LocalAiConfig>();
      final store = MemoryStore()..pendingRead = pending;
      final ai = AiService(localConfigStore: store);
      ai.setRemoteAccountActive(false);
      final save = ai.saveLocalConfiguration(
        enabled: true,
        baseUrl: 'https://old.example',
        model: 'old',
        apiKey: 'old-key',
      );
      final assertion = expectLater(save, throwsA(isA<AiException>()));
      await ai.clearLocalConfiguration();
      pending.complete(const LocalAiConfig());
      await assertion;
      expect(store.value.hasApiKey, isFalse);
      expect(ai.enabled, isFalse);
      ai.dispose();
    },
  );
}
