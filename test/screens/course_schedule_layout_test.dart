import 'package:duoyi/models/course_schedule.dart';
import 'package:duoyi/providers/course_provider.dart';
import 'package:duoyi/screens/course_schedule_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('课程表在 320px 下保留可读列宽并避免课程块溢出', (tester) async {
    _setPhoneSize(tester);
    final provider = await _courseProviderWithLongCourse();

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final gridSize = tester.getSize(
      find.byKey(const ValueKey('course_schedule_adaptive_grid')),
    );
    expect(gridSize.width, greaterThan(320));
    expect(find.textContaining('超长课程名称'), findsOneWidget);
  });

  testWidgets('周次选择器在 320px 下不再固定 5 列', (tester) async {
    _setPhoneSize(tester);
    final provider = await _courseProviderWithLongCourse();

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第 1 周'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final grid = tester.widget<GridView>(
      find.byKey(const ValueKey('course_week_picker_adaptive_grid')),
    );
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, lessThan(5));
  });

  testWidgets('课程设置和编辑器在 320px 下不出现横向布局异常', (tester) async {
    _setPhoneSize(tester);
    final provider = await _courseProviderWithLongCourse();

    await tester.pumpWidget(_wrap(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('课表设置'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(4));
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('新增课程'), findsOneWidget);
    expect(find.text('上课周'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('单周'), findsOneWidget);
    expect(find.text('双周'), findsOneWidget);
    expect(find.text('清空'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _setPhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<CourseProvider> _courseProviderWithLongCourse() async {
  final provider = CourseProvider();
  await provider.updateSettings(
    ScheduleSettings(
      termStart: DateTime(2026, 6, 1),
      totalWeeks: 20,
      sessionsPerDay: 12,
    ),
  );
  provider.setViewingWeek(1);
  await provider.add(
    CourseItem(
      name: '超长课程名称用于验证窄屏课程块不会溢出',
      teacher: '非常非常长的教师姓名',
      location: 'A 座非常长的教室位置 101',
      weekday: 1,
      startSection: 1,
      sectionCount: 1,
      weeks: const [1],
    ),
  );
  return provider;
}

Widget _wrap(CourseProvider provider) {
  return ChangeNotifierProvider<CourseProvider>.value(
    value: provider,
    child: const MaterialApp(home: CourseScheduleScreen()),
  );
}
