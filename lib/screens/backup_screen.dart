import 'package:flutter/material.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:provider/provider.dart';
import '../providers/anniversary_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/countdown_provider.dart';
import '../providers/course_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/location_reminder_provider.dart';
import '../providers/note_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/quick_capture_template_provider.dart';
import '../providers/todo_provider.dart';
import '../providers/user_provider.dart';
import '../providers/time_audit_provider.dart';
import '../providers/achievement_provider.dart';
import '../providers/share_provider.dart';
import '../services/backup_service.dart';
import '../services/competitor_task_importer.dart';
import '../services/ics_exporter.dart';
import '../services/reminder_ringtone_settings.dart';
import '../services/webdav_backup_service.dart';
import '../widgets/surface_components.dart';

enum BackupEntryMode { backup, restore }

enum _CompetitorImportSource { zhijianTime, ticktick, todoist, generic }

class _CompetitorImportDraft {
  final String raw;
  final _CompetitorImportSource source;
  final CompetitorFieldMapping fieldMapping;

  const _CompetitorImportDraft({
    required this.raw,
    required this.source,
    this.fieldMapping = const CompetitorFieldMapping(),
  });
}

class _CompetitorImportConfig {
  final _CompetitorImportSource source;
  final CompetitorFieldMapping fieldMapping;

  const _CompetitorImportConfig({
    required this.source,
    this.fieldMapping = const CompetitorFieldMapping(),
  });
}

const _competitorFieldMappingTargets = <(String, String)>[
  ('title', '标题/名称'),
  ('date', '日期/开始日期'),
  ('due', '截止时间/结束时间'),
  ('list', '清单/项目'),
  ('tags', '标签'),
  ('priority', '优先级'),
  ('quadrant', '四象限'),
  ('completed', '完成状态'),
  ('completedAt', '完成时间'),
  ('reminder', '提醒时间'),
  ('repeat', '重复规则'),
  ('notes', '备注/描述'),
  ('type', '模块类型'),
  ('target', '习惯目标次数'),
  ('unit', '习惯单位'),
  ('category', '分类/分组'),
  ('duration', '时间足迹时长'),
];

class _CompetitorImportApplySummary {
  final int todoInserted;
  final int habitInserted;
  final int noteInserted;
  final int eventInserted;
  final int anniversaryInserted;
  final int countdownInserted;
  final int timeEntryInserted;
  final int skippedRows;
  final int skippedDuplicates;

  const _CompetitorImportApplySummary({
    required this.todoInserted,
    required this.habitInserted,
    required this.noteInserted,
    required this.eventInserted,
    required this.anniversaryInserted,
    required this.countdownInserted,
    required this.timeEntryInserted,
    required this.skippedRows,
    required this.skippedDuplicates,
  });

  int get inserted =>
      todoInserted +
      habitInserted +
      noteInserted +
      eventInserted +
      anniversaryInserted +
      countdownInserted +
      timeEntryInserted;

  int get skipped => skippedRows + skippedDuplicates;
}

class BackupScreen extends StatefulWidget {
  final BackupEntryMode initialMode;

  const BackupScreen({super.key, this.initialMode = BackupEntryMode.backup});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  String? _exported;
  String? _exportedTitle;
  bool _busy = false;
  WebDavBackupConfig _webDavConfig = WebDavBackupConfig.empty();

  @override
  void initState() {
    super.initState();
    _loadWebDavConfig();
  }

  Future<void> _loadWebDavConfig() async {
    final config = await WebDavBackupService.loadConfig();
    if (!mounted) return;
    setState(() => _webDavConfig = config);
  }

