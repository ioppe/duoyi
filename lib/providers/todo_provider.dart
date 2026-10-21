import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/completion_visibility_policy.dart';
import '../core/domain_event_bus.dart';
import '../core/todo_kanban.dart';
import '../models/time_entry.dart';
import '../models/todo.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/reminder_scheduler.dart';
import 'cloud_sync_provider.dart';
import 'time_audit_provider.dart';

class TodoImportSummary {
  final int inserted;
  final int skippedDuplicates;

  const TodoImportSummary({
    required this.inserted,
    required this.skippedDuplicates,
  });
}

class TodoProvider extends ChangeNotifier {
  static const Duration _reminderSyncTimeout = Duration(seconds: 5);

  /// 超过该条数时，持久化编码放到后台 isolate 执行：主 isolate 只付出
  /// 对象图快照拷贝的成本，JSON 编码不再阻塞 UI 帧。
  static const int _isolateEncodeMinItems = 500;

  /// 存储字符串超过该长度时，启动解码放到后台 isolate 执行
  /// （约对应数百条待办）。
  static const int _isolateDecodeMinChars = 60000;

  /// 确认等待上限可在测试中缩短；生产默认 5 秒。
  @visibleForTesting
  Duration reminderSyncTimeout = _reminderSyncTimeout;

  List<TodoItem> _todos = [];
  bool _storageLoaded = false;
  Future<void>? _storageLoadFuture;
  Future<void> _storageWriteQueue = Future<void>.value();
  int _storageGeneration = 0;
  final Set<String> _inFlightCreateKeys = {};
  final Set<String> _inFlightUpdateTodoIds = {};
  final Set<String> _inFlightCompleteTodoIds = {};
  final Set<String> _inFlightDeleteTodoIds = {};
  final Set<String> _inFlightQuadrantTodoIds = {};
  final Set<String> _inFlightPriorityTodoIds = {};
  final Set<String> _inFlightKanbanTodoIds = {};
  final Set<String> _inFlightScheduleTodayTodoIds = {};
  final Set<String> _inFlightReorderKeys = {};
  final Set<String> _inFlightListGroupWorkspaceKeys = {};
  final Set<String> _inFlightArchiveKeys = {};
  final Set<String> _inFlightPostponeKeys = {};
  final Set<String> _inFlightSubtaskCreateKeys = {};
  final Set<String> _inFlightSubtaskToggleKeys = {};
  final Set<String> _inFlightSubtaskDeleteKeys = {};
  final Set<String> _inFlightSubtaskReorderKeys = {};

  /// 可选的 [ReminderScheduler] 引用，由 `main.dart` 在构造完整对象图后注入。
  ///
  /// 设计上允许 `null`：TodoProvider 的持久化路径**不**强依赖调度器。
  /// 注入后，创建、编辑、完成、恢复、删除和顺延会主动重同步，确保系统
  /// 队列及时注册或取消；`main.dart` 的监听重同步仍作为兜底。
  ReminderScheduler? _scheduler;
  TimeAuditProvider? _timeAudit;
  String? _lastReminderSyncIssue;
  String? _lastReminderScheduleIssue;
  DateTime? _lastReminderScheduleIssueAt;
  DateTime? _lastReminderSyncAttemptAt;
  DateTime? _lastReminderSyncSucceededAt;

  /// 注入或解绑调度器；传 `null` 即解绑。
  // ignore: use_setters_to_change_properties
  set scheduler(ReminderScheduler? s) {
    _scheduler = s;
    if (s != null && _lastReminderSyncIssue == 'reminder_scheduler_missing') {
      _lastReminderSyncIssue = null;
    }
  }

  // ignore: use_setters_to_change_properties
  set timeAudit(TimeAuditProvider? provider) {
    _timeAudit = provider;
  }

  List<TodoItem> get todos => _todos;
  String? get lastReminderSyncIssue => _lastReminderSyncIssue;
  String? get lastReminderScheduleIssue => _lastReminderScheduleIssue;
  DateTime? get lastReminderScheduleIssueAt => _lastReminderScheduleIssueAt;
  DateTime? get lastReminderSyncAttemptAt => _lastReminderSyncAttemptAt;
  DateTime? get lastReminderSyncSucceededAt => _lastReminderSyncSucceededAt;

  int _compareTodos(TodoItem a, TodoItem b) {
    if (a.sortOrder != b.sortOrder) {
      return a.sortOrder.compareTo(b.sortOrder);
    }
    // 次序相同时按优先级倒序，再按创建时间
    final p = b.priority.rank.compareTo(a.priority.rank);
    if (p != 0) return p;
    return a.createdAt.compareTo(b.createdAt);
  }

  int _revision = 0;

  /// 每次 [notifyListeners] 自增；供界面做派生数据 memo 化，避免
  /// 每帧重复过滤/分组整份待办列表。
  int get revision => _revision;

  void _notify() {
    _revision++;
    // 大列表下每次 notify 全量 sort 是明显热点；大多数变更不改变排序，
    // 先做一次 O(n) 有序性检查，已有序时直接跳过 sort。
    var sorted = true;
    for (var i = 1; i < _todos.length; i++) {
      if (_compareTodos(_todos[i - 1], _todos[i]) > 0) {
        sorted = false;
        break;
      }
    }
    if (!sorted) {
      _todos.sort(_compareTodos);
    }
    notifyListeners();
  }

  // --- Queries ---

  List<TodoItem> getTodosForDate(DateTime date) {
    final key = _dateKey(date);
    return _todos.where((t) => _dateKey(t.date) == key).toList();
  }

  /// "今日"视图可见的 todos（不包含已完成、归档、未到进入日期与已逾期项）。
  ///
  /// 与 [activeTodos] 不同：后者是"未完成"过滤，跨日通用；这里严格对齐
  /// `CompletionVisibilityPolicy.shouldShowInToday`，只返回
  /// 从进入日期起、到截止日期当天的未完成条目；无截止日期则从进入日期起持续展示。
  /// 供 Today 列表 / Today Widget 复用，避免各处重复判断。
  List<TodoItem> visibleTodayTodos(DateTime now) => _todos
      .where((t) => CompletionVisibilityPolicy.shouldShowInToday(t, now))
      .toList();

  List<TodoItem> get activeTodos =>
      _todos.where((t) => !t.isCompleted).toList();
  List<TodoItem> get visibleListTodos => _todos
      .where(
        (t) =>
            CompletionVisibilityPolicy.visualState(t) !=
            TodoVisualState.archived,
      )
      .toList();
  List<TodoItem> get completedTodos =>
      _todos.where((t) => t.isCompleted).toList();

  List<TodoItem> get overdueTodos => _todos.where((t) => t.isOverdue).toList();

  Map<EisenhowerQuadrant, List<TodoItem>> get quadrantGroups {
    final map = <EisenhowerQuadrant, List<TodoItem>>{};
    for (final q in EisenhowerQuadrant.values) {
      map[q] = visibleListTodos.where((t) => t.quadrant == q).toList();
    }
    return map;
  }

  List<TodoItem> getQuadrantTodos(EisenhowerQuadrant q) =>
      visibleListTodos.where((t) => t.quadrant == q).toList();

  Map<String, List<TodoItem>> get listGroupedTodos {
    final map = <String, List<TodoItem>>{};
    for (final t in visibleListTodos) {
      final key = t.listGroupName ?? '未分组';
      map.putIfAbsent(key, () => []).add(t);
    }
    return map;
  }

  Set<String> get listGroupNames {
    final names = <String>{};
    for (final t in todos) {
      if (t.listGroupName != null && t.listGroupName!.isNotEmpty) {
        names.add(t.listGroupName!);
      }
    }
    return names;
  }

