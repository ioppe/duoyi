import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:duoyi/services/admin_api.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'relative API path on mobile/desktop returns friendly configuration error',
    () async {
      final client = ApiClient(baseUrl: '');

      await expectLater(
        client.get('/api/announcements'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('登录页配置服务器地址'),
          ),
        ),
      );
    },
  );

  test('base URL trailing slash is trimmed before joining API paths', () async {
    final seen = <Uri>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test/',
      httpClient: MockClient((request) async {
        seen.add(request.url);
        return http.Response('{"ok":true}', 200);
      }),
    );

    await client.get('/api/config');

    expect(seen.single.toString(), 'https://duoyi.test/api/config');
  });

  test('base URL joining also handles paths without leading slash', () async {
    final seen = <Uri>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test///',
      httpClient: MockClient((request) async {
        seen.add(request.url);
        return http.Response('{"ok":true}', 200);
      }),
    );

    await client.post('api/auth/login', {'username': 'u'});

    expect(seen.single.toString(), 'https://duoyi.test/api/auth/login');
  });

  test(
    'base URL joining accepts server URL accidentally ending with /api',
    () async {
      final seen = <Uri>[];
      final client = ApiClient(
        baseUrl: 'https://duoyi.test/api/',
        httpClient: MockClient((request) async {
          seen.add(request.url);
          return http.Response('{"ok":true}', 200);
        }),
      );

      await client.patch('/api/me/profile', {'display_name': '多仪'});

      expect(seen.single.toString(), 'https://duoyi.test/api/me/profile');
    },
  );

  test('map and list helpers fail loudly on wrong response shape', () async {
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/object')) {
          return http.Response('{"items":[]}', 200);
        }
        return http.Response('[]', 200);
      }),
    );

    await expectLater(
      client.get('/api/list'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('需要对象'),
        ),
      ),
    );
    await expectLater(
      client.getList('/api/object'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('需要列表'),
        ),
      ),
    );
  });

  test(
    'upload helper fails loudly when successful response is not an object',
    () async {
      final client = ApiClient(
        baseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async => http.Response('[]', 200)),
      );

      await expectLater(
        client.uploadBytes(
          '/api/me/avatar',
          fieldName: 'avatar',
          filename: 'avatar.png',
          bytes: Uint8List.fromList(<int>[137, 80, 78, 71]),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('需要对象'),
          ),
        ),
      );
    },
  );

  test('upload helper sends image content type for avatar files', () async {
    String? multipartBody;
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      httpClient: MockClient((request) async {
        multipartBody = latin1.decode(request.bodyBytes);
        return http.Response('{"ok":true}', 200);
      }),
    );

    await client.uploadBytes(
      '/api/me/avatar',
      fieldName: 'avatar',
      filename: 'avatar.png',
      bytes: Uint8List.fromList(<int>[137, 80, 78, 71]),
    );

    expect(multipartBody, contains('content-type: image/png'));
  });

  test('successful API helpers wrap invalid JSON in ApiException', () async {
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      httpClient: MockClient((request) async => http.Response('<html>', 200)),
    );

    await expectLater(
      client.get('/api/config'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('不是有效 JSON'),
        ),
      ),
    );
    await expectLater(
      client.uploadBytes(
        '/api/me/avatar',
        fieldName: 'avatar',
        filename: 'avatar.png',
        bytes: Uint8List.fromList(<int>[137, 80, 78, 71]),
      ),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('不是有效 JSON'),
        ),
      ),
    );
  });

  test(
    'missing current backend route explains stale server contract',
    () async {
      final seen = <String>[];
      final client = ApiClient(
        baseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          seen.add('${request.method} ${request.url.path}');
          if (request.url.path == '/api/config') {
            return http.Response(
              json.encode({'registration_enabled': true, 'version': '3.1.0'}),
              200,
            );
          }
          return http.Response('{"detail":"Not Found"}', 404);
        }),
      );

      await expectLater(
        client.post('/api/me/email-code', {'email': 'u@example.com'}),
        throwsA(
          isA<ApiException>()
              .having(
                (e) => e.message,
                'message',
                contains('当前服务器 duoyi.test/api/config'),
              )
              .having(
                (e) => e.message,
                'message',
                contains('当前后端未部署本版本接口：/api/me/email-code'),
              )
              .having(
                (e) => e.message,
                'message',
                contains('缺少接口契约 api_contract_version'),
              ),
        ),
      );
      expect(seen, ['POST /api/me/email-code', 'GET /api/config']);
    },
  );

  test('business 404 does not get stale backend route diagnosis', () async {
    final seen = <String>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      httpClient: MockClient((request) async {
        seen.add('${request.method} ${request.url.path}');
        return http.Response('{"detail":"User not found"}', 404);
      }),
    );

    await expectLater(
      client.get('/api/admin/users/missing'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.message, 'message', contains('User not found'))
            .having(
              (e) => e.message,
              'message',
              isNot(contains('当前后端未部署本版本接口')),
            ),
      ),
    );
    expect(seen, ['GET /api/admin/users/missing']);
  });

  test(
    'user visible API error hides backend compatibility diagnostics only',
    () {
      for (final message in const [
        '当前后端未部署本版本接口：/api/me/profile。缺少接口契约 api_contract_version。',
        '检查更新失败：当前后端未部署本版本更新接口：/api/mobile/apps/duoyi/update。',
        '接口契约 2024-01-01.1 低于客户端要求 2026-05-20.1。',
        '缺少必备路由摘要 required_routes_hash。',
        '反向代理未转发 /api/*。',
      ]) {
        expect(
          userVisibleApiError(ApiException(message)),
          defaultUserVisibleBackendErrorMessage,
        );
      }

      expect(
        userVisibleApiError(const ApiException('User not found')),
        'User not found',
      );
    },
  );

  test('upload avatar 404 also explains stale server contract', () async {
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/config') {
          return http.Response(
            json.encode({
              'api_contract_version': '2024-01-01.1',
              'features': {'email_code': true},
            }),
            200,
          );
        }
        return http.Response('{"detail":"Not Found"}', 404);
      }),
    );

    await expectLater(
      client.uploadBytes(
        '/api/me/avatar',
        fieldName: 'avatar',
        filename: 'avatar.png',
        bytes: Uint8List.fromList(<int>[137, 80, 78, 71]),
      ),
      throwsA(
        isA<ApiException>()
            .having(
              (e) => e.message,
              'message',
              contains('接口契约 2024-01-01.1 低于客户端要求'),
            )
            .having(
              (e) => e.message,
              'message',
              contains('当前服务器 duoyi.test/api/config'),
            ),
      ),
    );
  });

  test(
    'missing current backend route also diagnoses required route hash mismatch',
    () async {
      final seen = <String>[];
      final client = ApiClient(
        baseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          seen.add('${request.method} ${request.url.path}');
          if (request.url.path == '/api/config') {
            return http.Response(
              json.encode({
                'api_contract_version': ApiClient.requiredApiContractVersion,
                'required_routes_hash': 'stale-routes',
                'version': '3.1.0',
              }),
              200,
            );
          }
          return http.Response('{"detail":"Not Found"}', 404);
        }),
      );

      await expectLater(
        client.post('/api/me/email-code', {'email': 'u@example.com'}),
        throwsA(
          isA<ApiException>()
              .having(
                (e) => e.message,
                'message',
                contains('当前后端未部署本版本接口：/api/me/email-code'),
              )
              .having(
                (e) => e.message,
                'message',
                contains('必备路由摘要 stale-routes 与客户端要求'),
              ),
        ),
      );
      expect(seen, ['POST /api/me/email-code', 'GET /api/config']);
    },
  );

  test(
    'text and event stream helpers also diagnose stale backend routes',
    () async {
      final seen = <String>[];
      final client = ApiClient(
        baseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          seen.add('${request.method} ${request.url.path}');
          if (request.url.path == '/api/config') {
            return http.Response(
              json.encode({
                'api_contract_version': '2024-01-01.1',
                'version': '3.1.0',
              }),
              200,
            );
          }
          return http.Response('{"detail":"Not Found"}', 404);
        }),
      );

      await expectLater(
        client.getText('/api/admin/backups/export.csv'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('当前后端未部署本版本接口：/api/admin/backups/export.csv'),
          ),
        ),
      );
      await expectLater(
        client.streamLines('/api/sync/events').drain<void>(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('接口契约 2024-01-01.1 低于客户端要求'),
          ),
        ),
      );
      expect(seen, [
        'GET /api/admin/backups/export.csv',
        'GET /api/config',
        'GET /api/sync/events',
      ]);
    },
  );

  test(
    'fallback route failure can diagnose stale backend or api proxy',
    () async {
      final client = ApiClient(
        baseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/config') {
            return http.Response('<html>frontend shell</html>', 404);
          }
          return http.Response('{"detail":"Not Found"}', 404);
        }),
      );

      final error = await client.missingRoutesException(
        featureName: '头像上传',
        paths: const ['/api/me/avatar', '/api/profile/avatar'],
        fallback: const ApiException('404: Not Found'),
      );

      expect(error.message, contains('头像上传接口均未命中'));
      expect(error.message, contains('/api/me/avatar'));
      expect(error.message, contains('当前服务器 duoyi.test/api/config 返回 404'));
      expect(error.message, contains('反向代理未转发 /api/*'));
    },
  );

  test('html proxy 404 is also diagnosed as stale backend route', () async {
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/config') {
          return http.Response(
            json.encode({
              'api_contract_version': '2024-01-01.1',
              'version': '3.1.0',
            }),
            200,
          );
        }
        return http.Response('<html><title>404 Not Found</title></html>', 404);
      }),
    );

    await expectLater(
      client.post('/api/me/email-code', {'email': 'u@example.com'}),
      throwsA(
        isA<ApiException>()
            .having(
              (e) => e.message,
              'message',
              contains('当前后端未部署本版本接口：/api/me/email-code'),
            )
            .having(
              (e) => e.message,
              'message',
              contains('接口契约 2024-01-01.1 低于客户端要求'),
            ),
      ),
    );
  });

  test(
    'stale backend diagnosis includes concrete server for admin coin 404',
    () async {
      final client = ApiClient(
        baseUrl: 'https://api.duoyi.test/root/',
        httpClient: MockClient((request) async {
          if (request.url.path == '/root/api/config') {
            return http.Response(
              json.encode({
                'api_contract_version': '2024-01-01.1',
                'version': '3.0.0',
              }),
              200,
            );
          }
          return http.Response('{"detail":"Not Found"}', 404);
        }),
      );

      await expectLater(
        AdminApi(client).adjustUserCoins('u1', delta: 25, reason: '补偿'),
        throwsA(
          isA<ApiException>()
              .having(
                (e) => e.message,
                'message',
                contains('当前后端未部署本版本接口：/api/admin/users/u1/coins'),
              )
              .having(
                (e) => e.message,
                'message',
                contains('当前服务器 api.duoyi.test/root/api/config'),
              )
              .having((e) => e.message, 'message', contains('后端版本 3.0.0')),
        ),
      );
    },
  );

  test(
    'admin pagination still accepts legacy list responses through getRaw',
    () async {
      final client = ApiClient(
        baseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/admin/users');
          return http.Response('[{"user_id":"u1","username":"alice"}]', 200);
        }),
      );

      final page = await AdminApi(client).listUsersPage();

      expect(page.items, hasLength(1));
      expect(page.items.single['user_id'], 'u1');
      expect(page.hasMore, isFalse);
    },
  );

  test('admin pagination fails loudly when items is not a list', () async {
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      httpClient: MockClient((request) async {
        return http.Response('{"items":{}}', 200);
      }),
    );

    await expectLater(
      AdminApi(client).listUsersPage(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('items 需要列表'),
        ),
      ),
    );
  });

  test('admin feedback detail uses current item route', () async {
    final seen = <String>[];
    final client = ApiClient(
      baseUrl: 'https://duoyi.test/api/',
      httpClient: MockClient((request) async {
        seen.add('${request.method} ${request.url.path}');
        if (request.method == 'GET' &&
            request.url.path == '/api/admin/feedback/7') {
          return http.Response.bytes(
            utf8.encode(
              json.encode({
                'id': 7,
                'category': 'bug',
                'content': '详情内容',
                'status': 'open',
              }),
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{"detail":"Not Found"}', 404);
      }),
    );

    final detail = await AdminApi(client).getFeedbackDetail(7);

    expect(detail['id'], 7);
    expect(detail['content'], '详情内容');
    expect(seen, ['GET /api/admin/feedback/7']);
  });

  test('admin coin adjustment uses current primary route only', () async {
    final seen = <String>[];
    Map<String, dynamic>? successfulBody;
    final client = ApiClient(
      baseUrl: 'https://duoyi.test',
      httpClient: MockClient((request) async {
        seen.add('${request.method} ${request.url.path}');
        final body = json.decode(request.body) as Map<String, dynamic>;
        expect(body['delta'], 25);
        expect(body['reason'], '补偿');
        if (request.method == 'POST' &&
            request.url.path == '/api/admin/users/u1/coins') {
          successfulBody = body;
          return http.Response(
            '{"balance":125,"lifetime":225,"server_version":3}',
            200,
          );
        }
        return http.Response('{"detail":"Not Found"}', 404);
      }),
    );

    final result = await AdminApi(
      client,
    ).adjustUserCoins('u1', delta: 25, reason: '  补偿  ');

    expect(result['balance'], 125);
    expect(result['lifetime'], 225);
    expect(result['server_version'], 3);
    expect(successfulBody, isNotNull);
    expect(seen, ['POST /api/admin/users/u1/coins']);
  });

  test(
    'admin coin adjustment missing route does not try legacy fallbacks',
    () async {
      final seen = <String>[];
      final client = ApiClient(
        baseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          seen.add('${request.method} ${request.url.path}');
          if (request.url.path == '/api/config') {
            return http.Response(
              json.encode({'registration_enabled': true, 'version': '3.1.0'}),
              200,
            );
          }
          return http.Response('{"detail":"Not Found"}', 404);
        }),
      );

      await expectLater(
        AdminApi(client).adjustUserCoins('u1', delta: 25, reason: '补偿'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('当前后端未部署本版本接口：/api/admin/users/u1/coins'),
          ),
        ),
      );
      expect(seen, ['POST /api/admin/users/u1/coins', 'GET /api/config']);
    },
  );

  test(
    'admin update settings sends force update payload to settings route',
    () async {
      final seen = <String>[];
      Map<String, dynamic>? payload;
      final client = ApiClient(
        baseUrl: 'https://duoyi.test/api/',
        httpClient: MockClient((request) async {
          seen.add('${request.method} ${request.url.path}');
          payload = json.decode(request.body) as Map<String, dynamic>;
          return http.Response('{"ok":true}', 200);
        }),
      );

      await AdminApi(client).updateSettings(
        forceUpdateRequired: true,
        latestVersion: '1.2.0',
        minimumSupportedVersion: '1.1.9',
        updateNotes: '修复通知和小组件问题',
        updateDownloadUrl: '',
      );

      expect(seen, ['PATCH /api/admin/settings']);
      expect(payload, {
        'force_update_required': true,
        'latest_version': '1.2.0',
        'minimum_supported_version': '1.1.9',
        'update_notes': '修复通知和小组件问题',
        'update_download_url': '',
      });
    },
  );

  test(
    'admin update settings falls back to compatible settings routes',
    () async {
      final seen = <String>[];
      final client = ApiClient(
        baseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          seen.add('${request.method} ${request.url.path}');
          if (request.method == 'PATCH' &&
              request.url.path == '/api/admin/settings') {
            return http.Response('{"detail":"Not Found"}', 404);
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/admin/settings') {
            return http.Response(
              '{"status":"ok","changed":{"force_update_required":true}}',
              200,
            );
          }
          return http.Response('{"detail":"Not Found"}', 404);
        }),
      );

      final result = await AdminApi(
        client,
      ).updateSettings(forceUpdateRequired: true);

      expect(result['status'], 'ok');
      expect(seen, ['PATCH /api/admin/settings', 'POST /api/admin/settings']);
    },
  );

  test(
    'admin system settings fallback normalizes legacy settings payload',
    () async {
      final seen = <String>[];
      final client = ApiClient(
        baseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          seen.add('${request.method} ${request.url.path}');
          if (request.url.path == '/api/admin/system-settings') {
            return http.Response('{"detail":"Not Found"}', 404);
          }
          if (request.url.path == '/api/admin/settings') {
            return http.Response(
              '{"force_update_required":true,"latest_version":"2.0.0"}',
              200,
            );
          }
          return http.Response('{"detail":"Not Found"}', 404);
        }),
      );

      final payload = await AdminApi(client).getSystemSettings();
      final settings = await AdminApi(client).getSettings();

      expect(payload['runtime_status']['force_update_required'], isTrue);
      expect(payload['runtime_status']['latest_version'], '2.0.0');
      expect(settings['force_update_required'], isTrue);
      expect(settings['latest_version'], '2.0.0');
      expect(seen, [
        'GET /api/admin/system-settings',
        'GET /api/admin/settings',
        'GET /api/admin/settings',
      ]);
    },
  );

  test(
    'admin system settings update falls back to admin settings then refetches normalized payload',
    () async {
      final seen = <String>[];
      final client = ApiClient(
        baseUrl: 'https://duoyi.test',
        httpClient: MockClient((request) async {
          seen.add('${request.method} ${request.url.path}');
          if (request.method == 'POST' &&
              request.url.path == '/api/admin/system-settings') {
            return http.Response('{"detail":"Not Found"}', 404);
          }
          if (request.method == 'PATCH' &&
              request.url.path == '/api/admin/settings') {
            return http.Response(
              '{"status":"ok","changed":{"force_update_required":true}}',
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/admin/system-settings') {
            return http.Response('{"detail":"Not Found"}', 404);
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/admin/settings') {
            return http.Response(
              '{"force_update_required":true,"latest_version":"3.0.0"}',
              200,
            );
          }
          return http.Response('{"detail":"Not Found"}', 404);
        }),
      );

      final payload = await AdminApi(
        client,
      ).updateSystemSettings({'force_update_required': true});

      expect(payload['runtime_status']['force_update_required'], isTrue);
      expect(payload['runtime_status']['latest_version'], '3.0.0');
      expect(seen, [
        'POST /api/admin/system-settings',
        'PATCH /api/admin/settings',
        'GET /api/admin/system-settings',
        'GET /api/admin/settings',
      ]);
    },
  );
}
