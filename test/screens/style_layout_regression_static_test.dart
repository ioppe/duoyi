import 'dart:io';

import 'package:test/test.dart';

void main() {
  const scopedScreens = [
    'lib/screens/admin_screen.dart',
    'lib/screens/preferences_screen.dart',
    'lib/screens/more_apps_screen.dart',
    'lib/screens/integrations_screen.dart',
    'lib/screens/calendar_screen.dart',
    'lib/screens/ai_schedule_screen.dart',
    'lib/screens/feedback_screen.dart',
    'lib/screens/notification_history_screen.dart',
    'lib/screens/search_screen.dart',
    'lib/screens/share_screen.dart',
    'lib/screens/profile_screen.dart',
    'lib/screens/widget_screen.dart',
    'lib/screens/anniversary_screen.dart',
    'lib/screens/countdown_screen.dart',
    'lib/screens/goal_edit_screen.dart',
  ];

  test('二级页面使用共享粗体且避免大标题和厚边框回退', () {
    for (final path in scopedScreens) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(matches(RegExp(r'FontWeight\.(normal|w[1-6]00)'))),
        reason:
            '$path should inherit rounded bold typography or use the shared token',
      );
      expect(
        source,
        isNot(matches(RegExp(r'fontSize:\s*(?:19|[2-9]\d)'))),
        reason: '$path should not introduce large secondary-page titles',
      );
    }

    for (final path in [
      ...scopedScreens,
      'lib/widgets/surface_components.dart',
    ]) {
      final source = File(path).readAsStringSync();
      for (final call in [
        ..._calls(source, 'Border.all('),
        ..._calls(source, 'BorderSide('),
      ]) {
        final width = RegExp(
          r'width:\s*([0-9]+(?:\.[0-9]+)?)',
        ).firstMatch(call);
        final sharedInputWidth = RegExp(
          r'OutlineInputBorder inputBorder\(Color color, \{double width = ([0-9]+(?:\.[0-9]+)?)\}\)',
        ).firstMatch(source);
        final usesSharedInputWidth =
            call.contains('width: width') &&
            sharedInputWidth != null &&
            double.parse(sharedInputWidth.group(1)!) <= 0.5;
        expect(
          width != null || usesSharedInputWidth,
          isTrue,
          reason: '$path uses default 1px border:\n$call',
        );
        if (width != null) {
          expect(
            double.parse(width.group(1)!),
            lessThanOrEqualTo(0.6),
            reason: '$path uses a thick border:\n$call',
          );
        }
      }
    }
  });

  test('全局二级控件选中态和卡片边框保持轻量可读', () {
    final source = File(
      'lib/widgets/surface_components.dart',
    ).readAsStringSync();

    final surfaceCard = source.substring(
      source.indexOf('final surfaceColor'),
      source.indexOf('final content = Ink('),
    );
    expect(surfaceCard, contains('final cardBorderColor'));
    expect(surfaceCard, contains('DesignTokens.defaultBorder'));
    expect(surfaceCard, contains('width: 0.55'));
    expect(surfaceCard, contains('elevation <= 0'));
    expect(
      surfaceCard,
      isNot(contains('Colors.black.withValues(alpha: 0.05)')),
    );
    expect(surfaceCard, contains('final surfaceColor = color ?? cs.surface'));

    final controls = source.substring(
      source.indexOf('class AppSecondaryControlTheme'),
      source.indexOf('class AppSecondaryMenuText'),
    );
    expect(
      controls,
      contains(
        'OutlineInputBorder inputBorder(Color color, {double width = 0.35})',
      ),
    );
    expect(controls, contains('alpha: isDark ? 0.12 : 0.16'));
    expect(controls, contains('Color.alphaBlend('));
    expect(controls, contains('alpha: isDark ? 0.14 : 0.09'));
    expect(
      controls,
      contains('cs.primary.withValues(alpha: isDark ? 0.34 : 0.30)'),
    );
    expect(controls, contains('BorderSide(color: color, width: 0.4)'));
    expect(controls, contains('side: BorderSide(color: subtleBorder'));

    final selectedForeground = source.substring(
      source.indexOf('final selectedControlForeground'),
      source.indexOf('final selectedControlIcon'),
    );
    expect(selectedForeground, contains('selectedControlRenderedBackground'));
    expect(selectedForeground, contains('cs.onSurface'));
    expect(selectedForeground, isNot(contains('Colors.white')));
    expect(
      controls,
      isNot(
        contains('alpha: theme.brightness == Brightness.dark ? 0.22 : 0.12'),
      ),
    );

    final calendar = File(
      'lib/screens/calendar_screen.dart',
    ).readAsStringSync();
    final yearOverview = calendar.substring(
      calendar.indexOf('class _CalendarYearOverview'),
      calendar.indexOf('class _MonthDot'),
    );
    expect(yearOverview, contains('final selectedFill = Color.alphaBlend('));
    expect(yearOverview, contains('final selectedText = cs.onSurface'));
    expect(yearOverview, isNot(contains('cs.primaryContainer')));
    expect(yearOverview, isNot(contains('cs.onPrimaryContainer')));

    final goalEdit = File(
      'lib/screens/goal_edit_screen.dart',
    ).readAsStringSync();
    expect(goalEdit, contains('width: 0.45'));
    expect(goalEdit, isNot(matches(RegExp(r'width:\s*2(?:\.0)?\b'))));
    expect(goalEdit, isNot(contains('width: isSelected ? 1.6 : 1')));
  });

  test('管理后台分页条在窄屏保持全宽分组布局', () {
    final admin = File('lib/screens/admin_screen.dart').readAsStringSync();
    final pagination = admin.substring(
      admin.indexOf('class _AdminPaginationBar'),
      admin.indexOf('class _AdminPaginationLabeledControl'),
    );

    expect(
      pagination,
      contains("key: const ValueKey('admin_compact_pagination_full_width')"),
    );
    expect(
      pagination,
      contains('crossAxisAlignment: CrossAxisAlignment.stretch'),
    );
    expect(pagination, contains('WrapAlignment.spaceBetween'));
    expect(
      pagination,
      contains('return SizedBox(\n              width: double.infinity,'),
    );
    final compactControls = pagination.substring(
      pagination.indexOf("ValueKey('admin_compact_pagination_controls')"),
      pagination.indexOf('if (isCompact)'),
    );
    expect(compactControls, contains('?pageJump'));
    expect(compactControls, contains('?pageSizePicker'));
    expect(
      compactControls,
      contains("Tooltip(message: '分页导航', child: navigation())"),
    );
    expect(
      pagination,
      isNot(contains('BoxConstraints(maxWidth: 960)')),
      reason:
          'Desktop pagination must not collapse into a centered 960px strip.',
    );
    expect(
      pagination,
      isNot(contains("ValueKey('admin_compact_pagination_horizontal')")),
      reason: 'Compact pagination should not be a narrow horizontal strip.',
    );

    final primaryTabBar = admin.substring(
      admin.indexOf('bottom: AppPageTabs('),
      admin.indexOf('tabs: const [', admin.indexOf('bottom: AppPageTabs(')),
    );
    expect(primaryTabBar, contains('height: AppPageTabs.heightFor(context)'));
    expect(primaryTabBar, isNot(contains('labelColor:')));
    expect(primaryTabBar, isNot(contains('indicator: BoxDecoration')));
  });

  test('管理后台筛选控件不因低高度退回固定窄宽', () {
    final admin = File('lib/screens/admin_screen.dart').readAsStringSync();

    expect(
      admin,
      isNot(contains('constraints.maxWidth < 700 || constraints.maxHeight')),
      reason:
          'Admin filter compactness should be width-driven, not low-height.',
    );
    expect(
      admin,
      isNot(contains('width: compactAdminFilters ? 280 : double.infinity')),
    );
    expect(admin, isNot(contains('constraints.maxHeight < 520')));
    expect(admin, isNot(contains('SizedBox(width: 260, child: sortField)')));
  });

  test('管理后台弹窗内容不使用固定大宽度挤压窄屏', () {
    final admin = File('lib/screens/admin_screen.dart').readAsStringSync();

    expect(
      admin,
      isNot(matches(RegExp(r'SizedBox\(\s*width:\s*(?:400|420|430)'))),
      reason:
          'Admin dialogs should let AppDialog clamp content to the viewport.',
    );
    expect(admin, contains('BoxConstraints(maxWidth: 430)'));
    expect(admin, contains('BoxConstraints(maxWidth: 420)'));
    expect(admin, contains('BoxConstraints(maxWidth: 400)'));
  });

  test('反馈记录分页和标题保持紧凑且不挤压文本区域', () {
    final feedback = File(
      'lib/screens/feedback_screen.dart',
    ).readAsStringSync();
    final sectionStart = feedback.indexOf("title: '反馈记录'");
    final sectionEnd = feedback.indexOf('Text(', sectionStart + 1);
    expect(sectionStart, greaterThanOrEqualTo(0));
    expect(sectionEnd, greaterThan(sectionStart));
    final sectionHeader = feedback.substring(sectionStart, sectionEnd);

    expect(
      sectionHeader,
      isNot(contains('Theme.of(context).textTheme.titleMedium')),
      reason:
          'Feedback records title should use the shared compact section style.',
    );

    final pagination = feedback.substring(
      feedback.indexOf('class _FeedbackPagination'),
      feedback.indexOf('String normalizeFeedbackCategory'),
    );
    expect(pagination, contains('LayoutBuilder('));
    expect(pagination, contains('constraints.maxWidth < 360'));
    expect(pagination, contains('Column('));
    expect(pagination, contains('Row(children: controls)'));
    expect(pagination, contains('appSecondaryControlLabelStyle(context)'));
    expect(
      pagination,
      isNot(contains('padding: const EdgeInsets.symmetric(horizontal: 12)')),
      reason:
          'Narrow feedback pagination should not reserve a fixed wide center label.',
    );
  });

  test('局部选中态不绕过可读前景色规则', () {
    final reminderPlan = File(
      'lib/widgets/reminder_plan_editor.dart',
    ).readAsStringSync();
    final selectedHelpers = reminderPlan.substring(
      reminderPlan.indexOf('ButtonStyle _selectedSegmentStyle'),
      reminderPlan.indexOf('IconData _ruleIcon'),
    );
    expect(selectedHelpers, contains('_readableForeground('));
    expect(selectedHelpers, contains('final selectedForeground'));
    expect(
      selectedHelpers,
      isNot(contains('return Theme.of(context).colorScheme.primary;')),
    );
    expect(selectedHelpers, isNot(contains('return cs.primary;')));

    final course = File(
      'lib/screens/course_schedule_screen.dart',
    ).readAsStringSync();
    final weekPicker = course.substring(
      course.indexOf('void _pickWeek'),
      course.indexOf('String _courseWeekLabel'),
    );
    expect(
      weekPicker,
      contains('foregroundColor: selected ? cs.onSurface : null'),
    );
    expect(
      weekPicker,
      isNot(contains('foregroundColor: selected ? cs.primary')),
    );

    final eventSheet = File(
      'lib/widgets/calendar_event_sheet.dart',
    ).readAsStringSync();
    final colorChoice = eventSheet.substring(
      eventSheet.indexOf('class _ColorChoice'),
      eventSheet.indexOf('const _localEventColors'),
    );
    expect(colorChoice, contains('color.computeLuminance()'));
    expect(
      colorChoice,
      isNot(contains('const Icon(Icons.check, color: Colors.white')),
    );
  });

  test('任务语义图标与新建任务入口保持一致', () {
    final quick = File('lib/widgets/quick_capture_fab.dart').readAsStringSync();
    final quickTodo = quick.substring(
      quick.indexOf("label: I18n.tr('quick.menu.todo')") - 120,
      quick.indexOf("label: I18n.tr('quick.menu.todo')") + 120,
    );
    expect(quickTodo, contains('icon: Icons.check_circle_outline'));

    final today = File('lib/screens/today_screen.dart').readAsStringSync();
    final todayTodo = today.substring(
      today.indexOf('label: s.navTodo'),
      today.indexOf('label: s.navHabit'),
    );
    expect(todayTodo, contains('icon: Icons.check_circle_outline'));

    final todo = File('lib/screens/todo_screen.dart').readAsStringSync();
    final summary = todo.substring(
      todo.indexOf("icon: Icons.check_circle_outline"),
      todo.indexOf("label: '重点'"),
    );
    expect(summary, contains('icon: Icons.check_circle_outline'));

    final completionMenu = todo.substring(
      todo.indexOf('_TodoFilterMenu<TodoCompletionFilter>('),
      todo.indexOf('selected: filter.completion != TodoCompletionFilter.all'),
    );
    expect(completionMenu, contains('icon: Icons.check_circle_outline'));
  });

  test('管理后台备份记录列表独立滚动且分页固定在记录区底部', () {
    final admin = File('lib/screens/admin_screen.dart').readAsStringSync();
    final backupTab = admin.substring(
      admin.indexOf('class _BackupSettingsTab'),
      admin.indexOf(
        '// ====================================================================\n// 用户',
      ),
    );

    expect(backupTab, contains("ValueKey('admin_backup_record_tabs')"));
    expect(backupTab, contains("ValueKey('admin_backup_server_records')"));
    expect(backupTab, contains("ValueKey('admin_backup_user_records')"));
    expect(backupTab, contains("ValueKey('admin_backup_server_pagination')"));
    expect(backupTab, contains("ValueKey('admin_backup_user_pagination')"));
    expect(backupTab, contains('ListView.builder('));
    expect(
      backupTab,
      contains('height: 640'),
      reason: 'Backup records need a stable viewport instead of a narrow tail.',
    );

    final buildMethod = backupTab.substring(
      backupTab.indexOf('Widget build(BuildContext context)'),
    );
    expect(
      buildMethod,
      isNot(contains("title: '服务器备份记录'")),
      reason:
          'Backup records should be rendered by dedicated panels, not appended to the outer settings ListView.',
    );
    expect(
      buildMethod,
      contains('_buildBackupRecordTabs('),
      reason:
          'The outer settings ListView should only host the record viewport.',
    );
  });

  test('更多应用与日历弹层不会回退到黑屏或原生大面板', () {
    final moreApps = File(
      'lib/screens/more_apps_screen.dart',
    ).readAsStringSync();
    expect(moreApps, contains('final routeBackground'));
    expect(moreApps, contains('backgroundColor: routeBackground'));
    expect(
      moreApps,
      contains('titleTextStyle: appSecondaryRouteTitleTextStyle(context)'),
    );
    expect(moreApps, contains('body: ColoredBox('));
    expect(moreApps, contains('SafeArea('));
    expect(
      moreApps.substring(moreApps.indexOf('class MoreApplicationButton')),
      isNot(contains('return Scaffold(')),
    );
    expect(
      moreApps.substring(moreApps.indexOf('class MoreApplicationButton')),
      contains('BrandRouteSurface('),
      reason:
          'Standalone hidden app fallback needs a route backing surface for transparent pages.',
    );
    expect(moreApps, isNot(contains('backgroundColor: Colors.transparent')));

    final brandBackground = File(
      'lib/widgets/brand_background.dart',
    ).readAsStringSync();
    final routeSurface = brandBackground.substring(
      brandBackground.indexOf('class BrandRouteSurface'),
      brandBackground.indexOf('class BrandScaffold'),
    );
    expect(routeSurface, contains('final routeBackground'));
    expect(routeSurface, contains('color: routeBackground'));
    // 子树经 locale 键控的 KeyedSubtree 挂载：语言热切换时强制重挂 const 子页，
    // 文案即时跟随（详见 BrandRouteSurface 内注释）。
    expect(routeSurface, contains('AppSecondaryControlTheme('));
    expect(routeSurface, contains('I18n.localeListenable'));
    expect(routeSurface, contains('ValueKey<AppLocale>(locale)'));
    expect(
      routeSurface,
      contains(
        'child: BrandBackground(\n            child: AppSecondaryControlTheme(',
      ),
      reason: '跳转页统一套二级控件字号，避免从我的/更多应用进入后字号偏大。',
    );
    final brandScaffold = brandBackground.substring(
      brandBackground.indexOf('class BrandScaffold'),
    );
    expect(brandScaffold, contains('final routeBackground'));
    expect(brandScaffold, contains('ColoredBox('));
    expect(
      brandScaffold,
      contains('color: paintBackground ? routeBackground : Colors.transparent'),
    );
    expect(brandScaffold, contains('final bool paintBackground'));
    expect(brandScaffold, contains('this.paintBackground = true'));
    expect(
      brandScaffold,
      contains('paintBackground ? BrandBackground(child: scaffold) : scaffold'),
      reason: '主导航 shell 已经绘制品牌背景，tab 内 BrandScaffold 需要可关闭内层背景以避免重复解码和重绘。',
    );

    final surfaceComponents = File(
      'lib/widgets/surface_components.dart',
    ).readAsStringSync();
    final modalSheet = surfaceComponents.substring(
      surfaceComponents.indexOf('Future<T?> showAppModalSheet<T>'),
      surfaceComponents.indexOf('class AppDialog'),
    );
    expect(modalSheet, contains('requestFocus: false'));
    expect(modalSheet, isNot(contains('requestFocus: false ||')));
    expect(
      surfaceComponents,
      contains('TextStyle appSecondaryRouteTitleTextStyle'),
    );
    expect(surfaceComponents, contains('fontSize: DesignTokens.fontSizeMd'));
    expect(
      surfaceComponents,
      contains('fontWeight: DesignTokens.fontWeightStrong'),
    );

    final calendar = File(
      'lib/screens/calendar_screen.dart',
    ).readAsStringSync();
    final quickMenu = calendar.substring(
      calendar.indexOf('void _showQuickAddMenu'),
      calendar.indexOf('Future<void> _showQuickAddTimeEntry'),
    );
    expect(quickMenu, contains('showAppModalSheet<void>('));
    expect(quickMenu, contains('AppModalSheet('));
    expect(quickMenu, isNot(contains('showModalBottomSheet')));
    expect(quickMenu, contains('BrandRouteSurface('));
    expect(
      quickMenu,
      contains('child: AiScheduleScreen(initialDate: _selectedDay)'),
    );

    final todo = File('lib/screens/todo_screen.dart').readAsStringSync();
    final kanbanSettings = todo.substring(
      todo.indexOf('Future<void> _showKanbanSettings'),
      todo.indexOf('Future<void> _deleteSelected'),
    );
    expect(
      kanbanSettings,
      contains('showAppModalSheet<TodoKanbanBoardConfig>('),
    );
    expect(kanbanSettings, isNot(contains('showModalBottomSheet')));
    final kanbanSheet = todo.substring(
      todo.indexOf('class _KanbanSettingsSheet'),
      todo.indexOf('Color _quadrantColor'),
    );
    expect(kanbanSheet, contains('AppModalSheet('));
    expect(kanbanSheet, contains('appSecondaryFilledButtonStyle(context)'));
    expect(kanbanSheet, isNot(contains('return SafeArea(')));
    expect(kanbanSheet, isNot(contains('textTheme.titleMedium')));

    final note = File('lib/screens/note_screen.dart').readAsStringSync();
    final attachmentPicker = note.substring(
      note.indexOf('Future<void> _addAttachment'),
      note.indexOf('if (source == null) return;'),
    );
    expect(attachmentPicker, contains('showAppModalSheet<_AttachmentSource>('));
    expect(attachmentPicker, contains('AppModalSheet('));
    expect(attachmentPicker, contains('AppSettingsTile('));
    expect(attachmentPicker, isNot(contains('showModalBottomSheet')));
    expect(attachmentPicker, isNot(contains('ListTile(')));

    final projectDetail = calendar.substring(
      calendar.indexOf('Future<void> _showProjectDetail'),
      calendar.indexOf('void _showQuickAddMenu'),
    );
    expect(projectDetail, contains('scrollable: false'));
    expect(projectDetail, contains("'calendar_project_detail_scroll_region'"));
    expect(projectDetail, contains('ListView.separated('));
    expect(projectDetail, contains('itemCount: todos.length'));
    expect(projectDetail, isNot(contains('.take(8)')));

    final habit = File('lib/screens/habit_screen.dart').readAsStringSync();
    expect(habit, contains('final routeBackground'));
    expect(habit, contains('backgroundColor: routeBackground'));
    expect(habit, contains('AppPageTabs('));
    expect(habit, contains('height: AppPageTabs.heightFor(context)'));
    expect(habit, isNot(contains('backgroundColor: Colors.transparent')));

    final preferences = File(
      'lib/screens/preferences_screen.dart',
    ).readAsStringSync();
    expect(preferences, contains('final routeBackground'));
    expect(preferences, contains('backgroundColor: routeBackground'));
    expect(
      RegExp(
        r'titleTextStyle:\s*appSecondaryRouteTitleTextStyle\(context\)',
      ).allMatches(preferences).length,
      greaterThanOrEqualTo(3),
      reason: '个性设置入口、显示与行为、底部导航设置都要使用二级页标题样式',
    );
    expect(preferences, isNot(contains('backgroundColor: Colors.transparent')));

    final mine = File('lib/screens/mine_screen.dart').readAsStringSync();
    expect(mine, contains('final bool useShellBackground'));
    expect(mine, contains('final routeBackground'));
    expect(mine, contains('final scaffoldBackground = useShellBackground'));
    expect(mine, contains('backgroundColor: scaffoldBackground'));
    expect(mine, contains('final toolbarBackground = useShellBackground'));
    expect(mine, contains('appBar: AppBar('));
    expect(mine, contains('backgroundColor: toolbarBackground'));
    expect(mine, contains('title: Text(s.mineTitle)'));
    expect(mine, isNot(contains('final mineToolbar = Padding(')));
    expect(mine, contains('void _openBrandedRoute'));
    expect(mine, contains('BrandRouteSurface(child: child)'));
    for (final rawRoute in [
      'builder: (_) => const SearchScreen()',
      'builder: (_) => const GoalScreen()',
      'builder: (_) => const PomodoroScreen()',
      'builder: (_) => const CourseScheduleScreen()',
      'builder: (_) => const AchievementsScreen()',
      'builder: (_) => const NotificationSettingsScreen()',
      'builder: (_) => FeedbackScreen(initialCategory: category)',
    ]) {
      expect(
        mine,
        isNot(contains(rawRoute)),
        reason:
            'Mine secondary routes need BrandRouteSurface to avoid black backing.',
      );
    }
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('useShellBackground: true'));

    for (final path in [
      'lib/screens/ai_schedule_screen.dart',
      'lib/screens/feedback_screen.dart',
      'lib/screens/notification_history_screen.dart',
      'lib/screens/search_screen.dart',
      'lib/screens/share_screen.dart',
      'lib/screens/integrations_screen.dart',
      'lib/screens/profile_screen.dart',
      'lib/screens/diary_screen.dart',
      'lib/screens/widget_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('final routeBackground'), reason: path);
      expect(
        source,
        contains('backgroundColor: routeBackground'),
        reason: path,
      );
      expect(
        source,
        contains('surfaceTintColor: Colors.transparent'),
        reason: path,
      );
      if (path == 'lib/screens/profile_screen.dart') {
        expect(
          source,
          contains('final routeBackground = Colors.transparent;'),
          reason: path,
        );
      } else {
        expect(
          source,
          isNot(contains('backgroundColor: Colors.transparent')),
          reason: path,
        );
      }
    }

    final notificationHistory = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();
    final reminderKindSelector = notificationHistory.substring(
      notificationHistory.indexOf('class _ReminderKindSelector'),
      notificationHistory.indexOf('String _kindLabel'),
    );
    expect(reminderKindSelector, contains('return cs.onSurface;'));
    expect(
      reminderKindSelector,
      contains('cs.primary.withValues(alpha: 0.12)'),
    );
    expect(reminderKindSelector, isNot(contains('return cs.onPrimary;')));
    expect(reminderKindSelector, isNot(contains('alpha: 0.82')));

    final weekStrip = File(
      'lib/widgets/calendar_week_strip.dart',
    ).readAsStringSync();
    final monthGrid = File(
      'lib/widgets/calendar_month_grid.dart',
    ).readAsStringSync();
    for (final source in [weekStrip, monthGrid]) {
      expect(source, contains('final selectedBackground = Color.alphaBlend('));
      expect(source, contains('final selectedForeground = cs.onSurface'));
      expect(source, contains('cs.primary.withValues('));
      expect(source, contains('Border.all('));
      expect(source, contains('button: true'));
      expect(source, contains('selected: isSelected'));
      expect(source, isNot(contains('? cs.onPrimary')));
      expect(
        source,
        isNot(
          contains(
            'color: isSelected\n                                        ? cs.onPrimary',
          ),
        ),
      );
    }
    expect(weekStrip, contains('d.year == selectedDay.year'));
    expect(weekStrip, contains('d.year == today.year'));
    expect(monthGrid, contains('final selectedDotColor = cs.onSurface'));
    expect(monthGrid, isNot(contains('? Colors.white')));
    expect(monthGrid, isNot(contains('? Colors.white70')));
    expect(monthGrid, isNot(contains('? Colors.white60')));
    expect(monthGrid, isNot(contains('? Colors.white54')));

    expect(calendar, contains('child: AppPageTabs('));
    expect(calendar, contains('Color.alphaBlend('));
    expect(calendar, isNot(contains('labelColor: cs.onPrimaryContainer')));
    expect(calendar, isNot(contains('foregroundColor: cs.onPrimaryContainer')));

    final almanac = File('lib/screens/almanac_screen.dart').readAsStringSync();
    expect(almanac, contains("import '../widgets/surface_components.dart';"));
    expect(almanac, contains('final routeBackground'));
    expect(almanac, contains('backgroundColor: routeBackground'));
    expect(
      almanac,
      contains('titleTextStyle: appSecondaryRouteTitleTextStyle(context)'),
    );
    expect(
      almanac,
      contains('backgroundColor: routeBackground.withValues(alpha: 0.96)'),
    );
    expect(almanac, contains('surfaceTintColor: Colors.transparent'));
    expect(almanac, contains('body: ColoredBox('));
    expect(almanac, contains('color: routeBackground.withValues(alpha: 0.92)'));
    expect(
      almanac,
      contains('22 + MediaQuery.paddingOf(context).bottom'),
      reason: '万年历主页面底部滚动 padding 需要避开 Android 手势区。',
    );
    expect(almanac, isNot(contains('backgroundColor: Colors.transparent')));
    expect(almanac, isNot(contains('return BrandScaffold(')));

    final appDatePicker = File(
      'lib/widgets/app_date_picker.dart',
    ).readAsStringSync();
    final solarDayCell = appDatePicker.substring(
      appDatePicker.indexOf('class _SolarDayCell'),
      appDatePicker.indexOf('class _LunarPicker'),
    );
    expect(solarDayCell, contains('final selectedFill = Color.alphaBlend('));
    expect(solarDayCell, contains('? selectedFill'));
    expect(solarDayCell, contains('? cs.onSurface'));
    expect(solarDayCell, contains('color: cs.primary.withValues(alpha: 0.26)'));
    expect(solarDayCell, isNot(contains('? cs.onPrimary')));
    expect(almanac, contains('final selectedFill = Color.alphaBlend('));
    expect(almanac, contains('final selectedText = cs.onSurface'));
    expect(almanac, isNot(contains('? cs.onPrimary')));
    expect(almanac, isNot(contains('cs.onPrimary.withValues')));
  });

  test('二级页面沿用全局正文、辅助文字和标题层级', () {
    final mine = File('lib/screens/mine_screen.dart').readAsStringSync();
    final surfaceComponents = File(
      'lib/widgets/surface_components.dart',
    ).readAsStringSync();
    final brandBackground = File(
      'lib/widgets/brand_background.dart',
    ).readAsStringSync();
    final moreApps = File(
      'lib/screens/more_apps_screen.dart',
    ).readAsStringSync();

    final nameTextIndex = mine.indexOf('nameText,');
    expect(nameTextIndex, greaterThanOrEqualTo(0));
    final nameTextStart = mine.lastIndexOf('Text(', nameTextIndex);
    expect(nameTextStart, greaterThanOrEqualTo(0));
    final metadataIndex = mine.indexOf('_MineHeaderMetadata(', nameTextIndex);
    expect(metadataIndex, greaterThan(nameTextIndex));
    final mineProfileHeader = mine.substring(nameTextStart, metadataIndex);
    final mainRegularSize = _requiredFontSize(mineProfileHeader);
    expect(mainRegularSize, equals(14));

    final controlText = surfaceComponents.substring(
      surfaceComponents.indexOf('TextStyle appSecondaryControlTextStyle'),
      surfaceComponents.indexOf('TextStyle appSecondaryControlLabelStyle'),
    );
    final menuText = surfaceComponents.substring(
      surfaceComponents.indexOf('TextStyle appSecondaryMenuItemTextStyle'),
      surfaceComponents.indexOf('TextStyle appSecondaryRouteTitleTextStyle'),
    );
    final routeTitle = surfaceComponents.substring(
      surfaceComponents.indexOf('TextStyle appSecondaryRouteTitleTextStyle'),
      surfaceComponents.indexOf('Color _appSecondaryActionBackground'),
    );

    expect(controlText, contains('fontSize: DesignTokens.fontSizeBody'));
    expect(menuText, contains('fontSize: DesignTokens.fontSizeBody'));
    expect(routeTitle, contains('fontSize: DesignTokens.fontSizePageTitle'));
    expect(controlText, contains('fontWeight: DesignTokens.fontWeightRegular'));
    expect(menuText, contains('fontWeight: DesignTokens.fontWeightMedium'));
    expect(routeTitle, contains('fontWeight: DesignTokens.fontWeightStrong'));

    final secondaryTheme = surfaceComponents.substring(
      surfaceComponents.indexOf('class AppSecondaryControlTheme'),
      surfaceComponents.indexOf('class AppSecondaryMenuText'),
    );
    for (final textRole in [
      'titleMedium',
      'titleSmall',
      'bodyLarge',
      'bodyMedium',
    ]) {
      expect(
        secondaryTheme,
        contains('$textRole: controlText.copyWith'),
        reason: '$textRole should inherit compact secondary route text.',
      );
    }
    for (final textRole in ['bodySmall', 'labelLarge', 'labelMedium']) {
      expect(
        secondaryTheme,
        contains('$textRole: labelText.copyWith'),
        reason: '$textRole should inherit smaller secondary label text.',
      );
    }

    final routeSurface = brandBackground.substring(
      brandBackground.indexOf('class BrandRouteSurface'),
      brandBackground.indexOf('/// A scaffold'),
    );
    expect(
      routeSurface,
      contains(
        'child: BrandBackground(\n            child: AppSecondaryControlTheme(',
      ),
      reason:
          'Pushed routes must inherit the compact secondary text scale before painting their page content.',
    );

    final moreApplicationButton = moreApps.substring(
      moreApps.indexOf('class MoreApplicationButton'),
    );
    expect(moreApplicationButton, contains('BrandRouteSurface('));
    expect(
      moreApplicationButton,
      isNot(contains('builder: (_) => app.builder(')),
      reason:
          'More-app fallbacks should not bypass the compact route surface when pushed.',
    );
  });

  test('下拉菜单先收起键盘再按安全区域重算弹出位置', () {
    final source = File(
      'lib/widgets/surface_components.dart',
    ).readAsStringSync();
    final keyboardGuard = source.substring(
      source.indexOf('Future<void> _hideKeyboardBeforePicker'),
      source.indexOf('Future<T?> _showAnchoredDropdownMenu<T>'),
    );
    expect(
      keyboardGuard,
      contains('FocusScope.of(context, createDependency: false).unfocus()'),
    );
    expect(
      keyboardGuard,
      contains('FocusManager.instance.primaryFocus?.unfocus()'),
    );
    expect(keyboardGuard, contains("'TextInput.hide'"));
    expect(
      keyboardGuard,
      contains('await _waitForDropdownInsetsToSettle(context)'),
    );
    expect(
      keyboardGuard,
      contains('Future<void> _waitForDropdownInsetsToSettle'),
    );
    expect(keyboardGuard, contains('for (var i = 0; i < 18; i += 1)'));
    expect(keyboardGuard, contains('closedStableFrames >= 3'));
    expect(keyboardGuard, contains('unchangedFrames >= 4'));
    expect(keyboardGuard, contains('await WidgetsBinding.instance.endOfFrame'));
    expect(
      keyboardGuard,
      contains('MediaQuery.maybeOf(context)?.viewInsets.bottom'),
    );
    expect(keyboardGuard, contains('final hadKeyboard'));
    expect(
      keyboardGuard,
      contains('Future<void> _waitForDropdownAnchorLayoutToSettle'),
    );
    expect(keyboardGuard, contains('View.maybeOf(context)'));
    expect(
      keyboardGuard,
      contains('view.viewInsets.bottom / view.devicePixelRatio'),
    );
    expect(keyboardGuard, contains('if (!_dropdownAnchorIsVisible(context))'));
    expect(keyboardGuard, contains('if (hadKeyboard)'));
    expect(
      keyboardGuard,
      contains('ScrollPositionAlignmentPolicy.keepVisibleAtStart'),
    );
    expect(
      source,
      contains('bool _dropdownAnchorIsVisible(BuildContext context)'),
    );

    final menu = source.substring(
      source.indexOf('Future<T?> _showAnchoredDropdownMenu<T>'),
      source.indexOf('class AppCompactDropdown<T>'),
    );
    expect(menu, contains('_DropdownMenuPosition positionForCurrentLayout()'));
    expect(source, contains('class _DropdownMenuPosition'));
    expect(menu, contains('_effectiveDropdownBottomInset(context)'));
    expect(
      menu,
      contains(
        'final safeBottom = (activeOverlay.size.height - bottomInset - 8)',
      ),
    );
    expect(
      menu,
      contains('belowSpace < preferredMaxHeight && aboveSpace > belowSpace'),
    );
    expect(menu, contains('items.length * itemHeight + menuPadding.vertical'));
    expect(menu, contains('menuPadding: menuPadding'));
    expect(menu, contains('height: itemHeight'));
    expect(
      menu,
      contains(
        'final menuTop = unclampedTop.clamp(safeTop, maxTop).toDouble()',
      ),
    );
    expect(
      menu,
      contains(
        'final menuBottom = (activeOverlay.size.height - menuTop - availableHeight)',
      ),
    );
    expect(
      menu,
      contains(
        'positionBuilder: (_, constraints) => positionForCurrentLayout()',
      ),
    );
    expect(menu, contains('requestFocus: false'));
    expect(menu, contains('maxHeight: initialPosition.height'));
    expect(menu, contains('height: availableHeight'));
    expect(menu, isNot(contains('DropdownButton(')));
    expect(menu, isNot(contains('DropdownButtonFormField(')));

    final compactDropdown = source.substring(
      source.indexOf('class AppCompactDropdown<T>'),
      source.indexOf('class AppDropdownField<T>'),
    );
    expect(
      compactDropdown,
      contains('await _hideKeyboardBeforePicker(anchorContext)'),
    );
    expect(compactDropdown, contains('onTapDown: enabled'));
    expect(
      compactDropdown,
      contains('_beginDropdownKeyboardDismiss(anchorContext)'),
    );
    expect(compactDropdown, contains('context: anchorContext'));

    final dropdownField = source.substring(
      source.indexOf('class AppDropdownField<T>'),
    );
    expect(
      dropdownField,
      contains('await _hideKeyboardBeforePicker(anchorContext)'),
    );
    expect(dropdownField, contains('onTapDown: canOpen'));
    expect(
      dropdownField,
      contains('_beginDropdownKeyboardDismiss(anchorContext)'),
    );
    expect(dropdownField, contains('context: anchorContext'));
  });

  test('个人资料、通知二级页和管理员子页保持紧凑标题与单层内容区', () {
    final profile = File('lib/screens/profile_screen.dart').readAsStringSync();
    final notification = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();
    final diary = File('lib/screens/diary_screen.dart').readAsStringSync();
    final admin = File('lib/screens/admin_screen.dart').readAsStringSync();
    final course = File(
      'lib/screens/course_schedule_screen.dart',
    ).readAsStringSync();

    expect(
      profile,
      contains('titleTextStyle: appSecondaryRouteTitleTextStyle(context)'),
    );
    expect(
      notification,
      contains('titleTextStyle: appSecondaryRouteTitleTextStyle(context)'),
    );
    expect(
      course,
      contains('titleTextStyle: appSecondaryRouteTitleTextStyle(context)'),
    );
    expect(
      diary,
      contains('titleTextStyle: appSecondaryRouteTitleTextStyle(context)'),
    );
    expect(diary, contains('AppSecondaryControlTheme('));
    expect(diary, contains('final routeBackground'));
    expect(diary, contains('backgroundColor: routeBackground'));
    expect(diary, contains('surfaceTintColor: Colors.transparent'));
    expect(diary, contains("I18n.tr('feature.unavailable')"));
    expect(diary, isNot(contains('TextField(')));
    expect(diary, isNot(contains('TextFormField(')));
    expect(diary, isNot(contains('DiaryProvider')));
    expect(diary, isNot(contains('action.save')));
    expect(profile, isNot(contains('fontSize: 12')));
    expect(
      profile,
      contains('textStyle: appSecondaryControlTextStyle(context)'),
    );
    expect(admin, contains('bottom: AppPageTabs('));
    expect(admin, contains('height: AppPageTabs.heightFor(context)'));
    expect(admin, contains('height: 38'));
    expect(admin, isNot(contains('height: 44')));
    final tabLabel = admin.substring(
      admin.indexOf('class _AdminTabLabel'),
      admin.indexOf('class _AdminChipWrap'),
    );
    expect(tabLabel, contains('mainAxisSize: MainAxisSize.min'));
    expect(tabLabel, isNot(contains('maxWidth: 128')));
    expect(admin, contains('Icon(icon, size: 16)'));

    for (final className in [
      'class _AnnouncementsTabState',
      'class _FeedbackTabState',
      'class _InvitesTabState',
    ]) {
      final start = admin.indexOf(className);
      expect(start, greaterThanOrEqualTo(0), reason: className);
      final nextClass = admin.indexOf('\nclass ', start + className.length);
      final section = admin.substring(
        start,
        nextClass == -1 ? admin.length : nextClass,
      );
      expect(section, contains('return Column('), reason: className);
      expect(section, isNot(contains('return Scaffold(')), reason: className);
    }
  });

  test('日历详情区域和扩展功能按钮保持紧凑不挤压', () {
    final calendar = File(
      'lib/screens/calendar_screen.dart',
    ).readAsStringSync();
    expect(
      calendar,
      contains("key: const ValueKey('calendar_month_detail_agenda')"),
    );
    expect(
      calendar,
      contains("key: const ValueKey('calendar_fixed_month_grid')"),
    );
    expect(
      calendar,
      contains("key: const ValueKey('calendar_month_global_scrollbar')"),
    );
    expect(calendar, contains("'calendar_month_global_scroll_view'"));
    expect(calendar, contains('double _monthGridHeightFor'));
    expect(
      calendar,
      matches(
        RegExp(
          r'rows >= 6\s*\?\s*288\.0\s*:\s*\(rows == 5 \?\s*260\.0\s*:\s*236\.0\)',
          multiLine: true,
        ),
      ),
    );
    expect(
      calendar,
      matches(
        RegExp(
          r'rows >= 6\s*\?\s*318\.0\s*:\s*\(rows == 5 \?\s*292\.0\s*:\s*268\.0\)',
          multiLine: true,
        ),
      ),
    );
    expect(calendar, contains('const monthGridChromeHeight = 36.0'));
    expect(calendar, contains('final minGridHeight'));
    expect(calendar, contains('final preferredGridHeight'));
    expect(calendar, contains('height: monthGridHeight'));
    expect(calendar, contains('scrollable: false'));
    expect(calendar, contains('horizontalPadding: 8'));
    expect(calendar, contains('maxLines: 2'));
    expect(calendar, contains('dimension: 48'));
    final eventSheet = File(
      'lib/widgets/calendar_event_sheet.dart',
    ).readAsStringSync();
    expect(eventSheet, contains('maxWidth: 860'));
    expect(eventSheet, contains('scrollable: false'));
    expect(eventSheet, contains('SingleChildScrollView('));
    expect(
      eventSheet,
      contains("ValueKey('calendar_event_detail_scroll_region')"),
    );
    expect(eventSheet, isNot(contains('detailMaxHeight')));
    expect(calendar, contains('maxWidth: 860'));
    expect(calendar, contains('MediaQuery.sizeOf(context).height * 0.68'));

    final integrations = File(
      'lib/screens/integrations_screen.dart',
    ).readAsStringSync();
    expect(integrations, contains('_integrationHintTextStyle'));
    expect(integrations, isNot(contains('Colors.black54')));
    expect(integrations, isNot(contains('Colors.black45')));
    expect(integrations, isNot(contains('right: 88')));
    expect(integrations, contains('class _IntegrationActionStrip'));
    expect(
      integrations,
      contains("key: const ValueKey('integration_action_strip')"),
    );
    expect(integrations, contains('SingleChildScrollView('));
    expect(integrations, contains('scrollDirection: Axis.horizontal'));
    expect(integrations, contains('mainAxisAlignment: MainAxisAlignment.end'));
    expect(integrations, contains('AppSecondaryMenuText(account.enabled'));
    expect(integrations, contains('AppSecondaryMenuText(sub.enabled'));

    final moreApps = File(
      'lib/screens/more_apps_screen.dart',
    ).readAsStringSync();
    expect(
      moreApps,
      contains("key: const ValueKey('more_application_button_tap_region')"),
    );
    expect(moreApps, isNot(contains('return OutlinedButton.icon(')));
    expect(moreApps, contains('SizedBox.square('));
    expect(moreApps, contains('Expanded('));

    final habit = File('lib/screens/habit_screen.dart').readAsStringSync();
    expect(habit, contains('const double _habitCheckinCardBodyHeight = 38'));
    expect(habit, isNot(contains("label: const Text('还原')")));
    expect(habit, contains('fixedSize: const Size(_habitUndoButtonWidth, 26)'));
  });

  test('小组件页自身有背景且预览不会在宽屏左侧缩成窄列', () {
    final widgetScreen = File(
      'lib/screens/widget_screen.dart',
    ).readAsStringSync();
    expect(widgetScreen, contains('final routeBackground'));
    expect(widgetScreen, contains('backgroundColor: routeBackground'));
    expect(
      widgetScreen,
      contains('backgroundColor: routeBackground.withValues(alpha: 0.96)'),
    );
    expect(widgetScreen, contains('surfaceTintColor: Colors.transparent'));
    expect(widgetScreen, contains('AppSecondaryControlTheme('));
    expect(widgetScreen, contains('appSecondaryFilledButtonStyle(context)'));
    expect(widgetScreen, isNot(contains('fontSize: 20')));
    expect(
      widgetScreen,
      isNot(contains('backgroundColor: Colors.transparent')),
    );
    expect(widgetScreen, contains("'2x2', 1.0, 320"));
    expect(widgetScreen, contains("'3x2', 1.5, 480"));
    expect(widgetScreen, contains("'4x3', 4 / 3, 640"));
    expect(widgetScreen, contains('alignment: Alignment.center'));
  });

  test('习惯今日打卡优先展示且懒构建，避免一屏只露出一个卡片', () {
    final habit = File('lib/screens/habit_screen.dart').readAsStringSync();

    expect(habit, contains("key: const ValueKey('habit_today_scroll_view')"));
    expect(
      habit,
      contains("key: const ValueKey('habit_today_checkin_sliver')"),
    );
    expect(habit, contains('SliverList.builder('));
    expect(habit, contains('itemCount: visibleHabits.length'));
    expect(habit, contains('final visibleHabits = activeHabits'));
    expect(habit, contains('_HabitStatusFilter.pending'));
    expect(habit, contains('_HabitTodaySummaryCard('));
    expect(habit, contains('const double _habitCheckinCardBodyHeight = 38'));
    expect(habit, contains('const double _habitTitleStatusHeight = 15'));
    expect(habit, contains('const double _habitUndoButtonWidth = 28'));
    expect(habit, contains('const double _habitCheckinButtonWidth = 52'));
    expect(habit, contains('minimumSize: const Size('));
    expect(habit, contains('_habitCheckinButtonWidth'));
    expect(habit, contains('fixedSize: const Size(_habitUndoButtonWidth, 26)'));
    expect(habit, contains('const double _habitActionRailWidth'));
    expect(habit, contains("key: const ValueKey('habit-undo-inline-button')"));
    expect(habit, contains('IconButton.styleFrom('));
    expect(habit, isNot(contains("label: const Text('还原')")));
    expect(habit, isNot(contains('Icons.verified_rounded')));
    expect(habit, contains('class _HabitSwipeActionWrapper'));
    expect(habit, contains('if (_swipeOffset > 0)'));
    expect(habit, contains('onEnd: () => _runAction('));
    expect(habit, contains('onDelete: () => _runAction('));
    expect(
      habit,
      contains("_handleHabitMenuAction(context, widget.habit, 'end')"),
    );
    expect(
      habit,
      contains("_handleHabitMenuAction(context, widget.habit, 'delete')"),
    );
    expect(habit, contains('await provider.deleteHabit(habit.id)'));
    expect(habit, contains('await provider.endHabit(habit.id)'));
    expect(habit, contains('builder: (ctx) => AppDialog('));
    expect(habit, isNot(contains('builder: (ctx) => AlertDialog(')));
    expect(habit, isNot(contains('...activeHabits.map')));
    final heatmapStart = habit.indexOf('class _HabitHeatmapTab');
    final heatmapEnd = habit.indexOf(
      'class _HabitInsightSection',
      heatmapStart,
    );
    expect(heatmapStart, greaterThanOrEqualTo(0));
    expect(heatmapEnd, greaterThan(heatmapStart));
    final heatmapTab = habit.substring(heatmapStart, heatmapEnd);
    expect(heatmapTab, contains('return CustomScrollView('));
    expect(heatmapTab, contains('SliverList.builder('));
    expect(heatmapTab, contains('itemCount: habitGroups.length'));
    expect(
      heatmapTab,
      isNot(contains('return ListView(')),
      reason: '热力图分组不能一次性 eager 构建所有分组和任务。',
    );
    expect(
      habit.indexOf('const SliverToBoxAdapter(child: HabitWeeklyCard())'),
      lessThan(
        habit.indexOf("key: const ValueKey('habit_today_checkin_sliver')"),
      ),
    );
  });
}

