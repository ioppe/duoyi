import 'package:duoyi/widgets/keyboard_dismiss_scope.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpApp(
  WidgetTester tester,
  Widget child, {
  GlobalKey<NavigatorState>? navigatorKey,
}) => tester.pumpWidget(
  MaterialApp(
    navigatorKey: navigatorKey,
    navigatorObservers: [KeyboardDismissNavigatorObserver()],
    scrollBehavior: const KeyboardDismissScrollBehavior(),
    builder: (_, child) => KeyboardDismissScope(child: child!),
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('安卓触摸空白同时清除焦点并隐藏键盘', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await _pumpApp(tester, Column(children: [TextField(focusNode: focus)]));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tapAt(const Offset(300, 300));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('输入框之间切换不发送隐藏键盘命令', (tester) async {
    final first = FocusNode();
    final second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await _pumpApp(
      tester,
      Column(
        children: [
          TextField(focusNode: first),
          TextField(focusNode: second),
        ],
      ),
    );
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    tester.testTextInput.log.clear();
    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    expect(first.hasFocus, isFalse);
    expect(second.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(
      tester.testTextInput.log.where((call) => call.method == 'TextInput.hide'),
      isEmpty,
    );
  });

  testWidgets('非输入控件点击仍执行操作并收起键盘', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var pressed = 0;
    await _pumpApp(
      tester,
      Column(
        children: [
          TextField(focusNode: focus),
          IconButton(onPressed: () => pressed++, icon: const Icon(Icons.save)),
        ],
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(pressed, 1);
    expect(focus.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('输入区域内的辅助按钮保留输入焦点', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var pressed = false;
    await _pumpApp(
      tester,
      Column(
        children: [
          TextField(focusNode: focus),
          TextFieldTapRegion(
            child: IconButton(
              onPressed: () => pressed = true,
              icon: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(pressed, isTrue);
    expect(focus.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('程序使输入框失焦后隐藏残留键盘', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await _pumpApp(tester, TextField(focusNode: focus));
    await tester.tap(find.byType(TextField));
    await tester.pump();
    tester.testTextInput.log.clear();
    focus.unfocus();
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(
      tester.testTextInput.log.where((call) => call.method == 'TextInput.hide'),
      isNotEmpty,
    );
  });

  testWidgets('全局列表拖动策略收起键盘', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await _pumpApp(
      tester,
      ListView(
        children: [
          TextField(focusNode: focus, onTapOutside: (_) {}),
          const SizedBox(height: 1600),
        ],
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('切换路由允许新页自动聚焦，返回后不恢复旧页焦点', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final first = FocusNode();
    final second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await _pumpApp(
      tester,
      TextField(focusNode: first),
      navigatorKey: navigator,
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) =>
            Scaffold(body: TextField(focusNode: second, autofocus: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(first.hasFocus, isFalse);
    expect(second.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(first.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('打开和关闭共享弹层不留下底层输入焦点', (tester) async {
    final focus = FocusNode();
    final navigator = GlobalKey<NavigatorState>();
    addTearDown(focus.dispose);
    await _pumpApp(
      tester,
      TextField(focusNode: focus),
      navigatorKey: navigator,
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final context = tester.element(find.byType(TextField));
    showAppModalSheet<void>(
      context: context,
      builder: (_) => const AppModalSheet(title: '设置', child: Text('内容')),
    );
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(tester.takeException(), isNull);
  });
}
