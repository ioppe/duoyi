import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_clock.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../models/time_entry.dart';
import '../providers/time_audit_provider.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/surface_components.dart';

enum _AuditRange { today, week, month, all }

enum _AuditView { timeline, category, calendar, trend }

class TimeAuditScreen extends StatefulWidget {
  final String? initialEntryId;

  const TimeAuditScreen({super.key, this.initialEntryId});

  @override
  State<TimeAuditScreen> createState() => _TimeAuditScreenState();
}

class _TimeAuditScreenState extends State<TimeAuditScreen> {
  _AuditRange _range = _AuditRange.today;
  _AuditView _view = _AuditView.timeline;
  bool _openedInitialEntry = false;

  void _openInitialEntryIfNeeded(TimeAuditProvider provider) {
    if (_openedInitialEntry) return;
    final id = widget.initialEntryId;
    if (id == null || id.isEmpty) return;
    final index = provider.entries.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    _openedInitialEntry = true;
    if (_range != _AuditRange.all) {
      _range = _AuditRange.all;
      _view = _AuditView.timeline;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showEditor(context, entry: provider.entries[index]);
    });
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final provider = context.watch<TimeAuditProvider>();
    _openInitialEntryIfNeeded(provider);
    final entries = _entriesFor(provider);
    final totalSeconds = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.durationSeconds,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(I18n.tr('time_audit.title')),
        actions: [
          IconButton(
            tooltip: I18n.tr('time_audit.copy_report'),
            icon: const Icon(Icons.content_copy_outlined),
            onPressed: entries.isEmpty ? null : () => _copyReport(entries),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context),
        icon: const Icon(Icons.add),
        label: Text(I18n.tr('time_audit.add_manual')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _SummaryCard(
            rangeLabel: _rangeLabel(_range),
            totalSeconds: totalSeconds,
            entries: entries,
          ),
          const SizedBox(height: 10),
          _HorizontalSegmentStrip(
            child: SegmentedButton<_AuditRange>(
              segments: [
                ButtonSegment(
                  value: _AuditRange.today,
                  label: Text(I18n.tr('time_audit.segment.today')),
                ),
                ButtonSegment(
                  value: _AuditRange.week,
                  label: Text(I18n.tr('time_audit.range.week')),
                ),
                ButtonSegment(
                  value: _AuditRange.month,
                  label: Text(I18n.tr('time_audit.range.month')),
                ),
                ButtonSegment(
                  value: _AuditRange.all,
                  label: Text(I18n.tr('time_audit.range.all')),
                ),
              ],
              selected: {_range},
              onSelectionChanged: (value) =>
                  setState(() => _range = value.first),
            ),
          ),
          const SizedBox(height: 10),
          _HorizontalSegmentStrip(
            child: SegmentedButton<_AuditView>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: _AuditView.timeline,
                  icon: const Icon(Icons.view_agenda_outlined),
                  label: Text(I18n.tr('time_audit.view.timeline')),
                ),
                ButtonSegment(
                  value: _AuditView.category,
                  icon: const Icon(Icons.donut_small_outlined),
                  label: Text(I18n.tr('time_audit.view.category')),
                ),
                ButtonSegment(
                  value: _AuditView.calendar,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(I18n.tr('time_audit.view.calendar')),
                ),
                ButtonSegment(
                  value: _AuditView.trend,
                  icon: const Icon(Icons.bar_chart_outlined),
                  label: Text(I18n.tr('time_audit.view.trend')),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (value) =>
                  setState(() => _view = value.first),
            ),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            AppSurfaceCard(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
              child: Column(
                children: [
                  Icon(
                    Icons.timeline_outlined,
                    size: 42,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.32),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${_rangeLabel(_range)}${I18n.tr('time_audit.empty.suffix')}',
                  ),
                ],
              ),
            )
          else
            _buildActiveView(context, entries),
        ],
      ),
    );
  }

  Widget _buildActiveView(BuildContext context, List<TimeEntry> entries) {
    return switch (_view) {
      _AuditView.timeline => _TimelineView(
        rangeLabel: _rangeLabel(_range),
        entries: entries,
        onEdit: (entry) => _showEditor(context, entry: entry),
      ),
      _AuditView.category => _CategoryView(
        entries: entries,
        onCategoryTap: (category) {
          setState(() => _view = _AuditView.timeline);
        },
      ),
      _AuditView.calendar => _CalendarAuditView(
        entries: entries,
        onEdit: (entry) => _showEditor(context, entry: entry),
      ),
      _AuditView.trend => _TrendAuditView(entries: entries),
    };
  }

  void _showEditor(BuildContext context, {TimeEntry? entry}) {
    showAppModalSheet(
      context: context,
      builder: (_) => _TimeEntrySheet(entry: entry),
    );
  }

  Future<void> _copyReport(List<TimeEntry> entries) async {
    final report = _buildReport(entries);
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(I18n.tr('time_audit.report_copied')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _buildReport(List<TimeEntry> entries) {
    final totalSeconds = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.durationSeconds,
    );
    final byCategory = <TimeEntryCategory, int>{};
    for (final entry in entries) {
      byCategory[entry.category] =
          (byCategory[entry.category] ?? 0) + entry.durationSeconds;
    }
    final categories = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sorted = [...entries]..sort((a, b) => a.startAt.compareTo(b.startAt));
    final separator = _labelSeparator();
    final buffer = StringBuffer()
      ..writeln('# ${I18n.tr('time_audit.report.title')}')
      ..writeln()
      ..writeln(
        '- ${I18n.tr('time_audit.report.range')}$separator${_rangeLabel(_range)}',
      )
      ..writeln(
        '- ${I18n.tr('time_audit.report.total')}$separator${_formatDuration(totalSeconds)}',
      )
      ..writeln(
        '- ${I18n.tr('time_audit.entry_count')}$separator${entries.length}',
      )
      ..writeln()
      ..writeln('## ${I18n.tr('time_audit.report.category')}');
    for (final item in categories) {
      buffer.writeln(
        '- ${item.key.label}$separator${_formatDuration(item.value)}',
      );
    }
    buffer
      ..writeln()
      ..writeln('## ${I18n.tr('time_audit.report.details')}');
    for (final entry in sorted) {
      buffer.writeln(
        '- ${_date(entry.startAt)} ${_clock(entry.startAt)}-${_clock(entry.endAt)} '
        '${entry.title} · ${entry.category.label} · ${_formatDuration(entry.durationSeconds)}',
      );
    }
    return buffer.toString().trimRight();
  }

  List<TimeEntry> _entriesFor(TimeAuditProvider provider) {
    final now = AppClock.now();
    final todayStart = AppClock.date(now.year, now.month, now.day);
    final weekStart = AppClock.date(
      now.year,
      now.month,
      now.day - now.weekday + 1,
    );
    final monthStart = AppClock.date(now.year, now.month, 1);
    return switch (_range) {
      _AuditRange.today => provider.entriesInRange(
        todayStart,
        AppClock.date(now.year, now.month, now.day + 1),
      ),
      _AuditRange.week => provider.entriesInRange(
        weekStart,
        AppClock.date(weekStart.year, weekStart.month, weekStart.day + 7),
      ),
      _AuditRange.month => provider.entriesInRange(
        monthStart,
        AppClock.date(now.year, now.month + 1, 1),
      ),
      _AuditRange.all => provider.entries,
    };
  }

  String _rangeLabel(_AuditRange range) => switch (range) {
    _AuditRange.today => I18n.tr('time_audit.range.today'),
    _AuditRange.week => I18n.tr('time_audit.range.week'),
    _AuditRange.month => I18n.tr('time_audit.range.month'),
    _AuditRange.all => I18n.tr('time_audit.range.all'),
  };
}

