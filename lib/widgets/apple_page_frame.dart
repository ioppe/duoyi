import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import 'surface_components.dart';

/// 页面是否处于默认主题的 Apple minimal 档位。
///
/// 只有默认主题注册了 `AppSurfaceStyle.appleMinimal`；re0..botw 与液态玻璃主题
/// 都返回 false，下方组件据此回退到调用点既有结构（透明 / 逐像素不变）。
bool usesApplePageLayout(BuildContext context) =>
    AppSurfaceStyle.isDefaultTheme(appSurfaceStyleOf(context));

/// 一级页面内容列：左对齐页头 + 限宽内容 + 统一左右页边距。
///
/// 默认主题下把页面内容收进 720 宽、左右 16 的内容列（桌面居中，不拉满）；
/// 其他主题直接返回 [child]，不改变任何既有布局。
class ApplePageFrame extends StatelessWidget {
  /// 内容列左右页边距。
  static const double gutter = 16;

  /// 内容列最大宽度：与 `DesignTokens.homeContentMaxWidth` 同档，
  /// 保证首页 FAB 仍贴在内容列右缘。
  static const double maxContentWidth = 720;

  /// 页头顶部留白。
  static const double pageTop = 16;

  /// 页尾安全留白（不压住底部导航 / 手势区）。
  static const double pageBottom = 32;

  /// 组与组之间的固定间距。
  static const double sectionGap = 16;

  final Widget child;

  /// 左右页边距；滚动容器自带左右 padding 时传 0，避免双重留白。
  final double horizontalInset;
  final double maxWidth;

  const ApplePageFrame({
    super.key,
    required this.child,
    this.horizontalInset = gutter,
    this.maxWidth = maxContentWidth,
  });

  /// 滚动容器（ListView / CustomScrollView）的统一内边距。
  static EdgeInsets scrollPadding({
    double top = pageTop,
    double bottom = pageBottom,
    double horizontal = 0,
    double extraBottom = 0,
  }) => EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom + extraBottom);

  @override
  Widget build(BuildContext context) {
    if (!usesApplePageLayout(context)) return child;
    final Widget framed = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: horizontalInset > 0
          ? Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalInset),
              child: child,
            )
          : child,
    );
    return Align(alignment: Alignment.topCenter, child: framed);
  }
}

