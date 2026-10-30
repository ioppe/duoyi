import 'dart:convert';
import 'dart:io';

import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/pomodoro_floating_window_size.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/pomodoro_floating_window_service.dart';
import 'package:duoyi/widgets/pomodoro_floating_window_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/pomodoro_floating_window_host');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late PomodoroProvider pomodoro;
  late LocaleProvider locale;
  late ThemeProvider theme;
  late AppLockProvider lock;
  late AuthProvider auth;
  late AppUpdateService update;
  late PomodoroFloatingWindowService service;
  late PreferencesProvider preferences;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
    calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    pomodoro = PomodoroProvider();
    locale = LocaleProvider();
    theme = ThemeProvider();
    lock = AppLockProvider();
    auth = AuthProvider();
    update = AppUpdateService(repo: 'duoyi/test', currentVersion: '1.0.0');
    preferences = PreferencesProvider();
    service = PomodoroFloatingWindowService(supported: true, channel: channel);
  });

  tearDown(() {
    service.detach();
    service.dispose();
    pomodoro.dispose();
    locale.dispose();
    theme.dispose();
    lock.dispose();
    auth.dispose();
    update.dispose();
    preferences.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Widget host({ThemeData? inheritedTheme}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoro),
        ChangeNotifierProvider<LocaleProvider>.value(value: locale),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<AppLockProvider>.value(value: lock),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<AppUpdateService>.value(value: update),
        ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
      ],
      child: MaterialApp(
        theme: inheritedTheme ?? theme.brand.theme,
        home: PomodoroFloatingWindowHost(
          service: service,
          child: const Scaffold(body: Text('计时页')),
        ),
      ),
    );
  }

  testWidgets('全局 Host 绑定 Provider，每秒 tick 转发但不自动 show', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    expect(
      calls.where((call) => call.method == 'update'),
      isNotEmpty,
      reason: '绑定时先同步一次快照',
    );

    calls.clear();
    pomodoro.startIfIdle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    final updates = calls.where((call) => call.method == 'update').toList();
    expect(updates, isNotEmpty);
    final snapshot = (updates.last.arguments as Map<Object?, Object?>)
        .cast<String, Object?>();
    expect(snapshot['isRunning'], isTrue);
    expect(snapshot['timeText'], '24:59');
    expect(calls.where((call) => call.method == 'show'), isEmpty);

    pomodoro.toggleTimer();
    await tester.pump();
  });

  testWidgets('应用锁定后隐藏面板且恢复不自动重开', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    expect(await service.open(), isTrue);
    await tester.pump();
    expect(service.isVisible, isTrue);

    await lock.setPin('1234');
    lock.lock();
    await tester.pump();

    expect(service.isVisible, isFalse);
    expect(calls.where((call) => call.method == 'hide'), isNotEmpty);

    final showsBefore = calls.where((call) => call.method == 'show').length;
    await lock.unlockWith('1234');
    await tester.pump();
    expect(service.isVisible, isFalse, reason: '恢复后由用户重新打开');
    expect(
      calls.where((call) => call.method == 'show'),
      hasLength(showsBefore),
    );
  });

  testWidgets('切换服务器身份隐藏面板', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    expect(await service.open(), isTrue);
    await tester.pump();

    await tester.runAsync(
      () => auth.configureServer('https://another.example'),
    );
    await tester.pump();

    expect(service.isVisible, isFalse);
    expect(calls.where((call) => call.method == 'hide'), isNotEmpty);
  });

  testWidgets('入口按钮 tooltip 切换开/关，失败时显示 I18n 提示', (tester) async {
    service.attach(pomodoro);
    service.configure(
      available: true,
      sessionIdentity: 'local|',
      windowTitle: '专注',
      playLabel: I18n.tr('focus.start'),
      pauseLabel: I18n.tr('focus.pause'),
      closeLabel: I18n.tr('focus.floating.close'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [PomodoroFloatingWindowButton(service: service)],
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    );

    final openTooltip = I18n.tr('focus.floating.open');
    final hideTooltip = I18n.tr('focus.floating.hide');
    expect(find.byTooltip(openTooltip), findsOneWidget);

    await tester.tap(find.byTooltip(openTooltip));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.method == 'show'), hasLength(1));
    expect(find.byTooltip(hideTooltip), findsOneWidget);

    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'window_unavailable');
    });
    await tester.tap(find.byTooltip(hideTooltip));
    await tester.pumpAndSettle();

    expect(find.text(I18n.tr('focus.floating.error')), findsOneWidget);
    expect(service.isVisible, isTrue, reason: '隐藏失败时面板仍在显示');
  });
  testWidgets('悬浮窗继承卡片与主按钮主题，切换主题不重开计时', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    await service.open();
    pomodoro.startIfIdle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    Map<String, Object?> latest() =>
        (calls.lastWhere((call) => call.method == 'update').arguments
                as Map<Object?, Object?>)
            .cast<String, Object?>();
    final original = latest();
    final originalAppearance = original['appearance']! as Map;
    final originalTheme = theme.brand.theme;
    final originalSurface = originalTheme.extension<AppSurfaceStyle>()!;
    expect(
      originalAppearance['backgroundColor'],
      Color.alphaBlend(
        originalSurface.cardFillColor!,
        originalTheme.colorScheme.surface,
      ).toARGB32(),
    );
    expect(
      originalAppearance['windowBackgroundColor'],
      originalTheme.scaffoldBackgroundColor.toARGB32(),
    );
    expect(
      originalAppearance['windowForegroundColor'],
      originalTheme.colorScheme.onSurface.toARGB32(),
    );
    expect(
      originalAppearance['primaryColor'],
      originalTheme.filledButtonTheme.style!.backgroundColor!
          .resolve({})!
          .toARGB32(),
    );
    expect(originalAppearance['cornerRadius'], originalSurface.cardRadius);
    expect(
      originalAppearance['timeFontSize'],
      DesignTokens.fontSizeNumericHighlight,
    );
    final remaining = pomodoro.state.remainingSeconds;

    await tester.runAsync(() => theme.setBrand('re0'));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final alternate = latest();
    final alternateAppearance = alternate['appearance']! as Map;
    expect(
      alternateAppearance['primaryColor'],
      theme.brand.theme.filledButtonTheme.style!.backgroundColor!
          .resolve({})!
          .toARGB32(),
    );
    expect(
      alternateAppearance['primaryColor'],
      isNot(originalAppearance['primaryColor']),
    );
    expect(alternateAppearance['cornerRadius'], DesignTokens.radiusCard);
    expect(pomodoro.state.remainingSeconds, remaining);
    expect(pomodoro.state.isRunning, isTrue);
    expect(service.isVisible, isTrue);
    expect(calls.where((call) => call.method == 'show'), hasLength(1));

    final exportPath = Platform.environment['DUOYI_FLOATING_THEME_EXPORT'];
    if (exportPath != null && exportPath.isNotEmpty) {
      File(exportPath).writeAsStringSync(
        jsonEncode({'default': original, 'alternate': alternate}),
      );
    }
    pomodoro.toggleTimer();
    await tester.pump();
  });

  testWidgets('继承深色 Theme，不使用固定白底青绿配色', (tester) async {
    final dark = ThemeData.dark();
    await tester.pumpWidget(host(inheritedTheme: dark));
    await tester.pump();
    final snapshot =
        calls.lastWhere((call) => call.method == 'update').arguments as Map;
    final appearance = snapshot['appearance'] as Map;
    expect(appearance['backgroundColor'], dark.colorScheme.surface.toARGB32());
    expect(
      appearance['foregroundColor'],
      dark.colorScheme.onSurface.toARGB32(),
    );
    expect(appearance['primaryColor'], dark.colorScheme.primary.toARGB32());
    expect(
      appearance['windowBackgroundColor'],
      dark.scaffoldBackgroundColor.toARGB32(),
    );
    expect(
      appearance['windowForegroundColor'],
      dark.colorScheme.onSurface.toARGB32(),
    );
  });

  testWidgets('悬浮窗尺寸默认 large，切换 compact 只发送 update', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();
    expect(await service.open(), isTrue);
    await tester.pump();

    Map<String, Object?> latestSnapshot() =>
        (calls.lastWhere((call) => call.method == 'update').arguments
                as Map<Object?, Object?>)
            .cast<String, Object?>();
    expect(latestSnapshot()['windowSize'], 'large');
    final showCount = calls.where((call) => call.method == 'show').length;
    expect(showCount, 1);

    await tester.runAsync(
      () => preferences.setPomodoroFloatingWindowSize(
        PomodoroFloatingWindowSize.compact,
      ),
    );
    await tester.pump();

    expect(latestSnapshot()['windowSize'], 'compact');
    expect(
      calls.where((call) => call.method == 'show'),
      hasLength(showCount),
      reason: '尺寸切换只更新已显示面板，不重新 show',
    );
    expect(service.isVisible, isTrue);
  });
}
