import 'dart:io';

import 'package:test/test.dart';

/// 心情统计弹窗（diary_screen.dart `_showMoodStats`）暗色适配守卫：
/// 进度条轨道与计数文本不得再使用固定 Colors.grey，需跟随主题 ColorScheme。
void main() {
  test('心情统计弹窗取色守卫：轨道/计数文字随亮暗主题取色', () {
    final source = File('lib/screens/diary_screen.dart').readAsStringSync();

    final start = source.indexOf('void _showMoodStats(');
    final end = source.indexOf('Future<void> _runDeepDiaryReview(');
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final stats = source.substring(start, end);

    expect(
      stats,
      isNot(contains('Colors.grey')),
      reason: '心情统计弹窗内不应残留固定 Colors.grey 取色',
    );
    // 允许格式化换行：`cs.surfaceContainerHighest` 后可能换行再接 `.withValues`。
    expect(
      stats.replaceAll(RegExp(r'\s+'), ' '),
      contains('surfaceContainerHighest .withValues'),
      reason: '进度条轨道应使用主题容器色',
    );
    expect(stats, contains('Brightness.dark'), reason: '轨道透明度需按亮暗分支');
    expect(
      stats,
      contains('cs.onSurface.withValues(alpha: 0.55)'),
      reason: '计数文字应使用主题前景色',
    );
  });
}
