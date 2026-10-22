import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/pomodoro_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });

  testWidgets(
    'editing only a focus tag preserves task linkage; renaming clears it',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final provider = PomodoroProvider();
      addTearDown(provider.dispose);
      provider.setTaskTarget(
        todoId: 'task',
        todoTitle: '项目任务',
        taskName: '调研',
        subtaskId: 'child',
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PomodoroProvider>.value(value: provider),
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ChangeNotifierProvider(create: (_) => FocusRoomProvider()),
            ChangeNotifierProvider(create: (_) => CustomFocusSoundProvider()),
          ],
          child: const MaterialApp(home: PomodoroScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('项目任务 / 调研').first);
      await tester.pumpAndSettle();
      final name = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '任务名称',
      );
      final tag = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '标签（用于专注统计分类，可选）',
      );
      expect(tester.widget<TextField>(name).controller?.text, '调研');
      await tester.enterText(tag, '工作');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(provider.state.todoId, 'task');
      expect(provider.state.subtaskId, 'child');
      expect(provider.state.taskName, '调研');
      expect(provider.state.tag, '工作');
      await tester.tap(find.text('项目任务 / 调研').first);
      await tester.pumpAndSettle();
      await tester.enterText(name, '手动专注');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(provider.state.todoId, isNull);
      expect(provider.state.subtaskId, isNull);
      expect(provider.state.taskName, '手动专注');
      expect(tester.takeException(), isNull);
    },
  );
}
