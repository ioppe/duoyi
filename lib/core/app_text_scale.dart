import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// 应用内字体大小档位。
///
/// 只影响多仪内部的文字排版，与手机系统字号相乘后生效；不会修改系统
/// 设置，也不影响其他应用的显示。
class AppTextScale {
  AppTextScale._();

  /// 历史三档常量保留，供升级前的存储值/调用方继续引用。
  static const double small = 0.85;
  static const double standard = 1.0;
  static const double large = 1.15;

  /// 默认档位：标准（100%），位于滑块第二档。
  static const double defaultScale = standard;

  /// 可选档位，按从小到大的顺序排列；索引即滑块刻度位置。
  static const List<double> options = <double>[
    small,
    standard,
    large,
    1.30,
    1.45,
    1.60,
    1.75,
    1.90,
  ];

  /// 标准档在 [options] 中的索引（第二档），用于滑块标准标识。
  static int get standardIndex => options.indexOf(standard);

  /// 把任意输入归一化到 [options] 中的一档。
  ///
  /// 合法档位原样保留；有限正数吸附到最近档位（超出范围时取最近边界）；
  /// null / NaN / infinity / 非正数回落到标准档。
  static double normalize(double? value) {
    if (value == null || !value.isFinite || value <= 0) return defaultScale;
    var snapped = options.first;
    var smallestDelta = double.infinity;
    for (final option in options) {
      final delta = (value - option).abs();
      if (delta < smallestDelta) {
        smallestDelta = delta;
        snapped = option;
      }
    }
    return snapped;
  }

  /// 档位在 [options] 中的索引；非法输入返回标准档索引。
  static int indexOf(double value) {
    final index = options.indexOf(normalize(value));
    return index < 0 ? standardIndex : index;
  }

  /// 档位对应的整数百分比（85 / 100 / 115 / … / 190）。
  static int percentOf(double value) => (normalize(value) * 100).round();

  /// 从当前应用 wrapper 中取回平台 [TextScaler]。
  ///
  /// [resolve] 会把应用档位包在系统 scaler 外层；页面预览需要系统字号叠加
  /// 草稿档位，必须先剥掉应用 factor，否则会重复相乘。
  static TextScaler systemScalerOf(TextScaler scaler) {
    var current = scaler;
    while (current is _AppTextScaler) {
      current = current.system;
    }
    return current;
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
