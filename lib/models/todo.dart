import 'package:uuid/uuid.dart';
import '../core/app_clock.dart';
import '../core/todo_filters.dart';
import '../core/i18n.dart';
import '../core/todo_kanban.dart';
import 'goal.dart' show FocusLink, ReminderConfig, ReminderKind, ReminderPlan;
import 'note.dart' show NoteAttachment;
import 'recurrence.dart';

const uuid = Uuid();
const Object _copyWithUnset = Object();

enum EisenhowerQuadrant {
  urgentImportant, // Q1 - red: Do First
  notUrgentImportant, // Q2 - purple: Schedule
  urgentNotImportant, // Q3 - yellow: Delegate
  notUrgentNotImportant, // Q4 - green: Eliminate
}

/// 优先级(独立于四象限，可组合使用)。
enum TodoPriority { none, low, medium, high, urgent }

extension TodoPriorityX on TodoPriority {
  String get label => switch (this) {
    TodoPriority.none => I18n.tr('todo.priority.none'),
    TodoPriority.low => I18n.tr('todo.priority.low'),
    TodoPriority.medium => I18n.tr('todo.priority.medium'),
    TodoPriority.high => I18n.tr('todo.priority.high'),
    TodoPriority.urgent => I18n.tr('todo.priority.urgent'),
  };

  int get rank => switch (this) {
    TodoPriority.none => 0,
    TodoPriority.low => 1,
    TodoPriority.medium => 2,
    TodoPriority.high => 3,
    TodoPriority.urgent => 4,
  };
}

class Subtask {
  String id;
  String title;
  bool isCompleted;
  int sortOrder;

  Subtask({
    String? id,
    required this.title,
    this.isCompleted = false,
    this.sortOrder = 0,
  }) : id = id ?? uuid.v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'isCompleted': isCompleted,
    'sortOrder': sortOrder,
  };

  factory Subtask.fromJson(Map<String, dynamic> json) => Subtask(
    id: json['id'],
    title: json['title'],
    isCompleted: json['isCompleted'] ?? false,
    sortOrder: json['sortOrder'] ?? 0,
  );
}

/// 任务顺延记录：记录一次 `dueDate` 被改动的"从 → 到"以及触发原因。
///
/// - `reason = "manual"`：用户在详情页手动调整截止日。
/// - `reason = "auto_daily_rollover"`：由 `DailyRollover` 把过期任务顺延到今日。
class PostponeRecord {
  final DateTime from;
  final DateTime to;
  final String reason;
  final DateTime at;

  const PostponeRecord({
    required this.from,
    required this.to,
    required this.reason,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
    'from': from.toIso8601String(),
    'to': to.toIso8601String(),
    'reason': reason,
    'at': at.toIso8601String(),
  };

  factory PostponeRecord.fromJson(Map<String, dynamic> json) => PostponeRecord(
    from: DateTime.parse(json['from']),
    to: DateTime.parse(json['to']),
    reason: json['reason'] ?? 'manual',
    at: DateTime.parse(json['at']),
  );
}

class TodoItem {
  final String id;
  String title;
  String notes;
  bool isCompleted;
  EisenhowerQuadrant quadrant;
  TodoPriority priority;
  String kanbanColumnId;
  String? listGroupId;
  String? listGroupName;
  String workspaceId;
  String? createdBy;
  String? updatedBy;
  String? assigneeId;
  List<String> tags;
  List<NoteAttachment> attachments;
  DateTime? dueDate;
  DateTime date;

  /// 旧版"是否启用提醒"开关，Task 7 UI 改造前保留以维持向后兼容。
  /// 新代码请读写 [reminder]。
  @Deprecated('Use reminder instead; kept for backward compatibility')
  bool hasReminder;

  /// 旧版提醒触发时间（含日期与时间）。Task 7 UI 改造前保留。
  /// 新代码请读写 [reminder]。
  @Deprecated('Use reminder instead; kept for backward compatibility')
  DateTime? reminderAt;

  /// 新版提醒配置（push / alarm + hour/minute）。
  /// 当 [hasReminder] 为 true 时优先以此为准。
  ReminderConfig reminder;

  /// 新版多提醒计划；当前仍以 legacy reminder 为主，后续 UI 会切到此字段。
  ReminderPlan reminderPlan;

