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
      names: [
        ...TodoListTemplates.all.map((item) => item.name),
        ...customNames,
      ],
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

    final search = find.byKey(const ValueKey('todo_list_group_search'));
    await tester.enterText(search, '不存在的清单');
    await tester.pump();
    expect(find.text(I18n.tr('list_group.no_matches')), findsOneWidget);
    await tester.enterText(search, '项目79');
    await tester.pump();
    final last = find.byKey(const ValueKey('todo_list_group_项目79'));
    expect(last, findsOneWidget);
    await tester.tap(last);
    await tester.pump();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('todo_list_group_selected_name')),
          )
          .data,
      '项目79',
    );
    expect(find.byKey(const ValueKey('todo_list_group_search')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('内联新建、重命名和删除复用同一面板', (tester) async {
    final provider = ListGroupProvider();
    final initial = await provider.create('旅行', 0);
    await _pumpPicker(
      tester,
      provider: provider,
      names: [...TodoListTemplates.all.map((item) => item.name), '旅行'],
    );
    await _openPicker(tester);
    final create = find.byKey(const ValueKey('todo_list_group_create'));
    expect(create, findsOneWidget);
    await tester.tap(create);
    await tester.pump();
    final input = find.byKey(const ValueKey('todo_list_group_input'));
    expect(find.byType(AlertDialog), findsNothing);
    await tester.enterText(input, '新清单');
    await tester.tap(
      find.byKey(const ValueKey('todo_list_group_create_confirm')),
    );
    await tester.pumpAndSettle();
    expect(provider.groups.any((group) => group.name == '新清单'), isTrue);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('todo_list_group_selected_name')),
          )
          .data,
      '新清单',
    );

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

  testWidgets('无 provider 时仍可选择，禁用和只读管理保持收敛', (tester) async {
    await _pumpPicker(
      tester,
      provider: null,
      canCreate: false,
      names: TodoListTemplates.all.map((item) => item.name).toList(),
    );
    await _openPicker(tester);
    expect(find.byKey(const ValueKey('todo_list_group_create')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('todo_list_group_工作')));
    await tester.pump();
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('todo_list_group_selected_name')),
          )
          .data,
      '工作',
    );

    await _pumpPicker(
      tester,
      enabled: false,
      names: TodoListTemplates.all.map((item) => item.name).toList(),
    );
    await tester.tap(find.byKey(const ValueKey('todo_list_group_selector')));
    await tester.pump();
    expect(find.byKey(const ValueKey('todo_list_group_search')), findsNothing);

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
    final option = find.byKey(const ValueKey('todo_list_group_旅行'));
    final search = find.byKey(const ValueKey('todo_list_group_search'));
    await tester.enterText(search, '旅行');
    await tester.pump();
    expect(option, findsOneWidget);
    expect(
      find.byKey(ValueKey('todo_list_group_manage_${group.id}')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('todo_list_group_create')), findsNothing);
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
    final search = find.byKey(const ValueKey('todo_list_group_search'));
    await tester.enterText(search, '旅行');
    await tester.pump();
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
    await tester.enterText(
      find.byKey(const ValueKey('todo_list_group_search')),
      '工作',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('todo_list_group_工作')), findsOneWidget);
    expect(
      find.byKey(ValueKey('todo_list_group_manage_${group.id}')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏和大字号下 picker 保持有界且无布局异常', (tester) async {
    await _pumpPicker(
      tester,
      size: const Size(320, 844),
      textScale: 1.8,
      names: [...TodoListTemplates.all.map((item) => item.name), '旅行'],
    );
    await _openPicker(tester);
    final options = find.byKey(const ValueKey('todo_list_group_options'));
    expect(tester.getSize(options).height, lessThanOrEqualTo(320));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('todo_list_group_search')))
          .width,
      greaterThan(200),
    );
    expect(tester.takeException(), isNull);
  });
}
