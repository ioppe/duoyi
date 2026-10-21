import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('统计页支持复制 Markdown 报告', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final reportModel = File('lib/core/period_report.dart').readAsStringSync();
    final cjkFont = File('assets/fonts/DroidSansFallbackFull.ttf');

    expect(source, contains("tooltip: '复制报告'"));
    expect(source, contains("tooltip: '报告分享图'"));
    expect(source, contains('Clipboard.setData'));
    expect(source, contains("package:share_plus/share_plus.dart"));
    expect(source, contains("package:pdf/pdf.dart"));
    expect(source, contains("package:pdf/widgets.dart"));
    expect(pubspec, contains('pdf:'));
    expect(source, contains('SharePlus.instance.share'));
    expect(source, contains('ShareParams('));
    expect(source, contains('XFile(file.path)'));
    expect(source, contains('_buildReportMarkdown'));
    expect(source, contains('_ReportShareDialog'));
    expect(source, contains('PeriodReportDigest'));
    expect(source, contains('_PeriodReportDigestCard'));
    expect(source, contains('PeriodReportKind.weekly'));
    expect(source, contains('PeriodReportKind.monthly'));
    expect(source, contains('PeriodReportKind.yearly'));
    expect(source, contains('_copyDigest'));
    expect(source, contains('digest.toMarkdown'));
    expect(reportModel, contains('PeriodReportKind.yearly => \'年度报告\''));
    expect(source, contains('RenderRepaintBoundary'));
    expect(source, contains('ui.ImageByteFormat.png'));
    expect(source, contains('pw.Document'));
    expect(source, contains('PdfPageFormat.a4'));
    expect(source, contains('pw.MemoryImage'));
    expect(source, contains('保存 PDF'));
    expect(source, contains('_ReportPdfTemplate'));
    expect(source, contains('_ReportPdfTemplate.visual'));
    expect(source, contains('_ReportPdfTemplate.archive'));
    expect(source, contains('_ReportPdfTemplate.briefing'));
    expect(source, contains('_ReportPdfTemplate.dashboard'));
    expect(source, contains('_ReportPdfTemplate.timeline'));
    expect(source, contains('SegmentedButton<_ReportPdfTemplate>'));
    expect(source, contains('SingleChildScrollView'));
    expect(source, contains('scrollDirection: Axis.horizontal'));
    expect(source, contains('PDF 模板'));
    expect(source, contains('视觉版'));
    expect(source, contains('归档版'));
    expect(source, contains('简报版'));
    expect(source, contains('仪表版'));
    expect(source, contains('时间线版'));
    expect(source, contains('_buildPdfDocument'));
    expect(source, contains('_buildBriefingPdfContent'));
    expect(source, contains('_buildBriefingSection'));
    expect(source, contains('_buildDashboardPdfContent'));
    expect(source, contains('_buildDashboardMetricCard'));
    expect(source, contains('_buildDashboardRankItem'));
    expect(source, contains('_buildTimelinePdfContent'));
    expect(source, contains('_buildTimelineItem'));
    expect(source, contains('_buildTimelineSideSection'));
    expect(source, contains('_buildPdfBullet'));
    expect(source, contains('_buildPdfMutedText'));
    expect(source, contains('_buildSearchablePdfContent'));
    expect(source, contains('_reportPdfTemplateLabel'));
    expect(source, contains('_markdownTitle'));
    expect(source, contains('_markdownSectionItems'));
    expect(source, contains('pw.MultiPage'));
    expect(source, contains('pw.Text('));
    expect(source, contains('可检索文字层'));
    expect(source, contains('适合快速复盘、转发和归档'));
    expect(source, contains('仪表版适合复盘关键指标和投入结构'));
    expect(source, contains('时间线版适合按行动顺序复盘过程'));
    expect(source, contains("rootBundle.load("));
    expect(source, contains('assets/fonts/DroidSansFallbackFull.ttf'));
    expect(source, contains('pw.Font.ttf'));
    expect(source, contains('pw.ThemeData.withFont'));
    expect(source, contains('fontFallback'));
    expect(source, contains('template == _ReportPdfTemplate.visual'));
    expect(pubspec, contains('assets/fonts/'));
    expect(cjkFont.existsSync(), isTrue);
    expect(source, contains('PDF 报告已保存并打开系统分享面板'));
    expect(source, contains('getTemporaryDirectory'));
    expect(source, contains('# 多仪时光报告'));
    expect(source, contains('## 概览'));
    expect(source, contains('## 时间投入分布'));
    expect(source, contains('## 最近时间记录'));
    expect(source, contains('## 已完成待办'));
    expect(source, contains('报告已复制'));
    expect(source, contains('分享图已保存并打开系统分享面板'));
  });

  test('统计页支持云端 AI 个性化报告解读', () {
    final source = File(
      'lib/screens/statistics_screen.dart',
    ).readAsStringSync();
    final aiService = File('lib/services/ai_service.dart').readAsStringSync();

    expect(source, contains("import '../services/ai_service.dart';"));
    expect(source, contains("import 'ai_history_screen.dart';"));
    expect(source, contains('context.watch<AiService>()'));
    expect(source, contains('_runDigestAiReview'));
    expect(source, contains('personalizedReportReview('));
    expect(source, contains('reportMarkdown: _digestMarkdown(digest)'));
    expect(source, contains("label: const Text('AI 解读')"));
    expect(source, contains("label: const Text('AI 历史')"));
    expect(source, contains('云端个性化解读'));
    expect(source, contains('管理员启用 AI 后可生成云端个性化解读'));
    expect(
      source,
      contains('MaterialPageRoute(builder: (_) => const AiHistoryScreen())'),
    );
    expect(source, contains('_aiReportReview = null'));
    expect(source, contains('_aiReportError = null'));

    expect(aiService, contains('Future<String> personalizedReportReview('));
    expect(aiService, contains("'/api/ai/chat'"));
    expect(aiService, contains('云端效率报告分析师'));
    expect(aiService, contains('未来 7 天 3 条可执行动作'));
    expect(aiService, contains(r"summary: '统计报告 AI 解读：$periodLabel'"));
    expect(aiService, contains('_reviewHistory.insert(0, entry)'));
    expect(aiService, contains('await _saveHistory()'));
    // 推理模型先花 reasoning token，解读预算需覆盖“思考 + 正文”。
    expect(aiService, contains('maxTokens: 2200'));
  });
}
