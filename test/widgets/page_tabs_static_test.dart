import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('页面子页切换统一经过共享页签，禁止局部样式分叉', () {
    final screens = Directory(
      'lib/screens',
    ).listSync().whereType<File>().where((file) => file.path.endsWith('.dart'));
    final offenders = [
      for (final file in screens)
        if (RegExp(r'\bTabBar\(').hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(offenders, isEmpty, reason: '内容子页使用 AppPageTabs，共享文字短线、字重和触摸范围。');
    for (final file in [
      'today',
      'habit',
      'anniversary',
      'pomodoro',
      'integrations',
      'calendar',
      'admin',
    ]) {
      expect(
        File('lib/screens/${file}_screen.dart').readAsStringSync(),
        contains('AppPageTabs('),
      );
    }
    for (final file in ['todo', 'note', 'time_audit']) {
      expect(
        File('lib/screens/${file}_screen.dart').readAsStringSync(),
        contains('AppPageSwitcher<'),
      );
    }
    final theme = File('lib/core/app_brand.dart').readAsStringSync();
    expect(theme, contains('tabBarTheme: appPageTabTheme(theme)'));
    final tabs = File('lib/widgets/app_page_tabs.dart').readAsStringSync();
    expect(tabs, contains('isScrollable: true'));
    expect(tabs, contains('tabAlignment: TabAlignment.start'));
  });
}