  Future<void> _exportAll() async {
    setState(() => _busy = true);
    try {
      final text = await BackupService.exportAll();
      if (!mounted) return;
      setState(() {
        _exported = text;
        _exportedTitle = '全量备份 (JSON)';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
    }
  }

  void _showExport(String title, String text) {
    setState(() {
      _exportedTitle = title;
      _exported = text;
    });
  }

  Future<void> _copy() async {
    if (_exported == null) return;
    await Clipboard.setData(ClipboardData(text: _exported!));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
  }

  Future<void> _import({bool merge = false}) async {
    final ctrl = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text(merge ? '合并导入' : '覆盖导入'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              maxLines: 10,
              decoration: const InputDecoration(hintText: '把之前导出的备份 JSON 粘贴进来'),
            ),
            // 覆盖=真删数据：备份中不存在的本机数据会被删除，必须写明后果，
            // 避免用户用旧备份覆盖后误以为"还原失败"。
            if (!merge) ...[
              const SizedBox(height: 8),
              Text(
                I18n.tr('backup.overwrite.will_delete_missing'),
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('确认导入'),
          ),
        ],
      ),
    );
    if (raw == null || raw.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      final count = await BackupService.importAll(
        raw,
        merge: merge,
        // 覆盖=还原到备份快照：备份中不存在的本机数据一并删除，弹窗已警告。
        // 服务层 `clearMissing && !merge` 守卫保证 merge 合并入口不受影响。
        clearMissing: true,
      );
      if (!mounted) return;
      await _reloadAll();
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功${merge ? '合并' : '导入'} $count 项数据')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  Future<String?> _pickImportTextFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Backup or CSV',
          extensions: ['json', 'csv', 'txt'],
          mimeTypes: ['application/json', 'text/csv', 'text/plain'],
        ),
      ],
    );
    return file?.readAsString();
  }

  Future<void> _importBackupFile({required bool merge}) async {
    // 覆盖=真删数据：文件覆盖与粘贴覆盖导入 / WebDAV 覆盖恢复一致，
    // 必须先弹窗写明删除后果，防止误触一次即静默删除本机数据。
    if (!merge) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AppDialog(
          title: const Text('从文件覆盖导入?'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('会选择备份文件并覆盖本机可备份数据。'),
              // 覆盖=真删数据：写明缺失数据将被删除的后果。
              const SizedBox(height: 8),
              Text(
                I18n.tr('backup.overwrite.will_delete_missing'),
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('选择文件'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      if (!mounted) return;
    }
    setState(() => _busy = true);
    try {
      final raw = await _pickImportTextFile();
      if (raw == null || raw.trim().isEmpty) {
        if (!mounted) return;
        setState(() => _busy = false);
        return;
      }
      final count = await BackupService.importAll(
        raw,
        merge: merge,
        // 覆盖=还原到备份快照：备份中不存在的本机数据一并删除，弹窗已警告。
        // 服务层 `clearMissing && !merge` 守卫保证 merge 合并入口不受影响。
        clearMissing: true,
      );
      if (!mounted) return;
      await _reloadAll();
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已从文件${merge ? '合并' : '导入'} $count 项数据')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('文件导入失败: $e')));
    }
  }

  Future<void> _importTasksFromOtherApps() async {
    final draft = await _askCompetitorImportText(
      title: '导入其他 App 待办',
      actionLabel: '预览待办',
      hintText: '粘贴 Todoist、滴答清单或指尖时光风格的 CSV / JSON 任务导出',
    );
    if (draft == null) return;
    await _previewAndImportCompetitorData(draft, tasksOnly: true);
  }

  Future<void> _importProductivityDataFromOtherApps() async {
    final draft = await _askCompetitorImportText(
      title: '导入其他 App 数据',
      actionLabel: '预览数据',
      hintText:
          '粘贴 Todoist、滴答清单或指尖时光风格 CSV / JSON；支持 type=task/habit/note/event/birthday/anniversary/countdown/time_entry',
    );
    if (draft == null) return;
    await _previewAndImportCompetitorData(draft, tasksOnly: false);
  }

  Future<void> _importProductivityDataFile() async {
    try {
      final raw = await _pickImportTextFile();
      if (raw == null || raw.trim().isEmpty) return;
      final config = await _selectCompetitorImportSource(
        title: '选择文件来源',
        actionLabel: '继续预览',
      );
      if (config == null) return;
      await _previewAndImportCompetitorData(
        _CompetitorImportDraft(
          raw: raw,
          source: config.source,
          fieldMapping: config.fieldMapping,
        ),
        tasksOnly: false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('文件迁移失败: $e')));
    }
  }

  Future<_CompetitorImportDraft?> _askCompetitorImportText({
    required String title,
    required String actionLabel,
    required String hintText,
  }) async {
    final ctrl = TextEditingController();
    var source = _CompetitorImportSource.zhijianTime;
    var fieldMapping = const CompetitorFieldMapping();
    final draft = await showDialog<_CompetitorImportDraft>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AppDialog(
          title: Text(title),
          maxWidth: 560,
          content: AppSecondaryControlTheme(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppDropdownField<_CompetitorImportSource>(
                    initialValue: source,
                    decoration: const InputDecoration(
                      labelText: '来源',
                      prefixIcon: Icon(Icons.source_outlined),
                    ),
                    items: _CompetitorImportSource.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(_competitorSourceLabel(value)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => source = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _competitorSourceHint(source),
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        ctx,
                      ).colorScheme.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final updated = await _editCompetitorFieldMapping(
                        fieldMapping,
                      );
                      if (updated == null) return;
                      setDialogState(() => fieldMapping = updated);
                    },
                    icon: const Icon(Icons.schema_outlined),
                    label: const Text('高级字段映射'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _fieldMappingSummary(fieldMapping),
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        ctx,
                      ).colorScheme.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    maxLines: 12,
                    decoration: InputDecoration(hintText: hintText),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              onPressed: () {
                final raw = ctrl.text.trim();
                if (raw.isEmpty) return;
                Navigator.pop(
                  ctx,
                  _CompetitorImportDraft(
                    raw: raw,
                    source: source,
                    fieldMapping: fieldMapping,
                  ),
                );
              },
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return draft;
  }

  Future<_CompetitorImportConfig?> _selectCompetitorImportSource({
    required String title,
    required String actionLabel,
  }) {
    var source = _CompetitorImportSource.zhijianTime;
    var fieldMapping = const CompetitorFieldMapping();
    return showDialog<_CompetitorImportConfig>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AppDialog(
          title: Text(title),
          content: AppSecondaryControlTheme(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppDropdownField<_CompetitorImportSource>(
                  initialValue: source,
                  decoration: const InputDecoration(
                    labelText: '来源',
                    prefixIcon: Icon(Icons.source_outlined),
                  ),
                  items: _CompetitorImportSource.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_competitorSourceLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() => source = value);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  _competitorSourceHint(source),
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      ctx,
                    ).colorScheme.onSurface.withValues(alpha: 0.62),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final updated = await _editCompetitorFieldMapping(
                      fieldMapping,
                    );
                    if (updated == null) return;
                    setDialogState(() => fieldMapping = updated);
                  },
                  icon: const Icon(Icons.schema_outlined),
                  label: const Text('高级字段映射'),
                ),
                const SizedBox(height: 6),
                Text(
                  _fieldMappingSummary(fieldMapping),
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      ctx,
                    ).colorScheme.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                ctx,
                _CompetitorImportConfig(
                  source: source,
                  fieldMapping: fieldMapping,
                ),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _previewAndImportCompetitorData(
    _CompetitorImportDraft draft, {
    required bool tasksOnly,
  }) async {
    final parsed = const CompetitorTaskImporter().parse(
      draft.raw,
      fieldMapping: draft.fieldMapping,
    );
    final recognized = tasksOnly ? parsed.todos.length : parsed.totalImported;
    if (recognized == 0) {
      if (!mounted) return;
      final warning = parsed.warnings.isEmpty
          ? ''
          : '：${parsed.warnings.take(2).join('；')}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('未识别到可导入${tasksOnly ? '待办' : '数据'}$warning')),
      );
      return;
    }

    final confirmed = await _confirmCompetitorImportPreview(
      draft: draft,
      parsed: parsed,
      tasksOnly: tasksOnly,
    );
    if (confirmed != true || !mounted) return;

    final todoProvider = context.read<TodoProvider>();
    final habitProvider = context.read<HabitProvider>();
    final noteProvider = context.read<NoteProvider>();
    final calendarProvider = context.read<CalendarProvider>();
    final anniversaryProvider = context.read<AnniversaryProvider>();
    final countdownProvider = context.read<CountdownProvider>();
    final timeAuditProvider = context.read<TimeAuditProvider>();
    setState(() => _busy = true);
    try {
      final rollbackSnapshot = await BackupService.exportAll();
      if (!mounted) return;
      final todoSummary = await todoProvider.importTodos(parsed.todos);
      final habitSummary = tasksOnly
          ? const HabitImportSummary(inserted: 0, skippedDuplicates: 0)
          : await habitProvider.importHabits(parsed.habits);
      final noteSummary = tasksOnly
          ? const NoteImportSummary(inserted: 0, skippedDuplicates: 0)
          : await noteProvider.importNotes(parsed.notes);
      final eventSummary = tasksOnly
          ? const CalendarEventImportSummary(inserted: 0, skippedDuplicates: 0)
          : await calendarProvider.importLocalEvents(parsed.calendarEvents);
      final anniversarySummary = tasksOnly
          ? const AnniversaryImportSummary(inserted: 0, skippedDuplicates: 0)
          : await anniversaryProvider.importAnniversaries(parsed.anniversaries);
      final countdownSummary = tasksOnly
          ? const CountdownImportSummary(inserted: 0, skippedDuplicates: 0)
          : await countdownProvider.importCountdowns(parsed.countdowns);
      final timeEntrySummary = tasksOnly
          ? const TimeEntryImportSummary(inserted: 0, skippedDuplicates: 0)
          : await timeAuditProvider.importTimeEntries(parsed.timeEntries);
      if (!mounted) return;
      setState(() => _busy = false);
      final summary = _CompetitorImportApplySummary(
        todoInserted: todoSummary.inserted,
        habitInserted: habitSummary.inserted,
        noteInserted: noteSummary.inserted,
        eventInserted: eventSummary.inserted,
        anniversaryInserted: anniversarySummary.inserted,
        countdownInserted: countdownSummary.inserted,
        timeEntryInserted: timeEntrySummary.inserted,
        skippedRows: parsed.skippedRows,
        skippedDuplicates:
            todoSummary.skippedDuplicates +
            habitSummary.skippedDuplicates +
            noteSummary.skippedDuplicates +
            eventSummary.skippedDuplicates +
            anniversarySummary.skippedDuplicates +
            countdownSummary.skippedDuplicates +
            timeEntrySummary.skippedDuplicates,
      );
      final undo = await _showCompetitorImportResult(
        draft: draft,
        parsed: parsed,
        summary: summary,
        tasksOnly: tasksOnly,
        rollbackSnapshot: rollbackSnapshot,
      );
      if (!mounted) return;
      if (undo == true) {
        await _rollbackCompetitorImport(rollbackSnapshot);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已从 ${_competitorSourceLabel(draft.source)} 导入 ${summary.inserted} 项，跳过 ${summary.skipped} 项',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('数据迁移失败: $e')));
    }
  }

  Future<bool> _confirmCompetitorImportPreview({
    required _CompetitorImportDraft draft,
    required CompetitorTaskImportResult parsed,
    required bool tasksOnly,
  }) async {
    var confirmed = false;
    final otherModuleCount = parsed.totalImported - parsed.todos.length;
    final samples = _competitorPreviewSamples(parsed, tasksOnly: tasksOnly);
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) => AppDialog(
              title: const Text('导入预览'),
              maxWidth: 600,
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '来源：${_competitorSourceLabel(draft.source)} · 格式：${parsed.sourceLabel}',
                    ),
                    if (!draft.fieldMapping.isEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '字段映射：${_fieldMappingSummary(draft.fieldMapping)}',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _importPreviewChip('待办', parsed.todos.length),
                        _importPreviewChip('习惯', parsed.habits.length),
                        _importPreviewChip('笔记', parsed.notes.length),
                        _importPreviewChip('日程', parsed.calendarEvents.length),
                        _importPreviewChip('纪念日', parsed.anniversaries.length),
                        _importPreviewChip('倒数日', parsed.countdowns.length),
                        _importPreviewChip('时间足迹', parsed.timeEntries.length),
                        if (parsed.skippedRows > 0)
                          _importPreviewChip('解析跳过', parsed.skippedRows),
                      ],
                    ),
                    if (tasksOnly && otherModuleCount > 0) ...[
                      const SizedBox(height: 12),
                      Text(
                        '当前入口只导入待办；解析出的 $otherModuleCount 条其它模块数据不会写入。',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      '重复项策略：导入时会按本机已有标题、日期、内容等字段自动去重；重复项会跳过，不覆盖本机数据。',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    if (samples.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        '样例',
                        style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: DesignTokens.fontWeightStrong,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...samples
                          .take(6)
                          .map(
                            (line) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('· $line'),
                            ),
                          ),
                    ],
                    if (parsed.warnings.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        '解析提示',
                        style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: DesignTokens.fontWeightStrong,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...parsed.warnings
                          .take(4)
                          .map(
                            (line) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('· $line'),
                            ),
                          ),
                    ],
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: confirmed,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('我已确认预览和重复项处理策略'),
                      onChanged: (value) {
                        setDialogState(() => confirmed = value == true);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(I18n.tr('action.cancel')),
                ),
                FilledButton(
                  onPressed: confirmed ? () => Navigator.pop(ctx, true) : null,
                  child: const Text('确认导入'),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Future<bool> _showCompetitorImportResult({
    required _CompetitorImportDraft draft,
    required CompetitorTaskImportResult parsed,
    required _CompetitorImportApplySummary summary,
    required bool tasksOnly,
    required String rollbackSnapshot,
  }) async {
    assert(rollbackSnapshot.isNotEmpty);
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AppDialog(
            title: const Text('导入完成'),
            maxWidth: 560,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_competitorSourceLabel(draft.source)} · ${parsed.sourceLabel}',
                ),
                const SizedBox(height: 12),
                _importResultLine('待办', summary.todoInserted),
                if (!tasksOnly) ...[
                  _importResultLine('习惯', summary.habitInserted),
                  _importResultLine('笔记', summary.noteInserted),
                  _importResultLine('日程', summary.eventInserted),
                  _importResultLine('纪念日', summary.anniversaryInserted),
                  _importResultLine('倒数日', summary.countdownInserted),
                  _importResultLine('时间足迹', summary.timeEntryInserted),
                ],
                const SizedBox(height: 8),
                Text(
                  '跳过：解析无效 ${summary.skippedRows}，重复 ${summary.skippedDuplicates}',
                ),
                if (tasksOnly &&
                    parsed.totalImported > parsed.todos.length) ...[
                  const SizedBox(height: 8),
                  Text('本次使用待办入口，其它模块仅预览未写入。'),
                ],
                if (parsed.warnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('提示：${parsed.warnings.take(2).join('；')}'),
                ],
                const SizedBox(height: 8),
                Text(
                  '如发现导入结果不符合预期，可撤销本次导入并恢复到导入前的本地快照。',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('撤销本次导入'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('知道了'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _rollbackCompetitorImport(String rollbackSnapshot) async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await BackupService.importAll(
        rollbackSnapshot,
        merge: false,
        clearMissing: true,
      );
      if (!mounted) return;
      await _reloadAll();
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已撤销本次导入')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('撤销导入失败: $e')));
    }
  }

  String _competitorSourceLabel(_CompetitorImportSource source) {
    switch (source) {
      case _CompetitorImportSource.zhijianTime:
        return '指尖时光';
      case _CompetitorImportSource.ticktick:
        return '滴答清单';
      case _CompetitorImportSource.todoist:
        return 'Todoist';
      case _CompetitorImportSource.generic:
        return '通用 CSV / JSON';
    }
  }

  String _competitorSourceHint(_CompetitorImportSource source) {
    switch (source) {
      case _CompetitorImportSource.zhijianTime:
        return '适合指尖时光导出的计划、打卡、备忘录、日程、生日、纪念日和倒数日数据。';
      case _CompetitorImportSource.ticktick:
        return '适合滴答清单导出的任务、清单、标签、截止时间、重复和完成状态。';
      case _CompetitorImportSource.todoist:
        return '适合 Todoist 导出的任务、项目、标签、优先级、截止日期和备注字段。';
      case _CompetitorImportSource.generic:
        return '适合手工整理的 CSV / JSON。可用 type 字段指定 task、habit、note、event、birthday、anniversary、countdown、time_entry。';
    }
  }

  Future<CompetitorFieldMapping?> _editCompetitorFieldMapping(
    CompetitorFieldMapping initial,
  ) async {
    final controllers = <String, TextEditingController>{
      for (final target in _competitorFieldMappingTargets)
        target.$1: TextEditingController(text: initial.sourceFor(target.$1)),
    };
    try {
      return await showDialog<CompetitorFieldMapping>(
        context: context,
        builder: (ctx) => AppDialog(
          title: const Text('高级字段映射'),
          maxWidth: 680,
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '把非标准导出字段映射到多仪字段。留空的字段继续使用自动识别。',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  for (final target in _competitorFieldMappingTargets) ...[
                    TextField(
                      controller: controllers[target.$1],
                      decoration: InputDecoration(
                        labelText: target.$2,
                        hintText: '来源字段名',
                        helperText: '标准字段：${target.$1}',
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                for (final controller in controllers.values) {
                  controller.clear();
                }
              },
              child: const Text('清空'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  ctx,
                  CompetitorFieldMapping({
                    for (final target in _competitorFieldMappingTargets)
                      if (controllers[target.$1]!.text.trim().isNotEmpty)
                        target.$1: controllers[target.$1]!.text.trim(),
                  }),
                );
              },
              child: const Text('保存'),
            ),
          ],
        ),
      );
    } finally {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
  }

  String _fieldMappingSummary(CompetitorFieldMapping fieldMapping) {
    final entries = fieldMapping.targetToSource.entries
        .where(
          (entry) =>
              entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty,
        )
        .toList();
    if (entries.isEmpty) return '未设置字段映射，使用自动识别';
    final preview = entries
        .take(3)
        .map(
          (entry) => '${_fieldMappingTargetLabel(entry.key)} <- ${entry.value}',
        )
        .join('，');
    if (entries.length <= 3) return preview;
    return '$preview，另 ${entries.length - 3} 项';
  }

  String _fieldMappingTargetLabel(String key) {
    for (final target in _competitorFieldMappingTargets) {
      if (target.$1 == key) return target.$2;
    }
    return key;
  }

  Widget _importPreviewChip(String label, int count) {
    final cs = Theme.of(context).colorScheme;
    return Chip(
      label: Text('$label $count'),
      backgroundColor: count > 0
          ? cs.primaryContainer.withValues(alpha: 0.72)
          : cs.surfaceContainerHighest.withValues(alpha: 0.52),
      side: BorderSide(
        color: count > 0
            ? cs.primary.withValues(alpha: 0.28)
            : cs.outlineVariant,
      ),
    );
  }

  Widget _importResultLine(String label, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text('$count 项'),
        ],
      ),
    );
  }

  List<String> _competitorPreviewSamples(
    CompetitorTaskImportResult parsed, {
    required bool tasksOnly,
  }) {
    final samples = <String>[];
    samples.addAll(
      parsed.todos.take(3).map((todo) => '待办：${_shortImportText(todo.title)}'),
    );
    if (!tasksOnly) {
      samples.addAll(
        parsed.habits
            .take(2)
            .map((habit) => '习惯：${_shortImportText(habit.name)}'),
      );
      samples.addAll(
        parsed.notes
            .take(2)
            .map((note) => '笔记：${_shortImportText(note.content)}'),
      );
      samples.addAll(
        parsed.calendarEvents
            .take(2)
            .map((event) => '日程：${_shortImportText(event.title)}'),
      );
      samples.addAll(
        parsed.anniversaries
            .take(2)
            .map((item) => '纪念日：${_shortImportText(item.title)}'),
      );
      samples.addAll(
        parsed.countdowns
            .take(2)
            .map((item) => '倒数日：${_shortImportText(item.title)}'),
      );
      samples.addAll(
        parsed.timeEntries
            .take(2)
            .map((entry) => '时间足迹：${_shortImportText(entry.title)}'),
      );
    }
    return samples.where((line) => !line.endsWith('：')).toList();
  }

  String _shortImportText(String value) {
    final compact = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.length <= 32) return compact;
    return '${compact.substring(0, 32)}...';
  }

  Future<void> _wipe() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('清空全部数据?'),
        content: Text(I18n.tr('backup.wipe.confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await BackupService.wipeAll();
    if (!mounted) return;
    await _reloadAll();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清空本地数据')));
  }

  Future<void> _configureWebDavBackup() async {
    final baseCtrl = TextEditingController(text: _webDavConfig.baseUrl);
    final userCtrl = TextEditingController(text: _webDavConfig.username);
    final passwordCtrl = TextEditingController(text: _webDavConfig.password);
    final pathCtrl = TextEditingController(text: _webDavConfig.remotePath);
    final fileCtrl = TextEditingController(text: _webDavConfig.filename);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('WebDAV 云盘备份'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: baseCtrl,
                decoration: const InputDecoration(
                  labelText: 'WebDAV URL',
                  hintText: 'https://dav.example.com/dav',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: userCtrl,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码 / Token'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pathCtrl,
                decoration: const InputDecoration(
                  labelText: '远端目录',
                  hintText: '/duoyi-backups',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: fileCtrl,
                decoration: const InputDecoration(
                  labelText: '文件名',
                  hintText: 'duoyi-latest.json',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(I18n.tr('action.save')),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final config = WebDavBackupConfig(
      baseUrl: baseCtrl.text.trim(),
      username: userCtrl.text.trim(),
      password: passwordCtrl.text,
      remotePath: pathCtrl.text.trim().isEmpty
          ? '/duoyi-backups'
          : pathCtrl.text.trim(),
      filename: fileCtrl.text.trim().isEmpty
          ? 'duoyi-latest.json'
          : fileCtrl.text.trim(),
    );
    try {
      await WebDavBackupService.saveConfig(config);
      if (!mounted) return;
      setState(() => _webDavConfig = config);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('WebDAV 配置已保存')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
  }

  Future<void> _uploadWebDavBackup() async {
    if (!_webDavConfig.isConfigured) {
      await _configureWebDavBackup();
      if (!mounted) return;
      if (!_webDavConfig.isConfigured) return;
    }
    setState(() => _busy = true);
    try {
      final result = await WebDavBackupService().uploadCurrentBackup(
        _webDavConfig,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已上传到 WebDAV：${(result.bytes / 1024).toStringAsFixed(1)} KB · ${result.uri}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('WebDAV 上传失败: $e')));
    }
  }

  Future<void> _restoreFromWebDav({required bool merge}) async {
    if (!_webDavConfig.isConfigured) {
      await _configureWebDavBackup();
      if (!mounted) return;
      if (!_webDavConfig.isConfigured) return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text(merge ? '从 WebDAV 合并恢复?' : '从 WebDAV 覆盖恢复?'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              merge
                  ? '会下载 ${_webDavConfig.filename} 并合并到本机数据。'
                  : '会下载 ${_webDavConfig.filename} 并覆盖本机可备份数据。',
            ),
            // 覆盖恢复同样真删数据：写明缺失数据将被删除的后果。
            if (!merge) ...[
              const SizedBox(height: 8),
              Text(
                I18n.tr('backup.overwrite.will_delete_missing'),
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始恢复'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final raw = await WebDavBackupService().downloadLatestBackup(
        _webDavConfig,
      );
      final count = await BackupService.importAll(
        raw,
        merge: merge,
        // 覆盖=还原到备份快照：备份中不存在的本机数据一并删除，弹窗已警告。
        // 服务层 `clearMissing && !merge` 守卫保证 merge 合并入口不受影响。
        clearMissing: true,
      );
      if (!mounted) return;
      await _reloadAll();
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已从 WebDAV ${merge ? '合并' : '恢复'} $count 项数据')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('WebDAV 恢复失败: $e')));
    }
  }

  Future<void> _reloadAll() async {
    // 偏好键已纳入备份键集（BackupService._keys）：wipeAll/importAll 都会
    // 改写偏好存储，而根级 PreferencesProvider 的值缓存在内存字段，不重载
    // 会造成进程内偏好与存储分叉。与 main.dart 账号清理/云同步拉取一致：
    // 先 resetLocalState 作废在途读取并套用默认值，再 loadFromStorage 读回
    // 存储真值，最后把铃声偏好重放到原生设置（非 Android 为 no-op）。
    final preferencesProvider = context.read<PreferencesProvider>();
    preferencesProvider.resetLocalState();
    await preferencesProvider.loadFromStorage();
    await ReminderRingtoneSettings.applyPersistedSettingsToNative();
    if (!mounted) return;
    await Future.wait([
      context.read<TodoProvider>().loadFromStorage(),
      context.read<HabitProvider>().loadFromStorage(),
      context.read<PomodoroProvider>().loadFromStorage(),
      context.read<NoteProvider>().loadFromStorage(),
      context.read<AnniversaryProvider>().loadFromStorage(),
      context.read<DiaryProvider>().loadFromStorage(),
      context.read<GoalProvider>().loadFromStorage(),
      context.read<CourseProvider>().loadFromStorage(),
      context.read<UserProvider>().loadFromStorage(),
      context.read<TimeAuditProvider>().loadFromStorage(),
      context.read<AchievementProvider>().loadFromStorage(),
      context.read<ShareProvider>().load(),
      context.read<CalendarProvider>().loadFromStorage(),
      context.read<LocationReminderProvider>().loadFromStorage(),
      context.read<QuickCaptureTemplateProvider>().loadFromStorage(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final restoreFirst = widget.initialMode == BackupEntryMode.restore;
    final pageTitle = restoreFirst ? '恢复数据' : '备份';
    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(pageTitle),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppSecondaryControlTheme(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          children: [
            AppSurfaceCard(
              padding: const EdgeInsets.all(16),
              gradient: LinearGradient(
                colors: [cs.primary.withValues(alpha: 0.12), cs.surface],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.backup_outlined,
                      color: cs.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pageTitle,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: DesignTokens.fontWeightStrong,
                                color: cs.onSurface,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          restoreFirst
                              ? '把之前导出的 JSON 粘贴回来，可以合并到当前数据或覆盖本机数据。'
                              : '把本机所有数据打包成一段 JSON 文本，可以复制、发给自己，或者保存到另一台设备。',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.66),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (restoreFirst) ...[
              _restoreSection(),
              const SizedBox(height: 12),
              _backupSection(),
            ] else ...[
              _backupSection(),
              const SizedBox(height: 12),
              _restoreSection(),
            ],
            const SizedBox(height: 12),
            _webDavBackupSection(),
            const SizedBox(height: 12),
            AppSettingsSection(
              title: '单模块导出',
              subtitle: 'CSV / Markdown 格式',
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _chip('待办 · CSV', () {
                      final todos = context.read<TodoProvider>().todos;
                      _showExport('待办 CSV', ModuleExporter.todosCsv(todos));
                    }),
                    _chip('待办 · Markdown', () {
                      final todos = context.read<TodoProvider>().todos;
                      _showExport(
                        '待办 Markdown',
                        ModuleExporter.todosMarkdown(todos),
                      );
                    }),
                    _chip('习惯 · CSV', () {
                      final hs = context.read<HabitProvider>().habits;
                      _showExport('习惯 CSV', ModuleExporter.habitsCsv(hs));
                    }),
                    _chip('时间足迹 · CSV', () {
                      final entries = context.read<TimeAuditProvider>().entries;
                      _showExport(
                        '时间足迹 CSV',
                        ModuleExporter.timeEntriesCsv(entries),
                      );
                    }),
                    _chip('笔记 · CSV', () {
                      final ns = context.read<NoteProvider>().notes;
                      _showExport('笔记 CSV', ModuleExporter.notesCsv(ns));
                    }),
                    _chip('笔记 · Markdown', () {
                      final ns = context.read<NoteProvider>().notes;
                      _showExport(
                        '笔记 Markdown',
                        ModuleExporter.notesMarkdown(ns),
                      );
                    }),
                    _chip('纪念日 · CSV', () {
                      final list = context.read<AnniversaryProvider>().items;
                      _showExport(
                        '纪念日 CSV',
                        ModuleExporter.anniversariesCsv(list),
                      );
                    }),
                    _chip('纪念日 · Markdown', () {
                      final list = context.read<AnniversaryProvider>().items;
                      _showExport(
                        '纪念日 Markdown',
                        ModuleExporter.anniversariesMarkdown(list),
                      );
                    }),
                    _chip('目标 · CSV', () {
                      final list = context.read<GoalProvider>().goals;
                      _showExport('目标 CSV', ModuleExporter.goalsCsv(list));
                    }),
                    _chip('目标 · Markdown', () {
                      final list = context.read<GoalProvider>().goals;
                      _showExport(
                        '目标 Markdown',
                        ModuleExporter.goalsMarkdown(list),
                      );
                    }),
                  ],
                ),
              ],
            ),
            if (_exported != null) ...[
              const SizedBox(height: 12),
              AppSurfaceCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _exportedTitle ?? '导出内容',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontWeight: DesignTokens.fontWeightStrong,
                                  color: cs.onSurface,
                                ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _copy,
                          icon: const Icon(Icons.copy, size: 14),
                          label: const Text('复制'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      height: 200,
                      width: double.infinity,
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _exported!,
                          style: const TextStyle(
                            fontFamily: DesignTokens.fontFamily,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            AppSettingsSection(
              title: '危险操作',
              subtitle: '清空本机数据会删除本地内容',
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _wipe,
                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                  label: const Text(
                    '清空本机数据',
                    style: TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.red.shade300),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, VoidCallback onTap) {
    return ActionChip(
      avatar: const Icon(Icons.download, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
    );
  }

  Widget _backupSection() {
    return AppSettingsSection(
      title: '生成备份',
      subtitle: '导出本机全部数据为 JSON',
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _exportAll,
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('生成 JSON'),
          ),
        ),
      ],
    );
  }

  Widget _webDavBackupSection() {
    final configured = _webDavConfig.isConfigured;
    final subtitle = configured
        ? '${_webDavConfig.baseUrl} · ${_webDavConfig.remotePath}/${_webDavConfig.filename}'
        : '备份到 OpenList、坚果云、NAS 等兼容 WebDAV 的云盘';
    return AppSettingsSection(
      title: 'WebDAV 云盘备份',
      subtitle: subtitle,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _configureWebDavBackup,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: Text(configured ? '修改配置' : '配置云盘'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _uploadWebDavBackup,
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('上传备份'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _restoreFromWebDav(merge: true),
                icon: const Icon(Icons.cloud_sync_outlined, size: 18),
                label: const Text('云端合并'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _restoreFromWebDav(merge: false),
                icon: const Icon(Icons.cloud_download_outlined, size: 18),
                label: const Text('云端覆盖'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _restoreSection() {
    return AppSettingsSection(
      title: '恢复数据',
      subtitle: '粘贴备份 JSON，或从其他 App 的 CSV / JSON 迁移待办、习惯、笔记、日程、纪念日、倒数日和时间足迹',
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _import(merge: true),
                icon: const Icon(Icons.merge, size: 18),
                label: const Text('合并导入'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _import(merge: false),
                icon: const Icon(Icons.upload, size: 18),
                label: const Text('覆盖导入'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _importBackupFile(merge: true),
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: const Text('文件合并'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _importBackupFile(merge: false),
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('文件覆盖'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _importTasksFromOtherApps,
            icon: const Icon(Icons.move_to_inbox_outlined, size: 18),
            label: const Text('从其他 App 导入待办'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _importProductivityDataFromOtherApps,
            icon: const Icon(Icons.input_outlined, size: 18),
            label: const Text('从其他 App 导入待办/习惯/笔记/日程/纪念日/倒数日/时间足迹'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _importProductivityDataFile,
            icon: const Icon(Icons.upload_file_outlined, size: 18),
            label: const Text('从文件导入其他 App 数据'),
          ),
        ),
      ],
    );
  }
}
