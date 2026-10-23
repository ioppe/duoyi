import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// 应用内字体大小档位。
///
/// 只影响多仪内部的文字排版，与手机系统字号相乘后生效；不会修改系统
/// 设置，也不影响其他应用的显示。
class AppTextScale {
  AppTextScale._();

  static const double small = 0.85;
  static const double standard = 1.0;
  static const double large = 1.15;

  /// 默认档位：标准（100%）。
  static const double defaultScale = standard;

  /// 可选档位，按从小到大的顺序排列。
  static const List<double> options = <double>[small, standard, large];

  /// 相邻档位间隔的一半：只有落在该范围内的历史/异常存储值才吸附到最近
  /// 档位，超出则回落到标准档，避免出现 1.5 倍这类未提供的字号。
  static const double _snapTolerance = 0.075;

  /// 把任意输入归一化到三个档位之一；非法值回落到标准档。
  static double normalize(double? value) {
    if (value == null || !value.isFinite) return defaultScale;
    var snapped = defaultScale;
    var smallestDelta = double.infinity;
    for (final option in options) {
      final delta = (value - option).abs();
      if (delta < smallestDelta) {
        smallestDelta = delta;
        snapped = option;
      }
    }
    return smallestDelta <= _snapTolerance ? snapped : defaultScale;
  }

  /// 组合系统字号与应用字号。
  ///
  /// 应用比例为 1 时直接返回 [system]，避免多包一层造成无意义的文字重建。
  static TextScaler resolve({
    required TextScaler system,
    required double appScale,
  }) {
    final scale = normalize(appScale);
    if (scale == standard) return system;
    return _AppTextScaler(system: system, factor: scale);
  }
}

/// 保留系统 [TextScaler] 的缩放行为，再乘上应用字号档位。
@immutable
class _AppTextScaler extends TextScaler {
  const _AppTextScaler({required this.system, required this.factor});

  final TextScaler system;
  final double factor;

  @override
  double scale(double fontSize) => system.scale(fontSize * factor);

  // 仅为兼容 TextScaler 的旧接口保留；这里不读取系统已废弃的
  // textScaleFactor，而是用 scale(1) 估算，保证与 scale 实现一致。
  @override
  double get textScaleFactor => system.scale(1) * factor;

  @override
  bool operator ==(Object other) =>
      other is _AppTextScaler &&
      other.system == system &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(system, factor);

  @override
  String toString() => 'AppTextScaler(${factor}x on $system)';
}
