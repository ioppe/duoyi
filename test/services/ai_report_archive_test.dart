import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/statistics_period.dart';
import 'package:duoyi/models/ai_report_context.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/ai_review_history_store.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

AiReportContext _weekContext({int day = 26}) => AiReportContext.fromWindow(
  StatisticsWindow(StatisticsPeriod.week, today: DateTime(2026, 5, day)),
  timeZone: 'Asia/Shanghai',
);

AiReportContext _monthContext() => AiReportContext.fromWindow(
  StatisticsWindow(StatisticsPeriod.month, today: DateTime(2026, 5, 20)),
  timeZone: 'Asia/Shanghai',
);

ApiClient _apiClient(MockClient httpClient) => ApiClient(
  baseUrl: 'https://duoyi.test',
  token: 'token',
  httpClient: httpClient,
);

http.Response _chatResponse(String content) => http.Response.bytes(
  utf8.encode(jsonEncode({'content': content})),
  200,
  headers: {'content-type': 'application/json'},
);

AiService _service({AiReviewHistoryStore? store}) =>
    AiService(historyStore: store)
      ..updateFromServerConfig({'ai_enabled': true, 'ai_model': 'gpt-test'});

String _sessionChanged() => I18n.tr('statistics.ai.error.session_changed');

/// 单条存档 payload 的 id（用于验证重试复用同一条目身份）。
String _entryIdIn(List<String> payload) =>
    (jsonDecode(payload.single) as Map<String, dynamic>)['id'].toString();

const String _structuredWeeklyReview =
    '上周回顾\n'
    '总览：整体推进不错，可以继续加固。\n'
    '数据\n'
    '待办：完成 1 / 2 项，完成率 50%。\n'
    '专注：30 分钟，保留固定专注窗口。\n'
    '习惯：连续 3 天，继续守住当前节奏。\n'
    '观察：待办有推进，适合减少目标切换。\n'
    '下周行动\n'
    '行动一：保留两件关键任务。\n'
    '行动二：周中复盘一次任务清单。';

/// 可控的历史存储：可以阻塞读取/写入，也可以让写入直接失败。
class _FakeHistoryStore extends AiReviewHistoryStore {
  _FakeHistoryStore({List<String>? initial}) : _entries = [...?initial];

  List<String> _entries;
  final List<List<String>> writes = <List<String>>[];
  Completer<void>? blockedRead;
  Completer<void>? blockedWrite;
  bool failWrites = false;

  /// 只让满足条件的这一次写入失败（用于“append 成功、随后 delete 写失败”这类序列）。
  bool Function(List<String> entries)? writeFailure;

  List<String> get persisted => List<String>.of(_entries);

  @override
  Future<List<String>> read() async {
    final gate = blockedRead;
    if (gate != null) await gate.future;
    return List<String>.of(_entries);
  }

  @override
  Future<void> write(List<String> entries) async {
    final gate = blockedWrite;
    if (gate != null) await gate.future;
    final failure = writeFailure;
    if (failWrites || (failure != null && failure(List<String>.of(entries)))) {
      throw const AiReviewHistoryStoreException('storage blocked');
    }
    _entries = List<String>.of(entries);
    writes.add(List<String>.of(entries));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'same natural period makes one upstream request and one archive entry',
    () async {
      final store = _FakeHistoryStore();
      final service = _service(store: store);
      addTearDown(service.dispose);
      final gate = Completer<void>();
      var calls = 0;
      service.attachClient(
        _apiClient(
          MockClient((request) async {
            calls++;
            await gate.future;
            return _chatResponse('本周解读正文');
          }),
        ),
      );
      final week = _weekContext();

      final first = service.personalizedReportReview(
        periodLabel: '本周',
        reportMarkdown: '# 本周',
        reportContext: week,
        dataThrough: DateTime(2026, 5, 26),
      );
      final second = service.personalizedReportReview(
        periodLabel: '本周',
        reportMarkdown: '# 本周',
        reportContext: week,
        dataThrough: DateTime(2026, 5, 27),
      );

      expect(identical(first, second), isTrue);
      expect(service.reportJobFor(week)?.phase, AiReportReviewPhase.generating);
      gate.complete();

      expect(await first, '本周解读正文');
      expect(await second, '本周解读正文');
      expect(calls, 1);
      expect(store.persisted, hasLength(1));
      expect(service.reportHistoryFor(week), hasLength(1));
      expect(service.reportJobFor(week), isNull);
      expect(
        service.reportHistoryFor(week).single.kind,
        AiService.statisticsReportKind,
      );
    },
  );

