import 'dart:async';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/ai_todo_breakdown.dart';
import 'package:duoyi/core/app_clock.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/web_target.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/l10n/generated/app_localizations.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/models/list_group.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/list_group_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/reminder_scheduler.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:duoyi/widgets/todo_create_sheet.dart';
import 'package:duoyi/widgets/todo_subtask_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DelayedTodos extends TodoProvider {
  final pending = Completer<void>();
  int calls = 0;

  @override
  Future<void> addTodo(
    TodoItem todo, {
    bool waitForReminderSync = true,
    bool reportReminderScheduleFailure = false,
  }) async {
    calls++;
    await pending.future;
    await super.addTodo(
      todo,
      waitForReminderSync: waitForReminderSync,
      reportReminderScheduleFailure: reportReminderScheduleFailure,
    );
  }
}

class _CapturingTodos extends TodoProvider {
  final saved = <TodoItem>[];

  @override
  List<TodoItem> get todos => saved;

  @override
  Future<void> addTodo(
    TodoItem todo, {
    bool waitForReminderSync = true,
    bool reportReminderScheduleFailure = false,
  }) async => saved.add(todo);
}

class _ReadyNotifications extends NotificationService {
  DateTime? scheduledTime;

  @override
  Future<bool> ensureReadyForReminder({
    DateTime? scheduledTime,
    String issueTitle = '提醒注册失败',
    String? relatedId,
  }) async {
    this.scheduledTime = scheduledTime;
    return true;
  }
}

class _ReadyAi extends AiService {
  final AiTodoBreakdown result;
  List<String>? receivedListGroups;
  _ReadyAi(this.result);

  @override
  bool get enabled => true;

  @override
  Future<AiTodoBreakdown> breakDownTodo(
    String input, {
    required List<String> listGroups,
    DateTime? now,
  }) async {
    receivedListGroups = List.of(listGroups);
    return result;
  }
}

class _DelayedAi extends AiService {
  final pending = Completer<AiTodoBreakdown>();
  @override
  bool get enabled => true;
  @override
  Future<AiTodoBreakdown> breakDownTodo(
    String input, {
    required List<String> listGroups,
    DateTime? now,
  }) => pending.future;
}

class _SwitchableAuth extends AuthProvider {
  AuthState _current = const AuthState(userId: 'account-a', token: 'fixture');
  String _server = 'https://server-a.invalid';

  @override
  AuthState get state => _current;

  @override
  String get baseUrl => _server;

  void switchIdentity({required bool changeServer}) {
    if (changeServer) {
      _server = 'https://server-b.invalid';
    } else {
      _current = const AuthState(userId: 'account-b', token: 'fixture-b');
    }
    notifyListeners();
  }
}

class _ReadOnlyShare extends ShareProvider {
  @override
  bool canEdit(String? workspaceId) => false;
}

class _RestrictedShare extends ShareProvider {
  @override
  bool canEdit(String? workspaceId) => workspaceId != 'read-only';
}

class _ListGroupTodos extends _CapturingTodos {
  @override
  String? workspaceForListGroup(String groupName) {
    for (final todo in saved) {
      if (todo.listGroupName == groupName) return todo.workspaceId;
    }
    return null;
  }
}

Future<void> _open(
  WidgetTester tester, {
  TodoProvider? todos,
  ShareProvider? shares,
  AiService? ai,
  Size size = const Size(390, 844),
  double textScale = 1,
  ThemeData? theme,
  EisenhowerQuadrant? quadrant,
  NotificationService? notifications,
  ListGroupProvider? listGroups,
  AuthProvider? auth,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => auth ?? AuthProvider(),
        ),
        ChangeNotifierProvider<NotificationService>(
          create: (_) => notifications ?? NotificationService(),
        ),
        ChangeNotifierProvider<TodoProvider>(
          create: (_) => todos ?? TodoProvider(),
        ),
        ChangeNotifierProvider<ShareProvider>(
          create: (_) => shares ?? ShareProvider(),
        ),
        ChangeNotifierProvider<AiService>(create: (_) => ai ?? AiService()),
        ChangeNotifierProvider<ListGroupProvider>(
          create: (_) => listGroups ?? ListGroupProvider(),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppBrands.defaultBrand.theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showTodoCreateSheet(context, initialQuadrant: quadrant),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _scrollToSubmit(WidgetTester tester) async {
  final scroll = find.descendant(
    of: find.byKey(const ValueKey('todo_create_sheet')),
    matching: find.byType(SingleChildScrollView),
  );
  for (var i = 0; i < 12; i++) {
    final target = find.byKey(const ValueKey('todo_create_submit'));
    if (target.hitTestable().evaluate().isNotEmpty) return;
    await tester.drag(scroll, const Offset(0, -180));
    await tester.pumpAndSettle();
  }
  expect(
    find.byKey(const ValueKey('todo_create_submit')).hitTestable(),
    findsOneWidget,
  );
}

Future<({_CapturingTodos todos, _ReadyNotifications notifications})>
_openReminderSheet(
  WidgetTester tester, {
  AiService? ai,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  final todos = _CapturingTodos();
  final notifications = _ReadyNotifications();
  await _open(
    tester,
    todos: todos,
    notifications: notifications,
    ai: ai,
    size: size,
    textScale: textScale,
  );
  return (todos: todos, notifications: notifications);
}

Future<void> _enterCreateTitle(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('todo_create_title')), text);
  await tester.pumpAndSettle();
}

String _reminderLabel(WidgetTester tester, String key) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Text),
      ),
    )
    .data!;

bool _reminderEnabled(WidgetTester tester) => tester
    .widget<Switch>(find.byKey(const ValueKey('todo_create_reminder')))
    .value;

String _clockLabel(WidgetTester tester, TimeOfDay time) => time.format(
  tester.element(find.byKey(const ValueKey('todo_create_reminder_time'))),
);

String _expectReminderLabels(
  WidgetTester tester,
  DateTime date,
  TimeOfDay time,
) {
  expect(
    _reminderLabel(tester, 'todo_create_reminder_date'),
    I18nDateFormat.date(date),
  );
  final label = _clockLabel(tester, time);
  expect(_reminderLabel(tester, 'todo_create_reminder_time'), label);
  return label;
}

