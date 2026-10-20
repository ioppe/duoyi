import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('calendar project detail is a separate project action', () {
    final source = File('lib/screens/calendar_screen.dart').readAsStringSync();

    expect(source, contains("label: const Text('项目详情')"));
    expect(source, contains('Future<void> _showProjectDetail'));
    expect(source, contains('class _ProjectStat'));
    expect(source, contains("label: const Text('打开待办')"));
    expect(source, contains('const BrandRouteSurface(child: TodoScreen())'));

    expect(source, isNot(contains("title: '\${option.name} · 项目详情'")));
    expect(source, contains("title: '项目详情'"));
    expect(source, contains('subtitle: option.name'));
    expect(source, contains('scrollable: false'));
    expect(source, contains("'calendar_project_detail_scroll_region'"));
    expect(source, contains('ListView.separated('));
    expect(source, contains('primary: false'));
    expect(source, contains('itemCount: todos.length'));
    expect(source, isNot(contains('.take(8)')));
  });

  test('calendar detail area and paging are widened for dense views', () {
    final source = File('lib/screens/calendar_screen.dart').readAsStringSync();

    expect(source, contains('child: AppPageTabs('));
    expect(source, contains('height: AppPageTabs.heightFor(context)'));
    final tabs = File('lib/widgets/app_page_tabs.dart').readAsStringSync();
    expect(tabs, contains('isScrollable: true'));
    expect(tabs, contains('tabAlignment: TabAlignment.start'));
    expect(tabs, contains('DesignTokens.spaceMd'));
    expect(source, contains('fontSize: compact ? 12.5 : 13.5'));
    expect(source, contains("'calendar_navigation_date_button'"));
    expect(source, contains('height: compact ? 62 : 68'));
    expect(
      source,
      contains("key: const ValueKey('calendar_navigation_header_bar')"),
    );
    expect(source, contains('const Size(double.infinity, 56)'));
    expect(source, contains('const Size(0, 52)'));
    expect(source, contains('constraints.maxWidth < 390'));
    expect(
      source,
      contains("key: const ValueKey('calendar_month_detail_agenda')"),
    );
    expect(
      source,
      contains("key: const ValueKey('calendar_fixed_month_grid')"),
    );
    expect(source, contains('height: monthGridHeight'));
    expect(
      source,
      matches(
        RegExp(
          r'final preferredGridHeight = rows >= 6\s*\?\s*318\.0\s*:\s*\(rows == 5 \?\s*292\.0\s*:\s*268\.0\)',
          multiLine: true,
        ),
      ),
    );
    expect(
      source,
      matches(
        RegExp(
          r'final minGridHeight = rows >= 6\s*\?\s*288\.0\s*:\s*\(rows == 5 \?\s*260\.0\s*:\s*236\.0\)',
          multiLine: true,
        ),
      ),
    );
    expect(source, isNot(contains('if (availableHeight <= 120)')));
    expect(source, contains('final viewportTarget = availableHeight * 0.46'));
    expect(
      source,
      contains('viewportTarget.clamp(minGridHeight, preferredGridHeight)'),
    );
    expect(source, contains("'calendar_month_global_scrollbar'"));
    expect(source, contains("'calendar_month_global_scroll_view'"));
    expect(source, isNot(contains("'calendar_month_detail_scroll_region'")));
    final monthDetailStart = source.indexOf(
      "key: const ValueKey('calendar_month_detail_agenda')",
    );
    final weekViewStart = source.indexOf('// Week', monthDetailStart);
    expect(monthDetailStart, greaterThanOrEqualTo(0));
    expect(weekViewStart, greaterThan(monthDetailStart));
    final monthDetail = source.substring(monthDetailStart, weekViewStart);
    expect(monthDetail, contains('horizontalPadding:'));
    expect(monthDetail, contains('8,'));
    expect(monthDetail, contains('scrollable: false'));
    expect(monthDetail, contains('previewLimit: 8'));
    expect(source, isNot(contains('desiredDetailHeight')));
    expect(source, isNot(contains('maxGridForReadableDetail')));
    expect(source, contains('bool _monthGridShowsLunar('));
    expect(source, contains('maxWidth: 860'));
    expect(source, contains('MediaQuery.sizeOf(context).height * 0.68'));
    expect(source, contains('.clamp(360.0, 680.0)'));
    final agenda = File(
      'lib/widgets/calendar_day_agenda.dart',
    ).readAsStringSync();
    expect(agenda, contains('return Scrollbar('));
    expect(agenda, contains('final int? previewLimit'));
    expect(agenda, contains('final todoById = {'));
    expect(agenda, contains('events.take(previewLimit!'));
    expect(agenda, contains('class _AgendaOverflowNotice'));
    expect(
      agenda,
      contains("key: const ValueKey('calendar_day_agenda_inline_content')"),
    );
    expect(
      agenda,
      contains("key: const ValueKey('calendar_day_agenda_scroll_view')"),
    );
    expect(agenda, contains('primary: false'));
    expect(source, contains('width: constraints.maxWidth < 390'));
    expect(source, contains('? constraints.maxWidth'));
    expect(source, contains(': 380'));
    expect(source, contains('workspaceId: workspaceId'));
    expect(source, contains('CompletionVisibilityPolicy.visualState('));
    expect(source, contains('TodoVisualState.completed'));
    expect(source, contains('TodoVisualState.overdue'));
    expect(source, contains('Icons.priority_high_rounded'));
    expect(source, contains('TextDecoration.lineThrough'));
    expect(source, contains("isCompleted ? '已完成' : '逾期'"));
  });

  test('calendar exposes shared workspace filters', () {
    final source = File('lib/screens/calendar_screen.dart').readAsStringSync();
    final model = File('lib/models/calendar_event.dart').readAsStringSync();
    final provider = File(
      'lib/providers/calendar_provider.dart',
    ).readAsStringSync();
    final aggregator = File(
      'lib/core/calendar_aggregator.dart',
    ).readAsStringSync();

    expect(model, contains('final String? workspaceId;'));
    expect(aggregator, contains('workspaceId: t.workspaceId'));
    expect(provider, contains('String? workspaceId'));
    expect(provider, contains('bool _matchesWorkspace('));
    expect(source, contains("label: const Text('全部空间')"));
    expect(
      source,
      contains('List<_CalendarWorkspaceOption> _workspaceOptions('),
    );
    expect(source, contains('workspaceId: effectiveWorkspaceId'));
    expect(source, contains('class _CalendarWorkspaceOption'));
  });
}
