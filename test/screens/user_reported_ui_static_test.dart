import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('用户反馈 UI 静态回归', () {
    test('黄历宜忌条目在列内容区内缩放，避免 6 月 28 日宜项溢出', () {
      final source = File('lib/screens/almanac_screen.dart').readAsStringSync();
      final panel = _sourceBlock(
        source,
        'class _VerticalYijiPanel extends StatelessWidget',
        'class _VerticalYijiColumn extends StatelessWidget',
      );
      final column = _sourceBlock(
        source,
        'class _VerticalYijiColumn extends StatelessWidget',
        'class _VerticalTerm extends StatelessWidget',
      );

      expect(panel, contains('static const int _visibleTermLimit = 5'));
      expect(
        panel,
        contains(').take(_visibleTermLimit).toList(growable: false)'),
      );
      expect(column, contains('Expanded('));
      expect(column, contains('FittedBox('));
      expect(column, contains('fit: BoxFit.scaleDown'));
      expect(
        column,
        contains("ValueKey('almanac_vertical_\${keyName}_terms_box')"),
      );
      expect(column, contains('mainAxisSize: MainAxisSize.min'));
    });

    test('我的 AI 回顾默认折叠，摘要常驻，正文手动展开', () {
      final source = File('lib/screens/mine_screen.dart').readAsStringSync();
      final card = _sourceBlock(
        source,
        'class _AiWeeklyReviewCardState extends State<_AiWeeklyReviewCard>',
        'class _TileGroup extends StatelessWidget',
      );

      expect(card, contains('bool _reviewExpanded = false;'));
      expect(card, contains('_reviewExpanded = false;'));
      expect(card, contains('_reviewExpanded = true;'));
      expect(card, contains("key: const ValueKey('mine_ai_review_toggle')"));
      expect(card, contains("key: const ValueKey('mine_ai_review_content')"));
      expect(
        card,
        contains("_reviewExpanded ? 'mine.ai.collapse' : 'mine.ai.expand'"),
      );
      expect(card, contains('ClipRect('));
      expect(card, contains('AnimatedSize('));
      expect(card, contains('_reviewExpanded'));
      expect(card, contains('const SizedBox.shrink()'));
      expect(card, contains("label: Text(I18n.tr('mine.ai.expand_full'))"));
    });

    test('我的页保留固定顶部栏，资料统计和菜单作为内容整体滚动', () {
      final source = File('lib/screens/mine_screen.dart').readAsStringSync();
      final body = _sourceBlock(
        source,
        'body: SafeArea(',
        'int _todoRate(TodoProvider t)',
      );

      expect(body, contains("restorationId: 'mine_screen_list'"));
      expect(body, contains('mineHeader'));
      expect(body, contains('mineStats'));
      expect(body, contains('mine_apps_entry'));
      final apps = _sourceBlock(
        source,
        'final appSections = <Widget>[',
        'final settingsSections = <Widget>[',
      );
      expect(apps, contains('aiAssistant'));
      expect(body.indexOf('mineHeader'), lessThan(body.indexOf('mineStats')));
      expect(source, contains('appBar: AppBar('));
      expect(source, contains('title: Text(s.mineTitle)'));
      expect(source, contains('backgroundColor: toolbarBackground'));
      expect(source, isNot(contains('final mineToolbar = Padding(')));
      expect(source, isNot(contains('fixedOverview')));
      expect(source, isNot(contains("ValueKey('mine_fixed_overview_panel')")));
      expect(
        source,
        isNot(contains("ValueKey('mine_desktop_fixed_overview_layout')")),
      );
    });

    test('我的页统计卡片使用稳定布局，避免滚动时重绘闪烁', () {
      final source = File('lib/screens/mine_screen.dart').readAsStringSync();
      final stats = _sourceBlock(
        source,
        'final mineStats = Padding(',
        'final aiAssistant = Padding(',
      );
      final stableGrid = _sourceBlock(
        source,
        'class _MineStatsGrid extends StatelessWidget',
        'class _AiWeeklyReviewCard extends StatefulWidget',
      );

      expect(stats, contains('_MineStatsGrid('));
      expect(stats, isNot(contains('GridView.count(')));
      expect(stableGrid, contains('RepaintBoundary('));
      expect(stableGrid, contains("ValueKey('mine_stats_stable_grid')"));
      expect(stableGrid, contains('SizedBox('));
      expect(stableGrid, contains('height: baseHeight + fontGrowth * 2'));
      expect(stableGrid, contains('Row('));
      expect(stableGrid, isNot(contains('shrinkWrap: true')));
      expect(stableGrid, isNot(contains('NeverScrollableScrollPhysics')));
    });

    test('纪念日和生日列表沿用倒数日式摘要与最近日期提示', () {
      final source = File(
        'lib/screens/anniversary_screen.dart',
      ).readAsStringSync();
      final body = _sourceBlock(
        source,
        'final listTitle = fixedType == AnniversaryType.birthday',
        'class _AnniversarySummaryStat extends StatelessWidget',
      );

      expect(body, contains('fixedType == AnniversaryType.birthday'));
      expect(body, contains('I18n.tr(\'anniversary.birthday\')'));
      expect(body, contains('I18n.tr(\'anniversary.title\')'));
      expect(body, contains('AppSectionHeader('));
      expect(body, contains("I18n.tr('countdown.nearest.prefix')"));
      expect(body, contains("I18n.tr('countdown.nearest.days_prefix')"));
      expect(body, contains("I18n.tr('countdown.summary.total')"));
      expect(body, contains("'anniversary.summary.within_30_days'"));
      expect(body, contains("'anniversary_summary_total'"));
      expect(body, contains("'anniversary_summary_within_30_days'"));
    });
  });
}

String _sourceBlock(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  expect(start, isNonNegative, reason: startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(end, isNonNegative, reason: endMarker);
  return source.substring(start, end);
}
