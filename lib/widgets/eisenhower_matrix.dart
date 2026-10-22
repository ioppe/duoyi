import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/completion_visibility_policy.dart';
import '../core/design_tokens.dart';
import '../core/todo_quadrant_style.dart';
import '../models/todo.dart';
import '../providers/theme_provider.dart';

class EisenhowerMatrix extends StatelessWidget {
  final Map<EisenhowerQuadrant, List<TodoItem>> quadrantGroups;
  final void Function(EisenhowerQuadrant) onQuadrantTap;

  /// 长按拖动条目到目标象限时回调；为 null 时矩阵保持只读。
  final void Function(TodoItem todo, EisenhowerQuadrant target)?
  onTodoQuadrantChanged;

  /// 单条待办的拖拽编辑权限谓词；为 null 时全部允许。
  /// 只读共享工作区成员应返回 false：该行不再可拖拽，投放也被拒收，
  /// 与 tile 级入口的 canEdit 闸保持一致。
  final bool Function(TodoItem todo)? canEditTodo;

  /// 最宽桌面档（调用方按窗口宽度 ≥ DesktopTokens.breakpointThreeColumn
  /// 传入）：四象限单行 4 列横排。false（默认）保持 2×2 竖排，
  /// 紧迫/重要两轴语义不变。
  final bool fourColumn;

  const EisenhowerMatrix({
    super.key,
    required this.quadrantGroups,
    required this.onQuadrantTap,
    this.onTodoQuadrantChanged,
    this.canEditTodo,
    this.fourColumn = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ThemeProvider>().brand.strings;
    // 局部变量以获得空值提升，供四处 _QuadrantCard 接线使用。
    final onTodoChanged = onTodoQuadrantChanged;
    _QuadrantCard quadrantCard(
      EisenhowerQuadrant quadrant,
      String label,
      String sub,
    ) {
      return _QuadrantCard(
        quadrant: quadrant,
        label: label,
        subLabel: sub,
        items: quadrantGroups[quadrant] ?? [],
        onTodoDropped: onTodoChanged == null
            ? null
            : (todo) => onTodoChanged(todo, quadrant),
        canEditTodo: canEditTodo,
        onTap: () => onQuadrantTap(quadrant),
      );
    }

    final cards = <_QuadrantCard>[
      quadrantCard(
        EisenhowerQuadrant.urgentImportant,
        s.quadrantQ1Label,
        s.quadrantQ1Sub,
      ),
      quadrantCard(
        EisenhowerQuadrant.notUrgentImportant,
        s.quadrantQ2Label,
        s.quadrantQ2Sub,
      ),
      quadrantCard(
        EisenhowerQuadrant.urgentNotImportant,
        s.quadrantQ3Label,
        s.quadrantQ3Sub,
      ),
      quadrantCard(
        EisenhowerQuadrant.notUrgentNotImportant,
        s.quadrantQ4Label,
        s.quadrantQ4Sub,
      ),
    ];
    if (fourColumn) {
      return Row(
        children: [
          Expanded(child: cards[0]),
          const SizedBox(width: DesignTokens.spaceSm),
          Expanded(child: cards[1]),
          const SizedBox(width: DesignTokens.spaceSm),
          Expanded(child: cards[2]),
          const SizedBox(width: DesignTokens.spaceSm),
          Expanded(child: cards[3]),
        ],
      );
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: DesignTokens.spaceSm),
            Expanded(child: cards[1]),
          ],
        ),
        const SizedBox(height: DesignTokens.spaceSm),
        Row(
          children: [
            Expanded(child: cards[2]),
            const SizedBox(width: DesignTokens.spaceSm),
            Expanded(child: cards[3]),
          ],
        ),
      ],
    );
  }
}

class _QuadrantCard extends StatelessWidget {
  final EisenhowerQuadrant quadrant;
  final String label;
  final String subLabel;
  final List<TodoItem> items;
  final VoidCallback onTap;
  final ValueChanged<TodoItem>? onTodoDropped;
  final bool Function(TodoItem)? canEditTodo;

  const _QuadrantCard({
    required this.quadrant,
    required this.label,
    required this.subLabel,
    required this.items,
    required this.onTap,
    this.onTodoDropped,
    this.canEditTodo,
  });

  Color _bgColor() => todoQuadrantColor(quadrant);

