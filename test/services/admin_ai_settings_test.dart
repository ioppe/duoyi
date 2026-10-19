import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'AI entry points use the correct user proxy and admin diagnostic routes',
    () {
      final adminApi = File('lib/services/admin_api.dart').readAsStringSync();
      final adminScreen = File(
        'lib/screens/admin_screen.dart',
      ).readAsStringSync();
      final diaryScreen = File(
        'lib/screens/diary_screen.dart',
      ).readAsStringSync();
      final mineScreen = File(
        'lib/screens/mine_screen.dart',
      ).readAsStringSync();
      final aiScheduleScreen = File(
        'lib/screens/ai_schedule_screen.dart',
      ).readAsStringSync();

      expect(adminApi, contains('Future<Map<String, dynamic>> testAi({'));
      expect(adminApi, contains("payload['ai_base_url'] = baseUrl"));
      expect(adminApi, contains("payload['ai_api_key'] = apiKey"));
      expect(adminApi, contains("payload['ai_model'] = model"));
      expect(adminApi, contains("'/api/admin/ai/test'"));
      expect(adminApi, contains("'/api/admin/provider-healthcheck'"));
      expect(adminApi, contains("const Duration(seconds: 30)"));
      expect(adminApi, isNot(contains("client.post('/api/ai/chat'")));
      expect(adminScreen, contains("widget.api.getSettings(scope: 'ai')"));
      expect(adminScreen, contains("import '../services/ai_service.dart';"));
      expect(adminScreen, contains('context.read<AiService>()'));
      expect(adminScreen, contains('widget.api.testAi('));
      expect(adminScreen, contains('aiEnabled: _enabled'));
      expect(adminScreen, contains('baseUrl: _baseCtrl.text.trim()'));
      expect(adminScreen, contains('apiKey: submitKey'));
      expect(adminScreen, contains('model: _modelCtrl.text.trim()'));
      expect(adminScreen, contains('测试当前表单'));
      expect(adminScreen, isNot(contains('ai.testConnection()')));
      expect(adminScreen, contains("res['sample']"));
      expect(adminScreen, isNot(contains("res['content']")));
      expect(adminScreen, contains('_adminAiFailureReason'));
      expect(adminScreen, contains('AI 上游服务不可达'));
      expect(adminScreen, contains('AI 代理或上游模型不可用'));
      expect(adminScreen, contains('AI 功能未启用'));

      expect(diaryScreen, isNot(contains('context.read<AiService>()')));
      expect(diaryScreen, isNot(contains('ai.deepDiaryReview(')));
      expect(mineScreen, contains('ai.weeklyReview('));
      expect(
        aiScheduleScreen,
        contains('context.read<AiService>().createScheduleDraft'),
      );

      final backend = File('backend/main.py').readAsStringSync();
      final aiService = File('lib/services/ai_service.dart').readAsStringSync();
      expect(backend, contains('def _ai_chat_completions_url'));
      expect(backend, contains('def _call_ai_chat_upstream('));
      expect(backend, contains('def _ai_chat_content_from_response('));
      expect(backend, contains('base.endswith("/v1")'));
      expect(backend, contains('@app.post("/api/ai/chat")'));
      expect(backend, contains('@app.post("/api/admin/ai/test")'));
      expect(backend, contains('@app.post("/api/admin/provider-healthcheck")'));
      expect(aiService, contains("_client.post('/api/ai/chat'"));
      expect(aiService, contains('Future<String> testConnection()'));
      expect(aiService, contains('你是多仪的 AI 连通性测试助手。只回复 ok。'));
      expect(
        backend,
        isNot(
          contains('raise HTTPException(status_code=503, detail="AI 未启用")'),
        ),
      );
      expect(backend, contains('"ok": False'));
      expect(backend, contains('"skipped": True'));
      expect(backend, contains('"message": "AI 未启用，未测试上游连接。"'));
      expect(adminScreen, contains("res['skipped'] == true"));
      expect(adminScreen, contains('Colors.orange'));
    },
  );
}