  test('regeneration appends a version inside its own period group', () async {
    final store = _FakeHistoryStore();
    final service = _service(store: store);
    addTearDown(service.dispose);
    service.attachClient(
      _apiClient(
        MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final user = (body['user'] ?? '').toString();
          return _chatResponse(user.contains('第二次') ? '第二次解读' : '第一次解读');
        }),
      ),
    );
    final week = _weekContext();
    final month = _monthContext();

    final first = await service.personalizedReportReview(
      periodLabel: '本周',
      reportMarkdown: '第一次',
      reportContext: week,
      dataThrough: DateTime(2026, 5, 26),
    );
    final second = await service.personalizedReportReview(
      periodLabel: '本周',
      reportMarkdown: '第二次',
      reportContext: week,
      dataThrough: DateTime(2026, 5, 27),
    );
    final monthly = await service.personalizedReportReview(
      periodLabel: '本月',
      reportMarkdown: '月度',
      reportContext: month,
      dataThrough: DateTime(2026, 5, 20),
    );

    expect(first, '第一次解读');
    expect(second, '第二次解读');
    expect(monthly, '第一次解读');
    expect(service.reportHistoryFor(week), hasLength(2));
    expect(service.reportHistoryFor(week).first.content, '第二次解读');
    expect(
      service.reportHistoryFor(week).first.dataThrough,
      DateTime.utc(2026, 5, 27),
    );
    expect(service.reportHistoryFor(month), hasLength(1));
    expect(
      service.reportContexts.map((context) => context.key),
      containsAll(<String>[week.key, month.key]),
    );
  });

  test(
    'out-of-order completions stay in their captured period group',
    () async {
      final store = _FakeHistoryStore();
      final service = _service(store: store);
      addTearDown(service.dispose);
      final monthGate = Completer<void>();
      service.attachClient(
        _apiClient(
          MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final user = (body['user'] ?? '').toString();
            if (user.contains('MONTH')) {
              await monthGate.future;
              return _chatResponse('月解读');
            }
            return _chatResponse('周解读');
          }),
        ),
      );
      final week = _weekContext();
      final month = _monthContext();

      final monthFuture = service.personalizedReportReview(
        periodLabel: '本月',
        reportMarkdown: 'MONTH',
        reportContext: month,
        dataThrough: DateTime(2026, 5, 20),
      );
      final weekResult = await service.personalizedReportReview(
        periodLabel: '本周',
        reportMarkdown: 'WEEK',
        reportContext: week,
        dataThrough: DateTime(2026, 5, 26),
      );

      expect(weekResult, '周解读');
      expect(service.reportJobFor(week), isNull);
      expect(
        service.reportJobFor(month)?.phase,
        AiReportReviewPhase.generating,
      );

      monthGate.complete();
      expect(await monthFuture, '月解读');
      expect(service.reportHistoryFor(week).single.content, '周解读');
      expect(service.reportHistoryFor(month).single.content, '月解读');
      expect(service.reportJobFor(month), isNull);
    },
  );

  test(
    'each period keeps up to 50 entries without evicting other periods',
    () async {
      final store = _FakeHistoryStore();
      final service = _service(store: store);
      addTearDown(service.dispose);
      var calls = 0;
      service.attachClient(
        _apiClient(
          MockClient((request) async {
            calls++;
            return _chatResponse('解读 $calls');
          }),
        ),
      );
      final week = _weekContext();
      final month = _monthContext();

      for (var index = 1; index <= 51; index++) {
        await service.personalizedReportReview(
          periodLabel: '本周',
          reportMarkdown: '# $index',
          reportContext: week,
          dataThrough: DateTime(2026, 5, 26),
        );
      }
      await service.personalizedReportReview(
        periodLabel: '本月',
        reportMarkdown: '# month',
        reportContext: month,
        dataThrough: DateTime(2026, 5, 20),
      );

      final weekly = service.reportHistoryFor(week);
      expect(weekly, hasLength(AiService.maxReviewEntriesPerGroup));
      expect(weekly.map((entry) => entry.content), isNot(contains('解读 1')));
      expect(weekly.map((entry) => entry.content), contains('解读 51'));
      expect(service.reportHistoryFor(month), hasLength(1));
      expect(service.reviewHistory, hasLength(51));
      expect(store.persisted, hasLength(51));
    },
  );

  test('archived reports survive a fresh service load', () async {
    final week = _weekContext();
    final service = _service();
    addTearDown(service.dispose);
    service.attachClient(
      _apiClient(MockClient((request) async => _chatResponse('重启前解读'))),
    );

    await service.personalizedReportReview(
      periodLabel: '本周',
      reportMarkdown: '# 本周',
      reportContext: week,
      dataThrough: DateTime(2026, 5, 26),
    );
    final raw =
        (await SharedPreferences.getInstance()).getStringList(
          AiReviewHistoryStore.key,
        ) ??
        const <String>[];
    expect(raw, hasLength(1));

    final restarted = AiService();
    addTearDown(restarted.dispose);
    await restarted.loadFromStorage();

    final history = restarted.reportHistoryFor(week);
    expect(history, hasLength(1));
    expect(history.single.content, '重启前解读');
    expect(history.single.reportContext, week);
    expect(history.single.dataThrough, DateTime.utc(2026, 5, 26));
    expect(restarted.reportContexts.map((context) => context.key), [week.key]);

    // 模拟进程/偏好缓存重置：只保留磁盘上的内容。
    SharedPreferences.setMockInitialValues({'ai_review_history': raw});
    final rehydrated = AiService();
    addTearDown(rehydrated.dispose);
    await rehydrated.loadFromStorage();
    expect(rehydrated.reportHistoryFor(week), hasLength(1));
  });

  test(
    'old entries stay readable and malformed metadata never drops content',
    () {
      final legacy = AiReviewEntry.fromJson({
        'id': 'legacy-weekly',
        'createdAt': DateTime(2026, 5, 22, 10).toIso8601String(),
        'content': '旧内容',
        'summary': '本周数据：完成 1 / 2 项待办',
        'model': 'gpt-test',
      });
      expect(legacy.content, '旧内容');
      expect(legacy.reportContext, isNull);
      expect(legacy.dataThrough, isNull);
      expect(legacy.toJson().containsKey('reportContext'), isFalse);

      final corrupted = AiReviewEntry.fromJson({
        'id': 'broken-metadata',
        'createdAt': DateTime(2026, 5, 22, 10).toIso8601String(),
        'content': '正文必须保留',
        'summary': '统计报告 AI 解读：本周',
        'kind': AiService.statisticsReportKind,
        'reportContext': {'period': 'week'},
        'dataThrough': 'not-a-date',
      });
      expect(corrupted.content, '正文必须保留');
      expect(corrupted.reportContext, isNull);
      expect(corrupted.dataThrough, isNull);

      final week = _weekContext();
      final entry = AiReviewEntry(
        id: 'new-entry',
        createdAt: DateTime(2026, 5, 26, 9),
        content: '新内容',
        summary: '统计报告 AI 解读：本周',
        kind: AiService.statisticsReportKind,
        reportContext: week,
        dataThrough: DateTime(2026, 5, 26),
      );
      final restored = AiReviewEntry.fromJson(entry.toJson());
      expect(restored.reportContext, week);
      expect(restored.dataThrough, DateTime.utc(2026, 5, 26));
      expect(restored.content, '新内容');
    },
  );

  test(
    'legacy weekly review stays a normal entry without period metadata',
    () async {
      final store = _FakeHistoryStore();
      final service = _service(store: store);
      addTearDown(service.dispose);
      var calls = 0;
      service.attachClient(
        _apiClient(
          MockClient((request) async {
            calls++;
            return _chatResponse(_structuredWeeklyReview);
          }),
        ),
      );

      await service.weeklyReview(
        completedTodos: 1,
        totalTodos: 2,
        weeklyFocusMinutes: 30,
        habitStreak: 3,
        periodLabel: '上周',
        now: DateTime(2026, 5, 25, 9),
      );

      expect(calls, 1);
      expect(store.persisted, hasLength(1));
      expect(service.reviewHistory.single.kind, AiService.weeklyReviewKind);
      expect(service.reviewHistory.single.reportContext, isNull);
      expect(service.reportContexts, isEmpty);
    },
  );

  test('reset while a response is in flight never recreates history', () async {
    final store = _FakeHistoryStore();
    final service = _service(store: store);
    addTearDown(service.dispose);
    final gate = Completer<void>();
    service.attachClient(
      _apiClient(
        MockClient((request) async {
          await gate.future;
          return _chatResponse('旧账号晚到解读');
        }),
      ),
    );
    final week = _weekContext();

    final future = service.personalizedReportReview(
      periodLabel: '本周',
      reportMarkdown: '# 本周',
      reportContext: week,
      dataThrough: DateTime(2026, 5, 26),
    );
    await pumpEventQueue();
    expect(service.reportJobFor(week)?.phase, AiReportReviewPhase.generating);

    service.resetLocalState();
    expect(service.reportJobFor(week), isNull);
    gate.complete();

    await expectLater(
      future,
      throwsA(
        isA<AiException>().having(
          (error) => error.message,
          'message',
          _sessionChanged(),
        ),
      ),
    );
    expect(service.reviewHistory, isEmpty);
    expect(store.persisted, isEmpty);
    expect(store.writes, isEmpty);
  });

  test('clearing history invalidates the in-flight generation', () async {
    final store = _FakeHistoryStore();
    final service = _service(store: store);
    addTearDown(service.dispose);
    final gate = Completer<void>();
    service.attachClient(
      _apiClient(
        MockClient((request) async {
          await gate.future;
          return _chatResponse('清空后晚到解读');
        }),
      ),
    );
    final week = _weekContext();

    final future = service.personalizedReportReview(
      periodLabel: '本周',
      reportMarkdown: '# 本周',
      reportContext: week,
      dataThrough: DateTime(2026, 5, 26),
    );
    await pumpEventQueue();
    await service.clearReviewHistory();
    expect(store.persisted, isEmpty);

    gate.complete();
    await expectLater(future, throwsA(isA<AiException>()));
    await service.waitForHistoryWrites();

    expect(service.reviewHistory, isEmpty);
    expect(service.reportJobFor(week), isNull);
    expect(store.persisted, isEmpty);
  });

  test('account data generation invalidates a late response', () async {
    final store = _FakeHistoryStore();
    final service = _service(store: store);
    addTearDown(service.dispose);
    final gate = Completer<void>();
    service.attachClient(
      _apiClient(
        MockClient((request) async {
          await gate.future;
          return _chatResponse('切号后晚到解读');
        }),
      ),
    );
    final week = _weekContext();

    final future = service.personalizedReportReview(
      periodLabel: '本周',
      reportMarkdown: '# 本周',
      reportContext: week,
      dataThrough: DateTime(2026, 5, 26),
    );
    await pumpEventQueue();
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    gate.complete();

    await expectLater(future, throwsA(isA<AiException>()));
    expect(service.reviewHistory, isEmpty);
    expect(store.persisted, isEmpty);
  });

  test(
    'a write landing after reset is repaired instead of resurrecting data',
    () async {
      final store = _FakeHistoryStore();
      final service = _service(store: store);
      addTearDown(service.dispose);
      service.attachClient(
        _apiClient(MockClient((request) async => _chatResponse('待存档解读'))),
      );
      final week = _weekContext();
      store.blockedWrite = Completer<void>();

      final future = service.personalizedReportReview(
        periodLabel: '本周',
        reportMarkdown: '# 本周',
        reportContext: week,
        dataThrough: DateTime(2026, 5, 26),
      );
      await pumpEventQueue();
      expect(service.reportJobFor(week)?.phase, AiReportReviewPhase.saving);

      service.resetLocalState();
      final gate = store.blockedWrite!;
      store.blockedWrite = null;
      gate.complete();

      await expectLater(future, throwsA(isA<AiException>()));
      await service.waitForHistoryWrites();

      expect(service.reviewHistory, isEmpty);
      expect(store.persisted, isEmpty);
    },
  );

  test('waitForHistoryWrites drains the serialized queue', () async {
    final store = _FakeHistoryStore();
    final service = _service(store: store);
    addTearDown(service.dispose);
    service.attachClient(
      _apiClient(MockClient((request) async => _chatResponse('排空解读'))),
    );
    final week = _weekContext();
    store.blockedWrite = Completer<void>();

    final review = service.personalizedReportReview(
      periodLabel: '本周',
      reportMarkdown: '# 本周',
      reportContext: week,
      dataThrough: DateTime(2026, 5, 26),
    );
    await pumpEventQueue();
    var drained = false;
    final wait = service.waitForHistoryWrites().then((_) => drained = true);
    await pumpEventQueue();
    expect(drained, isFalse);

    final gate = store.blockedWrite!;
    store.blockedWrite = null;
    gate.complete();
    expect(await review, '排空解读');
    await wait;
    expect(drained, isTrue);
    expect(store.persisted, hasLength(1));
  });

  test(
    'failed archive keeps unsaved content and retries storage only',
    () async {
      final store = _FakeHistoryStore()..failWrites = true;
      final service = _service(store: store);
      addTearDown(service.dispose);
      var calls = 0;
      service.attachClient(
        _apiClient(
          MockClient((request) async {
            calls++;
            return _chatResponse('生成成功但存档失败');
          }),
        ),
      );
      final week = _weekContext();

      final content = await service.personalizedReportReview(
        periodLabel: '本周',
        reportMarkdown: '# 本周',
        reportContext: week,
        dataThrough: DateTime(2026, 5, 26),
      );

      expect(content, '生成成功但存档失败');
      expect(service.reviewHistory, isEmpty);
      expect(store.persisted, isEmpty);
      final failed = service.reportJobFor(week);
      expect(failed, isNotNull);
      expect(failed!.phase, AiReportReviewPhase.failed);
      expect(failed.isRunning, isFalse);
      expect(failed.unsavedContent, content);
      expect(failed.error, I18n.tr('statistics.ai.error.archive_failed'));
      expect(service.reportContexts.map((context) => context.key), [week.key]);

      store.failWrites = false;
      await service.retryReportArchive(week);

      expect(calls, 1);
      expect(service.reportJobFor(week), isNull);
      expect(service.reportHistoryFor(week), hasLength(1));
      expect(service.reportHistoryFor(week).single.content, content);
      expect(store.persisted, hasLength(1));

      // 没有待保存正文时重试保存是空操作，不会凭空生成条目。
      await service.retryReportArchive(_monthContext());
      expect(service.reviewHistory, hasLength(1));
    },
  );

  test('an empty model response never becomes an archive entry', () async {
    final store = _FakeHistoryStore();
    final service = _service(store: store);
    addTearDown(service.dispose);
    service.attachClient(
      _apiClient(MockClient((request) async => _chatResponse('   '))),
    );
    final week = _weekContext();

    await expectLater(
      service.personalizedReportReview(
        periodLabel: '本周',
        reportMarkdown: '# 本周',
        reportContext: week,
        dataThrough: DateTime(2026, 5, 26),
      ),
      throwsA(
        isA<AiException>().having(
          (error) => error.message,
          'message',
          contains('未返回正文'),
        ),
      ),
    );

    expect(service.reviewHistory, isEmpty);
    expect(service.reportHistoryFor(week), isEmpty);
    expect(store.persisted, isEmpty);
    // 失败的任务留在原周期上供内联展示，但没有可存档正文、也不进历史选择器。
    final failed = service.reportJobFor(week);
    expect(failed?.phase, AiReportReviewPhase.failed);
    expect(failed?.unsavedContent, isNull);
    expect(failed?.error, contains('未返回正文'));
    expect(service.reportContexts, isEmpty);
  });

  test(
    'a queued append does not drop records loaded by a concurrent load',
    () async {
      final week = _weekContext();
      final seeded = AiReviewEntry(
        id: 'seeded',
        createdAt: DateTime(2026, 5, 24, 10),
        content: '已有历史',
        summary: '本周数据：完成 1 / 1 项待办',
        kind: AiService.weeklyReviewKind,
      );
      final store = _FakeHistoryStore(initial: [jsonEncode(seeded.toJson())]);
      final service = _service(store: store);
      addTearDown(service.dispose);
      service.attachClient(
        _apiClient(MockClient((request) async => _chatResponse('新解读'))),
      );

      final readGate = Completer<void>();
      store.blockedRead = readGate;
      final load = service.loadFromStorage();
      final review = service.personalizedReportReview(
        periodLabel: '本周',
        reportMarkdown: '# 本周',
        reportContext: week,
        dataThrough: DateTime(2026, 5, 26),
      );
      await pumpEventQueue();
      store.blockedRead = null;
      readGate.complete();

      await load;
      expect(await review, '新解读');

      expect(service.reviewHistory, hasLength(2));
      expect(store.persisted, hasLength(2));
      expect(service.reportHistoryFor(week), hasLength(1));

      final reloaded = _FakeHistoryStore(initial: store.persisted);
      final other = _service(store: reloaded);
      addTearDown(other.dispose);
      await other.loadFromStorage();
      expect(other.reviewHistory, hasLength(2));
    },
  );

  test(
    'default preferences store round-trips the account history key',
    () async {
      final store = SharedPreferencesAiReviewHistoryStore();

      expect(await store.read(), isEmpty);
      await store.write(const ['first', 'second']);
      expect(await store.read(), ['first', 'second']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(AiReviewHistoryStore.key), [
        'first',
        'second',
      ]);
    },
  );

  test(
    'delete queued behind a blocked load still removes the stored row',
    () async {
      const storedId = 'stored-row';
      final seeded = AiReviewEntry(
        id: storedId,
        createdAt: DateTime(2026, 5, 20, 10),
        content: '已存在的历史',
        summary: '本周数据：完成 1 / 1 项待办',
        kind: AiService.weeklyReviewKind,
      );
      final store = _FakeHistoryStore(initial: [jsonEncode(seeded.toJson())]);
      final service = _service(store: store);
      addTearDown(service.dispose);

      final readGate = Completer<void>();
      store.blockedRead = readGate;
      final load = service.loadFromStorage();
      final deletion = service.deleteReview(storedId);
      await pumpEventQueue();
      store.blockedRead = null;
      readGate.complete();

      await load;
      await deletion;

      expect(service.reviewHistory.where((e) => e.id == storedId), isEmpty);
      expect(store.persisted.where((e) => e.contains(storedId)), isEmpty);
      expect(store.persisted, isEmpty);
    },
  );

  test(
    'a failed delete write keeps the row appended after it was queued',
    () async {
      const oldId = 'old-row';
      final seeded = AiReviewEntry(
        id: oldId,
        createdAt: DateTime(2026, 5, 20, 10),
        content: '旧历史',
        summary: '本周数据：完成 1 / 1 项待办',
        kind: AiService.weeklyReviewKind,
      );
      final store = _FakeHistoryStore(initial: [jsonEncode(seeded.toJson())]);
      final service = _service(store: store);
      addTearDown(service.dispose);
      service.attachClient(
        _apiClient(MockClient((request) async => _chatResponse('新解读'))),
      );
      await service.loadFromStorage();

      final week = _weekContext();
      final writeGate = Completer<void>();
      store.blockedWrite = writeGate;
      final review = service.personalizedReportReview(
        periodLabel: '本周',
        reportMarkdown: '# 本周',
        reportContext: week,
        dataThrough: DateTime(2026, 5, 26),
      );
      await pumpEventQueue();

      // append 还在写入时排队删除旧行；只有 append 落盘后 delete 才轮到写。
      final deletion = service.deleteReview(oldId);
      await pumpEventQueue();
      store.writeFailure = (entries) =>
          entries.every((entry) => !entry.contains(oldId));
      store.blockedWrite = null;
      writeGate.complete();

      expect(await review, '新解读');
      await expectLater(
        deletion,
        throwsA(isA<AiReviewHistoryStoreException>()),
      );

      // 回滚只回到队列内的最新列表：新行仍在，内存与磁盘一致。
      expect(service.reviewHistory, hasLength(2));
      expect(service.reviewHistory.first.content, '新解读');
      expect(store.persisted, hasLength(2));
      expect(store.persisted.where((e) => e.contains('新解读')), hasLength(1));

      // 恢复写入后重删旧行：新行不会丢，磁盘与内存一致。
      store.writeFailure = null;
      await service.deleteReview(oldId);
      expect(service.reviewHistory.single.content, '新解读');
      expect(store.persisted.single, contains('新解读'));
      expect(store.persisted.where((e) => e.contains(oldId)), isEmpty);
    },
  );

  test('repeated archive retries never create a second entry', () async {
    final store = _FakeHistoryStore();
    final service = _service(store: store);
    addTearDown(service.dispose);
    var calls = 0;
    service.attachClient(
      _apiClient(
        MockClient((request) async {
          calls++;
          return _chatResponse('生成成功但存档失败');
        }),
      ),
    );
    final week = _weekContext();

    store.failWrites = true;
    final content = await service.personalizedReportReview(
      periodLabel: '本周',
      reportMarkdown: '# 本周',
      reportContext: week,
      dataThrough: DateTime(2026, 5, 26),
    );
    expect(content, '生成成功但存档失败');
    expect(service.reviewHistory, isEmpty);
    expect(store.persisted, isEmpty);

    // 第一次重试写入失败：待保存条目的身份必须留给后续重试复用。
    final attemptedIds = <String>[];
    var failNextRetry = true;
    store.failWrites = false;
    store.writeFailure = (entries) {
      attemptedIds.add(_entryIdIn(entries));
      return failNextRetry;
    };
    await expectLater(
      service.retryReportArchive(week),
      throwsA(isA<AiReviewHistoryStoreException>()),
    );
    expect(attemptedIds, hasLength(1));
    expect(service.reviewHistory, isEmpty);
    expect(service.reportJobFor(week)?.phase, AiReportReviewPhase.failed);

    // 阻塞中的重复点击共享同一个 Future：只会发生一次写入。
    failNextRetry = false;
    final gate = Completer<void>();
    store.blockedWrite = gate;
    final first = service.retryReportArchive(week);
    final second = service.retryReportArchive(week);
    expect(identical(first, second), isTrue);
    await pumpEventQueue();
    store.blockedWrite = null;
    gate.complete();
    await first;
    await second;

    expect(calls, 1);
    expect(service.reportJobFor(week), isNull);
    expect(service.reviewHistory, hasLength(1));
    expect(service.reportHistoryFor(week), hasLength(1));
    expect(store.persisted, hasLength(1));
    // 同一次生成只有一个条目身份：两次尝试用的是同一个 id。
    expect(attemptedIds, hasLength(2));
    expect(attemptedIds.toSet(), hasLength(1));
    expect(_entryIdIn(store.persisted), attemptedIds.first);
  });
}
