import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/ai_todo_breakdown.dart';
import '../core/app_clock.dart';
import '../core/app_config.dart';
import '../core/diary_deep_review.dart';
import '../core/i18n.dart';
import '../core/local_timezone_resolver.dart';
import '../core/smart_date_parser.dart';
import '../core/smart_todo_draft.dart';
import '../core/statistics_period.dart';
import '../core/web_target.dart';
import '../models/ai_report_context.dart';
import '../models/diary_entry.dart';
import '../models/goal.dart'
    show
        ReminderConfig,
        ReminderKind,
        ReminderPlan,
        ReminderRule,
        ReminderRuleType;
import '../models/server_config_status.dart';
import '../models/todo.dart';
import 'account_local_data_cleaner.dart';
import 'ai_review_history_store.dart';
import 'api_client.dart';
import 'local_ai_client.dart';
import 'local_ai_config_store.dart';

/// AI 客户端：**不再持有任何 key/base_url**，所有调用通过 `/api/ai/chat`
/// 由已登录用户的 token 代理到管理员在服务端配置好的上游。
///
/// `enabled` 状态来自 `/api/config`。
class AiService extends ChangeNotifier {
  AiService({
    AiReviewHistoryStore? historyStore,
    LocalAiConfigStore? localConfigStore,
    http.Client? localHttpClient,
  }) : _historyStore = historyStore ?? SharedPreferencesAiReviewHistoryStore(),
       _localStore = localConfigStore ?? SecureLocalAiConfigStore(),
       _localClient = LocalAiClient(client: localHttpClient);

  /// 历史只读写 `ai_review_history` 这一个账号私有键。
  final AiReviewHistoryStore _historyStore;
  ApiClient _client = ApiClient();
  bool _enabled = false;
  String _model = '';
  ServerConfigStatus _configStatus = ServerConfigStatus.unknown;
  List<AiReviewEntry> _reviewHistory = [];

  /// 周期解读任务只存在内存：应用存活期间独立于统计页运行，退出后不恢复，
  /// 也不代表服务端或操作系统在后台继续执行。
  final Map<String, AiReportReviewJob> _reportJobs = {};
  final Map<String, _ScopedReportDraft> _reportDrafts = {};
  final Map<String, Future<String>> _reportRequests = {};

  /// 存档重试单飞：同一周期的重复“仅重试保存”共享同一个 Future。
  final Map<String, Future<void>> _reportRetries = {};

  /// 待保存条目的稳定身份：重试复用同一条，避免同一次生成被存成多个版本。
  final Map<String, AiReviewEntry> _reportPendingArchives = {};

  /// 历史读写串行队列：load/append/delete/clear 不会互相覆盖。
  Future<void> _historyTail = Future<void>.value();
  int _storageGeneration = 0;
  int _requestGeneration = 0;
  int _localMutation = 0;
  int _localClearGeneration = 0;
  bool _remoteAccountActive = true;
  bool _disposed = false;
  final LocalAiConfigStore _localStore;
  final LocalAiClient _localClient;
  LocalAiConfig _localConfig = const LocalAiConfig();
  bool _localConfigLoaded = false;
  String? _localConfigError;
  Future<void>? _localLoad;
  Future<void> _localWriteQueue = Future<void>.value();
  String? _boundClientIdentity;

  /// `/api/config` 的拉取状态：unknown/loading/failed 时不得显示成管理员关闭。
  ServerConfigStatus get configStatus => _configStatus;

  /// 远端账号跟随 `/api/config`；原生未登录改用设备独立的本地连接。
  bool get supportsLocalConfiguration => !WebTarget.isWebBuild;
  bool get usingLocalConfiguration =>
      supportsLocalConfiguration && !_remoteAccountActive;

  /// 只有拿到真实配置且管理员开启过才算可用；本地模式只看设备连接本身。
  bool get enabled => usingLocalConfiguration
      ? _localConfigLoaded && _localConfig.enabled && _validLocalConfiguration
      : _configStatus == ServerConfigStatus.ready && _enabled;
  bool get isConfigured => usingLocalConfiguration
      ? _localConfigLoaded && _validLocalConfiguration
      : enabled;
  String get model => usingLocalConfiguration ? _localConfig.model : _model;
  LocalAiConfig get localConfig => _localConfig;
  bool get localConfigLoaded => _localConfigLoaded;
  String? get localConfigError => _localConfigError;
  List<AiReviewEntry> get reviewHistory => List.unmodifiable(_reviewHistory);

