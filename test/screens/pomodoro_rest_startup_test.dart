import 'dart:convert';

import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/pomodoro_screen.dart';
import 'package:duoyi/widgets/focus_rest_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 实机 C05：快速重启后进入专注页，5/15/4 默认值覆盖已保存的 7/20/3。
/// 这里复现"启动批次 14s 延迟未水合前就进入页面"的时序。
Map<String, Object> _savedRestConfig() => <String, Object>{
  'pomodoro_config': json.encode(
    PomodoroConfig(
      focusDuration: 1800,
      shortBreakDuration: 420,
      longBreakDuration: 1200,
      sessionsPerLongBreak: 3,
      linkShortBreakToFocus: false,
      autoStartBreaks: true,
      autoStartFocus: false,
      whiteNoiseSound: 'rain',
      strictFocusMode: false,
    ).toJson(),
  ),
};

Future<Map<String, dynamic>?> _storedConfig() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('pomodoro_config');
  return raw == null ? null : json.decode(raw) as Map<String, dynamic>;
}

class _Harness {
  _Harness()
    : pomodoro = PomodoroProvider(),
      rooms = FocusRoomProvider(),
      theme = ThemeProvider(),
      customSounds = CustomFocusSoundProvider(),
      auth = AuthProvider();

  final PomodoroProvider pomodoro;
  final FocusRoomProvider rooms;
  final ThemeProvider theme;
  final CustomFocusSoundProvider customSounds;
  final AuthProvider auth;

  Widget build() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoro),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<FocusRoomProvider>.value(value: rooms),
        ChangeNotifierProvider<CustomFocusSoundProvider>.value(
          value: customSounds,
        ),
      ],
      child: MaterialApp(
        theme: theme.brand.theme,
        home: const PomodoroScreen(),
      ),
    );
  }

  void dispose() {
    pomodoro.dispose();
    rooms.dispose();
    theme.dispose();
    customSounds.dispose();
    auth.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final font = FontLoader(DesignTokens.fontFamily)
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'));
    await font.load();
  });

  setUp(() => SharedPreferences.setMockInitialValues(_savedRestConfig()));

  Future<_Harness> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = _Harness();
    addTearDown(harness.dispose);
    expect(harness.pomodoro.storageHydrated, isFalse);
    await tester.pumpWidget(harness.build());
    return harness;
  }

  testWidgets('快速重启未预先水合时进入专注页，已保存的休息设置不被默认值覆盖', (tester) async {
    // 只放 mock 存储，不调用 loadFromStorage：模拟 14s 延迟批次尚未执行。
    final harness = await pumpScreen(tester);

    await tester.pumpAndSettle();

    final config = harness.pomodoro.config;
    expect(config.shortBreakDuration, 420);
    expect(config.longBreakDuration, 1200);
    expect(config.sessionsPerLongBreak, 3);
    expect(config.autoStartBreaks, isTrue);
    expect(config.whiteNoiseSound, 'rain');
    expect(config.strictFocusMode, isFalse);

    // 原初始化区域（默认关联自习室）会写回整份配置：写入的必须是水合后的值。
    expect(find.byKey(FocusRestKeys.summary), findsOneWidget);
    final stored = await _storedConfig();
    expect(stored, isNotNull);
    expect(stored!['shortBreakDuration'], 420);
    expect(stored['longBreakDuration'], 1200);
    expect(stored['sessionsPerLongBreak'], 3);
    expect(stored['autoStartBreaks'], isTrue);
    expect(stored['whiteNoiseSound'], 'rain');
    expect(stored['strictFocusMode'], isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('存储水合完成前不渲染默认计时、休息设置与主操作', (tester) async {
    await pumpScreen(tester);

    // 首帧：加载使用不确定进度；计时环本身也使用确定进度控件。
    final loading = find.byWidgetPredicate(
      (widget) => widget is CircularProgressIndicator && widget.value == null,
    );
    expect(loading, findsOneWidget);
    expect(find.byKey(FocusRestKeys.summary), findsNothing);
    expect(find.text('开始专注'), findsNothing);

    await tester.pumpAndSettle();

    expect(loading, findsNothing);
    expect(find.byKey(FocusRestKeys.summary), findsOneWidget);
    expect(find.text('开始专注'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已水合的 Provider 进页不重复加载、不重置任务', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.pomodoro.loadFromStorage();
    harness.pomodoro.setTaskName('写代码');
    final revision = harness.pomodoro.persistedRevision;

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.build());
    await tester.pumpAndSettle();

    // 只允许"默认关联自习室"那一次写入；再读一次存储会多加一次 revision 并重置任务。
    expect(harness.pomodoro.persistedRevision, revision + 1);
    expect(harness.pomodoro.state.taskName, '写代码');
    expect(harness.pomodoro.config.shortBreakDuration, 420);
    expect(harness.pomodoro.storageHydrated, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('账号代际推进后页面重新按需水合，不用默认值覆盖磁盘配置', (tester) async {
    final harness = await pumpScreen(tester);
    await tester.pumpAndSettle();
    expect(harness.pomodoro.storageHydrated, isTrue);

    // 换号/重置：代际推进，旧代际的水合结果立即失效。
    harness.pomodoro.resetLocalState();
    expect(harness.pomodoro.storageHydrated, isFalse);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(FocusRestKeys.summary), findsNothing);

    await tester.pumpAndSettle();
    expect(harness.pomodoro.storageHydrated, isTrue);
    expect(harness.pomodoro.config.shortBreakDuration, 420);
    expect(harness.pomodoro.config.sessionsPerLongBreak, 3);
    final stored = await _storedConfig();
    expect(stored!['shortBreakDuration'], 420);
    expect(stored['longBreakDuration'], 1200);
    expect(tester.takeException(), isNull);
  });
}