double _requiredFontSize(String source) {
  final literal = RegExp(
    r'fontSize:\s*([0-9]+(?:\.[0-9]+)?)',
  ).firstMatch(source);
  if (literal != null) return double.parse(literal.group(1)!);
  final token = RegExp(r'fontSize:\s*DesignTokens\.(\w+)').firstMatch(source);
  expect(
    token,
    isNotNull,
    reason: 'Expected a numeric fontSize or design token in:\n$source',
  );
  final tokens = File('lib/core/design_tokens.dart').readAsStringSync();
  var name = token!.group(1)!;
  for (var i = 0; i < 5; i++) {
    final declaration = RegExp(
      'static const double $name = ([a-zA-Z0-9_.]+);',
    ).firstMatch(tokens);
    expect(declaration, isNotNull, reason: 'Unknown font size token: $name');
    final value = declaration!.group(1)!;
    final number = double.tryParse(value);
    if (number != null) return number;
    name = value;
  }
  throw StateError('Unresolved font size token: $name');
}

Iterable<String> _calls(String source, String token) sync* {
  var searchFrom = 0;
  while (true) {
    final start = source.indexOf(token, searchFrom);
    if (start == -1) return;
    var depth = 0;
    var end = start;
    for (; end < source.length; end++) {
      final char = source[end];
      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
        if (depth == 0) {
          end++;
          break;
        }
      }
    }
    yield source.substring(start, end);
    searchFrom = end;
  }
}
