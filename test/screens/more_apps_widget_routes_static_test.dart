import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('更多应用入口在行动计划内并以二级页面打开隐藏功能', () {
    final main = File('lib/main.dart').readAsStringSync();
    final mine = File('lib/screens/mine_screen.dart').readAsStringSync();
    final moreApps = File(
      'lib/screens/more_apps_screen.dart',
    ).readAsStringSync();

    final actionPlanStart = mine.indexOf(
      "title: I18n.tr('mine.group.action_plan')",
    );
    final reviewStart = mine.indexOf("title: I18n.tr('mine.group.review')");
    final moreAppsTile = mine.indexOf("label: I18n.tr('mine.tile.more_apps')");
    expect(actionPlanStart, greaterThanOrEqualTo(0));
    expect(reviewStart, greaterThan(actionPlanStart));
    expect(moreAppsTile, inInclusiveRange(actionPlanStart, reviewStart));
    expect(mine, contains('onTap: () => _openMoreApplications(context)'));

    expect(
      main,
      isNot(
        contains(
          'onOpenHiddenBottomNavTab: (tab) => navigateTo(tab, allowHidden: true)',
        ),
      ),
    );
    expect(main, contains('WidgetScreen(key: widgetKey)'));
    expect(main, contains('final Set<int> _builtTabs = <int>{0}'));
    expect(main, contains('_LazyTabPlaceholder'));
    expect(main, contains('_buildTab(tab, safeVisibleTabs)'));
    expect(main, contains('state.navigateTo(idx, allowHidden: true);'));
    expect(main, contains('bottomNavigationBar: showingHiddenTab'));
    expect(main, contains("const Text('返回我的')"));

    expect(
      moreApps,
      isNot(contains('final openHiddenTab = onOpenHiddenBottomNavTab')),
    );
    expect(
      moreApps,
      isNot(contains('final ValueChanged<int>? onOpenHiddenTab')),
    );
    expect(moreApps, isNot(contains('final shellOpen = onOpenHiddenTab')));
    expect(moreApps, isNot(contains('shellOpen(app.tab);')));
    expect(moreApps, isNot(contains('Navigator.of(context).maybePop()')));
    expect(
      moreApps,
      isNot(contains('WidgetsBinding.instance.addPostFrameCallback')),
    );
    expect(moreApps, contains('Navigator.of(context).push('));
    expect(moreApps, contains('BrandRouteSurface('));
    expect(moreApps, contains('builder: (routeContext)'));
    expect(moreApps, contains('child: app.builder(routeContext)'));
    expect(moreApps, contains('appSecondaryMenuItemTextStyle('));
    expect(moreApps, isNot(contains('fontSize: 13')));
    expect(moreApps, contains("label: '小组件'"));
    expect(moreApps, contains('builder: (_) => const WidgetScreen()'));
    expect(moreApps, isNot(contains("label: '番茄专注'")));
    expect(moreApps, isNot(contains("label: '倒数日'")));
    expect(moreApps, isNot(contains('CountdownScreen')));
  });

  test('widget deep links keep hidden routes reachable and detail rows clickable', () {
    final main = File('lib/main.dart').readAsStringSync();
    final receiver = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetPinResultReceiver.kt',
    ).readAsStringSync();
    final providers = <String, _ProviderRouteCheck>{
      'goal': _ProviderRouteCheck(
        fileName: 'DuoyiGoalWidgetProvider.kt',
        keyPrefix: 'goal_highlight_',
        fallback: 'duoyi://goal',
      ),
      'course': _ProviderRouteCheck(
        fileName: 'DuoyiCourseWidgetProvider.kt',
        keyPrefix: 'course_highlight_',
        fallback: 'duoyi://course',
      ),
      'schedule': _ProviderRouteCheck(
        fileName: 'DuoyiScheduleWidgetProvider.kt',
        keyPrefix: 'schedule_highlight_',
        fallback: 'duoyi://calendar',
      ),
      'note': _ProviderRouteCheck(
        fileName: 'DuoyiNoteWidgetProvider.kt',
        keyPrefix: 'note_highlight_',
        fallback: 'duoyi://note',
      ),
      'anniversary': _ProviderRouteCheck(
        fileName: 'DuoyiAnniversaryWidgetProvider.kt',
        keyPrefix: 'memorial_highlight_',
        fallback: 'duoyi://anniversary',
      ),
    };

    for (final tab in ['todo', 'habit', 'calendar', 'focus', 'widget']) {
      expect(main, contains("'$tab' => "));
    }
    expect(main, contains('state.navigateTo(idx, allowHidden: true);'));
    expect(main, contains('state.navigateTo(4, allowHidden: true)'));
    expect(main, contains('state.navigateTo(1, allowHidden: true)'));
    expect(main, contains('state.navigateTo(2, allowHidden: true)'));
    expect(main, contains('state.navigateTo(5, allowHidden: true)'));
    expect(main, contains('_pushHiddenWidgetFallbackRoute'));

    // 小组件待办点击必须走 MainShellState.openTodoFromWidget 的返回链
    // （主页面 → 清单 → 详情），不能在深链层直接切隐藏 tab 1 或直接压栈。
    final todoBranchStart = main.indexOf("} else if (uri.host == 'todo'");
    final todoBranchEnd = main.indexOf(
      "} else if (uri.host == 'goal'",
      todoBranchStart,
    );
    expect(todoBranchStart, greaterThanOrEqualTo(0));
    expect(todoBranchEnd, greaterThan(todoBranchStart));
    final todoBranch = main.substring(todoBranchStart, todoBranchEnd);
    expect(todoBranch, contains('state.openTodoFromWidget('));
    expect(
      todoBranch,
      contains(
        'id: uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null',
      ),
    );
    expect(
      todoBranch,
      contains("confirm: uri.queryParameters['confirm'] == '1'"),
    );
    expect(todoBranch, isNot(contains('navigateTo(1')));
    expect(
      todoBranch,
      isNot(contains('TodayDetailRouter.open')),
      reason: '待办深链必须复用 openTodoFromWidget 的清单/详情栈，避免叠清单。',
    );

    final tabBranchStart = main.indexOf("if (uri.host == 'tab')");
    final tabBranchEnd = main.indexOf(
      "} else if (uri.host == 'oauth'",
      tabBranchStart,
    );
    expect(tabBranchStart, greaterThanOrEqualTo(0));
    expect(tabBranchEnd, greaterThan(tabBranchStart));
    final tabBranch = main.substring(tabBranchStart, tabBranchEnd);
    expect(tabBranch, contains('state.openTodoFromWidget();'));
    expect(tabBranch, contains('state.navigateTo(idx, allowHidden: true);'));
    expect(tabBranch, contains('if (idx == 1)'));

    expect(main, contains('void openTodoFromWidget('));
    expect(tabBranch, isNot(contains("state.navigateTo(1, allowHidden")));
    expect(
      main,
      contains('mainShellKey.currentState?.navigateTo(6, allowHidden: true)'),
      reason:
          'Fallback module links should route through the More Apps/Mine surface so hidden pages remain reachable.',
    );
    expect(
      main,
      contains('BrandRouteSurface(child: child)'),
      reason: 'Hidden fallback pages need the same route backing surface.',
    );
    expect(
      main,
      contains('_pushHiddenWidgetFallbackRoute(ctx, const GoalScreen())'),
    );
    expect(
      main,
      contains(
        '_pushHiddenWidgetFallbackRoute(ctx, const CourseScheduleScreen())',
      ),
    );
    expect(
      main,
      contains(
        '_pushHiddenWidgetFallbackRoute(ctx, const AnniversaryScreen())',
      ),
    );
    expect(
      main,
      contains('_pushHiddenWidgetFallbackRoute(ctx, const NoteScreen())'),
    );
    expect(
      File('lib/screens/today_detail_router.dart').readAsStringSync(),
      isNot(contains('DiaryEditScreen')),
    );

    expect(
      receiver,
      contains(
        'DuoyiWidgetProviderRegistry.requestUpdateForKind(context, kind)',
      ),
    );
    expect(receiver, isNot(contains('.requestUpdate(context)')));

    for (final entry in providers.entries) {
      final source = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/${entry.value.fileName}',
      ).readAsStringSync();
      expect(source, contains('detailUri(prefs, key, fallback)'));
      expect(
        source,
        contains('if (rawId.isBlank()) return Uri.parse(fallback)'),
      );
      expect(
        source,
        contains('if (rawId.startsWith("duoyi://")) return Uri.parse(rawId)'),
        reason:
            '${entry.key} should not double-encode full duoyi:// detail links saved by Flutter.',
      );
      expect(source, contains(r'Uri.parse("$fallback/${Uri.encode(rawId)}")'));
      expect(
        source,
        isNot(
          contains(
            'Uri.parse((prefs.getString(key, "") ?: "").ifBlank { fallback })',
          ),
        ),
      );
      for (var index = 1; index <= 3; index++) {
        expect(
          source,
          contains(
            'itemIntent(context, prefs, "${entry.value.keyPrefix}${index}_id", "${entry.value.fallback}")',
          ),
          reason: '${entry.key} row $index should open detail or fallback page',
        );
      }
    }
  });

  test('widget click streams are deferred before opening hidden tabs', () {
    final main = File('lib/main.dart').readAsStringSync();

    final handlerStart = main.indexOf('void handleDeepLink(Uri uri)');
    final handlerEnd = main.indexOf('void handleSharedText', handlerStart);
    expect(handlerStart, greaterThanOrEqualTo(0));
    expect(handlerEnd, greaterThan(handlerStart));
    final handler = main.substring(handlerStart, handlerEnd);
    expect(handler, contains('WidgetsBinding.instance.addPostFrameCallback'));
    expect(handler, contains('_handleWidgetUri(uri, pomodoroProvider)'));

    final widgetStreamStart = main.indexOf(
      'HomeWidgetService.widgetClickedStream.listen',
    );
    final widgetStreamEnd = main.indexOf('} catch (e, st)', widgetStreamStart);
    expect(widgetStreamStart, greaterThanOrEqualTo(0));
    expect(widgetStreamEnd, greaterThan(widgetStreamStart));
    final widgetStream = main.substring(widgetStreamStart, widgetStreamEnd);
    expect(widgetStream, contains('if (uri != null)'));
    expect(widgetStream, contains('handleDeepLink(uri)'));
    expect(
      widgetStream,
      isNot(contains('_handleWidgetUri(uri, pomodoroProvider)')),
      reason:
          'Widget stream taps should use the deferred deep-link handler so hidden tabs are not lost while the shell is attaching.',
    );

    expect(main, contains('HomeWidgetService.initialLaunchUri()'));
    expect(main, contains('DeepLinkService.takeInitialLink()'));
    expect(main, contains('_handleWidgetUri(initial, pomodoroProvider)'));
    expect(
      main,
      contains('_handleWidgetUri(initialDeepLink, pomodoroProvider)'),
    );
    expect(main, contains('final List<Uri> _pendingWidgetUris = <Uri>[]'));
    expect(
      main,
      contains('void _queuePendingWidgetUri(Uri uri, String reason)'),
    );
    expect(
      main,
      contains('void _drainPendingWidgetUris(PomodoroProvider pomodoro)'),
    );
    expect(
      main,
      contains(
        "_queuePendingWidgetUri(uri, 'main shell not ready after \$retry frames')",
      ),
      reason:
          'Deep links that arrive before the shell attaches should be queued instead of dropped.',
    );
    expect(
      main,
      contains("_drainPendingWidgetUris(context.read<PomodoroProvider>())"),
    );
    expect(main, contains("debugPrint('[DeepLink] unknown duoyi host:"));
    expect(main, contains("state.navigateTo(6, allowHidden: true);"));
  });

  test(
    'share text note route keeps brand surface instead of transparent route',
    () {
      final main = File('lib/main.dart').readAsStringSync();
      final start = main.indexOf("} else if (action == 'note') {");
      final end = main.indexOf('\n  }\n}', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final noteBranch = main.substring(start, end);

      expect(noteBranch, contains('NoteItem('));
      expect(noteBranch, contains('BrandRouteSurface(child: NoteScreen())'));
      expect(
        noteBranch,
        isNot(contains('builder: (_) => const NoteScreen()')),
        reason:
            'Share/deep-link note route must not expose a transparent Navigator background.',
      );
    },
  );
  test(
    'android widget deep link: new intent replaces the pending initial link',
    () {
      final activity = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
      ).readAsStringSync();
      final start = activity.indexOf(
        'override fun onNewIntent(intent: Intent)',
      );
      final end = activity.indexOf(
        'private fun scheduleWidgetRestoreAfterResume',
        start,
      );
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final onNewIntent = activity.substring(start, end);

      final forward = onNewIntent.indexOf(
        'channel.invokeMethod("onLink", deepLink)',
      );
      final clearPending = onNewIntent.indexOf('pendingInitialDeepLink = null');
      expect(forward, greaterThanOrEqualTo(0));
      expect(clearPending, greaterThanOrEqualTo(0));
      expect(
        clearPending,
        lessThan(forward),
        reason:
            '新 intent 已经通过 onLink 实时转发给 Dart，冷启动时记录的旧链接必须'
            '同时清掉，否则 takeInitialLink 会把过期深链再重放一次。',
      );
      // channel 还没创建（纯冷启动）时仍然只记录，等 Dart 主动来取。
      expect(
        onNewIntent,
        contains('if (deepLink != null) pendingInitialDeepLink = deepLink'),
      );
    },
  );

  test('widget todo cold start waits for local hydration before open', () {
    final main = File('lib/main.dart').readAsStringSync();
    // 公共入口保持同步 void：调用方（深链/小组件）不依赖 Future。
    expect(main, contains('void openTodoFromWidget('));
    // 带 id 但未水合时先等一次本地读取，再开栈。
    expect(main, contains('context.read<TodoProvider>().isHydrated'));
    expect(
      main,
      contains('suppressDirtyMarkWhile(() => todos.loadFromStorage())'),
      reason: '冷启动水合只是读盘，不能把读到的数据标成待上传的脏改动。',
    );
    // 等待期间的新导航与账号代际变化都必须让旧链接失效。
    expect(
      main,
      contains('if (serial != _widgetTodoNavigationSerial) return;'),
    );
    expect(main, contains('isCurrentAccountDataGeneration(generation)'));
    // 详情栈仍然由 TodayDetailRouter.open 打开，返回链规则不变。
    expect(
      main,
      contains('TodayDetailRouter.open(ctx, TodaySectionKind.todos, id: id)'),
    );
  });
}

class _ProviderRouteCheck {
  final String fileName;
  final String keyPrefix;
  final String fallback;

  const _ProviderRouteCheck({
    required this.fileName,
    required this.keyPrefix,
    required this.fallback,
  });
}
