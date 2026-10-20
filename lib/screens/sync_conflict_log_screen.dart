import '../core/app_clock.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../providers/cloud_sync_provider.dart' show SyncMergeDecision;
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

class SyncConflictLogScreen extends StatefulWidget {
  const SyncConflictLogScreen({super.key});

  @override
  State<SyncConflictLogScreen> createState() => _SyncConflictLogScreenState();
}

class _SyncConflictLogScreenState extends State<SyncConflictLogScreen> {
  var _loading = true;
  var _items = const <SyncMergeDecision>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = prefs.getStringList('sync_merge_decisions') ?? const [];
    final items = rows
        .map((raw) {
          try {
            return SyncMergeDecision.fromJson(
              Map<String, dynamic>.from(json.decode(raw) as Map),
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<SyncMergeDecision>()
        .toList();
    items.sort((a, b) => b.decidedAt.compareTo(a.decidedAt));
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    AppClock.watch(context);
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(I18n.tr('sync_conflict.title')),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppSecondaryControlTheme(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
            ? EmptyState(
                icon: Icons.sync_problem_outlined,
                message: I18n.tr('sync_conflict.empty'),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final remote = item.winner == 'remote';
                    final color = remote ? cs.primary : Colors.orange;
                    return AppSurfaceCard(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      border: Border.all(color: color.withValues(alpha: 0.22)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                remote
                                    ? Icons.cloud_done_outlined
                                    : Icons.phone_android_outlined,
                                color: color,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  remote
                                      ? I18n.tr('sync_conflict.keep_remote')
                                      : I18n.tr('sync_conflict.keep_local'),
                                  style: const TextStyle(
                                    fontWeight: DesignTokens.fontWeightStrong,
                                  ),
                                ),
                              ),
                              Text(
                                _formatTime(item.decidedAt),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.reason,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          if (item.changedFields.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final field in item.changedFields)
                                  _FieldChip(field: field),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _InfoChip(
                                label: I18n.tr('sync_conflict.type'),
                                value: item.itemType,
                              ),
                              _InfoChip(
                                label: I18n.tr('sync_conflict.item'),
                                value: item.itemId,
                              ),
                              if (item.workspaceId.isNotEmpty)
                                _InfoChip(
                                  label: I18n.tr('sync_conflict.workspace'),
                                  value: item.workspaceId,
                                ),
                              if (item.localUpdatedAt.isNotEmpty)
                                _InfoChip(
                                  label: I18n.tr('sync_conflict.local'),
                                  value: item.localUpdatedAt,
                                ),
                              if (item.remoteUpdatedAt.isNotEmpty)
                                _InfoChip(
                                  label: I18n.tr('sync_conflict.remote'),
                                  value: item.remoteUpdatedAt,
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    return I18nDateFormat.shortDateTime(AppClock.toLocal(value));
  }
}

class _FieldChip extends StatelessWidget {
  final String field;

  const _FieldChip({required this.field});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.edit_note_outlined,
            size: 13,
            color: cs.onTertiaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            '字段: $field',
            style: TextStyle(fontSize: 11, color: cs.onTertiaryContainer),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
      ),
    );
  }
}
