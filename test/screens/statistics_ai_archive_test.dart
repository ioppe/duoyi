import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/statistics_period.dart';
import 'package:duoyi/models/ai_report_context.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/ai_history_screen.dart';
import 'package:duoyi/screens/statistics_screen.dart';
import 'package:duoyi/services/ai_review_history_store.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 每个上游请求都挂在一个 Completer 上，测试可以精确控制“还在等待”的时机。
class _AiGate {
  final List<Completer<http.Response>> _pending = <Completer<http.Response>>[];
  int requestCount = 0;

  AiService service({bool enabled = true, AiReviewHistoryStore? historyStore}) {
    final ai = AiService(historyStore: historyStore);
    ai.attachClient(
      ApiClient(
        baseUrl: 'https://test.example',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/ai/chat');
          requestCount++;
          final completer = Completer<http.Response>();
          _pending.add(completer);
          return completer.future;
        }),
      ),
    );
    if (enabled) {
      ai.updateFromServerConfig({'ai_enabled': true, 'ai_model': 'test-model'});
    }
    return ai;
  }

  int get pendingCount => _pending.length;

  void reply(String content) {
    expect(_pending, isNotEmpty, reason: '没有等待中的上游请求');
    _pending.removeAt(0).complete(_chatResponse(content));
  }
}

class _RetryableArchiveStore extends AiReviewHistoryStore {
  bool allowWrites = false;
  List<String> savedEntries = <String>[];

  @override
  Future<List<String>> read() async => List<String>.of(savedEntries);

  @override
  Future<void> write(List<String> entries) async {
    if (!allowWrites) {
      throw const AiReviewHistoryStoreException('fixture archive unavailable');
    }
    savedEntries = List<String>.of(entries);
  }
}

http.Response _chatResponse(String content) => http.Response.bytes(
  utf8.encode(jsonEncode({'content': content})),
  200,
  headers: {'content-type': 'application/json'},
);

AiReportContext _weekContext() => AiReportContext.fromWindow(
  StatisticsWindow(StatisticsPeriod.week),
  timeZone: LocalTimezoneResolver.currentIana,
);

AiReportContext _previousWeekContext() {
  final week = _weekContext();
  return AiReportContext(
    period: StatisticsPeriod.week,
    start: week.start.subtract(const Duration(days: 7)),
    end: week.end.subtract(const Duration(days: 7)),
    timeZone: week.timeZone,
  );
}

const Key _captureKey = ValueKey('ai_report_capture');

ThemeData _darkTheme() => AppBrands.starRail.theme;

Widget _app(
  AiService ai,
  Widget home, {
  ThemeData? theme,
  String? captureKey,
  bool textScaleTwo = false,
  bool reduceMotion = false,
}) {
  final bool capture = captureKey != null;
  Widget app = MultiProvider(
    providers: [
      ChangeNotifierProvider<AiService>.value(value: ai),
      ChangeNotifierProvider(create: (_) => TodoProvider()),
      ChangeNotifierProvider(create: (_) => GoalProvider()),
      ChangeNotifierProvider(create: (_) => HabitProvider()),
      ChangeNotifierProvider(create: (_) => PomodoroProvider()),
      ChangeNotifierProvider(create: (_) => TimeAuditProvider()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? AppBrands.defaultBrand.theme,
      home: home,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: textScaleTwo ? const TextScaler.linear(2) : null,
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
    ),
  );
  if (capture) {
    app = RepaintBoundary(key: _captureKey, child: app);
  }
  return app;
}

Finder _aiAction() {
  final regenerate = find.text(I18n.tr('statistics.ai.regenerate'));
  if (regenerate.evaluate().isNotEmpty) return regenerate;
  return find.text(I18n.tr('statistics.ai.generate'));
}

Future<void> _tapAiAction(WidgetTester tester) async {
  final target = _aiAction();
  await tester.ensureVisible(target);
  await tester.tap(target);
}

Finder _insightText(String text) =>
    find.textContaining(text, findRichText: true);

Finder _elapsedText() {
  final template = I18n.tr('statistics.ai.elapsed');
  final prefix = template.split('{seconds}').first;
  return find.byWidgetPredicate(
    (widget) => widget is Text && (widget.data ?? '').startsWith(prefix),
  );
}

Finder _toggle(String id) => find.byKey(ValueKey('ai_history_toggle_$id'));

/// 可选真实截图：设置 AI_REPORT_CAPTURE_DIR 时把当前画面写成 PNG。
/// 需要真实 Noto/图标字体，避免截图出现方块字。
Future<void> _loadCaptureFonts() async {
  await _installNoto();
  final iconsPath = _iconsFontPath();
  if (iconsPath != null) {
    await _installIcons(iconsPath);
  }
}

Future<void> _installNoto() async {
  try {
    final loader = FontLoader('NotoSansSC')
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Variable.ttf'));
    await loader.load();
  } catch (_) {
    // 截图属于可选辅助，字体不可用时不阻塞断言。
  }
}

Future<void> _installIcons(String path) async {
  try {
    final bytes = File(path).readAsBytesSync();
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(bytes.buffer.asByteData()));
    await loader.load();
  } catch (_) {
    // 图标字体同样只是让截图可读，不影响断言。
  }
}

