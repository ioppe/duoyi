import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('iOS WidgetKit resources', () {
    final swift = File(
      'ios/DuoyiWidgets/DuoyiWidgets.swift',
    ).readAsStringSync();
    final infoPlist = File('ios/DuoyiWidgets/Info.plist').readAsStringSync();
    final runnerInfoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final sceneDelegate = File(
      'ios/Runner/SceneDelegate.swift',
    ).readAsStringSync();
    final entitlements = File(
      'ios/DuoyiWidgets/DuoyiWidgets.entitlements',
    ).readAsStringSync();
    final runnerEntitlements = File(
      'ios/Runner/Runner.entitlements',
    ).readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final service = File(
      'lib/services/home_widget_service.dart',
    ).readAsStringSync();

    const widgetKinds = [
      'DuoyiTodoWidget',
      'DuoyiFocusWidget',
      'DuoyiHabitWidget',
      'DuoyiCalendarWidget',
      'DuoyiScheduleWidget',
      'DuoyiGoalWidget',
      'DuoyiCourseWidget',
      'DuoyiNoteWidget',
      'DuoyiAnniversaryWidget',
    ];

    test('declares 9 visible independent WidgetKit kinds', () {
      final declaredKinds = RegExp(
        r'kind: "([^"]+)"',
      ).allMatches(swift).map((match) => match.group(1)!).toSet();
      final bundledConfigs = RegExp(
        r'DuoyiAnyWidget\(config: ([^)]+)\)',
      ).allMatches(swift).map((match) => match.group(1)!).toList();

      expect(declaredKinds, containsAll(widgetKinds));
      expect(declaredKinds, hasLength(widgetKinds.length));
      expect(bundledConfigs, containsAll(widgetKinds.map(_configName)));
      expect(bundledConfigs, hasLength(widgetKinds.length));
      expect(swift, isNot(contains('DuoyiDiaryWidget')));

      for (final kind in widgetKinds) {
        final configBlock = _swiftConfigBlock(swift, _configName(kind));
        expect(configBlock, contains('kind: "$kind"'));
        expect(swift, contains('DuoyiAnyWidget(config: ${_configName(kind)})'));
        expect(
          service,
          contains("static const String _ios${_serviceName(kind)} = '$kind';"),
        );
        expect(
          service,
          contains('iOSName: HomeWidgetService._ios${_serviceName(kind)}'),
        );
      }

      expect(swift, isNot(contains('Overview')));
      expect(swift, isNot(contains('overview')));
      expect(swift, isNot(contains('Combo')));
      expect(swift, isNot(contains('combo')));
      expect(service, isNot(contains('DuoyiOverviewWidget')));
      expect(service, isNot(contains('DuoyiComboWidget')));
      expect(service, isNot(contains('DuoyiWidgetKind.overview')));
      expect(service, isNot(contains('DuoyiWidgetKind.combo')));
    });

    test('shares the same app group and WidgetKit extension point', () {
      expect(
        swift,
        contains('private let appGroupId = "group.com.duoyi.duoyi"'),
      );
      expect(
        service,
        contains("static const String _appGroupId = 'group.com.duoyi.duoyi';"),
      );
      expect(entitlements, contains('group.com.duoyi.duoyi'));
      expect(runnerEntitlements, contains('group.com.duoyi.duoyi'));
      expect(infoPlist, contains('com.apple.widgetkit-extension'));
      expect(infoPlist, contains('CFBundleShortVersionString'));
      expect(infoPlist, contains('CFBundleVersion'));
      expect(runnerInfoPlist, contains('com.duoyi.duoyi.deep-links'));
      expect(runnerInfoPlist, contains('<string>duoyi</string>'));
    });

    test('Xcode project embeds the WidgetKit extension target', () {
      expect(project, contains('DuoyiWidgets.appex'));
      expect(
        project,
        matches(
          RegExp(
            r'/\* DuoyiWidgets \*/ = \{\s*'
            r'isa = PBXNativeTarget;[\s\S]*?'
            r'name = DuoyiWidgets;[\s\S]*?'
            r'productName = DuoyiWidgets;[\s\S]*?'
            r'productReference = [^;]+ /\* DuoyiWidgets\.appex \*/;[\s\S]*?'
            r'productType = "com\.apple\.product-type\.app-extension";',
          ),
        ),
      );
      expect(project, contains('Embed App Extensions'));
      expect(project, contains('DuoyiWidgets.swift in Sources'));
      expect(project, contains('path = DuoyiWidgets.swift;'));
      expect(project, contains('path = DuoyiWidgets.entitlements;'));
      expect(project, contains('path = DuoyiWidgets.appex;'));
      expect(project, contains('path = DuoyiWidgets;'));
      expect(project, matches(RegExp(r'target = [^;]+ /\* DuoyiWidgets \*/;')));
      expect(
        project,
        contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'),
      );
      expect(
        project,
        contains(
          'CODE_SIGN_ENTITLEMENTS = DuoyiWidgets/DuoyiWidgets.entitlements;',
        ),
      );
      expect(
        project,
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.duoyi.duoyi.DuoyiWidgets;'),
      );
      expect(project, contains('MARKETING_VERSION = 1.1.11;'));
      expect(project, contains('CURRENT_PROJECT_VERSION = 110011;'));
      expect(project, contains('APPLICATION_EXTENSION_API_ONLY = YES;'));
      expect(project, contains('INFOPLIST_FILE = DuoyiWidgets/Info.plist;'));
    });

    test('uses the same payload keys written by HomeWidgetService', () {
      const sharedKeys = [
        'todo_top3_1',
        'todo_top3_2',
        'todo_top3_3',
        'next_focus_label',
        'focus_summary',
        'focus_timer_running',
        'focus_timer_remaining_seconds',
        'focus_timer_total_seconds',
        'focus_timer_ends_at_millis',
        'focus_timer_label',
        'streak_summary',
        'habit_summary',
        'habit_quick_check_label',
        'habit_quick_check_id',
        'calendar_month_summary',
        'today_event_summary',
        'schedule_highlight_1',
        'schedule_highlight_2',
        'schedule_highlight_3',
        'goal_highlight_1',
        'goal_highlight_2',
        'goal_highlight_3',
        'course_highlight_1',
        'course_highlight_2',
        'note_highlight_1',
        'note_highlight_2',
        'note_highlight_3',
        'anniversary_highlight_1',
        'anniversary_highlight_2',
        'memorial_highlight_1',
        'memorial_highlight_2',
        'memorial_highlight_3',
        'widget_display_mode',
        'brand_app_title',
        'nav_todo',
        'nav_habit',
        'nav_calendar',
        'nav_focus',
      ];

      for (final key in sharedKeys) {
        expect(swift, contains('"$key"'));
        expect(service, contains("'$key'"));
      }
      const configKeys = {
        'todoConfig': ['todo_top3_1', 'todo_top3_2', 'todo_top3_3'],
        'focusConfig': ['next_focus_label', 'focus_summary', 'streak_summary'],
        'habitConfig': [
          'habit_summary',
          'habit_quick_check_label',
          'streak_summary',
        ],
        'calendarConfig': [
          'calendar_month_summary',
          'today_event_summary',
          'schedule_highlight_2',
        ],
        'scheduleConfig': [
          'today_event_summary',
          'schedule_highlight_1',
          'schedule_highlight_2',
          'schedule_highlight_3',
        ],
        'goalConfig': [
          'goal_highlight_1',
          'goal_highlight_2',
          'goal_highlight_3',
        ],
        'courseConfig': [
          'course_highlight_1',
          'course_highlight_2',
          'today_event_summary',
        ],
        'noteConfig': [
          'note_highlight_1',
          'note_highlight_2',
          'note_highlight_3',
        ],
        'anniversaryConfig': [
          'anniversary_highlight_1',
          'anniversary_highlight_2',
          'memorial_highlight_1',
          'memorial_highlight_2',
          'memorial_highlight_3',
        ],
      };
      for (final configEntry in configKeys.entries) {
        final configBlock = _swiftConfigBlock(swift, configEntry.key);
        for (final key in configEntry.value) {
          expect(configBlock, contains('"$key"'));
        }
      }
      expect(swift, contains('todo_top3_\\(index)_id'));
      expect(swift, contains('private struct DuoyiWidgetRow'));
      expect(swift, contains('primaryTarget'));
      expect(swift, contains('readPrimary'));
      expect(swift, contains('config.kind == "DuoyiAnniversaryWidget"'));
      expect(swift, contains('trimmedTitle == config.fallback'));
      expect(swift, contains('key: "memorial_highlight_1", fallback: ""'));
      expect(swift, contains('key: "memorial_highlight_1_id"'));
      expect(swift, contains('sourceKey = "memorial_highlight_1"'));
      expect(swift, contains('readRows'));
      expect(swift, contains('excluding: primarySource.sourceKey'));
      expect(swift, contains('"\\(config.primaryKey)_id"'));
      expect(swift, contains('"\\(key)_id"'));
      expect(swift, contains('linkedText(entry.primary'));
      expect(swift, contains('linkedText(row.title'));
      expect(swift, contains('Link(destination: url)'));
      for (final key in [
        'todo_top3_1_id',
        'todo_top3_2_id',
        'todo_top3_3_id',
        'schedule_highlight_1_id',
        'schedule_highlight_2_id',
        'schedule_highlight_3_id',
        'goal_highlight_1_id',
        'goal_highlight_2_id',
        'goal_highlight_3_id',
        'course_highlight_1_id',
        'course_highlight_2_id',
        'note_highlight_1_id',
        'note_highlight_2_id',
        'note_highlight_3_id',
        'anniversary_highlight_1_id',
        'anniversary_highlight_2_id',
        'memorial_highlight_1_id',
        'memorial_highlight_2_id',
        'memorial_highlight_3_id',
        'diary_highlight_1_id',
        'diary_highlight_2_id',
        'diary_highlight_3_id',
      ]) {
        expect(service, contains("'$key'"));
      }
    });

    test('focus widget renders the shared timer contract', () {
      expect(swift, contains('focusTimerRunning'));
      expect(swift, contains('focusTimerRemainingSeconds'));
      expect(swift, contains('focusTimerTotalSeconds'));
      expect(swift, contains('focusTimerEndsAtMillis'));
      expect(swift, contains('focusTimerLabel'));
      expect(swift, contains('Text(endDate, style: .timer)'));
      expect(swift, contains('.monospacedDigit()'));
      expect(swift, contains('current.focusTimerRunning ? 1 : 15'));

      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('focusTimerRunning: focusState.isRunning'));
      expect(
        main,
        contains('focusTimerRemainingSeconds: focusState.remainingSeconds'),
      );
      expect(main, contains('focusTimerTotalSeconds: focusState.totalSeconds'));
      expect(main, contains('focusTimerEndsAtMillis: focusTimerEndsAtMillis'));
      expect(main, contains('focusTimerLabel: focusTimerLabel'));
    });

    test('supports home screen and lock screen WidgetKit families', () {
      expect(
        swift,
        contains(
          'var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]',
        ),
      );
      expect(swift, contains('families.append(.systemExtraLarge)'));
      expect(swift, contains('.accessoryInline'));
      expect(swift, contains('.accessoryCircular'));
      expect(swift, contains('.accessoryRectangular'));
      expect(swift, contains('private var accessoryContent: some View'));
      expect(swift, contains('AccessoryWidgetBackground()'));
      expect(swift, contains('private var isAccessoryFamily: Bool'));
      expect(swift, contains('private var accessoryPrimaryText: String'));
      expect(swift, contains('private var accessorySecondaryText: String?'));
      expect(swift, contains('private var accessorySymbol: String'));
      expect(swift, contains('formatMinutes'));
    });

    test('keeps WidgetKit text compatible with iOS 14 and clipped in bounds', () {
      final widgetTargetBlocks = RegExp(
        r'IPHONEOS_DEPLOYMENT_TARGET = 14\.0;',
      ).allMatches(project).length;
      expect(widgetTargetBlocks, greaterThanOrEqualTo(3));
      expect(swift, isNot(contains('.foregroundStyle(')));
      expect(swift, contains('.foregroundColor(entry.theme.mutedText)'));
      expect(swift, contains('.foregroundColor(entry.theme.primary)'));
      expect(
        swift,
        contains(
          '.foregroundColor(primary ? entry.theme.text : entry.theme.mutedText)',
        ),
      );
      expect(
        swift,
        contains(
          'private func todoText(_ title: String, primary: Bool) -> some View',
        ),
      );
      final rowText = _swiftFunctionBlock(swift, 'rowText');
      final todoText = _swiftFunctionBlock(swift, 'todoText');
      final navText = _swiftFunctionBlock(swift, 'navText');
      for (final block in [rowText, todoText, navText]) {
        expect(block, contains('.lineLimit('));
        expect(block, contains('.truncationMode(.tail)'));
      }
      final header = _swiftPropertyBlock(swift, 'header');
      final focusContent = _swiftPropertyBlock(swift, 'focusContent');
      final todoRow = _swiftFunctionBlock(swift, 'todoRow');
      final accessoryContent = _swiftPropertyBlock(swift, 'accessoryContent');
      for (final block in [header, focusContent, todoRow, accessoryContent]) {
        expect(block, contains('.lineLimit(1)'));
        expect(block, contains('.truncationMode(.tail)'));
      }
      expect(header, contains('.layoutPriority(1)'));
      expect(focusContent, contains('.minimumScaleFactor(0.78)'));
      expect(todoText, contains('.lineLimit(primary ? primaryLines : 1)'));
      expect(navText, contains('.lineLimit(1)'));
    });

    test('Flutter side enables iOS home_widget updates', () {
      expect(service, contains('PlatformInfo.isAndroid || PlatformInfo.isIOS'));
      expect(service, contains('HomeWidget.setAppGroupId(_appGroupId)'));
      expect(service, contains('HomeWidget.initiallyLaunchedFromHomeWidget()'));
      expect(service, contains('HomeWidget.widgetClicked'));
    });

    test(
      'exposes WidgetKit deep links for quick actions and footer navigation',
      () {
        const deepLinksByKind = {
          'DuoyiTodoWidget': 'duoyi://todo',
          'DuoyiFocusWidget': 'duoyi://action/start_pomodoro',
          'DuoyiHabitWidget': 'duoyi://habit',
          'DuoyiCalendarWidget': 'duoyi://calendar',
          'DuoyiScheduleWidget': 'duoyi://calendar',
          'DuoyiGoalWidget': 'duoyi://goal',
          'DuoyiCourseWidget': 'duoyi://course',
          'DuoyiNoteWidget': 'duoyi://note',
          'DuoyiAnniversaryWidget': 'duoyi://anniversary',
        };
        const quickLinksByKind = {
          'DuoyiTodoWidget': 'duoyi://action/quick_todo',
          'DuoyiFocusWidget': 'duoyi://action/start_pomodoro',
          'DuoyiHabitWidget': 'duoyi://habit',
          'DuoyiCalendarWidget': 'duoyi://calendar',
          'DuoyiScheduleWidget': 'duoyi://calendar',
          'DuoyiGoalWidget': 'duoyi://goal',
          'DuoyiCourseWidget': 'duoyi://course',
          'DuoyiNoteWidget': 'duoyi://note',
          'DuoyiAnniversaryWidget': 'duoyi://anniversary',
        };
        const handlingByKind = {
          'DuoyiTodoWidget': [
            "uri.host == 'todo'",
            'state.navigateTo(1, allowHidden: true);',
            'TodayDetailRouter.open(ctx, TodaySectionKind.todos, id: id)',
            "action == 'quick_todo'",
            "action == 'complete_todo'",
          ],
          'DuoyiFocusWidget': [
            "action == 'start_pomodoro'",
            'state.navigateTo(4, allowHidden: true);',
            'pomodoro.startIfIdle()',
            '专注计时正在进行',
          ],
          'DuoyiHabitWidget': [
            "uri.host == 'habit'",
            'state.navigateTo(2, allowHidden: true);',
            'TodayDetailRouter.open(ctx, TodaySectionKind.habits, id: id)',
            "action == 'checkin_habit'",
          ],
          'DuoyiCalendarWidget': [
            "uri.host == 'calendar'",
            'state.navigateTo(3, allowHidden: true);',
          ],
          'DuoyiScheduleWidget': [
            "uri.host == 'calendar'",
            'state.navigateTo(3, allowHidden: true);',
          ],
          'DuoyiGoalWidget': [
            "uri.host == 'goal'",
            '_pushHiddenWidgetFallbackRoute(ctx, const GoalScreen())',
            'TodayDetailRouter.open(ctx, TodaySectionKind.goals, id: id)',
          ],
          'DuoyiCourseWidget': [
            "uri.host == 'course'",
            'TodayDetailRouter.open(ctx, TodaySectionKind.courses, id: id)',
          ],
          'DuoyiNoteWidget': [
            "uri.host == 'note'",
            'TodayDetailRouter.open(ctx, TodaySectionKind.notes, id: id)',
          ],
          'DuoyiAnniversaryWidget': [
            "uri.host == 'anniversary'",
            'TodayDetailRouter.open(ctx, TodaySectionKind.anniversaries, id: id)',
          ],
        };

        expect(swift, contains('Link(destination: quickURL)'));
        expect(swift, contains('Link(destination: url)'));
        expect(swift, contains('navLink(entry.navTodo, "duoyi://todo")'));
        expect(swift, contains('navLink(entry.navHabit, "duoyi://habit")'));
        expect(
          swift,
          contains('navLink(entry.navCalendar, "duoyi://calendar")'),
        );
        expect(swift, contains('navLink(entry.navFocus, "duoyi://focus")'));
        expect(
          swift,
          contains('navTodo: readString(defaults, key: "nav_todo"'),
        );
        expect(
          swift,
          contains('navHabit: readString(defaults, key: "nav_habit"'),
        );
        expect(
          swift,
          contains('navCalendar: readString(defaults, key: "nav_calendar"'),
        );
        expect(
          swift,
          contains('navFocus: readString(defaults, key: "nav_focus"'),
        );

        for (final kind in widgetKinds) {
          final configBlock = _swiftConfigBlock(swift, _configName(kind));
          expect(configBlock, contains('deepLink: "${deepLinksByKind[kind]}"'));
          expect(
            configBlock,
            contains('quickActionLink: "${quickLinksByKind[kind]}"'),
          );
        }
        expect(
          swift,
          contains('URLComponents(string: "duoyi://action/checkin_habit")'),
        );
        expect(swift, contains('duoyiPathSegmentAllowed'));
        expect(
          swift,
          contains(r'''allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")'''),
        );
        expect(swift, contains('duoyi://todo/\\(encodedId)'));
        expect(
          swift,
          contains('URLComponents(string: "duoyi://action/complete_todo")'),
        );
        expect(swift, contains('URLQueryItem(name: "id", value: todoId)'));
        expect(
          swift,
          contains('URLComponents(string: "duoyi://action/checkin_habit")'),
        );
        expect(swift, contains('readTodoRows'));
        expect(swift, contains('todo_top3_\\(index)_id'));
        expect(swift, contains('ForEach(visibleTodoRows)'));
        expect(swift, contains('Text("o")'));
        expect(swift, isNot(contains('Text("完成")')));
        expect(swift, isNot(contains('duoyi://action/start_focus')));

        final main = File('lib/main.dart').readAsStringSync();
        expect(main, contains('_homeWidgetEventsForToday'));
        expect(main, contains('_homeWidgetEventDeepLink'));
        expect(
          main,
          contains("'duoyi://goal/\${Uri.encodeComponent(goal.id)}'"),
        );
        expect(
          main,
          contains("'duoyi://course/\${Uri.encodeComponent(course.id)}'"),
        );
        expect(
          main,
          contains("'duoyi://note/\${Uri.encodeComponent(note.id)}'"),
        );
        expect(service, isNot(contains('_iosDiaryWidgetName')));
        expect(main, contains('todayEventSummary ='));
        expect(
          main,
          isNot(contains("todayEventSummary: top3.isEmpty ? '今日没有日程'")),
        );
        for (final kind in widgetKinds) {
          for (final snippet in handlingByKind[kind]!) {
            expect(main, contains(snippet), reason: kind);
          }
        }
        expect(main, contains("uri.host == 'focus'"));
        expect(
          main,
          contains('state.navigateTo(idx, allowHidden: true);'),
          reason:
              'WidgetKit footer links must keep hidden bottom-nav destinations reachable.',
        );
      },
    );

    test('Runner forwards WidgetKit and OAuth deep links into Flutter', () {
      expect(appDelegate, contains('final class DuoyiDeepLinkBridge'));
      expect(appDelegate, contains('FlutterMethodChannel('));
      expect(appDelegate, contains('name: channelName'));
      expect(appDelegate, contains('"duoyi/deep_links"'));
      expect(appDelegate, contains('case "takeInitialLink"'));
      expect(appDelegate, contains('case "takeInitialOAuthLink"'));
      expect(appDelegate, contains('case "takeInitialSharedText"'));
      expect(appDelegate, contains('channel?.invokeMethod("onLink"'));
      expect(appDelegate, contains('url.scheme == "duoyi"'));
      expect(appDelegate, contains('url.host == "oauth"'));
      expect(appDelegate, contains('launchOptions?[.url] as? URL'));
      expect(appDelegate, contains('open url: URL'));
      expect(appDelegate, contains('controller.binaryMessenger'));

      expect(sceneDelegate, contains('willConnectTo session'));
      expect(
        sceneDelegate,
        contains('connectionOptions.urlContexts.first?.url'),
      );
      expect(sceneDelegate, contains('openURLContexts URLContexts'));
      expect(sceneDelegate, contains('DuoyiDeepLinkBridge.shared.handle'));
      expect(sceneDelegate, contains('controller.binaryMessenger'));

      final deepLinkService = File(
        'lib/services/deep_link_service.dart',
      ).readAsStringSync();
      final main = File('lib/main.dart').readAsStringSync();
      expect(deepLinkService, contains('takeInitialLink'));
      expect(deepLinkService, contains('_isDuoyiDeepLink(uri)'));
      expect(main, contains('DeepLinkService.takeInitialLink()'));
      expect(main, contains('DeepLinkService.takeInitialOAuthLink()'));
    });
  });
}

