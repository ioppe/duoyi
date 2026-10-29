import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/screens/note_screen.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder get _sheet => find.byType(AppModalSheet);
Finder get _card =>
    find.descendant(of: _sheet, matching: find.byType(Material)).first;
Finder get _editor =>
    find.descendant(of: _sheet, matching: find.byType(TextField));
Finder _key(String value) => find.byKey(ValueKey(value));

Future<NoteProvider> _pumpNoteScreen(
  WidgetTester tester, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final notes = NoteProvider();
  addTearDown(notes.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<NoteProvider>.value(
      value: notes,
      child: MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        home: const NoteScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return notes;
}

Future<void> _openNoteCreateSheet(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(DesignTokens.fontFamily)..addFont(
          rootBundle.load('assets/fonts/ResourceHanRoundedCN-Bold.ttf'),
        ))
        .load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('便签库两处新建入口都打开共享底部弹窗且弹窗内没有 Scaffold', (tester) async {
    await _pumpNoteScreen(tester);
    await tester.tap(
      find.widgetWithText(FilledButton, I18n.tr('note.empty.action')),
    );
    await tester.pumpAndSettle();
    expect(_sheet, findsOneWidget);
    expect(
      find.descendant(of: _sheet, matching: find.byType(Scaffold)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: _sheet,
        matching: find.byTooltip(I18n.tr('note.toolbar.bold')),
      ),
      findsOneWidget,
    );
    expect(_editor, findsOneWidget);
    expect(_key('note_create_cancel'), findsOneWidget);
    expect(_key('note_create_save'), findsOneWidget);
    expect(_key('note_create_preview_toggle'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(_key('note_create_cancel'));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(find.byType(NoteScreen), findsOneWidget);

    await _openNoteCreateSheet(tester);
    expect(_sheet, findsOneWidget);
    expect(
      find.descendant(of: _sheet, matching: find.byType(Scaffold)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏 300 键盘 inset 下弹窗保持共享尺寸且不溢出', (tester) async {
    const size = Size(320, 720);
    await _pumpNoteScreen(tester, size: size);
    await _openNoteCreateSheet(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();

    final card = tester.getRect(_card);
    expect(card.bottom, closeTo(size.height - 300, 1));
    expect(
      card.height,
      inInclusiveRange(
        (size.height - 300) / 2 - 1,
        (size.height - 300) * 2 / 3 + 1,
      ),
    );
    expect(card.width, lessThanOrEqualTo(DesignTokens.creationFormMaxWidth));
    expect(_editor, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('输入 Markdown 切预览再返回保留草稿，保存写入并关闭', (tester) async {
    final notes = await _pumpNoteScreen(tester);
    await _openNoteCreateSheet(tester);
    const draft = '## 标题\n- [ ] 事项\n**加粗** 正文';
    await tester.enterText(_editor, draft);
    await tester.pumpAndSettle();

    await tester.tap(_key('note_create_preview_toggle'));
    await tester.pumpAndSettle();
    expect(_editor, findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

    await tester.tap(_key('note_create_preview_toggle'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_editor).controller!.text, draft);

    await tester.tap(_key('note_create_save'));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    final note = notes.notes.single;
    expect(note.content, draft);
    expect(note.format, 'markdown');
    expect(note.blocks, isNotEmpty);
    expect(note.attachments, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('取消和点击遮罩关闭都不写入数据', (tester) async {
    final notes = await _pumpNoteScreen(tester);
    await _openNoteCreateSheet(tester);
    await tester.enterText(_editor, '不该保存的草稿');
    await tester.pumpAndSettle();

    await tester.tap(_key('note_create_cancel'));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(notes.notes, isEmpty);

    await _openNoteCreateSheet(tester);
    await tester.enterText(_editor, '遮罩关闭的草稿');
    await tester.pumpAndSettle();
    final card = tester.getRect(_card);
    await tester.tapAt(Offset(card.center.dx, card.top - 20));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(notes.notes, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
