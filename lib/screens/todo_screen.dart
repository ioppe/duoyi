import 'package:flutter/material.dart';
import '../widgets/app_page_tabs.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_clock.dart';
import '../core/local_timezone_resolver.dart';
import '../core/completion_visibility_policy.dart';
import '../core/desktop_tokens.dart';
import '../core/design_tokens.dart';
import '../core/i18n_date_format.dart';
import '../core/iterable_extensions.dart';
import '../core/i18n.dart';
import '../core/todo_filters.dart';
import '../core/todo_kanban.dart';
import '../models/goal.dart' show ReminderKind;
import '../models/habit.dart';
import '../models/todo.dart';
import '../models/workspace.dart';
import '../providers/auth_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/share_provider.dart';
import '../providers/todo_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/eisenhower_matrix.dart';
import '../widgets/empty_state.dart';
import '../widgets/todo_completion_flow.dart';
import '../widgets/surface_components.dart';
import '../widgets/todo_create_sheet.dart';
import 'share_screen.dart';
import 'todo_detail_screen.dart' show TodoDetailScreen, priorityColor;

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

enum _TodoViewMode { matrix, list, kanban }

/// 待办页派生数据（过滤 + 分组 + 标签聚合）的 memo 缓存。
/// 这些计算都是 O(n) 且每次 build 都会执行；滚动起手的 setState、
/// 其他 Provider 通知都会触发重建，缓存命中时可整块跳过。
class _TodoDerivedData {
  final List<TodoItem> baseTodos;
  final List<TodoItem> filteredTodos;
  final Map<EisenhowerQuadrant, List<TodoItem>> quadrantGroups;
  final Map<String, List<TodoItem>> listGroups;
  final List<MapEntry<String, List<TodoItem>>> listGroupEntries;
  final Map<String, List<TodoItem>> kanbanGroups;
  final List<String> availableTags;
  final List<String> availableListGroups;
  final int overdueCount;

  const _TodoDerivedData({
    required this.baseTodos,
    required this.filteredTodos,
    required this.quadrantGroups,
    required this.listGroups,
    required this.listGroupEntries,
    required this.kanbanGroups,
    required this.availableTags,
    required this.availableListGroups,
    required this.overdueCount,
  });
}

class _TodoScreenState extends State<TodoScreen> {
  _TodoViewMode _viewMode = _TodoViewMode.matrix;
  TodoFilterState<EisenhowerQuadrant, TodoPriority> _filter =
      const TodoFilterState<EisenhowerQuadrant, TodoPriority>();
  TodoKanbanBoardConfig _kanbanConfig = TodoKanbanBoardConfig.defaults();
  bool _batchMode = false;
  bool _batchSubmitting = false;
  int _swipeDismissSerial = 0;
  final Set<String> _selectedTodoIds = <String>{};

  _TodoDerivedData? _derived;
  int? _derivedRevision;
  TodoFilterState<EisenhowerQuadrant, TodoPriority>? _derivedFilter;
  TodoKanbanBoardConfig? _derivedKanbanConfig;
  int? _derivedMinuteKey;
  String? _derivedTimezone;

  _TodoDerivedData _computeDerivedData({
    required TodoProvider todoProvider,
    required int minuteKey,
  }) {
    final now = AppClock.now();
    final baseTodos = todoProvider.visibleListTodos;
    final filteredTodos = filterTodos(
      baseTodos,
      _filter,
      now: now,
      quadrantOf: (todo) => todo.quadrant,
      priorityOf: (todo) => todo.priority,
      tagsOf: (todo) => todo.tags,
      listGroupNameOf: (todo) => todo.listGroupName,
      dueDateOf: (todo) => todo.localDueDate,
      isCompletedOf: (todo) => todo.isCompleted,
      isArchivedAfterRolloverOf: (todo) => todo.isArchivedAfterRollover,
    );
    final quadrantGroups = groupTodosByQuadrant(
      filteredTodos,
      quadrants: EisenhowerQuadrant.values,
      quadrantOf: (todo) => todo.quadrant,
    );
    final listGroups = groupTodosByList(
      filteredTodos,
      (todo) => todo.listGroupName,
    );
    final listGroupEntries = listGroups.entries.toList(growable: false);
    final kanbanGroups = <String, List<TodoItem>>{
      for (final column in _kanbanConfig.columns) column.id: <TodoItem>[],
    };
    for (final todo in filteredTodos) {
      final columnId = _kanbanConfig.normalizeColumnId(todo.kanbanColumnId);
      kanbanGroups.putIfAbsent(columnId, () => <TodoItem>[]).add(todo);
    }
    return _TodoDerivedData(
      baseTodos: baseTodos,
      filteredTodos: filteredTodos,
      quadrantGroups: quadrantGroups,
      listGroups: listGroups,
      listGroupEntries: listGroupEntries,
      kanbanGroups: kanbanGroups,
      availableTags: collectTodoTags(baseTodos, (todo) => todo.tags),
      availableListGroups: collectTodoListGroups(
        baseTodos,
        (todo) => todo.listGroupName,
      ),
      overdueCount: todoProvider.overdueTodos.length,
    );
  }

  _TodoDerivedData _derivedDataFor(TodoProvider todoProvider) {
    // 逾期/今日等时间过滤按分钟粒度失效即可；按帧取 `DateTime.now()` 会让
    // 缓存永远失效。
    final minuteKey = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    final derived = _derived;
    if (derived != null &&
        _derivedRevision == todoProvider.revision &&
        identical(_derivedFilter, _filter) &&
        identical(_derivedKanbanConfig, _kanbanConfig) &&
        _derivedTimezone == LocalTimezoneResolver.currentIana &&
        _derivedMinuteKey == minuteKey) {
      return derived;
    }
    final computed = _computeDerivedData(
      todoProvider: todoProvider,
      minuteKey: minuteKey,
    );
    _derived = computed;
    _derivedRevision = todoProvider.revision;
    _derivedFilter = _filter;
    _derivedKanbanConfig = _kanbanConfig;
    _derivedMinuteKey = minuteKey;
    _derivedTimezone = LocalTimezoneResolver.currentIana;
    return computed;
  }

  @override
  void initState() {
    super.initState();
    _loadKanbanConfig();
  }

