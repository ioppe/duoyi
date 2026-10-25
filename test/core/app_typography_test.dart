import 'package:duoyi/core/app_text_scale.dart';
import 'package:duoyi/core/app_typography.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模拟系统非线性字号：小字号放大比例高，大字号趋于饱和。
class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();

  @override
  double scale(double fontSize) => fontSize + 8 * fontSize / (fontSize + 8);

  @override
  double get textScaleFactor => scale(14) / 14;
}

TextScaler _android(TextScaler system) => AppTypography.platformScaler(
  system: system,
  platform: TargetPlatform.android,
  isWeb: false,
);

void main() {
  test('Android 正文基准是 10，共享字号 token 与其它平台仍是 14', () {
    expect(DesignTokens.androidFontSizeBody, 10);
    expect(DesignTokens.fontSizeBody, 14);
    expect(DesignTokens.fontSizeBase, 14);
    expect(AppTypography.androidBodyFactor, closeTo(10 / 14, 1e-12));
  });

  test('原生 Android 无系统额外放大时正文 14 的实际字号是 10', () {
    final scaler = _android(TextScaler.noScaling);
    expect(scaler.scale(DesignTokens.fontSizeBody), closeTo(10, 1e-9));
    // 其它层级按同一比例同比缩放，字号层级关系不变。
    expect(
      scaler.scale(DesignTokens.fontSizePageTitle),
      closeTo(DesignTokens.fontSizePageTitle * 10 / 14, 1e-9),
    );
    expect(
      scaler.scale(DesignTokens.fontSizeCaption),
      closeTo(DesignTokens.fontSizeCaption * 10 / 14, 1e-9),
    );
    expect(
      scaler.scale(DesignTokens.fontSizeBody),
      lessThan(DesignTokens.fontSizePageTitle),
    );
  });

  test('除原生 Android 外的平台原样返回同一个系统 scaler', () {
    const system = TextScaler.linear(1.2);
    for (final platform in TargetPlatform.values) {
      if (platform == TargetPlatform.android) continue;
      expect(
        identical(
          AppTypography.platformScaler(
            system: system,
            platform: platform,
            isWeb: false,
          ),
          system,
        ),
        isTrue,
        reason: '$platform 的正文基准必须维持 14',
      );
    }
    // 移动 Web 不缩小：即使目标平台是 Android 也原样返回。
    expect(
      identical(
        AppTypography.platformScaler(
          system: system,
          platform: TargetPlatform.android,
          isWeb: true,
        ),
        system,
      ),
      isTrue,
    );
    // 只有原生 Android 才包一层基准。
    expect(
      identical(
        AppTypography.platformScaler(
          system: system,
          platform: TargetPlatform.android,
          isWeb: false,
        ),
        system,
      ),
      isFalse,
    );
    expect(
      AppTypography.platformScaler(
        system: system,
        platform: TargetPlatform.android,
        isWeb: false,
      ).scale(DesignTokens.fontSizeBody),
      closeTo(10 * 1.2, 1e-9),
    );
  });

  test('省略 platform / isWeb 时等同于使用真实平台默认值', () {
    const system = TextScaler.linear(1.1);
    final byDefault = AppTypography.platformScaler(system: system);
    final byExplicit = AppTypography.platformScaler(
      system: system,
      platform: defaultTargetPlatform,
      isWeb: kIsWeb,
    );
    expect(byDefault, equals(byExplicit));
    // 无论宿主平台是什么，基准都只由 kIsWeb / 目标平台决定。
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      expect(identical(byDefault, system), isTrue);
    } else {
      expect(
        byDefault.scale(DesignTokens.fontSizeBody),
        closeTo(10 * 1.1, 1e-9),
      );
    }
  });

  test('系统非线性与八档用户比例组合，标准 100% 正文 10、85% 拖动到 8.5', () {
    for (final system in <TextScaler>[
      TextScaler.noScaling,
      const TextScaler.linear(1.25),
      const _NonlinearScaler(),
    ]) {
      final platform = _android(system);
      for (final ratio in AppTextScale.options) {
        final resolved = AppTextScale.resolve(
          system: platform,
          appScale: ratio,
        );
        for (final fontSize in <double>[11, 12, 14, 16, 18, 24]) {
          expect(
            resolved.scale(fontSize),
            closeTo(system.scale(fontSize * ratio * 10 / 14), 1e-9),
            reason: '${system.runtimeType} x $ratio x $fontSize',
          );
        }
      }
    }

    final platform = _android(TextScaler.noScaling);
    final standard = AppTextScale.resolve(
      system: platform,
      appScale: AppTextScale.defaultScale,
    );
    expect(standard.scale(DesignTokens.fontSizeBody), closeTo(10, 1e-9));
    final small = AppTextScale.resolve(
      system: platform,
      appScale: AppTextScale.small,
    );
    expect(small.scale(DesignTokens.fontSizeBody), closeTo(8.5, 1e-9));
  });

  test('已保存比例保留 Android 基准，预览草稿只叠一次不会乘回已保存比例', () {
    final platform = _android(TextScaler.noScaling);
    final saved = AppTextScale.resolve(system: platform, appScale: 1.75);
    expect(saved.scale(DesignTokens.fontSizeBody), closeTo(17.5, 1e-9));
    final previewBase = AppTextScale.systemScalerOf(saved);
    expect(identical(previewBase, platform), isTrue);
    expect(previewBase.scale(DesignTokens.fontSizeBody), closeTo(10, 1e-9));

    final draft = AppTextScale.resolve(system: previewBase, appScale: 1.30);
    expect(draft.scale(DesignTokens.fontSizeBody), closeTo(13, 1e-9));
    // 没有把已保存的 175% 再乘进草稿预览。
    expect(draft.scale(DesignTokens.fontSizeBody), lessThan(13 * 1.75));

    final standardDraft = AppTextScale.resolve(
      system: previewBase,
      appScale: AppTextScale.defaultScale,
    );
    expect(standardDraft.scale(DesignTokens.fontSizeBody), closeTo(10, 1e-9));
  });

  test('重复包裹不会叠加两次基准', () {
    const system = TextScaler.linear(1.0);
    final once = _android(system);
    final twice = _android(once);
    expect(identical(twice, once), isTrue);
    expect(twice.scale(DesignTokens.fontSizeBody), closeTo(10, 1e-9));
    expect(
      _android(_android(_android(system))).scale(DesignTokens.fontSizeBody),
      closeTo(10, 1e-9),
    );
  });

  test('相等性与 hashCode 保持一致', () {
    const system = TextScaler.linear(1.4);
    final a = _android(system);
    final b = _android(system);
    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(equals(_android(TextScaler.noScaling))));
    expect(a, isNot(equals(system)));
    expect(a.toString(), contains('AndroidBaselineTextScaler'));
  });

  testWidgets('Android 基准只缩放排版：正文实际 10，padding / insets / 触控尺寸不变', (
    tester,
  ) async {
    const padding = EdgeInsets.fromLTRB(4, 6, 8, 10);
    const viewInsets = EdgeInsets.fromLTRB(0, 12, 0, 20);
    final heights = <TargetPlatform, double>{};
    final scalers = <TargetPlatform, TextScaler>{};

    for (final platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.linux,
    ]) {
      late TextScaler seenScaler;
      late EdgeInsets seenPadding;
      late EdgeInsets seenInsets;
      await tester.pumpWidget(
        MediaQuery(
          data:
              const MediaQueryData(
                size: Size(390, 844),
                padding: padding,
                viewInsets: viewInsets,
              ).copyWith(
                textScaler: AppTypography.platformScaler(
                  system: TextScaler.noScaling,
                  platform: platform,
                  isWeb: false,
                ),
              ),
          child: Builder(
            builder: (context) {
              seenScaler = MediaQuery.textScalerOf(context);
              seenPadding = MediaQuery.paddingOf(context);
              seenInsets = MediaQuery.viewInsetsOf(context);
              return Directionality(
                textDirection: TextDirection.ltr,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 300,
                      child: Text(
                        '默认字号正文',
                        style: TextStyle(
                          fontSize: DesignTokens.fontSizeBody,
                          fontFamily: DesignTokens.fontFamily,
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 120,
                      height: DesignTokens.controlMinHeight,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      heights[platform] = tester
          .renderObject<RenderParagraph>(find.byType(RichText))
          .size
          .height;
      scalers[platform] = seenScaler;
      // 文字缩放不改变系统 padding / insets。
      expect(seenPadding, padding);
      expect(seenInsets, viewInsets);
      // 触控尺寸由设计 token 决定，不随字号基准缩小。
      expect(
        tester.getSize(
          find.byWidgetPredicate(
            (widget) =>
                widget is SizedBox &&
                widget.height == DesignTokens.controlMinHeight,
          ),
        ),
        const Size(120, DesignTokens.controlMinHeight),
      );
    }

    expect(
      scalers[TargetPlatform.android]!.scale(DesignTokens.fontSizeBody),
      closeTo(10, 1e-9),
    );
    expect(
      scalers[TargetPlatform.linux]!.scale(DesignTokens.fontSizeBody),
      closeTo(14, 1e-9),
    );
    // 真实渲染的段落高度按 10/14 缩小，证明缩放作用到了实际排版。
    expect(
      heights[TargetPlatform.android]! / heights[TargetPlatform.linux]!,
      closeTo(10 / 14, .01),
    );
  });
}
