import 'dart:convert';
import 'dart:io';

import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

AiService _serviceReturning(
  String content, {
  String model = '',
  void Function(http.Request)? onRequest,
}) {
  final client = MockClient((request) async {
    onRequest?.call(request);
    return http.Response.bytes(
      utf8.encode(jsonEncode({'content': content})),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  final service = AiService()
    ..attachClient(
      ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'test-token',
        httpClient: client,
      ),
    )
    ..updateFromServerConfig({'ai_enabled': true, 'ai_model': model});
  addTearDown(service.dispose);
  addTearDown(client.close);
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('空正文抛 AiException，不再把空串当成功结果', () async {
    final service = _serviceReturning('');
    await expectLater(
      service.personalizedReportReview(
        periodLabel: '本周周报',
        reportMarkdown: '# 本周周报\n- 待办完成：0 项',
      ),
      throwsA(
        isA<AiException>().having(
          (error) => error.message,
          'message',
          contains('未返回正文'),
        ),
      ),
    );
  });

  test('上游空正文的 502 细节不会被通用「不可达」文案吞掉', () async {
    final client = MockClient(
      (request) async => http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'detail':
                '模型把输出预算全部用于思考，正文为空（finish_reason=length，'
                '思考 900 tokens）。请调大 max_tokens 或改用非推理模型。',
          }),
        ),
        502,
        headers: {'content-type': 'application/json'},
      ),
    );
    final service = AiService()
      ..attachClient(
        ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'test-token',
          httpClient: client,
        ),
      )
      ..updateFromServerConfig({'ai_enabled': true});
    addTearDown(service.dispose);
    addTearDown(client.close);
    await expectLater(
      service.personalizedReportReview(
        periodLabel: '本周周报',
        reportMarkdown: '# 本周周报',
      ),
      throwsA(
        isA<AiException>().having(
          (error) => error.message,
          'message',
          allOf(contains('正文为空'), contains('max_tokens')),
        ),
      ),
    );
  });

  test('502 保留格式、空响应和模型错误详情，不误报为网络不可达', () async {
    for (final detail in [
      '模型已达到输出上限，正文为空（finish_reason=length，输出 2200 tokens，检测到思考内容）。请调大 max_tokens。',
      '上游响应格式错误（预期 JSON 或 SSE）：SSE 流未完整结束，请重试',
      '上游返回空内容（finish_reason=stop），请检查网关配置',
      '上游错误: 模型暂不可用',
    ]) {
      final client = MockClient(
        (request) async => http.Response.bytes(
          utf8.encode(jsonEncode({'detail': detail})),
          502,
          headers: {'content-type': 'application/json'},
        ),
      );
      final service = AiService()
        ..attachClient(
          ApiClient(
            baseUrl: 'https://duoyi.test',
            token: 'test-token',
            httpClient: client,
          ),
        )
        ..updateFromServerConfig({'ai_enabled': true});
      addTearDown(service.dispose);
      addTearDown(client.close);
      await expectLater(
        service.personalizedReportReview(
          periodLabel: '本周周报',
          reportMarkdown: '# 本周周报',
        ),
        throwsA(
          isA<AiException>().having(
            (error) => error.message,
            'message',
            allOf(contains(detail), isNot(contains('上游服务不可达'))),
          ),
        ),
      );
      expect(service.reviewHistory, isEmpty);
    }
  });

  test('正常正文原样返回并去掉首尾空白', () async {
    final service = _serviceReturning('  本周节奏稳定。  ');
    final review = await service.personalizedReportReview(
      periodLabel: '本周周报',
      reportMarkdown: '# 本周周报',
    );
    expect(review, '本周节奏稳定。');
  });

  test('MiniMax 报告留足推理预算，短探针和其他模型保持原预算', () async {
    for (final (model, reportBudget, weeklyBudget) in [
      ('minimax-m3.1-flash-free', 8192, 8192),
      ('opencode/minimax-m3.1-flash-free', 8192, 8192),
      ('deepseek-v4.1-flash', 2200, 1000),
    ]) {
      final budgets = <int>[];
      final service = _serviceReturning(
        '本周回顾已完成。',
        model: model,
        onRequest: (request) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          budgets.add(body['max_tokens'] as int);
        },
      );
      await service.personalizedReportReview(
        periodLabel: '本周周报',
        reportMarkdown: '# 本周周报',
      );
      await service.weeklyReview(
        completedTodos: 1,
        totalTodos: 1,
        weeklyFocusMinutes: 0,
        habitStreak: 0,
      );
      await service.testConnection();
      expect(budgets, [reportBudget, weeklyBudget, 256], reason: model);
    }
  });

  test('推理模型的输出预算已覆盖思考与正文', () {
    final source = File('lib/services/ai_service.dart').readAsStringSync();
    // 解读 2200 / 拆解 2000 / 周报与周期报告 1000 / 探针 256。
    expect(source, contains('maxTokens: 2200'));
    expect(source, contains('maxTokens: 2000'));
    expect(source, contains('maxTokens: 1000'));
    expect(source, contains('maxTokens: 256'));
    for (final tooSmall in [
      'maxTokens: 900,',
      'maxTokens: 420,',
      'maxTokens: 400,',
      'maxTokens: 260,',
      'maxTokens: 16,',
      'maxTokens: 512,',
    ]) {
      expect(source, isNot(contains(tooSmall)), reason: '$tooSmall 会被思考吃光');
    }
    expect(source, contains('推理型模型会先消耗大量 reasoning token'));
  });

  test('解读面板不会把空正文渲染成空白卡片', () {
    final statistics = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();
    expect(statistics, contains("review.trim().isEmpty"));
    expect(statistics, contains('模型未返回正文'));
  });
}