  String? workspaceForListGroup(String groupName) {
    final group = visibleListTodos.where(
      (todo) => (todo.listGroupName ?? '未分组') == groupName,
    );
    for (final todo in group) {
      if (todo.workspaceId != 'private' && todo.workspaceId.isNotEmpty) {
        return todo.workspaceId;
      }
    }
    return null;
  }

  Set<String> get allTags {
    final tags = <String>{};
    for (final t in _todos) {
      tags.addAll(t.tags);
    }
    return tags;
  }

  List<TodoItem> byTag(String tag) =>
      _todos.where((t) => t.tags.contains(tag)).toList();

  // --- Persistence ---

  Future<void> loadFromStorage({bool force = false}) async {
    if (!force) {
      if (_storageLoaded) return;
      final running = _storageLoadFuture;
      if (running != null) return running;
      final generation = _storageGeneration;
      final future = _loadFromStorage(generation);
      _storageLoadFuture = future;
      try {
        await future;
      } finally {
        _storageLoadFuture = null;
      }
      return;
    }
    // 云同步回写 SharedPreferences 后必须强制重读：内存列表若停留在旧快照，
    // 下一次本地写入会把同步结果整表覆盖，重启后服务端数据又“回来”。
    // 强制重读与写入共用同一条串行队列——先落盘未写入的内存改动再重读，
    // 重读之后的写入看到的是包含同步结果的最新列表。
    final reload = _storageWriteQueue.then(
      (_) => _loadFromStorage(_storageGeneration),
    );
    _storageWriteQueue = reload.catchError((Object e, StackTrace st) {
      debugPrint('[TodoProvider] forced reload from storage failed: $e\n$st');
    });
    await reload;
  }

  void resetLocalState() {
    _storageGeneration++;
    _todos = [];
    _storageLoaded = false;
    _storageLoadFuture = null;
    _lastReminderSyncIssue = null;
    _lastReminderScheduleIssue = null;
    _lastReminderScheduleIssueAt = null;
    _lastReminderSyncAttemptAt = null;
    _lastReminderSyncSucceededAt = null;
    _notify();
  }

