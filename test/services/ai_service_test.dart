import 'dart:convert';

import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/reminder_scheduler.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'weekly review history keeps same-day generated result visible',
    () async {
      final today = DateTime(2026, 5, 23, 10);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ai_review_history': [
          jsonEncode({
            'id': 'weekly-today',
            'createdAt': today.toIso8601String(),
            'content': '今天已经生成过的周回顾',
            'summary': '本周数据：完成 3 / 5 项待办，专注 60 分钟，习惯连续打卡 4 天。',
            'model': 'gpt-test',
            'kind': AiService.weeklyReviewKind,
          }),
          jsonEncode({
            'id': 'diary-today',
            'createdAt': today.toIso8601String(),
            'content': '日记复盘不应命中周回顾',
            'summary': '日记深度复盘',
            'kind': 'diary_review',
          }),
        ],
      });

      final service = AiService();
      await service.loadFromStorage();

      final cached = service.weeklyReviewForDay(today);
      expect(cached, isNotNull);
      expect(cached!.content, '今天已经生成过的周回顾');
      expect(cached.summary, contains('本周数据'));
    },
  );

  test('review entry keeps old history compatible without kind', () {
    final entry = AiReviewEntry.fromJson({
      'id': 'old',
      'createdAt': DateTime(2026, 5, 22).toIso8601String(),
      'content': '旧内容',
      'summary': '旧摘要',
      'model': 'gpt-test',
    });

    expect(entry.kind, isEmpty);
    expect(entry.toJson()['kind'], isEmpty);
  });

  test(
    'same-day weekly review lookup accepts legacy weekly summaries',
    () async {
      final today = DateTime(2026, 5, 23, 10);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ai_review_history': [
          jsonEncode({
            'id': 'legacy-weekly',
            'createdAt': today.toIso8601String(),
            'content': '旧版当天周回顾',
            'summary': '本周数据：完成 1 / 2 项待办，专注 30 分钟，习惯连续打卡 3 天。',
            'model': 'gpt-test',
          }),
        ],
      });

      final service = AiService();
      await service.loadFromStorage();

      expect(service.weeklyReviewForDay(today)?.content, '旧版当天周回顾');
    },
  );

  test(
    'weekly review returns same-day cached result without upstream call',
    () async {
      final today = DateTime(2026, 5, 25, 9);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'ai_review_history': [
          jsonEncode({
            'id': 'weekly-cached',
            'createdAt': today.toIso8601String(),
            'content': '本周回顾：缓存内容',
            'summary': '本周数据：完成 4 / 6 项待办，专注 90 分钟，习惯连续打卡 5 天。',
            'kind': AiService.weeklyReviewKind,
          }),
        ],
      });
      final service = AiService();
      service.attachClient(
        ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token',
          httpClient: MockClient((request) async {
            fail('weeklyReview should use same-day cache before calling AI');
          }),
        ),
      );
      service.updateFromServerConfig({'ai_enabled': true});
      await service.loadFromStorage();

      final review = await service.weeklyReview(
        completedTodos: 1,
        totalTodos: 1,
        weeklyFocusMinutes: 1,
        habitStreak: 1,
        periodLabel: '本周',
        now: today,
      );

      expect(review, '本周回顾：缓存内容');
    },
  );

  test(
    'weekly review stores one same-day entry with explicit range prompt',
    () async {
      final today = DateTime(2026, 5, 25, 9);
      final service = AiService();
      service.attachClient(
        ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token',
          httpClient: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['system'], contains('输出分层纯文本'));
            expect(body['system'], contains('不要 Markdown、表格、emoji、加粗'));
            expect(body['system'], contains('上周回顾\n总览：一句总判断'));
            expect(body['user'], contains('待办完成：2 / 3'));
            return http.Response(
              jsonEncode({
                'content':
                    '上周回顾\n'
                    '总览：整体推进不错，可以继续加固。\n'
                    '数据\n'
                    '待办：完成 2 / 3 项，完成率 67%。\n'
                    '专注：45 分钟，保留固定专注窗口。\n'
                    '习惯：连续 4 天，继续守住当前节奏。\n'
                    '观察：待办有推进，适合减少目标切换。\n'
                    '下周行动\n'
                    '行动一：保留两件关键任务。\n'
                    '行动二：周中复盘一次任务清单。',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      service.updateFromServerConfig({'ai_enabled': true});

      final review = await service.weeklyReview(
        completedTodos: 2,
        totalTodos: 3,
        weeklyFocusMinutes: 45,
        habitStreak: 4,
        periodLabel: '上周',
        now: today,
      );

      expect(review, startsWith('上周回顾\n'));
      expect(review, contains('\n总览：'));
      expect(review, contains('\n数据\n'));
      expect(review, contains('\n待办：'));
      expect(review, contains('\n专注：'));
      expect(review, contains('\n习惯：'));
      expect(review, contains('\n观察：'));
      expect(review, contains('\n下周行动\n'));
      expect(review, contains('\n行动一：'));
      expect(review, contains('\n行动二：'));
      final cached = service.weeklyReviewForDay(today);
      expect(cached, isNotNull);
      expect(cached!.kind, AiService.weeklyReviewKind);
      expect(cached.createdAt, today);
      expect(cached.summary, startsWith('上周数据：'));
    },
  );

  test('weekly review normalizes markdown-heavy upstream content', () async {
    final today = DateTime(2026, 6, 2, 9);
    final service = AiService();
    service.attachClient(
      ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token',
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'content':
                  '## 📊 上周数据概览\n\n'
                  '| 指标 | 完成情况 |\n'
                  '|---|---|\n'
                  '| ✅ 待办事项 | **3 / 4 项** |\n'
                  '如果你需要我帮你制定本周计划，随时告诉我哦！',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    service.updateFromServerConfig({'ai_enabled': true});

    final review = await service.weeklyReview(
      completedTodos: 3,
      totalTodos: 4,
      weeklyFocusMinutes: 0,
      habitStreak: 0,
      periodLabel: '上周',
      now: today,
    );

    expect(review, startsWith('上周回顾\n'));
    expect(review.split('\n'), hasLength(10));
    expect(review, contains('\n总览：'));
    expect(review, contains('\n数据\n'));
    expect(review, contains('待办：完成 3 / 4 项，完成率 75%。'));
    expect(review, contains('专注：0 分钟'));
    expect(review, contains('习惯：连续 0 天'));
    expect(review, contains('\n观察：'));
    expect(review, contains('\n下周行动\n'));
    expect(review, contains('\n行动一：'));
    expect(review, contains('\n行动二：'));
    expect(review, isNot(contains('|')));
    expect(review, isNot(contains('**')));
    expect(review, isNot(contains('📊')));
    expect(review, isNot(contains('随时告诉我')));
  });

  test(
    'AI schedule creation falls back to local parser when disabled',
    () async {
      final service = AiService();
      service.updateFromServerConfig({'ai_enabled': false});

      final draft = await service.createScheduleDraft(
        '明天下午3点和产品开会，提前提醒我',
        now: DateTime(2026, 5, 23, 9),
      );

      expect(draft.source, AiScheduleSource.localParser);
      expect(draft.type, AiScheduleType.calendar);
      expect(draft.title, contains('产品'));
      expect(draft.startAt, DateTime(2026, 5, 24, 15));
      expect(draft.endAt, DateTime(2026, 5, 24, 16));
      expect(draft.reminderEnabled, isTrue);
    },
  );

  test('AI schedule creation parses structured AI result', () async {
    final service = AiService();
    service.attachClient(
      ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/ai/chat');
          return http.Response(
            jsonEncode({
              'content': jsonEncode({
                'type': 'calendar',
                'title': '产品评审会',
                'start_at': '2026-05-24T15:00:00',
                'end_at': '2026-05-24T16:30:00',
                'all_day': false,
                'reminder': true,
                'notes': '带上 PRD',
                'subtasks': ['准备材料', '同步风险'],
              }),
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    service.updateFromServerConfig({
      'ai_enabled': true,
      'ai_model': 'gpt-test',
    });

    final draft = await service.createScheduleDraft(
      '明天下午3点产品评审会，带上 PRD',
      now: DateTime(2026, 5, 23, 9),
    );

    expect(draft.source, AiScheduleSource.ai);
    expect(draft.type, AiScheduleType.calendar);
    expect(draft.title, '产品评审会');
    expect(draft.startAt, DateTime(2026, 5, 24, 15));
    expect(draft.endAt, DateTime(2026, 5, 24, 16, 30));
    expect(draft.reminderEnabled, isTrue);
    expect(draft.notes, '带上 PRD');
    expect(draft.subtasks, ['准备材料', '同步风险']);
  });

  test('AiService connection test uses the user /api/ai/chat proxy', () async {
    final service = AiService();
    service.attachClient(
      ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'admin-token',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/ai/chat');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['system'], contains('连通性测试助手'));
          expect(body['user'], contains('/api/ai/chat'));
          expect(body['temperature'], 0);
          return http.Response(
            jsonEncode({'content': 'ok'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    service.updateFromServerConfig({
      'ai_enabled': true,
      'ai_model': 'gpt-test',
    });

    expect(await service.testConnection(), 'ok');
  });

  test(
    'AI schedule creation extracts fenced nested JSON and aliases',
    () async {
      final service = AiService();
      service.attachClient(
        ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token',
          httpClient: MockClient((request) async {
            return http.Response(
              jsonEncode({
                'content': '''
```json
{
  "draft": {
    "kind": "event",
    "name": "和医生复诊",
    "startAt": "2026-05-25 09:30",
    "提醒": "是",
    "备注": "带检查报告",
    "清单": "确认挂号\\n带医保卡"
  }
}
```
''',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      service.updateFromServerConfig({'ai_enabled': true});

      final draft = await service.createScheduleDraft(
        '下周一上午9点半和医生复诊，提醒我带检查报告',
        now: DateTime(2026, 5, 23, 9),
      );

      expect(draft.source, AiScheduleSource.ai);
      expect(draft.type, AiScheduleType.calendar);
      expect(draft.title, '医生复诊');
      expect(draft.startAt, DateTime(2026, 5, 25, 9, 30));
      expect(draft.endAt, DateTime(2026, 5, 25, 10, 30));
      expect(draft.reminderEnabled, isTrue);
      expect(draft.notes, '带检查报告');
      expect(draft.subtasks, ['确认挂号', '带医保卡']);
    },
  );

  test(
    'AI schedule creation falls back with warning for invalid AI JSON',
    () async {
      final service = AiService();
      service.attachClient(
        ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token',
          httpClient: MockClient((request) async {
            return http.Response(
              jsonEncode({'content': '我无法判断，请手动创建。'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      service.updateFromServerConfig({'ai_enabled': true});

      final draft = await service.createScheduleDraft(
        '明天上午10点开项目会',
        now: DateTime(2026, 5, 23, 9),
      );

      expect(draft.source, AiScheduleSource.aiWithLocalFallback);
      expect(draft.warning, contains('AI 没有返回可用草稿'));
      expect(draft.type, AiScheduleType.calendar);
      expect(draft.startAt, DateTime(2026, 5, 24, 10));
    },
  );

  test('AI schedule creation keeps local draft when upstream fails', () async {
    final service = AiService();
    service.attachClient(
      ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'token',
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({'detail': '上游不可达: timeout'}),
            502,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    service.updateFromServerConfig({'ai_enabled': true});

    final draft = await service.createScheduleDraft(
      '明天下午3点和产品开会，提前提醒我',
      now: DateTime(2026, 5, 23, 9),
    );

    expect(draft.source, AiScheduleSource.localParser);
    expect(draft.warning, contains('AI 识别失败，已用本地时间解析生成草稿'));
    expect(draft.warning, contains('AI 上游服务不可达'));
    expect(draft.type, AiScheduleType.calendar);
    expect(draft.startAt, DateTime(2026, 5, 24, 15));
    expect(draft.reminderEnabled, isTrue);
  });

  test(
    'AI schedule creation reports route failures as local fallback warning',
    () async {
      final service = AiService();
      service.attachClient(
        ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token',
          httpClient: MockClient((request) async {
            return http.Response(
              jsonEncode({'detail': 'Not Found'}),
              404,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      service.updateFromServerConfig({'ai_enabled': true});

      final draft = await service.createScheduleDraft(
        '明天下午3点和产品开会，提前提醒我',
        now: DateTime(2026, 5, 23, 9),
      );

      expect(draft.source, AiScheduleSource.localParser);
      expect(draft.warning, contains('AI 识别失败'));
      expect(draft.warning, contains('/api/ai/chat'));
      expect(draft.warning, contains('Base URL'));
      expect(draft.title, contains('产品'));
    },
  );

  test('AI schedule todo draft persists reminder and subtasks', () {
    final draft = AiScheduleDraft(
      type: AiScheduleType.todo,
      title: '写补丁说明',
      startAt: DateTime(2026, 5, 24, 10, 30),
      reminderEnabled: true,
      notes: '发布前完成',
      subtasks: const ['整理变更', '检查截图'],
    );

    final todo = draft.toTodo();

    expect(todo.title, '写补丁说明');
    expect(todo.dueDate, DateTime(2026, 5, 24, 10, 30));
    expect(todo.hasReminder, isTrue);
    expect(todo.reminderAt, DateTime(2026, 5, 24, 10, 30));
    expect(todo.reminderPlan.enabled, isTrue);
    expect(todo.reminderPlan.rules.single.hour, 10);
    expect(todo.reminderPlan.rules.single.minute, 30);
    expect(todo.subtasks.map((item) => item.title), ['整理变更', '检查截图']);
    final preflight = preflightTodoReminderPlan(
      todo,
      now: DateTime(2026, 5, 24, 10),
    );
    expect(preflight.ok, isTrue);
    expect(preflight.firstScheduledTime, DateTime(2026, 5, 24, 10, 30));
  });

  test(
    'statistics report review without period metadata stays unscoped',
    () async {
      final service = AiService();
      service.attachClient(
        ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'token',
          httpClient: MockClient((request) async {
            return http.Response(
              jsonEncode({'content': '无周期元数据解读'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      service.updateFromServerConfig({
        'ai_enabled': true,
        'ai_model': 'gpt-test',
      });

      // 旧调用方签名不变：不传 reportContext/dataThrough 仍然可用。
      final review = await service.personalizedReportReview(
        periodLabel: '本周周报',
        reportMarkdown: '# 本周周报',
      );
      await service.waitForHistoryWrites();

      expect(review, '无周期元数据解读');
      final entry = service.reviewHistory.single;
      expect(entry.content, review);
      expect(entry.reportContext, isNull);
      expect(entry.dataThrough, isNull);
      expect(entry.kind, AiService.statisticsReportKind);
      expect(entry.summary, '统计报告 AI 解读：本周周报');
      expect(service.reportContexts, isEmpty);
      service.dispose();
    },
  );
}