  Future<void> _loadKanbanConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final config = TodoKanbanBoardConfig.decode(
      prefs.getString(todoKanbanColumnsPrefsKey),
    );
    if (!mounted) return;
    setState(() => _kanbanConfig = config);
  }

  Future<void> _saveKanbanConfig(TodoKanbanBoardConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(todoKanbanColumnsPrefsKey, config.encode());
    if (!mounted) return;
    setState(() => _kanbanConfig = config);
  }

  void _enterBatchMode({String? todoId, bool switchToList = false}) {
    if (_batchSubmitting) return;
    setState(() {
      _batchMode = true;
      if (switchToList) _viewMode = _TodoViewMode.list;
      if (todoId != null) _selectedTodoIds.add(todoId);
    });
  }

  void _exitBatchMode() {
    setState(() {
      _batchMode = false;
      _selectedTodoIds.clear();
    });
  }

  void _toggleSelection(String todoId) {
    if (_batchSubmitting) return;
    setState(() {
      if (_selectedTodoIds.contains(todoId)) {
        _selectedTodoIds.remove(todoId);
        if (_selectedTodoIds.isEmpty) _batchMode = false;
      } else {
        _batchMode = true;
        _selectedTodoIds.add(todoId);
      }
    });
  }

  void _selectAllVisible(Iterable<String> editableIds) {
    if (_batchSubmitting) return;
    final ids = editableIds.toSet();
    setState(() {
      _batchMode = true;
      if (_selectedTodoIds.containsAll(ids)) {
        _selectedTodoIds.removeAll(ids);
        if (_selectedTodoIds.isEmpty) _batchMode = false;
      } else {
        _selectedTodoIds.addAll(ids);
      }
    });
  }

  void _setFilter(TodoFilterState<EisenhowerQuadrant, TodoPriority> filter) {
    setState(() {
      _filter = filter;
      _batchMode = false;
      _selectedTodoIds.clear();
    });
  }

  void _clearFilter() {
    _setFilter(const TodoFilterState<EisenhowerQuadrant, TodoPriority>());
  }

  bool _dismissSwipeActionsOnScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      setState(() => _swipeDismissSerial++);
    }
    return false;
  }

  Future<void> _completeSelected() async {
    var skipped = 0;
    await _runBatchAction(
      (ids) async {
        final provider = context.read<TodoProvider>();
        final count = await provider.completeTodos(ids);
        skipped = provider.lastSkippedBySubtasks;
        return count;
      },
      (count) =>
          skipped > 0 ? '已完成 $count 个任务，$skipped 个需先完成子任务' : '已完成 $count 个任务',
    );
  }

  Future<void> _reopenSelected() async {
    var skipped = 0;
    await _runBatchAction(
      (ids) async {
        final provider = context.read<TodoProvider>();
        final count = await provider.reopenTodos(ids);
        skipped = provider.lastSkippedBySubtasks;
        return count;
      },
      (count) => skipped > 0
          ? '已恢复 $count 个任务为未完成，$skipped 个有子任务需在子任务里取消'
          : '已恢复 $count 个任务为未完成',
    );
  }

  Future<void> _moveSelected(EisenhowerQuadrant quadrant) async {
    await _runBatchAction(
      (ids) => context.read<TodoProvider>().updateTodosQuadrant(ids, quadrant),
      (count) => '已移动 $count 个任务到${_quadrantLabel(quadrant)}',
    );
  }

  Future<void> _setSelectedPriority(TodoPriority priority) async {
    await _runBatchAction(
      (ids) => context.read<TodoProvider>().updateTodosPriority(ids, priority),
      (count) => '已更新 $count 个任务优先级',
    );
  }

  Future<void> _showKanbanSettings() async {
    final next = await showAppModalSheet<TodoKanbanBoardConfig>(
      context: context,
      builder: (_) => _KanbanSettingsSheet(config: _kanbanConfig),
    );
    if (!mounted || next == null) return;
    await _saveKanbanConfig(next);
  }

  Future<void> _deleteSelected() async {
    if (_batchSubmitting) return;
    final selectedCount = _selectedTodoIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AppDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('删除所选任务'),
        content: Text('确认删除 $selectedCount 个任务吗？相关时间足迹也会同步移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _runBatchAction(
      (ids) => context.read<TodoProvider>().deleteTodos(ids),
      (count) => '已删除 $count 个任务',
    );
  }

  Future<void> _runBatchAction(
    Future<int> Function(Set<String> ids) action,
    String Function(int count) message,
  ) async {
    if (_batchSubmitting) return;
    final ids = Set<String>.from(_selectedTodoIds);
    if (ids.isEmpty) return;
    setState(() => _batchSubmitting = true);
    try {
      final count = await action(ids);
      if (!mounted) return;
      _exitBatchMode();
      _showBatchSnack(message(count));
    } finally {
      if (mounted) {
        setState(() => _batchSubmitting = false);
      }
    }
  }

  void _showBatchSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _showAddDialog({EisenhowerQuadrant? initialQuadrant}) {
    showTodoCreateSheet(context, initialQuadrant: initialQuadrant);
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final todoProvider = context.watch<TodoProvider>();
    final habitProvider = context.watch<HabitProvider>();
    final goalProvider = context.watch<GoalProvider>();
    final shareProvider = context.watch<ShareProvider>();
    final s = context.watch<ThemeProvider>().brand.strings;
    final now = AppClock.now();
    final derived = _derivedDataFor(todoProvider);
    final baseTodos = derived.baseTodos;
    final filteredTodos = derived.filteredTodos;
    final quadrantGroups = derived.quadrantGroups;
    final listGroupEntries = derived.listGroupEntries;
    final kanbanGroups = derived.kanbanGroups;
    final availableTags = derived.availableTags;
    final availableListGroups = derived.availableListGroups;
    final overdueCount = derived.overdueCount;
    final editableVisibleIds = filteredTodos
        .where((todo) => shareProvider.canEdit(todo.workspaceId))
        .map((todo) => todo.id)
        .toList();
    final allVisibleSelected =
        editableVisibleIds.isNotEmpty &&
        editableVisibleIds.every(_selectedTodoIds.contains);
    // 宽屏桌面档（与 today 桌面仪表盘同款纯宽度判定，不依赖编译期 web
    // 档位）：左侧视图内容 + 右侧固定侧栏（今日概要 + 自定义视图筛选），
    // 消除 1280 限宽内仍通栏拉伸的"手机感"；批量模式退回通栏列表，
    // 便于横向扫选与底部批量操作条。
    final isWidescreen =
        MediaQuery.widthOf(context) >= DesktopTokens.breakpointTwoColumn;
    // 最宽桌面档（调研锚点 1400 = DesktopTokens.breakpointThreeColumn，即
    // docs/desktop-layout-optimization.md 的三栏布局档）：四象限单行 4 列
    // 横排，避免限宽内容区内 2×2 卡片各占半宽被拉成过宽横条；窄档与
    // 移动端保持 2×2 竖排（紧迫/重要两轴语义不变）。
    final isWidestTier =
        MediaQuery.widthOf(context) >= DesktopTokens.breakpointThreeColumn;
    final viewContent = filteredTodos.isEmpty
        ? _TodoNoMatches(
            onClear: () {
              setState(
                () => _filter =
                    const TodoFilterState<EisenhowerQuadrant, TodoPriority>(),
              );
            },
          )
        : switch (_viewMode) {
            _TodoViewMode.matrix => SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: EisenhowerMatrix(
                quadrantGroups: quadrantGroups,
                fourColumn: isWidestTier,
                onQuadrantTap: (q) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => QuadrantListScreen(
                        quadrant: q,
                        filter: _filter,
                        onCreateTodo: (quadrant) =>
                            _showAddDialog(initialQuadrant: quadrant),
                      ),
                    ),
                  );
                },
                // 长按拖动待办到目标象限，松手即换象限。
                // 与 tile 级入口一致：只读成员不可拖拽换象限。
                canEditTodo: (todo) =>
                    context.read<ShareProvider>().canEdit(todo.workspaceId),
                onTodoQuadrantChanged: (todo, target) {
                  // 投放时点用最新权限复查，防止陈旧快照放行。
                  if (!context.read<ShareProvider>().canEdit(
                    todo.workspaceId,
                  )) {
                    return;
                  }
                  context.read<TodoProvider>().updateTodosQuadrant([
                    todo.id,
                  ], target);
                },
              ),
            ),
            _TodoViewMode.list => NotificationListener<ScrollNotification>(
              onNotification: _dismissSwipeActionsOnScroll,
              child: ListView.builder(
                // ignore: deprecated_member_use
                cacheExtent: 640,
                itemCount: listGroupEntries.length,
                itemBuilder: (context, index) {
                  final entry = listGroupEntries[index];
                  return _ListGroupTile(
                    groupName: entry.key,
                    todos: entry.value,
                    batchMode: _batchMode,
                    selectedTodoIds: _selectedTodoIds,
                    onToggleSelection: _toggleSelection,
                    onEnterBatchMode: (id) => _enterBatchMode(todoId: id),
                    swipeDismissSerial: _swipeDismissSerial,
                  );
                },
              ),
            ),
            _TodoViewMode.kanban => _TodoKanbanView(
              config: _kanbanConfig,
              kanbanGroups: kanbanGroups,
              batchMode: _batchMode,
              selectedTodoIds: _selectedTodoIds,
              onToggleSelection: _toggleSelection,
              onEnterBatchMode: (id) => _enterBatchMode(todoId: id),
              swipeDismissSerial: _swipeDismissSerial,
              onScrollStart: _dismissSwipeActionsOnScroll,
            ),
          };
    final widescreenBody = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              _TodoViewSwitcher(
                selected: _viewMode,
                onChanged: (mode) => setState(() => _viewMode = mode),
              ),
              Expanded(child: viewContent),
            ],
          ),
        ),
        const VerticalDivider(
          width: 1,
          thickness: 1,
          // 不传 color：走主题 dividerTheme 档位（outlineVariant@feel alpha）。
        ),
        SizedBox(
          width: DesktopTokens.rightSidebarWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TodoTodaySummaryCard(
                todos: baseTodos,
                habits: habitProvider.habits,
                activeGoalCount: goalProvider.activeGoals.length,
                now: now,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: DesignTokens.spaceLg),
                  child: _TodoFilterBar(
                    filter: _filter,
                    totalCount: baseTodos.length,
                    filteredCount: filteredTodos.length,
                    availableTags: availableTags,
                    availableListGroups: availableListGroups,
                    onChanged: _setFilter,
                    onClear: _clearFilter,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: _batchMode
            ? IconButton(
                tooltip: '退出批量操作',
                onPressed: _exitBatchMode,
                icon: const Icon(Icons.close),
              )
            : null,
        title: Text(
          _batchMode ? '已选择 ${_selectedTodoIds.length} 项' : s.todoTitle,
        ),
        actions: [
          if (_batchMode)
            IconButton(
              tooltip: allVisibleSelected ? '取消全选' : '全选当前视图',
              onPressed: editableVisibleIds.isEmpty
                  ? null
                  : () => _selectAllVisible(editableVisibleIds),
              icon: Icon(
                allVisibleSelected
                    ? Icons.deselect_outlined
                    : Icons.select_all_outlined,
              ),
            )
          else ...[
            if (_viewMode == _TodoViewMode.kanban)
              IconButton(
                tooltip: '看板列设置',
                onPressed: _showKanbanSettings,
                icon: const Icon(Icons.tune_outlined),
              ),
            IconButton(
              tooltip: '批量操作',
              onPressed: filteredTodos.isEmpty
                  ? null
                  : () => _enterBatchMode(switchToList: true),
              icon: const Icon(Icons.checklist_outlined),
            ),
            if (overdueCount > 0)
              TextButton.icon(
                onPressed: () async {
                  await context.read<TodoProvider>().postponeOverdue(
                    AppClock.now(),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已顺延 $overdueCount 个逾期任务'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.update_outlined, size: 18),
                label: const Text('顺延'),
              ),
          ],
        ],
      ),
      body: baseTodos.isEmpty
          ? EmptyState(
              icon: Icons.check_circle_outline,
              message: s.todoEmpty,
              actionLabel: s.todoAddAction,
              onAction: _showAddDialog,
            )
          : isWidescreen && !_batchMode
          ? widescreenBody
          : Column(
              children: [
                if (!_batchMode)
                  _TodoViewSwitcher(
                    selected: _viewMode,
                    onChanged: (mode) => setState(() => _viewMode = mode),
                  ),
                if (!_batchMode)
                  _TodoTodaySummaryCard(
                    todos: baseTodos,
                    habits: habitProvider.habits,
                    activeGoalCount: goalProvider.activeGoals.length,
                    now: now,
                  ),
                _TodoFilterBar(
                  filter: _filter,
                  totalCount: baseTodos.length,
                  filteredCount: filteredTodos.length,
                  availableTags: availableTags,
                  availableListGroups: availableListGroups,
                  onChanged: _setFilter,
                  onClear: _clearFilter,
                ),
                Expanded(child: viewContent),
              ],
            ),
      bottomNavigationBar: _batchMode
          ? _TodoBatchActionBar(
              selectedCount: _selectedTodoIds.length,
              submitting: _batchSubmitting,
              onComplete: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _completeSelected,
              onReopen: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _reopenSelected,
              onMove: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _moveSelected,
              onPriority: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _setSelectedPriority,
              onDelete: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _deleteSelected,
            )
          : null,
      floatingActionButton: _batchMode
          ? null
          : FloatingActionButton(
              onPressed: _showAddDialog,
              child: const Icon(Icons.add),
            ),
    );
  }
}

class _TodoViewSwitcher extends StatelessWidget {
  final _TodoViewMode selected;
  final ValueChanged<_TodoViewMode> onChanged;

  const _TodoViewSwitcher({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: AppPageSwitcher<_TodoViewMode>(
        options: const [
          AppPageOption(value: _TodoViewMode.matrix, text: '四象限'),
          AppPageOption(value: _TodoViewMode.list, text: '列表'),
          AppPageOption(value: _TodoViewMode.kanban, text: '看板'),
        ],
        value: selected,
        onChanged: onChanged,
      ),
    );
  }
}

class _TodoTodaySummaryCard extends StatelessWidget {
  final List<TodoItem> todos;
  final List<Habit> habits;
  final int activeGoalCount;
  final DateTime now;

