import '../widgets/app_create_fab.dart';
import 'package:flutter/material.dart';
import '../core/app_clock.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import 'package:provider/provider.dart';
import '../models/course_schedule.dart';
import '../providers/course_provider.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

const _weekdayKeys = [
  'weekday.mon',
  'weekday.tue',
  'weekday.wed',
  'weekday.thu',
  'weekday.fri',
  'weekday.sat',
  'weekday.sun',
];

Future<void> showCourseEditor(BuildContext context, {CourseItem? course}) {
  final provider = context.read<CourseProvider>();
  return showAppModalSheet<void>(
    context: context,
    builder: (_) => _CourseEditSheet(provider: provider, course: course),
  );
}

class CourseScheduleScreen extends StatefulWidget {
  final String? initialCourseId;

  const CourseScheduleScreen({super.key, this.initialCourseId});

  @override
  State<CourseScheduleScreen> createState() => _CourseScheduleScreenState();
}

class _CourseScheduleScreenState extends State<CourseScheduleScreen> {
  bool _openedInitialCourse = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _openInitialCourseIfNeeded();
  }

  void _openInitialCourseIfNeeded() {
    final id = widget.initialCourseId;
    if (_openedInitialCourse || id == null || id.isEmpty) return;
    _openedInitialCourse = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<CourseProvider>();
      final matches = provider.courses.where((course) => course.id == id);
      if (matches.isEmpty) return;
      final course = matches.first;
      if (course.weeks.isNotEmpty) {
        provider.setViewingWeek(course.weeks.first);
      }
      showCourseEditor(context, course: course);
    });
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final provider = context.watch<CourseProvider>();
    final settings = provider.settings;
    final week = provider.viewingWeek;
    final courses = provider.coursesOfWeek(week);
    final compactToolbar = MediaQuery.sizeOf(context).width < 360;

    return Scaffold(
      appBar: AppBar(
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        title: GestureDetector(
          onTap: () => _pickWeek(context, provider),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _courseWeekLabel(week),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            constraints: compactToolbar
                ? const BoxConstraints.tightFor(width: 40, height: 40)
                : null,
            padding: compactToolbar ? EdgeInsets.zero : null,
            onPressed: () => provider.setViewingWeek(week - 1),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            constraints: compactToolbar
                ? const BoxConstraints.tightFor(width: 40, height: 40)
                : null,
            padding: compactToolbar ? EdgeInsets.zero : null,
            onPressed: () => provider.setViewingWeek(week + 1),
          ),
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: I18n.tr('course.week.current_tooltip'),
            constraints: compactToolbar
                ? const BoxConstraints.tightFor(width: 40, height: 40)
                : null,
            padding: compactToolbar ? EdgeInsets.zero : null,
            onPressed: () => provider.setViewingWeek(
              provider.settings.weekOf(AppClock.now()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            constraints: compactToolbar
                ? const BoxConstraints.tightFor(width: 40, height: 40)
                : null,
            padding: compactToolbar ? EdgeInsets.zero : null,
            onPressed: () => _editSettings(context, provider),
          ),
        ],
      ),
      body: provider.courses.isEmpty
          ? EmptyState(
              icon: Icons.school_outlined,
              message: I18n.tr('course.empty.message'),
              actionLabel: I18n.tr('course.add'),
              onAction: () => _addCourse(context),
            )
          : _ScheduleGrid(settings: settings, courses: courses, week: week),
      floatingActionButton: AppCreateFab(
        label: I18n.tr('course.add'),
        onPressed: () => _addCourse(context),
      ),
    );
  }

  void _pickWeek(BuildContext context, CourseProvider p) {
    showAppModalSheet(
      context: context,
      builder: (_) => AppModalSheet(
        title: I18n.tr('course.week_picker.title'),
        subtitle: I18n.tr('course.week_picker.subtitle'),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final crossAxisCount = width < 300
                ? 3
                : width < 420
                ? 4
                : 5;
            return GridView.builder(
              key: const ValueKey('course_week_picker_adaptive_grid'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: width < 340 ? 1.75 : 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: p.settings.totalWeeks,
              itemBuilder: (context, i) {
                final w = i + 1;
                final cs = Theme.of(context).colorScheme;
                final current = w == p.currentWeek;
                final selected = w == p.viewingWeek;
                final selectedBackground = Color.alphaBlend(
                  cs.primary.withValues(alpha: 0.09),
                  cs.surface,
                );
                return OutlinedButton(
                  onPressed: () {
                    p.setViewingWeek(w);
                    Navigator.pop(context);
                  },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: selected
                        ? selectedBackground
                        : (current ? cs.primary.withValues(alpha: 0.1) : null),
                    foregroundColor: selected ? cs.onSurface : null,
                    side: BorderSide(
                      color: selected
                          ? cs.primary.withValues(alpha: 0.32)
                          : cs.outlineVariant.withValues(alpha: 0.24),
                      width: 0.45,
                    ),
                  ),
                  child: Text(
                    _courseWeekLabel(w),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _editSettings(BuildContext context, CourseProvider p) {
    showAppModalSheet(
      context: context,
      builder: (_) => _ScheduleSettingsSheet(provider: p),
    );
  }

  void _addCourse(BuildContext context) => showCourseEditor(context);
}

class _ScheduleGrid extends StatelessWidget {
  final ScheduleSettings settings;
  final List<CourseItem> courses;
  final int week;

  const _ScheduleGrid({
    required this.settings,
    required this.courses,
    required this.week,
  });

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final monday = settings.termStart.add(Duration(days: (week - 1) * 7));
    final today = AppClock.now();

    const sectionH = 56.0;
    const timeW = 34.0;
    const minDayW = 64.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        const minGridW = timeW + minDayW * 7;
        final gridW = availableW > minGridW ? availableW : minGridW;
        final bodyW = gridW - timeW;
        final cellW = bodyW / 7;

        return SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              key: const ValueKey('course_schedule_adaptive_grid'),
              width: gridW,
              child: Column(
                children: [
                  // 顶栏：周几 + 日期
                  Row(
                    children: [
                      const SizedBox(width: timeW),
                      ...List.generate(7, (i) {
                        final d = monday.add(Duration(days: i));
                        final isToday =
                            d.year == today.year &&
                            d.month == today.month &&
                            d.day == today.day;
                        final cs = Theme.of(context).colorScheme;
                        return Expanded(
                          child: Container(
                            height: 48,
                            alignment: Alignment.center,
                            color: isToday
                                ? cs.primary.withValues(alpha: 0.08)
                                : null,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _weekdayLabel(i + 1),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isToday ? cs.primary : null,
                                    fontWeight: DesignTokens.fontWeightStrong,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${d.month}/${d.day}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isToday
                                        ? cs.primary
                                        : Colors.grey.shade600,
                                  ),
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                  const Divider(height: 1),
                  // 主体：节数 × 星期
                  SizedBox(
                    height: sectionH * settings.sessionsPerDay,
                    child: Stack(
                      children: [
                        // 背景：节次+格线
                        Row(
                          children: [
                            // 节次列
                            SizedBox(
                              width: timeW,
                              child: Column(
                                children: List.generate(
                                  settings.sessionsPerDay,
                                  (i) => Container(
                                    height: sectionH,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Colors.grey.shade200,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                        fontWeight:
                                            DesignTokens.fontWeightStrong,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // 日格
                            ...List.generate(7, (col) {
                              return Expanded(
                                child: Column(
                                  children: List.generate(
                                    settings.sessionsPerDay,
                                    (row) => Container(
                                      height: sectionH,
                                      decoration: BoxDecoration(
                                        border: Border(
                                          right: BorderSide(
                                            color: Colors.grey.shade200,
                                          ),
                                          bottom: BorderSide(
                                            color: Colors.grey.shade200,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                        // 课程块
                        ...courses.map((c) {
                          final col = c.weekday - 1;
                          final row = c.startSection - 1;
                          if (row < 0 || row >= settings.sessionsPerDay) {
                            return const SizedBox.shrink();
                          }
                          return Positioned(
                            left: timeW + col * cellW + 2,
                            top: row * sectionH + 2,
                            width: cellW - 4,
                            height: sectionH * c.sectionCount - 4,
                            child: _CourseBlock(course: c),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CourseBlock extends StatelessWidget {
  final CourseItem course;
  const _CourseBlock({required this.course});

  @override
  Widget build(BuildContext context) {
    final color = Color(course.colorValue);
    final settings = context.read<CourseProvider>().settings;
    final weekPattern = _weekPatternLabel(course.weeks, settings.totalWeeks);
    return GestureDetector(
      onTap: () => showCourseEditor(context, course: course),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactWidth = constraints.maxWidth < 76;
          final compactHeight = constraints.maxHeight < 72;
          final padding = compactWidth
              ? const EdgeInsets.symmetric(horizontal: 4, vertical: 4)
              : const EdgeInsets.all(6);
          final showTime = constraints.maxHeight >= 42;
          final showDetails =
              !compactWidth && constraints.maxHeight >= 96 && !compactHeight;
          final showTeacher =
              showDetails &&
              constraints.maxHeight >= 112 &&
              course.teacher.isNotEmpty;
          final showWeek =
              showDetails &&
              constraints.maxHeight >= 128 &&
              weekPattern != null;
          final titleMaxLines = constraints.maxHeight >= 82 && !compactWidth
              ? 2
              : 1;

          return Container(
            clipBehavior: Clip.antiAlias,
            padding: padding,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showTime) ...[
                  Text(
                    settings.sectionTimeRangeLabel(
                      course.startSection,
                      course.sectionCount,
                    ),
                    style: const TextStyle(
                      fontSize: 9,
                      height: 1.05,
                      color: Colors.white70,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  course.name,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.08,
                    fontWeight: DesignTokens.fontWeightStrong,
                    color: Colors.white,
                  ),
                  maxLines: titleMaxLines,
                  overflow: TextOverflow.ellipsis,
                ),
                if (showDetails && course.location.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '@${course.location}',
                      style: const TextStyle(
                        fontSize: 10,
                        height: 1.05,
                        color: Colors.white70,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (showTeacher)
                  Text(
                    course.teacher,
                    style: const TextStyle(
                      fontSize: 10,
                      height: 1.05,
                      color: Colors.white70,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (showWeek)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      weekPattern,
                      style: const TextStyle(
                        fontSize: 9,
                        height: 1.05,
                        color: Colors.white70,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String? _weekPatternLabel(List<int> weeks, int totalWeeks) {
    if (weeks.isEmpty) return null;
    final normalized = weeks.toSet();
    final all = normalized.length >= totalWeeks;
    if (all) return I18n.tr('course.weeks.all');
    final oddCount = normalized.where((w) => w.isOdd).length;
    final evenCount = normalized.where((w) => w.isEven).length;
    final expectedOdd = List.generate(
      totalWeeks,
      (i) => i + 1,
    ).where((w) => w.isOdd).length;
    final expectedEven = totalWeeks - expectedOdd;
    if (oddCount == expectedOdd && evenCount == 0) {
      return I18n.tr('course.weeks.odd');
    }
    if (evenCount == expectedEven && oddCount == 0) {
      return I18n.tr('course.weeks.even');
    }
    return '${normalized.length}${I18n.tr('course.week.count_suffix')}';
  }
}

class _ScheduleSettingsSheet extends StatefulWidget {
  final CourseProvider provider;
  const _ScheduleSettingsSheet({required this.provider});

  @override
  State<_ScheduleSettingsSheet> createState() => _ScheduleSettingsSheetState();
}

class _ScheduleSettingsSheetState extends State<_ScheduleSettingsSheet> {
  late DateTime _termStart;
  late int _totalWeeks;
  late int _sessionsPerDay;
  late int _sessionMinutes;
  late TimeOfDay _firstSessionTime;
  late int _breakMinutes;

  @override
  void initState() {
    super.initState();
    final s = widget.provider.settings;
    _termStart = s.termStart;
    _totalWeeks = s.totalWeeks;
    _sessionsPerDay = s.sessionsPerDay;
    _sessionMinutes = s.sessionMinutes;
    _firstSessionTime = TimeOfDay(
      hour: s.firstSessionHour,
      minute: s.firstSessionMinute,
    );
    _breakMinutes = s.breakMinutes;
  }

  @override
  Widget build(BuildContext context) {
    return AppModalSheet(
      title: I18n.tr('course.settings.title'),
      subtitle: I18n.tr('course.settings.subtitle'),
      actions: [
        FilledButton(
          onPressed: () {
            widget.provider.updateSettings(
              ScheduleSettings(
                termStart: _termStart,
                totalWeeks: _totalWeeks,
                sessionsPerDay: _sessionsPerDay,
                sessionMinutes: _sessionMinutes,
                firstSessionHour: _firstSessionTime.hour,
                firstSessionMinute: _firstSessionTime.minute,
                breakMinutes: _breakMinutes,
              ),
            );
            Navigator.pop(context);
          },
          child: Text(I18n.tr('action.save')),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(I18n.tr('course.field.term_start')),
            subtitle: Text(I18nDateFormat.date(_termStart)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await AppDatePicker.pickSolar(
                context,
                initialDate: _termStart,
                firstDate: DateTime(2020),
                lastDate: DateTime(2099, 12, 31),
                title: I18n.tr('course.field.term_start_picker'),
              );
              if (!mounted) return;
              if (picked != null) {
                final monday = picked.subtract(
                  Duration(days: picked.weekday - 1),
                );
                setState(() => _termStart = monday);
              }
            },
          ),
          _sliderRow(
            I18n.tr('course.field.total_weeks'),
            _totalWeeks.toDouble(),
            8,
            30,
            1,
            (v) {
              setState(() => _totalWeeks = v.toInt());
            },
          ),
          _sliderRow(
            I18n.tr('course.field.sessions_per_day'),
            _sessionsPerDay.toDouble(),
            4,
            14,
            1,
            (v) {
              setState(() => _sessionsPerDay = v.toInt());
            },
          ),
          _sliderRow(
            I18n.tr('course.field.session_minutes'),
            _sessionMinutes.toDouble(),
            30,
            90,
            5,
            (v) {
              setState(() => _sessionMinutes = v.toInt());
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(I18n.tr('course.field.first_session_time')),
            subtitle: Text(
              I18nDateFormat.timeOfDay(
                hour: _firstSessionTime.hour,
                minute: _firstSessionTime.minute,
              ),
            ),
            trailing: const Icon(Icons.schedule),
            onTap: () async {
              final picked = await AppTimePicker.show(
                context,
                initialTime: _firstSessionTime,
                title: I18n.tr('course.field.first_session_time'),
                subtitle: I18n.tr('course.field.first_session_time_subtitle'),
                minuteStep: 5,
              );
              if (!mounted) return;
              if (picked != null) {
                setState(() => _firstSessionTime = picked);
              }
            },
          ),
          _sliderRow(
            I18n.tr('course.field.break_minutes'),
            _breakMinutes.toDouble(),
            0,
            30,
            5,
            (v) {
              setState(() => _breakMinutes = v.toInt());
            },
          ),
          const SizedBox(height: 8),
          Text(
            '${I18n.tr('course.settings.preview_prefix')}1 ${_previewSettings().sectionTimeLabel(1)} · '
            '2 ${_previewSettings().sectionTimeLabel(2)}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
        ],
      ),
    );
  }

  ScheduleSettings _previewSettings() {
    return ScheduleSettings(
      termStart: _termStart,
      totalWeeks: _totalWeeks,
      sessionsPerDay: _sessionsPerDay,
      sessionMinutes: _sessionMinutes,
      firstSessionHour: _firstSessionTime.hour,
      firstSessionMinute: _firstSessionTime.minute,
      breakMinutes: _breakMinutes,
    );
  }

  Widget _sliderRow(
    String label,
    double value,
    double min,
    double max,
    double step,
    ValueChanged<double> onChange,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final valueText = Text(
            value.toInt().toString(),
            textAlign: TextAlign.right,
            maxLines: 1,
          );
          final slider = Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) / step).round(),
            label: value.toInt().toString(),
            onChanged: onChange,
          );
          final title = Text(
            label,
            style: const TextStyle(fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );

          if (constraints.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 8),
                    SizedBox(width: 42, child: valueText),
                  ],
                ),
                slider,
              ],
            );
          }

          return Row(
            children: [
              SizedBox(width: 104, child: title),
              Expanded(child: slider),
              SizedBox(width: 42, child: valueText),
            ],
          );
        },
      ),
    );
  }
}

class _CourseEditSheet extends StatefulWidget {
  final CourseProvider provider;
  final CourseItem? course;
  const _CourseEditSheet({required this.provider, this.course});

  @override
  State<_CourseEditSheet> createState() => _CourseEditSheetState();
}

class _CourseEditSheetState extends State<_CourseEditSheet> {
  late TextEditingController _name;
  late TextEditingController _teacher;
  late TextEditingController _location;
  int _weekday = 1;
  int _startSection = 1;
  int _sectionCount = 2;
  List<int> _weeks = [];
  int _colorValue = 0xFF42A5F5;

  static const _presetColors = [
    0xFF42A5F5,
    0xFF66BB6A,
    0xFFFFA726,
    0xFFEF5350,
    0xFFAB47BC,
    0xFF26A69A,
    0xFFEC407A,
    0xFF5C6BC0,
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    _name = TextEditingController(text: c?.name ?? '');
    _teacher = TextEditingController(text: c?.teacher ?? '');
    _location = TextEditingController(text: c?.location ?? '');
    _weekday = c?.weekday ?? 1;
    _startSection = c?.startSection ?? 1;
    _sectionCount = c?.sectionCount ?? 2;
    _weeks = [...?c?.weeks];
    if (_weeks.isEmpty) {
      _weeks = List.generate(widget.provider.settings.totalWeeks, (i) => i + 1);
    }
    _colorValue = c?.colorValue ?? 0xFF42A5F5;
  }

  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.provider.settings;
    return AppModalSheet(
      title: widget.course == null
          ? I18n.tr('course.editor.add_title')
          : I18n.tr('course.editor.edit_title'),
      subtitle: I18n.tr('course.editor.subtitle'),
      leadingActions: widget.course == null
          ? const []
          : [
              TextButton(
                onPressed: () {
                  widget.provider.delete(widget.course!.id);
                  Navigator.pop(context);
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(I18n.tr('action.delete')),
              ),
            ],
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(I18n.tr('action.cancel')),
        ),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            final item = CourseItem(
              id: widget.course?.id,
              name: _name.text.trim(),
              teacher: _teacher.text.trim(),
              location: _location.text.trim(),
              weekday: _weekday,
              startSection: _startSection,
              sectionCount: _sectionCount,
              weeks: _weeks..sort(),
              colorValue: _colorValue,
            );
            if (widget.course == null) {
              widget.provider.add(item);
            } else {
              widget.provider.update(item);
            }
            Navigator.pop(context);
          },
          child: Text(
            widget.course == null
                ? I18n.tr('action.add')
                : I18n.tr('action.save'),
          ),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: widget.course == null,
            decoration: InputDecoration(
              labelText: I18n.tr('course.field.name'),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _teacher,
            decoration: InputDecoration(
              labelText: I18n.tr('course.field.teacher'),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _location,
            decoration: InputDecoration(
              labelText: I18n.tr('course.field.location'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            I18n.tr('course.field.weekday'),
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: List.generate(7, (i) {
              final w = i + 1;
              return ChoiceChip(
                label: Text(_weekdayLabel(w)),
                selected: _weekday == w,
                onSelected: (_) => setState(() => _weekday = w),
              );
            }),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _numberPick(
                  label: I18n.tr('course.field.start_section'),
                  helper: settings.sectionTimeLabel(_startSection),
                  value: _startSection,
                  min: 1,
                  max: settings.sessionsPerDay,
                  onChange: (v) => setState(() => _startSection = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _numberPick(
                  label: I18n.tr('course.field.section_count'),
                  helper: settings.sectionTimeRangeLabel(
                    _startSection,
                    _sectionCount,
                  ),
                  value: _sectionCount,
                  min: 1,
                  max: (settings.sessionsPerDay - _startSection + 1).clamp(
                    1,
                    settings.sessionsPerDay,
                  ),
                  onChange: (v) => setState(() => _sectionCount = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _classWeeksHeader(settings),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: List.generate(settings.totalWeeks, (i) {
              final w = i + 1;
              final selected = _weeks.contains(w);
              return FilterChip(
                label: Text('$w'),
                selected: selected,
                showCheckmark: false,
                onSelected: (_) => setState(() {
                  if (selected) {
                    _weeks.remove(w);
                  } else {
                    _weeks.add(w);
                  }
                }),
              );
            }),
          ),
          const SizedBox(height: 14),
          Text(
            I18n.tr('course.field.color'),
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            children: _presetColors.map((v) {
              return GestureDetector(
                onTap: () => setState(() => _colorValue = v),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Color(v),
                    shape: BoxShape.circle,
                    border: v == _colorValue
                        ? Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.42),
                            width: 0.8,
                          )
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _classWeeksHeader(ScheduleSettings settings) {
    Widget action(String label, VoidCallback onPressed) {
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    }

    final label = Text(
      I18n.tr('course.field.class_weeks'),
      style: const TextStyle(fontSize: 13, color: Colors.grey),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final actions = Wrap(
      alignment: WrapAlignment.end,
      spacing: 4,
      runSpacing: 4,
      children: [
        action(
          I18n.tr('course.weeks.select_all'),
          () => setState(
            () => _weeks = List.generate(settings.totalWeeks, (i) => i + 1),
          ),
        ),
        action(
          I18n.tr('course.weeks.odd'),
          () => setState(
            () => _weeks = List.generate(
              settings.totalWeeks,
              (i) => i + 1,
            ).where((w) => w.isOdd).toList(),
          ),
        ),
        action(
          I18n.tr('course.weeks.even'),
          () => setState(
            () => _weeks = List.generate(
              settings.totalWeeks,
              (i) => i + 1,
            ).where((w) => w.isEven).toList(),
          ),
        ),
        action(I18n.tr('action.clear'), () => setState(() => _weeks = [])),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label,
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerLeft, child: actions),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: label),
            const SizedBox(width: 8),
            Flexible(
              flex: 2,
              child: Align(alignment: Alignment.centerRight, child: actions),
            ),
          ],
        );
      },
    );
  }

  Widget _numberPick({
    required String label,
    String? helper,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChange,
  }) {
    Widget stepButton(IconData icon, VoidCallback? onPressed) {
      return SizedBox.square(
        dimension: 28,
        child: IconButton(
          iconSize: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: const Size(28, 28),
          ),
          icon: Icon(icon),
          onPressed: onPressed,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (helper != null) ...[
            const SizedBox(height: 2),
            Text(
              helper,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          Row(
            children: [
              stepButton(
                Icons.remove,
                value > min ? () => onChange(value - 1) : null,
              ),
              Expanded(
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: DesignTokens.fontWeightStrong,
                  ),
                ),
              ),
              stepButton(
                Icons.add,
                value < max ? () => onChange(value + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _courseWeekLabel(int week) {
  return '${I18n.tr('course.week.prefix')}$week${I18n.tr('course.week.suffix')}';
}

String _weekdayLabel(int weekday) {
  final index = weekday.clamp(1, 7) - 1;
  return I18n.tr(_weekdayKeys[index]);
}
