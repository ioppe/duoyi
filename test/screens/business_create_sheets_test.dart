import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/calendar_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/screens/share_screen.dart';
import 'package:duoyi/widgets/calendar_event_sheet.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignedIn extends AuthProvider {
  @override
  AuthState get state =>
      const AuthState(userId: 'sheet-test', token: 'fixture');
}

class _Shares extends ShareProvider {
  int creations = 0;
  @override
  Future<void> load() async {}
  @override
  Future<void> createWorkspace(String name) async {
    creations++;
  }
}

Finder get _sheet => find.byType(AppModalSheet);
Finder get _scroll =>
    find.descendant(of: _sheet, matching: find.byType(Scrollable)).first;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('日程新建底部表单保留标题备注并保存返回', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final events = CalendarProvider();
    addTearDown(events.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<CalendarProvider>.value(
        value: events,
        child: MaterialApp(
          theme: AppBrands.defaultBrand.theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showLocalCalendarEventEditor(context),
                child: const Text('打开日程'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开日程'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('calendar_event_create_sheet')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _sheet, matching: find.byType(Dialog)),
      findsNothing,
    );
    await tester.enterText(find.widgetWithText(TextField, '日程标题'), '周末出行');
    await tester.enterText(find.widgetWithText(TextField, '备注'), '保留行程说明');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('保存'), 200, scrollable: _scroll);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(events.localEvents, hasLength(1));
    expect(events.localEvents.single.title, '周末出行');
    expect(events.localEvents.single.note, '保留行程说明');
    expect(find.text('打开日程'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('共享空间新建在键盘上方显示且取消不提交', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shares = _Shares();
    addTearDown(shares.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(create: (_) => _SignedIn()),
          ChangeNotifierProvider<ShareProvider>.value(value: shares),
        ],
        child: MaterialApp(
          theme: AppBrands.defaultBrand.theme,
          home: const ShareScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final createButton = find.byType(FloatingActionButton);
    expect(createButton, findsOneWidget);
    expect(tester.getBottomRight(createButton).dx, closeTo(304, 1));
    expect(tester.getBottomRight(createButton).dy, closeTo(704, 1));
    await tester.tap(createButton);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('workspace_create_sheet')),
      findsOneWidget,
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final card = find
        .descendant(of: _sheet, matching: find.byType(Material))
        .first;
    expect(tester.getRect(card).bottom, closeTo(420, 1));
    await tester.enterText(find.widgetWithText(TextField, '空间名称'), '取消的草稿');
    await tester.scrollUntilVisible(find.text('取消'), 160, scrollable: _scroll);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(shares.creations, 0);
    expect(find.byType(ShareScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
