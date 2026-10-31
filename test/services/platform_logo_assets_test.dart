import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// Canonical brand artwork: a pure red rounded tile carrying the white
/// three-block glyph. It is rendered from `assets/logo/duoyi_app_logo.svg` by
/// `scripts/sync_app_icons.py`.
///
/// The palette and geometry below are the user-confirmed reference values, so
/// recycling the retired calendar illustration or the hourglass logo fails here
/// instead of silently shipping to every platform.
const double _artboard = 88;
const (int, int, int) _background = (246, 247, 249); // #F6F7F9
const (int, int, int) _brandRed = (200, 86, 86); // #C85656
const (int, int, int) _glyphWhite = (255, 255, 255);

const String _canonicalPath = 'assets/logo/duoyi_app_logo_1024.png';
const String _masterSvgPath = 'assets/logo/duoyi_app_logo.svg';
const String _foregroundPath = 'assets/logo/duoyi_app_logo_foreground_1024.png';
const String _referencePath = 'assets/logo/duoyi_logo_reference.png';
const String _iosMarketingPath =
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png';
const String _macMarketingPath =
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png';
const String _androidRes = 'android/app/src/main/res';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'canonical artwork is the red tile with the three-block glyph',
    () async {
      final artwork = await _Artwork.load(_canonicalPath);
      expect(artwork.width, 1024);
      expect(artwork.height, 1024);

      // The rounded corner shows the artboard background; the tile is pure red.
      _expectColor(
        artwork,
        2,
        2,
        _background,
        reason: 'rounded corner background',
      );
      _expectColor(artwork, 44, 1, _brandRed, reason: 'red tile top edge');
      _expectColor(artwork, 1, 44, _brandRed, reason: 'red tile left edge');
      _expectColor(artwork, 84, 44, _brandRed, reason: 'red tile right edge');

      // Three white geometric blocks with red gaps between them.
      _expectColor(artwork, 34, 27, _glyphWhite, reason: 'left bar top');
      _expectColor(artwork, 34, 44, _glyphWhite, reason: 'left white bar');
      _expectColor(artwork, 34, 61, _glyphWhite, reason: 'left bar bottom');
      _expectColor(
        artwork,
        54,
        32,
        _glyphWhite,
        reason: 'top right white block',
      );
      _expectColor(
        artwork,
        54,
        52,
        _glyphWhite,
        reason: 'bottom right white block',
      );
      _expectColor(
        artwork,
        54,
        42,
        _brandRed,
        reason: 'red gap between the two right blocks',
      );
      _expectColor(
        artwork,
        44,
        44,
        _brandRed,
        reason: 'red gap between the left bar and the right blocks',
      );
      _expectColor(
        artwork,
        34,
        25,
        _brandRed,
        reason: 'red area above the bar',
      );
    },
  );

  test('every client renders the same canonical artwork', () async {
    final canonical = File(_canonicalPath).readAsBytesSync();
    expect(File(_iosMarketingPath).readAsBytesSync(), canonical);
    expect(File(_macMarketingPath).readAsBytesSync(), canonical);

    for (final path in <String>[
      'web/icons/Icon-512.png',
      'linux/duoyi.png',
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png',
      '$_androidRes/mipmap-xxxhdpi/ic_launcher.png',
    ]) {
      final artwork = await _Artwork.load(path);
      _expectColor(artwork, 44, 1, _brandRed, reason: '$path red tile');
      _expectColor(
        artwork,
        34,
        44,
        _glyphWhite,
        reason: '$path left white bar',
      );
      _expectColor(
        artwork,
        54,
        32,
        _glyphWhite,
        reason: '$path top right white block',
      );
      _expectColor(
        artwork,
        54,
        52,
        _glyphWhite,
        reason: '$path bottom right white block',
      );
      _expectColor(
        artwork,
        54,
        42,
        _brandRed,
        reason: '$path red gap between the right blocks',
      );
    }
  });

  test('launcher icon configuration points at the canonical artwork', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('image_path: "$_canonicalPath"'));
    expect(pubspec, contains('adaptive_icon_background: "#C85656"'));
    expect(pubspec, contains('adaptive_icon_foreground: "$_foregroundPath"'));
    expect(pubspec, isNot(contains('duoyi_logo_redesign_1024.png')));
    expect(pubspec, isNot(contains('#FFC79A')));

    for (final path in <String>[
      _canonicalPath,
      _foregroundPath,
      _masterSvgPath,
      _referencePath,
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }

    // These source parameters are part of the approved design, so the existing
    // Flutter CI also rejects an unrendered SVG palette/orientation change.
    final master = File(_masterSvgPath).readAsStringSync();
    expect(master, contains('viewBox="0 0 88 88"'));
    expect(master, contains('fill="#C85656"'));
    expect(master, contains('fill="#FFFFFF"'));
    expect(
      master,
      contains('transform="translate(20 68) scale(0.09375 -0.09375)"'),
    );

    final adaptive = File(
      '$_androidRes/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    expect(adaptive, contains('@drawable/ic_launcher_foreground'));
    expect(adaptive, contains('@color/ic_launcher_background'));
    expect(adaptive, contains('android:inset="16%"'));

    final colors = File('$_androidRes/values/colors.xml').readAsStringSync();
    final background = RegExp(
      r'''<color\b[^>]*\bname=["']ic_launcher_background["'][^>]*>\s*([^<]+)\s*</color>''',
    ).firstMatch(colors);
    expect(background?.group(1)?.trim().toUpperCase(), '#C85656');
    expect(colors, isNot(contains('#FFC79A')));
  });

  test('adaptive foreground keeps transparent corners', () async {
    const densities = <String, int>{
      'drawable-mdpi/ic_launcher_foreground.png': 108,
      'drawable-hdpi/ic_launcher_foreground.png': 162,
      'drawable-xhdpi/ic_launcher_foreground.png': 216,
      'drawable-xxhdpi/ic_launcher_foreground.png': 324,
      'drawable-xxxhdpi/ic_launcher_foreground.png': 432,
    };
    for (final entry in densities.entries) {
      final path = '$_androidRes/${entry.key}';
      final artwork = await _Artwork.load(path);
      expect(artwork.width, entry.value, reason: path);
      expect(artwork.height, entry.value, reason: path);
      for (final corner in const <(double, double)>[
        (2.0, 2.0),
        (85.0, 2.0),
        (2.0, 85.0),
        (85.0, 85.0),
      ]) {
        expect(
          artwork.alphaAt(corner.$1, corner.$2),
          0,
          reason:
              '$path corner (${corner.$1}, ${corner.$2}) must be transparent',
        );
      }
      expect(artwork.alphaAt(34, 44), 255, reason: '$path left bar');
      expect(artwork.alphaAt(54, 32), 255, reason: '$path top right block');
      expect(artwork.alphaAt(54, 52), 255, reason: '$path bottom right block');
      expect(
        artwork.alphaAt(54, 42),
        lessThanOrEqualTo(8),
        reason: '$path red gap must stay transparent',
      );
    }

    final canonicalForeground = await _Artwork.load(_foregroundPath);
    expect(canonicalForeground.width, 1024);
    expect(canonicalForeground.height, 1024);
    expect(canonicalForeground.alphaAt(2, 2), 0);
    expect(canonicalForeground.alphaAt(34, 44), 255);
  });

  test('auth page tile shows the shared brand image, not a theme icon', () {
    final frame = File('lib/widgets/auth_page_frame.dart').readAsStringSync();
    expect(frame, contains("'$_canonicalPath'"));
    expect(frame, contains('_brandLogoAsset'));
    expect(frame, contains('Image.asset('));
    expect(frame, contains('ClipRRect('));
    expect(frame, contains('DesignTokens.authLogoSize'));
    expect(frame, contains('excludeFromSemantics: true'));
    // The old tile painted the active theme colour behind a Material icon.
    expect(frame, isNot(contains('Icons.space_dashboard_rounded')));
    expect(frame, isNot(contains('cs.onPrimary')));
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

      final android = <String, int>{
        'mipmap-mdpi/ic_launcher.png': 48,
        'mipmap-hdpi/ic_launcher.png': 72,
        'mipmap-xhdpi/ic_launcher.png': 96,
        'mipmap-xxhdpi/ic_launcher.png': 144,
        'mipmap-xxxhdpi/ic_launcher.png': 192,
      };
      for (final entry in android.entries) {
        expect(_pngSize('$_androidRes/${entry.key}'), (
          entry.value,
          entry.value,
        ), reason: entry.key);
      }

      expect(_pngSize('web/icons/Icon-192.png'), (192, 192));
      expect(_pngSize('web/icons/Icon-maskable-192.png'), (192, 192));
      expect(_pngSize('web/icons/Icon-512.png'), (512, 512));
      expect(_pngSize('web/icons/Icon-maskable-512.png'), (512, 512));
      expect(_pngSize('web/favicon.png'), (16, 16));
      expect(_pngSize('linux/duoyi.png'), (512, 512));
      expect(
        File('web/icons/Icon-512.png').readAsBytesSync(),
        File('linux/duoyi.png').readAsBytesSync(),
      );
    },
  );
}