  @override
  Widget build(BuildContext context) {
    final bg = _bgColor();
    // 系统大字号（textScaler 2.0）下固定卡高 160 与固定预览行高 24 不随字号
    // 缩放，卡片底部溢出渲染黄黑警示条。参照 today_screen.dart 的兜底模式：
    // 按 MediaQuery.textScalerOf 换算倍率放大并封顶 1.6 倍；空态分支在
    // Expanded 内自适应，不受影响。
    final fontScale = MediaQuery.textScalerOf(
      context,
    ).scale(1.0).clamp(1.0, 1.6).toDouble();
    final card = GestureDetector(
      onTap: onTap,
      child: Container(
        height: 160 * fontScale,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.018),
              blurRadius: 7,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 4, width: double.infinity, color: bg),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: TextStyle(
                                fontWeight: DesignTokens.fontWeightStrong,
                                color: bg,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (items.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: bg.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${items.length}',
                                style: TextStyle(
                                  color: bg,
                                  fontWeight: DesignTokens.fontWeightStrong,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (items.isEmpty)
                        Expanded(
                          child: Center(
                            child: Text(
                              '暂无任务',
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              // 预览行高与「更多」标签预留高按同一倍率放大，
                              // 保证行数推导在任何字号下都不超出实际可容行高。
                              final previewRowHeight = 24.0 * fontScale;
                              final moreLabelHeight = 17.0 * fontScale;
                              final reserveMoreLabel = items.length > 3;
                              final availableForRows =
                                  constraints.maxHeight -
                                  (reserveMoreLabel ? moreLabelHeight : 0);
                              var visibleCount =
                                  (availableForRows / previewRowHeight).floor();
                              if (visibleCount < 1) visibleCount = 1;
                              if (visibleCount > 3) visibleCount = 3;

                              final visibleItems = items
                                  .take(visibleCount)
                                  .toList(growable: false);
                              final hiddenCount =
                                  items.length - visibleItems.length;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ...visibleItems.map((t) {
                                    final visual =
                                        CompletionVisibilityPolicy.visualState(
                                          t,
                                        );
                                    final stateColor =
                                        CompletionVisibilityPolicy.colorFor(
                                          visual,
                                        );
                                    final isCompleted =
                                        visual == TodoVisualState.completed;
                                    final isOverdue =
                                        visual == TodoVisualState.overdue;
                                    final isDueSoon =
                                        visual == TodoVisualState.dueSoon;
                                    final itemColor =
                                        isCompleted || isOverdue || isDueSoon
                                        ? stateColor
                                        : bg.withValues(alpha: 0.8);
                                    final row = Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: itemColor,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              t.title,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isCompleted
                                                    ? Colors.grey
                                                    : isOverdue
                                                    ? stateColor
                                                    : null,
                                                decoration: isCompleted
                                                    ? TextDecoration.lineThrough
                                                    : null,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isOverdue || isCompleted)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                left: 6,
                                              ),
                                              child: Text(
                                                isCompleted ? '已完成' : '逾期',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: itemColor,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                    // 只读成员（canEditTodo 返回 false）的行
                                    // 不进入拖拽，杜绝绕过权限换象限。
                                    final canDrag =
                                        onTodoDropped != null &&
                                        (canEditTodo?.call(t) ?? true);
                                    if (!canDrag) return row;
                                    return LongPressDraggable<TodoItem>(
                                      data: t,
                                      feedback: Material(
                                        elevation: 4,
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          child: Text(
                                            t.title,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                            ),
                                          ),
                                        ),
                                      ),
                                      childWhenDragging: Opacity(
                                        opacity: 0.4,
                                        child: row,
                                      ),
                                      child: row,
                                    );
                                  }),
                                  if (hiddenCount > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        '+$hiddenCount 更多...',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade400,
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (onTodoDropped == null) return card;
    return DragTarget<TodoItem>(
      // 拒收同象限与无编辑权限的投放（防御性复查，拖拽源已按权限收口）。
      onWillAcceptWithDetails: (details) =>
          details.data.quadrant != quadrant &&
          (canEditTodo?.call(details.data) ?? true),
      onAcceptWithDetails: (details) => onTodoDropped!(details.data),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        if (!hovering) return card;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
            border: Border.all(color: bg, width: 2),
          ),
          child: card,
        );
      },
    );
  }
}
