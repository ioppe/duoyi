import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/statistics_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('统计页 KPI 网格适配 320/390/430 和桌面宽度', (tester) async {
    addTearDown(tester.view.reset);

    for (final scenario in const [
      (width: 320.0, expectedColumns: 1),
      (width: 390.0, expectedColumns: 2),
      (width: 430.0, expectedColumns: 2),
      (width: 900.0, expectedColumns: 3),
    ]) {
      tester.view.physicalSize = Size(scenario.width, 760);
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(_wrapStatistics());
      await tester.pump();
      expect(find.text('日记'), findsNothing);
      expect(find.text('待办完成'), findsOneWidget);
      expect(find.text('深度专注'), findsOneWidget);
      expect(find.text('习惯打卡'), findsOneWidget);

      final grid = tester.widget<GridView>(
        find.byKey(const ValueKey('statistics_kpi_grid')),
      );
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(
        delegate.crossAxisCount,
        scenario.expectedColumns,
        reason: 'width=${scenario.width}',
      );
      expect(tester.takeException(), isNull, reason: 'width=${scenario.width}');
    }
  });

  testWidgets('系统大字号（2.0）下 KPI 卡随字号放大兜底，三断点不溢出', (tester) async {
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    tester.platformDispatcher.textScaleFactorTestValue = 2.0;

    final overflowErrors = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = originalOnError);
    FlutterError.onError = (details) {
      final exception = details.exception;
      if (exception is FlutterError &&
          exception.toString().contains('RenderFlex')) {
        overflowErrors.add(details);
      } else {
        originalOnError?.call(details);
      }
    };

    for (final scenario in const [
      (width: 320.0, expectedColumns: 1),
      (width: 390.0, expectedColumns: 2),
      (width: 900.0, expectedColumns: 3),
    ]) {
      overflowErrors.clear();
      tester.view.physicalSize = Size(scenario.width, 760);
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(_wrapStatistics());
      await tester.pump();

      final grid = tester.widget<GridView>(
        find.byKey(const ValueKey('statistics_kpi_grid')),
      );
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(
        delegate.crossAxisCount,
        scenario.expectedColumns,
        reason: 'width=${scenario.width}',
      );
      expect(
        delegate.mainAxisExtent,
        isNotNull,
        reason: 'width=${scenario.width} 大字号下必须提供随字号放大的瓦片高度兜底',
      );
      expect(
        overflowErrors,
        isEmpty,
        reason: 'width=${scenario.width} textScale=2.0 不应出现 RenderFlex 溢出',
      );
    }
  });
}

Widget _wrapStatistics() {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => TodoProvider()),
      ChangeNotifierProvider(create: (_) => GoalProvider()),
      ChangeNotifierProvider(create: (_) => HabitProvider()),
      ChangeNotifierProvider(create: (_) => PomodoroProvider()),
      ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
      ChangeNotifierProvider(create: (_) => AiService()),
    ],
    child: const MaterialApp(home: StatisticsScreen()),
  );
}
