/// 视觉三件套：EmptyState / LoadingState / ErrorState（Task 20 / Req 10.2）。
///
/// - [EmptyState] 沿用 `lib/widgets/empty_state.dart` 中的既有实现，这里
///   重导出，便于调用方统一从 `result_states.dart` 导入。
/// - [LoadingState] 基于纯 Flutter `AnimationController` 实现 shimmer 条带，
///   不引入 `shimmer` 包，保持依赖表干净。
/// - [ErrorState] 接收 `Object error, VoidCallback? onRetry`，统一错误展示。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
export 'empty_state.dart' show EmptyState;

/// 加载中占位：带 shimmer 扫光的骨架条。
class LoadingState extends StatefulWidget {
  /// 可选的加载文案。
  final String? message;

  /// 占位条的数量。
  final int lines;

  const LoadingState({super.key, this.message, this.lines = 3});

  @override
  State<LoadingState> createState() => _LoadingStateState();
}

class _LoadingStateState extends State<LoadingState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth.isFinite && constraints.maxWidth < 320;
        final padding = narrow ? DesignTokens.spaceMd : DesignTokens.spaceXxl;
        final availableWidth = constraints.maxWidth.isFinite
            ? math.max(0.0, constraints.maxWidth - padding * 2)
            : 260.0;

        double barWidth(int index) {
          final desired = index == 0 ? 220.0 : 180.0 - index * 20.0;
          return math.max(0.0, math.min(desired, availableWidth));
        }

        return Center(
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < widget.lines; i++) ...[
                  _ShimmerBar(controller: _controller, width: barWidth(i)),
                  const SizedBox(height: DesignTokens.spaceSm),
                ],
                if (widget.message != null) ...[
                  const SizedBox(height: DesignTokens.spaceLg),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: availableWidth),
                    child: Text(
                      widget.message!,
                      textAlign: TextAlign.center,
                      maxLines: narrow ? 3 : null,
                      overflow: narrow ? TextOverflow.ellipsis : null,
                      style: TextStyle(
                        fontSize: DesignTokens.fontSizeSm,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ShimmerBar extends StatelessWidget {
  final AnimationController controller;
  final double width;

  const _ShimmerBar({required this.controller, required this.width});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        return ClipRRect(
          borderRadius: DesignTokens.borderRadiusSm,
          child: SizedBox(
            width: width,
            height: 12,
            child: ShaderMask(
              shaderCallback: (rect) {
                return LinearGradient(
                  begin: Alignment(-1.0 + 2.0 * t, 0),
                  end: Alignment(0.0 + 2.0 * t, 0),
                  colors: const [
                    DesignTokens.resultLoadingShimmerBase,
                    DesignTokens.resultLoadingShimmerHighlight,
                    DesignTokens.resultLoadingShimmerBase,
                  ],
                ).createShader(rect);
              },
              child: Container(color: DesignTokens.resultLoadingShimmerBase),
            ),
          ),
        );
      },
    );
  }
}

/// 紧凑型空态提示：用于卡片/区块内部的小占位。
///
/// 区别于整页 [EmptyState]（卡片式大图标 + 操作按钮），本组件只渲染
/// 一个弱化的图标与文案，适合嵌入统计卡片、图表区块内部的空数据占位。
class EmptyHint extends StatelessWidget {
  final IconData icon;
  final String message;

  const EmptyHint({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: DesignTokens.spaceLg,
          horizontal: DesignTokens.spaceMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: cs.onSurface.withValues(alpha: 0.35)),
            const SizedBox(height: DesignTokens.spaceSm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: DesignTokens.fontSizeSm,
                color: cs.onSurface.withValues(alpha: 0.5),
                fontWeight: DesignTokens.fontWeightStrong,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 错误态占位：带重试按钮的错误展示。
class ErrorState extends StatelessWidget {
  /// 具体错误对象；调用 `toString()` 展示。
  final Object error;

  /// 可选重试回调。为 null 时按钮隐藏。
  final VoidCallback? onRetry;

  /// 可选的标题文案，默认 "出错了"。
  final String title;

  const ErrorState({
    super.key,
    required this.error,
    this.onRetry,
    this.title = '出错了',
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth.isFinite && constraints.maxWidth < 320;
        final padding = narrow ? DesignTokens.spaceMd : DesignTokens.space3xl;
        final availableWidth = constraints.maxWidth.isFinite
            ? math.max(0.0, constraints.maxWidth - padding * 2)
            : 420.0;
        return Center(
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: availableWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: narrow ? 44 : 56,
                    color: DesignTokens.resultError,
                  ),
                  const SizedBox(height: DesignTokens.spaceMd),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: narrow ? 2 : null,
                    overflow: narrow ? TextOverflow.ellipsis : null,
                    style: const TextStyle(
                      fontSize: DesignTokens.fontSizeMd,
                      fontWeight: DesignTokens.fontWeightStrong,
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceXs),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: DesignTokens.fontSizeSm,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: DesignTokens.spaceLg),
                    SizedBox(
                      width: narrow ? double.infinity : null,
                      child: FilledButton.tonalIcon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
