import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// 允许的字重入口：正文 400 / 标签 500 / 标题 600。
const _allowedWeights = [
  'DesignTokens.fontWeightRegular',
  'DesignTokens.fontWeightMedium',
  'DesignTokens.fontWeightStrong',
];

void main() {
  test('应用 UI 只使用共享字重令牌，禁止局部硬编码字重', () {
    final rawWeight = RegExp(r'\bFontWeight\.(normal|bold|w[1-9]00)\b');
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      // design_tokens.dart 是唯一允许声明字重常量的位置。
      if (file.path.endsWith('core/design_tokens.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // PDF 导出使用 pdf 包自己的字重枚举，与应用界面字体无关。
        final line = lines[i].replaceAll(RegExp(r'pw\.FontWeight\.\w+'), '');
        if (rawWeight.hasMatch(line)) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    final allowed = _allowedWeights.join(' / ');

    expect(
      offenders,
      isEmpty,
      reason:
          '应用文字统一继承主题字体；显式字重只允许 $allowed，'
          '不要在页面或控件里写 FontWeight.w400/w500/w600 等字面量。',
    );
  });

  test('字体家族只能来自共享令牌或主题继承，禁止局部硬编码', () {
    final rawFamily = RegExp(r'''fontFamily:\s*['"]''');
    final legacy = RegExp(r'fontFamilyRounded|ResourceHanRounded');
    final offenders = <String>[];

    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      if (rawFamily.hasMatch(source) || legacy.hasMatch(source)) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '字体家族只能通过 DesignTokens.fontFamily 或主题继承获得；'
          '旧的 ResourceHanRounded / fontFamilyRounded 入口已废弃。',
    );
  });

  test('共享令牌与主题声明新的中文无衬线字体与三档字重', () {
    final tokens = File('lib/core/design_tokens.dart').readAsStringSync();
    final brand = File('lib/core/app_brand.dart').readAsStringSync();

    expect(tokens, contains("fontFamily = 'NotoSansSC'"));
    expect(tokens, contains('fontWeightRegular = FontWeight.w400'));
    expect(tokens, contains('fontWeightMedium = FontWeight.w500'));
    expect(tokens, contains('fontWeightStrong = FontWeight.w600'));

    // 九套主题共用同一个家族常量，不允许各自定义字体。
    expect(brand, contains('_cnFontFamily = DesignTokens.fontFamily'));
    expect(
      RegExp(r'fontFamily:\s*_cnFontFamily').allMatches(brand).length,
      greaterThanOrEqualTo(1),
    );
    for (final weight in _allowedWeights) {
      expect(brand, contains(weight), reason: '共享控件应使用 $weight');
    }
  });

  test('打包的是官方 Noto Sans SC 变量字体，附 OFL 许可', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: NotoSansSC'));
    expect(pubspec, contains('assets/fonts/NotoSansSC-Variable.ttf'));
    for (final weight in [400, 500, 600, 700]) {
      expect(
        pubspec,
        contains('weight: $weight'),
        reason: '变量字体需要为 $weight 注册字重',
      );
    }
    expect(pubspec, contains('assets/fonts/'));

    final font = File('assets/fonts/NotoSansSC-Variable.ttf');
    expect(font.existsSync(), isTrue);
    final bytes = font.readAsBytesSync();
    expect(bytes.length, greaterThan(1000000));

    // 表目录里必须同时有 fvar（变量轴）与轮廓表，确认是变量字体。
    final tableCount = bytes[4] << 8 | bytes[5];
    final tables = <String>{};
    for (var i = 0; i < tableCount; i++) {
      final offset = 12 + 16 * i;
      tables.add(ascii.decode(bytes.sublist(offset, offset + 4)));
    }
    expect(tables, contains('fvar'), reason: '必须打包变量字体（wght 轴）');
    expect(tables.contains('glyf') || tables.contains('CFF2'), isTrue);

    final license = File('assets/fonts/NotoSansSC-OFL.txt').readAsStringSync();
    expect(license, contains('SIL OPEN FONT LICENSE Version 1.1'));
  });
}
