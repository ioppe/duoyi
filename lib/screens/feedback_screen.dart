import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';
import 'login_screen.dart';

class FeedbackScreen extends StatefulWidget {
  final String initialCategory;

  const FeedbackScreen({super.key, this.initialCategory = 'feature'});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  static const int _pageSize = 10;

  final List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  int _loadSerial = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _categoryLabel(String value) => feedbackCategoryLabel(value);

  String _statusLabel(String value) => switch (value) {
    'resolved' => I18n.tr('feedback.status.resolved'),
    'closed' => I18n.tr('feedback.status.closed'),
    'in_progress' => I18n.tr('feedback.status.in_progress'),
    _ => I18n.tr('feedback.status.open'),
  };

  Color _statusColor(BuildContext context, String value) {
    return switch (value) {
      'resolved' => Colors.green,
      'closed' => Theme.of(context).colorScheme.onSurfaceVariant,
      'in_progress' => Colors.orange,
      _ => Theme.of(context).colorScheme.primary,
    };
  }

  Future<void> _load({int? page}) async {
    final auth = context.read<AuthProvider>();
    if (!auth.state.isLoggedIn) return;
    final loadSerial = ++_loadSerial;
    final nextPage = page ?? _page;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final path = '/api/feedback/me?page=$nextPage&page_size=$_pageSize';
      final raw = await auth.client.getRaw(path);
      final res = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
      final list = raw is List<dynamic>
          ? raw
          : (res['items'] as List<dynamic>? ?? const []);
      final rawItems = list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted || loadSerial != _loadSerial) return;
      setState(() {
        _items
          ..clear()
          ..addAll(rawItems);
        _page = raw is Map ? ((res['page'] as num?) ?? nextPage).toInt() : 1;
        _totalPages = raw is Map
            ? ((res['total_pages'] as num?) ?? 1).toInt().clamp(1, 999999)
            : 1;
        _total = raw is Map
            ? ((res['total'] as num?) ?? rawItems.length).toInt()
            : rawItems.length;
      });
    } on ApiException catch (e) {
      if (mounted && loadSerial == _loadSerial) {
        setState(() => _error = userVisibleApiError(e));
      }
    } catch (e) {
      if (mounted && loadSerial == _loadSerial) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && loadSerial == _loadSerial) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openSubmit(String category) async {
    final auth = context.read<AuthProvider>();
    if (!auth.state.isLoggedIn) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      if (!mounted) return;
      if (!context.read<AuthProvider>().state.isLoggedIn) return;
    }
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FeedbackSubmitScreen(initialCategory: category),
      ),
    );
    if (submitted == true && mounted) {
      await _load(page: 1);
    }
  }

  void _showFeedbackDetail(Map<String, dynamic> item) {
    final category = (item['category'] ?? 'feature').toString();
    final status = (item['status'] ?? 'open').toString();
    final content = (item['content'] ?? '').toString();
    final reply = (item['admin_reply'] ?? '').toString();
    final createdAt = (item['created_at'] ?? '').toString();
    final updatedAt = (item['updated_at'] ?? '').toString();
    showDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        maxWidth: 620,
        icon: const Icon(Icons.feedback_outlined),
        title: const Text('反馈详情'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540, maxHeight: 520),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FeedbackDetailBadge(
                      label: _categoryLabel(category),
                      icon: Icons.category_outlined,
                      color: Theme.of(ctx).colorScheme.primary,
                    ),
                    _FeedbackDetailBadge(
                      label: _statusLabel(status),
                      icon: Icons.radio_button_checked,
                      color: _statusColor(ctx, status),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (createdAt.isNotEmpty)
                  _FeedbackDetailField(label: '提交', value: createdAt),
                if (updatedAt.isNotEmpty)
                  _FeedbackDetailField(label: '更新', value: updatedAt),
                _FeedbackDetailField(
                  label: '内容',
                  value: content.trim().isEmpty ? '暂无内容' : content,
                  multiline: true,
                ),
                if (reply.trim().isNotEmpty)
                  _FeedbackDetailField(
                    label: I18n.tr('feedback.admin_reply'),
                    value: reply,
                    multiline: true,
                    tint: Theme.of(ctx).colorScheme.primary,
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final loggedIn = auth.state.isLoggedIn;
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: const Text('许愿与反馈'),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('feedback_submit_fab'),
        onPressed: () => _openSubmit(widget.initialCategory),
        icon: const Icon(Icons.add_comment_outlined),
        label: Text(I18n.tr('feedback.submit.button')),
      ),
      body: AppSecondaryControlTheme(
        child: RefreshIndicator(
          onRefresh: () => _load(page: _page),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            children: [
              AppSurfaceCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.forum_outlined, color: cs.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppSectionHeader(
                            title: '反馈记录',
                            padding: EdgeInsets.zero,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            loggedIn
                                ? '共 $_total 条，当前第 $_page/$_totalPages 页'
                                : I18n.tr('feedback.login.records_required'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.64),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (!loggedIn)
                EmptyState(
                  icon: Icons.login_outlined,
                  message: I18n.tr('feedback.login.records_required'),
                  actionLabel:
                      '${I18n.tr('feedback.submit.login_prefix')}${_categoryLabel(widget.initialCategory)}',
                  onAction: () => _openSubmit(widget.initialCategory),
                )
              else if (_loading && _items.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_error != null && _items.isEmpty)
                EmptyState(
                  icon: Icons.error_outline,
                  message: _error!,
                  actionLabel: I18n.tr('feedback.refresh'),
                  onAction: () => _load(page: _page),
                )
              else if (_items.isEmpty)
                EmptyState(
                  icon: Icons.feedback_outlined,
                  message: I18n.tr('feedback.empty'),
                  actionLabel: I18n.tr('feedback.submit.button'),
                  onAction: () => _openSubmit(widget.initialCategory),
                )
              else ...[
                ..._items.map((item) {
                  final recordId = (item['id'] ?? item['created_at'] ?? '')
                      .toString();
                  return _FeedbackRecordSwipeActions(
                    key: ValueKey('feedback_record_swipe_$recordId'),
                    recordId: recordId,
                    onDetail: () => _showFeedbackDetail(item),
                    child: _FeedbackRecordCard(
                      item: item,
                      categoryLabel: _categoryLabel,
                      statusLabel: _statusLabel,
                      statusColor: (status) => _statusColor(context, status),
                      onTap: () => _showFeedbackDetail(item),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                _FeedbackPagination(
                  key: const ValueKey('feedback_record_pagination'),
                  page: _page,
                  totalPages: _totalPages,
                  loading: _loading,
                  onPrevious: _page <= 1 ? null : () => _load(page: _page - 1),
                  onNext: _page >= _totalPages
                      ? null
                      : () => _load(page: _page + 1),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackDetailBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _FeedbackDetailBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AppStatusBadge(label: label, color: color, icon: icon);
  }
}

class _FeedbackDetailField extends StatelessWidget {
  final String label;
  final String value;
  final bool multiline;
  final Color? tint;

  const _FeedbackDetailField({
    required this.label,
    required this.value,
    this.multiline = false,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = tint ?? cs.outlineVariant;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: tint == null ? 0.06 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accent.withValues(alpha: tint == null ? 0.10 : 0.14),
          width: 0.45,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: appSecondaryControlLabelStyle(
              context,
            ).copyWith(color: cs.onSurface.withValues(alpha: 0.58)),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style:
                (multiline
                        ? theme.textTheme.bodyMedium
                        : theme.textTheme.bodySmall)
                    ?.copyWith(
                      color: cs.onSurface.withValues(
                        alpha: multiline ? 0.84 : 0.70,
                      ),
                      height: multiline ? 1.38 : 1.25,
                      fontWeight: DesignTokens.fontWeightStrong,
                    ),
          ),
        ],
      ),
    );
  }
}

class FeedbackSubmitScreen extends StatefulWidget {
  final String initialCategory;

  const FeedbackSubmitScreen({super.key, this.initialCategory = 'feature'});

  @override
  State<FeedbackSubmitScreen> createState() => _FeedbackSubmitScreenState();
}

class _FeedbackSubmitScreenState extends State<FeedbackSubmitScreen> {
  late String _category;
  final _contentCtrl = TextEditingController();
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _category = normalizeFeedbackCategory(widget.initialCategory);
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    if (!auth.state.isLoggedIn) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      setState(() => _submitError = I18n.tr('feedback.content.empty'));
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await auth.client.post('/api/feedback', {
        'category': _category,
        'content': content,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(I18n.tr('feedback.submitted'))));
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _submitError = userVisibleApiError(e));
    } catch (e) {
      if (mounted) setState(() => _submitError = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final loggedIn = auth.state.isLoggedIn;
    final cs = Theme.of(context).colorScheme;
    final categoryLabel = feedbackCategoryLabel(_category);
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: const Text('提交许愿与反馈'),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppSecondaryControlTheme(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            AppSurfaceCard(
              key: const ValueKey('feedback_submit_page_card'),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSectionHeader(
                    title: '提交许愿与反馈',
                    subtitle: loggedIn
                        ? '选择反馈类型后提交，处理进度会回到记录列表'
                        : I18n.tr('feedback.login.submit_required'),
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 12),
                  _FeedbackCategoryMenu(
                    selected: _category,
                    labelFor: feedbackCategoryLabel,
                    onSelected: loggedIn && !_submitting
                        ? (value) => setState(() {
                            _category = normalizeFeedbackCategory(value);
                            _submitError = null;
                          })
                        : (_) {},
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('feedback_submit_content'),
                    controller: _contentCtrl,
                    enabled: loggedIn && !_submitting,
                    minLines: 5,
                    maxLines: 9,
                    decoration: InputDecoration(
                      labelText:
                          '${I18n.tr('feedback.content.label_prefix')}$categoryLabel',
                      helperText: feedbackCategoryHelp(_category),
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (_submitError != null) ...[
                    const SizedBox(height: 10),
                    Text(_submitError!, style: TextStyle(color: cs.error)),
                  ],
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: const ValueKey('feedback_submit_page_button'),
                      onPressed: loggedIn && !_submitting ? _submit : null,
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined),
                      label: Text(
                        _submitting
                            ? I18n.tr('feedback.submitting')
                            : I18n.tr('feedback.submit.button'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackCategoryMenu extends StatelessWidget {
  final String selected;
  final String Function(String) labelFor;
  final ValueChanged<String> onSelected;

  const _FeedbackCategoryMenu({
    required this.selected,
    required this.labelFor,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedBg = cs.primary.withValues(alpha: 0.1);
    final selectedBorder = cs.primary.withValues(alpha: 0.28);
    final selectedFg = cs.onSurface;
    return Row(
      key: const ValueKey('feedback_three_level_menu'),
      children: [
        Text(
          '类型',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.54),
          ),
        ),
        const SizedBox(width: 8),
        Listener(
          onPointerDown: (_) {
            FocusScope.of(context, createDependency: false).unfocus();
            FocusManager.instance.primaryFocus?.unfocus();
          },
          child: PopupMenuButton<String>(
            tooltip: I18n.tr('feedback.category.label'),
            initialValue: selected,
            onSelected: onSelected,
            itemBuilder: (_) => [
              for (final category in const ['feature', 'bug', 'wish'])
                PopupMenuItem(
                  value: category,
                  child: Row(
                    children: [
                      Expanded(child: AppSecondaryMenuText(labelFor(category))),
                      if (selected == category)
                        Icon(Icons.check, size: 16, color: cs.primary),
                    ],
                  ),
                ),
            ],
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selectedBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: selectedBorder, width: 0.45),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    labelFor(selected),
                    style: appSecondaryControlTextStyle(context).copyWith(
                      color: selectedFg,
                      fontWeight: DesignTokens.fontWeightStrong,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, color: cs.primary, size: 18),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeedbackRecordCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String Function(String) categoryLabel;
  final String Function(String) statusLabel;
  final Color Function(String) statusColor;
  final VoidCallback onTap;

  const _FeedbackRecordCard({
    required this.item,
    required this.categoryLabel,
    required this.statusLabel,
    required this.statusColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final category = (item['category'] ?? 'feature').toString();
    final status = (item['status'] ?? 'open').toString();
    final content = (item['content'] ?? '').toString();
    final reply = (item['admin_reply'] ?? '').toString();
    final createdAt = (item['created_at'] ?? '').toString();
    final color = statusColor(status);
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.zero,
      child: InkWell(
        key: const ValueKey('feedback_record_card_tap_target'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      categoryLabel(category),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  AppStatusBadge(label: statusLabel(status), color: color),
                ],
              ),
              if (createdAt.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  createdAt,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.52),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(content, maxLines: 4, overflow: TextOverflow.ellipsis),
              if (reply.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        I18n.tr('feedback.admin_reply'),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: cs.onPrimaryContainer),
                      ),
                      const SizedBox(height: 4),
                      Text(reply, maxLines: 3, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackRecordSwipeActions extends StatefulWidget {
  final String recordId;
  final Widget child;
  final VoidCallback onDetail;

  const _FeedbackRecordSwipeActions({
    super.key,
    required this.recordId,
    required this.child,
    required this.onDetail,
  });

  @override
  State<_FeedbackRecordSwipeActions> createState() =>
      _FeedbackRecordSwipeActionsState();
}

class _FeedbackRecordSwipeActionsState
    extends State<_FeedbackRecordSwipeActions> {
  static const double _actionRailWidth = 58;
  static const double _dragOpenThreshold = 40;
  double _dragDistance = 0;
  bool _open = false;

  @override
  void didUpdateWidget(covariant _FeedbackRecordSwipeActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.recordId != oldWidget.recordId) {
      _dragDistance = 0;
      _open = false;
    }
  }

  void _setOpen(bool value) {
    if (_open == value) return;
    setState(() => _open = value);
  }

  void _showDetail() {
    _setOpen(false);
    widget.onDetail();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRect(
      child: GestureDetector(
        key: const ValueKey('feedback_record_swipe_actions'),
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => _dragDistance = 0,
        onHorizontalDragUpdate: (details) {
          _dragDistance += details.delta.dx;
          if (_dragDistance <= -_dragOpenThreshold) _setOpen(true);
          if (_dragDistance >= _dragOpenThreshold) _setOpen(false);
        },
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -120) _setOpen(true);
          if (velocity > 120) _setOpen(false);
          _dragDistance = 0;
        },
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (_open)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4, bottom: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.92,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.18),
                          width: 0.45,
                        ),
                      ),
                      child: SizedBox(
                        width: _actionRailWidth,
                        height: 42,
                        child: Center(
                          child: IconButton(
                            key: const ValueKey(
                              'feedback_record_detail_action',
                            ),
                            tooltip: '查看反馈详情',
                            constraints: const BoxConstraints.tightFor(
                              width: 36,
                              height: 36,
                            ),
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.visibility_outlined,
                              color: cs.primary,
                              size: 18,
                            ),
                            onPressed: _showDetail,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(
                _open ? -_actionRailWidth : 0,
                0,
                0,
              ),
              child: widget.child,
            ),
            if (_open)
              Positioned.fill(
                right: _actionRailWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => _setOpen(false),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackPagination extends StatelessWidget {
  final int page;
  final int totalPages;
  final bool loading;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _FeedbackPagination({
    super.key,
    required this.page,
    required this.totalPages,
    required this.loading,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final pageLabel = Text(
      '第 $page/$totalPages 页',
      textAlign: TextAlign.center,
      style: appSecondaryControlLabelStyle(context),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final controls = [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: loading ? null : onPrevious,
              icon: const Icon(Icons.chevron_left),
              label: const Text('上一页'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: loading ? null : onNext,
              icon: const Icon(Icons.chevron_right),
              label: const Text('下一页'),
            ),
          ),
        ];
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              pageLabel,
              const SizedBox(height: 6),
              Row(children: controls),
            ],
          );
        }
        return Row(
          children: [
            controls[0],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: pageLabel,
            ),
            controls[2],
          ],
        );
      },
    );
  }
}

String normalizeFeedbackCategory(String value) {
  return switch (value) {
    'bug' => 'bug',
    'wish' => 'wish',
    'other' => 'other',
    _ => 'feature',
  };
}

String feedbackCategoryLabel(String value) => switch (value) {
  'bug' => I18n.tr('feedback.category.bug'),
  'wish' => I18n.tr('feedback.category.wish'),
  'other' => I18n.tr('feedback.category.other'),
  _ => I18n.tr('feedback.category.feature'),
};

String feedbackCategoryHelp(String value) => switch (value) {
  'bug' => I18n.tr('feedback.help.bug'),
  'wish' => I18n.tr('feedback.help.wish'),
  'other' => I18n.tr('feedback.help.other'),
  _ => I18n.tr('feedback.help.feature'),
};