/// Apple 页头：超大左对齐标题 + 可选副标题 + 可选右侧轻量动作。
///
/// 只在默认主题下由调用点使用；标题走 [DesignTokens] 字阶（24 / strong），
/// 与内容列共用同一左侧基线，不使用居中标题或大号 AppBar。
class ApplePageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Key? titleKey;
  final Key? subtitleKey;
  final EdgeInsetsGeometry padding;

  const ApplePageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.titleKey,
    this.subtitleKey,
    this.padding = const EdgeInsets.fromLTRB(0, 8, 0, 12),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    final titleColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            key: titleKey,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: (theme.textTheme.headlineSmall ?? const TextStyle())
                .copyWith(
                  fontSize: DesignTokens.homeHeadingSize,
                  fontWeight: DesignTokens.fontWeightStrong,
                  color: cs.onSurface,
                  height: 1.18,
                ),
          ),
        ),
        if (hasSubtitle) ...[
          const SizedBox(height: DesignTokens.spaceXs),
          Text(
            subtitle!,
            key: subtitleKey,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
              fontSize: DesignTokens.homeCaptionSize,
              fontWeight: DesignTokens.fontWeightRegular,
              color: DesignTokens.homeMuted,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: titleColumn),
          if (trailing != null) ...[
            const SizedBox(width: DesignTokens.spaceSm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// 轻量分组容器：默认主题下是一张白色组面，组内使用细分隔线和扁平行；
/// 不再嵌套 `AppSurfaceCard`，避免 Apple 页面出现连续厚卡。其他主题原样透传 [child]。
class AppleGroup extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;

  const AppleGroup({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(14, 10, 14, 10),
    this.margin = EdgeInsets.zero,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (!usesApplePageLayout(context)) return child;
    final surfaceStyle = appSurfaceStyleOf(context);
    final radius = BorderRadius.circular(
      surfaceStyle?.cardRadius ?? DesignTokens.radiusCard,
    );
    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(
            color:
                color ??
                surfaceStyle?.cardFillColor ??
                Theme.of(context).colorScheme.surface,
            borderRadius: radius,
            border: surfaceStyle?.cardBorder ?? const Border(),
            boxShadow: surfaceStyle?.cardShadow ?? const <BoxShadow>[],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// 组面内的扁平列表：行与行之间只留 0.5 细分隔线，不再逐行套卡片。
///
/// 默认主题下由一张 [AppleGroup] 承载所有 [children]；其他主题退化为零间距
/// [Column]，调用点可继续沿用旧结构。
class AppleGroupedList extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double dividerIndent;
  final bool showDividers;

  const AppleGroupedList({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(vertical: 2),
    this.margin = EdgeInsets.zero,
    this.dividerIndent = 0,
    this.showDividers = true,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && showDividers) {
        rows.add(
          Divider(
            height: 0.5,
            thickness: 0.5,
            indent: dividerIndent,
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        );
      }
      rows.add(children[i]);
    }
    if (!usesApplePageLayout(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    }
    return AppleGroup(
      margin: margin,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

/// 组面内的扁平行：左侧可选图标块、标题 / 副标题、右侧尾随控件。
///
/// 默认主题不使用卡片，只在白组面内画一行；触摸目标保持
/// [DesignTokens.controlMinHeight] 以上。
class AppleRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;
  final EdgeInsetsGeometry padding;
  final double minHeight;

  const AppleRow({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.titleColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
    this.minHeight = DesignTokens.controlMinHeight,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: DesignTokens.spaceMd),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (theme.textTheme.bodyMedium ?? const TextStyle())
                        .copyWith(
                          fontSize: DesignTokens.fontSizeBody,
                          fontWeight: DesignTokens.fontWeightRegular,
                          color: titleColor ?? cs.onSurface,
                          height: 1.3,
                        ),
                  ),
                  if (hasSubtitle) ...[
                    const SizedBox(height: DesignTokens.spaceXxs),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (theme.textTheme.bodySmall ?? const TextStyle())
                          .copyWith(
                            fontSize: DesignTokens.fontSizeSecondary,
                            fontWeight: DesignTokens.fontWeightRegular,
                            color: cs.onSurface.withValues(alpha: 0.58),
                            height: 1.3,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: DesignTokens.spaceSm),
              trailing!,
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        child: content,
      ),
    );
  }
}

/// 轻量控制带：把页签 / 视图切换 / 筛选等控件收进一条淡底分组，而不是
/// 让每个控制器各自贴边成卡。
class AppleControlBand extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const AppleControlBand({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(6, 6, 6, 6),
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    if (!usesApplePageLayout(context)) {
      return Padding(padding: margin, child: child);
    }
    final cs = Theme.of(context).colorScheme;
    return AppleGroup(
      margin: margin,
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            cs.onSurface.withValues(alpha: 0.045),
            cs.surface,
          ),
          borderRadius: BorderRadius.circular(DesignTokens.radiusControlIos),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.30),
            width: 0.45,
          ),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// 统一的左对齐分组标题。
///
/// 默认主题：左对齐标题 + 可选副标题（明确层级），右侧轻量文本操作，不使用
/// 硬分割线。其他主题沿用调用点既有样式（[titleStyle] / [subtitleStyle] /
/// [actionTextStyle]），结构退化为改造前的行式页头。
class AppleSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final Key? headerKey;
  final EdgeInsetsGeometry padding;

  /// 非默认主题使用的标题 / 副标题 / 操作文字样式（默认主题忽略）。
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final TextStyle? actionTextStyle;
  final Color? actionColor;

  const AppleSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.headerKey,
    this.padding = EdgeInsets.zero,
    this.titleStyle,
    this.subtitleStyle,
    this.actionTextStyle,
    this.actionColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final apple = usesApplePageLayout(context);
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;

    final titleWidget = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: apple
          ? (theme.textTheme.titleSmall ?? const TextStyle()).copyWith(
              fontSize: DesignTokens.fontSizeSection,
              fontWeight: DesignTokens.fontWeightStrong,
              color: cs.onSurface,
              height: 1.25,
            )
          : titleStyle,
    );
    final subtitleWidget = !hasSubtitle
        ? null
        : Text(
            subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: apple
                ? (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
                    fontSize: DesignTokens.fontSizeSecondary,
                    fontWeight: DesignTokens.fontWeightRegular,
                    color: cs.onSurface.withValues(alpha: 0.60),
                    height: 1.35,
                  )
                : subtitleStyle,
          );

    final titleColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (apple) Semantics(header: true, child: titleWidget) else titleWidget,
        if (subtitleWidget != null) ...[
          SizedBox(
            height: apple ? DesignTokens.spaceXs : DesignTokens.spaceXxs,
          ),
          subtitleWidget,
        ],
      ],
    );

    final action = (onAction == null || actionLabel == null)
        ? null
        : TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: actionColor ?? (apple ? cs.primary : null),
              textStyle: apple ? null : actionTextStyle,
              minimumSize: const Size(0, DesignTokens.controlMinHeight),
              padding: EdgeInsets.symmetric(
                horizontal: apple ? DesignTokens.spaceSm : DesignTokens.spaceXs,
              ),
              visualDensity: apple ? VisualDensity.compact : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    actionLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: DesignTokens.spaceXs),
                Icon(
                  actionIcon ?? Icons.chevron_right,
                  size: apple
                      ? DesignTokens.fontSizeCaption
                      : DesignTokens.fontSizeMd,
                ),
              ],
            ),
          );

    return Padding(
      key: headerKey,
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (action == null) return titleColumn;
          if (constraints.maxWidth < 340) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleColumn,
                const SizedBox(height: DesignTokens.spaceXs),
                Align(alignment: Alignment.centerLeft, child: action),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: titleColumn),
              const SizedBox(width: DesignTokens.spaceSm),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: (constraints.maxWidth * 0.42).clamp(96.0, 180.0),
                ),
                child: action,
              ),
            ],
          );
        },
      ),
    );
  }
}
