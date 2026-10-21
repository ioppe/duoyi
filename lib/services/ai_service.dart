import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/ai_todo_breakdown.dart';
import '../core/app_clock.dart';
import '../core/app_config.dart';
import '../core/local_timezone_resolver.dart';
import '../core/smart_date_parser.dart';
import '../core/smart_todo_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/diary_deep_review.dart';
import '../models/diary_entry.dart';
import '../models/goal.dart'
    show
        ReminderConfig,
        ReminderKind,
        ReminderPlan,
        ReminderRule,
        ReminderRuleType;
import '../models/todo.dart';
import 'api_client.dart';

/// AI 客户端：**不再持有任何 key/base_url**，所有调用通过 `/api/ai/chat`
/// 由已登录用户的 token 代理到管理员在服务端配置好的上游。
///
/// `enabled` 状态来自 `/api/config`。
class AiService extends ChangeNotifier {
  ApiClient _client = ApiClient();
  bool _enabled = false;
  String _model = '';
  List<AiReviewEntry> _reviewHistory = [];
  int _storageGeneration = 0;

  bool get enabled => _enabled;
  bool get isConfigured => _enabled;
  String get model => _model;
  List<AiReviewEntry> get reviewHistory => List.unmodifiable(_reviewHistory);

  static const _kReviewHistory = 'ai_review_history';
  static const weeklyReviewKind = 'weekly_review';

  void attachClient(ApiClient client) {
    _client = client;
  }

  void updateFromServerConfig(Map<String, dynamic> cfg) {
    _enabled = cfg['ai_enabled'] == true;
    _model = (cfg['ai_model'] ?? '').toString();
    notifyListeners();
  }

  Future<void> loadFromStorage() async {
    final generation = _storageGeneration;
    final p = await SharedPreferences.getInstance();
    if (generation != _storageGeneration) return;
    final raw = p.getStringList(_kReviewHistory) ?? [];
    _reviewHistory = raw
        .map((e) {
          try {
            return AiReviewEntry.fromJson(jsonDecode(e));
          } catch (_) {
            return null;
          }
        })
        .whereType<AiReviewEntry>()
        .toList();
    notifyListeners();
  }

  void resetLocalState() {
    _storageGeneration++;
    _reviewHistory = [];
    notifyListeners();
  }

  Future<void> _saveHistory() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
      _kReviewHistory,
      _reviewHistory.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<void> deleteReview(String id) async {
    _reviewHistory.removeWhere((e) => e.id == id);
    notifyListeners();
    await _saveHistory();
  }

  Future<void> clearReviewHistory() async {
    _reviewHistory.clear();
    notifyListeners();
    await _saveHistory();
  }

  Future<String> _chat(
    String systemPrompt,
    String userPrompt, {
    double temperature = 0.4,
    int maxTokens = 512,
  }) async {
    if (!_enabled) throw const AiException('AI 功能未启用，请联系管理员');
    try {
      final res = await _client.post('/api/ai/chat', {
        'system': systemPrompt,
        'user': userPrompt,
        'temperature': temperature,
        'max_tokens': maxTokens,
      }, AppConfig.aiTimeout);
      final content = (res['content'] ?? '').toString();
      return content;
    } on ApiException catch (e) {
      throw AiException(_friendlyAiError(e.message));
    }
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
    if (!_enabled) return baseDraft.withSource(AiScheduleSource.localParser);

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
        maxTokens: 420,
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
      maxTokens: 900,
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
      maxTokens: 16,
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
      maxTokens: 260,
    );
    final review = _normalizeWeeklyReview(
      out,
      periodLabel: periodLabel,
      completedTodos: completedTodos,
      totalTodos: totalTodos,
      weeklyFocusMinutes: weeklyFocusMinutes,
      habitStreak: habitStreak,
    );
    final entry = AiReviewEntry(
      id: createdAt.millisecondsSinceEpoch.toString(),
      createdAt: createdAt,
      content: review,
      summary: summary,
      model: _model,
      kind: weeklyReviewKind,
    );
    _reviewHistory.insert(0, entry);
    if (_reviewHistory.length > 50) {
      _reviewHistory = _reviewHistory.sublist(0, 50);
    }
    await _saveHistory();
    notifyListeners();
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