class _TimelineView extends StatelessWidget {
  final String rangeLabel;
  final List<TimeEntry> entries;
  final ValueChanged<TimeEntry> onEdit;

  const _TimelineView({
    required this.rangeLabel,
    required this.entries,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
          child: Text(
            _rangeViewTitle(rangeLabel, I18n.tr('time_audit.view.timeline')),
            style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
          ),
        ),
        for (final entry in entries) ...[
          _TimeEntryCard(entry: entry, onTap: () => onEdit(entry)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _CategoryView extends StatelessWidget {
  final List<TimeEntry> entries;
  final ValueChanged<TimeEntryCategory> onCategoryTap;

  const _CategoryView({required this.entries, required this.onCategoryTap});

  @override
  Widget build(BuildContext context) {
    final total = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.durationSeconds,
    );
    final byCategory = <TimeEntryCategory, int>{};
    final bySource = <TimeEntrySource, int>{};
    for (final entry in entries) {
      byCategory[entry.category] =
          (byCategory[entry.category] ?? 0) + entry.durationSeconds;
      bySource[entry.source] =
          (bySource[entry.source] ?? 0) + entry.durationSeconds;
    }
    final categories = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sources = bySource.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
          child: Text(
            I18n.tr('time_audit.category_view'),
            style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
          ),
        ),
        AppSurfaceCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              for (final item in categories)
                _CategoryBreakdownTile(
                  category: item.key,
                  seconds: item.value,
                  totalSeconds: total,
                  onTap: () => onCategoryTap(item.key),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppSurfaceCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                I18n.tr('time_audit.source_breakdown'),
                style: const TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              for (final item in sources)
                _SourceBreakdownRow(
                  source: item.key,
                  seconds: item.value,
                  totalSeconds: total,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryBreakdownTile extends StatelessWidget {
  final TimeEntryCategory category;
  final int seconds;
  final int totalSeconds;
  final VoidCallback onTap;

  const _CategoryBreakdownTile({
    required this.category,
    required this.seconds,
    required this.totalSeconds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(category);
    final ratio = totalSeconds <= 0 ? 0.0 : seconds / totalSeconds;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_iconFor(category), color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          category.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatDuration(seconds),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 7,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceBreakdownRow extends StatelessWidget {
  final TimeEntrySource source;
  final int seconds;
  final int totalSeconds;

  const _SourceBreakdownRow({
    required this.source,
    required this.seconds,
    required this.totalSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ratio = totalSeconds <= 0 ? 0.0 : seconds / totalSeconds;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Text(
              source.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 7,
                color: cs.primary,
                backgroundColor: cs.primary.withValues(alpha: 0.12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(
              _formatDuration(seconds),
              maxLines: 1,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarAuditView extends StatelessWidget {
  final List<TimeEntry> entries;
  final ValueChanged<TimeEntry> onEdit;

  const _CalendarAuditView({required this.entries, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final grouped = <DateTime, List<TimeEntry>>{};
    for (final entry in entries) {
      final day = AppClock.dateOnly(AppClock.toLocal(entry.startAt));
      grouped.putIfAbsent(day, () => <TimeEntry>[]).add(entry);
    }
    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
          child: Text(
            I18n.tr('time_audit.calendar_view'),
            style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
          ),
        ),
        for (final day in days) ...[
          _DayGroupCard(day: day, entries: grouped[day]!, onEdit: onEdit),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _TrendAuditView extends StatelessWidget {
  final List<TimeEntry> entries;

  const _TrendAuditView({required this.entries});

  @override
  Widget build(BuildContext context) {
    final grouped = <DateTime, List<TimeEntry>>{};
    for (final entry in entries) {
      final day = AppClock.dateOnly(AppClock.toLocal(entry.startAt));
      grouped.putIfAbsent(day, () => <TimeEntry>[]).add(entry);
    }
    final days = grouped.keys.toList()..sort();
    final totals = {
      for (final day in days)
        day: grouped[day]!.fold<int>(
          0,
          (sum, entry) => sum + entry.durationSeconds,
        ),
    };
    final maxSeconds = totals.values.fold<int>(
      0,
      (max, value) => value > max ? value : max,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
          child: Text(
            I18n.tr('time_audit.trend_view'),
            style: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
          ),
        ),
        AppSurfaceCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              for (final day in days)
                _TrendDayRow(
                  day: day,
                  entries: grouped[day]!,
                  totalSeconds: totals[day] ?? 0,
                  maxSeconds: maxSeconds,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrendDayRow extends StatelessWidget {
  final DateTime day;
  final List<TimeEntry> entries;
  final int totalSeconds;
  final int maxSeconds;

  const _TrendDayRow({
    required this.day,
    required this.entries,
    required this.totalSeconds,
    required this.maxSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ratio = maxSeconds <= 0 ? 0.0 : totalSeconds / maxSeconds;
    final topCategory = _topCategory(entries);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              '${day.month}/${day.day}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 9,
                color: topCategory == null
                    ? cs.primary
                    : _colorFor(topCategory),
                backgroundColor: cs.primary.withValues(alpha: 0.10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 74,
            child: Text(
              _formatDuration(totalSeconds),
              maxLines: 1,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  TimeEntryCategory? _topCategory(List<TimeEntry> entries) {
    if (entries.isEmpty) return null;
    final totals = <TimeEntryCategory, int>{};
    for (final entry in entries) {
      totals[entry.category] =
          (totals[entry.category] ?? 0) + entry.durationSeconds;
    }
    return totals.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}

class _DayGroupCard extends StatelessWidget {
  final DateTime day;
  final List<TimeEntry> entries;
  final ValueChanged<TimeEntry> onEdit;

  const _DayGroupCard({
    required this.day,
    required this.entries,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final total = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.durationSeconds,
    );
    final sorted = [...entries]..sort((a, b) => a.startAt.compareTo(b.startAt));
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  I18nDateFormat.monthDay(day),
                  style: const TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(_formatDuration(total)),
            ],
          ),
          const SizedBox(height: 10),
          for (final entry in sorted)
            _CompactEntryRow(entry: entry, onTap: () => onEdit(entry)),
        ],
      ),
    );
  }
}

class _CompactEntryRow extends StatelessWidget {
  final TimeEntry entry;
  final VoidCallback onTap;

  const _CompactEntryRow({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(entry.category);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 30,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_clock(entry.startAt)}-${_clock(entry.endAt)} · ${entry.category.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(
                _formatDuration(entry.durationSeconds),
                maxLines: 1,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HorizontalSegmentStrip extends StatelessWidget {
  final Widget child;

  const _HorizontalSegmentStrip({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: child,
          ),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String rangeLabel;
  final int totalSeconds;
  final List<TimeEntry> entries;

  const _SummaryCard({
    required this.rangeLabel,
    required this.totalSeconds,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final byCategory = <TimeEntryCategory, int>{};
    for (final entry in entries) {
      byCategory[entry.category] =
          (byCategory[entry.category] ?? 0) + entry.durationSeconds;
    }
    final categories = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return AppSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _MetricBlock(
                  title:
                      '$rangeLabel${I18n.tr('time_audit.investment_suffix')}',
                  value: _formatDuration(totalSeconds),
                  icon: Icons.timelapse_outlined,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricBlock(
                  title: I18n.tr('time_audit.entry_count'),
                  value:
                      '${entries.length}${I18n.tr('time_audit.entry_count_suffix')}',
                  icon: Icons.list_alt_outlined,
                  color: const Color(0xFF26A69A),
                ),
              ),
            ],
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final entry in categories.take(4))
              _CategoryShareRow(
                category: entry.key,
                seconds: entry.value,
                totalSeconds: totalSeconds,
              ),
          ],
        ],
      ),
    );
  }
}

class _MetricBlock extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricBlock({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: 0.62),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryShareRow extends StatelessWidget {
  final TimeEntryCategory category;
  final int seconds;
  final int totalSeconds;

  const _CategoryShareRow({
    required this.category,
    required this.seconds,
    required this.totalSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(category);
    final ratio = totalSeconds <= 0 ? 0.0 : seconds / totalSeconds;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: Text(
              category.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 7,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 54,
            child: Text(
              _formatDuration(seconds),
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeEntryCard extends StatelessWidget {
  final TimeEntry entry;
  final VoidCallback onTap;

  const _TimeEntryCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(entry.category);
    return AppSurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_iconFor(entry.category), color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatDateTime(entry.startAt)} - ${_formatDateTime(entry.endAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.62),
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _Chip(text: entry.category.label),
                    _Chip(text: entry.source.label),
                    _Chip(text: _formatDuration(entry.durationSeconds)),
                    if (entry.note.isNotEmpty) _Chip(text: entry.note),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: I18n.tr('action.delete'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () => context.read<TimeAuditProvider>().delete(entry.id),
          ),
        ],
      ),
    );
  }
}

class _TimeEntrySheet extends StatefulWidget {
  final TimeEntry? entry;

  const _TimeEntrySheet({this.entry});

  @override
  State<_TimeEntrySheet> createState() => _TimeEntrySheetState();
}

class _TimeEntrySheetState extends State<_TimeEntrySheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _noteCtrl;
  late final TextEditingController _minutesCtrl;
  late TimeEntryCategory _category;
  late DateTime _startAt;
  late DateTime _endAt;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _titleCtrl = TextEditingController(
      text: entry?.title ?? I18n.tr('time_audit.default_title'),
    );
    _noteCtrl = TextEditingController(text: entry?.note ?? '');
    _minutesCtrl = TextEditingController(
      text: entry == null
          ? '25'
          : (entry.durationSeconds ~/ 60).clamp(1, 1440).toString(),
    );
    _category = entry?.category ?? TimeEntryCategory.focus;
    _startAt = AppClock.toLocal(entry?.startAt ?? AppClock.now());
    _endAt = AppClock.toLocal(
      entry?.endAt ?? AppClock.now().add(const Duration(minutes: 25)),
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    _minutesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    return AppModalSheet(
      title: widget.entry == null
          ? I18n.tr('time_audit.sheet.add_title')
          : I18n.tr('time_audit.sheet.edit_title'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(I18n.tr('action.cancel')),
        ),
        FilledButton(onPressed: _save, child: Text(I18n.tr('action.save'))),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: InputDecoration(
              labelText: I18n.tr('time_audit.field.title'),
              prefixIcon: const Icon(Icons.title, size: 20),
            ),
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          AppDropdownField<TimeEntryCategory>(
            initialValue: _category,
            labelText: I18n.tr('time_audit.field.category'),
            prefixIcon: const Icon(Icons.label_outline, size: 20),
            items: [
              for (final c in TimeEntryCategory.values)
                DropdownMenuItem(value: c, child: Text(c.label)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _category = v);
            },
          ),
          const SizedBox(height: DesignTokens.spaceMd),
          LayoutBuilder(
            builder: (context, constraints) {
              final startTile = _TimeEndpointTile(
                icon: Icons.play_arrow,
                title: I18n.tr('time_audit.field.start'),
                subtitle: _formatDateTime(_startAt),
                onTap: _pickStart,
              );
              final endTile = _TimeEndpointTile(
                icon: Icons.stop,
                title: I18n.tr('time_audit.field.end'),
                subtitle: _formatDateTime(_endAt),
                onTap: _pickEnd,
              );
              if (constraints.maxWidth < 360) {
                return Column(
                  children: [
                    startTile,
                    const SizedBox(height: DesignTokens.spaceXs),
                    endTile,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: startTile),
                  const SizedBox(width: DesignTokens.spaceSm),
                  Expanded(child: endTile),
                ],
              );
            },
          ),
          const SizedBox(height: DesignTokens.spaceSm),
          TextField(
            controller: _minutesCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: I18n.tr('time_audit.field.minutes'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: DesignTokens.spaceSm),
          TextField(
            controller: _noteCtrl,
            decoration: InputDecoration(
              labelText: I18n.tr('time_audit.field.note'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickStart() async {
    final date = await AppDatePicker.pickSolar(
      context,
      initialDate: AppClock.toLocal(_startAt),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      title: I18n.tr('time_audit.picker.start_date'),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await AppTimePicker.show(
      context,
      initialTime: TimeOfDay.fromDateTime(AppClock.toLocal(_startAt)),
      title: I18n.tr('time_audit.picker.start_time'),
      minuteStep: 5,
    );
    if (time == null) return;
    if (!mounted) return;
    setState(() {
      _startAt = AppClock.date(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      final minutes = int.tryParse(_minutesCtrl.text.trim()) ?? 25;
      _endAt = _startAt.add(Duration(minutes: minutes));
    });
  }

  Future<void> _pickEnd() async {
    final date = await AppDatePicker.pickSolar(
      context,
      initialDate: AppClock.toLocal(_endAt),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      title: I18n.tr('time_audit.picker.end_date'),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await AppTimePicker.show(
      context,
      initialTime: TimeOfDay.fromDateTime(AppClock.toLocal(_endAt)),
      title: I18n.tr('time_audit.picker.end_time'),
      minuteStep: 5,
    );
    if (time == null) return;
    if (!mounted) return;
    setState(
      () => _endAt = AppClock.date(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _save() async {
    final provider = context.read<TimeAuditProvider>();
    final minutes = int.tryParse(_minutesCtrl.text.trim()) ?? 0;
    final endAt = _endAt.isAfter(_startAt)
        ? _endAt
        : _startAt.add(Duration(minutes: minutes <= 0 ? 1 : minutes));
    final entry = TimeEntry(
      id: widget.entry?.id,
      title: _titleCtrl.text.trim().isEmpty
          ? I18n.tr('time_audit.default_title')
          : _titleCtrl.text.trim(),
      startAt: _startAt.toUtc(),
      endAt: endAt.toUtc(),
      category: _category,
      source: TimeEntrySource.manual,
      note: _noteCtrl.text.trim(),
      createdAt: widget.entry?.createdAt,
    );
    if (widget.entry == null) {
      await provider.add(entry);
    } else {
      await provider.update(entry);
    }
    if (!mounted) return;
    Navigator.pop(context);
  }
}

class _TimeEndpointTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _TimeEndpointTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }
}

String _formatDateTime(DateTime d) =>
    I18nDateFormat.shortDateTime(AppClock.toLocal(d));

String _clock(DateTime d) => I18nDateFormat.time(AppClock.toLocal(d));

String _date(DateTime d) => I18nDateFormat.date(AppClock.toLocal(d));

String _formatDuration(int seconds) {
  if (seconds >= 3600) {
    return '${(seconds / 3600).toStringAsFixed(seconds % 3600 == 0 ? 0 : 1)} ${I18n.tr('unit.hour')}';
  }
  return '${(seconds / 60).toStringAsFixed(seconds % 60 == 0 ? 0 : 1)} ${I18n.tr('unit.minute')}';
}

String _rangeViewTitle(String rangeLabel, String viewLabel) {
  return switch (I18n.current) {
    AppLocale.en => '$rangeLabel $viewLabel',
    AppLocale.zh => '$rangeLabel$viewLabel',
  };
}

String _labelSeparator() {
  return switch (I18n.current) {
    AppLocale.en => ': ',
    AppLocale.zh => '：',
  };
}

Color _colorFor(TimeEntryCategory category) => switch (category) {
  TimeEntryCategory.focus => const Color(0xFFE53935),
  TimeEntryCategory.todo => const Color(0xFF42A5F5),
  TimeEntryCategory.habit => const Color(0xFF66BB6A),
  TimeEntryCategory.goal => const Color(0xFFAB47BC),
  TimeEntryCategory.study => const Color(0xFF26A69A),
  TimeEntryCategory.work => const Color(0xFFFF9800),
  TimeEntryCategory.life => const Color(0xFF8D6E63),
  TimeEntryCategory.other => const Color(0xFF78909C),
};

IconData _iconFor(TimeEntryCategory category) => switch (category) {
  TimeEntryCategory.focus => Icons.timer_outlined,
  TimeEntryCategory.todo => Icons.check_circle_outline,
  TimeEntryCategory.habit => Icons.repeat,
  TimeEntryCategory.goal => Icons.flag_outlined,
  TimeEntryCategory.study => Icons.menu_book_outlined,
  TimeEntryCategory.work => Icons.work_outline,
  TimeEntryCategory.life => Icons.favorite_outline,
  TimeEntryCategory.other => Icons.more_horiz,
};