  bool get _validLocalConfiguration {
    try {
      LocalAiClient.endpointFor(_localConfig.baseUrl);
      return _localConfig.model.trim().isNotEmpty;
    } on LocalAiError {
      return false;
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void setRemoteAccountActive(bool active) {
    if (_remoteAccountActive == active) return;
    _remoteAccountActive = active;
    resetLocalState();
    if (usingLocalConfiguration) unawaited(loadLocalConfiguration());
  }

  static const weeklyReviewKind = 'weekly_review';

  /// 新统计报告条目的显式类型；旧条目没有该字段仍然有效。
  static const statisticsReportKind = 'statistics_report';

  /// 每个自然周期存档组最多保留 50 条；无周期元数据的老记录共用原有 50 条池。
  static const maxReviewEntriesPerGroup = 50;

  static const _unscopedPoolKey = 'legacy:unscoped';

  void attachClient(ApiClient client) {
    final identity = '${client.baseUrl}\n${client.token ?? ''}';
    if (!identical(_client, client) || identity != _boundClientIdentity) {
      _requestGeneration++;
    }
    _client = client;
    _boundClientIdentity = identity;
  }

  /// 收到服务端配置：非空 map 视为一次成功读取（置 ready 再更新开关），
  /// 空 map 表示连接已切换/登出，回到 unknown 并清除模型信息。
  ///
  /// 配置刷新不触碰报告历史、进行中的解读任务或模型预算。
  void updateFromServerConfig(Map<String, dynamic> cfg) {
    if (cfg.isEmpty) {
      if (_configStatus == ServerConfigStatus.unknown &&
          !_enabled &&
          _model.isEmpty) {
        return;
      }
      _configStatus = ServerConfigStatus.unknown;
      _enabled = false;
      _model = '';
      if (!usingLocalConfiguration) _requestGeneration++;
      _changed();
      return;
    }
    final nextEnabled = cfg['ai_enabled'] == true;
    final nextModel = (cfg['ai_model'] ?? '').toString();
    if (_configStatus == ServerConfigStatus.ready &&
        _enabled == nextEnabled &&
        _model == nextModel) {
      return;
    }
    _configStatus = ServerConfigStatus.ready;
    _enabled = nextEnabled;
    _model = nextModel;
    if (!usingLocalConfiguration) _requestGeneration++;
    _changed();
  }

  /// 只更新配置拉取状态（loading / failed / unknown / ready）。
  ///
  /// 与 [updateFromServerConfig] 分开，这样 AuthProvider 可以在拿到 map 之前/之后
  /// 如实广播状态，而不会把 unknown/failed 误判成「管理员关闭 AI」。
  void updateServerConfigStatus(ServerConfigStatus status) {
    if (_configStatus == status) return;
    _configStatus = status;
    _changed();
  }

  Future<void> loadLocalConfiguration() {
    if (!supportsLocalConfiguration || _localConfigLoaded || _disposed) {
      return Future<void>.value();
    }
    final existing = _localLoad;
    if (existing != null) return existing;
    final serial = _localMutation;
    final future = () async {
      try {
        final config = await _localStore.read();
        if (serial != _localMutation || _disposed) return;
        _localConfig = config;
        _localConfigLoaded = true;
        _localConfigError = null;
      } catch (_) {
        if (serial != _localMutation || _disposed) return;
        _localConfig = const LocalAiConfig();
        _localConfigError = I18n.tr('ai.local.error_storage');
      }
      _changed();
    }();
    _localLoad = future;
    return future.whenComplete(() {
      if (identical(_localLoad, future)) _localLoad = null;
    });
  }

  Future<void> _requireLocalMode() async {
    if (!usingLocalConfiguration || _disposed) {
      throw AiException(I18n.tr('ai.local.unavailable'));
    }
    await loadLocalConfiguration();
    if (!usingLocalConfiguration || _disposed) {
      throw AiException(I18n.tr('ai.local.changed'));
    }
    if (!_localConfigLoaded) {
      throw AiException(I18n.tr('ai.local.error_storage'));
    }
  }

  LocalAiConfig _draftConfiguration({
    required bool enabled,
    required String baseUrl,
    required String model,
    String? apiKey,
  }) {
    try {
      final url = enabled
          ? LocalAiClient.normalizeBaseUrl(baseUrl)
          : baseUrl.trim();
      if (enabled && model.trim().isEmpty) {
        throw const LocalAiError('ai.local.error_model');
      }
      if (_localConfig.hasApiKey && apiKey == null) {
        String? origin(String value) {
          try {
            return Uri.parse(LocalAiClient.normalizeBaseUrl(value)).origin;
          } on LocalAiError {
            return null;
          }
        }

        if (origin(url) != origin(_localConfig.baseUrl)) {
          throw const LocalAiError('ai.local.key_new_host');
        }
      }
      return LocalAiConfig(
        enabled: enabled,
        baseUrl: url,
        model: model.trim(),
        apiKey: apiKey?.trim() ?? _localConfig.apiKey,
      );
    } on LocalAiError catch (error) {
      throw AiException(I18n.tr(error.messageKey));
    }
  }

  Future<void> _queueLocalWrite(Future<void> Function() action) {
    final operation = _localWriteQueue.then((_) => action());
    _localWriteQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> saveLocalConfiguration({
    required bool enabled,
    required String baseUrl,
    required String model,
    String? apiKey,
  }) async {
    final clearGeneration = _localClearGeneration;
    await _requireLocalMode();
    if (clearGeneration != _localClearGeneration) {
      throw AiException(I18n.tr('ai.local.changed'));
    }
    final config = _draftConfiguration(
      enabled: enabled,
      baseUrl: baseUrl,
      model: model,
      apiKey: apiKey,
    );
    final serial = ++_localMutation;
    _requestGeneration++;
    try {
      await _queueLocalWrite(() => _localStore.write(config));
      if (serial != _localMutation || _disposed) return;
      _localConfig = config;
      _localConfigLoaded = true;
      _localConfigError = null;
      _changed();
    } catch (_) {
      throw AiException(I18n.tr('ai.local.error_storage'));
    }
  }

  Future<void> clearLocalConfiguration() async {
    if (!usingLocalConfiguration || _disposed) {
      throw AiException(I18n.tr('ai.local.unavailable'));
    }
    _localClearGeneration++;
    final serial = ++_localMutation;
    _requestGeneration++;
    try {
      await _queueLocalWrite(_localStore.clear);
      if (serial != _localMutation || _disposed) return;
      _localConfig = const LocalAiConfig();
      _localConfigLoaded = true;
      _localConfigError = null;
      _changed();
    } catch (_) {
      throw AiException(I18n.tr('ai.local.error_storage'));
    }
  }

  Future<String> testLocalConfiguration({
    required String baseUrl,
    required String model,
    String? apiKey,
  }) async {
    await _requireLocalMode();
    final config = _draftConfiguration(
      enabled: true,
      baseUrl: baseUrl,
      model: model,
      apiKey: apiKey,
    );
    final generation = _requestGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    try {
      final content = await _localClient.chat(
        config: config,
        system: 'Reply with ok to test the configured AI service.',
        user: 'ok',
        temperature: 0,
        maxTokens: 1200,
      );
      _checkRequest(generation, accountGeneration);
      return content;
    } on LocalAiError catch (error) {
      throw AiException(I18n.tr(error.messageKey));
    }
  }

  Future<void> loadFromStorage() {
    final generation = _storageGeneration;
    return _serialize(() async {
      if (generation != _storageGeneration) return;
      // 本地 AI 连接属于设备，读取历史前先完成设备配置加载。
      if (usingLocalConfiguration) await loadLocalConfiguration();
      List<String> raw;
      try {
        raw = await _historyStore.read();
      } catch (_) {
        // 读失败保持现有内存内容，不要把历史清空。
        return;
      }
      if (generation != _storageGeneration) return;
      _reviewHistory = _decodeHistory(raw);
      _changed();
    });
  }

  /// 账号切换/退出：同步失效旧代际并清空内存。晚到的响应和晚到的写入都不会
  /// 重新生成 `ai_review_history`。
  void resetLocalState() {
    _storageGeneration++;
    _requestGeneration++;
    _reviewHistory = [];
    _reportJobs.clear();
    _reportDrafts.clear();
    _reportRequests.clear();
    _reportRetries.clear();
    _reportPendingArchives.clear();
    _changed();
  }

  /// 排空历史读写队列：账号清理在最终 prefs 清理前调用，避免旧写入在清理后落地。
  Future<void> waitForHistoryWrites() async {
    var tail = _historyTail;
    while (true) {
      try {
        await tail;
      } catch (_) {
        // 队列尾部的失败已被吸收，这里只负责排空。
      }
      if (identical(tail, _historyTail)) return;
      tail = _historyTail;
    }
  }

  /// 删除单条历史。
  ///
  /// 计算、内存移除、落盘与回滚全部在历史串行区内完成：并发 load/append 不会
  /// 让删除静默失效，写入失败时也只回滚到队列内看到的最新列表。
  Future<void> deleteReview(String id) async {
    final generation = _storageGeneration;
    await _serialize(() async {
      if (generation != _storageGeneration) return;
      final previous = _reviewHistory;
      final next = previous.where((entry) => entry.id != id).toList();
      // 队列内已没有这一条（例如刚被清空或并发删除）：不需要写盘。
      if (next.length == previous.length) return;
      _reviewHistory = next;
      _changed();
      try {
        await _saveHistory();
      } catch (_) {
        if (generation == _storageGeneration) {
          _reviewHistory = previous;
          _changed();
        }
        rethrow;
      }
    });
  }

  /// 清空全部历史（所有周期）：同时让进行中的旧请求失效，避免清空后被写回。
  Future<void> clearReviewHistory() async {
    _storageGeneration++;
    final generation = _storageGeneration;
    _reviewHistory = [];
    _reportJobs.clear();
    _reportDrafts.clear();
    _reportRequests.clear();
    _reportRetries.clear();
    _reportPendingArchives.clear();
    _changed();
    await _serialize(() async {
      if (generation != _storageGeneration) return;
      await _saveHistory();
    });
  }

  /// 指定自然周期的历史解读，最新在前。
  List<AiReviewEntry> reportHistoryFor(AiReportContext context) {
    final key = context.key;
    final entries =
        _reviewHistory
            .where((entry) => entry.reportContext?.key == key)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<AiReviewEntry>.unmodifiable(entries);
  }

  /// 指定周期当前的未完成任务（generating/saving）或存档失败任务。
  AiReportReviewJob? reportJobFor(AiReportContext context) =>
      _reportJobs[context.key];

  /// 历史选择器可选的自然周期：已存档分组 + 进行中/存档失败分组，最新在前。
  List<AiReportContext> get reportContexts {
    final contexts = <String, AiReportContext>{};
    final activity = <String, DateTime>{};
    for (final entry in _reviewHistory) {
      final context = entry.reportContext;
      if (context == null) continue;
      contexts.putIfAbsent(context.key, () => context);
      final seen = activity[context.key];
      if (seen == null || entry.createdAt.isAfter(seen)) {
        activity[context.key] = entry.createdAt;
      }
    }
    for (final job in _reportJobs.values) {
      if (!_isPickerVisibleJob(job)) continue;
      final key = job.context.key;
      contexts.putIfAbsent(key, () => job.context);
      final seen = activity[key];
      if (seen == null || job.startedAt.isAfter(seen)) {
        activity[key] = job.startedAt;
      }
    }
    final keys = contexts.keys.toList()
      ..sort((a, b) {
        final left = activity[a];
        final right = activity[b];
        if (left == null && right == null) return a.compareTo(b);
        if (left == null) return 1;
        if (right == null) return -1;
        return right.compareTo(left);
      });
    return List<AiReportContext>.unmodifiable([
      for (final key in keys) contexts[key]!,
    ]);
  }

  List<AiReviewEntry> _decodeHistory(List<String> raw) {
    final entries = <AiReviewEntry>[];
    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map) {
          entries.add(
            AiReviewEntry.fromJson(Map<String, dynamic>.from(decoded)),
          );
        }
      } catch (_) {
        // 损坏的单条记录不影响其它历史条目。
        continue;
      }
    }
    return entries;
  }

  /// 串行执行历史 IO。返回的 Future 保留本次操作的真实异常，
  /// 而队列尾部永远正常完成，后续操作不会被前一次失败卡住。
  Future<T> _serialize<T>(Future<T> Function() action) async {
    final previous = _historyTail;
    final done = Completer<void>();
    _historyTail = done.future;
    try {
      try {
        await previous;
      } catch (_) {
        // 吸收上一次排队的失败。
      }
      return await action();
    } finally {
      if (!done.isCompleted) done.complete();
    }
  }