String _swiftConfigBlock(String swift, String configName) {
  final match = RegExp(
    'private let ${RegExp.escape(configName)} = DuoyiWidgetConfig\\((.*?)^\\)',
    multiLine: true,
    dotAll: true,
  ).firstMatch(swift);
  if (match == null) {
    throw StateError('Missing Swift widget config $configName');
  }
  return match.group(0)!;
}

String _swiftFunctionBlock(String swift, String functionName) {
  final start = swift.indexOf('private func $functionName');
  if (start < 0) {
    throw StateError('Missing Swift function $functionName');
  }
  final next = swift.indexOf('\n    private ', start + 1);
  final end = next < 0 ? swift.indexOf('\n}', start + 1) : next;
  if (end <= start) {
    throw StateError('Missing Swift function end for $functionName');
  }
  return swift.substring(start, end);
}

String _swiftPropertyBlock(String swift, String propertyName) {
  final start = swift.indexOf('private var $propertyName');
  if (start < 0) {
    throw StateError('Missing Swift property $propertyName');
  }
  final next = swift.indexOf('\n    private ', start + 1);
  final end = next < 0 ? swift.indexOf('\n}', start + 1) : next;
  if (end <= start) {
    throw StateError('Missing Swift property end for $propertyName');
  }
  return swift.substring(start, end);
}