  const _TodoTodaySummaryCard({
    required this.todos,
    required this.habits,
    required this.activeGoalCount,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime(now.year, now.month, now.day);
    final visibleTodos = todos
        .where(
          (todo) => CompletionVisibilityPolicy.shouldShowInToday(todo, now),
        )
        .toList(growable: false);
    final todoCount = visibleTodos.length;
    final todayDone = todos.where((todo) {
      if (!todo.isCompleted) return false;
      final completedAt = todo.completedAt;
      if (completedAt == null) return false;
      return CompletionVisibilityPolicy.dateOnly(
            AppClock.toLocal(completedAt),
          ) ==
          today;
    }).length;
    final todayTotal = todayDone + todoCount;
    final overdueCount = todos.where((todo) => todo.isOverdue).length;
    final activeDailyHabits = habits.where((habit) => habit.activeForDate(now));
    final dailyCount = activeDailyHabits.length;
    final dailyDone = activeDailyHabits
        .where((habit) => habit.isCompletedForDate(now))
        .length;
    final dailyRemaining = (dailyCount - dailyDone).clamp(0, dailyCount);
    final remaining = dailyRemaining + todoCount + activeGoalCount;
    final urgentCount = todos
        .where(
          (todo) =>
              !todo.isCompleted &&
              (todo.priority == TodoPriority.urgent ||
                  todo.quadrant == EisenhowerQuadrant.urgentImportant),
        )
        .length;
    final chips = <_TodoSummaryChipData>[
      _TodoSummaryChipData(
        icon: Icons.check_circle_outline,
        label: '今日',
        value: '$todayDone/$todayTotal',
        color: cs.primary,
      ),
      _TodoSummaryChipData(
        icon: Icons.priority_high_outlined,
        label: '重点',
        value: '$urgentCount',
        color: Colors.deepOrange,
      ),
      _TodoSummaryChipData(
        icon: Icons.warning_amber_outlined,
        label: '逾期',
        value: '$overdueCount',
        color: cs.error,
      ),
    ];

    return AppSurfaceCard(
      key: const ValueKey('todo_today_summary_card'),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      borderRadius: BorderRadius.circular(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 420;
          final header = Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.today_outlined, color: cs.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '今日还要完成 $remaining 项',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: DesignTokens.fontWeightStrong,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '日常 $dailyRemaining / 待办 $todoCount / 目标 $activeGoalCount',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final chipRow = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips
                .map((chip) => _TodoSummaryChip(data: chip))
                .toList(),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [header, const SizedBox(height: 12), chipRow],
            );
          }
          return Row(
            children: [
              Expanded(child: header),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: chipRow,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TodoSummaryChipData {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _TodoSummaryChipData({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}

class _TodoSummaryChip extends StatelessWidget {
  final _TodoSummaryChipData data;

  const _TodoSummaryChip({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 86, maxWidth: 118),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: data.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: data.color.withValues(alpha: 0.16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(data.icon, size: 15, color: data.color),
            const SizedBox(width: 6),
            Text(
              data.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.68),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                data.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoFilterBar extends StatelessWidget {
  final TodoFilterState<EisenhowerQuadrant, TodoPriority> filter;
  final int totalCount;
  final int filteredCount;
  final List<String> availableTags;
  final List<String> availableListGroups;
  final ValueChanged<TodoFilterState<EisenhowerQuadrant, TodoPriority>>
  onChanged;
  final VoidCallback onClear;

  const _TodoFilterBar({
    required this.filter,
    required this.totalCount,
    required this.filteredCount,
    required this.availableTags,
    required this.availableListGroups,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = filter.hasActiveFilters;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.filter_alt_outlined,
                size: 18,
                color: active ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '自定义视图 · $filteredCount/$totalCount',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: active ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
              ),
              if (active)
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('清空'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _TodoQuickFilterChip(
                  label: '今日',
                  icon: Icons.today_outlined,
                  selected: filter.due == TodoDueFilter.dueToday,
                  onPressed: () => onChanged(
                    filter.copyWith(
                      due: filter.due == TodoDueFilter.dueToday
                          ? TodoDueFilter.all
                          : TodoDueFilter.dueToday,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _TodoQuickFilterChip(
                  label: '逾期',
                  icon: Icons.warning_amber_outlined,
                  selected: filter.due == TodoDueFilter.overdue,
                  onPressed: () => onChanged(
                    filter.copyWith(
                      due: filter.due == TodoDueFilter.overdue
                          ? TodoDueFilter.all
                          : TodoDueFilter.overdue,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _TodoQuickFilterChip(
                  label: '7天内',
                  icon: Icons.date_range_outlined,
                  selected: filter.due == TodoDueFilter.next7Days,
                  onPressed: () => onChanged(
                    filter.copyWith(
                      due: filter.due == TodoDueFilter.next7Days
                          ? TodoDueFilter.all
                          : TodoDueFilter.next7Days,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _TodoQuickFilterChip(
                  label: '已完成',
                  icon: Icons.check_circle_outline,
                  selected: filter.completion == TodoCompletionFilter.completed,
                  onPressed: () => onChanged(
                    filter.copyWith(
                      completion:
                          filter.completion == TodoCompletionFilter.completed
                          ? TodoCompletionFilter.all
                          : TodoCompletionFilter.completed,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _TodoFilterMenu<EisenhowerQuadrant>(
                  icon: Icons.grid_view_outlined,
                  label: filter.quadrant == null
                      ? '象限'
                      : _quadrantLabel(filter.quadrant!),
                  selected: filter.quadrant != null,
                  selectedValue: filter.quadrant,
                  options: [
                    const _TodoFilterOption(label: '全部象限'),
                    for (final quadrant in EisenhowerQuadrant.values)
                      _TodoFilterOption(
                        label: _quadrantLabel(quadrant),
                        value: quadrant,
                      ),
                  ],
                  onSelected: (value) =>
                      onChanged(filter.copyWith(quadrant: value)),
                ),
                const SizedBox(width: 8),
                _TodoFilterMenu<TodoPriority>(
                  icon: Icons.flag_outlined,
                  label: filter.priority == null
                      ? '优先级'
                      : filter.priority!.label,
                  selected: filter.priority != null,
                  selectedValue: filter.priority,
                  options: [
                    const _TodoFilterOption(label: '全部优先级'),
                    for (final priority in TodoPriority.values)
                      _TodoFilterOption(label: priority.label, value: priority),
                  ],
                  onSelected: (value) =>
                      onChanged(filter.copyWith(priority: value)),
                ),
                const SizedBox(width: 8),
                _TodoFilterMenu<TodoDueFilter>(
                  icon: Icons.event_outlined,
                  label: filter.due == TodoDueFilter.all
                      ? '日期'
                      : _dueFilterLabel(filter.due),
                  selected: filter.due != TodoDueFilter.all,
                  selectedValue: filter.due,
                  options: [
                    for (final due in TodoDueFilter.values)
                      _TodoFilterOption(
                        label: _dueFilterLabel(due),
                        value: due,
                      ),
                  ],
                  onSelected: (value) => onChanged(filter.copyWith(due: value)),
                ),
                const SizedBox(width: 8),
                _TodoFilterMenu<TodoCompletionFilter>(
                  icon: Icons.check_circle_outline,
                  label: filter.completion == TodoCompletionFilter.all
                      ? '完成状态'
                      : _completionFilterLabel(filter.completion),
                  selected: filter.completion != TodoCompletionFilter.all,
                  selectedValue: filter.completion,
                  options: [
                    for (final completion in TodoCompletionFilter.values)
                      _TodoFilterOption(
                        label: _completionFilterLabel(completion),
                        value: completion,
                      ),
                  ],
                  onSelected: (value) =>
                      onChanged(filter.copyWith(completion: value)),
                ),
                if (availableTags.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _TodoFilterMenu<String>(
                    icon: Icons.sell_outlined,
                    label: filter.tag == null ? '标签' : '#${filter.tag}',
                    selected: filter.tag != null,
                    selectedValue: filter.tag,
                    options: [
                      const _TodoFilterOption(label: '全部标签'),
                      for (final tag in availableTags)
                        _TodoFilterOption(label: '#$tag', value: tag),
                    ],
                    onSelected: (value) =>
                        onChanged(filter.copyWith(tag: value)),
                  ),
                ],
                if (availableListGroups.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _TodoFilterMenu<String>(
                    icon: Icons.folder_outlined,
                    label: filter.listGroupName ?? '清单',
                    selected: filter.listGroupName != null,
                    selectedValue: filter.listGroupName,
                    options: [
                      const _TodoFilterOption(label: '全部清单'),
                      for (final group in availableListGroups)
                        _TodoFilterOption(label: group, value: group),
                    ],
                    onSelected: (value) =>
                        onChanged(filter.copyWith(listGroupName: value)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodoQuickFilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  const _TodoQuickFilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onSelected: (_) => onPressed(),
    );
  }
}

class _TodoFilterMenu<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final T? selectedValue;
  final List<_TodoFilterOption<T>> options;
  final ValueChanged<T?> onSelected;

  const _TodoFilterMenu({
    required this.icon,
    required this.label,
    required this.selected,
    required this.selectedValue,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.primary : cs.onSurfaceVariant;

    return PopupMenuButton<_TodoFilterOption<T>>(
      tooltip: label,
      position: PopupMenuPosition.under,
      onSelected: (option) => onSelected(option.value),
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem(
            value: option,
            child: Row(
              children: [
                Expanded(
                  child: AppSecondaryMenuText(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (option.value == selectedValue)
                  Icon(Icons.check, size: 16, color: cs.primary),
              ],
            ),
          ),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.1)
              : cs.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? cs.primary.withValues(alpha: 0.35)
                : cs.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: color),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}

class _TodoFilterOption<T> {
  final String label;
  final T? value;

  const _TodoFilterOption({required this.label, this.value});
}

class _TodoNoMatches extends StatelessWidget {
  final VoidCallback onClear;

  const _TodoNoMatches({required this.onClear});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_off_outlined,
              size: 44,
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text('没有匹配任务', style: TextStyle(fontSize: 16, color: cs.onSurface)),
            const SizedBox(height: 8),
            Text(
              '调整自定义视图条件或清空筛选',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('清空筛选'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoBatchActionBar extends StatelessWidget {
  final int selectedCount;
  final bool submitting;
  final Future<void> Function()? onComplete;
  final Future<void> Function()? onReopen;
  final Future<void> Function(EisenhowerQuadrant quadrant)? onMove;
  final Future<void> Function(TodoPriority priority)? onPriority;
  final Future<void> Function()? onDelete;

  const _TodoBatchActionBar({
    required this.selectedCount,
    required this.submitting,
    required this.onComplete,
    required this.onReopen,
    required this.onMove,
    required this.onPriority,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = selectedCount > 0 && !submitting;
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(
            top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
          ),
          boxShadow: DesignTokens.shadowXs,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    submitting ? '处理中...' : '已选 $selectedCount',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.primary,
                      fontWeight: DesignTokens.fontWeightStrong,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: enabled ? onComplete : null,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('完成'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: enabled ? onReopen : null,
                  icon: const Icon(Icons.undo_outlined, size: 18),
                  label: const Text('恢复'),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<EisenhowerQuadrant>(
                  tooltip: '移动到',
                  enabled: enabled && onMove != null,
                  onSelected: (quadrant) => onMove?.call(quadrant),
                  itemBuilder: (context) => [
                    for (final quadrant in EisenhowerQuadrant.values)
                      PopupMenuItem(
                        value: quadrant,
                        child: Row(
                          children: [
                            Icon(
                              Icons.circle,
                              size: 10,
                              color: _quadrantColor(quadrant),
                            ),
                            const SizedBox(width: 8),
                            AppSecondaryMenuText(_quadrantLabel(quadrant)),
                          ],
                        ),
                      ),
                  ],
                  child: _BatchMenuButton(
                    icon: Icons.drive_file_move_outline,
                    label: '移动到',
                    enabled: enabled && onMove != null,
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<TodoPriority>(
                  tooltip: '优先级',
                  enabled: enabled && onPriority != null,
                  onSelected: (priority) => onPriority?.call(priority),
                  itemBuilder: (context) => [
                    for (final priority in TodoPriority.values)
                      PopupMenuItem(
                        value: priority,
                        child: Row(
                          children: [
                            Icon(
                              Icons.flag,
                              size: 16,
                              color: priorityColor(priority),
                            ),
                            const SizedBox(width: 8),
                            AppSecondaryMenuText(priority.label),
                          ],
                        ),
                      ),
                  ],
                  child: _BatchMenuButton(
                    icon: Icons.flag_outlined,
                    label: '优先级',
                    enabled: enabled && onPriority != null,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: enabled ? onDelete : null,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('删除'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.error,
                    side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BatchMenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;

  const _BatchMenuButton({
    required this.icon,
    required this.label,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.38);
    final border = enabled
        ? cs.outline.withValues(alpha: 0.5)
        : cs.outline.withValues(alpha: 0.24);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: appSecondaryControlTextStyle(
              context,
            ).copyWith(color: color, fontWeight: DesignTokens.fontWeightStrong),
          ),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down, size: 18, color: color),
        ],
      ),
    );
  }
}

String _dueFilterLabel(TodoDueFilter filter) {
  return switch (filter) {
    TodoDueFilter.all => '全部日期',
    TodoDueFilter.overdue => '逾期',
    TodoDueFilter.dueToday => '今日',
    TodoDueFilter.next7Days => '未来7天',
    TodoDueFilter.noDue => '无日期',
  };
}

String _completionFilterLabel(TodoCompletionFilter filter) {
  return switch (filter) {
    TodoCompletionFilter.all => '全部任务',
    TodoCompletionFilter.active => '未完成',
    TodoCompletionFilter.completed => '已完成',
  };
}

class _TodoKanbanView extends StatelessWidget {
  final TodoKanbanBoardConfig config;
  final Map<String, List<TodoItem>> kanbanGroups;
  final bool batchMode;
  final Set<String> selectedTodoIds;
  final ValueChanged<String> onToggleSelection;
  final ValueChanged<String> onEnterBatchMode;
  final int swipeDismissSerial;
  final ValueChanged<ScrollNotification> onScrollStart;

  const _TodoKanbanView({
    required this.config,
    required this.kanbanGroups,
    required this.batchMode,
    required this.selectedTodoIds,
    required this.onToggleSelection,
    required this.onEnterBatchMode,
    required this.swipeDismissSerial,
    required this.onScrollStart,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final columns = config.sortedColumns;
    return Column(
      children: [
        if (config.groupMode != TodoKanbanGroupMode.none)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                Icon(Icons.account_tree_outlined, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  '看板分组：${config.groupMode.label}',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.66),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              onScrollStart(notification);
              return false;
            },
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              // ignore: deprecated_member_use
              cacheExtent: 560,
              itemCount: columns.length,
              itemBuilder: (context, index) {
                final column = columns[index];
                return _KanbanColumn(
                  column: column,
                  columns: columns,
                  groupMode: config.groupMode,
                  todos: kanbanGroups[column.id] ?? const <TodoItem>[],
                  batchMode: batchMode,
                  selectedTodoIds: selectedTodoIds,
                  onToggleSelection: onToggleSelection,
                  onEnterBatchMode: onEnterBatchMode,
                  swipeDismissSerial: swipeDismissSerial,
                  onScrollStart: onScrollStart,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _KanbanGroupedTodos {
  final String label;
  final int sortOrder;
  final List<TodoItem> todos;

  const _KanbanGroupedTodos({
    required this.label,
    required this.sortOrder,
    required this.todos,
  });
}

class _KanbanColumnListEntry {
  final _KanbanGroupedTodos? header;
  final TodoItem? todo;

  const _KanbanColumnListEntry.header(this.header) : todo = null;

  const _KanbanColumnListEntry.todo(this.todo) : header = null;
}

class _KanbanGroupKey {
  final String id;
  final String label;
  final int sortOrder;

  const _KanbanGroupKey({
    required this.id,
    required this.label,
    required this.sortOrder,
  });
}

List<_KanbanGroupedTodos> _groupKanbanTodos(
  List<TodoItem> todos,
  TodoKanbanGroupMode mode,
  DateTime now,
) {
  if (mode == TodoKanbanGroupMode.none) {
    return [
      if (todos.isNotEmpty)
        _KanbanGroupedTodos(label: '', sortOrder: 0, todos: todos),
    ];
  }
  final groups = <String, _KanbanGroupedTodos>{};
  for (final todo in todos) {
    final key = _kanbanGroupKey(todo, mode, now);
    groups.putIfAbsent(
      key.id,
      () => _KanbanGroupedTodos(
        label: key.label,
        sortOrder: key.sortOrder,
        todos: <TodoItem>[],
      ),
    );
    groups[key.id]!.todos.add(todo);
  }
  final result = groups.values.toList();
  result.sort((a, b) {
    final order = a.sortOrder.compareTo(b.sortOrder);
    if (order != 0) return order;
    return a.label.compareTo(b.label);
  });
  return result;
}

_KanbanGroupKey _kanbanGroupKey(
  TodoItem todo,
  TodoKanbanGroupMode mode,
  DateTime now,
) {
  switch (mode) {
    case TodoKanbanGroupMode.priority:
      if (todo.priority == TodoPriority.none) {
        return _KanbanGroupKey(
          id: 'priority_none',
          label: I18n.tr('todo.kanban.no_priority'),
          sortOrder: 50,
        );
      }
      return _KanbanGroupKey(
        id: 'priority_${todo.priority.name}',
        label: todo.priority.label,
        sortOrder: 10 - todo.priority.rank,
      );
    case TodoKanbanGroupMode.dueDate:
      final due = todo.dueDate;
      if (due == null) {
        return _KanbanGroupKey(
          id: 'due_none',
          label: I18n.tr('todo.kanban.no_due'),
          sortOrder: 50,
        );
      }
      final today = DateTime(now.year, now.month, now.day);
      final dueDay = DateTime(due.year, due.month, due.day);
      if (dueDay.isBefore(today)) {
        return _KanbanGroupKey(
          id: 'due_overdue',
          label: I18n.tr('todo.kanban.overdue'),
          sortOrder: 0,
        );
      }
      if (dueDay == today) {
        return _KanbanGroupKey(
          id: 'due_today',
          label: I18n.tr('todo.kanban.today'),
          sortOrder: 10,
        );
      }
      if (dueDay.isBefore(today.add(const Duration(days: 7)))) {
        return _KanbanGroupKey(
          id: 'due_week',
          label: I18n.tr('todo.kanban.within_7_days'),
          sortOrder: 20,
        );
      }
      return _KanbanGroupKey(
        id: 'due_later',
        label: I18n.tr('todo.kanban.later'),
        sortOrder: 30,
      );
    case TodoKanbanGroupMode.tag:
      final tag = todo.tags
          .map((item) => item.trim())
          .firstWhere((item) => item.isNotEmpty, orElse: () => '');
      if (tag.isEmpty) {
        return _KanbanGroupKey(
          id: 'tag_none',
          label: I18n.tr('todo.kanban.no_tag'),
          sortOrder: 9999,
        );
      }
      return _KanbanGroupKey(id: 'tag_$tag', label: tag, sortOrder: 100);
    case TodoKanbanGroupMode.list:
      final listName = todo.listGroupName?.trim() ?? '';
      if (listName.isEmpty) {
        return _KanbanGroupKey(
          id: 'list_default',
          label: I18n.tr('todo.kanban.default_list'),
          sortOrder: 9999,
        );
      }
      return _KanbanGroupKey(
        id: 'list_$listName',
        label: listName,
        sortOrder: 100,
      );
    case TodoKanbanGroupMode.none:
      return const _KanbanGroupKey(id: 'none', label: '', sortOrder: 0);
  }
}

class _KanbanColumn extends StatelessWidget {
  final TodoKanbanColumn column;
  final List<TodoKanbanColumn> columns;
  final TodoKanbanGroupMode groupMode;
  final List<TodoItem> todos;
  final bool batchMode;
  final Set<String> selectedTodoIds;
  final ValueChanged<String> onToggleSelection;
  final ValueChanged<String> onEnterBatchMode;
  final int swipeDismissSerial;
  final ValueChanged<ScrollNotification> onScrollStart;

  const _KanbanColumn({
    required this.column,
    required this.columns,
    required this.groupMode,
    required this.todos,
    required this.batchMode,
    required this.selectedTodoIds,
    required this.onToggleSelection,
    required this.onEnterBatchMode,
    required this.swipeDismissSerial,
    required this.onScrollStart,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = Color(column.colorValue);
    AppClock.watch(context);
    final groupedTodos = _groupKanbanTodos(todos, groupMode, AppClock.now());
    final listEntries = <_KanbanColumnListEntry>[
      for (final group in groupedTodos) ...[
        if (groupMode != TodoKanbanGroupMode.none)
          _KanbanColumnListEntry.header(group),
        for (final todo in group.todos) _KanbanColumnListEntry.todo(todo),
      ],
    ];
    return SizedBox(
      width: 280,
      child: DragTarget<String>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (details) {
          context.read<TodoProvider>().updateTodosKanbanColumn([
            details.data,
          ], column.id);
        },
        builder: (context, candidateData, rejectedData) {
          final hovering = candidateData.isNotEmpty;
          return AppSurfaceCard(
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withValues(alpha: hovering ? 0.58 : 0.22),
              width: hovering ? 1.4 : 1,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        column.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface,
                          fontWeight: DesignTokens.fontWeightStrong,
                        ),
                      ),
                    ),
                    AppStatusBadge(label: '${todos.length}', color: color),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: todos.isEmpty
                      ? Center(
                          child: Text(
                            hovering ? '松手移动到这里' : '暂无任务',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withValues(alpha: 0.45),
                            ),
                          ),
                        )
                      : NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            onScrollStart(notification);
                            return false;
                          },
                          child: ListView.builder(
                            // ignore: deprecated_member_use
                            cacheExtent: 560,
                            itemCount: listEntries.length,
                            itemBuilder: (context, index) {
                              final entry = listEntries[index];
                              final header = entry.header;
                              if (header != null) {
                                return Padding(
                                  padding: const EdgeInsets.only(
                                    top: 2,
                                    bottom: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          header.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: cs.onSurface.withValues(
                                              alpha: 0.62,
                                            ),
                                            fontWeight:
                                                DesignTokens.fontWeightStrong,
                                          ),
                                        ),
                                      ),
                                      AppStatusBadge(
                                        label: '${header.todos.length}',
                                        color: color,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              final todo = entry.todo!;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _KanbanTodoCard(
                                  todo: todo,
                                  columns: columns,
                                  color: color,
                                  batchMode: batchMode,
                                  selected: selectedTodoIds.contains(todo.id),
                                  onToggleSelection: onToggleSelection,
                                  onEnterBatchMode: onEnterBatchMode,
                                  swipeDismissSerial: swipeDismissSerial,
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _KanbanTodoCard extends StatefulWidget {
  final TodoItem todo;
  final List<TodoKanbanColumn> columns;
  final Color color;
  final bool batchMode;
  final bool selected;
  final ValueChanged<String> onToggleSelection;
  final ValueChanged<String> onEnterBatchMode;
  final int swipeDismissSerial;

  const _KanbanTodoCard({
    required this.todo,
    required this.columns,
    required this.color,
    required this.batchMode,
    required this.selected,
    required this.onToggleSelection,
    required this.onEnterBatchMode,
    required this.swipeDismissSerial,
  });

  @override
  State<_KanbanTodoCard> createState() => _KanbanTodoCardState();
}

class _KanbanTodoCardState extends State<_KanbanTodoCard> {
  static const double _swipeActionWidth = _TodoTileState._swipeActionWidth;
  static const double _swipeOpenThreshold = 36;

  double _swipeOffset = 0;
  bool _dragging = false;

  bool get _swipeOpen => _swipeOffset > 0;
  bool get _swipeActive => _swipeOffset > 0;

  @override
  void didUpdateWidget(covariant _KanbanTodoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.batchMode ||
        widget.todo.id != oldWidget.todo.id ||
        widget.swipeDismissSerial != oldWidget.swipeDismissSerial) {
      _swipeOffset = 0;
      _dragging = false;
    }
  }

  void _closeSwipe() {
    if (!_swipeOpen || !mounted) return;
    setState(() => _swipeOffset = 0);
  }

  Future<void> _openDetails(BuildContext context) async {
    _closeSwipe();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TodoDetailScreen(todoId: widget.todo.id),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    TodoProvider provider,
  ) async {
    _closeSwipe();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AppDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('删除任务？'),
        content: Text('将删除“${widget.todo.title}”，相关时间足迹也会同步移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.deleteTodo(widget.todo.id);
    } else {
      _closeSwipe();
    }
  }

  Future<void> _toggleCompletion(BuildContext context) async {
    _closeSwipe();
    await _toggleTodoCompletionFromSwipe(context, widget.todo);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.read<TodoProvider>();
    final todo = widget.todo;
    final canEdit = context.watch<ShareProvider>().canEdit(todo.workspaceId);
    final visual = CompletionVisibilityPolicy.visualState(todo);
    final stateColor = CompletionVisibilityPolicy.colorFor(visual);
    final isCompleted = visual == TodoVisualState.completed;
    final isOverdue = visual == TodoVisualState.overdue;
    final isDueSoon = visual == TodoVisualState.dueSoon;
    final statusColor = isCompleted || isOverdue || isDueSoon
        ? stateColor
        : widget.color;
    final statusBackground = isCompleted || isOverdue || isDueSoon
        ? Color.alphaBlend(
            stateColor.withValues(alpha: isCompleted ? 0.06 : 0.08),
            cs.surfaceContainerHighest,
          )
        : cs.surfaceContainerHighest.withValues(alpha: 0.42);
    final card = Material(
      color: widget.selected
          ? widget.color.withValues(alpha: 0.14)
          : statusBackground,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.batchMode
            ? canEdit
                  ? () => widget.onToggleSelection(todo.id)
                  : null
            : _swipeOpen
            ? _closeSwipe
            : () => _openDetails(context),
        onLongPress: canEdit ? () => widget.onEnterBatchMode(todo.id) : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.batchMode) ...[
                    Checkbox(
                      value: widget.selected,
                      visualDensity: VisualDensity.compact,
                      onChanged: canEdit
                          ? (_) => widget.onToggleSelection(todo.id)
                          : null,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      todo.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: isCompleted
                            ? cs.onSurface.withValues(alpha: 0.54)
                            : isOverdue
                            ? cs.error
                            : cs.onSurface,
                        decoration: isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        fontWeight: DesignTokens.fontWeightStrong,
                      ),
                    ),
                  ),
                  if (canEdit && !widget.batchMode)
                    PopupMenuButton<TodoKanbanColumn>(
                      tooltip: '移动到',
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.more_horiz,
                        size: 18,
                        color: cs.onSurface.withValues(alpha: 0.56),
                      ),
                      onSelected: (column) => provider.updateTodosKanbanColumn([
                        todo.id,
                      ], column.id),
                      itemBuilder: (context) => [
                        for (final column in widget.columns)
                          PopupMenuItem(
                            value: column,
                            enabled: column.id != todo.kanbanColumnId,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 10,
                                  color: Color(column.colorValue),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: AppSecondaryMenuText(column.title),
                                ),
                                if (column.id == todo.kanbanColumnId) ...[
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.check,
                                    size: 16,
                                    color: cs.primary,
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (todo.priority != TodoPriority.none)
                    AppStatusBadge(
                      label: todo.priority.label,
                      color: priorityColor(todo.priority),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                    ),
                  if (todo.dueDate != null)
                    AppStatusBadge(
                      label: I18nDateFormat.compactDateTime(
                        todo.dueDate!,
                        omitTimeWhenMidnight: true,
                      ),
                      color: statusColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                    ),
                  if (isCompleted)
                    AppStatusBadge(
                      label: '已完成',
                      color: statusColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                    ),
                  if (isOverdue)
                    AppStatusBadge(
                      label: '过期',
                      color: statusColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                    ),
                  if (isDueSoon)
                    AppStatusBadge(
                      label: '临期',
                      color: statusColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                    ),
                  if (todo.subtasks.isNotEmpty)
                    AppStatusBadge(
                      label:
                          '${todo.subtasks.where((s) => s.isCompleted).length}/${todo.subtasks.length} 子任务',
                      color: cs.secondary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!canEdit || widget.batchMode) return card;

    final swipeCard = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => setState(() => _dragging = true),
      onHorizontalDragUpdate: (details) {
        final next = (_swipeOffset - details.delta.dx).clamp(
          0.0,
          _swipeActionWidth,
        );
        if (next == _swipeOffset) return;
        setState(() => _swipeOffset = next);
      },
      onHorizontalDragEnd: (_) {
        final shouldOpen = _swipeOffset >= _swipeOpenThreshold;
        setState(() {
          _dragging = false;
          _swipeOffset = shouldOpen ? _swipeActionWidth : 0;
        });
      },
      onHorizontalDragCancel: () => setState(() {
        _dragging = false;
        _swipeOffset = _swipeOffset >= _swipeOpenThreshold
            ? _swipeActionWidth
            : 0;
      }),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          if (_swipeActive)
            Positioned.fill(
              child: RepaintBoundary(
                child: _TodoInlineSwipeActions(
                  margin: EdgeInsets.zero,
                  onToggleCompletion: () => _toggleCompletion(context),
                  onDelete: () => _confirmDelete(context, provider),
                  completed: todo.isCompleted,
                ),
              ),
            ),
          AnimatedContainer(
            duration: _dragging
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(-_swipeOffset, 0, 0),
            child: RepaintBoundary(child: card),
          ),
        ],
      ),
    );

    return LongPressDraggable<String>(
      data: todo.id,
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Opacity(opacity: 0.92, child: card),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.42, child: swipeCard),
      child: swipeCard,
    );
  }
}

class _KanbanSettingsSheet extends StatefulWidget {
  final TodoKanbanBoardConfig config;

  const _KanbanSettingsSheet({required this.config});

  @override
  State<_KanbanSettingsSheet> createState() => _KanbanSettingsSheetState();
}

class _KanbanSettingsSheetState extends State<_KanbanSettingsSheet> {
  late List<TodoKanbanColumn> _columns;
  late TodoKanbanGroupMode _groupMode;

  static const _palette = [
    0xFF607D8B,
    0xFF1976D2,
    0xFF7B1FA2,
    0xFFD32F2F,
    0xFFF57C00,
    0xFF2E7D32,
    0xFF00897B,
  ];

  @override
  void initState() {
    super.initState();
    _columns = widget.config.sortedColumns;
    _groupMode = widget.config.groupMode;
  }

  void _updateColumn(TodoKanbanColumn column) {
    setState(() {
      final index = _columns.indexWhere((item) => item.id == column.id);
      if (index != -1) _columns[index] = column;
    });
  }

  void _moveColumn(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _columns.length) return;
    setState(() {
      final column = _columns.removeAt(index);
      _columns.insert(target, column);
      _renumber();
    });
  }

  void _addColumn() {
    setState(() {
      final id = 'custom_${DateTime.now().microsecondsSinceEpoch}';
      _columns.add(
        TodoKanbanColumn(
          id: id,
          title: '新列',
          colorValue: _palette[_columns.length % _palette.length],
          sortOrder: _columns.length,
        ),
      );
    });
  }

  void _renumber() {
    for (var i = 0; i < _columns.length; i++) {
      _columns[i] = _columns[i].copyWith(sortOrder: i);
    }
  }

  /// 删除自定义看板列；该列上的任务会由 normalizeColumnId
  /// 归并到默认「待处理」列（保存后生效）。
  Future<void> _deleteColumn(int index) async {
    final column = _columns[index];
    if (column.builtIn) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AppDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('删除看板列'),
        content: Text('确认删除「${column.title}」吗？该列上的任务会移回「待处理」。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      // 删除语义统一走 core 的 removeColumn（内置列拒删、normalizeColumnId
      // 归并、sortOrder 压实），避免 UI 与 core 双实现后续分叉。
      final next = TodoKanbanBoardConfig(
        columns: _columns,
        groupMode: _groupMode,
      ).removeColumn(column.id);
      if (next == null) return;
      _columns = next.sortedColumns;
    });
  }

  void _save() {
    final normalized = <TodoKanbanColumn>[];
    for (var i = 0; i < _columns.length; i++) {
      final column = _columns[i];
      final title = column.title.trim();
      normalized.add(
        column.copyWith(title: title.isEmpty ? '未命名列' : title, sortOrder: i),
      );
    }
    Navigator.pop(
      context,
      TodoKanbanBoardConfig(columns: normalized, groupMode: _groupMode),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppModalSheet(
      title: '看板列设置',
      subtitle: '调整列顺序、颜色和默认分组',
      actions: [
        FilledButton(
          onPressed: _save,
          style: appSecondaryFilledButtonStyle(context),
          child: const Text('保存'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppDropdownField<TodoKanbanGroupMode>(
            initialValue: _groupMode,
            decoration: const InputDecoration(
              labelText: '默认分组',
              helperText: '列内可按优先级、截止日、标签或清单分组',
              isDense: true,
            ),
            items: [
              for (final mode in TodoKanbanGroupMode.values)
                DropdownMenuItem(value: mode, child: Text(mode.label)),
            ],
            onChanged: (mode) {
              if (mode == null) return;
              setState(() => _groupMode = mode);
            },
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 440),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _columns.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final column = _columns[index];
                return AppSurfaceCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.circle,
                            color: Color(column.colorValue),
                            size: 14,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              initialValue: column.title,
                              decoration: const InputDecoration(
                                labelText: '列名称',
                                isDense: true,
                              ),
                              onChanged: (value) =>
                                  _updateColumn(column.copyWith(title: value)),
                            ),
                          ),
                          IconButton(
                            tooltip: '上移',
                            onPressed: index == 0
                                ? null
                                : () => _moveColumn(index, -1),
                            icon: const Icon(Icons.arrow_upward),
                          ),
                          IconButton(
                            tooltip: '下移',
                            onPressed: index == _columns.length - 1
                                ? null
                                : () => _moveColumn(index, 1),
                            icon: const Icon(Icons.arrow_downward),
                          ),
                          IconButton(
                            tooltip: column.builtIn ? '内置列不可删除' : '删除列',
                            onPressed: column.builtIn
                                ? null
                                : () => _deleteColumn(index),
                            icon: Icon(
                              Icons.delete_outline,
                              color: column.builtIn
                                  ? null
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final value in _palette)
                            InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () => _updateColumn(
                                column.copyWith(colorValue: value),
                              ),
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Color(value),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: column.colorValue == value
                                        ? cs.onSurface
                                        : cs.outlineVariant,
                                    width: column.colorValue == value ? 2 : 1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _addColumn,
            icon: const Icon(Icons.add),
            label: const Text('新增列'),
          ),
        ],
      ),
    );
  }
}

Color _quadrantColor(EisenhowerQuadrant q) {
  switch (q) {
    case EisenhowerQuadrant.urgentImportant:
      return const Color(0xFFE53935);
    case EisenhowerQuadrant.notUrgentImportant:
      return const Color(0xFFF6A339);
    case EisenhowerQuadrant.urgentNotImportant:
      return const Color(0xFF42A5F5);
    case EisenhowerQuadrant.notUrgentNotImportant:
      return const Color(0xFF8E8E8E);
  }
}

String _quadrantLabel(EisenhowerQuadrant q) {
  switch (q) {
    case EisenhowerQuadrant.urgentImportant:
      return '重要且紧急';
    case EisenhowerQuadrant.notUrgentImportant:
      return '重要不紧急';
    case EisenhowerQuadrant.urgentNotImportant:
      return '紧急不重要';
    case EisenhowerQuadrant.notUrgentNotImportant:
      return '不重要不紧急';
  }
}

class _ListGroupTile extends StatefulWidget {
  final String groupName;
  final List<TodoItem> todos;
  final bool batchMode;
  final Set<String> selectedTodoIds;
  final ValueChanged<String> onToggleSelection;
  final ValueChanged<String> onEnterBatchMode;
  final int swipeDismissSerial;

  const _ListGroupTile({
    required this.groupName,
    required this.todos,
    required this.batchMode,
    required this.selectedTodoIds,
    required this.onToggleSelection,
    required this.onEnterBatchMode,
    required this.swipeDismissSerial,
  });

  @override
  State<_ListGroupTile> createState() => _ListGroupTileState();
}

class _ListGroupTileState extends State<_ListGroupTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final todoProvider = context.watch<TodoProvider>();
    final shareProvider = context.watch<ShareProvider>();
    final workspaceId = todoProvider.workspaceForListGroup(widget.groupName);
    final workspace = workspaceId == null
        ? null
        : shareProvider.workspaces
              .where((workspace) => workspace.id == workspaceId)
              .firstOrNull;
    return AppSurfaceCard(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                color: cs.primary,
              ),
            ),
            title: Text(
              widget.groupName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: DesignTokens.fontWeightStrong),
            ),
            subtitle: workspace == null
                ? null
                : Text(
                    '共享：${workspace.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (workspace != null)
                  Icon(Icons.groups_2_outlined, size: 18, color: cs.primary),
                IconButton(
                  tooltip: '共享清单',
                  onPressed: () => _shareGroup(context),
                  icon: const Icon(Icons.ios_share_outlined),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${widget.todos.length}',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: DesignTokens.fontWeightStrong,
                    ),
                  ),
                ),
              ],
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded) _buildTodoList(context, shareProvider),
        ],
      ),
    );
  }

  Widget _buildTodoList(BuildContext context, ShareProvider shareProvider) {
    final canReorder =
        !widget.batchMode &&
        widget.todos.length > 1 &&
        widget.todos.every((todo) => shareProvider.canEdit(todo.workspaceId));

    if (!canReorder) {
      return Column(
        children: [for (final todo in widget.todos) _buildTodoTile(todo)],
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: widget.todos.length,
      // ignore: deprecated_member_use
      onReorder: _reorderTodos,
      proxyDecorator: (child, index, animation) => Material(
        type: MaterialType.transparency,
        child: ScaleTransition(
          scale: Tween<double>(begin: 1, end: 1.02).animate(animation),
          child: child,
        ),
      ),
      itemBuilder: (context, index) {
        final todo = widget.todos[index];
        return _buildTodoTile(
          todo,
          key: ValueKey('todo-reorder-${todo.id}'),
          trailing: ReorderableDragStartListener(
            index: index,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Tooltip(
                message: '拖拽排序',
                child: Padding(
                  padding: const EdgeInsets.only(left: DesignTokens.spaceXs),
                  child: Icon(
                    Icons.drag_indicator,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTodoTile(TodoItem todo, {Key? key, Widget? trailing}) {
    return _TodoTile(
      key: key,
      todo: todo,
      batchMode: widget.batchMode,
      selected: widget.selectedTodoIds.contains(todo.id),
      onToggleSelection: widget.onToggleSelection,
      onEnterBatchMode: widget.onEnterBatchMode,
      trailing: trailing,
      swipeDismissSerial: widget.swipeDismissSerial,
    );
  }

  Future<void> _reorderTodos(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    if (newIndex > oldIndex) newIndex -= 1;

    final ids = widget.todos.map((todo) => todo.id).toList();
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    await context.read<TodoProvider>().reorderVisibleTodos(ids);
  }

  Future<void> _shareGroup(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (!auth.state.isLoggedIn) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ShareScreen()),
      );
      return;
    }

    final share = context.read<ShareProvider>();
    if (share.workspaces.isEmpty) await share.load();
    if (!context.mounted) return;
    final workspaces = share.workspaces.where((w) => !w.isPrivate).toList();
    if (workspaces.isEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ShareScreen()),
      );
      return;
    }

    final picked = await showAppModalSheet<String>(
      context: context,
      builder: (_) => AppModalSheet(
        title: '共享清单',
        subtitle: '把「${widget.groupName}」标记到共享空间',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: const Text('仅自己可见'),
              onTap: () => Navigator.pop(context, 'private'),
            ),
            for (final workspace in workspaces)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.groups_2_outlined),
                title: Text(workspace.name),
                subtitle: Text(
                  '${workspace.members.length} 位成员 · ${workspace.roleFor(auth.state.userId).label}',
                ),
                enabled: workspace.roleFor(auth.state.userId).canEdit,
                onTap: workspace.roleFor(auth.state.userId).canEdit
                    ? () => Navigator.pop(context, workspace.id)
                    : null,
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    await context.read<TodoProvider>().updateListGroupWorkspace(
      widget.groupName,
      picked,
      userId: auth.state.userId,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('共享状态已更新')));
  }
}

class _TodoTile extends StatefulWidget {
  final TodoItem todo;
  final bool batchMode;
  final bool selected;
  final ValueChanged<String> onToggleSelection;
  final ValueChanged<String> onEnterBatchMode;
  final Widget? trailing;
  final int swipeDismissSerial;

  const _TodoTile({
    super.key,
    required this.todo,
    required this.batchMode,
    required this.selected,
    required this.onToggleSelection,
    required this.onEnterBatchMode,
    this.trailing,
    this.swipeDismissSerial = 0,
  });

  @override
  State<_TodoTile> createState() => _TodoTileState();
}

class _TodoTileState extends State<_TodoTile> {
  static const double _swipeActionWidth = 98;
  static const double _swipeOpenThreshold = 36;

  double _swipeOffset = 0;
  bool _dragging = false;

  bool get _swipeOpen => _swipeOffset > 0;
  bool get _swipeActive => _swipeOffset > 0;

  @override
  void didUpdateWidget(covariant _TodoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.batchMode ||
        widget.todo.id != oldWidget.todo.id ||
        widget.swipeDismissSerial != oldWidget.swipeDismissSerial) {
      _swipeOffset = 0;
      _dragging = false;
    }
  }

  void _closeSwipe() {
    if (!_swipeOpen || !mounted) return;
    setState(() => _swipeOffset = 0);
  }

  Future<void> _openDetails(BuildContext context) async {
    _closeSwipe();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TodoDetailScreen(todoId: widget.todo.id),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    TodoProvider provider,
  ) async {
    _closeSwipe();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AppDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('删除任务？'),
        content: Text('将删除“${widget.todo.title}”，相关时间足迹也会同步移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.deleteTodo(widget.todo.id);
    } else {
      _closeSwipe();
    }
  }

  Future<void> _toggleCompletion(BuildContext context) async {
    _closeSwipe();
    await _toggleTodoCompletionFromSwipe(context, widget.todo);
  }

  @override
  Widget build(BuildContext context) {
    final todo = widget.todo;
    final visual = CompletionVisibilityPolicy.visualState(todo);
    // 已归档的任务不在今日 / 列表中渲染（P5）。
    if (visual == TodoVisualState.archived) {
      return const SizedBox.shrink();
    }

    final provider = context.read<TodoProvider>();
    final canEdit = context.watch<ShareProvider>().canEdit(todo.workspaceId);
    final cs = Theme.of(context).colorScheme;
    final qColor = _quadrantColor(todo.quadrant);
    final stateColor = CompletionVisibilityPolicy.colorFor(visual);
    final visualAccentColor = switch (visual) {
      TodoVisualState.completed ||
      TodoVisualState.overdue ||
      TodoVisualState.dueSoon => stateColor,
      _ => qColor,
    };
    final statusBackground = switch (visual) {
      TodoVisualState.completed => Color.alphaBlend(
        stateColor.withValues(alpha: 0.06),
        cs.surface,
      ),
      TodoVisualState.overdue => Color.alphaBlend(
        stateColor.withValues(alpha: 0.08),
        cs.surface,
      ),
      TodoVisualState.dueSoon => Color.alphaBlend(
        stateColor.withValues(alpha: 0.07),
        cs.surface,
      ),
      _ => cs.surface,
    };
    final statusBorder = switch (visual) {
      TodoVisualState.completed ||
      TodoVisualState.overdue ||
      TodoVisualState.dueSoon => Border.all(
        color: stateColor.withValues(alpha: 0.24),
        width: 0.7,
      ),
      _ => null,
    };
    final content = Container(
      margin: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceMd,
        vertical: DesignTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: widget.selected
            ? cs.primary.withValues(alpha: 0.08)
            : statusBackground,
        borderRadius: DesignTokens.borderRadiusMd,
        border: widget.selected
            ? Border.all(color: cs.primary.withValues(alpha: 0.28))
            : statusBorder,
        boxShadow: DesignTokens.shadowXs,
      ),
      child: ClipRRect(
        borderRadius: DesignTokens.borderRadiusMd,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(color: visualAccentColor),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.batchMode
                    ? canEdit
                          ? () => widget.onToggleSelection(todo.id)
                          : null
                    : _swipeOpen
                    ? _closeSwipe
                    : () => _openDetails(context),
                onLongPress: canEdit
                    ? () => widget.onEnterBatchMode(todo.id)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DesignTokens.spaceSm + 4,
                    DesignTokens.spaceSm,
                    DesignTokens.spaceSm,
                    DesignTokens.spaceSm,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          top: DesignTokens.spaceXxs,
                        ),
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          // 有子任务时完成态由子任务决定，这里显示进度而不是整任务勾选。
                          child: !widget.batchMode && todo.subtasks.isNotEmpty
                              ? Center(
                                  child: Text(
                                    '${todo.subtasks.where((subtask) => subtask.isCompleted).length}/${todo.subtasks.length}',
                                    key: ValueKey(
                                      'todo_subtask_progress_${todo.id}',
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          fontSize: 11,
                                          color: todo.isCompleted
                                              ? visualAccentColor
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                )
                              : Checkbox(
                                  value: widget.batchMode
                                      ? widget.selected
                                      : todo.isCompleted,
                                  shape: const CircleBorder(),
                                  activeColor: visualAccentColor,
                                  onChanged: canEdit
                                      ? (_) {
                                          if (widget.batchMode) {
                                            widget.onToggleSelection(todo.id);
                                          } else {
                                            completeTodoWithOptionalTimeRecord(
                                              context,
                                              todo,
                                            );
                                          }
                                        }
                                      : null,
                                ),
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spaceXs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _TitleRow(todo: todo, visual: visual),
                            const SizedBox(height: DesignTokens.spaceXxs),
                            _MetaRow(
                              todo: todo,
                              quadrantColor: qColor,
                              visual: visual,
                            ),
                          ],
                        ),
                      ),
                      if (widget.trailing != null) widget.trailing!,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.batchMode) return content;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: canEdit
          ? (_) => setState(() => _dragging = true)
          : null,
      onHorizontalDragUpdate: canEdit
          ? (details) {
              final next = (_swipeOffset - details.delta.dx).clamp(
                0.0,
                _swipeActionWidth,
              );
              if (next == _swipeOffset) return;
              setState(() => _swipeOffset = next);
            }
          : null,
      onHorizontalDragEnd: canEdit
          ? (_) {
              final shouldOpen = _swipeOffset >= _swipeOpenThreshold;
              setState(() {
                _dragging = false;
                _swipeOffset = shouldOpen ? _swipeActionWidth : 0;
              });
            }
          : null,
      onHorizontalDragCancel: canEdit
          ? () => setState(() {
              _dragging = false;
              _swipeOffset = _swipeOffset >= _swipeOpenThreshold
                  ? _swipeActionWidth
                  : 0;
            })
          : null,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          if (_swipeActive)
            Positioned.fill(
              child: RepaintBoundary(
                child: _TodoInlineSwipeActions(
                  margin: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spaceMd,
                    vertical: DesignTokens.spaceSm,
                  ),
                  onToggleCompletion: () => _toggleCompletion(context),
                  onDelete: () => _confirmDelete(context, provider),
                  completed: todo.isCompleted,
                ),
              ),
            ),
          AnimatedContainer(
            duration: _dragging
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(-_swipeOffset, 0, 0),
            child: RepaintBoundary(child: content),
          ),
        ],
      ),
    );
  }
}

class _TodoInlineSwipeActions extends StatelessWidget {
  final EdgeInsetsGeometry margin;
  final VoidCallback onToggleCompletion;
  final VoidCallback onDelete;
  final bool completed;

  const _TodoInlineSwipeActions({
    required this.margin,
    required this.onToggleCompletion,
    required this.onDelete,
    required this.completed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.74),
        borderRadius: DesignTokens.borderRadiusMd,
      ),
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: _TodoTileState._swipeActionWidth,
        height: double.infinity,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _TodoInlineSwipeButton(
              key: ValueKey(
                completed
                    ? 'todo_swipe_reopen_button'
                    : 'todo_swipe_complete_button',
              ),
              icon: completed
                  ? Icons.undo_outlined
                  : Icons.check_circle_outline,
              label: completed ? '恢复' : '完成',
              background:
                  (completed ? cs.tertiaryContainer : cs.secondaryContainer)
                      .withValues(alpha: 0.60),
              foreground: completed ? cs.tertiary : cs.secondary,
              onTap: onToggleCompletion,
            ),
            const SizedBox(width: 6),
            _TodoInlineSwipeButton(
              key: const ValueKey('todo_swipe_delete_button'),
              icon: Icons.delete_outline,
              label: '删除',
              background: cs.errorContainer.withValues(alpha: 0.64),
              foreground: cs.error,
              onTap: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoInlineSwipeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _TodoInlineSwipeButton({
    super.key,
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 40,
              child: Icon(icon, color: foreground, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _toggleTodoCompletionFromSwipe(
  BuildContext context,
  TodoItem todo,
) async {
  if (todo.isCompleted) {
    final count = await context.read<TodoProvider>().reopenTodos([todo.id]);
    if (!context.mounted || count == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已恢复：${todo.title}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  await completeTodoWithOptionalTimeRecord(context, todo);
}

/// 标题 + 优先级色点。
class _TitleRow extends StatelessWidget {
  final TodoItem todo;
  final TodoVisualState visual;
  const _TitleRow({required this.todo, required this.visual});

  @override
  Widget build(BuildContext context) {
    final isCompleted = visual == TodoVisualState.completed;
    final baseColor = Theme.of(context).colorScheme.onSurface;
    final titleColor = isCompleted
        ? baseColor.withValues(alpha: DesignTokens.completedTextOpacity)
        : null;

    return Row(
      children: [
        if (todo.priority != TodoPriority.none) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: priorityColor(todo.priority),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: DesignTokens.spaceXs),
        ],
        Expanded(
          child: Text(
            todo.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: DesignTokens.fontSizeBase,
              color: titleColor,
              decoration: isCompleted ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// 元信息行：优先级胶囊、重复、过期、子任务、标签、目标时长、下次提醒、截止日。
class _MetaRow extends StatelessWidget {
  final TodoItem todo;
  final Color quadrantColor;
  final TodoVisualState visual;

  const _MetaRow({
    required this.todo,
    required this.quadrantColor,
    required this.visual,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    final shareProvider = context.watch<ShareProvider>();

    if (todo.priority != TodoPriority.none) {
      final c = priorityColor(todo.priority);
      chips.add(
        _MetaPill(
          color: c,
          child: Text(
            todo.priority.label,
            style: TextStyle(
              fontSize: DesignTokens.fontSizeXs,
              color: c,
              fontWeight: DesignTokens.fontWeightStrong,
            ),
          ),
        ),
      );
    }

    if (todo.recurrence.isActive) {
      chips.add(Icon(Icons.repeat, size: 12, color: Colors.grey.shade500));
    }

    // 已完成：绿色 "已完成" 徽章。
    if (visual == TodoVisualState.completed) {
      final c = CompletionVisibilityPolicy.colorFor(TodoVisualState.completed);
      chips.add(
        _MetaPill(
          color: c,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 11, color: c),
              const SizedBox(width: 2),
              Text(
                '已完成',
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  color: c,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 临期：橙色 "临期" 胶囊 + 闪烁 alarm icon。
    if (visual == TodoVisualState.dueSoon) {
      final c = CompletionVisibilityPolicy.colorFor(TodoVisualState.dueSoon);
      chips.add(
        _MetaPill(
          color: c,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BlinkingIcon(icon: Icons.alarm, color: c, size: 11),
              const SizedBox(width: 2),
              Text(
                '临期',
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  color: c,
                  fontWeight: DesignTokens.fontWeightStrong,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 已过期：红色 "过期" 胶囊。沿用已有视觉语义，统一 token 色。
    if (visual == TodoVisualState.overdue) {
      final c = CompletionVisibilityPolicy.colorFor(TodoVisualState.overdue);
      chips.add(
        _MetaPill(
          color: c,
          child: Text(
            '过期',
            style: TextStyle(
              fontSize: DesignTokens.fontSizeXs,
              color: c,
              fontWeight: DesignTokens.fontWeightStrong,
            ),
          ),
        ),
      );
    }

    if (todo.subtasks.isNotEmpty) {
      chips.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 12,
              color: Colors.grey.shade500,
            ),
            const SizedBox(width: 2),
            Text(
              '${todo.subtasks.where((s) => s.isCompleted).length}/${todo.subtasks.length}',
              style: TextStyle(
                fontSize: DesignTokens.fontSizeSm,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }

    // 标签：最多展示前 3 个，多出部分以 "+N" 汇总。
    if (todo.tags.isNotEmpty) {
      const maxShown = 3;
      final shown = todo.tags.take(maxShown).toList();
      for (final t in shown) {
        chips.add(
          _MetaPill(
            color: Theme.of(context).colorScheme.primary,
            child: Text(
              '#$t',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        );
      }
      final overflow = todo.tags.length - shown.length;
      if (overflow > 0) {
        chips.add(
          _MetaPill(
            color: Colors.grey.shade600,
            child: Text(
              '+$overflow',
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        );
      }
    }

    // 目标时长
    final tSec = todo.timeTargetSeconds;
    if (tSec != null && tSec > 0) {
      chips.add(
        _MetaPill(
          color: Colors.teal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_bottom, size: 11, color: Colors.teal),
              const SizedBox(width: 2),
              Text(
                '目标 ${tSec ~/ 60}m',
                style: const TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  color: Colors.teal,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 下一次提醒。临期状态下把 alarm icon 也闪烁一下，强化提示。
    final r = todo.reminder;
    if (r.enabled && r.hour != null && r.minute != null) {
      final reminderTime = I18nDateFormat.timeOfDay(
        hour: r.hour!,
        minute: r.minute!,
      );
      final icon = r.kind == ReminderKind.alarm
          ? Icons.alarm
          : r.kind == ReminderKind.popup
          ? Icons.open_in_new
          : Icons.notifications;
      final reminderColor = visual == TodoVisualState.dueSoon
          ? CompletionVisibilityPolicy.colorFor(TodoVisualState.dueSoon)
          : Colors.indigo;
      final iconWidget = visual == TodoVisualState.dueSoon
          ? _BlinkingIcon(icon: icon, color: reminderColor, size: 11)
          : Icon(icon, size: 11, color: reminderColor);
      chips.add(
        _MetaPill(
          color: reminderColor,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconWidget,
              const SizedBox(width: 2),
              Text(
                '下次 $reminderTime',
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  color: reminderColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (todo.dueDate != null) {
      chips.add(
        _MetaPill(
          color: quadrantColor,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today, size: 10, color: quadrantColor),
              const SizedBox(width: 4),
              Text(
                I18nDateFormat.monthDay(todo.dueDate!),
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  color: quadrantColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (todo.workspaceId != 'private') {
      chips.add(
        _MetaPill(
          color: Theme.of(context).colorScheme.primary,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.groups_2_outlined,
                size: 11,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 2),
              Text(
                '共享',
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeXs,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final assigneeName = _assigneeName(shareProvider, todo);
    if (assigneeName != null) {
      chips.add(
        _MetaPill(
          color: Colors.deepPurple,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.assignment_ind_outlined,
                size: 11,
                color: Colors.deepPurple,
              ),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  '@$assigneeName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: DesignTokens.fontSizeXs,
                    color: Colors.deepPurple,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: DesignTokens.spaceXs,
      runSpacing: DesignTokens.spaceXxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: chips,
    );
  }

  String? _assigneeName(ShareProvider provider, TodoItem todo) {
    final assigneeId = todo.assigneeId;
    if (assigneeId == null || assigneeId.isEmpty) return null;
    for (final workspace in provider.workspaces) {
      if (workspace.id != todo.workspaceId) continue;
      for (final member in workspace.members) {
        if (member.userId == assigneeId) {
          return member.username.isEmpty ? member.userId : member.username;
        }
      }
    }
    return assigneeId;
  }
}

class _BlinkingIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _BlinkingIcon({
    required this.icon,
    required this.color,
    this.size = 12,
  });

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: size, color: color.withValues(alpha: 0.92));
}

/// 统一的元信息胶囊（带 12% 底色）。
class _MetaPill extends StatelessWidget {
  final Color color;
  final Widget child;

  const _MetaPill({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceXs,
          vertical: 1,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: DesignTokens.borderRadiusSm,
        ),
        child: child,
      ),
    );
  }
}

class QuadrantListScreen extends StatefulWidget {
  final EisenhowerQuadrant quadrant;
  final TodoFilterState<EisenhowerQuadrant, TodoPriority>? filter;

  /// 右下角新建入口（由主屏传入，如 _showAddDialog）；null 时无 FAB。
  /// 触发时携带本页象限，新建待办默认落入该象限。
  final ValueChanged<EisenhowerQuadrant>? onCreateTodo;

  const QuadrantListScreen({
    super.key,
    required this.quadrant,
    this.filter,
    this.onCreateTodo,
  });

  @override
  State<QuadrantListScreen> createState() => _QuadrantListScreenState();
}

class _QuadrantListScreenState extends State<QuadrantListScreen> {
  int _swipeDismissSerial = 0;
  bool _batchMode = false;
  bool _batchSubmitting = false;
  final Set<String> _selectedTodoIds = <String>{};

  void _enterBatchMode(String todoId) {
    setState(() {
      _batchMode = true;
      _selectedTodoIds.add(todoId);
    });
  }

  void _exitBatchMode() {
    setState(() {
      _batchMode = false;
      _selectedTodoIds.clear();
    });
  }

  void _toggleSelection(String todoId) {
    setState(() {
      if (!_selectedTodoIds.add(todoId)) {
        _selectedTodoIds.remove(todoId);
      }
    });
  }

  Future<void> _runBatchAction(
    Future<int> Function(Set<String> ids) action,
    String Function(int count) message,
  ) async {
    if (_batchSubmitting) return;
    final ids = Set<String>.from(_selectedTodoIds);
    if (ids.isEmpty) return;
    setState(() => _batchSubmitting = true);
    try {
      final count = await action(ids);
      if (!mounted) return;
      _exitBatchMode();
      _showBatchSnack(message(count));
    } finally {
      if (mounted) {
        setState(() => _batchSubmitting = false);
      }
    }
  }

  void _showBatchSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _completeSelected() async {
    var skipped = 0;
    await _runBatchAction(
      (ids) async {
        final provider = context.read<TodoProvider>();
        final count = await provider.completeTodos(ids);
        skipped = provider.lastSkippedBySubtasks;
        return count;
      },
      (count) =>
          skipped > 0 ? '已完成 $count 个任务，$skipped 个需先完成子任务' : '已完成 $count 个任务',
    );
  }

  Future<void> _reopenSelected() async {
    var skipped = 0;
    await _runBatchAction(
      (ids) async {
        final provider = context.read<TodoProvider>();
        final count = await provider.reopenTodos(ids);
        skipped = provider.lastSkippedBySubtasks;
        return count;
      },
      (count) => skipped > 0
          ? '已恢复 $count 个任务为未完成，$skipped 个有子任务需在子任务里取消'
          : '已恢复 $count 个任务为未完成',
    );
  }

  Future<void> _moveSelected(EisenhowerQuadrant quadrant) async {
    await _runBatchAction(
      (ids) => context.read<TodoProvider>().updateTodosQuadrant(ids, quadrant),
      (count) => '已移动 $count 个任务到${_title(quadrant)}',
    );
  }

  Future<void> _setSelectedPriority(TodoPriority priority) async {
    await _runBatchAction(
      (ids) => context.read<TodoProvider>().updateTodosPriority(ids, priority),
      (count) => '已更新 $count 个任务优先级',
    );
  }

  Future<void> _deleteSelected() async {
    if (_batchSubmitting) return;
    final selectedCount = _selectedTodoIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AppDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('删除所选任务'),
        content: Text('确认删除 $selectedCount 个任务吗？相关时间足迹也会同步移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _runBatchAction(
      (ids) => context.read<TodoProvider>().deleteTodos(ids),
      (count) => '已删除 $count 个任务',
    );
  }

  bool _dismissSwipeActionsOnScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      setState(() => _swipeDismissSerial++);
    }
    return false;
  }

  String _title(EisenhowerQuadrant q) {
    switch (q) {
      case EisenhowerQuadrant.urgentImportant:
        return '重要且紧急';
      case EisenhowerQuadrant.notUrgentImportant:
        return '重要不紧急';
      case EisenhowerQuadrant.urgentNotImportant:
        return '紧急不重要';
      case EisenhowerQuadrant.notUrgentNotImportant:
        return '不重要不紧急';
    }
  }

  @override
  Widget build(BuildContext context) {
    final quadrant = widget.quadrant;
    final baseTodos = context.watch<TodoProvider>().visibleListTodos;
    final effectiveFilter =
        widget.filter?.copyWith(quadrant: quadrant) ??
        TodoFilterState<EisenhowerQuadrant, TodoPriority>(quadrant: quadrant);
    final todos = filterTodos(
      baseTodos,
      effectiveFilter,
      now: AppClock.now(),
      quadrantOf: (todo) => todo.quadrant,
      priorityOf: (todo) => todo.priority,
      tagsOf: (todo) => todo.tags,
      listGroupNameOf: (todo) => todo.listGroupName,
      dueDateOf: (todo) => todo.dueDate,
      isCompletedOf: (todo) => todo.isCompleted,
      isArchivedAfterRolloverOf: (todo) => todo.isArchivedAfterRollover,
    );

    return Scaffold(
      appBar: AppBar(
        leading: _batchMode
            ? IconButton(
                tooltip: '退出批量操作',
                onPressed: _exitBatchMode,
                icon: const Icon(Icons.close),
              )
            : null,
        title: Text(
          _batchMode ? '已选择 ${_selectedTodoIds.length} 项' : _title(quadrant),
        ),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        actions: [
          if (!_batchMode)
            IconButton(
              tooltip: '批量管理',
              icon: const Icon(Icons.checklist_rounded),
              onPressed: todos.isEmpty
                  ? null
                  : () => setState(() => _batchMode = true),
            ),
        ],
      ),
      body: todos.isEmpty
          ? const EmptyState(icon: Icons.inbox, message: '这个象限没有任务')
          : NotificationListener<ScrollNotification>(
              onNotification: _dismissSwipeActionsOnScroll,
              child: ListView.builder(
                // ignore: deprecated_member_use
                cacheExtent: 640,
                itemCount: todos.length,
                itemBuilder: (context, index) {
                  final todo = todos[index];
                  return _TodoTile(
                    todo: todo,
                    batchMode: _batchMode,
                    selected: _selectedTodoIds.contains(todo.id),
                    onToggleSelection: _toggleSelection,
                    onEnterBatchMode: _enterBatchMode,
                    swipeDismissSerial: _swipeDismissSerial,
                  );
                },
              ),
            ),
      bottomNavigationBar: _batchMode
          ? _TodoBatchActionBar(
              selectedCount: _selectedTodoIds.length,
              submitting: _batchSubmitting,
              onComplete: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _completeSelected,
              onReopen: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _reopenSelected,
              onMove: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _moveSelected,
              onPriority: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _setSelectedPriority,
              onDelete: _selectedTodoIds.isEmpty || _batchSubmitting
                  ? null
                  : _deleteSelected,
            )
          : null,
      floatingActionButton: _batchMode || widget.onCreateTodo == null
          ? null
          : FloatingActionButton(
              // 在本象限新建：把当前象限带回主屏的新建入口。
              onPressed: () => widget.onCreateTodo!(widget.quadrant),
              child: const Icon(Icons.add),
            ),
    );
  }
}
