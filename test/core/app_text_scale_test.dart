import 'package:duoyi/core/app_text_scale.dart';
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
  test('八档字号保留旧三档，标准为第二档', () {
    expect(AppTextScale.options, [.85, 1.0, 1.15, 1.3, 1.45, 1.6, 1.75, 1.9]);
    expect(AppTextScale.standardIndex, 1);
    expect(AppTextScale.defaultScale, AppTextScale.standard);
    for (final value in AppTextScale.options) {
      expect(AppTextScale.normalize(value), value);
    }
    expect(AppTextScale.percentOf(1.9), 190);
    expect(AppTextScale.normalize(1.18), 1.15);
    expect(AppTextScale.normalize(.9), .85);
  });

  test('异常值安全回退，有限正数归一到最近档位', () {
    for (final value in [null, double.nan, double.infinity, -1.0, 0.0]) {
      expect(AppTextScale.normalize(value), AppTextScale.standard);
    }
    expect(AppTextScale.normalize(.4), .85);
    expect(AppTextScale.normalize(5), 1.9);
    expect(AppTextScale.normalize(1.6), 1.6);
  });

  test('标准字号原样保留系统 scaler', () {
    const system = _NonlinearScaler();
    expect(
      identical(AppTextScale.resolve(system: system, appScale: 1), system),
      isTrue,
    );
  });

  test('八档保留系统线性和非线性缩放，不转成单个线性比例', () {
    for (final system in [
      TextScaler.noScaling,
      const TextScaler.linear(2),
      const _NonlinearScaler(),
    ]) {
      for (final value in AppTextScale.options) {
        final resolved = AppTextScale.resolve(system: system, appScale: value);
        for (final fontSize in [12.0, 16.0, 20.0, 32.0]) {
          expect(
            resolved.scale(fontSize),
            closeTo(system.scale(fontSize * value), 1e-9),
          );
        }
      }
    }
  });

  test('字号预览剥离已保存应用档位后只叠加一次草稿', () {
    const system = _NonlinearScaler();
    final saved = AppTextScale.resolve(system: system, appScale: 1.75);
    expect(identical(AppTextScale.systemScalerOf(saved), system), isTrue);
    final preview = AppTextScale.resolve(
      system: AppTextScale.systemScalerOf(saved),
      appScale: 1.3,
    );
    expect(preview.scale(16), closeTo(system.scale(16 * 1.3), 1e-9));
    final duplicate = AppTextScale.resolve(system: saved, appScale: 1.3);
    expect(identical(AppTextScale.systemScalerOf(duplicate), system), isTrue);
  });

  test('相同字号配置的相等性和 hash 保持一致', () {
    const system = TextScaler.linear(1.3);
    final first = AppTextScale.resolve(system: system, appScale: .85);
    final same = AppTextScale.resolve(system: system, appScale: .86);
    final other = AppTextScale.resolve(system: system, appScale: 1.9);
    expect(first, same);
    expect(first.hashCode, same.hashCode);
    expect(first, isNot(other));
  });
}
