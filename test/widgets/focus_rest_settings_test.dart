import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/focus_rest_settings.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

Widget _summaryHarness({
  int shortBreakDuration = 300,
  int longBreakDuration = 900,
  int sessionsPerLongBreak = 4,
  bool autoStartBreaks = false,
  bool isCountUp = false,
  PomodoroProvider? provider,
  VoidCallback? onTap,
}) {
  return ChangeNotifierProvider(
    create: (_) => provider ?? PomodoroProvider(),
    builder: (context, _) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: FocusRestPlanSummary(
            shortBreakDuration: shortBreakDuration,
            longBreakDuration: longBreakDuration,
            sessionsPerLongBreak: sessionsPerLongBreak,
            autoStartBreaks: autoStartBreaks,
            isCountUp: isCountUp,
            onTap: onTap ?? () {},
          ),
        ),
      ),
    ),
  );
}

Widget _sheetHarness(PomodoroProvider provider) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: provider),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
    ],
    child: MaterialApp(
      home: Consumer<PomodoroProvider>(
        builder: (context, provider, _) => Scaffold(
          body: Center(
            child: FocusRestPlanSummary(
              shortBreakDuration: provider.config.shortBreakDuration,
              longBreakDuration: provider.config.longBreakDuration,
              sessionsPerLongBreak: provider.config.sessionsPerLongBreak,
              autoStartBreaks: provider.config.autoStartBreaks,
              isCountUp: provider.state.isCountUp,
              onTap: () => showFocusRestSettingsSheet(
                context: context,
                provider: provider,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openSheet(WidgetTester tester, PomodoroProvider provider) async {
  await tester.pumpWidget(_sheetHarness(provider));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(FocusRestKeys.summary));
  await tester.pumpAndSettle();
  expect(find.byKey(FocusRestKeys.sheet), findsOneWidget);
}

class _FailingRestStore extends InMemorySharedPreferencesStore {
  _FailingRestStore(this.throwOnFailure) : super.withData(<String, Object>{});
  final bool throwOnFailure;

  @override
  Future<bool> setValue(String type, String key, Object value) {
    if (key == 'flutter.pomodoro_config') {
      return throwOnFailure
          ? Future<bool>.error(StateError('storage failed'))
          : Future<bool>.value(false);
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('休息摘要显示默认短休 5 / 长休 15 / 每 4 轮 / 手动开始', (tester) async {
    await tester.pumpWidget(_summaryHarness());
    await tester.pumpAndSettle();

    expect(find.text('短休 5 分钟 · 长休 15 分钟'), findsOneWidget);
    expect(find.text('每4轮长休息 · 完成后手动开始'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('自动开始休息时摘要使用自动文案', (tester) async {
    await tester.pumpWidget(_summaryHarness(autoStartBreaks: true));
    await tester.pumpAndSettle();

    expect(find.text('每4轮长休息 · 自动开始休息'), findsOneWidget);
  });

  testWidgets('自由计时摘要提示休息安排属于倒计时模式', (tester) async {
    await tester.pumpWidget(_summaryHarness(isCountUp: true));
    await tester.pumpAndSettle();

    expect(find.text('倒计时模式的休息安排'), findsOneWidget);
  });

  testWidgets('取消丢弃草稿并保留原配置', (tester) async {
    final provider = PomodoroProvider();
    await _openSheet(tester, provider);

    await tester.enterText(find.byKey(FocusRestKeys.shortInput), '12');
    await tester.enterText(find.byKey(FocusRestKeys.longInput), '30');
    await tester.pump();
    await tester.tap(find.byKey(FocusRestKeys.cancel));
    await tester.pumpAndSettle();

    expect(find.byKey(FocusRestKeys.sheet), findsNothing);
    expect(provider.config.shortBreakDuration, 300);
    expect(provider.config.longBreakDuration, 900);
    expect(find.text('短休 5 分钟 · 长休 15 分钟'), findsOneWidget);

    await tester.tap(find.byKey(FocusRestKeys.summary));
    await tester.pumpAndSettle();
    expect(
      (tester.widget<TextField>(
        find.byKey(FocusRestKeys.shortInput),
      )).controller!.text,
      '5',
    );
  });

  testWidgets('5∶1 联动按当前专注时长推导短休（25→5，60→12）', (tester) async {
    final provider = PomodoroProvider();
    provider.setConfig(provider.config..focusDuration = 25 * 60);
    await _openSheet(tester, provider);

    await tester.tap(find.byKey(FocusRestKeys.linkSwitch));
    await tester.pumpAndSettle();
    expect(
      (tester.widget<TextField>(
        find.byKey(FocusRestKeys.shortInput),
      )).controller!.text,
      '5',
    );
    expect(
      tester.widget<TextField>(find.byKey(FocusRestKeys.shortInput)).enabled,
      isFalse,
    );

    await tester.tap(find.byKey(FocusRestKeys.linkSwitch));
    await tester.pumpAndSettle();
    provider.setConfig(provider.config..focusDuration = 60 * 60);
    await tester.tap(find.byKey(FocusRestKeys.linkSwitch));
    await tester.pumpAndSettle();
    expect(
      (tester.widget<TextField>(
        find.byKey(FocusRestKeys.shortInput),
      )).controller!.text,
      '12',
    );
  });

  testWidgets('非法输入留在面板内并说明范围，不写配置', (tester) async {
    final provider = PomodoroProvider();
    await _openSheet(tester, provider);

    await tester.scrollUntilVisible(
      find.byKey(FocusRestKeys.intervalInput),
      100,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.enterText(find.byKey(FocusRestKeys.intervalInput), '21');
    await tester.pump();
    await tester.tap(find.byKey(FocusRestKeys.save));
    await tester.pumpAndSettle();

    expect(find.byKey(FocusRestKeys.sheet), findsOneWidget);
    expect(find.byKey(FocusRestKeys.error), findsOneWidget);
    expect(find.text('长休息间隔请输入 1–20 的整数。'), findsOneWidget);
    expect(provider.config.sessionsPerLongBreak, 4);
  });

  testWidgets('保存成功后关闭面板并写入休息设置', (tester) async {
    final provider = PomodoroProvider();
    await _openSheet(tester, provider);

    await tester.enterText(find.byKey(FocusRestKeys.shortInput), '10');
    await tester.pump();
    await tester.tap(find.byKey(FocusRestKeys.save));
    await tester.pumpAndSettle();

    expect(find.byKey(FocusRestKeys.sheet), findsNothing);
    expect(provider.config.shortBreakDuration, 600);
    expect(find.text('短休 10 分钟 · 长休 15 分钟'), findsOneWidget);
  });

  testWidgets('运行中打开面板提示不影响当前计时，保存不重置剩余时长', (tester) async {
    final provider = PomodoroProvider();
    provider.toggleTimer();
    final before = provider.state.remainingSeconds;
    await _openSheet(tester, provider);

    expect(find.byKey(FocusRestKeys.sheet), findsOneWidget);
    expect(find.text('当前计时不受影响；之后开始的专注使用新设置。'), findsOneWidget);

    await tester.enterText(find.byKey(FocusRestKeys.longInput), '20');
    await tester.pump();
    await tester.tap(find.byKey(FocusRestKeys.save));
    await tester.pumpAndSettle();

    expect(find.byKey(FocusRestKeys.sheet), findsNothing);
    expect(provider.config.longBreakDuration, 1200);
    expect(provider.state.isRunning, isTrue);
    expect(provider.state.remainingSeconds, closeTo(before, 2));
    provider.resetTimer();
  });

  testWidgets('生成号过期时保存失败并留在面板内', (tester) async {
    final provider = PomodoroProvider();
    await _openSheet(tester, provider);
    // 面板打开后清理账号：页面持有的生成号立即过期。
    provider.resetLocalState();

    await tester.tap(find.byKey(FocusRestKeys.save));
    await tester.pumpAndSettle();

    expect(find.byKey(FocusRestKeys.sheet), findsOneWidget);
    expect(find.text('账号或连接状态已变化，请重新打开后再保存。'), findsOneWidget);
    expect(provider.config.shortBreakDuration, 300);
  });

  testWidgets('清空数字后点击加号从 1 开始', (tester) async {
    final provider = PomodoroProvider();
    await _openSheet(tester, provider);
    await tester.enterText(find.byKey(FocusRestKeys.shortInput), '');
    await tester.tap(find.widgetWithIcon(IconButton, Icons.add).first);
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(FocusRestKeys.shortInput))
          .controller!
          .text,
      '1',
    );
  });

  for (final throwing in <bool>[false, true]) {
    testWidgets('保存存储失败 ($throwing) 时保留草稿并显示错误', (tester) async {
      SharedPreferencesStorePlatform.instance = _FailingRestStore(throwing);
      final provider = PomodoroProvider();
      await _openSheet(tester, provider);
      await tester.enterText(find.byKey(FocusRestKeys.shortInput), '12');
      await tester.tap(find.byKey(FocusRestKeys.save));
      await tester.pumpAndSettle();
      expect(find.byKey(FocusRestKeys.sheet), findsOneWidget);
      expect(find.text('保存失败，请稍后再试。'), findsOneWidget);
      expect(provider.config.shortBreakDuration, 300);
      expect(
        tester
            .widget<TextField>(find.byKey(FocusRestKeys.shortInput))
            .controller!
            .text,
        '12',
      );
    });
  }

  testWidgets('nativeAndroid 使用底部面板，nativeMac 使用居中弹窗', (tester) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    final provider = PomodoroProvider();
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await _openSheet(tester, provider);
      final sheet = tester.getRect(find.byKey(FocusRestKeys.sheet));
      expect(sheet.bottom, tester.getSize(find.byType(Scaffold)).height);
      await tester.tap(find.byKey(FocusRestKeys.cancel));
      await tester.pumpAndSettle();

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await tester.tap(find.byKey(FocusRestKeys.summary));
      await tester.pumpAndSettle();
      expect(find.byKey(FocusRestKeys.sheet), findsOneWidget);
      expect(find.byType(AppModalSheet), findsOneWidget);
      final dialog = tester.getRect(find.byType(AppModalSheet));
      expect(dialog.width, lessThanOrEqualTo(464));
      expect(
        dialog.center.dx,
        closeTo(tester.getSize(find.byType(Scaffold)).width / 2, 1),
      );
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}