  Future<void> _saveHistory() => _saveEntries(_reviewHistory);

  Future<void> _saveEntries(List<AiReviewEntry> entries) {
    final payload = [for (final entry in entries) jsonEncode(entry.toJson())];
    return _historyStore.write(payload);
  }

  /// 每个自然周期分组各自最多 50 条；无元数据的老记录共用原有 50 条池，
  /// 其它周期不会因为本周期新增而被挤掉。
  List<AiReviewEntry> _capHistory(List<AiReviewEntry> entries) {
    final counts = <String, int>{};
    final kept = <AiReviewEntry>[];
    for (final entry in entries) {
      final key = entry.reportContext?.key ?? _unscopedPoolKey;
      final count = counts[key] ?? 0;
      if (count >= maxReviewEntriesPerGroup) continue;
      counts[key] = count + 1;
      kept.add(entry);
    }
    return kept;
  }

  /// 先落盘再入内存：只有写入成功才把条目提交为可读历史。
  ///
  /// 追加目标列表在串行区内计算，保证并发 load/append 不会互相丢记录。
  Future<bool> _commitEntry(
    AiReviewEntry entry, {
    required int generation,
    required int accountGeneration,
  }) {
    return _serialize(() async {
      if (_isRequestStale(generation, accountGeneration)) return false;
      final candidate = _capHistory(<AiReviewEntry>[entry, ..._reviewHistory]);
      try {
        await _saveEntries(candidate);
      } catch (_) {
        if (_isRequestStale(generation, accountGeneration)) return false;
        rethrow;
      }
      if (_isRequestStale(generation, accountGeneration)) {
        await _repairStaleWrite();
        return false;
      }
      _reviewHistory.insert(0, entry);
      _reviewHistory = _capHistory(_reviewHistory);
      _changed();
      return true;
    });
  }

  /// 旧代际的写入已经落地时，用当前内存（重置后为空）覆盖回去。
  Future<void> _repairStaleWrite() async {
    try {
      await _saveHistory();
    } catch (_) {
      // 尽力而为：账号清理随后还会再清一遍该键。
    }
  }

