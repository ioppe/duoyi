import 'dart:async';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/todo_templates.dart';
import 'package:duoyi/l10n/generated/app_localizations.dart';
import 'package:duoyi/models/list_group.dart';
import 'package:duoyi/providers/list_group_provider.dart';
import 'package:duoyi/widgets/todo_list_group_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PickerHost extends StatefulWidget {
  final List<String> initialNames;
  final ListGroupProvider? provider;
  final bool enabled;
  final bool canCreate;
  final bool Function(ListGroup group)? canManage;
  final bool Function() isCurrent;
  final Size size;
  final double textScale;

  const _PickerHost({
    super.key,
    required this.initialNames,
    required this.provider,
    required this.size,
    required this.textScale,
    this.enabled = true,
    this.canCreate = true,
    this.canManage,
    this.isCurrent = _alwaysCurrent,
  });

  static bool _alwaysCurrent() => true;

  @override
  State<_PickerHost> createState() => _PickerHostState();
}

class _PickerHostState extends State<_PickerHost> {
  late String _value = '';
  late List<String> _names = _namesFromProvider();

  List<String> _namesFromProvider() {
    final provider = widget.provider;
    final providerNames = {
      for (final group in provider?.allGroups ?? const <ListGroup>[])
        ListGroupProvider.normalizedName(group.name),
    };
    final names = <String, String>{};
    for (final name in widget.initialNames) {
      final clean = name.trim();
      if (clean.isNotEmpty &&
          !providerNames.contains(ListGroupProvider.normalizedName(clean))) {
        names[ListGroupProvider.normalizedName(clean)] = clean;
      }
    }
    for (final group in provider?.groups ?? const <ListGroup>[]) {
      names[ListGroupProvider.normalizedName(group.name)] = group.name;
    }
    return names.values.toList();
  }

  void _providerChanged() {
    if (mounted) setState(() => _names = _namesFromProvider());
  }

  @override
  void initState() {
    super.initState();
    widget.provider?.addListener(_providerChanged);
  }

  @override
  void dispose() {
    widget.provider?.removeListener(_providerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppBrands.defaultBrand.theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(widget.textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TodoListGroupPicker(
              value: _value,
              names: _names,
              provider: widget.provider,
              enabled: widget.enabled,
              canCreate: widget.canCreate,
              canManage: widget.canManage,
              isCurrent: widget.isCurrent,
              onChanged: (value) => setState(() => _value = value),
            ),
          ),
        ),
      ),
    );
  }
}

/// 新建延迟到测试放行，用于验证等待期间重复触发只落一次写入。
class _DelayedListGroups extends ListGroupProvider {
  final pending = Completer<void>();
  int createCalls = 0;

  @override
  Future<ListGroup> create(String name, int sortOrder) async {
    createCalls++;
    await pending.future;
    return super.create(name, sortOrder);
  }
}

Future<void> _pumpPicker(
  WidgetTester tester, {
  required List<String> names,
  ListGroupProvider? provider,
  bool enabled = true,
  bool canCreate = true,
  bool Function(ListGroup group)? canManage,
  bool Function() isCurrent = _alwaysCurrent,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _PickerHost(
      key: UniqueKey(),
      initialNames: names,
      provider: provider,
      enabled: enabled,
      canCreate: canCreate,
      canManage: canManage,
      isCurrent: isCurrent,
      size: size,
      textScale: textScale,
    ),
  );
  await tester.pump();
}

bool _alwaysCurrent() => true;

Future<void> _openPicker(WidgetTester tester) async {
  if (find.byKey(const ValueKey('todo_list_group_search')).evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('todo_list_group_selector')));
    await tester.pump();
  }
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  final options = find.byKey(const ValueKey('todo_list_group_options'));
  for (var i = 0; i < 16; i++) {
    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target);
      if (target.hitTestable().evaluate().isNotEmpty) return;
    }
    await tester.drag(options, const Offset(0, -120));
    await tester.pump();
  }
  expect(target.hitTestable(), findsOneWidget);
}

Finder _searchField() => find.byKey(const ValueKey('todo_list_group_search'));

Finder _createAction() => find.byKey(const ValueKey('todo_list_group_create'));

String? _searchLabel(WidgetTester tester) =>
    tester.widget<TextField>(_searchField()).decoration?.labelText;

