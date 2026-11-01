import 'dart:convert';

import 'package:duoyi/core/statistics_period.dart';
import 'package:duoyi/models/ai_report_context.dart';
import 'package:duoyi/models/server_config_status.dart';
import 'package:duoyi/services/ai_review_history_store.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只保存内存里的历史条目：配置状态测试不需要真实持久化。
class _MemoryHistoryStore extends AiReviewHistoryStore {
  _MemoryHistoryStore(this.entries);

  List<String> entries;
  int writeCount = 0;

  @override
  Future<List<String>> read() async => List<String>.of(entries);

  @override
  Future<void> write(List<String> next) async {
    writeCount++;
    entries = List<String>.of(next);
  }
}

AiReportContext _weekContext() => AiReportContext(
  period: StatisticsPeriod.week,
  start: DateTime(2026, 10, 19),
  end: DateTime(2026, 10, 25),
  timeZone: 'Asia/Shanghai',
);

List<AiReviewEntry> _entries() {
  final week = _weekContext();
  return <AiReviewEntry>[
    AiReviewEntry(
      id: 'e-week',
      createdAt: DateTime(2026, 10, 21, 9),
      content: 'WEEK-ARCHIVED',
      summary: '本周存档',
      model: 'test-model',
      kind: AiService.statisticsReportKind,
      reportContext: week,
      dataThrough: week.start,
    ),
    AiReviewEntry(
      id: 'e-legacy',
      createdAt: DateTime(2026, 10, 1, 9),
      content: 'LEGACY-ARCHIVED',
      summary: '旧版记录',
      model: 'test-model',
    ),
  ];
}

Future<AiService> _loadedService(_MemoryHistoryStore store) async {
  final ai = AiService(historyStore: store);
  await ai.loadFromStorage();
  return ai;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('初始 unknown 不可用；非空配置 ready 后按 ai_enabled 决定', () {
    final ai = AiService(historyStore: _MemoryHistoryStore(<String>[]));
    addTearDown(ai.dispose);

    expect(ai.configStatus, ServerConfigStatus.unknown);
    expect(ai.enabled, isFalse);
    expect(ai.isConfigured, isFalse);

    ai.updateFromServerConfig(<String, dynamic>{
      'ai_enabled': true,
      'ai_model': 'cfg-model',
    });
    expect(ai.configStatus, ServerConfigStatus.ready);
    expect(ai.enabled, isTrue);
    expect(ai.isConfigured, isTrue);
    expect(ai.model, 'cfg-model');

    ai.updateFromServerConfig(<String, dynamic>{
      'ai_enabled': false,
      'ai_model': 'cfg-model',
    });
    expect(ai.configStatus, ServerConfigStatus.ready);
    expect(ai.enabled, isFalse, reason: 'ready 但管理员关闭时不可用');
    expect(ai.model, 'cfg-model', reason: '关闭开关不清模型信息');

    // 非空 map 即使缺少 ai_enabled 也只按“关闭”处理，仍是 ready。
    ai.updateFromServerConfig(<String, dynamic>{'ai_model': 'cfg-model'});
    expect(ai.configStatus, ServerConfigStatus.ready);
    expect(ai.enabled, isFalse);
  });

  test('loading/failed 期间不可用，ready 恢复此前配置', () {
    final ai = AiService(historyStore: _MemoryHistoryStore(<String>[]));
    addTearDown(ai.dispose);

    ai.updateFromServerConfig(<String, dynamic>{
      'ai_enabled': true,
      'ai_model': 'cfg-model',
    });
    expect(ai.enabled, isTrue);

    ai.updateServerConfigStatus(ServerConfigStatus.loading);
    expect(ai.configStatus, ServerConfigStatus.loading);
    expect(ai.enabled, isFalse, reason: 'loading 不能被当成可用');

    ai.updateServerConfigStatus(ServerConfigStatus.failed);
    expect(ai.configStatus, ServerConfigStatus.failed);
    expect(ai.enabled, isFalse, reason: 'failed 不能被当成可用');
    expect(ai.model, 'cfg-model', reason: '失败保留同连接上一次成功的配置');

    ai.updateServerConfigStatus(ServerConfigStatus.ready);
    expect(ai.configStatus, ServerConfigStatus.ready);
    expect(ai.enabled, isTrue, reason: 'ready 后恢复此前拿到的开关');
    expect(ai.model, 'cfg-model');

    // 反过来：关闭后的 loading/failed 也不能被误解成可用。
    ai.updateFromServerConfig(<String, dynamic>{'ai_enabled': false});
    ai.updateServerConfigStatus(ServerConfigStatus.failed);
    expect(ai.enabled, isFalse);
    ai.updateServerConfigStatus(ServerConfigStatus.ready);
    expect(ai.enabled, isFalse);
  });

  test('empty 配置回到 unknown 并清空模型，已加载历史保留', () async {
    final store = _MemoryHistoryStore(<String>[
      for (final entry in _entries()) jsonEncode(entry.toJson()),
    ]);
    final ai = await _loadedService(store);
    addTearDown(ai.dispose);

    expect(ai.reviewHistory, hasLength(2));
    ai.updateFromServerConfig(<String, dynamic>{
      'ai_enabled': true,
      'ai_model': 'cfg-model',
    });
    expect(ai.enabled, isTrue);

    ai.updateFromServerConfig(const <String, dynamic>{});
    expect(ai.configStatus, ServerConfigStatus.unknown);
    expect(ai.enabled, isFalse);
    expect(ai.model, isEmpty, reason: '切连接/登出后不再保留旧模型');
    expect(ai.reviewHistory, hasLength(2), reason: '配置清空不删历史');
    expect(ai.reportHistoryFor(_weekContext()), hasLength(1));
  });

  test('配置状态变化不丢已加载历史，也不写盘', () async {
    final store = _MemoryHistoryStore(<String>[
      for (final entry in _entries()) jsonEncode(entry.toJson()),
    ]);
    final ai = await _loadedService(store);
    addTearDown(ai.dispose);

    final before = ai.reviewHistory;
    final writesBefore = store.writeCount;

    for (final status in const [
      ServerConfigStatus.loading,
      ServerConfigStatus.failed,
      ServerConfigStatus.ready,
      ServerConfigStatus.unknown,
    ]) {
      ai.updateServerConfigStatus(status);
      expect(ai.reviewHistory, hasLength(before.length), reason: status.name);
      expect(
        ai.reviewHistory.map((entry) => entry.id),
        before.map((entry) => entry.id),
        reason: '${status.name} 不得改动历史顺序或内容',
      );
    }

    ai.updateFromServerConfig(<String, dynamic>{'ai_enabled': true});
    ai.updateFromServerConfig(const <String, dynamic>{});
    expect(ai.reviewHistory, hasLength(2));
    expect(ai.reportHistoryFor(_weekContext()), hasLength(1));
    expect(store.writeCount, writesBefore, reason: '配置变化不是一次历史写入');
  });
}
