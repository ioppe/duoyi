import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/global_search.dart';
import '../core/i18n.dart';
import '../providers/anniversary_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/countdown_provider.dart';
import '../providers/course_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/note_provider.dart';
import '../providers/time_audit_provider.dart';
import '../providers/todo_provider.dart';
import '../widgets/brand_background.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';
import 'anniversary_screen.dart';
import 'calendar_screen.dart';
import 'countdown_screen.dart';
import 'course_schedule_screen.dart';
import 'goal_screen.dart';
import 'habit_screen.dart';
import 'note_screen.dart';
import 'time_audit_screen.dart';
import 'todo_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<SearchHit> _hits = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_syncControllerState);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_syncControllerState);
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _syncControllerState() {
    if (mounted) setState(() {});
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      final q = v.trim();
      if (!mounted) return;
      if (q.isEmpty) {
        setState(() {
          _hits = [];
          _query = '';
        });
        return;
      }
      final hits = GlobalSearch.run(
        query: q,
        todos: context.read<TodoProvider>().todos,
        habits: context.read<HabitProvider>().habits,
        notes: context.read<NoteProvider>().notes,
        anniversaries: context.read<AnniversaryProvider>().items,
        countdowns: context.read<CountdownProvider>().items,
        goals: context.read<GoalProvider>().goals,
        courses: context.read<CourseProvider>().courses,
        calendarEvents: context.read<CalendarProvider>().events,
        timeEntries: context.read<TimeAuditProvider>().entries,
      );
      setState(() {
        _hits = hits;
        _query = q;
      });
    });
  }

  void _open(SearchHit h) {
    switch (h.kind) {
      case SearchKind.todo:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                BrandRouteSurface(child: TodoDetailScreen(todoId: h.sourceId)),
          ),
        );
        break;
      case SearchKind.habit:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const BrandRouteSurface(child: HabitScreen()),
          ),
        );
        break;
      case SearchKind.note:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const BrandRouteSurface(child: NoteScreen()),
          ),
        );
        break;
      case SearchKind.anniversary:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BrandRouteSurface(
              child: AnniversaryScreen(initialAnniversaryId: h.sourceId),
            ),
          ),
        );
        break;
      case SearchKind.countdown:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BrandRouteSurface(
              child: CountdownScreen(initialCountdownId: h.sourceId),
            ),
          ),
        );
        break;
      case SearchKind.goal:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const BrandRouteSurface(child: GoalScreen()),
          ),
        );
        break;
      case SearchKind.course:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const BrandRouteSurface(child: CourseScheduleScreen()),
          ),
        );
        break;
      case SearchKind.calendarEvent:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                BrandRouteSurface(child: CalendarScreen(initialDate: h.when)),
          ),
        );
        break;
      case SearchKind.timeEntry:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const BrandRouteSurface(child: TimeAuditScreen()),
          ),
        );
        break;
    }
  }

  Widget _highlight(String text, String q) {
    if (q.isEmpty) return Text(text);
    final lower = text.toLowerCase();
    final qLower = q.toLowerCase();
    final idx = lower.indexOf(qLower);
    if (idx < 0) return Text(text);
    final end = idx + q.length;
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, end),
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.normal,
            ),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
    );
  }

  Widget _resultCard(SearchHit h) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      onTap: () => _open(h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(h.icon, size: 20, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
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
                        h.kindLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.normal,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (h.when != null)
                      Text(
                        '${h.when!.month}/${h.when!.day}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.52),
                          fontWeight: FontWeight.normal,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                DefaultTextStyle(
                  style: theme.textTheme.bodyMedium!.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.normal,
                    color: cs.onSurface,
                    height: 1.25,
                  ),
                  child: _highlight(h.title, _query),
                ),
                if (h.subtitle != null && h.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  DefaultTextStyle(
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.64),
                      height: 1.35,
                    ),
                    child: _highlight(h.subtitle!, _query),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final routeBackground = theme.brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: I18n.tr('search.hint'),
          ),
          onChanged: _onChanged,
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: I18n.tr('search.clear'),
              onPressed: () {
                _ctrl.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: AppSecondaryControlTheme(
        child: _query.isEmpty
            ? EmptyState(icon: Icons.search, message: I18n.tr('search.empty'))
            : _hits.isEmpty
            ? EmptyState(
                icon: Icons.sentiment_dissatisfied,
                message:
                    '${I18n.tr('search.no_results.prefix')}"$_query"${I18n.tr('search.no_results.suffix')}',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                children: [
                  AppSurfaceCard(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(Icons.search, color: cs.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                I18n.tr('search.results.title'),
                                style: appSecondaryMenuItemTextStyle(context)
                                    .copyWith(
                                      fontSize: 13,
                                      fontWeight: FontWeight.normal,
                                      color: cs.onSurface,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${I18n.tr('search.results.summary_prefix')}$_query${I18n.tr('search.results.summary_middle')}${_hits.length}${I18n.tr('search.results.summary_suffix')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.66),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: I18n.tr('search.clear'),
                          onPressed: () {
                            _ctrl.clear();
                            _onChanged('');
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._hits.map(_resultCard),
                ],
              ),
      ),
    );
  }
}