  Future<void> _loadFromStorage(int generation) async {
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return;
    }
    final data = prefs.getString('todos');
    if (data != null && data.isNotEmpty) {
      List<TodoItem> parsed = <TodoItem>[];
      var shouldRewrite = false;
      try {
        if (data.length >= _isolateDecodeMinChars) {
          // 大列表的 JSON 解码 + 逐条 fromJson 会阻塞主 isolate 数十毫秒，
          // 且发生在启动关键路径上；挪到后台 isolate，容错语义保持一致。
          final result = await compute(_decodeTodoStoragePayload, data);
          if (generation != _storageGeneration) return;
          parsed = result.items;
          shouldRewrite = result.rewrite;
          if (result.notAList) {
            debugPrint(
              '[TodoProvider] ignored invalid todos storage: not a list',
            );
          }
          final errorDetail = result.errorDetail;
          if (errorDetail != null) {
            debugPrint(
              '[TodoProvider] todos storage decode failed: $errorDetail',
            );
          }
        } else {
          final decoded = json.decode(data);
          if (decoded is List) {
            for (var i = 0; i < decoded.length; i++) {
              final raw = decoded[i];
              try {
                if (raw is! Map) {
                  shouldRewrite = true;
                  debugPrint(
                    '[TodoProvider] skipped invalid todo[$i]: not a map',
                  );
                  continue;
                }
                parsed.add(TodoItem.fromJson(Map<String, dynamic>.from(raw)));
              } catch (e, st) {
                shouldRewrite = true;
                debugPrint('[TodoProvider] skipped invalid todo[$i]: $e\n$st');
              }
            }
          } else {
            shouldRewrite = true;
            debugPrint(
              '[TodoProvider] ignored invalid todos storage: not a list',
            );
          }
        }
        _todos = _dedupeTodosById(
          parsed,
          onDuplicate: () => shouldRewrite = true,
        );
      } catch (e, st) {
        shouldRewrite = true;
        debugPrint('[TodoProvider] todos storage decode failed: $e\n$st');
      }
      if (shouldRewrite) {
        if (generation != _storageGeneration) return;
        await prefs.setString(
          'todos_corrupt_backup_${DateTime.now().millisecondsSinceEpoch}',
          data,
        );
        if (generation != _storageGeneration) return;
        // 内联写入重写结果，不经 _writeToStorage 的队列串联——
        // 强制重读自身占用 _storageWriteQueue 尾部，再入队会循环等待死锁。
        await _writeTodosSnapshot();
        if (generation != _storageGeneration) return;
      }
    }
    if (generation != _storageGeneration) return;
    _storageLoaded = true;
    _notify();
  }

  /// 同一 id 出现多条属于存储异常（例如同步应用与本地写入交叠留下的重复），
  /// 保留 `updatedAt` 最新的一条，避免列表重复展示并被再次同步放大。
  List<TodoItem> _dedupeTodosById(
    List<TodoItem> items, {
    VoidCallback? onDuplicate,
  }) {
    if (items.length < 2) return items;
    final byId = <String, TodoItem>{};
    final order = <String>[];
    var duplicated = false;
    for (final todo in items) {
      final existing = byId[todo.id];
      if (existing == null) {
        byId[todo.id] = todo;
        order.add(todo.id);
        continue;
      }
      duplicated = true;
      if (existing.updatedAt.isBefore(todo.updatedAt)) {
        byId[todo.id] = todo;
      }
    }
    if (!duplicated) return items;
    onDuplicate?.call();
    return [for (final id in order) byId[id]!];
  }

  Future<void> _ensureStorageLoaded() async {
    if (_storageLoaded) return;
    debugPrint('[TodoProvider] waiting for local todo hydration before write');
    await loadFromStorage();
  }

  Future<void> _saveToStorage() async {
    await _ensureStorageLoaded();
    await _writeToStorage();
  }

  /// 将当前内存列表编码并写入存储，不做队列串联。
  /// 只应在上游已与写入队列串行化的上下文调用：
  /// - `_writeToStorage` 的队列任务内部；
  /// - `_loadFromStorage` 的损坏重写分支（加载流程已与队列串行：
  ///   pending 写入先于加载执行，加载期间新提交的写入链在加载完成之后；
  ///   若此处再走队列，强制重读会链到自身导致循环等待死锁）。
  Future<void> _writeTodosSnapshot() async {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    // 大列表的 JSON 编码会阻塞主 isolate 数十毫秒（2000 条 ≈ 20ms），
    // 挪到后台 isolate 执行；模型对象图在发送时自动快照拷贝，
    // 因此这里直接传列表，不需要在主 isolate 先做 toJson。
    final data = _todos.length >= _isolateEncodeMinItems
        ? await compute(_encodeTodoStoragePayload, List<TodoItem>.of(_todos))
        : json.encode(_todos.map((e) => e.toJson()).toList());
    final prefs = await SharedPreferences.getInstance();
    if (generation != _storageGeneration ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return;
    }
    await prefs.setString('todos', data);
  }

  Future<void> _writeToStorage() async {
    final write = _storageWriteQueue.then((_) => _writeTodosSnapshot());
    _storageWriteQueue = write.catchError((Object e, StackTrace st) {
      debugPrint('[TodoProvider] queued local todo write failed: $e\n$st');
    });
    await write;
  }

  // --- CRUD ---

  Future<void> _syncTodoRemindersNow({String? reportTodoId}) async {
    _lastReminderSyncAttemptAt = DateTime.now();
    _lastReminderScheduleIssue = null;
    _lastReminderScheduleIssueAt = null;
    final scheduler = _scheduler;
    if (scheduler == null) {
      // 调度器缺失是稳态（初始化完成前每次 CRUD 都会命中本分支），
      // 逐次打日志会淹没控制台/测试输出；改为每个缺失周期只提示一次，
      // 状态字段仍逐次记录，诊断语义不变。
      if (_lastReminderSyncIssue != 'reminder_scheduler_missing') {
        debugPrint('[TodoProvider] reminder sync skipped: scheduler missing');
      }
      _lastReminderSyncIssue = 'reminder_scheduler_missing';
      return;
    }
    try {
      final syncStartedAt = DateTime.now();
      if (reportTodoId == null) {
        await _awaitReminderSyncWithLateConfirmation(
          scheduler.syncTodos(List.of(_todos)),
        );
      } else {
        final outcome = scheduler.syncTodosAndGetTodoFailure(
          List.of(_todos),
          reportTodoId,
        );
        String? failure;
        var confirmed = false;
        try {
          failure = await outcome.timeout(reminderSyncTimeout);
          confirmed = true;
        } on TimeoutException {
          // 启动等场景调度队列繁忙时，确认超时不代表注册失败：
          // 底层同步继续执行，完成后按真实结果补记，避免误导性的“注册失败”提示。
          unawaited(
            outcome.then((lateFailure) {
              if (lateFailure == null) return;
              _lastReminderScheduleIssue = lateFailure;
              _lastReminderScheduleIssueAt = syncStartedAt;
              notifyListeners();
            }),
          );
        }
        if (confirmed && failure != null) {
          _lastReminderScheduleIssue = failure;
          _lastReminderScheduleIssueAt = syncStartedAt;
        }
      }
      _lastReminderSyncIssue = null;
      _lastReminderSyncSucceededAt = DateTime.now();
    } catch (e, st) {
      _lastReminderSyncIssue = e.toString();
      debugPrint('[TodoProvider] reminder sync failed: $e\n$st');
    }
  }

  /// 等待提醒同步完成；超时后不当作失败上报，改为在后台等它跑完，
  /// 真正抛错时才补记同步诊断。
  Future<void> _awaitReminderSyncWithLateConfirmation(
    Future<void> pending,
  ) async {
    try {
      await pending.timeout(reminderSyncTimeout);
    } on TimeoutException {
      unawaited(
        pending.then(
          (_) {
            _lastReminderSyncSucceededAt = DateTime.now();
            notifyListeners();
          },
          onError: (Object e, StackTrace st) {
            _lastReminderSyncIssue = e.toString();
            debugPrint('[TodoProvider] reminder sync failed late: $e\n$st');
            notifyListeners();
          },
        ),
      );
    }
  }

  Future<void> addTodo(
    TodoItem todo, {
    bool waitForReminderSync = true,
    bool reportReminderScheduleFailure = false,
  }) async {
    await _ensureStorageLoaded();
    final createKey = _createInFlightDuplicateKey(todo);
    final claimed = _claimInFlightKeys(
      _inFlightCreateKeys,
      [createKey],
      label: 'todo create',
      duplicateMessage: '待办正在创建中，请勿重复提交',
    );
    try {
      _todos.add(todo);
      DomainEventBus.instance.publish(
        DomainEvent(type: DomainEventType.todoCreated, objectId: todo.id),
      );
      _notify();
      await _saveToStorage();
      if (waitForReminderSync) {
        await _syncTodoRemindersNow(
          reportTodoId: reportReminderScheduleFailure ? todo.id : null,
        );
      } else {
        unawaited(_syncTodoRemindersNow());
      }
    } finally {
      _inFlightCreateKeys.removeAll(claimed);
    }
  }

  Future<TodoImportSummary> importTodos(Iterable<TodoItem> imported) async {
    await _ensureStorageLoaded();
    final incoming = imported.toList();
    if (incoming.isEmpty) {
      return const TodoImportSummary(inserted: 0, skippedDuplicates: 0);
    }

    final seen = _todos.map(_importDuplicateKey).toSet();
    final currentMaxSortOrder = _todos.isEmpty
        ? -1
        : _todos.map((todo) => todo.sortOrder).reduce((a, b) => a > b ? a : b);
    var nextSortOrder = currentMaxSortOrder + 1;
    var inserted = 0;
    var skippedDuplicates = 0;

    for (final todo in incoming) {
      final key = _importDuplicateKey(todo);
      if (seen.contains(key)) {
        skippedDuplicates++;
        continue;
      }
      seen.add(key);
      final next = todo.copyWith(sortOrder: nextSortOrder++);
      _todos.add(next);
      inserted++;
      DomainEventBus.instance.publish(
        DomainEvent(type: DomainEventType.todoCreated, objectId: next.id),
      );
    }

    if (inserted == 0) {
      return TodoImportSummary(
        inserted: 0,
        skippedDuplicates: skippedDuplicates,
      );
    }
    await _saveToStorage();
    _notify();
    await _syncTodoRemindersNow();
    return TodoImportSummary(
      inserted: inserted,
      skippedDuplicates: skippedDuplicates,
    );
  }

  Future<void> updateTodo(
    String id,
    TodoItem updated, {
    bool waitForReminderSync = true,
  }) async {
    final claimed = _claimInFlightKeys(
      _inFlightUpdateTodoIds,
      [id],
      label: 'todo update',
      duplicateMessage: '待办保存正在进行中，请勿重复提交',
      throwWhenDuplicate: false,
    );
    if (claimed.isEmpty) return;
    try {
      await _updateTodoLocked(
        id,
        updated,
        waitForReminderSync: waitForReminderSync,
      );
    } finally {
      _inFlightUpdateTodoIds.removeAll(claimed);
    }
  }

  Future<void> _updateTodoLocked(
    String id,
    TodoItem updated, {
    required bool waitForReminderSync,
  }) async {
    await _ensureStorageLoaded();
    final idx = _todos.indexWhere((t) => t.id == id);
    if (idx != -1) {
      final prev = _todos[idx];
      var next = updated.isCompleted && updated.completedAt == null
          ? updated.copyWith(completedAt: DateTime.now())
          : updated;
      // Commit edited children and their aggregate as one persisted task.
      final childrenChanged =
          jsonEncode(prev.subtasks.map((task) => task.toJson()).toList()) !=
          jsonEncode(next.subtasks.map((task) => task.toJson()).toList());
      if (childrenChanged &&
          next.autoToggleByChildren &&
          next.subtasks.isNotEmpty) {
        final allDone = next.subtasks.every((task) => task.isCompleted);
        if (allDone && !next.isCompleted) {
          next = next.copyWith(isCompleted: true, completedAt: DateTime.now());
        } else if (!allDone && next.isCompleted) {
          next = next.copyWith(isCompleted: false, completedAt: null);
        }
      }
      if (!prev.isCompleted && next.isCompleted) {
        next = next.copyWith(kanbanColumnId: defaultKanbanDoneColumnId);
      } else if (prev.isCompleted &&
          !next.isCompleted &&
          next.kanbanColumnId == defaultKanbanDoneColumnId) {
        next = next.copyWith(kanbanColumnId: defaultKanbanPendingColumnId);
      }
      _todos[idx] = next;
      if (!prev.isCompleted && next.isCompleted) {
        DomainEventBus.instance.publish(
          DomainEvent(type: DomainEventType.todoCompleted, objectId: next.id),
        );
      }
      await _saveToStorage();
      _notify();
      if (waitForReminderSync) {
        await _syncTodoRemindersNow();
      } else {
        unawaited(_syncTodoRemindersNow());
      }
      if (next.isCompleted) {
        await _timeAudit?.recordTodoCompletion(
          next,
          completedAt: next.completedAt,
        );
      } else if (prev.isCompleted && !next.isCompleted) {
        await _timeAudit?.removeTodoCompletion(
          prev,
          completedAt: prev.completedAt,
        );
      }
    }
  }

  Future<int> completeTodos(
    Iterable<String> ids, {
    bool recordCompletionTime = true,
  }) async {
    final requested = ids.toSet();
    if (requested.isEmpty) return 0;
    final selected = _claimInFlightKeys(
      _inFlightCompleteTodoIds,
      requested,
      label: 'todo complete',
      duplicateMessage: '待办完成操作正在进行中，请勿重复提交',
      allowPartial: true,
      throwWhenDuplicate: false,
    );
    if (selected.isEmpty) return 0;
    try {
      return await _completeTodosLocked(
        selected,
        recordCompletionTime: recordCompletionTime,
      );
    } finally {
      _inFlightCompleteTodoIds.removeAll(selected);
    }
  }

  Future<int> _completeTodosLocked(
    Set<String> selected, {
    required bool recordCompletionTime,
  }) async {
    await _ensureStorageLoaded();
    final completed = <TodoItem>[];
    var changed = 0;
    for (var i = 0; i < _todos.length; i++) {
      final prev = _todos[i];
      if (!selected.contains(prev.id) || prev.isCompleted) continue;

      final next = prev.copyWith(
        isCompleted: true,
        completedAt: DateTime.now(),
        kanbanColumnId: defaultKanbanDoneColumnId,
      );
      _todos[i] = next;
      completed.add(next);
      changed++;
      DomainEventBus.instance.publish(
        DomainEvent(type: DomainEventType.todoCompleted, objectId: next.id),
      );

      if (prev.recurrence.isActive) {
        final recurring = _nextRecurringTodo(prev);
        if (recurring != null) _todos.add(recurring);
      }
    }

    if (changed == 0) return 0;
    await _saveToStorage();
    _notify();

    if (recordCompletionTime) {
      for (final todo in completed) {
        await _timeAudit?.recordTodoCompletion(
          todo,
          completedAt: todo.completedAt,
        );
      }
    }
    await _syncTodoRemindersNow();
    return changed;
  }

  Future<int> reopenTodos(Iterable<String> ids) async {
    final requested = ids.toSet();
    if (requested.isEmpty) return 0;
    final selected = _claimInFlightKeys(
      _inFlightCompleteTodoIds,
      requested,
      label: 'todo reopen',
      duplicateMessage: '待办恢复操作正在进行中，请勿重复提交',
      allowPartial: true,
      throwWhenDuplicate: false,
    );
    if (selected.isEmpty) return 0;
    try {
      return await _reopenTodosLocked(selected);
    } finally {
      _inFlightCompleteTodoIds.removeAll(selected);
    }
  }

  Future<int> _reopenTodosLocked(Set<String> selected) async {
    await _ensureStorageLoaded();
    final reopened = <TodoItem>[];
    var changed = 0;
    for (var i = 0; i < _todos.length; i++) {
      final prev = _todos[i];
      if (!selected.contains(prev.id) || !prev.isCompleted) continue;
      _todos[i] = prev.copyWith(
        isCompleted: false,
        completedAt: null,
        kanbanColumnId: prev.kanbanColumnId == defaultKanbanDoneColumnId
            ? defaultKanbanPendingColumnId
            : prev.kanbanColumnId,
      );
      reopened.add(prev);
      changed++;
    }

    if (changed == 0) return 0;
    await _saveToStorage();
    _notify();

    for (final todo in reopened) {
      await _timeAudit?.removeTodoCompletion(
        todo,
        completedAt: todo.completedAt,
      );
    }
    await _syncTodoRemindersNow();
    return changed;
  }

  /// 切换完成状态。若任务带有重复规则并且本次变为已完成，自动克隆一条下次的任务。
  ///
  /// [recordCompletionTime] 为 `true` 时，在完成状态变更后会自动写入时间足迹；
  /// 由 UI 层统一决定是否要先弹出"顺手记耗时"对话框，或改用自定义时长。
  Future<void> toggleTodo(String id, {bool recordCompletionTime = true}) async {
    final claimed = _claimInFlightKeys(
      _inFlightCompleteTodoIds,
      [id],
      label: 'todo toggle',
      duplicateMessage: '待办状态更新正在进行中，请勿重复提交',
      throwWhenDuplicate: false,
    );
    if (claimed.isEmpty) return;
    try {
      await _toggleTodoLocked(id, recordCompletionTime: recordCompletionTime);
    } finally {
      _inFlightCompleteTodoIds.removeAll(claimed);
    }
  }

  Future<void> _toggleTodoLocked(
    String id, {
    required bool recordCompletionTime,
  }) async {
    await _ensureStorageLoaded();
    final idx = _todos.indexWhere((t) => t.id == id);
    if (idx == -1) return;
    final prev = _todos[idx];
    final nowCompleted = !prev.isCompleted;
    _todos[idx] = prev.copyWith(
      isCompleted: nowCompleted,
      completedAt: nowCompleted ? DateTime.now() : null,
      kanbanColumnId: nowCompleted
          ? defaultKanbanDoneColumnId
          : prev.kanbanColumnId == defaultKanbanDoneColumnId
          ? defaultKanbanPendingColumnId
          : prev.kanbanColumnId,
    );
    if (nowCompleted) {
      DomainEventBus.instance.publish(
        DomainEvent(type: DomainEventType.todoCompleted, objectId: prev.id),
      );
    }

    if (nowCompleted && prev.recurrence.isActive) {
      final recurring = _nextRecurringTodo(prev);
      if (recurring != null) _todos.add(recurring);
    }

    await _saveToStorage();
    _notify();
    if (nowCompleted && recordCompletionTime) {
      await _timeAudit?.recordTodoCompletion(
        _todos[idx],
        completedAt: _todos[idx].completedAt,
      );
    } else if (!nowCompleted) {
      await _timeAudit?.removeTodoCompletion(
        prev,
        completedAt: prev.completedAt,
      );
    }
    await _syncTodoRemindersNow();
  }

  Future<void> deleteTodo(String id) async {
    await deleteTodos([id]);
  }

  Future<int> deleteTodos(Iterable<String> ids) async {
    final requested = ids.toSet();
    if (requested.isEmpty) return 0;
    final selected = _claimInFlightKeys(
      _inFlightDeleteTodoIds,
      requested,
      label: 'todo delete',
      duplicateMessage: '待办删除操作正在进行中，请勿重复提交',
      allowPartial: true,
    );

    try {
      return await _deleteTodosLocked(selected);
    } finally {
      _inFlightDeleteTodoIds.removeAll(selected);
    }
  }

  Future<int> _deleteTodosLocked(Set<String> selected) async {
    await _ensureStorageLoaded();
    final existing = _todos.where((t) => selected.contains(t.id)).toList();
    if (existing.isEmpty) return 0;

    await CloudSyncProvider.recordDeletedItems(
      'todos',
      existing.map((todo) => todo.id),
    );
    for (final todo in existing) {
      await _timeAudit?.deleteBySource(TimeEntrySource.todo, todo.id);
    }
    _todos.removeWhere((t) => selected.contains(t.id));
    await _saveToStorage();
    _notify();
    await _syncTodoRemindersNow();
    return existing.length;
  }

  Future<int> updateTodosQuadrant(
    Iterable<String> ids,
    EisenhowerQuadrant quadrant,
  ) async {
    final requested = ids.toSet();
    if (requested.isEmpty) return 0;
    final selected = _claimInFlightKeys(
      _inFlightQuadrantTodoIds,
      requested,
      label: 'todo quadrant update',
      duplicateMessage: '待办移动操作正在进行中，请勿重复提交',
      allowPartial: true,
      throwWhenDuplicate: false,
    );
    if (selected.isEmpty) return 0;
    try {
      return await _updateTodosQuadrantLocked(selected, quadrant);
    } finally {
      _inFlightQuadrantTodoIds.removeAll(selected);
    }
  }

  Future<int> _updateTodosQuadrantLocked(
    Set<String> selected,
    EisenhowerQuadrant quadrant,
  ) async {
    await _ensureStorageLoaded();
    var changed = 0;
    for (var i = 0; i < _todos.length; i++) {
      final todo = _todos[i];
      if (!selected.contains(todo.id) || todo.quadrant == quadrant) continue;
      _todos[i] = todo.copyWith(quadrant: quadrant);
      changed++;
    }
    if (changed == 0) return 0;
    await _saveToStorage();
    _notify();
    return changed;
  }

  Future<int> updateTodosPriority(
    Iterable<String> ids,
    TodoPriority priority,
  ) async {
    final requested = ids.toSet();
    if (requested.isEmpty) return 0;
    final selected = _claimInFlightKeys(
      _inFlightPriorityTodoIds,
      requested,
      label: 'todo priority update',
      duplicateMessage: '待办优先级更新正在进行中，请勿重复提交',
      allowPartial: true,
      throwWhenDuplicate: false,
    );
    if (selected.isEmpty) return 0;
    try {
      return await _updateTodosPriorityLocked(selected, priority);
    } finally {
      _inFlightPriorityTodoIds.removeAll(selected);
    }
  }

  Future<int> _updateTodosPriorityLocked(
    Set<String> selected,
    TodoPriority priority,
  ) async {
    await _ensureStorageLoaded();
    var changed = 0;
    for (var i = 0; i < _todos.length; i++) {
      final todo = _todos[i];
      if (!selected.contains(todo.id) || todo.priority == priority) continue;
      _todos[i] = todo.copyWith(priority: priority);
      changed++;
    }
    if (changed == 0) return 0;
    await _saveToStorage();
    _notify();
    return changed;
  }

  Future<int> updateTodosKanbanColumn(
    Iterable<String> ids,
    String columnId,
  ) async {
    final requested = ids.toSet();
    if (requested.isEmpty) return 0;
    final target = columnId.trim().isEmpty
        ? defaultKanbanPendingColumnId
        : columnId.trim();
    final selected = _claimInFlightKeys(
      _inFlightKanbanTodoIds,
      requested.map((id) => '$id:$target'),
      label: 'todo kanban update',
      duplicateMessage: '待办看板更新正在进行中，请勿重复提交',
      allowPartial: true,
      throwWhenDuplicate: false,
    );
    if (selected.isEmpty) return 0;
    final selectedIds = {
      for (final key in selected) key.substring(0, key.lastIndexOf(':')),
    };
    try {
      return await _updateTodosKanbanColumnLocked(selectedIds, target);
    } finally {
      _inFlightKanbanTodoIds.removeAll(selected);
    }
  }

  Future<int> _updateTodosKanbanColumnLocked(
    Set<String> selected,
    String target,
  ) async {
    await _ensureStorageLoaded();
    final completed = <TodoItem>[];
    final reopened = <TodoItem>[];
    var changed = 0;
    for (var i = 0; i < _todos.length; i++) {
      final todo = _todos[i];
      if (!selected.contains(todo.id) || todo.kanbanColumnId == target) {
        continue;
      }
      final next = todo.copyWith(
        kanbanColumnId: target,
        isCompleted: target == defaultKanbanDoneColumnId
            ? true
            : target != defaultKanbanDoneColumnId &&
                  todo.kanbanColumnId == defaultKanbanDoneColumnId
            ? false
            : todo.isCompleted,
        completedAt: target == defaultKanbanDoneColumnId && !todo.isCompleted
            ? DateTime.now()
            : target != defaultKanbanDoneColumnId &&
                  todo.kanbanColumnId == defaultKanbanDoneColumnId
            ? null
            : todo.completedAt,
      );
      _todos[i] = next;
      if (!todo.isCompleted && next.isCompleted) {
        completed.add(next);
        DomainEventBus.instance.publish(
          DomainEvent(type: DomainEventType.todoCompleted, objectId: next.id),
        );
        if (todo.recurrence.isActive) {
          final recurring = _nextRecurringTodo(todo);
          if (recurring != null) _todos.add(recurring);
        }
      } else if (todo.isCompleted && !next.isCompleted) {
        reopened.add(todo);
      }
      changed++;
    }
    if (changed == 0) return 0;
    await _saveToStorage();
    _notify();
    for (final todo in completed) {
      await _timeAudit?.recordTodoCompletion(
        todo,
        completedAt: todo.completedAt,
      );
    }
    for (final todo in reopened) {
      await _timeAudit?.removeTodoCompletion(
        todo,
        completedAt: todo.completedAt,
      );
    }
    await _syncTodoRemindersNow();
    return changed;
  }

  Future<bool> scheduleTodoForToday(
    String id, {
    DateTime? now,
    bool waitForReminderSync = true,
  }) async {
    final claimed = _claimInFlightKeys(
      _inFlightScheduleTodayTodoIds,
      [id],
      label: 'todo schedule today',
      duplicateMessage: '待办安排到今天正在进行中，请勿重复提交',
      throwWhenDuplicate: false,
    );
    if (claimed.isEmpty) return false;
    try {
      return await _scheduleTodoForTodayLocked(
        id,
        now: now,
        waitForReminderSync: waitForReminderSync,
      );
    } finally {
      _inFlightScheduleTodayTodoIds.removeAll(claimed);
    }
  }

  Future<bool> _scheduleTodoForTodayLocked(
    String id, {
    DateTime? now,
    required bool waitForReminderSync,
  }) async {
    await _ensureStorageLoaded();
    final idx = _todos.indexWhere((t) => t.id == id);
    if (idx == -1) return false;
    final todo = _todos[idx];
    if (todo.isCompleted || todo.isArchivedAfterRollover) return false;

    final base = now ?? DateTime.now();
    final today = DateTime(base.year, base.month, base.day);
    final trigger = todo.hasReminder && todo.reminderAt != null
        ? todo.reminderAt
        : todo.dueDate;
    final triggerIsUsableToday =
        trigger != null && _isSameDay(trigger, today) && trigger.isAfter(base);
    final shouldUseFallbackDue = !triggerIsUsableToday;
    final currentDay = DateTime(todo.date.year, todo.date.month, todo.date.day);
    if (currentDay == today &&
        !todo.isArchivedAfterRollover &&
        triggerIsUsableToday) {
      return false;
    }
    final preferredDue = DateTime(
      today.year,
      today.month,
      today.day,
      base.hour,
      base.minute,
    ).add(const Duration(minutes: 30));
    final endOfToday = DateTime(today.year, today.month, today.day, 23, 59, 59);
    final fallbackDue = preferredDue.isBefore(endOfToday)
        ? preferredDue
        : endOfToday;
    final nextDue = shouldUseFallbackDue ? fallbackDue : todo.dueDate;
    final shouldMirrorReminder =
        shouldUseFallbackDue &&
        (todo.hasReminder ||
            todo.reminder.enabled ||
            todo.reminderPlan.enabled);

    _todos[idx] = todo.copyWith(
      date: today,
      dueDate: nextDue,
      isArchivedAfterRollover: false,
      hasReminder: shouldMirrorReminder ? true : null,
      reminderAt: shouldMirrorReminder ? fallbackDue : todo.reminderAt,
      reminder: shouldMirrorReminder
          ? todo.reminder.copyWith(
              enabled: true,
              hour: fallbackDue.hour,
              minute: fallbackDue.minute,
            )
          : null,
    );
    await _saveToStorage();
    _notify();
    if (waitForReminderSync) {
      await _syncTodoRemindersNow();
    } else {
      unawaited(_syncTodoRemindersNow());
    }
    return true;
  }

  bool _isSameDay(DateTime value, DateTime day) =>
      value.year == day.year &&
      value.month == day.month &&
      value.day == day.day;

  Future<void> reorder(List<String> orderedIds) async {
    final key = orderedIds.join('|');
    final claimed = _claimInFlightKeys(
      _inFlightReorderKeys,
      ['all:$key'],
      label: 'todo reorder',
      duplicateMessage: '待办排序正在保存中，请勿重复提交',
      throwWhenDuplicate: false,
    );
    if (claimed.isEmpty) return;
    try {
      await _reorderLocked(orderedIds);
    } finally {
      _inFlightReorderKeys.removeAll(claimed);
    }
  }

  Future<void> _reorderLocked(List<String> orderedIds) async {
    await _ensureStorageLoaded();
    final map = {for (final t in _todos) t.id: t};
    final newList = <TodoItem>[];
    for (int i = 0; i < orderedIds.length; i++) {
      final t = map[orderedIds[i]];
      if (t != null) {
        newList.add(t.copyWith(sortOrder: i));
        map.remove(orderedIds[i]);
      }
    }
    newList.addAll(map.values);
    _todos = newList;
    await _saveToStorage();
    _notify();
  }

  Future<int> reorderVisibleTodos(List<String> orderedIds) async {
    final key = orderedIds.join('|');
    final claimed = _claimInFlightKeys(
      _inFlightReorderKeys,
      ['visible:$key'],
      label: 'visible todo reorder',
      duplicateMessage: '待办排序正在保存中，请勿重复提交',
      throwWhenDuplicate: false,
    );
    if (claimed.isEmpty) return 0;
    try {
      return await _reorderVisibleTodosLocked(orderedIds);
    } finally {
      _inFlightReorderKeys.removeAll(claimed);
    }
  }

  Future<int> _reorderVisibleTodosLocked(List<String> orderedIds) async {
    await _ensureStorageLoaded();
    final ordered = orderedIds.toList(growable: false);
    if (ordered.length < 2) return 0;
    final orderedSet = ordered.toSet();
    if (orderedSet.length != ordered.length) return 0;

    final byId = {for (final todo in _todos) todo.id: todo};
    if (!ordered.every(byId.containsKey)) return 0;

    final sorted = [..._todos]..sort(_compareTodos);
    final slots = <int>[];
    for (var i = 0; i < sorted.length; i++) {
      if (orderedSet.contains(sorted[i].id)) slots.add(i);
    }
    if (slots.length != ordered.length) return 0;

    final current = [for (final slot in slots) sorted[slot].id];
    var changedOrder = false;
    for (var i = 0; i < current.length; i++) {
      if (current[i] != ordered[i]) {
        changedOrder = true;
        break;
      }
    }
    if (!changedOrder) return 0;

    for (var i = 0; i < slots.length; i++) {
      sorted[slots[i]] = byId[ordered[i]]!;
    }

    var changed = 0;
    final rebuilt = <TodoItem>[];
    for (var i = 0; i < sorted.length; i++) {
      final todo = sorted[i];
      if (todo.sortOrder == i) {
        rebuilt.add(todo);
      } else {
        rebuilt.add(todo.copyWith(sortOrder: i));
        changed++;
      }
    }
    _todos = rebuilt;
    await _saveToStorage();
    _notify();
    return changed;
  }

  TodoItem? _nextRecurringTodo(TodoItem prev) {
    final remainingOccurrences = prev.recurrence.maxOccurrences;
    if (remainingOccurrences != null && remainingOccurrences <= 1) {
      return null;
    }
    final next = prev.recurrence.nextAfter(prev.date);
    if (next == null) return null;
    final nextRecurrence = remainingOccurrences == null
        ? prev.recurrence
        : prev.recurrence.copyWith(maxOccurrences: remainingOccurrences - 1);
    final delta = prev.dueDate == null
        ? Duration.zero
        : prev.dueDate!.difference(prev.date);
    final nextDue = prev.dueDate == null ? null : next.add(delta);
    DateTime? nextReminderAt;
    // ignore: deprecated_member_use_from_same_package
    final reminderEnabled = prev.reminder.enabled || prev.hasReminder;
    if (reminderEnabled) {
      final hour = prev.reminder.enabled
          ? prev.reminder.hour
          // ignore: deprecated_member_use_from_same_package
          : prev.reminderAt?.hour;
      final minute = prev.reminder.enabled
          ? prev.reminder.minute
          // ignore: deprecated_member_use_from_same_package
          : prev.reminderAt?.minute;
      if (hour != null && minute != null) {
        final reminderAnchor = nextDue ?? next;
        nextReminderAt = DateTime(
          reminderAnchor.year,
          reminderAnchor.month,
          reminderAnchor.day,
          hour,
          minute,
        );
      }
    }
    return TodoItem(
      title: prev.title,
      notes: prev.notes,
      quadrant: prev.quadrant,
      priority: prev.priority,
      listGroupId: prev.listGroupId,
      listGroupName: prev.listGroupName,
      workspaceId: prev.workspaceId,
      createdBy: prev.createdBy,
      updatedBy: prev.updatedBy,
      assigneeId: prev.assigneeId,
      tags: [...prev.tags],
      attachments: [...prev.attachments],
      dueDate: nextDue,
      date: next,
      hasReminder: reminderEnabled,
      reminderAt: nextReminderAt,
      reminder: prev.reminder,
      reminderPlan: prev.reminderPlan,
      focusLink: prev.focusLink,
      timeTargetSeconds: prev.timeTargetSeconds,
      subtasks: prev.subtasks
          .map((s) => Subtask(title: s.title, sortOrder: s.sortOrder))
          .toList(),
      autoToggleByChildren: prev.autoToggleByChildren,
      recurrence: nextRecurrence,
      sortOrder: prev.sortOrder,
    );
  }

  Future<void> updateListGroupWorkspace(
    String groupName,
    String workspaceId, {
    String? userId,
  }) async {
    final key = '${groupName.trim()}:$workspaceId';
    final claimed = _claimInFlightKeys(
      _inFlightListGroupWorkspaceKeys,
      [key],
      label: 'todo list workspace update',
      duplicateMessage: '清单共享状态正在保存中，请勿重复提交',
      throwWhenDuplicate: false,
    );
    if (claimed.isEmpty) return;
    try {
      await _updateListGroupWorkspaceLocked(
        groupName,
        workspaceId,
        userId: userId,
      );
    } finally {
      _inFlightListGroupWorkspaceKeys.removeAll(claimed);
    }
  }

  Future<void> _updateListGroupWorkspaceLocked(
    String groupName,
    String workspaceId, {
    String? userId,
  }) async {
    await _ensureStorageLoaded();
    var mutated = false;
    for (var i = 0; i < _todos.length; i++) {
      final todo = _todos[i];
      if ((todo.listGroupName ?? '未分组') != groupName) continue;
      _todos[i] = todo.copyWith(
        workspaceId: workspaceId,
        updatedBy: userId,
        createdBy: todo.createdBy ?? userId,
      );
      mutated = true;
    }
    if (!mutated) return;
    await _saveToStorage();
    _notify();
    await _syncTodoRemindersNow();
  }

  // --- Subtask operations ---

  Future<void> addSubtask(String todoId, String title) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return;
    final key = '$todoId:${cleanTitle.toLowerCase()}';
    if (!_inFlightSubtaskCreateKeys.add(key)) {
      debugPrint('[TodoProvider] duplicate in-flight subtask create skipped');
      throw StateError('子任务正在创建中，请勿重复提交');
    }
    try {
      await _addSubtaskLocked(todoId, cleanTitle);
    } finally {
      _inFlightSubtaskCreateKeys.remove(key);
    }
  }

  Future<void> _addSubtaskLocked(String todoId, String title) async {
    await _ensureStorageLoaded();
    final idx = _todos.indexWhere((t) => t.id == todoId);
    if (idx != -1) {
      final newSubtasks = List<Subtask>.from(_todos[idx].subtasks)
        ..add(Subtask(title: title, sortOrder: _todos[idx].subtasks.length));
      _todos[idx] = _todos[idx].copyWith(subtasks: newSubtasks);
      await _saveToStorage();
      _notify();
    }
  }

  Future<void> toggleSubtask(String todoId, String subtaskId) async {
    final key = '$todoId:$subtaskId';
    if (!_inFlightSubtaskToggleKeys.add(key)) return;
    try {
      await _toggleSubtaskLocked(todoId, subtaskId);
    } finally {
      _inFlightSubtaskToggleKeys.remove(key);
    }
  }

  Future<void> _toggleSubtaskLocked(String todoId, String subtaskId) async {
    await _ensureStorageLoaded();
    final idx = _todos.indexWhere((t) => t.id == todoId);
    if (idx == -1) return;
    final sIdx = _todos[idx].subtasks.indexWhere((s) => s.id == subtaskId);
    if (sIdx == -1) return;
    _todos[idx].subtasks[sIdx].isCompleted =
        !_todos[idx].subtasks[sIdx].isCompleted;
    await recomputeParent(todoId);
  }

  /// 依据子任务聚合状态重算父任务完成态（P6/P7 不变式）。
  ///
  /// - 若 `subtasks.isEmpty`：视为 no-op，不触碰父任务也不写入存储。
  /// - 若 `autoToggleByChildren = true`：
  ///   - 全部子任务完成且父任务未完成 → `isCompleted = true` 且 `completedAt = now`
  ///   - 存在未完成子任务且父任务已完成 → `isCompleted = false` 且 `completedAt = null`
  /// - 若 `autoToggleByChildren = false`：不触碰父任务完成态，仅持久化当前子任务变动。
  Future<void> recomputeParent(String todoId) async {
    await _ensureStorageLoaded();
    final idx = _todos.indexWhere((t) => t.id == todoId);
    if (idx == -1) return;
    final t = _todos[idx];
    if (t.subtasks.isEmpty) return;

    TodoItem? completedTodo;
    DateTime? removedCompletedAt;
    if (t.autoToggleByChildren) {
      final allDone = t.subtasks.every((s) => s.isCompleted);
      if (allDone && !t.isCompleted) {
        t.isCompleted = true;
        t.completedAt = DateTime.now();
        completedTodo = t;
      } else if (!allDone && t.isCompleted) {
        removedCompletedAt = t.completedAt;
        t.isCompleted = false;
        t.completedAt = null;
      }
    }

    await _saveToStorage();
    _notify();
    if (completedTodo != null) {
      await _timeAudit?.recordTodoCompletion(
        completedTodo,
        completedAt: completedTodo.completedAt,
      );
    } else if (removedCompletedAt != null) {
      await _timeAudit?.removeTodoCompletion(
        t,
        completedAt: removedCompletedAt,
      );
    }
    await _syncTodoRemindersNow();
  }

  Future<void> deleteSubtask(String todoId, String subtaskId) async {
    final key = '$todoId:$subtaskId';
    if (!_inFlightSubtaskDeleteKeys.add(key)) return;
    try {
      await _deleteSubtaskLocked(todoId, subtaskId);
    } finally {
      _inFlightSubtaskDeleteKeys.remove(key);
    }
  }

  Future<void> _deleteSubtaskLocked(String todoId, String subtaskId) async {
    await _ensureStorageLoaded();
    final idx = _todos.indexWhere((t) => t.id == todoId);
    if (idx != -1) {
      _todos[idx].subtasks.removeWhere((s) => s.id == subtaskId);
      await _saveToStorage();
      _notify();
    }
  }

  Future<void> reorderSubtasks(String todoId, List<String> orderedIds) async {
    final key = '$todoId:${orderedIds.join('|')}';
    final claimed = _claimInFlightKeys(
      _inFlightSubtaskReorderKeys,
      [key],
      label: 'subtask reorder',
      duplicateMessage: '子任务排序正在保存中，请勿重复提交',
      throwWhenDuplicate: false,
    );
    if (claimed.isEmpty) return;
    try {
      await _reorderSubtasksLocked(todoId, orderedIds);
    } finally {
      _inFlightSubtaskReorderKeys.removeAll(claimed);
    }
  }

  Future<void> _reorderSubtasksLocked(
    String todoId,
    List<String> orderedIds,
  ) async {
    await _ensureStorageLoaded();
    final idx = _todos.indexWhere((t) => t.id == todoId);
    if (idx == -1) return;
    final map = {for (final s in _todos[idx].subtasks) s.id: s};
    final newList = <Subtask>[];
    for (int i = 0; i < orderedIds.length; i++) {
      final s = map[orderedIds[i]];
      if (s != null) {
        s.sortOrder = i;
        newList.add(s);
        map.remove(orderedIds[i]);
      }
    }
    newList.addAll(map.values);
    _todos[idx] = _todos[idx].copyWith(subtasks: newList);
    await _saveToStorage();
    _notify();
  }

  // --- Daily rollover ---

  /// 归档"昨天及更早"的已完成 todos（P5 / Requirement 3.4, 3.5）。
  ///
  /// 对每个满足 `t.isCompleted ∧ t.completedAt != null ∧
  /// dateOnly(completedAt) < todayDay ∧ !t.isArchivedAfterRollover` 的任务，
  /// 置 `isArchivedAfterRollover = true` 并刷新 `updatedAt`。
  ///
  /// 幂等性：若没有任务满足条件（例如二次调用），方法不会写入存储也不会通知
  /// 监听器。`todayDay` 会先裁剪到本地"日"起点，避免在调用方未对齐时误判。
  ///
  /// 注意：本方法只处理"已完成 → 归档"的迁移；对"昨日未完成且已过期"的任务
  /// 由 [postponeOverdue] 负责顺延。两者在 `CompletionVisibilityPolicy
  /// .runDailyRollover` 中组合使用。
  Future<void> archivePastCompletions(DateTime todayDay) async {
    final todayStart = DateTime(todayDay.year, todayDay.month, todayDay.day);
    final claimed = _claimInFlightKeys(
      _inFlightArchiveKeys,
      [_dateKey(todayStart)],
      label: 'todo archive rollover',
      duplicateMessage: '待办归档正在执行中，请勿重复提交',
      throwWhenDuplicate: false,
    );
    if (claimed.isEmpty) return;
    try {
      await _archivePastCompletionsLocked(todayStart);
    } finally {
      _inFlightArchiveKeys.removeAll(claimed);
    }
  }

  Future<void> _archivePastCompletionsLocked(DateTime todayStart) async {
    await _ensureStorageLoaded();
    var mutated = false;

    for (final t in _todos) {
      if (!t.isCompleted) continue;
      if (t.isArchivedAfterRollover) continue;
      final completedAt = t.completedAt;
      if (completedAt == null) continue;

      final completedDay = DateTime(
        completedAt.year,
        completedAt.month,
        completedAt.day,
      );
      if (!completedDay.isBefore(todayStart)) continue;

      t.isArchivedAfterRollover = true;
      t.updatedAt = DateTime.now();
      mutated = true;
    }

    if (!mutated) return;

    await _saveToStorage();
    _notify();
  }

  /// 把所有"未完成且已过期"的 todo 顺延到 [today] 同一时刻。
  ///
  /// 对每个满足 `!isCompleted ∧ dueDate != null ∧ dueDay < todayDay` 的任务：
  /// - 生成新的 `dueDate = todayDay + (prev.hour, prev.minute)`；
  /// - 在 `postponeHistory` 追加一条 `reason = 'auto_daily_rollover'` 记录；
  /// - 若任务启用了提醒（新版 `reminder.enabled` 或遗留 `hasReminder`），
  ///   同步把遗留字段 `reminderAt` 镜像到新的 `dueDate`，保证既有
  ///   `ReminderScheduler.syncTodos` 能按新时间重新调度；
  ///   新版 `ReminderConfig` 只含 `hour / minute`，不持有日期，这里不需要改动。
  ///
  /// 幂等性（P13）：若所有任务已满足 `dueDay ≥ todayDay`，二次调用不会追加任何
  /// 新的 `PostponeRecord`，也不会写入存储、不会通知监听器。
  ///
  /// [today] 作为参数注入，便于测试；内部会先取其日部分做"本地 00:00"对齐。
  Future<void> postponeOverdue(DateTime today) async {
    final todayDay = DateTime(today.year, today.month, today.day);
    final claimed = _claimInFlightKeys(
      _inFlightPostponeKeys,
      [_dateKey(todayDay)],
      label: 'todo overdue postpone',
      duplicateMessage: '待办顺延正在执行中，请勿重复提交',
      throwWhenDuplicate: false,
    );
    if (claimed.isEmpty) return;
    try {
      await _postponeOverdueLocked(todayDay);
    } finally {
      _inFlightPostponeKeys.removeAll(claimed);
    }
  }

  Future<void> _postponeOverdueLocked(DateTime todayDay) async {
    await _ensureStorageLoaded();
    var mutated = false;

    for (final t in _todos) {
      if (t.isCompleted) continue;
      final prevDue = t.dueDate;
      if (prevDue == null) continue;

      final dueDay = DateTime(prevDue.year, prevDue.month, prevDue.day);
      // 未到期：dueDay == todayDay 或更晚。
      if (!dueDay.isBefore(todayDay)) continue;

      final newDue = DateTime(
        todayDay.year,
        todayDay.month,
        todayDay.day,
        prevDue.hour,
        prevDue.minute,
      );

      t.postponeHistory.add(
        PostponeRecord(
          from: prevDue,
          to: newDue,
          reason: 'auto_daily_rollover',
          at: DateTime.now(),
        ),
      );
      t.dueDate = newDue;
      t.updatedAt = DateTime.now();

      // 同步遗留的 reminderAt 镜像：新版 ReminderConfig 只记录 hour/minute，
      // 但 ReminderScheduler 仍会优先读 `reminderAt ?? dueDate`，因此把镜像
      // 保持在最新的 dueDate 上，触发下一次 `syncTodos` 重新调度。
      // ignore: deprecated_member_use_from_same_package
      final reminderEnabled = t.reminder.enabled || t.hasReminder;
      if (reminderEnabled) {
        // ignore: deprecated_member_use_from_same_package
        t.reminderAt = newDue;
      }

      mutated = true;
    }

    if (!mutated) return;

    await _saveToStorage();
    _notify();

    // 顺延后重新同步提醒调度队列。
    await _syncTodoRemindersNow();
  }

  Set<String> _claimInFlightKeys(
    Set<String> bucket,
    Iterable<String> keys, {
    required String label,
    required String duplicateMessage,
    bool allowPartial = false,
    bool throwWhenDuplicate = true,
  }) {
    final requested = keys.where((key) => key.isNotEmpty).toSet();
    if (requested.isEmpty) return <String>{};

    final claimed = <String>{};
    final duplicates = <String>[];
    for (final key in requested) {
      if (bucket.add(key)) {
        claimed.add(key);
      } else {
        duplicates.add(key);
      }
    }
    if (duplicates.isEmpty) return claimed;

    if (allowPartial && claimed.isNotEmpty) {
      debugPrint(
        '[TodoProvider] ${duplicates.length} duplicate $label request(s) '
        'skipped; ${claimed.length} new request(s) will continue',
      );
      return claimed;
    }

    bucket.removeAll(claimed);
    debugPrint(
      '[TodoProvider] duplicate $label request skipped: '
      '${duplicates.length}/${requested.length} already in-flight',
    );
    if (throwWhenDuplicate) {
      throw StateError(duplicateMessage);
    }
    return <String>{};
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _importDuplicateKey(TodoItem todo) {
    final dueKey = todo.dueDate == null ? '' : _dateKey(todo.dueDate!);
    final title = todo.title.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final list = (todo.listGroupName ?? '').trim().toLowerCase();
    return '$title|$dueKey|$list';
  }

  String _createInFlightDuplicateKey(TodoItem todo) {
    final title = todo.title.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final dateKey = _dateKey(todo.date);
    final dueKey = todo.dueDate == null
        ? ''
        : todo.dueDate!.millisecondsSinceEpoch.toString();
    final list = (todo.listGroupName ?? '').trim().toLowerCase();
    return [todo.workspaceId, list, title, dateKey, dueKey].join('|');
  }
}

