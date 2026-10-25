import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'design_tokens.dart';

/// 原生平台的基础文字排版基准。
///
/// Android 端正文默认按逻辑字号 10 排版（[DesignTokens.androidFontSizeBody]），
/// 其它平台沿用共享的 [DesignTokens.fontSizeBody] 14。实现方式是给系统
/// [TextScaler] 再包一层基准 scaler，因此：
///
/// - 只影响文字排版，padding / viewInsets / 触控尺寸仍是系统原值；
/// - 基准比例由常量 `10 / 14` 计算，不读写偏好、不做档位归一化，
///   用户档位默认仍为 100%；Android 七档与其它平台八档的已保存比例语义不变；
/// - 内层系统 scaler 原样保留，系统线性 / 非线性缩放行为不变；
/// - 非 Android 平台与移动 Web 直接返回同一个 `system` 对象。
class AppTypography {
  AppTypography._();

  /// Android 正文基准相对共享正文 token 的比例（10 / 14）。
  static const double androidBodyFactor =
      DesignTokens.androidFontSizeBody / DesignTokens.fontSizeBody;

  /// 在系统 scaler 上叠加原生平台的基础文字排版。
  ///
  /// [system] 通常是 `MediaQuery.textScaler`；[platform] 省略时取
  /// [defaultTargetPlatform]，[isWeb] 省略时取 [kIsWeb]。移动 Web 即使目标
  /// 平台是 Android 也不缩小，保持浏览器端 14 的排版基准；只有
  /// `!isWeb && platform == TargetPlatform.android` 才包一层 Android 基准
  /// scaler。已经叠加过本基准的 scaler 原样返回，重复调用不会叠加两次。
  static TextScaler platformScaler({
    required TextScaler system,
    TargetPlatform? platform,
    bool isWeb = kIsWeb,
  }) {
    if (system is _AndroidBaselineTextScaler) return system;
    final target = platform ?? defaultTargetPlatform;
    if (isWeb || target != TargetPlatform.android) return system;
    return _AndroidBaselineTextScaler(
      system: system,
      factor: androidBodyFactor,
    );
  }
}

/// 保留系统 [TextScaler] 的缩放行为，再乘上 Android 正文基准比例。
@immutable
class _AndroidBaselineTextScaler extends TextScaler {
  const _AndroidBaselineTextScaler({
    required this.system,
    required this.factor,
  });

  final TextScaler system;
  final double factor;

  @override
  double scale(double fontSize) => system.scale(fontSize * factor);

  // 仅为兼容 TextScaler 的旧接口保留；这里不读取系统已废弃的
  // textScaleFactor，而是用 scale(1) 估算，保证与 scale 实现一致。
  @override
  double get textScaleFactor => scale(1);

  @override
  bool operator ==(Object other) =>
      other is _AndroidBaselineTextScaler &&
      other.system == system &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(system, factor);

  @override
  String toString() => 'AndroidBaselineTextScaler(${factor}x on $system)';
}
