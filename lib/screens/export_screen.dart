import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../providers/anniversary_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/countdown_provider.dart';
import '../providers/course_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/todo_provider.dart';
import '../services/calendar_sync_service.dart';
import '../services/ics_exporter.dart';
import '../widgets/surface_components.dart';

/// iCalendar 导出：生成 .ics 文本供复制或订阅。
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool _includeAnniversaries = true;
  bool _includeCalendar = true;
  String? _ics;
  bool _pushingCalDav = false;

  void _rebuildCalendarIndex() {
    final ann = context.read<AnniversaryProvider>();
    final cal = context.read<CalendarProvider>();

    // 先刷新一次日历索引
    cal.rebuild(
      context.read<TodoProvider>().todos,
      context.read<HabitProvider>().habits,
      context.read<PomodoroProvider>().sessions,
      Theme.of(context).colorScheme,
      anniversaries: ann.items,
      courses: context.read<CourseProvider>().courses,
      courseSettings: context.read<CourseProvider>().settings,
      countdowns: context.read<CountdownProvider>().items,
      goals: context.read<GoalProvider>().goals,
    );
  }

  void _generate() {
    _rebuildCalendarIndex();
    final ann = context.read<AnniversaryProvider>();
    final cal = context.read<CalendarProvider>();

    final sb = StringBuffer();
    if (_includeAnniversaries) {
      sb.writeln(IcsExporter.fromAnniversaries(ann.items));
    }
    if (_includeCalendar) {
      sb.writeln(IcsExporter.fromEvents(cal.events));
    }
    setState(() => _ics = sb.toString());
  }

  Future<void> _pushCalDav() async {
    final sync = context.read<CalendarSyncProvider>();
    if (sync.writeTarget?.isConfigured != true) return;
    setState(() => _pushingCalDav = true);
    try {
      _rebuildCalendarIndex();
      final count = await sync.pushEventsToCalDav(
        context.read<CalendarProvider>().events,
      );
      if (!mounted) return;
      final conflicts = sync.lastCalDavConflicts.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            conflicts == 0
                ? '${I18n.tr('export.caldav.success.prefix')}$count'
                      '${I18n.tr('export.caldav.success.suffix')}'
                : '${I18n.tr('export.caldav.conflict.prefix')}$count'
                      '${I18n.tr('export.caldav.conflict.middle')}$conflicts'
                      '${I18n.tr('export.caldav.conflict.suffix')}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${I18n.tr('export.caldav.failed_prefix')}$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _pushingCalDav = false);
    }
  }

  Future<void> _copy() async {
    if (_ics == null) return;
    await Clipboard.setData(ClipboardData(text: _ics!));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(I18n.tr('export.copy.done'))));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final calendarSync = context.watch<CalendarSyncProvider>();
    final canPushCalDav =
        _includeCalendar && calendarSync.writeTarget?.isConfigured == true;

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(I18n.tr('export.title')),
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
                      Icons.event_note_outlined,
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
                          I18n.tr('export.hero.title'),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.normal,
                                color: cs.onSurface,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          I18n.tr('export.hero.subtitle'),
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
            const SizedBox(height: 12),
            AppSettingsSection(
              title: I18n.tr('export.range.title'),
              subtitle: I18n.tr('export.range.subtitle'),
              children: [
                AppSwitchTile(
                  icon: Icons.cake_outlined,
                  color: Colors.pink,
                  title: I18n.tr('export.include_anniversaries'),
                  subtitle: I18n.tr('export.include_anniversaries.subtitle'),
                  value: _includeAnniversaries,
                  onChanged: (v) => setState(() => _includeAnniversaries = v),
                ),
                AppSwitchTile(
                  icon: Icons.calendar_month_outlined,
                  color: Colors.blue,
                  title: I18n.tr('export.include_calendar'),
                  subtitle: I18n.tr('export.include_calendar.subtitle'),
                  value: _includeCalendar,
                  onChanged: (v) => setState(() => _includeCalendar = v),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: canPushCalDav && !_pushingCalDav
                          ? _pushCalDav
                          : null,
                      icon: _pushingCalDav
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined),
                      label: Text(I18n.tr('export.push_caldav')),
                    ),
                    FilledButton.icon(
                      onPressed: _generate,
                      icon: const Icon(Icons.file_download_outlined),
                      label: Text(I18n.tr('export.generate_ics')),
                    ),
                  ],
                ),
              ],
            ),
            if (_ics != null) ...[
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
                            I18n.tr('export.content.title'),
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.normal,
                                  color: cs.onSurface,
                                ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _copy,
                          icon: const Icon(Icons.copy, size: 14),
                          label: Text(I18n.tr('export.copy')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 220,
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _ics!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