/// 在后台 isolate 中编码待办存储载荷（供 `compute` 调用，必须是顶层函数）。
/// 传入的是模型对象图的拷贝，与发送时刻的内存状态一致。
String _encodeTodoStoragePayload(List<TodoItem> todos) =>
    json.encode(todos.map((e) => e.toJson()).toList());

/// 在后台 isolate 中解码待办存储载荷，保留与主线程路径一致的逐条容错：
/// 坏记录跳过并标记重写，整体不是列表或 JSON 损坏时也标记重写。
({List<TodoItem> items, bool rewrite, bool notAList, String? errorDetail})
_decodeTodoStoragePayload(String data) {
  final parsed = <TodoItem>[];
  var shouldRewrite = false;
  var notAList = false;
  String? errorDetail;
  try {
    final decoded = json.decode(data);
    if (decoded is List) {
      for (var i = 0; i < decoded.length; i++) {
        final raw = decoded[i];
        try {
          if (raw is! Map) {
            shouldRewrite = true;
            continue;
          }
          parsed.add(TodoItem.fromJson(Map<String, dynamic>.from(raw)));
        } catch (e) {
          shouldRewrite = true;
          errorDetail ??= 'skipped invalid todo[$i]: $e';
        }
      }
    } else {
      shouldRewrite = true;
      notAList = true;
    }
  } catch (e) {
    shouldRewrite = true;
    errorDetail = '$e';
  }
  return (
    items: parsed,
    rewrite: shouldRewrite,
    notAList: notAList,
    errorDetail: errorDetail,
  );
}