  Future<String> personalizedReportReview({
    required String periodLabel,
    required String reportMarkdown,
  }) async {
    final out = await _chat(
      '你是多仪的云端效率报告分析师。基于用户的周期统计报告，输出一段结构化中文个性化解读。'
          '要求：1) 先给一句总判断；2) 分析待办、专注、习惯、时间足迹中最值得保留和最需要调整的点；'
          '3) 给出未来 7 天 3 条可执行动作；4) 不要泛泛鼓励，不要重复原始数据堆砌。',
      '周期：$periodLabel\n\n$reportMarkdown',
      temperature: 0.5,
      maxTokens: 900,
    );
    final entry = AiReviewEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      content: out,
      summary: '统计报告 AI 解读：$periodLabel',
      model: _model,
    );
    _reviewHistory.insert(0, entry);
    if (_reviewHistory.length > 50) {
      _reviewHistory = _reviewHistory.sublist(0, 50);
    }
    await _saveHistory();
    notifyListeners();
    return out;
  }

  Future<String> deepDiaryReview({
    required Iterable<DiaryEntry> entries,
    DateTime? today,
  }) async {
    final prompt = DiaryDeepReviewBuilder.build(entries: entries, today: today);
    final out = await _chat(
      prompt.systemPrompt,
      prompt.userPrompt,
      temperature: 0.55,
      maxTokens: 900,
    );
    final entry = AiReviewEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      content: out,
      summary: '日记深度复盘：${prompt.summary}',
      model: _model,
    );
    _reviewHistory.insert(0, entry);
    if (_reviewHistory.length > 50) {
      _reviewHistory = _reviewHistory.sublist(0, 50);
    }
    await _saveHistory();
    notifyListeners();
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
    final out = await _chat(
      '你是一个温柔且实用的效率教练。基于$periodLabel完成情况写一段 80-150 字的中文回顾，'
      '开头必须明确写“$periodLabel回顾：”。语气积极不空洞，先肯定 1-2 点亮点，'
      '再提 1-2 个具体可执行的下周建议。不要使用 Markdown、表格、emoji、加粗或分隔线。',
      summary,
      temperature: 0.6,
      maxTokens: 400,
    );
    final entryTime = createdAt ?? DateTime.now();
    final entry = AiReviewEntry(
      id: entryTime.millisecondsSinceEpoch.toString(),
      createdAt: entryTime,
      content: out,
      summary: summary,
      model: _model,
      kind: kind,
    );
    _reviewHistory.insert(0, entry);
    if (_reviewHistory.length > 50) {
      _reviewHistory = _reviewHistory.sublist(0, 50);
    }
    await _saveHistory();
    notifyListeners();
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
  if (text.contains('上游不可达') || text.contains('502')) {
    return 'AI 上游服务不可达，请检查 Base URL、网络或模型配置';
  }
  if (text.contains('401') || text.contains('403')) return 'AI 密钥无效或没有模型权限';
  return text;
}

/// 持久化的 AI 周报条目。
class AiReviewEntry {
  final String id;
  final DateTime createdAt;
  final String content;
  final String summary;
  final String model;
  final String kind;

  const AiReviewEntry({
    required this.id,
    required this.createdAt,
    required this.content,
    required this.summary,
    this.model = '',
    this.kind = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'content': content,
    'summary': summary,
    'model': model,
    'kind': kind,
  };

  factory AiReviewEntry.fromJson(Map<String, dynamic> j) => AiReviewEntry(
    id: j['id'].toString(),
    createdAt: DateTime.parse(j['createdAt']),
    content: (j['content'] ?? '').toString(),
    summary: (j['summary'] ?? '').toString(),
    model: (j['model'] ?? '').toString(),
    kind: (j['kind'] ?? '').toString(),
  );
}

class AiException implements Exception {
  final String message;
  const AiException(this.message);
  @override
  String toString() => message;
}
