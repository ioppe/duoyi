import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const canonicalPath = 'assets/logo/duoyi_logo_redesign_1024.png';
  const iosMarketingPath =
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png';
  const macMarketingPath =
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png';

  test('platform application icons use the Android canonical logo', () {
    final canonical = File(canonicalPath).readAsBytesSync();

    expect(File(iosMarketingPath).readAsBytesSync(), canonical);
    expect(File(macMarketingPath).readAsBytesSync(), canonical);

    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec,
      contains('image_path: "assets/logo/duoyi_logo_redesign_1024.png"'),
    );
    expect(
      pubspec,
      contains(
        'adaptive_icon_foreground: "assets/logo/duoyi_logo_redesign_1024.png"',
      ),
    );
    expect(
      File(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      ).readAsStringSync(),
      contains('@drawable/ic_launcher_foreground'),
    );

    expect(_pngSize('web/icons/Icon-512.png'), (512, 512));
    expect(_pngSize('linux/duoyi.png'), (512, 512));
    expect(
      File('web/icons/Icon-512.png').readAsBytesSync(),
      File('linux/duoyi.png').readAsBytesSync(),
    );
  });

  test(
    'platform icon manifests keep every declared PNG at its target size',
    () {
      final ios = <String, (int, int)>{
        'Icon-App-20x20@1x.png': (20, 20),
        'Icon-App-20x20@2x.png': (40, 40),
        'Icon-App-20x20@3x.png': (60, 60),
        'Icon-App-29x29@1x.png': (29, 29),
        'Icon-App-29x29@2x.png': (58, 58),
        'Icon-App-29x29@3x.png': (87, 87),
        'Icon-App-40x40@1x.png': (40, 40),
        'Icon-App-40x40@2x.png': (80, 80),
        'Icon-App-40x40@3x.png': (120, 120),
        'Icon-App-50x50@1x.png': (50, 50),
        'Icon-App-50x50@2x.png': (100, 100),
        'Icon-App-57x57@1x.png': (57, 57),
        'Icon-App-57x57@2x.png': (114, 114),
        'Icon-App-60x60@2x.png': (120, 120),
        'Icon-App-60x60@3x.png': (180, 180),
        'Icon-App-72x72@1x.png': (72, 72),
        'Icon-App-72x72@2x.png': (144, 144),
        'Icon-App-76x76@1x.png': (76, 76),
        'Icon-App-76x76@2x.png': (152, 152),
        'Icon-App-83.5x83.5@2x.png': (167, 167),
        'Icon-App-1024x1024@1x.png': (1024, 1024),
      };
      for (final entry in ios.entries) {
        expect(
          _pngSize(
            'ios/Runner/Assets.xcassets/AppIcon.appiconset/${entry.key}',
          ),
          entry.value,
          reason: entry.key,
        );
      }

      final mac = <String, int>{
        'app_icon_16.png': 16,
        'app_icon_32.png': 32,
        'app_icon_64.png': 64,
        'app_icon_128.png': 128,
        'app_icon_256.png': 256,
        'app_icon_512.png': 512,
        'app_icon_1024.png': 1024,
      };
      for (final entry in mac.entries) {
        expect(
          _pngSize(
            'macos/Runner/Assets.xcassets/AppIcon.appiconset/${entry.key}',
          ),
          (entry.value, entry.value),
          reason: entry.key,
        );
      }
    },
  );
}

(int, int) _pngSize(String path) {
  final bytes = File(path).readAsBytesSync();
  expect(bytes.length, greaterThanOrEqualTo(24), reason: path);
  expect(bytes.sublist(0, 8), <int>[
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
  ], reason: path);
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  return (data.getUint32(16), data.getUint32(20));
}
