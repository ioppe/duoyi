import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<AuthProvider>().client.getList(
        '/api/announcements',
      );
      _items = list.cast<Map<String, dynamic>>();
    } on ApiException catch (e) {
      _error = userVisibleApiError(e);
    } catch (e) {
      _error = '${I18n.tr('announcement.load_failed_prefix')}$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _levelColor(String level) {
    switch (level) {
      case 'warning':
        return Colors.orange;
      case 'critical':
        return Colors.red;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  String _levelLabel(String level) {
    switch (level) {
      case 'warning':
        return I18n.tr('announcement.level.warning');
      case 'critical':
        return I18n.tr('announcement.level.critical');
      default:
        return I18n.tr('announcement.level.info');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(I18n.tr('announcement.title')),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppSecondaryControlTheme(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            children: [
              AppSurfaceCard(
                padding: const EdgeInsets.all(16),
                gradient: LinearGradient(
                  colors: [cs.primary.withValues(alpha: 0.12), cs.surface],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.campaign_outlined,
                        color: cs.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            I18n.tr('announcement.center'),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: DesignTokens.fontWeightStrong,
                                  color: cs.onSurface,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            I18n.tr('announcement.subtitle'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.66),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppSectionHeader(
                title: I18n.tr('announcement.latest'),
                subtitle: I18n.tr('announcement.pull_to_refresh'),
                padding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_items.isEmpty)
                EmptyState(
                  icon: Icons.campaign_outlined,
                  message: _error ?? I18n.tr('announcement.empty'),
                  actionLabel: I18n.tr('announcement.refresh'),
                  onAction: _load,
                )
              else
                ..._items.map((a) {
                  final level = (a['level'] ?? 'info').toString();
                  final levelColor = _levelColor(level);
                  return AppSurfaceCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: levelColor.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _levelLabel(level),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: DesignTokens.fontWeightStrong,
                                  color: levelColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                (a['title'] ?? '').toString(),
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      fontWeight: DesignTokens.fontWeightStrong,
                                      color: cs.onSurface,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          (a['body'] ?? '').toString(),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.74),
                                height: 1.5,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          (a['created_at'] ?? '').toString(),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.52),
                              ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}