String? _searchError(WidgetTester tester) =>
    tester.widget<TextField>(_searchField()).decoration?.errorText;

String _selected(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('todo_list_group_selected_name')))
    .data!;

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(_searchField(), query);
  await tester.pump();
}

/// 新建动作位于结果列表内，必要时滚动到可点击位置。
Future<Finder> _revealCreateAction(WidgetTester tester) async {
  final action = _createAction();
  final options = find.byKey(const ValueKey('todo_list_group_options'));
  for (var i = 0; i < 16; i++) {
    if (action.hitTestable().evaluate().isNotEmpty) return action;
    if (options.evaluate().isEmpty) break;
    await tester.drag(options, const Offset(0, -120));
    await tester.pump();
  }
  expect(action.hitTestable(), findsOneWidget);
  return action;
}

Future<void> _submitSearch(WidgetTester tester) async {
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

List<String> _builtInNames() =>
    TodoListTemplates.all.map((item) => item.name).toList();

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(DesignTokens.fontFamily)..addFont(
          rootBundle.load('assets/fonts/ResourceHanRoundedCN-Bold.ttf'),
        ))
        .load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });

  testWidgets('80 个清单使用有界惰性列表，搜索最后一项后选择并收起', (tester) async {
    final provider = ListGroupProvider();
    final now = DateTime.utc(2026, 10, 21);
    final customNames = [for (var i = 0; i < 80; i++) '项目$i'];
    await provider.mergeRemote([
      for (var i = 0; i < customNames.length; i++)
        ListGroup(
          id: 'group-$i',
          name: customNames[i],
          sortOrder: i,
          createdAt: now.add(Duration(seconds: i)),
          updatedAt: now.add(Duration(seconds: i)),
        ).toJson(),
    ]);
    await _pumpPicker(
      tester,
      provider: provider,
      names: [..._builtInNames(), ...customNames],
    );
    await _openPicker(tester);
    final options = find.byKey(const ValueKey('todo_list_group_options'));
    expect(options, findsOneWidget);
    expect(tester.getSize(options).height, lessThanOrEqualTo(320));
    expect(find.text(I18n.tr('list_group.built_in')), findsOneWidget);
    expect(find.text(I18n.tr('list_group.custom')), findsOneWidget);
    final builtCustomRows = tester.allWidgets.where((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('todo_list_group_项目');
    }).length;
    expect(builtCustomRows, lessThan(customNames.length));

    final search = _searchField();
    await tester.enterText(search, '不存在的清单');
    await tester.pump();
    expect(_createAction(), findsOneWidget);
    expect(provider.groups, hasLength(80));
    await tester.enterText(search, '项目79');
    await tester.pump();
    final last = find.byKey(const ValueKey('todo_list_group_项目79'));
    expect(last, findsOneWidget);
    await tester.tap(last);
    await tester.pump();
    expect(_selected(tester), '项目79');
    expect(_searchField(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索框内新建、重命名和删除复用同一面板', (tester) async {
    final provider = ListGroupProvider();
    final initial = await provider.create('旅行', 0);
    await _pumpPicker(
      tester,
      provider: provider,
      names: [..._builtInNames(), '旅行'],
    );
    await _openPicker(tester);
    expect(_searchLabel(tester), I18n.tr('list_group.search_or_create'));
    await _search(tester, '新清单');
    final action = await _revealCreateAction(tester);
    expect(_createAction(), findsOneWidget);
    expect(find.byKey(const ValueKey('todo_list_group_input')), findsNothing);
    expect(
      find.byKey(const ValueKey('todo_list_group_create_confirm')),
      findsNothing,
    );
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(provider.groups, hasLength(2));
    expect(provider.groups.any((group) => group.name == '新清单'), isTrue);
    expect(_selected(tester), '新清单');
    expect(_searchField(), findsNothing);

    await _openPicker(tester);
    final rename = find.byKey(ValueKey('todo_list_group_manage_${initial.id}'));
    await _reveal(tester, rename);
    await tester.tap(rename);
    await tester.pumpAndSettle();
    await tester.tap(find.text(I18n.tr('list_group.rename')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('todo_list_group_input')),
      '假期',
    );
    await tester.tap(
      find.byKey(const ValueKey('todo_list_group_create_confirm')),
    );
    await tester.pumpAndSettle();
    expect(
      provider.groups.singleWhere((group) => group.id == initial.id).name,
      '假期',
    );

    await _openPicker(tester);
    final delete = find.byKey(ValueKey('todo_list_group_manage_${initial.id}'));
    await _reveal(tester, delete);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    await tester.tap(find.text(I18n.tr('action.delete')));
    await tester.pumpAndSettle();
    expect(provider.groups, hasLength(1));
    expect(provider.groups.single.name, '新清单');
    expect(
      provider.allGroups
          .firstWhere((group) => group.id == initial.id)
          .isDeleted,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('无 provider 或只读时输入不显示新建动作，禁用和只读管理保持收敛', (tester) async {
    await _pumpPicker(
      tester,
      provider: null,
      canCreate: false,
      names: _builtInNames(),
    );
    await _openPicker(tester);
    expect(_searchLabel(tester), I18n.tr('list_group.search'));
    expect(_createAction(), findsNothing);
    await _search(tester, '新清单');
    expect(_createAction(), findsNothing);
    expect(find.byKey(const ValueKey('todo_list_group_input')), findsNothing);
    await _search(tester, '');
    await tester.tap(find.byKey(const ValueKey('todo_list_group_工作')));
    await tester.pump();
    expect(_selected(tester), '工作');

    await _pumpPicker(tester, enabled: false, names: _builtInNames());
    await tester.tap(find.byKey(const ValueKey('todo_list_group_selector')));
    await tester.pump();
    expect(_searchField(), findsNothing);

    final provider = ListGroupProvider();
    final group = await provider.create('旅行', 0);
    await _pumpPicker(
      tester,
      provider: provider,
      canCreate: false,
      canManage: (_) => false,
      names: ['旅行'],
    );
    await _openPicker(tester);
    expect(_searchLabel(tester), I18n.tr('list_group.search'));
    final option = find.byKey(const ValueKey('todo_list_group_旅行'));
    await _search(tester, '旅行');
    expect(option, findsOneWidget);
    expect(
      find.byKey(ValueKey('todo_list_group_manage_${group.id}')),
      findsNothing,
    );
    expect(_createAction(), findsNothing);
    await _search(tester, '新清单');
    expect(_createAction(), findsNothing);
    expect(provider.groups, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑中和菜单打开后撤销权限不会重命名或删除清单', (tester) async {
    final provider = ListGroupProvider();
    final group = await provider.create('旅行', 0);
    var allowed = true;
    await _pumpPicker(
      tester,
      provider: provider,
      names: ['旅行'],
      canManage: (_) => allowed,
    );
    await _openPicker(tester);
    await _search(tester, '旅行');
    final menu = find.byKey(ValueKey('todo_list_group_manage_${group.id}'));
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text(I18n.tr('list_group.rename')));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('todo_list_group_input'));
    await tester.enterText(input, '不应写入');
    allowed = false;
    await tester.tap(
      find.byKey(const ValueKey('todo_list_group_create_confirm')),
    );
    await tester.pumpAndSettle();
    expect(provider.groups.single.name, '旅行');
    expect(
      tester.widget<TextField>(input).decoration?.errorText,
      I18n.tr('todo.create.read_only'),
    );

    allowed = true;
    await tester.tap(
      find.byKey(const ValueKey('todo_list_group_create_cancel')),
    );
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    allowed = false;
    await tester.tap(find.text(I18n.tr('action.delete')));
    await tester.pumpAndSettle();
    expect(provider.groups.single.id, group.id);
    expect(provider.allGroups.single.isDeleted, isFalse);
    expect(find.text(I18n.tr('todo.create.read_only')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('内置清单遇到远端同名记录仍无管理菜单', (tester) async {
    final provider = ListGroupProvider();
    final group = await provider.create('工作', 0);
    await _pumpPicker(tester, provider: provider, names: ['工作']);
    await _openPicker(tester);
    await _search(tester, '工作');
    expect(find.byKey(const ValueKey('todo_list_group_工作')), findsOneWidget);
    expect(
      find.byKey(ValueKey('todo_list_group_manage_${group.id}')),
      findsNothing,
    );
    expect(_createAction(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未匹配查询显示新建动作，点击只创建一次并选择收起', (tester) async {
    final provider = ListGroupProvider();
    await _pumpPicker(tester, provider: provider, names: _builtInNames());
    await _openPicker(tester);
    await _search(tester, '海边');
    expect(_searchLabel(tester), I18n.tr('list_group.search_or_create'));
    expect(
      find.text(I18n.tr('list_group.create_named').replaceAll('{name}', '海边')),
      findsOneWidget,
    );
    expect(provider.groups, isEmpty);
    expect(_createAction(), findsOneWidget);
    final action = await _revealCreateAction(tester);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(provider.groups, hasLength(1));
    expect(provider.groups.single.name, '海边');
    expect(_selected(tester), '海边');
    expect(_searchField(), findsNothing);
    expect(find.byKey(const ValueKey('todo_list_group_input')), findsNothing);
    expect(
      find.byKey(const ValueKey('todo_list_group_create_confirm')),
      findsNothing,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('输入过程不创建，归一化同名单凭 Enter 复用且部分匹配优先', (tester) async {
    final provider = ListGroupProvider();
    await provider.create('Travel', 0);
    await provider.create('项目1', 1);
    await provider.create('项目2', 2);
    await _pumpPicker(
      tester,
      provider: provider,
      names: [..._builtInNames(), 'Travel', '项目1', '项目2'],
    );
    await _openPicker(tester);
    expect(_createAction(), findsNothing);
    expect(provider.groups, hasLength(3));

    await _search(tester, '海');
    expect(_createAction(), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(provider.groups, hasLength(3), reason: '输入过程中不得自动创建');

    await _search(tester, ' travel ');
    expect(_createAction(), findsNothing, reason: '归一化同名清单抑制新建');
    await _submitSearch(tester);
    expect(_selected(tester), 'Travel');
    expect(_searchField(), findsNothing);
    expect(provider.groups, hasLength(3));

    await _openPicker(tester);
    await _search(tester, 'Trav');
    expect(_createAction(), findsOneWidget);
    await _submitSearch(tester);
    expect(_selected(tester), 'Travel');
    expect(_searchField(), findsNothing);
    expect(provider.groups, hasLength(3), reason: '唯一部分匹配只能复用');

    await _openPicker(tester);
    await _search(tester, '项目');
    expect(_createAction(), findsOneWidget, reason: '部分匹配可与新建动作共存');
    await _submitSearch(tester);
    expect(_searchField(), findsOneWidget, reason: '多个部分匹配不得隐式创建');
    expect(_selected(tester), 'Travel');
    expect(provider.groups, hasLength(3));

    await _search(tester, '海边');
    await _submitSearch(tester);
    expect(provider.groups, hasLength(4));
    expect(provider.groups.last.name, '海边');
    expect(_selected(tester), '海边');
    expect(_searchField(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('新建动作等待期间重复点击不会重复创建', (tester) async {
    final provider = _DelayedListGroups();
    await _pumpPicker(tester, provider: provider, names: _builtInNames());
    await _openPicker(tester);
    await _search(tester, '海边');
    final action = await _revealCreateAction(tester);
    await tester.tap(action);
    await tester.pump();
    final pendingAction = _createAction();
    if (pendingAction.hitTestable().evaluate().isNotEmpty) {
      await tester.tap(pendingAction);
      await tester.pump();
    }
    provider.pending.complete();
    await tester.pumpAndSettle();
    expect(provider.createCalls, 1);
    expect(provider.groups, hasLength(1));
    expect(_selected(tester), '海边');
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏和大字号下 picker 保持有界且无布局异常', (tester) async {
    await _pumpPicker(
      tester,
      size: const Size(320, 844),
      textScale: 1.8,
      provider: ListGroupProvider(),
      names: [..._builtInNames(), '旅行'],
    );
    await _openPicker(tester);
    final options = find.byKey(const ValueKey('todo_list_group_options'));
    expect(tester.getSize(options).height, lessThanOrEqualTo(320));
    expect(tester.getSize(_searchField()).width, greaterThan(200));
    await _search(tester, '海边');
    expect(_searchError(tester), isNull);
    await _revealCreateAction(tester);
    expect(tester.takeException(), isNull);
  });
}