void _expectReminderPlan(TodoItem saved, DateTime at) {
  expect(saved.toJson()['reminderAt'], at.toUtc().toIso8601String());
  expect(saved.reminderPlan.enabled, isTrue);
  expect(saved.reminderPlan.rules.single.hour, at.hour);
  expect(saved.reminderPlan.rules.single.minute, at.minute);
}

Future<void> _tapAi(WidgetTester tester) async {
  final chip = find.widgetWithText(ActionChip, I18n.tr('todo.create.ai'));
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<void> _submitCreateSheet(WidgetTester tester) async {
  await _scrollToSubmit(tester);
  await tester.tap(find.byKey(const ValueKey('todo_create_submit')));
  await tester.pumpAndSettle();
}

/// 通过现有 [AppDatePicker] 的公历日期单元格选择提醒日期。
Future<void> _pickReminderDate(
  WidgetTester tester,
  DateTime day, {
  bool confirm = true,
}) async {
  final button = find.byKey(const ValueKey('todo_create_reminder_date'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.text(I18n.tr('todo.create.pick_date')), findsOneWidget);
  final cell = find.byKey(
    ValueKey(
      'solar-day-${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}',
    ),
  );
  expect(cell, findsOneWidget);
  await tester.ensureVisible(cell);
  await tester.pumpAndSettle();
  await tester.tap(cell);
  await tester.pumpAndSettle();
  final action = confirm
      ? find.widgetWithText(FilledButton, '确定')
      : find.widgetWithText(TextButton, '取消').last;
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  if (action.hitTestable().evaluate().isEmpty) {
    await tester.drag(find.byType(AppModalSheet).last, const Offset(0, -180));
    await tester.pumpAndSettle();
  }
  expect(action.hitTestable(), findsOneWidget);
  await tester.tap(action);
  await tester.pumpAndSettle();
  expect(find.text(I18n.tr('todo.create.pick_date')), findsNothing);
}

Future<void> _expandListGroup(WidgetTester tester) async {
  final selector = find.byKey(const ValueKey('todo_list_group_selector'));
  await tester.ensureVisible(selector);
  if (find.byKey(const ValueKey('todo_list_group_search')).evaluate().isEmpty) {
    await tester.tap(selector);
    await tester.pump();
  }
  final search = find.byKey(const ValueKey('todo_list_group_search'));
  await tester.ensureVisible(search);
  await tester.pump();
}

Future<void> _revealListGroupTarget(WidgetTester tester, Finder target) async {
  final options = find.byKey(const ValueKey('todo_list_group_options'));
  for (var i = 0; i < 16; i++) {
    if (target.hitTestable().evaluate().isNotEmpty) return;
    await tester.drag(options, const Offset(0, -120));
    await tester.pump();
  }
  expect(target.hitTestable(), findsOneWidget);
}

Future<void> _selectListGroup(WidgetTester tester, String name) async {
  await _expandListGroup(tester);
  final target = find.byKey(ValueKey('todo_list_group_$name'));
  await _revealListGroupTarget(tester, target);
  await tester.tap(target);
  await tester.pump();
  expect(
    tester
        .widget<Text>(
          find.byKey(const ValueKey('todo_list_group_selected_name')),
        )
        .data,
    name,
  );
}

Finder _listGroupSearch() =>
    find.byKey(const ValueKey('todo_list_group_search'));

String? _searchErrorText(WidgetTester tester) =>
    tester.widget<TextField>(_listGroupSearch()).decoration?.errorText;

String _selectedListGroup(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('todo_list_group_selected_name')))
    .data!;

Future<void> _searchListGroup(WidgetTester tester, String query) async {
  await tester.enterText(_listGroupSearch(), query);
  await tester.pump();
}

Future<void> _submitListGroupSearch(WidgetTester tester) async {
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

/// 新建动作位于结果列表内，必要时滚动到可点击位置。
Future<void> _createListGroup(WidgetTester tester) async {
  final action = find.byKey(const ValueKey('todo_list_group_create'));
  final options = find.byKey(const ValueKey('todo_list_group_options'));
  for (var i = 0; i < 16; i++) {
    if (action.hitTestable().evaluate().isNotEmpty) break;
    if (options.evaluate().isEmpty) break;
    await tester.drag(options, const Offset(0, -120));
    await tester.pump();
  }
  expect(action.hitTestable(), findsOneWidget);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(DesignTokens.fontFamilyRounded)..addFont(
          rootBundle.load('assets/fonts/ResourceHanRoundedCN-Bold.ttf'),
        ))
        .load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
    await LocalTimezoneResolver.setApplicationTimeZone('UTC');
    AppClock.debugNow = () => DateTime.utc(2026, 10, 21, 2);
  });

  tearDown(() => AppClock.debugNow = null);

  for (final changeServer in [false, true]) {
    testWidgets('账号或服务器切换会丢弃清单搜索草稿 server=$changeServer', (tester) async {
      final auth = _SwitchableAuth();
      final groups = ListGroupProvider();
      await _open(tester, auth: auth, listGroups: groups);
      await _expandListGroup(tester);
      await _searchListGroup(tester, '旧账号草稿');
      expect(_listGroupSearch(), findsOneWidget);
      expect(groups.groups, isEmpty, reason: '输入过程中不得自动创建');
      auth.switchIdentity(changeServer: changeServer);
      await tester.pumpAndSettle();
      expect(_listGroupSearch(), findsNothing);
      expect(
        find.byKey(const ValueKey('todo_list_group_create')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('todo_list_group_input')), findsNothing);
      expect(
        find.byKey(const ValueKey('todo_list_group_create_confirm')),
        findsNothing,
      );
      expect(groups.groups, isEmpty);
      await _expandListGroup(tester);
      expect(
        tester.widget<TextField>(_listGroupSearch()).controller!.text,
        isEmpty,
      );
      expect(
        find.byKey(const ValueKey('todo_list_group_create')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('键盘弹出时展开清单仍可搜索选择并收起', (tester) async {
    await _open(tester, size: const Size(320, 844), textScale: 1.5);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    await _expandListGroup(tester);
    final search = find.byKey(const ValueKey('todo_list_group_search'));
    await tester.enterText(search, '工作');
    await tester.pumpAndSettle();
    final option = find.byKey(const ValueKey('todo_list_group_工作'));
    await tester.ensureVisible(option);
    expect(option.hitTestable(), findsOneWidget);
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(search, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('收纳清单选择器与 AI 白名单共用可编辑清单', (tester) async {
    final groups = ListGroupProvider();
    await groups.create('旅行', 0);
    final now = DateTime.now();
    await groups.mergeRemote([
      ListGroup(
        id: 'shared-empty',
        name: '只读自定义',
        sortOrder: 1,
        workspaceId: 'read-only',
        createdAt: now,
        updatedAt: now,
      ).toJson(),
    ]);
    final todos = _ListGroupTodos()
      ..saved.addAll([
        TodoItem(title: '旧任务', listGroupName: '旧项目'),
        TodoItem(
          title: '共享任务',
          listGroupName: '只读项目',
          workspaceId: 'read-only',
        ),
        TodoItem(title: '共享工作', listGroupName: '工作', workspaceId: 'read-only'),
      ]);
    final ai = _ReadyAi(
      const AiTodoBreakdown(subtasks: ['准备行李'], listGroupName: '旅行'),
    );
    await _open(
      tester,
      listGroups: groups,
      todos: todos,
      shares: _RestrictedShare(),
      ai: ai,
    );
    await tester.enterText(
      find.byKey(const ValueKey('todo_create_title')),
      '准备假期',
    );
    await tester.tap(
      find.widgetWithText(ActionChip, I18n.tr('todo.create.ai')),
    );
    await tester.pumpAndSettle();
    expect(
      ai.receivedListGroups,
      containsAll(['个人', '学习', '购物', '阅读清单', '健身', '旅行', '旧项目']),
    );
    expect(ai.receivedListGroups, isNot(contains('工作')));
    expect(ai.receivedListGroups, isNot(contains('只读自定义')));
    expect(ai.receivedListGroups, isNot(contains('只读项目')));

    await _selectListGroup(tester, '旅行');
    expect(find.byKey(const ValueKey('todo_list_group_search')), findsNothing);
    await _expandListGroup(tester);
    final search = find.byKey(const ValueKey('todo_list_group_search'));
    await tester.enterText(search, '旧');
    await tester.pump();
    expect(find.byKey(const ValueKey('todo_list_group_旧项目')), findsOneWidget);
    await tester.enterText(search, '只读');
    await tester.pump();
    expect(find.byKey(const ValueKey('todo_list_group_只读自定义')), findsNothing);
    expect(find.byKey(const ValueKey('todo_list_group_只读项目')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('展开面板内搜索新建清单并随待办保存 id 和名称', (tester) async {
    final groups = ListGroupProvider();
    final todos = _CapturingTodos();
    await _open(tester, listGroups: groups, todos: todos);
    await tester.enterText(
      find.byKey(const ValueKey('todo_create_title')),
      '准备旅行',
    );
    await _expandListGroup(tester);
    expect(_listGroupSearch(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('todo_list_group_options')),
      findsOneWidget,
    );
    await _searchListGroup(tester, '  旅行  ');
    expect(groups.groups, isEmpty, reason: '输入过程中不得自动创建');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('todo_list_group_input')), findsNothing);
    await _createListGroup(tester);
    expect(_selectedListGroup(tester), '旅行');
    expect(_listGroupSearch(), findsNothing);
    expect(groups.groups.single.name, '旅行');
    await _scrollToSubmit(tester);
    await tester.tap(find.byKey(const ValueKey('todo_create_submit')));
    await tester.pumpAndSettle();
    expect(todos.saved.single.listGroupName, '旅行');
    expect(todos.saved.single.listGroupId, groups.groups.single.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索补全复用内置、自定义和历史清单并在字段内显示校验', (tester) async {
    final groups = ListGroupProvider();
    final travel = await groups.create('Travel', 0);
    final todos = _CapturingTodos()
      ..saved.add(TodoItem(title: '旧任务', listGroupName: '旧项目'));
    await _open(tester, listGroups: groups, todos: todos);

    await _expandListGroup(tester);
    await _searchListGroup(tester, '旧');
    await tester.pumpAndSettle();
    final suggestion = find.byKey(const ValueKey('todo_list_group_旧项目'));
    expect(suggestion, findsOneWidget);
    await tester.tap(suggestion);
    await tester.pumpAndSettle();
    expect(_selectedListGroup(tester), '旧项目');
    expect(groups.groups, hasLength(1));
    expect(find.byKey(const ValueKey('todo_list_group_input')), findsNothing);

    // 输入完全匹配内置清单时 Enter 复用，不新建。
    await _expandListGroup(tester);
    await _searchListGroup(tester, '工作');
    expect(find.byKey(const ValueKey('todo_list_group_create')), findsNothing);
    await _submitListGroupSearch(tester);
    expect(_selectedListGroup(tester), '工作');
    expect(_listGroupSearch(), findsNothing);

    // 归一化同名（大小写与首尾空格）同样复用已有自定义清单。
    await _expandListGroup(tester);
    await _searchListGroup(tester, ' travel ');
    expect(find.byKey(const ValueKey('todo_list_group_create')), findsNothing);
    await _submitListGroupSearch(tester);
    expect(_selectedListGroup(tester), 'Travel');
    expect(_listGroupSearch(), findsNothing);
    expect(groups.groups.single.id, travel.id);

    // 完全匹配历史清单也不新建。
    await _expandListGroup(tester);
    await _searchListGroup(tester, '旧项目');
    expect(find.byKey(const ValueKey('todo_list_group_create')), findsNothing);
    await _submitListGroupSearch(tester);
    expect(_selectedListGroup(tester), '旧项目');
    expect(groups.groups, hasLength(1));

    // 空输入没有新建动作。
    await _expandListGroup(tester);
    expect(find.byKey(const ValueKey('todo_list_group_create')), findsNothing);

    // 超长输入的校验显示在搜索框内，编辑后清除。
    final tooLong = List.filled(25, '旅').join();
    await _searchListGroup(tester, tooLong);
    expect(
      find.text(
        I18n.tr('list_group.create_named').replaceAll('{name}', tooLong),
      ),
      findsOneWidget,
    );
    await _createListGroup(tester);
    expect(_searchErrorText(tester), I18n.tr('list_group.name_length'));
    expect(groups.groups, hasLength(1));
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await _searchListGroup(tester, '假期');
    expect(_searchErrorText(tester), isNull);
    expect(find.byKey(const ValueKey('todo_list_group_input')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自定义清单通过可见菜单重命名和删除，内置清单无管理入口', (tester) async {
    final groups = ListGroupProvider();
    final initial = await groups.create('旅行', 0);
    await _open(tester, listGroups: groups);
    await _selectListGroup(tester, '旅行');
    await _expandListGroup(tester);
    final manage = find.byKey(ValueKey('todo_list_group_manage_${initial.id}'));
    await _revealListGroupTarget(tester, manage);
    expect(manage, findsOneWidget);
    await tester.tap(manage);
    await tester.pumpAndSettle();
    await tester.tap(find.text(I18n.tr('list_group.rename')));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('todo_list_group_input'));
    expect(tester.widget<TextField>(input).controller!.text, '旅行');
    await tester.enterText(input, '   ');
    await tester.tap(
      find.byKey(const ValueKey('todo_list_group_create_confirm')),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(input).decoration?.errorText,
      I18n.tr('list_group.name_required'),
    );
    expect(groups.groups.single.name, '旅行');
    await tester.enterText(input, '假期');
    await tester.pump();
    expect(tester.widget<TextField>(input).decoration?.errorText, isNull);
    await tester.tap(
      find.byKey(const ValueKey('todo_list_group_create_confirm')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('todo_list_group_selected_name')),
          )
          .data,
      '假期',
    );
    expect(groups.groups.single.id, initial.id);

    await _expandListGroup(tester);
    await _revealListGroupTarget(tester, manage);
    await tester.tap(manage);
    await tester.pumpAndSettle();
    await tester.tap(find.text(I18n.tr('action.delete')));
    await tester.pumpAndSettle();
    expect(groups.groups, isEmpty);
    expect(groups.allGroups.single.isDeleted, isTrue);
    expect(find.byKey(const ValueKey('todo_list_group_假期')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('主输入在手机长文本时自动换行并增高', (tester) async {
    await _open(tester, size: const Size(320, 900));
    final title = find.byKey(const ValueKey('todo_create_title'));
    await tester.enterText(title, '短任务');
    await tester.pumpAndSettle();
    final short = tester.getSize(title).height;
    await tester.enterText(
      title,
      List.filled(5, '明天下午3点到3楼B15参加云计算项目评审并准备真实尖锐的问题。').join(),
    );
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(title);
    expect(field.maxLines, isNull);
    expect(field.keyboardType, TextInputType.multiline);
    expect(tester.getSize(title).height, greaterThan(short + 20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI精简名称、完整描述和编辑后的子任务一同保存且不丢时间', (tester) async {
    const original =
        '明天下午3点到3楼B15房间参加云计算项目评审，要先准备评审问题，评审问题必须真实且尖锐。\n保留完整地点和要求。';
    final todos = _CapturingTodos();
    final notifications = _ReadyNotifications();
    await _open(
      tester,
      todos: todos,
      notifications: notifications,
      ai: _ReadyAi(
        const AiTodoBreakdown(
          title: '准备问题并参加云计算评审',
          subtasks: ['收集资料', '核实证据', '整理问题'],
        ),
      ),
    );
    final title = find.byKey(const ValueKey('todo_create_title'));
    await tester.enterText(title, original);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(ActionChip, I18n.tr('todo.create.ai')),
    );
    await tester.tap(
      find.widgetWithText(ActionChip, I18n.tr('todo.create.ai')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(title).controller!.text, '准备问题并参加云计算评审');
    final description = find.byKey(const ValueKey('todo_create_description'));
    expect(tester.widget<TextField>(description).controller!.text, original);
    final editor = find.byType(TodoSubtaskEditor);
    var items = tester.widget<TodoSubtaskEditor>(editor).subtasks;
    final firstId = items.first.id;
    await tester.ensureVisible(
      find.byKey(ValueKey('todo_subtask_text_$firstId')),
    );
    await tester.enterText(
      find.byKey(ValueKey('todo_subtask_text_$firstId')),
      '收集方案和测试报告',
    );
    await tester.pumpAndSettle();
    final deletedId = items[1].id;
    await tester.ensureVisible(
      find.byKey(ValueKey('todo_subtask_delete_$deletedId')),
    );
    await tester.tap(find.byKey(ValueKey('todo_subtask_delete_$deletedId')));
    await tester.pumpAndSettle();
    final add = find.byKey(const ValueKey('todo_subtask_add_input'));
    await tester.ensureVisible(add);
    await tester.enterText(add, '补充追问');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('todo_subtask_add')));
    await tester.tap(find.byKey(const ValueKey('todo_subtask_add')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(title);
    await tester.enterText(title, '云计算评审准备');
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(ActionChip, I18n.tr('todo.create.ai')),
    );
    await tester.tap(
      find.widgetWithText(ActionChip, I18n.tr('todo.create.ai')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(title).controller!.text, '云计算评审准备');
    expect(tester.widget<TextField>(description).controller!.text, original);
    expect(tester.widget<TodoSubtaskEditor>(editor).subtasks.first.id, firstId);
    await _scrollToSubmit(tester);
    await tester.tap(find.byKey(const ValueKey('todo_create_submit')));
    await tester.pumpAndSettle();
    final saved = todos.saved.single;
    expect(saved.title, '云计算评审准备');
    expect(saved.notes, original);
    expect(saved.subtasks.map((item) => item.title), [
      '收集方案和测试报告',
      '整理问题',
      '补充追问',
    ]);
    expect(saved.subtasks.first.id, firstId);
    expect(saved.subtasks.map((item) => item.sortOrder), [0, 1, 2]);
    expect(saved.date, AppClock.date(2026, 10, 22, 15));
    expect(notifications.scheduledTime, saved.date);
    expect(tester.takeException(), isNull);
  });

  for (final item in [
    (
      name: 'ISO UTC 完整时间',
      zone: 'Asia/Shanghai',
      now: DateTime.utc(2026, 10, 21, 2),
      input: '2026-10-23T02:30:00Z 开会',
      expected: DateTime.utc(2026, 10, 23, 2, 30),
      ai: false,
    ),
    (
      name: '跨午夜同分钟顺延',
      zone: 'UTC',
      now: DateTime.utc(2026, 10, 21, 23, 59, 35),
      input: '今天23:59整理资料',
      expected: DateTime.utc(2026, 10, 22),
      ai: false,
    ),
    (
      name: '重复任务下一次时间',
      zone: 'Asia/Shanghai',
      now: DateTime.utc(2026, 10, 21, 2),
      input: '每天上午9点跑步',
      expected: DateTime.utc(2026, 10, 22, 1),
      ai: false,
    ),
    (
      name: '纽约回拨第二次01:30',
      zone: 'America/New_York',
      now: DateTime.utc(2026, 11, 1, 5, 45),
      input: '整理会议资料',
      expected: DateTime.utc(2026, 11, 1, 6, 30),
      ai: true,
    ),
  ]) {
    testWidgets('${item.name} 的预览、保存与提醒保持一致', (tester) async {
      await LocalTimezoneResolver.setApplicationTimeZone(item.zone);
      AppClock.debugNow = () => item.now;
      final todos = _CapturingTodos();
      final notifications = _ReadyNotifications();
      final expected = AppClock.toLocal(item.expected);
      await _open(
        tester,
        todos: todos,
        notifications: notifications,
        ai: _ReadyAi(
          AiTodoBreakdown(
            subtasks: const ['准备资料'],
            dateTime: expected,
            hasTimeOfDay: true,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('todo_create_title')),
        item.input,
      );
      if (item.ai) {
        await tester.tap(
          find.widgetWithText(ActionChip, I18n.tr('todo.create.ai')),
        );
      }
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          I18nDateFormat.smartDate(expected, includeTime: true),
        ),
        findsOneWidget,
      );
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      await _scrollToSubmit(tester);
      await tester.tap(find.byKey(const ValueKey('todo_create_submit')));
      await tester.pumpAndSettle();
      expect(todos.saved.single.date.toUtc(), item.expected);
      expect(notifications.scheduledTime!.toUtc(), item.expected);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Web 保存提醒配置并说明系统通知限制，不阻止任务创建', (tester) async {
    WebTarget.debugWebBuild = true;
    addTearDown(() => WebTarget.debugWebBuild = null);
    final todos = _CapturingTodos();
    await _open(tester, todos: todos);
    await tester.enterText(
      find.byKey(const ValueKey('todo_create_title')),
      '后天下午3点会议',
    );
    await tester.pumpAndSettle();
    await _scrollToSubmit(tester);
    await tester.tap(find.byKey(const ValueKey('todo_create_submit')));
    await tester.pumpAndSettle();
    expect(todos.saved.single.reminderPlan.enabled, isTrue);
    expect(todos.saved.single.reminderPlan.rules.single.hour, 15);
    expect(
      find.text(I18n.tr('todo.create.created_web_reminder')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI 自动填写清单和象限，并保存有序子任务与到点提醒', (tester) async {
    await LocalTimezoneResolver.setApplicationTimeZone('Asia/Shanghai');
    final todos = _CapturingTodos();
    final notifications = _ReadyNotifications();
    await _open(
      tester,
      todos: todos,
      notifications: notifications,
      ai: _ReadyAi(
        AiTodoBreakdown(
          subtasks: const ['确认会议地点', '查找云计算资料', '整理会议摘要'],
          listGroupName: '学习',
          quadrant: EisenhowerQuadrant.urgentImportant,
          dateTime: AppClock.date(2030, 1, 1, 9),
          hasTimeOfDay: true,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('todo_create_title')),
      '后天下午3点参加周老师的云计算资料会议',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(ActionChip, I18n.tr('todo.create.ai')),
    );
    await tester.pumpAndSettle();
    expect(todos.saved, isEmpty, reason: '拆解只填入草稿，等待统一保存');
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('todo_list_group_selected_name')),
          )
          .data,
      '学习',
    );
    expect(
      tester
          .state<FormFieldState<EisenhowerQuadrant>>(
            find.byType(FormField<EisenhowerQuadrant>),
          )
          .value,
      EisenhowerQuadrant.urgentImportant,
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.text('确认会议地点'), findsOneWidget);
    expect(find.textContaining('Asia/Shanghai'), findsOneWidget);
    await _scrollToSubmit(tester);
    await tester.tap(find.byKey(const ValueKey('todo_create_submit')));
    await tester.pumpAndSettle();
    final saved = todos.saved.single;
    expect(saved.listGroupName, '学习');
    expect(saved.quadrant, EisenhowerQuadrant.urgentImportant);
    expect(saved.priority, TodoPriority.none);
    expect(saved.subtasks.map((item) => item.title), [
      '确认会议地点',
      '查找云计算资料',
      '整理会议摘要',
    ]);
    expect(saved.subtasks.map((item) => item.sortOrder), [0, 1, 2]);
    expect(saved.subtasks.every((item) => !item.isCompleted), isTrue);
    expect(saved.date, AppClock.date(2026, 10, 23, 15));
    expect(saved.dueDate, saved.date);
    expect(saved.reminderPlan.enabled, isTrue);
    expect(saved.reminderPlan.rules.single.hour, 15);
    expect(notifications.scheduledTime!.toUtc(), DateTime.utc(2026, 10, 23, 7));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI 可补充本地未识别的时间，无具体时间时不推断提醒', (tester) async {
    for (final timed in [true, false]) {
      final todos = _CapturingTodos();
      final notifications = _ReadyNotifications();
      final at = AppClock.date(2026, 10, 28, timed ? 16 : 0, timed ? 30 : 0);
      await _open(
        tester,
        todos: todos,
        notifications: notifications,
        ai: _ReadyAi(
          AiTodoBreakdown(
            subtasks: const ['整理资料'],
            listGroupName: '工作',
            dateTime: at,
            hasTimeOfDay: timed,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('todo_create_title')),
        '评审前整理资料',
      );
      await tester.tap(
        find.widgetWithText(ActionChip, I18n.tr('todo.create.ai')),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, timed);
      await _scrollToSubmit(tester);
      await tester.tap(find.byKey(const ValueKey('todo_create_submit')));
      await tester.pumpAndSettle();
      expect(todos.saved.single.date, at);
      expect(todos.saved.single.reminderPlan.enabled, timed);
      expect(notifications.scheduledTime, timed ? at : null);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('等待 AI 时保留手动清单、象限和关闭提醒，禁止抢先保存', (tester) async {
    final ai = _DelayedAi();
    final todos = _CapturingTodos();
    await _open(tester, ai: ai, todos: todos);
    await tester.enterText(
      find.byKey(const ValueKey('todo_create_title')),
      '后天下午3点会议',
    );
    await tester.tap(
      find.widgetWithText(ActionChip, I18n.tr('todo.create.ai')),
    );
    await tester.pump();
    await _selectListGroup(tester, '个人');
    tester
        .widget<AppDropdownField<EisenhowerQuadrant>>(
          find.byKey(const ValueKey('todo_create_quadrant')),
        )
        .onChanged(EisenhowerQuadrant.notUrgentNotImportant);
    await tester.pump();
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('todo_create_submit')),
          )
          .onPressed,
      isNull,
    );
    ai.pending.complete(
      const AiTodoBreakdown(
        subtasks: ['准备会议资料'],
        listGroupName: '工作',
        quadrant: EisenhowerQuadrant.urgentImportant,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('todo_list_group_selected_name')),
          )
          .data,
      '个人',
    );
    expect(
      tester
          .state<FormFieldState<EisenhowerQuadrant>>(
            find.byType(FormField<EisenhowerQuadrant>),
          )
          .value,
      EisenhowerQuadrant.notUrgentNotImportant,
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await _scrollToSubmit(tester);
    await tester.tap(find.byKey(const ValueKey('todo_create_submit')));
    await tester.pumpAndSettle();
    expect(todos.saved.single.listGroupName, '个人');
    expect(
      todos.saved.single.quadrant,
      EisenhowerQuadrant.notUrgentNotImportant,
    );
    expect(todos.saved.single.reminderPlan.enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final changeZone in [false, true]) {
    testWidgets('旧 AI 结果在输入或时区变化后丢弃，changeZone=$changeZone', (tester) async {
      final ai = _DelayedAi();
      final todos = _CapturingTodos();
      await _open(tester, ai: ai, todos: todos);
      final title = find.byKey(const ValueKey('todo_create_title'));
      await tester.enterText(title, '整理旧资料');
      await tester.tap(
        find.widgetWithText(ActionChip, I18n.tr('todo.create.ai')),
      );
      await tester.pump();
      if (changeZone) {
        await LocalTimezoneResolver.setApplicationTimeZone('America/New_York');
      } else {
        await tester.enterText(title, '整理新资料');
      }
      ai.pending.complete(
        AiTodoBreakdown(
          subtasks: const ['过期子任务'],
          listGroupName: '工作',
          quadrant: EisenhowerQuadrant.urgentImportant,
          dateTime: AppClock.date(2026, 10, 28, 16),
          hasTimeOfDay: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('过期子任务'), findsNothing);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('todo_list_group_selected_name')),
            )
            .data,
        I18n.tr('list_group.ungrouped'),
      );
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await _scrollToSubmit(tester);
      await tester.tap(find.byKey(const ValueKey('todo_create_submit')));
      await tester.pumpAndSettle();
      expect(todos.saved.single.subtasks, isEmpty);
      expect(todos.saved.single.listGroupName, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (zone, day, utcHour) in [
    ('Asia/Shanghai', 23, 7),
    ('America/New_York', 22, 19),
  ]) {
    testWidgets('$zone 相对日期预览、保存和提醒使用同一应用时区', (tester) async {
      await LocalTimezoneResolver.setApplicationTimeZone(zone);
      final todos = _CapturingTodos();
      final notifications = _ReadyNotifications();
      await _open(tester, todos: todos, notifications: notifications);
      await tester.enterText(
        find.byKey(const ValueKey('todo_create_title')),
        '后天下午3点开会',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(zone), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      await _scrollToSubmit(tester);
      await tester.tap(find.byKey(const ValueKey('todo_create_submit')));
      await tester.pumpAndSettle();
      expect(todos.saved.single.date, AppClock.date(2026, 10, day, 15));
      expect(
        notifications.scheduledTime!.toUtc(),
        DateTime.utc(2026, 10, day, utcHour),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('只有日期和明确过去的时间不会自动开启提醒', (tester) async {
    await _open(tester);
    for (final text in ['后天整理资料', '昨天下午3点会议']) {
      await tester.enterText(
        find.byKey(const ValueKey('todo_create_title')),
        text,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('具体时间自动打开提醒，关闭后保存不再保留隐式提醒', (tester) async {
    await LocalTimezoneResolver.setApplicationTimeZone('Asia/Shanghai');
    AppClock.debugNow = () => DateTime.utc(2026, 10, 21, 2);
    addTearDown(() => AppClock.debugNow = null);
    final todos = TodoProvider();
    await _open(tester, todos: todos);
    await tester.enterText(
      find.byKey(const ValueKey('todo_create_title')),
      '后天下午3点参加云计算资料会议',
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await _scrollToSubmit(tester);
    await tester.tap(find.byKey(const ValueKey('todo_create_submit')));
    await tester.pumpAndSettle();
    final saved = todos.todos.single;
    expect(saved.reminder.enabled, isFalse);
    expect(saved.reminderPlan.enabled, isFalse);
    // ignore: deprecated_member_use_from_same_package
    expect(saved.hasReminder, isFalse);
    // ignore: deprecated_member_use_from_same_package
    expect(saved.reminderAt, isNull);
    expect(AppClock.toLocal(saved.date).hour, 15);
    expect(saved.date.day, 23);
    expect(tester.takeException(), isNull);
  });

  testWidgets('共享表单保存清单和象限，不再提供优先级标记且阻止重复提交', (tester) async {
    final todos = _DelayedTodos();
    await _open(
      tester,
      todos: todos,
      quadrant: EisenhowerQuadrant.urgentNotImportant,
    );
    await tester.enterText(
      find.byKey(const ValueKey('todo_create_title')),
      '共享表单验收',
    );
    await _selectListGroup(tester, '工作');
    expect(find.text(I18n.tr('todo.create.priority')), findsNothing);
    expect(
      find.widgetWithText(ChoiceChip, TodoPriority.high.label),
      findsNothing,
    );
    await _scrollToSubmit(tester);
    final save = tester
        .widget<FilledButton>(find.byKey(const ValueKey('todo_create_submit')))
        .onPressed!;
    save();
    save();
    await tester.pump();
    expect(todos.calls, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('todo_create_submit')),
          )
          .onPressed,
      isNull,
    );
    todos.pending.complete();
    await tester.pumpAndSettle();
    final saved = todos.todos.single;
    expect(saved.title, '共享表单验收');
    expect(saved.listGroupName, '工作');
    expect(saved.quadrant, EisenhowerQuadrant.urgentNotImportant);
    expect(saved.priority, TodoPriority.none);
    expect(find.byType(AppModalSheet), findsNothing);
    expect(find.text(I18n.tr('todo.create.created')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 1.5]) {
    testWidgets('实际新建表单四象限菜单 ×$scale 紧贴字段并可选择', (tester) async {
      await _open(tester, textScale: scale);
      final anchor = find.byKey(const ValueKey('todo_create_quadrant'));
      await tester.ensureVisible(anchor);
      await tester.pumpAndSettle();
      await tester.tap(anchor);
      for (
        var i = 0;
        i < 24 &&
            find.byType(PopupMenuItem<EisenhowerQuadrant>).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      final entries = find.byType(PopupMenuItem<EisenhowerQuadrant>);
      expect(entries, findsNWidgets(4));
      final menuRect = tester.getRect(
        find.ancestor(of: entries.first, matching: find.byType(Material)).first,
      );
      final anchorRect = tester.getRect(anchor);
      final gap = menuRect.top >= anchorRect.bottom
          ? menuRect.top - anchorRect.bottom
          : anchorRect.top - menuRect.bottom;
      expect(gap, closeTo(6, 1));
      expect(menuRect.left, closeTo(anchorRect.left, 1));
      expect(menuRect.width, closeTo(anchorRect.width, 1));
      await tester.tap(entries.at(2));
      await tester.pumpAndSettle();
      expect(
        tester
            .state<FormFieldState<EisenhowerQuadrant>>(
              find.byType(FormField<EisenhowerQuadrant>),
            )
            .value,
        EisenhowerQuadrant.urgentNotImportant,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final (size, keyboard) in [
    (const Size(320, 720), 0.0),
    (const Size(390, 844), 300.0),
    (const Size(1440, 900), 0.0),
  ]) {
    testWidgets('$size keyboard=$keyboard 表单可展开、收回并点击遮罩关闭', (tester) async {
      final todos = TodoProvider();
      await _open(
        tester,
        todos: todos,
        size: size,
        textScale: 1.5,
        theme: AppBrands.starRail.theme,
      );
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      await tester.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('todo_create_sheet'));
      final card = tester.getRect(
        find.descendant(of: sheet, matching: find.byType(Material)).first,
      );
      final available = size.height - keyboard;
      expect(
        card.height,
        inInclusiveRange(available / 2, available * 2 / 3 + 1),
      );
      expect(card.bottom, closeTo(available, 1));
      expect(
        tester.getSize(find.byKey(const ValueKey('todo_create_title'))).height,
        greaterThanOrEqualTo(DesignTokens.formFieldMinHeight),
      );
      await _scrollToSubmit(tester);
      final scroll = find.descendant(
        of: sheet,
        matching: find.byType(SingleChildScrollView),
      );
      final scrollRect = tester.getRect(scroll);
      final start = Offset(scrollRect.left + 4, scrollRect.center.dy);
      await tester.dragFrom(start, const Offset(0, 3000));
      await tester.pumpAndSettle();
      await tester.dragFrom(start, const Offset(0, 100));
      await tester.pumpAndSettle();
      final collapsed = tester.getRect(
        find.descendant(of: sheet, matching: find.byType(Material)).first,
      );
      expect(collapsed.height, closeTo(card.height, 1));
      await tester.tapAt(Offset(collapsed.center.dx, collapsed.top - 15));
      await tester.pumpAndSettle();
      expect(find.byType(AppModalSheet), findsNothing);
      expect(todos.todos, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('只读工作区创建被拦截，表单保留输入', (tester) async {
    final todos = TodoProvider();
    await _open(tester, todos: todos, shares: _ReadOnlyShare());
    await tester.enterText(
      find.byKey(const ValueKey('todo_create_title')),
      '只读验收',
    );
    await _scrollToSubmit(tester);
    await tester.tap(find.byKey(const ValueKey('todo_create_submit')));
    await tester.pumpAndSettle();
    expect(todos.todos, isEmpty);
    expect(find.byType(AppModalSheet), findsOneWidget);
    expect(find.text('只读验收'), findsOneWidget);
    expect(find.text(I18n.tr('todo.create.read_only')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI 返回前关闭添加表单不会写入或更新已销毁状态', (tester) async {
    final ai = _DelayedAi();
    final todos = TodoProvider();
    await _open(tester, todos: todos, ai: ai);
    await tester.enterText(
      find.byKey(const ValueKey('todo_create_title')),
      '拆解验收',
    );
    await tester.tap(
      find.widgetWithText(ActionChip, I18n.tr('todo.create.ai')),
    );
    await tester.pump();
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 500));
    ai.pending.complete(const AiTodoBreakdown(subtasks: ['稍后返回的子任务']));
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsNothing);
    expect(todos.todos, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI 完整日期时间填充提醒日期与时间并保存到点提醒', (tester) async {
    final at = AppClock.date(2026, 11, 1, 10, 30);
    final (:todos, :notifications) = await _openReminderSheet(
      tester,
      size: const Size(320, 844),
      textScale: 1.5,
      ai: _ReadyAi(
        AiTodoBreakdown(subtasks: const [], dateTime: at, hasTimeOfDay: true),
      ),
    );
    await _enterCreateTitle(tester, '整理会议资料');
    expect(_reminderEnabled(tester), isFalse);
    expect(
      find.byKey(const ValueKey('todo_create_reminder_date')),
      findsNothing,
    );
    await _tapAi(tester);
    expect(_reminderEnabled(tester), isTrue);
    final time = _expectReminderLabels(
      tester,
      at,
      const TimeOfDay(hour: 10, minute: 30),
    );
    expect(
      tester.widget<Text>(find.text(I18n.tr('todo.create.at_time'))).data,
      isNot(contains(time)),
    );
    final dateButton = find.byKey(const ValueKey('todo_create_reminder_date'));
    final timeButton = find.byKey(const ValueKey('todo_create_reminder_time'));
    await tester.ensureVisible(dateButton);
    await tester.ensureVisible(timeButton);
    expect(dateButton.hitTestable(), findsOneWidget);
    expect(timeButton.hitTestable(), findsOneWidget);
    await _submitCreateSheet(tester);
    final saved = todos.saved.single;
    expect(saved.date, at);
    _expectReminderPlan(saved, at);
    expect(notifications.scheduledTime!.toUtc(), at.toUtc());
    expect(tester.takeException(), isNull);
  });

  testWidgets('本地日期同日 AI 补全时间，冲突日期不覆盖完整本地时间', (tester) async {
    for (final (input, aiAt, before, hour, minute) in [
      ('明天参加会议', AppClock.date(2026, 10, 22, 15, 30), false, 15, 30),
      ('明天下午3点会议', AppClock.date(2026, 10, 24, 9), true, 15, 0),
    ]) {
      final (:todos, :notifications) = await _openReminderSheet(
        tester,
        ai: _ReadyAi(
          AiTodoBreakdown(
            subtasks: const [],
            dateTime: aiAt,
            hasTimeOfDay: true,
          ),
        ),
      );
      await _enterCreateTitle(tester, input);
      expect(_reminderEnabled(tester), before);
      if (!before) {
        expect(
          find.byKey(const ValueKey('todo_create_reminder_date')),
          findsNothing,
        );
      }
      await _tapAi(tester);
      expect(_reminderEnabled(tester), isTrue);
      _expectReminderLabels(
        tester,
        DateTime(2026, 10, 22),
        TimeOfDay(hour: hour, minute: minute),
      );
      await _submitCreateSheet(tester);
      final expectedAt = DateTime.utc(2026, 10, 22, hour, minute);
      _expectReminderPlan(todos.saved.single, expectedAt);
      expect(notifications.scheduledTime!.toUtc(), expectedAt);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('手动提醒日期只改提醒锚点，任务日期与序列化预检保持独立', (tester) async {
    final (:todos, notifications: _) = await _openReminderSheet(tester);
    await _enterCreateTitle(tester, '明天下午3点会议');
    expect(_reminderEnabled(tester), isTrue);
    _expectReminderLabels(
      tester,
      DateTime(2026, 10, 22),
      const TimeOfDay(hour: 15, minute: 0),
    );
    await _pickReminderDate(tester, DateTime(2026, 10, 25));
    _expectReminderLabels(
      tester,
      DateTime(2026, 10, 25),
      const TimeOfDay(hour: 15, minute: 0),
    );
    await _submitCreateSheet(tester);
    final saved = todos.saved.single;
    final taskAt = AppClock.date(2026, 10, 22, 15);
    expect(saved.date, taskAt);
    expect(saved.dueDate, taskAt);
    _expectReminderPlan(saved, DateTime.utc(2026, 10, 25, 15));
    final preflight = preflightTodoReminderPlan(
      TodoItem.fromJson(saved.toJson()),
    );
    expect(preflight.blockingIssue, isNull);
    expect(
      preflight.firstScheduledTime!.toUtc(),
      DateTime.utc(2026, 10, 25, 15),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI 返回不覆盖已手动选择的提醒日期', (tester) async {
    final (:todos, :notifications) = await _openReminderSheet(
      tester,
      ai: _ReadyAi(
        AiTodoBreakdown(
          subtasks: const [],
          dateTime: AppClock.date(2026, 10, 23, 15, 30),
          hasTimeOfDay: true,
        ),
      ),
    );
    await _enterCreateTitle(tester, '后天下午3点会议');
    await _pickReminderDate(tester, DateTime(2026, 10, 26));
    await _tapAi(tester);
    expect(_reminderEnabled(tester), isTrue);
    _expectReminderLabels(
      tester,
      DateTime(2026, 10, 26),
      const TimeOfDay(hour: 15, minute: 0),
    );
    await _submitCreateSheet(tester);
    final saved = todos.saved.single;
    expect(saved.date, AppClock.date(2026, 10, 23, 15));
    _expectReminderPlan(saved, DateTime.utc(2026, 10, 26, 15));
    expect(
      notifications.scheduledTime!.toUtc(),
      DateTime.utc(2026, 10, 26, 15),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('取消日期选择保留原提醒日期与时间', (tester) async {
    final (:todos, notifications: _) = await _openReminderSheet(tester);
    await _enterCreateTitle(tester, '后天下午3点会议');
    await _pickReminderDate(tester, DateTime(2026, 10, 28), confirm: false);
    _expectReminderLabels(
      tester,
      DateTime(2026, 10, 23),
      const TimeOfDay(hour: 15, minute: 0),
    );
    await _submitCreateSheet(tester);
    _expectReminderPlan(todos.saved.single, DateTime.utc(2026, 10, 23, 15));
    expect(tester.takeException(), isNull);
  });

  testWidgets('过去提醒在表单内提示，关闭开关后可保存无提醒任务', (tester) async {
    final (:todos, notifications: _) = await _openReminderSheet(tester);
    await _enterCreateTitle(tester, '昨天下午3点会议');
    expect(_reminderEnabled(tester), isFalse);
    final reminderSwitch = find.byKey(const ValueKey('todo_create_reminder'));
    await tester.ensureVisible(reminderSwitch);
    await tester.tap(reminderSwitch);
    await tester.pumpAndSettle();
    expect(_reminderEnabled(tester), isTrue);
    _expectReminderLabels(
      tester,
      DateTime(2026, 10, 20),
      const TimeOfDay(hour: 15, minute: 0),
    );
    await _submitCreateSheet(tester);
    final error = find.byKey(const ValueKey('todo_create_reminder_error'));
    expect(
      tester.widget<Text>(error).data,
      I18n.tr('todo.create.reminder_past'),
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(todos.saved, isEmpty);
    await tester.ensureVisible(reminderSwitch);
    await tester.tap(reminderSwitch);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('todo_create_reminder_error')),
      findsNothing,
    );
    await _submitCreateSheet(tester);
    final saved = todos.saved.single;
    expect(saved.reminderPlan.enabled, isFalse);
    expect(saved.toJson()['reminderAt'], isNull);
    expect(saved.date, AppClock.date(2026, 10, 20, 15));
    expect(tester.takeException(), isNull);
  });
}