String _configName(String kind) {
  return switch (kind) {
    'DuoyiTodoWidget' => 'todoConfig',
    'DuoyiFocusWidget' => 'focusConfig',
    'DuoyiHabitWidget' => 'habitConfig',
    'DuoyiCalendarWidget' => 'calendarConfig',
    'DuoyiScheduleWidget' => 'scheduleConfig',
    'DuoyiGoalWidget' => 'goalConfig',
    'DuoyiCourseWidget' => 'courseConfig',
    'DuoyiNoteWidget' => 'noteConfig',
    'DuoyiAnniversaryWidget' => 'anniversaryConfig',
    'DuoyiDiaryWidget' => 'diaryConfig',
    _ => throw ArgumentError.value(kind, 'kind'),
  };
}

String _serviceName(String kind) {
  return switch (kind) {
    'DuoyiTodoWidget' => 'TodoWidgetName',
    'DuoyiFocusWidget' => 'FocusWidgetName',
    'DuoyiHabitWidget' => 'HabitWidgetName',
    'DuoyiCalendarWidget' => 'CalendarWidgetName',
    'DuoyiScheduleWidget' => 'ScheduleWidgetName',
    'DuoyiGoalWidget' => 'GoalWidgetName',
    'DuoyiCourseWidget' => 'CourseWidgetName',
    'DuoyiNoteWidget' => 'NoteWidgetName',
    'DuoyiAnniversaryWidget' => 'AnniversaryWidgetName',
    'DuoyiDiaryWidget' => 'DiaryWidgetName',
    _ => throw ArgumentError.value(kind, 'kind'),
  };
}