  bool _isRequestStale(int generation, int accountGeneration) =>
      generation != _storageGeneration ||
      !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
        accountGeneration,
      );

  void _throwIfStale(int generation, int accountGeneration) {
    if (_isRequestStale(generation, accountGeneration)) {
      throw AiException(I18n.tr('statistics.ai.error.session_changed'));
    }
  }

  void _checkRequest(int generation, int accountGeneration) {
    if (_disposed ||
        generation != _requestGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      throw AiException(I18n.tr('ai.local.changed'));
    }
  }

  void _discardJob(String key, DateTime startedAt) {
    if (_reportJobs[key]?.startedAt != startedAt) return;
    _reportJobs.remove(key);
    _reportDrafts.remove(key);
    // 任务结束后不再需要“待保存条目身份”，避免下一次生成误用旧 id。
    _reportPendingArchives.remove(key);
    _changed();
  }

  /// 生成失败的本地化错误留在任务上供内联展示（没有可存档正文）。
  void _markGenerationFailed(String key, DateTime startedAt, String message) {
    final current = _reportJobs[key];
    if (current == null || current.startedAt != startedAt) return;
    _reportJobs[key] = current.copyWith(
      phase: AiReportReviewPhase.failed,
      error: message,
    );
    _changed();
  }

  /// 历史选择器只列出“进行中”或“有未存档正文”的分组；
  /// 纯生成失败的分组没有可查看内容，不进选择器。
  bool _isPickerVisibleJob(AiReportReviewJob job) =>
      job.isRunning || (job.unsavedContent?.trim().isNotEmpty ?? false);

  String _newEntryId(DateTime instant, AiReportContext? context) {
    final stamp = instant.microsecondsSinceEpoch.toString();
    if (context == null) return stamp;
    return '$stamp@${context.key}';
  }

  Future<String> _chat(
    String systemPrompt,
    String userPrompt, {
    double temperature = 0.4,
    int maxTokens = 1200,
  }) async {
    final generation = _requestGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    if (usingLocalConfiguration) await loadLocalConfiguration();
    _checkRequest(generation, accountGeneration);
    if (!enabled) {
      throw AiException(
        usingLocalConfiguration
            ? I18n.tr('ai.local.not_configured')
            : 'AI 功能未启用，请联系管理员',
      );
    }
    final modelId = model.toLowerCase().split('/').last;
    // 推理型模型会先消耗大量 reasoning token，预算需覆盖思考与正文。
    final requestMaxTokens =
        modelId == 'minimax-m3.1-flash-free' &&
            maxTokens > 256 &&
            maxTokens < 8192
        ? 8192
        : maxTokens;
    try {
      if (usingLocalConfiguration) {
        final content = await _localClient.chat(
          config: _localConfig,
          system: systemPrompt,
          user: userPrompt,
          temperature: temperature,
          maxTokens: requestMaxTokens,
        );
        _checkRequest(generation, accountGeneration);
        return content;
      }
      final res = await _client.post('/api/ai/chat', {
        'system': systemPrompt,
        'user': userPrompt,
        'temperature': temperature,
        'max_tokens': requestMaxTokens,
      }, AppConfig.aiTimeout);
      _checkRequest(generation, accountGeneration);
      final content = (res['content'] ?? '').toString().trim();
      if (content.isEmpty) {
        throw const AiException('模型未返回正文。若使用推理模型，请让管理员调大 max_tokens 或改用非推理模型。');
      }
      return content;
    } on LocalAiError catch (error) {
      throw AiException(I18n.tr(error.messageKey));
    } on ApiException catch (e) {
      throw AiException(_friendlyAiError(e.message));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _requestGeneration++;
    _localClient.dispose();
    super.dispose();
  }

  Future<AiScheduleDraft> createScheduleDraft(
    String input, {
    DateTime? now,
  }) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const AiException('请输入要创建的日程或待办内容');
    }
    final localNow = now ?? DateTime.now();
    final baseDraft = _fallbackScheduleDraft(trimmed, now: localNow);
    if (!enabled) return baseDraft.withSource(AiScheduleSource.localParser);

    final prompt = [
      '当前本地时间：${localNow.toIso8601String()}',
      '用户输入：$trimmed',
      '',
      '请识别用户想创建的是 calendar（日程）还是 todo（待办）。',
      '只返回 JSON，不要 Markdown。字段：',
      '{"type":"calendar|todo","title":"标题","start_at":"ISO8601 或空",'
          '"end_at":"ISO8601 或空","all_day":false,"reminder":true,'
          '"notes":"补充说明","subtasks":["子任务"]}',
      '规则：有明确开始时间/会议/日程/安排，优先 calendar；只表达要完成的任务，优先 todo。',
      '没有结束时间时，calendar 默认 60 分钟；todo 没有时间也可以创建。',
    ].join('\n');
    try {
      final raw = await _chat(
        '你是多仪的日程创建助手。你必须把自然语言转成可确认的结构化草稿。'
        '不要编造用户没有提到的地点、人名或重复规则。输出必须是严格 JSON。',
        prompt,
        temperature: 0.1,
        maxTokens: 1200,
      );
      final parsed = _parseScheduleDraft(raw, trimmed, localNow);
      return parsed ??
          baseDraft.withSource(
            AiScheduleSource.aiWithLocalFallback,
            warning: 'AI 没有返回可用草稿，已用本地时间解析生成草稿。',
          );
    } on AiException catch (e) {
      return baseDraft.withSource(
        AiScheduleSource.localParser,
        warning: 'AI 识别失败，已用本地时间解析生成草稿：${e.message}',
      );
    } catch (e) {
      return baseDraft.withSource(
        AiScheduleSource.aiWithLocalFallback,
        warning: 'AI 返回内容无法解析，已用本地时间解析生成草稿：$e',
      );
    }
  }

  Future<AiTodoBreakdown> breakDownTodo(
    String input, {
    required List<String> listGroups,
    DateTime? now,
  }) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const AiException('请输入要拆解的待办内容');
    }
    final localNow = now == null ? AppClock.now() : AppClock.toLocal(now);
    final out = await _chat(
      '你是多仪的新建待办拆解助手。只返回一个严格 JSON 对象，禁止 Markdown 和其它解释。'
          '字段格式示例：{"title":"准备云计算项目评审问题","subtasks":["具体动作"],"list_group":"工作",'
          '"quadrant":"Q2","date_time":"2026-10-23T15:00:00","has_time":true}。'
          'subtasks 必须是 3 到 7 条具体可执行动作的字符串数组。'
          'title 是精简明确的任务名，突出动作和对象，约12到24个中文字或等效简短短语；'
          '时间、地点、具体要求保留在原始描述中，不要把完整用户原话重复为标题，不要编造新事实。'
          'list_group 只能是用户提供的可选清单中的完整名称，无法匹配就返回 null，不创建新清单。'
          'quadrant 只能为 Q1（紧急重要）、Q2（重要不紧急）、Q3（紧急不重要）、Q4（都不），'
          '无法判断则为 null；不要返回独立的低、中、高 priority 标记。'
          '日期只有用户原文有依据时才能输出；普通任务没有日期依据时 date_time 必须为 null。'
          '相对日期按给定的当前应用墙上时间和应用时区解释。'
          '有具体时分才 has_time=true；只有日期时 date_time 使用 YYYY-MM-DD 且 has_time=false。'
          '无日期时 has_time=false。不要自行添加默认 9 点或任何原文未指定的时刻。'
          '时间使用 ISO8601；不带 offset 的时间按应用时区解释，带 Z 或数值 offset 表示对应瞬间。',
      '当前应用墙上时间：${localNow.toIso8601String()}\n'
          '应用时区（IANA）：${LocalTimezoneResolver.currentIana}\n'
          '可选清单（allowed listGroups）：${jsonEncode(listGroups)}\n'
          '用户原文：$trimmed',
      temperature: 0.2,
      maxTokens: 2000,
    );
    final result = AiTodoBreakdown.tryParse(out, listGroups: listGroups);
    if (result == null) {
      throw const AiException('AI 没有返回可用的待办拆解，请重试');
    }
    return result;
  }

  Future<List<String>> breakDownTask(String goal) async {
    final out = await _chat(
      '你是一个高效任务分解助手，将用户的目标拆成 3 到 7 条具体可执行的子任务。'
      '只输出子任务，每条一行，不要编号、解释、客套话。',
      goal,
      temperature: 0.3,
    );
    return out
        .split(RegExp(r'\r?\n'))
        .map(
          (line) =>
              line.trim().replaceFirst(RegExp(r'^[\-\*\d\.\s]+'), '').trim(),
        )
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Future<String> testConnection() {
    return _chat(
      '你是多仪的 AI 连通性测试助手。只回复 ok。',
      '请回复 ok，用于验证 /api/ai/chat 代理链路可用。',
      temperature: 0,
      maxTokens: 256,
    );
  }

  Future<String> weeklyReview({
    required int completedTodos,
    required int totalTodos,
    required int weeklyFocusMinutes,
    required int habitStreak,
    String periodLabel = '本周',
    DateTime? now,
  }) async {
    final createdAt = now ?? DateTime.now();
    final cached = weeklyReviewForDay(createdAt);
    if (cached != null) return cached.content;
    // 网络请求前先固定代际与模型，晚到的响应不能写进新账号的历史。
    final storageGeneration = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final model = _model;
    final summary =
        '$periodLabel数据：完成 $completedTodos / $totalTodos 项待办，专注 $weeklyFocusMinutes 分钟，习惯连续打卡 $habitStreak 天。';
    final out = await _chat(
      _weeklyReviewSystemPrompt(periodLabel),
      '周期：$periodLabel\n'
      '待办完成：$completedTodos / $totalTodos\n'
      '专注时长：$weeklyFocusMinutes 分钟\n'
      '习惯连续打卡：$habitStreak 天\n'
      '请生成这次周回顾。',
      temperature: 0.45,
      maxTokens: 1000,
    );
    final review = _normalizeWeeklyReview(
      out,
      periodLabel: periodLabel,
      completedTodos: completedTodos,
      totalTodos: totalTodos,
      weeklyFocusMinutes: weeklyFocusMinutes,
      habitStreak: habitStreak,
    );
    _throwIfStale(storageGeneration, accountGeneration);
    final entry = AiReviewEntry(
      id: createdAt.millisecondsSinceEpoch.toString(),
      createdAt: createdAt,
      content: review,
      summary: summary,
      model: model,
      kind: weeklyReviewKind,
    );
    final applied = await _commitEntry(
      entry,
      generation: storageGeneration,
      accountGeneration: accountGeneration,
    );
    if (!applied) {
      throw AiException(I18n.tr('statistics.ai.error.session_changed'));
    }
    return review;
  }

  /// 基于 ReportEngine 的 PeriodReport 生成自然语言周/月/年报。
  Future<String> reviewFromReport({
    required int completedTodos,
    required int totalTodos,
    required int focusMinutes,
    required int habitStreak,
    required int habitCheckIns,
    required int timeEntryMinutes,
    required String periodLabel,
  }) async {
    final summary =
        '$periodLabel数据：完成 $completedTodos / $totalTodos 项待办，'
        '专注 $focusMinutes 分钟，习惯打卡 $habitCheckIns 次（最长连续 $habitStreak 天），'
        '记录时间 $timeEntryMinutes 分钟。';
    return _runReview(summary, periodLabel);
  }

  /// 生成统计报告的个性化解读。
  ///
  /// 传入 [reportContext] 时，本服务负责按自然周期去重、任务状态和存档；
  /// 不传时保持旧的“无周期元数据”行为（进入原有 latest-50 池）。
  Future<String> personalizedReportReview({
    required String periodLabel,
    required String reportMarkdown,
    AiReportContext? reportContext,
    DateTime? dataThrough,
  }) {
    final context = reportContext;
    if (context == null) {
      return _runUnscopedReportReview(
        periodLabel: periodLabel,
        reportMarkdown: reportMarkdown,
        dataThrough: dataThrough,
      );
    }
    // 同一自然周期已有进行中的请求：复用同一个 Future，只发一次上游请求。
    final running = _reportRequests[context.key];
    if (running != null) return running;
    return _startScopedReportReview(
      periodLabel: periodLabel,
      reportMarkdown: reportMarkdown,
      context: context,
      dataThrough: dataThrough,
    );
  }

  /// 存档失败后只重试“保存”，不再调用模型。
  ///
  /// 同一周期的重复点击共享同一个 Future，并复用同一条待保存条目身份，
  /// 因此阻塞或连续重试最多只落一条存档，不会把同一次生成存成多个版本。
  Future<void> retryReportArchive(AiReportContext context) {
    final key = context.key;
    final running = _reportRetries[key];
    if (running != null) return running;
    final job = _reportJobs[key];
    final content = (job?.unsavedContent ?? '').trim();
    // 没有待保存正文时不做任何事，绝不能凭空生成一条空存档。
    if (job == null || content.isEmpty) return Future<void>.value();
    final completer = Completer<void>();
    final future = completer.future;
    _reportRetries[key] = future;
    Future<void>.sync(() => _runArchiveRetry(context, job, content)).then(
      (_) {
        if (identical(_reportRetries[key], future)) {
          _reportRetries.remove(key);
        }
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_reportRetries[key], future)) {
          _reportRetries.remove(key);
        }
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
    );
    return future;
  }

  Future<void> _runArchiveRetry(
    AiReportContext context,
    AiReportReviewJob job,
    String content,
  ) async {
    final key = context.key;
    final storageGeneration = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final entry = _pendingArchiveEntry(context, content);
    _reportJobs[key] = job.copyWith(
      phase: AiReportReviewPhase.saving,
      clearError: true,
    );
    _changed();
    final bool applied;
    try {
      applied = await _commitEntry(
        entry,
        generation: storageGeneration,
        accountGeneration: accountGeneration,
      );
    } catch (_) {
      _markArchiveFailed(key, job, content);
      rethrow;
    }
    if (!applied) {
      _discardJob(key, job.startedAt);
      throw AiException(I18n.tr('statistics.ai.error.session_changed'));
    }
    _discardJob(key, job.startedAt);
  }

  /// 同一次生成只有一个待保存条目身份；正文变了（新的生成又失败）才换新条目。
  AiReviewEntry _pendingArchiveEntry(AiReportContext context, String content) {
    final key = context.key;
    final pending = _reportPendingArchives[key];
    if (pending != null && pending.content == content) return pending;
    final draft = _reportDrafts[key];
    final createdAt = DateTime.now();
    final entry = AiReviewEntry(
      id: _newEntryId(createdAt, context),
      createdAt: createdAt,
      content: content,
      summary: draft?.summary ?? _statisticsSummary(context.period.name),
      model: draft?.model ?? _model,
      kind: statisticsReportKind,
      reportContext: context,
      dataThrough: draft?.dataThrough,
    );
    _reportPendingArchives[key] = entry;
    return entry;
  }

  Future<String> _startScopedReportReview({
    required String periodLabel,
    required String reportMarkdown,
    required AiReportContext context,
    DateTime? dataThrough,
  }) {
    final key = context.key;
    final completer = Completer<String>();
    _reportRequests[key] = completer.future;
    Future<String>.sync(
      () => _runScopedReportReview(
        periodLabel: periodLabel,
        reportMarkdown: reportMarkdown,
        context: context,
        dataThrough: dataThrough,
      ),
    ).then(
      (value) {
        if (identical(_reportRequests[key], completer.future)) {
          _reportRequests.remove(key);
        }
        if (!completer.isCompleted) completer.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_reportRequests[key], completer.future)) {
          _reportRequests.remove(key);
        }
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
    );
    return completer.future;
  }

  Future<String> _runScopedReportReview({
    required String periodLabel,
    required String reportMarkdown,
    required AiReportContext context,
    DateTime? dataThrough,
  }) async {
    final key = context.key;
    final storageGeneration = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final model = _model;
    final startedAt = DateTime.now();
    final snapshot = _resolveDataThrough(context, dataThrough);
    final summary = _statisticsSummary(periodLabel);
    _reportDrafts[key] = _ScopedReportDraft(
      model: model,
      summary: summary,
      dataThrough: snapshot,
    );
    _reportJobs[key] = AiReportReviewJob(
      context: context,
      startedAt: startedAt,
      phase: AiReportReviewPhase.generating,
    );
    _changed();

    final String out;
    try {
      out = await _requestReportMarkdown(periodLabel, reportMarkdown);
    } catch (error) {
      // 会话已变化（切号 / resetLocalState / 连接失效）时，`_chat` 的
      // `_checkRequest` 会先抛出“连接或账号已变化”的连接层文案。统计报告
      // 契约要求统一报 session_changed，且旧任务不能被标成“生成失败”。
      // 与下方成功分支的 stale 处理保持一致。
      if (_isRequestStale(storageGeneration, accountGeneration)) {
        _discardJob(key, startedAt);
        throw AiException(I18n.tr('statistics.ai.error.session_changed'));
      }
      // 生成失败没有可存档正文；本地化的 AI 错误留在任务上供内联展示，
      // 其它异常仍由调用方按原异常处理。
      if (error is AiException) {
        _markGenerationFailed(key, startedAt, error.message);
      } else {
        _discardJob(key, startedAt);
      }
      rethrow;
    }
    if (_isRequestStale(storageGeneration, accountGeneration)) {
      _discardJob(key, startedAt);
      throw AiException(I18n.tr('statistics.ai.error.session_changed'));
    }
    final content = out.trim();
    if (content.isEmpty) {
      _discardJob(key, startedAt);
      throw AiException(I18n.tr('statistics.ai.error.empty'));
    }
    final createdAt = DateTime.now();
    final entry = AiReviewEntry(
      id: _newEntryId(createdAt, context),
      createdAt: createdAt,
      content: content,
      summary: summary,
      model: model,
      kind: statisticsReportKind,
      reportContext: context,
      dataThrough: snapshot,
    );
    final savingJob = AiReportReviewJob(
      context: context,
      startedAt: startedAt,
      phase: AiReportReviewPhase.saving,
    );
    _reportJobs[key] = savingJob;
    _changed();
    final bool applied;
    try {
      applied = await _commitEntry(
        entry,
        generation: storageGeneration,
        accountGeneration: accountGeneration,
      );
    } catch (_) {
      // 存档失败：正文留在内存供复制/仅重试保存，不谎报成功。
      _markArchiveFailed(key, savingJob, content);
      return content;
    }
    if (!applied) {
      _discardJob(key, startedAt);
      throw AiException(I18n.tr('statistics.ai.error.session_changed'));
    }
    _discardJob(key, startedAt);
    return content;
  }

  /// 旧调用方（无周期元数据）保持原有行为：写入无 scope 的 latest-50 池。
  Future<String> _runUnscopedReportReview({
    required String periodLabel,
    required String reportMarkdown,
    DateTime? dataThrough,
  }) async {
    final storageGeneration = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final model = _model;
    final snapshot = _floatingDate(dataThrough);
    final out = await _requestReportMarkdown(periodLabel, reportMarkdown);
    _throwIfStale(storageGeneration, accountGeneration);
    final content = out.trim();
    if (content.isEmpty) {
      throw AiException(I18n.tr('statistics.ai.error.empty'));
    }
    final createdAt = DateTime.now();
    final entry = AiReviewEntry(
      id: _newEntryId(createdAt, null),
      createdAt: createdAt,
      content: content,
      summary: '统计报告 AI 解读：$periodLabel',
      model: model,
      kind: statisticsReportKind,
      dataThrough: snapshot,
    );
    final applied = await _commitEntry(
      entry,
      generation: storageGeneration,
      accountGeneration: accountGeneration,
    );
    if (!applied) {
      throw AiException(I18n.tr('statistics.ai.error.session_changed'));
    }
    return content;
  }

  Future<String> _requestReportMarkdown(
    String periodLabel,
    String reportMarkdown,
  ) {
    return _chat(
      '你是多仪的云端效率报告分析师。基于用户的周期统计报告，输出一段结构化中文个性化解读。'
          '要求：1) 先给一句总判断；2) 分析待办、专注、习惯、时间足迹中最值得保留和最需要调整的点；'
          '3) 给出未来 7 天 3 条可执行动作；4) 不要泛泛鼓励，不要重复原始数据堆砌。',
      '周期：$periodLabel\n\n$reportMarkdown',
      temperature: 0.5,
      maxTokens: 2200,
    );
  }

  String _statisticsSummary(String periodLabel) => '统计报告 AI 解读：$periodLabel';

  /// `dataThrough` 是浮动快照日，只能落在本周期内；UI 正常会显式传入。
  DateTime? _resolveDataThrough(
    AiReportContext context,
    DateTime? dataThrough,
  ) {
    final provided = _floatingDate(dataThrough);
    if (provided != null) return provided;
    final today = StatisticsSpan.calendarDate(AppClock.today());
    if (today.isBefore(context.start)) return context.start;
    if (today.isAfter(context.end)) return context.end;
    return today;
  }

  DateTime? _floatingDate(DateTime? value) =>
      value == null ? null : StatisticsSpan.calendarDate(value);

  void _markArchiveFailed(String key, AiReportReviewJob job, String content) {
    final current = _reportJobs[key];
    if (current == null || current.startedAt != job.startedAt) return;
    _reportJobs[key] = current.copyWith(
      phase: AiReportReviewPhase.failed,
      error: I18n.tr('statistics.ai.error.archive_failed'),
      unsavedContent: content,
    );
    _changed();
  }

  Future<String> deepDiaryReview({
    required Iterable<DiaryEntry> entries,
    DateTime? today,
  }) async {
    final prompt = DiaryDeepReviewBuilder.build(entries: entries, today: today);
    final storageGeneration = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final model = _model;
    final out = await _chat(
      prompt.systemPrompt,
      prompt.userPrompt,
      temperature: 0.55,
      maxTokens: 1600,
    );
    _throwIfStale(storageGeneration, accountGeneration);
    final createdAt = DateTime.now();
    final entry = AiReviewEntry(
      id: createdAt.millisecondsSinceEpoch.toString(),
      createdAt: createdAt,
      content: out,
      summary: '日记深度复盘：${prompt.summary}',
      model: model,
    );
    final applied = await _commitEntry(
      entry,
      generation: storageGeneration,
      accountGeneration: accountGeneration,
    );
    if (!applied) {
      throw AiException(I18n.tr('statistics.ai.error.session_changed'));
    }
    return out;
  }

  AiReviewEntry? weeklyReviewForDay(DateTime day) {
    for (final entry in _reviewHistory) {
      if (_looksLikeWeeklyReview(entry) && _sameDay(entry.createdAt, day)) {
        return entry;
      }
    }
    return null;
  }

  Future<String> _runReview(
    String summary,
    String periodLabel, {
    String kind = '',
    DateTime? createdAt,
  }) async {
    final storageGeneration = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final model = _model;
    final out = await _chat(
      '你是一个温柔且实用的效率教练。基于$periodLabel完成情况写一段 80-150 字的中文回顾，'
      '开头必须明确写“$periodLabel回顾：”。语气积极不空洞，先肯定 1-2 点亮点，'
      '再提 1-2 个具体可执行的下周建议。不要使用 Markdown、表格、emoji、加粗或分隔线。',
      summary,
      temperature: 0.6,
      maxTokens: 1000,
    );
    _throwIfStale(storageGeneration, accountGeneration);
    final entryTime = createdAt ?? DateTime.now();
    final entry = AiReviewEntry(
      id: entryTime.millisecondsSinceEpoch.toString(),
      createdAt: entryTime,
      content: out,
      summary: summary,
      model: model,
      kind: kind,
    );
    final applied = await _commitEntry(
      entry,
      generation: storageGeneration,
      accountGeneration: accountGeneration,
    );
    if (!applied) {
      throw AiException(I18n.tr('statistics.ai.error.session_changed'));
    }
    return out;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _looksLikeWeeklyReview(AiReviewEntry entry) {
    if (entry.kind == weeklyReviewKind) return true;
    return RegExp(r'^(本周|上周)数据：').hasMatch(entry.summary);
  }

  String _weeklyReviewSystemPrompt(String periodLabel) {
    return '你是多仪的效率回顾助手。基于$periodLabel完成情况输出中文周回顾。'
        '必须严格遵守：'
        '1. 输出分层纯文本，不要写成长段落；'
        '2. 不要 Markdown、表格、emoji、加粗、标题、分隔线或客套结尾；'
        '3. 不要出现“根据你提供的数据”“随时告诉我”“加油”等套话；'
        '4. 每行尽量不超过 32 个汉字；'
        '5. 固定格式如下：\n'
        '$periodLabel回顾\n'
        '总览：一句总判断\n'
        '数据\n'
        '待办：完成情况\n'
        '专注：专注时长\n'
        '习惯：连续打卡\n'
        '观察：一句关键原因或状态\n'
        '下周行动\n'
        '行动一：一个具体动作\n'
        '行动二：一个具体动作';
  }

  String _normalizeWeeklyReview(
    String raw, {
    required String periodLabel,
    required int completedTodos,
    required int totalTodos,
    required int weeklyFocusMinutes,
    required int habitStreak,
  }) {
    final lines = raw
        .split(RegExp(r'\r?\n'))
        .where((line) => !_looksLikeMarkdownTableLine(line))
        .map(_cleanReviewLine)
        .where((line) => line.isNotEmpty)
        .where((line) => !_looksLikeMarkdownTableLine(line))
        .take(8)
        .toList(growable: false);
    final cleaned = lines.join('\n').trim();
    if (_looksLikeStructuredWeeklyReview(cleaned, periodLabel)) return cleaned;
    final suggestion = lines
        .map(
          (line) => line.replaceFirst(RegExp(r'^(下周建议|建议|行动)[:：]'), '').trim(),
        )
        .firstWhere(
          (line) =>
              line.length >= 8 &&
              !line.contains('数据概览') &&
              !line.startsWith('待办') &&
              !line.startsWith('专注') &&
              !line.startsWith('习惯') &&
              !line.contains('根据你提供的数据') &&
              !line.contains('随时告诉') &&
              !line.contains('加油'),
          orElse: () => '',
        );
    return _fallbackWeeklyReview(
      periodLabel: periodLabel,
      completedTodos: completedTodos,
      totalTodos: totalTodos,
      weeklyFocusMinutes: weeklyFocusMinutes,
      habitStreak: habitStreak,
      suggestion: suggestion,
    );
  }

  String _cleanReviewLine(String line) {
    return line
        .trim()
        .replaceAll(RegExp(r'^[#>\-\*\d\.\s]+'), '')
        .replaceAll(RegExp(r'[`*_~|]'), '')
        .replaceAll(RegExp(r'[\u{1F300}-\u{1FAFF}]', unicode: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _looksLikeMarkdownTableLine(String line) {
    final compact = line.replaceAll(' ', '');
    if (compact.contains('---')) return true;
    if (line.contains('指标') && line.contains('完成')) return true;
    if (line.contains('|')) return true;
    return false;
  }

  bool _looksLikeStructuredWeeklyReview(String text, String periodLabel) {
    final lines = text.split('\n').where((line) => line.trim().isNotEmpty);
    if (lines.length != 10) return false;
    return text.startsWith('$periodLabel回顾\n') &&
        text.contains('\n总览：') &&
        text.contains('\n数据\n') &&
        text.contains('\n待办：') &&
        text.contains('\n专注：') &&
        text.contains('\n习惯：') &&
        text.contains('\n观察：') &&
        text.contains('\n下周行动\n') &&
        text.contains('\n行动一：') &&
        text.contains('\n行动二：') &&
        !RegExp(r'[*_#|]').hasMatch(text) &&
        !RegExp(r'[\u{1F300}-\u{1FAFF}]', unicode: true).hasMatch(text);
  }

  String _fallbackWeeklyReview({
    required String periodLabel,
    required int completedTodos,
    required int totalTodos,
    required int weeklyFocusMinutes,
    required int habitStreak,
    required String suggestion,
  }) {
    final rate = totalTodos <= 0
        ? 0
        : (completedTodos / totalTodos * 100).round();
    final overview =
        totalTodos <= 0 && weeklyFocusMinutes <= 0 && habitStreak <= 0
        ? '记录偏少，先恢复基础节奏。'
        : totalTodos > 0 && completedTodos >= totalTodos
        ? '待办推进稳定，继续保持。'
        : rate >= 70
        ? '整体完成不错，可以继续加固。'
        : '节奏还有提升空间。';
    final todoLine = totalTodos <= 0
        ? '待办：暂无计划项，先安排关键任务。'
        : '待办：完成 $completedTodos / $totalTodos 项，完成率 $rate%。';
    final focusLine = weeklyFocusMinutes <= 0
        ? '专注：0 分钟，先从每天 10 分钟开始。'
        : '专注：$weeklyFocusMinutes 分钟，保留固定专注窗口。';
    final habitLine = habitStreak <= 0
        ? '习惯：连续 0 天，先重启一个最小习惯。'
        : '习惯：连续 $habitStreak 天，继续守住当前节奏。';
    final observation = _weeklyObservation(
      totalTodos: totalTodos,
      completedTodos: completedTodos,
      weeklyFocusMinutes: weeklyFocusMinutes,
      habitStreak: habitStreak,
    );
    final firstAction = suggestion.isEmpty
        ? _defaultWeeklyAction(totalTodos, weeklyFocusMinutes, habitStreak)
        : suggestion;
    final secondAction = _secondaryWeeklyAction(
      totalTodos,
      weeklyFocusMinutes,
      habitStreak,
    );
    return [
      '$periodLabel回顾',
      '总览：$overview',
      '数据',
      todoLine,
      focusLine,
      habitLine,
      '观察：$observation',
      '下周行动',
      '行动一：$firstAction',
      '行动二：$secondAction',
    ].join('\n');
  }

  String _weeklyObservation({
    required int totalTodos,
    required int completedTodos,
    required int weeklyFocusMinutes,
    required int habitStreak,
  }) {
    if (totalTodos > 0 && completedTodos > 0 && weeklyFocusMinutes <= 0) {
      return '待办有推进，但专注时间没有形成记录。';
    }
    if (habitStreak <= 0 && weeklyFocusMinutes > 0) {
      return '专注已经启动，习惯链还需要重新接上。';
    }
    if (totalTodos <= 0 && weeklyFocusMinutes <= 0 && habitStreak <= 0) {
      return '本周更像恢复周，先把记录节奏找回来。';
    }
    return '当前节奏可延续，重点是减少目标切换。';
  }

  String _defaultWeeklyAction(
    int totalTodos,
    int weeklyFocusMinutes,
    int habitStreak,
  ) {
    if (weeklyFocusMinutes <= 0) return '每天先排一个 10 分钟专注块。';
    if (habitStreak <= 0) return '选择一个低门槛习惯连续打卡 3 天。';
    if (totalTodos <= 0) return '提前列出 3 件本周关键任务。';
    return '保留 2 件关键任务，完成后再加新任务。';
  }

  String _secondaryWeeklyAction(
    int totalTodos,
    int weeklyFocusMinutes,
    int habitStreak,
  ) {
    if (habitStreak <= 0) return '把喝水或早睡设为本周最小习惯。';
    if (weeklyFocusMinutes <= 0) return '把专注提醒放到每天固定时段。';
    if (totalTodos <= 0) return '每天只确认一次任务清单。';
    return '周中复盘一次，及时删掉低优先级任务。';
  }
}

enum AiScheduleType { calendar, todo }

enum AiScheduleSource { ai, aiWithLocalFallback, localParser }

class AiScheduleDraft {
  final AiScheduleType type;
  final String title;
  final DateTime startAt;
  final DateTime? endAt;
  final bool allDay;
  final bool reminderEnabled;
  final String notes;
  final List<String> subtasks;
  final AiScheduleSource source;
  final String? warning;

  const AiScheduleDraft({
    required this.type,
    required this.title,
    required this.startAt,
    this.endAt,
    this.allDay = false,
    this.reminderEnabled = false,
    this.notes = '',
    this.subtasks = const <String>[],
    this.source = AiScheduleSource.ai,
    this.warning,
  });

  bool get isCalendar => type == AiScheduleType.calendar;
  bool get hasTime => !allDay;

  AiScheduleDraft withSource(AiScheduleSource next, {String? warning}) {
    return AiScheduleDraft(
      type: type,
      title: title,
      startAt: startAt,
      endAt: endAt,
      allDay: allDay,
      reminderEnabled: reminderEnabled,
      notes: notes,
      subtasks: subtasks,
      source: next,
      warning: warning ?? this.warning,
    );
  }

  TodoItem toTodo() {
    final dueDate = allDay ? null : startAt;
    final reminder = reminderEnabled
        ? ReminderConfig(
            enabled: true,
            kind: ReminderKind.push,
            hour: startAt.hour,
            minute: startAt.minute,
            vibrate: true,
          )
        : const ReminderConfig.disabled();
    final plan = reminderEnabled
        ? ReminderPlan(
            enabled: true,
            rules: [
              ReminderRule(
                id: 'ai-schedule-${startAt.millisecondsSinceEpoch}',
                enabled: true,
                type: ReminderRuleType.absolute,
                kind: ReminderKind.push,
                hour: startAt.hour,
                minute: startAt.minute,
                vibrate: true,
              ),
            ],
          )
        : const ReminderPlan.disabled();
    return TodoItem(
      title: title,
      notes: notes,
      date: startAt,
      dueDate: dueDate,
      hasReminder: reminderEnabled,
      reminderAt: reminderEnabled ? startAt : null,
      reminder: reminder,
      reminderPlan: plan,
      subtasks: subtasks.map((title) => Subtask(title: title)).toList(),
    );
  }
}

AiScheduleDraft _fallbackScheduleDraft(String input, {DateTime? now}) {
  final localNow = now ?? DateTime.now();
  final draft = SmartTodoDraftBuilder.fromText(input, now: localNow);
  final parsed = SmartDateParser.parse(input, now: localNow);
  final hasExplicitTime = parsed.isSuccess && parsed.hasTimeOfDay;
  final type = _inferScheduleType(input, hasExplicitTime: hasExplicitTime);
  final title = _cleanScheduleTitle(
    draft.title.trim().isEmpty ? input.trim() : draft.title.trim(),
    input,
  );
  final startAt = parsed.isSuccess
      ? draft.date
      : DateTime(localNow.year, localNow.month, localNow.day);
  final reminder = draft.hasReminder && !_hasNoReminderIntent(input);
  return AiScheduleDraft(
    type: type,
    title: title,
    startAt: startAt,
    endAt: type == AiScheduleType.calendar && hasExplicitTime
        ? startAt.add(const Duration(hours: 1))
        : null,
    allDay: !hasExplicitTime,
    reminderEnabled: reminder,
    notes: '来自输入：$input',
    source: AiScheduleSource.localParser,
  );
}

AiScheduleDraft? _parseScheduleDraft(
  String raw,
  String original,
  DateTime now,
) {
  final jsonText = _extractJsonObject(raw);
  if (jsonText == null) return null;
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map) return null;
  final fallback = _fallbackScheduleDraft(original, now: now);
  final data = _scheduleDataFromJson(Map<String, dynamic>.from(decoded));
  final rawTitle = _firstString(data, const [
    'title',
    'name',
    'summary',
    'content',
    '标题',
    '主题',
    '内容',
  ]);
  final title = _cleanScheduleTitle(
    rawTitle.isEmpty ? fallback.title : rawTitle,
    original,
  );
  if (title.isEmpty) return null;

  final parsedStart = _parseScheduleTime(
    _firstValue(data, const [
      'start_at',
      'startAt',
      'start',
      'date',
      'time',
      'due_at',
      'dueAt',
      'reminder_at',
      'reminderAt',
      '开始时间',
      '开始',
      '时间',
      '日期',
    ]),
    now,
  );
  final parsedEnd = _parseScheduleTime(
    _firstValue(data, const ['end_at', 'endAt', 'end', '结束时间', '结束']),
    now,
  );
  final start = parsedStart?.dateTime ?? fallback.startAt;
  final hasTime = parsedStart?.hasTimeOfDay ?? fallback.hasTime;
  final type = _typeFromAiData(data, original, hasExplicitTime: hasTime);
  var end = parsedEnd?.dateTime;
  if (end != null && !end.isAfter(start)) {
    end = null;
  }
  if (type == AiScheduleType.calendar && end == null && hasTime) {
    end = start.add(const Duration(hours: 1));
  }
  final allDay =
      _parseBoolValue(
        _firstValue(data, const ['all_day', 'allDay', '全天', '是否全天']),
      ) ??
      !hasTime;
  final reminderRequested =
      _parseBoolValue(
        _firstValue(data, const [
          'reminder',
          'has_reminder',
          'reminder_enabled',
          'reminderEnabled',
          '提醒',
          '是否提醒',
        ]),
      ) ??
      fallback.reminderEnabled;
  final reminder =
      reminderRequested && hasTime && !_hasNoReminderIntent(original);
  final warning = reminderRequested && !hasTime ? '未识别到具体提醒时间，提醒已关闭。' : null;
  final subtasks = _parseSubtasks(
    _firstValue(data, const ['subtasks', 'tasks', 'checklist', '子任务', '清单']),
  );
  return AiScheduleDraft(
    type: type,
    title: title,
    startAt: start,
    endAt: end,
    allDay: allDay,
    reminderEnabled: reminder,
    notes: _firstString(data, const [
      'notes',
      'note',
      'description',
      '备注',
      '说明',
    ]),
    subtasks: subtasks,
    warning: warning,
  );
}

String? _extractJsonObject(String raw) {
  var text = raw.trim();
  final fence = RegExp(
    r'```(?:json)?\s*([\s\S]*?)```',
    caseSensitive: false,
  ).firstMatch(text);
  if (fence != null) {
    text = fence.group(1)!.trim();
  }
  var depth = 0;
  var start = -1;
  var inString = false;
  var escaping = false;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (inString) {
      if (escaping) {
        escaping = false;
      } else if (char == '\\') {
        escaping = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }
    if (char == '"') {
      inString = true;
      continue;
    }
    if (char == '{') {
      if (depth == 0) start = i;
      depth++;
    } else if (char == '}') {
      if (depth == 0) continue;
      depth--;
      if (depth == 0 && start >= 0) return text.substring(start, i + 1);
    }
  }
  return null;
}

Map<String, dynamic> _scheduleDataFromJson(Map<String, dynamic> data) {
  for (final key in const [
    'draft',
    'schedule',
    'event',
    'todo',
    'task',
    'data',
    'result',
  ]) {
    final nested = data[key];
    if (nested is Map) {
      final next = Map<String, dynamic>.from(nested);
      if (!next.containsKey('type') && data['type'] != null) {
        next['type'] = data['type'];
      }
      return next;
    }
  }
  return data;
}

Object? _firstValue(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    if (data.containsKey(key)) return data[key];
  }
  return null;
}

String _firstString(Map<String, dynamic> data, List<String> keys) {
  final value = _firstValue(data, keys);
  if (value == null) return '';
  final text = value.toString().trim();
  if (_isBlankAiValue(text)) return '';
  return text;
}

bool _isBlankAiValue(String text) {
  final normalized = text.trim().toLowerCase();
  return normalized.isEmpty ||
      normalized == 'null' ||
      normalized == 'none' ||
      normalized == 'n/a' ||
      normalized == '[]' ||
      normalized == '无' ||
      normalized == '空';
}

AiScheduleType _typeFromAiData(
  Map<String, dynamic> data,
  String original, {
  required bool hasExplicitTime,
}) {
  final raw = _firstString(data, const ['type', 'kind', '类别', '类型']);
  final typeText = raw.toLowerCase();
  if (RegExp(r'(calendar|event|schedule|日程|会议|活动|行程|课程)').hasMatch(typeText)) {
    return AiScheduleType.calendar;
  }
  if (RegExp(r'(todo|task|reminder|待办|任务|提醒)').hasMatch(typeText)) {
    return AiScheduleType.todo;
  }
  return _inferScheduleType(original, hasExplicitTime: hasExplicitTime);
}

AiScheduleType _inferScheduleType(
  String input, {
  required bool hasExplicitTime,
}) {
  final text = input.trim();
  final looksCalendar = RegExp(
    r'(日程|会议|开会|会面|安排|约|预约|行程|面试|上课|课程|课|活动|团建|体检|复诊|看诊|拜访|出差|航班|火车|电影|演出|calendar|meeting|appointment|event|class|interview|flight)',
    caseSensitive: false,
  ).hasMatch(text);
  if (looksCalendar) return AiScheduleType.calendar;
  final looksTodo = RegExp(
    r'(待办|任务|提醒我|记得|完成|提交|购买|买|写|整理|处理|缴|交|打卡|复习|学习|阅读|看书|发送|发给|寄|取|拿|还|做|todo|task|remind)',
    caseSensitive: false,
  ).hasMatch(text);
  if (looksTodo) return AiScheduleType.todo;
  return hasExplicitTime ? AiScheduleType.calendar : AiScheduleType.todo;
}

bool _hasNoReminderIntent(String input) {
  return RegExp(
    r'(不提醒|不用提醒|无需提醒|不要提醒|无提醒|no reminder)',
    caseSensitive: false,
  ).hasMatch(input);
}

String _cleanScheduleTitle(String value, String original) {
  var title = value.trim();
  if (title.isEmpty) title = original.trim();
  title = title.replaceAll(RegExp(r'\s+'), ' ');
  title = title.replaceFirst(RegExp(r'^[，,。；;\s]+'), '');
  title = title.replaceFirst(RegExp(r'^(请|麻烦|帮我|请帮我|给我|为我|我要|我想|我需要)\s*'), '');
  title = title.replaceFirst(
    RegExp(r'^(创建|新建|添加|安排|设置|设|加)(一个|一条)?(日程|待办|任务|提醒)?\s*'),
    '',
  );
  title = title.replaceFirst(
    RegExp(r'^(和|跟|与)(?=[\u4e00-\u9fa5A-Za-z0-9])'),
    '',
  );
  title = title.replaceAll(
    RegExp(r'(提前\s*\d*\s*(分钟|小时)?\s*提醒我|提前提醒我|到时候提醒我|记得提醒我|提醒我|记得)$'),
    '',
  );
  title = title.replaceAll(RegExp(r'[，,。；;\s]+$'), '').trim();
  return title.isEmpty ? original.trim() : title;
}

_ParsedScheduleTime? _parseScheduleTime(Object? value, DateTime now) {
  if (value == null) return null;
  if (value is num) {
    final millis = value > 1000000000000 ? value.toInt() : value.toInt() * 1000;
    return _ParsedScheduleTime(
      DateTime.fromMillisecondsSinceEpoch(millis).toLocal(),
      hasTimeOfDay: true,
    );
  }
  final text = value.toString().trim();
  if (_isBlankAiValue(text)) return null;
  final normalized = text.replaceAll('/', '-').replaceFirst(' ', 'T');
  final iso = DateTime.tryParse(normalized) ?? DateTime.tryParse(text);
  if (iso != null) {
    return _ParsedScheduleTime(
      iso.toLocal(),
      hasTimeOfDay:
          RegExp(r'(T|\s)\d{1,2}[:：]\d{1,2}').hasMatch(text) ||
          RegExp(r'\d{1,2}[:：]\d{1,2}').hasMatch(text),
    );
  }
  final parsed = SmartDateParser.parse(text, now: now);
  if (!parsed.isSuccess) return null;
  return _ParsedScheduleTime(
    parsed.dateTime!,
    hasTimeOfDay: parsed.hasTimeOfDay,
  );
}

bool? _parseBoolValue(Object? value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value.toString().trim().toLowerCase();
  if (_isBlankAiValue(text)) return null;
  if (const {
    'true',
    'yes',
    'y',
    '1',
    '是',
    '需要',
    '开启',
    '开',
    '有',
  }.contains(text)) {
    return true;
  }
  if (const {
    'false',
    'no',
    'n',
    '0',
    '否',
    '不需要',
    '关闭',
    '关',
    '无',
  }.contains(text)) {
    return false;
  }
  return null;
}

List<String> _parseSubtasks(Object? value) {
  final rawItems = <Object?>[];
  if (value is List) {
    rawItems.addAll(value);
  } else if (value is String && !_isBlankAiValue(value)) {
    rawItems.addAll(value.split(RegExp(r'[\n；;]+')));
  }
  return rawItems
      .map((item) => item.toString().trim())
      .map((item) => item.replaceFirst(RegExp(r'^[\-\*\d\.\s]+'), '').trim())
      .where((item) => item.isNotEmpty)
      .take(8)
      .toList(growable: false);
}

class _ParsedScheduleTime {
  final DateTime dateTime;
  final bool hasTimeOfDay;

  const _ParsedScheduleTime(this.dateTime, {required this.hasTimeOfDay});
}

String _friendlyAiError(String raw) {
  final text = raw.trim();
  final lower = text.toLowerCase();
  if (text.isEmpty) return 'AI 服务没有返回有效内容';
  if (text.contains('AI 功能未启用')) return 'AI 功能未启用，请先在管理后台开启';
  if (text.contains('API Key')) return '管理员尚未配置 AI API Key';
  if (text.contains('额度') || text.contains('429')) return '今日 AI 额度已用尽';
  if (text.contains('超时')) return 'AI 服务响应超时，请稍后重试';
  if (text.contains('404') || lower.contains('not found')) {
    return 'AI 代理或上游模型不可用，请检查后端 /api/ai/chat、Base URL 和模型名称';
  }
  if (text.contains('503')) return 'AI 服务暂不可用，请检查管理后台配置';
  if (text.contains('正文为空') || text.contains('调大 max_tokens')) {
    return text.replaceFirst(RegExp(r'^502:\s*'), '');
  }
  if (text.contains('上游不可达')) {
    final detail = text.replaceFirst(RegExp(r'^(502:\s*)?上游不可达[:：]\s*'), '');
    return 'AI 上游服务不可达：$detail';
  }
  if (text.contains('502')) {
    final detail = text.replaceFirst(RegExp(r'^502:\s*'), '');
    return 'AI 代理处理失败：$detail';
  }
  if (text.contains('401') || text.contains('403')) return 'AI 密钥无效或没有模型权限';
  return text;
}

/// 持久化的 AI 解读条目（周报、日记复盘、统计报告解读共用）。
///
/// 旧的 JSON（没有 `kind`/`reportContext`/`dataThrough`）仍然可读；
/// 缺失或损坏的周期元数据只会让该条退化为“无周期”记录，不会丢正文。
class AiReviewEntry {
  final String id;
  final DateTime createdAt;
  final String content;
  final String summary;
  final String model;
  final String kind;

  /// 统计报告解读所属的自然周期；旧条目为 null。
  final AiReportContext? reportContext;

  /// 生成时的数据截止日（浮动日历日，不做时区换算）。
  final DateTime? dataThrough;

  const AiReviewEntry({
    required this.id,
    required this.createdAt,
    required this.content,
    required this.summary,
    this.model = '',
    this.kind = '',
    this.reportContext,
    this.dataThrough,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'content': content,
      'summary': summary,
      'model': model,
      'kind': kind,
    };
    final context = reportContext;
    if (context != null) json['reportContext'] = context.toJson();
    final through = dataThrough;
    if (through != null) json['dataThrough'] = _calendarDateKey(through);
    return json;
  }

  factory AiReviewEntry.fromJson(Map<String, dynamic> j) => AiReviewEntry(
    id: j['id'].toString(),
    createdAt: DateTime.parse(j['createdAt']),
    content: (j['content'] ?? '').toString(),
    summary: (j['summary'] ?? '').toString(),
    model: (j['model'] ?? '').toString(),
    kind: (j['kind'] ?? '').toString(),
    reportContext: AiReportContext.tryFromJson(j['reportContext']),
    dataThrough: _tryCalendarDate(j['dataThrough']),
  );
}

/// 周期解读任务的私有附加信息（模型、摘要、快照日），只用于存档失败后的重试。
class _ScopedReportDraft {
  final String model;
  final String summary;
  final DateTime? dataThrough;

  const _ScopedReportDraft({
    required this.model,
    required this.summary,
    this.dataThrough,
  });
}

String _calendarDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime? _tryCalendarDate(Object? raw) {
  if (raw == null) return null;
  final text = raw.toString().trim();
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return StatisticsSpan.calendarDate(parsed);
}

class AiException implements Exception {
  final String message;
  const AiException(this.message);
  @override
  String toString() => message;
}
