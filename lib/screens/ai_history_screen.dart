import 'package:flutter/material.dart';
import '../core/app_motion.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/ai_service.dart';
import '../widgets/ai_review_markdown.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

/// AI 周回顾历史：本地持久化最近 50 条。
class AiHistoryScreen extends StatefulWidget {
  const AiHistoryScreen({super.key});

  @override
  State<AiHistoryScreen> createState() => _AiHistoryScreenState();
}

class _AiHistoryScreenState extends State<AiHistoryScreen> {
  final Set<String> _expandedReviewIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiService>();
    final items = ai.reviewHistory;
    return Scaffold(
      appBar: AppBar(
        title: Text(I18n.tr('ai_history.title')),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: I18n.tr('ai_history.clear.tooltip'),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AppDialog(
                    title: Text(I18n.tr('ai_history.clear.title')),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    content: Text(I18n.tr('ai_history.clear.content')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(I18n.tr('action.cancel')),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(I18n.tr('ai_history.clear.action')),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await context.read<AiService>().clearReviewHistory();
                }
              },
            ),
        ],
      ),
      body: items.isEmpty
          ? EmptyState(
              icon: Icons.auto_awesome,
              message: I18n.tr('ai_history.empty'),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (context, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final e = items[i];
                final theme = Theme.of(context);
                final cs = theme.colorScheme;
                final createdAt = I18nDateFormat.fullDateTime(e.createdAt);
                final expanded = _expandedReviewIds.contains(e.id);
                return AppSurfaceCard(
                  padding: const EdgeInsets.all(14),
                  child: Padding(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 18,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                createdAt,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.62),
                                  fontWeight: DesignTokens.fontWeightStrong,
                                ),
                              ),
                            ),
                            IconButton(
                              key: ValueKey('ai_history_toggle_${e.id}'),
                              tooltip: expanded ? '收起回顾' : '展开回顾',
                              visualDensity: VisualDensity.compact,
                              iconSize: 18,
                              onPressed: () {
                                setState(() {
                                  if (expanded) {
                                    _expandedReviewIds.remove(e.id);
                                  } else {
                                    _expandedReviewIds.add(e.id);
                                  }
                                });
                              },
                              icon: Icon(
                                expanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                              ),
                            ),
                            PopupMenuButton<String>(
                              iconSize: 18,
                              onSelected: (v) async {
                                if (v == 'copy') {
                                  await Clipboard.setData(
                                    ClipboardData(text: e.content),
                                  );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        I18n.tr('ai_history.copy.done'),
                                      ),
                                    ),
                                  );
                                } else if (v == 'delete') {
                                  await context.read<AiService>().deleteReview(
                                    e.id,
                                  );
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'copy',
                                  child: Text(I18n.tr('ai_history.copy')),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    I18n.tr('ai_history.delete'),
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (e.model.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          AppStatusBadge(
                            label: e.model,
                            color: cs.primary,
                            icon: Icons.memory_outlined,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          e.summary,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.68),
                            fontWeight: DesignTokens.fontWeightStrong,
                          ),
                        ),
                        ClipRect(
                          key: ValueKey('ai_history_content_${e.id}'),
                          child: AnimatedSize(
                            duration: AppMotion.transition(context),
                            curve: AppMotion.enterCurve,
                            child: expanded
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: AiReviewMarkdown(data: e.content),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
