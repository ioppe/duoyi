import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/models/goal.dart';
import 'package:duoyi/models/workspace.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/screens/goal_edit_screen.dart';
import 'package:duoyi/screens/goal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('目标编辑页通过 RecurrenceEngine 计算下一派发日并跳过节假日', () {
    final source = File('lib/screens/goal_edit_screen.dart').readAsStringSync();
    final screen = File('lib/screens/goal_screen.dart').readAsStringSync();
    final recurrence = File(
      'lib/services/recurrence_engine.dart',
    ).readAsStringSync();
    final holiday = File(
      'lib/services/holiday_calendar.dart',
    ).readAsStringSync();

    expect(source, contains("import '../services/recurrence_engine.dart';"));
    expect(source, contains('bool _skipHolidays = false;'));
    expect(source, contains('_skipHolidays = g?.skipHolidays ?? false;'));
    expect(source, contains('_SkipHolidaysSection('));
    expect(source, contains('enabled: _skipHolidays'));
    expect(
      source,
      contains('onChange: (v) => setState(() => _skipHolidays = v)'),
    );
    expect(source, contains('nextDispatchLabel: _nextDispatchLabel()'));
    expect(source, contains('RecurrenceEngine.nextOccurrence'));
    expect(source, contains('skipHolidays: _skipHolidays'));
    expect(source, contains("import '../models/workspace.dart';"));
    expect(source, contains("import '../providers/share_provider.dart';"));
    expect(source, contains("String _workspaceId = 'private';"));
    expect(
      source,
      contains('_workspaceId = _normalizeWorkspaceId(g?.workspaceId);'),
    );
    expect(source, contains('workspaceId: _workspaceId,'));
    expect(source, contains('_WorkspaceSection('));
    expect(source, contains('AppDropdownField<String>'));
    expect(source, contains('initialValue: current,'));
    expect(source, contains('enabled: canEdit'));
    expect(source, contains("option.id == 'private' || optionRole.canEdit"));
    expect(source, contains('你在这个共享空间中只有查看权限'));
    expect(source, contains('_canEditWorkspace('));
    expect(
      source,
      contains(
        'onPressed: canEditCurrentWorkspace ? _deleteCurrentGoal : null',
      ),
    );
    expect(source, contains('onPressed: canEditCurrentWorkspace'));
    expect(source, contains('_persist(pop: true)'));
    expect(
      source,
      contains('final shareProvider = context.watch<ShareProvider?>();'),
    );
    expect(source, contains('shareProvider?.canEdit(current) ?? true'));
    expect(screen, contains("import '../providers/share_provider.dart';"));
    expect(screen, contains('_SharedGoalBadge('));
    expect(screen, contains('goal.workspaceId.trim()'));
    expect(screen, contains('_workspaceLabel('));

    expect(recurrence, contains('class RecurrenceEngine'));
    expect(recurrence, contains('HolidayCalendar.isHoliday(candidate!)'));
    expect(recurrence, contains('materializeTodayFromRecurring'));
    expect(holiday, contains('class HolidayCalendar'));
    expect(holiday, contains('2026'));
    expect(holiday, contains('workMakeupDays'));
    expect(holiday, contains('updateFrom'));
  });

  test('目标编辑页日期字段在窄屏保持一行紧凑布局', () {
    final source = File('lib/screens/goal_edit_screen.dart').readAsStringSync();

    expect(source, contains('class _GoalDateFields'));
    expect(source, contains("label: '开始日期'"));
    expect(source, contains("label: '目标日期'"));
    expect(source, contains("emptyText: '创建即开启'"));
    expect(source, contains("emptyText: '无期限'"));
    expect(source, contains("ValueKey('goal_start_date_field')"));
    expect(source, contains("ValueKey('goal_target_date_field')"));
    expect(source, contains('constraints.maxWidth < 460'));
    final dateFields = _slice(
      source,
      'class _GoalDateFields',
      'Future<String?> _showGoalIconPicker',
    );
    expect(dateFields, contains('Row('));
    expect(dateFields, isNot(contains('return Column(')));
  });

  test('目标编辑页空间归属窄屏展示保留保存到并约束长文案', () {
    final source = File('lib/screens/goal_edit_screen.dart').readAsStringSync();
    final workspace = _slice(
      source,
      'class _WorkspaceSection',
      'class _GoalIconField',
    );

    expect(workspace, contains("title: '空间归属'"));
    expect(workspace, contains("labelText: '保存到'"));
    expect(
      workspace,
      contains('floatingLabelBehavior: FloatingLabelBehavior.always'),
    );
    expect(workspace, contains('mainAxisSize: MainAxisSize.max'));
    expect(workspace, contains('class _WorkspaceOptionLabel'));
    expect(workspace, contains('maxLines: 1'));
    expect(workspace, contains('TextOverflow.ellipsis'));
    expect(source, contains('subtitle!,'));
    expect(source, contains('overflow: TextOverflow.ellipsis'));
  });

  test('目标编辑页基础信息保持原输入框标签并用顶部间距避免裁切', () {
    final source = File('lib/screens/goal_edit_screen.dart').readAsStringSync();
    final basic = _slice(
      source,
      'class _BasicSection',
      'class _WorkspaceSection',
    );
    final sectionCard = _slice(
      source,
      'class _SectionCard',
      'class _DateField',
    );

    expect(basic, contains("labelText: '目标'"));
    expect(basic, contains("labelText: '描述 (可选)'"));
    expect(basic, isNot(contains("Text('目标'")));
    expect(basic, isNot(contains("Text('描述 (可选)'")));
    expect(sectionCard, contains('DesignTokens.spaceSm,'));
  });

  test('目标编辑页分组内容按表单左对齐铺满宽度', () {
    final source = File('lib/screens/goal_edit_screen.dart').readAsStringSync();
    final sectionCard = _slice(
      source,
      'class _SectionCard',
      'class _DateField',
    );

    expect(sectionCard, contains('AppFormFieldTheme('));
    expect(
      sectionCard,
      contains('crossAxisAlignment: CrossAxisAlignment.stretch'),
    );
  });

  testWidgets('新建目标窄屏日期同一行并展示空日期语义', (tester) async {
    final screenshotKey = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => CustomFocusSoundProvider()),
        ],
        child: MaterialApp(
          home: RepaintBoundary(
            key: screenshotKey,
            child: const GoalEditScreen(),
          ),
        ),
      ),
    );
    if (_shouldCaptureGoalEditScreenshot) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    } else {
      await tester.pumpAndSettle();
    }

    expect(find.text('新建目标'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('goal_start_date_field')),
        matching: find.text('开始'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('goal_target_date_field')),
        matching: find.text('目标'),
      ),
      findsOneWidget,
    );
    expect(find.text('创建即开启'), findsOneWidget);
    expect(find.text('无期限'), findsOneWidget);
    _expectTextFits(tester, find.text('创建即开启'));
    _expectTextFits(tester, find.text('无期限'));
    final startTop = tester
        .getTopLeft(find.byKey(const ValueKey('goal_start_date_field')))
        .dy;
    final targetTop = tester
        .getTopLeft(find.byKey(const ValueKey('goal_target_date_field')))
        .dy;
    expect((startTop - targetTop).abs(), lessThan(4));
    await _captureGoalEditScreenshot(screenshotKey, 'dates');
    if (_shouldCaptureGoalEditScreenshot) return;

    await tester.scrollUntilVisible(
      find.text('提醒'),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('提醒'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('开启提醒'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('目标编辑页选中日期后使用短日期避免移动端截断', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => CustomFocusSoundProvider()),
        ],
        child: MaterialApp(
          home: GoalEditScreen(
            goal: GoalItem(
              id: 'goal-with-dates',
              title: '有日期目标',
              startDate: DateTime(2026, 12, 31),
              targetDate: DateTime(2027, 1, 1),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026/12/31'), findsOneWidget);
    expect(find.text('2027/1/1'), findsOneWidget);
    _expectTextFits(tester, find.text('2026/12/31'));
    _expectTextFits(tester, find.text('2027/1/1'));
    expect(find.text('2026年12月31日'), findsNothing);
    expect(find.text('2027年1月1日'), findsNothing);
    final startClear = find.descendant(
      of: find.byKey(const ValueKey('goal_start_date_field')),
      matching: find.byIcon(Icons.close),
    );
    final targetClear = find.descendant(
      of: find.byKey(const ValueKey('goal_target_date_field')),
      matching: find.byIcon(Icons.close),
    );
    expect(startClear, findsOneWidget);
    expect(targetClear, findsOneWidget);
    await tester.tap(startClear);
    await tester.pump();
    expect(find.text('2026/12/31'), findsNothing);
    expect(find.text('创建即开启'), findsOneWidget);
    expect(targetClear, findsOneWidget);
    final startTop = tester
        .getTopLeft(find.byKey(const ValueKey('goal_start_date_field')))
        .dy;
    final targetTop = tester
        .getTopLeft(find.byKey(const ValueKey('goal_target_date_field')))
        .dy;
    expect((startTop - targetTop).abs(), lessThan(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('空间归属长名称在窄屏保留保存到标签且不溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final shareProvider = _FakeShareProvider(
      workspaces: [
        Workspace(
          id: 'shared-long',
          name: '非常非常非常非常非常长的项目协作空间名称',
          ownerUserId: 'u1',
          isPrivate: false,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          members: [
            WorkspaceMember(
              workspaceId: 'shared-long',
              userId: 'u1',
              username: 'owner',
              role: WorkspaceRole.owner,
              joinedAt: DateTime(2026),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => GoalProvider()),
          ChangeNotifierProvider(create: (_) => CustomFocusSoundProvider()),
          ChangeNotifierProvider<ShareProvider>.value(value: shareProvider),
        ],
        child: MaterialApp(
          home: GoalEditScreen(
            goal: GoalItem(
              id: 'goal-shared',
              title: '共享目标',
              workspaceId: 'shared-long',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('空间归属'), findsOneWidget);
    await tester.ensureVisible(find.text('空间归属'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('空间归属'));
    await tester.pumpAndSettle();

    expect(find.text('保存到'), findsOneWidget);
    expect(find.textContaining('非常非常'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('目标列表对无目标日期展示无期限并适配常用宽度', (tester) async {
    final provider = GoalProvider();
    await provider.add(GoalItem(id: 'goal-no-deadline', title: '长期目标'));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final size in const [
      Size(320, 720),
      Size(390, 720),
      Size(430, 720),
      Size(1024, 768),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GoalProvider>.value(value: provider),
            ChangeNotifierProvider<ShareProvider>(
              create: (_) => ShareProvider(),
            ),
          ],
          child: const MaterialApp(home: GoalScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('长期目标'), findsOneWidget);
      expect(find.text('无期限'), findsOneWidget);
      expect(
        tester.getRect(find.text('无期限')).right,
        lessThanOrEqualTo(size.width),
      );
      expect(tester.takeException(), isNull);
    }
  });

  test('目标空日期保存和读取仍为空', () async {
    final provider = GoalProvider();
    await provider.add(GoalItem(id: 'goal-null-dates', title: '无日期目标'));

    final reloaded = GoalProvider();
    await reloaded.loadFromStorage();
    final stored = reloaded.goals.singleWhere((g) => g.id == 'goal-null-dates');

    expect(stored.startDate, isNull);
    expect(stored.targetDate, isNull);
    expect(stored.toJson()['startDate'], isNull);
    expect(stored.toJson()['targetDate'], isNull);
  });
}

String _slice(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  expect(startIndex, isNot(-1), reason: 'missing start marker: $start');
  final endIndex = source.indexOf(end, startIndex);
  expect(endIndex, isNot(-1), reason: 'missing end marker: $end');
  return source.substring(startIndex, endIndex);
}

void _expectTextFits(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final context = tester.element(finder);
  final widget = tester.widget<Text>(finder);
  final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
  final style = widget.style ?? DefaultTextStyle.of(context).style;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    maxLines: 1,
  )..layout();
  final renderedWidth = tester.getSize(finder).width;

  expect(
    renderedWidth + 0.5,
    greaterThanOrEqualTo(painter.width),
    reason: '$text is visually truncated',
  );
}

class _FakeShareProvider extends ShareProvider {
  final List<Workspace> _items;

  _FakeShareProvider({required List<Workspace> workspaces})
    : _items = workspaces;

  @override
  List<Workspace> get workspaces => List.unmodifiable(_items);

  @override
  WorkspaceRole roleFor(String workspaceId) {
    if (workspaceId == 'private') return WorkspaceRole.owner;
    for (final workspace in _items) {
      if (workspace.id == workspaceId) return WorkspaceRole.owner;
    }
    return WorkspaceRole.viewer;
  }

  @override
  bool canEdit(String? workspaceId) =>
      roleFor(workspaceId ?? 'private').canEdit;
}

Future<void> _captureGoalEditScreenshot(GlobalKey key, String name) async {
  if (!_shouldCaptureGoalEditScreenshot) return;
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(
    'evidence/web-preview-1137-current/goal_edit_320_$name.png',
  );
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(data!.buffer.asUint8List());
  image.dispose();
}

bool get _shouldCaptureGoalEditScreenshot =>
    Platform.environment['DUOYI_CAPTURE_GOAL_EDIT_SCREENSHOT'] == '1';
