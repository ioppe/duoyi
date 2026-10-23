import 'package:duoyi/core/app_text_scale.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('字号档位为 0.85 / 1.0 / 1.15，默认标准档', () {
    expect(AppTextScale.small, 0.85);
    expect(AppTextScale.standard, 1.0);
    expect(AppTextScale.large, 1.15);
    expect(AppTextScale.defaultScale, AppTextScale.standard);
    expect(AppTextScale.options, <double>[
      AppTextScale.small,
      AppTextScale.standard,
      AppTextScale.large,
    ]);
  });

  test('normalize 只保留三个档位，其余回退标准档', () {
    expect(AppTextScale.normalize(AppTextScale.small), AppTextScale.small);
    expect(
      AppTextScale.normalize(AppTextScale.standard),
      AppTextScale.standard,
    );
    expect(AppTextScale.normalize(AppTextScale.large), AppTextScale.large);

    // 历史/异常存储值吸附到最近档位。
    expect(AppTextScale.normalize(0.9), AppTextScale.small);
    expect(AppTextScale.normalize(1.18), AppTextScale.large);

    // 超出档位范围或非法输入回退标准档。
    expect(AppTextScale.normalize(1.6), AppTextScale.standard);
    expect(AppTextScale.normalize(0.4), AppTextScale.standard);
    expect(AppTextScale.normalize(double.nan), AppTextScale.standard);
    expect(AppTextScale.normalize(double.infinity), AppTextScale.standard);
    expect(AppTextScale.normalize(null), AppTextScale.standard);
  });

  test('应用比例为 1 时直接复用系统 scaler', () {
    const system = TextScaler.linear(1.3);

    expect(
      identical(
        AppTextScale.resolve(system: system, appScale: AppTextScale.standard),
        system,
      ),
      isTrue,
    );
    // 超出档位的输入归一化回标准档，同样不加包装层。
    expect(
      identical(AppTextScale.resolve(system: system, appScale: 1.6), system),
      isTrue,
    );
  });

  test('组合 scaler 在多个字号上等于系统缩放乘应用档位', () {
    final systemScalers = <TextScaler>[
      TextScaler.noScaling,
      const TextScaler.linear(1.3),
      const TextScaler.linear(0.8),
    ];
    const fontSizes = <double>[10, 12.5, 16, 24];

    for (final system in systemScalers) {
      for (final appScale in const [AppTextScale.small, AppTextScale.large]) {
        final scaler = AppTextScale.resolve(system: system, appScale: appScale);
        for (final fontSize in fontSizes) {
          expect(
            scaler.scale(fontSize),
            closeTo(system.scale(fontSize * appScale), 1e-9),
            reason: 'system=$system appScale=$appScale fontSize=$fontSize',
          );
        }
      }
    }
  });

  test('相同配置的 scaler 相等且 hashCode 一致，不同档位不相等', () {
    const system = TextScaler.linear(1.25);
    final small = AppTextScale.resolve(
      system: system,
      appScale: AppTextScale.small,
    );
    final same = AppTextScale.resolve(
      system: system,
      appScale: AppTextScale.small,
    );
    // 归一化后落到同一档位的历史值也应视为相等，避免无意义的文字重建。
    final normalized = AppTextScale.resolve(system: system, appScale: 0.86);
    final large = AppTextScale.resolve(
      system: system,
      appScale: AppTextScale.large,
    );

    expect(small, same);
    expect(small.hashCode, same.hashCode);
    expect(small, normalized);
    expect(normalized.hashCode, small.hashCode);
    expect(small, isNot(large));
    expect(
      small.scale(16),
      closeTo(system.scale(16 * AppTextScale.small), 1e-9),
    );
  });
}