  /// 专注模式联动（番茄钟预设、专注时长、白噪音）。
  FocusLink focusLink;

  /// 目标时长（秒）。用于"本任务我想专注多久"。
  int? timeTargetSeconds;

  /// 顺延历史：每次 dueDate 被改动都追加一条记录。
  List<PostponeRecord> postponeHistory;

  List<Subtask> subtasks;

  /// 子任务是否驱动父任务完成态（P6/P7 不变式）。
  ///
  /// 默认 `true`：
  /// - 当全部子任务完成时，父任务自动置为 `isCompleted = true` 且 `completedAt = now`；
  /// - 当在父任务已完成的状态下取消任一子任务，父任务自动置为未完成。
  ///
  /// 置为 `false` 表示父任务完成态与子任务解耦，由用户手动维护。
  bool autoToggleByChildren;
  int sortOrder;
  RecurrenceRule recurrence;
  DateTime? completedAt;

  /// 是否在"次日 00:00 归档"阶段被归档（P5）。
  ///
  /// 被归档的任务在"今日"视图中不可见，但仍保留在本地数据中用于历史统计。
  /// 由 `DailyRollover` 在跨日时对"昨日已完成"的任务置为 `true`，
  /// 对应可视状态 `TodoVisualState.archived`。
  bool isArchivedAfterRollover;
  DateTime createdAt;
  DateTime updatedAt;

