import 'package:duoyi/core/app_text_scale.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double fontSize) => fontSize + 8 * fontSize / (fontSize + 8);
  @override
  double get textScaleFactor => scale(14) / 14;
}

void main() {
  const android = TargetPlatform.android;
  const androidProfile = <double>[.55, .70, .85, 1.0, 1.15, 1.30, 1.45];
  const sharedProfile = <double>[.85, 1.0, 1.15, 1.30, 1.45, 1.60, 1.75, 1.90];

  List<double> optionsFor({TargetPlatform? platform, bool isWeb = false}) =>
      AppTextScale.optionsFor(platform: platform, isWeb: isWeb);

  test('原生 Android 七档 55–145，每侧三档且标准 100% 为第四档', () {
    final options = optionsFor(platform: android);
    expect(options, androidProfile);
    expect(options.length, 7);
    expect(AppTextScale.androidOptions, androidProfile);
    expect(options.indexOf(AppTextScale.standard), 3);
    expect(AppTextScale.standardIndex, options.indexOf(AppTextScale.standard));
    expect(AppTextScale.defaultScale, 1.0);
    expect(AppTextScale.small, .85);
    expect(AppTextScale.large, 1.15);
    for (final value in options) {
      expect(AppTextScale.normalize(value, platform: android), value);
      expect(
        AppTextScale.percentOf(value, platform: android),
        (value * 100).round(),
      );
      expect(
        AppTextScale.indexOf(value, platform: android),
        options.indexOf(value),
      );
    }
    // 标准档左右各三档，步长保持 15%。
    for (var step = 1; step <= 3; step++) {
      expect(options[3 - step], closeTo(1 - step * .15, 1e-9));
      expect(options[3 + step], closeTo(1 + step * .15, 1e-9));
    }
  });

  test('非 Android 各平台与移动 Web 都保持八档 85–190', () {
    expect(AppTextScale.sharedOptions, sharedProfile);
    final nonAndroid = TargetPlatform.values
        .where((platform) => platform != android)
        .toList();
    expect(nonAndroid, isNotEmpty);
    for (final platform in nonAndroid) {
      final options = optionsFor(platform: platform);
      expect(options, sharedProfile, reason: '$platform 必须保持八档');
      expect(options.indexOf(AppTextScale.standard), 1);
    }
    // 覆盖需求点名的平台集合。
    expect(
      nonAndroid,
      containsAll(<TargetPlatform>[
        TargetPlatform.iOS,
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ]),
    );
    // 移动 Web：目标平台是 Android 也不缩小档位范围。
    expect(optionsFor(platform: android, isWeb: true), sharedProfile);
    // 省略参数时与真实平台一致（测试环境默认 Android）。
    expect(
      AppTextScale.options,
      optionsFor(platform: defaultTargetPlatform, isWeb: kIsWeb),
    );
  });

  test('异常值安全回退，有限正数就近吸附，距离相同时取较小档位', () {
    for (final platform in <TargetPlatform>[android, TargetPlatform.iOS]) {
      final options = optionsFor(platform: platform);
      for (final value in <double?>[
        null,
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -1,
        0,
      ]) {
        expect(
          AppTextScale.normalize(value, platform: platform),
          AppTextScale.defaultScale,
          reason: '$platform $value',
        );
        expect(
          AppTextScale.indexOf(double.nan, platform: platform),
          options.indexOf(AppTextScale.standard),
        );
      }
      for (final value in options) {
        expect(AppTextScale.normalize(value, platform: platform), value);
      }
      expect(AppTextScale.normalize(1.18, platform: platform), 1.15);
      expect(
        AppTextScale.normalize(options.first / 2, platform: platform),
        options.first,
      );
      expect(
        AppTextScale.normalize(options.last + 5, platform: platform),
        options.last,
      );
      expect(
        AppTextScale.normalize(double.maxFinite, platform: platform),
        options.last,
      );
      // 两个档位正中间时吸附到较小档位（历史行为不变）。
      expect(
        AppTextScale.normalize(
          (options.first + options[1]) / 2,
          platform: platform,
        ),
        options.first,
      );
    }
  });

  test('Android 旧版越界大值按最近有效边界读取，其它平台原样保留', () {
    for (final legacy in <double>[1.60, 1.75, 1.90]) {
      expect(AppTextScale.normalize(legacy, platform: android), 1.45);
      expect(AppTextScale.indexOf(legacy, platform: android), 6);
      expect(AppTextScale.percentOf(legacy, platform: android), 145);
    }
    for (final legacy in <double>[1.60, 1.75, 1.90]) {
      expect(
        AppTextScale.normalize(legacy, platform: TargetPlatform.iOS),
        legacy,
      );
      expect(
        AppTextScale.percentOf(legacy, platform: TargetPlatform.iOS),
        (legacy * 100).round(),
      );
    }
    // 下边界同样是最近有效档位。
    expect(AppTextScale.normalize(.4, platform: android), .55);
    expect(AppTextScale.normalize(.4, platform: TargetPlatform.iOS), .85);
    expect(AppTextScale.normalize(5, platform: android), 1.45);
    expect(AppTextScale.normalize(5, platform: TargetPlatform.iOS), 1.9);
  });

  test('标准字号原样保留系统 scaler', () {
    const system = _NonlinearScaler();
    for (final platform in <TargetPlatform>[android, TargetPlatform.iOS]) {
      expect(
        identical(
          AppTextScale.resolve(system: system, appScale: 1, platform: platform),
          system,
        ),
        isTrue,
      );
      // 100% 在两种档位表里都等于标准档。
      expect(
        identical(
          AppTextScale.resolve(
            system: system,
            appScale: AppTextScale.defaultScale,
            platform: platform,
          ),
          system,
        ),
        isTrue,
      );
    }
  });

  test('七档与八档都保留系统线性和非线性缩放，不转成单个线性比例', () {
    for (final platform in <TargetPlatform>[android, TargetPlatform.iOS]) {
      for (final system in <TextScaler>[
        TextScaler.noScaling,
        const TextScaler.linear(2),
        const _NonlinearScaler(),
      ]) {
        for (final value in optionsFor(platform: platform)) {
          final resolved = AppTextScale.resolve(
            system: system,
            appScale: value,
            platform: platform,
          );
          for (final fontSize in <double>[12, 16, 20, 32]) {
            expect(
              resolved.scale(fontSize),
              closeTo(system.scale(fontSize * value), 1e-9),
              reason: '$platform x $value x $fontSize',
            );
          }
        }
      }
    }
  });

  test('字号预览剥离已保存应用档位后只叠加一次草稿', () {
    const system = _NonlinearScaler();
    // Android 保存的 175% 读出来是有效的 145%，预览只叠一次草稿。
    final saved = AppTextScale.resolve(
      system: system,
      appScale: 1.75,
      platform: android,
    );
    expect(saved.scale(16), closeTo(system.scale(16 * 1.45), 1e-9));
    expect(identical(AppTextScale.systemScalerOf(saved), system), isTrue);
    final preview = AppTextScale.resolve(
      system: AppTextScale.systemScalerOf(saved),
      appScale: 1.30,
      platform: android,
    );
    expect(preview.scale(16), closeTo(system.scale(16 * 1.30), 1e-9));
    final duplicate = AppTextScale.resolve(
      system: saved,
      appScale: 1.30,
      platform: android,
    );
    expect(identical(AppTextScale.systemScalerOf(duplicate), system), isTrue);
  });

  test('相同字号配置的相等性和 hash 保持一致', () {
    const system = TextScaler.linear(1.3);
    final first = AppTextScale.resolve(
      system: system,
      appScale: .85,
      platform: android,
    );
    final same = AppTextScale.resolve(
      system: system,
      appScale: .86,
      platform: android,
    );
    final other = AppTextScale.resolve(
      system: system,
      appScale: 1.75,
      platform: android,
    );
    expect(first, same);
    expect(first.hashCode, same.hashCode);
    expect(first, isNot(other));
  });
}
