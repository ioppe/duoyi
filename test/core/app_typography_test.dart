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

/// 共享排版角色：标题 / 卡片标题 / 正文 / 辅助 / 说明 / 按钮 / 导航标签。
const _roles = <String, double>{
  'page title': DesignTokens.fontSizePageTitle,
  'card title': DesignTokens.fontSizeCardTitle,
  'body': DesignTokens.fontSizeBody,
  'secondary': DesignTokens.fontSizeSecondary,
  'caption': DesignTokens.fontSizeCaption,
  'button': DesignTokens.fontSizeButton,
  'bottom nav label': DesignTokens.fontSizeBottomNavLabel,
};

void main() {
  test('Android 正文基准是 12，共享字号 token 与其它平台仍是 14', () {
    expect(DesignTokens.androidFontSizeBody, 12);
    expect(DesignTokens.fontSizeBody, 14);
    expect(DesignTokens.fontSizeBase, 14);
    expect(AppTypography.androidBodyFactor, closeTo(12 / 14, 1e-12));
  });

  test('原生 Android 无系统额外放大时正文 14 的实际字号是 12', () {
    final scaler = _android(TextScaler.noScaling);
    expect(scaler.scale(DesignTokens.fontSizeBody), closeTo(12, 1e-9));
    // 其它层级按同一比例同比缩放，字号层级关系不变。
    expect(
      scaler.scale(DesignTokens.fontSizePageTitle),
      closeTo(DesignTokens.fontSizePageTitle * 12 / 14, 1e-9),
    );
    expect(
      scaler.scale(DesignTokens.fontSizeCaption),
      closeTo(DesignTokens.fontSizeCaption * 12 / 14, 1e-9),
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
      closeTo(12 * 1.2, 1e-9),
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
        closeTo(12 * 1.1, 1e-9),
      );
    }
  });

  test('Android 七档 × 共享排版角色：先叠 12/14 基准再乘用户比例', () {
    final options = AppTextScale.optionsFor(
      platform: TargetPlatform.android,
      isWeb: false,
    );
    expect(options, [.55, .70, .85, 1.0, 1.15, 1.30, 1.45]);
    for (final system in <TextScaler>[
      TextScaler.noScaling,
      const TextScaler.linear(1.25),
      const _NonlinearScaler(),
    ]) {
      final platform = _android(system);
      for (final ratio in options) {
        final resolved = AppTextScale.resolve(
          system: platform,
          appScale: ratio,
          platform: TargetPlatform.android,
        );
        for (final role in _roles.entries) {
          expect(
            resolved.scale(role.value),
            closeTo(system.scale(role.value * ratio * 12 / 14), 1e-9),
            reason: '${role.key} x ${system.runtimeType} x $ratio',
          );
        }
      }
    }

    final platform = _android(TextScaler.noScaling);
    double bodyAt(double ratio) => AppTextScale.resolve(
      system: platform,
      appScale: ratio,
      platform: TargetPlatform.android,
    ).scale(DesignTokens.fontSizeBody);
    // 七档正文全部由 12 基准等比缩放：55% 6.6、70% 8.4、85% 10.2、
    // 100% 12、115% 13.8、130% 15.6、145% 17.4。
    expect(bodyAt(.55), closeTo(6.6, 1e-9));
    expect(bodyAt(.70), closeTo(8.4, 1e-9));
    expect(bodyAt(.85), closeTo(10.2, 1e-9));
    expect(bodyAt(AppTextScale.defaultScale), closeTo(12, 1e-9));
    expect(bodyAt(1.15), closeTo(13.8, 1e-9));
    expect(bodyAt(1.30), closeTo(15.6, 1e-9));
    expect(bodyAt(1.45), closeTo(17.4, 1e-9));
  });

  test('非 Android 八档 × 共享角色保持 14 基准，移动 Web 同样是八档', () {
    const shared = [.85, 1.0, 1.15, 1.30, 1.45, 1.60, 1.75, 1.90];
    for (final platformKind in <TargetPlatform>[
      TargetPlatform.iOS,
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    ]) {
      final options = AppTextScale.optionsFor(
        platform: platformKind,
        isWeb: false,
      );
      expect(options, shared, reason: '$platformKind 必须保持八档');
      for (final system in <TextScaler>[
        TextScaler.noScaling,
        const TextScaler.linear(1.25),
        const _NonlinearScaler(),
      ]) {
        for (final ratio in options) {
          final resolved = AppTextScale.resolve(
            system: system,
            appScale: ratio,
            platform: platformKind,
          );
          for (final role in _roles.entries) {
            expect(
              resolved.scale(role.value),
              closeTo(system.scale(role.value * ratio), 1e-9),
              reason: '$platformKind ${role.key} x $ratio',
            );
          }
        }
      }
    }

    // 移动 Web：目标平台是 Android 也保持八档与 14 的正文基准。
    expect(
      AppTextScale.optionsFor(platform: TargetPlatform.android, isWeb: true),
      shared,
    );
    final webScaler = AppTextScale.resolve(
      system: AppTypography.platformScaler(
        system: TextScaler.noScaling,
        platform: TargetPlatform.android,
        isWeb: true,
      ),
      appScale: 1.90,
      platform: TargetPlatform.android,
      isWeb: true,
    );
    expect(
      webScaler.scale(DesignTokens.fontSizeBody),
      closeTo(14 * 1.90, 1e-9),
    );
  });

  test('已保存比例保留 Android 基准，预览草稿只叠一次不会乘回已保存比例', () {
    final platform = _android(TextScaler.noScaling);
    // 旧版保存的 175% 在 Android 七档里读到有效的 145%。
    final saved = AppTextScale.resolve(
      system: platform,
      appScale: 1.75,
      platform: TargetPlatform.android,
    );
    expect(saved.scale(DesignTokens.fontSizeBody), closeTo(17.4, 1e-9));
    final previewBase = AppTextScale.systemScalerOf(saved);
    expect(identical(previewBase, platform), isTrue);
    expect(previewBase.scale(DesignTokens.fontSizeBody), closeTo(12, 1e-9));

    final draft = AppTextScale.resolve(
      system: previewBase,
      appScale: 1.30,
      platform: TargetPlatform.android,
    );
    expect(draft.scale(DesignTokens.fontSizeBody), closeTo(15.6, 1e-9));
    // 没有把已保存的 145% 再乘进草稿预览。
    expect(draft.scale(DesignTokens.fontSizeBody), lessThan(15.6 * 1.45));

    final standardDraft = AppTextScale.resolve(
      system: previewBase,
      appScale: AppTextScale.defaultScale,
      platform: TargetPlatform.android,
    );
    expect(standardDraft.scale(DesignTokens.fontSizeBody), closeTo(12, 1e-9));
  });

  test('重复包裹不会叠加两次基准', () {
    const system = TextScaler.linear(1.0);
    final once = _android(system);
    final twice = _android(once);
    expect(identical(twice, once), isTrue);
    expect(twice.scale(DesignTokens.fontSizeBody), closeTo(12, 1e-9));
    expect(
      _android(_android(_android(system))).scale(DesignTokens.fontSizeBody),
      closeTo(12, 1e-9),
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

  testWidgets('Android 基准只缩放排版：正文实际 12，padding / insets / 触控尺寸不变', (
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
      closeTo(12, 1e-9),
    );
    expect(
      scalers[TargetPlatform.linux]!.scale(DesignTokens.fontSizeBody),
      closeTo(14, 1e-9),
    );
    // 真实渲染的段落高度按 12/14 缩小，证明缩放作用到了实际排版。
    expect(
      heights[TargetPlatform.android]! / heights[TargetPlatform.linux]!,
      closeTo(12 / 14, .01),
    );
  });

  testWidgets('Android 七档在真实段落上应用组合 scaler：正文 6.6 / 12 / 17.4', (tester) async {
    for (final system in <TextScaler>[
      TextScaler.noScaling,
      const _NonlinearScaler(),
    ]) {
      final baseline = _android(system);
      for (final ratio in AppTextScale.androidOptions) {
        final scaler = AppTextScale.resolve(
          system: baseline,
          appScale: ratio,
          platform: TargetPlatform.android,
        );
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              textScaler: scaler,
            ),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                '正文',
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeBody,
                  fontFamily: DesignTokens.fontFamily,
                ),
              ),
            ),
          ),
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.byType(RichText),
        );
        // 真实段落拿到的是 12 / 14 基准与用户档位组合后的 scaler。
        expect(
          paragraph.textScaler.scale(DesignTokens.fontSizeBody),
          closeTo(system.scale(12 * ratio), .001),
          reason: '${system.runtimeType} x $ratio',
        );
      }
    }
    // 标准档正文 12、最大档 145% 正文 17.4。
    final standard = AppTextScale.resolve(
      system: _android(TextScaler.noScaling),
      appScale: AppTextScale.defaultScale,
      platform: TargetPlatform.android,
    );
    expect(standard.scale(DesignTokens.fontSizeBody), closeTo(12, 1e-9));
    final maximum = AppTextScale.resolve(
      system: _android(TextScaler.noScaling),
      appScale: 1.45,
      platform: TargetPlatform.android,
    );
    expect(maximum.scale(DesignTokens.fontSizeBody), closeTo(17.4, 1e-9));
  });
}