  TodoItem({
    String? id,
    required this.title,
    this.notes = '',
    this.isCompleted = false,
    this.quadrant = EisenhowerQuadrant.notUrgentImportant,
    this.priority = TodoPriority.none,
    String? kanbanColumnId,
    this.listGroupId,
    this.listGroupName,
    this.workspaceId = 'private',
    this.createdBy,
    this.updatedBy,
    this.assigneeId,
    List<String>? tags,
    List<NoteAttachment>? attachments,
    this.dueDate,
    DateTime? date,
    bool hasReminder = false,
    this.reminderAt,
    ReminderConfig? reminder,
    ReminderPlan? reminderPlan,
    FocusLink? focusLink,
    this.timeTargetSeconds,
    List<PostponeRecord>? postponeHistory,
    List<Subtask>? subtasks,
    this.autoToggleByChildren = true,
    this.sortOrder = 0,
    RecurrenceRule? recurrence,
    this.completedAt,
    this.isArchivedAfterRollover = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? uuid.v4(),
       date = date ?? AppClock.now(),
       kanbanColumnId =
           kanbanColumnId ??
           (isCompleted
               ? defaultKanbanDoneColumnId
               : defaultKanbanPendingColumnId),
       tags = tags ?? [],
       reminder =
           reminder ??
           reminderPlan?.toLegacyReminderConfig() ??
           const ReminderConfig.disabled(),
       reminderPlan =
           reminderPlan ??
           ReminderPlan.fromLegacy(reminder ?? const ReminderConfig.disabled()),
       hasReminder =
           hasReminder ||
           (reminder?.enabled ?? false) ||
           (reminderPlan?.enabled ?? false),
       attachments = attachments ?? [],
       focusLink = focusLink ?? const FocusLink.disabled(),
       postponeHistory = postponeHistory ?? [],
       subtasks = subtasks ?? [],
       recurrence = recurrence ?? const RecurrenceRule(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'notes': notes,
    'isCompleted': isCompleted,
    'quadrant': quadrant.index,
    'priority': priority.index,
    'kanbanColumnId': kanbanColumnId,
    'listGroupId': listGroupId,
    'listGroupName': listGroupName,
    'workspaceId': workspaceId,
    'createdBy': createdBy,
    'updatedBy': updatedBy,
    'assigneeId': assigneeId,
    'tags': tags,
    'attachments': attachments.map((a) => a.toJson()).toList(),
    'dueDate': dueDate == null ? null : serializeTodoDueDate(dueDate!),
    'date': date.toIso8601String(),
    // 旧字段保留，方便旧代码与降级读取。
    'hasReminder': hasReminder,
    'reminderAt': reminderAt?.toUtc().toIso8601String(),
    // 新字段。
    'reminder': reminderPlan
        .toLegacyReminderConfig(fallback: reminder)
        .toJson(),
    'reminderPlan': reminderPlan.toJson(),
    'focusLink': focusLink.toJson(),
    'timeTargetSeconds': timeTargetSeconds,
    'postponeHistory': postponeHistory.map((p) => p.toJson()).toList(),
    'subtasks': subtasks.map((s) => s.toJson()).toList(),
    'autoToggleByChildren': autoToggleByChildren,
    'sortOrder': sortOrder,
    'recurrence': recurrence.toJson(),
    'completedAt': completedAt?.toIso8601String(),
    'isArchivedAfterRollover': isArchivedAfterRollover,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    // --- 提醒字段迁移：优先新 reminder，缺失则从旧 hasReminder / reminderAt 合成。
    final legacyHasReminder = json['hasReminder'] == true;
    final legacyReminderAt = json['reminderAt'] != null
        ? DateTime.tryParse(json['reminderAt'].toString())
        : null;

    final reminderJson = json['reminder'];
    ReminderConfig reminder;
    if (reminderJson is Map<String, dynamic>) {
      reminder = ReminderConfig.fromJson(reminderJson);
    } else if (legacyHasReminder) {
      reminder = ReminderConfig(
        enabled: true,
        kind: ReminderKind.push,
        hour: legacyReminderAt?.hour,
        minute: legacyReminderAt?.minute,
      );
    } else {
      reminder = const ReminderConfig.disabled();
    }
    final reminderPlanJson = json['reminderPlan'];
    var reminderPlan = reminderPlanJson is Map
        ? ReminderPlan.fromJson(Map<String, dynamic>.from(reminderPlanJson))
        : ReminderPlan.fromLegacy(reminder);
    // Some migrated/cloud-synced payloads can contain a disabled new
    // reminderPlan with retained rules while the legacy reminder is still the
    // only enabled source. Prefer the enabled legacy reminder in that conflict
    // instead of silently dropping the system notification registration.
    if (!reminderPlan.enabled && reminder.enabled) {
      reminderPlan = ReminderPlan.fromLegacy(reminder);
    }
    final effectiveReminder = reminderPlan.toLegacyReminderConfig(
      fallback: reminder,
    );

    // 兜底：hasReminder 与 reminder.enabled 同步，让旧代码读 hasReminder 也正确。
    final effectiveHasReminder = legacyHasReminder || effectiveReminder.enabled;

    return TodoItem(
      id: json['id'],
      title: json['title'],
      notes: json['notes'] ?? '',
      isCompleted: json['isCompleted'] ?? false,
      quadrant: EisenhowerQuadrant.values[json['quadrant'] ?? 1],
      priority: TodoPriority.values[json['priority'] ?? 0],
      kanbanColumnId: (json['kanbanColumnId'] ?? _legacyKanbanColumnId(json))
          .toString(),
      listGroupId: json['listGroupId'],
      listGroupName: json['listGroupName'],
      workspaceId: json['workspaceId']?.toString() ?? 'private',
      createdBy: json['createdBy']?.toString(),
      updatedBy: json['updatedBy']?.toString(),
      assigneeId: json['assigneeId']?.toString(),
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      attachments:
          (json['attachments'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((e) => NoteAttachment.fromJson(Map<String, dynamic>.from(e)))
              .where((a) => a.uri.isNotEmpty)
              .toList() ??
          [],
      dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate']) : null,
      date: DateTime.parse(json['date']),
      hasReminder: effectiveHasReminder,
      reminderAt: legacyReminderAt,
      reminder: effectiveReminder,
      reminderPlan: reminderPlan,
      focusLink: FocusLink.fromJson(json['focusLink'] as Map<String, dynamic>?),
      timeTargetSeconds: (json['timeTargetSeconds'] as num?)?.toInt(),
      postponeHistory:
          (json['postponeHistory'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(PostponeRecord.fromJson)
              .toList() ??
          [],
      subtasks:
          (json['subtasks'] as List<dynamic>?)
              ?.map((s) => Subtask.fromJson(s))
              .toList() ??
          [],
      autoToggleByChildren: json['autoToggleByChildren'] ?? true,
      sortOrder: json['sortOrder'] ?? 0,
      recurrence: RecurrenceRule.fromJson(
        json['recurrence'] as Map<String, dynamic>?,
      ),
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'])
          : null,
      isArchivedAfterRollover: json['isArchivedAfterRollover'] ?? false,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }

  TodoItem copyWith({
    String? title,
    String? notes,
    bool? isCompleted,
    EisenhowerQuadrant? quadrant,
    TodoPriority? priority,
    String? kanbanColumnId,
    Object? listGroupId = _copyWithUnset,
    Object? listGroupName = _copyWithUnset,
    String? workspaceId,
    Object? createdBy = _copyWithUnset,
    Object? updatedBy = _copyWithUnset,
    Object? assigneeId = _copyWithUnset,
    List<String>? tags,
    List<NoteAttachment>? attachments,
    Object? dueDate = _copyWithUnset,
    DateTime? date,
    bool? hasReminder,
    Object? reminderAt = _copyWithUnset,
    ReminderConfig? reminder,
    ReminderPlan? reminderPlan,
    FocusLink? focusLink,
    Object? timeTargetSeconds = _copyWithUnset,
    List<PostponeRecord>? postponeHistory,
    List<Subtask>? subtasks,
    bool? autoToggleByChildren,
    int? sortOrder,
    RecurrenceRule? recurrence,
    Object? completedAt = _copyWithUnset,
    bool? isArchivedAfterRollover,
  }) => TodoItem(
    id: id,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    isCompleted: isCompleted ?? this.isCompleted,
    quadrant: quadrant ?? this.quadrant,
    priority: priority ?? this.priority,
    kanbanColumnId: kanbanColumnId ?? this.kanbanColumnId,
    listGroupId: identical(listGroupId, _copyWithUnset)
        ? this.listGroupId
        : listGroupId as String?,
    listGroupName: identical(listGroupName, _copyWithUnset)
        ? this.listGroupName
        : listGroupName as String?,
    workspaceId: workspaceId ?? this.workspaceId,
    createdBy: identical(createdBy, _copyWithUnset)
        ? this.createdBy
        : createdBy as String?,
    updatedBy: identical(updatedBy, _copyWithUnset)
        ? this.updatedBy
        : updatedBy as String?,
    assigneeId: identical(assigneeId, _copyWithUnset)
        ? this.assigneeId
        : assigneeId as String?,
    tags: tags ?? this.tags,
    attachments: attachments ?? this.attachments,
    dueDate: identical(dueDate, _copyWithUnset)
        ? this.dueDate
        : dueDate as DateTime?,
    date: date ?? this.date,
    hasReminder: hasReminder ?? this.hasReminder,
    reminderAt: identical(reminderAt, _copyWithUnset)
        ? this.reminderAt
        : reminderAt as DateTime?,
    reminder: reminder ?? this.reminder,
    reminderPlan:
        reminderPlan ??
        (reminder != null
            ? ReminderPlan.fromLegacy(reminder)
            : this.reminderPlan),
    focusLink: focusLink ?? this.focusLink,
    timeTargetSeconds: identical(timeTargetSeconds, _copyWithUnset)
        ? this.timeTargetSeconds
        : timeTargetSeconds as int?,
    postponeHistory: postponeHistory ?? this.postponeHistory,
    subtasks: subtasks ?? this.subtasks,
    autoToggleByChildren: autoToggleByChildren ?? this.autoToggleByChildren,
    sortOrder: sortOrder ?? this.sortOrder,
    recurrence: recurrence ?? this.recurrence,
    completedAt: identical(completedAt, _copyWithUnset)
        ? this.completedAt
        : completedAt as DateTime?,
    isArchivedAfterRollover:
        isArchivedAfterRollover ?? this.isArchivedAfterRollover,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  double get subtaskProgress => subtasks.isEmpty
      ? 0.0
      : subtasks.where((s) => s.isCompleted).length / subtasks.length;

  DateTime? get localDueDate =>
      dueDate == null ? null : todoDateInAppZone(dueDate!);

  DateTime? get dueAt => dueDate == null ? null : todoDueAt(dueDate!);

  bool get isOverdue =>
      !isCompleted && dueAt != null && dueAt!.isBefore(AppClock.now());
}

String _legacyKanbanColumnId(Map<String, dynamic> json) {
  return json['isCompleted'] == true
      ? defaultKanbanDoneColumnId
      : defaultKanbanPendingColumnId;
}
