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
    // macOS drops the opaque #F6F7F9 artboard for a transparent RGBA tile, so
    // it must no longer be a byte copy of the canonical PNG; the macOS test
    // below pins its palette, geometry and transparent corners instead.
    expect(File(_macMarketingPath).readAsBytesSync(), isNot(canonical));

    for (final path in <String>[
      'web/icons/Icon-512.png',
      'linux/duoyi.png',
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
      expect(_pngSize('web/favicon.png'), (32, 32));
      expect(_pngSize('linux/duoyi.png'), (512, 512));
      expect(
        File('web/icons/Icon-512.png').readAsBytesSync(),
        File('linux/duoyi.png').readAsBytesSync(),
      );
    },
  );

  // The Dock painted a light square behind the logo because every macOS icon
  // was the opaque #F6F7F9 artboard render. Each declared macOS size must now
  // be the RGBA transparent tile the favicon already used, with the approved
  // red/white palette and the tile geometry unchanged.
  test(
    'macOS icons are transparent rounded tiles on every declared size',
    () async {
      const macDir = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';
      const mac = <String, int>{
        'app_icon_16.png': 16,
        'app_icon_32.png': 32,
        'app_icon_64.png': 64,
        'app_icon_128.png': 128,
        'app_icon_256.png': 256,
        'app_icon_512.png': 512,
        'app_icon_1024.png': 1024,
      };
      // The 16 px tile still gets sub-pixel corner coverage from the rounded
      // antialias (alpha 2 of 255), everything else is fully transparent.
      const transparentCornerMaxAlpha = 8;

      for (final entry in mac.entries) {
        final path = '$macDir/${entry.key}';
        final tile = await _Artwork.load(path);
        expect(tile.width, entry.value, reason: path);
        expect(tile.height, entry.value, reason: path);

        for (final corner in const <(double, double)>[
          (0, 0),
          (88, 0),
          (0, 88),
          (88, 88),
        ]) {
          expect(
            tile.alphaAt(corner.$1, corner.$2),
            lessThanOrEqualTo(transparentCornerMaxAlpha),
            reason:
                '$path corner (${corner.$1}, ${corner.$2}) must be '
                'transparent, not the light #F6F7F9 artboard',
          );
        }

        (int, int, int, int)? lightMatte;
        (int, int, int, int)? offPaletteEdge;
        var redPixels = 0;
        var whitePixels = 0;
        for (final pixel in tile.pixels) {
          if ((pixel.$1, pixel.$2, pixel.$3) == _background) {
            lightMatte ??= pixel;
          }
          final opaque = (pixel.$1, pixel.$2, pixel.$3);
          if (pixel.$4 == 255) {
            if (_isNear(opaque, _brandRed)) redPixels++;
            if (_isNear(opaque, _glyphWhite)) whitePixels++;
          } else if (pixel.$4 > 0) {
            // A baked light matte leaks blue > green into the antialiased tile
            // edge; a red/white blend keeps those two channels equal.
            final offBlend =
                (pixel.$2 - pixel.$3).abs() > 1 || pixel.$1 + 1 < pixel.$2;
            if (offBlend) offPaletteEdge ??= pixel;
          }
        }
        expect(
          lightMatte,
          isNull,
          reason: '$path bakes the #F6F7F9 artboard back in: $lightMatte',
        );
        expect(
          offPaletteEdge,
          isNull,
          reason:
              '$path antialiased edge pixel $offPaletteEdge is not a '
              'brand-red/white blend',
        );
        expect(redPixels, greaterThan(0), reason: '$path keeps the red tile');
        expect(
          whitePixels,
          greaterThan(0),
          reason: '$path keeps the white glyph',
        );
      }

      // From 128 px up these samples land on flat pixels, so the approved
      // palette and geometry are pinned exactly as for the canonical artwork.
      final highResolution = mac.entries.where((entry) => entry.value >= 128);
      for (final entry in highResolution) {
        final path = '$macDir/${entry.key}';
        final tile = await _Artwork.load(path);
        _expectColor(tile, 44, 1, _brandRed, reason: '$path red tile top edge');
        _expectColor(
          tile,
          1,
          44,
          _brandRed,
          reason: '$path red tile left edge',
        );
        _expectColor(tile, 34, 44, _glyphWhite, reason: '$path left white bar');
        _expectColor(
          tile,
          54,
          32,
          _glyphWhite,
          reason: '$path top right white block',
        );
        _expectColor(
          tile,
          54,
          52,
          _glyphWhite,
          reason: '$path bottom right white block',
        );
        _expectColor(
          tile,
          54,
          42,
          _brandRed,
          reason: '$path red gap between the right blocks',
        );
      }
    },
  );

  test(
    'web favicon is a transparent rounded tile with a PNG fallback',
    () async {
      final index = File('web/index.html').readAsStringSync();
      final pngLink = RegExp(
        r'<link rel="icon" type="image/png" sizes="32x32" '
        r'href="favicon\.png\?v=transparent-v1"',
      ).firstMatch(index);
      expect(pngLink, isNotNull, reason: 'PNG fallback with a fresh cache key');
      final svgLink = RegExp(
        r'<link rel="icon" type="image/svg\+xml" sizes="any" '
        r'href="favicon\.svg"',
      ).firstMatch(index);
      expect(svgLink, isNotNull, reason: 'vector favicon link');
      expect(
        pngLink!.start,
        lessThan(svgLink!.start),
        reason: 'the PNG fallback must be declared before the SVG',
      );

      final faviconSvg = File('web/favicon.svg').readAsStringSync();
      expect(faviconSvg, contains('xmlns="http://www.w3.org/2000/svg"'));
      expect(faviconSvg, contains('viewBox="0 0 88 88"'));
      expect(
        faviconSvg,
        isNot(contains('<image')),
        reason: 'the favicon must stay vector, never embed a bitmap',
      );

      // Same geometry and palette as the canonical master: the red rounded
      // tile and the white glyph path are copied from it. Only the #F6F7F9
      // artboard is dropped, so the corners stay transparent on dark tabs.
      final master = File(_masterSvgPath).readAsStringSync();
      final masterGlyph = RegExp(
        r'<path fill="#FFFFFF"[^>]*d="([^"]+)"',
      ).firstMatch(master);
      expect(masterGlyph, isNotNull, reason: 'canonical master glyph path');
      expect(faviconSvg, contains('d="${masterGlyph!.group(1)}"'));
      expect(
        faviconSvg,
        contains('transform="translate(20 68) scale(0.09375 -0.09375)"'),
      );
      final tileRects = RegExp(
        r'<rect\b[^>]*>',
      ).allMatches(faviconSvg).map((match) => match.group(0)!).toList();
      expect(
        tileRects,
        hasLength(1),
        reason: 'only the rounded tile rect may remain',
      );
      expect(tileRects.single, contains('rx="32"'));
      expect(tileRects.single, contains('fill="#C85656"'));
      expect(faviconSvg, contains('fill="#FFFFFF"'));
      expect(
        faviconSvg,
        isNot(contains('#F6F7F9')),
        reason: 'an opaque artboard would repaint the light square',
      );

      final favicon = await _Artwork.load('web/favicon.png');
      expect(favicon.width, 32);
      expect(favicon.height, 32);
      for (final corner in const <(double, double)>[
        (1, 1),
        (86, 1),
        (1, 86),
        (86, 86),
      ]) {
        expect(
          favicon.alphaAt(corner.$1, corner.$2),
          0,
          reason:
              'corner (${corner.$1}, ${corner.$2}) must be transparent, '
              'not a light artboard square',
        );
      }
      _expectColor(favicon, 1, 44, _brandRed, reason: 'opaque red tile edge');
      _expectColor(favicon, 34, 44, _glyphWhite, reason: 'left white bar');
      _expectColor(favicon, 54, 48, _glyphWhite, reason: 'top right block');
      _expectColor(favicon, 54, 28, _glyphWhite, reason: 'bottom right block');
      _expectColor(
        favicon,
        54,
        42,
        _brandRed,
        reason: 'red gap between the right blocks',
      );
      expect(favicon.alphaAt(34, 44), 255, reason: 'glyph stays opaque');
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

  /// Every pixel as `(r, g, b, a)`, in row-major order.
  Iterable<(int, int, int, int)> get pixels sync* {
    for (var offset = 0; offset < _pixels.lengthInBytes; offset += 4) {
      yield (
        _pixels.getUint8(offset),
        _pixels.getUint8(offset + 1),
        _pixels.getUint8(offset + 2),
        _pixels.getUint8(offset + 3),
      );
    }
  }
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

/// Same two-step tolerance as [_expectColor], for whole-pixel comparisons.
bool _isNear((int, int, int) actual, (int, int, int) expected) =>
    (actual.$1 - expected.$1).abs() <= 2 &&
    (actual.$2 - expected.$2).abs() <= 2 &&
    (actual.$3 - expected.$3).abs() <= 2;

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
