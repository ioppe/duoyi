import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/server_config_status.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/widgets/report_ai_review_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 面板本身只依赖真实主题与真实 i18n：这里不复制整个统计页的数据集，
/// 直接验证「配置状态 → 提示/重试/历史保留」的可见行为。
Widget _panelApp({
  required bool aiEnabled,
  ServerConfigStatus configStatus = ServerConfigStatus.ready,
  VoidCallback? onRetryConfig,
  AiReviewEntry? latestEntry,
  double textScale = 1,
  bool reduceMotion = false,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppBrands.defaultBrand.theme,
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ReportAiReviewPanel(
          aiEnabled: aiEnabled,
          configStatus: configStatus,
          onRetryConfig: onRetryConfig,
          job: null,
          latestEntry: latestEntry,
          onGenerate: () {},
          onRetrySave: () {},
        ),
      ),
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reduceMotion,
      ),
      child: child!,
    ),
  );
}

/// 加载细线是持续动画：细分帧推进，绝不 pumpAndSettle。
Future<void> _pumpFrames(WidgetTester tester, {int frames = 3}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Finder _richText(String text) => find.textContaining(text, findRichText: true);

AiReviewEntry _archivedEntry() => AiReviewEntry(
  id: 'e-archived',
  createdAt: DateTime(2026, 10, 21, 9),
  content: '**结论**：保持记录。\n\nARCHIVED-VISIBLE',
  summary: '本周存档',
  model: 'test-model',
  kind: AiService.statisticsReportKind,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  testWidgets('unknown/loading 只显示细加载提示，不冒充管理员关闭', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final status in const [
      ServerConfigStatus.unknown,
      ServerConfigStatus.loading,
    ]) {
      await tester.pumpWidget(
        _panelApp(aiEnabled: false, configStatus: status),
      );
      await _pumpFrames(tester);

      expect(
        find.text(I18n.tr('statistics.ai.config.loading')),
        findsOneWidget,
        reason: '${status.name} 应如实显示加载中',
      );
      expect(
        find.text(I18n.tr('statistics.ai.disabled_hint')),
        findsNothing,
        reason: '${status.name} 不能显示成管理员关闭',
      );
      expect(find.text(I18n.tr('statistics.ai.config.failed')), findsNothing);
      expect(find.text(I18n.tr('statistics.ai.config.retry')), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('failed 显示失败与重试，点击执行真实绑定回调', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var retries = 0;
    await tester.pumpWidget(
      _panelApp(
        aiEnabled: false,
        configStatus: ServerConfigStatus.failed,
        onRetryConfig: () => retries++,
      ),
    );
    await _pumpFrames(tester);

    expect(find.text(I18n.tr('statistics.ai.config.failed')), findsOneWidget);
    expect(find.text(I18n.tr('statistics.ai.disabled_hint')), findsNothing);
    expect(find.text(I18n.tr('statistics.ai.config.loading')), findsNothing);

    final retry = find.text(I18n.tr('statistics.ai.config.retry'));
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    await tester.pump();
    expect(retries, 1, reason: '重试必须真的调用注入的回调');

    await tester.tap(retry);
    await tester.pump();
    expect(retries, 2);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('只有 ready 且管理员关闭才显示原提示', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _panelApp(aiEnabled: false, configStatus: ServerConfigStatus.ready),
    );
    await _pumpFrames(tester);
    expect(find.text(I18n.tr('statistics.ai.disabled_hint')), findsOneWidget);
    expect(find.text(I18n.tr('statistics.ai.config.loading')), findsNothing);
    expect(find.text(I18n.tr('statistics.ai.config.failed')), findsNothing);

    await tester.pumpWidget(
      _panelApp(aiEnabled: true, configStatus: ServerConfigStatus.ready),
    );
    await _pumpFrames(tester);
    expect(
      find.text(I18n.tr('statistics.ai.disabled_hint')),
      findsNothing,
      reason: '已启用时不得出现管理员关闭提示',
    );
    expect(find.text(I18n.tr('statistics.ai.config.loading')), findsNothing);
    expect(find.text(I18n.tr('statistics.ai.config.failed')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('loading/failed 下已存档解读仍可见且可复制', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

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

    final entry = _archivedEntry();
    for (final status in const [
      ServerConfigStatus.loading,
      ServerConfigStatus.failed,
    ]) {
      copied = null;
      await tester.pumpWidget(
        _panelApp(aiEnabled: false, configStatus: status, latestEntry: entry),
      );
      await _pumpFrames(tester);

      expect(
        find.text(I18n.tr('statistics.ai.result_title')),
        findsOneWidget,
        reason: '${status.name} 下历史结果不能被配置提示顶掉',
      );
      expect(_richText('ARCHIVED-VISIBLE'), findsWidgets);

      final copy = find.text(I18n.tr('statistics.ai.copy_insight'));
      expect(copy, findsOneWidget);
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await _pumpFrames(tester);
      expect(copied, entry.content);

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('320 宽 + 2x 字号 + 减少动效下混合状态不溢出', (tester) async {
    addTearDown(tester.view.reset);
    FlutterErrorDetails? lastLayoutError;
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      lastLayoutError = details;
      previousErrorHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousErrorHandler);

    final entry = _archivedEntry();
    for (final status in const [
      ServerConfigStatus.loading,
      ServerConfigStatus.failed,
    ]) {
      lastLayoutError = null;
      tester.view.physicalSize = const Size(320, 1600);
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(
        _panelApp(
          aiEnabled: false,
          configStatus: status,
          latestEntry: entry,
          onRetryConfig: () {},
          textScale: 2,
          reduceMotion: true,
        ),
      );
      await _pumpFrames(tester);

      expect(
        tester.takeException(),
        isNull,
        reason: '${status.name} 2x 字号 320 宽不溢出\n$lastLayoutError',
      );
      expect(find.text(I18n.tr('statistics.ai.result_title')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
