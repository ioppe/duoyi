import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('应用 UI 使用共享粗体令牌，禁止局部恢复常规字重', () {
    final regularWeight = RegExp(r'\bFontWeight\.(normal|w[1-6]00)\b');
    final rawWeight = RegExp(r'\bFontWeight\.(bold|w[1-9]00)\b');
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // PDF exports use the pdf package's own weight enum.
        final line = lines[i].replaceAll('pw.FontWeight.normal', '');
        if (regularWeight.hasMatch(line) ||
            line.contains('DesignTokens.fontWeightRegular') ||
            (!file.path.endsWith('core/design_tokens.dart') &&
                rawWeight.hasMatch(line))) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '全部应用文字使用圆体粗体；显式字重统一使用 DesignTokens.fontWeightStrong。',
    );
  });

  test('圆体字体随应用打包，局部页面不绕回系统字体', () {
    final tokens = File('lib/core/design_tokens.dart').readAsStringSync();
    final brand = File('lib/core/app_brand.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(tokens, contains("fontFamilyRounded = 'ResourceHanRounded'"));
    expect(tokens, contains('fontWeightStrong = FontWeight.w700'));
    expect(brand, contains('_cnFontFamily = DesignTokens.fontFamilyRounded'));
    expect(pubspec, contains('family: ResourceHanRounded'));
    expect(pubspec, contains('assets/fonts/ResourceHanRoundedCN-Bold.ttf'));
    expect(pubspec, contains('weight: 700'));
    expect(
      File('assets/fonts/ResourceHanRoundedCN-Bold.ttf').existsSync(),
      isTrue,
    );
    expect(
      File('assets/fonts/ResourceHanRounded-OFL.txt').readAsStringSync(),
      contains('SIL OPEN FONT LICENSE Version 1.1'),
    );

    final rawFamily = RegExp(r'''fontFamily:\s*['"]''');
    for (final directory in ['lib/screens', 'lib/widgets']) {
      for (final file
          in Directory(directory)
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))) {
        expect(
          file.readAsStringSync(),
          isNot(matches(rawFamily)),
          reason: '${file.path} 应继承圆体主题或使用 DesignTokens.fontFamilyRounded。',
        );
      }
    }
  });
}