String? _iconsFontPath() {
  final explicit = Platform.environment['AI_REPORT_CAPTURE_ICONS_FONT'];
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null || flutterRoot.isEmpty) return null;
  final path =
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
  return File(path).existsSync() ? path : null;
}

Future<void> _captureIfRequested(WidgetTester tester, String name) async {
  final dir = Platform.environment['AI_REPORT_CAPTURE_DIR'];
  if (dir == null || dir.isEmpty) return;
  // 图片编码和文件 IO 需要真实异步事件，不能留在 widget 测试的假时钟里等待。
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return;
    final file = File('$dir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  setUpAll(() async {
    final dir = Platform.environment['AI_REPORT_CAPTURE_DIR'];
    if (dir != null && dir.isNotEmpty) {
      await _loadCaptureFonts();
    }
  });

  testWidgets('生成的解读在离开统计页再回来后仍然可见', (tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final gate = _AiGate();
    final ai = gate.service();

    await tester.pumpWidget(_app(ai, const StatisticsScreen()));
    await tester.pump();
    await _tapAiAction(tester);
    await tester.pump();
    expect(gate.pendingCount, 1, reason: '点击后应立即发出一次上游请求');

    gate.reply('**总判断**：先恢复真实记录。');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text(I18n.tr('statistics.ai.result_title')), findsOneWidget);
    expect(_insightText('先恢复真实记录'), findsWidgets);

    // 销毁统计页（模拟离开页面）再重新进入：结果由 service 持有。
    await tester.pumpWidget(_app(ai, const SizedBox.shrink()));
    await tester.pump();
    await tester.pumpWidget(_app(ai, const StatisticsScreen()));
    await tester.pump();

    expect(find.text(I18n.tr('statistics.ai.result_title')), findsOneWidget);
    expect(_insightText('先恢复真实记录'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    ai.dispose();
  });

  testWidgets('周/月/年各自恢复自己的存档解读，切期不串结果', (tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final gate = _AiGate();
    final ai = gate.service();
    await tester.pumpWidget(_app(ai, const StatisticsScreen()));
    await tester.pump();

    Future<void> archiveFor(String periodKey, String content) async {
      await tester.tap(find.text(I18n.tr('statistics.period.$periodKey')));
      await tester.pump();
      await _tapAiAction(tester);
      await tester.pump();
      gate.reply(content);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(_insightText(content), findsWidgets, reason: periodKey);
    }

    await archiveFor('week', 'WEEK-INSIGHT');
    await archiveFor('month', 'MONTH-INSIGHT');
    await archiveFor('year', 'YEAR-INSIGHT');
    expect(gate.requestCount, 3);

    await tester.tap(find.text(I18n.tr('statistics.period.week')));
    await tester.pumpAndSettle();
    expect(_insightText('WEEK-INSIGHT'), findsWidgets);
    expect(_insightText('MONTH-INSIGHT'), findsNothing);
    expect(_insightText('YEAR-INSIGHT'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    ai.dispose();
  });

  testWidgets('等待中离页再进入仍显示进度，完成后落入正确周期', (tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final gate = _AiGate();
    final ai = gate.service();
    await tester.pumpWidget(_app(ai, const StatisticsScreen()));
    await tester.pump();
    await _tapAiAction(tester);
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text(I18n.tr('statistics.ai.stage.generating')),
      findsOneWidget,
    );
    expect(_elapsedText(), findsOneWidget, reason: '应显示真实已用时长');
    expect(find.text(I18n.tr('statistics.ai.leave_hint')), findsOneWidget);

    await tester.pumpWidget(_app(ai, const SizedBox.shrink()));
    await tester.pump();
    await tester.pumpWidget(_app(ai, const StatisticsScreen()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text(I18n.tr('statistics.ai.stage.generating')),
      findsOneWidget,
      reason: '重新进入后应恢复进行中的任务状态',
    );
    expect(_insightText('PENDING-INSIGHT'), findsNothing);

    gate.reply('PENDING-INSIGHT');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(_insightText('PENDING-INSIGHT'), findsWidgets);
    expect(find.text(I18n.tr('statistics.ai.stage.generating')), findsNothing);
    expect(gate.requestCount, 1);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    ai.dispose();
  });

  testWidgets('先切到月再收到周回复时，月视图不会显示周内容', (tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final gate = _AiGate();
    final ai = gate.service();
    await tester.pumpWidget(_app(ai, const StatisticsScreen()));
    await tester.pump();
    await _tapAiAction(tester);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text(I18n.tr('statistics.period.month')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text(I18n.tr('statistics.ai.stage.generating')),
      findsNothing,
      reason: '月周期没有进行中的任务',
    );

    gate.reply('WEEK-ONLY');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(_insightText('WEEK-ONLY'), findsNothing);

    await tester.tap(find.text(I18n.tr('statistics.period.week')));
    await tester.pumpAndSettle();
    expect(_insightText('WEEK-ONLY'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    ai.dispose();
  });

  testWidgets('重复点击只发出一次上游请求', (tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final gate = _AiGate();
    final ai = gate.service();
    await tester.pumpWidget(_app(ai, const StatisticsScreen()));
    await tester.pump();

    final target = _aiAction();
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 100));
    expect(gate.requestCount, 1);

    gate.reply('ONCE');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(gate.requestCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    ai.dispose();
  });

  testWidgets('历史选择器覆盖旧周期，旧版记录留在全部历史并提示周期未知', (tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final week = _weekContext();
    final previousWeek = _previousWeekContext();
    final entries = <AiReviewEntry>[
      AiReviewEntry(
        id: 'e-week',
        createdAt: DateTime(2026, 10, 21, 9),
        content: 'WEEK-CONTENT',
        summary: '本周存档',
        model: 'test-model',
        kind: AiService.statisticsReportKind,
        reportContext: week,
        dataThrough: week.start,
      ),
      AiReviewEntry(
        id: 'e-prev',
        createdAt: DateTime(2026, 10, 14, 9),
        content: 'PREV-CONTENT',
        summary: '上周存档',
        model: 'test-model',
        kind: AiService.statisticsReportKind,
        reportContext: previousWeek,
        dataThrough: previousWeek.end,
      ),
      AiReviewEntry(
        id: 'e-legacy',
        createdAt: DateTime(2026, 10, 1, 9),
        content: 'LEGACY-CONTENT',
        summary: '统计报告 AI 解读：旧周报',
        model: 'test-model',
      ),
      AiReviewEntry(
        id: 'e-normal',
        createdAt: DateTime(2026, 10, 2, 9),
        content: 'NORMAL-CONTENT',
        summary: '昨天回顾：保持记录',
        model: 'test-model',
        kind: AiService.weeklyReviewKind,
      ),
    ];
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ai_review_history': [
        for (final entry in entries) jsonEncode(entry.toJson()),
      ],
    });
    final ai = AiService();
    await ai.loadFromStorage();

    await tester.pumpWidget(
      _app(ai, AiHistoryScreen(initialReportContext: week)),
    );
    await tester.pumpAndSettle();

    expect(_toggle('e-week'), findsOneWidget);
    expect(_toggle('e-prev'), findsNothing, reason: '默认按传入周期过滤');
    expect(_toggle('e-legacy'), findsNothing);
    expect(_toggle('e-normal'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('ai_history_period_filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(I18n.tr('ai_history.filter.all')).last);
    await tester.pumpAndSettle();

    expect(_toggle('e-week'), findsOneWidget);
    expect(_toggle('e-prev'), findsOneWidget);
    expect(_toggle('e-legacy'), findsOneWidget);
    expect(_toggle('e-normal'), findsOneWidget);
    expect(
      find.text(I18n.tr('ai_history.period.unknown')),
      findsOneWidget,
      reason: '只有旧版统计报告提示周期未知，普通回顾不提示',
    );

    await tester.tap(find.byKey(const ValueKey('ai_history_period_filter')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.textContaining(I18nDateFormat.date(previousWeek.start)).last,
    );
    await tester.pumpAndSettle();

    expect(_toggle('e-prev'), findsOneWidget);
    expect(_toggle('e-week'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    ai.dispose();
  });

  testWidgets('AI 关闭时仍可进入历史并复制已存档解读', (tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final week = _weekContext();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ai_review_history': [
        jsonEncode(
          AiReviewEntry(
            id: 'e-disabled',
            createdAt: DateTime(2026, 10, 21, 9),
            content: 'ARCHIVED-CONTENT',
            summary: '本周存档',
            model: 'test-model',
            kind: AiService.statisticsReportKind,
            reportContext: week,
            dataThrough: week.start,
          ).toJson(),
        ),
      ],
    });
    final ai = AiService();
    await ai.loadFromStorage();
    expect(ai.enabled, isFalse);

    await tester.pumpWidget(_app(ai, const StatisticsScreen()));
    await tester.pump();
    expect(find.text(I18n.tr('statistics.ai.disabled_hint')), findsOneWidget);

    final historyButton = find.textContaining(I18n.tr('statistics.ai.history'));
    expect(historyButton, findsWidgets, reason: 'AI 关闭时历史入口仍要显示');
    await tester.ensureVisible(historyButton.first);
    await tester.tap(historyButton.first);
    await tester.pumpAndSettle();

    expect(find.byType(AiHistoryScreen), findsOneWidget);
    expect(_toggle('e-disabled'), findsOneWidget);
    expect(find.text('本周存档'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    ai.dispose();
  });

  testWidgets('正文已生成但存档失败时可复制并只重试保存', (tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = _RetryableArchiveStore();
    final gate = _AiGate();
    final ai = gate.service(historyStore: store);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    await tester.pumpWidget(_app(ai, const StatisticsScreen()));
    await tester.pump();
    await _tapAiAction(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(gate.pendingCount, 1);
    const content = '**可复制正文**\n\nUNSAVED-REPORT-CONTENT';
    gate.reply(content);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text(I18n.tr('statistics.ai.unsaved_title')), findsOneWidget);
    expect(find.text(I18n.tr('statistics.ai.result_title')), findsNothing);
    expect(ai.reportHistoryFor(_weekContext()), isEmpty);
    final copy = find.text(I18n.tr('statistics.ai.copy_insight'));
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(copied, content);
    store.allowWrites = true;
    final retry = find.text(I18n.tr('statistics.ai.retry_save'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.text(I18n.tr('statistics.ai.unsaved_title')), findsNothing);
    expect(find.text(I18n.tr('statistics.ai.result_title')), findsOneWidget);
    expect(ai.reportHistoryFor(_weekContext()), hasLength(1));
    expect(store.savedEntries, hasLength(1));
    expect(gate.requestCount, 1, reason: '重试存档不得再调用模型');
    await tester.pumpWidget(const SizedBox.shrink());
    ai.dispose();
  });

  testWidgets('320/390 大字号深色减少动效下进行中与完成状态都不溢出', (tester) async {
    addTearDown(tester.view.reset);
    FlutterErrorDetails? lastLayoutError;
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      lastLayoutError = details;
      previousErrorHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousErrorHandler);

    for (final width in const [320.0, 390.0]) {
      lastLayoutError = null;
      tester.view.physicalSize = Size(width, 1800);
      tester.view.devicePixelRatio = 1;

      final gate = _AiGate();
      final ai = gate.service();
      await tester.pumpWidget(
        _app(
          ai,
          const StatisticsScreen(),
          theme: _darkTheme(),
          textScaleTwo: true,
          reduceMotion: true,
          captureKey: Platform.environment['AI_REPORT_CAPTURE_DIR'] == null
              ? null
              : 'capture',
        ),
      );
      await tester.pump();

      await _tapAiAction(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text(I18n.tr('statistics.ai.stage.generating')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.text(I18n.tr('statistics.ai.stage.generating')),
      );
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'width=$width 进行中不溢出\n$lastLayoutError',
      );
      await _captureIfRequested(tester, 'statistics_ai_pending_$width');

      gate.reply('**结论**：保持记录。');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text(I18n.tr('statistics.ai.result_title')), findsOneWidget);
      await tester.ensureVisible(
        find.text(I18n.tr('statistics.ai.result_title')),
      );
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'width=$width 完成态不溢出\n$lastLayoutError',
      );
      await _captureIfRequested(tester, 'statistics_ai_done_$width');

      await tester.pumpWidget(const SizedBox.shrink());
      ai.dispose();
    }
  });
}
