import 'dart:async';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/l10n/generated/app_localizations.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:duoyi/widgets/todo_create_sheet.dart';
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

class _DelayedAi extends AiService {
  final pending = Completer<List<String>>();
  @override
  bool get enabled => true;
  @override
  Future<List<String>> breakDownTask(String goal) => pending.future;
}

class _ReadOnlyShare extends ShareProvider {
  @override
  bool canEdit(String? workspaceId) => false;
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
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => NotificationService()),
        ChangeNotifierProvider<TodoProvider>(
          create: (_) => todos ?? TodoProvider(),
        ),
        ChangeNotifierProvider<ShareProvider>(
          create: (_) => shares ?? ShareProvider(),
        ),
        ChangeNotifierProvider<AiService>(create: (_) => ai ?? AiService()),
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

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(DesignTokens.fontFamilyRounded)..addFont(
          rootBundle.load('assets/fonts/ResourceHanRoundedCN-Bold.ttf'),
        ))
        .load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });

  testWidgets('共享表单保存清单、象限和优先级，保存中阻止重复提交', (tester) async {
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
    await tester.tap(find.widgetWithText(ChoiceChip, '工作'));
    final high = find.widgetWithText(ChoiceChip, TodoPriority.high.label);
    await tester.ensureVisible(high);
    await tester.pumpAndSettle();
    await tester.tap(high);
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
    expect(saved.priority, TodoPriority.high);
    expect(find.byType(AppModalSheet), findsNothing);
    expect(find.text(I18n.tr('todo.create.created')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (size, keyboard) in [
    (const Size(320, 720), 0.0),
    (const Size(390, 844), 300.0),
    (const Size(1440, 900), 0.0),
  ]) {
    testWidgets('$size keyboard=$keyboard 表单保持范围、可滚动并能点击遮罩关闭', (tester) async {
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
      await tester.tapAt(Offset(card.center.dx, card.top - 15));
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
    ai.pending.complete(['稍后返回的子任务']);
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsNothing);
    expect(todos.todos, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
