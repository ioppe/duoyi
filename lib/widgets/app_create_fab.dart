import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

/// Page-level creation action. Place in Scaffold.floatingActionButton so the
/// primary entry stays at the lower end on phones and desktop layouts alike.
///
/// 全站唯一视觉实现：主题形状与底色、20 图标、14 medium 标签、左右 16 内边距、
/// 8 图文间距、56 最小高度（大字号自动增高），因此不同页面同文案的按钮尺寸一致。
///
/// 需要长按展开二级菜单的入口（首页快速捕获）传入 [onLongPress]：此时按钮不使用
/// 内建 Tooltip（其默认 longPress 触发会吞掉长按），改由外层手动 Tooltip +
/// GestureDetector 承载，点击与长按互不干扰。
class AppCreateFab extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final IconData icon;
  final String? tooltip;
  final Color? backgroundColor;
  final Object? heroTag;

  const AppCreateFab({
    super.key,
    required this.label,
    required this.onPressed,
    this.onLongPress,
    this.icon = Icons.add,
    this.tooltip,
    this.backgroundColor,
    this.heroTag,
  });

  /// 主创建按钮的默认高度档（Material 3 扩展 FAB）。
  static const double minHeight = 56;

  @override
  Widget build(BuildContext context) {
    final fab = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minHeight),
      child: _buildFab(context),
    );
    if (onLongPress == null) return fab;
    return Tooltip(
      message: tooltip ?? '',
      triggerMode: TooltipTriggerMode.manual,
      child: GestureDetector(onLongPress: onLongPress, child: fab),
    );
  }

  Widget _buildFab(BuildContext context) {
    final maxLabelWidth =
        (MediaQuery.sizeOf(context).width - DesignTokens.space5xl * 2).clamp(
          0.0,
          double.infinity,
        );
    return FloatingActionButton.extended(
      heroTag: heroTag,
      onPressed: onPressed,
      tooltip: onLongPress == null ? (tooltip ?? label) : null,
      backgroundColor: backgroundColor,
      extendedPadding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceLg,
      ),
      extendedIconLabelSpacing: DesignTokens.spaceSm,
      extendedTextStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        fontSize: DesignTokens.fontSizeButton,
        fontWeight: DesignTokens.fontWeightMedium,
      ),
      icon: Icon(icon, size: DesignTokens.controlIconSize),
      label: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxLabelWidth),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
