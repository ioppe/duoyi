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

  /// 默认档位：标准（100%），新安装或从未保存过档位时按 100% 显示。
  static const double defaultScale = standard;

  /// 原生 Android 七档：55 / 70 / 85 / 100 / 115 / 130 / 145。
  ///
  /// 步长 15%，标准 100% 为第四档（索引 3），左右各三档。
  static const List<double> androidOptions = <double>[
    0.55,
    0.70,
    small,
    standard,
    large,
    1.30,
    1.45,
  ];

  /// 其它平台（含移动 Web）八档：85 / 100 / 115 / … / 190。
  static const List<double> sharedOptions = <double>[
    small,
    standard,
    large,
    1.30,
    1.45,
    1.60,
    1.75,
    1.90,
  ];

  /// 指定平台生效的档位表。
  ///
  /// 只有原生 Android（`!isWeb && platform == TargetPlatform.android`）用
  /// 七档 [androidOptions]，其它平台与移动 Web 沿用八档 [sharedOptions]。
  /// [platform] 省略时取 [defaultTargetPlatform]，[isWeb] 省略时取 [kIsWeb]。
  static List<double> optionsFor({
    TargetPlatform? platform,
    bool isWeb = kIsWeb,
  }) => _androidProfile(platform: platform, isWeb: isWeb)
      ? androidOptions
      : sharedOptions;

  static bool _androidProfile({TargetPlatform? platform, bool isWeb = kIsWeb}) {
    if (isWeb) return false;
    return (platform ?? defaultTargetPlatform) == TargetPlatform.android;
  }

  /// 当前平台生效的档位表，按从小到大的顺序排列；索引即滑块刻度位置。
  static List<double> get options => optionsFor();

  /// 标准档在当前档位表中的索引，用于滑块标准标识（八档为 1，七档为 3）。
  static int get standardIndex => options.indexOf(standard);

  /// 把任意输入归一化到当前档位表中的一档。
  ///
  /// 合法档位原样保留；有限正数吸附到最近档位（超出范围时取最近边界，
  /// 距离相同时取较小档位）；null / NaN / infinity / 非正数回落到默认标准档。
  static double normalize(
    double? value, {
    TargetPlatform? platform,
    bool isWeb = kIsWeb,
  }) {
    if (value == null || !value.isFinite || value <= 0) return defaultScale;
    final options = optionsFor(platform: platform, isWeb: isWeb);
    // 按有序档位的中点分区，避免两次减法的浮点尾差把等距值推向较大档。
    for (var index = 0; index < options.length - 1; index++) {
      final midpoint = (options[index] + options[index + 1]) / 2;
      if (value <= midpoint) return options[index];
    }
    return options.last;
  }

  /// 档位在当前档位表中的索引；非法输入归一化到默认标准档。
  static int indexOf(
    double value, {
    TargetPlatform? platform,
    bool isWeb = kIsWeb,
  }) {
    final options = optionsFor(platform: platform, isWeb: isWeb);
    final index = options.indexOf(
      normalize(value, platform: platform, isWeb: isWeb),
    );
    if (index >= 0) return index;
    final standardIndex = options.indexOf(standard);
    return standardIndex < 0 ? 0 : standardIndex;
  }

  /// 档位对应的整数百分比（Android 55 / … / 145，其它平台 85 / … / 190）。
  static int percentOf(
    double value, {
    TargetPlatform? platform,
    bool isWeb = kIsWeb,
  }) => (normalize(value, platform: platform, isWeb: isWeb) * 100).round();

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
  /// 应用比例按 [optionsFor] 的同一平台档位表归一化；比例为 1 时直接返回
  /// [system]，避免多包一层造成无意义的文字重建。
  static TextScaler resolve({
    required TextScaler system,
    required double appScale,
    TargetPlatform? platform,
    bool isWeb = kIsWeb,
  }) {
    final scale = normalize(appScale, platform: platform, isWeb: isWeb);
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