/// Decoded artwork addressed in artboard units (0..88) so one set of sample
/// points works for every rendered icon size.
class _Artwork {
  _Artwork(this._pixels, this.width, this.height);

  final ByteData _pixels;
  final int width;
  final int height;

  static Future<_Artwork> load(String path) async {
    final image = await _decode(path);
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final artwork = _Artwork(pixels!, image.width, image.height);
    image.dispose();
    return artwork;
  }

  int _channelAt(double artX, double artY, int channel) {
    final x = (artX / _artboard * width).floor().clamp(0, width - 1).toInt();
    final y = (artY / _artboard * height).floor().clamp(0, height - 1).toInt();
    return _pixels.getUint8((y * width + x) * 4 + channel);
  }

  (int, int, int) rgbAt(double artX, double artY) => (
    _channelAt(artX, artY, 0),
    _channelAt(artX, artY, 1),
    _channelAt(artX, artY, 2),
  );

  int alphaAt(double artX, double artY) => _channelAt(artX, artY, 3);
}

Future<ui.Image> _decode(String path) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromList(File(path).readAsBytesSync(), completer.complete);
  return completer.future;
}

/// Colours are sampled deep inside flat regions, so a two-step tolerance keeps
/// the check robust against colour-management rounding without weakening it.
void _expectColor(
  _Artwork artwork,
  double artX,
  double artY,
  (int, int, int) expected, {
  required String reason,
}) {
  final actual = artwork.rgbAt(artX, artY);
  final deltas = <int>[
    (actual.$1 - expected.$1).abs(),
    (actual.$2 - expected.$2).abs(),
    (actual.$3 - expected.$3).abs(),
  ];
  expect(
    deltas.every((delta) => delta <= 2),
    isTrue,
    reason:
        '$reason at artboard ($artX, $artY): '
        'expected $expected, found $actual',
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
