import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

/// 允许的字重入口：正文 400 / 标签 500 / 标题 600。
const _allowedWeights = [
  'DesignTokens.fontWeightRegular',
  'DesignTokens.fontWeightMedium',
  'DesignTokens.fontWeightStrong',
];

Map<String, int> _tableOffsets(Uint8List bytes) {
  final count = (bytes[4] << 8) | bytes[5];
  final result = <String, int>{};
  for (var i = 0; i < count; i++) {
    final record = 12 + i * 16;
    final tag = String.fromCharCodes(bytes.sublist(record, record + 4));
    final offset =
        (bytes[record + 8] << 24) |
        (bytes[record + 9] << 16) |
        (bytes[record + 10] << 8) |
        bytes[record + 11];
    result[tag] = offset;
  }
  return result;
}

int _uint16(Uint8List bytes, int offset) =>
    (bytes[offset] << 8) | bytes[offset + 1];

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
    final legacy = RegExp(r'fontFamilyRounded|NotoSansSC');
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
          'ResourceHanRounded 只应出现在共享字体令牌中。',
    );
  });

  test('共享令牌与主题声明 Resource Han Rounded 与三档字重', () {
    final tokens = File('lib/core/design_tokens.dart').readAsStringSync();
    final brand = File('lib/core/app_brand.dart').readAsStringSync();

    expect(tokens, contains("fontFamily = 'ResourceHanRounded'"));
    expect(tokens, contains('fontWeightRegular = FontWeight.w400'));
    expect(tokens, contains('fontWeightMedium = FontWeight.w500'));
    expect(tokens, contains('fontWeightStrong = FontWeight.w600'));

    // 所有主题共用同一个家族常量，不允许各自定义字体。
    expect(brand, contains('_cnFontFamily = DesignTokens.fontFamily'));
    expect(
      RegExp(r'fontFamily:\s*_cnFontFamily').allMatches(brand).length,
      greaterThanOrEqualTo(1),
    );
    for (final weight in _allowedWeights) {
      expect(brand, contains(weight), reason: '共享控件应使用 $weight');
    }
  });

  test('打包的是 Resource Han Rounded CN Bold，附 OFL 许可', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: ResourceHanRounded'));
    expect(pubspec, contains('assets/fonts/ResourceHanRoundedCN-Bold.ttf'));
    for (final weight in [400, 500, 600, 700]) {
      expect(
        pubspec,
        contains('weight: $weight'),
        reason: '圆体资源需要为 $weight 注册字重',
      );
    }

    final font = File('assets/fonts/ResourceHanRoundedCN-Bold.ttf');
    expect(font.existsSync(), isTrue);
    final bytes = font.readAsBytesSync();
    expect(bytes.length, greaterThan(1000000));
    final tables = _tableOffsets(Uint8List.fromList(bytes));
    expect(tables, contains('OS/2'));
    expect(tables, contains('cmap'));
    expect(tables, contains('glyf'));
    expect(
      _uint16(Uint8List.fromList(bytes), tables['OS/2']! + 4),
      700,
      reason: 'Resource Han Rounded CN 必须是粗体字库',
    );

    final license = File(
      'assets/fonts/ResourceHanRounded-OFL.txt',
    ).readAsStringSync();
    expect(license, contains('SIL OPEN FONT LICENSE Version 1.1'));
  });
}
